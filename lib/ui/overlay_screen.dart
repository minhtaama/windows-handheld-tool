import 'package:flutter/material.dart';
import '../core/config.dart';
import '../services/overlay_controller.dart';
import 'quick_panel.dart';

/// Màn hình Overlay toàn màn hình có vùng backdrop trong suốt và thanh trượt bên phải.
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
    final durationMs = widget.config.get("overlay.animation_duration_ms", 220);
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Bắt đầu ở ngoài mép phải màn hình
      end: Offset.zero,              // Trượt vào hiển thị trọn vẹn
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    OverlayController.instance.addListener(_handleVisibilityChange);
  }

  void _handleVisibilityChange() {
    if (OverlayController.instance.isVisible) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    OverlayController.instance.removeListener(_handleVisibilityChange);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = widget.config.get("overlay.width", 360).toDouble();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          // Vùng trong suốt bên trái: Bấm vào bất kỳ đâu sẽ ẩn overlay
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => OverlayController.instance.hideOverlay(),
              child: const SizedBox.expand(),
            ),
          ),
          // Bảng Quick Settings trượt từ phải sang
          SlideTransition(
            position: _slideAnimation,
            child: SizedBox(
              width: panelWidth,
              height: double.infinity,
              child: QuickSettingsPanel(config: widget.config),
            ),
          ),
        ],
      ),
    );
  }
}
