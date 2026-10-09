import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'help_box.dart';

/// Widget bộ chọn mốc giá trị dùng chung (Preset Selector / Segmented Group).
/// Tuân thủ nguyên tắc DRY & Separation of Concern.
/// Hỗ trợ chia đều 100% diện tích (Responsive) để không bao giờ bị tràn pixel khi resize panel.
/// Có thể sử dụng độc lập (standalone) hoặc bao bọc dưới dạng Thẻ cài đặt có tiêu đề (Card Mode).
class PresetSelector<T> extends StatelessWidget {
  final List<T> presets;
  final T selectedValue;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onSelected;
  final bool fillWidth;
  final double height;
  final double spacing;

  // Thuộc tính tùy chọn khi hiển thị dạng Card
  final String? title;
  final IconData? icon;
  final String? currentValueText;
  final bool isFocused;
  final String? helpText;

  const PresetSelector({
    super.key,
    required this.presets,
    required this.selectedValue,
    required this.labelBuilder,
    required this.onSelected,
    this.fillWidth = true,
    this.height = 36.0,
    this.spacing = 8.0,
    this.title,
    this.icon,
    this.currentValueText,
    this.isFocused = false,
    this.helpText,
  });

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) return const SizedBox.shrink();

    final buttons = presets.map((preset) {
      final isSelected = (preset == selectedValue);
      final label = labelBuilder(preset);

      final button = AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: height,
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.2)
              : AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          border: Border.all(color: AppTheme.cardBorder, width: 1.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            splashColor: AppTheme.primary.withValues(alpha: 0.08),
            highlightColor: AppTheme.primary.withValues(alpha: 0.04),
            onTap: () => onSelected(preset),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  label,
                  style: AppTheme.body.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      );

      if (fillWidth) {
        return Expanded(child: button);
      }
      return button;
    }).toList();

    final rowContent = fillWidth
        ? Row(
            children: [
              for (int i = 0; i < buttons.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                buttons[i],
              ],
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: buttons,
          );

    if (title == null) {
      return rowContent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isFocused ? AppTheme.accent : AppTheme.cardBackground,
          width: isFocused ? 1.8 : 1.0,
        ),
        boxShadow: isFocused
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
              if (icon != null) ...[
                Icon(icon, size: AppTheme.scaled(16), color: AppTheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title!,
                        style: AppTheme.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (helpText != null) ...[
                      const SizedBox(width: 6),
                      HelpBox(helpText: helpText!, isFocused: isFocused),
                    ],
                  ],
                ),
              ),
              if (currentValueText != null)
                Text(
                  currentValueText!,
                  style: AppTheme.title.copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 16),
          rowContent,
        ],
      ),
    );
  }
}
