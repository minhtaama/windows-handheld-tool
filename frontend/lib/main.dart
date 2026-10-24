import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'core/config.dart';
import 'services/bridge_service.dart';
import 'services/overlay_controller.dart';
import 'ui/quick_panel/quick_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ConfigManager();
  OverlayController.instance.config = config;
  await BridgeService.instance.init();
  runApp(HandheldApp(config: config));
}

class HandheldApp extends StatelessWidget {
  final ConfigManager config;

  const HandheldApp({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handheld Quick Settings',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: OverlayScreen(config: config),
    );
  }
}
