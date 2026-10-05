import 'dart:async';
import 'dart:ffi';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../core/logger.dart';

typedef _GetAsyncKeyStateC = Int16 Function(Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

class _KeyComboTracker {
  bool _wasPressed = false;

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

/// Dịch vụ đăng ký và lắng nghe phím tắt toàn cục (Global Hotkeys) trên Windows.
/// Tích hợp GetAsyncKeyState phần cứng từ user32.dll để hoạt động xuyên qua mọi Game Fullscreen/DirectX.
class HotkeyService {
  static const _logger = AppLogger('HotkeyService');

  // Virtual Key Codes chuẩn Win32
  static const int vkShift = 0x10;
  static const int vkControl = 0x11;
  static const int vkLShift = 0xA0;
  static const int vkRShift = 0xA1;
  static const int vkLControl = 0xA2;
  static const int vkRControl = 0xA3;
  static const int vkQ = 0x51;
  static const int vkK = 0x4B;

  static _GetAsyncKeyStateDart? _getAsyncKeyState;
  static Timer? _pollTimer;

  static final _overlayCombo = _KeyComboTracker();
  static final _keyboardCombo = _KeyComboTracker();

  static bool _isKeyDown(int vk) {
    if (_getAsyncKeyState == null) return false;
    final state = _getAsyncKeyState!(vk);
    return state < 0 || (state & 0x8000) != 0;
  }

  static Future<void> init({
    required VoidCallback onToggleOverlay,
    required VoidCallback onToggleKeyboard,
  }) async {
    // 1. Nạp hàm GetAsyncKeyState từ user32.dll qua Dart FFI
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _getAsyncKeyState = user32
          .lookupFunction<_GetAsyncKeyStateC, _GetAsyncKeyStateDart>('GetAsyncKeyState');
      _logger.info('Đã kết nối thành công với user32.dll GetAsyncKeyState.');
    } catch (e) {
      _logger.warning('Không thể nạp GetAsyncKeyState từ user32.dll: $e');
    }

    // 2. Vòng lặp quét trạng thái phần cứng bàn phím định kỳ mỗi 20ms (nhạy và hoạt động xuyên game Fullscreen)
    if (_getAsyncKeyState != null) {
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        try {
          final isCtrl = _isKeyDown(vkControl) || _isKeyDown(vkLControl) || _isKeyDown(vkRControl);
          final isShift = _isKeyDown(vkShift) || _isKeyDown(vkLShift) || _isKeyDown(vkRShift);

          if (isCtrl && isShift) {
            final isQ = _isKeyDown(vkQ);
            final isK = _isKeyDown(vkK);

            if (_overlayCombo.update(isQ)) {
              _logger.info('Nhận phím tắt phần cứng: Ctrl + Shift + Q (GetAsyncKeyState)');
              onToggleOverlay();
            }

            if (_keyboardCombo.update(isK)) {
              _logger.info('Nhận phím tắt phần cứng: Ctrl + Shift + K (GetAsyncKeyState)');
              onToggleKeyboard();
            }
          } else {
            _overlayCombo.update(false);
            _keyboardCombo.update(false);
          }
        } catch (_) {}
      });
    }

    // 3. Đăng ký bổ trợ qua hotkey_manager cho môi trường Desktop thông thường
    try {
      await hotKeyManager.unregisterAll();

      final overlayHotKey = HotKey(
        key: PhysicalKeyboardKey.keyQ,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        overlayHotKey,
        keyDownHandler: (hotKey) {
          _logger.info('Nhận tín hiệu phím tắt: Ctrl + Shift + Q (hotkey_manager)');
          onToggleOverlay();
        },
      );

      final keyboardHotKey = HotKey(
        key: PhysicalKeyboardKey.keyK,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        keyboardHotKey,
        keyDownHandler: (hotKey) {
          _logger.info('Nhận tín hiệu phím tắt: Ctrl + Shift + K (hotkey_manager)');
          onToggleKeyboard();
        },
      );

      _logger.info('Đã đăng ký thành công các phím tắt toàn cục hệ thống.');
    } catch (e) {
      _logger.warning('hotkey_manager fallback: $e');
    }
  }

  static Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }
}
