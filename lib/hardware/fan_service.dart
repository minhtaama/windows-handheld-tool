import '../core/logger.dart';
import '../services/bridge_service.dart';
import 'hardware_base.dart';

/// Bộ điều khiển quạt tản nhiệt cho máy Handheld thông qua BridgeService.
class FanController extends HardwareController {
  static const _logger = AppLogger('FanControl');

  int _currentSpeed;

  FanController({
    super.minVal = 0,
    super.maxVal = 100,
    super.step = 5,
    int defaultVal = 50,
  })  : _currentSpeed = defaultVal,
        super(
          name: "Tốc độ quạt",
          unit: "%",
        ) {
    _currentSpeed = BridgeService.instance.fanSpeed.value;
    BridgeService.instance.fanSpeed.addListener(() {
      _currentSpeed = BridgeService.instance.fanSpeed.value;
    });
  }

  @override
  bool isAvailable() => true;

  bool isAuto() => BridgeService.instance.isFanAuto.value;

  bool setAuto(bool auto) {
    BridgeService.instance.setFan(_currentSpeed, auto);
    _logger.info('Đã chuyển chế độ quạt: ${auto ? 'Tự động (Auto)' : 'Thủ công (Manual)'}');
    return true;
  }

  @override
  int getValue() => _currentSpeed;

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentSpeed = target;
    BridgeService.instance.setFan(target, false);
    _logger.info('Đã thiết lập tốc độ quạt: $target%');
    return true;
  }
}
