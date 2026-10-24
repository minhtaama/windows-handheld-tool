import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../hardware/rtss_service.dart';
import '../../hardware/rtss_osd_formatter.dart';
import '../../hardware/rtss_osd_service.dart';
import '../../hardware/rtss_syntax_parser.dart';
import '../../services/rtss_installer_service.dart';
import '../../services/system_telemetry_service.dart';
import '../quick_panel/gamepad_navigable.dart';
import '../widgets/setting_slider.dart';
import '../widgets/section_label.dart';
import '../widgets/toggle_card.dart';
import '../widgets/help_box.dart';
import '../widgets/preset_selector.dart';

/// Tab controlling RivaTuner Statistics Server (RTSS): Frame rate limiter
/// and deeply customizable In-Game Overlay (OSD).
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

  late final TextEditingController _templateTextCtrl;

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
    _templateTextCtrl = TextEditingController(text: _osdMetrics.customTemplate);

    if (_rtssCtrl.isAvailable()) {
      _rtssCtrl.setOsdEnabled(_osdEnabled);
      _rtssCtrl.setOsdZoom(_osdZoom);
      _rtssCtrl.setOsdPosition(_osdPosition);
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
      } else {
        _liveFps = null;
        _activeGame = null;
      }
    });
  }

  void _syncConfig(RtssOsdMetricsConfig updated) {
    setState(() => _osdMetrics = updated);
    RtssOsdService.instance.updateConfig(updated, config: widget.config ?? ConfigManager());
  }

  void _updateFpsLimit(int val) {
    setState(() => _fpsLimit = val);
    _rtssCtrl.setValue(val);
    widget.config?.set("hardware.rtss.fps_limit", val);
  }

  void _toggleOsd(bool val) {
    setState(() => _osdEnabled = val);
    _rtssCtrl.setOsdEnabled(val);
    RtssOsdService.instance.setOsdEnabled(val, config: widget.config ?? ConfigManager());
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

  void _updateOsdMode(RtssOsdMode mode) {
    _syncConfig(_osdMetrics.copyWith(mode: mode));
  }

  void _updateOsdLayout(RtssOsdLayout layout) {
    _syncConfig(_osdMetrics.copyWith(layout: layout));
  }

  void _updatePalette(String paletteName) {
    final basePalette = RtssColorPalettes.all[paletteName] ?? RtssColorPalettes.defaultPalette;
    _syncConfig(_osdMetrics.copyWith(
      paletteName: paletteName,
      colors: Map.from(basePalette),
    ));
  }

  void _insertTokenToTemplate(String token) {
    final text = _templateTextCtrl.text;
    final selection = _templateTextCtrl.selection;
    String newText;
    int newPos;

    if (selection.isValid && selection.start >= 0 && selection.end >= selection.start) {
      newText = text.replaceRange(selection.start, selection.end, token);
      newPos = selection.start + token.length;
    } else {
      newText = text + token;
      newPos = newText.length;
    }

    _templateTextCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newPos),
    );
    _syncConfig(_osdMetrics.copyWith(customTemplate: newText));
  }

  void _resetTemplate() {
    _templateTextCtrl.text = RtssOsdMetricsConfig.defaultTemplate;
    _syncConfig(_osdMetrics.copyWith(customTemplate: RtssOsdMetricsConfig.defaultTemplate));
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
  List<List<int>> get navigationLayout {
    if (!RtssInstallerService.isInstalled()) {
      return const [[0]];
    }

    final rows = <List<int>>[
      const [0], // FPS Limit
      const [1], // OSD Toggle
    ];

    if (_osdEnabled) {
      rows.add(const [2]); // OSD Zoom
      rows.add(const [3]); // OSD Position
      rows.add(const [4]); // OSD Mode (Visual vs Syntax)

      if (_osdMetrics.mode == RtssOsdMode.visual) {
        rows.add(const [5]); // OSD Layout
        rows.add(const [6]); // Palette
        rows.add(const [7, 8]); // FPS, TDP
        rows.add(const [9, 10]); // CPU Temp, CPU Usage
        rows.add(const [11, 12]); // RAM, Battery
        rows.add(const [13, 14]); // Time Left, Fan
      } else {
        // Syntax mode
        rows.add(const [15]); // Reset template button
      }
    }

    return rows;
  }

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
        cyclePreset(RtssOsdMode.values, _osdMetrics.mode, 1, _updateOsdMode);
        break;
      case 5:
        cyclePreset(RtssOsdLayout.values, _osdMetrics.layout, 1, _updateOsdLayout);
        break;
      case 6:
        cyclePreset(RtssColorPalettes.all.keys.toList(), _osdMetrics.paletteName, 1, _updatePalette);
        break;
      case 7:
        _syncConfig(_osdMetrics.copyWith(showFps: !_osdMetrics.showFps));
        break;
      case 8:
        _syncConfig(_osdMetrics.copyWith(showTdp: !_osdMetrics.showTdp));
        break;
      case 9:
        _syncConfig(_osdMetrics.copyWith(showCpuTemp: !_osdMetrics.showCpuTemp));
        break;
      case 10:
        _syncConfig(_osdMetrics.copyWith(showCpuUsage: !_osdMetrics.showCpuUsage));
        break;
      case 11:
        _syncConfig(_osdMetrics.copyWith(showRam: !_osdMetrics.showRam));
        break;
      case 12:
        _syncConfig(_osdMetrics.copyWith(showBattery: !_osdMetrics.showBattery));
        break;
      case 13:
        _syncConfig(_osdMetrics.copyWith(showTimeLeft: !_osdMetrics.showTimeLeft));
        break;
      case 14:
        _syncConfig(_osdMetrics.copyWith(showFan: !_osdMetrics.showFan));
        break;
      case 15:
        _resetTemplate();
        break;
    }
  }

  @override
  void onGamepadAdjustSlider(int focusedIndex, int direction) {
    if (RtssInstallerService.isInstalled() && focusedIndex == 0) {
      _updateFpsLimit(
        (_fpsLimit + direction * _rtssCtrl.step).clamp(_rtssCtrl.minVal, _rtssCtrl.maxVal),
      );
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _templateTextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telem = SystemTelemetryService.instance.getSnapshot();
    final compiledPreviewText = RtssOsdFormatter.format(
      config: _osdMetrics,
      telem: telem,
      fps: _liveFps,
      game: _activeGame,
    );

    return ListView(
      key: const ValueKey('tab_rtss'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        const SectionLabel(label: "KHÓA KHUNG HÌNH (FPS LIMITER)", isFirst: true),
        if (!RtssInstallerService.isInstalled())
          _buildInstallCard()
        else ...[
          SettingSlider(
            key: getItemKey(0),
            icon: Icons.timelapse_rounded,
            title: _activeGame != null ? "Giới hạn FPS ($_activeGame)" : "Giới hạn FPS",
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
            helpText:
                "Khóa tốc độ khung hình tối đa trong game. Đặt mức 30, 40 hoặc 60 FPS giúp ổn định độ mượt (Frame Time) và giảm tải nhiệt độ.",
          ),

          const SectionLabel(label: "LỚP PHỦ MÀN HÌNH (OSD)"),
          ToggleCard(
            key: getItemKey(1),
            icon: Icons.subtitles_rounded,
            title: "Lớp phủ Overlay (OSD)",
            subtitle: _rtssCtrl.isAvailable()
                ? (_osdEnabled ? "Đang hiển thị trên màn hình" : "Đã tắt hiển thị OSD")
                : (_isInstallingRtss
                    ? "Đang cài đặt RTSS..."
                    : "Chưa kết nối RTSS (Gạt để khởi chạy)"),
            value: _osdEnabled && _rtssCtrl.isAvailable(),
            onChanged: _toggleOsd,
            isFocused: focusedIndex == 1,
            helpText:
                "Hiển thị lớp phủ theo dõi số khung hình FPS và thông số phần cứng trực tiếp trên màn hình trò chơi qua RivaTuner.",
          ),

          if (_osdEnabled) ...[
            const SizedBox(height: 10),
            // Live Simulation In-App Preview
            _OsdLivePreviewCard(
              previewText: compiledPreviewText,
              position: _osdPosition,
              zoom: _osdZoom,
            ),
            const SizedBox(height: 10),

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
              helpText:
                  "Phóng to hoặc thu nhỏ kích thước chữ của lớp phủ OSD trên màn hình. Mức 2x hoặc 3x phù hợp nhất cho màn hình Handheld 7-8 inch.",
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
              helpText:
                  "Chọn 1 trong 4 góc màn hình để neo lớp phủ OSD, tránh che khuất các thành phần HUD hoặc bản đồ nhỏ (Minimap) của game.",
            ),
            const SizedBox(height: 8),

            PresetSelector<RtssOsdMode>(
              key: getItemKey(4),
              title: "Chế độ tùy biến OSD",
              icon: Icons.tune_rounded,
              currentValueText: _osdMetrics.mode.label,
              presets: RtssOsdMode.values,
              selectedValue: _osdMetrics.mode,
              labelBuilder: (preset) => preset.label,
              onSelected: _updateOsdMode,
              isFocused: focusedIndex == 4,
              helpText:
                  "Chọn 'Trực quan' để cấu hình nhanh bằng các nút gạt và bảng màu mẫu. Chọn 'Cú pháp' để tự do viết chuỗi hiển thị theo chuẩn Macro Tags RTSS.",
            ),
            const SizedBox(height: 8),

            // Mode 1: Visual Mode
            if (_osdMetrics.mode == RtssOsdMode.visual) ...[
              PresetSelector<RtssOsdLayout>(
                key: getItemKey(5),
                title: "Bố cục OSD",
                icon: Icons.view_comfortable_rounded,
                currentValueText: _osdMetrics.layout.label,
                presets: RtssOsdLayout.values,
                selectedValue: _osdMetrics.layout,
                labelBuilder: (preset) => preset.label,
                onSelected: _updateOsdLayout,
                isFocused: focusedIndex == 5,
                helpText:
                    "Thu gọn (1 dòng) giúp tiết kiệm diện tích trên màn hình Handheld. Chi tiết (Nhiều dòng) hiển thị từng linh kiện trên một dòng riêng.",
              ),
              const SizedBox(height: 8),

              PresetSelector<String>(
                key: getItemKey(6),
                title: "Bảng màu hiển thị",
                icon: Icons.palette_rounded,
                currentValueText: _osdMetrics.paletteName,
                presets: RtssColorPalettes.all.keys.toList(),
                selectedValue: _osdMetrics.paletteName,
                labelBuilder: (preset) => preset,
                onSelected: _updatePalette,
                isFocused: focusedIndex == 6,
                helpText:
                    "Chọn bảng phối màu đồng bộ cho các thông số hiển thị trên OSD (Neon Cyber, Amber Retro, Trắng tối giản...).",
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  "THÔNG SỐ & MỤC HIỂN THỊ",
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
                      key: getItemKey(7),
                      icon: Icons.speed_rounded,
                      title: "FPS",
                      colorDot: _osdMetrics.colors['fps'],
                      value: _osdMetrics.showFps,
                      onTap: () => _syncConfig(_osdMetrics.copyWith(showFps: !_osdMetrics.showFps)),
                      isFocused: focusedIndex == 7,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricToggleCard(
                      key: getItemKey(8),
                      icon: Icons.bolt_rounded,
                      title: "TDP (W)",
                      colorDot: _osdMetrics.colors['tdp'],
                      value: _osdMetrics.showTdp,
                      onTap: () => _syncConfig(_osdMetrics.copyWith(showTdp: !_osdMetrics.showTdp)),
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
                      icon: Icons.thermostat_rounded,
                      title: "Nhiệt độ CPU",
                      colorDot: _osdMetrics.colors['cpu_temp'],
                      value: _osdMetrics.showCpuTemp,
                      onTap: () => _syncConfig(
                        _osdMetrics.copyWith(showCpuTemp: !_osdMetrics.showCpuTemp),
                      ),
                      isFocused: focusedIndex == 9,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricToggleCard(
                      key: getItemKey(10),
                      icon: Icons.memory_rounded,
                      title: "Mức tải CPU",
                      colorDot: _osdMetrics.colors['cpu_usage'],
                      value: _osdMetrics.showCpuUsage,
                      onTap: () => _syncConfig(
                        _osdMetrics.copyWith(showCpuUsage: !_osdMetrics.showCpuUsage),
                      ),
                      isFocused: focusedIndex == 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricToggleCard(
                      key: getItemKey(11),
                      icon: Icons.storage_rounded,
                      title: "RAM",
                      colorDot: _osdMetrics.colors['ram'],
                      value: _osdMetrics.showRam,
                      onTap: () => _syncConfig(_osdMetrics.copyWith(showRam: !_osdMetrics.showRam)),
                      isFocused: focusedIndex == 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricToggleCard(
                      key: getItemKey(12),
                      icon: Icons.battery_charging_full_rounded,
                      title: "Pin (BAT)",
                      colorDot: _osdMetrics.colors['battery'],
                      value: _osdMetrics.showBattery,
                      onTap: () => _syncConfig(
                        _osdMetrics.copyWith(showBattery: !_osdMetrics.showBattery),
                      ),
                      isFocused: focusedIndex == 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricToggleCard(
                      key: getItemKey(13),
                      icon: Icons.hourglass_bottom_rounded,
                      title: "Thời lượng pin",
                      colorDot: _osdMetrics.colors['time_left'],
                      value: _osdMetrics.showTimeLeft,
                      onTap: () => _syncConfig(
                        _osdMetrics.copyWith(showTimeLeft: !_osdMetrics.showTimeLeft),
                      ),
                      isFocused: focusedIndex == 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricToggleCard(
                      key: getItemKey(14),
                      icon: Icons.mode_fan_off_rounded,
                      title: "Quạt (FAN)",
                      colorDot: _osdMetrics.colors['fan'],
                      value: _osdMetrics.showFan,
                      onTap: () => _syncConfig(_osdMetrics.copyWith(showFan: !_osdMetrics.showFan)),
                      isFocused: focusedIndex == 14,
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Mode 2: Syntax Mode
              _buildSyntaxEditorCard(),
            ],
          ],
        ],
      ],
    );
  }

  Widget _buildInstallCard() {
    return AnimatedContainer(
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: AppTheme.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Chưa cài đặt RTSS",
                  style: AppTheme.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isInstallingRtss)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _rtssInstallMsg ??
                "Cần RivaTuner Statistics Server để đo FPS và khóa tốc độ khung hình.",
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
                side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
              ),
              icon: Icon(
                _isInstallingRtss ? Icons.hourglass_top_rounded : Icons.download_rounded,
                size: 16,
              ),
              label: Text(
                _isInstallingRtss ? "Đang cài đặt..." : "Tự động cài đặt RTSS qua Winget",
                style: AppTheme.body.copyWith(fontWeight: FontWeight.bold),
              ),
              onPressed: _isInstallingRtss ? null : _handleInstallRtss,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyntaxEditorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "MẪU CÚ PHÁP (TEMPLATE STRING)",
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: AppTheme.accent,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HelpBox(
                    helpText:
                        "BẢNG TRA CỨU MACRO TOKENS KHẢ DỤNG:\n"
                        "• {fps}: Tốc độ khung hình tức thời (FPS)\n"
                        "• {tdp}: Công suất tiêu thụ CPU (W)\n"
                        "• {cpu_temp}: Nhiệt độ vi xử lý (°C)\n"
                        "• {cpu_usage}: Mức tải phần trăm CPU (%)\n"
                        "• {ram_used} / {ram_total}: RAM đã dùng / Tổng RAM (GB)\n"
                        "• {battery}: Phần trăm pin còn lại (%)\n"
                        "• {time_left}: Thời lượng pin ước tính (1h45m / CHG / AC)\n"
                        "• {fan}: Tốc độ quạt tản nhiệt (%)\n"
                        "• {time}: Giờ đồng hồ hệ thống (HH:mm)\n"
                        "• {game}: Tên game đang kích hoạt\n"
                        "• Thẻ màu động: {cpu_temp_color}, {fps_color}, {bat_color}\n"
                        "• Thẻ RTSS chuẩn: <C=RRGGBB>văn bản<C>, \\n (xuống dòng)",
                    isFocused: false,
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    key: getItemKey(15),
                    borderRadius: BorderRadius.circular(4),
                    onTap: _resetTemplate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 13,
                            color: focusedIndex == 15 ? AppTheme.accent : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "Mặc định",
                            style: AppTheme.caption.copyWith(
                              fontSize: 10,
                              color: focusedIndex == 15 ? AppTheme.accent : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _templateTextCtrl,
            maxLines: 4,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              color: Colors.white,
              height: 1.3,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.35),
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                borderSide: const BorderSide(color: AppTheme.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
              ),
            ),
            onChanged: (val) {
              _syncConfig(_osdMetrics.copyWith(customTemplate: val));
            },
          ),
          const SizedBox(height: 10),
          Text(
            "Chạm nhanh để chèn Token vào vị trí con trỏ:",
            style: AppTheme.caption.copyWith(fontSize: 10, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...RtssSyntaxParser.availableTokens.map((t) {
                return _TokenChip(
                  label: t.token,
                  tooltip: "${t.label} (ví dụ: ${t.example})",
                  onTap: () => _insertTokenToTemplate(t.token),
                );
              }),
              _TokenChip(
                label: "<C=FFFF00>Vàng<C>",
                tooltip: "Chèn thẻ màu Vàng RTSS",
                onTap: () => _insertTokenToTemplate("<C=FFFF00><C>"),
              ),
              _TokenChip(
                label: "<C=00FFFF>Xanh<C>",
                tooltip: "Chèn thẻ màu Cyan RTSS",
                onTap: () => _insertTokenToTemplate("<C=00FFFF><C>"),
              ),
              _TokenChip(
                label: "\\n",
                tooltip: "Chèn ký tự ngắt xuống dòng mới",
                onTap: () => _insertTokenToTemplate("\\n"),
              ),
              _TokenChip(
                label: " | ",
                tooltip: "Chèn thanh ngăn cách",
                onTap: () => _insertTokenToTemplate(" <C=808080>|<C> "),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Token insertion chip button.
class _TokenChip extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _TokenChip({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppTheme.cardBorder.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 10,
                color: AppTheme.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live preview simulating RTSS Overlay in-game with pixel monospace font.
class _OsdLivePreviewCard extends StatelessWidget {
  final String previewText;
  final RtssOsdPosition position;
  final int zoom;

  const _OsdLivePreviewCard({
    required this.previewText,
    required this.position,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    Alignment align;
    switch (position) {
      case RtssOsdPosition.topLeft:
        align = Alignment.topLeft;
        break;
      case RtssOsdPosition.topRight:
        align = Alignment.topRight;
        break;
      case RtssOsdPosition.bottomLeft:
        align = Alignment.bottomLeft;
        break;
      case RtssOsdPosition.bottomRight:
        align = Alignment.bottomRight;
        break;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.remove_red_eye_rounded, size: 13, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(
                  "MÔ PHỎNG IN-GAME (LIVE PREVIEW)",
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    fontSize: 10,
                    color: AppTheme.accent,
                  ),
                ),
                const Spacer(),
                Text(
                  "${position.label} • ${zoom}x",
                  style: AppTheme.caption.copyWith(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: AppTheme.cardBorder.withValues(alpha: 0.4),
          ),
          Container(
            height: 80,
            padding: const EdgeInsets.all(10),
            alignment: align,
            child: _buildRichMarkup(previewText),
          ),
        ],
      ),
    );
  }

  Widget _buildRichMarkup(String text) {
    if (text.isEmpty) {
      return Text(
        "[Trống hoặc chưa có dữ liệu]",
        style: TextStyle(fontFamily: 'Consolas', fontSize: 11, color: Colors.grey[600]),
      );
    }

    final spans = <TextSpan>[];
    final colorRegex = RegExp(r'<C(?:=([0-9A-Fa-f]{6,8}))?>');
    int lastIndex = 0;
    Color currentColor = Colors.white;

    for (final match in colorRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: TextStyle(color: currentColor),
        ));
      }

      final hex = match.group(1);
      if (hex != null && hex.isNotEmpty) {
        final parsedHex = hex.length == 6 ? 'FF$hex' : hex;
        currentColor = Color(int.tryParse(parsedHex, radix: 16) ?? 0xFFFFFFFF);
      } else {
        currentColor = Colors.white;
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: TextStyle(color: currentColor),
      ));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: (10 + (zoom * 1.5)).clamp(10.0, 16.0),
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1)),
            Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1, -1)),
          ],
        ),
        children: spans,
      ),
    );
  }
}

class _MetricToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? colorDot;
  final bool value;
  final VoidCallback onTap;
  final bool isFocused;

  const _MetricToggleCard({
    super.key,
    required this.icon,
    required this.title,
    this.colorDot,
    required this.value,
    required this.onTap,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    Color dotColor = AppTheme.accent;
    if (colorDot != null && colorDot!.length >= 6) {
      final parsed = int.tryParse('FF${colorDot!.substring(colorDot!.length - 6)}', radix: 16);
      if (parsed != null) dotColor = Color(parsed);
    }

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
                  color: value ? dotColor : AppTheme.textSecondary,
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
                    color: value ? dotColor : Colors.transparent,
                    border: Border.all(
                      color: value ? dotColor : AppTheme.cardBorder,
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
