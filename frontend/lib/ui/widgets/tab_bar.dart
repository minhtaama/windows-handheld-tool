import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'bumper_button.dart';

/// Data definition of a single tab in the Compact Mode navigation bar.
class AppTabItem {
  final IconData icon;
  final String label;

  /// Per-tab accent hue used by the selected tile rail and glow, so the user
  /// can locate the active section by colour instead of by reading the label.
  final Color accent;

  const AppTabItem({
    required this.icon,
    required this.label,
    required this.accent,
  });
}

/// Tab bar made of square tiles that scale with the UI Scale, with automatic
/// horizontal scrolling and right-aligned collapsing when the tiles are
/// narrower than the panel.
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
  static const Duration _animDuration = Duration(milliseconds: 180);
  static const Curve _animCurve = Curves.easeOutCubic;

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
    final itemWidth = tabSize + 6.0; // 3px padding on each side
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
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      decoration: const BoxDecoration(
        gradient: AppTheme.tabBarGradient,
        border: Border(bottom: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Fixed LB bumper shortcut (previous tab)
          const SizedBox(width: 6),
          BumperButton(
            type: BumperType.lb,
            width: 38,
            height: 20,
            isEnabled: widget.selectedIndex > 0,
            onTap: _prevTab,
          ),
          const SizedBox(width: 6),

          // Tile strip: collapses to the right when there are few tabs and
          // scrolls horizontally when they overflow the available width.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.items.length,
                    (index) => _buildTabTile(
                      index: index,
                      item: widget.items[index],
                      isSelected: index == widget.selectedIndex,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),
          // Fixed RB bumper shortcut (next tab)
          BumperButton(
            type: BumperType.rb,
            width: 38,
            height: 20,
            isEnabled: widget.selectedIndex < widget.items.length - 1,
            onTap: _nextTab,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// Builds one tab tile: an invisible idle slot on the recessed track that
  /// turns into a lifted metal tile with a per-tab accent rail when selected.
  Widget _buildTabTile({
    required int index,
    required AppTabItem item,
    required bool isSelected,
  }) {
    final tabSize = AppTheme.scaledHalf(85.0);
    final iconSize = AppTheme.scaled(30.0);
    final accent = item.accent;
    final foreground = isSelected ? AppTheme.textPrimary : AppTheme.tabIdleIcon;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => widget.onTabSelected(index),
        child: AnimatedContainer(
          duration: _animDuration,
          curve: _animCurve,
          width: tabSize,
          height: tabSize,
          decoration: BoxDecoration(
            // Always a gradient so AnimatedContainer can lerp between the idle
            // (transparent) and selected fills instead of snapping.
            gradient: isSelected
                ? AppTheme.tabSelectedGradient
                : AppTheme.tabIdleGradient,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            // Constant stroke width: only the colour animates, which avoids
            // the sub-pixel border jitter of animating the width itself.
            border: Border.all(
              color: isSelected
                  ? AppTheme.tabSelectedBorder
                  : AppTheme.transparent,
            ),
            // boxShadow: isSelected
            //     ? [
            //         // Depth: the drop shadow must be dark; white glows only
            //         // produce a halo around the tile.
            //         BoxShadow(
            //           color: AppTheme.shadow.withValues(alpha: 0.55),
            //           blurRadius: 10,
            //           offset: const Offset(0, 3),
            //         ),
            //         // // Orientation: faint accent bloom under the active tab.
            //         // BoxShadow(
            //         //   color: accent.withValues(alpha: 0.16),
            //         //   blurRadius: 16,
            //         //   spreadRadius: -2,
            //         // ),
            //       ]
            //     : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    size: iconSize,
                    color: isSelected ? AppTheme.textPrimary : foreground,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    style: AppTheme.caption.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              // Accent rail: a hardware LED strip rather than a colour block.
              Positioned(
                left: 16,
                right: 16,
                bottom: 5,
                child: AnimatedContainer(
                  duration: _animDuration,
                  curve: _animCurve,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: isSelected ? accent : AppTheme.transparent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
