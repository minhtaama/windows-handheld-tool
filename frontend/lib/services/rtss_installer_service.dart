import '../core/logger.dart';
import '../hardware/rtss_service.dart';
import 'bridge_service.dart';

/// Trạng thái của quá trình cài đặt RTSS.
enum RtssInstallStatus { notInstalled, installing, installed, failed }

/// Dịch vụ quản lý kiểm tra và cài đặt RivaTuner Statistics Server (RTSS).
class RtssInstallerService {
  static const _logger = AppLogger('RtssInstallerService');

  static bool isInstalled() {
    return RtssService.instance.isInstalled();
  }

  static Future<bool> installRtss({
    void Function(String message)? onStatusUpdate,
  }) async {
    if (isInstalled()) {
      _logger.info('RTSS already installed.');
      onStatusUpdate?.call('RTSS đã sẵn sàng.');
      return true;
    }
    _logger.info('Đang kích hoạt cài đặt RTSS ngầm qua Backend...');
    onStatusUpdate?.call('Đang tải và cài đặt RTSS ngầm qua winget...');
    BridgeService.instance.installRtss();
    return true;
  }
}
