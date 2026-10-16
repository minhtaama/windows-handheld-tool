import ctypes
from ctypes import wintypes
import threading
import time
from typing import Callable, Optional, Tuple, Dict
from src.core.logger import setup_logger

logger = setup_logger("HotkeyCapture")

# Định nghĩa các mã phím ảo Win32 (Virtual-Key Codes) thông dụng
VK_MAPPINGS: Dict[int, str] = {
    0x08: "Backspace",
    0x09: "Tab",
    0x0D: "Enter",
    0x13: "Pause",
    0x14: "CapsLock",
    0x1B: "Esc",
    0x20: "Space",
    0x21: "PageUp",
    0x22: "PageDown",
    0x23: "End",
    0x24: "Home",
    0x25: "Left",
    0x26: "Up",
    0x27: "Right",
    0x28: "Down",
    0x2D: "Insert",
    0x2E: "Delete",
    0x5B: "Win",
    0x5C: "Win",
}
# Bổ sung các phím 0-9 và A-Z
for code in range(0x30, 0x3A):
    VK_MAPPINGS[code] = chr(code)
for code in range(0x41, 0x5B):
    VK_MAPPINGS[code] = chr(code)
# Bổ sung các phím F1 - F24
for i in range(1, 25):
    VK_MAPPINGS[0x70 + (i - 1)] = f"F{i}"

# Bitmask Gamepad XInput
GAMEPAD_BUTTON_NAMES: Dict[int, str] = {
    0x0001: "DPAD_UP",
    0x0002: "DPAD_DOWN",
    0x0004: "DPAD_LEFT",
    0x0008: "DPAD_RIGHT",
    0x0010: "START",
    0x0020: "BACK",
    0x0040: "LS",
    0x0080: "RS",
    0x0100: "LB",
    0x0200: "RB",
    0x1000: "A",
    0x2000: "B",
    0x4000: "X",
    0x8000: "Y",
}

class HotkeyCaptureService:
    """
    Dịch vụ bắt phím toàn cục cho Windows Handheld Tool.
    Sử dụng GetAsyncKeyState và XInputGetState để quét trực tiếp trạng thái phần cứng,
    hoàn toàn độc lập với việc cửa sổ có giữ tiêu điểm (Focus) hay không.
    """
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(HotkeyCaptureService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.is_capturing = False
        self.target: str = ""
        self._thread: Optional[threading.Thread] = None
        self._callback: Optional[Callable[[str, str, str, bool], None]] = None
        # callback signature: (target, device, combo, is_completed)
        self.user32 = ctypes.windll.user32
        self._load_xinput()
        self._initialized = True

    def _load_xinput(self):
        self.xinput = None
        for dll_name in ["xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"]:
            try:
                self.xinput = ctypes.windll.LoadLibrary(dll_name)
                break
            except Exception:
                pass

    def start_capture(self, target: str, callback: Callable[[str, str, str, bool], None]):
        """Bắt đầu phiên ghi nhận phím nóng cho một mục tiêu cụ thể ('overlay' hoặc 'keyboard')"""
        self.stop_capture()
        self.target = target
        self._callback = callback
        self.is_capturing = True
        self._thread = threading.Thread(target=self._capture_worker, daemon=True)
        self._thread.start()
        logger.info(f"Đã bắt đầu phiên quét phím nóng cho mục tiêu: {target}")

    def stop_capture(self):
        """Dừng phiên quét phím nóng"""
        self.is_capturing = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=0.3)
        self._thread = None
        self._callback = None

    def _get_pressed_modifiers(self) -> Tuple[bool, bool, bool, bool]:
        """Kiểm tra Ctrl, Alt, Shift, Win bằng GetAsyncKeyState"""
        is_ctrl = bool(self.user32.GetAsyncKeyState(0x11) & 0x8000)
        is_alt = bool(self.user32.GetAsyncKeyState(0x12) & 0x8000)
        is_shift = bool(self.user32.GetAsyncKeyState(0x10) & 0x8000)
        is_win = bool((self.user32.GetAsyncKeyState(0x5B) & 0x8000) or (self.user32.GetAsyncKeyState(0x5C) & 0x8000))
        return is_ctrl, is_alt, is_shift, is_win

    def _capture_worker(self):
        # Chờ người dùng nhả hết phím hiện tại trước khi bắt đầu nhận diện
        time.sleep(0.2)

        last_reported_keys = ""
        gamepad_hold_start = 0.0
        last_gamepad_buttons = 0

        # Cấu trúc XINPUT_STATE
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

        x_state = XINPUT_STATE()

        while self.is_capturing:
            # 1. Kiểm tra phím ESC để hủy
            if bool(self.user32.GetAsyncKeyState(0x1B) & 0x8000):
                logger.info("Người dùng nhấn ESC để hủy ghi nhận phím.")
                if self._callback:
                    self._callback(self.target, "", "ESC_CANCEL", True)
                break

            # 2. Quét bàn phím PC
            is_ctrl, is_alt, is_shift, is_win = self._get_pressed_modifiers()
            mods = []
            if is_ctrl: mods.append("Ctrl")
            if is_alt: mods.append("Alt")
            if is_shift: mods.append("Shift")
            if is_win: mods.append("Win")

            pressed_main_key = ""
            for vk, name in VK_MAPPINGS.items():
                if vk in (0x10, 0x11, 0x12, 0x5B, 0x5C, 0x1B):
                    continue
                if bool(self.user32.GetAsyncKeyState(vk) & 0x8000):
                    pressed_main_key = name
                    break

            if pressed_main_key:
                combo_parts = list(mods)
                if pressed_main_key not in combo_parts:
                    combo_parts.append(pressed_main_key)
                full_combo = "+".join(combo_parts)

                # Bàn phím hoàn thành ghi nhận ngay khi có phím chính
                if self._callback:
                    self._callback(self.target, "keyboard", full_combo, True)
                logger.info(f"Đã ghi nhận phím nóng Bàn phím: {full_combo}")
                break
            elif mods:
                current_mods = "+".join(mods)
                if current_mods != last_reported_keys:
                    last_reported_keys = current_mods
                    if self._callback:
                        self._callback(self.target, "keyboard", current_mods, False)

            # 3. Quét tay cầm Gamepad nếu có kết nối
            if self.xinput:
                res = self.xinput.XInputGetState(0, ctypes.byref(x_state))
                if res == 0:
                    buttons = x_state.Gamepad.wButtons
                    if buttons != 0:
                        pressed_names = [name for mask, name in GAMEPAD_BUTTON_NAMES.items() if (buttons & mask)]
                        if pressed_names:
                            gp_combo = "+".join(pressed_names)
                            now = time.time()
                            if buttons == last_gamepad_buttons:
                                # Giữ nút ít nhất 0.4s để xác nhận
                                if now - gamepad_hold_start >= 0.4:
                                    if self._callback:
                                        self._callback(self.target, "gamepad", gp_combo, True)
                                    logger.info(f"Đã ghi nhận tổ hợp Gamepad: {gp_combo}")
                                    break
                            else:
                                last_gamepad_buttons = buttons
                                gamepad_hold_start = now
                                if self._callback:
                                    self._callback(self.target, "gamepad", gp_combo, False)
                    else:
                        last_gamepad_buttons = 0

            time.sleep(0.04)  # Chu kỳ quét ~25Hz cực kỳ nhẹ nhàng cho CPU
        self.is_capturing = False

