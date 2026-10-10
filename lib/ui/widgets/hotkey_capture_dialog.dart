import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../input/gamepad_service.dart';

/// Kết quả thu nhận phím tắt bao gồm loại thiết bị và chuỗi phím
class CapturedHotkeyResult {
  final String device; // 'keyboard' hoặc 'gamepad'
  final String hotkey;

  const CapturedHotkeyResult({required this.device, required this.hotkey});
}

/// Hộp thoại ghi nhận phím tắt hợp nhất: lắng nghe đồng thời cả Bàn phím PC và Gamepad theo thời gian thực.
class HotkeyCaptureDialog extends StatefulWidget {
  final String title;

  const HotkeyCaptureDialog({super.key, required this.title});

  /// Phương thức tĩnh hiển thị hộp thoại lắng nghe
  static Future<CapturedHotkeyResult?> show(
    BuildContext context, {
    required String title,
  }) {
    return showDialog<CapturedHotkeyResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => HotkeyCaptureDialog(title: title),
    );
  }

  @override
  State<HotkeyCaptureDialog> createState() => _HotkeyCaptureDialogState();
}

class _HotkeyCaptureDialogState extends State<HotkeyCaptureDialog> {
  String _capturedKeys = "";
  String _activeDevice = ""; // 'keyboard' hoặc 'gamepad'
  double _gamepadProgress = 0.0;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();

    // 1. Lắng nghe sự kiện Bàn phím PC
    HardwareKeyboard.instance.addHandler(_handleKeyboardEvent);

    // 2. Lắng nghe đồng thời sự kiện Tay cầm Gamepad (XInput)
    GamepadService.startRecordingCombo(
      onCurrentKeysChanged: (keys) {
        if (mounted && !_isSuccess) {
          setState(() {
            _activeDevice = 'gamepad';
            _capturedKeys = keys;
          });
        }
      },
      onProgress: (p) {
        if (mounted && !_isSuccess) {
          setState(() => _gamepadProgress = p);
        }
      },
      onRecorded: (recorded) {
        if (mounted && !_isSuccess) {
          HardwareKeyboard.instance.removeHandler(_handleKeyboardEvent);
          setState(() {
            _activeDevice = 'gamepad';
            _capturedKeys = recorded;
            _isSuccess = true;
            _gamepadProgress = 1.0;
          });
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted) {
              Navigator.of(
                context,
              ).pop(CapturedHotkeyResult(device: 'gamepad', hotkey: recorded));
            }
          });
        }
      },
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboardEvent);
    GamepadService.cancelRecordingCombo();
    super.dispose();
  }

  bool _handleKeyboardEvent(KeyEvent event) {
    if (_isSuccess) return true;

    // Phím Escape để hủy
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(null);
      return true;
    }

    if (event is! KeyDownEvent) return false;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.control);
    final isWin =
        HardwareKeyboard.instance.isMetaPressed ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.meta);
    final isAlt =
        HardwareKeyboard.instance.isAltPressed ||
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight) ||
        pressed.contains(LogicalKeyboardKey.alt);
    final isShift =
        HardwareKeyboard.instance.isShiftPressed ||
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        pressed.contains(LogicalKeyboardKey.shift);

    final isModifierKey =
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.logicalKey == LogicalKeyboardKey.control ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight ||
        event.logicalKey == LogicalKeyboardKey.meta ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight ||
        event.logicalKey == LogicalKeyboardKey.alt ||
        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight ||
        event.logicalKey == LogicalKeyboardKey.shift;

    // Người dùng đang giữ các phím bổ trợ đơn thuần -> cập nhật preview trực quan
    if (isModifierKey) {
      final parts = <String>[];
      if (isCtrl ||
          event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight ||
          event.logicalKey == LogicalKeyboardKey.control) {
        parts.add('Ctrl');
      }
      if (isWin ||
          event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight ||
          event.logicalKey == LogicalKeyboardKey.meta) {
        parts.add('Win');
      }
      if (isAlt ||
          event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight ||
          event.logicalKey == LogicalKeyboardKey.alt) {
        parts.add('Alt');
      }
      if (isShift ||
          event.logicalKey == LogicalKeyboardKey.shiftLeft ||
          event.logicalKey == LogicalKeyboardKey.shiftRight ||
          event.logicalKey == LogicalKeyboardKey.shift) {
        parts.add('Shift');
      }

      setState(() {
        _activeDevice = 'keyboard';
        _capturedKeys = parts.join(' + ');
      });
      return true;
    }

    // Xác định tên phím chính (Action key)
    final keyLabel = _resolveKeyLabel(event.logicalKey);
    if (keyLabel.isEmpty) return false;

    final parts = <String>[];
    if (isCtrl) parts.add('Ctrl');
    if (isWin) parts.add('Win');
    if (isAlt) parts.add('Alt');
    if (isShift) parts.add('Shift');
    parts.add(keyLabel);

    final result = parts.join('+');

    // Chốt phím ngay lập tức khi người dùng ấn phím action (kèm hoặc không kèm modifier)
    GamepadService.cancelRecordingCombo();
    setState(() {
      _activeDevice = 'keyboard';
      _capturedKeys = result;
      _isSuccess = true;
    });

    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        Navigator.of(context)
            .pop(CapturedHotkeyResult(device: 'keyboard', hotkey: result));
      }
    });
    return true;
  }

  String _resolveKeyLabel(LogicalKeyboardKey key) {
    // Phím chức năng F1 - F12
    if (key == LogicalKeyboardKey.f1) return 'F1';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.f3) return 'F3';
    if (key == LogicalKeyboardKey.f4) return 'F4';
    if (key == LogicalKeyboardKey.f5) return 'F5';
    if (key == LogicalKeyboardKey.f6) return 'F6';
    if (key == LogicalKeyboardKey.f7) return 'F7';
    if (key == LogicalKeyboardKey.f8) return 'F8';
    if (key == LogicalKeyboardKey.f9) return 'F9';
    if (key == LogicalKeyboardKey.f10) return 'F10';
    if (key == LogicalKeyboardKey.f11) return 'F11';
    if (key == LogicalKeyboardKey.f12) return 'F12';

    // Phím điều hướng & phím đặc biệt
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.delete) return 'Delete';
    if (key == LogicalKeyboardKey.insert) return 'Insert';
    if (key == LogicalKeyboardKey.home) return 'Home';
    if (key == LogicalKeyboardKey.end) return 'End';
    if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
    if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
    if (key == LogicalKeyboardKey.arrowUp) return 'Up';
    if (key == LogicalKeyboardKey.arrowDown) return 'Down';
    if (key == LogicalKeyboardKey.arrowLeft) return 'Left';
    if (key == LogicalKeyboardKey.arrowRight) return 'Right';

    // Hàng phím số chính (0-9) & Numpad (0-9)
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      return '0';
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      return '1';
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      return '2';
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      return '3';
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      return '4';
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      return '5';
    }
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      return '6';
    }
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      return '7';
    }
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      return '8';
    }
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      return '9';
    }

    // Chữ cái A-Z: so khớp keyId chuẩn tránh bị bộ gõ tiếng Việt Unikey/EVKey thay đổi
    final keyAId = LogicalKeyboardKey.keyA.keyId;
    final keyZId = LogicalKeyboardKey.keyZ.keyId;
    if (key.keyId >= keyAId && key.keyId <= keyZId) {
      return String.fromCharCode(65 + (key.keyId - keyAId));
    }

    final label = key.keyLabel.toUpperCase().trim();
    if (label.length == 1 && RegExp(r'^[A-Z0-9]$').hasMatch(label)) {
      return label;
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: _isSuccess
                ? AppTheme.accent
                : AppTheme.accent.withValues(alpha: 0.4),
            width: _isSuccess ? 2.0 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon tiêu đề: biểu tượng kép Bàn phím & Gamepad
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_activeDevice == 'keyboard')
                        ? AppTheme.accent.withValues(alpha: 0.25)
                        : AppTheme.cardBorder,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.keyboard_rounded,
                    color: AppTheme.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_activeDevice == 'gamepad')
                        ? AppTheme.accent.withValues(alpha: 0.25)
                        : AppTheme.cardBorder,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sports_esports_rounded,
                    color: AppTheme.accent,
                    size: 24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Tiêu đề
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: AppTheme.title.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 6),

            // Hướng dẫn hợp nhất
            Text(
              "Nhấn tổ hợp trên Bàn phím HOẶC Giữ cụm nút trên Gamepad (0.5s)...",
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),

            // Khung hiển thị phím đang bấm
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                border: Border.all(
                  color: _isSuccess
                      ? AppTheme.accent
                      : (_capturedKeys.isNotEmpty
                            ? AppTheme.accent.withValues(alpha: 0.6)
                            : AppTheme.cardBorder),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activeDevice.isNotEmpty && _capturedKeys.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _activeDevice == 'keyboard'
                              ? Icons.keyboard_outlined
                              : Icons.sports_esports_outlined,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _activeDevice == 'keyboard'
                              ? "Bàn phím PC"
                              : "Gamepad",
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    _capturedKeys.isEmpty
                        ? "Đang chờ bạn bấm phím..."
                        : _capturedKeys,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _capturedKeys.isEmpty
                          ? AppTheme.textSecondary.withValues(alpha: 0.5)
                          : (_isSuccess ? AppTheme.accent : Colors.white),
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (_activeDevice == 'gamepad' &&
                      _capturedKeys.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _gamepadProgress,
                        backgroundColor: AppTheme.cardBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isSuccess
                              ? AppTheme.accent
                              : AppTheme.accent.withValues(alpha: 0.8),
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Nút hủy
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.cardBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text("Hủy bỏ (Esc)"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
