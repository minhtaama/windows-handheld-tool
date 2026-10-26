import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'cap_surface.dart';

/// Shoulder keys (LB / RB) that drive tab switching in the Compact Mode bar.
///
/// Only the two lateral bumpers are modelled: they are the keys physically
/// mapped to tab navigation, and the trigger variants (LT / RT) had no call
/// site left after the tab bar rework.
enum BumperType {
  lb(Icons.chevron_left_rounded),
  rb(Icons.chevron_right_rounded);

  const BumperType(this.icon);

  /// Direction chevron drawn inside the key body.
  final IconData icon;

  String get label => name.toUpperCase();

  bool get isLeft => this == BumperType.lb;
}

/// Shoulder key rendered on top of [CapSurface]: direction is encoded in the
/// silhouette (rounded outer edge, tight inner edge) so the key reads without
/// the label, and pressing dips the cap for tactile feedback.
class BumperButton extends StatefulWidget {
  final BumperType type;
  final bool isEnabled;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const BumperButton({
    super.key,
    this.type = BumperType.lb,
    this.isEnabled = true,
    this.onTap,
    this.width = 40.0,
    this.height = 22.0,
  });

  @override
  State<BumperButton> createState() => _BumperButtonState();
}

class _BumperButtonState extends State<BumperButton> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (!mounted || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.isEnabled;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.type.label,
      child: MouseRegion(
        cursor: isEnabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: isEnabled ? (_) => _setPressed(true) : null,
          onTapUp: isEnabled ? (_) => _setPressed(false) : null,
          onTapCancel: isEnabled ? () => _setPressed(false) : null,
          onTap: isEnabled ? widget.onTap : null,
          child: AnimatedScale(
            scale: _isPressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: CapSurface(
              shape: widget.type.isLeft
                  ? CapShape.shoulderLeft
                  : CapShape.shoulderRight,
              width: widget.width,
              height: widget.height,
              isEnabled: isEnabled,
              isPressed: _isPressed,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.type.icon,
                      size: widget.height * 0.52,
                      color: isEnabled
                          ? AppTheme.textSecondary
                          : AppTheme.textDisabled,
                    ),
                    const SizedBox(width: 1),
                    Text(
                      widget.type.label,
                      style: AppTheme.hint.copyWith(
                        fontSize: AppTheme.scaledHalf(10),
                        letterSpacing: 0.6,
                        color: isEnabled
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
