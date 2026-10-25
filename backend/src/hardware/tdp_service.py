import os
import sys
import math
import time
import json
import ctypes
import subprocess
import threading
from ctypes import c_void_p, c_ulong, c_float
from typing import Optional, Tuple, Dict
from src.core.logger import setup_logger
from src.hardware.rapl_service import RaplService

logger = setup_logger("TdpService")

# Burst headroom above STAPM (RyzenAdj "fast" PPT). Writing fast == stapm removes the burst
# budget and measurably lowers average FPS, so keep the historical +3W offset.
FAST_BURST_OFFSET_W = 3

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
        self.persisted_tdp: Optional[float] = None
        self.rapl = RaplService()
        self._write_lock = threading.Lock()
        self._ensure_winring0_driver()
        self._load_library()
        # Restore the TDP the user last applied. Stored in %LOCALAPPDATA% so a deploy never
        # overwrites it (the shipped config.json still carries the factory default).
        self.persisted_tdp = self._load_persisted_tdp()
        if self.persisted_tdp:
            self.last_set_tdp = self.persisted_tdp
        else:
            # Nothing saved yet: mirror the limit currently programmed in the SMU so the UI
            # shows the real value instead of the factory default from config.json.
            current = self._read_stapm_limit_watts()
            if current:
                self.last_set_tdp = current
        self._reapply_running = True
        self._reapply_thread = threading.Thread(target=self._reapply_worker, daemon=True)
        self._reapply_thread.start()
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

            for fn in ["get_fast_limit", "get_slow_limit", "get_stapm_limit", "get_tctl_temp", "get_socket_power", "get_stapm_value", "get_tctl_temp_value"]:
                if hasattr(self.lib, fn):
                    f = getattr(self.lib, fn)
                    f.restype = c_float
                    f.argtypes = [c_void_p]

            # get_core_power/get_core_temp/get_core_clk take an extra uint32 core index
            if hasattr(self.lib, "get_core_power"):
                f = self.lib.get_core_power
                f.restype = c_float
                f.argtypes = [c_void_p, c_ulong]

            for fn in ["set_stapm_limit", "set_fast_limit", "set_slow_limit", "set_apu_slow_limit"]:
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
    def set_tdp(self, watts: int) -> bool:
        """Apply STAPM/Slow = target and Fast PPT = target + burst offset (APU SLOW stays at BIOS default)."""
        self.last_set_tdp = float(watts)
        self.persisted_tdp = float(watts)
        self._save_persisted_tdp(watts)
        mw = watts * 1000
        fast_mw = (watts + FAST_BURST_OFFSET_W) * 1000

        # 1. Prefer the DLL path when a valid Ring 0 handle is available
        if self.is_active and self.ry_handle and self.lib:
            results = self._write_limits_dll(watts)
            core_ok = all(results.get(f) == 0 for f in ("set_stapm_limit", "set_fast_limit", "set_slow_limit"))
            logger.info(f"Đặt TDP = {watts}W (fast={watts + FAST_BURST_OFFSET_W}W) qua RyzenAdj DLL: {results}")
            if core_ok:
                return True

        # 2. Fallback to the bundled ryzenadj.exe CLI on a background thread
        if self.cli_path and os.path.isfile(self.cli_path):
            cli_exe = self.cli_path
            def _bg_cli():
                try:
                    cmd = [
                        cli_exe,
                        f"--stapm-limit={mw}",
                        f"--fast-limit={fast_mw}",
                        f"--slow-limit={mw}",
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

    def _invoke_set(self, func_name: str, value_mw: int) -> int:
        """Call a libryzenadj set_* export and return its SMU status code (0 = OK)."""
        f = getattr(self.lib, func_name, None)
        if f is None:
            return -998
        try:
            f.argtypes = [c_void_p, c_ulong]
            f.restype = ctypes.c_int
            return int(f(self.ry_handle, value_mw))
        except Exception as e:
            logger.warning(f"{func_name} raised: {e}")
            return -997

    def _write_limits_dll(self, watts: int) -> Dict[str, int]:
        """Write STAPM/Slow = target and Fast PPT = target + burst offset.

        `set_apu_slow_limit` is intentionally NOT written: on Phoenix/Rembrandt handhelds it caps the
        SoC/iGPU budget, and forcing it down to the STAPM value throttles the GPU far below the
        configured TDP (measured: 72-85 fps -> 26-44 fps at the same 15W).
        """
        mw = watts * 1000
        fast_mw = (watts + FAST_BURST_OFFSET_W) * 1000
        results: Dict[str, int] = {}
        with self._write_lock:
            results["set_stapm_limit"] = self._invoke_set("set_stapm_limit", mw)
            results["set_fast_limit"] = self._invoke_set("set_fast_limit", fast_mw)
            results["set_slow_limit"] = self._invoke_set("set_slow_limit", mw)
        return results

    @staticmethod
    def _state_path() -> str:
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        return os.path.join(base, "WindowsHandheldTools", "tdp_state.json")

    def _read_stapm_limit_watts(self) -> Optional[float]:
        """Read the STAPM limit currently programmed in the SMU (None when unavailable)."""
        if not (self.is_active and self.ry_handle and self.lib):
            return None
        try:
            getter = getattr(self.lib, "get_stapm_limit", None)
            if getter is None:
                return None
            value = float(getter(self.ry_handle))
            if not math.isnan(value) and 1.0 < value < 100.0:
                return value
        except Exception as e:
            logger.debug(f"Không đọc được STAPM limit hiện tại: {e}")
        return None

    def _load_persisted_tdp(self) -> Optional[float]:
        """Read the TDP value the user last applied, or None when nothing was saved yet."""
        try:
            with open(self._state_path(), "r", encoding="utf-8") as f:
                value = float(json.load(f).get("current", 0))
            return value if value > 0 else None
        except Exception:
            return None

    def _save_persisted_tdp(self, watts: float) -> None:
        try:
            path = self._state_path()
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"current": watts}, f)
        except Exception as e:
            logger.warning(f"Không lưu được TDP đã đặt vào {self._state_path()}: {e}")

    def _reapply_worker(self):
        """Periodically re-write the persisted limit to counter EC/firmware reverting it."""
        while self._reapply_running:
            time.sleep(5.0)
            if not (self.is_active and self.ry_handle and self.lib and self.last_set_tdp > 0):
                continue
            try:
                results = self._write_limits_dll(int(self.last_set_tdp))
                if not all(results.get(f) == 0 for f in ("set_stapm_limit", "set_fast_limit", "set_slow_limit")):
                    logger.warning(f"Re-apply TDP {int(self.last_set_tdp)}W bị SMU từ chối: {results}")
            except Exception as e:
                logger.debug(f"Reapply loop error: {e}")

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
                fallback_fast = float(fast if (fast > 0.0 and not math.isnan(fast)) else getattr(self, "last_set_tdp", 15.0))

                if valid_temp is not None or valid_power is not None:
                    return valid_temp, valid_power, fallback_fast
            except Exception as e:
                logger.debug(f"Error in get_telemetry: {e}")

        # Return None when Ring 0 hardware driver is blocked by HVCI
        return None, None, float(getattr(self, "last_set_tdp", 15.0))

