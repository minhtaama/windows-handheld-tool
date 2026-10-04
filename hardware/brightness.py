import subprocess
from core.logger import setup_logger
from .base import HardwareController

logger = setup_logger("BrightnessControl")

class BrightnessController(HardwareController):
    def __init__(self, min_val: int = 0, max_val: int = 100, step: int = 5):
        super().__init__(name="Độ sáng", min_val=min_val, max_val=max_val, step=step, unit="%")
        self._wmi_instance = None
        self._current_cache: int = 70
        self._init_wmi()

    def _init_wmi(self) -> None:
        try:
            import wmi
            self._wmi_instance = wmi.WMI(namespace="wmi")
        except Exception as e:
            logger.warning(f"Không thể khởi tạo kết nối WMI Brightness: {e}")
            self._wmi_instance = None

    def is_available(self) -> bool:
        if not self._wmi_instance:
            return False
        try:
            methods = self._wmi_instance.WmiMonitorBrightnessMethods()
            return len(methods) > 0
        except Exception:
            return False

    def get_value(self) -> int:
        if self._wmi_instance:
            try:
                monitors = self._wmi_instance.WmiMonitorBrightness()
                if monitors:
                    val = int(monitors[0].CurrentBrightness)
                    self._current_cache = val
                    return val
            except Exception as e:
                logger.debug(f"Lỗi khi đọc độ sáng WMI: {e}")
        return self._current_cache

    def set_value(self, value: int) -> bool:
        target = self.clamp(value)
        self._current_cache = target
        if self._wmi_instance:
            try:
                methods = self._wmi_instance.WmiMonitorBrightnessMethods()
                if methods:
                    for method in methods:
                        method.WmiSetBrightness(Timeout=1, Brightness=target)
                    return True
            except Exception as e:
                logger.debug(f"WmiSetBrightness thất bại: {e}. Thử fallback powershell.")

        # Fallback qua PowerShell WmiSetBrightness
        try:
            cmd = f"(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, {target})"
            subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, timeout=2)
            return True
        except Exception as e:
            logger.warning(f"Không thể thay đổi độ sáng: {e}")
            return False
