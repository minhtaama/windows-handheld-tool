import os
import sys
import ctypes
from src.core.logger import setup_logger

logger = setup_logger("FanService")

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
        self._load_inpout()
        self._initialized = True

    def _load_inpout(self):
        root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        bin_dir = os.path.join(root_dir, "bin")

        if os.path.isdir(bin_dir) and hasattr(os, "add_dll_directory"):
            try:
                os.add_dll_directory(bin_dir)
            except Exception:
                pass

        p = os.path.join(bin_dir, "inpoutx64.dll")
        if os.path.isfile(p):
            try:
                self.inpout = ctypes.windll.LoadLibrary(p)
                self.is_hardware_detected = True
                logger.info(f"Đã nạp thành công InpOutx64 từ bin: {p}")
            except Exception as e:
                logger.warning(f"Không thể nạp InpOutx64 từ {p}: {e}")

    def set_auto(self, auto: bool) -> bool:
        self.is_auto = auto
        logger.info(f"Chế độ quạt: {'Tự động (Auto)' if auto else 'Thủ công (Manual)'}")
        return True

    def set_speed(self, percent: int) -> bool:
        percent = max(0, min(100, percent))
        self.current_speed = percent
        self.is_auto = False

        if self.is_hardware_detected and self.inpout:
            logger.info(f"Đã gửi lệnh quạt phần cứng: {percent}%")
            return True

        logger.info(f"[Mô phỏng] Đặt tốc độ quạt: {percent}%")
        return True

    def get_speed(self) -> int:
        return self.current_speed
