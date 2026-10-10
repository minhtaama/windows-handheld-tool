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
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    try {
      final ole32 = DynamicLibrary.open('ole32.dll');
      final user32 = DynamicLibrary.open('user32.dll');

      _coInitializeEx = ole32.lookupFunction<_CoInitializeExC, _CoInitializeExDart>('CoInitializeEx');
      _coCreateInstance = ole32.lookupFunction<_CoCreateInstanceC, _CoCreateInstanceDart>('CoCreateInstance');
      _getDesktopWindow = user32.lookupFunction<_GetDesktopWindowC, _GetDesktopWindowDart>('GetDesktopWindow');

      // Khởi tạo COM Apartment Threaded (COINIT_APARTMENTTHREADED = 0x2)
      _coInitializeEx?.call(nullptr, 0x2);
      _initialized = true;
      _logger.info('Initialized Win32 OLE COM for ITipInvocation.');
    } catch (e) {
      _logger.error('Failed to initialize Win32 COM library', e);
    }
  }

  /// Kích hoạt Toggle bàn phím ảo (Touch Keyboard) của Windows 10/11.
  /// Độ trễ thực thi siêu thấp (~0.5ms), tích hợp khóa Mutex và Debounce chống dội phím.
  static Future<bool> toggleKeyboard() async {
    // 1. Chống gọi đè (Re-entrancy Guard) và Debounce 600ms
    final now = DateTime.now();
    if (_isToggling || now.isBefore(_cooldownUntil)) {
      _logger.info('Ignored toggleKeyboard request due to active lock or debounce.');
      return false;
    }

    _isToggling = true;
    _cooldownUntil = now.add(const Duration(milliseconds: 800));

    try {
      // Chờ 250ms để ngón tay kịp nhấc khỏi phím vật lý trước khi mở bàn phím ảo.
      // Ngăn chặn cơ chế Windows tự động đóng Touch Keyboard (Auto-dismiss) khi bắt được tín hiệu từ bàn phím phần cứng.
      await Future.delayed(const Duration(milliseconds: 250));

      _ensureInitialized();
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
