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
      _logger.info('Windows autostart status: ${_isEnabled ? "Enabled" : "Disabled"}');
    } catch (e) {
      _logger.error('Error checking Task Scheduler status', e);
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
        final exeDir = File(exePath).parent.path;

        // Tạo tác vụ bằng PowerShell với đầy đủ thuộc tính:
        // 1. Cho phép chạy khi dùng nguồn PIN (AllowStartIfOnBatteries, DontStopIfGoingOnBatteries)
        // 2. Thiết lập thư mục làm việc (WorkingDirectory = exeDir) để nạp đúng config.json và driver
        // 3. Quyền hạn cao nhất (Highest) bỏ qua rào cản UAC khi đăng nhập (ONLOGON)
        final psCommand =
            "\$action = New-ScheduledTaskAction -Execute '$exePath' -WorkingDirectory '$exeDir'; "
            "\$trigger = New-ScheduledTaskTrigger -AtLogOn; "
            "\$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -Priority 4; "
            "\$principal = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive -RunLevel Highest; "
            "Register-ScheduledTask -TaskName '$_taskName' -Action \$action -Trigger \$trigger -Settings \$settings -Principal \$principal -Force;";

        final result = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          psCommand,
        ]);

        if (result.exitCode == 0) {
          _isEnabled = true;
          _config?.set('system.autostart', true);
          _logger.info('Enabled Windows autostart successfully via Task Scheduler (Battery-aware & Custom WorkingDir)');
          notifyListeners();
          return true;
        } else {
          _logger.warning('PowerShell Register-ScheduledTask error: ${result.stderr}, falling back to schtasks');
          final fallback = await Process.run('schtasks', [
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
          if (fallback.exitCode == 0) {
            _isEnabled = true;
            _config?.set('system.autostart', true);
            notifyListeners();
            return true;
          } else {
            _logger.error('Failed to create autostart Task: ${fallback.stderr}');
            return false;
          }
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
          _logger.info('Disabled Windows autostart');
          notifyListeners();
          return true;
        } else {
          _logger.error('Failed to delete autostart Task: ${result.stderr}');
          return false;
        }
      }
    } catch (e) {
      _logger.error('Error changing Windows autostart state', e);
      return false;
    }
  }

  /// Chuyển đổi trạng thái Bật / Tắt
  Future<bool> toggle() async {
    return setEnabled(!_isEnabled);
  }
}
