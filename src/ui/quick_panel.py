import os
import sys
import ctypes
import urllib.request
from PySide6.QtWidgets import QWidget, QVBoxLayout
from PySide6.QtCore import Qt, Signal, QUrl, QCoreApplication, QEvent
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWebEngineCore import QWebEngineSettings, QWebEnginePage
from PySide6.QtWebChannel import QWebChannel
from PySide6.QtGui import QKeySequence, QShortcut, QColor

from src.ui.web_bridge import WebBridge
from src.ui.ws_server import WsServer
from src.ui.static_server import StaticServer
from src.core.logger import setup_logger

logger = setup_logger("QuickPanel")

class QuickPanel(QWidget):
    request_close = Signal()
    request_width_change = Signal(int)
    request_scale_change = Signal(float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.bridge = WebBridge(self)
        self.ws_server = WsServer(self.bridge, port=8765, parent=self)
        self.static_server = None
        self.dev_tools_view = None
        self._setup_ui()
        self._connect_bridge_signals()

    def bring_to_front(self):
        """Kích hoạt và đưa cửa sổ lên đỉnh cao nhất của dải Topmost (đè Taskbar và nhận bàn phím)"""
        from ctypes import wintypes
        hwnd = wintypes.HWND(self.winId())
        user32 = ctypes.windll.user32
        user32.SetWindowPos.argtypes = [
            wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
            ctypes.c_int, ctypes.c_int, wintypes.UINT
        ]
        user32.SetWindowPos.restype = wintypes.BOOL
        user32.SetForegroundWindow.argtypes = [wintypes.HWND]
        user32.SetForegroundWindow.restype = wintypes.BOOL

        user32.SetWindowPos(
            hwnd,
            wintypes.HWND(-1),  # HWND_TOPMOST
            0, 0, 0, 0,
            0x0001 | 0x0002 | 0x0040  # SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW
        )
        user32.SetForegroundWindow(hwnd)
        self.activateWindow()

    def mousePressEvent(self, event):
        self.bring_to_front()
        super().mousePressEvent(event)

    def eventFilter(self, watched, event):
        if event.type() in (QEvent.Type.MouseButtonPress, QEvent.Type.FocusIn):
            self.bring_to_front()
        return super().eventFilter(watched, event)

    def _on_page_load_finished(self, ok: bool):
        proxy = self.view.focusProxy()
        if proxy:
            proxy.installEventFilter(self)

    def _setup_ui(self):
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setStyleSheet("background: transparent;")
        self.installEventFilter(self)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # 1. Khởi tạo QWebEngineView trong suốt
        self.view = QWebEngineView(self)
        self.view.setStyleSheet("background: transparent;")
        self.view.page().setBackgroundColor(QColor(0, 0, 0, 0))
        self.view.installEventFilter(self)
        self.view.loadFinished.connect(self._on_page_load_finished)

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

    def _is_dev_server_running(self) -> bool:
        try:
            req = urllib.request.urlopen("http://localhost:5173", timeout=0.3)
            return req.status == 200
        except Exception:
            return False

    def _load_frontend(self):
        # 1. Nếu đang chạy Flutter Web Dev Server tại cổng 5173 (phát triển độc lập)
        if self._is_dev_server_running():
            logger.info("Phát hiện Flutter Web Dev Server đang chạy tại http://localhost:5173. Đang nạp chế độ Dev...")
            self.view.load(QUrl("http://localhost:5173"))
            return

        # 2. Quét tìm thư mục build/web chứa index.html từ các vị trí tiềm năng (PyInstaller bundle, _internal, exe_dir hoặc project root)
        candidates = []
        if getattr(sys, "frozen", False):
            mei_dir = getattr(sys, "_MEIPASS", "")
            if mei_dir:
                candidates.append(os.path.join(mei_dir, "build", "web"))
            exe_dir = os.path.dirname(os.path.abspath(sys.executable))
            candidates.append(os.path.join(exe_dir, "build", "web"))
            candidates.append(os.path.join(exe_dir, "_internal", "build", "web"))
        else:
            dev_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            candidates.append(os.path.join(dev_root, "build", "web"))

        found_build_dir = None
        for path in candidates:
            if os.path.isfile(os.path.join(path, "index.html")):
                found_build_dir = path
                break

        if found_build_dir:
            if not self.static_server:
                self.static_server = StaticServer(directory=found_build_dir, port=8766)
                self.static_server.start()
            logger.info(f"Đang nạp giao diện Flutter Web Production từ máy chủ tĩnh: http://127.0.0.1:8766 (Thư mục: {found_build_dir})")
            self.view.load(QUrl("http://127.0.0.1:8766"))
        else:
            logger.warning("Chưa tìm thấy bản build tĩnh (build/web/index.html). Đang nạp máy chủ dev fallback...")
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
        self.bridge.requestExitApp.connect(self._handle_exit_app)

    def _handle_exit_app(self):
        if self.static_server:
            self.static_server.stop()
        QCoreApplication.quit()

    def closeEvent(self, event):
        if self.static_server:
            self.static_server.stop()
        super().closeEvent(event)
