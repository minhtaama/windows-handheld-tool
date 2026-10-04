import time
import threading
from typing import Callable, Dict, List
import keyboard
from core.logger import setup_logger

logger = setup_logger("HotkeyManager")

class HotkeyManager:
    """
    Quản lý phím tắt toàn cục (Global Hotkeys) cho Windows Handheld.
    Hỗ trợ chế độ chờ nhả phím (Key Release) trước khi phát tín hiệu.
    """
    def __init__(self):
        self._registered_hotkeys: Dict[str, Callable] = {}
        self._is_waiting_release: bool = False

    def register(self, hotkey_str: str, callback: Callable, wait_for_release: bool = False) -> bool:
        """
        Đăng ký phím tắt mới.
        Nếu wait_for_release=True: Chờ cho tới khi người dùng nhả toàn bộ các phím
        trong tổ hợp ra khỏi bàn phím thì mới kích hoạt callback.
        """
        keys = [k.strip() for k in hotkey_str.split("+")]

        def _handler():
            if wait_for_release:
                threading.Thread(
                    target=self._wait_for_release_and_call,
                    args=(keys, callback),
                    daemon=True,
                    name=f"KeyReleaseWaitThread_{hotkey_str}"
                ).start()
            else:
                callback()

        try:
            keyboard.add_hotkey(hotkey_str, _handler, suppress=False)
            self._registered_hotkeys[hotkey_str] = _handler
            logger.info(f"Đã đăng ký phím tắt toàn cục: {hotkey_str} (wait_for_release={wait_for_release})")
            return True
        except Exception as e:
            logger.error(f"Lỗi khi đăng ký phím tắt '{hotkey_str}': {e}")
            return False

    def _wait_for_release_and_call(self, keys: List[str], callback: Callable) -> None:
        """Theo dõi liên tục cho đến khi toàn bộ phím được nhấc lên hoàn toàn."""
        if self._is_waiting_release:
            return
        self._is_waiting_release = True
        try:
            start_time = time.time()
            # Chờ người dùng nhấc ngón tay ra khỏi toàn bộ các phím (timeout tối đa 2.0 giây an toàn)
            while time.time() - start_time < 2.0:
                any_pressed = False
                for k in keys:
                    try:
                        if keyboard.is_pressed(k):
                            any_pressed = True
                            break
                    except Exception:
                        pass
                if not any_pressed:
                    break
                time.sleep(0.015)

            # Nghỉ thêm 30ms để Windows xả hết thông điệp Key Up trong hệ thống
            time.sleep(0.03)
            logger.info(f"Các phím {keys} đã nhả hoàn toàn. Kích hoạt hành động.")
            callback()
        finally:
            self._is_waiting_release = False

    def unregister(self, hotkey_str: str) -> bool:
        """Hủy đăng ký phím tắt."""
        if hotkey_str in self._registered_hotkeys:
            try:
                keyboard.remove_hotkey(hotkey_str)
                del self._registered_hotkeys[hotkey_str]
                logger.info(f"Đã hủy phím tắt: {hotkey_str}")
                return True
            except Exception as e:
                logger.warning(f"Lỗi khi hủy phím tắt '{hotkey_str}': {e}")
        return False

    def unregister_all(self) -> None:
        """Hủy tất cả phím tắt đã đăng ký."""
        for hotkey_str in list(self._registered_hotkeys.keys()):
            self.unregister(hotkey_str)
