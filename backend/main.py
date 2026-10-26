import sys
import os
import ctypes
from ctypes import wintypes

# Set Per-Monitor V2 DPI Awareness prior to loading any windows
# DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
dpi_set_ok = False
try:
    user32 = ctypes.windll.user32
    if hasattr(user32, "SetProcessDpiAwarenessContext"):
        res = user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
        dpi_set_ok = bool(res)
    else:
        res = ctypes.windll.shcore.SetProcessDpiAwareness(2)
        dpi_set_ok = (res == 0)
except Exception:
    dpi_set_ok = False

from PySide6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PySide6.QtGui import QIcon, QAction, QPixmap, QColor, QPainter
from PySide6.QtCore import Qt, QObject, Signal, Slot

from src.core.config import ConfigManager
from src.core.logger import setup_logger
from src.bridge.web_bridge import WebBridge
from src.bridge.ws_server import WsServer
from src.overlay.window_manager import WindowManager
from src.input.hotkey_service import HotkeyService
from src.input.gamepad_service import GamepadService

logger = setup_logger("Main")

def _log_seamless_environment():
    """Logs diagnostic details of seamless transition prerequisites at the OS level."""
    logger.info("================================================================")
    logger.info("  SEAMLESS TRANSITION ENVIRONMENT DIAGNOSTICS (OS LEVEL)        ")
    logger.info("================================================================")

    # 1.1. Per-Monitor V2 DPI Awareness
    try:
        cur_dpi_ctx = "N/A"
        dpi_awareness = "N/A"
        if hasattr(user32, "GetThreadDpiAwarenessContext"):
            user32.GetThreadDpiAwarenessContext.restype = ctypes.c_void_p
            ctx = user32.GetThreadDpiAwarenessContext()
            cur_dpi_ctx = hex(ctx) if ctx else "0x0"
            if hasattr(user32, "GetAwarenessFromDpiAwarenessContext") and ctx:
                user32.GetAwarenessFromDpiAwarenessContext.argtypes = [ctypes.c_void_p]
                user32.GetAwarenessFromDpiAwarenessContext.restype = ctypes.c_int
                dpi_awareness = user32.GetAwarenessFromDpiAwarenessContext(ctx)
        sys_dpi = user32.GetDpiForSystem() if hasattr(user32, "GetDpiForSystem") else 96
        logger.info(f"[SEAMLESS-1.1] DPI Awareness: SetOk={dpi_set_ok}, Context={cur_dpi_ctx}, Awareness={dpi_awareness}, SystemDPI={sys_dpi}")
    except Exception as e:
        logger.warning(f"[SEAMLESS-1.1] Error reading DPI Context: {e}")

    # 1.7. Elevated Administrator Token
    try:
        is_admin = bool(ctypes.windll.shell32.IsUserAnAdmin())
        logger.info(f"[SEAMLESS-1.7] Token Elevation: IsAdministrator={is_admin}")
    except Exception as e:
        logger.warning(f"[SEAMLESS-1.7] Error checking IsUserAnAdmin: {e}")

    # 1.8 & 1.9. Secure Directory Execution & TokenUIAccess
    exe_path = os.path.abspath(sys.executable)
    is_program_files = "program files" in exe_path.lower()
    logger.info(f"[SEAMLESS-1.8 & 1.9] Secure Execution: ExePath='{exe_path}', IsProgramFiles={is_program_files}")

    try:
        advapi32 = ctypes.windll.advapi32
        kernel32 = ctypes.windll.kernel32
        kernel32.GetCurrentProcess.restype = wintypes.HANDLE
        advapi32.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
        advapi32.OpenProcessToken.restype = wintypes.BOOL
        advapi32.GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
        advapi32.GetTokenInformation.restype = wintypes.BOOL

        h_process = kernel32.GetCurrentProcess()
        h_token = wintypes.HANDLE()
        TOKEN_QUERY = 0x0008
        TokenUIAccess = 26
        if advapi32.OpenProcessToken(h_process, TOKEN_QUERY, ctypes.byref(h_token)):
            ui_access = wintypes.DWORD()
            ret_len = wintypes.DWORD()
            if advapi32.GetTokenInformation(h_token, TokenUIAccess, ctypes.byref(ui_access), ctypes.sizeof(ui_access), ctypes.byref(ret_len)):
                logger.info(f"[SEAMLESS-1.8 & 1.9] TokenUIAccess Flag: {ui_access.value}")
            else:
                logger.warning(f"[SEAMLESS-1.8 & 1.9] GetTokenInformation failed: {kernel32.GetLastError()}")
            kernel32.CloseHandle(h_token)
        else:
            logger.warning(f"[SEAMLESS-1.8 & 1.9] OpenProcessToken failed: {kernel32.GetLastError()}")
    except Exception as e:
        logger.warning(f"[SEAMLESS-1.8 & 1.9] Error reading TokenUIAccess: {e}")
    logger.info("================================================================")

class AppController(QObject):
    toggle_requested = Signal()

    def __init__(self, bridge: WebBridge, win_mgr: WindowManager):
        super().__init__()
        self.bridge = bridge
        self.win_mgr = win_mgr
        self.toggle_requested.connect(self.win_mgr.toggle, Qt.ConnectionType.QueuedConnection)

        self.bridge.requestClose.connect(self.win_mgr.hide, Qt.ConnectionType.QueuedConnection)
        self.bridge.requestWidthChange.connect(self._on_width_changed, Qt.ConnectionType.QueuedConnection)
        self.bridge.requestScaleChange.connect(self._on_scale_changed, Qt.ConnectionType.QueuedConnection)
        self.bridge.requestBringToFront.connect(self.win_mgr.bring_to_front, Qt.ConnectionType.QueuedConnection)
        self.bridge.requestExitApp.connect(self._on_exit_requested, Qt.ConnectionType.QueuedConnection)
        self.win_mgr.visibility_changed.connect(self.bridge.overlayVisibilityChanged.emit, Qt.ConnectionType.QueuedConnection)

    @Slot()
    def _on_exit_requested(self):
        """Logs the source of an exit request before shutting the host down."""
        logger.warning("[EXIT] requestExitApp received from UI -> stopping host runtime")
        QApplication.instance().quit()

    @Slot(int)
    def _on_width_changed(self, width: int):
        self.win_mgr.update_geometry(width)

    @Slot(float)
    def _on_scale_changed(self, scale: float):
        pass

def get_app_icon() -> QIcon:
    """Loads gamepad icon compatible with both dev mode and PyInstaller bundle."""
    candidate_dirs = [
        os.path.join(getattr(sys, "_MEIPASS", ""), "assets"),
        os.path.join(os.path.dirname(os.path.abspath(sys.executable)), "assets"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets"),
        os.path.join(os.path.abspath("backend"), "assets"),
        os.path.abspath("assets"),
    ]

    for adir in candidate_dirs:
        if not adir or not os.path.isdir(adir):
            continue
        for icon_name in ("app_icon.ico", "app_icon.png"):
            icon_path = os.path.join(adir, icon_name)
            if os.path.isfile(icon_path):
                icon = QIcon(icon_path)
                if not icon.isNull():
                    return icon

    # Fallback to vector drawing of Google Fonts gamepad symbol
    try:
        from PySide6.QtSvg import QSvgRenderer
        from PySide6.QtCore import QByteArray, QRectF
        svg_code = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="64" height="64">
          <path fill="rgba(0,0,0,0.25)" transform="translate(0, 0.6)" d="M21.58 16.09l-1.09-7.66C20.21 6.46 18.52 5 16.53 5H7.47C5.48 5 3.79 6.46 3.51 8.43l-1.09 7.66C2.2 17.63 3.39 19 4.94 19c.68 0 1.32-.27 1.8-.75L9 16h6l2.25 2.25c.48.48 1.13.75 1.8.75 1.56 0 2.75-1.37 2.53-2.91zM11 11H9v2H8v-2H6v-1h2V8h1v2h2v1zm4-1c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm2 3c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
          <path fill="#FFFFFF" stroke="rgba(40,40,40,0.35)" stroke-width="0.35" stroke-linejoin="round" d="M21.58 16.09l-1.09-7.66C20.21 6.46 18.52 5 16.53 5H7.47C5.48 5 3.79 6.46 3.51 8.43l-1.09 7.66C2.2 17.63 3.39 19 4.94 19c.68 0 1.32-.27 1.8-.75L9 16h6l2.25 2.25c.48.48 1.13.75 1.8.75 1.56 0 2.75-1.37 2.53-2.91zM11 11H9v2H8v-2H6v-1h2V8h1v2h2v1zm4-1c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm2 3c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
          <circle cx="9.2" cy="15.0" r="1.7" fill="#E8E8E8" stroke="rgba(0,0,0,0.25)" stroke-width="0.25"/>
          <circle cx="14.8" cy="15.0" r="1.7" fill="#E8E8E8" stroke="rgba(0,0,0,0.25)" stroke-width="0.25"/>
          <circle cx="9.2" cy="15.0" r="1.0" fill="#9E9E9E"/>
          <circle cx="14.8" cy="15.0" r="1.0" fill="#9E9E9E"/>
        </svg>'''
        renderer = QSvgRenderer(QByteArray(svg_code.encode("utf-8")))
        pixmap = QPixmap(64, 64)
        pixmap.fill(Qt.GlobalColor.transparent)
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        renderer.render(painter, QRectF(0, 0, 64, 64))
        painter.end()
        return QIcon(pixmap)
    except Exception:
        pass

    return QIcon()

def main():
    logger.info("Starting Windows Handheld Tool (Python Host Runtime)...")
    _log_seamless_environment()
    config = ConfigManager()

    # 1. Initialize Qt Application
    app = QApplication(sys.argv)
    app.setApplicationName("WindowsHandheldTools")
    app.setOrganizationName("")
    app.setQuitOnLastWindowClosed(False)
    app.aboutToQuit.connect(lambda: logger.warning("[EXIT] QApplication aboutToQuit -> host runtime is stopping"))

    # 2. Initialize WebBridge & WebSocket Server
    bridge = WebBridge()
    ws_port = config.get("server", "ws_port", default=8765)
    ws_server = WsServer(bridge, port=ws_port)

    # 3. Initialize Flutter Desktop Window Manager
    win_mgr = WindowManager()
    ws_server.win_mgr = win_mgr
    controller = AppController(bridge, win_mgr)

    initial_percent = config.get("overlay", "width_percent", default=35)
    win_mgr.update_geometry(initial_percent)
    win_mgr.hide()

    # 4. Initialize System Tray Icon
    app_icon = get_app_icon()
    app.setWindowIcon(app_icon)
    tray = QSystemTrayIcon(app_icon, app)
    tray.setToolTip("Windows Handheld Tool")

    menu = QMenu()
    act_toggle = QAction("Open / Close Quick Panel (Ctrl+Shift+Q)", menu)
    act_toggle.triggered.connect(win_mgr.toggle)
    menu.addAction(act_toggle)

    menu.addSeparator()

    act_exit = QAction("Exit Completely", menu)
    act_exit.triggered.connect(app.quit)
    menu.addAction(act_exit)

    tray.setContextMenu(menu)
    tray.activated.connect(lambda reason: win_mgr.toggle() if reason in (
        QSystemTrayIcon.ActivationReason.Trigger,
        QSystemTrayIcon.ActivationReason.DoubleClick
    ) else None)
    tray.show()

    # 5. Initialize Global Hotkey Service
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

    # 6. Initialize Gamepad Input Service
    gamepad_svc = GamepadService()
    win_mgr.visibility_changed.connect(gamepad_svc.set_panel_visible, Qt.ConnectionType.QueuedConnection)

    if config.get("gamepad", "enabled", default=True):
        overlay_gp = config.get("gamepad", "overlay_combo", default="BACK+RB")
        keyboard_gp = config.get("gamepad", "keyboard_combo", default="")
        gamepad_svc.start(
            toggle_callback=lambda: controller.toggle_requested.emit(),
            button_callback=lambda btn: bridge.gamepadButtonEvent.emit(btn),
            keyboard_callback=lambda: VirtualKeyboardService.toggle_keyboard(),
            overlay_combo=overlay_gp,
            keyboard_combo=keyboard_gp,
        )

    logger.info("Application ready on system overlay layer.")

    # Main Qt event loop
    exit_code = app.exec()

    # Cleanup resources on exit
    win_mgr.cleanup()
    win_mgr.game_compat.uninstall_anti_minimize_hook()
    hotkey_svc.stop()
    gamepad_svc.stop()
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
