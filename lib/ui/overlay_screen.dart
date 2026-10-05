import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/config.dart';
import '../services/overlay_controller.dart';
import 'quick_panel.dart';

/// Màn hình Side Dock Panel chuẩn Fullscreen Transparent Overlay (chống phá vỡ DirectX SwapChain).
class OverlayScreen extends StatefulWidget {
  final ConfigManager config;

  const OverlayScreen({super.key, required this.config});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _backdropFadeAnimation;
  late final Animation<double> _panelFadeAnimation;

  @override
  void initState() {
    super.initState();

    final durationMs = widget.config.get("overlay.animation_duration_ms", 180);

    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
      reverseDuration: const Duration(milliseconds: 140),
      value: 1.0, // Ban đầu ở trạng thái sẵn sàng
    );

    // Hoạt cảnh trượt: từ ngoài mép phải vào sát mép phải
    _slideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    // Hoạt cảnh làm mờ nền tối Backdrop phía sau
    _backdropFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    // Hoạt cảnh mờ dần (Fade In / Fade Out) đồng bộ cho Side Panel
    _panelFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    // Đăng ký bộ kích hoạt hoạt cảnh với OverlayController
    OverlayController.instance.onAnimateShow = () async {
      try {
        await _animController.forward(from: 0.0);
      } catch (_) {}
    };

    OverlayController.instance.onAnimateHide = () async {
      try {
        await _animController.reverse();
      } catch (_) {}
    };
  }

  @override
  void dispose() {
    OverlayController.instance.onAnimateShow = null;
    OverlayController.instance.onAnimateHide = null;
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OverlayController.instance,
      builder: (context, _) {
        final widthPercent = OverlayController.instance.widthPercent;

        return Scaffold(
          backgroundColor: AppTheme.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = constraints.maxWidth;
              final panelWidth = (screenWidth * (widthPercent / 100.0)).clamp(
                280.0,
                screenWidth * 0.6,
              );

              return Stack(
                children: [
                  // 1. Nền trong suốt (Backdrop): Chạm/click ra ngoài để đóng Side Panel
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: _backdropFadeAnimation,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => OverlayController.instance.hideOverlay(),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),

                  // 2. Floating Panel dạng thẻ nổi (vừa trượt vừa làm mờ)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _panelFadeAnimation,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: panelWidth,
                          height: double.infinity,
                          padding: const EdgeInsets.only(
                            top: 24,
                            bottom: 24,
                            right: 20,
                          ),
                          child: QuickSettingsPanel(config: widget.config),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
