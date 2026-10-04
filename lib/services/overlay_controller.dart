import 'dart:ffi' hide Size;
import 'dart:ui';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../core/logger.dart';
import 'system_optimizer.dart';

typedef _FindWindowWC = IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef _FindWindowWDart = int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);

typedef _GetForegroundWindowC = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr hWnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart = int Function(int hWnd, Pointer<Uint32> lpdwProcessId);

typedef _GetCurrentThreadIdC = Uint32 Function();
typedef _GetCurrentThreadIdDart = int Function();

typedef _AttachThreadInputC = Int32 Function(Uint32 idAttach, Uint32 idAttachTo, Int32 fAttach);
typedef _AttachThreadInputDart = int Function(int idAttach, int idAttachTo, int fAttach);

typedef _SetWindowPosC = Int32 Function(IntPtr hWnd, IntPtr hWndInsertAfter, Int32 X, Int32 Y, Int32 cx, Int32 cy, Uint32 uFlags);
typedef _SetWindowPosDart = int Function(int hWnd, int hWndInsertAfter, int X, int Y, int cx, int cy, int uFlags);

typedef _SetForegroundWindowC = Int32 Function(IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);

typedef _BringWindowToTopC = Int32 Function(IntPtr hWnd);
typedef _BringWindowToTopDart = int Function(int hWnd);

typedef _SetActiveWindowC = IntPtr Function(IntPtr hWnd);
typedef _SetActiveWindowDart = int Function(int hWnd);

/// Quản lý trạng thái và hành vi ẩn/hiện của Side Dock Panel trên Windows.
/// Hỗ trợ hoạt cảnh trượt mượt mà (Smooth Slide Animation) từ mép phải màn hình.
class OverlayController extends ChangeNotifier {
  static const _logger = AppLogger('OverlayController');
  static final OverlayController instance = OverlayController._();

  OverlayController._();

  bool _isVisible = false;
  bool get isVisible => _isVisible;

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
      _findWindowW = user32.lookupFunction<_FindWindowWC, _FindWindowWDart>('FindWindowW');
      _getForegroundWindow = user32.lookupFunction<_GetForegroundWindowC, _GetForegroundWindowDart>('GetForegroundWindow');
      _getWindowThreadProcessId = user32.lookupFunction<_GetWindowThreadProcessIdC, _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
      _attachThreadInput = user32.lookupFunction<_AttachThreadInputC, _AttachThreadInputDart>('AttachThreadInput');
      _setWindowPos = user32.lookupFunction<_SetWindowPosC, _SetWindowPosDart>('SetWindowPos');
      _setForegroundWindow = user32.lookupFunction<_SetForegroundWindowC, _SetForegroundWindowDart>('SetForegroundWindow');
      _bringWindowToTop = user32.lookupFunction<_BringWindowToTopC, _BringWindowToTopDart>('BringWindowToTop');
      _setActiveWindow = user32.lookupFunction<_SetActiveWindowC, _SetActiveWindowDart>('SetActiveWindow');

      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _getCurrentThreadId = kernel32.lookupFunction<_GetCurrentThreadIdC, _GetCurrentThreadIdDart>('GetCurrentThreadId');

      _win32Initialized = true;
    } catch (e) {
      _logger.warning('Không thể khởi tạo Win32 FFI cho Force Foreground: $e');
    }
  }

  /// Cưỡng chế đưa cửa sổ lên tiền cảnh (TopMost) đè lên cả các game chạy Exclusive Fullscreen.
  /// Kỹ thuật tương tự GPD Tool / Motion Assistant (AttachThreadInput + SetWindowPos).
  static void _forceForeground() {
    _initWin32();
    if (!_win32Initialized) return;

    try {
      final titlePtr = 'Handheld Quick Settings'.toNativeUtf16();
      final hwnd = _findWindowW!(nullptr, titlePtr);
      calloc.free(titlePtr);

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
      }
    } catch (e) {
      _logger.warning('Lỗi khi cưỡng chế cửa sổ lên tiền cảnh: $e');
    }
  }

  /// Callback kích hoạt hoạt cảnh trượt mở từ UI
  AsyncCallback? onAnimateShow;

  /// Callback kích hoạt hoạt cảnh trượt đóng về mép phải từ UI
  AsyncCallback? onAnimateHide;

  /// Mở Side Dock Panel với hoạt cảnh trượt từ mép phải màn hình.
  Future<void> showOverlay() async {
    try {
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

      // Cưỡng chế đưa cửa sổ lên trên cùng của Exclusive Fullscreen bằng AttachThreadInput
      _forceForeground();

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
    // Không tự động đóng panel khi mất tiêu điểm để tránh xung đột với Game loop hoặc Gamepad
    // Panel chỉ đóng khi người dùng chủ động nhấn lại phím tắt, bấm Back + RB hoặc nhấn nút Đóng
    _logger.info('Bỏ qua sự kiện Window Blur để duy trì hiển thị trên Game.');
  }
}
