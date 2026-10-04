import subprocess
import ctypes
from ctypes import wintypes
from pathlib import Path
import comtypes
from core.logger import setup_logger

logger = setup_logger("VirtualKeyboard")

class ITipInvocation(comtypes.IUnknown):
    _iid_ = comtypes.GUID('{37c994e7-432b-4834-a2f7-dce1f13b834b}')
    _methods_ = [
        comtypes.COMMETHOD(
            [],
            comtypes.HRESULT,
            'Toggle',
            (['in'], wintypes.HWND, 'hwndDesktop')
        )
    ]

class VirtualKeyboardService:
    """
    Dịch vụ kích hoạt bàn phím ảo trên Windows Handheld (ITipInvocation / TabTip / OSK).
    """
    TABTIP_PATHS = [
        Path(r"C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe"),
        Path(r"C:\Program Files (x86)\Common Files\microsoft shared\ink\TabTip.exe")
    ]
    OSK_PATH = Path(r"C:\Windows\System32\osk.exe")

    @classmethod
    def toggle_keyboard(cls) -> bool:
        """Bật hoặc hiển thị bàn phím ảo."""
        # 1. Kích hoạt thông qua COM Interface ITipInvocation (Chuẩn Windows 10/11)
        try:
            comtypes.CoInitialize()
            ui_host = comtypes.CoCreateInstance(
                comtypes.GUID('{4ce576fa-83dc-4f88-951c-9d0782b4e376}'),
                interface=ITipInvocation,
                clsctx=comtypes.CLSCTX_INPROC_HANDLER | comtypes.CLSCTX_LOCAL_SERVER
            )
            windll = getattr(ctypes, "windll", None)
            hwnd = windll.user32.GetDesktopWindow() if windll else 0
            res = ui_host.Toggle(hwnd)
            if res == 0:
                logger.info("Đã kích hoạt bàn phím cảm ứng Windows qua ITipInvocation.")
                return True
        except Exception as e:
            logger.debug(f"Kích hoạt COM ITipInvocation không thành công: {e}. Thử fallback.")

        # 2. Fallback: ShellExecute TabTip.exe
        tabtip_path = next((p for p in cls.TABTIP_PATHS if p.exists()), None)
        if tabtip_path:
            try:
                windll = getattr(ctypes, "windll", None)
                if windll:
                    ret = windll.shell32.ShellExecuteW(
                        None,
                        "open",
                        str(tabtip_path),
                        None,
                        None,
                        1  # SW_SHOWNORMAL
                    )
                    if ret > 32:
                        logger.info("Đã kích hoạt TabTip qua ShellExecute.")
                        return True
            except Exception as e:
                logger.warning(f"Lỗi khi gọi ShellExecute TabTip: {e}")

        # 3. Fallback: Mở osk.exe
        try:
            if cls.OSK_PATH.exists():
                subprocess.Popen([str(cls.OSK_PATH)], shell=True)
                logger.info("Đã khởi chạy bàn phím ảo On-Screen Keyboard (osk.exe).")
                return True
        except Exception as e:
            logger.error(f"Không thể mở bàn phím ảo: {e}")

        return False
