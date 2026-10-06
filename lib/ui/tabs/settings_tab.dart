import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../widgets/preset_selector.dart';
import '../widgets/section_label.dart';
import '../widgets/status_indicator.dart';

/// Tab Cài đặt & Trạng thái: Bảng kiểm tra kết nối phần cứng (RTSS, RyzenAdj, DXGI Hook, Gamepad)
/// và các tùy chỉnh kích thước hiển thị của Side Panel.
class SettingsTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;

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
        // 1. BẢNG TRẠNG THÁI KẾT NỐI (STATUS)
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

        // 2. TÙY BIẾN SIDE PANEL (UI SCALE & WIDTH)
        const SectionLabel(label: "TÙY BIẾN GIAO DIỆN"),

        // Tỷ lệ phóng đại UI Scale
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: focusedIndex == 0 ? AppTheme.accent : AppTheme.cardBorder,
              width: focusedIndex == 0 ? 1.8 : 1.0,
            ),
            boxShadow: focusedIndex == 0
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.format_size_rounded,
                    size: AppTheme.scaled(16),
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Tỷ lệ hiển thị (UI Scale)",
                      style: AppTheme.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    "${(scale * 100).toInt()}%",
                    style: AppTheme.cardValue,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PresetSelector<double>(
                presets: const [0.8, 1.0, 1.2, 1.4],
                selectedValue: scale,
                labelBuilder: (preset) => "${(preset * 100).toInt()}%",
                onSelected: onScaleChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Độ rộng Side Panel
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: focusedIndex == 1 ? AppTheme.accent : AppTheme.cardBorder,
              width: focusedIndex == 1 ? 1.8 : 1.0,
            ),
            boxShadow: focusedIndex == 1
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.aspect_ratio_rounded,
                    size: AppTheme.scaled(16),
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Độ rộng Side Panel",
                      style: AppTheme.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text("$widthPercent %", style: AppTheme.cardValue),
                ],
              ),
              const SizedBox(height: 8),
              PresetSelector<int>(
                presets: const [30, 35, 40, 45],
                selectedValue: widthPercent,
                labelBuilder: (preset) => "$preset%",
                onSelected: onWidthPercentChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. THÔNG TIN PHẦN MỀM
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Handheld Gaming Tools",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Phiên bản 2.0 (Monochrome Clean Edition)",
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
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
