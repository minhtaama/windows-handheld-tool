import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../hardware/rtss_service.dart';
import '../../hardware/rtss_osd_formatter.dart';
import '../../services/rtss_installer_service.dart';
import '../../services/system_telemetry_service.dart';
import '../quick_panel/gamepad_navigable.dart';
import '../widgets/setting_slider.dart';
import '../widgets/section_label.dart';
import '../widgets/toggle_card.dart';
import '../widgets/help_box.dart';
import '../widgets/preset_selector.dart';

/// Tab điều khiển RivaTuner Statistics Server (RTSS): Khóa khung hình (FPS Limiter)
/// và Cấu hình Lớp phủ in-game (In-Game OSD).
class RtssTab extends StatefulWidget {
  final ConfigManager? config;

  const RtssTab({super.key, this.config});

  @override
  State<RtssTab> createState() => RtssTabState();
}

class RtssTabState extends State<RtssTab> with GamepadNavigableMixin<RtssTab> {
  late final RtssFpsController _rtssCtrl;

  late int _fpsLimit;
  int? _liveFps;
  String? _activeGame;

  late bool _osdEnabled;
  late int _osdZoom;
  late RtssOsdPosition _osdPosition;
  late RtssOsdMetricsConfig _osdMetrics;

  bool _isInstallingRtss = false;
  String? _rtssInstallMsg;
  Timer? _telemetryTimer;

  @override
  void initState() {
    super.initState();
    final cfg = widget.config ?? ConfigManager();
    _rtssCtrl = RtssFpsController();

    final savedFps = cfg.get("hardware.rtss.fps_limit", 60);
    _fpsLimit = _rtssCtrl.isAvailable() ? _rtssCtrl.getValue() : savedFps;
    _osdEnabled = cfg.get("hardware.rtss.osd_enabled", true);
    _osdZoom = cfg.get("hardware.rtss.osd_zoom", 2);

    final savedPos = cfg.get("hardware.rtss.osd_position", "topLeft");
    _osdPosition = RtssOsdPosition.values.firstWhere(
      (p) => p.name == savedPos,
      orElse: () => RtssOsdPosition.topLeft,
    );

    _osdMetrics = RtssOsdMetricsConfig.fromConfig(cfg);

    if (_rtssCtrl.isAvailable()) {
      _rtssCtrl.setOsdEnabled(_osdEnabled);
      _rtssCtrl.setOsdZoom(_osdZoom);
      _rtssCtrl.setOsdPosition(_osdPosition);
      if (_osdEnabled) {
        _refreshOsdText();
      }
    }

    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _pollTelemetry();
    });
  }

  void _pollTelemetry() {
    if (!mounted) return;
    setState(() {
      if (_rtssCtrl.isAvailable()) {
        _liveFps = _rtssCtrl.getLiveFps();
        _activeGame = _rtssCtrl.getActiveGame();
        if (_osdEnabled) {
          _refreshOsdText();
        }
      } else {
        _liveFps = null;
        _activeGame = null;
      }
    });
  }

  void _refreshOsdText() {
    if (!_rtssCtrl.isAvailable() || !_osdEnabled) return;
    final telem = SystemTelemetryService.instance.getSnapshot();
    final text = RtssOsdFormatter.format(
      config: _osdMetrics,
      fps: _liveFps,
      liveTdp: telem.liveTdp,
      liveFan: telem.liveFan,
      cpuUsage: telem.cpuUsagePercent.toDouble(),
      ramUsedGb: telem.ramUsedGb,
      batteryPercent: telem.batteryPercent,
    );
    RtssService.instance.updateOsdText(text);
  }

  void _updateFpsLimit(int val) {
    setState(() => _fpsLimit = val);
    _rtssCtrl.setValue(val);
    widget.config?.set("hardware.rtss.fps_limit", val);
  }

  void _toggleOsd(bool val) {
    setState(() => _osdEnabled = val);
    _rtssCtrl.setOsdEnabled(val);
    widget.config?.set("hardware.rtss.osd_enabled", val);
    if (!val) {
      RtssService.instance.clearOsdText();
    } else {
      _refreshOsdText();
    }
  }

  void _updateOsdZoom(int val) {
    setState(() => _osdZoom = val);
    _rtssCtrl.setOsdZoom(val);
    widget.config?.set("hardware.rtss.osd_zoom", val);
  }

  void _updateOsdPosition(RtssOsdPosition pos) {
    setState(() => _osdPosition = pos);
    _rtssCtrl.setOsdPosition(pos);
    widget.config?.set("hardware.rtss.osd_position", pos.name);
  }

  void _updateOsdLayout(RtssOsdLayout layout) {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(layout: layout);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _toggleMetricFps() {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(showFps: !_osdMetrics.showFps);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _toggleMetricTdp() {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(showTdp: !_osdMetrics.showTdp);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _toggleMetricCpuTemp() {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(showCpuTemp: !_osdMetrics.showCpuTemp);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _toggleMetricCpuUsage() {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(showCpuUsage: !_osdMetrics.showCpuUsage);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _toggleMetricRam() {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(showRam: !_osdMetrics.showRam);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _toggleMetricBattery() {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(showBattery: !_osdMetrics.showBattery);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _toggleMetricFan() {
    setState(() {
      _osdMetrics = _osdMetrics.copyWith(showFan: !_osdMetrics.showFan);
    });
    _osdMetrics.saveToConfig(widget.config ?? ConfigManager());
    _refreshOsdText();
  }

  void _handleInstallRtss() {
    setState(() {
      _isInstallingRtss = true;
      _rtssInstallMsg = "Đang kết nối dịch vụ cài đặt...";
    });
    RtssInstallerService.installRtss(
      onStatusUpdate: (status) {
        if (mounted) {
          setState(() => _rtssInstallMsg = status);
        }
      },
    ).then((success) {
      if (!mounted) return;
      setState(() {
        _isInstallingRtss = false;
        _rtssInstallMsg = success ? "Cài đặt hoàn tất!" : "Cài đặt thất bại.";
      });
      if (success) {
        RtssService.instance.ensureRunning();
      }
    });
  }

  @override
  List<List<int>> get navigationLayout => [
        if (!RtssInstallerService.isInstalled())
          const [0]
        else ...[
          const [0], // FPS Limit
          const [1], // OSD Toggle
          if (_osdEnabled) ...[
            const [2], // OSD Zoom
            const [3], // OSD Position
            const [4], // OSD Layout
            const [5, 6], // FPS, TDP
            const [7, 8], // CPU Temp, CPU Usage
            const [9, 10], // RAM, Battery
            const [11], // Fan
          ],
        ],
      ];

  @override
  void onGamepadActionA(int focusedIndex) {
    if (!RtssInstallerService.isInstalled()) {
      if (focusedIndex == 0) _handleInstallRtss();
      return;
    }

    switch (focusedIndex) {
      case 0:
        cyclePreset(const [0, 30, 40, 60], _fpsLimit, 1, _updateFpsLimit);
        break;
      case 1:
        _toggleOsd(!_osdEnabled);
        break;
      case 2:
        cyclePreset(const [1, 2, 3, 4], _osdZoom, 1, _updateOsdZoom);
        break;
      case 3:
        cyclePreset(RtssOsdPosition.values, _osdPosition, 1, _updateOsdPosition);
        break;
      case 4:
        cyclePreset(RtssOsdLayout.values, _osdMetrics.layout, 1, _updateOsdLayout);
        break;
      case 5:
        _toggleMetricFps();
        break;
      case 6:
        _toggleMetricTdp();
        break;
      case 7:
        _toggleMetricCpuTemp();
        break;
      case 8:
        _toggleMetricCpuUsage();
        break;
      case 9:
        _toggleMetricRam();
        break;
      case 10:
        _toggleMetricBattery();
        break;
      case 11:
        _toggleMetricFan();
        break;
    }
  }

  @override
  void onGamepadAdjustSlider(int focusedIndex, int direction) {
    if (RtssInstallerService.isInstalled() && focusedIndex == 0) {
      _updateFpsLimit(
        (_fpsLimit + direction * _rtssCtrl.step)
            .clamp(_rtssCtrl.minVal, _rtssCtrl.maxVal),
      );
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('tab_rtss'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        const SectionLabel(label: "KHÓA KHUNG HÌNH (FPS LIMITER)", isFirst: true),
        if (!RtssInstallerService.isInstalled())
          AnimatedContainer(
            key: getItemKey(0),
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: focusedIndex == 0 ? AppTheme.accent : AppTheme.cardBorder,
                width: focusedIndex == 0 ? 1.8 : 1.0,
              ),
              boxShadow: focusedIndex == 0
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        blurRadius: 14,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
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
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              "Chưa cài đặt RTSS",
                              style: AppTheme.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          HelpBox(
                            helpText: "RTSS (RivaTuner Statistics Server) là dịch vụ giám sát và khóa tốc độ khung hình (FPS). Bấm nút A trên tay cầm để tự động tải và cài đặt nhanh qua Winget.",
                            isFocused: focusedIndex == 0,
                          ),
                        ],
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
                  style: AppTheme.caption.copyWith(fontSize: 11),
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
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
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
                      style: AppTheme.body.copyWith(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isInstallingRtss ? null : _handleInstallRtss,
                  ),
                ),
              ],
            ),
          )
        else ...[
          SettingSlider(
            key: getItemKey(0),
            icon: Icons.timelapse_rounded,
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
            isFocused: focusedIndex == 0,
            helpText: "Khóa tốc độ khung hình tối đa trong game. Đặt mức 30, 40 hoặc 60 FPS giúp ổn định độ mượt (Frame Time) và giảm tải nhiệt độ.",
          ),

          const SectionLabel(label: "LỚP PHỦ MÀN HÌNH (OSD)"),
          ToggleCard(
            key: getItemKey(1),
            icon: Icons.subtitles_rounded,
            title: "Lớp phủ Overlay (OSD)",
            subtitle: _rtssCtrl.isAvailable()
                ? (_osdEnabled
                    ? "Đang hiển thị trên màn hình"
                    : "Đã tắt hiển thị OSD")
                : (_isInstallingRtss
                    ? "Đang cài đặt RTSS..."
                    : "Chưa kết nối RTSS (Gạt để khởi chạy)"),
            value: _osdEnabled && _rtssCtrl.isAvailable(),
            onChanged: _toggleOsd,
            isFocused: focusedIndex == 1,
            helpText: "Hiển thị lớp phủ theo dõi số khung hình FPS và thông số phần cứng trực tiếp trên màn hình trò chơi qua RivaTuner.",
          ),
          if (_osdEnabled) ...[
            const SizedBox(height: 8),
            PresetSelector<int>(
              key: getItemKey(2),
              title: "Kích thước OSD",
              icon: Icons.format_size_rounded,
              currentValueText: "${_osdZoom}x",
              presets: const [1, 2, 3, 4],
              selectedValue: _osdZoom,
              labelBuilder: (preset) => "${preset}x",
              onSelected: _updateOsdZoom,
              isFocused: focusedIndex == 2,
              helpText: "Phóng to hoặc thu nhỏ kích thước chữ của lớp phủ OSD trên màn hình. Mức 2x hoặc 3x phù hợp nhất cho màn hình Handheld 7-8 inch.",
            ),
            const SizedBox(height: 8),
            PresetSelector<RtssOsdPosition>(
              key: getItemKey(3),
              title: "Vị trí hiển thị OSD",
              icon: Icons.fullscreen_rounded,
              currentValueText: _osdPosition.label,
              presets: RtssOsdPosition.values,
              selectedValue: _osdPosition,
              labelBuilder: (preset) => preset.label,
              onSelected: _updateOsdPosition,
              isFocused: focusedIndex == 3,
              helpText: "Chọn 1 trong 4 góc màn hình để neo lớp phủ OSD, tránh che khuất các thành phần HUD hoặc bản đồ nhỏ (Minimap) của game.",
            ),
            const SizedBox(height: 8),
            PresetSelector<RtssOsdLayout>(
              key: getItemKey(4),
              title: "Bố cục OSD",
              icon: Icons.view_comfortable_rounded,
              currentValueText: _osdMetrics.layout.label,
              presets: RtssOsdLayout.values,
              selectedValue: _osdMetrics.layout,
              labelBuilder: (preset) => preset.label,
              onSelected: _updateOsdLayout,
              isFocused: focusedIndex == 4,
              helpText: "Thu gọn (1 dòng) giúp tiết kiệm diện tích trên màn hình Handheld. Chi tiết (Nhiều dòng) hiển thị từng linh kiện trên một dòng riêng.",
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                "THÔNG SỐ OSD",
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontSize: 11,
                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _MetricToggleCard(
                    key: getItemKey(5),
                    icon: Icons.speed_rounded,
                    title: "FPS",
                    value: _osdMetrics.showFps,
                    onTap: _toggleMetricFps,
                    isFocused: focusedIndex == 5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricToggleCard(
                    key: getItemKey(6),
                    icon: Icons.bolt_rounded,
                    title: "TDP (W)",
                    value: _osdMetrics.showTdp,
                    onTap: _toggleMetricTdp,
                    isFocused: focusedIndex == 6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricToggleCard(
                    key: getItemKey(7),
                    icon: Icons.thermostat_rounded,
                    title: "Nhiệt độ CPU",
                    value: _osdMetrics.showCpuTemp,
                    onTap: _toggleMetricCpuTemp,
                    isFocused: focusedIndex == 7,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricToggleCard(
                    key: getItemKey(8),
                    icon: Icons.memory_rounded,
                    title: "Mức tải CPU",
                    value: _osdMetrics.showCpuUsage,
                    onTap: _toggleMetricCpuUsage,
                    isFocused: focusedIndex == 8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricToggleCard(
                    key: getItemKey(9),
                    icon: Icons.storage_rounded,
                    title: "RAM",
                    value: _osdMetrics.showRam,
                    onTap: _toggleMetricRam,
                    isFocused: focusedIndex == 9,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricToggleCard(
                    key: getItemKey(10),
                    icon: Icons.battery_charging_full_rounded,
                    title: "Pin (BAT)",
                    value: _osdMetrics.showBattery,
                    onTap: _toggleMetricBattery,
                    isFocused: focusedIndex == 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MetricToggleCard(
              key: getItemKey(11),
              icon: Icons.mode_fan_off_rounded,
              title: "Tốc độ quạt (FAN)",
              value: _osdMetrics.showFan,
              onTap: _toggleMetricFan,
              isFocused: focusedIndex == 11,
            ),
          ],
        ],
      ],
    );
  }
}

class _MetricToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final VoidCallback onTap;
  final bool isFocused;

  const _MetricToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isFocused ? AppTheme.accent : AppTheme.cardBorder,
          width: isFocused ? 1.8 : 1.0,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: value ? AppTheme.accent : AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTheme.body.copyWith(
                      fontSize: 12,
                      fontWeight: value ? FontWeight.w700 : FontWeight.normal,
                      color: value ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? AppTheme.accent : Colors.transparent,
                    border: Border.all(
                      color: value ? AppTheme.accent : AppTheme.cardBorder,
                      width: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

