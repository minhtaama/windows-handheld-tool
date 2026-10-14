import os
import sys
import struct
import ctypes
import mmap
import winreg
from typing import Optional
from src.core.logger import setup_logger

logger = setup_logger("RtssService")

RTSS_SIGNATURES = (0x53535452, 0x52545353)  # 'RTSS' trong little-endian / big-endian
OSD_APP_OWNER = "WindowsHandheldTool"

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
        self.handle = None
        self.rtss_dir: Optional[str] = self._detect_rtss_dir()
        self.hooks_dll = None
        self._load_hooks_dll()
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
            except Exception as e:
                logger.warning(f"Không thể nạp RTSSHooks64.dll: {e}")

    def _init_shared_memory(self):
        try:
            # FILE_MAP_ALL_ACCESS = 0x001F
            kernel32 = ctypes.windll.kernel32
            self.handle = kernel32.OpenFileMappingW(0x001F, False, "RTSSSharedMemoryV2")
            if self.handle:
                # Kích thước tối thiểu của bộ nhớ chia sẻ RTSS ~ 64KB
                self.mm = mmap.mmap(self.handle, 65536, access=mmap.ACCESS_WRITE)
                self.is_connected = True
                logger.info("Đã kết nối thành công RTSS Shared Memory V2.")
            else:
                self.is_connected = False
                self.mm = None
        except Exception as e:
            logger.warning(f"Không thể mở RTSS Shared Memory: {e}")
            self.is_connected = False
            self.mm = None

    def update_osd(self, text: str) -> bool:
        """Ghi chuỗi văn bản OSD vào bộ nhớ chia sẻ của RivaTuner Statistics Server theo chuẩn SDK"""
        if not self.is_connected or not self.mm:
            self._init_shared_memory()
            if not self.is_connected or not self.mm:
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

    def set_fps_limit(self, limit: int) -> bool:
        """Ghi giới hạn FPS vào tệp cấu hình profile Global của RTSS"""
        limit = max(0, min(360, limit))
        logger.info(f"Đặt giới hạn FPS RTSS: {limit} FPS")

        # 1. Thử cập nhật trực tiếp qua tệp cấu hình Global của RTSS
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
                logger.info(f"Đã ghi Framerate Limit={limit} vào {profile_path}")

                # Kích hoạt RTSS tải lại profile nếu có DLL
                if self.hooks_dll and hasattr(self.hooks_dll, "UpdateProfiles"):
                    self.hooks_dll.UpdateProfiles()

                return True
            except Exception as e:
                logger.error(f"Lỗi khi ghi profile RTSS: {e}")

        return False
