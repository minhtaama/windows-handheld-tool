import sys
import os
import ctypes

# Thiết lập Per-Monitor V2 DPI Awareness trước khi nạp bất kỳ cửa sổ nào
# DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
try:
    user32 = ctypes.windll.user32
    if hasattr(user32, "SetProcessDpiAwarenessContext"):
        user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    else:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    pass

# Thiết lập cờ Chromium hỗ trợ trong suốt và tương thích với tiến trình đặc quyền TokenUIAccess trước khi nạp QtWebEngine
os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = "--enable-transparent-visuals --no-sandbox --disable-gpu-sandbox"
os.environ["QTWEBENGINE_DISABLE_SANDBOX"] = "1"

from PySide6.QtWidgets import QApplication, QSystemTrayIcon, QMenu, QWidget
from PySide6.QtGui import QIcon, QAction, QPixmap, QColor, QPainter
from PySide6.QtCore import Qt, QObject, Signal, Slot

from src.core.config import ConfigManager
from src.core.logger import setup_logger
from src.overlay.window_manager import WindowManager
from src.overlay.quick_panel import QuickPanel
from src.input.hotkey_service import HotkeyService
from src.input.gamepad_service import GamepadService

logger = setup_logger("Main")

class AppController(QObject):
    toggle_requested = Signal()

    def __init__(self, panel: QuickPanel, win_mgr: WindowManager):
        super().__init__()
        self.panel = panel
        self.win_mgr = win_mgr
        self.toggle_requested.connect(self.win_mgr.toggle, Qt.ConnectionType.QueuedConnection)

        self.panel.request_close.connect(self.win_mgr.hide, Qt.ConnectionType.QueuedConnection)
        self.panel.request_width_change.connect(self._on_width_changed, Qt.ConnectionType.QueuedConnection)
        self.panel.request_scale_change.connect(self._on_scale_changed, Qt.ConnectionType.QueuedConnection)
        self.panel.bridge.requestBringToFront.connect(self.win_mgr.bring_to_front, Qt.ConnectionType.QueuedConnection)
        self.win_mgr.visibility_changed.connect(self.panel.bridge.overlayVisibilityChanged.emit, Qt.ConnectionType.QueuedConnection)

    @Slot(int)
    def _on_width_changed(self, width: int):
        self.win_mgr.update_geometry(width)

    @Slot(float)
    def _on_scale_changed(self, scale: float):
        # Có thể áp dụng QTransform hoặc cập nhật cỡ chữ/padding
        pass

def create_tray_icon() -> QIcon:
    """Tạo biểu tượng hình tròn hiện đại trên khay hệ thống nếu không có tệp icon"""
    pixmap = QPixmap(32, 32)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setBrush(QColor("#7C4DFF"))
    painter.setPen(Qt.PenStyle.NoPen)
    painter.drawEllipse(2, 2, 28, 28)
    painter.setPen(QColor("#FFFFFF"))
    painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, "H")
    painter.end()
    return QIcon(pixmap)

def main():
    logger.info("Khởi động Windows Handheld Tool (Python Host Runtime)...")
    config = ConfigManager()

    # 1. Khởi tạo Qt Application
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    # 2. Khởi tạo Panel Giao diện
    panel = QuickPanel()

    initial_percent = config.get("overlay", "width_percent", default=35)

    # 3. Quản lý cửa sổ Win32 và phân lớp hệ thống
    win_mgr = WindowManager(panel)
    panel.win_mgr = win_mgr
    controller = AppController(panel, win_mgr)

    # Đưa cửa sổ vào trạng thái ban đầu (Docked bên phải theo tỷ lệ width_percent, ẩn sẵn ở khay hệ thống)
    win_mgr.update_geometry(initial_percent)
    win_mgr.hide()

    # 4. Khởi tạo Khay hệ thống (System Tray Icon)
    tray = QSystemTrayIcon(create_tray_icon(), app)
    tray.setToolTip("Windows Handheld Tool")

    menu = QMenu()
    act_toggle = QAction("Mở / Đóng Bảng Điều Khiển (Ctrl+Shift+Q)", menu)
    act_toggle.triggered.connect(win_mgr.toggle)
    menu.addAction(act_toggle)

    menu.addSeparator()

    act_exit = QAction("Thoát Hoàn Toàn", menu)
    act_exit.triggered.connect(app.quit)
    menu.addAction(act_exit)

    tray.setContextMenu(menu)
    tray.activated.connect(lambda reason: win_mgr.toggle() if reason in (
        QSystemTrayIcon.ActivationReason.Trigger,
        QSystemTrayIcon.ActivationReason.DoubleClick
    ) else None)
    tray.show()

    # 5. Khởi tạo Dịch vụ Phím tắt toàn cục (Hotkey cho Overlay và Bàn phím ảo)
    from src.services.virtual_keyboard import VirtualKeyboardService
    VirtualKeyboardService.ensure_registry_settings()
    hotkey_svc = HotkeyService()
    overlay_hk = config.get("hotkey", "toggle_overlay", default="Ctrl+Shift+Q")
    keyboard_hk = config.get("hotkey", "toggle_keyboard", default="Ctrl+Alt+K")
    hotkey_svc.start(
        on_overlay_toggle=lambda: controller.toggle_requested.emit(),
        on_keyboard_toggle=lambda: VirtualKeyboardService.toggle_keyboard(),
        overlay_hk=overlay_hk,
        keyboard_hk=keyboard_hk,
    )

    # 6. Khởi tạo Dịch vụ Đọc Tay Cầm (Gamepad XInput)
    gamepad_svc = GamepadService()
    win_mgr.visibility_changed.connect(gamepad_svc.set_panel_visible, Qt.ConnectionType.QueuedConnection)

    if config.get("gamepad", "enabled", default=True):
        overlay_gp = config.get("gamepad", "overlay_combo", default="BACK+RB")
        keyboard_gp = config.get("gamepad", "keyboard_combo", default="")
        gamepad_svc.start(
            toggle_callback=lambda: controller.toggle_requested.emit(),
            button_callback=lambda btn: panel.bridge.gamepadButtonEvent.emit(btn),
            keyboard_callback=lambda: VirtualKeyboardService.toggle_keyboard(),
            overlay_combo=overlay_gp,
            keyboard_combo=keyboard_gp,
        )

    logger.info("Ứng dụng đã sẵn sàng trên phân lớp ZBID_SYSTEM_TOOLS.")

    # Vòng lặp sự kiện chính của Qt
    exit_code = app.exec()

    # Thu dọn tài nguyên khi thoát
    hotkey_svc.stop()
    gamepad_svc.stop()
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
