import '../core/logger.dart';
import '../services/bridge_service.dart';
import '../services/system_telemetry_service.dart';
import 'hardware_base.dart';

/// Điều khiển TDP cho CPU/APU Handheld (AMD APU) thông qua BridgeService.
class TdpController extends HardwareController {
  static const _logger = AppLogger('TdpControl');

  int _currentTdp;

  TdpController({
    super.minVal = 5,
    super.maxVal = 35,
    super.step = 1,
    int defaultVal = 15,
  })  : _currentTdp = defaultVal,
        super(
          name: "TDP",
          unit: "W",
        ) {
    _currentTdp = BridgeService.instance.tdp.value;
    BridgeService.instance.tdp.addListener(() {
      _currentTdp = BridgeService.instance.tdp.value;
    });
  }

  @override
  bool isAvailable() => true;

  @override
  int getValue() => _currentTdp;

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentTdp = target;
    BridgeService.instance.setTdp(target);
    _logger.info('Đã thiết lập TDP: $target W qua BridgeService');
    return true;
  }

  /// Đọc TDP đo thực tế tức thời từ cảm biến.
  double? getLiveTdp() {
    final live = SystemTelemetryService.instance.latest.liveTdp;
    return live > 0 ? live.toDouble() : _currentTdp.toDouble();
  }

  /// Đọc nhiệt độ CPU tức thời.
  double? getLiveCpuTemp() {
    final temp = SystemTelemetryService.instance.latest.cpuTemp;
    return temp > 0 ? temp.toDouble() : 45.0;
  }

  bool isHardwareActive() => true;
}
