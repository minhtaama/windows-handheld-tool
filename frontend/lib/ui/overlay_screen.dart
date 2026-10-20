import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/config.dart';
import '../services/overlay_controller.dart';
import 'quick_panel.dart';

/// Màn hình Lớp phủ Toàn màn hình (Fullscreen Overlay) bao gồm:
/// 1. Lớp nền đen mờ (Dimmed Backdrop) phủ toàn màn hình: nhấn vào vùng trống sẽ đóng panel.
/// 2. Bảng điều khiển QuickSettingsPanel neo bên phải kèm hiệu ứng Fade-In / Fade-Out & Slide.
class OverlayScreen extends StatefulWidget {
  final ConfigManager config;

  const OverlayScreen({super.key, required this.config});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
      value: 0.0,
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.06, 0.0),
      end: Offset.zero,
    ).animate(_fadeAnim);

    OverlayController.instance.onAnimateShow = () async {
      await _animController.forward(from: 0.0);
    };

    OverlayController.instance.onAnimateHide = () async {
      await _animController.reverse();
    };
  }

  @override
  void dispose() {
    if (OverlayController.instance.onAnimateShow != null) {
      OverlayController.instance.onAnimateShow = null;
    }
    if (OverlayController.instance.onAnimateHide != null) {
      OverlayController.instance.onAnimateHide = null;
    }
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OverlayController.instance,
      builder: (context, _) {
        final isVisible = OverlayController.instance.isVisible;
        final widthPercent = OverlayController.instance.widthPercent;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final panelWidth =
            (screenWidth * (widthPercent / 100.0)).clamp(320.0, screenWidth);

        return Scaffold(
          backgroundColor: AppTheme.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Điểm neo DWM 1x1 pixel (alpha = 1/255) luôn tồn tại để ép DWM duy trì Composed Flip
              const Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color.fromARGB(1, 0, 0, 0),
                  ),
                ),
              ),
              IgnorePointer(
                ignoring: !isVisible,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 20,
                        bottom: 20,
                        right: 16,
                        left: 8,
                      ),
                      child: QuickSettingsPanel(config: widget.config),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

