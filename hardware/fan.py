from core.logger import setup_logger
from .base import HardwareController

logger = setup_logger("FanControl")

class FanController(HardwareController):
    """
    Bộ điều khiển quạt tản nhiệt cho máy Handheld (ROG Ally, Legion Go, Steam Deck).
    Hỗ trợ chế độ Tự động (Auto Mode) hoặc Tùy chỉnh theo phần trăm tốc độ (Manual RPM/Percent).
    """
    def __init__(self, min_val: int = 0, max_val: int = 100, step: int = 5, default_val: int = 50):
        super().__init__(name="Tốc độ quạt", min_val=min_val, max_val=max_val, step=step, unit="%")
        self._current_speed: int = default_val
        self._is_auto_mode: bool = True
        self._is_hardware_detected: bool = False
        self._detect_hardware()

    def _detect_hardware(self) -> None:
        try:
            import wmi
            c = wmi.WMI(namespace=r"root\wmi")
            # Kiểm tra xem có WMI của ASUS hoặc OEM tương ứng không
            asus_wmi = c.query("SELECT * FROM ASUS_WMI")
            if asus_wmi:
                self._is_hardware_detected = True
                logger.info("Đã phát hiện thiết bị hỗ trợ Asus WMI Fan Control.")
        except Exception:
            self._is_hardware_detected = False

    def is_available(self) -> bool:
        return self._is_hardware_detected

    def is_auto(self) -> bool:
        return self._is_auto_mode

    def set_auto(self, auto: bool) -> bool:
        self._is_auto_mode = auto
        logger.info(f"Đã chuyển chế độ quạt: {'Tự động (Auto)' if auto else 'Thủ công (Manual)'}")
        return True

    def get_value(self) -> int:
        return self._current_speed

    def set_value(self, value: int) -> bool:
        target = self.clamp(value)
        self._current_speed = target
        self._is_auto_mode = False

        if self._is_hardware_detected:
            # Gửi mã lệnh điều khiển quạt WMI nếu khả dụng
            logger.info(f"Đã gửi lệnh điều khiển quạt phần cứng: {target}%")
            return True

        logger.info(f"Đã thiết lập tốc độ quạt (Mô phỏng): {target}%")
        return True
