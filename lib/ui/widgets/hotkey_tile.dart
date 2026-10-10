import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../input/gamepad_service.dart';
import '../../input/hotkey_service.dart';
import 'help_box.dart';

/// Thẻ cài đặt phím tắt đơn nhất (1 tính năng = 1 hotkey duy nhất: Bàn phím PC HOẶC Gamepad).
/// Tích hợp cơ chế Ghi phím trực tiếp Inline ngay trong Panel (không dùng Popup Window).
/// Sử dụng GetAsyncKeyState phần cứng từ user32.dll và XInput để nhận diện 100% phím Action, Win, Alt.
class HotkeyTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String device; // 'keyboard' hoặc 'gamepad'
  final String hotkey;
  final void Function(String device, String hotkey) onHotkeyChanged;
  final bool isFocused;
  final String? helpText;

  const HotkeyTile({
    super.key,
    required this.icon,
    required this.title,
    required this.device,
    required this.hotkey,
    required this.onHotkeyChanged,
    this.isFocused = false,
    this.helpText,
  });

  @override
  State<HotkeyTile> createState() => HotkeyTileState();
}

class HotkeyTileState extends State<HotkeyTile> {
  bool _isRecording = false;
  String _capturedKeys = '';
  String _activeDevice = ''; // 'keyboard' hoặc 'gamepad'
  double _gamepadProgress = 0.0;
  bool _isSuccess = false;

  bool get isRecording => _isRecording;

  /// Kích hoạt chế độ ghi nhận phím trực tiếp ngay trên thẻ
  void startRecording() {
    if (_isRecording) return;
    setState(() {
      _isRecording = true;
      _capturedKeys = '';
      _activeDevice = '';
      _gamepadProgress = 0.0;
      _isSuccess = false;
    });

    // 1. Lắng nghe Bàn phím PC trực tiếp từ Win32 GetAsyncKeyState phần cứng
    HotkeyService.startRecordingCombo(
      onCurrentKeysChanged: (keys) {
        if (mounted && _isRecording && !_isSuccess) {
          setState(() {
            _activeDevice = 'keyboard';
            _capturedKeys = keys;
          });
        }
      },
      onRecorded: (recorded) {
        if (mounted && _isRecording && !_isSuccess) {
          GamepadService.cancelRecordingCombo();
          setState(() {
            _activeDevice = 'keyboard';
            _capturedKeys = recorded;
            _isSuccess = true;
          });
          widget.onHotkeyChanged('keyboard', recorded);
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted) {
              setState(() {
                _isRecording = false;
                _isSuccess = false;
              });
            }
          });
        }
      },
      onCancelled: () {
        if (mounted && _isRecording) {
          cancelRecording();
        }
      },
    );

    // 2. Lắng nghe Tay cầm Gamepad trực tiếp từ XInput
    GamepadService.startRecordingCombo(
      onCurrentKeysChanged: (keys) {
        if (mounted && _isRecording && !_isSuccess) {
          setState(() {
            _activeDevice = 'gamepad';
            _capturedKeys = keys;
          });
        }
      },
      onProgress: (p) {
        if (mounted && _isRecording && !_isSuccess) {
          setState(() => _gamepadProgress = p);
        }
      },
      onRecorded: (recorded) {
        if (mounted && _isRecording && !_isSuccess) {
          HotkeyService.cancelRecordingCombo();
          setState(() {
            _activeDevice = 'gamepad';
            _capturedKeys = recorded;
            _isSuccess = true;
            _gamepadProgress = 1.0;
          });
          widget.onHotkeyChanged('gamepad', recorded);
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted) {
              setState(() {
                _isRecording = false;
                _isSuccess = false;
              });
            }
          });
        }
      },
    );
  }

  /// Hủy bỏ chế độ ghi nhận phím
  void cancelRecording() {
    HotkeyService.cancelRecordingCombo();
    GamepadService.cancelRecordingCombo();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _capturedKeys = '';
        _activeDevice = '';
        _gamepadProgress = 0.0;
        _isSuccess = false;
      });
    }
  }

  @override
  void dispose() {
    if (_isRecording) {
      HotkeyService.cancelRecordingCombo();
      GamepadService.cancelRecordingCombo();
    }
    super.dispose();
  }

  Widget _buildSingleBadge() {
    final isNone = widget.hotkey.isEmpty || widget.hotkey == "TẮT";
    final isGamepad = widget.device == 'gamepad';

    final IconData badgeIcon = isNone
        ? Icons.block_rounded
        : (isGamepad ? Icons.sports_esports_rounded : Icons.keyboard_rounded);

    final String deviceLabel = isNone
        ? ""
        : (isGamepad ? "Gamepad: " : "Bàn phím: ");

    final String keyLabel = isNone ? "TẮT" : widget.hotkey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: Border.all(
          color: isNone ? AppTheme.cardBorder : AppTheme.primary.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badgeIcon,
            size: AppTheme.scaled(14),
            color: isNone ? AppTheme.textSecondary : AppTheme.primary,
          ),
          const SizedBox(width: 6),
          if (deviceLabel.isNotEmpty)
            Text(
              deviceLabel,
              style: AppTheme.caption.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          Text(
            keyLabel,
            style: AppTheme.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: isNone ? AppTheme.textSecondary : AppTheme.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Trạng thái viền nổi bật khi ghi phím hoặc khi Gamepad giữ focus
    final borderColor = _isRecording
        ? (_isSuccess ? AppTheme.accent : AppTheme.danger)
        : (widget.isFocused ? AppTheme.accent : AppTheme.cardBackground);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: borderColor,
          width: (_isRecording || widget.isFocused) ? 1.8 : 1.0,
        ),
        boxShadow: (_isRecording || widget.isFocused)
            ? [
                BoxShadow(
                  color: (_isRecording
                          ? (_isSuccess ? AppTheme.accent : AppTheme.danger)
                          : AppTheme.primary)
                      .withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isRecording ? null : startRecording,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hàng 1: Icon + Tên tính năng + Nút Đổi phím / Hủy
                Row(
                  children: [
                    Icon(
                      _isRecording
                          ? (_isSuccess
                              ? Icons.check_circle_rounded
                              : Icons.fiber_manual_record_rounded)
                          : widget.icon,
                      size: AppTheme.scaled(18),
                      color: _isRecording
                          ? (_isSuccess ? AppTheme.accent : AppTheme.danger)
                          : AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _isRecording
                                  ? (_isSuccess
                                      ? "Đã gán phím thành công!"
                                      : "Đang ghi: ${widget.title}")
                                  : widget.title,
                              style: AppTheme.title.copyWith(
                                color: _isRecording
                                    ? (_isSuccess
                                        ? AppTheme.accent
                                        : AppTheme.textPrimary)
                                    : AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.helpText != null && !_isRecording) ...[
                            const SizedBox(width: 6),
                            HelpBox(
                              helpText: widget.helpText!,
                              isFocused: widget.isFocused,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Nút thao tác bên phải
                    if (_isRecording)
                      InkWell(
                        onTap: cancelRecording,
                        borderRadius:
                            BorderRadius.circular(AppTheme.buttonRadius),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius:
                                BorderRadius.circular(AppTheme.buttonRadius),
                            border: Border.all(
                              color: AppTheme.cardBorder,
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            "Hủy (Esc)",
                            style: AppTheme.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isFocused
                              ? AppTheme.accent.withValues(alpha: 0.25)
                              : AppTheme.background,
                          borderRadius:
                              BorderRadius.circular(AppTheme.buttonRadius),
                          border: Border.all(
                            color: widget.isFocused
                                ? AppTheme.accent
                                : AppTheme.cardBorder,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fiber_manual_record_rounded,
                              size: AppTheme.scaled(10),
                              color: widget.isFocused
                                  ? AppTheme.accent
                                  : AppTheme.danger,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              "Đổi phím",
                              style: AppTheme.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: widget.isFocused
                                    ? AppTheme.accent
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Hàng 2: Giao diện khi ở chế độ ghi phím Inline vs Hiển thị Badge duy nhất
                if (_isRecording)
                  _buildInlineRecordingView()
                else
                  _buildSingleBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Giao diện ghi phím trực tiếp trong thẻ (Inline Mode)
  Widget _buildInlineRecordingView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: Border.all(
          color: _isSuccess
              ? AppTheme.accent
              : (_capturedKeys.isNotEmpty
                  ? AppTheme.accent.withValues(alpha: 0.5)
                  : AppTheme.cardBorder),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _activeDevice == 'gamepad'
                    ? Icons.sports_esports_rounded
                    : Icons.keyboard_rounded,
                size: AppTheme.scaled(14),
                color: _isSuccess ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                _activeDevice == 'gamepad'
                    ? "Gamepad (giữ combo 0.5s)"
                    : (_activeDevice == 'keyboard'
                        ? "Bàn phím PC"
                        : "Bấm phím PC hoặc giữ nút Gamepad..."),
                style: AppTheme.caption.copyWith(
                  color: _isSuccess
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _capturedKeys.isEmpty
                ? "Đang chờ thao tác..."
                : _capturedKeys,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _isSuccess
                  ? AppTheme.accent
                  : (_capturedKeys.isEmpty
                      ? AppTheme.textSecondary
                      : AppTheme.accent),
              letterSpacing: 0.5,
            ),
          ),
          if (_activeDevice == 'gamepad' && _capturedKeys.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _gamepadProgress,
                backgroundColor: AppTheme.cardBorder,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _isSuccess ? AppTheme.accent : AppTheme.accent,
                ),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
