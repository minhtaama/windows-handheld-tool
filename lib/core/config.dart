import 'dart:convert';
import 'dart:io';
import 'logger.dart';

/// Quản lý cấu hình đọc và lưu file config.json cho ứng dụng.
class ConfigManager {
  static const _logger = AppLogger('ConfigManager');
  final String filePath;
  Map<String, dynamic> _data = {};

  ConfigManager({this.filePath = 'config.json'}) {
    load();
  }

  void load() {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        _data = jsonDecode(content) as Map<String, dynamic>;
        _logger.info('Loaded configuration successfully from $filePath');
      } else {
        _logger.warning('$filePath not found, using default configuration.');
        _data = _defaultConfig();
        save();
      }
    } catch (e) {
      _logger.error('Error reading config file, using defaults', e);
      _data = _defaultConfig();
    }
  }

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
    save();
  }

  void save() {
    try {
      final file = File(filePath);
      const encoder = JsonEncoder.withIndent('    ');
      file.writeAsStringSync(encoder.convert(_data));
    } catch (e) {
      _logger.error('Error saving configuration', e);
    }
  }

  Map<String, dynamic> _defaultConfig() => {
        "overlay": {
          "width": 360,
          "width_percent": 35,
          "animation_duration_ms": 220,
          "side": "right",
        },
        "hotkey": {
          "toggle_overlay": "ctrl+shift+q",
          "toggle_keyboard": "ctrl+shift+k",
        },
        "gamepad": {
          "enabled": true,
          "poll_interval_ms": 50,
          "toggle_combo": ["BACK", "RIGHT_SHOULDER"],
        },
        "dxgi_hook": {
          "enabled": true,
          "auto_borderless": true,
        },
        "hardware": {
          "tdp": {"min": 5, "max": 35, "step": 1, "current": 15},
          "fan": {"min": 0, "max": 100, "step": 5, "current": 50, "auto": true},
          "brightness": {"min": 0, "max": 100, "step": 5, "current": 70},
          "audio": {"min": 0, "max": 100, "step": 2, "current": 50},
        },
      };
}
