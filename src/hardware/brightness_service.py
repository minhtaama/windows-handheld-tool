import subprocess
from src.core.logger import setup_logger

logger = setup_logger("BrightnessService")

class BrightnessService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(BrightnessService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.wmi_obj = None
        self.current_brightness = 75
        self._init_wmi()
        self._initialized = True

    def _init_wmi(self):
        try:
            import wmi
            self.wmi_obj = wmi.WMI(namespace="root/wmi")
            logger.info("WMI Brightness namespace kết nối thành công.")
        except Exception as e:
            logger.warning(f"Không thể khởi tạo WMI trực tiếp: {e}")

    def get_brightness(self) -> int:
        if self.wmi_obj:
            try:
                brightness_methods = self.wmi_obj.WmiMonitorBrightness()
                if brightness_methods:
                    self.current_brightness = int(brightness_methods[0].CurrentBrightness)
                    return self.current_brightness
            except Exception:
                pass
        return self.current_brightness

    def set_brightness(self, percent: int) -> bool:
        percent = max(0, min(100, percent))
        self.current_brightness = percent

        if self.wmi_obj:
            try:
                methods = self.wmi_obj.WmiMonitorBrightnessMethods()
                if methods:
                    methods[0].WmiSetBrightness(Timeout=1, Brightness=percent)
                    return True
            except Exception as e:
                logger.warning(f"Lỗi WmiSetBrightness: {e}")

        # Fallback PowerShell ngầm không mở cửa sổ cmd
        try:
            cmd = f"(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods) | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{{Timeout=1; Brightness={percent}}}"
            subprocess.run(
                ["powershell", "-NoProfile", "-Command", cmd],
                creationflags=0x08000000, # CREATE_NO_WINDOW
                timeout=2,
            )
            return True
        except Exception as e:
            logger.error(f"Lỗi fallback PowerShell brightness: {e}")
            return False
