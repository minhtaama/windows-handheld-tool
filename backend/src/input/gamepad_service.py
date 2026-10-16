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
        self.is_connected = False
        self._combo_pressed = False
        self._initialized = True

    def _load_xinput(self):
        for dll_name in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"]:
            try:
                self.xinput = ctypes.windll.LoadLibrary(dll_name)
                logger.info(f"Đã nạp XInput: {dll_name}")
                break
            except Exception:
                pass

    def start(self, toggle_callback: Callable[[], None], poll_interval_ms: int = 40):
        if self.running or not self.xinput:
            return
        self.on_overlay_toggle = toggle_callback
        self.running = True
        self.thread = threading.Thread(target=self._poll_loop, args=(poll_interval_ms / 1000.0,), daemon=True)
        self.thread.start()
        logger.info("XInput Polling Thread đã bắt đầu.")

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
                # Quét controller 0
                res = xinput.XInputGetState(0, ctypes.byref(state))
                if res == 0: # ERROR_SUCCESS
                    self.is_connected = True
                    buttons = state.Gamepad.wButtons
                    # Kiểm tra tổ hợp BACK + RB
                    is_back_rb = (buttons & XINPUT_GAMEPAD_BACK) and (buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
                    if is_back_rb:
                        if not self._combo_pressed:
                            self._combo_pressed = True
                            logger.info("Phát hiện tổ hợp phím BACK + RB từ Gamepad.")
                            if self.on_overlay_toggle:
                                self.on_overlay_toggle()
                    else:
                        self._combo_pressed = False
                else:
                    self.is_connected = False
            except AttributeError:
                break
            except Exception:
                pass
            time.sleep(interval_sec)

