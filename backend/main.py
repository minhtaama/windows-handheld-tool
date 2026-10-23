import sys
import os
import ctypes
from ctypes import wintypes

# Thiết lập Per-Monitor V2 DPI Awareness trước khi nạp bất kỳ cửa sổ nào
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

def _log_seamless_environment():
    """Ghi nhật ký chẩn đoán chi tiết các tiêu chuẩn Seamless Transition tại tầng hệ điều hành"""
    logger.info("================================================================")
    logger.info("  KIỂM TRA HIỆN TRẠNG MÔI TRƯỜNG SEAMLESS TRANSITION (OS LEVEL)  ")
    logger.info("================================================================")

    # 1.1. Per-Monitor V2 DPI Awareness
    try:
        cur_dpi_ctx = user32.GetProcessDpiAwarenessContext(ctypes.windll.kernel32.GetCurrentProcess())
        sys_dpi = user32.GetDpiForSystem() if hasattr(user32, "GetDpiForSystem") else 96
        logger.info(f"[SEAMLESS-1.1] DPI Awareness: SetOk={dpi_set_ok}, Context={cur_dpi_ctx}, SystemDPI={sys_dpi} (100%=96, 150%=144)")
    except Exception as e:
        logger.warning(f"[SEAMLESS-1.1] Lỗi đọc DPI Context: {e}")

    # 1.7. Elevated Administrator Token
    try:
        is_admin = bool(ctypes.windll.shell32.IsUserAnAdmin())
        logger.info(f"[SEAMLESS-1.7] Token Elevation: IsAdministrator={is_admin}")
    except Exception as e:
        logger.warning(f"[SEAMLESS-1.7] Lỗi kiểm tra IsUserAnAdmin: {e}")

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
                logger.info(f"[SEAMLESS-1.8 & 1.9] TokenUIAccess Flag: {ui_access.value} (1=Đã cấp đặc quyền UIAccess, 0=Chưa có)")
            else:
                logger.warning(f"[SEAMLESS-1.8 & 1.9] GetTokenInformation thất bại: {kernel32.GetLastError()}")
            kernel32.CloseHandle(h_token)
        else:
            logger.warning(f"[SEAMLESS-1.8 & 1.9] OpenProcessToken thất bại: {kernel32.GetLastError()}")
    except Exception as e:
        logger.warning(f"[SEAMLESS-1.8 & 1.9] Lỗi đọc TokenUIAccess: {e}")
    logger.info("================================================================")

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

def get_app_icon() -> QIcon:
    """Nạp biểu tượng Gamepad chuẩn Google Fonts tương thích cả mã nguồn và bundle PyInstaller"""
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

    # Fallback tự vẽ vector Gamepad Google Fonts Material Symbols nếu thiếu tệp trên đĩa
    try:
        from PySide6.QtSvg import QSvgRenderer
        from PySide6.QtCore import QByteArray, QRectF
        svg_code = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="64" height="64">
          <defs>
            <linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#9C27B0"/>
              <stop offset="100%" stop-color="#673AB7"/>
            </linearGradient>
          </defs>
          <circle cx="12" cy="12" r="11" fill="url(#g)"/>
          <path fill="#FFFFFF" transform="scale(0.68) translate(5.6, 5.6)" d="M21.58 16.09l-1.09-7.66C20.21 6.46 18.52 5 16.53 5H7.47C5.48 5 3.79 6.46 3.51 8.43l-1.09 7.66C2.2 17.63 3.39 19 4.94 19c.68 0 1.32-.27 1.8-.75L9 16h6l2.25 2.25c.48.48 1.13.75 1.8.75 1.56 0 2.75-1.37 2.53-2.91zM11 11H9v2H8v-2H6v-1h2V8h1v2h2v1zm4-1c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm2 3c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
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
    logger.info("Khởi động Windows Handheld Tool (Python Host Runtime)...")
    _log_seamless_environment()
    config = ConfigManager()

    # 1. Khởi tạo Qt Application
    app = QApplication(sys.argv)
    # Gộp toàn bộ dữ liệu Qt (QtWebEngine cache, storage...) vào đúng 1 thư mục %LOCALAPPDATA%\WindowsHandheldTools
    app.setApplicationName("WindowsHandheldTools")
    app.setOrganizationName("")
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
    app_icon = get_app_icon()
    app.setWindowIcon(app_icon)
    tray = QSystemTrayIcon(app_icon, app)
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
    win_mgr.cleanup()
    win_mgr.game_compat.uninstall_anti_minimize_hook()
    hotkey_svc.stop()
    gamepad_svc.stop()
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
