import sys
import os
import winreg
from src.core.logger import setup_logger

logger = setup_logger("AutostartService")

APP_NAME = "WindowsHandheldTool"
RUN_KEY_PATH = r"Software\Microsoft\Windows\CurrentVersion\Run"

class AutostartService:
    @staticmethod
    def is_enabled() -> bool:
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY_PATH, 0, winreg.KEY_READ) as key:
                winreg.QueryValueEx(key, APP_NAME)
                return True
        except FileNotFoundError:
            return False
        except Exception as e:
            logger.error(f"Lỗi kiểm tra autostart: {e}")
            return False

    @staticmethod
    def set_enabled(enable: bool) -> bool:
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY_PATH, 0, winreg.KEY_SET_VALUE) as key:
                if enable:
                    # Đường dẫn tệp thực thi hiện tại
                    exe_path = os.path.abspath(sys.argv[0])
                    if exe_path.endswith(".py"):
                        val = f'"{sys.executable}" "{exe_path}"'
                    else:
                        val = f'"{exe_path}"'
                    winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, val)
                    logger.info(f"Đã bật khởi động cùng Windows: {val}")
                else:
                    try:
                        winreg.DeleteValue(key, APP_NAME)
                        logger.info("Đã tắt khởi động cùng Windows.")
                    except FileNotFoundError:
                        pass
            return True
        except Exception as e:
            logger.error(f"Lỗi gán autostart: {e}")
            return False
