import 'dart:ffi' hide Size;
import 'dart:ui';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';

typedef _FindWindowWC = IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef _FindWindowWDart = int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);

typedef _ShowWindowC = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hWnd, int nCmdShow);

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

typedef _IsWindowVisibleC = Int32 Function(IntPtr hWnd);
typedef _IsWindowVisibleDart = int Function(int hWnd);

typedef _IsWindowC = Int32 Function(IntPtr hWnd);
typedef _IsWindowDart = int Function(int hWnd);

/// Dịch vụ quản lý cửa sổ Native Win32 tối ưu cho Gaming Overlay.
/// Điều khiển cửa sổ với SW_SHOWNOACTIVATE và SWP_NOACTIVATE
/// để đảm bảo không cướp Focus của Game (chống văng/minimize game DirectX).
class NativeWindowService {
  static const _logger = AppLogger('NativeWindowService');

  static const int swHide = 0;
  static const int swShowNoActivate = 4;
  static const int swShow = 5;

  static const int hwndTopMost = -1;

  static const int swpNoSize = 0x0001;
  static const int swpNoMove = 0x0002;
  static const int swpNoZOrder = 0x0004;
  static const int swpNoActivate = 0x0010;
  static const int swpShowWindow = 0x0040;
  static const int swpHideWindow = 0x0080;

  static const int smCxScreen = 0;
  static const int smCyScreen = 1;

  static _FindWindowWDart? _findWindowW;
  static _ShowWindowDart? _showWindow;
  static _SetWindowPosDart? _setWindowPos;
  static _GetSystemMetricsDart? _getSystemMetrics;
  static _IsWindowVisibleDart? _isWindowVisible;
  static _IsWindowDart? _isWindow;

  static int? _cachedHwnd;

  static void _ensureInitialized() {
    if (_findWindowW != null) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _findWindowW = user32.lookupFunction<_FindWindowWC, _FindWindowWDart>('FindWindowW');
      _showWindow = user32.lookupFunction<_ShowWindowC, _ShowWindowDart>('ShowWindow');
      _setWindowPos = user32.lookupFunction<_SetWindowPosC, _SetWindowPosDart>('SetWindowPos');
      _getSystemMetrics = user32.lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>('GetSystemMetrics');
      _isWindowVisible = user32.lookupFunction<_IsWindowVisibleC, _IsWindowVisibleDart>('IsWindowVisible');
      _isWindow = user32.lookupFunction<_IsWindowC, _IsWindowDart>('IsWindow');
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
  /// (hoạt động chính xác ngay cả khi game đổi sang 720p / 800p / RSR / FSR)
  static Size getPhysicalScreenSize() {
    _ensureInitialized();
    if (_getSystemMetrics == null) {
      return const Size(1920, 1080);
    }
    final width = _getSystemMetrics!(smCxScreen);
    final height = _getSystemMetrics!(smCyScreen);
    return Size(width.toDouble(), height.toDouble());
  }

  /// Hiển thị cửa sổ Overlay ở trạng thái Always-on-Top mà KHÔNG cướp Focus của Game
  static bool showOverlayNoActivate({Size? size, Offset? position}) {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) {
      _logger.warning('Không tìm thấy HWND của cửa sổ Flutter');
      return false;
    }

    final targetSize = size ?? getPhysicalScreenSize();
    final posX = position?.dx.toInt() ?? 0;
    final posY = position?.dy.toInt() ?? 0;
    final width = targetSize.width.toInt();
    final height = targetSize.height.toInt();

    // 1. Đặt vị trí, kích thước và đưa lên Topmost mà không kích hoạt cửa sổ
    _setWindowPos?.call(
      hwnd,
      hwndTopMost,
      posX,
      posY,
      width,
      height,
      swpNoActivate | swpShowWindow,
    );

    // 2. Hiển thị cửa sổ mà không cướp tiêu điểm (Focus)
    _showWindow?.call(hwnd, swShowNoActivate);

    _logger.info('Đã hiển thị Overlay (SW_SHOWNOACTIVATE, Size: ${width}x$height)');
    return true;
  }

  /// Ẩn cửa sổ Overlay
  static bool hideOverlayWindow() {
    _ensureInitialized();
    final hwnd = getWindowHandle();
    if (hwnd == 0) return false;

    _showWindow?.call(hwnd, swHide);
    _logger.info('Đã ẩn Overlay (SW_HIDE)');
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
