import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/logger.dart';
import 'native_window_service.dart';

/// Quản lý trạng thái và hoạt cảnh ẩn/hiện của Side Dock Panel trên Windows.
/// Áp dụng mô hình True Fullscreen Transparent Overlay (chuẩn Gaming Overlay)
/// trên phân lớp hệ thống ZBID_SYSTEM_TOOLS.
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

  /// Lấy tỷ lệ phóng đại giao diện UI Scale (mặc định 1.0)
  double get scale => ((config?.get("overlay.scale", 1.0) ?? 1.0) as num).toDouble();

  /// Callback kích hoạt hoạt cảnh trượt mở từ UI
  AsyncCallback? onAnimateShow;

  /// Callback kích hoạt hoạt cảnh trượt đóng từ UI
  AsyncCallback? onAnimateHide;

  /// Thay đổi bề rộng Side Dock Panel tại chỗ (co dãn cửa sổ Win32 tức thời)
  void updateWidthPercent(int percent) {
    config?.set("overlay.width_percent", percent);
    final physicalSize = NativeWindowService.getPhysicalScreenSize();
    final pWidth = (physicalSize.width * (percent / 100.0)).clamp(320.0, 850.0).toInt();
    if (_isVisible) {
      NativeWindowService.resizeDockWindow(panelWidth: pWidth);
    }
    notifyListeners();
  }

  /// Thay đổi tỷ lệ phóng đại nội dung UI Scale
  void updateScale(double newScale) {
    config?.set("overlay.scale", newScale);
    notifyListeners();
  }

  int _lastGameHwnd = 0;

  /// Mở Side Dock Panel: hiển thị cửa sổ Dock neo mép phải
  Future<void> showOverlay() async {
    try {
      _isVisible = true;
      notifyListeners();

      // Lưu lại cửa sổ đang chơi game trước khi hiển thị overlay
      final fg = NativeWindowService.getForegroundWindow();
      if (fg != 0 && fg != NativeWindowService.getWindowHandle()) {
        _lastGameHwnd = fg;
      }

      // 1. Tính toán bề rộng panel vật lý và kích hoạt cửa sổ Side Dock (SWP_NOACTIVATE & Always-on-Top)
      final physicalSize = NativeWindowService.getPhysicalScreenSize();
      final pWidth = (physicalSize.width * (widthPercent / 100.0)).clamp(320.0, 850.0).toInt();
      NativeWindowService.showDockWindow(panelWidth: pWidth);

      // 2. Kích hoạt hoạt cảnh trượt từ mép phải vào
      onAnimateShow?.call();

      logger.info('Đã mở Side Dock Panel (width: $pWidth px).');
    } catch (e) {
      logger.error('Lỗi khi mở Overlay', e);
    }
  }

  /// Đóng Side Dock Panel: Chạy hoạt cảnh trượt ra và dời cửa sổ ra ngoài màn hình (Off-screen)
  Future<void> hideOverlay() async {
    try {
      _isVisible = false;
      notifyListeners();

      // 1. Chạy hoạt cảnh trượt ra mép phải
      if (onAnimateHide != null) {
        await onAnimateHide!();
      }

      // 2. Thu ẩn cửa sổ ra ngoài màn hình (Off-screen) nhưng giữ IsWindowVisible == true cho Windows 11 Taskbar
      NativeWindowService.hideDockWindow();

      // 3. Trả lại Foreground Focus cho cửa sổ game để game không bị bóp FPS khi chạy nền
      if (_lastGameHwnd != 0) {
        NativeWindowService.setForegroundWindow(_lastGameHwnd);
      }

      logger.info('Đã đóng Side Dock Panel.');
    } catch (e) {
      logger.error('Lỗi khi ẩn Overlay', e);
    }
  }

  /// Bật/tắt trạng thái Side Dock Panel với Debounce chống kích hoạt trùng lặp
  Future<void> toggleOverlay() async {
    final now = DateTime.now();
    if (now.difference(_lastToggleTime).inMilliseconds < 350) {
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
  }
}
