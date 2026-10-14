import '../core/logger.dart';
import '../services/bridge_service.dart';

/// Dịch vụ quản lý bật/tắt màn hình cảm ứng (Touchscreen) thông qua BridgeService.
class TouchscreenService {
  static const _logger = AppLogger('TouchscreenService');

  static bool get isEnabled => BridgeService.instance.isTouchEnabled.value;

  static Future<void> init() async {}

  static Future<bool> toggleTouchscreen() async {
    BridgeService.instance.toggleTouchscreen();
    _logger.info('Đã gửi yêu cầu chuyển đổi trạng thái cảm ứng.');
    return isEnabled;
  }
}
