import os
import sys
import shutil
import ctypes
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
        self._ensure_driver_sync()
        self._load_library()
        self._initialized = True

    def _ensure_driver_sync(self):
        """Đồng bộ WinRing0x64.sys và các DLL cần thiết ra cùng thư mục với tiến trình Python để driver nhân không lỗi"""
        try:
            exe_dir = os.path.dirname(os.path.abspath(sys.executable))
            root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            bin_dir = os.path.join(root_dir, "bin")

            critical_files = [
                "WinRing0x64.sys",
                "WinRing0x64.dll",
                "libryzenadj.dll",
                "ryzenadj.dll",
                "inpoutx64.dll",
            ]

            for fname in critical_files:
                bin_file = os.path.join(bin_dir, fname)
                root_file = os.path.join(root_dir, fname)
                exe_file = os.path.join(exe_dir, fname)

                # Đồng bộ ra root_dir
                if os.path.isfile(bin_file) and not os.path.isfile(root_file):
                    shutil.copyfile(bin_file, root_file)
                # Đồng bộ ra exe_dir nếu khác root_dir
                if os.path.isfile(bin_file) and not os.path.isfile(exe_file):
                    try:
                        shutil.copyfile(bin_file, exe_file)
                    except Exception:
                        pass
        except Exception as e:
            logger.warning(f"Lỗi khi đồng bộ tệp driver: {e}")

    def _load_library(self):
        root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        bin_dir = os.path.join(root_dir, "bin")

        candidates = [
            os.path.join(root_dir, "libryzenadj.dll"),
            os.path.join(bin_dir, "libryzenadj.dll"),
            os.path.join(root_dir, "ryzenadj.dll"),
            os.path.join(bin_dir, "ryzenadj.dll"),
        ]

        # Thêm đường dẫn dll directory cho Python 3.8+ trên Windows
        for p in [root_dir, bin_dir]:
            if os.path.isdir(p) and hasattr(os, "add_dll_directory"):
                try:
                    os.add_dll_directory(p)
                except Exception:
                    pass

        for path in candidates:
            if os.path.isfile(path):
                try:
                    self.lib = ctypes.cdll.LoadLibrary(path)
                    logger.info(f"Đã nạp thành công RyzenAdj DLL: {path}")
                    break
                except Exception as e:
                    logger.warning(f"Không thể nạp DLL từ {path}: {e}")

        if not self.lib:
            logger.warning("Không tìm thấy ryzenadj DLL. Dịch vụ TDP sẽ chạy ở chế độ mô phỏng.")
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

            self.ry_handle = self.lib.init_ryzenadj()
            if self.ry_handle:
                self.is_active = True
                if hasattr(self.lib, "init_table"):
                    self.lib.init_table(self.ry_handle)
                logger.info("RyzenAdj handle khởi tạo thành công.")
            else:
                logger.warning("init_ryzenadj trả về NULL.")
        except Exception as e:
            logger.error(f"Lỗi khi ánh xạ hàm RyzenAdj: {e}")

    def set_tdp(self, watts: int, fast_offset: int = 3, slow_offset: int = 0) -> bool:
        """Thiết lập đồng thời STAPM, Fast Limit và Slow Limit"""
        if not self.is_active or not self.ry_handle:
            logger.info(f"[Mô phỏng] Đặt TDP = {watts}W")
            return True

        stapm_mw = int(watts * 1000)
        fast_mw = int((watts + fast_offset) * 1000)
        slow_mw = int((watts + slow_offset) * 1000)

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
                        logger.warning(f"{func_name} thất bại với mã lỗi {res}")
                        success = False
                except Exception as e:
                    logger.error(f"Lỗi khi gọi {func_name}: {e}")
                    success = False
        return success

    def get_telemetry(self) -> Tuple[float, float, float]:
        """Trả về (CPU_Temp_C, TDP_Watt, Fast_Limit_Watt)"""
        if not self.is_active or not self.ry_handle:
            return 0.0, 0.0, 0.0
        try:
            self.lib.refresh_table(self.ry_handle)
            temp = self.lib.get_tctl_temp(self.ry_handle) if hasattr(self.lib, "get_tctl_temp") else 0.0
            stapm = self.lib.get_stapm_limit(self.ry_handle) if hasattr(self.lib, "get_stapm_limit") else 0.0
            fast = self.lib.get_fast_limit(self.ry_handle) if hasattr(self.lib, "get_fast_limit") else 0.0
            return float(temp), float(stapm), float(fast)
        except Exception:
            return 0.0, 0.0, 0.0
