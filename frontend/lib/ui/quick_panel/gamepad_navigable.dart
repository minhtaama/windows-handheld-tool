import 'dart:math';
import 'package:flutter/material.dart';

import '../../input/gamepad_service.dart';

/// Hàm tiện ích quay vòng preset tùy chọn cho các widget cài đặt (FPS, Slider, Layout...)
void cyclePreset<T>(
  List<T> presets,
  T current,
  int direction,
  ValueChanged<T> onSelect,
) {
  final idx = presets.indexOf(current);
  if (idx == -1) {
    onSelect(presets.first);
  } else {
    final nextIdx = (idx + direction + presets.length) % presets.length;
    onSelect(presets[nextIdx]);
  }
}

/// Interface/Contract chung cho phép QuickPanel tương tác với Tab qua Gamepad
abstract class GamepadNavigableTabState {
  void handleGamepadButton(GamepadButton button);
  void resetFocus();
}

/// Mixin quản lý điều hướng 2D Grid bằng Gamepad cho từng Tab nội bộ.
mixin GamepadNavigableMixin<T extends StatefulWidget> on State<T>
    implements GamepadNavigableTabState {
  final ScrollController scrollController = ScrollController();
  final Map<int, GlobalKey> itemKeys = {};
  int focusedIndex = 0;

  GlobalKey getItemKey(int index) =>
      itemKeys.putIfAbsent(index, () => GlobalKey());

  /// Ma trận layout 2D hàng x cột của Tab (ví dụ: [[0], [1], [2, 3]])
  List<List<int>> get navigationLayout;

  /// Xử lý khi bấm phím A vào widget đang focus
  void onGamepadActionA(int focusedIndex);

  /// Xử lý khi bấm phím D-pad Trái (-1) hoặc Phải (+1) để tăng giảm Slider
  void onGamepadAdjustSlider(int focusedIndex, int direction);

  @override
  void resetFocus() {
    if (focusedIndex != 0 && mounted) {
      setState(() => focusedIndex = 0);
      _autoScrollToFocused();
    }
  }

  /// Nhận tín hiệu nút bấm từ QuickPanel chuyển xuống
  @override
  void handleGamepadButton(GamepadButton button) {
    switch (button) {
      case GamepadButton.dpadUp:
        _handleGamepadUp();
        break;
      case GamepadButton.dpadDown:
        _handleGamepadDown();
        break;
      case GamepadButton.dpadLeft:
        _handleGamepadLeft();
        break;
      case GamepadButton.dpadRight:
        _handleGamepadRight();
        break;
      case GamepadButton.a:
        onGamepadActionA(focusedIndex);
        break;
      default:
        break;
    }
  }

  void setFocus(int index) {
    if (focusedIndex == index || !mounted) return;
    setState(() => focusedIndex = index);
    _autoScrollToFocused();
  }

  (int, int) _findGridPosition(List<List<int>> layout, int targetIndex) {
    for (int r = 0; r < layout.length; r++) {
      for (int c = 0; c < layout[r].length; c++) {
        if (layout[r][c] == targetIndex) {
          return (r, c);
        }
      }
    }
    return (0, 0);
  }

  void _handleGamepadUp() {
    final layout = navigationLayout;
    if (layout.isEmpty) return;
    final (r, c) = _findGridPosition(layout, focusedIndex);
    if (r > 0) {
      final prevRow = layout[r - 1];
      final targetCol = min(c, prevRow.length - 1);
      setFocus(prevRow[targetCol]);
    }
  }

  void _handleGamepadDown() {
    final layout = navigationLayout;
    if (layout.isEmpty) return;
    final (r, c) = _findGridPosition(layout, focusedIndex);
    if (r < layout.length - 1) {
      final nextRow = layout[r + 1];
      final targetCol = min(c, nextRow.length - 1);
      setFocus(nextRow[targetCol]);
    }
  }

  void _handleGamepadLeft() {
    final layout = navigationLayout;
    if (layout.isEmpty) return;
    final (r, c) = _findGridPosition(layout, focusedIndex);
    final currentRow = layout[r];
    if (currentRow.length > 1) {
      if (c > 0) {
        setFocus(currentRow[c - 1]);
      }
      return;
    }
    onGamepadAdjustSlider(focusedIndex, -1);
  }

  void _handleGamepadRight() {
    final layout = navigationLayout;
    if (layout.isEmpty) return;
    final (r, c) = _findGridPosition(layout, focusedIndex);
    final currentRow = layout[r];
    if (currentRow.length > 1) {
      if (c < currentRow.length - 1) {
        setFocus(currentRow[c + 1]);
      }
      return;
    }
    onGamepadAdjustSlider(focusedIndex, 1);
  }

  void _autoScrollToFocused() {
    if (!scrollController.hasClients) return;
    if (focusedIndex == 0) {
      scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final key = itemKeys[focusedIndex];
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}

