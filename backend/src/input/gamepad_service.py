import ctypes
import threading
import time
from typing import Callable, Optional
from src.core.logger import setup_logger

logger = setup_logger("GamepadService")

# Cấu trúc XINPUT_GAMEPAD & XINPUT_STATE
class XINPUT_GAMEPAD(ctypes.Structure):
    _fields_ = [
        ("wButtons", ctypes.c_ushort),
        ("bLeftTrigger", ctypes.c_ubyte),
        ("bRightTrigger", ctypes.c_ubyte),
        ("sThumbLX", ctypes.c_short),
        ("sThumbLY", ctypes.c_short),
        ("sThumbRX", ctypes.c_short),
        ("sThumbRY", ctypes.c_short),
    ]

class XINPUT_STATE(ctypes.Structure):
    _fields_ = [
        ("dwPacketNumber", ctypes.c_ulong),
        ("Gamepad", XINPUT_GAMEPAD),
    ]

# Bitmasks của nút Gamepad XInput
XINPUT_GAMEPAD_DPAD_UP        = 0x0001
XINPUT_GAMEPAD_DPAD_DOWN      = 0x0002
XINPUT_GAMEPAD_DPAD_LEFT      = 0x0004
XINPUT_GAMEPAD_DPAD_RIGHT     = 0x0008
XINPUT_GAMEPAD_START          = 0x0010
XINPUT_GAMEPAD_BACK           = 0x0020
XINPUT_GAMEPAD_LEFT_THUMB     = 0x0040
XINPUT_GAMEPAD_RIGHT_THUMB    = 0x0080
XINPUT_GAMEPAD_LEFT_SHOULDER  = 0x0100 # LB
XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200 # RB
XINPUT_GAMEPAD_A              = 0x1000
XINPUT_GAMEPAD_B              = 0x2000
XINPUT_GAMEPAD_X              = 0x4000
XINPUT_GAMEPAD_Y              = 0x8000
XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE = 16000

# Ánh xạ tên nút (dạng UPPERCASE) sang Bitmask XInput
GAMEPAD_NAME_TO_MASK = {
    "DPAD_UP": XINPUT_GAMEPAD_DPAD_UP,
    "DPAD_DOWN": XINPUT_GAMEPAD_DPAD_DOWN,
    "DPAD_LEFT": XINPUT_GAMEPAD_DPAD_LEFT,
    "DPAD_RIGHT": XINPUT_GAMEPAD_DPAD_RIGHT,
    "START": XINPUT_GAMEPAD_START,
    "BACK": XINPUT_GAMEPAD_BACK,
    "LS": XINPUT_GAMEPAD_LEFT_THUMB,
    "RS": XINPUT_GAMEPAD_RIGHT_THUMB,
    "LB": XINPUT_GAMEPAD_LEFT_SHOULDER,
    "RB": XINPUT_GAMEPAD_RIGHT_SHOULDER,
    "A": XINPUT_GAMEPAD_A,
    "B": XINPUT_GAMEPAD_B,
    "X": XINPUT_GAMEPAD_X,
    "Y": XINPUT_GAMEPAD_Y,
}

# Ánh xạ Bitmask XInput sang tên nút GamepadButton phía Flutter
GAMEPAD_NAV_BUTTONS = [
    (XINPUT_GAMEPAD_DPAD_UP, "dpadUp"),
    (XINPUT_GAMEPAD_DPAD_DOWN, "dpadDown"),
    (XINPUT_GAMEPAD_DPAD_LEFT, "dpadLeft"),
    (XINPUT_GAMEPAD_DPAD_RIGHT, "dpadRight"),
    (XINPUT_GAMEPAD_A, "a"),
    (XINPUT_GAMEPAD_B, "b"),
    (XINPUT_GAMEPAD_X, "x"),
    (XINPUT_GAMEPAD_Y, "y"),
    (XINPUT_GAMEPAD_LEFT_SHOULDER, "lb"),
    (XINPUT_GAMEPAD_RIGHT_SHOULDER, "rb"),
    (XINPUT_GAMEPAD_START, "start"),
    (XINPUT_GAMEPAD_BACK, "back"),
]

class GamepadService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(GamepadService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.xinput = None
        self._load_xinput()
        self.running = False
        self.thread: Optional[threading.Thread] = None
        self.on_overlay_toggle: Optional[Callable[[], None]] = None
        self.on_keyboard_toggle: Optional[Callable[[], None]] = None
        self.on_button_press: Optional[Callable[[str], None]] = None
        self.overlay_combo_mask = XINPUT_GAMEPAD_BACK | XINPUT_GAMEPAD_RIGHT_SHOULDER
        self.keyboard_combo_mask = 0
        self.is_connected = False
        self.is_panel_visible = False
        self._overlay_combo_pressed = False
        self._keyboard_combo_pressed = False
        self._button_states = {}  # {btn_name: {"first_pressed": time, "last_repeat": time}}
        self._initialized = True

    def _load_xinput(self):
        for dll_name in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"]:
            try:
                self.xinput = ctypes.windll.LoadLibrary(dll_name)
                logger.info(f"Đã nạp XInput: {dll_name}")
                break
            except Exception:
                pass

    @staticmethod
    def _parse_combo(combo_str: str) -> int:
        """Chuyển đổi chuỗi tổ hợp nút gamepad (ví dụ: 'BACK+RB') sang bitmask tổng hợp"""
        if not combo_str:
            return 0
        mask = 0
        tokens = [t.strip().upper() for t in combo_str.split("+") if t.strip()]
        for tok in tokens:
            btn_mask = GAMEPAD_NAME_TO_MASK.get(tok)
            if btn_mask:
                mask |= btn_mask
        return mask

    def update_combos(self, overlay_combo: Optional[str] = None, keyboard_combo: Optional[str] = None):
        """Cập nhật nóng tổ hợp phím tắt Gamepad từ cấu hình mà không cần khởi động lại"""
        if overlay_combo is not None:
            self.overlay_combo_mask = self._parse_combo(overlay_combo)
            logger.info(f"Đã cập nhật Gamepad Overlay Combo: '{overlay_combo}' (mask: {hex(self.overlay_combo_mask)})")
        if keyboard_combo is not None:
            self.keyboard_combo_mask = self._parse_combo(keyboard_combo)
            logger.info(f"Đã cập nhật Gamepad Keyboard Combo: '{keyboard_combo}' (mask: {hex(self.keyboard_combo_mask)})")

    def start(
        self,
        toggle_callback: Callable[[], None],
        button_callback: Optional[Callable[[str], None]] = None,
        keyboard_callback: Optional[Callable[[], None]] = None,
        overlay_combo: str = "BACK+RB",
        keyboard_combo: str = "",
        poll_interval_ms: int = 30
    ):
        if self.running or not self.xinput:
            return
        self.on_overlay_toggle = toggle_callback
        self.on_button_press = button_callback
        self.on_keyboard_toggle = keyboard_callback
        self.overlay_combo_mask = self._parse_combo(overlay_combo)
        self.keyboard_combo_mask = self._parse_combo(keyboard_combo)
        self.running = True
        self.thread = threading.Thread(target=self._poll_loop, args=(poll_interval_ms / 1000.0,), daemon=True)
        self.thread.start()
        logger.info("XInput Polling Thread đã bắt đầu.")

    def set_panel_visible(self, visible: bool):
        """Đồng bộ trạng thái hiển thị của QuickPanel để kích hoạt chế độ điều hướng tay cầm"""
        self.is_panel_visible = visible
        if not visible:
            self._button_states.clear()

    def stop(self):
        self.running = False
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=0.2)

    def _poll_loop(self, interval_sec: float):
        xinput = self.xinput
        if not xinput:
            return
        state = XINPUT_STATE()
        while self.running:
            if not self.xinput:
                break
            try:
                res = xinput.XInputGetState(0, ctypes.byref(state))
                if res == 0:  # ERROR_SUCCESS
                    self.is_connected = True
                    buttons = state.Gamepad.wButtons
                    now = time.time()

                    # 1. Kiểm tra tổ hợp toàn cục mở/đóng panel (Overlay Combo)
                    is_overlay_combo = False
                    if self.overlay_combo_mask > 0:
                        is_overlay_combo = ((buttons & self.overlay_combo_mask) == self.overlay_combo_mask)
                        if is_overlay_combo:
                            if not self._overlay_combo_pressed:
                                self._overlay_combo_pressed = True
                                logger.info(f"Phát hiện tổ hợp mở Panel từ Gamepad (mask: {hex(self.overlay_combo_mask)}).")
                                if self.on_overlay_toggle:
                                    self.on_overlay_toggle()
                        else:
                            self._overlay_combo_pressed = False

                    # 2. Kiểm tra tổ hợp toàn cục mở/đóng Bàn phím ảo (Keyboard Combo)
                    is_keyboard_combo = False
                    if self.keyboard_combo_mask > 0:
                        is_keyboard_combo = ((buttons & self.keyboard_combo_mask) == self.keyboard_combo_mask)
                        if is_keyboard_combo:
                            if not self._keyboard_combo_pressed:
                                self._keyboard_combo_pressed = True
                                logger.info(f"Phát hiện tổ hợp mở Bàn phím ảo từ Gamepad (mask: {hex(self.keyboard_combo_mask)}).")
                                if self.on_keyboard_toggle:
                                    threading.Thread(target=self.on_keyboard_toggle, daemon=True).start()
                        else:
                            self._keyboard_combo_pressed = False

                    # 3. Khi QuickPanel đang mở: Quét các nút điều hướng và chuyển tiếp sang Flutter Web
                    # (Bỏ qua nếu đang bấm bất kỳ tổ hợp phím tắt toàn cục nào để tránh nhảy focus)
                    if self.is_panel_visible and not is_overlay_combo and not is_keyboard_combo:
                        thumb_lx = state.Gamepad.sThumbLX
                        thumb_ly = state.Gamepad.sThumbLY

                        for mask, btn_name in GAMEPAD_NAV_BUTTONS:
                            is_down = bool(buttons & mask)
                            # Ánh xạ cần Joystick trái (Left Thumbstick) sang các hướng D-Pad tương ứng
                            if btn_name == "dpadUp":
                                is_down = is_down or (thumb_ly > XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
                            elif btn_name == "dpadDown":
                                is_down = is_down or (thumb_ly < -XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
                            elif btn_name == "dpadLeft":
                                is_down = is_down or (thumb_lx < -XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
                            elif btn_name == "dpadRight":
                                is_down = is_down or (thumb_lx > XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)

                            btn_state = self._button_states.get(btn_name)

                            if is_down:
                                if not btn_state:
                                    # Lần bấm đầu tiên (Initial Trigger)
                                    self._button_states[btn_name] = {
                                        "first_pressed": now,
                                        "last_repeat": now
                                    }
                                    if self.on_button_press:
                                        self.on_button_press(btn_name)
                                else:
                                    # Người dùng đang giữ nút (Hold to repeat)
                                    # Initial delay 350ms, sau đó lặp lại mỗi 100ms
                                    hold_duration = now - btn_state["first_pressed"]
                                    if hold_duration >= 0.35:
                                        if now - btn_state["last_repeat"] >= 0.10:
                                            btn_state["last_repeat"] = now
                                            if self.on_button_press:
                                                self.on_button_press(btn_name)
                            else:
                                if btn_state:
                                    self._button_states.pop(btn_name, None)
                    else:
                        if self._button_states:
                            self._button_states.clear()
                else:
                    self.is_connected = False
                    self._button_states.clear()
            except AttributeError:
                break
            except Exception:
                pass
            time.sleep(interval_sec)


