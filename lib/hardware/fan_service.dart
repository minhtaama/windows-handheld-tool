import '../core/logger.dart';
import 'hardware_base.dart';

/// Bộ điều khiển quạt tản nhiệt cho máy Handheld (ROG Ally, Legion Go, GPD Win 4).
class FanController extends HardwareController {
  static const _logger = AppLogger('FanControl');

  int _currentSpeed;
  bool _isAutoMode = true;
  final bool _isHardwareDetected = false;

  FanController({
    super.minVal = 0,
    super.maxVal = 100,
    super.step = 5,
    int defaultVal = 50,
  })  : _currentSpeed = defaultVal,
        super(
          name: "Tốc độ quạt",
          unit: "%",
        );

  @override
  bool isAvailable() => _isHardwareDetected;

  bool isAuto() => _isAutoMode;

  bool setAuto(bool auto) {
    _isAutoMode = auto;
    _logger.info('Đã chuyển chế độ quạt: ${auto ? 'Tự động (Auto)' : 'Thủ công (Manual)'}');
    return true;
  }

  @override
  int getValue() => _currentSpeed;

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentSpeed = target;
    _isAutoMode = false;

    if (_isHardwareDetected) {
      _logger.info('Đã gửi lệnh điều khiển quạt phần cứng: $target%');
      return true;
    }

    _logger.info('Đã thiết lập tốc độ quạt (Mô phỏng): $target%');
    return true;
  }
}
