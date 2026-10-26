import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Physical key silhouette shared by the tab bar bumpers and the footer hints.
enum CapShape {
  /// Shoulder key with the rounded edge on the left (LB).
  shoulderLeft,

  /// Shoulder key with the rounded edge on the right (RB).
  shoulderRight,

  /// Face button (X / A / B).
  circle,
}

/// Metal key cap used across the panel chrome.
///
/// One gradient fill, one seated drop shadow and one hairline rim live here, so
/// every hardware hint on screen reads as the same moulded material instead of
/// each widget inventing its own bevel.
class CapSurface extends StatelessWidget {
  final CapShape shape;
  final double width;
  final double height;
  final bool isEnabled;
  final bool isPressed;

  /// Optional tint for the rim and the outer bloom. Shoulder keys stay
  /// monochrome (null); face buttons pass their semantic colour.
  final Color? accent;

  final Widget? child;

  const CapSurface({
    super.key,
    required this.shape,
    required this.width,
    required this.height,
    this.isEnabled = true,
    this.isPressed = false,
    this.accent,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CapPainter(
        shape: shape,
        isEnabled: isEnabled,
        isPressed: isPressed,
        accent: accent,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2.0, left: 1, right: 1),
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
  }
}

class _CapPainter extends CustomPainter {
  _CapPainter({
    required this.shape,
    required this.isEnabled,
    required this.isPressed,
    required this.accent,
  });

  // Cap material. Slightly brighter than the selected tab tile so small keys
  // still catch the light on a recessed track.
  static const Color _fillTop = Color(0xFF2E3341);
  static const Color _fillBottom = Color(0xFF1A1D25);
  static const Color _fillTopPressed = Color(0xFF363C4B);
  static const Color _fillBottomPressed = Color(0xFF20242E);
  static const Color _fillTopDisabled = Color(0xFF171A21);
  static const Color _fillBottomDisabled = Color(0xFF121419);

  final CapShape shape;
  final bool isEnabled;
  final bool isPressed;
  final Color? accent;

  @override
  void paint(Canvas canvas, Size size) {
    final body = _buildBody(size);

    // Seat shadow: keeps the key visually attached to the bar surface.
    canvas.drawRRect(
      body.shift(const Offset(0, 1)),
      Paint()
        ..color = AppTheme.shadow.withValues(alpha: isEnabled ? 0.45 : 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    canvas.drawRRect(
      body,
      Paint()
        ..shader = _fillGradient().createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );

    final rimColor = _rimColor();

    // Faint accent bloom around face buttons, drawn under the rim.
    if (accent != null && isEnabled) {
      canvas.drawRRect(
        body.inflate(1.5),
        Paint()
          ..color = accent!.withValues(alpha: isPressed ? 0.22 : 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..color = rimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  RRect _buildBody(Size size) {
    final rect = Offset.zero & size;

    if (shape == CapShape.circle) {
      return RRect.fromRectAndRadius(
        rect,
        Radius.circular(size.shortestSide / 2),
      );
    }

    final isLeft = shape == CapShape.shoulderLeft;
    final outerRadius = size.height * 0.42;
    const innerRadius = 3.5;
    final leftRadius = isLeft ? outerRadius : innerRadius;
    final rightRadius = isLeft ? innerRadius : outerRadius;

    return RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(leftRadius),
      bottomLeft: Radius.circular(leftRadius),
      topRight: Radius.circular(rightRadius),
      bottomRight: Radius.circular(rightRadius),
    );
  }

  LinearGradient _fillGradient() {
    final List<Color> colors;
    if (!isEnabled) {
      colors = const [_fillTopDisabled, _fillBottomDisabled];
    } else if (isPressed) {
      colors = const [_fillTopPressed, _fillBottomPressed];
    } else {
      colors = const [_fillTop, _fillBottom];
    }

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
    );
  }

  Color _rimColor() {
    if (!isEnabled) return AppTheme.primary.withValues(alpha: 0.05);
    if (accent != null) {
      return accent!.withValues(alpha: isPressed ? 0.75 : 0.45);
    }
    return isPressed
        ? AppTheme.primary.withValues(alpha: 0.28)
        : AppTheme.cardBorder;
  }

  @override
  bool shouldRepaint(covariant _CapPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.isPressed != isPressed ||
        oldDelegate.accent != accent;
  }
}
