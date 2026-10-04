import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';

// Cấu trúc XINPUT_GAMEPAD và XINPUT_STATE của Windows SDK
final class _XInputGamepad extends Struct {
  @Uint16()
  external int wButtons;

  @Uint8()
  external int bLeftTrigger;

  @Uint8()
  external int bRightTrigger;

  @Int16()
  external int sThumbLX;

  @Int16()
  external int sThumbLY;

  @Int16()
  external int sThumbRX;

  @Int16()
  external int sThumbRY;
}

final class _XInputState extends Struct {
  @Uint32()
  external int dwPacketNumber;

  external _XInputGamepad gamepad;
}

typedef _XInputGetStateC = Uint32 Function(Uint32 dwUserIndex, Pointer<_XInputState> pState);
typedef _XInputGetStateDart = int Function(int dwUserIndex, Pointer<_XInputState> pState);

/// Dịch vụ theo dõi tín hiệu tay cầm Handheld (XInput) để kích hoạt Quick Settings.
class GamepadService {
  static const _logger = AppLogger('GamepadService');

  // Bitmask các phím XInput chuẩn
  static const int xinputGamepadBack = 0x0020;
  static const int xinputGamepadRightShoulder = 0x0200; // Nút RB

  static _XInputGetStateDart? _xInputGetState;
  static Timer? _pollTimer;
  static Pointer<_XInputState>? _pState;
  static bool _wasComboPressed = false;

  static void start({
    required void Function() onTriggerCombo,
    int intervalMs = 50,
  }) {
    if (_pollTimer != null) return;

    final candidateDlls = ['xinput1_4.dll', 'xinput1_3.dll', 'xinput9_1_0.dll'];
    for (final dll in candidateDlls) {
      try {
        final lib = DynamicLibrary.open(dll);
        _xInputGetState = lib.lookupFunction<_XInputGetStateC, _XInputGetStateDart>('XInputGetState');
        _logger.info('Đã kết nối thành công với $dll.');
        break;
      } catch (_) {}
    }

    if (_xInputGetState == null) {
      _logger.warning('Không tìm thấy thư viện XInput DLL trên máy.');
      return;
    }

    _pState = calloc<_XInputState>();

    // Vòng lặp quét trạng thái tay cầm định kỳ
    _pollTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      try {
        bool anyComboPressed = false;

        // Quét qua tối đa 4 tay cầm kết nối
        for (int i = 0; i < 4; i++) {
          final res = _xInputGetState!(i, _pState!);
          if (res == 0) { // ERROR_SUCCESS = 0
            final buttons = _pState!.ref.gamepad.wButtons;
            final isBackPressed = (buttons & xinputGamepadBack) != 0;
            final isRbPressed = (buttons & xinputGamepadRightShoulder) != 0;

            if (isBackPressed && isRbPressed) {
              anyComboPressed = true;
              break;
            }
          }
        }

        // Bắt sự kiện chuyển từ Chưa Bấm -> Bấm (chống kích hoạt lặp liên tục)
        if (anyComboPressed && !_wasComboPressed) {
          _wasComboPressed = true;
          _logger.info('Nhận tổ hợp phím tay cầm: BACK + RB');
          onTriggerCombo();
        } else if (!anyComboPressed) {
          _wasComboPressed = false;
        }
      } catch (e) {
        _logger.error('Lỗi khi quét trạng thái Gamepad', e);
      }
    });

    _logger.info('Gamepad listener đã khởi động (Tổ hợp: BACK + RB).');
  }

  static void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_pState != null) {
      calloc.free(_pState!);
      _pState = null;
    }
    _logger.info('Gamepad listener đã dừng.');
  }
}
