import ctypes
import threading
from typing import Callable, Optional, Tuple, Any
from ctypes import wintypes
from src.core.logger import setup_logger

logger = setup_logger("HotkeyService")

MOD_ALT = 0x0001
MOD_CONTROL = 0x0002
MOD_SHIFT = 0x0004
MOD_WIN = 0x0008
MOD_NOREPEAT = 0x4000
WM_HOTKEY = 0x0312
WM_UPDATE_HOTKEYS = 0x0400 + 101  # WM_USER + 101

HOTKEY_OVERLAY_ID = 1001
HOTKEY_KEYBOARD_ID = 1002


class HotkeyService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(HotkeyService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.running = False
        self.thread: Optional[threading.Thread] = None
        self.thread_id = 0
        self.on_overlay_toggle: Optional[Callable[[], Any]] = None
        self.on_keyboard_toggle: Optional[Callable[[], Any]] = None
        self.overlay_hk = "Ctrl+Shift+Q"
        self.keyboard_hk = "Ctrl+Alt+K"
        self._initialized = True

    def start(
        self,
        on_overlay_toggle: Callable[[], Any],
        on_keyboard_toggle: Optional[Callable[[], Any]] = None,
        overlay_hk: str = "Ctrl+Shift+Q",
        keyboard_hk: str = "Ctrl+Alt+K",
    ):
        if self.running:
            return
        self.on_overlay_toggle = on_overlay_toggle
        self.on_keyboard_toggle = on_keyboard_toggle
        self.overlay_hk = overlay_hk or "Ctrl+Shift+Q"
        self.keyboard_hk = keyboard_hk or "Ctrl+Alt+K"
        self.running = True
        self.thread = threading.Thread(target=self._msg_loop, daemon=True)
        self.thread.start()

    def update_hotkeys(self, overlay_hk: Optional[str] = None, keyboard_hk: Optional[str] = None):
        """Cập nhật nóng phím tắt ngay trong luồng mà không cần khởi động lại ứng dụng"""
        changed = False
        if overlay_hk is not None and overlay_hk != self.overlay_hk:
            self.overlay_hk = overlay_hk
            changed = True
        if keyboard_hk is not None and keyboard_hk != self.keyboard_hk:
            self.keyboard_hk = keyboard_hk
            changed = True

        if changed and self.thread_id:
            logger.info(f"Yêu cầu đổi phím tắt: Overlay='{self.overlay_hk}', Keyboard='{self.keyboard_hk}'")
            ctypes.windll.user32.PostThreadMessageW(self.thread_id, WM_UPDATE_HOTKEYS, 0, 0)

    def stop(self):
        self.running = False
        if self.thread_id:
            ctypes.windll.user32.PostThreadMessageW(self.thread_id, 0x0012, 0, 0)  # WM_QUIT
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=1.0)

    @staticmethod
    def _parse_hotkey(hotkey_str: str) -> Tuple[int, int]:
        if not hotkey_str:
            return 0, 0
        parts = [p.strip().upper() for p in hotkey_str.split("+")]
        modifiers = MOD_NOREPEAT
        if "CTRL" in parts or "CONTROL" in parts:
            modifiers |= MOD_CONTROL
        if "SHIFT" in parts:
            modifiers |= MOD_SHIFT
        if "ALT" in parts:
            modifiers |= MOD_ALT
        if "WIN" in parts or "WINDOWS" in parts:
            modifiers |= MOD_WIN

        key_name = parts[-1] if parts else ""
        vk_code = 0
        if len(key_name) == 1:
            vk_code = ord(key_name)
        elif key_name.startswith("F") and key_name[1:].isdigit():
            f_num = int(key_name[1:])
            if 1 <= f_num <= 24:
                vk_code = 0x70 + (f_num - 1)
        elif key_name == "SPACE":
            vk_code = 0x20
        elif key_name == "TAB":
            vk_code = 0x09
        elif key_name in ("ESC", "ESCAPE"):
            vk_code = 0x1B

        return modifiers, vk_code

    def _register_all(self, user32, kernel32):
        # 1. Đăng ký phím tắt cho Quick Settings Overlay
        if self.overlay_hk:
            mod1, vk1 = self._parse_hotkey(self.overlay_hk)
            if vk1:
                res1 = user32.RegisterHotKey(None, HOTKEY_OVERLAY_ID, mod1, vk1)
                if res1:
                    logger.info(f"Đã đăng ký phím tắt Overlay: {self.overlay_hk}")
                else:
                    err1 = kernel32.GetLastError()
                    if err1 == 1409:
                        logger.warning(f"Phím tắt Overlay '{self.overlay_hk}' đang bị chiếm giữ bởi ứng dụng khác (Mã lỗi 1409: ERROR_HOTKEY_ALREADY_REGISTERED).")
                    else:
                        logger.warning(f"Không thể đăng ký phím tắt Overlay '{self.overlay_hk}' (Lỗi: {err1})")

        # 2. Đăng ký phím tắt cho Virtual Keyboard (TabTip)
        if self.keyboard_hk:
            mod2, vk2 = self._parse_hotkey(self.keyboard_hk)
            if vk2:
                res2 = user32.RegisterHotKey(None, HOTKEY_KEYBOARD_ID, mod2, vk2)
                if res2:
                    logger.info(f"Đã đăng ký phím tắt Bàn phím ảo: {self.keyboard_hk}")
                else:
                    err2 = kernel32.GetLastError()
                    if err2 == 1409:
                        logger.warning(f"Phím tắt Bàn phím ảo '{self.keyboard_hk}' đang bị chiếm giữ bởi ứng dụng khác (Mã lỗi 1409: ERROR_HOTKEY_ALREADY_REGISTERED).")
                    else:
                        logger.warning(f"Không thể đăng ký phím tắt Bàn phím ảo '{self.keyboard_hk}' (Lỗi: {err2})")

    def _unregister_all(self, user32):
        user32.UnregisterHotKey(None, HOTKEY_OVERLAY_ID)
        user32.UnregisterHotKey(None, HOTKEY_KEYBOARD_ID)

    def _msg_loop(self):
        user32 = ctypes.windll.user32
        kernel32 = ctypes.windll.kernel32
        self.thread_id = kernel32.GetCurrentThreadId()

        # Định nghĩa kiểu tham số 64-bit chuẩn cho Win32 HotKey API
        user32.RegisterHotKey.argtypes = [wintypes.HWND, ctypes.c_int, wintypes.UINT, wintypes.UINT]
        user32.RegisterHotKey.restype = wintypes.BOOL

        user32.UnregisterHotKey.argtypes = [wintypes.HWND, ctypes.c_int]
        user32.UnregisterHotKey.restype = wintypes.BOOL

        user32.PostThreadMessageW.argtypes = [wintypes.DWORD, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
        user32.PostThreadMessageW.restype = wintypes.BOOL

        user32.GetMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT]
        user32.GetMessageW.restype = wintypes.BOOL

        user32.TranslateMessage.argtypes = [ctypes.POINTER(wintypes.MSG)]
        user32.TranslateMessage.restype = wintypes.BOOL

        user32.DispatchMessageW.argtypes = [ctypes.POINTER(wintypes.MSG)]
        user32.DispatchMessageW.restype = wintypes.LPARAM

        self._register_all(user32, kernel32)

        msg = wintypes.MSG()
        while self.running:
            b_ret = user32.GetMessageW(ctypes.byref(msg), None, 0, 0)
            if b_ret <= 0:
                break

            if msg.message == WM_UPDATE_HOTKEYS:
                logger.info("Đang áp dụng tổ hợp phím tắt mới...")
                self._unregister_all(user32)
                self._register_all(user32, kernel32)
            elif msg.message == WM_HOTKEY:
                if msg.wParam == HOTKEY_OVERLAY_ID:
                    logger.info(f"Phát hiện nhấn phím nóng Overlay ({self.overlay_hk}).")
                    if self.on_overlay_toggle:
                        self.on_overlay_toggle()
                elif msg.wParam == HOTKEY_KEYBOARD_ID:
                    logger.info(f"Phát hiện nhấn phím nóng Bàn phím ảo ({self.keyboard_hk}).")
                    if self.on_keyboard_toggle:
                        threading.Thread(target=self.on_keyboard_toggle, daemon=True).start()

            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

        self._unregister_all(user32)
        logger.info("Đã hủy toàn bộ phím tắt toàn cục.")
