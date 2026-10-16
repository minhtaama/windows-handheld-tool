import 'dart:async';
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

/// Dịch vụ quản lý sự kiện tay cầm (Gamepad) cho giao diện Quick Settings.
class GamepadService {
  static const _logger = AppLogger('GamepadService');
  static bool isConnected = true;

  static final StreamController<GamepadButton> _buttonEventsController =
      StreamController<GamepadButton>.broadcast();

  static Stream<GamepadButton> get buttonEvents => _buttonEventsController.stream;

  /// Tiếp nhận sự kiện bấm nút Gamepad từ Python Host qua BridgeService
  static void dispatchButton(String name) {
    try {
      for (final btn in GamepadButton.values) {
        if (btn.name.toLowerCase() == name.toLowerCase()) {
          _buttonEventsController.add(btn);
          break;
        }
      }
    } catch (e) {
      _logger.warning('Lỗi dispatch button Gamepad: $e');
    }
  }

  static void start({
    Function()? onToggleOverlay,
    Function()? onToggleKeyboard,
    String? initialOverlayCombo,
    String? initialKeyboardCombo,
    int intervalMs = 50,
  }) {
    _logger.info('GamepadService started.');
  }

  static void stop() {}

  static void startRecordingCombo({
    Function(String keys)? onCurrentKeysChanged,
    Function(double progress)? onProgress,
    required Function(String combo) onRecorded,
    Function()? onCancelled,
  }) {}

  static void cancelRecordingCombo() {}

  static void updateCombos({String? overlayCombo, String? keyboardCombo}) {}
}
