import os
import subprocess
import ctypes
from src.core.logger import setup_logger

logger = setup_logger("VirtualKeyboard")

class VirtualKeyboardService:
    @staticmethod
    def toggle_keyboard():
        """Bật / Tắt bàn phím ảo Windows Touch Keyboard (TabTip)"""
        try:
            # 1. Gọi trực tiếp TabTip.exe của Windows
            tabtip_paths = [
                r"C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe",
                r"C:\Windows\System32\osk.exe",
            ]

            launched = False
            for p in tabtip_paths:
                if os.path.isfile(p):
                    try:
                        ctypes.windll.shell32.ShellExecuteW(
                            None,
                            "open",
                            p,
                            None,
                            None,
                            1, # SW_SHOWNORMAL
                        )
                        logger.info(f"Đã kích hoạt bàn phím ảo: {p}")
                        launched = True
                        break
                    except Exception as e:
                        logger.warning(f"Lỗi ShellExecute {p}: {e}")

            if not launched:
                subprocess.Popen(["cmd.exe", "/c", "start", "tabtip.exe"], shell=True)
                logger.info("Đã gửi lệnh khởi động TabTip qua cmd.")
            return True
        except Exception as e:
            logger.error(f"Lỗi khi mở bàn phím ảo: {e}")
            return False
