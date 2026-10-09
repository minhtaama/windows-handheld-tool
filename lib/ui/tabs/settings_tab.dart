import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../services/dxgi_hook_service.dart';
import '../widgets/action_button.dart';
import '../widgets/hotkey_tile.dart';
import '../widgets/preset_selector.dart';
import '../widgets/section_label.dart';
import '../widgets/status_indicator.dart';
import '../widgets/toggle_card.dart';

/// Tab Cài đặt & Tiện ích: Phím tắt công cụ Windows, Cấu hình khởi động, Chế độ Hook và Tùy chỉnh hiển thị Side Panel.
class SettingsTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;

  // Khởi động cùng Windows
  final bool autoStartEnabled;
  final ValueChanged<bool> onToggleAutoStart;

  // Chế độ Overlay Hook (Phương án 2 Borderless vs Phương án 3 Shared Texture)
  final OverlayHookMode hookMode;
  final ValueChanged<OverlayHookMode> onHookModeChanged;

  // Callbacks công cụ hệ thống
  final VoidCallback onVirtualKeyboard;
  final VoidCallback onTaskManager;
  final VoidCallback onDisplaySettings;
  final VoidCallback onTrimMemory;
  final VoidCallback onClosePanel;

  // Trạng thái kết nối phần cứng
  final bool isRtssRunning;
  final String? activeGame;
  final bool isTdpHardwareActive;
  final bool isDxgiHookActive;
  final bool isGamepadConnected;

  // Cấu hình Phím tắt Đơn nhất (Bàn phím PC HOẶC Gamepad)
  final GlobalKey<HotkeyTileState>? overlayHotkeyTileKey;
  final String overlayHotkeyDevice;
  final String overlayHotkey;
  final void Function(String device, String hotkey) onOverlayHotkeyChanged;

  final GlobalKey<HotkeyTileState>? virtualKeyboardHotkeyTileKey;
  final String virtualKeyboardHotkeyDevice;
  final String virtualKeyboardHotkey;
  final void Function(String device, String hotkey)
  onVirtualKeyboardHotkeyChanged;

  // Tùy chỉnh hiển thị Side Panel
  final double scale;
  final ValueChanged<double> onScaleChanged;
  final int widthPercent;
  final ValueChanged<int> onWidthPercentChanged;

  const SettingsTab({
    super.key,
    required this.scrollController,
    required this.focusedIndex,
    required this.autoStartEnabled,
    required this.onToggleAutoStart,
    required this.hookMode,
    required this.onHookModeChanged,
    required this.onVirtualKeyboard,
    required this.onTaskManager,
    required this.onDisplaySettings,
    required this.onTrimMemory,
    required this.onClosePanel,
    required this.isRtssRunning,
    required this.activeGame,
    required this.isTdpHardwareActive,
    required this.isDxgiHookActive,
    required this.isGamepadConnected,
    this.overlayHotkeyTileKey,
    required this.overlayHotkeyDevice,
    required this.overlayHotkey,
    required this.onOverlayHotkeyChanged,
    this.virtualKeyboardHotkeyTileKey,
    required this.virtualKeyboardHotkeyDevice,
    required this.virtualKeyboardHotkey,
    required this.onVirtualKeyboardHotkeyChanged,
    required this.scale,
    required this.onScaleChanged,
    required this.widthPercent,
    required this.onWidthPercentChanged,
  });

  @override
  Widget build(BuildContext context) {
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
                icon: Icons.keyboard_alt_rounded,
                title: "Mở bàn phím ảo",
                isFocused: focusedIndex == 0,
                onTap: onVirtualKeyboard,
                helpText: "Mở bàn phím ảo trên màn hình (TabTip) của Windows để nhập liệu nhanh bằng cảm ứng hoặc cần điều khiển.",
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.analytics_outlined,
                title: "Mở Task Manager",
                isFocused: focusedIndex == 1,
                onTap: onTaskManager,
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
                icon: Icons.monitor_rounded,
                title: "Cài đặt màn hình",
                isFocused: focusedIndex == 2,
                onTap: onDisplaySettings,
                helpText: "Mở cửa sổ cài đặt hiển thị của Windows để thay đổi độ phân giải, tần số quét (Hz) hoặc cấu hình đa màn hình.",
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.cleaning_services_rounded,
                title: "Dọn dẹp RAM",
                isFocused: focusedIndex == 3,
                onTap: onTrimMemory,
                helpText: "Giải phóng bộ nhớ RAM đệm (Working Set Trimming) của các tiến trình nền để tăng dung lượng bộ nhớ trống cho game.",
              ),
            ),
          ],
        ),

        // 2. CẤU HÌNH HỆ THỐNG & TƯƠNG THÍCH
        const SectionLabel(label: "CẤU HÌNH HỆ THỐNG"),
        // Khởi động cùng Windows (Auto-start via Task Scheduler)
        ToggleCard(
          icon: Icons.power_settings_new_rounded,
          title: "Khởi động cùng Windows",
          subtitle: "Tự chạy với quyền Quản trị viên (Task Scheduler)",
          value: autoStartEnabled,
          onChanged: onToggleAutoStart,
          isFocused: focusedIndex == 4,
          helpText: "Kích hoạt tác vụ Windows Task Scheduler với quyền Quản trị viên tối đa (Highest Privileges) khi đăng nhập, khắc phục triệt để việc UAC chặn ứng dụng tự khởi động.",
        ),
        const SizedBox(height: 12),

        // Chế độ Overlay Hook: DXGI Borderless Hook vs Direct3D Shared Texture Injection
        PresetSelector<OverlayHookMode>(
          title: "Chế độ tương thích Game (Hook)",
          icon: Icons.layers_rounded,
          currentValueText: hookMode == OverlayHookMode.sharedTexture
              ? "Shared Texture"
              : "DXGI Borderless",
          presets: const [
            OverlayHookMode.dxgiBorderless,
            OverlayHookMode.sharedTexture,
          ],
          selectedValue: hookMode,
          labelBuilder: (m) => m == OverlayHookMode.sharedTexture
              ? "Shared Texture"
              : "DXGI Borderless",
          onSelected: onHookModeChanged,
          isFocused: focusedIndex == 5,
          helpText: "DXGI Borderless: Ép game toàn màn hình sang chế độ không viền (iFlip) để Quick Panel hiển thị đè mượt mà.\nShared Texture: Cơ chế OBS/Discord Overlay, nạp kết cấu GPU và vẽ đè trực tiếp lên bộ đệm BackBuffer tại hàm xuất hình Present.",
        ),
        const SizedBox(height: 12),

        // Phím tắt mở Quick Settings (Đơn nhất: Bàn phím PC HOẶC Gamepad)
        HotkeyTile(
          key: overlayHotkeyTileKey,
          icon: Icons.dashboard_customize_rounded,
          title: "Phím tắt mở Quick Settings",
          device: overlayHotkeyDevice,
          hotkey: overlayHotkey,
          onHotkeyChanged: onOverlayHotkeyChanged,
          isFocused: focusedIndex == 6,
          helpText: "Phím tắt duy nhất để bật hoặc ẩn bảng điều khiển Quick Settings (Bàn phím PC HOẶC Gamepad).",
        ),
        const SizedBox(height: 12),

        // Phím tắt mở Bàn phím ảo (Đơn nhất: Bàn phím PC HOẶC Gamepad)
        HotkeyTile(
          key: virtualKeyboardHotkeyTileKey,
          icon: Icons.keyboard_alt_rounded,
          title: "Phím tắt mở Bàn phím ảo",
          device: virtualKeyboardHotkeyDevice,
          hotkey: virtualKeyboardHotkey,
          onHotkeyChanged: onVirtualKeyboardHotkeyChanged,
          isFocused: focusedIndex == 7,
          helpText: "Phím tắt duy nhất để kích hoạt nhanh bàn phím ảo Windows TabTip khi chơi game (Bàn phím PC HOẶC Gamepad).",
        ),
        const SizedBox(height: 16),

        // 3. TÙY BIẾN GIAO DIỆN (UI SCALE & WIDTH)
        const SectionLabel(label: "TÙY BIẾN GIAO DIỆN"),

        // Tỷ lệ phóng đại UI Scale
        PresetSelector<double>(
          title: "Tỷ lệ hiển thị (UI Scale)",
          icon: Icons.format_size_rounded,
          currentValueText: "${(scale * 100).toInt()}%",
          presets: const [0.9, 1.0, 1.1, 1.2],
          selectedValue: scale,
          labelBuilder: (preset) => "${(preset * 100).toInt()}%",
          onSelected: onScaleChanged,
          isFocused: focusedIndex == 8,
        ),
        const SizedBox(height: 12),

        // Độ rộng Side Panel
        PresetSelector<int>(
          title: "Độ rộng Side Panel",
          icon: Icons.aspect_ratio_rounded,
          currentValueText: "$widthPercent %",
          presets: const [30, 35, 40, 45],
          selectedValue: widthPercent,
          labelBuilder: (preset) => "$preset%",
          onSelected: onWidthPercentChanged,
          isFocused: focusedIndex == 9,
        ),

        // 4. BẢNG TRẠNG THÁI KẾT NỐI (STATUS)
        const SectionLabel(label: "TRẠNG THÁI HỆ THỐNG"),
        StatusIndicatorCard(
          icon: Icons.speed_rounded,
          title: "RivaTuner RTSS",
          statusText: isRtssRunning
              ? (activeGame != null
                    ? "Đang hook game: $activeGame"
                    : "Đang chạy (Sẵn sàng đo FPS)")
              : "Chưa kết nối RTSS",
          isActive: isRtssRunning,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          icon: Icons.memory_rounded,
          title: "RyzenAdj TDP Driver",
          statusText: isTdpHardwareActive
              ? "WinRing0 Ring 0 Driver Hoạt động"
              : "Chế độ mô phỏng an toàn",
          isActive: isTdpHardwareActive,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          icon: Icons.layers_rounded,
          title: "Chế độ Game Hook",
          statusText: isDxgiHookActive
              ? (hookMode == OverlayHookMode.sharedTexture
                    ? "Direct3D Shared Texture Injection (Present Hook)"
                    : "DXGI Borderless Hook (iFlip Mode)")
              : "Chưa kích hoạt Hook",
          isActive: isDxgiHookActive,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          icon: Icons.sports_esports_rounded,
          title: "Tay cầm Gamepad",
          statusText: isGamepadConnected
              ? (overlayHotkeyDevice == 'gamepad' && overlayHotkey.isNotEmpty
                    ? "Đã kết nối (Phím tắt: $overlayHotkey)"
                    : "Đã kết nối (Sẵn sàng)")
              : "Chưa phát hiện tay cầm XInput",
          isActive: isGamepadConnected,
        ),

        // 5. THÔNG TIN PHẦN MỀM
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.info,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppTheme.cardBorder, width: 1.0),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: AppTheme.scaled(18),
                color: AppTheme.background,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Windows Handheld Tool",
                      style: AppTheme.title.copyWith(
                        color: AppTheme.background,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "v1.0 (Beta)",
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.background,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
