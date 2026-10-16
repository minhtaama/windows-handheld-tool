import ctypes
from ctypes import wintypes
from PySide6.QtCore import QObject, Signal, Slot, QRect, QTimer
from PySide6.QtWidgets import QWidget
from PySide6.QtGui import QGuiApplication
from src.core.logger import setup_logger

logger = setup_logger("WindowManager")

# Win32 Constants
GWL_EXSTYLE     = -20
GWL_STYLE       = -16
WS_EX_TOOLWINDOW = 0x00000080
WS_EX_NOACTIVATE = 0x08000000
WS_EX_TOPMOST    = 0x00000008

SWP_NOSIZE       = 0x0001
SWP_NOMOVE       = 0x0002
SWP_NOZORDER     = 0x0004
SWP_NOACTIVATE   = 0x0010
SWP_SHOWWINDOW   = 0x0040
SWP_HIDEWINDOW   = 0x0080

HWND_TOP         = wintypes.HWND(0)
HWND_BOTTOM      = wintypes.HWND(1)
HWND_TOPMOST     = wintypes.HWND(-1)
HWND_NOTOPMOST   = wintypes.HWND(-2)

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

user32.BringWindowToTop.argtypes = [wintypes.HWND]
user32.BringWindowToTop.restype = wintypes.BOOL

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
        self.is_visible = False
        self._is_closing = False
        self.width_setting = 35
        self.panel_width = 380
        self.current_band = ZBID_DESKTOP

        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self._perform_physical_hide)

        # Đặt tọa độ ngoài màn hình trước khi gọi show() lần đầu để khởi tạo QWebEngineView ngầm không nháy hình
        screen_w, screen_h = self._get_screen_dimensions()
        self.widget.setGeometry(screen_w, 0, screen_w, screen_h)
        self.widget.show()

        self.hwnd = wintypes.HWND(self.widget.winId())
        self._init_win32_attributes()

    def _init_win32_attributes(self):
        # 1. Thiết lập Extended Window Styles: Đảm bảo có WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW và WS_EX_TOPMOST
        try:
            current_style = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
            new_style = current_style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST
            user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)
            logger.info(f"Đã gán cờ WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW và WS_EX_TOPMOST cho HWND {self.hwnd}.")
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

    def _get_screen_dimensions(self) -> tuple[int, int]:
        """
        Xác định độ phân giải quét vật lý thực tế của Monitor chứa cửa sổ hiện hành.
        Đảm bảo Overlay luôn bao phủ 100% màn hình Desktop (kể cả khi Game đang render 720p/900p trên màn hình 1080p).
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
                            return mon_w, mon_h
        except Exception as e:
            logger.debug(f"Không thể lấy kích thước từ MonitorFromWindow: {e}")

        # 2. Đọc độ phân giải quét vật lý tức thời qua SM_CXSCREEN, SM_CYSCREEN
        sw = user32.GetSystemMetrics(0)  # SM_CXSCREEN (Độ phân giải quét thực tế tức thời)
        sh = user32.GetSystemMetrics(1)  # SM_CYSCREEN
        if sw > 0 and sh > 0:
            return sw, sh

        # 3. Fallback qua màn hình chính của Qt
        screen = QGuiApplication.primaryScreen()
        if screen:
            geo = screen.geometry()
            return geo.width(), geo.height()
        return 1920, 1080

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

        # Khi hiển thị: phủ toàn màn hình (0, 0, screen_w, screen_h) để chứa lớp nền đen mờ (Backdrop) + Panel bên phải
        # Khi ẩn: dời hoàn toàn ra ngoài màn hình bên phải (x = screen_w) để trả lại tương tác chuột cho Game/Desktop
        x = 0 if self.is_visible else screen_w
        y = 0

        self.widget.setGeometry(x, y, screen_w, screen_h)
        flags = SWP_NOACTIVATE | (SWP_SHOWWINDOW if self.is_visible else 0)
        res = user32.SetWindowPos(
            self.hwnd,
            HWND_TOPMOST,
            x, y, screen_w, screen_h,
            flags
        )
        if not res:
            logger.warning(f"SetWindowPos thất bại trong update_geometry (Lỗi: {ctypes.get_last_error()})")

    @Slot()
    def bring_to_front(self):
        """Đưa cửa sổ lên đỉnh cao nhất của dải Z-Order khi người dùng chạm hoặc click chuột mà không cướp focus"""
        if not self.is_visible:
            return
        user32.BringWindowToTop(self.hwnd)
        user32.SetWindowPos(
            self.hwnd,
            HWND_TOPMOST,
            0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_NOACTIVATE
        )

    @Slot()
    def show(self):
        self._hide_timer.stop()
        self._is_closing = False
        self.is_visible = True
        if not self.widget.isVisible():
            self.widget.show()
        self.update_geometry(self.width_setting)

        # 1. BringWindowToTop: Ép đưa cửa sổ lên vị trí đầu tiên của dải Band hiện tại
        user32.BringWindowToTop(self.hwnd)

        # 2. SetWindowPos với HWND_TOPMOST và SWP_SHOWWINDOW
        res = user32.SetWindowPos(
            self.hwnd,
            HWND_TOPMOST,
            0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_NOACTIVATE
        )
        if not res:
            logger.warning(f"SetWindowPos thất bại trong show (Lỗi: {ctypes.get_last_error()})")

        self.visibility_changed.emit(True)
        logger.info(f"Hiển thị thanh điều khiển Handheld Fullscreen (Phân lớp Band: {self.current_band}).")

    def _perform_physical_hide(self):
        self._hide_timer.stop()
        self._is_closing = False
        self.is_visible = False
        screen_w, screen_h = self._get_screen_dimensions()

        # Dời tọa độ ra ngoài màn hình X = screen_w nhưng vẫn giữ HWND mở để websocket và event không bị ngắt
        self.widget.setGeometry(screen_w, 0, screen_w, screen_h)
        if not self.widget.isVisible():
            self.widget.show()
        res = user32.SetWindowPos(
            self.hwnd,
            HWND_TOPMOST,
            screen_w, 0, screen_w, screen_h,
            SWP_NOACTIVATE
        )
        if not res:
            logger.warning(f"SetWindowPos thất bại trong hide (Lỗi: {ctypes.get_last_error()})")
        logger.info("Đã thu nhỏ / ẩn thanh điều khiển (Hide Dock).")

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

