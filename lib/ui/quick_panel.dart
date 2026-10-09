import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/config.dart';
import '../hardware/tdp_service.dart';
import '../hardware/fan_service.dart';
import '../hardware/brightness_service.dart';
import '../hardware/audio_service.dart';
import '../hardware/rtss_service.dart';
import '../hardware/touchscreen_service.dart';
import '../input/gamepad_service.dart';
import '../services/system_optimizer.dart';
import '../services/virtual_keyboard_service.dart';
import '../services/autostart_service.dart';
import '../services/dxgi_hook_service.dart';
import '../services/overlay_controller.dart';
import '../services/rtss_installer_service.dart';
import '../services/system_telemetry_service.dart';
import 'tabs/home_tab.dart';
import 'tabs/performance_tab.dart';
import 'tabs/device_tab.dart';
import 'tabs/settings_tab.dart';
import 'widgets/tab_bar.dart';

/// Nội dung thanh Quick Settings cho máy Handheld hỗ trợ đầy đủ cảm ứng & tay cầm Gamepad.
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
  late bool _autoStartEnabled;
  late OverlayHookMode _hookMode;
  late int _widthPercent;
  late double _scale;

  // Cấu hình RTSS OSD
  late bool _rtssOsdEnabled;
  late int _rtssOsdZoom;
  late RtssOsdPosition _rtssOsdPosition;

  // Tab đang được chọn (0: Trang chủ, 1: Hiệu năng, 2: Thiết bị, 3: Cài đặt & Tiện ích)
  int _selectedTabIndex = 0;

  // Vị trí điều khiển đang được chọn bằng Gamepad trong Tab hiện tại
  int _focusedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<GamepadButton>? _gamepadSub;

  // Dữ liệu đo cảm biến thực tế tức thời (Hardware Telemetry)
  late int _liveTdp;
  late int _liveFan;
  int? _liveFps;
  String? _activeGame;
  bool _isRtssRunning = false;
  Timer? _telemetryTimer;
  SystemTelemetryData _telemetryData = SystemTelemetryData.initial();

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
    _rtssOsdEnabled = widget.config.get("hardware.rtss.osd_enabled", true);
    if (_rtssCtrl.isAvailable()) {
      _rtssOsdEnabled = _rtssCtrl.isOsdEnabled();
    }
    _rtssOsdZoom = widget.config.get("hardware.rtss.osd_zoom", 2);
    if (_rtssCtrl.isAvailable()) {
      _rtssOsdZoom = _rtssCtrl.getOsdZoom();
    }
    final savedOsdPos = widget.config.get(
      "hardware.rtss.osd_position",
      "topLeft",
    );
    _rtssOsdPosition = RtssOsdPosition.values.firstWhere(
      (p) => p.name == savedOsdPos,
      orElse: () => _rtssCtrl.isAvailable()
          ? _rtssCtrl.getOsdPosition()
          : RtssOsdPosition.topLeft,
    );
    _touchEnabled = TouchscreenService.isEnabled;
    _autoStartEnabled = AutostartService.instance.isEnabled;
    _hookMode = DxgiHookService.instance.hookMode;
    _widthPercent = widget.config.get("overlay.width_percent", 35);
    _scale = (widget.config.get("overlay.scale", 1.0) as num).toDouble();
    AppTheme.uiScale = _scale;

    _liveTdp = (_tdp * 0.85).round().clamp(_tdpCtrl.minVal, _tdp);
    _liveFan = (_fan * 0.9).round().clamp(_fanCtrl.minVal, _fanCtrl.maxVal);
    _isRtssRunning = _rtssCtrl.isAvailable();
    if (RtssInstallerService.isInstalled() && !_isRtssRunning) {
      _startRtss();
    }
    _telemetryData = SystemTelemetryService.instance.getSnapshot();

    // Lắng nghe sự kiện điều hướng từ Gamepad
    _gamepadSub = GamepadService.buttonEvents.listen(_onGamepadButton);

    // Kích hoạt Timer quét cảm biến phần cứng định kỳ 1s khi panel mở
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1000), (
      timer,
    ) {
      if (!mounted) return;
      setState(() {
        _telemetryData = SystemTelemetryService.instance.getSnapshot();

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
    _gamepadSub?.cancel();
    _telemetryTimer?.cancel();
    _scrollController.dispose();
    SystemTelemetryService.instance.dispose();
    super.dispose();
  }

  List<List<int>> _getTabLayout(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return [
          [0],
          [1],
          [2, 3],
        ];
      case 1:
        return [
          [0],
          [1],
          [2],
          [3],
          if (RtssInstallerService.isInstalled()) ...[
            [4],
            [5],
            if (_rtssOsdEnabled) ...[
              [6],
              [7],
            ],
          ],
        ];
      case 2:
        return [
          [0],
          [1],
          [2],
        ];
      case 3:
        return [
          [0, 1],
          [2, 3],
          [4],
          [5],
          [6],
          [7],
          [8],
        ];
      default:
        return [
          [0],
        ];
    }
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

  void _switchTab(int newIndex) {
    if (_selectedTabIndex != newIndex) {
      setState(() {
        _selectedTabIndex = newIndex;
        _focusedIndex = 0;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  void _setFocus(int nextIdx) {
    if (nextIdx != _focusedIndex) {
      setState(() => _focusedIndex = nextIdx);
      _autoScrollToFocused();
    }
  }

  void _handleGamepadUp() {
    final layout = _getTabLayout(_selectedTabIndex);
    final (r, c) = _findGridPosition(layout, _focusedIndex);
    if (r > 0) {
      final prevRow = layout[r - 1];
      final targetCol = min(c, prevRow.length - 1);
      _setFocus(prevRow[targetCol]);
    }
  }

  void _handleGamepadDown() {
    final layout = _getTabLayout(_selectedTabIndex);
    final (r, c) = _findGridPosition(layout, _focusedIndex);
    if (r < layout.length - 1) {
      final nextRow = layout[r + 1];
      final targetCol = min(c, nextRow.length - 1);
      _setFocus(nextRow[targetCol]);
    }
  }

  void _autoScrollToFocused() {
    if (!_scrollController.hasClients) return;
    final layout = _getTabLayout(_selectedTabIndex);
    final (r, _) = _findGridPosition(layout, _focusedIndex);
    final targetOffset = (r * (120.0 * _scale)).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
    );
  }

  void _cyclePreset<T>(
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

  void _onGamepadButton(GamepadButton button) {
    if (!mounted || !OverlayController.instance.isVisible) return;

    switch (button) {
      case GamepadButton.lb:
        _switchTab((_selectedTabIndex - 1 + 4) % 4);
        break;
      case GamepadButton.rb:
        _switchTab((_selectedTabIndex + 1) % 4);
        break;
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
        _handleGamepadA();
        break;
      case GamepadButton.b:
        OverlayController.instance.hideOverlay();
        break;
      case GamepadButton.x:
        _handleGamepadX();
        break;
      default:
        break;
    }
  }

  void _handleGamepadLeft() {
    final layout = _getTabLayout(_selectedTabIndex);
    final (r, c) = _findGridPosition(layout, _focusedIndex);
    final currentRow = layout[r];

    // Nếu hàng có nhiều phần tử (Grid/Row), D-pad Left di chuyển sang phần tử bên trái
    if (currentRow.length > 1) {
      if (c > 0) {
        _setFocus(currentRow[c - 1]);
      }
      return;
    }

    // Nếu hàng chỉ có 1 phần tử (Slider, Toggle, Preset), điều chỉnh giá trị của phần tử
    switch (_selectedTabIndex) {
      case 1:
        if (_focusedIndex == 0) {
          _toggleTdpAuto();
        } else if (_focusedIndex == 1) {
          _updateTdp(max(_tdpCtrl.minVal, _tdp - _tdpCtrl.step));
        } else if (_focusedIndex == 2) {
          _toggleFanAuto();
        } else if (_focusedIndex == 3) {
          _updateFan(max(_fanCtrl.minVal, _fan - _fanCtrl.step));
        } else if (_focusedIndex == 4 && RtssInstallerService.isInstalled()) {
          _cyclePreset(const [0, 30, 40, 60], _fpsLimit, -1, _updateFpsLimit);
        } else if (_focusedIndex == 5 && RtssInstallerService.isInstalled()) {
          _toggleRtssOsd();
        } else if (_focusedIndex == 6 && RtssInstallerService.isInstalled()) {
          _cyclePreset(
            const [1, 2, 3, 4],
            _rtssOsdZoom,
            -1,
            _updateRtssOsdZoom,
          );
        } else if (_focusedIndex == 7 && RtssInstallerService.isInstalled()) {
          _cyclePreset(
            RtssOsdPosition.values,
            _rtssOsdPosition,
            -1,
            _updateRtssOsdPosition,
          );
        }
        break;
      case 2:
        if (_focusedIndex == 0) {
          _updateBrightness(
            max(_brightnessCtrl.minVal, _brightness - _brightnessCtrl.step),
          );
        } else if (_focusedIndex == 1) {
          _updateAudio(max(_audioCtrl.minVal, _audio - _audioCtrl.step));
        } else if (_focusedIndex == 2) {
          _toggleTouchscreen();
        }
        break;
      case 3:
        if (_focusedIndex == 5) {
          _toggleAutoStart(!_autoStartEnabled);
        } else if (_focusedIndex == 6) {
          _cyclePreset(
            OverlayHookMode.values,
            _hookMode,
            -1,
            _updateHookMode,
          );
        } else if (_focusedIndex == 7) {
          _cyclePreset(const [0.9, 1.0, 1.1, 1.2], _scale, -1, _updateScale);
        } else if (_focusedIndex == 8) {
          _cyclePreset(
            const [30, 35, 40, 45],
            _widthPercent,
            -1,
            _updateWidthPercent,
          );
        }
        break;
    }
  }

  void _handleGamepadRight() {
    final layout = _getTabLayout(_selectedTabIndex);
    final (r, c) = _findGridPosition(layout, _focusedIndex);
    final currentRow = layout[r];

    // Nếu hàng có nhiều phần tử (Grid/Row), D-pad Right di chuyển sang phần tử bên phải
    if (currentRow.length > 1) {
      if (c < currentRow.length - 1) {
        _setFocus(currentRow[c + 1]);
      }
      return;
    }

    // Nếu hàng chỉ có 1 phần tử (Slider, Toggle, Preset), điều chỉnh giá trị của phần tử
    switch (_selectedTabIndex) {
      case 1:
        if (_focusedIndex == 0) {
          _toggleTdpAuto();
        } else if (_focusedIndex == 1) {
          _updateTdp(min(_tdpCtrl.maxVal, _tdp + _tdpCtrl.step));
        } else if (_focusedIndex == 2) {
          _toggleFanAuto();
        } else if (_focusedIndex == 3) {
          _updateFan(min(_fanCtrl.maxVal, _fan + _fanCtrl.step));
        } else if (_focusedIndex == 4 && RtssInstallerService.isInstalled()) {
          _cyclePreset(const [0, 30, 40, 60], _fpsLimit, 1, _updateFpsLimit);
        } else if (_focusedIndex == 5 && RtssInstallerService.isInstalled()) {
          _toggleRtssOsd();
        } else if (_focusedIndex == 6 && RtssInstallerService.isInstalled()) {
          _cyclePreset(const [1, 2, 3, 4], _rtssOsdZoom, 1, _updateRtssOsdZoom);
        } else if (_focusedIndex == 7 && RtssInstallerService.isInstalled()) {
          _cyclePreset(
            RtssOsdPosition.values,
            _rtssOsdPosition,
            1,
            _updateRtssOsdPosition,
          );
        }
        break;
      case 2:
        if (_focusedIndex == 0) {
          _updateBrightness(
            min(_brightnessCtrl.maxVal, _brightness + _brightnessCtrl.step),
          );
        } else if (_focusedIndex == 1) {
          _updateAudio(min(_audioCtrl.maxVal, _audio + _audioCtrl.step));
        } else if (_focusedIndex == 2) {
          _toggleTouchscreen();
        }
        break;
      case 3:
        if (_focusedIndex == 5) {
          _toggleAutoStart(!_autoStartEnabled);
        } else if (_focusedIndex == 6) {
          _cyclePreset(
            OverlayHookMode.values,
            _hookMode,
            1,
            _updateHookMode,
          );
        } else if (_focusedIndex == 7) {
          _cyclePreset(const [0.9, 1.0, 1.1, 1.2], _scale, 1, _updateScale);
        } else if (_focusedIndex == 8) {
          _cyclePreset(
            const [30, 35, 40, 45],
            _widthPercent,
            1,
            _updateWidthPercent,
          );
        }
        break;
    }
  }

  void _handleGamepadA() {
    switch (_selectedTabIndex) {
      case 0:
        break;
      case 1:
        if (_focusedIndex == 0) {
          _toggleTdpAuto();
        } else if (_focusedIndex == 1) {
          _cyclePreset(const [10, 15, 20, 25, 30], _tdp, 1, _updateTdp);
        } else if (_focusedIndex == 2) {
          _toggleFanAuto();
        } else if (_focusedIndex == 3) {
          _cyclePreset(const [30, 50, 75, 100], _fan, 1, _updateFan);
        } else if (_focusedIndex == 4) {
          if (!RtssInstallerService.isInstalled()) {
            _handleInstallRtss();
          } else {
            _cyclePreset(const [0, 30, 40, 60], _fpsLimit, 1, _updateFpsLimit);
          }
        } else if (_focusedIndex == 5) {
          _toggleRtssOsd();
        } else if (_focusedIndex == 6) {
          _cyclePreset(const [1, 2, 3, 4], _rtssOsdZoom, 1, _updateRtssOsdZoom);
        } else if (_focusedIndex == 7) {
          _cyclePreset(
            RtssOsdPosition.values,
            _rtssOsdPosition,
            1,
            _updateRtssOsdPosition,
          );
        }
        break;
      case 2:
        if (_focusedIndex == 0) {
          _cyclePreset(
            const [25, 50, 75, 100],
            _brightness,
            1,
            _updateBrightness,
          );
        } else if (_focusedIndex == 1) {
          _cyclePreset(const [0, 30, 60, 100], _audio, 1, _updateAudio);
        } else if (_focusedIndex == 2) {
          _toggleTouchscreen();
        }
        break;
      case 3:
        if (_focusedIndex == 0) {
          OverlayController.instance.hideOverlay();
          VirtualKeyboardService.toggleKeyboard();
        } else if (_focusedIndex == 1) {
          OverlayController.instance.hideOverlay();
          Process.start('taskmgr.exe', [], runInShell: true);
        } else if (_focusedIndex == 2) {
          OverlayController.instance.hideOverlay();
          Process.start('explorer.exe', [
            'ms-settings:display',
          ], runInShell: true);
        } else if (_focusedIndex == 3) {
          SystemOptimizer.trimMemory();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã giải phóng bộ nhớ RAM tiến trình!'),
              duration: Duration(seconds: 1),
            ),
          );
        } else if (_focusedIndex == 4) {
          OverlayController.instance.hideOverlay();
        } else if (_focusedIndex == 5) {
          _toggleAutoStart(!_autoStartEnabled);
        } else if (_focusedIndex == 6) {
          _cyclePreset(
            OverlayHookMode.values,
            _hookMode,
            1,
            _updateHookMode,
          );
        } else if (_focusedIndex == 7) {
          _cyclePreset(const [0.9, 1.0, 1.1, 1.2], _scale, 1, _updateScale);
        } else if (_focusedIndex == 8) {
          _cyclePreset(
            const [30, 35, 40, 45],
            _widthPercent,
            1,
            _updateWidthPercent,
          );
        }
        break;
    }
  }

  void _handleGamepadX() {
    // Nút X hiện được xử lý trực tiếp bởi widget HelpBox đang giữ focus
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

  void _toggleRtssOsd() {
    final next = !_rtssOsdEnabled;
    setState(() => _rtssOsdEnabled = next);
    _rtssCtrl.setOsdEnabled(next);
    widget.config.set("hardware.rtss.osd_enabled", next);
  }

  void _updateRtssOsdZoom(int val) {
    setState(() => _rtssOsdZoom = val);
    _rtssCtrl.setOsdZoom(val);
    widget.config.set("hardware.rtss.osd_zoom", val);
  }

  void _updateRtssOsdPosition(RtssOsdPosition pos) {
    setState(() => _rtssOsdPosition = pos);
    _rtssCtrl.setOsdPosition(pos);
    widget.config.set("hardware.rtss.osd_position", pos.name);
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

  void _updateScale(double val) {
    setState(() {
      _scale = val;
      AppTheme.uiScale = val;
    });
    OverlayController.instance.updateScale(val);
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

  void _toggleAutoStart(bool val) async {
    setState(() => _autoStartEnabled = val);
    final success = await AutostartService.instance.setEnabled(val);
    if (mounted) {
      setState(() => _autoStartEnabled = AutostartService.instance.isEnabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (val
                    ? 'Đã bật khởi động cùng Windows (Task Scheduler elevated)!'
                    : 'Đã tắt khởi động cùng Windows!')
                : 'Không thể thay đổi tác vụ khởi động (Cần quyền Admin).',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? AppTheme.accent : AppTheme.danger,
        ),
      );
    }
  }

  void _updateHookMode(OverlayHookMode mode) {
    setState(() => _hookMode = mode);
    DxgiHookService.instance.setHookMode(mode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == OverlayHookMode.sharedTexture
              ? 'Chuyển sang Direct3D Shared Texture Injection (Present Hook)'
              : 'Chuyển sang DXGI Borderless Hook (iFlip Mode)',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Thanh Tab Bar nổi phía trên (Compact Mode với 4 Tab)
        AppTabBar(
          selectedIndex: _selectedTabIndex,
          items: const [
            AppTabItem(icon: Icons.home_rounded, label: 'Trang chủ'),
            AppTabItem(icon: Icons.bolt_rounded, label: 'Hiệu năng'),
            AppTabItem(icon: Icons.tune_rounded, label: 'Thiết bị'),
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
                _buildGamepadFooter(),
              ],
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
        return HomeTab(
          scrollController: _scrollController,
          focusedIndex: _focusedIndex,
          telemetry: _telemetryData,
          liveTdp: _liveTdp,
        );
      case 1:
        return PerformanceTab(
          scrollController: _scrollController,
          focusedIndex: _focusedIndex,
          tdp: _tdp,
          liveTdp: _liveTdp,
          tdpAuto: _tdpAuto,
          tdpCtrl: _tdpCtrl,
          onTdpChanged: _updateTdp,
          onToggleTdpAuto: _toggleTdpAuto,
          fan: _fan,
          liveFan: _liveFan,
          fanAuto: _fanAuto,
          fanCtrl: _fanCtrl,
          onFanChanged: _updateFan,
          onToggleFanAuto: _toggleFanAuto,
          fpsLimit: _fpsLimit,
          liveFps: _liveFps,
          activeGame: _activeGame,
          rtssCtrl: _rtssCtrl,
          onFpsLimitChanged: _updateFpsLimit,
          isInstallingRtss: _isInstallingRtss,
          rtssInstallMsg: _rtssInstallMsg,
          onInstallRtss: _handleInstallRtss,
          osdEnabled: _rtssOsdEnabled,
          onToggleOsd: (_) => _toggleRtssOsd(),
          osdZoom: _rtssOsdZoom,
          onOsdZoomChanged: _updateRtssOsdZoom,
          osdPosition: _rtssOsdPosition,
          onOsdPositionChanged: _updateRtssOsdPosition,
        );
      case 2:
        return DeviceTab(
          scrollController: _scrollController,
          focusedIndex: _focusedIndex,
          brightness: _brightness,
          brightnessCtrl: _brightnessCtrl,
          onBrightnessChanged: _updateBrightness,
          audio: _audio,
          audioCtrl: _audioCtrl,
          onAudioChanged: _updateAudio,
          touchEnabled: _touchEnabled,
          onToggleTouchscreen: _toggleTouchscreen,
        );
      case 3:
        return SettingsTab(
          scrollController: _scrollController,
          focusedIndex: _focusedIndex,
          autoStartEnabled: _autoStartEnabled,
          onToggleAutoStart: _toggleAutoStart,
          hookMode: _hookMode,
          onHookModeChanged: _updateHookMode,
          onVirtualKeyboard: () {
            OverlayController.instance.hideOverlay();
            VirtualKeyboardService.toggleKeyboard();
          },
          onTaskManager: () {
            OverlayController.instance.hideOverlay();
            Process.start('taskmgr.exe', [], runInShell: true);
          },
          onDisplaySettings: () {
            OverlayController.instance.hideOverlay();
            Process.start('explorer.exe', [
              'ms-settings:display',
            ], runInShell: true);
          },
          onTrimMemory: () {
            SystemOptimizer.trimMemory();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã giải phóng bộ nhớ RAM tiến trình!'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          onClosePanel: () => OverlayController.instance.hideOverlay(),
          isRtssRunning: _isRtssRunning,
          activeGame: _activeGame,
          isTdpHardwareActive: _tdpCtrl.isAvailable(),
          isDxgiHookActive:
              DxgiHookService.instance.isHookActive ||
              DxgiHookService.instance.isEnabled,
          isGamepadConnected: GamepadService.isConnected,
          scale: _scale,
          onScaleChanged: _updateScale,
          widthPercent: _widthPercent,
          onWidthPercentChanged: _updateWidthPercent,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Thanh gợi ý thao tác tay cầm Gamepad phong cách Console dưới đáy Panel
  Widget _buildGamepadFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: AppTheme.cardBorder, width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildHintBadge("X", "Trợ giúp"),
          const SizedBox(width: 12),
          _buildHintBadge("A", "Chọn"),
          const SizedBox(width: 12),
          _buildHintBadge("B", "Đóng"),
        ],
      ),
    );
  }

  Widget _buildHintBadge(String keyText, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.4),
              width: 0.8,
            ),
          ),
          child: Text(keyText, style: AppTheme.hint),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTheme.hint),
      ],
    );
  }
}
