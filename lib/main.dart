import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'core/app_theme.dart';
import 'core/config.dart';
import 'core/logger.dart';
import 'input/hotkey_service.dart';
import 'input/gamepad_service.dart';
import 'services/overlay_controller.dart';
import 'services/virtual_keyboard_service.dart';
import 'ui/overlay_screen.dart';

const _logger = AppLogger('Main');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ConfigManager();

  // 1. Cấu hình Cửa sổ Windows (Window Manager)
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    title: 'Handheld Quick Settings',
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setFullScreen(true);
    await windowManager.setBackgroundColor(Colors.transparent);
    // Khởi động ở trạng thái ẩn sẵn sàng chạy ngầm
    await windowManager.hide();
  });

  // 2. Khởi tạo Khay hệ thống (System Tray)
  await _initSystemTray();

  // 3. Khởi tạo Phím tắt toàn cục (Global Hotkeys)
  await HotkeyService.init(
    onToggleOverlay: () => OverlayController.instance.toggleOverlay(),
    onToggleKeyboard: () => VirtualKeyboardService.toggleKeyboard(),
  );

  // 4. Khởi tạo Gamepad Listener (XInput)
  if (config.get("gamepad.enabled", true)) {
    final pollMs = config.get("gamepad.poll_interval_ms", 50);
    GamepadService.start(
      onTriggerCombo: () => OverlayController.instance.toggleOverlay(),
      intervalMs: pollMs,
    );
  }

  _logger.info('Handheld Quick Settings Flutter đã sẵn sàng chạy ngầm!');

  runApp(HandheldApp(config: config));
}

Future<void> _initSystemTray() async {
  try {
    await trayManager.setIcon(
      Platform.isWindows ? 'windows/runner/resources/app_icon.ico' : '',
    );
    await trayManager.setToolTip('Handheld Quick Settings (GPD Win 4)');

    final menu = Menu(
      items: [
        MenuItem(
          key: 'toggle_overlay',
          label: 'Mở Quick Settings (Ctrl+Shift+Q)',
        ),
        MenuItem(
          key: 'virtual_keyboard',
          label: 'Bàn phím ảo (Ctrl+Shift+K)',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'Thoát ứng dụng',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);

    trayManager.addListener(_TrayListener());
    _logger.info('Đã cấu hình System Tray thành công.');
  } catch (e) {
    _logger.warning('Khởi tạo System Tray gặp lỗi: $e');
  }
}

class _TrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() {
    OverlayController.instance.toggleOverlay();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle_overlay':
        OverlayController.instance.toggleOverlay();
        break;
      case 'virtual_keyboard':
        VirtualKeyboardService.toggleKeyboard();
        break;
      case 'exit_app':
        GamepadService.stop();
        HotkeyService.dispose();
        exit(0);
    }
  }
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
