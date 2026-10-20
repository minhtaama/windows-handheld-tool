import ctypes
from ctypes import wintypes
from PySide6.QtCore import QObject, Signal, Slot, QRect, QTimer
from PySide6.QtWidgets import QWidget
from PySide6.QtGui import QGuiApplication
from src.core.logger import setup_logger
from src.services.game_compat_service import GameCompatService

logger = setup_logger("WindowManager")

# Win32 Constants
GWL_EXSTYLE       = -20
GWL_STYLE         = -16
WS_EX_TOPMOST     = 0x00000008
WS_EX_TRANSPARENT = 0x00000020
WS_EX_TOOLWINDOW  = 0x00000080
WS_EX_LAYERED     = 0x00080000
WS_EX_NOACTIVATE  = 0x08000000

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

# Các định danh phân lớp Z-Order Band (ZBID) nội vi của Windows
ZBID_DEFAULT      = 0
ZBID_DESKTOP      = 1
ZBID_UIACCESS     = 2   # Phân lớp đặc quyền UIAccess (dùng cho On-Screen Keyboard, Accessibility Overlay)
ZBID_SYSTEM_TOOLS = 16  # Phân lớp công cụ hệ thống cấp cao (Windows 10/11)

user32 = ctypes.WinDLL("user32", use_last_error=True)

# Khai báo đầy đủ nguyên mẫu hàm 64-bit để tránh lỗi 1400 (ERROR_INVALID_WINDOW_HANDLE) do cắt xén con trỏ HWND
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

# Khai báo Win32 Monitor API
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

# Khai báo nguyên mẫu API nội vi quản lý Window Band
# Khai báo nguyên mẫu API nội vi quản lý Window Band
pfnSetWindowBand = getattr(user32, "SetWindowBand", None)
if pfnSetWindowBand:
    pfnSetWindowBand.argtypes = [wintypes.HWND, wintypes.HWND, wintypes.DWORD]
    pfnSetWindowBand.restype = wintypes.BOOL

pfnGetWindowBand = getattr(user32, "GetWindowBand", None)
if pfnGetWindowBand:
    pfnGetWindowBand.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    pfnGetWindowBand.restype = wintypes.BOOL

pfnCreateWindowInBand = getattr(user32, "CreateWindowInBand", None)
if pfnCreateWindowInBand:
    pfnCreateWindowInBand.argtypes = [
        wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD,
        ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
        wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID,
        wintypes.DWORD
    ]
    pfnCreateWindowInBand.restype = wintypes.HWND

# Khai báo Win32 DWM API kiểm tra trạng thái Composed Flip
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
    """Wrapper gọi SetWindowPos có kèm kiểm tra và log chuẩn [SEAMLESS-1.5]"""
    has_frame_changed = bool(flags & SWP_FRAMECHANGED)
    flag_str = _decode_swp_flags(flags)
    logger.info(f"[SEAMLESS-1.5] SetWindowPos: HWND={hwnd}, InsertAfter={hwnd_insert_after}, Rect=({x},{y},{cx},{cy}), Flags={hex(flags)} [{flag_str}], HasFrameChanged={has_frame_changed}")
    return bool(user32.SetWindowPos(hwnd, hwnd_insert_after, x, y, cx, cy, flags))

class WindowManager(QObject):
    visibility_changed = Signal(bool)

    def __init__(self, widget: QWidget):
        super().__init__()
        self.widget = widget
        self.hwnd = wintypes.HWND(0)
        self.last_foreground_hwnd = wintypes.HWND(0)
        self.is_visible = False
        self._is_closing = False
        self.width_setting = 35
        self.panel_width = 380
        self.current_band = ZBID_DESKTOP
        self._panel_active_event = None
        self._sec_attr = None
        self._init_panel_event()

        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self._perform_physical_hide)

        # Khởi tạo Side Dock Viewport Geometry cố định tại mép phải (screen_w - panel_w, 0, panel_w, screen_h)
        self.screen_w, self.screen_h = self._get_screen_dimensions()
        dpr = float(self.widget.devicePixelRatio() or 1.0)
        self.panel_logical_w = max(240, int(round((self.screen_w / dpr) * (self.width_setting / 100.0))))
        self.panel_logical_h = max(1, int(round(self.screen_h / dpr)))
        self.panel_logical_x = max(0, int(round(self.screen_w / dpr)) - self.panel_logical_w)

        logger.info(
            f"[WINDOW-GEOMETRY] Khởi tạo Side Dock Viewport Geometry: "
            f"Screen={self.screen_w}x{self.screen_h}, DPR={dpr}, "
            f"Geometry=({self.panel_logical_x}, 0, {self.panel_logical_w}x{self.panel_logical_h})"
        )
        self.widget.setGeometry(self.panel_logical_x, 0, self.panel_logical_w, self.panel_logical_h)

        # Cấp phát native HWND trước khi hiển thị để gán cứng cờ và phân lớp
        self.hwnd = wintypes.HWND(self.widget.winId())
        self._init_win32_attributes()

        self.widget.show()
        # Mặc định khi khởi động ở trạng thái đóng (Click-Through xuyên thấu 100%)
        self._set_click_through(True)
        self.enforce_no_activate_children()

        # [SEAMLESS-COMPAT] Dịch vụ quản trị tương thích Game (FSO, Borderless, Anti-Minimize, DXGI Hook Injector)
        self.game_compat = GameCompatService(self)
        self.game_compat.install_lifecycle_hooks(
            target_hwnd_getter=lambda: self.last_foreground_hwnd.value if self.last_foreground_hwnd else 0,
            is_active_getter=lambda: self.is_visible,
            screen_dimensions_getter=lambda: (self.screen_w, self.screen_h)
        )

    def _init_panel_event(self):
        """Khởi tạo Named Event toàn cục HandheldTool_PanelActive để đồng bộ Gamepad Hook [SEAMLESS-1.10]"""
        try:
            p_sd = ctypes.c_void_p()
            p_sa = None
            if advapi32.ConvertStringSecurityDescriptorToSecurityDescriptorW("D:(A;;GA;;;WD)", 1, ctypes.byref(p_sd), None):
                self._sec_attr = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), p_sd.value, False)
                p_sa = ctypes.byref(self._sec_attr)

            self._panel_active_event = kernel32.CreateEventW(p_sa, True, False, "Global\\HandheldTool_PanelActive")
            if not self._panel_active_event:
                err = kernel32.GetLastError()
                logger.warning(f"[SEAMLESS-1.10] CreateEventW Global\\HandheldTool_PanelActive thất bại (Err={err}), thử session cục bộ...")
                self._panel_active_event = kernel32.CreateEventW(p_sa, True, False, "HandheldTool_PanelActive")

            if self._panel_active_event:
                logger.info(f"[SEAMLESS-1.10] Đã khởi tạo Named Event HandheldTool_PanelActive (Handle={self._panel_active_event})")
            else:
                logger.error(f"[SEAMLESS-1.10] Không thể tạo Named Event HandheldTool_PanelActive (Err={kernel32.GetLastError()})")
        except Exception as e:
            logger.error(f"[SEAMLESS-1.10] Lỗi khởi tạo Named Event: {e}")

    def _init_win32_attributes(self):
        # 1.3. Kiểm tra trạng thái DWM Composition
        if pfnDwmIsCompositionEnabled:
            try:
                enabled = wintypes.BOOL()
                pfnDwmIsCompositionEnabled(ctypes.byref(enabled))
                logger.info(f"[SEAMLESS-1.3] DWM Composition Anchor: Enabled={bool(enabled.value)} (Composed Flip Active)")
            except Exception as e:
                logger.warning(f"[SEAMLESS-1.3] Lỗi kiểm tra DwmIsCompositionEnabled: {e}")

        # 1.4. Thiết lập Extended Window Styles ban đầu
        try:
            current_style = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
            new_style = (
                current_style
                | WS_EX_NOACTIVATE
                | WS_EX_TOOLWINDOW
                | WS_EX_TOPMOST
                | WS_EX_LAYERED
                | WS_EX_TRANSPARENT
            )
            user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)
            logger.info(f"[SEAMLESS-1.4] Init Extended Styles: HWND={self.hwnd}, Old={hex(current_style)}, New={hex(new_style)} (HasTransparent={bool(new_style & WS_EX_TRANSPARENT)}, HasNoActivate={bool(new_style & WS_EX_NOACTIVATE)})")
        except Exception as e:
            logger.warning(f"[SEAMLESS-1.4] Lỗi khi gán ExStyle: {e}")

        # 1.10. Thử đưa vào phân lớp hệ thống ZBID_UIACCESS = 2
        band_applied = False
        if pfnSetWindowBand:
            for target_band in (ZBID_UIACCESS, ZBID_SYSTEM_TOOLS):
                try:
                    res = pfnSetWindowBand(self.hwnd, 0, target_band)
                    err = ctypes.get_last_error()
                    logger.info(f"[SEAMLESS-1.10] SetWindowBand: TargetBand={target_band}, Result={res}, LastError={err}")
                    if res:
                        self.current_band = target_band
                        band_applied = True
                        break
                except Exception as e:
                    logger.debug(f"[SEAMLESS-1.10] Ngoại lệ SetWindowBand({target_band}): {e}")

        if not band_applied:
            err = ctypes.get_last_error()
            logger.info(f"[SEAMLESS-1.10] SetWindowBand bỏ qua (Mã lỗi {err}: Cần TokenUIAccess khi chạy từ Program Files đã ký số).")

        # Đọc lại phân lớp thực tế qua GetWindowBand
        if pfnGetWindowBand:
            try:
                b = wintypes.DWORD()
                if pfnGetWindowBand(self.hwnd, ctypes.byref(b)):
                    self.current_band = b.value
                    band_name = "ZBID_UIACCESS (Band 2)" if self.current_band == 2 else ("ZBID_SYSTEM_TOOLS (Band 16)" if self.current_band == 16 else f"ZBID_DESKTOP (Band {self.current_band})")
                    logger.info(f"[SEAMLESS-1.10] Phân lớp Z-Band thực tế của cửa sổ: {band_name}")
            except Exception as e:
                logger.debug(f"[SEAMLESS-1.10] Lỗi GetWindowBand: {e}")

    def _get_window_title(self, hwnd: wintypes.HWND) -> str:
        """Đọc tiêu đề cửa sổ Win32 để nhận diện Game"""
        if not hwnd or not hwnd.value:
            return ""
        buf = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(hwnd, buf, 512)
        return buf.value

    def preserve_foreground_window(self):
        """Lưu lại HWND của cửa sổ đang có tiêu điểm (Game) trước khi nhận click hoặc phím tắt"""
        try:
            fg_hwnd = user32.GetForegroundWindow()
            if fg_hwnd and fg_hwnd != self.hwnd.value:
                pid = wintypes.DWORD()
                tid = user32.GetWindowThreadProcessId(fg_hwnd, ctypes.byref(pid))
                if pid.value != ctypes.windll.kernel32.GetCurrentProcessId():
                    self.last_foreground_hwnd = wintypes.HWND(fg_hwnd)
                    game_title = self._get_window_title(self.last_foreground_hwnd)
                    logger.info(f"[SEAMLESS-1.6] Preserve Foreground Window (Game): HWND={self.last_foreground_hwnd.value}, PID={pid.value}, TID={tid}, Title='{game_title}'")
        except Exception as e:
            logger.debug(f"[SEAMLESS-1.6] Lỗi preserve_foreground_window: {e}")

    def restore_foreground_window(self):
        """Khôi phục lại tiêu điểm ngay lập tức cho Game nếu phát hiện bị cướp Focus"""
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

                # Giả lập nhấn/nhả phím ALT để gỡ bỏ triệt để Foreground Lock của Windows Kernel
                # Giúp Game nhận Focus tức thời 100%, triệt tiêu hoàn toàn lỗi phải Double Click mới nhận tín hiệu
                user32.keybd_event(0x12, 0, 0, 0)      # VK_MENU (ALT) DOWN
                res = bool(user32.SetForegroundWindow(self.last_foreground_hwnd))
                user32.keybd_event(0x12, 0, 0x0002, 0) # VK_MENU (ALT) UP (KEYEVENTF_KEYUP = 2)

                last_err = ctypes.get_last_error()
                logger.info(f"[SEAMLESS-1.6] Restore Foreground Window (Game): HWND={self.last_foreground_hwnd.value}, Title='{game_title}', Result={res}, LastError={last_err}")
        except Exception as e:
            logger.debug(f"[SEAMLESS-1.6] Lỗi restore_foreground_window: {e}")

    def enforce_no_activate_children(self):
        """Khóa cờ WS_EX_NOACTIVATE cho toàn bộ các cửa sổ con (Chromium DirectComposition HWNDs)"""
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
            logger.info(f"[SEAMLESS-1.6] Enforce WS_EX_NOACTIVATE: Đã quét và khóa cờ cho {child_count} cửa sổ con Chromium")
        except Exception as e:
            logger.debug(f"[SEAMLESS-1.6] Lỗi enforce_no_activate_children: {e}")

    def _set_click_through(self, click_through: bool):
        """
        Bật/tắt chế độ xuyên thấu chuột & bàn phím (Hardware Click-Through) bằng cờ WS_EX_TRANSPARENT.
        Cửa sổ luôn giữ nguyên vị trí trên màn hình. Duy trì trạng thái hiển thị ổn định không gửi SWP_FRAMECHANGED thừa.
        """
        try:
            cur_style = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
            base_flags = WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED

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
                user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)
            else:
                new_style = (cur_style | base_flags) & ~WS_EX_TRANSPARENT
                user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)

            # Đồng bộ đệ quy cho toàn bộ cửa sổ con
            child_synced = 0
            def _child_cb(child_h, _):
                nonlocal child_synced
                child_synced += 1
                _apply_style(child_h, click_through)
                return True
            user32.EnumChildWindows(self.hwnd, WNDENUMPROC(_child_cb), 0)

            logger.info(f"[SEAMLESS-1.4] Click-Through Toggle: Requested={click_through}, HWND={self.hwnd}, OldStyle={hex(cur_style)}, NewStyle={hex(new_style)}, ChildrenSynced={child_synced}")

            # Chỉ gọi SetWindowPos nếu cửa sổ chưa nằm trên Band 2 (ZBID_UIACCESS).
            # Khi đã ở Band 2, cửa sổ mặc định nằm trên toàn bộ ứng dụng Band 1 (kể cả Exclusive Fullscreen).
            # Gọi SetWindowPos trên Band 2 sẽ phát sự kiện hệ thống khiến DXGI đánh văng Game Exclusive Fullscreen!
            if not click_through and self.current_band < ZBID_UIACCESS:
                safe_set_window_pos(
                    self.hwnd,
                    HWND_TOPMOST,
                    0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
                )
        except Exception as e:
            logger.warning(f"[SEAMLESS-1.4] Lỗi khi chuyển trạng thái Click-Through ({click_through}): {e}")

    def _get_monitor_dpi_ratio(self, h_mon) -> float:
        """Đọc hệ số tỉ lệ DPI thực tế trực tiếp từ Monitor qua shcore.GetDpiForMonitor"""
        try:
            shcore = ctypes.windll.shcore
            dpi_x = wintypes.UINT(96)
            dpi_y = wintypes.UINT(96)
            # MDT_EFFECTIVE_DPI = 0
            if shcore.GetDpiForMonitor(h_mon, 0, ctypes.byref(dpi_x), ctypes.byref(dpi_y)) == 0 and dpi_x.value > 0:
                return float(dpi_x.value) / 96.0
        except Exception:
            pass
        return float(self.widget.devicePixelRatio() or 1.0)

    def _get_screen_dimensions(self) -> tuple[int, int]:
        """
        Xác định độ phân giải quét vật lý thực tế (Physical Pixels) của Monitor chứa cửa sổ hiện hành.
        Tuyệt đối không dùng QGuiApplication.primaryScreen().geometry() vì hàm đó trả về Logical Pixels (1280x720 thay vì 1920x1080 ở DPI 150%).
        """
        # 1. Thử lấy thông số Monitor vật lý bao chứa cửa sổ Game hoặc cửa sổ chính qua MonitorFromWindow
        try:
            target_hwnd = user32.GetForegroundWindow() or self.hwnd
            if target_hwnd:
                h_mon = user32.MonitorFromWindow(target_hwnd, MONITOR_DEFAULTTONEAREST)
                if h_mon:
                    mi = MONITORINFO()
                    mi.cbSize = ctypes.sizeof(MONITORINFO)
                    if user32.GetMonitorInfoW(h_mon, ctypes.byref(mi)):
                        mon_w = mi.rcMonitor.right - mi.rcMonitor.left
                        mon_h = mi.rcMonitor.bottom - mi.rcMonitor.top
                        if mon_w >= 640 and mon_h >= 480:
                            logger.info(f"[WINDOW-GEOMETRY] Screen Dimensions Query: Result={mon_w}x{mon_h}, Source='MonitorFromWindow (HWND={target_hwnd})'")
                            return mon_w, mon_h
        except Exception as e:
            logger.debug(f"[WINDOW-GEOMETRY] Lỗi MonitorFromWindow: {e}")

        # 2. Đọc độ phân giải quét vật lý tức thời qua SM_CXSCREEN, SM_CYSCREEN
        sw = user32.GetSystemMetrics(0)
        sh = user32.GetSystemMetrics(1)
        if sw >= 640 and sh >= 480:
            logger.info(f"[WINDOW-GEOMETRY] Screen Dimensions Query: Result={sw}x{sh}, Source='GetSystemMetrics (SM_CXSCREEN)'")
            return sw, sh

        # 3. Fallback qua màn hình chính của Qt (Nhân lại với devicePixelRatio để ra Physical Pixels)
        screen = QGuiApplication.primaryScreen()
        if screen:
            geo = screen.geometry()
            dpr = float(screen.devicePixelRatio() or 1.0)
            pw = int(round(geo.width() * dpr))
            ph = int(round(geo.height() * dpr))
            logger.info(f"[WINDOW-GEOMETRY] Screen Dimensions Query: Result={pw}x{ph}, Source='QGuiApplication.primaryScreen * DPR({dpr})'")
            return pw, ph

        logger.info("[WINDOW-GEOMETRY] Screen Dimensions Query: Result=1920x1080, Source='Default Fallback'")
        return 1920, 1080

    @Slot(int)
    def update_geometry(self, width: int):
        self.width_setting = width
        screen_w, screen_h = self._get_screen_dimensions()
        self.screen_w = screen_w
        self.screen_h = screen_h
        dpr = float(self.widget.devicePixelRatio() or 1.0)

        logical_screen_w = max(1, int(round(screen_w / dpr)))
        logical_screen_h = max(1, int(round(screen_h / dpr)))

        # Tính toán bề rộng panel theo tỉ lệ % hoặc pixel trực tiếp
        if width <= 100:
            actual_width = int(round(logical_screen_w * (width / 100.0)))
        else:
            actual_width = int(round(width / dpr))

        self.panel_width = max(240, min(logical_screen_w, actual_width))
        target_x = max(0, logical_screen_w - self.panel_width)
        target_y = 0
        target_w = self.panel_width
        target_h = logical_screen_h

        cur_geo = self.widget.geometry()
        logger.info(
            f"[WINDOW-GEOMETRY] Side Dock Viewport Check: "
            f"Cur=({cur_geo.x()},{cur_geo.y()},{cur_geo.width()}x{cur_geo.height()}), "
            f"Target=({target_x},{target_y},{target_w}x{target_h}), "
            f"Screen={screen_w}x{screen_h}, DPR={dpr}, WidthSetting={width}%"
        )

        if (
            abs(cur_geo.width() - target_w) > 2
            or abs(cur_geo.height() - target_h) > 2
            or abs(cur_geo.x() - target_x) > 2
            or cur_geo.y() != target_y
        ):
            self.widget.setGeometry(target_x, target_y, target_w, target_h)

    @Slot()
    def bring_to_front(self):
        """Giữ cửa sổ ở đỉnh Z-Order mà tuyệt đối không phát thông điệp thừa khi đã ở ZBID_UIACCESS (Band 2)"""
        if not self.is_visible or self.current_band >= ZBID_UIACCESS:
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

        logger.info("----------------------------------------------------------------")
        logger.info("[SEAMLESS] BẮT ĐẦU HIỂN THỊ OVERLAY (SHOW REQUEST)")
        self.preserve_foreground_window()
        if self.last_foreground_hwnd and self.last_foreground_hwnd.value:
            self.game_compat.restore_if_minimized(self.last_foreground_hwnd.value)
        self.enforce_no_activate_children()

        self.update_geometry(self.width_setting)
        # 1.4. Tắt chế độ xuyên thấu để Panel nhận thao tác chuột
        self._set_click_through(False)
        # Giải phóng giới hạn con trỏ (ClipCursor) để chuột di chuyển tự do không bị kẹt lệch tọa độ
        try:
            user32.ClipCursor(None)
        except Exception:
            pass
        if self.last_foreground_hwnd and self.last_foreground_hwnd.value:
            self.game_compat.restore_if_minimized(self.last_foreground_hwnd.value)

        # 1.5. Khi cửa sổ đã nằm ở ZBID_UIACCESS (Band 2) và đã gọi widget.show() từ lúc khởi tạo,
        # TUYỆT ĐỐI KHÔNG gọi lại SetWindowPos(..., SWP_SHOWWINDOW) vì cờ SWP_SHOWWINDOW phát sự kiện
        # EVENT_OBJECT_SHOW cấp hệ thống làm 4A Engine (Metro Exodus) tự thoát Exclusive Fullscreen!
        if self.current_band < ZBID_UIACCESS:
            safe_set_window_pos(
                self.hwnd,
                HWND_TOPMOST,
                0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW
            )

        # 1.6. Kiểm tra nếu ForegroundWindow bị lệch sang HWND của chúng ta thì lập tức trả lại cho Game
        cur_fg = user32.GetForegroundWindow()
        if cur_fg == self.hwnd.value:
            logger.info(f"[SEAMLESS-1.6] Phát hiện Foreground bị chiếm bởi Overlay HWND={cur_fg}, đang khôi phục lại cho Game...")
            self.restore_foreground_window()

        # 1.10. Kích hoạt Named Event để DXGI/XInput Hook trong Game triệt tiêu input gamepad
        if self._panel_active_event:
            kernel32.SetEvent(self._panel_active_event)
            logger.info("[SEAMLESS-1.10] SetEvent(HandheldTool_PanelActive): Bật chặn Gamepad Input ở Game Hook")

        self.visibility_changed.emit(True)
        logger.info(f"[SEAMLESS] HOÀN TẤT HIỂN THỊ (Click-Through=False, Band={self.current_band})")
        logger.info("----------------------------------------------------------------")

    def _perform_physical_hide(self):
        self._hide_timer.stop()
        self._is_closing = False
        self.is_visible = False

        logger.info("----------------------------------------------------------------")
        logger.info("[SEAMLESS] ĐÓNG OVERLAY VẬT LÝ (_perform_physical_hide)")
        # 1.4. Bật chế độ xuyên thấu 100% mà KHÔNG ẩn hay di dời cửa sổ
        self._set_click_through(True)

        # 1.10. Tắt Named Event để DXGI/XInput Hook khôi phục input gamepad cho Game
        if self._panel_active_event:
            kernel32.ResetEvent(self._panel_active_event)
            logger.info("[SEAMLESS-1.10] ResetEvent(HandheldTool_PanelActive): Mở lại Gamepad Input cho Game")

        # 1.6. Đảm bảo Focus được giữ nguyên ở Game
        self.restore_foreground_window()
        logger.info(f"[SEAMLESS] HOÀN TẤT ĐÓNG OVERLAY (Click-Through=True, Bảo toàn Focus & DWM Flip của Game)")
        logger.info("----------------------------------------------------------------")

    @Slot()
    def request_animated_hide(self):
        """Yêu cầu Flutter chạy hiệu ứng Fade-Out trước, sau đó mới dời cửa sổ vật lý ra khỏi màn hình"""
        if not self.is_visible or self._is_closing:
            return
        self._is_closing = True
        self.visibility_changed.emit(False)
        self._hide_timer.start(240)

    @Slot()
    def hide(self):
        self._perform_physical_hide()

    @Slot()
    def toggle(self):
        logger.info(f"[SEAMLESS] Nhận yêu cầu TOGGLE: is_visible={self.is_visible}, is_closing={self._is_closing}")
        if self.is_visible and not self._is_closing:
            self.request_animated_hide()
        else:
            self.show()


    def cleanup(self):
        """Dọn dẹp tài nguyên và giải phóng Named Event [SEAMLESS-1.10]"""
        if self._panel_active_event:
            try:
                kernel32.ResetEvent(self._panel_active_event)
                kernel32.CloseHandle(self._panel_active_event)
                logger.info("[SEAMLESS-1.10] Đã giải phóng handle Named Event HandheldTool_PanelActive")
                self._panel_active_event = None
            except Exception as e:
                logger.warning(f"[SEAMLESS-1.10] Lỗi CloseHandle Named Event: {e}")
