import time
import threading
from typing import Callable, List, Optional
import XInput
from core.logger import setup_logger

logger = setup_logger("GamepadListener")

BUTTON_MAP = {
    "A": XInput.BUTTON_A,
    "B": XInput.BUTTON_B,
    "X": XInput.BUTTON_X,
    "Y": XInput.BUTTON_Y,
    "BACK": XInput.BUTTON_BACK,
    "START": XInput.BUTTON_START,
    "LEFT_SHOULDER": XInput.BUTTON_LEFT_SHOULDER,
    "RIGHT_SHOULDER": XInput.BUTTON_RIGHT_SHOULDER,
    "LEFT_THUMB": XInput.BUTTON_LEFT_THUMB,
    "RIGHT_THUMB": XInput.BUTTON_RIGHT_THUMB,
    "DPAD_UP": XInput.BUTTON_DPAD_UP,
    "DPAD_DOWN": XInput.BUTTON_DPAD_DOWN,
    "DPAD_LEFT": XInput.BUTTON_DPAD_LEFT,
    "DPAD_RIGHT": XInput.BUTTON_DPAD_RIGHT,
}

class GamepadListener:
    """
    Luồng chạy ngầm theo dõi trạng thái tay cầm Handheld (XInput) để kích hoạt Quick Settings.
    """
    def __init__(self, callback: Callable, toggle_combo: Optional[List[str]] = None, poll_interval_ms: int = 50):
        self._callback = callback
        self._toggle_combo = toggle_combo or ["BACK", "RIGHT_SHOULDER"]
        self._poll_interval = poll_interval_ms / 1000.0
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._was_combo_pressed = False

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._poll_loop, daemon=True, name="GamepadListenerThread")
        self._thread.start()
        logger.info(f"Gamepad listener đã khởi động. Tổ hợp phím kích hoạt: {' + '.join(self._toggle_combo)}")

    def stop(self) -> None:
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)
        logger.info("Gamepad listener đã dừng.")

    def _poll_loop(self) -> None:
        while self._running:
            try:
                connected = XInput.get_connected()
                any_pressed = False

                for user_index, is_conn in enumerate(connected):
                    if not is_conn:
                        continue

                    state = XInput.get_state(user_index)
                    buttons = state.Gamepad.wButtons

                    # Kiểm tra xem toàn bộ các phím trong tổ hợp có đang được nhấn không
                    combo_active = True
                    for btn_name in self._toggle_combo:
                        flag = BUTTON_MAP.get(btn_name.upper())
                        if flag is not None and not (buttons & flag):
                            combo_active = False
                            break

                    if combo_active:
                        any_pressed = True
                        break

                # Xử lý khử rung (Debounce): Chỉ kích hoạt khi vừa ấn xuống
                if any_pressed and not self._was_combo_pressed:
                    self._was_combo_pressed = True
                    logger.info("Phát hiện tổ hợp phím Gamepad! Kích hoạt Quick Settings.")
                    self._callback()
                elif not any_pressed:
                    self._was_combo_pressed = False

            except Exception as e:
                logger.debug(f"Lỗi polling Gamepad: {e}")

            time.sleep(self._poll_interval)
