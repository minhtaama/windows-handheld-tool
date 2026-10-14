import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';

final class _GuidStruct extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Uint8()
  external int data4_0;
  @Uint8()
  external int data4_1;
  @Uint8()
  external int data4_2;
  @Uint8()
  external int data4_3;
  @Uint8()
  external int data4_4;
  @Uint8()
  external int data4_5;
  @Uint8()
  external int data4_6;
  @Uint8()
  external int data4_7;
}

final class _RectStruct extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

typedef _LocationC = Int32 Function(Pointer<Void> thisPtr, Pointer<_RectStruct> prcInputPaneScreenLocation);
typedef _LocationDart = int Function(Pointer<Void> thisPtr, Pointer<_RectStruct> prcInputPaneScreenLocation);

typedef _CoInitializeExC = Int32 Function(Pointer<Void> pvReserved, Uint32 dwCoInit);
typedef _CoInitializeExDart = int Function(Pointer<Void> pvReserved, int dwCoInit);

typedef _CoCreateInstanceC = Int32 Function(
  Pointer<_GuidStruct> rclsid,
  Pointer<Void> pUnkOuter,
  Uint32 dwClsContext,
  Pointer<_GuidStruct> riid,
  Pointer<Pointer<Void>> ppv,
);
typedef _CoCreateInstanceDart = int Function(
  Pointer<_GuidStruct> rclsid,
  Pointer<Void> pUnkOuter,
  int dwClsContext,
  Pointer<_GuidStruct> riid,
  Pointer<Pointer<Void>> ppv,
);

typedef _GetDesktopWindowC = IntPtr Function();
typedef _GetDesktopWindowDart = int Function();

typedef _GetAsyncKeyStateC = Int16 Function(Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

typedef _FindWindowWC = IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef _FindWindowWDart = int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);

typedef _FindWindowExWC = IntPtr Function(
  IntPtr hWndParent,
  IntPtr hWndChildAfter,
  Pointer<Utf16> lpszClass,
  Pointer<Utf16> lpszWindow,
);
typedef _FindWindowExWDart = int Function(
  int hWndParent,
  int hWndChildAfter,
  Pointer<Utf16> lpszClass,
  Pointer<Utf16> lpszWindow,
);

typedef _IsWindowVisibleC = Int32 Function(IntPtr hWnd);
typedef _IsWindowVisibleDart = int Function(int hWnd);

typedef _DwmGetWindowAttributeC = Int32 Function(
  IntPtr hwnd,
  Uint32 dwAttribute,
  Pointer<Void> pvAttribute,
  Uint32 cbAttribute,
);
typedef _DwmGetWindowAttributeDart = int Function(
  int hwnd,
  int dwAttribute,
  Pointer<Void> pvAttribute,
  int cbAttribute,
);

typedef _ToggleC = Int32 Function(Pointer<Void> thisPtr, IntPtr hwndDesktop);
typedef _ToggleDart = int Function(Pointer<Void> thisPtr, int hwndDesktop);

typedef _ReleaseC = Uint32 Function(Pointer<Void> thisPtr);
typedef _ReleaseDart = int Function(Pointer<Void> thisPtr);

/// Dịch vụ điều khiển Bàn phím ảo Windows Touch Keyboard (TabTip).
/// Gọi trực tiếp COM Interface ITipInvocation::Toggle qua Win32 OLE FFI (tốc độ < 1ms).
class VirtualKeyboardService {
  static const _logger = AppLogger('VirtualKeyboard');

  static bool _isToggling = false;
  static DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static _CoInitializeExDart? _coInitializeEx;
  static _CoCreateInstanceDart? _coCreateInstance;
  static _GetDesktopWindowDart? _getDesktopWindow;
  static _GetAsyncKeyStateDart? _getAsyncKeyState;
  static _FindWindowWDart? _findWindowW;
  static _FindWindowExWDart? _findWindowExW;
  static _IsWindowVisibleDart? _isWindowVisible;
  static _DwmGetWindowAttributeDart? _dwmGetWindowAttribute;
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    try {
      final ole32 = DynamicLibrary.open('ole32.dll');
      final user32 = DynamicLibrary.open('user32.dll');

      _coInitializeEx = ole32.lookupFunction<_CoInitializeExC, _CoInitializeExDart>('CoInitializeEx');
      _coCreateInstance = ole32.lookupFunction<_CoCreateInstanceC, _CoCreateInstanceDart>('CoCreateInstance');
      _getDesktopWindow = user32.lookupFunction<_GetDesktopWindowC, _GetDesktopWindowDart>('GetDesktopWindow');
      _getAsyncKeyState = user32.lookupFunction<_GetAsyncKeyStateC, _GetAsyncKeyStateDart>('GetAsyncKeyState');
      _findWindowW = user32.lookupFunction<_FindWindowWC, _FindWindowWDart>('FindWindowW');
      _findWindowExW = user32.lookupFunction<_FindWindowExWC, _FindWindowExWDart>('FindWindowExW');
      _isWindowVisible = user32.lookupFunction<_IsWindowVisibleC, _IsWindowVisibleDart>('IsWindowVisible');

      try {
        final dwmapi = DynamicLibrary.open('dwmapi.dll');
        _dwmGetWindowAttribute = dwmapi.lookupFunction<_DwmGetWindowAttributeC, _DwmGetWindowAttributeDart>('DwmGetWindowAttribute');
      } catch (_) {}

      // Khởi tạo COM Apartment Threaded (COINIT_APARTMENTTHREADED = 0x2)
      _coInitializeEx?.call(nullptr, 0x2);
      _initialized = true;
      _logger.info('Initialized Win32 OLE COM for ITipInvocation.');
    } catch (e) {
      _logger.error('Failed to initialize Win32 COM library', e);
    }
  }

  static bool _isPhysicalKeyDown(int vk) {
    if (_getAsyncKeyState == null || vk == 0) return false;
    final state = _getAsyncKeyState!(vk);
    return state < 0 || (state & 0x8000) != 0;
  }

  /// Kiểm tra xem có phím phần cứng nào đang bị nhấn hay không (Modifiers + Action VK)
  static bool isAnyPhysicalModifierOrKeyDown(int? actionVk) {
    _ensureInitialized();
    if (_getAsyncKeyState == null) return false;
    if (actionVk != null && actionVk > 0 && _isPhysicalKeyDown(actionVk)) {
      return true;
    }
    return _isPhysicalKeyDown(0x10) || // VK_SHIFT
        _isPhysicalKeyDown(0x11) || // VK_CONTROL
        _isPhysicalKeyDown(0x12) || // VK_MENU (Alt)
        _isPhysicalKeyDown(0x5B) || // VK_LWIN
        _isPhysicalKeyDown(0x5C) || // VK_RWIN
        _isPhysicalKeyDown(0xA0) || // VK_LSHIFT
        _isPhysicalKeyDown(0xA1) || // VK_RSHIFT
        _isPhysicalKeyDown(0xA2) || // VK_LCONTROL
        _isPhysicalKeyDown(0xA3) || // VK_RCONTROL
        _isPhysicalKeyDown(0xA4) || // VK_LMENU
        _isPhysicalKeyDown(0xA5);   // VK_RMENU
  }

  /// Kiểm tra một HWND có thực sự đang hiển thị trên màn hình hay không.
  static bool _isHwndReallyVisible(int hwnd) {
    if (hwnd == 0 || _isWindowVisible == null) return false;
    if (_isWindowVisible!(hwnd) == 0) return false;

    // Kiểm tra cờ DWMWA_CLOAKED (14) từ dwmapi.dll nếu khả dụng
    if (_dwmGetWindowAttribute != null) {
      final pCloaked = calloc<Uint32>();
      try {
        const dwmwaCloaked = 14;
        final hr = _dwmGetWindowAttribute!(hwnd, dwmwaCloaked, pCloaked.cast<Void>(), sizeOf<Uint32>());
        if (hr == 0 && pCloaked.value != 0) {
          return false;
        }
      } finally {
        calloc.free(pCloaked);
      }
    }

    return true;
  }

  /// Truy vấn trực tiếp vị trí hiển thị của Touch Keyboard qua COM Interface IFrameworkInputPane của Windows Shell.
  /// Phản ánh 100% tọa độ thực tế trên màn hình, bất kể người dùng mở/đóng bằng cảm ứng, nút X hay phím tắt.
  static bool isTouchKeyboardVisibleViaCom() {
    _ensureInitialized();
    if (_coCreateInstance == null) return false;

    // CLSID_FrameworkInputPane: D5120AA3-46BA-44C5-822D-CA8092C1FC72
    final clsid = calloc<_GuidStruct>()
      ..ref.data1 = 0xd5120aa3
      ..ref.data2 = 0x46ba
      ..ref.data3 = 0x44c5
      ..ref.data4_0 = 0x82
      ..ref.data4_1 = 0x2d
      ..ref.data4_2 = 0xca
      ..ref.data4_3 = 0x80
      ..ref.data4_4 = 0x92
      ..ref.data4_5 = 0xc1
      ..ref.data4_6 = 0xfc
      ..ref.data4_7 = 0x72;

    // IID_IFrameworkInputPane: 5752238B-24F0-495A-82F1-2FD593056796
    final iid = calloc<_GuidStruct>()
      ..ref.data1 = 0x5752238b
      ..ref.data2 = 0x24f0
      ..ref.data3 = 0x495a
      ..ref.data4_0 = 0x82
      ..ref.data4_1 = 0xf1
      ..ref.data4_2 = 0x2f
      ..ref.data4_3 = 0xd5
      ..ref.data4_4 = 0x93
      ..ref.data4_5 = 0x05
      ..ref.data4_6 = 0x67
      ..ref.data4_7 = 0x96;

    final ppv = calloc<Pointer<Void>>();
    const clsctx = 0x1; // CLSCTX_INPROC_SERVER

    try {
      final hr = _coCreateInstance!(clsid, nullptr, clsctx, iid, ppv);
      if (hr == 0 && ppv.value != nullptr) {
        final pInterface = ppv.value;
        final vtable = pInterface.cast<Pointer<IntPtr>>().value;

        // Slot 6: Location(RECT *prcInputPaneScreenLocation)
        final locationAddr = (vtable + 6).value;
        final locationFn = Pointer<NativeFunction<_LocationC>>.fromAddress(locationAddr).asFunction<_LocationDart>();

        final pRect = calloc<_RectStruct>();
        try {
          final res = locationFn(pInterface, pRect);
          final isVisible = res == 0 && (pRect.ref.bottom > 0 && pRect.ref.right > 0);
          if (isVisible) {
            _logger.info('IFrameworkInputPane reports Touch Keyboard visible at (${pRect.ref.left}, ${pRect.ref.top}, ${pRect.ref.right}, ${pRect.ref.bottom}).');
          }
          return isVisible;
        } finally {
          calloc.free(pRect);
          final releaseAddr = (vtable + 2).value;
          final releaseFn = Pointer<NativeFunction<_ReleaseC>>.fromAddress(releaseAddr).asFunction<_ReleaseDart>();
          releaseFn(pInterface);
        }
      }
    } catch (e) {
      _logger.warning('Query IFrameworkInputPane error: $e');
    } finally {
      calloc.free(ppv);
      calloc.free(clsid);
      calloc.free(iid);
    }
    return false;
  }

  /// Kiểm tra xem Bàn phím ảo Windows (Touch Keyboard) có đang hiển thị trên màn hình hay không.
  /// Kết hợp COM Interface chuẩn IFrameworkInputPane và dự phòng quét cửa sổ Win32.
  static bool isKeyboardVisible() {
    // 1. Kiểm tra ưu tiên: Giao diện COM chính thức IFrameworkInputPane của Windows Shell
    if (isTouchKeyboardVisibleViaCom()) {
      return true;
    }

    _ensureInitialized();
    if (_findWindowW == null) return false;

    // 2. Dự phòng: Kiểm tra cửa sổ TabTip truyền thống (IPTip_Main_Window)
    final legacyClass = 'IPTip_Main_Window'.toNativeUtf16();
    try {
      final hwndLegacy = _findWindowW!(legacyClass, nullptr);
      if (_isHwndReallyVisible(hwndLegacy)) {
        return true;
      }
    } finally {
      calloc.free(legacyClass);
    }

    // 3. Dự phòng: Quét các biến thể tiêu đề hiện đại trên Windows 11 & Windows 10
    final modernCaptions = [
      'Windows Input Experience',
      'Microsoft Text Input Application',
    ];
    final coreWindowClass = 'Windows.UI.Core.CoreWindow'.toNativeUtf16();
    final appFrameClass = 'ApplicationFrameWindow'.toNativeUtf16();

    try {
      for (final title in modernCaptions) {
        final modernCaption = title.toNativeUtf16();
        try {
          final hwndTopCaption = _findWindowW!(nullptr, modernCaption);
          if (_isHwndReallyVisible(hwndTopCaption)) {
            return true;
          }

          final hwndCore = _findWindowW!(coreWindowClass, modernCaption);
          if (_isHwndReallyVisible(hwndCore)) {
            return true;
          }

          if (_findWindowExW != null) {
            int parent = 0;
            while (true) {
              parent = _findWindowExW!(0, parent, appFrameClass, nullptr);
              if (parent == 0) break;
              final child = _findWindowExW!(parent, 0, coreWindowClass, modernCaption);
              if (_isHwndReallyVisible(child)) {
                return true;
              }
            }
          }
        } finally {
          calloc.free(modernCaption);
        }
      }
    } finally {
      calloc.free(coreWindowClass);
      calloc.free(appFrameClass);
    }

    return false;
  }

  /// Kích hoạt Toggle bàn phím ảo (Touch Keyboard) của Windows 10/11.
  /// Tích hợp cơ chế chờ nhả phím vật lý tự thích ứng (Hardware Key Release Polling)
  /// và nhận diện thông minh trạng thái Auto-Dismiss khi bàn phím đang mở.
  static Future<bool> toggleKeyboard({
    bool fromGamepad = false,
    int? actionVk,
  }) async {
    // 1. Chống gọi đè (Re-entrancy Guard) và Debounce 900ms
    final now = DateTime.now();
    if (_isToggling || now.isBefore(_cooldownUntil)) {
      _logger.info('Ignored toggleKeyboard request due to active lock or debounce.');
      return false;
    }

    _isToggling = true;
    _cooldownUntil = now.add(const Duration(milliseconds: 900));

    try {
      _ensureInitialized();

      // Kiểm tra xem bàn phím ảo có ĐANG MỞ trước khi người dùng thực hiện thao tác hay không
      final wasOpen = isKeyboardVisible();
      _logger.info('toggleKeyboard called: initial wasOpen=$wasOpen, fromGamepad=$fromGamepad');

      // 2. Chờ cho tới khi người dùng nhấc hoàn toàn ngón tay khỏi tất cả các phím phần cứng
      // (Bỏ qua hoàn toàn đối với Gamepad vì nút tay cầm không sinh thông điệp WM_KEYUP của bàn phím).
      if (!fromGamepad && _getAsyncKeyState != null) {
        final startWait = DateTime.now();
        // Quét liên tục mỗi 15ms, tối đa 600ms đề phòng trường hợp phím bị kẹt phần cứng
        while (DateTime.now().difference(startWait).inMilliseconds < 600) {
          if (!isAnyPhysicalModifierOrKeyDown(actionVk)) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 15));
        }
        // Thêm khoảng đệm an toàn 80ms để Windows dọn sạch hàng đợi thông điệp WM_KEYUP
        await Future.delayed(const Duration(milliseconds: 80));

        // NẾU BÀN PHÍM VỪA MỞ TRƯỚC ĐÓ:
        // Ngay khi ngón tay người dùng bấm phím phần cứng (Ctrl/Shift/K), Windows Touch Keyboard
        // đã lập tức tự động thu bàn phím lại (Auto-Dismiss).
        // Mục tiêu "đóng bàn phím" của người dùng đã hoàn tất!
        // Nếu tiếp tục gọi Toggle(), lệnh này sẽ vô tình mở ngược bàn phím ra lại.
        if (wasOpen) {
          _logger.info('Virtual keyboard was already open and auto-dismissed by hardware keypress. Keeping it closed.');
          return true;
        }
      }

      if (_coCreateInstance == null || _getDesktopWindow == null) {
        _logger.warning('COM APIs not available.');
        return false;
      }

      // CLSID_UIHostNoLaunch: 4ce576fa-83dc-4f88-951c-9d0782b4e376
      final clsid = calloc<_GuidStruct>()
        ..ref.data1 = 0x4ce576fa
        ..ref.data2 = 0x83dc
        ..ref.data3 = 0x4f88
        ..ref.data4_0 = 0x95
        ..ref.data4_1 = 0x1c
        ..ref.data4_2 = 0x9d
        ..ref.data4_3 = 0x07
        ..ref.data4_4 = 0x82
        ..ref.data4_5 = 0xb4
        ..ref.data4_6 = 0xe3
        ..ref.data4_7 = 0x76;

      // IID_ITipInvocation: 37c994e7-432b-4834-a2f7-dce1f13b834b
      final iid = calloc<_GuidStruct>()
        ..ref.data1 = 0x37c994e7
        ..ref.data2 = 0x432b
        ..ref.data3 = 0x4834
        ..ref.data4_0 = 0xa2
        ..ref.data4_1 = 0xf7
        ..ref.data4_2 = 0xdc
        ..ref.data4_3 = 0xe1
        ..ref.data4_4 = 0xf1
        ..ref.data4_5 = 0x3b
        ..ref.data4_6 = 0x83
        ..ref.data4_7 = 0x4b;

      final ppv = calloc<Pointer<Void>>();
      const clsctx = 0x4 | 0x1; // CLSCTX_LOCAL_SERVER | CLSCTX_INPROC_SERVER

      try {
        final hr = _coCreateInstance!(clsid, nullptr, clsctx, iid, ppv);
        if (hr == 0 && ppv.value != nullptr) {
          final pInterface = ppv.value;
          final vtable = pInterface.cast<Pointer<IntPtr>>().value;

          // ITipInvocation::Toggle(HWND hwndDesktop) nằm ở vị trí slot 3 trong VTable
          final toggleAddr = (vtable + 3).value;
          final toggleFn = Pointer<NativeFunction<_ToggleC>>.fromAddress(toggleAddr).asFunction<_ToggleDart>();

          final hwndDesktop = _getDesktopWindow!();
          final toggleRes = toggleFn(pInterface, hwndDesktop);

          // Release COM Interface (slot 2)
          final releaseAddr = (vtable + 2).value;
          final releaseFn = Pointer<NativeFunction<_ReleaseC>>.fromAddress(releaseAddr).asFunction<_ReleaseDart>();
          releaseFn(pInterface);

          _logger.info('Executed ITipInvocation.Toggle() via Win32 FFI successfully (hr: 0x${toggleRes.toRadixString(16)}).');
          return toggleRes == 0;
        } else {
          _logger.warning('CoCreateInstance ITipInvocation failed with HRESULT: 0x${hr.toRadixString(16)}');
          return false;
        }
      } finally {
        calloc.free(ppv);
        calloc.free(clsid);
        calloc.free(iid);
      }
    } catch (e) {
      _logger.error('Error toggling virtual keyboard via FFI', e);
      return false;
    } finally {
      _isToggling = false;
    }
  }
}
