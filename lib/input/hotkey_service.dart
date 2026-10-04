import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../core/logger.dart';

/// Dịch vụ đăng ký và lắng nghe phím tắt toàn cục (Global Hotkeys) trên Windows.
class HotkeyService {
  static const _logger = AppLogger('HotkeyService');

  static Future<void> init({
    required VoidCallback onToggleOverlay,
    required VoidCallback onToggleKeyboard,
  }) async {
    try {
      await hotKeyManager.unregisterAll();

      // 1. Phím tắt mở Overlay: Ctrl + Shift + Q
      final overlayHotKey = HotKey(
        key: PhysicalKeyboardKey.keyQ,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        overlayHotKey,
        keyDownHandler: (hotKey) {
          _logger.info('Nhận tín hiệu phím tắt: Ctrl + Shift + Q');
          onToggleOverlay();
        },
      );

      // 2. Phím tắt mở Bàn phím ảo: Ctrl + Shift + K
      final keyboardHotKey = HotKey(
        key: PhysicalKeyboardKey.keyK,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        keyboardHotKey,
        keyDownHandler: (hotKey) {
          _logger.info('Nhận tín hiệu phím tắt: Ctrl + Shift + K');
          onToggleKeyboard();
        },
      );

      _logger.info('Đã đăng ký thành công các phím tắt toàn cục hệ thống.');
    } catch (e) {
      _logger.error('Lỗi khi thiết lập Hotkey toàn cục', e);
    }
  }

  static Future<void> dispose() async {
    await hotKeyManager.unregisterAll();
  }
}
