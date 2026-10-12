import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../core/logger.dart';

typedef _GetAsyncKeyStateC = Int16 Function(Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

class _HotkeyIsolateInitParams {
  final SendPort sendPort;
  final HotkeyBinding overlayBinding;
  final HotkeyBinding keyboardBinding;

  const _HotkeyIsolateInitParams({
    required this.sendPort,
    required this.overlayBinding,
    required this.keyboardBinding,
  });
}

class _KeyComboTracker {
  bool _wasPressed = false;

  void armAsPressed() {
    _wasPressed = true;
  }

  bool update(bool isPressed) {
    if (isPressed && !_wasPressed) {
      _wasPressed = true;
      return true; // Kích hoạt một lần duy nhất khi vừa nhấn xuống
    } else if (!isPressed) {
      _wasPressed = false;
    }
    return false;
  }
}

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

  bool matches(
    bool isCtrlDown,
    bool isWinDown,
    bool isShiftDown,
    bool isAltDown,
    bool Function(int vk) isKeyDown,
  ) {
    if (vkCode == 0) return false;
    if (requireCtrl && !isCtrlDown) return false;
    if (requireWin && !isWinDown) return false;
    if (requireShift && !isShiftDown) return false;
    if (requireAlt && !isAltDown) return false;
    return isKeyDown(vkCode);
  }

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
      } else if (part.startsWith('f') && part.length >= 2) {
        final fNum = int.tryParse(part.substring(1));
        if (fNum != null && fNum >= 1 && fNum <= 12) {
          vk = 0x6F + fNum; // F1 = 0x70, F12 = 0x7B
        }
      } else if (part == 'space') {
        vk = 0x20;
      } else if (part == 'tab') {
        vk = 0x09;
      } else if (part == 'enter' || part == 'return') {
        vk = 0x0D;
      } else if (part == 'esc' || part == 'escape') {
        vk = 0x1B;
      } else if (part == 'backspace') {
        vk = 0x08;
      } else if (part == 'delete' || part == 'del') {
        vk = 0x2E;
      } else if (part == 'insert') {
        vk = 0x2D;
      } else if (part == 'home') {
        vk = 0x24;
      } else if (part == 'end') {
        vk = 0x23;
      } else if (part == 'pageup') {
        vk = 0x21;
      } else if (part == 'pagedown') {
        vk = 0x22;
      } else if (part == 'up') {
        vk = 0x26;
      } else if (part == 'down') {
        vk = 0x28;
      } else if (part == 'left') {
        vk = 0x25;
      } else if (part == 'right') {
        vk = 0x27;
      } else if (part.length == 1) {
        vk = part.toUpperCase().codeUnitAt(0); // A-Z, 0-9
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

/// Dịch vụ đăng ký và lắng nghe phím tắt toàn cục (Global Hotkeys) trên Windows.
/// Tích hợp GetAsyncKeyState phần cứng từ user32.dll để hoạt động xuyên qua mọi Game Fullscreen/DirectX.
class HotkeyService {
  static const _logger = AppLogger('HotkeyService');

  // Virtual Key Codes chuẩn Win32
  static const int vkShift = 0x10;
  static const int vkControl = 0x11;
  static const int vkAlt = 0x12;
  static const int vkLShift = 0xA0;
  static const int vkRShift = 0xA1;
  static const int vkLControl = 0xA2;
  static const int vkRControl = 0xA3;
  static const int vkLAlt = 0xA4;
  static const int vkRAlt = 0xA5;
  static const int vkLWin = 0x5B;
  static const int vkRWin = 0x5C;

  static _GetAsyncKeyStateDart? _getAsyncKeyState;
  static Isolate? _workerIsolate;
  static ReceivePort? _workerReceivePort;
  static SendPort? _workerCommandPort;

  static HotkeyBinding _overlayBinding = HotkeyBinding.parse('Ctrl+Shift+Q');
  static HotkeyBinding _keyboardBinding = HotkeyBinding.parse('Ctrl+Shift+K');

  static VoidCallback? _onToggleOverlay;
  static VoidCallback? _onToggleKeyboard;

  static bool _isKeyDown(int vk) {
    if (_getAsyncKeyState == null || vk == 0) return false;
    final state = _getAsyncKeyState!(vk);
    return state < 0 || (state & 0x8000) != 0;
  }

  static Future<void> init({
    required VoidCallback onToggleOverlay,
    required VoidCallback onToggleKeyboard,
    String? initialOverlayHotkey,
    String? initialKeyboardHotkey,
  }) async {
    _onToggleOverlay = onToggleOverlay;
    _onToggleKeyboard = onToggleKeyboard;

    if (initialOverlayHotkey != null) {
      _overlayBinding = HotkeyBinding.parse(initialOverlayHotkey);
    }
    if (initialKeyboardHotkey != null) {
      _keyboardBinding = HotkeyBinding.parse(initialKeyboardHotkey);
    }

    // 1. Nạp hàm GetAsyncKeyState từ user32.dll qua Dart FFI (dành cho startRecordingCombo ở main thread)
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _getAsyncKeyState = user32
          .lookupFunction<_GetAsyncKeyStateC, _GetAsyncKeyStateDart>('GetAsyncKeyState');
      _logger.info('Connected to user32.dll GetAsyncKeyState successfully.');
    } catch (e) {
      _logger.warning('Could not load GetAsyncKeyState from user32.dll: $e');
    }

    // 2. Khởi chạy Isolate nền quét GetAsyncKeyState định kỳ 20ms
    // Chạy hoàn toàn độc lập với Flutter UI thread, không bị DWM đóng băng khi Alpha = 0
    await _startBackgroundIsolate();

    // 3. Luôn đăng ký qua hotkey_manager (Win32 RegisterHotKey) làm fallback dự phòng
    await _registerFallbackHotkeys();
  }

  static Future<void> _startBackgroundIsolate() async {
    await _stopBackgroundIsolate();
    try {
      _workerReceivePort = ReceivePort();
      final completer = Completer<SendPort>();

      _workerReceivePort!.listen((message) {
        if (message is SendPort) {
          if (!completer.isCompleted) completer.complete(message);
        } else if (message == 'toggle_overlay') {
          _logger.info('Hardware hotkey triggered: ${_overlayBinding.label} (Background Isolate)');
          _onToggleOverlay?.call();
        } else if (message == 'toggle_keyboard') {
          _logger.info('Hardware hotkey triggered: ${_keyboardBinding.label} (Background Isolate)');
          _onToggleKeyboard?.call();
        }
      });

      _workerIsolate = await Isolate.spawn(
        _hotkeyWorkerIsolateEntryPoint,
        _HotkeyIsolateInitParams(
          sendPort: _workerReceivePort!.sendPort,
          overlayBinding: _overlayBinding,
          keyboardBinding: _keyboardBinding,
        ),
      );

      _workerCommandPort = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Isolate startup timeout'),
      );
      _logger.info('Started background Hotkey polling isolate successfully.');
    } catch (e) {
      _logger.warning('Failed to start background Hotkey isolate: $e');
    }
  }

  static Future<void> _stopBackgroundIsolate() async {
    try {
      _workerCommandPort?.send('stop');
      _workerReceivePort?.close();
      _workerReceivePort = null;
      _workerCommandPort = null;
      _workerIsolate?.kill(priority: Isolate.immediate);
      _workerIsolate = null;
    } catch (_) {}
  }

  /// Cập nhật tổ hợp phím tắt trong thời gian thực
  static Future<void> updateHotkeys({
    String? overlayHotkey,
    String? keyboardHotkey,
  }) async {
    if (overlayHotkey != null) {
      _overlayBinding = HotkeyBinding.parse(overlayHotkey);
      _logger.info('Updated Overlay Hotkey: ${_overlayBinding.label}');
    }
    if (keyboardHotkey != null) {
      _keyboardBinding = HotkeyBinding.parse(keyboardHotkey);
      _logger.info('Updated Virtual Keyboard Hotkey: ${_keyboardBinding.label}');
    }

    _workerCommandPort?.send({
      'type': 'update_bindings',
      'overlay': _overlayBinding,
      'keyboard': _keyboardBinding,
    });

    await _registerFallbackHotkeys();
  }

  // --- QUẢN LÝ CHẾ ĐỘ GHI PHÍM BÀN PHÍM PC TRỰC TIẾP TỪ PHẦN CỨNG (GETASYNCKEYSTATE) ---
  static Timer? _recordingTimer;
  static bool _isRecording = false;
  static bool get isRecording => _isRecording;

  static final List<int> _actionVkCodes = [
    // F1 - F12
    for (int i = 0x70; i <= 0x7B; i++) i,
    // 0 - 9 (Main keys)
    for (int i = 0x30; i <= 0x39; i++) i,
    // 0 - 9 (Numpad)
    for (int i = 0x60; i <= 0x69; i++) i,
    // A - Z
    for (int i = 0x41; i <= 0x5A; i++) i,
    // Special & Navigation
    0x20, // Space
    0x09, // Tab
    0x0D, // Enter
    0x08, // Backspace
    0x2E, // Delete
    0x2D, // Insert
    0x24, // Home
    0x23, // End
    0x21, // PageUp
    0x22, // PageDown
    0x26, // Up
    0x28, // Down
    0x25, // Left
    0x27, // Right
  ];

  static String _vkToActionName(int vk) {
    if (vk >= 0x70 && vk <= 0x7B) {
      return 'F${vk - 0x70 + 1}';
    }
    if (vk >= 0x30 && vk <= 0x39) {
      return String.fromCharCode(vk);
    }
    if (vk >= 0x60 && vk <= 0x69) {
      return '${vk - 0x60}';
    }
    if (vk >= 0x41 && vk <= 0x5A) {
      return String.fromCharCode(vk);
    }
    switch (vk) {
      case 0x20:
        return 'Space';
      case 0x09:
        return 'Tab';
      case 0x0D:
        return 'Enter';
      case 0x08:
        return 'Backspace';
      case 0x2E:
        return 'Delete';
      case 0x2D:
        return 'Insert';
      case 0x24:
        return 'Home';
      case 0x23:
        return 'End';
      case 0x21:
        return 'PageUp';
      case 0x22:
        return 'PageDown';
      case 0x26:
        return 'Up';
      case 0x28:
        return 'Down';
      case 0x25:
        return 'Left';
      case 0x27:
        return 'Right';
      default:
        return '';
    }
  }

  /// Kích hoạt lắng nghe tổ hợp phím bàn phím PC trực tiếp từ phần cứng (không cần Window Focus)
  static void startRecordingCombo({
    required ValueChanged<String> onCurrentKeysChanged,
    required ValueChanged<String> onRecorded,
    VoidCallback? onCancelled,
  }) {
    if (_getAsyncKeyState == null) return;
    _workerCommandPort?.send({'type': 'pause'});
    _recordingTimer?.cancel();
    _isRecording = true;

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      // 1. Phím Escape để hủy
      if (_isKeyDown(0x1B)) {
        cancelRecordingCombo();
        onCancelled?.call();
        return;
      }

      // 2. Kiểm tra các phím bổ trợ (Modifiers)
      final isCtrl = _isKeyDown(vkControl) ||
          _isKeyDown(vkLControl) ||
          _isKeyDown(vkRControl);
      final isWin = _isKeyDown(vkLWin) || _isKeyDown(vkRWin);
      final isAlt = _isKeyDown(vkAlt) ||
          _isKeyDown(vkLAlt) ||
          _isKeyDown(vkRAlt);
      final isShift = _isKeyDown(vkShift) ||
          _isKeyDown(vkLShift) ||
          _isKeyDown(vkRShift);

      // 3. Quét tìm phím Action đang được nhấn
      int actionVk = 0;
      for (final vk in _actionVkCodes) {
        if (_isKeyDown(vk)) {
          actionVk = vk;
          break;
        }
      }

      if (actionVk != 0) {
        final actionName = _vkToActionName(actionVk);
        if (actionName.isNotEmpty) {
          final parts = <String>[];
          if (isCtrl) parts.add('Ctrl');
          if (isWin) parts.add('Win');
          if (isAlt) parts.add('Alt');
          if (isShift) parts.add('Shift');
          parts.add(actionName);

          final combo = parts.join('+');
          cancelRecordingCombo();
          onRecorded(combo);
          return;
        }
      }

      // 4. Nếu chưa có phím Action, hiển thị các Modifier đang giữ
      final modParts = <String>[];
      if (isCtrl) modParts.add('Ctrl');
      if (isWin) modParts.add('Win');
      if (isAlt) modParts.add('Alt');
      if (isShift) modParts.add('Shift');

      if (modParts.isNotEmpty) {
        onCurrentKeysChanged(modParts.join(' + '));
      } else {
        onCurrentKeysChanged('');
      }
    });
  }

  /// Hủy chế độ lắng nghe bàn phím
  static void cancelRecordingCombo() {
    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _workerCommandPort?.send({'type': 'resume'});
  }

  static Future<void> _registerFallbackHotkeys() async {
    try {
      await hotKeyManager.unregisterAll();

      final overlayKey = _toPhysicalKey(_overlayBinding.vkCode);
      if (overlayKey != null) {
        final modifiers = <HotKeyModifier>[];
        if (_overlayBinding.requireCtrl) modifiers.add(HotKeyModifier.control);
        if (_overlayBinding.requireWin) modifiers.add(HotKeyModifier.meta);
        if (_overlayBinding.requireShift) modifiers.add(HotKeyModifier.shift);
        if (_overlayBinding.requireAlt) modifiers.add(HotKeyModifier.alt);

        await hotKeyManager.register(
          HotKey(
            key: overlayKey,
            modifiers: modifiers,
            scope: HotKeyScope.system,
          ),
          keyDownHandler: (_) => _onToggleOverlay?.call(),
        );
      }

      final keyboardKey = _toPhysicalKey(_keyboardBinding.vkCode);
      if (keyboardKey != null) {
        final modifiers = <HotKeyModifier>[];
        if (_keyboardBinding.requireCtrl) modifiers.add(HotKeyModifier.control);
        if (_keyboardBinding.requireWin) modifiers.add(HotKeyModifier.meta);
        if (_keyboardBinding.requireShift) modifiers.add(HotKeyModifier.shift);
        if (_keyboardBinding.requireAlt) modifiers.add(HotKeyModifier.alt);

        await hotKeyManager.register(
          HotKey(
            key: keyboardKey,
            modifiers: modifiers,
            scope: HotKeyScope.system,
          ),
          keyDownHandler: (_) => _onToggleKeyboard?.call(),
        );
      }

      _logger.info('Registered hotkeys successfully via hotkey_manager fallback.');
    } catch (e) {
      _logger.warning('hotkey_manager fallback: $e');
    }
  }

  static PhysicalKeyboardKey? _toPhysicalKey(int vk) {
    // 0-9
    if (vk >= 0x30 && vk <= 0x39) {
      const digits = [
        PhysicalKeyboardKey.digit0,
        PhysicalKeyboardKey.digit1,
        PhysicalKeyboardKey.digit2,
        PhysicalKeyboardKey.digit3,
        PhysicalKeyboardKey.digit4,
        PhysicalKeyboardKey.digit5,
        PhysicalKeyboardKey.digit6,
        PhysicalKeyboardKey.digit7,
        PhysicalKeyboardKey.digit8,
        PhysicalKeyboardKey.digit9,
      ];
      return digits[vk - 0x30];
    }
    // A-Z
    if (vk >= 0x41 && vk <= 0x5A) {
      const letters = [
        PhysicalKeyboardKey.keyA,
        PhysicalKeyboardKey.keyB,
        PhysicalKeyboardKey.keyC,
        PhysicalKeyboardKey.keyD,
        PhysicalKeyboardKey.keyE,
        PhysicalKeyboardKey.keyF,
        PhysicalKeyboardKey.keyG,
        PhysicalKeyboardKey.keyH,
        PhysicalKeyboardKey.keyI,
        PhysicalKeyboardKey.keyJ,
        PhysicalKeyboardKey.keyK,
        PhysicalKeyboardKey.keyL,
        PhysicalKeyboardKey.keyM,
        PhysicalKeyboardKey.keyN,
        PhysicalKeyboardKey.keyO,
        PhysicalKeyboardKey.keyP,
        PhysicalKeyboardKey.keyQ,
        PhysicalKeyboardKey.keyR,
        PhysicalKeyboardKey.keyS,
        PhysicalKeyboardKey.keyT,
        PhysicalKeyboardKey.keyU,
        PhysicalKeyboardKey.keyV,
        PhysicalKeyboardKey.keyW,
        PhysicalKeyboardKey.keyX,
        PhysicalKeyboardKey.keyY,
        PhysicalKeyboardKey.keyZ,
      ];
      return letters[vk - 0x41];
    }
    // F1 - F12
    if (vk >= 0x70 && vk <= 0x7B) {
      const fKeys = [
        PhysicalKeyboardKey.f1,
        PhysicalKeyboardKey.f2,
        PhysicalKeyboardKey.f3,
        PhysicalKeyboardKey.f4,
        PhysicalKeyboardKey.f5,
        PhysicalKeyboardKey.f6,
        PhysicalKeyboardKey.f7,
        PhysicalKeyboardKey.f8,
        PhysicalKeyboardKey.f9,
        PhysicalKeyboardKey.f10,
        PhysicalKeyboardKey.f11,
        PhysicalKeyboardKey.f12,
      ];
      return fKeys[vk - 0x70];
    }
    switch (vk) {
      case 0x20: return PhysicalKeyboardKey.space;
      case 0x09: return PhysicalKeyboardKey.tab;
      case 0x0D: return PhysicalKeyboardKey.enter;
      case 0x08: return PhysicalKeyboardKey.backspace;
      case 0x2E: return PhysicalKeyboardKey.delete;
      case 0x2D: return PhysicalKeyboardKey.insert;
      case 0x24: return PhysicalKeyboardKey.home;
      case 0x23: return PhysicalKeyboardKey.end;
      case 0x21: return PhysicalKeyboardKey.pageUp;
      case 0x22: return PhysicalKeyboardKey.pageDown;
      case 0x26: return PhysicalKeyboardKey.arrowUp;
      case 0x28: return PhysicalKeyboardKey.arrowDown;
      case 0x25: return PhysicalKeyboardKey.arrowLeft;
      case 0x27: return PhysicalKeyboardKey.arrowRight;
    }
    return null;
  }

  static Future<void> dispose() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _stopBackgroundIsolate();
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }
}

/// Entry point cho Worker Isolate chạy độc lập với Flutter UI Thread
void _hotkeyWorkerIsolateEntryPoint(_HotkeyIsolateInitParams initParams) {
  final commandPort = ReceivePort();
  initParams.sendPort.send(commandPort.sendPort);

  _GetAsyncKeyStateDart? getAsyncKeyState;
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    getAsyncKeyState = user32
        .lookupFunction<_GetAsyncKeyStateC, _GetAsyncKeyStateDart>('GetAsyncKeyState');
  } catch (_) {
    return;
  }

  bool isKeyDown(int vk) {
    if (getAsyncKeyState == null || vk == 0) return false;
    final state = getAsyncKeyState(vk);
    return state < 0 || (state & 0x8000) != 0;
  }

  HotkeyBinding overlayBinding = initParams.overlayBinding;
  HotkeyBinding keyboardBinding = initParams.keyboardBinding;

  final overlayCombo = _KeyComboTracker();
  final keyboardCombo = _KeyComboTracker();

  DateTime cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool isPaused = false;
  Timer? pollTimer;

  pollTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    try {
      if (isPaused) return;
      if (DateTime.now().isBefore(cooldownUntil)) return;

      final isCtrl = isKeyDown(HotkeyService.vkControl) ||
          isKeyDown(HotkeyService.vkLControl) ||
          isKeyDown(HotkeyService.vkRControl);
      final isWin = isKeyDown(HotkeyService.vkLWin) ||
          isKeyDown(HotkeyService.vkRWin);
      final isShift = isKeyDown(HotkeyService.vkShift) ||
          isKeyDown(HotkeyService.vkLShift) ||
          isKeyDown(HotkeyService.vkRShift);
      final isAlt = isKeyDown(HotkeyService.vkAlt) ||
          isKeyDown(HotkeyService.vkLAlt) ||
          isKeyDown(HotkeyService.vkRAlt);

      if (overlayBinding.matches(isCtrl, isWin, isShift, isAlt, isKeyDown)) {
        if (overlayCombo.update(true)) {
          cooldownUntil = DateTime.now().add(const Duration(milliseconds: 700));
          initParams.sendPort.send('toggle_overlay');
        }
      } else {
        overlayCombo.update(false);
      }

      if (keyboardBinding.matches(isCtrl, isWin, isShift, isAlt, isKeyDown)) {
        if (keyboardCombo.update(true)) {
          cooldownUntil = DateTime.now().add(const Duration(milliseconds: 700));
          initParams.sendPort.send('toggle_keyboard');
        }
      } else {
        keyboardCombo.update(false);
      }
    } catch (_) {}
  });

  commandPort.listen((message) {
    if (message is Map) {
      final type = message['type'];
      if (type == 'update_bindings') {
        if (message['overlay'] is HotkeyBinding) {
          overlayBinding = message['overlay'] as HotkeyBinding;
          overlayCombo.armAsPressed();
        }
        if (message['keyboard'] is HotkeyBinding) {
          keyboardBinding = message['keyboard'] as HotkeyBinding;
          keyboardCombo.armAsPressed();
        }
        cooldownUntil = DateTime.now().add(const Duration(milliseconds: 800));
      } else if (type == 'pause') {
        isPaused = true;
      } else if (type == 'resume') {
        isPaused = false;
        cooldownUntil = DateTime.now().add(const Duration(milliseconds: 400));
      }
    } else if (message == 'stop') {
      pollTimer?.cancel();
      commandPort.close();
    }
  });
}
