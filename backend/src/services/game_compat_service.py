import os
import re
import glob
import time
import winreg
import ctypes
from ctypes import wintypes
from typing import Callable, Optional, Set, List
from PySide6.QtCore import QObject
from src.core.logger import setup_logger

logger = setup_logger("GameCompatService")

# Danh sách loại trừ các tiến trình hệ thống và tiện ích thông thường (Không can thiệp Borderless hay Registry)
NON_GAME_PROCESSES = {
    "explorer.exe",
    "taskmgr.exe",
    "cmd.exe",
    "powershell.exe",
    "pwsh.exe",
    "steam.exe",
    "steamwebhelper.exe",
    "devenv.exe",
    "code.exe",
    "chrome.exe",
    "msedge.exe",
    "firefox.exe",
    "discord.exe",
    "windows_handheld_tool.exe",
    "qtwebengineprocess.exe",
    "shellexperiencehost.exe",
    "searchapp.exe",
    "startmenuexperiencehost.exe",
    "textinputhost.exe",
    "applicationframehost.exe",
    "dwm.exe",
    "rtss.exe",
    "rtssharedmemory.exe",
}

# Win32 Constants
GWL_STYLE = -16
WS_CAPTION = 0x00C00000
WS_THICKFRAME = 0x00040000
WS_MINIMIZEBOX = 0x00020000
WS_MAXIMIZEBOX = 0x00010000
WS_SYSMENU = 0x00080000

SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_NOZORDER = 0x0004
SWP_NOACTIVATE = 0x0010
SWP_FRAMECHANGED = 0x0020
SWP_SHOWWINDOW = 0x0040

HWND_NOTOPMOST = -2
SW_RESTORE = 9
SW_SHOWMAXIMIZED = 3

EVENT_SYSTEM_MINIMIZESTART = 0x0016
WINEVENT_OUTOFCONTEXT = 0x0000
WINEVENT_SKIPOWNPROCESS = 0x0002
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

WINEVENTPROC = ctypes.WINFUNCTYPE(
    None,
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.HWND,
    wintypes.LONG,
    wintypes.LONG,
    wintypes.DWORD,
    wintypes.DWORD,
)

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

user32.IsIconic.argtypes = [wintypes.HWND]
user32.IsIconic.restype = wintypes.BOOL

user32.ShowWindowAsync.argtypes = [wintypes.HWND, ctypes.c_int]
user32.ShowWindowAsync.restype = wintypes.BOOL

user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
user32.ShowWindow.restype = wintypes.BOOL

user32.GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
user32.GetWindowLongW.restype = wintypes.LONG

user32.SetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int, wintypes.LONG]
user32.SetWindowLongW.restype = wintypes.LONG

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

user32.SetWinEventHook.argtypes = [
    wintypes.DWORD,
    wintypes.DWORD,
    wintypes.HMODULE,
    WINEVENTPROC,
    wintypes.DWORD,
    wintypes.DWORD,
    wintypes.DWORD,
]
user32.SetWinEventHook.restype = wintypes.HANDLE

user32.UnhookWinEvent.argtypes = [wintypes.HANDLE]
user32.UnhookWinEvent.restype = wintypes.BOOL

kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE

kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL

kernel32.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.LPWSTR,
    ctypes.POINTER(wintypes.DWORD),
]
kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL


class GameCompatService(QObject):
    """
    Dịch vụ quản trị tương thích trò chơi và cơ chế hiển thị Seamless (Phương án A):
    - Tự động cấu hình cờ Fullscreen Optimizations (FSO) trong Registry để chống văng FSE.
    - Chuyển đổi linh hoạt cửa sổ Game Windowed sang Borderless Fullscreen chuẩn hóa DWM.
    - Lắng nghe và chặn lệnh thu nhỏ (Anti-Minimize Protection) kèm cơ chế Debounce tránh giật màn hình.
    - Tự động chuẩn hóa tệp cấu hình đồ họa cho các tựa game đặc thù (như 4A Engine / Metro Exodus).
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self._hook_handle = None
        self._winevent_proc = None  # Giữ tham chiếu ctypes callback chống GC thu dọn
        self._target_hwnd_getter: Optional[Callable[[], int]] = None
        self._is_active_getter: Optional[Callable[[], bool]] = None
        self._optimized_pids: Set[int] = set()
        self._minimize_timestamps: List[float] = []

    def is_game_process(self, exe_path: str) -> bool:
        """Kiểm tra đường dẫn tệp thực thi có thuộc tiến trình trò chơi hay ứng dụng hệ thống thông thường"""
        if not exe_path:
            return False
        base = os.path.basename(exe_path).lower()
        if base in NON_GAME_PROCESSES:
            return False
        if "c:\\windows\\" in exe_path.lower():
            return False
        return True

    def get_process_image_path(self, pid: int) -> str:
        """Truy vấn đường dẫn tệp thực thi (.exe) tuyệt đối từ Process ID"""
        if pid <= 4:
            return ""
        h_proc = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not h_proc:
            return ""
        try:
            buf = ctypes.create_unicode_buffer(1024)
            size = wintypes.DWORD(1024)
            if kernel32.QueryFullProcessImageNameW(h_proc, 0, buf, ctypes.byref(size)):
                return buf.value
            return ""
        finally:
            kernel32.CloseHandle(h_proc)

    def optimize_fso_registry(self, exe_path: str) -> bool:
        """
        Tự động thiết lập cấu hình Fullscreen Optimizations (FSO) trong Windows Registry:
        1. Gỡ bỏ cờ DISABLEDXMAXIMIZEDWINDOWEDMODE trong AppCompatFlags\\Layers (nếu có).
        2. Gỡ bỏ cờ tắt FSO (bit 0x10) trong HKCU\\System\\GameConfigStore\\Children\\<GUID>.
        3. Bật GameDVR_DXGIHonorFSEWindowsCompatible = 1 để ép DWM duy trì DirectFlip/Composed Flip.
        """
        if not exe_path or not os.path.isabs(exe_path):
            return False

        modified = False
        try:
            # 1. Cấu hình AppCompatFlags\Layers
            layers_path = r"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, layers_path, 0, winreg.KEY_READ | winreg.KEY_WRITE) as k:
                try:
                    val, _ = winreg.QueryValueEx(k, exe_path)
                    if "DISABLEDXMAXIMIZEDWINDOWEDMODE" in val:
                        new_val = val.replace("DISABLEDXMAXIMIZEDWINDOWEDMODE", "").strip()
                        if not new_val or new_val == "~":
                            new_val = "~ HIGHDPIAWARE"
                        winreg.SetValueEx(k, exe_path, 0, winreg.REG_SZ, new_val)
                        logger.info(f"[SEAMLESS-COMPAT] Gỡ bỏ cờ DISABLEDXMAXIMIZEDWINDOWEDMODE cho: {exe_path} -> '{new_val}'")
                        modified = True
                except FileNotFoundError:
                    winreg.SetValueEx(k, exe_path, 0, winreg.REG_SZ, "~ HIGHDPIAWARE")
                    logger.info(f"[SEAMLESS-COMPAT] Đăng ký cờ tương thích ~ HIGHDPIAWARE cho: {exe_path}")
                    modified = True
        except Exception as e:
            logger.debug(f"[SEAMLESS-COMPAT] Ngoại lệ AppCompatFlags\\Layers: {e}")

        try:
            # 2. Cấu hình GameConfigStore\Children
            children_path = r"System\GameConfigStore\Children"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, children_path, 0, winreg.KEY_READ | winreg.KEY_WRITE) as k:
                num_subkeys = winreg.QueryInfoKey(k)[0]
                for i in range(num_subkeys):
                    subname = winreg.EnumKey(k, i)
                    try:
                        with winreg.OpenKey(k, subname, 0, winreg.KEY_READ | winreg.KEY_WRITE) as sk:
                            p, _ = winreg.QueryValueEx(sk, "MatchedExeFullPath")
                            if p.lower() == exe_path.lower():
                                flags, _ = winreg.QueryValueEx(sk, "Flags")
                                if flags & 0x10:  # Bit 4: Tắt Fullscreen Optimizations
                                    new_flags = flags & ~0x10
                                    if new_flags == 0:
                                        new_flags = 1
                                    winreg.SetValueEx(sk, "Flags", 0, winreg.REG_DWORD, new_flags)
                                    logger.info(f"[SEAMLESS-COMPAT] Bật Fullscreen Optimizations trong GameConfigStore ({subname}): Flags {flags} -> {new_flags}")
                                    modified = True
                    except Exception:
                        pass
        except Exception as e:
            logger.debug(f"[SEAMLESS-COMPAT] Ngoại lệ GameConfigStore\\Children: {e}")

        try:
            # 3. Cấu hình Global GameConfigStore
            global_store = r"System\GameConfigStore"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, global_store, 0, winreg.KEY_READ | winreg.KEY_WRITE) as k:
                winreg.SetValueEx(k, "GameDVR_DXGIHonorFSEWindowsCompatible", 0, winreg.REG_DWORD, 1)
                winreg.SetValueEx(k, "GameDVR_FSEBehaviorMode", 0, winreg.REG_DWORD, 2)
                logger.info(f"[SEAMLESS-COMPAT] Kích hoạt GameDVR_DXGIHonorFSEWindowsCompatible=1 và GameDVR_FSEBehaviorMode=2 toàn cục")
                modified = True
        except Exception as e:
            logger.debug(f"[SEAMLESS-COMPAT] Ngoại lệ Global GameConfigStore: {e}")

        return modified

    def optimize_metro_exodus_config(self) -> bool:
        """
        Tự động chuẩn hóa cấu hình Metro Exodus trong Saved Games:
        - Đặt r_fullscreen off (Windowed) để 4A Engine không độc chiếm quét phần cứng FSE.
        - Đặt r_res_hor 1920, r_res_vert 1080 (Độ phân giải gốc Native của màn hình Handheld).
        - Khi r_fullscreen off kết hợp convert_to_borderless, Metro Exodus sẽ chạy Borderless Fullscreen 100% mượt mà, triệt tiêu 100% hiện tượng văng game!
        """
        saved_games = os.path.expanduser(r"~\Saved Games\Metro Exodus")
        if not os.path.exists(saved_games):
            return False

        cfgs = glob.glob(os.path.join(saved_games, "*", "user.cfg"))
        modified_any = False
        for cfg_path in cfgs:
            try:
                with open(cfg_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()

                new_content = content
                if "r_fullscreen on" in new_content:
                    new_content = re.sub(r"r_fullscreen\s+on", "r_fullscreen off", new_content)
                    logger.info(f"[SEAMLESS-COMPAT] Metro Exodus: Tự động chuyển r_fullscreen off trong {cfg_path}")
                    modified_any = True

                if "r_res_hor 1128" in new_content or "r_res_vert 634" in new_content:
                    new_content = re.sub(r"r_res_hor\s+\d+", "r_res_hor 1920", new_content)
                    new_content = re.sub(r"r_res_vert\s+\d+", "r_res_vert 1080", new_content)
                    logger.info(f"[SEAMLESS-COMPAT] Metro Exodus: Tự động đồng bộ độ phân giải Native 1920x1080 trong {cfg_path}")
                    modified_any = True

                if new_content != content:
                    with open(cfg_path, "w", encoding="utf-8") as f:
                        f.write(new_content)
            except Exception as e:
                logger.debug(f"[SEAMLESS-COMPAT] Lỗi cập nhật cấu hình Metro Exodus: {e}")

        return modified_any

    def convert_to_borderless(self, hwnd: int, screen_w: int, screen_h: int) -> bool:
        """
        Nhận diện và chuyển đổi cửa sổ Game dạng có viền (Windowed) sang Borderless Fullscreen:
        - Xóa các cờ WS_CAPTION, WS_THICKFRAME, WS_MINIMIZEBOX, WS_MAXIMIZEBOX.
        - Điều chỉnh tọa độ bao phủ toàn bộ Monitor vật lý (0, 0, screen_w, screen_h).
        """
        if not hwnd or screen_w <= 0 or screen_h <= 0:
            return False

        try:
            cur_style = user32.GetWindowLongW(wintypes.HWND(hwnd), GWL_STYLE)
            border_flags = WS_CAPTION | WS_THICKFRAME
            if cur_style & border_flags:
                new_style = cur_style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU)
                user32.SetWindowLongW(wintypes.HWND(hwnd), GWL_STYLE, new_style)
                user32.SetWindowPos(
                    wintypes.HWND(hwnd),
                    wintypes.HWND(HWND_NOTOPMOST),
                    0, 0, screen_w, screen_h,
                    SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE
                )
                logger.info(f"[SEAMLESS-COMPAT] Đã chuyển đổi cửa sổ Game HWND={hwnd} sang Borderless Fullscreen ({screen_w}x{screen_h})")
                return True
        except Exception as e:
            logger.warning(f"[SEAMLESS-COMPAT] Lỗi khi chuyển đổi Borderless cho HWND={hwnd}: {e}")
        return False

    def restore_if_minimized(self, hwnd: int) -> bool:
        """Kiểm tra và khôi phục ngay lập tức cửa sổ Game nếu bị hệ thống thu nhỏ (SW_MINIMIZE)"""
        if not hwnd:
            return False
        try:
            if user32.IsIconic(wintypes.HWND(hwnd)):
                logger.info(f"[SEAMLESS-COMPAT] Phát hiện Game HWND={hwnd} đang ở trạng thái thu nhỏ (IsIconic=True). Đang cưỡng bức khôi phục (SW_RESTORE)...")
                user32.ShowWindowAsync(wintypes.HWND(hwnd), SW_RESTORE)
                user32.ShowWindow(wintypes.HWND(hwnd), SW_RESTORE)
                return True
        except Exception as e:
            logger.debug(f"[SEAMLESS-COMPAT] Lỗi kiểm tra IsIconic cho HWND={hwnd}: {e}")
        return False

    def optimize_game(self, pid: int, hwnd: int, screen_w: int, screen_h: int):
        """
        Quy trình tối ưu hóa tự động tổng thể khi phát hiện cửa sổ Game đang kích hoạt:
        - Lọc chỉ xử lý các tiến trình trò chơi (bỏ qua Windows Explorer, Steam, TaskMgr...).
        - Quét và cấu hình FSO Registry.
        - Kiểm tra và tự động chuẩn hóa cấu hình cho các tựa game đặc thù (Metro Exodus).
        - Khôi phục nếu Game vừa bị thu nhỏ.
        - Chuyển đổi Borderless nếu Game đang mở ở dạng cửa sổ viền.
        """
        if not pid or pid in self._optimized_pids:
            return

        exe_path = self.get_process_image_path(pid)
        if not self.is_game_process(exe_path):
            return

        self._optimized_pids.add(pid)
        logger.info(f"[SEAMLESS-COMPAT] Bắt đầu tối ưu tương thích Game: PID={pid}, HWND={hwnd}, Path='{exe_path}'")
        self.optimize_fso_registry(exe_path)

        # Hỗ trợ tối ưu đặc thù cho Metro Exodus
        if "metroexodus" in exe_path.lower():
            self.optimize_metro_exodus_config()

        if hwnd:
            self.restore_if_minimized(hwnd)
            self.convert_to_borderless(hwnd, screen_w, screen_h)

    def install_anti_minimize_hook(self, target_hwnd_getter: Callable[[], int], is_active_getter: Callable[[], bool]):
        """
        Cài đặt WinEventHook mức hệ thống để bắt sự kiện EVENT_SYSTEM_MINIMIZESTART (0x0016).
        Kèm bộ đệm Debounce chống vòng lặp khôi phục gián đoạn nếu game liên tục occlude.
        """
        if self._hook_handle:
            return

        self._target_hwnd_getter = target_hwnd_getter
        self._is_active_getter = is_active_getter

        def _event_proc(h_hook, event, hwnd, id_obj, id_child, thread_id, event_time):
            try:
                if event == EVENT_SYSTEM_MINIMIZESTART and hwnd:
                    target_hwnd = self._target_hwnd_getter() if self._target_hwnd_getter else 0
                    is_active = self._is_active_getter() if self._is_active_getter else False
                    if hwnd == target_hwnd and is_active:
                        now = time.time()
                        self._minimize_timestamps = [t for t in self._minimize_timestamps if now - t < 2.0]
                        if len(self._minimize_timestamps) >= 2:
                            logger.warning(f"[SEAMLESS-COMPAT] Game HWND={hwnd} kích hoạt thu nhỏ liên tiếp (>=2 lần trong 2s). Tạm dừng khôi phục tự động để chống nháy màn hình.")
                            return

                        self._minimize_timestamps.append(now)
                        logger.info(f"[SEAMLESS-COMPAT] BẮT SỰ KIỆN THU NHỎ (EVENT_SYSTEM_MINIMIZESTART) trên Game HWND={hwnd}! Đang chặn và khôi phục tức thời...")
                        user32.ShowWindowAsync(wintypes.HWND(hwnd), SW_RESTORE)
            except Exception as e:
                logger.debug(f"[SEAMLESS-COMPAT] Lỗi trong callback WinEvent: {e}")

        self._winevent_proc = WINEVENTPROC(_event_proc)
        self._hook_handle = user32.SetWinEventHook(
            EVENT_SYSTEM_MINIMIZESTART,
            EVENT_SYSTEM_MINIMIZESTART,
            0,
            self._winevent_proc,
            0,
            0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
        )
        if self._hook_handle:
            logger.info("[SEAMLESS-COMPAT] Đã cài đặt WinEventHook Anti-Minimize (EVENT_SYSTEM_MINIMIZESTART) thành công.")
        else:
            logger.warning("[SEAMLESS-COMPAT] Cài đặt WinEventHook Anti-Minimize thất bại.")

    def uninstall_anti_minimize_hook(self):
        """Gỡ bỏ WinEventHook an toàn khi kết thúc chương trình"""
        if self._hook_handle:
            user32.UnhookWinEvent(self._hook_handle)
            self._hook_handle = None
            self._winevent_proc = None
            logger.info("[SEAMLESS-COMPAT] Đã gỡ bỏ WinEventHook Anti-Minimize.")
