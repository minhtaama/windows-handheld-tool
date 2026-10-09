import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Thẻ hiển thị trạng thái kết nối phần cứng / dịch vụ hệ thống kèm đèn LED tín hiệu.
class StatusIndicatorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String statusText;
  final bool isActive;
  final Color? activeColor;
  final Color? inactiveColor;

  const StatusIndicatorCard({
    super.key,
    required this.icon,
    required this.title,
    required this.statusText,
    required this.isActive,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final ledColor = isActive
        ? (activeColor ?? AppTheme.active)
        : (inactiveColor ?? AppTheme.inactive);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: Border.all(color: AppTheme.cardBorder, width: 1.0),
      ),
      child: Row(
        children: [
          // Icon dịch vụ
          Container(
            width: AppTheme.scaled(32),
            height: AppTheme.scaled(32),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: AppTheme.scaled(17),
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),

          // Tên & Chi tiết trạng thái
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTheme.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: AppTheme.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Đèn LED phát sáng trạng thái
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ledColor,
              boxShadow: [
                BoxShadow(
                  color: ledColor.withValues(alpha: isActive ? 0.7 : 0.2),
                  blurRadius: isActive ? 6 : 2,
                  spreadRadius: isActive ? 1.5 : 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
