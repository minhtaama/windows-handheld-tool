import subprocess
import threading
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
            brightness_methods = self.wmi_obj.WmiMonitorBrightness()
            if brightness_methods:
                self.current_brightness = int(brightness_methods[0].CurrentBrightness)
            logger.info("WMI Brightness namespace kết nối thành công.")
        except Exception as e:
            logger.warning(f"Không thể khởi tạo WMI Brightness trực tiếp: {e}")
            self.wmi_obj = None

    def get_brightness(self) -> int:
        return self.current_brightness

    def set_brightness(self, percent: int) -> bool:
        percent = max(0, min(100, percent))
        self.current_brightness = percent

        def _bg_apply():
            if self.wmi_obj:
                try:
                    methods = self.wmi_obj.WmiMonitorBrightnessMethods()
                    if methods:
                        methods[0].WmiSetBrightness(Timeout=1, Brightness=percent)
                        return
                except Exception as e:
                    logger.warning(f"Lỗi WmiSetBrightness: {e}")

            try:
                cmd = f"(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods) | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{{Timeout=1; Brightness={percent}}}"
                subprocess.run(
                    ["powershell", "-NoProfile", "-Command", cmd],
                    creationflags=0x08000000,  # CREATE_NO_WINDOW
                    timeout=2,
                )
            except Exception as e:
                logger.error(f"Lỗi fallback PowerShell brightness: {e}")

        threading.Thread(target=_bg_apply, daemon=True).start()
        return True
