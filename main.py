import sys
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QPixmap, QPainter, QColor, QFont
from PyQt6.QtCore import QObject, pyqtSignal, Qt, QTimer

from core.config import ConfigManager
from core.logger import setup_logger
from ui.overlay_window import OverlayWindow
from services.virtual_keyboard import VirtualKeyboardService
from input_handler.hotkey import HotkeyManager
from input_handler.gamepad import GamepadListener

logger = setup_logger("Main")

class InputBridge(QObject):
    """
    Cầu nối an toàn chuyển đổi các sự kiện từ luồng ngầm (Keyboard/Gamepad)
    về luồng giao diện chính của Qt (Main GUI Thread).
    """
    toggle_overlay_signal = pyqtSignal()
    toggle_keyboard_signal = pyqtSignal()

def create_tray_pixmap() -> QPixmap:
    """Tạo biểu tượng System Tray icon trực quan khi chưa có file .ico rời."""
    pixmap = QPixmap(64, 64)
    pixmap.fill(QColor(0, 0, 0, 0))
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)

    # Nền tròn màu xanh Neon
    painter.setBrush(QColor(0, 210, 255))
    painter.setPen(QColor(255, 255, 255, 180))
    painter.drawEllipse(4, 4, 56, 56)

    # Chữ 'H' đại diện cho Handheld
    painter.setPen(QColor(18, 20, 29))
    font = QFont("Segoe UI", 28, QFont.Weight.Bold)
    painter.setFont(font)
    painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, "H")
    painter.end()
    return pixmap

def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    config = ConfigManager()
    bridge = InputBridge()

    # 1. Khởi tạo cửa sổ Overlay
    overlay = OverlayWindow(config)
    bridge.toggle_overlay_signal.connect(overlay.toggle_overlay)
    bridge.toggle_keyboard_signal.connect(VirtualKeyboardService.toggle_keyboard)

    # 2. Khởi tạo System Tray Icon
    tray_icon = QSystemTrayIcon()
    tray_icon.setIcon(QIcon(create_tray_pixmap()))
    tray_icon.setToolTip("Handheld Quick Settings")

    tray_menu = QMenu()
    tray_menu.addAction("Mở Quick Settings", overlay.toggle_overlay)
    tray_menu.addAction("Bàn phím ảo", VirtualKeyboardService.toggle_keyboard)
    tray_menu.addSeparator()
    tray_menu.addAction("Thoát", app.quit)

    tray_icon.setContextMenu(tray_menu)
    tray_icon.activated.connect(
        lambda reason: overlay.toggle_overlay()
        if reason == QSystemTrayIcon.ActivationReason.Trigger
        else None
    )
    tray_icon.show()

    hotkey_mgr = HotkeyManager()
    hotkey_overlay = config.get("hotkey.toggle_overlay", "ctrl+shift+q")
    hotkey_keyboard = config.get("hotkey.toggle_keyboard", "ctrl+shift+k")

    hotkey_mgr.register(hotkey_overlay, bridge.toggle_overlay_signal.emit)
    hotkey_mgr.register(hotkey_keyboard, bridge.toggle_keyboard_signal.emit, wait_for_release=True)

    # 4. Đăng ký Gamepad Listener (XInput)
    gamepad_listener = None
    if config.get("gamepad.enabled", True):
        gamepad_combo = config.get("gamepad.toggle_combo", ["BACK", "RIGHT_SHOULDER"])
        poll_ms = config.get("gamepad.poll_interval_ms", 50)
        gamepad_listener = GamepadListener(
            callback=bridge.toggle_overlay_signal.emit,
            toggle_combo=gamepad_combo,
            poll_interval_ms=poll_ms
        )
        gamepad_listener.start()

    logger.info("Handheld Quick Settings Overlay đã sẵn sàng chạy ngầm!")
    logger.info(f"- Phím tắt mở Menu: {hotkey_overlay.upper()}")
    logger.info(f"- Phím tắt mở Bàn phím: {hotkey_keyboard.upper()}")

    # Thoát an toàn
    def cleanup():
        logger.info("Đang dừng ứng dụng và giải phóng hooks...")
        hotkey_mgr.unregister_all()
        if gamepad_listener:
            gamepad_listener.stop()

    app.aboutToQuit.connect(cleanup)
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
