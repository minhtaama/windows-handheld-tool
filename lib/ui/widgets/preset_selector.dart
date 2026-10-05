import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Widget bộ chọn mốc giá trị dùng chung (Preset Selector / Segmented Group).
/// Tuân thủ nguyên tắc DRY & Separation of Concern.
/// Hỗ trợ chia đều 100% diện tích (Responsive) để không bao giờ bị tràn pixel khi resize panel.
class PresetSelector<T> extends StatelessWidget {
  final List<T> presets;
  final T selectedValue;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onSelected;
  final bool fillWidth;
  final double height;
  final double spacing;

  const PresetSelector({
    super.key,
    required this.presets,
    required this.selectedValue,
    required this.labelBuilder,
    required this.onSelected,
    this.fillWidth = true,
    this.height = 36.0,
    this.spacing = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) return const SizedBox.shrink();

    final buttons = presets.map((preset) {
      final isSelected = (preset == selectedValue);
      final label = labelBuilder(preset);

      final button = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: () => onSelected(preset),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryNeon.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryNeon
                    : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryNeon.withValues(alpha: 0.25),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppTheme.primaryNeon : AppTheme.textSecondary,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );

      if (fillWidth) {
        return Expanded(child: button);
      }
      return button;
    }).toList();

    if (fillWidth) {
      return Row(
        children: [
          for (int i = 0; i < buttons.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            buttons[i],
          ],
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: buttons,
    );
  }
}
