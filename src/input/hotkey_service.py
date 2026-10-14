import ctypes
import threading
from typing import Callable, Optional
from ctypes import wintypes
from src.core.logger import setup_logger

logger = setup_logger("HotkeyService")

MOD_ALT     = 0x0001
MOD_CONTROL = 0x0002
MOD_SHIFT   = 0x0004
MOD_WIN     = 0x0008
MOD_NOREPEAT = 0x4000
WM_HOTKEY   = 0x0312

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
        self.on_overlay_toggle: Optional[Callable[[], None]] = None
        self._initialized = True

    def start(self, toggle_callback: Callable[[], None], hotkey_str: str = "Ctrl+Shift+Q"):
        if self.running:
            return
        self.on_overlay_toggle = toggle_callback
        self.running = True
        self.thread = threading.Thread(target=self._msg_loop, args=(hotkey_str,), daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        if self.thread_id:
            ctypes.windll.user32.PostThreadMessageW(self.thread_id, 0x0012, 0, 0) # WM_QUIT
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=1.0)

    def _msg_loop(self, hotkey_str: str):
        user32 = ctypes.windll.user32
        kernel32 = ctypes.windll.kernel32
        self.thread_id = kernel32.GetCurrentThreadId()

        # Parse hotkey
        parts = [p.strip().upper() for p in hotkey_str.split("+")]
        modifiers = MOD_NOREPEAT
        if "CTRL" in parts or "CONTROL" in parts:
            modifiers |= MOD_CONTROL
        if "SHIFT" in parts:
            modifiers |= MOD_SHIFT
        if "ALT" in parts:
            modifiers |= MOD_ALT
        if "WIN" in parts:
            modifiers |= MOD_WIN

        key_char = parts[-1] if parts else "Q"
        vk_code = ord(key_char[0]) if len(key_char) == 1 else 0x51 # 'Q' default

        hotkey_id = 1001
        res = user32.RegisterHotKey(None, hotkey_id, modifiers, vk_code)
        if not res:
            logger.warning(f"Không thể đăng ký phím tắt toàn cục {hotkey_str} (Mã lỗi: {kernel32.GetLastError()})")
        else:
            logger.info(f"Đã đăng ký thành công phím tắt toàn cục: {hotkey_str}")

        msg = wintypes.MSG()
        while self.running:
            b_ret = user32.GetMessageW(ctypes.byref(msg), None, 0, 0)
            if b_ret <= 0:
                break
            if msg.message == WM_HOTKEY and msg.wParam == hotkey_id:
                logger.info(f"Phát hiện nhấn phím nóng {hotkey_str}.")
                if self.on_overlay_toggle:
                    self.on_overlay_toggle()
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

        user32.UnregisterHotKey(None, hotkey_id)
        logger.info("Đã hủy đăng ký phím tắt toàn cục.")
