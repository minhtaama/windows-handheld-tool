import 'package:flutter/services.dart';
import '../core/logger.dart';

/// Cấu trúc đại diện cho một tổ hợp phím ảo trên Windows
class HotkeyBinding {
  final bool requireCtrl;
  final bool requireWin;
  final bool requireShift;
  final bool requireAlt;
  final int vkCode;
  final String label;

  const HotkeyBinding({
    this.requireCtrl = false,
    this.requireWin = false,
    this.requireShift = false,
    this.requireAlt = false,
    required this.vkCode,
    required this.label,
  });

  static HotkeyBinding parse(String raw) {
    final lower = raw.toLowerCase().trim();
    final parts = lower.split(RegExp(r'[\+\s]+'));
    bool ctrl = false;
    bool win = false;
    bool shift = false;
    bool alt = false;
    int vk = 0;

    for (final part in parts) {
      if (part == 'ctrl' || part == 'control') {
        ctrl = true;
      } else if (part == 'win' || part == 'windows' || part == 'meta') {
        win = true;
      } else if (part == 'shift') {
        shift = true;
      } else if (part == 'alt') {
        alt = true;
      } else if (part.length == 1) {
        vk = part.toUpperCase().codeUnitAt(0);
      }
    }

    return HotkeyBinding(
      requireCtrl: ctrl,
      requireWin: win,
      requireShift: shift,
      requireAlt: alt,
      vkCode: vk,
      label: raw,
    );
  }
}

/// Dịch vụ quản lý hiển thị và cấu hình phím tắt toàn cục.
class HotkeyService {
  static const _logger = AppLogger('HotkeyService');

  static HotkeyBinding overlayBinding = HotkeyBinding.parse("Ctrl+Shift+Q");
  static HotkeyBinding keyboardBinding = HotkeyBinding.parse("Ctrl+Alt+K");

  static bool Function(KeyEvent)? _activeKeyHandler;

  static Future<void> init({
    Function()? onToggleOverlay,
    Function()? onToggleKeyboard,
    String? initialOverlayHotkey,
    String? initialKeyboardHotkey,
  }) async {
    if (initialOverlayHotkey != null) {
      overlayBinding = HotkeyBinding.parse(initialOverlayHotkey);
    }
    if (initialKeyboardHotkey != null) {
      keyboardBinding = HotkeyBinding.parse(initialKeyboardHotkey);
    }
    _logger.info('HotkeyService initialized.');
  }

  static void updateHotkeys({String? overlayHotkey, String? keyboardHotkey}) {
    if (overlayHotkey != null) {
      overlayBinding = HotkeyBinding.parse(overlayHotkey);
    }
    if (keyboardHotkey != null) {
      keyboardBinding = HotkeyBinding.parse(keyboardHotkey);
    }
  }

  static void startRecordingCombo({
    Function(String keys)? onCurrentKeysChanged,
    required Function(String combo) onRecorded,
    Function()? onCancelled,
  }) {
    cancelRecordingCombo();

    _activeKeyHandler = (KeyEvent event) {
      if (event is! KeyDownEvent) return false;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape) {
        cancelRecordingCombo();
        onCancelled?.call();
        return true;
      }

      final isCtrl = HardwareKeyboard.instance.isControlPressed;
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final isAlt = HardwareKeyboard.instance.isAltPressed;
      final isWin = HardwareKeyboard.instance.isMetaPressed;

      final mainKeyStr = _getKeyLabel(key);

      final parts = <String>[];
      if (isCtrl) parts.add('Ctrl');
      if (isAlt) parts.add('Alt');
      if (isShift) parts.add('Shift');
      if (isWin) parts.add('Win');

      if (mainKeyStr.isNotEmpty && !parts.contains(mainKeyStr)) {
        parts.add(mainKeyStr);
      }

      if (parts.isNotEmpty) {
        final currentCombo = parts.join('+');
        onCurrentKeysChanged?.call(currentCombo);

        if (mainKeyStr.isNotEmpty) {
          cancelRecordingCombo();
          onRecorded(currentCombo);
          return true;
        }
      }
      return false;
    };

    HardwareKeyboard.instance.addHandler(_activeKeyHandler!);
  }

  static void cancelRecordingCombo() {
    if (_activeKeyHandler != null) {
      HardwareKeyboard.instance.removeHandler(_activeKeyHandler!);
      _activeKeyHandler = null;
    }
  }

  static String _getKeyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) return '';
    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) return '';
    if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) return '';
    if (key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight) return '';

    final label = key.keyLabel.trim().toUpperCase();
    if (label.isNotEmpty && label.length == 1) {
      return label;
    }
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key.keyId >= LogicalKeyboardKey.f1.keyId && key.keyId <= LogicalKeyboardKey.f12.keyId) {
      return 'F${key.keyId - LogicalKeyboardKey.f1.keyId + 1}';
    }
    return label;
  }

  static void dispose() {
    cancelRecordingCombo();
  }
}
