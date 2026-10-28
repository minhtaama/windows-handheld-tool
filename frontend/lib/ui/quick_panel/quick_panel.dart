import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../input/gamepad_service.dart';
import '../../services/bridge_service.dart';
import '../../services/overlay_controller.dart';
import 'gamepad_navigable.dart';
import 'panel_footer.dart';
import '../tabs/home_tab.dart';
import '../tabs/performance_tab.dart';
import '../tabs/rtss_tab.dart';
import '../tabs/settings_tab.dart';
import '../widgets/tab_bar.dart';

/// Khung điều khiển Quick Panel tích hợp cơ chế Side-Dock Viewport của Windows
/// (Nền trong suốt, không che mờ game) kèm hiệu ứng chuyển động trượt mượt mà.
class OverlayScreen extends StatefulWidget {
  final ConfigManager config;

  const OverlayScreen({super.key, required this.config});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> with WidgetsBindingObserver {
  int _selectedTabIndex = 0;
  late double _scale;

  final _homeTabKey = GlobalKey<HomeTabState>();
  final _performanceTabKey = GlobalKey<PerformanceTabState>();
  final _rtssTabKey = GlobalKey<RtssTabState>();
  final _settingsTabKey = GlobalKey<SettingsTabState>();

  StreamSubscription<GamepadButton>? _gamepadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scale = (widget.config.get("overlay.scale", 1.0) as num).toDouble();
    AppTheme.uiScale = _scale;

    // Lắng nghe sự kiện phím bấm từ tay cầm Gamepad
    _gamepadSub = GamepadService.buttonEvents.listen(_onGamepadButton);
    GamepadService.isConnected.addListener(_onGamepadConnectionChanged);

    // Lắng nghe đồng bộ cấu hình từ Python WebSocket Server
    BridgeService.instance.config.addListener(_onConfigUpdated);
  }

  void _onConfigUpdated() {
    if (!mounted) return;
    setState(() {
      _scale = (widget.config.get("overlay.scale", 1.0) as num).toDouble();
      AppTheme.uiScale = _scale;
    });
  }

  void _switchTab(int index) {
    if (_selectedTabIndex == index) return;
    setState(() => _selectedTabIndex = index);

    // Đưa tiêu điểm về đầu Tab mới khi chuyển Tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getActiveTabState()?.resetFocus();
    });
  }

  GamepadNavigableTabState? _getActiveTabState() {
    switch (_selectedTabIndex) {
      case 0:
        return _homeTabKey.currentState;
      case 1:
        return _performanceTabKey.currentState;
      case 2:
        return _rtssTabKey.currentState;
      case 3:
        return _settingsTabKey.currentState;
      default:
        return null;
    }
  }

  /// Clears the focus ring when the pad disconnects and restores it when a pad
  /// is present again.
  void _onGamepadConnectionChanged() {
    if (!mounted) return;
    _getActiveTabState()?.resetFocus();
  }

  void _onGamepadButton(GamepadButton button) {
    if (!mounted || !OverlayController.instance.isVisible) return;

    switch (button) {
      case GamepadButton.lb:
        _switchTab((_selectedTabIndex - 1 + 4) % 4);
        break;
      case GamepadButton.rb:
        _switchTab((_selectedTabIndex + 1) % 4);
        break;
      case GamepadButton.b:
        OverlayController.instance.hideOverlay();
        break;
      default:
        // Chuyển tiếp D-pad Up/Down/Left/Right và nút A cho Tab hiện tại xử lý độc lập
        _getActiveTabState()?.handleGamepadButton(button);
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BridgeService.instance.config.removeListener(_onConfigUpdated);
    GamepadService.isConnected.removeListener(_onGamepadConnectionChanged);
    _gamepadSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // The display mode changes when a game starts/stops (the DXGI hook lowers it to the
    // render resolution). Rebuild so the panel re-lays out for the new window size instead
    // of staying scaled for the previous resolution until the width slider is touched.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OverlayController.instance,
      builder: (context, _) {
        final isVisible = OverlayController.instance.isVisible;
        if (!isVisible) {
          return const SizedBox.shrink();
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Column(
            children: [
              // 1. Thanh Tab Bar nổi phía trên (Compact Mode với 4 Tab)
              AppTabBar(
                selectedIndex: _selectedTabIndex,
                items: const [
                  AppTabItem(
                    icon: Icons.home_rounded,
                    label: 'Trang chủ',
                    accent: AppTheme.info,
                  ),
                  AppTabItem(
                    icon: Icons.bolt_rounded,
                    label: 'Hiệu năng',
                    accent: AppTheme.tdp,
                  ),
                  AppTabItem(
                    icon: Icons.speed_rounded,
                    label: 'RTSS / OSD',
                    accent: AppTheme.fan,
                  ),
                  AppTabItem(
                    icon: Icons.settings_rounded,
                    label: 'Cài đặt',
                    accent: AppTheme.ramAccent,
                  ),
                ],
                onTabSelected: _switchTab,
              ),
              const SizedBox(height: 6),

              // 2. Nội dung tab phủ kín phần còn lại của cửa sổ Win32.
              // Không còn Padding/card bo góc: nền panel chính là bề mặt cửa sổ.
              Expanded(
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(_scale)),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [...previousChildren, ?currentChild],
                      );
                    },
                    child: _buildSelectedTabContent(),
                  ),
                ),
              ),

              // 3. Footer giữ khoảng hở 20px với taskbar để không bị che.
              PanelFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return HomeTab(key: _homeTabKey);
      case 1:
        return PerformanceTab(key: _performanceTabKey, config: widget.config);
      case 2:
        return RtssTab(key: _rtssTabKey, config: widget.config);
      case 3:
        return SettingsTab(key: _settingsTabKey, config: widget.config);
      default:
        return const SizedBox.shrink();
    }
  }
}
