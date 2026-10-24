import os
import sys
import ctypes
from ctypes import wintypes
import socket
import urllib.request
from typing import TYPE_CHECKING, Optional
from PySide6.QtWidgets import QWidget, QVBoxLayout
from PySide6.QtCore import Qt, Signal, QUrl, QCoreApplication, QEvent, QTimer
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWebEngineCore import QWebEngineSettings, QWebEnginePage
from PySide6.QtWebChannel import QWebChannel
from PySide6.QtGui import QKeySequence, QShortcut, QColor

from src.bridge.web_bridge import WebBridge
from src.bridge.ws_server import WsServer
from src.bridge.static_server import StaticServer
from src.core.logger import setup_logger

if TYPE_CHECKING:
    from src.overlay.window_manager import WindowManager

logger = setup_logger("QuickPanel")

class QuickPanel(QWidget):
    request_close = Signal()
    request_width_change = Signal(int)
    request_scale_change = Signal(float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.Tool |
            Qt.WindowType.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, True)
        self.setStyleSheet("background: transparent;")
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)

        self._display_change_timer = QTimer(self)
        self._display_change_timer.setSingleShot(True)
        self._display_change_timer.timeout.connect(self._on_display_change_timeout)

        # Assigned by main.py once the WindowManager is created
        self.win_mgr: Optional["WindowManager"] = None
        self._dev_retries = 0
        self.bridge = WebBridge(self)
        self.ws_server = WsServer(self.bridge, port=8765, parent=self)
        self.static_server = None
        self.dev_tools_view = None
        self.is_dev_mode = False
        self._setup_ui()
        self._connect_bridge_signals()

    def _on_display_change_timeout(self):
        if self.win_mgr:
            logger.info("[WINDOW-GEOMETRY] Kích hoạt cập nhật kích thước Viewport sau Debounce (WM_DISPLAYCHANGE)...")
            self.win_mgr.update_geometry(self.win_mgr.width_setting)

    def mousePressEvent(self, event):
        if self.win_mgr:
            self.win_mgr.preserve_foreground_window()
        self.bridge.requestBringToFront.emit()
        super().mousePressEvent(event)

    def eventFilter(self, watched, event):
        if event.type() in (QEvent.Type.ChildAdded, QEvent.Type.Show, QEvent.Type.FocusIn):
            if hasattr(self, "view") and self.view:
                proxy = self.view.focusProxy()
                if proxy:
                    proxy.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        if event.type() == QEvent.Type.MouseButtonPress:
            if self.win_mgr:
                self.win_mgr.preserve_foreground_window()
            self.bridge.requestBringToFront.emit()
        return super().eventFilter(watched, event)

    def nativeEvent(self, eventType, message):
        if eventType == b"windows_generic_MSG":
            msg = wintypes.MSG.from_address(int(message))
            if msg.message == 0x0021:  # WM_MOUSEACTIVATE
                if self.win_mgr:
                    self.win_mgr.preserve_foreground_window()
                logger.info("[SEAMLESS-1.6] Bắt WM_MOUSEACTIVATE: Ép trả về MA_NOACTIVATE (3) để triệt tiêu hành vi cướp Focus của Game")
                return True, 3
            elif msg.message == 0x0086 and msg.wParam != 0:  # WM_NCACTIVATE
                return True, 0
            elif msg.message == 0x0006 and (msg.wParam & 0xFFFF) != 0:  # WM_ACTIVATE
                logger.info(f"[SEAMLESS-1.6] Bắt WM_ACTIVATE (wParam={msg.wParam}): Đang khôi phục tiêu điểm cho Game...")
                if self.win_mgr:
                    self.win_mgr.restore_foreground_window()
                return True, 0
            elif msg.message == 0x007E:  # WM_DISPLAYCHANGE
                new_w = msg.lParam & 0xFFFF
                new_h = (msg.lParam >> 16) & 0xFFFF
                logger.info(f"[WINDOW-GEOMETRY] Bắt WM_DISPLAYCHANGE: Độ phân giải quét phần cứng đổi sang {new_w}x{new_h} @ {msg.wParam}bpp (Bắt đầu Debounce 100ms)")
                self._display_change_timer.start(100)
                return True, 0
        return super().nativeEvent(eventType, message)

    def _on_page_load_finished(self, ok: bool):
        logger.info(f"[QuickPanel] Frontend page load finished: ok={ok}, url={self.view.url().toString()}")
        if not ok and self.is_dev_mode:
            logger.warning("[QuickPanel] Dev server web page failed to load initially. Auto-reloading in 1.5s...")
            QTimer.singleShot(1500, self.view.reload)
        elif ok and self.is_dev_mode:
            # DDC can stall while loading modules when the dev server is still compiling: verify the app started
            QTimer.singleShot(self.DEV_APP_CHECK_MS, self._ensure_dev_app_started)

        proxy = self.view.focusProxy()
        if proxy:
            proxy.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            proxy.installEventFilter(self)
        if self.win_mgr:
            self.win_mgr.enforce_no_activate_children()

    DEV_APP_CHECK_MS = 12000
    DEV_APP_MAX_RETRIES = 6

    def _ensure_dev_app_started(self):
        """Reload the dev page while the Flutter app (flt-glass-pane) has not started yet."""
        def _on_result(started):
            if started:
                self._dev_retries = 0
                return
            self._dev_retries += 1
            if self._dev_retries > self.DEV_APP_MAX_RETRIES:
                logger.error("[QuickPanel] Flutter dev app did not start after max retries.")
                return
            logger.warning(f"[QuickPanel] Flutter dev app not started, reloading (attempt {self._dev_retries})...")
            self.view.reload()
        self.view.page().runJavaScript("!!document.querySelector('flt-glass-pane')", _on_result)

    def _setup_ui(self):
        self.installEventFilter(self)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # 1. Khởi tạo QWebEngineView trong suốt
        # Đưa cache/storage của QtWebEngine vào %LOCALAPPDATA%\WindowsHandheldTools\cache (chung thư mục với logs)
        try:
            from PySide6.QtWebEngineCore import QWebEngineProfile
            from src.core.logger import get_cache_dir
            _profile = QWebEngineProfile.defaultProfile()
            _cache_dir = get_cache_dir()
            _profile.setCachePath(_cache_dir)
            _profile.setPersistentStoragePath(_cache_dir)
        except Exception:
            pass
        self.view = QWebEngineView(self)
        self.view.setStyleSheet("background: transparent;")
        self.view.setFocusPolicy(Qt.FocusPolicy.NoFocus)
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
        self.shortcut_f5 = QShortcut(QKeySequence("F5"), self)
        self.shortcut_f5.activated.connect(self._reload_frontend)
        self.shortcut_ctrl_r = QShortcut(QKeySequence("Ctrl+R"), self)
        self.shortcut_ctrl_r.activated.connect(self._reload_frontend)

        # 4. Xác định nạp Vite Dev Server hay Bản build Production
        self._load_frontend()

        layout.addWidget(self.view)

    def _is_dev_server_running(self) -> bool:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(0.5)
                return s.connect_ex(("127.0.0.1", 5173)) == 0
        except Exception as e:
            logger.debug(f"Dev server probe failed: {e}")
            return False

    def _load_frontend(self):
        # 1. Dev server chỉ được dò khi chạy từ source; bản đóng gói (frozen) luôn dùng build tĩnh
        if not getattr(sys, "frozen", False) and self._is_dev_server_running():
            logger.info("Phát hiện Flutter Web Dev Server đang chạy tại http://127.0.0.1:5173. Đang nạp chế độ Dev...")
            self.is_dev_mode = True
            self.view.load(QUrl("http://127.0.0.1:5173"))
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
            backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            project_root = os.path.dirname(backend_dir)
            candidates.append(os.path.join(project_root, "frontend", "build", "web"))
            candidates.append(os.path.join(backend_dir, "build", "web"))

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
            self.is_dev_mode = True
            self.view.load(QUrl("http://127.0.0.1:5173"))

    def _reload_frontend(self):
        logger.info("[QuickPanel] Reloading frontend view (F5 / Ctrl+R)...")
        self.view.reload()

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

