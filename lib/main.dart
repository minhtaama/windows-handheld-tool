import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

import 'core/app_theme.dart';
import 'core/config.dart';
import 'core/logger.dart';
import 'hardware/device_info_service.dart';
import 'hardware/touchscreen_service.dart';
import 'hardware/rtss_service.dart';
import 'input/hotkey_service.dart';
import 'input/gamepad_service.dart';
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

  // 1. Cấu hình Cửa sổ Side-Panel (Áp sát mép phải màn hình)
  await windowManager.ensureInitialized();

  final primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final screenHeight = primaryDisplay.size.height;
  final screenWidth = primaryDisplay.size.width;
  final panelWidth = config.get("overlay.width", 380).toDouble();

  final windowOptions = WindowOptions(
    title: 'Handheld Quick Settings',
    size: Size(panelWidth, screenHeight),
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setSize(Size(panelWidth, screenHeight));
    await windowManager.setPosition(Offset(screenWidth - panelWidth, 0));
    await windowManager.setAlwaysOnTop(true);
    // Để Flutter Engine vẽ hoàn thành frame đầu tiên vào DirectX buffer trước khi ẩn
  });

  // Tự động đóng panel khi người dùng click ra ngoài (mất focus sang game/desktop)
  windowManager.addListener(_WindowBlurListener());

  // 2. Khởi tạo Khay hệ thống (System Tray) với đường dẫn icon tuyệt đối
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

/// Tự động ẩn cửa sổ khi người dùng click chuột sang game hoặc ứng dụng khác
class _WindowBlurListener extends WindowListener {
  @override
  void onWindowBlur() {
    OverlayController.instance.handleWindowBlur();
  }
}

Future<void> _initSystemTray() async {
  try {
    final iconFile = File('windows/runner/resources/app_icon.ico');
    final iconPath = iconFile.existsSync() ? iconFile.absolute.path : '';

    if (iconPath.isNotEmpty) {
      await trayManager.setIcon(iconPath);
      _logger.info('Đã tải System Tray icon từ: $iconPath');
    } else {
      _logger.warning('Không tìm thấy file app_icon.ico');
    }

    await trayManager.setToolTip('Handheld Quick Settings (${DeviceInfoService.currentDevice.displayName})');

    final menu = Menu(
      items: [
        MenuItem(
          key: 'toggle_overlay',
          label: 'Mở Quick Settings (Ctrl+Shift+Q)',
        ),
        MenuItem(key: 'virtual_keyboard', label: 'Bàn phím ảo (Ctrl+Shift+K)'),
        MenuItem(key: 'toggle_touchscreen', label: 'Bật/Tắt màn hình cảm ứng'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'Thoát ứng dụng'),
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
    // Đợi frame đầu tiên vẽ xong hoàn toàn vào DirectX rồi mới ẩn xuống chạy ngầm
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 150));
      await windowManager.hide();
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
