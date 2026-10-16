import '../core/logger.dart';
import 'bridge_service.dart';

/// Bộ tối ưu hóa tài nguyên hệ thống dành cho máy Handheld.
class SystemOptimizer {
  static const _logger = AppLogger('SystemOptimizer');

  static void trimMemory() {
    _logger.info('Yêu cầu giải phóng RAM đã được tiếp nhận.');
    BridgeService.instance.trimMemory();
  }
}

