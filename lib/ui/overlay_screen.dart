import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/config.dart';
import '../services/overlay_controller.dart';
import 'quick_panel.dart';

/// Màn hình Side Dock Panel chuẩn True Fullscreen Transparent Overlay.
/// Toàn bộ không gian trong suốt bao phủ toàn màn hình, hỗ trợ co dãn bề rộng panel linh hoạt
/// với AnimatedContainer, đóng mở mượt mà bằng SlideTransition và tùy chỉnh tỷ lệ phóng đại UI Scale.
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
  late final Animation<double> _panelFadeAnimation;

  @override
  void initState() {
    super.initState();

    final durationMs = widget.config.get("overlay.animation_duration_ms", 180);

    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
      reverseDuration: Duration(milliseconds: durationMs),
      value: 0.0, // Ban đầu ở trạng thái đóng (ẩn ngoài màn hình)
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
        final isVisible = OverlayController.instance.isVisible;
        final screenWidth = MediaQuery.of(context).size.width;
        final panelWidth = (screenWidth * (OverlayController.instance.widthPercent / 100.0))
            .clamp(320.0, 850.0);

        // Panel trải dài toàn dải 100% chiều cao màn hình và phủ đè lên trên thanh Taskbar
        const bottomPadding = 20.0;

        return ExcludeSemantics(
          excluding: true,
          child: IgnorePointer(
            ignoring: !isVisible,
            child: Scaffold(
              backgroundColor: AppTheme.transparent,
              body: Stack(
                children: [
                  // Vùng nền trong suốt bên trái: Chạm vào để đóng panel
                  if (isVisible)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => OverlayController.instance.hideOverlay(),
                      ),
                    ),

                  // Side Dock Panel neo sát mép phải với hoạt cảnh co dãn AnimatedContainer
                  Align(
                    alignment: Alignment.centerRight,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _panelFadeAnimation,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          width: panelWidth,
                          padding: EdgeInsets.only(
                            top: 20,
                            bottom: bottomPadding,
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
            ),
          ),
        );
      },
    );
  }
}
