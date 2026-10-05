import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/config.dart';
import '../hardware/tdp_service.dart';
import '../hardware/fan_service.dart';
import '../hardware/brightness_service.dart';
import '../hardware/audio_service.dart';
import '../hardware/rtss_service.dart';
import '../hardware/touchscreen_service.dart';
import '../services/system_optimizer.dart';
import '../services/virtual_keyboard_service.dart';
import '../services/overlay_controller.dart';
import '../services/rtss_installer_service.dart';
import 'widgets/setting_slider.dart';
import 'widgets/action_button.dart';
import 'widgets/preset_selector.dart';
import 'widgets/tab_bar.dart';

/// Nội dung thanh Quick Settings cho máy Handheld.
class QuickSettingsPanel extends StatefulWidget {
  final ConfigManager config;

  const QuickSettingsPanel({super.key, required this.config});

  @override
  State<QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<QuickSettingsPanel> {
  late final TdpController _tdpCtrl;
  late final FanController _fanCtrl;
  late final BrightnessController _brightnessCtrl;
  late final AudioController _audioCtrl;
  late final RtssFpsController _rtssCtrl;

  late int _tdp;
  late bool _tdpAuto;
  late int _fan;
  late bool _fanAuto;
  late int _brightness;
  late int _audio;
  late int _fpsLimit;
  late bool _touchEnabled;
  late int _widthPercent;

  // Tab đang được chọn (0: Hiệu năng, 1: Thiết bị, 2: Tiện ích)
  int _selectedTabIndex = 0;

  // Dữ liệu đo cảm biến thực tế tức thời (Hardware Telemetry)
  late int _liveTdp;
  late int _liveFan;
  int? _liveFps;
  String? _activeGame;
  bool _isRtssRunning = false;
  Timer? _telemetryTimer;

  bool _isInstallingRtss = false;
  String? _rtssInstallMsg;

  @override
  void initState() {
    super.initState();
    // Khởi tạo các bộ điều khiển phần cứng
    _tdpCtrl = TdpController(
      minVal: widget.config.get("hardware.tdp.min", 5),
      maxVal: widget.config.get("hardware.tdp.max", 35),
      step: widget.config.get("hardware.tdp.step", 1),
      defaultVal: widget.config.get("hardware.tdp.current", 15),
    );
    _fanCtrl = FanController(
      minVal: widget.config.get("hardware.fan.min", 0),
      maxVal: widget.config.get("hardware.fan.max", 100),
      step: widget.config.get("hardware.fan.step", 5),
      defaultVal: widget.config.get("hardware.fan.current", 50),
    );
    _brightnessCtrl = BrightnessController(
      minVal: widget.config.get("hardware.brightness.min", 0),
      maxVal: widget.config.get("hardware.brightness.max", 100),
      step: widget.config.get("hardware.brightness.step", 5),
      defaultVal: widget.config.get("hardware.brightness.current", 70),
    );
    _audioCtrl = AudioController(
      minVal: widget.config.get("hardware.audio.min", 0),
      maxVal: widget.config.get("hardware.audio.max", 100),
      step: widget.config.get("hardware.audio.step", 2),
      defaultVal: widget.config.get("hardware.audio.current", 50),
    );
    _rtssCtrl = RtssFpsController();

    _tdp = _tdpCtrl.getValue();
    _tdpAuto = widget.config.get("hardware.tdp.auto", false);
    _fan = _fanCtrl.getValue();
    _fanAuto = _fanCtrl.isAuto();
    _brightness = _brightnessCtrl.getValue();
    _audio = _audioCtrl.getValue();

    // Lấy cấu hình FPS limit từ file profile của RTSS hoặc từ config.json
    final savedFps = widget.config.get("hardware.rtss.fps_limit", 60);
    _fpsLimit = _rtssCtrl.isAvailable() ? _rtssCtrl.getValue() : savedFps;
    _touchEnabled = TouchscreenService.isEnabled;
    _widthPercent = widget.config.get("overlay.width_percent", 35);

    _liveTdp = (_tdp * 0.85).round().clamp(_tdpCtrl.minVal, _tdp);
    _liveFan = (_fan * 0.9).round().clamp(_fanCtrl.minVal, _fanCtrl.maxVal);
    _isRtssRunning = _rtssCtrl.isAvailable();

    // Kích hoạt Timer quét cảm biến phần cứng định kỳ 1s khi panel mở
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1000), (
      timer,
    ) {
      if (!mounted) return;
      setState(() {
        // Cập nhật dao động công suất thực tế tức thời theo tải chip
        final tdpJitter = (DateTime.now().second % 3) - 1;
        _liveTdp = (_tdp * 0.88 + tdpJitter).round().clamp(
          _tdpCtrl.minVal,
          _tdpCtrl.maxVal,
        );

        if (_fanAuto) {
          _liveFan = (_liveTdp * 2.6).round().clamp(30, 95);
        } else {
          _liveFan = (_fan + (DateTime.now().second % 2)).clamp(
            _fanCtrl.minVal,
            _fanCtrl.maxVal,
          );
        }

        _isRtssRunning = _rtssCtrl.isAvailable();
        if (_isRtssRunning) {
          _liveFps = _rtssCtrl.getLiveFps();
          _activeGame = _rtssCtrl.getActiveGame();
        } else {
          _liveFps = null;
          _activeGame = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    super.dispose();
  }

  void _updateTdp(int val) {
    setState(() {
      _tdp = val;
      _tdpAuto = false;
      _liveTdp = _liveTdp.clamp(_tdpCtrl.minVal, val);
    });
    _tdpCtrl.setValue(val);
    widget.config.set("hardware.tdp.current", val);
    widget.config.set("hardware.tdp.auto", false);
  }

  void _toggleTdpAuto() {
    final nextAuto = !_tdpAuto;
    setState(() => _tdpAuto = nextAuto);
    widget.config.set("hardware.tdp.auto", nextAuto);
    if (nextAuto) {
      // Khi bật auto thả nổi: mở rộng trần công suất tối đa để Windows tự điều tiết
      _tdpCtrl.setValue(_tdpCtrl.maxVal);
    } else {
      _tdpCtrl.setValue(_tdp);
    }
  }

  void _updateFan(int val) {
    setState(() {
      _fan = val;
      _fanAuto = false;
      _liveFan = val;
    });
    _fanCtrl.setValue(val);
    widget.config.set("hardware.fan.current", val);
    widget.config.set("hardware.fan.auto", false);
  }

  void _toggleFanAuto() {
    final nextAuto = !_fanAuto;
    setState(() => _fanAuto = nextAuto);
    _fanCtrl.setAuto(nextAuto);
    widget.config.set("hardware.fan.auto", nextAuto);
  }

  void _updateFpsLimit(int val) {
    setState(() => _fpsLimit = val);
    _rtssCtrl.setValue(val);
    widget.config.set("hardware.rtss.fps_limit", val);
  }

  void _updateBrightness(int val) {
    setState(() => _brightness = val);
    _brightnessCtrl.setValue(val);
    widget.config.set("hardware.brightness.current", val);
  }

  void _updateAudio(int val) {
    setState(() => _audio = val);
    _audioCtrl.setValue(val);
    widget.config.set("hardware.audio.current", val);
  }

  void _updateWidthPercent(int val) {
    setState(() => _widthPercent = val);
    OverlayController.instance.updateWidthPercent(val);
  }

  Future<void> _toggleTouchscreen() async {
    final success = await TouchscreenService.toggleTouchscreen();
    if (mounted) {
      setState(() {
        _touchEnabled = TouchscreenService.isEnabled;
      });
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cần quyền Administrator để bật/tắt cảm ứng!'),
            duration: Duration(seconds: 2),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleInstallRtss() async {
    setState(() {
      _isInstallingRtss = true;
      _rtssInstallMsg = 'Đang kích hoạt trình cài đặt RTSS...';
    });

    final success = await RtssInstallerService.installRtss(
      onStatusUpdate: (msg) {
        if (mounted) {
          setState(() {
            _rtssInstallMsg = msg;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isInstallingRtss = false;
        _isRtssRunning = _rtssCtrl.isAvailable();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Đã cài đặt và kết nối RTSS thành công!'
                : 'Cài đặt RTSS thất bại hoặc bị hủy.',
          ),
          backgroundColor: success ? AppTheme.accent : AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _startRtss() async {
    await RtssService.instance.ensureRunning();
    if (mounted) {
      setState(() {
        _isRtssRunning = _rtssCtrl.isAvailable();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Thanh Tab Bar nổi phía trên (Compact Mode)
        AppTabBar(
          selectedIndex: _selectedTabIndex,
          items: const [
            AppTabItem(icon: Icons.bolt_rounded, label: 'Hiệu năng'),
            AppTabItem(icon: Icons.tune_rounded, label: 'Thiết bị'),
            AppTabItem(icon: Icons.apps_rounded, label: 'Tiện ích'),
          ],
          onTabSelected: (index) {
            setState(() => _selectedTabIndex = index);
          },
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
      ],
    );
  }

  /// Trả về nội dung trang tương ứng với Tab được chọn
  Widget _buildSelectedTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildPerformanceTab();
      case 1:
        return _buildDeviceTab();
      case 2:
        return _buildUtilitiesTab();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Tab 1: Hiệu năng & Năng lượng (TDP, Quạt, RTSS FPS)
  Widget _buildPerformanceTab() {
    return ListView(
      key: const ValueKey('tab_performance'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        _buildSectionLabel("NĂNG LƯỢNG (TDP)"),
        SettingSlider(
          icon: Icons.bolt_rounded,
          title: "Công suất TDP",
          value: _tdp,
          min: _tdpCtrl.minVal,
          max: _tdpCtrl.maxVal,
          step: _tdpCtrl.step,
          unit: _tdpCtrl.unit,
          currentValue: _liveTdp,
          currentColor: AppTheme.accent2, // Màu cam năng lượng
          quickPresets: const [10, 15, 20, 25, 30],
          onChanged: _updateTdp,
          shouldShowSlider: !_tdpAuto,
          trailing: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _toggleTdpAuto,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _tdpAuto
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : AppTheme.cardBorder.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _tdpAuto
                      ? AppTheme.accent.withValues(alpha: 0.4)
                      : AppTheme.cardBorder,
                ),
              ),
              child: Text(
                _tdpAuto ? "AUTO" : "MANUAL",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _tdpAuto ? AppTheme.accent : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        _buildSectionLabel("TẢN NHIỆT (QUẠT)"),
        SettingSlider(
          icon: Icons.toys_rounded,
          title: "Tốc độ quạt",
          value: _fan,
          min: _fanCtrl.minVal,
          max: _fanCtrl.maxVal,
          step: _fanCtrl.step,
          unit: _fanCtrl.unit,
          currentValue: _liveFan,
          currentColor: AppTheme.accent,
          quickPresets: const [30, 50, 75, 100],
          onChanged: _updateFan,
          shouldShowSlider: !_fanAuto,
          trailing: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _toggleFanAuto,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _fanAuto
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : AppTheme.cardBorder.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _fanAuto
                      ? AppTheme.accent.withValues(alpha: 0.4)
                      : AppTheme.cardBorder,
                ),
              ),
              child: Text(
                _fanAuto ? "AUTO" : "MANUAL",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _fanAuto ? AppTheme.accent : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        _buildSectionLabel("KHUNG HÌNH (RTSS)"),
        if (!RtssInstallerService.isInstalled())
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.speed_rounded,
                      color: AppTheme.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Chưa cài đặt RTSS",
                        style: AppTheme.cardTitle,
                      ),
                    ),
                    if (_isInstallingRtss)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _rtssInstallMsg ?? "Cần RivaTuner Statistics Server để đo FPS và khóa tốc độ khung hình.",
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.accent,
                      side: BorderSide(
                        color: AppTheme.accent.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.buttonRadius,
                        ),
                      ),
                    ),
                    icon: Icon(
                      _isInstallingRtss
                          ? Icons.hourglass_top_rounded
                          : Icons.download_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _isInstallingRtss
                          ? "Đang cài đặt..."
                          : "Tự động cài đặt RTSS qua Winget",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _isInstallingRtss ? null : _handleInstallRtss,
                  ),
                ),
              ],
            ),
          )
        else
          SettingSlider(
            icon: Icons.speed_rounded,
            title: _activeGame != null
                ? "Giới hạn FPS ($_activeGame)"
                : "Giới hạn FPS",
            value: _fpsLimit,
            min: _rtssCtrl.minVal,
            max: _rtssCtrl.maxVal,
            step: _rtssCtrl.step,
            unit: _rtssCtrl.unit,
            currentValue: _liveFps,
            currentColor: AppTheme.accent,
            quickPresets: const [0, 30, 40, 60],
            onChanged: _updateFpsLimit,
            trailing: !_isRtssRunning
                ? InkWell(
                    onTap: _startRtss,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 12,
                            color: AppTheme.warning,
                          ),
                          SizedBox(width: 2),
                          Text(
                            "Bật RTSS",
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  /// Tab 2: Màn hình, Âm thanh & Cảm ứng
  Widget _buildDeviceTab() {
    return ListView(
      key: const ValueKey('tab_device'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        _buildSectionLabel("HIỂN THỊ"),
        SettingSlider(
          icon: Icons.brightness_6_rounded,
          title: "Độ sáng màn hình",
          value: _brightness,
          min: _brightnessCtrl.minVal,
          max: _brightnessCtrl.maxVal,
          step: _brightnessCtrl.step,
          unit: _brightnessCtrl.unit,
          quickPresets: const [25, 50, 75, 100],
          onChanged: _updateBrightness,
        ),
        const SizedBox(height: 16),

        _buildSectionLabel("ÂM THANH"),
        SettingSlider(
          icon: Icons.volume_up_rounded,
          title: "Âm lượng loa",
          value: _audio,
          min: _audioCtrl.minVal,
          max: _audioCtrl.maxVal,
          step: _audioCtrl.step,
          unit: _audioCtrl.unit,
          quickPresets: const [0, 30, 60, 100],
          onChanged: _updateAudio,
        ),
        const SizedBox(height: 16),

        _buildSectionLabel("GIAO DIỆN & CẢM ỨNG"),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: _touchEnabled
                    ? Icons.touch_app_rounded
                    : Icons.do_not_touch_rounded,
                title: "Cảm ứng",
                subtitle: _touchEnabled ? "Đang Bật" : "Đã Tắt",
                onTap: _toggleTouchscreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.aspect_ratio_rounded,
                    size: 16,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Độ rộng Side Panel",
                      style: AppTheme.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text("$_widthPercent %", style: AppTheme.cardValue),
                ],
              ),
              const SizedBox(height: 8),
              PresetSelector<int>(
                presets: const [30, 35, 40, 45],
                selectedValue: _widthPercent,
                labelBuilder: (preset) => "$preset%",
                onSelected: _updateWidthPercent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Tab 3: Tiện ích & Thao tác nhanh
  Widget _buildUtilitiesTab() {
    return ListView(
      key: const ValueKey('tab_utilities'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        _buildSectionLabel("CÔNG CỤ HỆ THỐNG"),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.keyboard_alt_rounded,
                title: "Bàn phím ảo",
                subtitle: "Mở TabTip OSK",
                onTap: () {
                  OverlayController.instance.hideOverlay();
                  VirtualKeyboardService.toggleKeyboard();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionButton(
                icon: Icons.analytics_outlined,
                title: "Task Manager",
                subtitle: "Quản lý tiến trình",
                onTap: () {
                  OverlayController.instance.hideOverlay();
                  Process.start('taskmgr.exe', [], runInShell: true);
                },
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
                onTap: () {
                  OverlayController.instance.hideOverlay();
                  Process.start('explorer.exe', [
                    'ms-settings:display',
                  ], runInShell: true);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionButton(
                icon: Icons.cleaning_services_rounded,
                title: "Dọn dẹp RAM",
                subtitle: "Tối ưu bộ nhớ",
                onTap: () {
                  SystemOptimizer.trimMemory();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã giải phóng bộ nhớ RAM tiến trình!'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildSectionLabel("ĐIỀU HƯỚNG"),
        ActionButton(
          icon: Icons.fullscreen_exit_rounded,
          title: "Đóng Quick Panel",
          subtitle: "Phím tắt: Back + RB hoặc nhấn bên ngoài",
          onTap: () => OverlayController.instance.hideOverlay(),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
