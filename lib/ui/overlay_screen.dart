import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/config.dart';
import '../services/overlay_controller.dart';
import 'quick_panel.dart';

/// Màn hình Side Dock Panel neo sát mép phải màn hình (Right Dock Window).
/// Cửa sổ Win32 bên ngoài có kích thước đúng bằng panelWidth x screenHeight,
/// loại bỏ hoàn toàn các lớp phủ trong suốt toàn màn hình và hit-test hack.
class OverlayScreen extends StatelessWidget {
  final ConfigManager config;

  const OverlayScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OverlayController.instance,
      builder: (context, _) {
        final isVisible = OverlayController.instance.isVisible;

        return Scaffold(
          backgroundColor: AppTheme.transparent,
          body: isVisible
              ? SizedBox.expand(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 20,
                      bottom: 20,
                      right: 16,
                      left: 8,
                    ),
                    child: QuickSettingsPanel(config: config),
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}
