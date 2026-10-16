import '../services/bridge_service.dart';
import '../services/overlay_controller.dart';

/// Quản lý cấu hình đọc và lưu cho ứng dụng trong môi trường Web.
class ConfigManager {
  final String filePath;
  Map<String, dynamic> _data = {};

  ConfigManager({this.filePath = 'config.json'}) {
    _data = _defaultConfig();
    BridgeService.instance.config.addListener(() {
      if (BridgeService.instance.config.value.isNotEmpty) {
        _data = Map<String, dynamic>.from(BridgeService.instance.config.value);
        OverlayController.instance.notifyListeners();
      }
    });
  }

  void load() {}

  T get<T>(String dotKey, T defaultValue) {
    final keys = dotKey.split('.');
    dynamic current = _data;
    for (final key in keys) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return defaultValue;
      }
    }
    if (current is T) {
      return current;
    }
    // Chuyển đổi an toàn số nguyên/thực
    if (T == int && current is num) {
      return current.toInt() as T;
    }
    if (T == double && current is num) {
      return current.toDouble() as T;
    }
    return defaultValue;
  }

  void set(String dotKey, dynamic value) {
    final keys = dotKey.split('.');
    Map<String, dynamic> current = _data;
    for (int i = 0; i < keys.length - 1; i++) {
      final k = keys[i];
      if (!current.containsKey(k) || current[k] is! Map<String, dynamic>) {
        current[k] = <String, dynamic>{};
      }
      current = current[k] as Map<String, dynamic>;
    }
    current[keys.last] = value;
  }

  void save() {}

  Map<String, dynamic> _defaultConfig() => {
        "overlay": {
          "width": 360,
          "width_percent": 35,
          "scale": 1.0,
          "animation_duration_ms": 220,
          "side": "right",
        },
        "hotkey": {
          "toggle_overlay": "Ctrl+Shift+Q",
          "toggle_keyboard": "Ctrl+Alt+K",
        },
        "gamepad": {
          "enabled": true,
          "poll_interval_ms": 50,
          "overlay_combo": "",
          "keyboard_combo": "",
        },
        "hardware": {
          "tdp": {"min": 5, "max": 35, "step": 1, "current": 15},
          "fan": {"min": 0, "max": 100, "step": 5, "current": 50, "auto": true},
          "brightness": {"min": 0, "max": 100, "step": 5, "current": 70},
          "audio": {"min": 0, "max": 100, "step": 2, "current": 50},
          "rtss": {
            "fps_limit": 60,
            "osd_show_fps": true,
            "osd_show_tdp": true,
            "osd_show_cpu_temp": true,
            "osd_show_cpu_usage": true,
            "osd_show_ram": true,
            "osd_show_battery": true,
          }
        },
        "system": {
          "autostart": false,
        }
      };
}
