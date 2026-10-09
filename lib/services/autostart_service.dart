import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/logger.dart';

/// Dịch vụ quản lý khởi động cùng Windows (Auto-start on Windows Boot).
/// Do ứng dụng yêu cầu quyền Quản trị viên (Elevated/Administrator) để điều khiển Ring-0 TDP và Hook DXGI,
/// cơ chế Windows UAC sẽ âm thầm chặn Registry Run key thông thường.
/// Vì vậy, giải pháp tối ưu là tạo Scheduled Task với cờ `/RL HIGHEST` thông qua `schtasks.exe`.
class AutostartService extends ChangeNotifier {
  static const _logger = AppLogger('AutostartService');
  static const String _taskName = 'WindowsHandheldTool_AutoStart';

  static final AutostartService instance = AutostartService._();
  AutostartService._();

  ConfigManager? _config;
  bool _isEnabled = false;
  bool _isChecking = false;

  bool get isEnabled => _isEnabled;
  bool get isChecking => _isChecking;

  /// Khởi tạo dịch vụ và đồng bộ trạng thái ban đầu
  void init(ConfigManager config) {
    _config = config;
    _isEnabled = _config?.get('system.autostart', false) ?? false;
    checkStatus();
  }

  /// Kiểm tra trạng thái thực tế của tác vụ trong Windows Task Scheduler
  Future<bool> checkStatus() async {
    if (!Platform.isWindows) return false;

    _isChecking = true;
    notifyListeners();

    try {
      final result = await Process.run('schtasks', [
        '/query',
        '/tn',
        _taskName,
      ]);

      _isEnabled = (result.exitCode == 0);
      _config?.set('system.autostart', _isEnabled);
      _logger.info('Trạng thái khởi động cùng Windows: ${_isEnabled ? "Đang Bật" : "Đã Tắt"}');
    } catch (e) {
      _logger.error('Lỗi khi kiểm tra trạng thái Task Scheduler', e);
    } finally {
      _isChecking = false;
      notifyListeners();
    }

    return _isEnabled;
  }

  /// Bật hoặc tắt khởi động cùng Windows
  Future<bool> setEnabled(bool enable) async {
    if (!Platform.isWindows) return false;

    try {
      if (enable) {
        final exePath = Platform.resolvedExecutable;
        // Tạo tác vụ với quyền HIGHEST, kích hoạt khi đăng nhập người dùng (ONLOGON)
        final result = await Process.run('schtasks', [
          '/create',
          '/tn',
          _taskName,
          '/tr',
          '"$exePath"',
          '/sc',
          'onlogon',
          '/rl',
          'highest',
          '/f',
        ]);

        if (result.exitCode == 0) {
          _isEnabled = true;
          _config?.set('system.autostart', true);
          _logger.info('Đã bật khởi động cùng Windows thành công qua Task Scheduler');
          notifyListeners();
          return true;
        } else {
          _logger.error('Không thể tạo Task khởi động: ${result.stderr}');
          return false;
        }
      } else {
        // Xóa tác vụ khởi động
        final result = await Process.run('schtasks', [
          '/delete',
          '/tn',
          _taskName,
          '/f',
        ]);

        if (result.exitCode == 0 || result.exitCode == 1) {
          _isEnabled = false;
          _config?.set('system.autostart', false);
          _logger.info('Đã tắt khởi động cùng Windows');
          notifyListeners();
          return true;
        } else {
          _logger.error('Không thể xóa Task khởi động: ${result.stderr}');
          return false;
        }
      }
    } catch (e) {
      _logger.error('Lỗi khi thay đổi trạng thái khởi động cùng Windows', e);
      return false;
    }
  }

  /// Chuyển đổi trạng thái Bật / Tắt
  Future<bool> toggle() async {
    return setEnabled(!_isEnabled);
  }
}
