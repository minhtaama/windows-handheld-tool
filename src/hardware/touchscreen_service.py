import subprocess
import re
from typing import Optional
from src.core.logger import setup_logger

logger = setup_logger("TouchscreenService")

class TouchscreenService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(TouchscreenService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.instance_id: Optional[str] = None
        self.is_enabled: bool = True
        self._scan_touchscreen()
        self._initialized = True

    def _scan_touchscreen(self):
        try:
            res = subprocess.run(
                ["pnputil", "/enum-devices", "/class", "HIDClass"],
                capture_output=True,
                text=True,
                creationflags=0x08000000, # CREATE_NO_WINDOW
                timeout=5,
            )
            if res.returncode == 0:
                blocks = re.split(r"\r?\n\r?\n", res.stdout)
                for block in blocks:
                    lines = block.splitlines()
                    curr_id = None
                    desc = None
                    status = None
                    for line in lines:
                        line = line.strip()
                        if line.startswith("Instance ID:"):
                            curr_id = line.replace("Instance ID:", "").strip()
                        elif line.startswith("Device Description:"):
                            desc = line.replace("Device Description:", "").strip()
                        elif line.startswith("Status:"):
                            status = line.replace("Status:", "").strip()

                    if desc and ("touch screen" in desc.lower() or "touchscreen" in desc.lower()):
                        self.instance_id = curr_id
                        self.is_enabled = "started" in (status.lower() if status else "")
                        logger.info(f"Đã phát hiện màn hình cảm ứng: {self.instance_id} (Trạng thái: {'Bật' if self.is_enabled else 'Tắt'})")
                        return
        except Exception as e:
            logger.error(f"Lỗi khi quét màn hình cảm ứng: {e}")

        # Fallback ID cho thiết bị Handheld (GPD Win, Goodix) nếu không bắt được mô tả
        if not self.instance_id:
            self.instance_id = r"HID\GDIX1002\4&231bac70&0&0000"
            logger.info(f"Sử dụng fallback Touchscreen ID: {self.instance_id}")

    def toggle(self) -> bool:
        return self.set_enabled(not self.is_enabled)

    def set_enabled(self, enable: bool) -> bool:
        if not self.instance_id:
            self._scan_touchscreen()
            if not self.instance_id:
                logger.warning("Không tìm thấy màn hình cảm ứng trên thiết bị.")
                return False

        action_flag = "/enable-device" if enable else "/disable-device"
        logger.info(f"Thực thi pnputil {action_flag} '{self.instance_id}'...")

        try:
            res = subprocess.run(
                ["pnputil", action_flag, self.instance_id],
                capture_output=True,
                text=True,
                creationflags=0x08000000,
                timeout=5,
            )
            if res.returncode == 0:
                self.is_enabled = enable
                logger.info(f"Đã {'BẬT' if enable else 'TẮT'} màn hình cảm ứng thành công.")
                return True
            else:
                logger.warning(f"Lỗi khi đổi trạng thái touchscreen (ExitCode {res.returncode}): {res.stderr}")
                return False
        except Exception as e:
            logger.error(f"Lỗi gọi pnputil: {e}")
            return False
