import ctypes
from ctypes import wintypes
from PySide6.QtCore import QObject, Signal, QRect
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

HWND_TOPMOST     = -1
ZBID_SYSTEM_TOOLS = 2

class WindowManager(QObject):
    visibility_changed = Signal(bool)

    def __init__(self, widget: QWidget):
        super().__init__()
        self.widget = widget
        self.hwnd = int(widget.winId())
        self.is_visible = False
        self.panel_width = 380
        self._init_win32_attributes()

    def _init_win32_attributes(self):
        user32 = ctypes.windll.user32
        # Thiết lập Extended Window Styles: WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST
        try:
            current_style = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
            new_style = current_style | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST
            user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, new_style)
            logger.info(f"Đã gán cờ WS_EX_NOACTIVATE và WS_EX_TOOLWINDOW cho HWND {self.hwnd}.")
        except Exception as e:
            logger.warning(f"Lỗi khi gán ExStyle: {e}")

        # Thử đưa vào phân lớp hệ thống ZBID_SYSTEM_TOOLS = 2 nếu tiến trình có quyền uiAccess
        try:
            pfnSetWindowBand = getattr(user32, "SetWindowBand", None)
            if pfnSetWindowBand:
                res = pfnSetWindowBand(self.hwnd, None, ZBID_SYSTEM_TOOLS)
                if res:
                    logger.info("Đã gán thành công phân lớp ZBID_SYSTEM_TOOLS.")
                else:
                    logger.info("SetWindowBand bỏ qua (Yêu cầu TokenUIAccess trong môi trường Production).")
        except Exception as e:
            logger.warning(f"Lỗi gọi SetWindowBand: {e}")

    def update_geometry(self, width: int):
        self.panel_width = width
        screen = QGuiApplication.primaryScreen()
        if not screen:
            return
        geo = screen.geometry()
        screen_w = geo.width()
        screen_h = geo.height()

        x = screen_w - self.panel_width
        y = 0

        user32 = ctypes.windll.user32
        flags = SWP_NOZORDER | SWP_NOACTIVATE
        if not self.is_visible:
            # Nếu đang ẩn, dời ra ngoài màn hình bên phải
            x = screen_w

        user32.SetWindowPos(self.hwnd, 0, x, y, self.panel_width, screen_h, flags)

    def show(self):
        self.is_visible = True
        self.widget.show()
        self.update_geometry(self.panel_width)
        user32 = ctypes.windll.user32
        user32.SetWindowPos(
            self.hwnd,
            HWND_TOPMOST,
            0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW
        )
        self.visibility_changed.emit(True)
        logger.info("Hiển thị thanh điều khiển Handheld (Show Dock).")

    def hide(self):
        self.is_visible = False
        screen = QGuiApplication.primaryScreen()
        screen_w = screen.geometry().width() if screen else 1920
        screen_h = screen.geometry().height() if screen else 1080

        user32 = ctypes.windll.user32
        # Dời tọa độ ra ngoài màn hình X = screen_w nhưng vẫn giữ HWND mở để thông điệp và event không bị ngắt
        user32.SetWindowPos(
            self.hwnd,
            0,
            screen_w, 0, self.panel_width, screen_h,
            SWP_NOZORDER | SWP_NOACTIVATE
        )
        self.visibility_changed.emit(False)
        logger.info("Đã thu nhỏ / ẩn thanh điều khiển (Hide Dock).")

    def toggle(self):
        if self.is_visible:
            self.hide()
        else:
            self.show()
