import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';

/// Danh sách các nút tay cầm hỗ trợ tương tác với giao diện Quick Settings.
enum GamepadButton {
  dpadUp,
  dpadDown,
  dpadLeft,
  dpadRight,
  a,
  b,
  x,
  y,
  lb,
  rb,
  start,
  back,
}

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

/// Bộ theo dõi và xử lý lặp phím điều hướng khi người dùng giữ nút (D-Pad / Thumbstick).
class _NavRepeatTracker {
  int _holdTicks = 0;
  bool _isPressed = false;

  bool update(bool currentlyPressed) {
    if (!currentlyPressed) {
      _isPressed = false;
      _holdTicks = 0;
      return false;
    }

    if (!_isPressed) {
      _isPressed = true;
      _holdTicks = 1;
      return true; // Kích hoạt ngay lập tức ở lần bấm đầu tiên
    }

    _holdTicks++;
    // Sau 6 ticks (~300ms với poll 50ms), lặp lại mỗi 2 ticks (~100ms)
    if (_holdTicks >= 6 && (_holdTicks - 6) % 2 == 0) {
      return true;
    }

    return false;
  }
}

/// Bộ theo dõi sự kiện nút bấm đơn lẻ (chỉ kích hoạt một lần khi nhấn xuống).
class _ButtonTriggerTracker {
  bool _isPressed = false;

  bool update(bool currentlyPressed) {
    if (currentlyPressed && !_isPressed) {
      _isPressed = true;
      return true;
    } else if (!currentlyPressed) {
      _isPressed = false;
    }
    return false;
  }
}

/// Dịch vụ theo dõi tín hiệu tay cầm Handheld (XInput) để kích hoạt và thao tác Quick Settings.
class GamepadService {
  static const _logger = AppLogger('GamepadService');

  // Bitmask các phím XInput chuẩn
  static const int xinputGamepadDpadUp = 0x0001;
  static const int xinputGamepadDpadDown = 0x0002;
  static const int xinputGamepadDpadLeft = 0x0004;
  static const int xinputGamepadDpadRight = 0x0008;
  static const int xinputGamepadStart = 0x0010;
  static const int xinputGamepadBack = 0x0020;
  static const int xinputGamepadLeftShoulder = 0x0100; // Nút LB
  static const int xinputGamepadRightShoulder = 0x0200; // Nút RB
  static const int xinputGamepadA = 0x1000;
  static const int xinputGamepadB = 0x2000;
  static const int xinputGamepadX = 0x4000;
  static const int xinputGamepadY = 0x8000;

  static const int _stickDeadzone = 15000;

  static _XInputGetStateDart? _xInputGetState;
  static Timer? _pollTimer;
  static Pointer<_XInputState>? _pState;
  static bool _wasComboPressed = false;

  // Stream phát sự kiện nút bấm tay cầm tới UI
  static final StreamController<GamepadButton> _buttonEventsController =
      StreamController<GamepadButton>.broadcast();
  static Stream<GamepadButton> get buttonEvents => _buttonEventsController.stream;

  // Trình quản lý trạng thái phím
  static final _navUp = _NavRepeatTracker();
  static final _navDown = _NavRepeatTracker();
  static final _navLeft = _NavRepeatTracker();
  static final _navRight = _NavRepeatTracker();

  static final _btnA = _ButtonTriggerTracker();
  static final _btnB = _ButtonTriggerTracker();
  static final _btnX = _ButtonTriggerTracker();
  static final _btnY = _ButtonTriggerTracker();
  static final _btnLb = _ButtonTriggerTracker();
  static final _btnRb = _ButtonTriggerTracker();
  static final _btnStart = _ButtonTriggerTracker();
  static final _btnBack = _ButtonTriggerTracker();

  static bool _isConnected = false;
  /// Trạng thái phát hiện có ít nhất 1 tay cầm Gamepad đang kết nối
  static bool get isConnected => _isConnected;

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
        _logger.info('Connected to $dll successfully.');
        break;
      } catch (_) {}
    }

    if (_xInputGetState == null) {
      _logger.warning('XInput DLL not found on system.');
      return;
    }

    _pState = calloc<_XInputState>();

    // Vòng lặp quét trạng thái tay cầm định kỳ
    _pollTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      try {
        bool anyComboPressed = false;
        int activeButtons = 0;
        int activeThumbLX = 0;
        int activeThumbLY = 0;
        bool foundActiveGamepad = false;

        // Quét qua tối đa 4 tay cầm kết nối
        for (int i = 0; i < 4; i++) {
          final res = _xInputGetState!(i, _pState!);
          if (res == 0) { // ERROR_SUCCESS = 0
            foundActiveGamepad = true;
            final gamepad = _pState!.ref.gamepad;
            final buttons = gamepad.wButtons;

            final isBackPressed = (buttons & xinputGamepadBack) != 0;
            final isRbPressed = (buttons & xinputGamepadRightShoulder) != 0;

            if (isBackPressed && isRbPressed) {
              anyComboPressed = true;
            }

            activeButtons |= buttons;
            if (gamepad.sThumbLX.abs() > activeThumbLX.abs()) {
              activeThumbLX = gamepad.sThumbLX;
            }
            if (gamepad.sThumbLY.abs() > activeThumbLY.abs()) {
              activeThumbLY = gamepad.sThumbLY;
            }
          }
        }

        _isConnected = foundActiveGamepad;
        if (!foundActiveGamepad) return;

        // 1. Bắt sự kiện tổ hợp phím mở/tắt Overlay (BACK + RB)
        if (anyComboPressed && !_wasComboPressed) {
          _wasComboPressed = true;
          _logger.info('Gamepad combo triggered: BACK + RB');
          onTriggerCombo();
          return;
        } else if (!anyComboPressed) {
          _wasComboPressed = false;
        }

        // Nếu đang giữ tổ hợp thì không phát các nút riêng rẽ để tránh nhận nhầm
        if (anyComboPressed || _wasComboPressed) {
          return;
        }

        // 2. Xử lý điều hướng D-Pad và Cần Analog trái
        final stickUp = activeThumbLY > _stickDeadzone;
        final stickDown = activeThumbLY < -_stickDeadzone;
        final stickLeft = activeThumbLX < -_stickDeadzone;
        final stickRight = activeThumbLX > _stickDeadzone;

        final isUp = ((activeButtons & xinputGamepadDpadUp) != 0) || stickUp;
        final isDown = ((activeButtons & xinputGamepadDpadDown) != 0) || stickDown;
        final isLeft = ((activeButtons & xinputGamepadDpadLeft) != 0) || stickLeft;
        final isRight = ((activeButtons & xinputGamepadDpadRight) != 0) || stickRight;

        if (_navUp.update(isUp)) {
          _buttonEventsController.add(GamepadButton.dpadUp);
        }
        if (_navDown.update(isDown)) {
          _buttonEventsController.add(GamepadButton.dpadDown);
        }
        if (_navLeft.update(isLeft)) {
          _buttonEventsController.add(GamepadButton.dpadLeft);
        }
        if (_navRight.update(isRight)) {
          _buttonEventsController.add(GamepadButton.dpadRight);
        }

        // 3. Xử lý các nút bấm hành động (A, B, X, Y, LB, RB, Start, Back)
        if (_btnA.update((activeButtons & xinputGamepadA) != 0)) {
          _buttonEventsController.add(GamepadButton.a);
        }
        if (_btnB.update((activeButtons & xinputGamepadB) != 0)) {
          _buttonEventsController.add(GamepadButton.b);
        }
        if (_btnX.update((activeButtons & xinputGamepadX) != 0)) {
          _buttonEventsController.add(GamepadButton.x);
        }
        if (_btnY.update((activeButtons & xinputGamepadY) != 0)) {
          _buttonEventsController.add(GamepadButton.y);
        }
        if (_btnLb.update((activeButtons & xinputGamepadLeftShoulder) != 0)) {
          _buttonEventsController.add(GamepadButton.lb);
        }
        if (_btnRb.update((activeButtons & xinputGamepadRightShoulder) != 0)) {
          _buttonEventsController.add(GamepadButton.rb);
        }
        if (_btnStart.update((activeButtons & xinputGamepadStart) != 0)) {
          _buttonEventsController.add(GamepadButton.start);
        }
        if (_btnBack.update((activeButtons & xinputGamepadBack) != 0)) {
          _buttonEventsController.add(GamepadButton.back);
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
