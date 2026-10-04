from core.logger import setup_logger
from .base import HardwareController

logger = setup_logger("AudioControl")

class AudioController(HardwareController):
    def __init__(self, min_val: int = 0, max_val: int = 100, step: int = 2):
        super().__init__(name="Âm lượng", min_val=min_val, max_val=max_val, step=step, unit="%")
        self._volume_endpoint = None
        self._init_endpoint()

    def _init_endpoint(self) -> None:
        try:
            from pycaw.pycaw import AudioUtilities
            speakers = AudioUtilities.GetSpeakers()
            if speakers and hasattr(speakers, "EndpointVolume"):
                self._volume_endpoint = speakers.EndpointVolume
        except Exception as e:
            logger.warning(f"Không thể khởi tạo Core Audio Endpoint: {e}")
            self._volume_endpoint = None

    def is_available(self) -> bool:
        return self._volume_endpoint is not None

    def get_value(self) -> int:
        if not self._volume_endpoint:
            self._init_endpoint()
        if self._volume_endpoint:
            try:
                scalar = self._volume_endpoint.GetMasterVolumeLevelScalar()
                return int(round(scalar * 100))
            except Exception as e:
                logger.debug(f"Lỗi khi đọc âm lượng: {e}")
        return 50

    def set_value(self, value: int) -> bool:
        target = self.clamp(value)
        if not self._volume_endpoint:
            self._init_endpoint()
        if self._volume_endpoint:
            try:
                scalar = float(target) / 100.0
                self._volume_endpoint.SetMasterVolumeLevelScalar(scalar, None)
                return True
            except Exception as e:
                logger.warning(f"Lỗi khi thiết lập âm lượng: {e}")
                return False
        return False

    def is_muted(self) -> bool:
        if self._volume_endpoint:
            try:
                return bool(self._volume_endpoint.GetMute())
            except Exception:
                pass
        return False

    def set_mute(self, mute: bool) -> bool:
        if self._volume_endpoint:
            try:
                self._volume_endpoint.SetMute(1 if mute else 0, None)
                return True
            except Exception as e:
                logger.warning(f"Lỗi khi tắt/bật tiếng: {e}")
        return False
