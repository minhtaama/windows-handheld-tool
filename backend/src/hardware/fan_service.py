import os
import sys
import ctypes
import threading
import time
from typing import List, Tuple
from src.core.logger import setup_logger

logger = setup_logger("FanService")

# Mốc đường cong nhiệt độ mặc định: (nhiệt_độ_°C, tốc_độ_quạt_%)
DEFAULT_FAN_CURVE: List[Tuple[int, int]] = [
    (40, 30),
    (50, 42),
    (60, 58),
    (70, 75),
    (80, 90),
    (85, 100),
]

class FanService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(FanService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.inpout = None
        self.is_hardware_detected = False
        self.is_auto = True
        self.current_speed = 50
        self.fan_curve: List[Tuple[int, int]] = list(DEFAULT_FAN_CURVE)
        self._load_inpout()

        # Luồng nền tự động điều tốc quạt theo đường cong nhiệt độ
        self._running = True
        self._curve_thread = threading.Thread(target=self._fan_curve_worker, daemon=True)
        self._curve_thread.start()

        self._initialized = True

    def _load_inpout(self):
        bin_dirs = []
        if getattr(sys, "frozen", False):
            mei_dir = getattr(sys, "_MEIPASS", "")
            if mei_dir:
                bin_dirs.append(os.path.join(mei_dir, "bin"))
            exe_dir = os.path.dirname(os.path.abspath(sys.executable))
            bin_dirs.append(os.path.join(exe_dir, "bin"))
            bin_dirs.append(os.path.join(exe_dir, "_internal", "bin"))
        else:
            dev_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            bin_dirs.append(os.path.join(dev_root, "bin"))

        for bin_dir in bin_dirs:
            if os.path.isdir(bin_dir) and hasattr(os, "add_dll_directory"):
                try:
                    os.add_dll_directory(bin_dir)
                except Exception:
                    pass

        for b in bin_dirs:
            p = os.path.join(b, "inpoutx64.dll")
            if os.path.isfile(p):
                try:
                    self.inpout = ctypes.windll.LoadLibrary(p)
                    self.is_hardware_detected = True
                    logger.info(f"Đã nạp thành công InpOutx64 từ bin: {p}")
                    break
                except Exception as e:
                    logger.warning(f"Không thể nạp InpOutx64 từ {p}: {e}")

    def calculate_speed_from_temp(self, temp: float) -> int:
        """Nội suy tuyến tính tốc độ quạt (%) từ nhiệt độ CPU hiện thời theo bảng Fan Curve"""
        if not self.fan_curve:
            return 50
        sorted_curve = sorted(self.fan_curve, key=lambda x: x[0])
        if temp <= sorted_curve[0][0]:
            return sorted_curve[0][1]
        if temp >= sorted_curve[-1][0]:
            return sorted_curve[-1][1]

        for i in range(len(sorted_curve) - 1):
            t1, s1 = sorted_curve[i]
            t2, s2 = sorted_curve[i + 1]
            if t1 <= temp <= t2:
                ratio = (temp - t1) / float(t2 - t1)
                return round(s1 + ratio * (s2 - s1))
        return 50

    def _fan_curve_worker(self):
        """Vòng lặp chạy ngầm cập nhật tốc độ quạt theo chu kỳ 2s khi ở chế độ Auto"""
        from src.hardware.tdp_service import TdpService
        tdp_svc = TdpService()

        while self._running:
            time.sleep(2.0)
            if not self.is_auto:
                continue

            try:
                temp, _, _ = tdp_svc.get_telemetry()
                if temp > 0:
                    target_speed = self.calculate_speed_from_temp(temp)
                    if abs(target_speed - self.current_speed) >= 2:
                        self.current_speed = target_speed
                        self._apply_hardware_speed(target_speed)
            except Exception as e:
                logger.error(f"Lỗi trong vòng lặp Fan Curve Worker: {e}")

    def _apply_asus_wmi(self, percent: int) -> bool:
        """Gửi lệnh điều tốc quạt qua giao diện WMI của ASUS Handheld (ROG Ally / Ally X)"""
        try:
            import win32com.client
            wmi = win32com.client.GetObject("winmgmts:\\\\.\\root\\wmi")
            asus_methods = wmi.ExecQuery("SELECT * FROM AsusAtkWmi_WMNB")
            if asus_methods.Count > 0:
                for obj in asus_methods:
                    # Mã thiết bị phần cứng ASUS: 0x00110013 (Fan 1), 0x00110014 (Fan 2)
                    for dev_id in (0x00110013, 0x00110014):
                        obj.DEVS(dev_id, percent)
                logger.info(f"[ASUS WMI] Đã đồng bộ tốc độ quạt Handheld: {percent}%")
                return True
        except Exception:
            pass
        return False

    def _apply_ec_io(self, percent: int) -> bool:
        """
        Ghi giá trị điều tốc xuống thanh ghi của chip Embedded Controller (EC) qua cổng I/O 0x6C / 0x68.
        CHÚ Ý: Cổng 0x6C/0x68 là cổng ACPI EC dùng chung của Kernel. Việc ghi bừa bãi mã lệnh cố định (0x2E)
        sẽ làm xung đột ACPI bus, gây treo cứng hệ điều hành (Hardware Stall) dẫn đến sập nguồn/Black Screen.
        Tạm thời vô hiệu hóa việc ghi mù xuống cổng này trừ khi có handshake định danh thiết bị cụ thể.
        """
        return False

    def _apply_hardware_speed(self, percent: int):
        """Áp dụng tốc độ quạt xuống phần cứng Embedded Controller / WMI nếu có, hoặc mô phỏng mượt mà"""
        applied = False
        # 1. Thử gửi qua giao tiếp WMI ACPI dành riêng cho ASUS ROG Ally
        if self._apply_asus_wmi(percent):
            applied = True

        # 2. Thử ghi cổng thanh ghi phần cứng EC I/O (InpOutx64)
        if not applied and self.is_hardware_detected:
            if self._apply_ec_io(percent):
                applied = True

        if not applied:
            logger.info(f"[Điều tốc quạt] Tốc độ quạt hiện tại: {percent}% (Chế độ: {'Tự động' if self.is_auto else 'Thủ công'})")

    def set_fan_curve(self, curve: List[Tuple[int, int]]):
        """Cập nhật bảng mốc nhiệt độ - tốc độ quạt mới"""
        if curve:
            self.fan_curve = sorted(curve, key=lambda x: x[0])
            logger.info(f"Đã cập nhật Fan Curve mới: {self.fan_curve}")

    def get_fan_curve(self) -> List[Tuple[int, int]]:
        return list(self.fan_curve)

    def set_auto(self, auto: bool) -> bool:
        self.is_auto = auto
        logger.info(f"Chế độ quạt: {'Tự động theo đường cong nhiệt độ (Auto Fan Curve)' if auto else 'Thủ công (Manual)'}")
        return True

    def set_speed(self, percent: int) -> bool:
        percent = max(0, min(100, percent))
        self.current_speed = percent
        self.is_auto = False
        self._apply_hardware_speed(percent)
        return True

    def get_speed(self) -> int:
        return self.current_speed

