import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../hardware/tdp_service.dart';
import '../../hardware/fan_service.dart';
import '../../hardware/rtss_service.dart';
import '../../services/rtss_installer_service.dart';
import '../widgets/setting_slider.dart';
import '../widgets/section_label.dart';
import '../widgets/toggle_card.dart';
import '../widgets/help_box.dart';

/// Tab điều khiển Hiệu năng & Năng lượng: Quản lý TDP, Tốc độ quạt và Khóa khung hình RTSS.
class PerformanceTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;

  // Cấu hình & Dữ liệu đo TDP
  final int tdp;
  final int liveTdp;
  final bool tdpAuto;
  final TdpController tdpCtrl;
  final ValueChanged<int> onTdpChanged;
  final VoidCallback onToggleTdpAuto;

  // Cấu hình & Dữ liệu đo Quạt
  final int fan;
  final int liveFan;
  final bool fanAuto;
  final FanController fanCtrl;
  final ValueChanged<int> onFanChanged;
  final VoidCallback onToggleFanAuto;

  // Cấu hình & Dữ liệu đo RTSS
  final int fpsLimit;
  final int? liveFps;
  final String? activeGame;
  final bool isRtssRunning;
  final RtssFpsController rtssCtrl;
  final ValueChanged<int> onFpsLimitChanged;
  final VoidCallback onStartRtss;
  final bool isInstallingRtss;
  final String? rtssInstallMsg;
  final VoidCallback onInstallRtss;

  const PerformanceTab({
    super.key,
    required this.scrollController,
    required this.focusedIndex,
    required this.tdp,
    required this.liveTdp,
    required this.tdpAuto,
    required this.tdpCtrl,
    required this.onTdpChanged,
    required this.onToggleTdpAuto,
    required this.fan,
    required this.liveFan,
    required this.fanAuto,
    required this.fanCtrl,
    required this.onFanChanged,
    required this.onToggleFanAuto,
    required this.fpsLimit,
    required this.liveFps,
    required this.activeGame,
    required this.isRtssRunning,
    required this.rtssCtrl,
    required this.onFpsLimitChanged,
    required this.onStartRtss,
    required this.isInstallingRtss,
    required this.rtssInstallMsg,
    required this.onInstallRtss,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('tab_performance'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        const SectionLabel(label: "NĂNG LƯỢNG (TDP)"),
        ToggleCard(
          icon: Icons.bolt_rounded,
          title: "Chế độ TDP tự động",
          subtitle: "Tự điều chỉnh công suất theo tải hệ thống",
          value: tdpAuto,
          onChanged: (_) => onToggleTdpAuto(),
          isFocused: focusedIndex == 0,
          helpText:
              "Tự động điều chỉnh mức tiêu thụ điện năng (Watt) của CPU theo thời gian thực để tối ưu thời lượng pin và hiệu năng khi chơi game.",
        ),
        const SizedBox(height: 8),
        SettingSlider(
          icon: Icons.electric_meter_rounded,
          title: "Công suất TDP",
          value: tdp,
          min: tdpCtrl.minVal,
          max: tdpCtrl.maxVal,
          step: tdpCtrl.step,
          unit: tdpCtrl.unit,
          currentValue: liveTdp,
          currentColor: AppTheme.tdp,
          accentColor: AppTheme.tdp,
          quickPresets: const [10, 15, 20, 25, 30],
          onChanged: onTdpChanged,
          shouldShowSlider: !tdpAuto,
          isFocused: focusedIndex == 1,
          helpText:
              "Khóa công suất điện tối đa của bộ xử lý (TDP tính bằng Watt). Tăng TDP để có FPS cao hơn, giảm TDP để máy mát hơn và tiết kiệm pin.",
        ),
        const SizedBox(height: 16),

        const SectionLabel(label: "TẢN NHIỆT (QUẠT)"),
        ToggleCard(
          icon: Icons.toys_rounded,
          title: "Chế độ quạt tự động",
          subtitle: "Hệ thống tự điều tốc theo nhiệt độ chip",
          value: fanAuto,
          onChanged: (_) => onToggleFanAuto(),
          isFocused: focusedIndex == 2,
          helpText:
              "Tự động điều chỉnh vòng quay quạt tản nhiệt dựa theo nhiệt độ linh kiện. Chuyển sang MANUAL nếu muốn tự khóa % quạt cố định.",
        ),
        const SizedBox(height: 8),
        SettingSlider(
          icon: Icons.mode_fan_off_rounded,
          title: "Tốc độ quạt",
          value: fan,
          min: fanCtrl.minVal,
          max: fanCtrl.maxVal,
          step: fanCtrl.step,
          unit: fanCtrl.unit,
          currentValue: liveFan,
          currentColor: AppTheme.fan,
          accentColor: AppTheme.fan,
          quickPresets: const [30, 50, 75, 100],
          onChanged: onFanChanged,
          shouldShowSlider: !fanAuto,
          isFocused: focusedIndex == 3,
          helpText:
              "Điều chỉnh phần trăm tốc độ quạt làm mát của máy Handheld từ 0% đến 100%.",
        ),
        const SizedBox(height: 16),

        const SectionLabel(label: "KHUNG HÌNH (RTSS)"),
        if (!RtssInstallerService.isInstalled())
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: focusedIndex == 4 ? AppTheme.accent : AppTheme.cardBorder,
                width: focusedIndex == 4 ? 1.8 : 1.0,
              ),
              boxShadow: focusedIndex == 4
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
                    const Icon(
                      Icons.speed_rounded,
                      color: AppTheme.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              "Chưa cài đặt RTSS",
                              style: AppTheme.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          HelpBox(
                            helpText:
                                "RTSS (RivaTuner Statistics Server) là dịch vụ giám sát và khóa tốc độ khung hình (FPS). Bấm nút A trên tay cầm để tự động tải và cài đặt nhanh qua Winget.",
                            isFocused: focusedIndex == 4,
                          ),
                        ],
                      ),
                    ),
                    if (isInstallingRtss)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  rtssInstallMsg ??
                      "Cần RivaTuner Statistics Server để đo FPS và khóa tốc độ khung hình.",
                  style: AppTheme.caption.copyWith(
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.accent,
                      side: BorderSide(
                        color: AppTheme.accent.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.buttonRadius,
                        ),
                      ),
                    ),
                    icon: Icon(
                      isInstallingRtss
                          ? Icons.hourglass_top_rounded
                          : Icons.download_rounded,
                      size: 16,
                    ),
                    label: Text(
                      isInstallingRtss
                          ? "Đang cài đặt..."
                          : "Tự động cài đặt RTSS qua Winget",
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: isInstallingRtss ? null : onInstallRtss,
                  ),
                ),
              ],
            ),
          )
        else ...[
          ToggleCard(
            icon: Icons.speed_rounded,
            title: "Dịch vụ RivaTuner (RTSS)",
            subtitle: isRtssRunning ? "RTSS đang chạy nền" : "RTSS chưa khởi chạy",
            value: isRtssRunning,
            onChanged: (val) {
              if (!isRtssRunning) onStartRtss();
            },
            isFocused: focusedIndex == 4,
            helpText:
                "Bật dịch vụ nền RivaTuner Statistics Server để theo dõi số khung hình FPS và giới hạn tốc độ làm tươi màn hình.",
          ),
          const SizedBox(height: 8),
          SettingSlider(
            icon: Icons.timelapse_rounded,
            title: activeGame != null
                ? "Giới hạn FPS ($activeGame)"
                : "Giới hạn FPS",
            value: fpsLimit,
            min: rtssCtrl.minVal,
            max: rtssCtrl.maxVal,
            step: rtssCtrl.step,
            unit: rtssCtrl.unit,
            currentValue: liveFps,
            currentColor: AppTheme.accent,
            quickPresets: const [0, 30, 40, 60],
            onChanged: onFpsLimitChanged,
            isFocused: focusedIndex == 5,
            helpText:
                "Khóa tốc độ khung hình tối đa trong game. Đặt mức 30, 40 hoặc 60 FPS giúp ổn định độ mượt (Frame Time) và giảm tải nhiệt độ.",
          ),
        ],
      ],
    );
  }
}
