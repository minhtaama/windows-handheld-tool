import '../core/logger.dart';
import '../services/bridge_service.dart';
import 'hardware_base.dart';

/// Bộ điều khiển âm lượng hệ thống cho máy Handheld thông qua BridgeService.
class AudioController extends HardwareController {
  static const _logger = AppLogger('AudioControl');
  int _currentVolume = 50;

  AudioController({
    super.minVal = 0,
    super.maxVal = 100,
    super.step = 2,
    int defaultVal = 50,
  })  : _currentVolume = defaultVal,
        super(
          name: "Âm lượng",
          unit: "%",
        ) {
    _currentVolume = BridgeService.instance.volume.value;
    BridgeService.instance.volume.addListener(() {
      _currentVolume = BridgeService.instance.volume.value;
    });
  }

  @override
  bool isAvailable() => true;

  @override
  int getValue() => _currentVolume;

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentVolume = target;
    BridgeService.instance.setVolume(target);
    _logger.info('Đã thiết lập âm lượng: $target%');
    return true;
  }
}
