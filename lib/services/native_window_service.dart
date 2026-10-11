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

typedef _IsWindowC = Int32 Function(IntPtr hWnd);
typedef _IsWindowDart = int Function(int hWnd);

typedef _InvalidateRectC = Int32 Function(IntPtr hWnd, Pointer<Void> lpRect, Int32 bErase);
typedef _InvalidateRectDart = int Function(int hWnd, Pointer<Void> lpRect, int bErase);

typedef _SetLayeredWindowAttributesC = Int32 Function(IntPtr hWnd, Uint32 crKey, Uint8 bAlpha, Uint32 dwFlags);
typedef _SetLayeredWindowAttributesDart = int Function(int hWnd, int crKey, int bAlpha, int dwFlags);

typedef _GetForegroundWindowC = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr hWnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart = int Function(int hWnd, Pointer<Uint32> lpdwProcessId);

/// Dịch vụ quản lý cửa sổ Native Win32 tối ưu cho Gaming Overlay chuẩn Fullscreen Transparent Overlay.
/// Bao phủ toàn màn hình cố định và sử dụng SWP_NOACTIVATE
/// để đảm bảo không cướp Focus của Game (chống văng/minimize game DirectX).
class NativeWindowService {
  static const _logger = AppLogger('NativeWindowService');

  static const int hwndTopMost = -1;

  static const int swpNoSize = 0x0001;
  static const int swpNoMove = 0x0002;
  static const int swpNoActivate = 0x0010;
  static const int swpFrameChanged = 0x0020;
  static const int swpShowWindow = 0x0040;

  static const int gwlExStyle = -20;
  static const int wsExTransparent = 0x00000020;
  static const int wsExTopMost = 0x00000008;
  static const int wsExToolWindow = 0x00000080;
  static const int wsExNoActivate = 0x08000000;
  static const int wsExLayered = 0x00080000;

  static const int lwaAlpha = 0x00000002;

  static const int smCxScreen = 0;
  static const int smCyScreen = 1;

  static _FindWindowWDart? _findWindowW;
  static _SetWindowPosDart? _setWindowPos;
  static _GetSystemMetricsDart? _getSystemMetrics;
  static _IsWindowDart? _isWindow;
  static _InvalidateRectDart? _invalidateRect;
  static _GetWindowLongPtrWDart? _getWindowLongPtrW;
  static _SetWindowLongPtrWDart? _setWindowLongPtrW;
  static _SetLayeredWindowAttributesDart? _setLayeredWindowAttributes;
  static _GetForegroundWindowDart? _getForegroundWindow;
  static _GetWindowThreadProcessIdDart? _getWindowThreadProcessId;

  static int? _cachedHwnd;

  static void _ensureInitialized() {
    if (_findWindowW != null) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _findWindowW = user32.lookupFunction<_FindWindowWC, _FindWindowWDart>('FindWindowW');
      _setWindowPos = user32.lookupFunction<_SetWindowPosC, _SetWindowPosDart>('SetWindowPos');
      _getSystemMetrics = user32.lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>('GetSystemMetrics');
      _isWindow = user32.lookupFunction<_IsWindowC, _IsWindowDart>('IsWindow');
      _invalidateRect = user32.lookupFunction<_InvalidateRectC, _InvalidateRectDart>('InvalidateRect');
      _setLayeredWindowAttributes = user32.lookupFunction<_SetLayeredWindowAttributesC, _SetLayeredWindowAttributesDart>('SetLayeredWindowAttributes');
      _getForegroundWindow = user32.lookupFunction<_GetForegroundWindowC, _GetForegroundWindowDart>('GetForegroundWindow');
      _getWindowThreadProcessId = user32.lookupFunction<_GetWindowThreadProcessIdC, _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');

      try {
        _getWindowLongPtrW = user32.lookupFunction<_GetWindowLongPtrWC, _GetWindowLongPtrWDart>('GetWindowLongPtrW');
        _setWindowLongPtrW = user32.lookupFunction<_SetWindowLongPtrWC, _SetWindowLongPtrWDart>('SetWindowLongPtrW');
      } catch (_) {
        _getWindowLongPtrW = user32.lookupFunction<_GetWindowLongPtrWC, _GetWindowLongPtrWDart>('GetWindowLongW');
        _setWindowLongPtrW = user32.lookupFunction<_SetWindowLongPtrWC, _SetWindowLongPtrWDart>('SetWindowLongW');
      }
    } catch (e) {
      _logger.error('Error loading user32.dll API', e);
    }
  }

  /// Lấy tay nắm HWND của cửa sổ đang kích hoạt trên cùng màn hình (Foreground Window)
  static int getForegroundWindow() {
    _ensureInitialized();
    return _getForegroundWindow != null ? _getForegroundWindow!() : 0;
  }

  /// Lấy Process ID (PID) của tiến trình sở hữu cửa sổ kích hoạt trên cùng
  static int getForegroundProcessId() {
    _ensureInitialized();
    final hwnd = getForegroundWindow();
    if (hwnd == 0 || _getWindowThreadProcessId == null) return 0;
    final pidPtr = calloc<Uint32>();
    try {
      _getWindowThreadProcessId!(hwnd, pidPtr);
      return pidPtr.value;
    } finally {
      calloc.free(pidPtr);
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
  static bool showOverlayNoActivate({Size? size}) {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) {
      _logger.warning('Flutter window HWND not found');
      return false;
    }

    final physicalSize = size ?? getPhysicalScreenSize();
    final width = physicalSize.width.toInt();
    final height = physicalSize.height.toInt();

    // 1. Cấu hình Extended Styles: Bỏ cờ WS_EX_TRANSPARENT để nhận cảm ứng/chuột,
    // duy trì WS_EX_TOOLWINDOW và WS_EX_NOACTIVATE để tuyệt đối không cướp Focus của Game
    // (ngăn chặn triệt để Game Engine bóp FPS xuống 15 và tránh lỗi DXGI_STATUS_OCCLUDED)
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

    // Đặt độ mờ alpha = 255 để hiển thị hoàn toàn nội dung giao diện
    _setLayeredWindowAttributes?.call(hwnd, 0, 255, lwaAlpha);

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

    _logger.info('Displayed Fullscreen Transparent Overlay (${width}x$height)');
    return true;
  }

  /// Ẩn tương tác Overlay: Bật cờ xuyên thấu WS_EX_TRANSPARENT và alpha 0 để mọi click đi thẳng vào game
  static bool hideOverlayWindow() {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) return false;

    // 1. Đặt alpha = 0 (trong suốt 100%) để tránh chớp nháy hoặc để sót bất kỳ frame nào trên màn hình
    _setLayeredWindowAttributes?.call(hwnd, 0, 0, lwaAlpha);

    // 2. Gắn cờ WS_EX_TRANSPARENT (Click-Through) để chuột/cảm ứng không bị cản trở
    if (_getWindowLongPtrW != null && _setWindowLongPtrW != null) {
      try {
        final currentExStyle = _getWindowLongPtrW!(hwnd, gwlExStyle);
        _setWindowLongPtrW!(
          hwnd,
          gwlExStyle,
          currentExStyle | wsExTransparent | wsExNoActivate | wsExToolWindow,
        );
      } catch (_) {}
    }

    _logger.info('Switched Overlay to click-through state (WS_EX_TRANSPARENT, Alpha 0)');
    return true;
  }
}
