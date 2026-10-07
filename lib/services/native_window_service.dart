import 'dart:ffi' hide Size;
import 'dart:ui';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';

typedef _FindWindowWC = IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef _FindWindowWDart = int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);

typedef _SetWindowPosC = Int32 Function(
  IntPtr hWnd,
  IntPtr hWndInsertAfter,
  Int32 x,
  Int32 y,
  Int32 cx,
  Int32 cy,
  Uint32 uFlags,
);
typedef _SetWindowPosDart = int Function(
  int hWnd,
  int hWndInsertAfter,
  int x,
  int y,
  int cx,
  int cy,
  int uFlags,
);

typedef _GetSystemMetricsC = Int32 Function(Int32 nIndex);
typedef _GetSystemMetricsDart = int Function(int nIndex);

typedef _GetWindowLongPtrWC = IntPtr Function(IntPtr hWnd, Int32 nIndex);
typedef _GetWindowLongPtrWDart = int Function(int hWnd, int nIndex);

typedef _SetWindowLongPtrWC = IntPtr Function(IntPtr hWnd, Int32 nIndex, IntPtr dwNewLong);
typedef _SetWindowLongPtrWDart = int Function(int hWnd, int nIndex, int dwNewLong);

typedef _IsWindowVisibleC = Int32 Function(IntPtr hWnd);
typedef _IsWindowVisibleDart = int Function(int hWnd);

typedef _IsWindowC = Int32 Function(IntPtr hWnd);
typedef _IsWindowDart = int Function(int hWnd);

typedef _InvalidateRectC = Int32 Function(IntPtr hWnd, Pointer<Void> lpRect, Int32 bErase);
typedef _InvalidateRectDart = int Function(int hWnd, Pointer<Void> lpRect, int bErase);

/// Dịch vụ quản lý cửa sổ Native Win32 tối ưu cho Gaming Overlay chuẩn Fullscreen Transparent Overlay.
/// Bao phủ toàn màn hình cố định và sử dụng SWP_NOACTIVATE
/// để đảm bảo không cướp Focus của Game (chống văng/minimize game DirectX).
class NativeWindowService {
  static const _logger = AppLogger('NativeWindowService');

  static const int hwndTopMost = -1;

  static const int swpNoSize = 0x0001;
  static const int swpNoMove = 0x0002;
  static const int swpNoZOrder = 0x0004;
  static const int swpNoActivate = 0x0010;
  static const int swpFrameChanged = 0x0020;
  static const int swpShowWindow = 0x0040;
  static const int swpHideWindow = 0x0080;

  static const int gwlExStyle = -20;
  static const int wsExTransparent = 0x00000020;
  static const int wsExTopMost = 0x00000008;
  static const int wsExToolWindow = 0x00000080;
  static const int wsExNoActivate = 0x08000000;
  static const int wsExLayered = 0x00080000;

  static const int smCxScreen = 0;
  static const int smCyScreen = 1;

  static _FindWindowWDart? _findWindowW;
  static _SetWindowPosDart? _setWindowPos;
  static _GetSystemMetricsDart? _getSystemMetrics;
  static _IsWindowVisibleDart? _isWindowVisible;
  static _IsWindowDart? _isWindow;
  static _InvalidateRectDart? _invalidateRect;
  static _GetWindowLongPtrWDart? _getWindowLongPtrW;
  static _SetWindowLongPtrWDart? _setWindowLongPtrW;

  static int? _cachedHwnd;

  static void _ensureInitialized() {
    if (_findWindowW != null) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _findWindowW = user32.lookupFunction<_FindWindowWC, _FindWindowWDart>('FindWindowW');
      _setWindowPos = user32.lookupFunction<_SetWindowPosC, _SetWindowPosDart>('SetWindowPos');
      _getSystemMetrics = user32.lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>('GetSystemMetrics');
      _isWindowVisible = user32.lookupFunction<_IsWindowVisibleC, _IsWindowVisibleDart>('IsWindowVisible');
      _isWindow = user32.lookupFunction<_IsWindowC, _IsWindowDart>('IsWindow');
      _invalidateRect = user32.lookupFunction<_InvalidateRectC, _InvalidateRectDart>('InvalidateRect');

      try {
        _getWindowLongPtrW = user32.lookupFunction<_GetWindowLongPtrWC, _GetWindowLongPtrWDart>('GetWindowLongPtrW');
        _setWindowLongPtrW = user32.lookupFunction<_SetWindowLongPtrWC, _SetWindowLongPtrWDart>('SetWindowLongPtrW');
      } catch (_) {
        _getWindowLongPtrW = user32.lookupFunction<_GetWindowLongPtrWC, _GetWindowLongPtrWDart>('GetWindowLongW');
        _setWindowLongPtrW = user32.lookupFunction<_SetWindowLongPtrWC, _SetWindowLongPtrWDart>('SetWindowLongW');
      }
    } catch (e) {
      _logger.error('Lỗi khi nạp API user32.dll', e);
    }
  }

  /// Lấy HWND của cửa sổ Flutter hiện tại với nhiều chiến lược tìm kiếm
  static int getWindowHandle() {
    _ensureInitialized();
    if (_cachedHwnd != null && _isWindow != null && _isWindow!(_cachedHwnd!) != 0) {
      return _cachedHwnd!;
    }

    if (_findWindowW == null) return 0;

    // Chiến lược 1: Tìm theo Class Name chuẩn của Flutter Runner
    final classNamePtr = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    try {
      final hwnd = _findWindowW!(classNamePtr, nullptr);
      if (hwnd != 0) {
        _cachedHwnd = hwnd;
        return hwnd;
      }
    } finally {
      calloc.free(classNamePtr);
    }

    // Chiến lược 2: Tìm theo Window Title
    for (final title in ['Handheld Quick Settings', 'windows_handheld_tool']) {
      final titlePtr = title.toNativeUtf16();
      try {
        final hwnd = _findWindowW!(nullptr, titlePtr);
        if (hwnd != 0) {
          _cachedHwnd = hwnd;
          return hwnd;
        }
      } finally {
        calloc.free(titlePtr);
      }
    }

    return 0;
  }

  /// Lấy kích thước màn hình vật lý thực tế hiện hành của Windows
  static Size getPhysicalScreenSize() {
    _ensureInitialized();
    if (_getSystemMetrics == null) {
      return const Size(1920, 1080);
    }
    final width = _getSystemMetrics!(smCxScreen);
    final height = _getSystemMetrics!(smCyScreen);
    return Size(width.toDouble(), height.toDouble());
  }

  /// Hiển thị cửa sổ Fullscreen Transparent Overlay mà KHÔNG cướp Focus của Game
  static bool showOverlayNoActivate({Size? size, Offset? position}) {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) {
      _logger.warning('Không tìm thấy HWND của cửa sổ Flutter');
      return false;
    }

    final physicalSize = size ?? getPhysicalScreenSize();
    final width = physicalSize.width.toInt();
    final height = physicalSize.height.toInt();

    // 1. Cấu hình Extended Styles: Bỏ cờ WS_EX_TRANSPARENT để nhận cảm ứng/chuột
    if (_getWindowLongPtrW != null && _setWindowLongPtrW != null) {
      try {
        final currentExStyle = _getWindowLongPtrW!(hwnd, gwlExStyle);
        _setWindowLongPtrW!(
          hwnd,
          gwlExStyle,
          (currentExStyle & ~wsExTransparent) | wsExLayered | wsExNoActivate | wsExTopMost | wsExToolWindow,
        );
      } catch (_) {}
    }

    // 2. Đặt vị trí bao phủ toàn màn hình cố định (0, 0, width, height) ở chế độ Topmost
    _setWindowPos?.call(
      hwnd,
      hwndTopMost,
      0,
      0,
      width,
      height,
      swpNoActivate | swpShowWindow | swpFrameChanged,
    );

    // 3. Yêu cầu vẽ lại frame ngay lập tức
    _invalidateRect?.call(hwnd, nullptr, 1);

    _logger.info('Đã hiển thị Fullscreen Transparent Overlay (${width}x$height)');
    return true;
  }

  /// Ẩn tương tác Overlay: Bật cờ xuyên thấu WS_EX_TRANSPARENT để mọi click đi thẳng vào game
  static bool hideOverlayWindow() {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) return false;

    // Gắn cờ WS_EX_TRANSPARENT (Click-Through) để chuột/cảm ứng không bị cản trở
    if (_getWindowLongPtrW != null && _setWindowLongPtrW != null) {
      try {
        final currentExStyle = _getWindowLongPtrW!(hwnd, gwlExStyle);
        _setWindowLongPtrW!(
          hwnd,
          gwlExStyle,
          currentExStyle | wsExTransparent | wsExNoActivate,
        );
      } catch (_) {}
    }

    _logger.info('Đã chuyển Overlay sang trạng thái xuyên thấu (WS_EX_TRANSPARENT Click-Through)');
    return true;
  }

  /// Kiểm tra trạng thái hiển thị của cửa sổ Win32
  static bool isWindowVisible() {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) return false;
    return (_isWindowVisible?.call(hwnd) ?? 0) != 0;
  }
}
