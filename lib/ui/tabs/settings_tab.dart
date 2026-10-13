import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../widgets/action_button.dart';
import '../widgets/hotkey_tile.dart';
import '../widgets/preset_selector.dart';
import '../widgets/section_label.dart';
import '../widgets/status_indicator.dart';
import '../widgets/toggle_card.dart';

/// Tab Cài đặt & Tiện ích: Phím tắt công cụ Windows, Cấu hình khởi động và Tùy chỉnh hiển thị Side Panel.
class SettingsTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;

  // Khởi động cùng Windows
  final bool autoStartEnabled;
  final ValueChanged<bool> onToggleAutoStart;

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
  final String overlayHotkeyDevice;
  final String overlayHotkey;
  final void Function(String device, String hotkey) onOverlayHotkeyChanged;

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
    required this.overlayHotkeyDevice,
    required this.overlayHotkey,
    required this.onOverlayHotkeyChanged,
    required this.virtualKeyboardHotkeyDevice,
    required this.virtualKeyboardHotkey,
    required this.onVirtualKeyboardHotkeyChanged,
    required this.scale,
    required this.onScaleChanged,
    required this.widthPercent,
    required this.onWidthPercentChanged,
    required this.getItemKey,
  });

  final GlobalKey Function(int index) getItemKey;

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
                key: getItemKey(0),
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
                key: getItemKey(1),
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
                key: getItemKey(2),
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
                key: getItemKey(3),
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
          key: getItemKey(4),
          icon: Icons.power_settings_new_rounded,
          title: "Khởi động cùng Windows",
          subtitle: "Tự chạy với quyền Quản trị viên (Task Scheduler)",
          value: autoStartEnabled,
          onChanged: onToggleAutoStart,
          isFocused: focusedIndex == 4,
          helpText: "Kích hoạt tác vụ Windows Task Scheduler với quyền Quản trị viên tối đa (Highest Privileges) khi đăng nhập, khắc phục triệt để việc UAC chặn ứng dụng tự khởi động.",
        ),
        const SizedBox(height: 12),

        // Phím tắt mở Quick Settings (Đơn nhất: Bàn phím PC HOẶC Gamepad)
        HotkeyTile(
          key: getItemKey(5),
          icon: Icons.dashboard_customize_rounded,
          title: "Phím tắt mở Quick Settings",
          device: overlayHotkeyDevice,
          hotkey: overlayHotkey,
          onHotkeyChanged: onOverlayHotkeyChanged,
          isFocused: focusedIndex == 5,
          helpText: "Phím tắt duy nhất để bật hoặc ẩn bảng điều khiển Quick Settings (Bàn phím PC HOẶC Gamepad).",
        ),
        const SizedBox(height: 12),

        // Phím tắt mở Bàn phím ảo (Đơn nhất: Bàn phím PC HOẶC Gamepad)
        HotkeyTile(
          key: getItemKey(6),
          icon: Icons.keyboard_alt_rounded,
          title: "Phím tắt mở Bàn phím ảo",
          device: virtualKeyboardHotkeyDevice,
          hotkey: virtualKeyboardHotkey,
          onHotkeyChanged: onVirtualKeyboardHotkeyChanged,
          isFocused: focusedIndex == 6,
          helpText: "Phím tắt duy nhất để kích hoạt nhanh bàn phím ảo Windows TabTip khi chơi game (Bàn phím PC HOẶC Gamepad).",
        ),
        const SizedBox(height: 16),

        // 3. TÙY BIẾN GIAO DIỆN (UI SCALE & WIDTH)
        const SectionLabel(label: "TÙY BIẾN GIAO DIỆN"),

        // Tỷ lệ phóng đại UI Scale
        PresetSelector<double>(
          key: getItemKey(7),
          title: "Tỷ lệ hiển thị (UI Scale)",
          icon: Icons.format_size_rounded,
          currentValueText: "${(scale * 100).toInt()}%",
          presets: const [0.9, 1.0, 1.1, 1.2],
          selectedValue: scale,
          labelBuilder: (preset) => "${(preset * 100).toInt()}%",
          onSelected: onScaleChanged,
          isFocused: focusedIndex == 7,
        ),
        const SizedBox(height: 12),

        // Độ rộng Side Panel
        PresetSelector<int>(
          key: getItemKey(8),
          title: "Độ rộng Side Panel",
          icon: Icons.aspect_ratio_rounded,
          currentValueText: "$widthPercent %",
          presets: const [30, 35, 40, 45],
          selectedValue: widthPercent,
          labelBuilder: (preset) => "$preset%",
          onSelected: onWidthPercentChanged,
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
          icon: Icons.memory_rounded,
          title: "RyzenAdj TDP Driver",
          statusText: isTdpHardwareActive
              ? "WinRing0 Ring 0 Driver Hoạt động"
              : "Chế độ mô phỏng an toàn",
          isActive: isTdpHardwareActive,
          isFocused: focusedIndex == 10,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          key: getItemKey(11),
          icon: Icons.layers_rounded,
          title: "DXGI Borderless Hook",
          statusText: isDxgiHookActive
              ? "Đang hoạt động (DWM iFlip Mode - 0% Overhead)"
              : "Sẵn sàng (Tự động kích hoạt khi vào game)",
          isActive: isDxgiHookActive,
          isFocused: focusedIndex == 11,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          key: getItemKey(12),
          icon: Icons.sports_esports_rounded,
          title: "Tay cầm Gamepad",
          statusText: isGamepadConnected
              ? (overlayHotkeyDevice == 'gamepad' && overlayHotkey.isNotEmpty
                    ? "Đã kết nối (Phím tắt: $overlayHotkey)"
                    : "Đã kết nối (Sẵn sàng)")
              : "Chưa phát hiện tay cầm XInput",
          isActive: isGamepadConnected,
          isFocused: focusedIndex == 12,
        ),

        // 5. THÔNG TIN PHẦN MỀM
        const SizedBox(height: 18),
        AnimatedContainer(
          key: getItemKey(13),
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.info,
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
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Windows Handheld Tool v1.2.1-oct12 • Portable",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
