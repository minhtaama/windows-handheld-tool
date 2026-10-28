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


WH_KEYBOARD_LL = 13
WM_KEYDOWN = 0x0100
WM_KEYUP = 0x0101
WM_SYSKEYDOWN = 0x0104
WM_SYSKEYUP = 0x0105

VK_SHIFT = 0x10
VK_CONTROL = 0x11
VK_MENU = 0x12
VK_LWIN = 0x5B
VK_RWIN = 0x5C

class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wintypes.DWORD),
        ("scanCode", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.c_ulonglong),
    ]

HOOKPROC = ctypes.WINFUNCTYPE(ctypes.c_longlong, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)


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
        self.hook_handle = None
        self._hook_proc_ref = None
        self.on_overlay_toggle: Optional[Callable[[], Any]] = None
        self.on_keyboard_toggle: Optional[Callable[[], Any]] = None
        self.overlay_hk = "Ctrl+Shift+Q"
        self.keyboard_hk = "Ctrl+Alt+K"
        self._last_overlay_trigger_time = 0.0
        self._last_keyboard_trigger_time = 0.0
        # Latched until the hotkey key is physically released: the low-level hook, the
        # RegisterHotKey message and the GetAsyncKeyState poll loop all fire for the SAME
        # press, and key auto-repeat keeps the key down for seconds, which used to toggle
        # the panel open and closed immediately (one press = 2-3 toggles).
        self._overlay_latched = False
        self._keyboard_latched = False
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

    def _check_modifiers_match(self, user32, target_mods: int) -> bool:
        """Kiểm tra trạng thái thực tế của các phím bổ trợ qua GetAsyncKeyState"""
        ctrl_down = bool((user32.GetAsyncKeyState(VK_CONTROL) & 0x8000))
        shift_down = bool((user32.GetAsyncKeyState(VK_SHIFT) & 0x8000))
        alt_down = bool((user32.GetAsyncKeyState(VK_MENU) & 0x8000))
        win_down = bool((user32.GetAsyncKeyState(VK_LWIN) & 0x8000) or (user32.GetAsyncKeyState(VK_RWIN) & 0x8000))

        req_ctrl = bool(target_mods & MOD_CONTROL)
        req_shift = bool(target_mods & MOD_SHIFT)
        req_alt = bool(target_mods & MOD_ALT)
        req_win = bool(target_mods & MOD_WIN)

        return (
            ctrl_down == req_ctrl
            and shift_down == req_shift
            and alt_down == req_alt
            and win_down == req_win
        )

    def _register_all(self, user32, kernel32):
        if self.overlay_hk:
            mod1, vk1 = self._parse_hotkey(self.overlay_hk)
            if vk1:
                res1 = user32.RegisterHotKey(None, HOTKEY_OVERLAY_ID, mod1, vk1)
                logger.info(f"[SEAMLESS-HOTKEY] RegisterHotKey Overlay ('{self.overlay_hk}'): Result={bool(res1)}")

        if self.keyboard_hk:
            mod2, vk2 = self._parse_hotkey(self.keyboard_hk)
            if vk2:
                res2 = user32.RegisterHotKey(None, HOTKEY_KEYBOARD_ID, mod2, vk2)
                logger.info(f"[SEAMLESS-HOTKEY] RegisterHotKey Keyboard ('{self.keyboard_hk}'): Result={bool(res2)}")

    def _unregister_all(self, user32):
        user32.UnregisterHotKey(None, HOTKEY_OVERLAY_ID)
        user32.UnregisterHotKey(None, HOTKEY_KEYBOARD_ID)

    def _msg_loop(self):
        user32 = ctypes.windll.user32
        kernel32 = ctypes.windll.kernel32
        self.thread_id = kernel32.GetCurrentThreadId()

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

        user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD]
        user32.SetWindowsHookExW.restype = wintypes.HHOOK

        user32.UnhookWindowsHookEx.argtypes = [wintypes.HHOOK]
        user32.UnhookWindowsHookEx.restype = wintypes.BOOL

        user32.CallNextHookEx.argtypes = [wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
        user32.CallNextHookEx.restype = ctypes.c_longlong

        import time

        def _ll_keyboard_proc(nCode: int, wParam: wintypes.WPARAM, lParam: wintypes.LPARAM) -> int:
            if nCode >= 0 and wParam in (WM_KEYUP, WM_SYSKEYUP):
                # Nhả phím mới cho phép kích hoạt lần tiếp theo
                try:
                    vk_up = ctypes.cast(lParam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents.vkCode
                    if self.overlay_hk and vk_up == self._parse_hotkey(self.overlay_hk)[1]:
                        self._overlay_latched = False
                    if self.keyboard_hk and vk_up == self._parse_hotkey(self.keyboard_hk)[1]:
                        self._keyboard_latched = False
                except Exception:
                    pass
                return user32.CallNextHookEx(self.hook_handle, nCode, wParam, lParam)

            if nCode >= 0 and wParam in (WM_KEYDOWN, WM_SYSKEYDOWN):
                try:
                    kb_data = ctypes.cast(lParam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
                    vk = kb_data.vkCode
                    now = time.time()

                    # 1. Bắt tổ hợp phím Overlay
                    if self.overlay_hk:
                        o_mod, o_vk = self._parse_hotkey(self.overlay_hk)
                        if vk == o_vk and self._check_modifiers_match(user32, o_mod):
                            if not self._overlay_latched and now - self._last_overlay_trigger_time > 0.35:
                                self._overlay_latched = True
                                self._last_overlay_trigger_time = now
                                logger.info(f"[SEAMLESS-HOTKEY] WH_KEYBOARD_LL bắt thành công Overlay Hotkey ({self.overlay_hk})!")
                                if self.on_overlay_toggle:
                                    self.on_overlay_toggle()
                            return 1  # Nuốt phím để tránh truyền xuống game

                    # 2. Bắt tổ hợp phím Keyboard
                    if self.keyboard_hk:
                        k_mod, k_vk = self._parse_hotkey(self.keyboard_hk)
                        if vk == k_vk and self._check_modifiers_match(user32, k_mod):
                            if not self._keyboard_latched and now - self._last_keyboard_trigger_time > 0.35:
                                self._keyboard_latched = True
                                self._last_keyboard_trigger_time = now
                                logger.info(f"[SEAMLESS-HOTKEY] WH_KEYBOARD_LL bắt thành công Keyboard Hotkey ({self.keyboard_hk})!")
                                if self.on_keyboard_toggle:
                                    threading.Thread(target=self.on_keyboard_toggle, daemon=True).start()
                            return 1

                except Exception as ex:
                    logger.debug(f"Lỗi _ll_keyboard_proc: {ex}")

            return user32.CallNextHookEx(self.hook_handle, nCode, wParam, lParam)

        self._hook_proc_ref = HOOKPROC(_ll_keyboard_proc)
        # Đối với WH_KEYBOARD_LL toàn cục, hMod = None (0) là chuẩn xác trên Windows 10/11
        self.hook_handle = user32.SetWindowsHookExW(
            WH_KEYBOARD_LL,
            self._hook_proc_ref,
            None,
            0
        )
        if self.hook_handle:
            logger.info("[SEAMLESS-HOTKEY] Cài đặt thành công Low-Level Keyboard Hook (WH_KEYBOARD_LL, Handle=%s)" % self.hook_handle)
        else:
            logger.warning("[SEAMLESS-HOTKEY] SetWindowsHookExW thất bại (Mã lỗi: %s)" % kernel32.GetLastError())

        # Khởi động luồng phần cứng độc lập GetAsyncKeyState (Hardware Polling) dự phòng kép
        threading.Thread(target=self._hardware_poll_loop, daemon=True).start()
        logger.info("[SEAMLESS-HOTKEY] Đã khởi động luồng phần cứng GetAsyncKeyState Polling Thread (20ms).")

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
                now = time.time()
                if msg.wParam == HOTKEY_OVERLAY_ID:
                    if not self._overlay_latched and now - self._last_overlay_trigger_time > 0.35:
                        self._overlay_latched = True
                        self._last_overlay_trigger_time = now
                        logger.info(f"[SEAMLESS-HOTKEY] Phát hiện nhấn phím nóng Overlay ({self.overlay_hk}) qua WM_HOTKEY.")
                        if self.on_overlay_toggle:
                            self.on_overlay_toggle()
                elif msg.wParam == HOTKEY_KEYBOARD_ID:
                    if not self._keyboard_latched and now - self._last_keyboard_trigger_time > 0.35:
                        self._keyboard_latched = True
                        self._last_keyboard_trigger_time = now
                        logger.info(f"[SEAMLESS-HOTKEY] Phát hiện nhấn phím nóng Bàn phím ảo ({self.keyboard_hk}) qua WM_HOTKEY.")
                        if self.on_keyboard_toggle:
                            threading.Thread(target=self.on_keyboard_toggle, daemon=True).start()

            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

        if self.hook_handle:
            user32.UnhookWindowsHookEx(self.hook_handle)
            self.hook_handle = None
        self._unregister_all(user32)
        logger.info("Đã dọn dẹp và hủy toàn bộ phím tắt toàn cục.")

    def _hardware_poll_loop(self):
        user32 = ctypes.windll.user32
        import time
        while self.running:
            try:
                now = time.time()

                # Nhả phím -> mở khoá latch để lần nhấn sau mới kích hoạt lại
                if self.overlay_hk:
                    o_mod, o_vk = self._parse_hotkey(self.overlay_hk)
                    if o_vk and not (user32.GetAsyncKeyState(o_vk) & 0x8000):
                        self._overlay_latched = False
                if self.keyboard_hk:
                    k_mod, k_vk = self._parse_hotkey(self.keyboard_hk)
                    if k_vk and not (user32.GetAsyncKeyState(k_vk) & 0x8000):
                        self._keyboard_latched = False

                # 1. Thăm dò tổ hợp phím Overlay
                if self.overlay_hk and not self._overlay_latched and (now - self._last_overlay_trigger_time > 0.4):
                    o_mod, o_vk = self._parse_hotkey(self.overlay_hk)
                    if o_vk and bool(user32.GetAsyncKeyState(o_vk) & 0x8000):
                        if self._check_modifiers_match(user32, o_mod):
                            self._overlay_latched = True
                            self._last_overlay_trigger_time = now
                            logger.info(f"[SEAMLESS-HOTKEY] Hardware Polling bắt thành công Overlay Hotkey ({self.overlay_hk})!")
                            if self.on_overlay_toggle:
                                self.on_overlay_toggle()

                # 2. Thăm dò tổ hợp phím Virtual Keyboard
                if self.keyboard_hk and not self._keyboard_latched and (now - self._last_keyboard_trigger_time > 0.4):
                    k_mod, k_vk = self._parse_hotkey(self.keyboard_hk)
                    if k_vk and bool(user32.GetAsyncKeyState(k_vk) & 0x8000):
                        if self._check_modifiers_match(user32, k_mod):
                            self._keyboard_latched = True
                            self._last_keyboard_trigger_time = now
                            logger.info(f"[SEAMLESS-HOTKEY] Hardware Polling bắt thành công Keyboard Hotkey ({self.keyboard_hk})!")
                            if self.on_keyboard_toggle:
                                threading.Thread(target=self.on_keyboard_toggle, daemon=True).start()
            except Exception:
                pass
            time.sleep(0.02)
