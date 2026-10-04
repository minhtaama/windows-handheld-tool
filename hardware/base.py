from abc import ABC, abstractmethod

class HardwareController(ABC):
    """
    Lớp cơ sở trừu tượng cho tất cả các bộ điều khiển phần cứng.
    Đảm bảo tính nhất quán (DRY) và độc lập (SoC) trong toàn bộ dự án.
    """
    def __init__(self, name: str, min_val: int = 0, max_val: int = 100, step: int = 1, unit: str = ""):
        self.name = name
        self.min_val = min_val
        self.max_val = max_val
        self.step = step
        self.unit = unit

    @abstractmethod
    def is_available(self) -> bool:
        """Kiểm tra xem phần cứng này có khả dụng trên máy hiện tại không."""
        pass

    @abstractmethod
    def get_value(self) -> int:
        """Lấy giá trị hiện tại của phần cứng."""
        pass

    @abstractmethod
    def set_value(self, value: int) -> bool:
        """Thiết lập giá trị mới cho phần cứng."""
        pass

    def clamp(self, value: int) -> int:
        """Hạn chế giá trị nằm trong ngưỡng min-max."""
        return max(self.min_val, min(self.max_val, value))
