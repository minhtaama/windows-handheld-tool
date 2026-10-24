# -*- coding: utf-8 -*-
import ctypes
from ctypes import wintypes
import threading
import time
from typing import Optional
from src.core.logger import setup_logger

logger = setup_logger("BrightnessService")

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
try:
    dxva2 = ctypes.windll.dxva2
except Exception:
    dxva2 = None

class PHYSICAL_MONITOR(ctypes.Structure):
    _fields_ = [
        ("hPhysicalMonitor", wintypes.HANDLE),
        ("szPhysicalMonitorDescription", wintypes.WCHAR * 128)
    ]

class BrightnessService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(BrightnessService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.current_brightness = 70
        self.wmi_methods = None
        self._is_setting = False
        self._target_brightness = 70
        self._lock = threading.Lock()
        
        # Thử đọc độ sáng thực tế ban đầu từ phần cứng Windows
        init_val = self._read_hardware_brightness()
        if init_val is not None:
            self.current_brightness = init_val
            self._target_brightness = init_val
            logger.info(f"Đã đọc độ sáng thực tế ban đầu từ phần cứng: {self.current_brightness}%")
        else:
            logger.info(f"Không thể đọc độ sáng ban đầu, sử dụng mặc định: {self.current_brightness}%")

        # Khởi động luồng worker áp dụng độ sáng (Debounced Background Worker)
        self._apply_event = threading.Event()
        self._stop_event = threading.Event()
        self._worker_thread = threading.Thread(target=self._apply_worker, daemon=True)
        self._worker_thread.start()

        # Khởi động luồng định kỳ đồng bộ độ sáng từ Windows (Sync polling 2s)
        self._sync_thread = threading.Thread(target=self._sync_worker, daemon=True)
        self._sync_thread.start()

        self._initialized = True

    def _get_primary_hmonitor(self):
        h_wnd = user32.GetDesktopWindow()
        return user32.MonitorFromWindow(h_wnd, 1)  # MONITOR_DEFAULTTOPRIMARY

    def _read_dxva2_brightness(self) -> Optional[int]:
        if not dxva2:
            return None
        h_mon = self._get_primary_hmonitor()
        if not h_mon:
            return None
        count = wintypes.DWORD()
        if not dxva2.GetNumberOfPhysicalMonitorsFromHMONITOR(h_mon, ctypes.byref(count)) or count.value == 0:
            return None
        monitors = (PHYSICAL_MONITOR * count.value)()
        if not dxva2.GetPhysicalMonitorsFromHMONITOR(h_mon, count.value, monitors):
            return None
        res = None
        try:
            min_b = wintypes.DWORD()
            cur_b = wintypes.DWORD()
            max_b = wintypes.DWORD()
            if dxva2.GetMonitorBrightness(monitors[0].hPhysicalMonitor, ctypes.byref(min_b), ctypes.byref(cur_b), ctypes.byref(max_b)):
                res = int(cur_b.value)
        except Exception:
            pass
        finally:
            dxva2.DestroyPhysicalMonitors(count.value, monitors)
        return res

    def _set_dxva2_brightness(self, percent: int) -> bool:
        if not dxva2:
            return False
        h_mon = self._get_primary_hmonitor()
        if not h_mon:
            return False
        count = wintypes.DWORD()
        if not dxva2.GetNumberOfPhysicalMonitorsFromHMONITOR(h_mon, ctypes.byref(count)) or count.value == 0:
            return False
        monitors = (PHYSICAL_MONITOR * count.value)()
        if not dxva2.GetPhysicalMonitorsFromHMONITOR(h_mon, count.value, monitors):
            return False
        success = False
        try:
            for i in range(count.value):
                if dxva2.SetMonitorBrightness(monitors[i].hPhysicalMonitor, percent):
                    success = True
        except Exception as e:
            logger.debug(f"dxva2.SetMonitorBrightness lỗi: {e}")
        finally:
            dxva2.DestroyPhysicalMonitors(count.value, monitors)
        return success

    def _read_wmi_brightness(self) -> Optional[int]:
        try:
            import wmi
            w = wmi.WMI(namespace="root/wmi")
            b_list = w.WmiMonitorBrightness()
            if b_list and hasattr(b_list[0], "CurrentBrightness"):
                return int(b_list[0].CurrentBrightness)
        except Exception:
            pass
        return None

    def _set_wmi_brightness(self, percent: int) -> bool:
        try:
            import wmi
            w = wmi.WMI(namespace="root/wmi")
            methods = w.WmiMonitorBrightnessMethods()
            if methods:
                methods[0].WmiSetBrightness(Timeout=1, Brightness=percent)
                return True
        except Exception:
            pass
        return False

    def _set_gdi_gamma(self, percent: int) -> bool:
        try:
            hdc = user32.GetDC(None)
            if not hdc:
                return False
            ramp = (wintypes.WORD * 768)()
            factor = max(0.1, min(1.0, percent / 100.0))
            for i in range(256):
                val = int(i * 256 * factor)
                val = min(65535, max(0, val))
                ramp[i] = val
                ramp[i + 256] = val
                ramp[i + 512] = val
            res = gdi32.SetDeviceGammaRamp(hdc, ramp)
            user32.ReleaseDC(None, hdc)
            return bool(res)
        except Exception as e:
            logger.debug(f"GDI SetDeviceGammaRamp lỗi: {e}")
            return False

    def _read_hardware_brightness(self) -> Optional[int]:
        # Tầng 1: dxva2 DDC/CI
        val = self._read_dxva2_brightness()
        if val is not None:
            return val
        # Tầng 2: WMI ACPI
        val = self._read_wmi_brightness()
        if val is not None:
            return val
        return None

    def _apply_worker(self):
        """Worker áp dụng độ sáng ngầm có debounce, tránh nghẽn I2C DDC/CI bus"""
        while not self._stop_event.is_set():
            if self._apply_event.wait(timeout=0.5):
                self._apply_event.clear()
                with self._lock:
                    target = self._target_brightness

                # 1. Thử Tầng 1: Win32 dxva2 DDC/CI (Ưu tiên số 1)
                ok = self._set_dxva2_brightness(target)

                # 2. Thử Tầng 2: ACPI WMI nếu dxva2 không thành công
                if not ok:
                    ok = self._set_wmi_brightness(target)

                # 3. Fallback Tầng 3: GDI Gamma Ramp nếu cả hai phần cứng không hỗ trợ
                if not ok:
                    ok = self._set_gdi_gamma(target)

                if ok:
                    self.current_brightness = target

                time.sleep(0.04)  # 40ms debounce

    def _sync_worker(self):
        """Định kỳ 2 giây đồng bộ độ sáng nếu người dùng thay đổi bên ngoài Windows"""
        while not self._stop_event.is_set():
            time.sleep(2.0)
            if self._is_setting:
                continue
            try:
                hw_val = self._read_hardware_brightness()
                if hw_val is not None and abs(hw_val - self.current_brightness) >= 2:
                    logger.info(f"Đồng bộ độ sáng từ Windows: {self.current_brightness}% -> {hw_val}%")
                    with self._lock:
                        self.current_brightness = hw_val
                        self._target_brightness = hw_val
            except Exception:
                pass

    def get_brightness(self) -> int:
        return self.current_brightness

    def set_brightness(self, percent: int) -> bool:
        percent = max(0, min(100, percent))
        with self._lock:
            self._target_brightness = percent
            self.current_brightness = percent
            self._is_setting = True

        self._apply_event.set()

        # Reset cờ is_setting sau 300ms
        def _clear_is_setting():
            time.sleep(0.3)
            self._is_setting = False

        threading.Thread(target=_clear_is_setting, daemon=True).start()
        return True
