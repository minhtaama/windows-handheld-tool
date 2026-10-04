import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/config.dart';
import '../hardware/tdp_service.dart';
import '../hardware/fan_service.dart';
import '../hardware/brightness_service.dart';
import '../hardware/audio_service.dart';
import '../services/virtual_keyboard_service.dart';
import '../services/overlay_controller.dart';
import 'widgets/setting_slider.dart';
import 'widgets/action_button.dart';

/// Nội dung thanh Quick Settings dạng trượt dành cho máy Handheld.
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

  late int _tdp;
  late int _fan;
  late bool _fanAuto;
  late int _brightness;
  late int _audio;

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

    _tdp = _tdpCtrl.getValue();
    _fan = _fanCtrl.getValue();
    _fanAuto = _fanCtrl.isAuto();
    _brightness = _brightnessCtrl.getValue();
    _audio = _audioCtrl.getValue();
  }

  void _updateTdp(int val) {
    setState(() => _tdp = val);
    _tdpCtrl.setValue(val);
    widget.config.set("hardware.tdp.current", val);
  }

  void _updateFan(int val) {
    setState(() {
      _fan = val;
      _fanAuto = false;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppTheme.panelRadius),
          bottomLeft: Radius.circular(AppTheme.panelRadius),
        ),
        border: Border(
          left: BorderSide(
            color: AppTheme.primaryNeon.withOpacity(0.4),
            width: 2,
          ),
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNeon.withOpacity(0.05),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 1. Header (Tiêu đề + Nút Đóng)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.gamepad,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("QUICK SETTINGS", style: AppTheme.headerTitle),
                      Text("GPD Win 4 & Handheld Tool", style: AppTheme.headerSubtitle),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    splashRadius: 20,
                    onPressed: () => OverlayController.instance.hideOverlay(),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1),

            // 2. Nội dung cuộn chính
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                children: [
                  // Nhóm 1: Hiệu năng & Năng lượng
                  _buildSectionLabel("NĂNG LƯỢNG & TẢN NHIỆT"),
                  SettingSlider(
                    icon: Icons.bolt,
                    title: "Công suất TDP",
                    value: _tdp,
                    min: _tdpCtrl.minVal,
                    max: _tdpCtrl.maxVal,
                    step: _tdpCtrl.step,
                    unit: _tdpCtrl.unit,
                    onChanged: _updateTdp,
                  ),
                  const SizedBox(height: 10),
                  SettingSlider(
                    icon: Icons.toys,
                    title: "Tốc độ quạt",
                    value: _fan,
                    min: _fanCtrl.minVal,
                    max: _fanCtrl.maxVal,
                    step: _fanCtrl.step,
                    unit: _fanCtrl.unit,
                    onChanged: _updateFan,
                    trailing: ActionChip(
                      label: Text(
                        _fanAuto ? "AUTO" : "MANUAL",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _fanAuto ? AppTheme.primaryNeon : Colors.white70,
                        ),
                      ),
                      backgroundColor: _fanAuto
                          ? AppTheme.primaryNeon.withOpacity(0.15)
                          : Colors.white.withOpacity(0.08),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: _toggleFanAuto,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Nhóm 2: Màn hình & Âm thanh
                  _buildSectionLabel("MÀN HÌNH & ÂM THANH"),
                  SettingSlider(
                    icon: Icons.brightness_6,
                    title: "Độ sáng màn hình",
                    value: _brightness,
                    min: _brightnessCtrl.minVal,
                    max: _brightnessCtrl.maxVal,
                    step: _brightnessCtrl.step,
                    unit: _brightnessCtrl.unit,
                    onChanged: _updateBrightness,
                  ),
                  const SizedBox(height: 10),
                  SettingSlider(
                    icon: Icons.volume_up,
                    title: "Âm lượng loa",
                    value: _audio,
                    min: _audioCtrl.minVal,
                    max: _audioCtrl.maxVal,
                    step: _audioCtrl.step,
                    unit: _audioCtrl.unit,
                    onChanged: _updateAudio,
                  ),
                  const SizedBox(height: 18),

                  // Nhóm 3: Phím tắt nhanh dạng Lưới
                  _buildSectionLabel("THAO TÁC NHANH"),
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton(
                          icon: Icons.keyboard,
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
                          icon: Icons.memory,
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
                          icon: Icons.display_settings,
                          title: "Màn hình",
                          subtitle: "Đổi độ phân giải",
                          onTap: () {
                            OverlayController.instance.hideOverlay();
                            Process.start('explorer.exe', ['ms-settings:display'], runInShell: true);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ActionButton(
                          icon: Icons.fullscreen_exit,
                          title: "Đóng Menu",
                          subtitle: "Phím: Back + RB",
                          onTap: () => OverlayController.instance.hideOverlay(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6C7A92),
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
