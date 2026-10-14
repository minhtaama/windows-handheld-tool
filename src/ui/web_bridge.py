import json
from PySide6.QtCore import QObject, Signal, Slot, QTimer
from src.core.config import ConfigManager
from src.hardware.tdp_service import TdpService
from src.hardware.fan_service import FanService
from src.hardware.audio_service import AudioService
from src.hardware.brightness_service import BrightnessService
from src.hardware.touchscreen_service import TouchscreenService
from src.hardware.rtss_service import RtssService
from src.services.system_telemetry import SystemTelemetryService
from src.services.virtual_keyboard import VirtualKeyboardService
from src.services.autostart_service import AutostartService
from src.core.logger import setup_logger

logger = setup_logger("WebBridge")

class WebBridge(QObject):
    # Signals sent to React frontend
    telemetryUpdated = Signal(str)
    configUpdated = Signal(str)
    overlayVisibilityChanged = Signal(bool)

    # Signals to Main Window / Controller
    requestClose = Signal()
    requestWidthChange = Signal(int)
    requestScaleChange = Signal(float)
    requestBringToFront = Signal()
    requestExitApp = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.config = ConfigManager()
        self.tdp_svc = TdpService()
        self.fan_svc = FanService()
        self.audio_svc = AudioService()
        self.bright_svc = BrightnessService()
        self.touch_svc = TouchscreenService()
        self.rtss_svc = RtssService()
        self.telemetry_svc = SystemTelemetryService()

        # Telemetry timer pushing real-time hardware data to JS at 1000ms
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._push_telemetry)
        self.timer.start(1000)

    def _push_telemetry(self):
        try:
            snap = self.telemetry_svc.get_snapshot()
            snap["is_touch_enabled"] = self.touch_svc.is_enabled
            snap["is_fan_auto"] = self.fan_svc.is_auto
            snap["fan_speed"] = self.fan_svc.get_speed()
            snap["volume"] = self.audio_svc.get_volume()
            snap["is_muted"] = self.audio_svc.is_muted()
            snap["brightness"] = self.bright_svc.get_brightness()
            self.telemetryUpdated.emit(json.dumps(snap))
        except Exception as e:
            logger.error(f"Lỗi khi gửi telemetry sang JS: {e}")

    @Slot(result=str)
    def getInitialState(self) -> str:
        """Trả về toàn bộ trạng thái cấu hình và cảm biến ban đầu dưới dạng JSON"""
        try:
            state = {
                "config": self.config.data,
                "telemetry": self.telemetry_svc.get_snapshot(),
                "hardware": {
                    "tdp": self.config.get("hardware", "tdp", "current", default=15),
                    "fan": self.fan_svc.get_speed(),
                    "fan_auto": self.fan_svc.is_auto,
                    "volume": self.audio_svc.get_volume(),
                    "is_muted": self.audio_svc.is_muted(),
                    "brightness": self.bright_svc.get_brightness(),
                    "touch_enabled": self.touch_svc.is_enabled,
                    "autostart": AutostartService.is_enabled(),
                }
            }
            return json.dumps(state)
        except Exception as e:
            logger.error(f"Lỗi getInitialState: {e}")
            return "{}"

    @Slot(int)
    def setTdp(self, watts: int):
        watts = max(5, min(35, watts))
        self.tdp_svc.set_tdp(watts)
        self.config.set(watts, "hardware", "tdp", "current")
        logger.info(f"[Bridge] Đặt TDP: {watts}W")

    @Slot(int, bool)
    def setFan(self, percent: int, is_auto: bool):
        if is_auto:
            self.fan_svc.set_auto(True)
        else:
            self.fan_svc.set_speed(percent)
        self.config.set(percent, "hardware", "fan", "current")
        self.config.set(is_auto, "hardware", "fan", "auto")

    @Slot(int)
    def setVolume(self, percent: int):
        self.audio_svc.set_volume(percent)
        self.config.set(percent, "hardware", "volume", "current")

    @Slot(result=bool)
    def toggleMute(self) -> bool:
        return self.audio_svc.toggle_mute()

    @Slot(int)
    def setBrightness(self, percent: int):
        self.bright_svc.set_brightness(percent)
        self.config.set(percent, "hardware", "brightness", "current")

    @Slot(result=bool)
    def toggleTouchscreen(self) -> bool:
        new_val = self.touch_svc.toggle()
        return self.touch_svc.is_enabled

    @Slot()
    def toggleVirtualKeyboard(self):
        VirtualKeyboardService.toggle_keyboard()

    @Slot(int)
    def setFpsLimit(self, limit: int):
        self.rtss_svc.set_fps_limit(limit)
        self.config.set(limit, "hardware", "rtss", "fps_limit")

    @Slot(str)
    def updateOsdText(self, text: str):
        self.rtss_svc.update_osd(text)

    @Slot()
    def clearOsdText(self):
        self.rtss_svc.clear_osd()

    @Slot(str, bool)
    def setOsdMetric(self, metric_key: str, enabled: bool):
        self.config.set(enabled, "hardware", "rtss", f"osd_show_{metric_key}")

    @Slot(int)
    def setPanelWidth(self, width: int):
        if width <= 100:
            self.config.set(width, "overlay", "width_percent")
        else:
            self.config.set(width, "overlay", "width")
        self.requestWidthChange.emit(width)

    @Slot(float)
    def setPanelScale(self, scale: float):
        self.config.set(scale, "overlay", "scale")
        self.requestScaleChange.emit(scale)

    @Slot(str, str)
    def setHotkey(self, target: str, hotkey: str):
        """target: 'overlay' hoặc 'keyboard'"""
        from src.input.hotkey_service import HotkeyService
        hotkey_svc = HotkeyService()
        if target == "overlay":
            self.config.set(hotkey, "hotkey", "toggle_overlay")
            hotkey_svc.update_hotkeys(overlay_hk=hotkey)
            logger.info(f"Đã cập nhật phím tắt Overlay: {hotkey}")
        elif target == "keyboard":
            self.config.set(hotkey, "hotkey", "toggle_keyboard")
            hotkey_svc.update_hotkeys(keyboard_hk=hotkey)
            logger.info(f"Đã cập nhật phím tắt Bàn phím ảo: {hotkey}")

    @Slot(bool)
    def setAutostart(self, enabled: bool):
        AutostartService.set_enabled(enabled)
        self.config.set(enabled, "system", "autostart")

    @Slot()
    def bringToFront(self):
        self.requestBringToFront.emit()

    @Slot()
    def closeOverlay(self):
        self.requestClose.emit()

    @Slot()
    def exitApp(self):
        self.requestExitApp.emit()
