import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'core/config.dart';
import 'hardware/rtss_osd_service.dart';
import 'services/bridge_service.dart';
import 'services/overlay_controller.dart';
import 'ui/quick_panel/quick_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ConfigManager();
  RtssOsdService.instance.init(config);
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
      // While the panel is hidden the window is SW_HIDE'd but Flutter would still tick its
      // animations and rasterize frames, stealing GPU time from the game (measured: -16% FPS).
      // TickerMode stops animation tickers and Offstage skips paint/layout while hidden.
      home: AnimatedBuilder(
        animation: OverlayController.instance,
        builder: (context, _) {
          final visible = OverlayController.instance.isVisible;
          return TickerMode(
            enabled: visible,
            child: Offstage(
              offstage: !visible,
              child: OverlayScreen(config: config),
            ),
          );
        },
      ),
    );
  }
}
