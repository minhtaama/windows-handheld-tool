import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../core/logger.dart';
import 'system_optimizer.dart';

/// Quản lý trạng thái và hành vi ẩn/hiện của Side Dock Panel trên Windows.
/// Hỗ trợ hoạt cảnh trượt mượt mà (Smooth Slide Animation) từ mép phải màn hình.
class OverlayController extends ChangeNotifier {
  static const _logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;
  DateTime _lastShowTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Callback kích hoạt hoạt cảnh trượt mở từ UI
  AsyncCallback? onAnimateShow;

  /// Callback kích hoạt hoạt cảnh trượt đóng về mép phải từ UI
  AsyncCallback? onAnimateHide;

  /// Mở Side Dock Panel với hoạt cảnh trượt từ mép phải màn hình.
  Future<void> showOverlay() async {
    try {
      _lastShowTime = DateTime.now();

      // 1. Cập nhật động kích thước và vị trí theo độ phân giải màn hình
      try {
        final display = await screenRetriever.getPrimaryDisplay();
        final screenWidth = display.size.width;
        final screenHeight = display.size.height;
        final panelWidth = (screenWidth * 0.28).clamp(300.0, 380.0);

        await windowManager.setSize(Size(panelWidth, screenHeight));
        await windowManager.setPosition(Offset(screenWidth - panelWidth, 0));
      } catch (e) {
        _logger.warning('Lỗi khi truy vấn độ phân giải động: $e');
      }

      _isVisible = true;
      notifyListeners();

      // 2. Hiện cửa sổ và đưa lên trên cùng
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();

      // 3. Kích hoạt hoạt cảnh trượt từ mép phải vào
      if (onAnimateShow != null) {
        await onAnimateShow!();
      }

      _logger.info('Đã mở Side Dock Panel với hoạt cảnh trượt.');
    } catch (e) {
      _logger.error('Lỗi khi mở Overlay', e);
    }
  }

  /// Đóng Side Dock Panel: Chạy hoạt cảnh trượt về mép phải trước khi ẩn cửa sổ.
  Future<void> hideOverlay() async {
    try {
      _isVisible = false;
      notifyListeners();

      // 1. Chạy hoạt cảnh trượt ngược về mép phải
      if (onAnimateHide != null) {
        await onAnimateHide!();
      }

      // 2. Ẩn cửa sổ sau khi hoạt cảnh hoàn tất
      await windowManager.hide();
      _logger.info('Đã đóng Side Dock Panel.');

      // 3. Giải phóng bộ nhớ RAM
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
