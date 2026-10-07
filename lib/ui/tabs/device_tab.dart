import 'package:flutter/material.dart';

import '../../hardware/brightness_service.dart';
import '../../hardware/audio_service.dart';
import '../widgets/setting_slider.dart';
import '../widgets/toggle_card.dart';
import '../widgets/section_label.dart';

/// Tab điều khiển Thiết bị: Độ sáng màn hình, Âm lượng loa và Bật/tắt Cảm ứng màn hình.
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
          helpText:
              "Điều chỉnh cường độ sáng màn hình tích hợp. Giảm độ sáng giúp kéo dài đáng kể thời lượng pin.",
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
          helpText:
              "Điều chỉnh mức âm lượng tổng của hệ thống Windows từ 0% đến 100%.",
        ),
        const SizedBox(height: 16),

        const SectionLabel(label: "CẢM ỨNG MÀN HÌNH"),
        ToggleCard(
          icon: touchEnabled
              ? Icons.touch_app_rounded
              : Icons.do_not_touch_rounded,
          title: "Màn hình cảm ứng",
          subtitle: touchEnabled
              ? "Đang Bật (Chạm để tương tác)"
              : "Đã Tắt (Tránh chạm nhầm khi chơi)",
          value: touchEnabled,
          onChanged: (_) => onToggleTouchscreen(),
          isFocused: focusedIndex == 2,
          helpText:
              "Bật hoặc tắt màn hình cảm ứng để tránh chạm nhầm khi đang cầm chơi game bằng tay cầm.",
        ),
      ],
    );
  }
}
