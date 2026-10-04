import 'package:flutter/material.dart';
import '../core/config.dart';
import '../services/overlay_controller.dart';
import 'quick_panel.dart';

/// Màn hình Side Dock Panel có hoạt cảnh trượt mượt mà từ mép phải màn hình.
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

  @override
  void initState() {
    super.initState();

    final durationMs = widget.config.get("overlay.animation_duration_ms", 200);

    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
      reverseDuration: const Duration(milliseconds: 180),
      value: 1.0, // Ban đầu đã ở vị trí sẵn sàng
    );

    // Hoạt cảnh trượt: từ mép phải (Offset(1.0, 0.0)) vào vị trí hiển thị (Offset.zero)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    // Đăng ký bộ kích hoạt hoạt cảnh trượt với OverlayController
    OverlayController.instance.onAnimateShow = () async {
      await _animController.forward(from: 0.0);
    };

    OverlayController.instance.onAnimateHide = () async {
      await _animController.reverse();
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
      body: SlideTransition(
        position: _slideAnimation,
        child: QuickSettingsPanel(config: widget.config),
      ),
    );
  }
}
