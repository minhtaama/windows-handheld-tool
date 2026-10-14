import os
import urllib.request
from PySide6.QtWidgets import QWidget, QVBoxLayout
from PySide6.QtCore import Qt, Signal, QUrl, QCoreApplication
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWebEngineCore import QWebEngineSettings, QWebEnginePage
from PySide6.QtWebChannel import QWebChannel
from PySide6.QtGui import QKeySequence, QShortcut

from src.ui.web_bridge import WebBridge
from src.core.logger import setup_logger

logger = setup_logger("QuickPanel")

class QuickPanel(QWidget):
    request_close = Signal()
    request_width_change = Signal(int)
    request_scale_change = Signal(float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.bridge = WebBridge()
        self.dev_tools_view = None
        self._setup_ui()
        self._connect_bridge_signals()

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # 1. Khởi tạo QWebEngineView
        self.view = QWebEngineView(self)
        self.view.setStyleSheet("background: #0b0d14;")

        # Bật các tính năng tăng tốc và dev tools
        settings = self.view.settings()
        settings.setAttribute(QWebEngineSettings.WebAttribute.Accelerated2dCanvasEnabled, True)
        settings.setAttribute(QWebEngineSettings.WebAttribute.WebGLEnabled, True)
        settings.setAttribute(QWebEngineSettings.WebAttribute.JavascriptEnabled, True)
        settings.setAttribute(QWebEngineSettings.WebAttribute.LocalStorageEnabled, True)
        settings.setAttribute(QWebEngineSettings.WebAttribute.ScrollAnimatorEnabled, True)

        # 2. Khởi tạo QWebChannel cầu nối
        self.channel = QWebChannel(self)
        self.channel.registerObject("backend", self.bridge)
        self.view.page().setWebChannel(self.channel)

        # 3. Phím tắt F12 để mở Chromium DevTools kiểm tra và debug web
        self.shortcut_f12 = QShortcut(QKeySequence("F12"), self)
        self.shortcut_f12.activated.connect(self._toggle_dev_tools)

        # 4. Xác định nạp Vite Dev Server hay Bản build Production
        self._load_frontend()

        layout.addWidget(self.view)

    def _is_vite_dev_server_running(self) -> bool:
        try:
            req = urllib.request.urlopen("http://localhost:5173", timeout=0.3)
            return req.status == 200
        except Exception:
            return False

    def _load_frontend(self):
        root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        dist_index = os.path.join(root_dir, "frontend", "dist", "index.html")

        if self._is_vite_dev_server_running():
            logger.info("Phát hiện Vite Dev Server đang chạy tại http://localhost:5173. Đang nạp chế độ HMR Dev...")
            self.view.load(QUrl("http://localhost:5173"))
        elif os.path.isfile(dist_index):
            logger.info(f"Đang nạp giao diện React Production từ: {dist_index}")
            self.view.load(QUrl.fromLocalFile(dist_index))
        else:
            logger.warning(f"Chưa tìm thấy bản build {dist_index}. Đang nạp Vite server fallback...")
            self.view.load(QUrl("http://localhost:5173"))

    def _toggle_dev_tools(self):
        """Mở cửa sổ Chrome DevTools độc lập để Inspect Element, xem Console, Network..."""
        if not self.dev_tools_view:
            self.dev_tools_view = QWebEngineView()
            self.dev_tools_view.setWindowTitle("Handheld Tool - Chrome DevTools (F12)")
            self.dev_tools_view.resize(900, 600)
            self.view.page().setDevToolsPage(self.dev_tools_view.page())

        if self.dev_tools_view.isVisible():
            self.dev_tools_view.hide()
        else:
            self.dev_tools_view.show()
            self.dev_tools_view.activateWindow()

    def _connect_bridge_signals(self):
        self.bridge.requestClose.connect(self.request_close.emit)
        self.bridge.requestWidthChange.connect(self.request_width_change.emit)
        self.bridge.requestScaleChange.connect(self.request_scale_change.emit)
        self.bridge.requestExitApp.connect(QCoreApplication.quit)
