import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'bumper_button.dart';

/// Dữ liệu định nghĩa một tab trong thanh điều hướng Compact Mode.
class AppTabItem {
  final IconData icon;
  final String label;

  const AppTabItem({required this.icon, required this.label});
}

/// Thanh Tab Bar dạng ô vuông co dãn theo UI Scale, hỗ trợ cuộn ngang tự động (Auto-Scroll)
/// và tự động gom cụm dạt về lề phải khi tổng chiều rộng nhỏ hơn bề ngang panel.
class AppTabBar extends StatefulWidget {
  final int selectedIndex;
  final List<AppTabItem> items;
  final ValueChanged<int> onTabSelected;

  const AppTabBar({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onTabSelected,
  });

  @override
  State<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends State<AppTabBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(AppTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final tabSize = AppTheme.scaled(56.0);
    final itemWidth = tabSize + 6.0; // padding 3px mỗi bên
    final targetCenter = widget.selectedIndex * itemWidth + (itemWidth / 2);
    final viewportWidth = _scrollController.position.viewportDimension;
    final targetOffset = (targetCenter - (viewportWidth / 2)).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _prevTab() {
    if (widget.selectedIndex > 0) {
      widget.onTabSelected(widget.selectedIndex - 1);
    }
  }

  void _nextTab() {
    if (widget.selectedIndex < widget.items.length - 1) {
      widget.onTabSelected(widget.selectedIndex + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabSize = AppTheme.scaled(56.0);
    final iconSize = AppTheme.scaled(20.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Nút phím tắt LB (Bumper trái cố định gọn gàng)
          BumperButton(
            type: BumperType.lb,
            width: 38,
            height: 20,
            isEnabled: widget.selectedIndex > 0,
            onTap: _prevTab,
          ),
          const SizedBox(width: 6),

          // Vùng chứa các ô tab vuông: co lại khi ít tab (căn lề phải) và cuộn ngang khi nhiều tab
          Flexible(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.selectedIndex;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => widget.onTabSelected(index),
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: tabSize,
                        height: tabSize,
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
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.icon,
                              size: iconSize,
                              color: isSelected
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          const SizedBox(width: 6),
          // Nút phím tắt RB (Bumper phải cố định gọn gàng)
          BumperButton(
            type: BumperType.rb,
            width: 38,
            height: 20,
            isEnabled: widget.selectedIndex < widget.items.length - 1,
            onTap: _nextTab,
          ),
        ],
      ),
    );
  }
}
