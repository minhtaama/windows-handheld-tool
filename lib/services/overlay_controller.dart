import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/logger.dart';
import 'dxgi_hook_service.dart';
import 'native_window_service.dart';

/// Quản lý trạng thái và hoạt cảnh ẩn/hiện của Side Dock Panel trên Windows.
/// Áp dụng mô hình True Fullscreen Transparent Overlay (chuẩn Gaming Overlay)
/// kết hợp XInput Muting để ngăn chặn hoàn toàn việc game nhận nhầm thao tác tay cầm khi đang điều khiển Quick Panel.
class OverlayController extends ChangeNotifier {
  static const logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;

  DateTime _lastToggleTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _topmostWatchdogTimer;
  Timer? _sharedTextureTimer;

  ConfigManager? config;

  /// Lấy tỷ lệ phần trăm độ rộng của panel từ cấu hình (mặc định 35%)
  int get widthPercent => config?.get("overlay.width_percent", 35) ?? 35;

  /// Lấy tỷ lệ phóng đại giao diện UI Scale (mặc định 1.0)
  double get scale => ((config?.get("overlay.scale", 1.0) ?? 1.0) as num).toDouble();

  /// Callback kích hoạt hoạt cảnh trượt mở từ UI
  AsyncCallback? onAnimateShow;

  /// Callback kích hoạt hoạt cảnh trượt đóng từ UI
  AsyncCallback? onAnimateHide;

  /// Thay đổi bề rộng Side Dock Panel tại chỗ (Flutter tự động animate mượt mà 60fps/120fps)
  void updateWidthPercent(int percent) {
    config?.set("overlay.width_percent", percent);
    notifyListeners();
    logger.info('Đã cập nhật độ rộng panel: $percent%.');
  }

  /// Thay đổi tỷ lệ phóng đại nội dung UI Scale
  void updateScale(double newScale) {
    config?.set("overlay.scale", newScale);
    notifyListeners();
    logger.info('Đã cập nhật tỷ lệ UI Scale: ${newScale}x.');
  }

  /// Mở Side Dock Panel: Ngắt gamepad trong game, bật cửa sổ Overlay và chạy hoạt cảnh trượt vào
  Future<void> showOverlay() async {
    try {
      _isVisible = true;
      notifyListeners();

      // 1. Ngắt (Mute) tín hiệu Gamepad gửi đến game để tránh nhận nhầm thao tác
      DxgiHookService.instance.setOverlayActive(true);

      // Kích hoạt đồng bộ Direct3D Shared Texture liên tục (30fps) nếu đang ở chế độ sharedTexture
      _sharedTextureTimer?.cancel();
      if (DxgiHookService.instance.hookMode == OverlayHookMode.sharedTexture) {
        final hwnd = NativeWindowService.getWindowHandle();
        if (hwnd != 0) {
          DxgiHookService.instance.updateSharedTextureFromHwnd(hwnd);
          _sharedTextureTimer = Timer.periodic(
            const Duration(milliseconds: 33),
            (_) {
              if (_isVisible) {
                DxgiHookService.instance.updateSharedTextureFromHwnd(hwnd);
              }
            },
          );
        }
      }

      // 2. Hiển thị cửa sổ Fullscreen Transparent Overlay ở trạng thái SWP_NOACTIVATE & Always-on-Top
      NativeWindowService.showOverlayNoActivate();

      // 3. Kích hoạt bộ canh gác Z-Order tần số cao (High-Frequency Topmost Watchdog - 200ms):
      // Định kỳ tái khẳng định vị thế đỉnh của Overlay và cưỡng bức đẩy lùi Tablet Taskbar ra sau
      // để chống lại việc Windows Tablet Taskbar thức giấc và cướp ngôi vị Topmost khi có cử chỉ chạm ở cạnh đáy.
      _topmostWatchdogTimer?.cancel();
      _topmostWatchdogTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) {
          if (_isVisible) {
            NativeWindowService.reassertTopmost();
          }
        },
      );

      // 4. Kích hoạt hoạt cảnh trượt từ mép phải vào
      onAnimateShow?.call();

      logger.info('Đã mở Side Dock Panel (Fullscreen Transparent Overlay, Gamepad Muted in Game).');
    } catch (e) {
      logger.error('Lỗi khi mở Overlay', e);
    }
  }

  /// Đóng Side Dock Panel: Chạy hoạt cảnh trượt ra, khôi phục Gamepad cho game và bật cờ xuyên thấu
  Future<void> hideOverlay() async {
    try {
      _isVisible = false;
      notifyListeners();

      // 1. Hủy ngay lập tức các timer để giải phóng 100% CPU
      _topmostWatchdogTimer?.cancel();
      _topmostWatchdogTimer = null;
      _sharedTextureTimer?.cancel();
      _sharedTextureTimer = null;

      // 2. Khôi phục tín hiệu Gamepad cho game ngay lập tức
      DxgiHookService.instance.setOverlayActive(false);

      // 3. Chạy hoạt cảnh trượt ra mép phải
      if (onAnimateHide != null) {
        await onAnimateHide!();
      }

      // 4. Chuyển cửa sổ sang chế độ xuyên thấu (WS_EX_TRANSPARENT)
      NativeWindowService.hideOverlayWindow();

      logger.info('Đã đóng Side Dock Panel (Gamepad restored in Game).');
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
    // Duy trì hiển thị để không làm gián đoạn trải nghiệm chơi game
    logger.info('Bỏ qua sự kiện Window Blur để duy trì hiển thị trên Game.');
  }
}
