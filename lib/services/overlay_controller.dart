import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import '../core/logger.dart';
import 'system_optimizer.dart';

/// Quản lý trạng thái và hành vi ẩn/hiện của Side Dock Panel trên Windows.
class OverlayController extends ChangeNotifier {
  static const _logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;
  DateTime _lastShowTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> showOverlay() async {
    try {
      _lastShowTime = DateTime.now();
      _isVisible = true;
      notifyListeners();
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      _logger.info('Đã mở Side Dock Panel.');
    } catch (e) {
      _logger.error('Lỗi khi mở Overlay', e);
    }
  }

  Future<void> hideOverlay() async {
    try {
      _isVisible = false;
      notifyListeners();
      await windowManager.hide();
      _logger.info('Đã đóng Side Dock Panel.');

      // Ép Windows giải phóng RAM khi app ẩn
      SystemOptimizer.trimMemory();
    } catch (e) {
      _logger.error('Lỗi khi ẩn Overlay', e);
    }
  }

  Future<void> toggleOverlay() async {
    try {
      final isWindowVisible = await windowManager.isVisible();
      if (isWindowVisible) {
        await hideOverlay();
      } else {
        await showOverlay();
      }
    } catch (e) {
      if (_isVisible) {
        await hideOverlay();
      } else {
        await showOverlay();
      }
    }
  }

  /// Xử lý sự kiện khi người dùng click chuột ra ngoài panel sang game/desktop
  void handleWindowBlur() {
    // Bỏ qua các tín hiệu blur giả lập trong 400ms đầu tiên khi vừa mở panel
    if (DateTime.now().difference(_lastShowTime).inMilliseconds < 400) {
      return;
    }
    hideOverlay();
  }
}
