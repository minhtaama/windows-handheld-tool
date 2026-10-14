import '../core/logger.dart';
import '../services/bridge_service.dart';
import 'hardware_base.dart';

/// Bộ điều khiển độ sáng màn hình cho máy Handheld thông qua BridgeService.
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
        ) {
    _currentBrightness = BridgeService.instance.brightness.value;
    BridgeService.instance.brightness.addListener(() {
      _currentBrightness = BridgeService.instance.brightness.value;
    });
  }

  @override
  bool isAvailable() => true;

  @override
  int getValue() => _currentBrightness;

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentBrightness = target;
    BridgeService.instance.setBrightness(target);
    _logger.info('Đã thiết lập độ sáng: $target%');
    return true;
  }
}
