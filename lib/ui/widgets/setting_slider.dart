import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Widget thanh trượt điều khiển dùng chung (DRY) cao cấp với thanh đo kép đồng trục (Coaxial Dual-Gauge).
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

  /// Giá trị thực tế tức thời đo được từ phần cứng
  final int? currentValue;

  /// Màu sắc của dải đo thực tế bên trong thanh trượt
  final Color? currentColor;

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
  });

  @override
  Widget build(BuildContext context) {
    final liveColor = currentColor ?? AppTheme.secondaryNeon;

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
          // 1. Dòng tiêu đề và thông số (Gọn gàng, chống tràn pixel tuyệt đối)
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryNeon),
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
              // Nút phụ (ví dụ chip AUTO của Quạt)
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 8),
              ],
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
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ],
              Text('$value $unit', style: AppTheme.cardValue),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Thanh trượt đồng trục cao cấp (Coaxial Track: Live lồng trong Target)
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
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Lớp 1: Rãnh nền của thanh trượt (Background Groove)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Container(
                          height: 6,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),

                      // Lớp 2: Dải đo giá trị thực tế tức thời (Live Telemetry Gauge)
                      if (currentValue != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final ratio = ((currentValue! - min) / (max - min)).clamp(0.0, 1.0);
                              return Container(
                                height: 6,
                                width: constraints.maxWidth * ratio,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  gradient: LinearGradient(
                                    colors: [
                                      liveColor.withValues(alpha: 0.6),
                                      liveColor,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: liveColor.withValues(alpha: 0.5),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                      // Lớp 3: Thanh trượt điều khiển mục tiêu (Target Slider)
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          activeTrackColor: AppTheme.primaryNeon.withValues(alpha: 0.8),
                          inactiveTrackColor: Colors.transparent, // Trong suốt để lộ dải Live phía dưới
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                            elevation: 3,
                          ),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          overlayColor: AppTheme.primaryNeon.withValues(alpha: 0.15),
                        ),
                        child: Slider(
                          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
                          min: min.toDouble(),
                          max: max.toDouble(),
                          divisions: ((max - min) / step).round(),
                          onChanged: (val) => onChanged(val.round()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
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
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: Colors.white70),
        ),
      ),
    );
  }
}
