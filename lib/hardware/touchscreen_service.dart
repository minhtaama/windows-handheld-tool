import 'dart:io';
import '../core/logger.dart';

/// Dịch vụ quản lý bật/tắt màn hình cảm ứng (Touchscreen) trên thiết bị Handheld Windows.
/// Tự động dò tìm mã phần cứng (Instance ID) của thiết bị HID Touch Screen và dùng pnputil để bật/tắt.
class TouchscreenService {
  static const _logger = AppLogger('TouchscreenService');
  static String? _instanceId;
  static bool _isEnabled = true;
  static bool _isDetected = false;

  static bool get isEnabled => _isEnabled;
  static bool get isDetected => _isDetected;
  static String? get instanceId => _instanceId;

  /// Quét tìm thiết bị màn hình cảm ứng trong hệ thống qua pnputil.
  static Future<void> init() async {
    try {
      final result = await Process.run('pnputil', [
        '/enum-devices',
        '/class',
        'HIDClass',
      ]);

      if (result.exitCode == 0) {
        final content = result.stdout.toString();
        final blocks = content.split(RegExp(r'\r?\n\r?\n'));

        for (final block in blocks) {
          final lines = block.split(RegExp(r'\r?\n'));
          String? currentId;
          String? desc;
          String? status;

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('Instance ID:')) {
              currentId = trimmed.replaceFirst('Instance ID:', '').trim();
            } else if (trimmed.startsWith('Device Description:')) {
              desc = trimmed.replaceFirst('Device Description:', '').trim();
            } else if (trimmed.startsWith('Status:')) {
              status = trimmed.replaceFirst('Status:', '').trim();
            }
          }

          if (desc != null &&
              (desc.toLowerCase().contains('touch screen') ||
                  desc.toLowerCase().contains('touchscreen'))) {
            _instanceId = currentId;
            _isEnabled = status?.toLowerCase().contains('started') ?? true;
            _isDetected = true;
            _logger.info(
              'Found touchscreen device: $_instanceId (Description: "$desc", Status: ${_isEnabled ? "Enabled" : "Disabled"})',
            );
            return;
          }
        }
      }
    } catch (e) {
      _logger.error('Error scanning touchscreen devices via pnputil', e);
    }

    // Fallback ID cho GPD Win 4 (chip Goodix) nếu không bắt được mô tả
    if (!_isDetected) {
      _instanceId = r'HID\GDIX1002\4&231bac70&0&0000';
      _isDetected = true;
      _logger.info('Using fallback touchscreen ID: $_instanceId');
    }
  }

  /// Đảo trạng thái Bật / Tắt của màn hình cảm ứng.
  static Future<bool> toggleTouchscreen() async {
    return await setTouchscreen(!_isEnabled);
  }

  /// Bật hoặc Tắt màn hình cảm ứng.
  /// Lưu ý: Yêu cầu ứng dụng chạy dưới quyền Administrator trên Windows.
  static Future<bool> setTouchscreen(bool enable) async {
    if (_instanceId == null) {
      await init();
      if (_instanceId == null) {
        _logger.warning('No touchscreen device found on system.');
        return false;
      }
    }

    final actionFlag = enable ? '/enable-device' : '/disable-device';
    _logger.info('Executing pnputil $actionFlag "$_instanceId"...');

    try {
      final result = await Process.run('pnputil', [actionFlag, _instanceId!]);
      if (result.exitCode == 0) {
        _isEnabled = enable;
        _logger.info('${enable ? "ENABLED" : "DISABLED"} touchscreen successfully.');
        return true;
      } else {
        _logger.warning(
          'Failed to ${enable ? "enable" : "disable"} touchscreen (ExitCode: ${result.exitCode}). '
          'Stderr: ${result.stderr.toString().trim()}. '
          'Requires running application with Administrator privileges to modify hardware drivers.',
        );
        return false;
      }
    } catch (e) {
      _logger.error('Error executing pnputil', e);
      return false;
    }
  }
}
