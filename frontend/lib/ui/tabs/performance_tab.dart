import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../hardware/tdp_service.dart';
import '../../hardware/fan_service.dart';
import '../../services/bridge_service.dart';
import '../../services/system_telemetry_service.dart';
import '../quick_panel/gamepad_navigable.dart';
import '../widgets/setting_slider.dart';
import '../widgets/section_label.dart';
import '../widgets/toggle_card.dart';
import '../widgets/preset_selector.dart';
import '../widgets/fan_curve_graph.dart';

/// Tab điều khiển Hiệu năng & Năng lượng: Quản lý Công suất điện (TDP) và Tốc độ quạt tản nhiệt (Fan & Fan Curves).
class PerformanceTab extends StatefulWidget {
  final ConfigManager? config;

  const PerformanceTab({super.key, this.config});

  @override
  State<PerformanceTab> createState() => PerformanceTabState();
}

class PerformanceTabState extends State<PerformanceTab>
    with GamepadNavigableMixin<PerformanceTab> {
  late final TdpController _tdpCtrl;
  late final FanController _fanCtrl;

  late int _tdp;
  int? _liveTdp;
  late bool _tdpAuto;

  late int _liveFan;
  late bool _fanAuto;
  late String _fanProfile;
  late List<List<int>> _fanCurve;
  int _selectedCurvePoint = 0;
  int? _liveCpuTemp;

  Timer? _telemetryTimer;

  @override
  void initState() {
    super.initState();
    final cfg = widget.config ?? ConfigManager();

    _tdpCtrl = TdpController(
      minVal: cfg.get("hardware.tdp.min", 5),
      maxVal: cfg.get("hardware.tdp.max", 35),
      step: cfg.get("hardware.tdp.step", 1),
      defaultVal: cfg.get("hardware.tdp.current", 15),
    );

    _fanCtrl = FanController(
      minVal: cfg.get("hardware.fan.min", 0),
      maxVal: cfg.get("hardware.fan.max", 100),
      step: cfg.get("hardware.fan.step", 5),
      defaultVal: cfg.get("hardware.fan.current", 50),
    );

    _tdp = _tdpCtrl.getValue();
    _tdpAuto = cfg.get("hardware.tdp.auto", false);
    _liveTdp = _tdpCtrl.getLiveTdp()?.round();

    _fanAuto = _fanCtrl.isAuto();
    _liveFan = _fanCtrl.getValue();
    _fanProfile = _fanCtrl.profile;
    _fanCurve = List<List<int>>.from(_fanCtrl.curve);

    // Lắng nghe thay đổi từ BridgeService
    BridgeService.instance.tdp.addListener(_onBridgeTdpChanged);
    BridgeService.instance.fanSpeed.addListener(_onBridgeFanChanged);
    BridgeService.instance.isFanAuto.addListener(_onBridgeFanAutoChanged);
    BridgeService.instance.fanProfile.addListener(_onBridgeFanProfileChanged);
    BridgeService.instance.fanCurve.addListener(_onBridgeFanCurveChanged);


    // Bắt đầu chu kỳ đọc Telemetry cho Live TDP, Fan và Nhiệt độ CPU
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _pollTelemetry();
    });
  }

  void _onBridgeTdpChanged() {
    if (!mounted) return;
    final val = BridgeService.instance.tdp.value;
    if (_tdp != val) setState(() => _tdp = val);
  }

  void _onBridgeFanChanged() {
    if (!mounted) return;
    final val = BridgeService.instance.fanSpeed.value;
    if (_liveFan != val) setState(() => _liveFan = val);
  }

  void _onBridgeFanAutoChanged() {
    if (!mounted) return;
    final val = BridgeService.instance.isFanAuto.value;
    if (_fanAuto != val) setState(() => _fanAuto = val);
  }

  void _onBridgeFanProfileChanged() {
    if (!mounted) return;
    final val = BridgeService.instance.fanProfile.value;
    if (_fanProfile != val) setState(() => _fanProfile = val);
  }

  void _onBridgeFanCurveChanged() {
    if (!mounted) return;
    final val = BridgeService.instance.fanCurve.value;
    setState(() => _fanCurve = List<List<int>>.from(val));
  }


  void _pollTelemetry() {
    if (!mounted) return;
    final telem = SystemTelemetryService.instance.getSnapshot();
    final hwTdp = _tdpCtrl.getLiveTdp();

    setState(() {
      _liveTdp = hwTdp?.round() ?? telem.liveTdp;
      _liveFan = telem.liveFan;
      _liveCpuTemp = telem.cpuTemp;
    });
  }

  void _updateTdp(int val) {
    setState(() => _tdp = val);
    _tdpCtrl.setValue(val);
    widget.config?.set("hardware.tdp.current", val);
  }

  void _toggleTdpAuto() {
    final next = !_tdpAuto;
    setState(() => _tdpAuto = next);
    widget.config?.set("hardware.tdp.auto", next);
  }

  void _toggleFanAuto() {
    final next = !_fanAuto;
    setState(() => _fanAuto = next);
    _fanCtrl.setAuto(next);
    widget.config?.set("hardware.fan.auto", next);
  }

  void _updateFanProfile(String profile) {
    setState(() => _fanProfile = profile);
    _fanCtrl.setProfile(profile);
  }

  void _updateCustomCurvePoint(int pointIdx, int delta) {
    if (_fanCurve.isEmpty || pointIdx < 0 || pointIdx >= _fanCurve.length) return;
    final updated = List<List<int>>.from(_fanCurve.map((p) => [p[0], p[1]]));
    final newSpeed = (updated[pointIdx][1] + delta).clamp(0, 100);
    updated[pointIdx][1] = newSpeed;
    setState(() => _fanCurve = updated);
    _fanCtrl.setProfile('custom', updated);
  }

  String _getProfileLabel(String p) {
    switch (p) {
      case 'quiet':
        return 'Yên tĩnh';
      case 'balanced':
        return 'Cân bằng';
      case 'cool':
        return 'Mát lạnh';
      case 'custom':
        return 'Tùy chỉnh';
      default:
        return p;
    }
  }

  @override
  List<List<int>> get navigationLayout => [
        const [0],
        if (!_tdpAuto) const [1],
        const [2],
        if (!_fanAuto) ...[
          const [3],
          const [4],
        ],
      ];

  @override
  void onGamepadActionA(int focusedIndex) {
    switch (focusedIndex) {
      case 0:
        _toggleTdpAuto();
        break;
      case 1:
        if (!_tdpAuto) {
          cyclePreset(const [10, 15, 20, 25, 30], _tdp, 1, _updateTdp);
        }
        break;
      case 2:
        _toggleFanAuto();
        break;
      case 3:
        if (!_fanAuto) {
          cyclePreset(const ['quiet', 'balanced', 'cool', 'custom'], _fanProfile, 1, _updateFanProfile);
        }
        break;
      case 4:
        if (!_fanAuto && _fanProfile == 'custom' && _fanCurve.isNotEmpty) {
          setState(() => _selectedCurvePoint = (_selectedCurvePoint + 1) % _fanCurve.length);
        }
        break;
    }
  }

  @override
  void onGamepadAdjustSlider(int focusedIndex, int direction) {
    switch (focusedIndex) {
      case 1:
        if (!_tdpAuto) {
          _updateTdp(
            (_tdp + direction * _tdpCtrl.step).clamp(_tdpCtrl.minVal, _tdpCtrl.maxVal),
          );
        }
        break;
      case 4:
        if (!_fanAuto && _fanProfile == 'custom') {
          _updateCustomCurvePoint(_selectedCurvePoint, direction * 5);
        }
        break;
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    BridgeService.instance.tdp.removeListener(_onBridgeTdpChanged);
    BridgeService.instance.fanSpeed.removeListener(_onBridgeFanChanged);
    BridgeService.instance.isFanAuto.removeListener(_onBridgeFanAutoChanged);
    BridgeService.instance.fanProfile.removeListener(_onBridgeFanProfileChanged);
    BridgeService.instance.fanCurve.removeListener(_onBridgeFanCurveChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('tab_performance'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        const SectionLabel(label: "NĂNG LƯỢNG (TDP)", isFirst: true),
        ToggleCard(
          key: getItemKey(0),
          icon: Icons.bolt_rounded,
          title: "Chế độ TDP tự động",
          subtitle: "Tự điều chỉnh công suất theo tải hệ thống",
          value: _tdpAuto,
          onChanged: (_) => _toggleTdpAuto(),
          isFocused: focusedIndex == 0,
          helpText: "Tự động điều chỉnh mức tiêu thụ điện năng (Watt) của CPU theo thời gian thực để tối ưu thời lượng pin và hiệu năng khi chơi game.",
        ),
        const SizedBox(height: 8),
        SettingSlider(
          key: getItemKey(1),
          icon: Icons.electric_meter_rounded,
          title: "Công suất TDP",
          value: _tdp,
          min: _tdpCtrl.minVal,
          max: _tdpCtrl.maxVal,
          step: _tdpCtrl.step,
          unit: _tdpCtrl.unit,
          currentValue: _liveTdp,
          currentColor: AppTheme.tdp,
          accentColor: AppTheme.tdp,
          quickPresets: _tdpAuto ? null : const [10, 15, 20, 25, 30],
          onChanged: _updateTdp,
          shouldShowSlider: !_tdpAuto,
          isFocused: focusedIndex == 1,
          isWarning: !_tdpCtrl.isAvailable() || _tdpCtrl.isHvciBlocked(),
          warningTooltip: _tdpCtrl.isHvciBlocked()
              ? "Driver WinRing0 bị chặn bởi Windows Memory Integrity (HVCI). Vui lòng tắt HVCI trong Windows Security để đo và điều chỉnh TDP."
              : "Không phát hiện phần cứng điều khiển TDP tương thích.",
          helpText: "Khóa công suất điện tối đa của bộ xử lý (TDP tính bằng Watt). Tăng TDP để có FPS cao hơn, giảm TDP để máy mát hơn và tiết kiệm pin.",
        ),

        const SectionLabel(label: "TẢN NHIỆT (QUẠT)"),
        ToggleCard(
          key: getItemKey(2),
          icon: Icons.toys_rounded,
          title: "Chế độ quạt tự động",
          subtitle: _fanAuto
              ? "Do BIOS / Phần cứng thiết bị tự điều khiển"
              : "Điều khiển theo đường cong nhiệt độ (Fan Curve)",
          value: _fanAuto,
          onChanged: (_) => _toggleFanAuto(),
          isFocused: focusedIndex == 2,
          helpText: "Bật để quạt hoạt động theo mặc định an toàn của BIOS máy. Tắt để chủ động tùy biến đường cong tản nhiệt (Fan Curve).",
        ),
        const SizedBox(height: 8),
        if (!_fanAuto) ...[
          if (_liveCpuTemp == null && _tdpCtrl.isHvciBlocked()) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Memory Integrity (HVCI) đang chặn đọc nhiệt độ phần cứng. Cần tắt HVCI trong Windows Security để đo nhiệt độ và áp dụng Fan Curve.",
                      style: AppTheme.caption.copyWith(color: AppTheme.warning, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          PresetSelector<String>(
            key: getItemKey(3),
            title: "Cấu hình Fan Curve",
            icon: Icons.tune_rounded,
            currentValueText: _getProfileLabel(_fanProfile),
            presets: const ['quiet', 'balanced', 'cool', 'custom'],
            selectedValue: _fanProfile,
            labelBuilder: _getProfileLabel,
            onSelected: _updateFanProfile,
            isFocused: focusedIndex == 3,
            helpText: "Yên tĩnh: Giảm ồn khi chơi nhẹ. Cân bằng: Tối ưu hàng ngày. Mát lạnh: Quạt quay sớm để giữ xung nhịp. Tùy chỉnh: Chỉnh từng mốc.",
          ),
          const SizedBox(height: 8),
          FanCurveGraph(
            key: getItemKey(4),
            points: _fanCurve,
            liveTemp: _liveCpuTemp,
            liveFan: _liveFan,
            isCustom: _fanProfile == 'custom',
            isHvciBlocked: _tdpCtrl.isHvciBlocked(),
            selectedPointIndex: _selectedCurvePoint,
            onSelectPoint: (idx) => setState(() => _selectedCurvePoint = idx),
            isFocused: focusedIndex == 4,
          ),
          if (_fanProfile == 'custom') ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(
                    "Điểm đang chọn: ${_fanCurve.length > _selectedCurvePoint ? '${_fanCurve[_selectedCurvePoint][0]}°C ➔ ${_fanCurve[_selectedCurvePoint][1]}%' : '--'}",
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.fan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "D-Pad: Lên/Xuống chỉnh %",
                    style: AppTheme.hint.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.verified_user_rounded, color: AppTheme.success, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Quạt do BIOS phần cứng tự điều khiển",
                        style: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Bảo đảm an toàn tối đa theo thiết lập mặc định của thiết bị. Tắt chế độ tự động để tùy biến Fan Curve.",
                        style: AppTheme.hint.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
