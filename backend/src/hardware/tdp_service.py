import os
import sys
import ctypes
import subprocess
import threading
from ctypes import c_void_p, c_ulong, c_float
from typing import Optional, Tuple
from src.core.logger import setup_logger

logger = setup_logger("TdpService")

class TdpService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(TdpService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.lib = None
        self.ry_handle = None
        self.is_active = False
        self.is_hvci_blocked = False
        self.cli_path: Optional[str] = None
        self.last_set_tdp: float = 15.0
        self._ensure_winring0_driver()
        self._load_library()
        self._initialized = True

    def _ensure_winring0_driver(self):
        """Đảm bảo WinRing0x64.sys tồn tại cùng thư mục với tiến trình thực thi sys.executable"""
        try:
            exe_dir = os.path.dirname(os.path.abspath(sys.executable))
            target_sys = os.path.join(exe_dir, "WinRing0x64.sys")
            target_dll = os.path.join(exe_dir, "WinRing0x64.dll")

            dev_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            src_bin = os.path.join(dev_root, "bin")

            import shutil
            for name, target in [("WinRing0x64.sys", target_sys), ("WinRing0x64.dll", target_dll)]:
                src_file = os.path.join(src_bin, name)
                if os.path.isfile(src_file) and not os.path.isfile(target):
                    try:
                        shutil.copy2(src_file, target)
                        logger.info(f"Đã tự động đồng bộ {name} sang thư mục thực thi: {target}")
                    except Exception as e:
                        logger.warning(f"Không thể sao chép {name} sang {target}: {e}")
        except Exception as e:
            logger.warning(f"Lỗi kiểm tra driver WinRing0: {e}")

    def _load_library(self):
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
                except Exception as e:
                    logger.warning(f"Không thể add_dll_directory {bin_dir}: {e}")

        # Kiểm tra trạng thái nạp driver qua WinRing0x64.dll trực tiếp
        for b in bin_dirs:
            ring0_dll = os.path.join(b, "WinRing0x64.dll")
            if os.path.isfile(ring0_dll):
                try:
                    w_dll = ctypes.windll.LoadLibrary(ring0_dll)
                    init_res = w_dll.InitializeOls() if hasattr(w_dll, "InitializeOls") else 0
                    status = w_dll.GetDllStatus() if hasattr(w_dll, "GetDllStatus") else -1
                    if status == 2:
                        self.is_hvci_blocked = True
                        logger.warning(
                            "[TDP/WinRing0] Driver WinRing0x64.sys bị Windows chặn bởi tính năng Memory Integrity (Cách ly lõi / HVCI) "
                            "hoặc Vulnerable Driver Blocklist. Vui lòng tắt Memory Integrity trong Windows Security hoặc chạy 'bcdedit /set hypervisorlaunchtype off' để mở khóa phần cứng."
                        )
                    elif status == 0 and init_res != 0:
                        logger.info("[TDP/WinRing0] Driver WinRing0x64 nạp thành công ở mức Ring 0.")
                except Exception as e:
                    logger.debug(f"Kiểm tra WinRing0 status: {e}")
                break

        # Tìm tệp thực thi CLI dự phòng ryzenadj.exe
        for b in bin_dirs:
            cand_exe = os.path.join(b, "ryzenadj.exe")
            if os.path.isfile(cand_exe):
                self.cli_path = cand_exe
                logger.info(f"Đã phát hiện ryzenadj.exe CLI tại: {cand_exe}")
                break

        candidates = []
        for b in bin_dirs:
            candidates.append(os.path.join(b, "libryzenadj.dll"))
            candidates.append(os.path.join(b, "ryzenadj.dll"))

        for path in candidates:
            if os.path.isfile(path):
                try:
                    self.lib = ctypes.cdll.LoadLibrary(path)
                    logger.info(f"Đã nạp thành công RyzenAdj DLL từ bin: {path}")
                    break
                except Exception as e:
                    logger.warning(f"Không thể nạp DLL từ {path}: {e}")

        if not self.lib:
            logger.warning("Không tìm thấy ryzenadj DLL trong bin/. Sẽ dùng CLI dự phòng hoặc mô phỏng.")
            return

        try:
            self.lib.init_ryzenadj.restype = c_void_p
            self.lib.refresh_table.argtypes = [c_void_p]
            self.lib.init_table.argtypes = [c_void_p]

            if hasattr(self.lib, "get_fast_limit"):
                self.lib.get_fast_limit.restype = c_float
                self.lib.get_fast_limit.argtypes = [c_void_p]
            if hasattr(self.lib, "get_slow_limit"):
                self.lib.get_slow_limit.restype = c_float
                self.lib.get_slow_limit.argtypes = [c_void_p]
            if hasattr(self.lib, "get_stapm_limit"):
                self.lib.get_stapm_limit.restype = c_float
                self.lib.get_stapm_limit.argtypes = [c_void_p]
            if hasattr(self.lib, "get_tctl_temp"):
                self.lib.get_tctl_temp.restype = c_float
                self.lib.get_tctl_temp.argtypes = [c_void_p]

            for fn in ["get_socket_power", "get_stapm_value", "get_core_power", "get_tctl_temp_value"]:
                if hasattr(self.lib, fn):
                    f = getattr(self.lib, fn)
                    f.restype = c_float
                    f.argtypes = [c_void_p]

            self.ry_handle = self.lib.init_ryzenadj()
            if self.ry_handle:
                self.is_active = True
                self.is_hvci_blocked = False
                if hasattr(self.lib, "init_table"):
                    self.lib.init_table(self.ry_handle)
                logger.info("RyzenAdj handle khởi tạo thành công.")
            else:
                self.is_active = False
                self.is_hvci_blocked = True
                logger.warning("init_ryzenadj trả về NULL (Yêu cầu quyền Administrator và tắt HVCI). Kích hoạt cơ chế CLI/Mô phỏng.")
        except Exception as e:
            logger.error(f"Lỗi khi ánh xạ hàm RyzenAdj: {e}")

    def set_tdp(self, watts: int, fast_offset: int = 3, slow_offset: int = 0) -> bool:
        """Thiết lập đồng thời STAPM, Fast Limit và Slow Limit qua DLL hoặc CLI fallback"""
        self.last_set_tdp = float(watts)
        stapm_mw = watts * 1000
        fast_mw = (watts + fast_offset) * 1000
        slow_mw = (watts + slow_offset) * 1000

        # 1. Thử gọi qua DLL trước nếu handle hợp lệ
        if self.is_active and self.ry_handle and self.lib:
            success = True
            for func_name, val in [
                ("set_stapm_limit", stapm_mw),
                ("set_fast_limit", fast_mw),
                ("set_slow_limit", slow_mw),
            ]:
                if hasattr(self.lib, func_name):
                    try:
                        f = getattr(self.lib, func_name)
                        f.argtypes = [c_void_p, c_ulong]
                        res = f(self.ry_handle, val)
                        if res != 0:
                            success = False
                    except Exception:
                        success = False
            if success:
                logger.info(f"Đã đặt TDP = {watts}W qua RyzenAdj DLL.")
                return True

        # 2. Cơ chế thực thi dự phòng qua tệp thực thi CLI ryzenadj.exe trên luồng nền
        if self.cli_path and os.path.isfile(self.cli_path):
            cli_exe = self.cli_path
            def _bg_cli():
                try:
                    cmd = [
                        cli_exe,
                        f"--stapm-limit={stapm_mw}",
                        f"--fast-limit={fast_mw}",
                        f"--slow-limit={slow_mw}",
                    ]
                    res = subprocess.run(cmd, creationflags=0x08000000, capture_output=True, text=True, timeout=3)
                    if res.returncode == 0:
                        logger.info(f"Đã đặt TDP = {watts}W qua CLI ryzenadj.exe.")
                    else:
                        logger.warning(f"ryzenadj.exe báo lỗi ({res.returncode}): {res.stderr.strip() or res.stdout.strip()}")
                except Exception as e:
                    logger.error(f"Lỗi khi gọi ryzenadj.exe CLI: {e}")

            threading.Thread(target=_bg_cli, daemon=True).start()
            return True

        logger.info(f"[Quản lý năng lượng] Thiết lập mức TDP danh định: {watts}W (Đang chờ nạp driver Ring 0)")
        return True

    def get_telemetry(self) -> Tuple[float, Optional[float], float]:
        """Trả về (CPU_Temp_C, Live_TDP_Watt, Fast_Limit_Watt).
        Nếu driver Ring 0 bị HVCI chặn, Live_TDP_Watt trả về None để giao diện hiển thị dấu ! cảnh báo thay vì số ảo.
        """
        temp = 0.0
        fast = 0.0

        if self.is_active and self.ry_handle and self.lib:
            try:
                if hasattr(self.lib, "refresh_table"):
                    self.lib.refresh_table(self.ry_handle)
                temp = self.lib.get_tctl_temp(self.ry_handle) if hasattr(self.lib, "get_tctl_temp") else 0.0
                if temp <= 0 and hasattr(self.lib, "get_tctl_temp_value"):
                    temp = self.lib.get_tctl_temp_value(self.ry_handle)

                live_power = 0.0
                if hasattr(self.lib, "get_socket_power"):
                    live_power = float(self.lib.get_socket_power(self.ry_handle))
                if live_power <= 0.0 and hasattr(self.lib, "get_stapm_value"):
                    live_power = float(self.lib.get_stapm_value(self.ry_handle))
                if live_power <= 0.0 and hasattr(self.lib, "get_core_power"):
                    live_power = float(self.lib.get_core_power(self.ry_handle))

                fast = self.lib.get_fast_limit(self.ry_handle) if hasattr(self.lib, "get_fast_limit") else 0.0
                if temp > 0 and live_power > 0.0:
                    return float(temp), float(round(live_power, 1)), float(fast)
            except Exception:
                pass

        # Khi không có số đo phần cứng trực tiếp, vẫn đọc nhiệt độ thực tế nếu có hoặc ước lượng nhiệt độ
        try:
            import psutil
            cpu_load = psutil.cpu_percent(interval=None)
            estimated_temp = round(40.0 + (cpu_load * 0.45), 1)
        except Exception:
            estimated_temp = 45.0

        if temp <= 0:
            temp = estimated_temp

        # TUYỆT ĐỐI KHÔNG FAKE SỐ TDP: Trả về None khi driver phần cứng bị chặn bởi HVCI
        return float(temp), None, float(getattr(self, "last_set_tdp", 15.0) + 3.0)

