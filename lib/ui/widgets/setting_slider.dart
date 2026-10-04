import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Widget thanh trượt điều khiển dùng chung (DRY) tối ưu cho màn hình cảm ứng Handheld.
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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dòng tiêu đề + giá trị
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryNeon),
              const SizedBox(width: 8),
              Text(title, style: AppTheme.cardTitle),
              const Spacer(),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 8),
              ],
              Text('$value $unit', style: AppTheme.cardValue),
            ],
          ),
          const SizedBox(height: 6),
          // Dòng thanh trượt kèm nút +/- chạm tay
          Row(
            children: [
              // Nút giảm
              _StepButton(
                icon: Icons.remove,
                onPressed: () {
                  final next = (value - step).clamp(min, max);
                  onChanged(next);
                },
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: AppTheme.primaryNeon,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                    overlayColor: AppTheme.primaryNeon.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: ((max - min) / step).round(),
                    onChanged: (val) => onChanged(val.round()),
                  ),
                ),
              ),
              // Nút tăng
              _StepButton(
                icon: Icons.add,
                onPressed: () {
                  final next = (value + step).clamp(min, max);
                  onChanged(next);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _StepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: Colors.white70),
        ),
      ),
    );
  }
}
