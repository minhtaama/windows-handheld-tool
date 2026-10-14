import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/logger.dart';
import 'bridge_service.dart';

/// Dịch vụ quản lý khởi động cùng Windows thông qua BridgeService.
class AutostartService extends ChangeNotifier {
  static const _logger = AppLogger('AutostartService');

  static final AutostartService instance = AutostartService._();
  AutostartService._();

  bool get isEnabled => BridgeService.instance.autostart.value;

  void init(ConfigManager config) {
    BridgeService.instance.autostart.addListener(notifyListeners);
  }

  Future<bool> checkStatus() async => isEnabled;

  Future<bool> setEnabled(bool enable) async {
    BridgeService.instance.setAutostart(enable);
    _logger.info('Đã gửi yêu cầu thay đổi autostart: $enable');
    notifyListeners();
    return enable;
  }
}
