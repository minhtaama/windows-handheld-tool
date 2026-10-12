import 'dart:io';
import '../core/logger.dart';
import 'hardware_base.dart';

/// Bộ điều khiển độ sáng màn hình cho máy Handheld (WMI / PowerShell).
class BrightnessController extends HardwareController {
  static const _logger = AppLogger('BrightnessControl');
  int _currentBrightness = 70;

  BrightnessController({
    super.minVal = 0,
    super.maxVal = 100,
    super.step = 5,
    int defaultVal = 70,
  })  : _currentBrightness = defaultVal,
        super(
          name: "Độ sáng",
          unit: "%",
        );

  @override
  bool isAvailable() => true;

  @override
  int getValue() => _currentBrightness;

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentBrightness = target;

    try {
      final cmd =
          '(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods) | '
          'Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{Timeout=1; Brightness=$target}';

      Process.run('powershell', ['-NoProfile', '-Command', cmd]).then((result) {
        if (result.exitCode != 0) {
          _logger.warning('Lệnh đặt độ sáng PowerShell trả về mã lỗi ${result.exitCode}');
        }
      });
      return true;
    } catch (e) {
      _logger.error('Lỗi khi thiết lập độ sáng', e);
      return false;
    }
  }
}
