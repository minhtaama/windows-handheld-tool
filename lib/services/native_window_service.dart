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

typedef _GetForegroundWindowC = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _SetForegroundWindowC = Int32 Function(IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);

typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr hWnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart = int Function(int hWnd, Pointer<Uint32> lpdwProcessId);

/// Dịch vụ quản lý cửa sổ Native Win32 tối ưu cho Handheld Quick Settings Side Dock Window.
/// Cửa sổ chỉ có kích thước đúng bằng bề rộng của Panel neo ở mép phải màn hình,
/// không che khuất màn hình Desktop/Game và không cướp Focus (SWP_NOACTIVATE).
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

  static const int smCxScreen = 0;
  static const int smCyScreen = 1;

  static _FindWindowWDart? _findWindowW;
  static _SetWindowPosDart? _setWindowPos;
  static _GetSystemMetricsDart? _getSystemMetrics;
  static _IsWindowDart? _isWindow;
  static _InvalidateRectDart? _invalidateRect;
  static _GetWindowLongPtrWDart? _getWindowLongPtrW;
  static _SetWindowLongPtrWDart? _setWindowLongPtrW;
  static _GetForegroundWindowDart? _getForegroundWindow;
  static _SetForegroundWindowDart? _setForegroundWindow;
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
      _getForegroundWindow = user32.lookupFunction<_GetForegroundWindowC, _GetForegroundWindowDart>('GetForegroundWindow');
      _setForegroundWindow = user32.lookupFunction<_SetForegroundWindowC, _SetForegroundWindowDart>('SetForegroundWindow');
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

  /// Chuyển tiêu điểm hệ điều hành lên cửa sổ chỉ định (Foreground Window)
  static bool setForegroundWindow(int hwnd) {
    if (hwnd == 0) return false;
    _ensureInitialized();
    return (_setForegroundWindow?.call(hwnd) ?? 0) != 0;
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

  /// Hiển thị Side Dock Panel neo sát mép phải màn hình mà KHÔNG cướp Focus của Game
  static bool showDockWindow({required int panelWidth}) {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) {
      _logger.warning('Flutter window HWND not found');
      return false;
    }

    final physicalSize = getPhysicalScreenSize();
    final screenWidth = physicalSize.width.toInt();
    final screenHeight = physicalSize.height.toInt();
    final posX = screenWidth - panelWidth;

    // 1. Cấu hình Extended Styles: Duy trì WS_EX_TOOLWINDOW và WS_EX_NOACTIVATE, gỡ bỏ WS_EX_TRANSPARENT
    if (_getWindowLongPtrW != null && _setWindowLongPtrW != null) {
      try {
        final currentExStyle = _getWindowLongPtrW!(hwnd, gwlExStyle);
        _setWindowLongPtrW!(
          hwnd,
          gwlExStyle,
          (currentExStyle & ~wsExTransparent & ~wsExLayered) | wsExNoActivate | wsExTopMost | wsExToolWindow,
        );
      } catch (_) {}
    }

    // 2. Định vị cửa sổ neo sát mép phải (posX, 0, panelWidth, screenHeight) với SWP_NOACTIVATE
    _setWindowPos?.call(
      hwnd,
      hwndTopMost,
      posX,
      0,
      panelWidth,
      screenHeight,
      swpNoActivate | swpShowWindow | swpFrameChanged,
    );

    // 3. Yêu cầu vẽ lại frame ngay lập tức
    _invalidateRect?.call(hwnd, nullptr, 1);

    _logger.info('Hiển thị Side Dock Window tại X: $posX, Width: $panelWidth, Height: $screenHeight');
    return true;
  }

  /// Thay đổi bề rộng Side Dock Window khi người dùng kéo thanh trượt Cài đặt
  static bool resizeDockWindow({required int panelWidth}) {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) return false;

    final physicalSize = getPhysicalScreenSize();
    final screenWidth = physicalSize.width.toInt();
    final screenHeight = physicalSize.height.toInt();
    final posX = screenWidth - panelWidth;

    _setWindowPos?.call(
      hwnd,
      hwndTopMost,
      posX,
      0,
      panelWidth,
      screenHeight,
      swpNoActivate | swpFrameChanged,
    );

    _invalidateRect?.call(hwnd, nullptr, 1);
    _logger.info('Co dãn Side Dock Window tới Width: $panelWidth, X: $posX');
    return true;
  }

  /// Ẩn Side Dock Panel: Dời cửa sổ ra ngoài màn hình vật lý (Off-Screen)
  /// TUYỆT ĐỐI KHÔNG dùng SW_HIDE để duy trì IsWindowVisible == TRUE cho Windows 11 Taskbar
  static bool hideDockWindow() {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) return false;

    final physicalSize = getPhysicalScreenSize();
    final screenWidth = physicalSize.width.toInt();
    final screenHeight = physicalSize.height.toInt();

    // Dời tọa độ ra ngoài mép phải màn hình (X = screenWidth) với kích thước tối thiểu
    _setWindowPos?.call(
      hwnd,
      hwndTopMost,
      screenWidth,
      0,
      1,
      screenHeight,
      swpNoActivate,
    );

    _logger.info('Đã thu ẩn Side Dock Window ra ngoài màn hình (Off-screen, giữ IsWindowVisible cho Taskbar)');
    return true;
  }

  /// Chuẩn bị cửa sổ để hiển thị menu ngữ cảnh chuột phải trên Khay hệ thống (System Tray)
  /// Win32 TrackPopupMenu yêu cầu cửa sổ hợp lệ để tiếp nhận thông điệp menu
  static void prepareForContextMenu() {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) return;
    _setForegroundWindow?.call(hwnd);
  }
}

