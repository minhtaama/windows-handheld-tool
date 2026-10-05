import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'preset_selector.dart';

/// Widget thanh trượt điều khiển dùng chung (DRY) chuẩn Handheld Gaming với thanh đo kép đồng trục (Coaxial Dual-Gauge).
class SettingSlider extends StatelessWidget {
  final IconData icon;
  final String title;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final ValueChanged<int> onChanged;
  final Widget? trailing;

  /// Giá trị thực tế tức thời đo được từ phần cứng (Live Telemetry)
  final int? currentValue;

  /// Màu sắc của dải đo thực tế bên trong thanh trượt
  final Color? currentColor;

  /// Danh sách mốc chọn nhanh tùy chọn (ví dụ: [0, 30, 40, 60] cho FPS)
  final List<int>? quickPresets;

  /// Boolean ẩn thanh slider, ví dụ khi quạt chạy auto thì không hiện.
  final bool shouldShowSlider;

  const SettingSlider({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.trailing,
    this.currentValue,
    this.currentColor,
    this.quickPresets,
    this.shouldShowSlider = true,
  });

  String _formatTargetValue(int val) {
    if (unit.toUpperCase() == 'FPS' && val == 0) {
      return 'TẮT';
    }
    return '$val $unit';
  }

  @override
  Widget build(BuildContext context) {
    final liveColor = currentColor ?? AppTheme.secondary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Dòng tiêu đề và thông số (Gọn gàng, tinh tế, chống tràn pixel tuyệt đối)
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              // Tiêu đề tự co giãn linh hoạt
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // Widget bổ trợ nếu có (ví dụ nút AUTO/MANUAL)
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              // Thông số hiển thị: nếu có giá trị thực tế thì hiển thị "Live / Target"
              if (currentValue != null) ...[
                Text(
                  '$currentValue',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: liveColor,
                  ),
                ),
                Text(
                  ' / ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
              ],
              Text(_formatTargetValue(value), style: AppTheme.cardValue),
            ],
          ),
          const SizedBox(height: 8),

          // 2. Thanh trượt tràn viền (Full-Width Coaxial Dual-Gauge)
          SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Lớp 1: Rãnh nền của thanh trượt (Background Groove)
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBorder.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),

                // Lớp 2: Thanh giá trị mục tiêu màu xanh (Target Track)
                if (shouldShowSlider)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final targetRatio = max == min
                          ? 0.0
                          : ((value - min) / (max - min)).clamp(0.0, 1.0);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 60),
                        height: 5,
                        width: constraints.maxWidth * targetRatio,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: AppTheme.primary.withValues(alpha: 0.85),
                        ),
                      );
                    },
                  ),

                // Lớp 3: Dải đo giá trị thực tế tức thời chạy ngầm (Live Telemetry nằm trên thanh xanh)
                if (currentValue != null)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final ratio = max == min
                          ? 0.01
                          : ((currentValue! - min) / (max - min)).clamp(
                              0.01,
                              1.0,
                            );
                      return AnimatedContainer(
                        duration: Durations.short4,
                        height: 9,
                        width: constraints.maxWidth * (ratio - 0.02),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: liveColor,
                          boxShadow: [
                            BoxShadow(
                              color: liveColor.withValues(alpha: 0.6),
                              blurRadius: 15,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                // Lớp 4: Con chạy điều khiển (Slider Thumb nổi trên cùng, track trong suốt)
                if (shouldShowSlider)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5,
                      padding: EdgeInsets.zero,
                      activeTrackColor: AppTheme.transparent,
                      inactiveTrackColor: AppTheme.transparent,
                      thumbColor: AppTheme.textPrimary,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                        elevation: 2,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      overlayColor: AppTheme.primary.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: value.toDouble().clamp(
                        min.toDouble(),
                        max.toDouble(),
                      ),
                      min: min.toDouble(),
                      max: max.toDouble(),
                      divisions: max > min ? ((max - min) / step).round() : 1,
                      onChanged: (val) => onChanged(val.round()),
                    ),
                  ),
              ],
            ),
          ),

          // 3. Dãy mốc lựa chọn nhanh (Presets) nếu có
          if (quickPresets != null && quickPresets!.isNotEmpty) ...[
            const SizedBox(height: 8),
            PresetSelector<int>(
              presets: quickPresets!,
              selectedValue: value,
              height: 28.0,
              spacing: 6.0,
              labelBuilder: (preset) =>
                  (unit.toUpperCase() == 'FPS' && preset == 0)
                  ? 'TẮT'
                  : '$preset',
              onSelected: onChanged,
            ),
          ],
        ],
      ),
    );
  }
}
