import os
import sys
import math
import ctypes
import subprocess
import threading
from ctypes import c_void_p, c_ulong, c_float
from typing import Optional, Tuple
from src.core.logger import setup_logger
from src.hardware.rapl_service import RaplService

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
        self.rapl = RaplService()
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
            bin_dirs.append(exe_dir)
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

        # Locate bin directory containing WinRing0x64 driver
        self.bin_dir = None
        for b in bin_dirs:
            if os.path.isdir(b) and os.path.isfile(os.path.join(b, "WinRing0x64.sys")):
                self.bin_dir = b
                break

        # Find fallback CLI ryzenadj.exe
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

        # CRITICAL: Switch working directory to bin_dir BEFORE loading libryzenadj.dll
        # so that WinRing0x64 dynamically locates WinRing0x64.sys in its own folder.
        orig_cwd = os.getcwd()
        try:
            if self.bin_dir and os.path.isdir(self.bin_dir):
                os.chdir(self.bin_dir)

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

            self.lib.init_ryzenadj.restype = c_void_p
            self.lib.refresh_table.argtypes = [c_void_p]
            self.lib.refresh_table.restype = ctypes.c_int
            self.lib.init_table.argtypes = [c_void_p]
            self.lib.init_table.restype = ctypes.c_int

            for fn in ["get_fast_limit", "get_slow_limit", "get_stapm_limit", "get_tctl_temp", "get_socket_power", "get_stapm_value", "get_core_power", "get_tctl_temp_value"]:
                if hasattr(self.lib, fn):
                    f = getattr(self.lib, fn)
                    f.restype = c_float
                    f.argtypes = [c_void_p]

            for fn in ["set_stapm_limit", "set_fast_limit", "set_slow_limit"]:
                if hasattr(self.lib, fn):
                    f = getattr(self.lib, fn)
                    f.restype = ctypes.c_int
                    f.argtypes = [c_void_p, c_ulong]

            self.ry_handle = self.lib.init_ryzenadj()
            if self.ry_handle:
                self.is_active = True
                self.is_hvci_blocked = False
                init_res = -1
                if hasattr(self.lib, "init_table"):
                    init_res = self.lib.init_table(self.ry_handle)

                if init_res == 0:
                    logger.info("RyzenAdj handle & PM table khởi tạo thành công ở mức Ring 0.")
                else:
                    logger.info(
                        f"RyzenAdj handle hợp lệ (PM table status: {init_res}). "
                        "Khả dụng điều chỉnh TDP qua SMU."
                    )
            else:
                self.is_active = False
                self.is_hvci_blocked = True
                logger.warning("init_ryzenadj trả về NULL (Yêu cầu quyền Administrator và tắt HVCI).")
        finally:
            try:
                os.chdir(orig_cwd)
            except Exception:
                pass
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

    def get_telemetry(self) -> Tuple[Optional[float], Optional[float], float]:
        """Return (CPU_Temp_C, Live_TDP_Watt, Fast_Limit_Watt).
        If Ring 0 driver is blocked by HVCI, both CPU_Temp_C and Live_TDP_Watt return None to trigger warning UI.
        """
        temp = 0.0
        fast = 0.0

        if self.is_active and self.ry_handle and self.lib:
            try:
                orig_cwd = os.getcwd()
                try:
                    if self.bin_dir and os.path.isdir(self.bin_dir):
                        os.chdir(self.bin_dir)
                    if hasattr(self.lib, "refresh_table"):
                        ref_code = self.lib.refresh_table(self.ry_handle)
                        if ref_code != 0:
                            logger.debug(f"refresh_table returned {ref_code}")
                finally:
                    try:
                        os.chdir(orig_cwd)
                    except Exception:
                        pass

                # Prioritize get_tctl_temp_value (actual live temperature) over get_tctl_temp (TJMax limit)
                if hasattr(self.lib, "get_tctl_temp_value"):
                    try:
                        t = float(self.lib.get_tctl_temp_value(self.ry_handle))
                        if not math.isnan(t) and t > 0.0:
                            temp = t
                    except Exception:
                        pass

                if (temp <= 0.0 or math.isnan(temp)) and hasattr(self.lib, "get_tctl_temp"):
                    try:
                        t = float(self.lib.get_tctl_temp(self.ry_handle))
                        if not math.isnan(t) and 0.0 < t < 95.0:
                            temp = t
                    except Exception:
                        pass

                live_power = 0.0
                # 1. Prioritize native Windows RAPL package power reader
                if self.rapl:
                    rapl_val = self.rapl.get_power_watts()
                    if rapl_val is not None and rapl_val > 0.0:
                        live_power = rapl_val

                if live_power <= 0.0 and hasattr(self.lib, "get_socket_power"):
                    try:
                        p = float(self.lib.get_socket_power(self.ry_handle))
                        if not math.isnan(p) and p > 0.0:
                            live_power = p
                    except Exception:
                        pass

                # On mobile APUs (Rembrandt/Phoenix), socket power is NaN; fallback to STAPM power
                if (live_power <= 0.0 or math.isnan(live_power)) and hasattr(self.lib, "get_stapm_value"):
                    try:
                        p = float(self.lib.get_stapm_value(self.ry_handle))
                        if not math.isnan(p) and p > 0.0:
                            live_power = p
                    except Exception:
                        pass

                if (live_power <= 0.0 or math.isnan(live_power)) and hasattr(self.lib, "get_core_power"):
                    try:
                        p = float(self.lib.get_core_power(self.ry_handle))
                        if not math.isnan(p) and p > 0.0:
                            live_power = p
                    except Exception:
                        pass

                if hasattr(self.lib, "get_fast_limit"):
                    try:
                        f = float(self.lib.get_fast_limit(self.ry_handle))
                        if not math.isnan(f) and f > 0.0:
                            fast = f
                    except Exception:
                        pass

                valid_temp = float(round(temp, 1)) if (temp > 0.0 and not math.isnan(temp)) else None
                valid_power = float(round(live_power, 1)) if (live_power > 0.0 and not math.isnan(live_power)) else None
                fallback_fast = float(fast if (fast > 0.0 and not math.isnan(fast)) else getattr(self, "last_set_tdp", 15.0) + 3.0)

                if valid_temp is not None or valid_power is not None:
                    return valid_temp, valid_power, fallback_fast
            except Exception as e:
                logger.debug(f"Error in get_telemetry: {e}")

        # Return None when Ring 0 hardware driver is blocked by HVCI
        return None, None, float(getattr(self, "last_set_tdp", 15.0) + 3.0)

