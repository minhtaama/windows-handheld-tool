import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/logger.dart';
import 'bridge_service.dart';

/// Quản lý trạng thái và cấu hình hiển thị của Side Dock Panel trên Windows.
class OverlayController extends ChangeNotifier {
  static const logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = true;
  bool get isVisible => _isVisible;

  ConfigManager? config;

  int get widthPercent => config?.get("overlay.width_percent", 35) ?? 35;
  double get scale => ((config?.get("overlay.scale", 1.0) ?? 1.0) as num).toDouble();

  void refreshConfig() {
    notifyListeners();
  }

  void updateWidthPercent(int percent) {
    config?.set("overlay.width_percent", percent);
    BridgeService.instance.setPanelWidth(percent);
    notifyListeners();
  }

  void updateScale(double newScale) {
    config?.set("overlay.scale", newScale);
    BridgeService.instance.setPanelScale(newScale);
    notifyListeners();
  }

  Future<void> showOverlay() async {
    _isVisible = true;
    notifyListeners();
  }

  Future<void> hideOverlay() async {
    if (!_isVisible) return;
    _isVisible = false;
    notifyListeners();
    BridgeService.instance.closeOverlay();
  }

  Future<void> toggleOverlay() async {
    if (_isVisible) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }
}
