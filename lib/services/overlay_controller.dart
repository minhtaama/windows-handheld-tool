import 'dart:ffi' hide Size;
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config.dart';
import '../core/logger.dart';
import 'system_optimizer.dart';

typedef _FindWindowWC = IntPtr Function(
  Pointer<Utf16> lpClassName,
  Pointer<Utf16> lpWindowName,
);
typedef _FindWindowWDart = int Function(
  Pointer<Utf16> lpClassName,
  Pointer<Utf16> lpWindowName,
);

typedef _GetForegroundWindowC = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _GetWindowThreadProcessIdC = Uint32 Function(
  IntPtr hWnd,
  Pointer<Uint32> lpdwProcessId,
);
typedef _GetWindowThreadProcessIdDart = int Function(
  int hWnd,
  Pointer<Uint32> lpdwProcessId,
);

typedef _GetCurrentThreadIdC = Uint32 Function();
typedef _GetCurrentThreadIdDart = int Function();

typedef _AttachThreadInputC = Int32 Function(
  Uint32 idAttach,
  Uint32 idAttachTo,
  Int32 fAttach,
);
typedef _AttachThreadInputDart = int Function(
  int idAttach,
  int idAttachTo,
  int fAttach,
);

typedef _SetWindowPosC = Int32 Function(
  IntPtr hWnd,
  IntPtr hWndInsertAfter,
  Int32 X,
  Int32 Y,
  Int32 cx,
  Int32 cy,
  Uint32 uFlags,
);
typedef _SetWindowPosDart = int Function(
  int hWnd,
  int hWndInsertAfter,
  int X,
  int Y,
  int cx,
  int cy,
  int uFlags,
);

typedef _SetForegroundWindowC = Int32 Function(IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);

typedef _BringWindowToTopC = Int32 Function(IntPtr hWnd);
typedef _BringWindowToTopDart = int Function(int hWnd);

typedef _SetActiveWindowC = IntPtr Function(IntPtr hWnd);
typedef _SetActiveWindowDart = int Function(int hWnd);

/// Quản lý trạng thái và hành vi ẩn/hiện của Side Dock Panel trên Windows.
/// Hỗ trợ hoạt cảnh mượt mà từ mép phải màn hình và đè lên game Exclusive Fullscreen.
class OverlayController extends ChangeNotifier {
  static const _logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;

  ConfigManager? config;

  static _FindWindowWDart? _findWindowW;
  static _GetForegroundWindowDart? _getForegroundWindow;
  static _GetWindowThreadProcessIdDart? _getWindowThreadProcessId;
  static _GetCurrentThreadIdDart? _getCurrentThreadId;
  static _AttachThreadInputDart? _attachThreadInput;
  static _SetWindowPosDart? _setWindowPos;
  static _SetForegroundWindowDart? _setForegroundWindow;
  static _BringWindowToTopDart? _bringWindowToTop;
  static _SetActiveWindowDart? _setActiveWindow;
  static bool _win32Initialized = false;

  static void _initWin32() {
    if (_win32Initialized) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _findWindowW = user32.lookupFunction<_FindWindowWC, _FindWindowWDart>(
        'FindWindowW',
      );
      _getForegroundWindow = user32
          .lookupFunction<_GetForegroundWindowC, _GetForegroundWindowDart>(
            'GetForegroundWindow',
          );
      _getWindowThreadProcessId = user32
          .lookupFunction<
            _GetWindowThreadProcessIdC,
            _GetWindowThreadProcessIdDart
          >('GetWindowThreadProcessId');
      _attachThreadInput = user32
          .lookupFunction<_AttachThreadInputC, _AttachThreadInputDart>(
            'AttachThreadInput',
          );
      _setWindowPos = user32.lookupFunction<_SetWindowPosC, _SetWindowPosDart>(
        'SetWindowPos',
      );
      _setForegroundWindow = user32
          .lookupFunction<_SetForegroundWindowC, _SetForegroundWindowDart>(
            'SetForegroundWindow',
          );
      _bringWindowToTop = user32
          .lookupFunction<_BringWindowToTopC, _BringWindowToTopDart>(
            'BringWindowToTop',
          );
      _setActiveWindow = user32
          .lookupFunction<_SetActiveWindowC, _SetActiveWindowDart>(
            'SetActiveWindow',
          );

      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _getCurrentThreadId = kernel32
          .lookupFunction<_GetCurrentThreadIdC, _GetCurrentThreadIdDart>(
            'GetCurrentThreadId',
          );

      _win32Initialized = true;
    } catch (e) {
      _logger.warning('Không thể khởi tạo Win32 FFI cho Force Foreground: $e');
    }
  }

  /// Tìm handle (HWND) của cửa sổ Flutter trên Windows một cách chuẩn xác theo Window Class.
  /// Không phụ thuộc vào chuỗi tiêu đề (vốn bị xóa sạch khi dùng TitleBarStyle.hidden/setAsFrameless).
  static int _getFlutterHwnd() {
    _initWin32();
    if (!_win32Initialized || _findWindowW == null) return 0;
    try {
      final clsPtr = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = _findWindowW!(clsPtr, nullptr);
      calloc.free(clsPtr);
      return hwnd;
    } catch (e) {
      _logger.warning('Lỗi khi tìm FLUTTER_RUNNER_WIN32_WINDOW: $e');
      return 0;
    }
  }

  /// Cưỡng chế đưa cửa sổ lên tiền cảnh (TopMost) đè lên cả các game chạy Exclusive Fullscreen.
  /// Sử dụng kỹ thuật AttachThreadInput + SetWindowPos HWND_TOPMOST (chuẩn GPD Tool / Motion Assistant).
  /// Chỉ thay đổi Z-Order và kích hoạt cửa sổ, tuyệt đối không can thiệp tọa độ / kích thước Flutter.
  static void _forceForeground() {
    _initWin32();
    if (!_win32Initialized) return;

    try {
      final hwnd = _getFlutterHwnd();

      if (hwnd != 0) {
        final fgWnd = _getForegroundWindow!();
        final fgThreadId = _getWindowThreadProcessId!(fgWnd, nullptr);
        final curThreadId = _getCurrentThreadId!();

        if (fgThreadId != 0 && fgThreadId != curThreadId) {
          _attachThreadInput!(curThreadId, fgThreadId, 1);
        }

        const hwndTopMost = -1;
        const swpNoMove = 0x0002;
        const swpNoSize = 0x0001;
        const swpShowWindow = 0x0040;

        _setWindowPos!(
          hwnd,
          hwndTopMost,
          0,
          0,
          0,
          0,
          swpNoMove | swpNoSize | swpShowWindow,
        );
        _bringWindowToTop!(hwnd);
        _setForegroundWindow!(hwnd);
        _setActiveWindow!(hwnd);

        if (fgThreadId != 0 && fgThreadId != curThreadId) {
          _attachThreadInput!(curThreadId, fgThreadId, 0);
        }

        _logger.info('Đã cưỡng chế cửa sổ lên tiền cảnh đè lên game.');
      } else {
        _logger.warning('Không tìm thấy HWND của FLUTTER_RUNNER_WIN32_WINDOW.');
      }
    } catch (e) {
      _logger.warning('Lỗi khi cưỡng chế cửa sổ lên tiền cảnh: $e');
    }
  }

  /// Callback kích hoạt hoạt cảnh mở từ UI
  AsyncCallback? onAnimateShow;

  /// Callback kích hoạt hoạt cảnh đóng từ UI
  AsyncCallback? onAnimateHide;

  /// Mở Side Dock Panel với kích thước tự thích ứng với độ phân giải màn hình tức thời.
  Future<void> showOverlay() async {
    try {
      // 1. Đọc độ phân giải tức thời từ màn hình chính (Tự động thích ứng khi game đổi 720p/900p/1080p)
      final display = await screenRetriever.getPrimaryDisplay();
      final screenWidth = display.size.width;
      final screenHeight = display.size.height;

      // 2. Tính bề rộng panel theo tỷ lệ phần trăm tùy biến (overlay.width_percent)
      final widthPercent = (config?.get("overlay.width_percent", 28) ?? 28)
          .toDouble();
      final panelWidth = (screenWidth * (widthPercent / 100.0)).clamp(
        280.0,
        screenWidth * 0.6,
      );
      final targetX = screenWidth - panelWidth;

      // 3. Cập nhật kích thước & vị trí cho Flutter WindowManager
      await windowManager.setSize(Size(panelWidth, screenHeight));
      await windowManager.setPosition(Offset(targetX, 0));

      _isVisible = true;
      notifyListeners();

      // 4. Hiện cửa sổ và đưa lên trên cùng
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();

      // Cưỡng chế đưa cửa sổ lên trên cùng của Exclusive Fullscreen bằng AttachThreadInput & SetWindowPos
      _forceForeground();

      // 5. Kích hoạt hoạt cảnh Fade mờ dần sang rõ dần
      if (onAnimateShow != null) {
        await onAnimateShow!();
      }

      _logger.info(
        'Đã mở Side Dock Panel (Res: ${screenWidth.round()}x${screenHeight.round()}, Panel: ${panelWidth.round()}x${screenHeight.round()}).',
      );
    } catch (e) {
      _logger.error('Lỗi khi mở Overlay', e);
    }
  }

  /// Đóng Side Dock Panel: Chạy hoạt cảnh Fade mờ dần trước khi ẩn cửa sổ.
  Future<void> hideOverlay() async {
    try {
      _isVisible = false;
      notifyListeners();

      // 1. Chạy hoạt cảnh Fade mờ dần
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
    // Không tự động đóng panel khi mất tiêu điểm để tránh xung đột với Game loop hoặc Gamepad
    // Panel chỉ đóng khi người dùng chủ động nhấn lại phím tắt, bấm Back + RB hoặc nhấn nút Đóng
    _logger.info('Bỏ qua sự kiện Window Blur để duy trì hiển thị trên Game.');
  }
}
