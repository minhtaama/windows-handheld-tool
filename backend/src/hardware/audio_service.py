from typing import Optional
from src.core.logger import setup_logger

logger = setup_logger("AudioService")

class AudioService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(AudioService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.endpoint_volume = None
        self._init_pycaw()
        self._initialized = True

    def _init_pycaw(self):
        try:
            from pycaw.pycaw import AudioUtilities
            speakers = AudioUtilities.GetSpeakers()
            if speakers and hasattr(speakers, "EndpointVolume"):
                self.endpoint_volume = speakers.EndpointVolume
                logger.info("Windows CoreAudio (pycaw EndpointVolume) kết nối thành công.")
            else:
                logger.warning("Không tìm thấy Audio EndpointVolume.")
        except Exception as e:
            logger.error(f"Lỗi khi khởi tạo pycaw: {e}")
            self.endpoint_volume = None

    def get_volume(self) -> int:
        if not self.endpoint_volume:
            self._init_pycaw()
        if not self.endpoint_volume:
            return 50
        try:
            scalar = self.endpoint_volume.GetMasterVolumeLevelScalar()
            return int(round(scalar * 100))
        except Exception as e:
            logger.error(f"Lỗi khi đọc âm lượng: {e}")
            self._init_pycaw()
            try:
                if self.endpoint_volume:
                    return int(round(self.endpoint_volume.GetMasterVolumeLevelScalar() * 100))
            except Exception:
                pass
            return 50

    def set_volume(self, percent: int) -> bool:
        percent = max(0, min(100, percent))
        if not self.endpoint_volume:
            self._init_pycaw()
        if not self.endpoint_volume:
            logger.info(f"[Mô phỏng] Đặt âm lượng = {percent}%")
            return True
        try:
            scalar = float(percent) / 100.0
            self.endpoint_volume.SetMasterVolumeLevelScalar(scalar, None)
            return True
        except Exception as e:
            logger.error(f"Lỗi khi đặt âm lượng: {e}")
            self._init_pycaw()
            try:
                if self.endpoint_volume:
                    scalar = float(percent) / 100.0
                    self.endpoint_volume.SetMasterVolumeLevelScalar(scalar, None)
                    return True
            except Exception:
                pass
            return False

    def is_muted(self) -> bool:
        if not self.endpoint_volume:
            self._init_pycaw()
        if not self.endpoint_volume:
            return False
        try:
            return bool(self.endpoint_volume.GetMute())
        except Exception:
            return False

    def toggle_mute(self) -> bool:
        if not self.endpoint_volume:
            self._init_pycaw()
        if not self.endpoint_volume:
            return False
        try:
            muted = self.is_muted()
            self.endpoint_volume.SetMute(int(not muted), None)
            return not muted
        except Exception as e:
            logger.error(f"Lỗi khi toggle mute: {e}")
            return False
