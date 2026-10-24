import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../hardware/device_info_service.dart';
import '../../hardware/brightness_service.dart';
import '../../hardware/audio_service.dart';
import '../../hardware/touchscreen_service.dart';
import '../../services/bridge_service.dart';
import '../../services/system_telemetry_service.dart';
import '../quick_panel/gamepad_navigable.dart';
import '../widgets/section_label.dart';
import '../widgets/setting_slider.dart';
import '../widgets/toggle_card.dart';

/// Tab Trang chủ (Homepage): Hiển thị đồng hồ, điều khiển nhanh (Độ sáng, Âm thanh, Cảm ứng),
/// trạng thái Pin & Nguồn điện, và chỉ số phần cứng (CPU, GPU, RAM, TDP).
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> with GamepadNavigableMixin<HomeTab> {
  late SystemTelemetryData _telemetry;
  int? _liveTdp;
  Timer? _refreshTimer;

  late final BrightnessController _brightnessCtrl;
  late final AudioController _audioCtrl;

  late int _brightness;
  late int _audio;
  late bool _touchEnabled;

  @override
  void initState() {
    super.initState();
    _telemetry = SystemTelemetryService.instance.getSnapshot();
    _liveTdp = _telemetry.liveTdp;

    _brightnessCtrl = BrightnessController();
    _audioCtrl = AudioController();

    _brightness = _brightnessCtrl.getValue();
    _audio = _audioCtrl.getValue();
    _touchEnabled = TouchscreenService.isEnabled;

    // Lắng nghe đồng bộ từ Windows qua BridgeService
    BridgeService.instance.brightness.addListener(_onBrightnessChangedFromWindows);
    BridgeService.instance.volume.addListener(_onAudioChangedFromWindows);
    BridgeService.instance.isTouchEnabled.addListener(_onTouchChangedFromBridge);

    _refreshTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!mounted) return;
      setState(() {
        _telemetry = SystemTelemetryService.instance.getSnapshot();
        _liveTdp = _telemetry.liveTdp;
      });
    });
  }

  void _onBrightnessChangedFromWindows() {
    if (!mounted) return;
    final val = BridgeService.instance.brightness.value;
    if (_brightness != val) {
      setState(() => _brightness = val);
    }
  }

  void _onAudioChangedFromWindows() {
    if (!mounted) return;
    final val = BridgeService.instance.volume.value;
    if (_audio != val) {
      setState(() => _audio = val);
    }
  }

  void _onTouchChangedFromBridge() {
    if (!mounted) return;
    final val = BridgeService.instance.isTouchEnabled.value;
    if (_touchEnabled != val) {
      setState(() => _touchEnabled = val);
    }
  }

  void _updateBrightness(int val) {
    setState(() => _brightness = val);
    _brightnessCtrl.setValue(val);
  }

  void _updateAudio(int val) {
    setState(() => _audio = val);
    _audioCtrl.setValue(val);
  }

  void _toggleTouchscreen() async {
    await TouchscreenService.toggleTouchscreen();
    if (mounted) {
      setState(() => _touchEnabled = TouchscreenService.isEnabled);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    BridgeService.instance.brightness.removeListener(_onBrightnessChangedFromWindows);
    BridgeService.instance.volume.removeListener(_onAudioChangedFromWindows);
    BridgeService.instance.isTouchEnabled.removeListener(_onTouchChangedFromBridge);
    super.dispose();
  }

  @override
  List<List<int>> get navigationLayout => const [
        [0],
        [1],
        [2],
        [3],
        [4],
        [5, 6],
      ];

  @override
  void onGamepadActionA(int focusedIndex) {
    switch (focusedIndex) {
      case 1:
        cyclePreset(const [25, 50, 75, 100], _brightness, 1, _updateBrightness);
        break;
      case 2:
        cyclePreset(const [0, 30, 60, 100], _audio, 1, _updateAudio);
        break;
      case 3:
        _toggleTouchscreen();
        break;
    }
  }

  @override
  void onGamepadAdjustSlider(int focusedIndex, int direction) {
    switch (focusedIndex) {
      case 1:
        _updateBrightness(
          (_brightness + direction * _brightnessCtrl.step)
              .clamp(_brightnessCtrl.minVal, _brightnessCtrl.maxVal),
        );
        break;
      case 2:
        _updateAudio(
          (_audio + direction * _audioCtrl.step)
              .clamp(_audioCtrl.minVal, _audioCtrl.maxVal),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('tab_homepage'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // 1. Khối Đồng hồ hệ thống & Thiết bị Handheld
        _buildClockHeader(),

        // 2. Khối Điều khiển nhanh (Độ sáng, Âm lượng, Cảm ứng)
        const SectionLabel(label: "ĐIỀU KHIỂN NHANH"),
        SettingSlider(
          key: getItemKey(1),
          icon: Icons.brightness_6_rounded,
          title: "Độ sáng màn hình",
          value: _brightness,
          min: _brightnessCtrl.minVal,
          max: _brightnessCtrl.maxVal,
          step: _brightnessCtrl.step,
          unit: _brightnessCtrl.unit,
          quickPresets: const [25, 50, 75, 100],
          onChanged: _updateBrightness,
          isFocused: focusedIndex == 1,
        ),
        const SizedBox(height: 8),
        SettingSlider(
          key: getItemKey(2),
          icon: Icons.volume_up_rounded,
          title: "Âm lượng loa",
          value: _audio,
          min: _audioCtrl.minVal,
          max: _audioCtrl.maxVal,
          step: _audioCtrl.step,
          unit: _audioCtrl.unit,
          quickPresets: const [0, 30, 60, 100],
          onChanged: _updateAudio,
          isFocused: focusedIndex == 2,
        ),
        const SizedBox(height: 8),
        ToggleCard(
          key: getItemKey(3),
          icon: _touchEnabled
              ? Icons.touch_app_rounded
              : Icons.do_not_touch_rounded,
          title: "Màn hình cảm ứng",
          subtitle: _touchEnabled
              ? "Đang Bật (Chạm để tương tác)"
              : "Đã Tắt (Tránh chạm nhầm khi chơi)",
          value: _touchEnabled,
          onChanged: (_) => _toggleTouchscreen(),
          isFocused: focusedIndex == 3,
          helpText: "Bật hoặc tắt màn hình cảm ứng để tránh chạm nhầm.",
        ),

        // 3. Khối Trạng thái Pin & Nguồn điện
        const SectionLabel(label: "NGUỒN & PIN"),
        _buildBatteryCard(),

        // 4. Khối Tài nguyên Phần cứng
        const SectionLabel(label: "TÀI NGUYÊN HỆ THỐNG"),
        _buildHardwareGrid(),
      ],
    );
  }

  /// Khối hiển thị Đồng hồ lớn chuẩn theo định dạng Windows và Tên thiết bị
  Widget _buildClockHeader() {
    final device = DeviceInfoService.currentDevice;

    return Container(
      key: getItemKey(0),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: focusedIndex == 0 ? AppTheme.primary : AppTheme.cardBorder,
          width: focusedIndex == 0 ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _telemetry.timeString,
                  style: TextStyle(
                    fontSize: AppTheme.scaled(28),
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: AppTheme.scaled(13),
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _telemetry.dateString,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  device.isHandheld
                      ? Icons.videogame_asset_rounded
                      : Icons.computer_rounded,
                  size: AppTheme.scaled(23),
                  color: AppTheme.accent,
                ),
                const SizedBox(height: 6),
                Text(
                  device.displayName,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppTheme.scaled(11),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thẻ trạng thái Pin & Tình trạng sạc
  Widget _buildBatteryCard() {
    final bool hasBattery = _telemetry.hasBattery;
    final int percent = _telemetry.batteryPercent ?? 100;
    final bool isCharging = _telemetry.isCharging;
    final bool isAcOnline = _telemetry.isAcOnline;

    IconData batteryIcon;
    Color statusColor;
    String statusDesc;

    if (!hasBattery) {
      batteryIcon = Icons.power_rounded;
      statusColor = AppTheme.info;
      statusDesc = isAcOnline
          ? "Nguồn AC trực tiếp (Không pin)"
          : "Không phát hiện pin";
    } else if (isCharging) {
      batteryIcon = Icons.battery_charging_full_rounded;
      statusColor = AppTheme.success;
      statusDesc = percent >= 100 ? "Đã sạc đầy (Nguồn AC)" : "Đang sạc nguồn AC";
    } else {
      if (percent > 80) {
        batteryIcon = Icons.battery_full_rounded;
        statusColor = AppTheme.success;
      } else if (percent > 40) {
        batteryIcon = Icons.battery_5_bar_rounded;
        statusColor = AppTheme.info;
      } else if (percent > 20) {
        batteryIcon = Icons.battery_3_bar_rounded;
        statusColor = AppTheme.warning;
      } else {
        batteryIcon = Icons.battery_alert_rounded;
        statusColor = AppTheme.danger;
      }
      statusDesc = "Đang dùng pin thiết bị";
    }

    return Container(
      key: getItemKey(4),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: focusedIndex == 4 ? AppTheme.primary : AppTheme.cardBorder,
          width: focusedIndex == 4 ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppTheme.scaled(36),
                height: AppTheme.scaled(36),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Icon(
                  batteryIcon,
                  color: statusColor,
                  size: AppTheme.scaled(20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          hasBattery ? "$percent%" : "N/A",
                          style: TextStyle(
                            fontSize: AppTheme.scaled(18),
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (isCharging) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  size: AppTheme.scaled(11),
                                  color: AppTheme.success,
                                ),
                                Text(
                                  "SẠC",
                                  style: TextStyle(
                                    fontSize: AppTheme.scaled(9),
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusDesc,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.scaled(11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasBattery) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100.0,
                minHeight: 5,
                backgroundColor: AppTheme.secondary.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Khối hiển thị các chỉ số phần cứng (CPU, GPU, RAM)
  Widget _buildHardwareGrid() {
    final cpuColor = _telemetry.cpuUsagePercent > 85
        ? AppTheme.danger
        : (_telemetry.cpuUsagePercent > 50
            ? AppTheme.warning
            : AppTheme.cpuAccent);

    final ramColor = _telemetry.ramUsagePercent > 85
        ? AppTheme.danger
        : AppTheme.ramAccent;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                key: getItemKey(5),
                icon: Icons.memory_rounded,
                title: "CPU",
                valueText: "${_telemetry.cpuUsagePercent}%",
                subtitle: _liveTdp != null
                    ? "$_liveTdp W"
                    : (_telemetry.isHvciBlocked ? "Tắt HVCI !" : "-- W"),
                progressValue: _telemetry.cpuUsagePercent / 100.0,
                accentColor: cpuColor,
                isFocused: focusedIndex == 5,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                key: getItemKey(6),
                icon: Icons.storage_rounded,
                title: "RAM",
                valueText: "${_telemetry.ramUsagePercent}%",
                subtitle:
                    "${_telemetry.ramUsedGb.toStringAsFixed(1)}/${_telemetry.ramTotalGb.toStringAsFixed(0)}GB",
                progressValue: _telemetry.ramUsagePercent / 100.0,
                accentColor: ramColor,
                isFocused: focusedIndex == 6,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    Key? key,
    required IconData icon,
    required String title,
    required String valueText,
    required String subtitle,
    required double progressValue,
    required Color accentColor,
    required bool isFocused,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isFocused ? AppTheme.primary : AppTheme.cardBorder,
          width: isFocused ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppTheme.scaled(15), color: accentColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                subtitle,
                style: AppTheme.hint.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valueText,
            style: TextStyle(
              fontSize: AppTheme.scaled(20),
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progressValue.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppTheme.secondary.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
