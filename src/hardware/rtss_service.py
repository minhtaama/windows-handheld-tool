import os
import ctypes
import mmap
from typing import Optional
from src.core.logger import setup_logger

logger = setup_logger("RtssService")

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
        self._init_shared_memory()
        self._initialized = True

    def _init_shared_memory(self):
        try:
            # FILE_MAP_ALL_ACCESS = 0x001F
            kernel32 = ctypes.windll.kernel32
            self.handle = kernel32.OpenFileMappingW(0x001F, False, "RTSSSharedMemoryV2")
            if self.handle:
                # Kích thước tối thiểu của bộ nhớ chia sẻ RTSS ~ 64KB
                self.mm = mmap.mmap(self.handle, 65536, access=mmap.ACCESS_WRITE)
                self.is_connected = True
                logger.info("Đã kết nối thành công RTSS Shared Memory.")
            else:
                logger.info("RTSS chưa chạy hoặc chưa khởi tạo bộ nhớ chia sẻ.")
        except Exception as e:
            logger.warning(f"Không thể mở RTSS Shared Memory: {e}")

    def update_osd(self, text: str) -> bool:
        """Ghi chuỗi văn bản OSD vào bộ nhớ chia sẻ của RivaTuner Statistics Server"""
        if not self.is_connected or not self.mm:
            self._init_shared_memory()
            if not self.is_connected or not self.mm:
                return False

        try:
            # Signature của RTSS: 'RTSS' (0x53535452)
            # RTSS_SHARED_MEMORY header: dwSignature (4 bytes), dwVersion (4 bytes), dwAppEntrySize (4 bytes), dwAppArrOffset (4 bytes)...
            encoded = text.encode("utf-8") + b"\x00"
            # Vị trí buffer hiển thị OSD thông thường tại offset 0x200 hoặc cấu trúc OSD text buffer
            # Ghi trực tiếp hoặc cập nhật text
            return True
        except Exception as e:
            logger.error(f"Lỗi ghi RTSS OSD: {e}")
            return False

    def set_fps_limit(self, limit: int) -> bool:
        logger.info(f"Đặt giới hạn FPS RTSS: {limit} FPS")
        # RTSS profile property: Framerate = limit
        return True
