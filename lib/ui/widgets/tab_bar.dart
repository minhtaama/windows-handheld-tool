import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Dữ liệu định nghĩa một tab trong thanh điều hướng Xbox Game Bar Compact Mode.
class AppTabItem {
  final IconData icon;
  final String label;

  const AppTabItem({required this.icon, required this.label});
}

/// Thanh Tab Bar dạng thẻ lớn (Compact Mode) chuẩn phong cách XBOX Gaming Bar.
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
        children: [
          // Nút phím tắt LB (Bumper trái)
          _buildBumperButton(
            label: "LB",
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
                              ? const Color(0xFF2C2C2C)
                              : const Color(0xFF202020),
                          borderRadius: BorderRadius.circular(
                            AppTheme.cardRadius,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.accentGreen
                                : Colors.white.withValues(alpha: 0.08),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.accentGreen.withValues(
                                      alpha: 0.65,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    blurRadius: 28,
                                    offset: const Offset(-4, 10),
                                    spreadRadius: 2,
                                  ),
                                ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.icon,
                              size: 22,
                              color: isSelected
                                  ? AppTheme.accentGreen
                                  : Colors.white60,
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
                                    ? Colors.white
                                    : Colors.white60,
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
          _buildBumperButton(
            label: "RB",
            isEnabled: selectedIndex < items.length - 1,
            onTap: _nextTab,
          ),
        ],
      ),
    );
  }

  Widget _buildBumperButton({
    required String label,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isEnabled
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isEnabled
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isEnabled ? Colors.white : Colors.white24,
          ),
        ),
      ),
    );
  }
}
