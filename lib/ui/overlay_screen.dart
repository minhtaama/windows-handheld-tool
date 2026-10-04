import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/logger.dart';
import 'quick_panel.dart';

const _logger = AppLogger('OverlayScreen');

/// Màn hình Quick Settings
class OverlayScreen extends StatelessWidget {
  final ConfigManager config;

  const OverlayScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    _logger.info('OverlayScreen build() dang chay...');
    return Scaffold(
      backgroundColor: const Color(0xFF1E2230),
      body: SafeArea(child: QuickSettingsPanel(config: config)),
    );
  }
}
