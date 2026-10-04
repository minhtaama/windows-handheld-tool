import 'package:flutter/material.dart';
import '../core/config.dart';
import '../services/overlay_controller.dart';
import 'quick_panel.dart';

/// Màn hình Side Dock Panel có hoạt cảnh Fade mượt mà (chống tràn pixel tuyệt đối).
class OverlayScreen extends StatefulWidget {
  final ConfigManager config;

  const OverlayScreen({super.key, required this.config});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    final durationMs = widget.config.get("overlay.animation_duration_ms", 150);

    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
      reverseDuration: const Duration(milliseconds: 120),
      value: 1.0, // Ban đầu đã ở vị trí sẵn sàng
    );

    // Hoạt cảnh Fade: mờ dần - sáng dần (không can thiệp tọa độ X/Y, chống lệch ma trận render)
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: QuickSettingsPanel(config: widget.config),
      ),
    );
  }
}
