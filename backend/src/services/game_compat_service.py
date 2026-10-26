import os
import time
import winreg
import ctypes
from ctypes import wintypes
from typing import Callable, Optional, Set, List
from PySide6.QtCore import QObject
from src.core.logger import setup_logger
from src.core.config import ConfigManager

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
    "windows_handheld_ui.exe",
    "shellexperiencehost.exe",
    "searchapp.exe",
    "startmenuexperiencehost.exe",
    "textinputhost.exe",
    "applicationframehost.exe",
    "dwm.exe",
    "rtss.exe",
    "rtssharedmemory.exe",
}

# Dấu hiệu đường dẫn thuộc thư viện cài đặt trò chơi
GAME_LIBRARY_MARKERS = (
    "\\steamapps\\",
    "\\epic games\\",
    "\\gog galaxy\\games\\",
    "\\gog games\\",
    "\\xboxgames\\",
    "\\ea games\\",
    "\\origin games\\",
    "\\ubisoft game launcher\\games\\",
    "\\riot games\\",
    "\\games\\",
)

# Win32 Constants
GWL_STYLE = -16
GWL_EXSTYLE = -20
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

EVENT_SYSTEM_FOREGROUND = 0x0003
EVENT_SYSTEM_MINIMIZESTART = 0x0016
WINEVENT_OUTOFCONTEXT = 0x0000
WINEVENT_SKIPOWNPROCESS = 0x0002

PROCESS_ALL_ACCESS = 0x1F0FFF
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
MEM_RELEASE = 0x8000
PAGE_READWRITE = 0x04

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
advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)

class MONITORINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("rcMonitor", wintypes.RECT),
        ("rcWork", wintypes.RECT),
        ("dwFlags", wintypes.DWORD),
    ]

user32.MonitorFromWindow.argtypes = [wintypes.HWND, wintypes.DWORD]
user32.MonitorFromWindow.restype = wintypes.HMONITOR

user32.GetMonitorInfoW.argtypes = [wintypes.HMONITOR, ctypes.POINTER(MONITORINFO)]
user32.GetMonitorInfoW.restype = wintypes.BOOL

user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.GetWindowRect.restype = wintypes.BOOL

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

user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD

kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE

kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL

kernel32.GetCurrentProcess.argtypes = []
kernel32.GetCurrentProcess.restype = wintypes.HANDLE

kernel32.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.LPWSTR,
    ctypes.POINTER(wintypes.DWORD),
]
kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL

kernel32.VirtualAllocEx.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    ctypes.c_size_t,
    wintypes.DWORD,
    wintypes.DWORD,
]
kernel32.VirtualAllocEx.restype = wintypes.LPVOID

kernel32.WriteProcessMemory.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    wintypes.LPCVOID,
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
]
kernel32.WriteProcessMemory.restype = wintypes.BOOL

kernel32.CreateRemoteThread.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    ctypes.c_size_t,
    wintypes.LPVOID,
    wintypes.LPVOID,
    wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD),
]
kernel32.CreateRemoteThread.restype = wintypes.HANDLE

kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.restype = wintypes.DWORD

kernel32.GetExitCodeThread.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
kernel32.GetExitCodeThread.restype = wintypes.BOOL

kernel32.VirtualFreeEx.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    ctypes.c_size_t,
    wintypes.DWORD,
]
kernel32.VirtualFreeEx.restype = wintypes.BOOL

kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
kernel32.GetModuleHandleW.restype = wintypes.HMODULE

kernel32.GetProcAddress.argtypes = [wintypes.HMODULE, ctypes.c_char_p]
kernel32.GetProcAddress.restype = wintypes.LPVOID

kernel32.IsWow64Process.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.BOOL)]
kernel32.IsWow64Process.restype = wintypes.BOOL


class LUID(ctypes.Structure):
    _fields_ = [("LowPart", wintypes.DWORD), ("HighPart", wintypes.LONG)]

class LUID_AND_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("Luid", LUID), ("Attributes", wintypes.DWORD)]

class TOKEN_PRIVILEGES(ctypes.Structure):
    _fields_ = [("PrivilegeCount", wintypes.DWORD), ("Privileges", LUID_AND_ATTRIBUTES * 1)]

advapi32.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
advapi32.OpenProcessToken.restype = wintypes.BOOL

advapi32.LookupPrivilegeValueW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.POINTER(LUID)]
advapi32.LookupPrivilegeValueW.restype = wintypes.BOOL

advapi32.AdjustTokenPrivileges.argtypes = [
    wintypes.HANDLE,
    wintypes.BOOL,
    ctypes.POINTER(TOKEN_PRIVILEGES),
    wintypes.DWORD,
    ctypes.POINTER(TOKEN_PRIVILEGES),
    ctypes.POINTER(wintypes.DWORD),
]
advapi32.AdjustTokenPrivileges.restype = wintypes.BOOL

def enable_debug_privilege() -> bool:
    """Kích hoạt đặc quyền SeDebugPrivilege cho tiến trình để tiêm DLL vào các game chạy quyền Admin"""
    h_token = wintypes.HANDLE()
    if not advapi32.OpenProcessToken(kernel32.GetCurrentProcess(), 0x0028, ctypes.byref(h_token)):
        return False
    try:
        luid = LUID()
        if not advapi32.LookupPrivilegeValueW(None, "SeDebugPrivilege", ctypes.byref(luid)):
            return False

        tp = TOKEN_PRIVILEGES()
        tp.PrivilegeCount = 1
        tp.Privileges[0].Luid = luid
        tp.Privileges[0].Attributes = 0x00000002  # SE_PRIVILEGE_ENABLED

        res = advapi32.AdjustTokenPrivileges(h_token, False, ctypes.byref(tp), 0, None, None)
        return bool(res)
    except Exception as e:
        logger.debug(f"[INJECTOR] Lỗi kích hoạt SeDebugPrivilege: {e}")
        return False
    finally:
        kernel32.CloseHandle(h_token)


class GameCompatService(QObject):
    """
    Dịch vụ quản trị tương thích trò chơi và cơ chế hiển thị Seamless:
    - Quản lý vòng đời trò chơi và tự động tiêm dxgi_hook.dll nội tiến trình (1.8).
    - Tự động cấu hình cờ Fullscreen Optimizations (FSO) trong Registry để chống văng FSE.
    - Chuyển đổi linh hoạt cửa sổ Game Windowed sang Borderless Fullscreen chuẩn hóa DWM.
    - Lắng nghe và chặn lệnh thu nhỏ (Anti-Minimize Protection) kèm cơ chế Debounce tránh giật màn hình.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self._hook_handle = None
        self._foreground_hook_handle = None
        self._winevent_proc = None
        self._foreground_proc = None
        self._target_hwnd_getter: Optional[Callable[[], int]] = None
        self._is_active_getter: Optional[Callable[[], bool]] = None
        self._screen_dims_getter: Optional[Callable[[], tuple]] = None
        self._optimized_pids: Set[int] = set()
        self._injected_pids: Set[int] = set()
        self._minimize_timestamps: List[float] = []

        # Kích hoạt đặc quyền SeDebugPrivilege
        has_priv = enable_debug_privilege()
        logger.info(f"[INJECTOR] Khởi tạo GameCompatService: SeDebugPrivilege={has_priv}")

        # Cấu hình hook: cho phép bật/tắt tiêm DLL và ép Borderless ngay từ config.json
        # để A/B test mà không cần quyền admin hay đổi tên tệp trong Program Files.
        config = ConfigManager()
        self.hook_enabled = bool(config.get("dxgi_hook", "enabled", default=True))
        self.auto_borderless = bool(config.get("dxgi_hook", "auto_borderless", default=True))
        logger.info(f"[SEAMLESS-COMPAT] Cấu hình Hook: enabled={self.hook_enabled}, auto_borderless={self.auto_borderless}")

    def get_dxgi_hook_dll_path(self) -> str:
        """Xác định đường dẫn tuyệt đối của tệp dxgi_hook.dll"""
        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        p1 = os.path.join(base_dir, "bin", "dxgi_hook.dll")
        if os.path.exists(p1):
            return p1
        p2 = os.path.abspath(os.path.join("bin", "dxgi_hook.dll"))
        if os.path.exists(p2):
            return p2
        return p1

    def _window_covers_monitor(self, hwnd: int) -> bool:
        """Cửa sổ phủ kín toàn bộ Monitor chứa nó (đặc trưng của game Borderless/Fullscreen)"""
        if not hwnd:
            return False
        h_mon = user32.MonitorFromWindow(wintypes.HWND(hwnd), 2)  # MONITOR_DEFAULTTONEAREST
        if not h_mon:
            return False
        mi = MONITORINFO()
        mi.cbSize = ctypes.sizeof(MONITORINFO)
        rect = wintypes.RECT()
        if not user32.GetMonitorInfoW(h_mon, ctypes.byref(mi)) or not user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(rect)):
            return False
        return (
            rect.left <= mi.rcMonitor.left + 2 and rect.top <= mi.rcMonitor.top + 2
            and rect.right >= mi.rcMonitor.right - 2 and rect.bottom >= mi.rcMonitor.bottom - 2
        )

    def is_game_process(self, exe_path: str, hwnd: int = 0) -> bool:
        """
        Nhận diện tiến trình trò chơi: đường dẫn thuộc thư viện game (Steam, Epic, GOG, Xbox...)
        hoặc cửa sổ đang phủ kín Monitor. Loại trừ tiến trình hệ thống, ứng dụng UWP và tiện ích thông thường.
        """
        if not exe_path:
            return False
        base = os.path.basename(exe_path).lower()
        if base in NON_GAME_PROCESSES:
            return False
        lower = exe_path.lower()
        if "c:\\windows\\" in lower or "\\windowsapps\\" in lower:
            return False
        if any(marker in lower for marker in GAME_LIBRARY_MARKERS):
            return True
        return self._window_covers_monitor(hwnd)

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

    def inject_dxgi_hook(self, pid: int) -> bool:
        """
        Tiêm thư viện dxgi_hook.dll vào không gian địa chỉ bộ nhớ ảo của tiến trình trò chơi (Mục 1.8):
        1. Kiểm tra kiến trúc tiến trình (Chỉ tiêm vào tiến trình 64-bit).
        2. Cấp phát bộ nhớ trong không gian tiến trình game qua VirtualAllocEx.
        3. Ghi đường dẫn DLL vào bộ nhớ qua WriteProcessMemory.
        4. Tạo luồng từ xa gọi LoadLibraryW qua CreateRemoteThread.
        5. Đọc mã thoát (ExitCode) trả về chính là con trỏ HMODULE của dxgi_hook.dll trong game.
        """
        if not pid or pid in self._injected_pids:
            return True

        dll_path = self.get_dxgi_hook_dll_path()
        if not os.path.exists(dll_path):
            logger.warning(f"[INJECTOR] Không tìm thấy tệp DLL tại: '{dll_path}'")
            return False

        h_proc = kernel32.OpenProcess(PROCESS_ALL_ACCESS, False, pid)
        if not h_proc:
            # Fallback với cờ cơ bản nếu PROCESS_ALL_ACCESS bị từ chối
            h_proc = kernel32.OpenProcess(0x043A, False, pid)
        if not h_proc:
            logger.warning(f"[INJECTOR] OpenProcess thất bại cho PID={pid} (Mã lỗi: {ctypes.get_last_error()})")
            return False

        try:
            # Kiểm tra tiến trình có phải 32-bit (WoW64) không
            is_wow64 = wintypes.BOOL()
            if kernel32.IsWow64Process(h_proc, ctypes.byref(is_wow64)) and is_wow64.value:
                logger.warning(f"[INJECTOR] Tiến trình PID={pid} là ứng dụng 32-bit, bỏ qua tiêm dxgi_hook 64-bit.")
                return False

            dll_bytes = (os.path.abspath(dll_path) + '\0').encode('utf-16le')
            remote_mem = kernel32.VirtualAllocEx(h_proc, None, len(dll_bytes), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
            if not remote_mem:
                logger.warning(f"[INJECTOR] VirtualAllocEx thất bại trong PID={pid} (Mã lỗi: {ctypes.get_last_error()})")
                return False

            try:
                bytes_written = ctypes.c_size_t(0)
                if not kernel32.WriteProcessMemory(h_proc, remote_mem, dll_bytes, len(dll_bytes), ctypes.byref(bytes_written)):
                    logger.warning(f"[INJECTOR] WriteProcessMemory thất bại trong PID={pid} (Mã lỗi: {ctypes.get_last_error()})")
                    return False

                h_k32 = kernel32.GetModuleHandleW("kernel32.dll")
                p_load_lib = kernel32.GetProcAddress(h_k32, b"LoadLibraryW")
                if not p_load_lib:
                    logger.warning("[INJECTOR] Không thể tìm thấy địa chỉ LoadLibraryW")
                    return False

                thread_id = wintypes.DWORD(0)
                h_thread = kernel32.CreateRemoteThread(h_proc, None, 0, p_load_lib, remote_mem, 0, ctypes.byref(thread_id))
                if not h_thread:
                    logger.warning(f"[INJECTOR] CreateRemoteThread thất bại trong PID={pid} (Mã lỗi: {ctypes.get_last_error()})")
                    return False

                try:
                    kernel32.WaitForSingleObject(h_thread, 3000)
                    exit_code = wintypes.DWORD(0)
                    kernel32.GetExitCodeThread(h_thread, ctypes.byref(exit_code))
                    if exit_code.value != 0:
                        self._injected_pids.add(pid)
                        logger.info(f"[INJECTOR] Tiêm thành công dxgi_hook.dll vào Game PID={pid} (HMODULE=0x{exit_code.value:X})")
                        return True
                    else:
                        logger.warning(f"[INJECTOR] LoadLibraryW trả về NULL trong tiến trình Game PID={pid}")
                        return False
                finally:
                    kernel32.CloseHandle(h_thread)
            finally:
                kernel32.VirtualFreeEx(h_proc, remote_mem, 0, MEM_RELEASE)
        except Exception as e:
            logger.error(f"[INJECTOR] Ngoại lệ khi tiêm DLL vào PID={pid}: {e}")
            return False
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
            # 1. Cấu hình AppCompatFlags\Layers:
            # - Chỉ gỡ bỏ đúng token DISABLEDXMAXIMIZEDWINDOWEDMODE (nếu có) để Windows bật Fullscreen
            #   Optimizations / DWM Flip.
            # - Giữ nguyên mọi shim khác (PERMONITORV2, HIGHDPIAWARE, RUNASADMIN...) vì chúng điều khiển
            #   nhận thức DPI của tiến trình game. Xoá PERMONITORV2 sẽ khiến game bị DPI ảo hoá 1,75×
            #   (cửa sổ lớn hơn render buffer, lệch chuột và mất hiệu năng).
            layers_path = r"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, layers_path, 0, winreg.KEY_READ | winreg.KEY_WRITE) as k:
                try:
                    val, _ = winreg.QueryValueEx(k, exe_path)
                    tokens = val.split()
                    kept = [t for t in tokens if t.upper() != "DISABLEDXMAXIMIZEDWINDOWEDMODE"]
                    new_val = " ".join(kept).strip()

                    if new_val in ("", "~"):
                        try:
                            winreg.DeleteValue(k, exe_path)
                            logger.info(f"[SEAMLESS-COMPAT] Đã xóa giá trị AppCompatFlags thừa cho {exe_path}")
                            modified = True
                        except FileNotFoundError:
                            pass
                    elif new_val != val.strip():
                        winreg.SetValueEx(k, exe_path, 0, winreg.REG_SZ, new_val)
                        logger.info(f"[SEAMLESS-COMPAT] Đã gỡ cờ tắt FSO cho {exe_path}: '{val}' -> '{new_val}'")
                        modified = True
                except FileNotFoundError:
                    pass
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

    def convert_to_borderless(self, hwnd: int, screen_w: int, screen_h: int) -> bool:
        """
        Nhận diện và chuẩn hóa cửa sổ Game dạng có viền (Windowed) sang Borderless Fullscreen (Mục 1.9):
        - Truy vấn tọa độ và kích thước thực tế của màn hình chứa cửa sổ Game qua MonitorFromWindow.
        - Xóa các cờ WS_CAPTION, WS_THICKFRAME, WS_MINIMIZEBOX, WS_MAXIMIZEBOX, WS_SYSMENU.
        - Điều chỉnh tọa độ bao phủ toàn bộ Monitor vật lý (rcMonitor.left, rcMonitor.top, width, height).
        """
        if not hwnd:
            return False

        try:
            target_x = 0
            target_y = 0
            target_w = screen_w if screen_w > 0 else 1920
            target_h = screen_h if screen_h > 0 else 1080

            # 1. Truy vấn thông tin Monitor thực tế chứa cửa sổ Game (Hỗ trợ đa màn hình & xoay màn hình)
            h_mon = user32.MonitorFromWindow(wintypes.HWND(hwnd), 2)  # MONITOR_DEFAULTTONEAREST = 2
            if h_mon:
                mi = MONITORINFO()
                mi.cbSize = ctypes.sizeof(MONITORINFO)
                if user32.GetMonitorInfoW(h_mon, ctypes.byref(mi)):
                    target_x = mi.rcMonitor.left
                    target_y = mi.rcMonitor.top
                    target_w = mi.rcMonitor.right - mi.rcMonitor.left
                    target_h = mi.rcMonitor.bottom - mi.rcMonitor.top

            cur_style = user32.GetWindowLongW(wintypes.HWND(hwnd), GWL_STYLE)
            border_flags = WS_CAPTION | WS_THICKFRAME
            needs_style_update = bool(cur_style & border_flags)

            rect = wintypes.RECT()
            user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(rect))
            cur_w = rect.right - rect.left
            cur_h = rect.bottom - rect.top
            cur_x = rect.left
            cur_y = rect.top

            needs_geo_update = (
                abs(cur_w - target_w) > 2
                or abs(cur_h - target_h) > 2
                or abs(cur_x - target_x) > 2
                or abs(cur_y - target_y) > 2
            )

            if needs_style_update or needs_geo_update:
                # Xóa sạch thanh tiêu đề, viền dày, viền đơn (WS_BORDER=0x00800000) và viền hộp thoại (WS_DLGFRAME=0x00400000)
                strip_mask = (
                    WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX |
                    WS_MAXIMIZEBOX | WS_SYSMENU | 0x00800000 | 0x00400000
                )
                new_style = (cur_style & ~strip_mask) | 0x80000000  # WS_POPUP
                user32.SetWindowLongW(wintypes.HWND(hwnd), GWL_STYLE, new_style)

                # Xóa sạch các viền nổi mở rộng (WS_EX_WINDOWEDGE, WS_EX_CLIENTEDGE, WS_EX_STATICEDGE)
                cur_ex = user32.GetWindowLongW(wintypes.HWND(hwnd), GWL_EXSTYLE)
                ex_mask = 0x00000100 | 0x00000200 | 0x00020000
                if cur_ex & ex_mask:
                    user32.SetWindowLongW(wintypes.HWND(hwnd), GWL_EXSTYLE, cur_ex & ~ex_mask)

                user32.SetWindowPos(
                    wintypes.HWND(hwnd),
                    wintypes.HWND(HWND_NOTOPMOST),
                    target_x, target_y, target_w, target_h,
                    SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE | SWP_NOZORDER
                )
                logger.info(f"[SEAMLESS-COMPAT] Đã chuẩn hóa cửa sổ Game HWND={hwnd} sang Borderless Fullscreen: ({target_x}, {target_y}, {target_w}x{target_h})")
                return True
        except Exception as e:
            logger.warning(f"[SEAMLESS-COMPAT] Lỗi khi chuẩn hóa Borderless cho HWND={hwnd}: {e}")
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
        - Tự động tiêm dxgi_hook.dll nội tiến trình (Mục 1.8).
        - Khôi phục nếu Game vừa bị thu nhỏ.
        - Chuyển đổi Borderless nếu Game đang mở ở dạng cửa sổ viền.
        """
        if not pid:
            return

        exe_path = self.get_process_image_path(pid)
        if not self.is_game_process(exe_path, hwnd):
            return

        if pid not in self._optimized_pids:
            self._optimized_pids.add(pid)
            logger.info(f"[SEAMLESS-COMPAT] Bắt đầu tối ưu tương thích Game: PID={pid}, HWND={hwnd}, Path='{exe_path}'")
            self.optimize_fso_registry(exe_path)


            # 1.8. Tiêm dxgi_hook.dll vào tiến trình trò chơi (bỏ qua nếu tắt trong config)
            if self.hook_enabled:
                self.inject_dxgi_hook(pid)
            else:
                logger.info("[SEAMLESS-COMPAT] dxgi_hook.enabled=False -> bỏ qua tiêm DLL")

            if hwnd:
                self.restore_if_minimized(hwnd)
                if self.auto_borderless:
                    self.convert_to_borderless(hwnd, screen_w, screen_h)
                    # Cơ chế Delayed Enforcement chỉ kích hoạt 1 lần duy nhất khi game vừa khởi chạy
                    from PySide6.QtCore import QTimer
                    QTimer.singleShot(400, lambda: self.convert_to_borderless(hwnd, screen_w, screen_h))
                    QTimer.singleShot(1200, lambda: self.convert_to_borderless(hwnd, screen_w, screen_h))
                else:
                    logger.info("[SEAMLESS-COMPAT] dxgi_hook.auto_borderless=False -> giữ nguyên cửa sổ game")
        else:
            # Game đã tối ưu trước đó: chỉ khôi phục nếu game bị thu nhỏ
            if hwnd:
                self.restore_if_minimized(hwnd)

    def install_lifecycle_hooks(
        self,
        target_hwnd_getter: Callable[[], int],
        is_active_getter: Callable[[], bool],
        screen_dimensions_getter: Optional[Callable[[], tuple]] = None,
    ):
        """
        Cài đặt các WinEventHook mức hệ thống để quản lý vòng đời trò chơi:
        1. Bắt sự kiện EVENT_SYSTEM_FOREGROUND (0x0003): Tự động phát hiện khi game vừa khởi chạy/active để tiêm hook tức thời.
        2. Bắt sự kiện EVENT_SYSTEM_MINIMIZESTART (0x0016): Chặn và khôi phục nếu game cố thu nhỏ khi panel mở.
        """
        if self._hook_handle or self._foreground_hook_handle:
            return

        self._target_hwnd_getter = target_hwnd_getter
        self._is_active_getter = is_active_getter
        self._screen_dims_getter = screen_dimensions_getter

        # Callback 1: Anti-Minimize
        def _minimize_proc(h_hook, event, hwnd, id_obj, id_child, thread_id, event_time):
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
                logger.debug(f"[SEAMLESS-COMPAT] Lỗi callback WinEvent Anti-Minimize: {e}")

        # Callback 2: Foreground Game Detection & Auto-Injection
        def _foreground_proc(h_hook, event, hwnd, id_obj, id_child, thread_id, event_time):
            try:
                if event == EVENT_SYSTEM_FOREGROUND and hwnd:
                    pid = wintypes.DWORD(0)
                    user32.GetWindowThreadProcessId(wintypes.HWND(hwnd), ctypes.byref(pid))
                    if pid.value and pid.value != kernel32.GetCurrentProcessId():
                        exe_path = self.get_process_image_path(pid.value)
                        if self.is_game_process(exe_path, hwnd):
                            sw, sh = (1920, 1080)
                            if self._screen_dims_getter:
                                dims = self._screen_dims_getter()
                                if dims and len(dims) == 2:
                                    sw, sh = dims
                            self.optimize_game(pid.value, hwnd, sw, sh)
            except Exception as e:
                logger.debug(f"[SEAMLESS-COMPAT] Lỗi callback WinEvent Foreground: {e}")

        self._winevent_proc = WINEVENTPROC(_minimize_proc)
        self._hook_handle = user32.SetWinEventHook(
            EVENT_SYSTEM_MINIMIZESTART,
            EVENT_SYSTEM_MINIMIZESTART,
            0,
            self._winevent_proc,
            0,
            0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS,
        )

        self._foreground_proc = WINEVENTPROC(_foreground_proc)
        self._foreground_hook_handle = user32.SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND,
            EVENT_SYSTEM_FOREGROUND,
            0,
            self._foreground_proc,
            0,
            0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS,
        )

        if self._hook_handle and self._foreground_hook_handle:
            logger.info("[SEAMLESS-COMPAT] Đã cài đặt hoàn tất các WinEventHook vòng đời trò chơi (Foreground & Anti-Minimize).")
        else:
            logger.warning("[SEAMLESS-COMPAT] Cài đặt WinEventHook một phần thất bại.")

    def install_anti_minimize_hook(self, target_hwnd_getter: Callable[[], int], is_active_getter: Callable[[], bool]):
        """Bảo toàn tính tương thích với lời gọi cũ"""
        self.install_lifecycle_hooks(target_hwnd_getter, is_active_getter)

    def uninstall_lifecycle_hooks(self):
        """Gỡ bỏ toàn bộ WinEventHook an toàn khi tắt ứng dụng"""
        if self._hook_handle:
            user32.UnhookWinEvent(self._hook_handle)
            self._hook_handle = None
            self._winevent_proc = None
        if self._foreground_hook_handle:
            user32.UnhookWinEvent(self._foreground_hook_handle)
            self._foreground_hook_handle = None
            self._foreground_proc = None
        logger.info("[SEAMLESS-COMPAT] Đã gỡ bỏ toàn bộ WinEventHook vòng đời trò chơi.")

    def uninstall_anti_minimize_hook(self):
        """Bảo toàn tính tương thích với lời gọi cũ"""
        self.uninstall_lifecycle_hooks()
