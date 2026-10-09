import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
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

  void armAsPressed() {
    _isPressed = true;
  }

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
  // Bộ theo dõi sự kiện tổ hợp phím
  static String _overlayCombo = 'BACK + RB';
  static String _keyboardCombo = 'BACK + LB';
  static int _overlayMask = xinputGamepadBack | xinputGamepadRightShoulder;
  static int _keyboardMask = xinputGamepadBack | xinputGamepadLeftShoulder;

  static final _overlayTracker = _ButtonTriggerTracker();
  static final _keyboardTracker = _ButtonTriggerTracker();

  static DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static VoidCallback? _onToggleOverlay;
  static VoidCallback? _onToggleKeyboard;

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

  /// Phân giải chuỗi tổ hợp phím thành Bitmask XInput
  static int parseComboMask(String comboStr) {
    if (comboStr.isEmpty) return 0;
    final upper = comboStr.toUpperCase().trim();
    if (upper == 'TẮT' || upper == 'OFF' || upper == 'NONE') return 0;

    final parts = upper.split(RegExp(r'[\+\s]+'));
    int mask = 0;
    for (final part in parts) {
      switch (part) {
        case 'BACK':
          mask |= xinputGamepadBack;
          break;
        case 'START':
          mask |= xinputGamepadStart;
          break;
        case 'LB':
        case 'LEFT_SHOULDER':
          mask |= xinputGamepadLeftShoulder;
          break;
        case 'RB':
        case 'RIGHT_SHOULDER':
          mask |= xinputGamepadRightShoulder;
          break;
        case 'A':
          mask |= xinputGamepadA;
          break;
        case 'B':
          mask |= xinputGamepadB;
          break;
        case 'X':
          mask |= xinputGamepadX;
          break;
        case 'Y':
          mask |= xinputGamepadY;
          break;
        case 'UP':
          mask |= xinputGamepadDpadUp;
          break;
        case 'DOWN':
          mask |= xinputGamepadDpadDown;
          break;
        case 'LEFT':
          mask |= xinputGamepadDpadLeft;
          break;
        case 'RIGHT':
          mask |= xinputGamepadDpadRight;
          break;
      }
    }
    return mask;
  }

  /// Chuyển đổi Bitmask XInput thành chuỗi tổ hợp phím trực quan
  static String maskToComboString(int mask) {
    if (mask == 0) return '';
    final List<String> parts = [];
    if ((mask & xinputGamepadBack) != 0) parts.add('BACK');
    if ((mask & xinputGamepadStart) != 0) parts.add('START');
    if ((mask & xinputGamepadLeftShoulder) != 0) parts.add('LB');
    if ((mask & xinputGamepadRightShoulder) != 0) parts.add('RB');
    if ((mask & xinputGamepadA) != 0) parts.add('A');
    if ((mask & xinputGamepadB) != 0) parts.add('B');
    if ((mask & xinputGamepadX) != 0) parts.add('X');
    if ((mask & xinputGamepadY) != 0) parts.add('Y');
    if ((mask & xinputGamepadDpadUp) != 0) parts.add('UP');
    if ((mask & xinputGamepadDpadDown) != 0) parts.add('DOWN');
    if ((mask & xinputGamepadDpadLeft) != 0) parts.add('LEFT');
    if ((mask & xinputGamepadDpadRight) != 0) parts.add('RIGHT');
    return parts.join(' + ');
  }

  // Quản lý chế độ ghi nhận tổ hợp phím (Recording Mode)
  static bool _isRecordingCombo = false;
  static int _recordedMask = 0;
  static int _recordHoldTicks = 0;
  static const int _requiredHoldTicks = 10; // 10 ticks * 50ms = 500ms giữ ổn định
  static ValueChanged<String>? _onComboRecorded;
  static ValueChanged<double>? _onRecordProgress;
  static ValueChanged<String>? _onRecordCurrentMaskChanged;

  /// Kích hoạt chế độ lắng nghe tổ hợp phím tay cầm
  static void startRecordingCombo({
    required ValueChanged<String> onRecorded,
    ValueChanged<double>? onProgress,
    ValueChanged<String>? onCurrentKeysChanged,
  }) {
    _isRecordingCombo = true;
    _recordedMask = 0;
    _recordHoldTicks = 0;
    _onComboRecorded = onRecorded;
    _onRecordProgress = onProgress;
    _onRecordCurrentMaskChanged = onCurrentKeysChanged;
    _logger.info('Gamepad recording mode started.');
  }

  /// Hủy bỏ chế độ lắng nghe tổ hợp phím
  static void cancelRecordingCombo() {
    _isRecordingCombo = false;
    _recordedMask = 0;
    _recordHoldTicks = 0;
    _onComboRecorded = null;
    _onRecordProgress = null;
    _onRecordCurrentMaskChanged = null;
    _logger.info('Gamepad recording mode cancelled.');
  }

  /// Cập nhật tổ hợp phím tay cầm trong thời gian thực
  static void updateCombos({String? overlayCombo, String? keyboardCombo}) {
    // Hoãn kích hoạt 800ms để người dùng kịp nhả tay khỏi các nút trên Gamepad
    _cooldownUntil = DateTime.now().add(const Duration(milliseconds: 800));

    if (overlayCombo != null) {
      _overlayCombo = overlayCombo;
      _overlayMask = parseComboMask(overlayCombo);
      _overlayTracker.armAsPressed();
      _logger.info('Updated Gamepad Overlay Combo: $_overlayCombo (mask: 0x${_overlayMask.toRadixString(16)})');
    }
    if (keyboardCombo != null) {
      _keyboardCombo = keyboardCombo;
      _keyboardMask = parseComboMask(keyboardCombo);
      _keyboardTracker.armAsPressed();
      _logger.info('Updated Gamepad Virtual Keyboard Combo: $_keyboardCombo (mask: 0x${_keyboardMask.toRadixString(16)})');
    }
  }

  static void start({
    required VoidCallback onToggleOverlay,
    VoidCallback? onToggleKeyboard,
    String? initialOverlayCombo,
    String? initialKeyboardCombo,
    int intervalMs = 50,
  }) {
    if (_pollTimer != null) return;

    _onToggleOverlay = onToggleOverlay;
    _onToggleKeyboard = onToggleKeyboard;

    if (initialOverlayCombo != null) {
      _overlayCombo = initialOverlayCombo;
      _overlayMask = parseComboMask(initialOverlayCombo);
    }
    if (initialKeyboardCombo != null) {
      _keyboardCombo = initialKeyboardCombo;
      _keyboardMask = parseComboMask(initialKeyboardCombo);
    }

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
        bool anyOverlayComboPressed = false;
        bool anyKeyboardComboPressed = false;
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

            if (_overlayMask != 0 && (buttons & _overlayMask) == _overlayMask) {
              anyOverlayComboPressed = true;
            }
            if (_keyboardMask != 0 && (buttons & _keyboardMask) == _keyboardMask) {
              anyKeyboardComboPressed = true;
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

        // Xử lý chế độ ghi nhận tổ hợp Gamepad
        if (_isRecordingCombo) {
          if (activeButtons > 0) {
            final comboStr = maskToComboString(activeButtons);
            _onRecordCurrentMaskChanged?.call(comboStr);

            if (activeButtons == _recordedMask) {
              _recordHoldTicks++;
            } else {
              _recordedMask = activeButtons;
              _recordHoldTicks = 1;
            }

            final progress = (_recordHoldTicks / _requiredHoldTicks).clamp(0.0, 1.0);
            _onRecordProgress?.call(progress);

            if (_recordHoldTicks >= _requiredHoldTicks) {
              _isRecordingCombo = false;
              _logger.info('Gamepad combo recorded successfully: $comboStr');
              final callback = _onComboRecorded;
              _onComboRecorded = null;
              _onRecordProgress = null;
              _onRecordCurrentMaskChanged = null;
              callback?.call(comboStr);
            }
          } else {
            _recordHoldTicks = 0;
            _onRecordProgress?.call(0.0);
          }
          return; // Chặn các sự kiện nút thông thường khi đang ghi nhận
        }

        // Bỏ qua kích hoạt trong thời gian cooldown sau khi vừa gán combo
        if (DateTime.now().isBefore(_cooldownUntil)) {
          return;
        }

        // 1. Bắt sự kiện tổ hợp phím mở/tắt Overlay
        if (_overlayTracker.update(anyOverlayComboPressed)) {
          _logger.info('Gamepad combo triggered: $_overlayCombo');
          _onToggleOverlay?.call();
          return;
        }

        // 2. Bắt sự kiện tổ hợp phím mở/tắt Bàn phím ảo
        if (_keyboardTracker.update(anyKeyboardComboPressed)) {
          _logger.info('Gamepad combo triggered: $_keyboardCombo');
          _onToggleKeyboard?.call();
          return;
        }

        // Nếu đang giữ bất kỳ tổ hợp nào thì không phát các nút riêng rẽ để tránh nhận nhầm
        if (anyOverlayComboPressed || anyKeyboardComboPressed) {
          return;
        }

        // 3. Xử lý điều hướng D-Pad và Cần Analog trái
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

        // 4. Xử lý các nút bấm hành động (A, B, X, Y, LB, RB, Start, Back)
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
        _logger.error('Error polling Gamepad state', e);
      }
    });

    _logger.info('Gamepad listener started (Overlay: $_overlayCombo, Keyboard: $_keyboardCombo).');
  }

  static void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_pState != null) {
      calloc.free(_pState!);
      _pState = null;
    }
    _logger.info('Gamepad listener stopped.');
  }
}
