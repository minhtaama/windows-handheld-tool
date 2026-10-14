import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'core/app_theme.dart';
import 'core/config.dart';
import 'core/icon_utils.dart';
import 'core/logger.dart';
import 'hardware/device_info_service.dart';
import 'hardware/touchscreen_service.dart';
import 'hardware/rtss_service.dart';
import 'input/hotkey_service.dart';
import 'input/gamepad_service.dart';
import 'services/autostart_service.dart';
import 'services/native_window_service.dart';
import 'services/overlay_controller.dart';
import 'services/virtual_keyboard_service.dart';
import 'ui/overlay_screen.dart';

const _logger = AppLogger('Main');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceInfoService.init();
  await TouchscreenService.init();
  await RtssService.instance.ensureRunning();
  final config = ConfigManager();
  OverlayController.instance.config = config;
  AutostartService.instance.init(config);

  // 1. Cấu hình Cửa sổ Side Dock Panel (Chuẩn Handheld Gaming Dock)
  await windowManager.ensureInitialized();

  final physicalSize = NativeWindowService.getPhysicalScreenSize();
  final screenWidth = physicalSize.width;
  final screenHeight = physicalSize.height;
  final initialPanelWidth = (screenWidth * (OverlayController.instance.widthPercent / 100.0)).clamp(320.0, 850.0);

  _logger.info('Physical screen size: $physicalSize, Initial panel width: $initialPanelWidth');

  final windowOptions = WindowOptions(
    title: 'Windows Handheld Tool',
    size: Size(initialPanelWidth, screenHeight),
    backgroundColor: AppTheme.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(AppTheme.transparent);
    await windowManager.setSize(Size(initialPanelWidth, screenHeight));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    NativeWindowService.hideDockWindow();
  });

  // Tự động đóng panel khi người dùng click ra ngoài (mất focus sang game/desktop)
  windowManager.addListener(_WindowBlurListener());

  // 2. Khởi tạo Khay hệ thống (System Tray) với đường dẫn icon tuyệt đối
  await _initSystemTray();

  // 3. Khởi tạo Phím tắt toàn cục & Gamepad (Hỗ trợ song song cả Tay cầm lẫn Bàn phím)
  final overlayGamepad = config.get("gamepad.overlay_combo", "BACK + RB");
  final overlayKeyboard = config.get("hotkey.toggle_overlay", "Ctrl+Shift+Q");

  final keyboardGamepad = config.get("gamepad.keyboard_combo", "BACK + LB");
  final keyboardKeyboard = config.get("hotkey.toggle_keyboard", "Ctrl+Shift+K");

  await HotkeyService.init(
    onToggleOverlay: () => OverlayController.instance.toggleOverlay(),
    onToggleKeyboard: () => VirtualKeyboardService.toggleKeyboard(
      actionVk: HotkeyService.keyboardBinding.vkCode,
    ),
    initialOverlayHotkey: overlayKeyboard,
    initialKeyboardHotkey: keyboardKeyboard,
  );

  // 4. Khởi tạo Gamepad Listener (XInput)
  if (config.get("gamepad.enabled", true)) {
    final pollMs = config.get("gamepad.poll_interval_ms", 50);
    GamepadService.start(
      onToggleOverlay: () => OverlayController.instance.toggleOverlay(),
      onToggleKeyboard: () => VirtualKeyboardService.toggleKeyboard(fromGamepad: true),
      initialOverlayCombo: overlayGamepad,
      initialKeyboardCombo: keyboardGamepad,
      intervalMs: pollMs,
    );
  }

  _logger.info('Handheld Quick Settings background service ready.');

  runApp(HandheldApp(config: config));
}

/// Tự động ẩn cửa sổ khi người dùng click chuột sang game hoặc ứng dụng khác
class _WindowBlurListener extends WindowListener {
  @override
  void onWindowBlur() {
    OverlayController.instance.handleWindowBlur();
  }
}

Future<void> _initSystemTray() async {
  try {
    final iconPath = await IconUtils.ensureIcoFile(Icons.sports_esports);
    await trayManager.setIcon(iconPath);
    _logger.info('Loaded Gamepad System Tray icon from: $iconPath');

    await trayManager.setToolTip(
      'Handheld Quick Settings (${DeviceInfoService.currentDevice.displayName})',
    );

    final menu = Menu(
      items: [
        MenuItem(key: 'toggle_overlay', label: 'Mở Panel'),
        MenuItem(key: 'virtual_keyboard', label: 'Bàn phím ảo'),
        MenuItem(key: 'toggle_touchscreen', label: 'Bật/Tắt màn hình cảm ứng'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'Thoát ứng dụng'),
      ],
    );
    await trayManager.setContextMenu(menu);

    trayManager.addListener(_TrayListener());
    _logger.info('System Tray configured successfully.');
  } catch (e) {
    _logger.warning('System Tray initialization failed: $e');
  }
}

class _TrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() {
    OverlayController.instance.toggleOverlay();
  }

  @override
  void onTrayIconRightMouseDown() {
    NativeWindowService.prepareForContextMenu();
    trayManager.popUpContextMenu();
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
      case 'toggle_touchscreen':
        TouchscreenService.toggleTouchscreen();
        break;
      case 'exit_app':
        GamepadService.stop();
        HotkeyService.dispose();
        exit(0);
    }
  }
}

class HandheldApp extends StatefulWidget {
  final ConfigManager config;

  const HandheldApp({super.key, required this.config});

  @override
  State<HandheldApp> createState() => _HandheldAppState();
}

class _HandheldAppState extends State<HandheldApp> {
  @override
  void initState() {
    super.initState();
    // Đợi frame đầu tiên vẽ xong hoàn toàn vào DirectX rồi dời off-screen chạy ngầm
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 150));
      NativeWindowService.hideDockWindow();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handheld Quick Settings',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: OverlayScreen(config: widget.config),
    );
  }
}
