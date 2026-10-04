import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import '../core/logger.dart';
import 'system_optimizer.dart';

/// Quản lý trạng thái và hành vi ẩn/hiện của cửa sổ Overlay trên Windows.
class OverlayController extends ChangeNotifier {
  static const _logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;

  Future<void> showOverlay() async {
    if (_isVisible) return;
    try {
      _isVisible = true;
      notifyListeners();
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      _logger.info('Đã hiển thị cửa sổ Overlay.');
    } catch (e) {
      _logger.error('Lỗi khi mở Overlay', e);
    }
  }

  Future<void> hideOverlay() async {
    if (!_isVisible) return;
    try {
      _isVisible = false;
      notifyListeners();
      await windowManager.hide();
      _logger.info('Đã ẩn cửa sổ Overlay.');

      // Tối ưu hóa: Ép Windows giải phóng RAM khi app ẩn
      SystemOptimizer.trimMemory();
    } catch (e) {
      _logger.error('Lỗi khi ẩn Overlay', e);
    }
  }

  Future<void> toggleOverlay() async {
    if (_isVisible) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }
}
