import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:window_manager/window_manager.dart';

import '../core/config.dart';
import '../core/logger.dart';
import 'native_window_service.dart';

/// Quản lý trạng thái và hành vi ẩn/hiện của Side Dock Panel trên Windows.
/// Áp dụng mô hình Fullscreen Transparent Overlay (chuẩn Handheld Gaming Overlay)
/// kết hợp Native Win32 SW_SHOWNOACTIVATE để tránh cướp Focus và không làm văng game DirectX.
class OverlayController extends ChangeNotifier {
  static const logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;

  DateTime _lastToggleTime = DateTime.fromMillisecondsSinceEpoch(0);

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

      // 1. Lấy độ phân giải vật lý thực tế hiện hành của màn hình (hỗ trợ in-game 720p/800p/RSR)
      final currentScreenSize = NativeWindowService.getPhysicalScreenSize();

      // 2. Tính toán kích thước Side-Dock Panel (chuẩn kiến trúc GPD Tool / Handheld Sidebar)
      // Không bao phủ (0, 0) toàn màn hình để Windows DWM không coi đây là Fullscreen Replacement
      final panelWidth = (currentScreenSize.width * (widthPercent / 100.0)).clamp(
        320.0,
        520.0,
      );
      final posX = currentScreenSize.width - panelWidth;

      // 3. Hiển thị cửa sổ neo sát mép phải ở chế độ SW_SHOWNOACTIVATE & Always-on-Top (KHÔNG cướp Focus của Game)
      final shown = NativeWindowService.showOverlayNoActivate(
        size: Size(panelWidth, currentScreenSize.height),
        position: Offset(posX, 0),
      );

      // Fallback an toàn qua windowManager nếu cần
      if (!shown) {
        await windowManager.setPosition(Offset(posX, 0));
        await windowManager.setSize(Size(panelWidth, currentScreenSize.height));
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show(inactive: true);
      }

      // 4. Kích hoạt hoạt cảnh trượt từ mép phải vào (chạy bất đồng bộ, không nghẽn luồng)
      onAnimateShow?.call();

      logger.info('Đã mở Side Dock Panel (Pos: $posX, Width: $panelWidth, Height: ${currentScreenSize.height}).');
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

      // 2. Dời cửa sổ ra off-screen để giữ nguyên DWM composition surface
      NativeWindowService.hideOverlayWindow();

      logger.info('Đã đóng Side Dock Panel.');
    } catch (e) {
      logger.error('Lỗi khi ẩn Overlay', e);
    }
  }

  /// Bật/tắt trạng thái Side Dock Panel với Debounce chống kích hoạt trùng lặp
  Future<void> toggleOverlay() async {
    final now = DateTime.now();
    if (now.difference(_lastToggleTime).inMilliseconds < 350) {
      logger.info('Bỏ qua toggleOverlay do debounce (< 350ms).');
      return;
    }
    _lastToggleTime = now;

    if (_isVisible) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }

  /// Xử lý sự kiện khi người dùng click chuột ra ngoài panel sang game/desktop
  void handleWindowBlur() {
    // Không tự động đóng panel khi mất tiêu điểm để duy trì hiển thị khi chơi game
    logger.info('Bỏ qua sự kiện Window Blur để duy trì hiển thị trên Game.');
  }
}
