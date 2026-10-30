import '../core/logger.dart';
import '../services/bridge_service.dart';
import '../services/system_telemetry_service.dart';
import 'hardware_base.dart';

/// Dịch vụ quản lý kết nối RivaTuner Statistics Server (RTSS) qua BridgeService.
class RtssService {
  static const _logger = AppLogger('RtssService');
  static final RtssService instance = RtssService._();

  RtssService._();

  int _fpsLimit = 0;
  bool _osdEnabled = true;
  int _osdZoom = 2;
  RtssOsdPosition _osdPosition = RtssOsdPosition.topLeft;

  Future<bool> ensureRunning() async {
    _logger.info('RTSS service active.');
    return true;
  }

  bool isRunning() => true;
  bool isInstalled() => true;

  int getFpsLimit() => _fpsLimit;

  bool setFpsLimit(int limit) {
    _fpsLimit = limit;
    BridgeService.instance.setFpsLimit(limit);
    _logger.info('Đã thiết lập giới hạn FPS: $limit');
    return true;
  }

  int? getInstantaneousFps() => SystemTelemetryService.instance.latest.liveFps;

  String? getActiveGameName() => SystemTelemetryService.instance.latest.activeGame;

  bool isOsdEnabled() => _osdEnabled;

  bool setOsdEnabled(bool enabled) {
    _osdEnabled = enabled;
    BridgeService.instance.setOsdMetric('osd_enabled', enabled);
    return true;
  }

  int getOsdZoom() => _osdZoom;

  bool setOsdZoom(int zoom) {
    _osdZoom = zoom;
    _pushLayout();
    return true;
  }

  RtssOsdPosition getOsdPosition() => _osdPosition;

  bool setOsdPosition(RtssOsdPosition pos) {
    _osdPosition = pos;
    _pushLayout();
    return true;
  }

  /// Đẩy cặp Zoom/Position xuống backend (ghi ZoomRatio vào profile RTSS + ghim tag vị trí).
  void _pushLayout() {
    BridgeService.instance.setOsdLayout(_osdZoom, _osdPosition.name);
    _logger.info('Đã gửi layout OSD: ${_osdZoom}x @ ${_osdPosition.name}');
  }

  bool updateOsdText(String text) {
    BridgeService.instance.updateOsdText(text);
    return true;
  }

  bool clearOsdText() {
    BridgeService.instance.clearOsdText();
    return true;
  }
}

/// Các vị trí neo góc màn hình hiển thị Overlay OSD của RTSS.
///
/// Tên enum (`name`) là khóa gửi xuống backend; backend tự ánh xạ sang ô của lưới 3x3 RTSS.
enum RtssOsdPosition {
  topLeft('Trái trên'),
  topRight('Phải trên'),
  bottomLeft('Trái dưới'),
  bottomRight('Phải dưới');

  final String label;

  const RtssOsdPosition(this.label);
}

/// Bộ điều khiển phần cứng cho RTSS FPS Limit & OSD Overlay.
class RtssFpsController extends HardwareController {
  final RtssService _service = RtssService.instance;

  RtssFpsController()
      : super(
          name: 'Giới hạn FPS',
          minVal: 0,
          maxVal: 120,
          step: 5,
          unit: 'FPS',
        );

  @override
  bool isAvailable() => _service.isRunning();

  @override
  int getValue() => _service.getFpsLimit();

  @override
  bool setValue(int value) => _service.setFpsLimit(clamp(value));

  int? getLiveFps() => _service.getInstantaneousFps();

  String? getActiveGame() => _service.getActiveGameName();

  bool isOsdEnabled() => _service.isOsdEnabled();
  bool setOsdEnabled(bool enabled) => _service.setOsdEnabled(enabled);

  int getOsdZoom() => _service.getOsdZoom();
  bool setOsdZoom(int zoom) => _service.setOsdZoom(zoom);

  RtssOsdPosition getOsdPosition() => _service.getOsdPosition();
  bool setOsdPosition(RtssOsdPosition pos) => _service.setOsdPosition(pos);

  bool updateOsdText(String text) => _service.updateOsdText(text);
  bool clearOsdText() => _service.clearOsdText();
}
