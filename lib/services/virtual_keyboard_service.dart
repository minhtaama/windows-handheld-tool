import '../core/logger.dart';
import 'bridge_service.dart';

/// Dịch vụ kích hoạt bàn phím ảo (Virtual Keyboard / TabTip) của Windows qua BridgeService.
class VirtualKeyboardService {
  static const _logger = AppLogger('VirtualKeyboardService');

  static Future<bool> toggleKeyboard({int? actionVk, bool fromGamepad = false}) async {
    BridgeService.instance.toggleVirtualKeyboard();
    _logger.info('Đã gửi lệnh bật/tắt bàn phím ảo sang Python backend.');
    return true;
  }
}
