import 'package:flutter/material.dart';

import '../widgets/action_button.dart';
import '../widgets/section_label.dart';

/// Tab điều khiển Tiện ích: Phím tắt công cụ Windows (OSK, Task Manager, Display, DXGI Hook, RAM Cleaner, Close Panel).
class UtilitiesTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;

  // Trạng thái & Callback DXGI Hook
  final bool dxgiHookEnabled;
  final VoidCallback onToggleDxgiHook;

  // Callbacks công cụ hệ thống
  final VoidCallback onVirtualKeyboard;
  final VoidCallback onTaskManager;
  final VoidCallback onDisplaySettings;
  final VoidCallback onTrimMemory;
  final VoidCallback onClosePanel;

  const UtilitiesTab({
    super.key,
    required this.scrollController,
    required this.focusedIndex,
    required this.dxgiHookEnabled,
    required this.onToggleDxgiHook,
    required this.onVirtualKeyboard,
    required this.onTaskManager,
    required this.onDisplaySettings,
    required this.onTrimMemory,
    required this.onClosePanel,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('tab_utilities'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        const SectionLabel(label: "CÔNG CỤ HỆ THỐNG"),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.keyboard_alt_rounded,
                title: "Bàn phím ảo",
                subtitle: "Mở TabTip OSK",
                isFocused: focusedIndex == 0,
                onTap: onVirtualKeyboard,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionButton(
                icon: Icons.analytics_outlined,
                title: "Task Manager",
                subtitle: "Quản lý tiến trình",
                isFocused: focusedIndex == 1,
                onTap: onTaskManager,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.monitor_rounded,
                title: "Màn hình",
                subtitle: "Đổi độ phân giải",
                isFocused: focusedIndex == 2,
                onTap: onDisplaySettings,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionButton(
                icon: Icons.layers_rounded,
                title: "DXGI Hook",
                subtitle: dxgiHookEnabled
                    ? "Đang Bật (Borderless)"
                    : "Đã Tắt (FSE Gốc)",
                isFocused: focusedIndex == 3,
                onTap: onToggleDxgiHook,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.cleaning_services_rounded,
                title: "Dọn dẹp RAM",
                subtitle: "Tối ưu bộ nhớ",
                isFocused: focusedIndex == 4,
                onTap: onTrimMemory,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionButton(
                icon: Icons.fullscreen_exit_rounded,
                title: "Đóng Panel",
                subtitle: "Phím: B / Back+RB",
                isFocused: focusedIndex == 5,
                onTap: onClosePanel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
