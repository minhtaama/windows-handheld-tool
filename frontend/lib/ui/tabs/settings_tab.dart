import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../input/gamepad_service.dart';
import '../../hardware/rtss_service.dart';
import '../../services/autostart_service.dart';
import '../../services/bridge_service.dart';
import '../../services/overlay_controller.dart';
import '../../services/system_optimizer.dart';
import '../../services/system_telemetry_service.dart';
import '../../services/virtual_keyboard_service.dart';
import '../quick_panel/gamepad_navigable.dart';
import '../widgets/action_button.dart';
import '../widgets/hotkey_tile.dart';
import '../widgets/preset_selector.dart';
import '../widgets/section_label.dart';
import '../widgets/status_indicator.dart';
import '../widgets/toggle_card.dart';

/// Tab Cài đặt & Tiện ích: Phím tắt công cụ Windows, Cấu hình khởi động và Tùy chỉnh hiển thị Side Panel.
class SettingsTab extends StatefulWidget {
  final ConfigManager? config;

  const SettingsTab({super.key, this.config});

  @override
  State<SettingsTab> createState() => SettingsTabState();
}

class SettingsTabState extends State<SettingsTab>
    with GamepadNavigableMixin<SettingsTab> {
  late final RtssFpsController _rtssCtrl;

  late bool _autoStartEnabled;
  late String _overlayHotkeyDevice;
  late String _overlayHotkey;
  late String _virtualKeyboardHotkeyDevice;
  late String _virtualKeyboardHotkey;
  late double _scale;
  late int _widthPercent;

  @override
  void initState() {
    super.initState();
    final cfg = widget.config ?? ConfigManager();
    _rtssCtrl = RtssFpsController();

    _autoStartEnabled = AutostartService.instance.isEnabled;

    final kbOverlay = cfg.get("hotkey.toggle_overlay", "Ctrl+Shift+Q");
    final gpOverlay = cfg.get("gamepad.overlay_combo", "");
    if (kbOverlay.isNotEmpty) {
      _overlayHotkeyDevice = 'keyboard';
      _overlayHotkey = kbOverlay;
    } else if (gpOverlay.isNotEmpty) {
      _overlayHotkeyDevice = 'gamepad';
      _overlayHotkey = gpOverlay;
    } else {
      _overlayHotkeyDevice = 'keyboard';
      _overlayHotkey = 'Ctrl+Shift+Q';
    }

    final kbKb = cfg.get("hotkey.toggle_keyboard", "Ctrl+Alt+K");
    final gpKb = cfg.get("gamepad.keyboard_combo", "");
    if (kbKb.isNotEmpty) {
      _virtualKeyboardHotkeyDevice = 'keyboard';
      _virtualKeyboardHotkey = kbKb;
    } else if (gpKb.isNotEmpty) {
      _virtualKeyboardHotkeyDevice = 'gamepad';
      _virtualKeyboardHotkey = gpKb;
    } else {
      _virtualKeyboardHotkeyDevice = 'keyboard';
      _virtualKeyboardHotkey = 'Ctrl+Alt+K';
    }

    _scale = (cfg.get("overlay.scale", 1.0) as num).toDouble();
    _widthPercent = cfg.get("overlay.width_percent", 35);

    BridgeService.instance.autostart.addListener(_onBridgeAutostartChanged);
    GamepadService.isConnected.addListener(_onGamepadConnectionChanged);
  }

  void _onGamepadConnectionChanged() {
    if (mounted) setState(() {});
  }

  void _onBridgeAutostartChanged() {
    if (!mounted) return;
    final val = BridgeService.instance.autostart.value;
    if (_autoStartEnabled != val) {
      setState(() => _autoStartEnabled = val);
    }
  }

  void _toggleAutoStart(bool val) async {
    setState(() => _autoStartEnabled = val);
    await AutostartService.instance.setEnabled(val);
    if (mounted) {
      setState(() => _autoStartEnabled = AutostartService.instance.isEnabled);
    }
  }

  void _updateOverlayHotkey(String device, String hotkey) {
    setState(() {
      _overlayHotkeyDevice = device;
      _overlayHotkey = hotkey;
    });
    if (device == 'keyboard') {
      widget.config?.set("hotkey.toggle_overlay", hotkey);
      widget.config?.set("gamepad.overlay_combo", "");
    } else {
      widget.config?.set("gamepad.overlay_combo", hotkey);
      widget.config?.set("hotkey.toggle_overlay", "");
    }
  }

  void _updateVirtualKeyboardHotkey(String device, String hotkey) {
    setState(() {
      _virtualKeyboardHotkeyDevice = device;
      _virtualKeyboardHotkey = hotkey;
    });
    if (device == 'keyboard') {
      widget.config?.set("hotkey.toggle_keyboard", hotkey);
      widget.config?.set("gamepad.keyboard_combo", "");
    } else {
      widget.config?.set("gamepad.keyboard_combo", hotkey);
      widget.config?.set("hotkey.toggle_keyboard", "");
    }
  }

  void _updateScale(double val) {
    setState(() => _scale = val);
    AppTheme.uiScale = val;
    widget.config?.set("overlay.scale", val);
  }

  void _updateWidthPercent(int val) {
    setState(() => _widthPercent = val);
    widget.config?.set("overlay.width_percent", val);
    BridgeService.instance.setPanelWidth(val);
  }

  @override
  List<List<int>> get navigationLayout => const [
    [0, 1],
    [2, 3],
    [4],
    [5],
    [6],
    [7],
    [8],
    [9],
    [10],
    [11],
    [12],
    [13],
  ];

  @override
  void onGamepadActionA(int focusedIndex) async {
    switch (focusedIndex) {
      case 0:
        await OverlayController.instance.hideOverlay();
        VirtualKeyboardService.toggleKeyboard();
        break;
      case 1:
        await OverlayController.instance.hideOverlay();
        BridgeService.instance.launchTaskManager();
        break;
      case 2:
        await OverlayController.instance.hideOverlay();
        BridgeService.instance.launchDisplaySettings();
        break;
      case 3:
        SystemOptimizer.trimMemory();
        break;
      case 4:
        _toggleAutoStart(!_autoStartEnabled);
        break;
      case 7:
        cyclePreset(const [0.9, 1.0, 1.1, 1.2], _scale, 1, _updateScale);
        break;
      case 8:
        cyclePreset(
          const [30, 35, 40, 45],
          _widthPercent,
          1,
          _updateWidthPercent,
        );
        break;
    }
  }

  @override
  void onGamepadAdjustSlider(int focusedIndex, int direction) {
    switch (focusedIndex) {
      case 7:
        cyclePreset(
          const [0.9, 1.0, 1.1, 1.2],
          _scale,
          direction,
          _updateScale,
        );
        break;
      case 8:
        cyclePreset(
          const [30, 35, 40, 45],
          _widthPercent,
          direction,
          _updateWidthPercent,
        );
        break;
    }
  }

  @override
  void dispose() {
    BridgeService.instance.autostart.removeListener(_onBridgeAutostartChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telem = SystemTelemetryService.instance.latest;
    final isRtssRunning = _rtssCtrl.isAvailable();
    final activeGame = _rtssCtrl.getActiveGame();

    return ListView(
      key: const ValueKey('tab_settings'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // 1. CÔNG CỤ HỆ THỐNG
        const SectionLabel(label: "CÔNG CỤ HỆ THỐNG", isFirst: true),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                key: getItemKey(0),
                icon: Icons.keyboard_alt_rounded,
                title: "Mở bàn phím ảo",
                isFocused: focusedIndex == 0,
                onTap: () async {
                  await OverlayController.instance.hideOverlay();
                  VirtualKeyboardService.toggleKeyboard();
                },
                helpText: "Mở bàn phím ảo trên màn hình (TabTip) của Windows để nhập liệu nhanh bằng cảm ứng hoặc cần điều khiển.",
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                key: getItemKey(1),
                icon: Icons.analytics_outlined,
                title: "Mở Task Manager",
                isFocused: focusedIndex == 1,
                onTap: () async {
                  await OverlayController.instance.hideOverlay();
                  BridgeService.instance.launchTaskManager();
                },
                helpText: "Mở Trình quản lý tác vụ (Task Manager) để theo dõi tài nguyên phần cứng và quản lý các tiến trình đang chạy.",
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                key: getItemKey(2),
                icon: Icons.monitor_rounded,
                title: "Cài đặt màn hình",
                isFocused: focusedIndex == 2,
                onTap: () async {
                  await OverlayController.instance.hideOverlay();
                  BridgeService.instance.launchDisplaySettings();
                },
                helpText: "Mở cửa sổ cài đặt hiển thị của Windows để thay đổi độ phân giải, tần số quét (Hz) hoặc cấu hình đa màn hình.",
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                key: getItemKey(3),
                icon: Icons.cleaning_services_rounded,
                title: "Dọn dẹp RAM",
                isFocused: focusedIndex == 3,
                onTap: SystemOptimizer.trimMemory,
                helpText: "Giải phóng bộ nhớ RAM đệm (Working Set Trimming) của các tiến trình nền để tăng dung lượng bộ nhớ trống cho game.",
              ),
            ),
          ],
        ),

        // 2. CẤU HÌNH HỆ THỐNG & TƯƠNG THÍCH
        const SectionLabel(label: "CẤU HÌNH HỆ THỐNG"),
        ToggleCard(
          key: getItemKey(4),
          icon: Icons.power_settings_new_rounded,
          title: "Khởi động cùng Windows",
          subtitle: "Tự chạy với quyền Quản trị viên (Task Scheduler)",
          value: _autoStartEnabled,
          onChanged: _toggleAutoStart,
          isFocused: focusedIndex == 4,
          helpText: "Kích hoạt tác vụ Windows Task Scheduler với quyền Quản trị viên tối đa (Highest Privileges) khi đăng nhập, khắc phục triệt để việc UAC chặn ứng dụng tự khởi động.",
        ),
        const SizedBox(height: 12),

        HotkeyTile(
          key: getItemKey(5),
          icon: Icons.dashboard_customize_rounded,
          title: "Phím tắt mở Quick Settings",
          target: "overlay",
          device: _overlayHotkeyDevice,
          hotkey: _overlayHotkey,
          onHotkeyChanged: _updateOverlayHotkey,
          isFocused: focusedIndex == 5,
          helpText: "Phím tắt duy nhất để bật hoặc ẩn bảng điều khiển Quick Settings (Bàn phím PC HOẶC Gamepad).",
        ),
        const SizedBox(height: 12),

        HotkeyTile(
          key: getItemKey(6),
          icon: Icons.keyboard_alt_rounded,
          title: "Phím tắt mở Bàn phím ảo",
          target: "keyboard",
          device: _virtualKeyboardHotkeyDevice,
          hotkey: _virtualKeyboardHotkey,
          onHotkeyChanged: _updateVirtualKeyboardHotkey,
          isFocused: focusedIndex == 6,
          helpText: "Phím tắt duy nhất để kích hoạt nhanh bàn phím ảo Windows TabTip khi chơi game (Bàn phím PC HOẶC Gamepad).",
        ),
        const SizedBox(height: 16),

        // 3. TÙY BIẾN GIAO DIỆN (UI SCALE & WIDTH)
        const SectionLabel(label: "TÙY BIẾN GIAO DIỆN"),
        PresetSelector<double>(
          key: getItemKey(7),
          title: "Tỷ lệ hiển thị (UI Scale)",
          icon: Icons.format_size_rounded,
          currentValueText: "${(_scale * 100).toInt()}%",
          presets: const [0.9, 1.0, 1.1, 1.2],
          selectedValue: _scale,
          labelBuilder: (preset) => "${(preset * 100).toInt()}%",
          onSelected: _updateScale,
          isFocused: focusedIndex == 7,
        ),
        const SizedBox(height: 12),

        PresetSelector<int>(
          key: getItemKey(8),
          title: "Độ rộng Side Panel",
          icon: Icons.aspect_ratio_rounded,
          currentValueText: "$_widthPercent %",
          presets: const [30, 35, 40, 45],
          selectedValue: _widthPercent,
          labelBuilder: (preset) => "$preset%",
          onSelected: _updateWidthPercent,
          isFocused: focusedIndex == 8,
        ),

        // 4. BẢNG TRẠNG THÁI KẾT NỐI (STATUS)
        const SectionLabel(label: "TRẠNG THÁI HỆ THỐNG"),
        StatusIndicatorCard(
          key: getItemKey(9),
          icon: Icons.speed_rounded,
          title: "RivaTuner RTSS",
          statusText: isRtssRunning
              ? (activeGame != null
                    ? "Đang hook game: $activeGame"
                    : "Đang chạy (Sẵn sàng đo FPS)")
              : "Chưa kết nối RTSS",
          isActive: isRtssRunning,
          isFocused: focusedIndex == 9,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          key: getItemKey(10),
          icon: telem.isTdpHardwareActive
              ? Icons.memory_rounded
              : Icons.warning_amber_rounded,
          title: "RyzenAdj TDP Driver",
          statusText: telem.isTdpHardwareActive
              ? "WinRing0 Ring 0 Driver Hoạt động"
              : (telem.isHvciBlocked
                    ? "Bị chặn bởi Memory Integrity (HVCI) - Cần tắt HVCI"
                    : "Chưa nạp được driver Ring 0"),
          isActive: telem.isTdpHardwareActive,
          isFocused: focusedIndex == 10,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          key: getItemKey(11),
          icon: Icons.layers_rounded,
          title: "Windows System Z-Band",
          statusText: "Hoạt động (ZBID_SYSTEM_TOOLS - UIAccess)",
          isActive: true,
          isFocused: focusedIndex == 11,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          key: getItemKey(12),
          icon: Icons.sports_esports_rounded,
          title: "Tay cầm Gamepad",
          statusText: GamepadService.isConnected.value
              ? (_overlayHotkeyDevice == 'gamepad' && _overlayHotkey.isNotEmpty
                    ? "Đã kết nối (Phím tắt: $_overlayHotkey)"
                    : "Đã kết nối (Sẵn sàng)")
              : "Chưa phát hiện tay cầm XInput",
          isActive: GamepadService.isConnected.value,
          isFocused: focusedIndex == 12,
        ),

        // 5. THÔNG TIN PHẦN MỀM
        const SizedBox(height: 18),
        AnimatedContainer(
          key: getItemKey(13),
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 40, 132, 243),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: focusedIndex == 13
                  ? AppTheme.accent.withValues(alpha: 0.35)
                  : AppTheme.cardBorder,
              width: 1.0,
            ),
            boxShadow: focusedIndex == 13
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      blurRadius: 8,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTheme.background,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Windows Handheld Tool v1.4-oct26",
                  style: TextStyle(
                    fontSize: AppTheme.scaled(12),
                    fontWeight: FontWeight.w500,
                    color: AppTheme.background,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
