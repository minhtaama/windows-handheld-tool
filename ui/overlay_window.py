from typing import Optional
from PyQt6.QtWidgets import QMainWindow, QWidget, QHBoxLayout
from PyQt6.QtCore import Qt, QPoint, QPropertyAnimation, QEasingCurve, pyqtSignal
from PyQt6.QtGui import QGuiApplication, QKeyEvent

from core.config import ConfigManager
from core.logger import setup_logger
from .styles import MAIN_STYLESHEET
from .quick_panel import QuickSettingsPanel

logger = setup_logger("OverlayWindow")

class OverlayWindow(QMainWindow):
    """
    Cửa sổ Overlay không viền, luôn nằm trên cùng (TopMost) và trượt ra từ mép phải màn hình.
    """
    overlayToggled = pyqtSignal(bool)

    def __init__(self, config_manager: ConfigManager, parent: Optional[QWidget] = None):
        super().__init__(parent)
        self.config = config_manager
        self.is_open: bool = False
        self._panel_width: int = self.config.get("overlay.width", 360)
        self._anim_duration: int = self.config.get("overlay.animation_duration_ms", 220)

        self._setup_window_flags()
        self._init_ui()
        self._setup_animation()

    def _setup_window_flags(self) -> None:
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setStyleSheet(MAIN_STYLESHEET)

    def _init_ui(self) -> None:
        root = QWidget()
        root.setObjectName("OverlayRoot")
        layout = QHBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self.panel = QuickSettingsPanel(self.config, parent=self)
        self.panel.closeRequested.connect(self.hide_overlay)
        layout.addWidget(self.panel)

        self.setCentralWidget(root)

    def _get_screen_geometry(self):
        screen = QGuiApplication.primaryScreen()
        return screen.geometry() if screen else None

    def _setup_animation(self) -> None:
        self.anim = QPropertyAnimation(self, b"pos")
        self.anim.setDuration(self._anim_duration)
        self.anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        self.anim.finished.connect(self._on_animation_finished)

    def _on_animation_finished(self) -> None:
        if not self.is_open:
            self.hide()

    def toggle_overlay(self) -> None:
        if self.is_open:
            self.hide_overlay()
        else:
            self.show_overlay()

    def show_overlay(self) -> None:
        geom = self._get_screen_geometry()
        if not geom:
            return

        screen_w = geom.width()
        screen_h = geom.height()

        self.resize(self._panel_width, screen_h)
        self.panel.refresh_values()

        start_pos = QPoint(screen_w, 0)
        end_pos = QPoint(screen_w - self._panel_width, 0)

        self.move(start_pos)
        self.show()
        self.raise_()
        self.activateWindow()

        self.anim.stop()
        self.anim.setStartValue(self.pos())
        self.anim.setEndValue(end_pos)
        self.is_open = True
        self.anim.start()
        self.overlayToggled.emit(True)
        logger.info("Mở thanh Quick Settings Overlay.")

    def hide_overlay(self) -> None:
        geom = self._get_screen_geometry()
        if not geom:
            return

        screen_w = geom.width()
        end_pos = QPoint(screen_w, 0)

        self.anim.stop()
        self.anim.setStartValue(self.pos())
        self.anim.setEndValue(end_pos)
        self.is_open = False
        self.anim.start()
        self.overlayToggled.emit(False)
        logger.info("Đóng thanh Quick Settings Overlay.")

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if event.key() == Qt.Key.Key_Escape:
            self.hide_overlay()
        else:
            super().keyPressEvent(event)
