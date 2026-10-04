import ctypes
from pathlib import Path
from core.logger import setup_logger
from .base import HardwareController

logger = setup_logger("TdpControl")

class TdpController(HardwareController):
    """
    Điều khiển TDP cho CPU/APU Handheld (AMD APU qua RyzenAdj).
    Hỗ trợ chế độ mô phỏng an toàn khi chạy trên máy không tương thích hoặc chưa có ryzenadj.dll.
    """
    def __init__(self, min_val: int = 5, max_val: int = 35, step: int = 1, default_val: int = 15):
        super().__init__(name="TDP", min_val=min_val, max_val=max_val, step=step, unit="W")
        self._current_tdp: int = default_val
        self._ryzen_dll = None
        self._ryzen_handle = None
        self._is_hardware_active: bool = False
        self._init_ryzenadj()

    def _init_ryzenadj(self) -> None:
        dll_candidates = [
            Path("bin/ryzenadj.dll"),
            Path("lib/ryzenadj.dll"),
            Path("ryzenadj.dll"),
            Path(r"C:\Program Files\RyzenAdj\ryzenadj.dll")
        ]
        dll_path = next((p for p in dll_candidates if p.exists()), None)

        if dll_path:
            try:
                self._ryzen_dll = ctypes.CDLL(str(dll_path.resolve()))
                self._ryzen_dll.init_ryzenadj.restype = ctypes.c_void_p
                self._ryzen_dll.set_stapm_limit.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
                self._ryzen_dll.set_fast_limit.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
                self._ryzen_dll.set_slow_limit.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

                self._ryzen_handle = self._ryzen_dll.init_ryzenadj()
                if self._ryzen_handle:
                    self._is_hardware_active = True
                    logger.info("Khởi tạo thành công kết nối phần cứng RyzenAdj DLL.")
            except Exception as e:
                logger.warning(f"Không thể nạp thư viện ryzenadj.dll: {e}")
        else:
            logger.info("Chưa phát hiện file ryzenadj.dll. Hoạt động ở chế độ mô phỏng an toàn.")

    def is_available(self) -> bool:
        return self._is_hardware_active

    def get_value(self) -> int:
        return self._current_tdp

    def set_value(self, value: int) -> bool:
        target = self.clamp(value)
        self._current_tdp = target
        mw = target * 1000  # Đổi sang miliwatt

        if self._is_hardware_active and self._ryzen_dll and self._ryzen_handle:
            try:
                # Thiết lập đồng bộ các ngưỡng TDP: STAPM, Fast PPT, Slow PPT
                self._ryzen_dll.set_stapm_limit(self._ryzen_handle, ctypes.c_uint32(mw))
                self._ryzen_dll.set_fast_limit(self._ryzen_handle, ctypes.c_uint32(int(mw * 1.2)))
                self._ryzen_dll.set_slow_limit(self._ryzen_handle, ctypes.c_uint32(mw))
                logger.info(f"Đã cập nhật TDP phần cứng: {target}W")
                return True
            except Exception as e:
                logger.error(f"Lỗi khi ghi thông số TDP vào SMU: {e}")
                return False

        logger.info(f"Đã thiết lập TDP (Mô phỏng): {target}W")
        return True
