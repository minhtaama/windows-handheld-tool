import os
import sys
import time
import struct
import ctypes
from ctypes import wintypes
import mmap
import winreg
import subprocess
import threading
from typing import Optional, Tuple
from src.core.logger import setup_logger

logger = setup_logger("RtssService")

RTSS_SIGNATURES = (0x53535452, 0x52545353)  # 'RTSS' trong little-endian / big-endian
OSD_APP_OWNER = "WindowsHandheldTool"

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
kernel32.OpenFileMappingW.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.LPCWSTR]
kernel32.OpenFileMappingW.restype = wintypes.HANDLE
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL


class RtssService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(RtssService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.is_connected = False
        self.mm: Optional[mmap.mmap] = None
        self.app_arr_offset: int = 0
        self.app_arr_size: int = 0
        self.app_entry_size: int = 0
        self.rtss_dir: Optional[str] = self._detect_rtss_dir()
        self.hooks_dll = None
        self._last_launch_attempt: float = 0.0
        self._is_launching: bool = False
        self._load_hooks_dll()
        self._ensure_rtss_profiles()
        self._init_shared_memory()
        self._initialized = True

    def _detect_rtss_dir(self) -> Optional[str]:
        for root in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            for sub in (r"SOFTWARE\WOW6432Node\Unwinder\RTSS", r"SOFTWARE\Unwinder\RTSS"):
                try:
                    with winreg.OpenKey(root, sub) as key:
                        val, _ = winreg.QueryValueEx(key, "InstallPath")
                        if os.path.isdir(val):
                            return val
                except Exception:
                    pass
        candidates = [
            r"C:\Program Files (x86)\RivaTuner Statistics Server",
            r"C:\Program Files\RivaTuner Statistics Server",
        ]
        for c in candidates:
            if os.path.isdir(c):
                return c
        return None

    def _load_hooks_dll(self):
        if not self.rtss_dir:
            return
        dll_path = os.path.join(self.rtss_dir, "RTSSHooks64.dll")
        if os.path.isfile(dll_path):
            try:
                self.hooks_dll = ctypes.cdll.LoadLibrary(dll_path)
                if hasattr(self.hooks_dll, "LoadProfile"):
                    self.hooks_dll.LoadProfile.argtypes = [ctypes.c_char_p]
                    self.hooks_dll.LoadProfile.restype = None
                if hasattr(self.hooks_dll, "SaveProfile"):
                    self.hooks_dll.SaveProfile.argtypes = [ctypes.c_char_p]
                    self.hooks_dll.SaveProfile.restype = None
                if hasattr(self.hooks_dll, "SetProfileProperty"):
                    self.hooks_dll.SetProfileProperty.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_uint32]
                    self.hooks_dll.SetProfileProperty.restype = ctypes.c_bool
                if hasattr(self.hooks_dll, "GetProfileProperty"):
                    self.hooks_dll.GetProfileProperty.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_uint32]
                    self.hooks_dll.GetProfileProperty.restype = ctypes.c_bool
                if hasattr(self.hooks_dll, "UpdateProfiles"):
                    self.hooks_dll.UpdateProfiles.argtypes = []
                    self.hooks_dll.UpdateProfiles.restype = None
                logger.info("Đã nạp và cấu hình chữ ký API RTSSHooks64.dll thành công.")
            except Exception as e:
                logger.warning(f"Không thể nạp RTSSHooks64.dll: {e}")

    def _close_mm(self):
        if self.mm:
            try:
                self.mm.close()
            except Exception:
                pass
            self.mm = None
        self.is_connected = False

    def _init_shared_memory(self):
        if self.is_connected and self.mm:
            return

        handle = None
        try:
            # Kiểm tra trước xem RTSS đã khởi tạo vùng nhớ RTSSSharedMemoryV2 hay chưa (FILE_MAP_WRITE = 0x0002)
            handle = kernel32.OpenFileMappingW(0x0002, False, "RTSSSharedMemoryV2")
            if not handle:
                self._close_mm()
                return

            # Mở tạm 40 bytes đầu tiên để đọc Header xác định tổng kích thước vùng nhớ OSD & AppEntries thực tế
            temp_mm = mmap.mmap(-1, 40, tagname="RTSSSharedMemoryV2", access=mmap.ACCESS_READ)
            header_bytes = temp_mm.read(40)
            temp_mm.close()

            if len(header_bytes) < 40:
                self._close_mm()
                return

            sig, ver, app_entry_size, app_arr_offset, app_arr_size, \
                osd_entry_size, osd_arr_offset, osd_arr_size, osd_frame, busy = \
                struct.unpack("<IIIIIIIIII", header_bytes)

            if sig not in RTSS_SIGNATURES or osd_arr_size == 0 or osd_entry_size == 0:
                self._close_mm()
                return

            self.app_arr_offset = app_arr_offset
            self.app_arr_size = app_arr_size
            self.app_entry_size = app_entry_size

            # Bao phủ toàn bộ cả mảng OSD slots và mảng App entries
            total_size = max(
                65536,
                osd_arr_offset + (osd_arr_size * osd_entry_size),
                app_arr_offset + (app_arr_size * app_entry_size),
            )
            self.mm = mmap.mmap(-1, total_size, tagname="RTSSSharedMemoryV2", access=mmap.ACCESS_WRITE)
            self.is_connected = True
            logger.info(f"Đã kết nối thành công RTSS Shared Memory V2 (Kích thước map: {total_size} bytes, {app_arr_size} app entries).")
        except Exception as e:
            logger.debug(f"Không thể mở RTSS Shared Memory: {e}")
            self._close_mm()
        finally:
            if handle:
                kernel32.CloseHandle(handle)

    def _ensure_rtss_profiles(self):
        """
        Configure RTSS profiles:
        1. Enable Global OSD (EnableOSD=1) so in-game overlay works automatically.
        2. Create exclusion profiles for Handheld Tool and Chromium WebEngine processes
           (EnableHooking=0, EnableOSD=0) to prevent OSD from rendering on Quick Panel.
        3. Force RTSS to reload profiles via RTSSHooks64 UpdateProfiles API.
        """
        if not self.rtss_dir:
            return

        profiles_dir = os.path.join(self.rtss_dir, "Profiles")
        if not os.path.isdir(profiles_dir):
            return

        # 1. Ensure Global Profile has EnableOSD=1
        global_path = os.path.join(profiles_dir, "Global")
        try:
            if os.path.isfile(global_path):
                with open(global_path, "r", encoding="utf-8", errors="ignore") as f:
                    g_content = f.read()
                needs_update = False
                if "[OSD]" not in g_content:
                    g_content = "[OSD]\nEnableOSD=1\n" + g_content
                    needs_update = True
                elif "EnableOSD=0" in g_content:
                    g_content = g_content.replace("EnableOSD=0", "EnableOSD=1")
                    needs_update = True
                if needs_update:
                    with open(global_path, "w", encoding="utf-8") as f:
                        f.write(g_content)
                    logger.info("Configured RTSS Global profile: EnableOSD=1")
        except Exception as e:
            logger.warning(f"Error checking RTSS Global profile: {e}")

        # 2. Exclude Quick Panel & Tool processes from hooking and OSD
        exclude_apps = [
            "windows_handheld_tool.exe",
            "QtWebEngineProcess.exe",
            "python.exe",
            "pythonw.exe",
        ]
        profile_content = "[Hooking]\nEnableHooking=0\n\n[OSD]\nEnableOSD=0\n"

        needs_reload = False
        for app in exclude_apps:
            for fname in (f"{app}.cfg", app):
                target_file = os.path.join(profiles_dir, fname)
                try:
                    if not os.path.isfile(target_file):
                        with open(target_file, "w", encoding="utf-8") as f:
                            f.write(profile_content)
                        needs_reload = True
                    else:
                        with open(target_file, "r", encoding="utf-8", errors="ignore") as f:
                            existing = f.read()
                        if "EnableHooking=0" not in existing or "EnableOSD=0" not in existing:
                            with open(target_file, "w", encoding="utf-8") as f:
                                f.write(profile_content)
                            needs_reload = True
                except PermissionError:
                    logger.debug(f"Permission denied writing RTSS profile {fname}. App requires elevation.")
                except Exception as e:
                    logger.debug(f"Error checking RTSS profile {fname}: {e}")

        # Also apply via RTSSHooks64 DLL API if available
        if self.hooks_dll and hasattr(self.hooks_dll, "SetProfileProperty"):
            try:
                val_0 = ctypes.c_uint32(0)
                for app in exclude_apps:
                    app_b = app.encode("utf-8")
                    self.hooks_dll.LoadProfile(b"")
                    self.hooks_dll.SetProfileProperty(b"EnableHooking", ctypes.byref(val_0), 4)
                    self.hooks_dll.SetProfileProperty(b"EnableOSD", ctypes.byref(val_0), 4)
                    self.hooks_dll.SetProfileProperty(b"AppDetectionLevel", ctypes.byref(val_0), 4)
                    self.hooks_dll.SaveProfile(app_b)
                needs_reload = True
            except Exception as e:
                logger.debug(f"Error setting RTSS profile properties via DLL: {e}")

        if needs_reload and self.hooks_dll and hasattr(self.hooks_dll, "UpdateProfiles"):
            try:
                self.hooks_dll.UpdateProfiles()
                logger.info("RTSS profiles reloaded successfully via UpdateProfiles().")
            except Exception as e:
                logger.debug(f"Error calling RTSSHooks UpdateProfiles: {e}")

    def ensure_running(self) -> bool:
        """Kiểm tra kết nối Shared Memory và kích hoạt ngầm RTSS.exe bất đồng bộ (không chặn Main Thread)"""
        if self.is_connected and self.mm:
            return True

        self._init_shared_memory()
        if self.is_connected and self.mm:
            return True

        if not self.rtss_dir:
            return False

        rtss_exe = os.path.join(self.rtss_dir, "RTSS.exe")
        if not os.path.isfile(rtss_exe):
            return False

        now = time.time()
        if self._is_launching or (now - self._last_launch_attempt < 15.0):
            return False

        self._last_launch_attempt = now
        self._is_launching = True

        def _bg_launch():
            try:
                self._ensure_rtss_profiles()
                logger.info(f"Đang kích hoạt tiến trình ngầm RivaTuner Statistics Server: {rtss_exe}")
                started = False
                try:
                    clean_env = os.environ.copy()
                    mei_dir = getattr(sys, "_MEIPASS", "")
                    exe_dir = os.path.dirname(os.path.abspath(sys.executable))
                    raw_paths = clean_env.get("PATH", "").split(os.pathsep)
                    filtered_paths = [
                        p for p in raw_paths
                        if p and (not mei_dir or not os.path.normcase(p).startswith(os.path.normcase(mei_dir)))
                        and not os.path.normcase(p).startswith(os.path.normcase(exe_dir))
                    ]
                    clean_env["PATH"] = os.pathsep.join(filtered_paths)

                    subprocess.Popen(
                        [rtss_exe],
                        cwd=self.rtss_dir,
                        env=clean_env,
                        creationflags=0x08000000,
                    )
                    started = True
                except Exception as e:
                    logger.debug(f"subprocess Popen RTSS thất bại: {e}")

                if not started:
                    try:
                        ret = ctypes.windll.shell32.ShellExecuteW(None, "open", rtss_exe, None, self.rtss_dir, 0)
                        if ret <= 32:
                            ctypes.windll.shell32.ShellExecuteW(None, "runas", rtss_exe, None, self.rtss_dir, 0)
                    except Exception as e:
                        logger.error(f"Lỗi khi khởi chạy RTSS qua ShellExecuteW: {e}")
            finally:
                self._is_launching = False

        threading.Thread(target=_bg_launch, daemon=True).start()
        return False

    def update_osd(self, text: str) -> bool:
        """Ghi chuỗi văn bản OSD vào bộ nhớ chia sẻ của RivaTuner Statistics Server theo chuẩn SDK"""
        if not self.is_connected or not self.mm:
            if not self.ensure_running() or not self.mm:
                return False

        try:
            self.mm.seek(0)
            header_bytes = self.mm.read(40)
            if len(header_bytes) < 40:
                return False

            sig, ver, app_entry_size, app_arr_offset, app_arr_size, \
                osd_entry_size, osd_arr_offset, osd_arr_size, osd_frame, busy = \
                struct.unpack("<IIIIIIIIII", header_bytes)

            if sig not in RTSS_SIGNATURES:
                return False

            target_slot = -1

            # 1st pass: Tìm slot đã thuộc quyền sở hữu của app
            for i in range(osd_arr_size):
                entry_offset = osd_arr_offset + (i * osd_entry_size)
                self.mm.seek(entry_offset + 256)
                owner_raw = self.mm.read(256).split(b"\x00")[0].decode("utf-8", errors="ignore")
                if owner_raw == OSD_APP_OWNER:
                    target_slot = i
                    break

            # 2nd pass: Nếu chưa có slot, tìm slot trống đầu tiên từ i = 1 (nhường slot 0 cho Afterburner)
            if target_slot == -1:
                for i in range(1, osd_arr_size):
                    entry_offset = osd_arr_offset + (i * osd_entry_size)
                    self.mm.seek(entry_offset + 256)
                    first_byte = self.mm.read(1)
                    if not first_byte or first_byte == b"\x00":
                        target_slot = i
                        break

            # 3rd pass: Nếu các slot từ 1 trở đi đã kín, kiểm tra slot 0
            if target_slot == -1 and osd_arr_size > 0:
                self.mm.seek(osd_arr_offset + 256)
                owner_raw = self.mm.read(256).split(b"\x00")[0].decode("utf-8", errors="ignore")
                if not owner_raw or owner_raw == OSD_APP_OWNER:
                    target_slot = 0

            if target_slot == -1:
                return False

            entry_offset = osd_arr_offset + (target_slot * osd_entry_size)

            # Đồng bộ khóa dwBusy (v2.14+)
            if ver >= 0x0002000E:
                if (busy & 1) != 0:
                    return False  # RTSS đang đọc để render, bỏ qua frame này
                self.mm.seek(36)
                self.mm.write(struct.pack("<I", busy | 1))

            try:
                # Ghi tên chủ sở hữu slot szOSDOwner tại offset + 256
                owner_encoded = OSD_APP_OWNER.encode("utf-8")[:255] + b"\x00"
                self.mm.seek(entry_offset + 256)
                self.mm.write(owner_encoded)

                text_bytes = text.encode("utf-8")
                if ver >= 0x00020007:
                    # Chuẩn RTSS v2.7+: szOSD[0] = 0 (tránh render lặp lại 2 lần)
                    self.mm.seek(entry_offset)
                    self.mm.write(b"\x00")
                    # Ghi chuỗi mở rộng vào szOSDEx (offset + 512, tối đa 4095 bytes)
                    self.mm.seek(entry_offset + 512)
                    self.mm.write(text_bytes[:4095] + b"\x00")
                else:
                    self.mm.seek(entry_offset)
                    self.mm.write(text_bytes[:255] + b"\x00")

                # Tăng dwOSDFrame tại offset 32 để RTSS vẽ lại ngay lập tức
                self.mm.seek(32)
                self.mm.write(struct.pack("<I", osd_frame + 1))
            finally:
                if ver >= 0x0002000E:
                    self.mm.seek(36)
                    self.mm.write(struct.pack("<I", 0))

            return True
        except Exception as e:
            logger.error(f"Lỗi ghi RTSS OSD: {e}")
            self._close_mm()
            return False

    def clear_osd(self) -> bool:
        """Xóa trắng chuỗi OSD do app tạo ra khi người dùng tắt OSD"""
        if not self.is_connected or not self.mm:
            return False
        try:
            self.mm.seek(0)
            header_bytes = self.mm.read(40)
            sig, ver, app_entry_size, app_arr_offset, app_arr_size, \
                osd_entry_size, osd_arr_offset, osd_arr_size, osd_frame, busy = \
                struct.unpack("<IIIIIIIIII", header_bytes)

            for i in range(osd_arr_size):
                entry_offset = osd_arr_offset + (i * osd_entry_size)
                self.mm.seek(entry_offset + 256)
                owner_raw = self.mm.read(256).split(b"\x00")[0].decode("utf-8", errors="ignore")
                if owner_raw == OSD_APP_OWNER:
                    # Xóa toàn bộ entry
                    self.mm.seek(entry_offset)
                    self.mm.write(b"\x00" * osd_entry_size)
                    # Tăng frame
                    self.mm.seek(32)
                    self.mm.write(struct.pack("<I", osd_frame + 1))
                    break
            return True
        except Exception:
            return False

    _IGNORED_APPS = {
        "windows_handheld_tool.exe",
        "qtwebengineprocess.exe",
        "python.exe",
        "pythonw.exe",
        "rtss.exe",
        "rivatunerstatisticsserver.exe",
        "rtsshstig.exe",
        "cloudflare warp.exe",
        "amdinstallmanager.exe",
        "explorer.exe",
        "taskmgr.exe",
        "dwmapi.exe",
    }

    def get_active_game_and_fps(self) -> Tuple[Optional[str], Optional[int]]:
        """
        Quét mảng AppEntries trong RTSSSharedMemoryV2 để lấy tên game đang chạy và FPS tức thời.
        Ưu tiên các ứng dụng 3D thực tế thay vì các tool nền.
        """
        if not self.is_connected or not self.mm:
            if not self.ensure_running() or not self.mm:
                return None, None

        if self.app_arr_size <= 0 or self.app_entry_size <= 0:
            return None, None

        try:
            fallback_candidate = None
            total_mm_size = self.mm.size()

            for i in range(self.app_arr_size):
                offset = self.app_arr_offset + (i * self.app_entry_size)
                if offset + 284 > total_mm_size:
                    break

                self.mm.seek(offset)
                data = self.mm.read(284)
                pid, = struct.unpack("<I", data[0:4])
                if pid == 0:
                    continue

                raw_name = data[4:264].split(b"\x00")[0].decode("utf-8", errors="ignore").strip()
                if not raw_name:
                    continue

                exe_name = os.path.basename(raw_name)
                time0, time1, frames, frametime = struct.unpack("<IIII", data[268:284])

                # Tính FPS tức thời từ micro-giây của frame gần nhất (chuẩn RTSS SDK)
                instant_fps = 0
                if frametime > 0:
                    instant_fps = round(1000000.0 / frametime)
                elif time1 > time0 and frames > 0:
                    instant_fps = round(1000.0 * frames / (time1 - time0))

                if instant_fps > 0:
                    if exe_name.lower() not in self._IGNORED_APPS:
                        # Tìm thấy game 3D thực sự đang render
                        return exe_name, instant_fps
                    elif fallback_candidate is None:
                        fallback_candidate = (exe_name, instant_fps)

            # Nếu không có game 3D ngoài nhưng có app fallback thì trả về None để không nhầm tool là game
            return None, None
        except Exception as e:
            logger.debug(f"Lỗi khi đọc AppEntries từ RTSS Shared Memory: {e}")
            return None, None

    def get_fps_limit(self) -> int:
        """Đọc giới hạn FPS hiện tại từ RTSSHooks64 DLL"""
        if self.hooks_dll and hasattr(self.hooks_dll, "GetProfileProperty"):
            try:
                self.hooks_dll.LoadProfile(b"")
                val = ctypes.c_uint32(0)
                if self.hooks_dll.GetProfileProperty(b"FramerateLimit", ctypes.byref(val), 4):
                    return int(val.value)
            except Exception as e:
                logger.debug(f"Lỗi đọc FramerateLimit qua RTSSHooks64: {e}")
        return 0

    def set_fps_limit(self, limit: int) -> bool:
        """Thiết lập giới hạn FPS qua RTSSHooks64 DLL API hoặc fallback ghi tệp cấu hình profile Global"""
        limit = max(0, min(360, limit))
        logger.info(f"Đặt giới hạn FPS RTSS: {limit} FPS")

        # 1. Ưu tiên hàng đầu: Sử dụng API chính thức của RTSSHooks64.dll
        if self.hooks_dll and hasattr(self.hooks_dll, "SetProfileProperty"):
            try:
                self.hooks_dll.LoadProfile(b"")
                val = ctypes.c_uint32(limit)
                res = self.hooks_dll.SetProfileProperty(b"FramerateLimit", ctypes.byref(val), 4)
                if res:
                    self.hooks_dll.SaveProfile(b"")
                    self.hooks_dll.UpdateProfiles()
                    logger.info(f"Đã cập nhật FramerateLimit={limit} qua RTSSHooks64 API thành công.")
                    return True
                else:
                    logger.warning("RTSSHooks64 SetProfileProperty trả về False.")
            except Exception as e:
                logger.warning(f"Lỗi khi cập nhật FramerateLimit qua DLL: {e}")

        # 2. Cơ chế Fallback: Ghi trực tiếp vào tệp cấu hình Global của RTSS nếu DLL lỗi
        if self.rtss_dir:
            profile_path = os.path.join(self.rtss_dir, "Profiles", "Global")
            try:
                lines = []
                if os.path.isfile(profile_path):
                    with open(profile_path, "r", encoding="utf-8", errors="ignore") as f:
                        lines = f.readlines()

                framerate_sec_found = False
                limit_found = False
                new_lines = []

                for line in lines:
                    stripped = line.strip()
                    if stripped.lower() == "[framerate]":
                        framerate_sec_found = True
                        new_lines.append(line)
                        continue
                    if framerate_sec_found and stripped.startswith("["):
                        if not limit_found:
                            new_lines.append(f"Limit={limit}\n")
                            limit_found = True
                        framerate_sec_found = False
                    if framerate_sec_found and stripped.lower().startswith("limit="):
                        new_lines.append(f"Limit={limit}\n")
                        limit_found = True
                        continue
                    new_lines.append(line)

                if not framerate_sec_found and not limit_found:
                    new_lines.append("\n[Framerate]\n")
                    new_lines.append(f"Limit={limit}\n")
                elif framerate_sec_found and not limit_found:
                    new_lines.append(f"Limit={limit}\n")

                os.makedirs(os.path.dirname(profile_path), exist_ok=True)
                with open(profile_path, "w", encoding="utf-8") as f:
                    f.writelines(new_lines)
                logger.info(f"Đã ghi Framerate Limit={limit} vào {profile_path} (Fallback)")

                if self.hooks_dll and hasattr(self.hooks_dll, "UpdateProfiles"):
                    self.hooks_dll.UpdateProfiles()

                return True
            except Exception as e:
                logger.error(f"Lỗi khi ghi profile RTSS fallback: {e}")

        return False

    def install_rtss_silent(self) -> bool:
        """Tự động cài đặt RTSS ngầm qua winget hoặc tải bộ cài đặt chính thức"""
        logger.info("Bắt đầu tiến trình tự động tải và cài đặt RTSS ngầm...")
        try:
            # 1. Thử cài đặt qua winget
            res = subprocess.run(
                ["winget", "install", "--id", "Guru3D.RTSS", "-e", "--silent", "--accept-package-agreements", "--accept-source-agreements"],
                capture_output=True,
                text=True,
                creationflags=0x08000000,
                timeout=180,
            )
            if res.returncode == 0:
                logger.info("Đã cài đặt RTSS thành công qua winget.")
                self.rtss_dir = self._detect_rtss_dir()
                self._load_hooks_dll()
                self.ensure_running()
                return True
        except Exception as e:
            logger.warning(f"Lỗi khi cài RTSS qua winget: {e}")

        # 2. Fallback tải installer qua PowerShell và chạy /S
        try:
            ps_script = """
            $url = 'https://download.guru3d.com/rtss/RTSSSetup737.exe'
            $out = "$env:TEMP\\RTSSSetup.exe"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 60
            if (Test-Path $out) {
                Start-Process -FilePath $out -ArgumentList '/S' -Wait
                Remove-Item $out -Force -ErrorAction SilentlyContinue
            }
            """
            subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_script],
                capture_output=True,
                creationflags=0x08000000,
                timeout=180,
            )
            self.rtss_dir = self._detect_rtss_dir()
            self._load_hooks_dll()
            self.ensure_running()
            return bool(self.rtss_dir)
        except Exception as e:
            logger.error(f"Lỗi fallback tải RTSS: {e}")
            return False
