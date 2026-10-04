import json
from pathlib import Path
from typing import Any, Dict

DEFAULT_CONFIG: Dict[str, Any] = {
    "overlay": {
        "width": 360,
        "animation_duration_ms": 220,
        "side": "right"
    },
    "hotkey": {
        "toggle_overlay": "ctrl+shift+q",
        "toggle_keyboard": "ctrl+shift+k"
    },
    "gamepad": {
        "enabled": True,
        "poll_interval_ms": 50,
        "toggle_combo": ["BACK", "RIGHT_SHOULDER"]
    },
    "hardware": {
        "tdp": {
            "min": 5,
            "max": 35,
            "step": 1,
            "current": 15
        },
        "fan": {
            "min": 0,
            "max": 100,
            "step": 5,
            "current": 50,
            "auto": True
        },
        "brightness": {
            "min": 0,
            "max": 100,
            "step": 5,
            "current": 70
        },
        "volume": {
            "min": 0,
            "max": 100,
            "step": 2,
            "current": 50
        }
    }
}

class ConfigManager:
    def __init__(self, config_file: str = "config.json"):
        self.config_path = Path(config_file)
        self.data: Dict[str, Any] = self._load()

    def _load(self) -> Dict[str, Any]:
        if self.config_path.exists():
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    return self._merge_defaults(data, DEFAULT_CONFIG)
            except Exception:
                return DEFAULT_CONFIG.copy()
        else:
            self._save(DEFAULT_CONFIG)
            return DEFAULT_CONFIG.copy()

    def _merge_defaults(self, source: Dict[str, Any], defaults: Dict[str, Any]) -> Dict[str, Any]:
        result = defaults.copy()
        for k, v in source.items():
            if k in result and isinstance(result[k], dict) and isinstance(v, dict):
                result[k] = self._merge_defaults(v, result[k])
            else:
                result[k] = v
        return result

    def get(self, key_path: str, default: Any = None) -> Any:
        keys = key_path.split(".")
        val = self.data
        for k in keys:
            if isinstance(val, dict) and k in val:
                val = val[k]
            else:
                return default
        return val

    def set(self, key_path: str, value: Any, save: bool = True) -> None:
        keys = key_path.split(".")
        current = self.data
        for k in keys[:-1]:
            if k not in current or not isinstance(current[k], dict):
                current[k] = {}
            current = current[k]
        current[keys[-1]] = value
        if save:
            self.save()

    def save(self) -> None:
        self._save(self.data)

    def _save(self, data: Dict[str, Any]) -> None:
        with open(self.config_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
