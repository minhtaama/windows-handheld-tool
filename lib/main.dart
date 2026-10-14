import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'core/config.dart';
import 'services/bridge_service.dart';
import 'ui/overlay_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BridgeService.instance.init();
  final config = ConfigManager();
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
