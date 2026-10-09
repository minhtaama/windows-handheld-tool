import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../widgets/action_button.dart';
import '../widgets/preset_selector.dart';
import '../widgets/section_label.dart';
import '../widgets/status_indicator.dart';

/// Tab Cài đặt & Tiện ích: Phím tắt công cụ Windows, Tùy chỉnh hiển thị Side Panel và Trạng thái kết nối phần cứng.
class SettingsTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;

  // Trạng thái & Callback DXGI Hook
  final bool dxgiHookEnabled;
  final VoidCallback onToggleDxgiHook;

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

  // Tùy chỉnh hiển thị Side Panel
  final double scale;
  final ValueChanged<double> onScaleChanged;
  final int widthPercent;
  final ValueChanged<int> onWidthPercentChanged;

  const SettingsTab({
    super.key,
    required this.scrollController,
    required this.focusedIndex,
    required this.dxgiHookEnabled,
    required this.onToggleDxgiHook,
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
        // 1. CÔNG CỤ HỆ THỐNG (Chuyển dịch từ Tab Tiện ích sang)
        const SectionLabel(label: "CÔNG CỤ HỆ THỐNG"),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.keyboard_alt_rounded,
                title: "Bàn phím ảo",
                subtitle: "Mở TabTip OSK",
                isFocused: focusedIndex == 0,
                onTap: onVirtualKeyboard,
                helpText: "Mở bàn phím ảo trên màn hình (TabTip) của Windows để nhập liệu nhanh bằng cảm ứng hoặc cần điều khiển.",
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.analytics_outlined,
                title: "Task Manager",
                subtitle: "Quản lý tiến trình",
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
                title: "Màn hình",
                subtitle: "Đổi độ phân giải",
                isFocused: focusedIndex == 2,
                onTap: onDisplaySettings,
                helpText: "Mở cửa sổ cài đặt hiển thị của Windows để thay đổi độ phân giải, tần số quét (Hz) hoặc cấu hình đa màn hình.",
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.layers_rounded,
                title: "DXGI Hook",
                subtitle: dxgiHookEnabled
                    ? "Đang Bật (Borderless)"
                    : "Đã Tắt (FSE Gốc)",
                isFocused: focusedIndex == 3,
                onTap: onToggleDxgiHook,
                helpText: "Ép chế độ Borderless Fullscreen cho các game chạy Exclusive Fullscreen, giúp Quick Panel hiển thị đè mượt mà không bị đen màn hình.",
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.cleaning_services_rounded,
                title: "Dọn dẹp RAM",
                subtitle: "Tối ưu bộ nhớ",
                isFocused: focusedIndex == 4,
                onTap: onTrimMemory,
                helpText: "Giải phóng bộ nhớ RAM đệm (Working Set Trimming) của các tiến trình nền để tăng dung lượng bộ nhớ trống cho game.",
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.fullscreen_exit_rounded,
                title: "Đóng Panel",
                subtitle: "Phím: B / Back+RB",
                isFocused: focusedIndex == 5,
                onTap: onClosePanel,
                helpText: "Đóng giao diện Quick Settings Panel và trả quyền điều khiển về cho game. Bạn cũng có thể bấm nút B hoặc tổ hợp Back + RB trên tay cầm.",
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. TÙY BIẾN GIAO DIỆN (UI SCALE & WIDTH)
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
          isFocused: focusedIndex == 6,
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
          isFocused: focusedIndex == 7,
        ),
        const SizedBox(height: 16),

        // 3. BẢNG TRẠNG THÁI KẾT NỐI (STATUS)
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
          title: "DXGI Borderless Hook",
          statusText: isDxgiHookActive
              ? "Hỗ trợ Borderless iFlip (Chống giật lag)"
              : "Đã tắt (Chế độ FSE gốc)",
          isActive: isDxgiHookActive,
        ),
        const SizedBox(height: 8),

        StatusIndicatorCard(
          icon: Icons.sports_esports_rounded,
          title: "Tay cầm Gamepad",
          statusText: isGamepadConnected
              ? "Đã kết nối (Phím tắt: Back + RB)"
              : "Chưa phát hiện tay cầm XInput",
          isActive: isGamepadConnected,
        ),
        const SizedBox(height: 16),

        // 4. THÔNG TIN PHẦN MỀM
        const SectionLabel(label: "THÔNG TIN"),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppTheme.cardBorder, width: 1.0),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: AppTheme.scaled(18),
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Windows Handheld Tools", style: AppTheme.body),
                    const SizedBox(height: 2),
                    Text("v1.0", style: AppTheme.caption),
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
