import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../input/gamepad_service.dart';

/// Lớp vẽ mũi tên nhọn (Callout Arrow) chỉ trực tiếp vào tâm của biểu tượng (?).
class _CalloutArrowPainter extends CustomPainter {
  final Color fillColor;
  final Color strokeColor;
  final bool isPointingUp;

  _CalloutArrowPainter({
    required this.fillColor,
    required this.strokeColor,
    required this.isPointingUp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (isPointingUp) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CalloutArrowPainter oldDelegate) =>
      oldDelegate.fillColor != fillColor ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.isPointingUp != isPointingUp;
}

/// Nút biểu tượng trợ giúp (?) độc lập, đặt cạnh tiêu đề của từng widget điều khiển.
/// Khi kích hoạt sẽ hiển thị Tooltip Overlay nổi đè lên trên có mũi tên trỏ thẳng vào icon (?).
class HelpBox extends StatefulWidget {
  final String? helpText;
  final bool isFocused;

  const HelpBox({super.key, this.helpText, this.isFocused = false});

  @override
  State<HelpBox> createState() => _HelpBoxState();
}

class _HelpBoxState extends State<HelpBox> {
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  bool _isOpen = false;
  Timer? _hideTimer;
  StreamSubscription<GamepadButton>? _gamepadSub;

  @override
  void initState() {
    super.initState();
    _gamepadSub = GamepadService.buttonEvents.listen((button) {
      if (!mounted || widget.helpText == null || widget.helpText!.isEmpty) {
        return;
      }
      if (widget.isFocused && button == GamepadButton.x) {
        _toggle();
      }
    });
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_overlayController.isShowing) {
      _overlayController.show();
      setState(() => _isOpen = true);
    }
  }

  void _hide() {
    _hideTimer?.cancel();
    if (_overlayController.isShowing) {
      _overlayController.hide();
      setState(() => _isOpen = false);
    }
  }

  void _hideAfterDelay() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _overlayController.isShowing) {
        _hide();
      }
    });
  }

  void _toggle() {
    if (_overlayController.isShowing) {
      _hide();
    } else {
      _show();
    }
  }

  @override
  void didUpdateWidget(covariant HelpBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tự động đóng popup trợ giúp khi người dùng di chuyển focus sang widget khác
    if (oldWidget.isFocused &&
        !widget.isFocused &&
        _overlayController.isShowing) {
      _hide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gamepadSub?.cancel();
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    super.dispose();
  }

  Widget _buildTooltipOverlay(BuildContext overlayContext) {
    final renderBox = context.findRenderObject() as RenderBox?;
    const double tooltipWidth = 280.0;
    const double arrowWidth = 12.0;
    const double arrowHeight = 7.0;

    double iconCenterX = 0;
    bool isAbove = false;
    double boxLeft = 0;
    double arrowX = 20.0;

    if (renderBox != null && renderBox.hasSize) {
      final iconPos = renderBox.localToGlobal(Offset.zero);
      final iconSize = renderBox.size;
      final screenSize = MediaQuery.of(overlayContext).size;

      iconCenterX = iconPos.dx + (iconSize.width / 2);
      // Nếu vị trí gần đáy màn hình (< 150px) thì hiển thị tooltip ở phía TRÊN icon
      isAbove = (iconPos.dy + iconSize.height + 150) > screenSize.height;

      // Căn giữa hộp tooltip theo icon, đồng thời giữ lề an toàn tối thiểu 12px
      final desiredLeft = iconCenterX - (tooltipWidth / 2);
      boxLeft = desiredLeft.clamp(
        12.0,
        max(12.0, screenSize.width - tooltipWidth - 12.0),
      );

      // Vị trí mũi tên trên thanh ngang của hộp thoại sao cho trỏ thẳng tâm icon (?)
      arrowX = (iconCenterX - boxLeft).clamp(16.0, tooltipWidth - 16.0);
    }

    final offsetX = boxLeft - iconCenterX;
    final offsetY = isAbove ? -4.0 : 4.0;

    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: isAbove ? Alignment.topCenter : Alignment.bottomCenter,
        followerAnchor: isAbove ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(offsetX, offsetY),
        child: MouseRegion(
          onEnter: (_) => _hideTimer?.cancel(),
          onExit: (_) => _hideAfterDelay(),
          child: SizedBox(
            width: tooltipWidth,
            child: Material(
              color: AppTheme.transparent,
              child: GestureDetector(
                onTap: _hide,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Khi popup hiển thị ở DƯỚI icon: Mũi tên nằm trên đỉnh trỏ ngược lên icon
                    if (!isAbove)
                      Padding(
                        padding: EdgeInsets.only(
                          left: max(0.0, arrowX - arrowWidth / 2),
                        ),
                        child: CustomPaint(
                          size: const Size(arrowWidth, arrowHeight),
                          painter: _CalloutArrowPainter(
                            fillColor: const Color(0xFF141720),
                            strokeColor: AppTheme.accent.withValues(
                              alpha: 0.85,
                            ),
                            isPointingUp: true,
                          ),
                        ),
                      ),

                    // Khung hộp thoại chứa văn bản giải thích
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141720),
                        borderRadius: BorderRadius.circular(
                          AppTheme.cardRadius,
                        ),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.85),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.8),
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "TRỢ GIÚP",
                                style: AppTheme.caption.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardBorder.withValues(
                                    alpha: 0.35,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.textPrimary,
                                    width: 1.2,
                                  ),
                                ),
                                child: Text(
                                  "X",
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                    height: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Đóng",
                                style: AppTheme.caption.copyWith(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.helpText!,
                            style: AppTheme.body.copyWith(
                              fontSize: 12,
                              height: 1.4,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Khi popup hiển thị ở TRÊN icon: Mũi tên nằm ở đáy trỏ ngược xuống icon
                    if (isAbove)
                      Padding(
                        padding: EdgeInsets.only(
                          left: max(0.0, arrowX - arrowWidth / 2),
                        ),
                        child: CustomPaint(
                          size: const Size(arrowWidth, arrowHeight),
                          painter: _CalloutArrowPainter(
                            fillColor: const Color(0xFF141720),
                            strokeColor: AppTheme.accent.withValues(
                              alpha: 0.85,
                            ),
                            isPointingUp: false,
                          ),
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

  @override
  Widget build(BuildContext context) {
    if (widget.helpText == null || widget.helpText!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final isHighlighted = widget.isFocused || _isOpen;

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildTooltipOverlay,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _show(),
          onExit: (_) => _hideAfterDelay(),
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              Icons.help_outline_rounded,
              size: AppTheme.scaled(15),
              color: isHighlighted ? AppTheme.accent : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
