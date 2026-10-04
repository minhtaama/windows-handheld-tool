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
              'Đã tìm thấy màn hình cảm ứng: $_instanceId (Mô tả: "$desc", Trạng thái: ${_isEnabled ? "Bật" : "Tắt"})',
            );
            return;
          }
        }
      }
    } catch (e) {
      _logger.error('Lỗi khi quét màn hình cảm ứng qua pnputil', e);
    }

    // Fallback ID cho GPD Win 4 (chip Goodix) nếu không bắt được mô tả
    if (!_isDetected) {
      _instanceId = r'HID\GDIX1002\4&231bac70&0&0000';
      _isDetected = true;
      _logger.info('Sử dụng Fallback Touchscreen ID: $_instanceId');
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
        _logger.warning('Không tìm thấy thiết bị màn hình cảm ứng trên máy.');
        return false;
      }
    }

    final actionFlag = enable ? '/enable-device' : '/disable-device';
    _logger.info('Đang thực thi pnputil $actionFlag "$_instanceId"...');

    try {
      final result = await Process.run('pnputil', [actionFlag, _instanceId!]);
      if (result.exitCode == 0) {
        _isEnabled = enable;
        _logger.info('Đã ${enable ? "BẬT" : "TẮT"} màn hình cảm ứng thành công.');
        return true;
      } else {
        _logger.warning(
          'Không thể ${enable ? "bật" : "tắt"} cảm ứng (ExitCode: ${result.exitCode}). '
          'Stderr: ${result.stderr.toString().trim()}. '
          'Yêu cầu chạy ứng dụng với quyền Administrator để thay đổi driver phần cứng.',
        );
        return false;
      }
    } catch (e) {
      _logger.error('Lỗi khi thực thi pnputil', e);
      return false;
    }
  }
}
