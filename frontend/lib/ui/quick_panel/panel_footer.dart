import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Thanh gợi ý thao tác tay cầm Gamepad phong cách Console dưới đáy Quick Panel
class PanelFooter extends StatelessWidget {
  const PanelFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: AppTheme.cardBorder, width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildHintBadge("X", "Thông tin"),
          const SizedBox(width: 10),
          _buildHintBadge("A", "Chọn"),
          const SizedBox(width: 10),
          _buildHintBadge("B", "Đóng"),
        ],
      ),
    );
  }

  Widget _buildHintBadge(String keyText, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.18),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.4),
              width: 0.8,
            ),
            shape: BoxShape.circle,
          ),
          child: Text(keyText, style: AppTheme.hint),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTheme.hint),
      ],
    );
  }
}
