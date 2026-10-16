import os
import time
import winreg
import subprocess
import ctypes
from ctypes import wintypes
from src.core.logger import setup_logger

logger = setup_logger("VirtualKeyboard")

class GUID(ctypes.Structure):
    _fields_ = [
        ("Data1", ctypes.c_ulong),
        ("Data2", ctypes.c_ushort),
        ("Data3", ctypes.c_ushort),
        ("Data4", ctypes.c_ubyte * 8),
    ]

class RECT(ctypes.Structure):
    _fields_ = [
        ("left", ctypes.c_long),
        ("top", ctypes.c_long),
        ("right", ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]

# CLSID & IID cho ITipInvocation (Toggle Touch Keyboard)
CLSID_UIHostNoLaunch = GUID(
    0x4CE576FA, 0x83DC, 0x4F88,
    (ctypes.c_ubyte * 8)(0x95, 0x1C, 0x9D, 0x07, 0x82, 0xB4, 0xE3, 0x76)
)
IID_ITipInvocation = GUID(
    0x37C994E7, 0x432B, 0x4834,
    (ctypes.c_ubyte * 8)(0xA2, 0xF7, 0xDC, 0xE1, 0xF1, 0x3B, 0x83, 0x4B)
)

# CLSID & IID cho IFrameworkInputPane (Query Touch Keyboard Screen Location)
CLSID_FrameworkInputPane = GUID(
    0xD5120AA3, 0x46BA, 0x44C5,
    (ctypes.c_ubyte * 8)(0x82, 0x2D, 0xCA, 0x80, 0x92, 0xC1, 0xFC, 0x72)
)
IID_IFrameworkInputPane = GUID(
    0x5752238B, 0x24F0, 0x495A,
    (ctypes.c_ubyte * 8)(0x82, 0xF1, 0x2F, 0xD5, 0x93, 0x05, 0x67, 0x96)
)

user32 = ctypes.windll.user32
user32.GetDesktopWindow.argtypes = []
user32.GetDesktopWindow.restype = wintypes.HWND
user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
user32.GetAsyncKeyState.restype = ctypes.c_short

class VirtualKeyboardService:
    _last_toggle_time = 0.0
    _assumed_open = False

    @staticmethod
    def ensure_registry_settings():
        """Thiết lập Registry vô hiệu hóa tính năng tự động mở lại bàn phím ảo (AutoInvoke) của Windows."""
        try:
            # 1. Tắt Auto-Invoke trong TabletTip (Tránh Windows tự bật lại bàn phím khi mất focus hoặc khi vừa đóng)
            key_path = r"Software\Microsoft\TabletTip\1.7"
            try:
                with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_SET_VALUE) as key:
                    winreg.SetValueEx(key, "EnableDesktopModeAutoInvoke", 0, winreg.REG_DWORD, 0)
            except Exception as e:
                logger.warning(f"Lỗi khi cấu hình TabletTip\\1.7: {e}")

            # 2. Tắt Auto-Invoke trong TouchKeyboard của Windows Explorer
            exp_path = r"Software\Microsoft\Windows\CurrentVersion\Explorer\TouchKeyboard"
            try:
                with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, exp_path, 0, winreg.KEY_SET_VALUE) as key:
                    winreg.SetValueEx(key, "TouchKeyboardAutoInvokeDesktopMode", 0, winreg.REG_DWORD, 0)
            except Exception as e:
                logger.warning(f"Lỗi khi cấu hình Explorer\\TouchKeyboard: {e}")

            logger.info("Đã cấu hình Registry: Vô hiệu hóa triệt để cơ chế Auto-Invoke tự động mở lại bàn phím ảo.")
        except Exception as e:
            logger.warning(f"Lỗi khi dọn dẹp Registry TouchKeyboard: {e}")

    @staticmethod
    def is_keyboard_visible():
        """Kiểm tra xem bàn phím ảo Windows Touch Keyboard có đang thực sự hiển thị trên màn hình hay không.
        Trả về True nếu hiển thị, False nếu đã ẩn, None nếu không thể truy vấn COM."""
        try:
            ole32 = ctypes.windll.ole32
            ole32.CoInitialize(None)

            p_pane = ctypes.c_void_p()
            hr = ole32.CoCreateInstance(
                ctypes.byref(CLSID_FrameworkInputPane),
                None,
                1,  # CLSCTX_INPROC_SERVER
                ctypes.byref(IID_IFrameworkInputPane),
                ctypes.byref(p_pane),
            )

            if hr == 0 and p_pane.value:
                vtable = ctypes.cast(p_pane, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
                # vtable: [0] QI, [1] AddRef, [2] Release, [3] Advise, [4] AdviseWithHWND, [5] Unadvise, [6] Location
                LocationFunc = ctypes.WINFUNCTYPE(ctypes.c_long, ctypes.c_void_p, ctypes.POINTER(RECT))
                loc_func = LocationFunc(vtable[6])

                rc = RECT()
                hr_loc = loc_func(p_pane, ctypes.byref(rc))

                ReleaseFunc = ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)
                ReleaseFunc(vtable[2])(p_pane)
                ole32.CoUninitialize()

                if hr_loc == 0:
                    width = rc.right - rc.left
                    height = rc.bottom - rc.top
                    return (width > 0 and height > 0)
        except Exception as e:
            logger.warning(f"Lỗi khi kiểm tra IFrameworkInputPane::Location: {e}")

        return None

    @staticmethod
    def _wait_for_keys_up(timeout_ms: int = 800):
        """Chờ cho đến khi người dùng nhấc ngón tay ra khỏi toàn bộ phím phần cứng (Ctrl, Alt, Shift, Win...)."""
        user32 = ctypes.windll.user32
        # Mã phím ảo: Ctrl (0x11), Alt (0x12), Shift (0x10), LWin (0x5B), RWin (0x5C)
        modifier_vks = [0x11, 0x12, 0x10, 0x5B, 0x5C]
        start_time = time.time()

        was_pressed = False
        for vk in modifier_vks:
            if user32.GetAsyncKeyState(vk) & 0x8000:
                was_pressed = True
                break

        if was_pressed:
            logger.info("Phát hiện phím vật lý đang được giữ. Đang chờ người dùng nhấc tay...")
            while (time.time() - start_time) * 1000 < timeout_ms:
                still_pressed = False
                for vk in modifier_vks:
                    if user32.GetAsyncKeyState(vk) & 0x8000:
                        still_pressed = True
                        break
                if not still_pressed:
                    break
                time.sleep(0.02)
            # Nghỉ thêm 150ms để toàn bộ hàng đợi thông điệp WM_KEYUP của Windows được xả sạch hoàn toàn
            time.sleep(0.15)
            logger.info("Người dùng đã nhấc tay khỏi bàn phím vật lý.")

    @staticmethod
    def _direct_toggle() -> bool:
        """Gọi trực tiếp ITipInvocation::Toggle để đảo trạng thái bàn phím ảo."""
        try:
            ole32 = ctypes.windll.ole32
            ole32.CoInitialize(None)

            p_tip = ctypes.c_void_p()
            hr = ole32.CoCreateInstance(
                ctypes.byref(CLSID_UIHostNoLaunch),
                None,
                1 | 4,  # CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER
                ctypes.byref(IID_ITipInvocation),
                ctypes.byref(p_tip),
            )

            if hr == 0 and p_tip.value:
                vtable = ctypes.cast(p_tip, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
                toggle_func_ptr = vtable[3]
                ToggleFunc = ctypes.WINFUNCTYPE(ctypes.c_long, ctypes.c_void_p, wintypes.HWND)
                toggle = ToggleFunc(toggle_func_ptr)

                desktop_hwnd = ctypes.windll.user32.GetDesktopWindow()
                hr_toggle = toggle(p_tip, desktop_hwnd)

                release_func_ptr = vtable[2]
                ReleaseFunc = ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)
                ReleaseFunc(release_func_ptr)(p_tip)
                ole32.CoUninitialize()

                if hr_toggle == 0:
                    return True
        except Exception as e:
            logger.warning(f"Lỗi gọi ITipInvocation: {e}")

        # Fallback 1: Thử kích hoạt qua Shell AppsFolder protocol
        try:
            ctypes.windll.shell32.ShellExecuteW(
                None,
                "open",
                "explorer.exe",
                r"shell:AppsFolder\Windows.Shell.InputApp_cw5n1h2txyewy!App",
                None,
                1,
            )
            return True
        except Exception as e:
            logger.warning(f"Lỗi kích hoạt Shell InputApp: {e}")

        # Fallback 2: Thử mở trực tiếp osk.exe
        try:
            osk_path = r"C:\Windows\System32\osk.exe"
            if os.path.isfile(osk_path):
                ctypes.windll.shell32.ShellExecuteW(None, "open", osk_path, None, None, 1)
                return True
        except Exception as e:
            logger.error(f"Lỗi khi fallback mở osk.exe: {e}")

        return False

    @staticmethod
    def toggle_keyboard():
        """Bật / Tắt bàn phím ảo Windows Touch Keyboard với phân tách luồng Mở và Đóng thông minh."""
        now = time.time()
        if now - VirtualKeyboardService._last_toggle_time < 0.5:
            logger.info("Bỏ qua lệnh toggle lặp do debounce (< 0.5s).")
            return True
        VirtualKeyboardService._last_toggle_time = now

        # Kiểm tra trạng thái hiển thị thực tế của bàn phím ảo từ Windows COM
        is_visible = VirtualKeyboardService.is_keyboard_visible()
        if is_visible is None:
            should_close = VirtualKeyboardService._assumed_open
        else:
            should_close = is_visible

        if should_close:
            logger.info("Phát hiện bàn phím ảo đang mở. Thực thi luồng ĐÓNG bàn phím...")
            # Gọi đóng bàn phím ảo ngay lập tức
            VirtualKeyboardService._direct_toggle()

            # Chờ người dùng nhấc tay ra khỏi các phím vật lý để xả sạch thông điệp
            VirtualKeyboardService._wait_for_keys_up()

            # Cập nhật trạng thái và kết thúc mà TUYỆT ĐỐI không gọi lệnh Toggle nào nữa
            VirtualKeyboardService._assumed_open = False
            VirtualKeyboardService._last_toggle_time = time.time()
            logger.info("Đã đóng bàn phím ảo thành công và duy trì trạng thái đóng.")
            return True
        else:
            logger.info("Phát hiện bàn phím ảo đang đóng. Thực thi luồng MỞ bàn phím...")
            # Chờ người dùng nhấc tay khỏi bàn phím vật lý trước khi mở để tránh Windows nhận KEYUP rồi tự đóng
            VirtualKeyboardService._wait_for_keys_up()

            # Gọi mở bàn phím ảo khi tay đã nhấc ra an toàn
            success = VirtualKeyboardService._direct_toggle()
            VirtualKeyboardService._assumed_open = True
            VirtualKeyboardService._last_toggle_time = time.time()
            logger.info("Đã mở bàn phím ảo thành công và duy trì hiển thị trên màn hình.")
            return success
