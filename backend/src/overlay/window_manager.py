import ctypes
from ctypes import wintypes
import time
import os
import sys
from pathlib import Path
from typing import Optional

from PySide6.QtCore import QObject, Signal, Slot, QTimer
from PySide6.QtGui import QGuiApplication
from src.core.logger import setup_logger
from src.core.config import ConfigManager
from src.services.game_compat_service import GameCompatService

logger = setup_logger("WindowManager")

# Win32 Constants
GWL_EXSTYLE       = -20
GWL_STYLE         = -16
WS_EX_TOPMOST     = 0x00000008
WS_EX_TRANSPARENT = 0x00000020
WS_EX_TOOLWINDOW  = 0x00000080
WS_EX_NOACTIVATE  = 0x08000000

SW_HIDE            = 0
SW_SHOWNOACTIVATE  = 4

SWP_NOSIZE        = 0x0001
SWP_NOMOVE        = 0x0002
SWP_NOZORDER      = 0x0004
SWP_NOACTIVATE    = 0x0010
SWP_FRAMECHANGED  = 0x0020
SWP_SHOWWINDOW    = 0x0040
SWP_HIDEWINDOW    = 0x0080
SWP_NOOWNERZORDER = 0x0200

HWND_TOP          = wintypes.HWND(0)
HWND_BOTTOM       = wintypes.HWND(1)
HWND_TOPMOST      = wintypes.HWND(-1)
HWND_NOTOPMOST    = wintypes.HWND(-2)

# Windows internal Z-Order Band (ZBID) identifiers
ZBID_DESKTOP      = 1
ZBID_UIACCESS     = 2   # Privileged UIAccess band (not used: hides Flutter's hosted view)

user32 = ctypes.WinDLL("user32", use_last_error=True)

# 64-bit function prototypes to prevent handle truncation (error 1400)
user32.SetWindowPos.argtypes = [
    wintypes.HWND,
    wintypes.HWND,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.UINT,
]
user32.SetWindowPos.restype = wintypes.BOOL

user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.SetForegroundWindow.restype = wintypes.BOOL

user32.GetForegroundWindow.argtypes = []
user32.GetForegroundWindow.restype = wintypes.HWND

user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.GetClientRect.restype = wintypes.BOOL

user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.GetWindowRect.restype = wintypes.BOOL

user32.GetSystemMetrics.argtypes = [ctypes.c_int]
user32.GetSystemMetrics.restype = ctypes.c_int

user32.GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
user32.GetWindowLongW.restype = wintypes.LONG

user32.SetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int, wintypes.LONG]
user32.SetWindowLongW.restype = wintypes.LONG

WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
user32.EnumChildWindows.argtypes = [wintypes.HWND, WNDENUMPROC, wintypes.LPARAM]
user32.EnumChildWindows.restype = wintypes.BOOL

user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD

user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
user32.AttachThreadInput.restype = wintypes.BOOL

user32.AllowSetForegroundWindow.argtypes = [wintypes.DWORD]
user32.AllowSetForegroundWindow.restype = wintypes.BOOL

user32.ClipCursor.argtypes = [ctypes.POINTER(wintypes.RECT)]
user32.ClipCursor.restype = wintypes.BOOL

user32.keybd_event.argtypes = [wintypes.BYTE, wintypes.BYTE, wintypes.DWORD, ctypes.c_size_t]
user32.keybd_event.restype = None

user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
user32.FindWindowW.restype = wintypes.HWND

user32.IsWindow.argtypes = [wintypes.HWND]
user32.IsWindow.restype = wintypes.BOOL

user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.PostMessageW.restype = wintypes.BOOL

user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int

user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
user32.ShowWindow.restype = wintypes.BOOL

user32.FindWindowExW.argtypes = [wintypes.HWND, wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR]
user32.FindWindowExW.restype = wintypes.HWND

user32.SendMessageTimeoutW.argtypes = [
    wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM,
    wintypes.UINT, wintypes.UINT, ctypes.POINTER(ctypes.c_size_t)
]
user32.SendMessageTimeoutW.restype = wintypes.LPARAM

SMTO_ABORTIFHUNG = 0x0002
ASFW_ANY = 0xFFFFFFFF

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
kernel32.GetCurrentThreadId.argtypes = []
kernel32.GetCurrentThreadId.restype = wintypes.DWORD

kernel32.CreateEventW.argtypes = [ctypes.c_void_p, wintypes.BOOL, wintypes.BOOL, wintypes.LPCWSTR]
kernel32.CreateEventW.restype = wintypes.HANDLE

kernel32.SetEvent.argtypes = [wintypes.HANDLE]
kernel32.SetEvent.restype = wintypes.BOOL

kernel32.ResetEvent.argtypes = [wintypes.HANDLE]
kernel32.ResetEvent.restype = wintypes.BOOL

kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL

kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE

kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
kernel32.TerminateProcess.restype = wintypes.BOOL

PROCESS_TERMINATE = 0x0001

advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
advapi32.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [
    wintypes.LPCWSTR, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(wintypes.ULONG)
]
advapi32.ConvertStringSecurityDescriptorToSecurityDescriptorW.restype = wintypes.BOOL

class SECURITY_ATTRIBUTES(ctypes.Structure):
    _fields_ = [
        ("nLength", wintypes.DWORD),
        ("lpSecurityDescriptor", ctypes.c_void_p),
        ("bInheritHandle", wintypes.BOOL),
    ]

class MONITORINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("rcMonitor", wintypes.RECT),
        ("rcWork", wintypes.RECT),
        ("dwFlags", wintypes.DWORD),
    ]

MONITOR_DEFAULTTONEAREST = 2
MONITOR_DEFAULTTOPRIMARY = 1

user32.MonitorFromWindow.argtypes = [wintypes.HWND, wintypes.DWORD]
user32.MonitorFromWindow.restype = wintypes.HMONITOR

user32.GetMonitorInfoW.argtypes = [wintypes.HMONITOR, ctypes.POINTER(MONITORINFO)]
user32.GetMonitorInfoW.restype = wintypes.BOOL

# DWM Composition inspection API
dwmapi = ctypes.WinDLL("dwmapi", use_last_error=True)
pfnDwmIsCompositionEnabled = getattr(dwmapi, "DwmIsCompositionEnabled", None)
if pfnDwmIsCompositionEnabled:
    pfnDwmIsCompositionEnabled.argtypes = [ctypes.POINTER(wintypes.BOOL)]
    pfnDwmIsCompositionEnabled.restype = ctypes.c_long

def _decode_swp_flags(flags: int) -> str:
    parts = []
    if flags & SWP_NOSIZE: parts.append("NOSIZE")
    if flags & SWP_NOMOVE: parts.append("NOMOVE")
    if flags & SWP_NOZORDER: parts.append("NOZORDER")
    if flags & SWP_NOACTIVATE: parts.append("NOACTIVATE")
    if flags & SWP_FRAMECHANGED: parts.append("FRAMECHANGED(!)")
    if flags & SWP_SHOWWINDOW: parts.append("SHOWWINDOW")
    if flags & SWP_HIDEWINDOW: parts.append("HIDEWINDOW")
    if flags & SWP_NOOWNERZORDER: parts.append("NOOWNERZORDER")
    return " | ".join(parts) if parts else hex(flags)

def safe_set_window_pos(hwnd, hwnd_insert_after, x, y, cx, cy, flags: int) -> bool:
    """Wrapper for SetWindowPos with validation and diagnostic logging [SEAMLESS-1.5]."""
    has_frame_changed = bool(flags & SWP_FRAMECHANGED)
    flag_str = _decode_swp_flags(flags)
    h_val = hwnd.value if hasattr(hwnd, "value") else hwnd
    ins_val = hwnd_insert_after.value if hasattr(hwnd_insert_after, "value") else hwnd_insert_after
    logger.info(f"[SEAMLESS-1.5] SetWindowPos: HWND={h_val}, InsertAfter={ins_val}, Rect=({x},{y},{cx},{cy}), Flags={hex(flags)} [{flag_str}], HasFrameChanged={has_frame_changed}")
    return bool(user32.SetWindowPos(hwnd, hwnd_insert_after, x, y, cx, cy, flags))

class WindowManager(QObject):
    visibility_changed = Signal(bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.hwnd = wintypes.HWND(0)
        self.last_foreground_hwnd = wintypes.HWND(0)
        self.is_visible = False
        self._is_closing = False
        self.width_setting = 35
        self.panel_width = 380
        self.current_band = ZBID_DESKTOP
        self._panel_active_event = None
        self._shutdown_event = None
        self._match_mode_event = None
        self._sec_attr = None
        self._ui_pid = 0
        self._init_panel_event()

        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self._perform_physical_hide)

        # Initialize screen dimensions
        self.screen_w, self.screen_h = self._get_screen_dimensions()

        # Connect or launch Flutter Desktop UI
        self.ensure_flutter_ui()

        # Listen for screen resolution changes to re-dock geometry
        screen = QGuiApplication.primaryScreen()
        if screen:
            screen.geometryChanged.connect(lambda _: self.update_geometry(self.width_setting))

        # Lifecycle and compatibility management for games (FSO, Borderless, Anti-Minimize, DXGI Hook)
        self.game_compat = GameCompatService(self)
        self.game_compat.install_lifecycle_hooks(
            target_hwnd_getter=lambda: (self.last_foreground_hwnd.value or 0) if self.last_foreground_hwnd else 0,
            is_active_getter=lambda: self.is_visible,
            screen_dimensions_getter=lambda: (self.screen_w, self.screen_h)
        )

    def _get_window_process_id(self, hwnd) -> int:
        """Returns the owning process id of a window handle."""
        try:
            pid = wintypes.DWORD()
            user32.GetWindowThreadProcessId(wintypes.HWND(hwnd), ctypes.byref(pid))
            return int(pid.value)
        except Exception:
            return 0

    def _is_window_responsive(self, hwnd) -> bool:
        """Returns False when the UI window stopped pumping messages (hung renderer)."""
        try:
            result = ctypes.c_size_t()
            res = user32.SendMessageTimeoutW(
                wintypes.HWND(hwnd), 0x0000, 0, 0, SMTO_ABORTIFHUNG, 300, ctypes.byref(result)
            )
            return bool(res)
        except Exception:
            return False

    def _terminate_process(self, pid: int):
        """Force-terminates a UI process that no longer responds to WM_CLOSE."""
        if not pid:
            return
        try:
            handle = kernel32.OpenProcess(PROCESS_TERMINATE, False, int(pid))
            if handle:
                kernel32.TerminateProcess(handle, 1)
                kernel32.CloseHandle(handle)
                logger.info(f"[SEAMLESS] Terminated unresponsive Flutter UI process PID={pid}")
        except Exception as e:
            logger.warning(f"[SEAMLESS] Could not terminate UI process PID={pid}: {e}")

    def _close_duplicate_ui_windows(self, keep_hwnd):
        """Closes orphaned Flutter UI windows left behind by a previous host process."""
        try:
            keep = int(keep_hwnd or 0)
            handles = []
            hwnd = user32.FindWindowExW(None, None, "FLUTTER_RUNNER_WIN32_WINDOW", None)
            while hwnd:
                handles.append(hwnd)
                hwnd = user32.FindWindowExW(None, wintypes.HWND(hwnd), "FLUTTER_RUNNER_WIN32_WINDOW", None)

            for h in handles:
                if int(h) == keep:
                    continue
                pid = self._get_window_process_id(h)
                logger.info(f"[SEAMLESS] Closing orphan Flutter UI HWND={h} PID={pid}")
                self._terminate_process(pid)
        except Exception as e:
            logger.warning(f"[SEAMLESS] Error closing duplicate UI windows: {e}")

    def _find_flutter_ui_exe(self) -> Optional[str]:
        """Locates the windows_handheld_ui.exe executable for the Flutter Desktop runtime."""
        # 1. PyInstaller frozen environment or alongside executable
        if getattr(sys, "frozen", False):
            exe_dir = Path(sys.executable).resolve().parent
            for rel in ("ui/windows_handheld_ui.exe", "_internal/ui/windows_handheld_ui.exe", "windows_handheld_ui.exe"):
                p = exe_dir / rel
                if p.is_file():
                    return str(p)

        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            p = Path(meipass) / "ui" / "windows_handheld_ui.exe"
            if p.is_file():
                return str(p)

        # 2. Development workspace build (preferred when running from source so the
        # freshly compiled UI is used instead of the previously installed one)
        backend_dir = Path(__file__).resolve().parent.parent.parent
        repo_root = backend_dir.parent
        dev_candidates = [
            repo_root / "frontend" / "build" / "windows" / "x64" / "runner" / "Release" / "windows_handheld_ui.exe",
            repo_root / "frontend" / "build" / "windows" / "x64" / "runner" / "Debug" / "windows_handheld_ui.exe",
            repo_root / "dist" / "windows_handheld_tool" / "ui" / "windows_handheld_ui.exe",
            Path.cwd() / "frontend" / "build" / "windows" / "x64" / "runner" / "Release" / "windows_handheld_ui.exe",
            Path.cwd() / "frontend" / "build" / "windows" / "x64" / "runner" / "Debug" / "windows_handheld_ui.exe",
            Path.cwd() / "ui" / "windows_handheld_ui.exe",
        ]
        if not getattr(sys, "frozen", False):
            for cand in dev_candidates:
                if cand.is_file():
                    return str(cand.resolve())

        # 3. Installed secure directory
        prog_files = os.environ.get("ProgramFiles", "C:\\Program Files")
        p = Path(prog_files) / "WindowsHandheldTools" / "ui" / "windows_handheld_ui.exe"
        if p.is_file():
            return str(p)

        for cand in dev_candidates:
            if cand.is_file():
                return str(cand.resolve())

        return None

    def ensure_flutter_ui(self) -> bool:
        """Ensures the Flutter Desktop UI process is running and binds to its native HWND."""
        if self.hwnd and self.hwnd.value and user32.IsWindow(self.hwnd):
            return True

        hwnd = user32.FindWindowW("FLUTTER_RUNNER_WIN32_WINDOW", "WindowsHandheldOverlay")
        if not hwnd:
            hwnd = user32.FindWindowW("FLUTTER_RUNNER_WIN32_WINDOW", None)

        if hwnd and not self._is_window_responsive(hwnd):
            hung_pid = self._get_window_process_id(hwnd)
            logger.warning(f"[SEAMLESS] Existing Flutter UI HWND={hwnd} is hung (PID={hung_pid}); restarting it")
            self._terminate_process(hung_pid)
            hwnd = 0

        if hwnd:
            self.hwnd = wintypes.HWND(hwnd)
            self._ui_pid = self._get_window_process_id(hwnd)
            logger.info(f"[SEAMLESS] Attached to existing Flutter UI window: HWND={self.hwnd.value}, PID={self._ui_pid}")
            self._close_duplicate_ui_windows(hwnd)
            self._init_win32_attributes()
            self._set_click_through(True)
            self.enforce_no_activate_children()
            self.update_geometry(self.width_setting)
            return True

        exe_path = self._find_flutter_ui_exe()
        if not exe_path:
            logger.warning("[SEAMLESS] windows_handheld_ui.exe not found to spawn.")
            return False

        logger.info(f"[SEAMLESS] Spawning Flutter Desktop UI from: {exe_path}")
        try:
            exe_dir = str(Path(exe_path).parent)
            res = ctypes.windll.shell32.ShellExecuteW(None, "open", exe_path, None, exe_dir, 1)
            if res <= 32:
                logger.error(f"[SEAMLESS] ShellExecuteW failed with error code: {res}")
                return False
        except Exception as e:
            logger.error(f"[SEAMLESS] Exception launching Flutter UI: {e}")
            return False

        # Non-blocking quick poll (up to 300ms) to attach immediately if window appears
        for _ in range(6):
            time.sleep(0.05)
            hwnd = user32.FindWindowW("FLUTTER_RUNNER_WIN32_WINDOW", "WindowsHandheldOverlay")
            if not hwnd:
                hwnd = user32.FindWindowW("FLUTTER_RUNNER_WIN32_WINDOW", None)
            if hwnd:
                self.hwnd = wintypes.HWND(hwnd)
                self._ui_pid = self._get_window_process_id(hwnd)
                logger.info(f"[SEAMLESS] Successfully bound Flutter UI window: HWND={self.hwnd.value}, PID={self._ui_pid}")
                self._close_duplicate_ui_windows(hwnd)
                self._init_win32_attributes()
                self._set_click_through(True)
                self.enforce_no_activate_children()
                self.update_geometry(self.width_setting)
                return True

        logger.info("[SEAMLESS] Flutter UI spawned; binding will finalize on WebSocket handshake.")
        return False

    def _init_panel_event(self):
        """Initializes global Named Events HandheldTool_PanelActive and HandheldTool_Shutdown [SEAMLESS-1.10]."""
        try:
            p_sd = ctypes.c_void_p()
            p_sa = None
            if advapi32.ConvertStringSecurityDescriptorToSecurityDescriptorW("D:(A;;GA;;;WD)", 1, ctypes.byref(p_sd), None):
                self._sec_attr = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), p_sd.value, False)
                p_sa = ctypes.byref(self._sec_attr)

            self._panel_active_event = kernel32.CreateEventW(p_sa, True, False, "Global\\HandheldTool_PanelActive")
            if not self._panel_active_event:
                err = kernel32.GetLastError()
                logger.warning(f"[SEAMLESS-1.10] CreateEventW Global\\HandheldTool_PanelActive failed (Err={err}), trying local...")
                self._panel_active_event = kernel32.CreateEventW(p_sa, True, False, "HandheldTool_PanelActive")

            if self._panel_active_event:
                logger.info(f"[SEAMLESS-1.10] Named Event HandheldTool_PanelActive initialized (Handle={self._panel_active_event})")
            else:
                logger.error(f"[SEAMLESS-1.10] Could not create Named Event HandheldTool_PanelActive (Err={kernel32.GetLastError()})")

            self._shutdown_event = kernel32.CreateEventW(p_sa, True, False, "Global\\HandheldTool_Shutdown")
            if not self._shutdown_event:
                err = kernel32.GetLastError()
                logger.warning(f"[SEAMLESS-1.10] CreateEventW Global\\HandheldTool_Shutdown failed (Err={err}), trying local...")
                self._shutdown_event = kernel32.CreateEventW(p_sa, True, False, "HandheldTool_Shutdown")

            if self._shutdown_event:
                logger.info(f"[SEAMLESS-1.10] Named Event HandheldTool_Shutdown initialized (Handle={self._shutdown_event})")
            else:
                logger.error(f"[SEAMLESS-1.10] Could not create Named Event HandheldTool_Shutdown (Err={kernel32.GetLastError()})")

            self._init_match_display_mode_event(p_sa)
        except Exception as e:
            logger.error(f"[SEAMLESS-1.10] Error initializing Named Events: {e}")

    def _init_match_display_mode_event(self, p_sa):
        """Creates Named Event to allow dxgi_hook to match display mode to buffer resolution."""
        if not bool(ConfigManager().get("dxgi_hook", "match_display_mode", default=True)):
            return
        try:
            self._match_mode_event = kernel32.CreateEventW(p_sa, True, True, "Global\\HandheldTool_MatchDisplayMode")
            if not self._match_mode_event:
                self._match_mode_event = kernel32.CreateEventW(p_sa, True, True, "HandheldTool_MatchDisplayMode")
            if self._match_mode_event:
                logger.info("[SEAMLESS-1.13] Match display mode enabled (match_display_mode=True)")
            else:
                logger.error(f"[SEAMLESS-1.13] Could not create Named Event HandheldTool_MatchDisplayMode (Err={kernel32.GetLastError()})")
        except Exception as e:
            logger.error(f"[SEAMLESS-1.13] Error creating MatchDisplayMode Named Event: {e}")

    def _init_win32_attributes(self):
        if not self.hwnd or not self.hwnd.value:
            return

        if pfnDwmIsCompositionEnabled:
            try:
                enabled = wintypes.BOOL()
                pfnDwmIsCompositionEnabled(ctypes.byref(enabled))
                logger.info(f"[SEAMLESS-1.3] DWM Composition Anchor: Enabled={bool(enabled.value)} (Composed Flip Active)")
            except Exception as e:
                logger.warning(f"[SEAMLESS-1.3] Error checking DwmIsCompositionEnabled: {e}")

        try:
            current_style = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
            new_style = (
                current_style
                | WS_EX_NOACTIVATE
                | WS_EX_TOOLWINDOW
                | WS_EX_TOPMOST
                | WS_EX_TRANSPARENT
            )
            user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)
            logger.info(f"[SEAMLESS-1.4] Init Extended Styles: HWND={self.hwnd.value}, Old={hex(current_style)}, New={hex(new_style)}")
        except Exception as e:
            logger.warning(f"[SEAMLESS-1.4] Error setting ExStyle: {e}")

        # The overlay stays in the default desktop band. Flutter's hosted view
        # disappears when the window is moved to ZBID_UIACCESS, so the overlay
        # relies on WS_EX_TOPMOST plus the borderless DXGI hook instead.
        self.current_band = ZBID_DESKTOP

    def _get_window_title(self, hwnd: wintypes.HWND) -> str:
        """Retrieves window title string."""
        if not hwnd or not hwnd.value:
            return ""
        buf = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(hwnd, buf, 512)
        return buf.value

    def preserve_foreground_window(self):
        """Caches foreground window handle before opening overlay."""
        try:
            fg_hwnd = user32.GetForegroundWindow()
            if fg_hwnd and (not self.hwnd or fg_hwnd != self.hwnd.value):
                pid = wintypes.DWORD()
                tid = user32.GetWindowThreadProcessId(fg_hwnd, ctypes.byref(pid))
                if pid.value != ctypes.windll.kernel32.GetCurrentProcessId():
                    exe_path = self.game_compat.get_process_image_path(pid.value)
                    if not self.game_compat.is_game_process(exe_path, fg_hwnd):
                        return
                    self.last_foreground_hwnd = wintypes.HWND(fg_hwnd)
                    game_title = self._get_window_title(self.last_foreground_hwnd)
                    logger.info(f"[SEAMLESS-1.6] Preserve Foreground Window: HWND={self.last_foreground_hwnd.value}, PID={pid.value}, TID={tid}, Title='{game_title}'")
        except Exception as e:
            logger.debug(f"[SEAMLESS-1.6] Error in preserve_foreground_window: {e}")

    def restore_foreground_window(self):
        """Restores focus immediately to cached game window."""
        try:
            if self.last_foreground_hwnd and self.last_foreground_hwnd.value:
                self.game_compat.restore_if_minimized(self.last_foreground_hwnd.value)
                game_title = self._get_window_title(self.last_foreground_hwnd)
                target_pid = wintypes.DWORD()
                user32.GetWindowThreadProcessId(self.last_foreground_hwnd, ctypes.byref(target_pid))

                if target_pid.value:
                    user32.AllowSetForegroundWindow(target_pid.value)
                else:
                    user32.AllowSetForegroundWindow(ASFW_ANY)

                # Simulate ALT key event to break foreground lock
                user32.keybd_event(0x12, 0, 0, 0)      # VK_MENU (ALT) DOWN
                res = bool(user32.SetForegroundWindow(self.last_foreground_hwnd))
                user32.keybd_event(0x12, 0, 0x0002, 0) # VK_MENU (ALT) UP (KEYEVENTF_KEYUP = 2)

                last_err = ctypes.get_last_error()
                logger.info(f"[SEAMLESS-1.6] Restore Foreground Window: HWND={self.last_foreground_hwnd.value}, Title='{game_title}', Result={res}, LastError={last_err}")
        except Exception as e:
            logger.debug(f"[SEAMLESS-1.6] Error in restore_foreground_window: {e}")

    def enforce_no_activate_children(self):
        """Enforces WS_EX_NOACTIVATE style on child windows."""
        if not self.hwnd or not self.hwnd.value:
            return
        try:
            child_count = 0
            def _enum_cb(child_hwnd, lparam):
                nonlocal child_count
                try:
                    child_count += 1
                    st = user32.GetWindowLongW(child_hwnd, GWL_EXSTYLE)
                    if not (st & WS_EX_NOACTIVATE):
                        user32.SetWindowLongW(child_hwnd, GWL_EXSTYLE, st | WS_EX_NOACTIVATE)
                except Exception:
                    pass
                return True

            user32.EnumChildWindows(self.hwnd, WNDENUMPROC(_enum_cb), 0)
            logger.info(f"[SEAMLESS-1.6] Enforce WS_EX_NOACTIVATE: Enforced on {child_count} child windows")
        except Exception as e:
            logger.debug(f"[SEAMLESS-1.6] Error in enforce_no_activate_children: {e}")

    def _set_click_through(self, click_through: bool):
        """Toggles hardware click-through using WS_EX_TRANSPARENT flag."""
        if not self.hwnd or not self.hwnd.value:
            return
        try:
            cur_style = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
            base_flags = WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST

            def _apply_style(h, is_transparent):
                try:
                    s = user32.GetWindowLongW(h, GWL_EXSTYLE)
                    ns = (s | WS_EX_TRANSPARENT) if is_transparent else (s & ~WS_EX_TRANSPARENT)
                    if ns != s:
                        user32.SetWindowLongW(h, GWL_EXSTYLE, ns)
                except Exception:
                    pass

            if click_through:
                new_style = (cur_style | base_flags) | WS_EX_TRANSPARENT
            else:
                new_style = (cur_style | base_flags) & ~WS_EX_TRANSPARENT

            if new_style != cur_style:
                user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)

            child_synced = 0
            def _child_cb(child_h, _):
                nonlocal child_synced
                child_synced += 1
                _apply_style(child_h, click_through)
                return True
            user32.EnumChildWindows(self.hwnd, WNDENUMPROC(_child_cb), 0)

            logger.info(f"[SEAMLESS-1.4] Click-Through Toggle: Requested={click_through}, HWND={self.hwnd.value}, Old={hex(cur_style)}, New={hex(new_style)}, ChildrenSynced={child_synced}")

            if not click_through and self.current_band < ZBID_UIACCESS:
                safe_set_window_pos(
                    self.hwnd,
                    HWND_TOPMOST,
                    0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
                )
        except Exception as e:
            logger.warning(f"[SEAMLESS-1.4] Error toggling click-through ({click_through}): {e}")

    def _get_screen_dimensions(self) -> tuple[int, int]:
        """Resolves active monitor physical scan resolution in physical pixels."""
        try:
            target_hwnd = user32.GetForegroundWindow() or (self.hwnd.value if self.hwnd else 0)
            if target_hwnd:
                h_mon = user32.MonitorFromWindow(wintypes.HWND(target_hwnd), MONITOR_DEFAULTTONEAREST)
                if h_mon:
                    mi = MONITORINFO()
                    mi.cbSize = ctypes.sizeof(MONITORINFO)
                    if user32.GetMonitorInfoW(h_mon, ctypes.byref(mi)):
                        mon_w = mi.rcMonitor.right - mi.rcMonitor.left
                        mon_h = mi.rcMonitor.bottom - mi.rcMonitor.top
                        if mon_w >= 640 and mon_h >= 480:
                            logger.info(f"[WINDOW-GEOMETRY] Screen Dimensions Query: Result={mon_w}x{mon_h}, Source='MonitorFromWindow'")
                            return mon_w, mon_h
        except Exception as e:
            logger.debug(f"[WINDOW-GEOMETRY] MonitorFromWindow query error: {e}")

        sw = user32.GetSystemMetrics(0)
        sh = user32.GetSystemMetrics(1)
        if sw >= 640 and sh >= 480:
            logger.info(f"[WINDOW-GEOMETRY] Screen Dimensions Query: Result={sw}x{sh}, Source='GetSystemMetrics'")
            return sw, sh

        screen = QGuiApplication.primaryScreen()
        if screen:
            geo = screen.geometry()
            dpr = float(screen.devicePixelRatio() or 1.0)
            pw = int(round(geo.width() * dpr))
            ph = int(round(geo.height() * dpr))
            logger.info(f"[WINDOW-GEOMETRY] Screen Dimensions Query: Result={pw}x{ph}, Source='primaryScreen * DPR'")
            return pw, ph

        return 1920, 1080

    @Slot(int)
    def update_geometry(self, width: int):
        self.width_setting = width
        screen_w, screen_h = self._get_screen_dimensions()
        self.screen_w = screen_w
        self.screen_h = screen_h

        if width <= 100:
            actual_width = int(round(screen_w * (width / 100.0)))
        else:
            actual_width = int(width)

        self.panel_width = max(240, min(screen_w, actual_width))
        target_x = max(0, screen_w - self.panel_width)
        target_y = 0
        target_w = self.panel_width
        target_h = screen_h

        if not self.hwnd or not self.hwnd.value:
            return

        cur_rect = wintypes.RECT()
        user32.GetWindowRect(self.hwnd, ctypes.byref(cur_rect))
        cur_w = cur_rect.right - cur_rect.left
        cur_h = cur_rect.bottom - cur_rect.top
        cur_x = cur_rect.left
        cur_y = cur_rect.top

        logger.info(
            f"[WINDOW-GEOMETRY] Side Dock Viewport Check: "
            f"Cur=({cur_x},{cur_y},{cur_w}x{cur_h}), "
            f"Target=({target_x},{target_y},{target_w}x{target_h}), "
            f"Screen={screen_w}x{screen_h}, WidthSetting={width}%"
        )

        if (
            abs(cur_w - target_w) > 2
            or abs(cur_h - target_h) > 2
            or abs(cur_x - target_x) > 2
            or cur_y != target_y
        ):
            safe_set_window_pos(
                self.hwnd,
                HWND_TOPMOST if self.current_band < ZBID_UIACCESS else wintypes.HWND(0),
                target_x, target_y, target_w, target_h,
                SWP_NOACTIVATE | (0 if self.current_band < ZBID_UIACCESS else SWP_NOZORDER)
            )

    @Slot()
    def bring_to_front(self):
        """Brings overlay window to top of Z-Order if not in privileged band."""
        if not self.is_visible or self.current_band >= ZBID_UIACCESS or not self.hwnd or not self.hwnd.value:
            return
        safe_set_window_pos(
            self.hwnd,
            HWND_TOPMOST,
            0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
        )

    @Slot()
    def show(self):
        self._hide_timer.stop()
        self._is_closing = False
        self.is_visible = True

        logger.info("[SEAMLESS] Show overlay requested")
        self.ensure_flutter_ui()
        self.preserve_foreground_window()
        if self.last_foreground_hwnd and self.last_foreground_hwnd.value:
            self.game_compat.restore_if_minimized(self.last_foreground_hwnd.value)
        self.enforce_no_activate_children()

        self.update_geometry(self.width_setting)
        self._set_click_through(False)
        if self.hwnd and self.hwnd.value:
            user32.ShowWindow(self.hwnd, SW_SHOWNOACTIVATE)
            logger.info(f"[SEAMLESS-1.4] ShowWindow(SW_SHOWNOACTIVATE): HWND={self.hwnd.value}")
        try:
            user32.ClipCursor(None)
        except Exception:
            pass

        if self.last_foreground_hwnd and self.last_foreground_hwnd.value:
            self.game_compat.restore_if_minimized(self.last_foreground_hwnd.value)

        if self.current_band < ZBID_UIACCESS and self.hwnd and self.hwnd.value:
            safe_set_window_pos(
                self.hwnd,
                HWND_TOPMOST,
                0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
            )

        cur_fg = user32.GetForegroundWindow()
        if self.hwnd and cur_fg == self.hwnd.value:
            logger.info(f"[SEAMLESS-1.6] Overlay stolen foreground detected (HWND={cur_fg}), restoring to game...")
            self.restore_foreground_window()

        if self._panel_active_event:
            kernel32.SetEvent(self._panel_active_event)
            logger.info("[SEAMLESS-1.10] SetEvent(HandheldTool_PanelActive)")

        self.visibility_changed.emit(True)

    def _perform_physical_hide(self):
        self._hide_timer.stop()
        self._is_closing = False
        was_visible = self.is_visible
        self.is_visible = False

        logger.info("[SEAMLESS] Physical hide overlay requested")
        self._set_click_through(True)

        if self.hwnd and self.hwnd.value:
            user32.ShowWindow(self.hwnd, SW_HIDE)
            logger.info(f"[SEAMLESS-1.4] ShowWindow(SW_HIDE): HWND={self.hwnd.value}")

        if self._panel_active_event:
            kernel32.ResetEvent(self._panel_active_event)
            logger.info("[SEAMLESS-1.10] ResetEvent(HandheldTool_PanelActive)")

        self.restore_foreground_window()

        if was_visible:
            self.visibility_changed.emit(False)

    @Slot()
    def request_animated_hide(self):
        """Closes the overlay cleanly."""
        self._perform_physical_hide()

    @Slot()
    def hide(self):
        self._perform_physical_hide()

    @Slot()
    def toggle(self):
        logger.info(f"[SEAMLESS] Toggle overlay requested: is_visible={self.is_visible}")
        if self.is_visible:
            self.hide()
        else:
            self.show()

    def cleanup(self):
        """Cleans up system events and sends WM_CLOSE to Flutter desktop window."""
        if self._shutdown_event:
            try:
                kernel32.SetEvent(self._shutdown_event)
                logger.info("[SEAMLESS-1.10] SetEvent(HandheldTool_Shutdown)")
            except Exception as e:
                logger.warning(f"[SEAMLESS-1.10] Error in SetEvent HandheldTool_Shutdown: {e}")

        if self.hwnd and self.hwnd.value:
            try:
                WM_CLOSE = 0x0010
                user32.PostMessageW(self.hwnd, WM_CLOSE, 0, 0)
                logger.info(f"[SEAMLESS] Sent WM_CLOSE to Flutter UI HWND={self.hwnd.value}")

                # The UI is a separate process. A message posted from a different
                # integrity level can be filtered by UIPI, so make sure the process
                # really exits instead of leaving an invisible overlay behind.
                time.sleep(0.8)
                if user32.IsWindow(self.hwnd):
                    pid = self._ui_pid or self._get_window_process_id(self.hwnd)
                    logger.warning(f"[SEAMLESS] Flutter UI still alive after WM_CLOSE (PID={pid}); terminating")
                    self._terminate_process(pid)
                self._close_duplicate_ui_windows(0)
            except Exception as e:
                logger.warning(f"[SEAMLESS] Error closing Flutter UI: {e}")

        if self._panel_active_event:
            try:
                kernel32.ResetEvent(self._panel_active_event)
                kernel32.CloseHandle(self._panel_active_event)
                self._panel_active_event = None
            except Exception as e:
                logger.warning(f"[SEAMLESS-1.10] Error in CloseHandle HandheldTool_PanelActive: {e}")

        if self._shutdown_event:
            try:
                kernel32.CloseHandle(self._shutdown_event)
                self._shutdown_event = None
            except Exception as e:
                logger.warning(f"[SEAMLESS-1.10] Error in CloseHandle HandheldTool_Shutdown: {e}")

        if self._match_mode_event:
            try:
                kernel32.ResetEvent(self._match_mode_event)
                kernel32.CloseHandle(self._match_mode_event)
                self._match_mode_event = None
            except Exception as e:
                logger.warning(f"[SEAMLESS-1.13] Error in CloseHandle HandheldTool_MatchDisplayMode: {e}")
