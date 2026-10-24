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

class _OverlayScreenState extends State<OverlayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

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
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
      value: 0.0,
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.06, 0.0),
      end: Offset.zero,
    ).animate(_fadeAnim);

    OverlayController.instance.onAnimateShow = () async {
      await _animController.forward(from: 0.0);
    };

    OverlayController.instance.onAnimateHide = () async {
      await _animController.reverse();
    };

    _scale = (widget.config.get("overlay.scale", 1.0) as num).toDouble();
    AppTheme.uiScale = _scale;

    // Lắng nghe sự kiện phím bấm từ tay cầm Gamepad
    _gamepadSub = GamepadService.buttonEvents.listen(_onGamepadButton);

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
    if (OverlayController.instance.onAnimateShow != null) {
      OverlayController.instance.onAnimateShow = null;
    }
    if (OverlayController.instance.onAnimateHide != null) {
      OverlayController.instance.onAnimateHide = null;
    }
    _animController.dispose();
    BridgeService.instance.config.removeListener(_onConfigUpdated);
    _gamepadSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OverlayController.instance,
      builder: (context, _) {
        final isVisible = OverlayController.instance.isVisible;

        return Scaffold(
          backgroundColor: AppTheme.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                ignoring: !isVisible,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 20,
                        bottom: 20,
                        right: 16,
                        left: 8,
                      ),
                      child: Column(
                        children: [
                          // 1. Thanh Tab Bar nổi phía trên (Compact Mode với 4 Tab)
                          AppTabBar(
                            selectedIndex: _selectedTabIndex,
                            items: const [
                              AppTabItem(icon: Icons.home_rounded, label: 'Trang chủ'),
                              AppTabItem(icon: Icons.bolt_rounded, label: 'Hiệu năng'),
                              AppTabItem(icon: Icons.speed_rounded, label: 'RTSS / OSD'),
                              AppTabItem(icon: Icons.settings_rounded, label: 'Cài đặt'),
                            ],
                            onTabSelected: _switchTab,
                          ),
                          const SizedBox(height: 12),

                          // 2. Khung nội dung chi tiết nổi bên dưới (Fixed bounds cho ListView)
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(AppTheme.panelRadius),
                                border: Border.all(color: AppTheme.cardBorder, width: 1.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.shadow.withValues(alpha: 0.65),
                                    blurRadius: 28,
                                    offset: const Offset(-4, 10),
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: MediaQuery(
                                      data: MediaQuery.of(context).copyWith(
                                        textScaler: TextScaler.linear(_scale),
                                      ),
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
                                  const PanelFooter(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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

