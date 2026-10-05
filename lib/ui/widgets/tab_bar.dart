import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'bumper_button.dart';

/// Dữ liệu định nghĩa một tab trong thanh điều hướng Compact Mode.
class AppTabItem {
  final IconData icon;
  final String label;

  const AppTabItem({required this.icon, required this.label});
}

/// Thanh Tab Bar dạng thẻ lớn (Compact Mode) phong cách Acrylic Dock.
class AppTabBar extends StatelessWidget {
  final int selectedIndex;
  final List<AppTabItem> items;
  final ValueChanged<int> onTabSelected;

  const AppTabBar({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onTabSelected,
  });

  void _prevTab() {
    if (selectedIndex > 0) {
      onTabSelected(selectedIndex - 1);
    }
  }

  void _nextTab() {
    if (selectedIndex < items.length - 1) {
      onTabSelected(selectedIndex + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Nút phím tắt LB (Bumper trái)
          BumperButton(
            type: BumperType.lb,
            isEnabled: selectedIndex > 0,
            onTap: _prevTab,
          ),
          const SizedBox(width: 8),

          // Danh sách các thẻ Tab dạng khối vuông
          Expanded(
            child: Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = index == selectedIndex;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => onTabSelected(index),
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 64,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.tabSelected
                              : AppTheme.tabUnselected,
                          borderRadius: BorderRadius.circular(
                            AppTheme.cardRadius,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.accent.withValues(alpha: 0.8)
                                : AppTheme.cardBorder,
                            width: isSelected ? 1.2 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.icon,
                              size: 22,
                              color: isSelected
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(width: 8),
          // Nút phím tắt RB (Bumper phải)
          BumperButton(
            type: BumperType.rb,
            isEnabled: selectedIndex < items.length - 1,
            onTap: _nextTab,
          ),
        ],
      ),
    );
  }
}
