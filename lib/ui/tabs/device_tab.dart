import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../hardware/brightness_service.dart';
import '../../hardware/audio_service.dart';
import '../widgets/setting_slider.dart';
import '../widgets/action_button.dart';
import '../widgets/preset_selector.dart';
import '../widgets/section_label.dart';

/// Tab điều khiển Thiết bị: Độ sáng màn hình, Âm lượng loa, Bật/tắt Cảm ứng và Tùy chỉnh độ rộng Panel.
class DeviceTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;

  // Cấu hình Độ sáng
  final int brightness;
  final BrightnessController brightnessCtrl;
  final ValueChanged<int> onBrightnessChanged;

  // Cấu hình Âm lượng
  final int audio;
  final AudioController audioCtrl;
  final ValueChanged<int> onAudioChanged;

  // Cấu hình Màn hình cảm ứng
  final bool touchEnabled;
  final VoidCallback onToggleTouchscreen;

  // Cấu hình Độ rộng Side Panel
  final int widthPercent;
  final ValueChanged<int> onWidthPercentChanged;

  const DeviceTab({
    super.key,
    required this.scrollController,
    required this.focusedIndex,
    required this.brightness,
    required this.brightnessCtrl,
    required this.onBrightnessChanged,
    required this.audio,
    required this.audioCtrl,
    required this.onAudioChanged,
    required this.touchEnabled,
    required this.onToggleTouchscreen,
    required this.widthPercent,
    required this.onWidthPercentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('tab_device'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        const SectionLabel(label: "HIỂN THỊ"),
        SettingSlider(
          icon: Icons.brightness_6_rounded,
          title: "Độ sáng màn hình",
          value: brightness,
          min: brightnessCtrl.minVal,
          max: brightnessCtrl.maxVal,
          step: brightnessCtrl.step,
          unit: brightnessCtrl.unit,
          quickPresets: const [25, 50, 75, 100],
          onChanged: onBrightnessChanged,
          isFocused: focusedIndex == 0,
        ),
        const SizedBox(height: 16),

        const SectionLabel(label: "ÂM THANH"),
        SettingSlider(
          icon: Icons.volume_up_rounded,
          title: "Âm lượng loa",
          value: audio,
          min: audioCtrl.minVal,
          max: audioCtrl.maxVal,
          step: audioCtrl.step,
          unit: audioCtrl.unit,
          quickPresets: const [0, 30, 60, 100],
          onChanged: onAudioChanged,
          isFocused: focusedIndex == 1,
        ),
        const SizedBox(height: 16),

        const SectionLabel(label: "GIAO DIỆN & CẢM ỨNG"),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: touchEnabled
                    ? Icons.touch_app_rounded
                    : Icons.do_not_touch_rounded,
                title: "Cảm ứng",
                subtitle: touchEnabled ? "Đang Bật" : "Đã Tắt",
                onTap: onToggleTouchscreen,
                isFocused: focusedIndex == 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: focusedIndex == 3 ? AppTheme.accent : AppTheme.cardBorder,
              width: focusedIndex == 3 ? 1.8 : 1.0,
            ),
            boxShadow: focusedIndex == 3
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
                    Icons.aspect_ratio_rounded,
                    size: 16,
                    color: AppTheme.accent,
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
      ],
    );
  }
}
