import json
import os
from typing import Any, Dict
from src.core.logger import setup_logger

logger = setup_logger("ConfigManager")

DEFAULT_CONFIG: Dict[str, Any] = {
    "overlay": {
        "width": 380,
        "width_percent": 45,
        "animation_duration_ms": 250,
        "side": "right",
        "scale_percent": 100,
        "scale": 1.0,
    },
    "hotkey": {
        "toggle_overlay": "Ctrl+Shift+Q",
        "toggle_keyboard": "Ctrl+Alt+K",
    },
    "gamepad": {
        "enabled": True,
        "poll_interval_ms": 50,
        "overlay_combo": "BACK+RB",
        "keyboard_combo": "",
    },
    "system": {
        "autostart": False,
    },
    "hardware": {
        "tdp": {
            "min": 5,
            "max": 35,
            "step": 1,
            "current": 15,
            "auto": False,
            "stapm": 15,
            "fast": 18,
            "slow": 15,
        },
        "fan": {
            "min": 0,
            "max": 100,
            "step": 5,
            "current": 50,
            "auto": True,
        },
        "brightness": {
            "min": 0,
            "max": 100,
            "step": 5,
            "current": 75,
        },
        "volume": {
            "min": 0,
            "max": 100,
            "step": 2,
            "current": 50,
        },
        "rtss": {
            "fps_limit": 60,
            "osd_enabled": True,
            "osd_zoom": 1,
            "osd_show_fps": True,
            "osd_show_tdp": True,
            "osd_show_cpu_temp": True,
            "osd_show_cpu_usage": True,
            "osd_show_ram": True,
            "osd_show_battery": True,
            "osd_show_fan": False,
            "osd_layout": "compact",
            "osd_position": "topLeft",
        },
    },
}

class ConfigManager:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(ConfigManager, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self, config_path: str = "config.json"):
        if self._initialized:
            return
        self.config_path = os.path.abspath(config_path)
        self.data: Dict[str, Any] = self._load_config()
        self._initialized = True

    def _deep_merge(self, base: dict, override: dict) -> dict:
        result = dict(base)
        for key, val in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(val, dict):
                result[key] = self._deep_merge(result[key], val)
            else:
                result[key] = val
        return result

    def _load_config(self) -> Dict[str, Any]:
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    content = json.load(f)
                    return self._deep_merge(DEFAULT_CONFIG, content)
            except Exception as e:
                logger.error(f"Lỗi khi đọc file config {self.config_path}: {e}")
        return dict(DEFAULT_CONFIG)

    def save(self) -> bool:
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self.data, f, indent=4, ensure_ascii=False)
            return True
        except Exception as e:
            logger.error(f"Lỗi khi lưu config: {e}")
            return False

    def get(self, *keys, default=None) -> Any:
        curr = self.data
        for k in keys:
            if isinstance(curr, dict) and k in curr:
                curr = curr[k]
            else:
                return default
        return curr

    def set(self, value: Any, *keys) -> None:
        if not keys:
            return
        curr = self.data
        for k in keys[:-1]:
            if k not in curr or not isinstance(curr[k], dict):
                curr[k] = {}
            curr = curr[k]
        curr[keys[-1]] = value
        self.save()
