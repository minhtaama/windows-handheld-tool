import ctypes
from ctypes import wintypes
from PySide6.QtCore import QObject, Signal, Slot, QRect, QTimer
from PySide6.QtWidgets import QWidget
from PySide6.QtGui import QGuiApplication
from src.core.logger import setup_logger

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

        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self._perform_physical_hide)

        # Khởi tạo cửa sổ cố định 1 lần duy nhất ở tọa độ (0, 0, native_w, native_h)
        # Tuyệt đối không bao giờ gọi lại widget.hide() hay widget.show() để tránh Qt can thiệp HWND và làm mất Focus của Game
        self.native_w, self.native_h = self._get_screen_dimensions()
        self.widget.setGeometry(0, 0, self.native_w, self.native_h)

        # Ép Qt cấp phát native HWND trước khi hiển thị để gán cứng WS_EX_NOACTIVATE và ZBID_UIACCESS ngay từ đầu
        self.hwnd = wintypes.HWND(self.widget.winId())
        self._init_win32_attributes()

        self.widget.show()
        # Mặc định khi khởi động ở trạng thái đóng (Click-Through xuyên thấu 100%)
        self._set_click_through(True)
        self.enforce_no_activate_children()

    def _init_win32_attributes(self):
        # 1. Thiết lập Extended Window Styles: WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT
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
            logger.info(f"Đã gán cờ WS_EX_NOACTIVATE, WS_EX_LAYERED, WS_EX_TRANSPARENT cho HWND {self.hwnd}.")
        except Exception as e:
            logger.warning(f"Lỗi khi gán ExStyle: {e}")

        # 2. Thử đưa vào phân lớp hệ thống ZBID_UIACCESS = 2 (Đặc quyền UIAccess)
        band_applied = False
        if pfnSetWindowBand:
            for target_band in (ZBID_UIACCESS, ZBID_SYSTEM_TOOLS):
                try:
                    res = pfnSetWindowBand(self.hwnd, 0, target_band)
                    if res:
                        self.current_band = target_band
                        band_applied = True
                        logger.info(f"Đã gán thành công cửa sổ vào phân lớp Z-Band: {target_band}.")
                        break
                except Exception as e:
                    logger.debug(f"Thử gán Z-Band {target_band}: {e}")

        if not band_applied:
            err = ctypes.get_last_error()
            logger.info(f"SetWindowBand bỏ qua (Mã {err}: Cần TokenUIAccess khi chạy từ Program Files đã ký số).")

        # 3. Đọc lại phân lớp thực tế qua GetWindowBand
        if pfnGetWindowBand:
            try:
                b = wintypes.DWORD()
                if pfnGetWindowBand(self.hwnd, ctypes.byref(b)):
                    self.current_band = b.value
                    logger.info(f"Phân lớp Z-Band thực tế hiện tại của cửa sổ: {self.current_band}")
            except Exception as e:
                logger.debug(f"Lỗi GetWindowBand: {e}")

    def preserve_foreground_window(self):
        """Lưu lại HWND của cửa sổ đang có tiêu điểm (Game) trước khi nhận click hoặc phím tắt"""
        try:
            fg_hwnd = user32.GetForegroundWindow()
            if fg_hwnd and fg_hwnd != self.hwnd.value:
                pid = wintypes.DWORD()
                user32.GetWindowThreadProcessId(fg_hwnd, ctypes.byref(pid))
                if pid.value != ctypes.windll.kernel32.GetCurrentProcessId():
                    self.last_foreground_hwnd = wintypes.HWND(fg_hwnd)
        except Exception as e:
            logger.debug(f"Lỗi preserve_foreground_window: {e}")

    def restore_foreground_window(self):
        """Khôi phục lại tiêu điểm ngay lập tức cho Game nếu phát hiện bị cướp Focus"""
        try:
            if self.last_foreground_hwnd and self.last_foreground_hwnd.value:
                user32.SetForegroundWindow(self.last_foreground_hwnd)
        except Exception as e:
            logger.debug(f"Lỗi restore_foreground_window: {e}")

    def enforce_no_activate_children(self):
        """Khóa cờ WS_EX_NOACTIVATE cho toàn bộ các cửa sổ con (Chromium DirectComposition HWNDs)"""
        try:
            def _enum_cb(child_hwnd, lparam):
                try:
                    st = user32.GetWindowLongW(child_hwnd, GWL_EXSTYLE)
                    if not (st & WS_EX_NOACTIVATE):
                        user32.SetWindowLongW(child_hwnd, GWL_EXSTYLE, st | WS_EX_NOACTIVATE)
                except Exception:
                    pass
                return True

            user32.EnumChildWindows(self.hwnd, WNDENUMPROC(_enum_cb), 0)
        except Exception as e:
            logger.debug(f"Lỗi enforce_no_activate_children: {e}")

    def _set_click_through(self, click_through: bool):
        """
        Bật/tắt chế độ xuyên thấu chuột & bàn phím (Hardware Click-Through) bằng cờ WS_EX_TRANSPARENT.
        Cửa sổ luôn giữ nguyên vị trí trên màn hình. Tuyệt đối không gửi SWP_FRAMECHANGED để tránh kích hoạt Fullscreen Occlusion của DXGI.
        """
        try:
            current_style = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
            base_flags = WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED
            if click_through:
                new_style = (current_style | base_flags) | WS_EX_TRANSPARENT
                user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)
            else:
                new_style = (current_style | base_flags) & ~WS_EX_TRANSPARENT
                user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)
                user32.SetWindowPos(
                    self.hwnd,
                    HWND_TOPMOST,
                    0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
                )
        except Exception as e:
            logger.warning(f"Lỗi khi chuyển trạng thái Click-Through ({click_through}): {e}")

    def _get_screen_dimensions(self) -> tuple[int, int]:
        """
        Xác định độ phân giải quét vật lý thực tế của Monitor chứa cửa sổ hiện hành.
        Đảm bảo không bao giờ bị bóp về 720p khi Game đang tạm thời ép màn hình xuống 720p.
        """
        w, h = 1920, 1080
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
                            w, h = mon_w, mon_h
        except Exception as e:
            logger.debug(f"Không thể lấy kích thước từ MonitorFromWindow: {e}")

        # 2. Đọc độ phân giải quét vật lý tức thời qua SM_CXSCREEN, SM_CYSCREEN
        if w == 1920 and h == 1080:
            sw = user32.GetSystemMetrics(0)
            sh = user32.GetSystemMetrics(1)
            if sw > 0 and sh > 0:
                w, h = sw, sh

        # 3. Fallback qua màn hình chính của Qt
        if w == 1920 and h == 1080:
            screen = QGuiApplication.primaryScreen()
            if screen:
                geo = screen.geometry()
                w, h = geo.width(), geo.height()

        # Đảm bảo không bao giờ co lại nhỏ hơn kích thước Desktop gốc đã xác định lúc khởi tạo
        if hasattr(self, "native_w") and hasattr(self, "native_h"):
            self.native_w = max(self.native_w, w)
            self.native_h = max(self.native_h, h)
            return self.native_w, self.native_h

        return w, h

    @Slot(int)
    def update_geometry(self, width: int):
        self.width_setting = width
        screen_w, screen_h = self._get_screen_dimensions()

        # Nếu giá trị truyền vào là phần trăm (<= 100), tính ra pixel thực tế
        if width <= 100:
            actual_width = int(screen_w * (width / 100.0))
        else:
            actual_width = width

        self.panel_width = max(300, min(screen_w, actual_width))

        # Chỉ cập nhật kích thước nếu độ phân giải màn hình vật lý thực sự thay đổi
        cur_geo = self.widget.geometry()
        if cur_geo.width() != screen_w or cur_geo.height() != screen_h or cur_geo.x() != 0 or cur_geo.y() != 0:
            self.widget.setGeometry(0, 0, screen_w, screen_h)
            user32.SetWindowPos(
                self.hwnd,
                HWND_TOPMOST,
                0, 0, screen_w, screen_h,
                SWP_NOACTIVATE | SWP_NOOWNERZORDER
            )

    @Slot()
    def bring_to_front(self):
        """Giữ cửa sổ ở đỉnh Z-Order mà tuyệt đối không gọi BringWindowToTop để tránh làm mất Focus của Game"""
        if not self.is_visible:
            return
        user32.SetWindowPos(
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

        self.preserve_foreground_window()
        self.enforce_no_activate_children()

        self.update_geometry(self.width_setting)
        # Tắt chế độ xuyên thấu (gỡ cờ WS_EX_TRANSPARENT) để Panel và Backdrop nhận tương tác chuột
        self._set_click_through(False)

        # Kiểm tra nếu ForegroundWindow bị lệch sang HWND của chúng ta thì lập tức trả lại cho Game
        if user32.GetForegroundWindow() == self.hwnd.value:
            self.restore_foreground_window()

        self.visibility_changed.emit(True)
        logger.info(f"Hiển thị thanh điều khiển Handheld (Click-Through=False, Band={self.current_band}).")

    def _perform_physical_hide(self):
        self._hide_timer.stop()
        self._is_closing = False
        self.is_visible = False

        # Bật chế độ xuyên thấu 100% (WS_EX_TRANSPARENT) mà KHÔNG ẩn hay di dời cửa sổ
        # Giúp DWM giữ nguyên Composed Flip, chuột đi xuyên thẳng vào Game bên dưới, không bao giờ nháy màn hình đen
        self._set_click_through(True)
        logger.info("Đã đóng thanh điều khiển (Click-Through=True, bảo toàn Focus & DWM Flip của Game).")

    @Slot()
    def request_animated_hide(self):
        """Yêu cầu Flutter chạy hiệu ứng Fade-Out trước, sau đó mới dời cửa sổ vật lý ra khỏi màn hình"""
        if not self.is_visible or self._is_closing:
            return
        self._is_closing = True
        self.visibility_changed.emit(False)
        # Hẹn giờ dự phòng 240ms phòng trường hợp WebSocket chưa phản hồi lệnh closeOverlay
        self._hide_timer.start(240)

    @Slot()
    def hide(self):
        """Được gọi khi khởi tạo hoặc ngay sau khi Flutter đã hoàn tất hiệu ứng Fade-Out (closeOverlay)"""
        self._perform_physical_hide()

    @Slot()
    def toggle(self):
        if self.is_visible and not self._is_closing:
            self.request_animated_hide()
        else:
            self.show()

