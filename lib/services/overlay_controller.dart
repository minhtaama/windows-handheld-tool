import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config.dart';
import '../core/logger.dart';
import 'system_optimizer.dart';

/// Quản lý trạng thái và hành vi ẩn/hiện của Side Dock Panel trên Windows.
/// Áp dụng mô hình Fullscreen Transparent Overlay (chuẩn Steam Overlay / Xbox Game Bar)
/// để tránh phá vỡ DirectX SwapChain và loại trừ triệt để lỗi xung đột với GPU Driver.
class OverlayController extends ChangeNotifier {
  static const logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;

  ConfigManager? config;

  /// Lấy tỷ lệ phần trăm độ rộng của panel từ cấu hình (mặc định 35%)
  int get widthPercent => config?.get("overlay.width_percent", 35) ?? 35;

  /// Callback kích hoạt hoạt cảnh trượt mở từ UI
  AsyncCallback? onAnimateShow;

  /// Callback kích hoạt hoạt cảnh trượt đóng từ UI
  AsyncCallback? onAnimateHide;

  /// Thay đổi bề rộng Side Dock Panel tại chỗ (Flutter tự động animate, không can thiệp Win32)
  void updateWidthPercent(int percent) {
    config?.set("overlay.width_percent", percent);
    notifyListeners();
    logger.info('Đã cập nhật độ rộng panel: $percent%.');
  }

  /// Mở Side Dock Panel với hoạt cảnh trượt mượt mà từ mép phải
  Future<void> showOverlay() async {
    try {
      _isVisible = true;
      notifyListeners();

      // Hiện cửa sổ toàn màn hình trong suốt và đưa lên trên cùng
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();

      // Kích hoạt hoạt cảnh trượt từ mép phải vào
      if (onAnimateShow != null) {
        await onAnimateShow!();
      }

      logger.info('Đã mở Side Dock Panel.');
    } catch (e) {
      logger.error('Lỗi khi mở Overlay', e);
    }
  }

  /// Đóng Side Dock Panel: Chạy hoạt cảnh trượt ra ngoài mép phải trước khi ẩn cửa sổ
  Future<void> hideOverlay() async {
    try {
      _isVisible = false;
      notifyListeners();

      // 1. Chạy hoạt cảnh trượt ra mép phải
      if (onAnimateHide != null) {
        await onAnimateHide!();
      }

      // 2. Ẩn cửa sổ sau khi hoạt cảnh hoàn tất
      await windowManager.hide();
      logger.info('Đã đóng Side Dock Panel.');

      // 3. Giải phóng bộ nhớ RAM
      SystemOptimizer.trimMemory();
    } catch (e) {
      logger.error('Lỗi khi ẩn Overlay', e);
    }
  }

  /// Bật/tắt trạng thái Side Dock Panel
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
    // Không tự động đóng panel khi mất tiêu điểm để duy trì hiển thị khi chơi game
    logger.info('Bỏ qua sự kiện Window Blur để duy trì hiển thị trên Game.');
  }
}
