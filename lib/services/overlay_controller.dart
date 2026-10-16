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
  bool _isClosing = false;

  ConfigManager? config;

  int get widthPercent => config?.get("overlay.width_percent", 35) ?? 35;
  double get scale => ((config?.get("overlay.scale", 1.0) ?? 1.0) as num).toDouble();

  AsyncCallback? onAnimateShow;
  AsyncCallback? onAnimateHide;

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
    _isClosing = false;
    _isVisible = true;
    notifyListeners();
    if (onAnimateShow != null) {
      await onAnimateShow!();
    }
  }

  Future<void> hideOverlay() async {
    if (_isClosing) return;
    _isClosing = true;
    if (onAnimateHide != null) {
      await onAnimateHide!();
    }
    _isVisible = false;
    _isClosing = false;
    notifyListeners();
    BridgeService.instance.closeOverlay();
  }

  Future<void> toggleOverlay() async {
    if (_isVisible && !_isClosing) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }
}
