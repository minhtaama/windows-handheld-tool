import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/config.dart';
import '../hardware/tdp_service.dart';
import '../hardware/fan_service.dart';
import '../hardware/brightness_service.dart';
import '../hardware/audio_service.dart';
import '../hardware/rtss_service.dart';
import '../hardware/rtss_osd_formatter.dart';
import '../hardware/touchscreen_service.dart';
import '../input/gamepad_service.dart';
import '../input/hotkey_service.dart';
import '../services/system_optimizer.dart';
import '../services/virtual_keyboard_service.dart';
import '../services/autostart_service.dart';
import '../services/overlay_controller.dart';
import '../services/rtss_installer_service.dart';
import '../services/system_telemetry_service.dart';
import '../services/bridge_service.dart';
import 'tabs/home_tab.dart';
import 'tabs/performance_tab.dart';
import 'tabs/device_tab.dart';
import 'tabs/settings_tab.dart';
import 'widgets/hotkey_tile.dart';
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
  late int _widthPercent;
  late double _scale;

  final _overlayHotkeyKey = GlobalKey<HotkeyTileState>();
  final _virtualKeyboardHotkeyKey = GlobalKey<HotkeyTileState>();

  // Cấu hình Phím tắt đơn nhất (Mỗi tính năng chỉ 1 hotkey: Bàn phím PC HOẶC Gamepad)
  late String _overlayHotkeyDevice;
  late String _overlayHotkey;
  late String _virtualKeyboardHotkeyDevice;
  late String _virtualKeyboardHotkey;

  // Cấu hình RTSS OSD
  late bool _rtssOsdEnabled;
  late int _rtssOsdZoom;
  late RtssOsdPosition _rtssOsdPosition;

  // Tab đang được chọn (0: Trang chủ, 1: Hiệu năng, 2: Thiết bị, 3: Cài đặt & Tiện ích)
  int _selectedTabIndex = 0;

  // Vị trí điều khiển đang được chọn bằng Gamepad trong Tab hiện tại
  int _focusedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  GlobalKey _getItemKey(int index) {
    if (_selectedTabIndex == 3) {
      if (index == 5) {
        _itemKeys[5] = _overlayHotkeyKey;
        return _overlayHotkeyKey;
      }
      if (index == 6) {
        _itemKeys[6] = _virtualKeyboardHotkeyKey;
        return _virtualKeyboardHotkeyKey;
      }
    }
    return _itemKeys.putIfAbsent(index, () => GlobalKey());
  }

  StreamSubscription<GamepadButton>? _gamepadSub;

  // Dữ liệu đo cảm biến thực tế tức thời (Hardware Telemetry)
  int? _liveTdp;
  late int _liveFan;
  int? _liveFps;
  String? _activeGame;
  bool _isRtssRunning = false;
  late RtssOsdMetricsConfig _rtssOsdMetrics;
  bool _isRevivingRtss = false;
  int _lastRtssWatchdogAttempt = 0;
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
    final initialTdp = _tdpAuto ? _tdpCtrl.maxVal : _tdp;
    _tdpCtrl.setValue(initialTdp);

    // Chống hiện tượng ACPI Power Plan của Windows tự động ghi đè lại giới hạn sau khi boot máy
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        final currentTdp = _tdpAuto ? _tdpCtrl.maxVal : _tdp;
        _tdpCtrl.setValue(currentTdp);
      }
    });

    _fan = _fanCtrl.getValue();
    _fanAuto = _fanCtrl.isAuto();
    _brightness = _brightnessCtrl.getValue();
    _audio = _audioCtrl.getValue();

    // Lấy cấu hình FPS limit từ file profile của RTSS hoặc từ config.json
    final savedFps = widget.config.get("hardware.rtss.fps_limit", 60);
    _fpsLimit = _rtssCtrl.isAvailable() ? _rtssCtrl.getValue() : savedFps;
    _rtssOsdEnabled = widget.config.get("hardware.rtss.osd_enabled", true);
    _rtssOsdZoom = widget.config.get("hardware.rtss.osd_zoom", 2);
    final savedOsdPos = widget.config.get(
      "hardware.rtss.osd_position",
      "topLeft",
    );
    _rtssOsdPosition = RtssOsdPosition.values.firstWhere(
      (p) => p.name == savedOsdPos,
      orElse: () => RtssOsdPosition.topLeft,
    );
    if (_rtssCtrl.isAvailable()) {
      _rtssCtrl.setOsdEnabled(_rtssOsdEnabled);
      _rtssCtrl.setOsdZoom(_rtssOsdZoom);
      _rtssCtrl.setOsdPosition(_rtssOsdPosition);
      if (_rtssOsdEnabled) {
        _refreshOsdText();
      }
    }
    _rtssOsdMetrics = RtssOsdMetricsConfig.fromConfig(widget.config);
    _touchEnabled = TouchscreenService.isEnabled;
    _autoStartEnabled = AutostartService.instance.isEnabled;
    _widthPercent = widget.config.get("overlay.width_percent", 35);
    _scale = (widget.config.get("overlay.scale", 1.0) as num).toDouble();
    AppTheme.uiScale = _scale;

    // Khởi tạo phím tắt duy nhất cho Quick Settings (Ưu tiên Keyboard)
    final kbOverlay = widget.config.get("hotkey.toggle_overlay", "Ctrl+Shift+Q");
    final gpOverlay = widget.config.get("gamepad.overlay_combo", "");
    if (kbOverlay.isNotEmpty) {
      _overlayHotkeyDevice = 'keyboard';
      _overlayHotkey = kbOverlay;
    } else if (gpOverlay.isNotEmpty) {
      _overlayHotkeyDevice = 'gamepad';
      _overlayHotkey = gpOverlay;
    } else {
      _overlayHotkeyDevice = 'keyboard';
      _overlayHotkey = 'Ctrl+Shift+Q';
    }

    // Khởi tạo phím tắt duy nhất cho Virtual Keyboard (Ưu tiên Keyboard)
    final kbKb = widget.config.get("hotkey.toggle_keyboard", "Ctrl+Alt+K");
    final gpKb = widget.config.get("gamepad.keyboard_combo", "");
    if (kbKb.isNotEmpty) {
      _virtualKeyboardHotkeyDevice = 'keyboard';
      _virtualKeyboardHotkey = kbKb;
    } else if (gpKb.isNotEmpty) {
      _virtualKeyboardHotkeyDevice = 'gamepad';
      _virtualKeyboardHotkey = gpKb;
    } else {
      _virtualKeyboardHotkeyDevice = 'keyboard';
      _virtualKeyboardHotkey = 'Ctrl+Alt+K';
    }

    _liveTdp = _tdpCtrl.getLiveTdp()?.round();
    _liveFan = _fan;
    _isRtssRunning = _rtssCtrl.isAvailable();
    if (RtssInstallerService.isInstalled() && !_isRtssRunning) {
      _startRtss();
    }
    _telemetryData = SystemTelemetryService.instance.getSnapshot();

    // Lắng nghe sự kiện điều hướng từ Gamepad
    _gamepadSub = GamepadService.buttonEvents.listen(_onGamepadButton);

    // Lắng nghe sự kiện đóng/mở panel để cập nhật số liệu ngay lập tức khi mở
    OverlayController.instance.addListener(_onOverlayVisibilityChanged);

    // Lắng nghe đồng bộ cấu hình từ Python WebSocket Server
    BridgeService.instance.config.addListener(_onConfigUpdated);

    // Lắng nghe đồng bộ độ sáng & âm lượng từ Windows qua BridgeService
    BridgeService.instance.brightness.addListener(_onBrightnessFromWindows);
    BridgeService.instance.volume.addListener(_onAudioFromWindows);

    // Kích hoạt Timer quét cảm biến phần cứng định kỳ 1s
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _updateTelemetry();
    });
  }

  void _onConfigUpdated() {
    if (!mounted) return;
    final cfg = BridgeService.instance.config.value;
    if (cfg.isEmpty) return;

    setState(() {
      final kbOverlay = widget.config.get("hotkey.toggle_overlay", "Ctrl+Shift+Q");
      final gpOverlay = widget.config.get("gamepad.overlay_combo", "");
      if (kbOverlay.isNotEmpty) {
        _overlayHotkeyDevice = 'keyboard';
        _overlayHotkey = kbOverlay;
      } else if (gpOverlay.isNotEmpty) {
        _overlayHotkeyDevice = 'gamepad';
        _overlayHotkey = gpOverlay;
      }

      final kbKb = widget.config.get("hotkey.toggle_keyboard", "Ctrl+Alt+K");
      final gpKb = widget.config.get("gamepad.keyboard_combo", "");
      if (kbKb.isNotEmpty) {
        _virtualKeyboardHotkeyDevice = 'keyboard';
        _virtualKeyboardHotkey = kbKb;
      } else if (gpKb.isNotEmpty) {
        _virtualKeyboardHotkeyDevice = 'gamepad';
        _virtualKeyboardHotkey = gpKb;
      }

      _widthPercent = widget.config.get("overlay.width_percent", 35);
      _scale = (widget.config.get("overlay.scale", 1.0) as num).toDouble();
      AppTheme.uiScale = _scale;
    });
  }

  void _onBrightnessFromWindows() {
    if (!mounted) return;
    final winVal = BridgeService.instance.brightness.value;
    if (_brightness != winVal) {
      setState(() => _brightness = winVal);
    }
  }

  void _onAudioFromWindows() {
    if (!mounted) return;
    final winVal = BridgeService.instance.volume.value;
    if (_audio != winVal) {
      setState(() => _audio = winVal);
    }
  }

  void _onOverlayVisibilityChanged() {
    if (!mounted) return;
    if (OverlayController.instance.isVisible) {
      setState(() {
        _brightness = _brightnessCtrl.getValue();
        _audio = _audioCtrl.getValue();
      });
      _updateTelemetry();
    }
  }

  /// Cập nhật dữ liệu phần cứng thông minh:
  /// - Khi panel ẩn & OSD tắt: Ngủ đông hoàn toàn, không tốn 0.01% CPU/GPU.
  /// - Khi panel ẩn & OSD bật: Chỉ đọc số liệu cần thiết cho RTSS và ghi OSD, TUYỆT ĐỐI KHÔNG gọi setState().
  /// - Khi panel mở: Đọc toàn diện và gọi setState() để cập nhật giao diện người dùng.
  void _updateTelemetry() {
    if (!mounted) return;
    final isVisible = OverlayController.instance.isVisible;

    // 1. Panel đang ẩn và OSD không bật: Ngủ đông hoàn toàn
    if (!isVisible && !_rtssOsdEnabled) {
      return;
    }

    // 2. Panel đang ẩn nhưng RTSS OSD đang bật:
    // Cập nhật trực tiếp số liệu cho OSD, KHÔNG gọi setState() của Flutter engine
    if (!isVisible) {
      _isRtssRunning = _rtssCtrl.isAvailable();
      if (_isRtssRunning) {
        _telemetryData = SystemTelemetryService.instance.getSnapshot();
        if (_rtssOsdMetrics.showTdp) {
          final hwTdp = _tdpCtrl.getLiveTdp();
          _liveTdp = hwTdp?.round();
        }
        _liveFps = _rtssCtrl.getLiveFps();
        _refreshOsdText();
      } else {
        _checkRtssWatchdog();
      }
      return;
    }

    // 3. Panel đang mở: Cập nhật đầy đủ và kích hoạt render UI qua setState()
    setState(() {
      _telemetryData = SystemTelemetryService.instance.getSnapshot();

      final hwTdp = _tdpCtrl.getLiveTdp();
      _liveTdp = hwTdp != null ? hwTdp.round() : _telemetryData.liveTdp;
      _liveFan = _telemetryData.liveFan;

      // Đồng bộ độ sáng & âm lượng từ Windows
      final curBrightness = _brightnessCtrl.getValue();
      if (_brightness != curBrightness) {
        _brightness = curBrightness;
      }
      final curAudio = _audioCtrl.getValue();
      if (_audio != curAudio) {
        _audio = curAudio;
      }

      _isRtssRunning = _rtssCtrl.isAvailable();
      if (_isRtssRunning) {
        _liveFps = _rtssCtrl.getLiveFps();
        _activeGame = _rtssCtrl.getActiveGame();
        if (_rtssOsdEnabled) {
          _refreshOsdText();
        }
      } else {
        _liveFps = null;
        _activeGame = null;
        _checkRtssWatchdog();
      }
    });
  }

  void _checkRtssWatchdog() {
    if (!RtssInstallerService.isInstalled()) return;
    if (!_rtssOsdEnabled && _fpsLimit == 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isRevivingRtss || (now - _lastRtssWatchdogAttempt < 5000)) return;

    _lastRtssWatchdogAttempt = now;
    _isRevivingRtss = true;

    RtssService.instance.ensureRunning().then((success) {
      _isRevivingRtss = false;
      if (mounted && success) {
        _isRtssRunning = _rtssCtrl.isAvailable();
        if (_isRtssRunning) {
          _rtssCtrl.setOsdEnabled(_rtssOsdEnabled);
          _rtssCtrl.setValue(_fpsLimit);
          _rtssCtrl.setOsdZoom(_rtssOsdZoom);
          _rtssCtrl.setOsdPosition(_rtssOsdPosition);
          _liveFps = _rtssCtrl.getLiveFps();
          _activeGame = _rtssCtrl.getActiveGame();
        }
        if (OverlayController.instance.isVisible) {
          setState(() {});
        }
      }
    }).catchError((_) {
      _isRevivingRtss = false;
    });
  }

  @override
  void dispose() {
    BridgeService.instance.config.removeListener(_onConfigUpdated);
    BridgeService.instance.brightness.removeListener(_onBrightnessFromWindows);
    BridgeService.instance.volume.removeListener(_onAudioFromWindows);
    OverlayController.instance.removeListener(_onOverlayVisibilityChanged);
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
              [8],
              [9, 10],
              [11, 12],
              [13, 14],
              [15],
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
          [0, 1], // Mở bàn phím ảo, Mở Task Manager
          [2, 3], // Cài đặt màn hình, Dọn dẹp RAM
          [4], // Khởi động cùng Windows
          [5], // Phím tắt mở Quick Settings (HotkeyTile)
          [6], // Phím tắt mở Bàn phím ảo (HotkeyTile)
          [7], // Tỷ lệ hiển thị UI Scale
          [8], // Độ rộng Side Panel
          [9], // RivaTuner RTSS
          [10], // RyzenAdj TDP Driver
          [11], // DXGI Borderless Hook
          [12], // Tay cầm Gamepad
          [13], // Thông tin phần mềm
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
        _itemKeys.clear();
        if (newIndex == 3) {
          _itemKeys[5] = _overlayHotkeyKey;
          _itemKeys[6] = _virtualKeyboardHotkeyKey;
        }
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  void _setFocus(int nextIdx) {
    if (nextIdx != _focusedIndex) {
      setState(() => _focusedIndex = nextIdx);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoScrollToFocused();
      });
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

    // Hàng đầu tiên luôn cuộn về đỉnh danh sách để hiển thị trọn vẹn cả tiêu đề SectionLabel
    if (_focusedIndex == 0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Căn giữa tâm RenderBox chính xác 100% qua cây dựng hình Render Tree của Flutter Framework
    final key = _itemKeys[_focusedIndex];
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
      default:
        break;
    }
  }

  void _adjustFocusedSlider(int direction) {
    switch (_selectedTabIndex) {
      case 1:
        if (_focusedIndex == 1) {
          _updateTdp(
            (_tdp + direction * _tdpCtrl.step).clamp(
              _tdpCtrl.minVal,
              _tdpCtrl.maxVal,
            ),
          );
        } else if (_focusedIndex == 3) {
          _updateFan(
            (_fan + direction * _fanCtrl.step).clamp(
              _fanCtrl.minVal,
              _fanCtrl.maxVal,
            ),
          );
        } else if (_focusedIndex == 4 && RtssInstallerService.isInstalled()) {
          _updateFpsLimit(
            (_fpsLimit + direction * _rtssCtrl.step).clamp(
              _rtssCtrl.minVal,
              _rtssCtrl.maxVal,
            ),
          );
        }
        break;
      case 2:
        if (_focusedIndex == 0) {
          _updateBrightness(
            (_brightness + direction * _brightnessCtrl.step).clamp(
              _brightnessCtrl.minVal,
              _brightnessCtrl.maxVal,
            ),
          );
        } else if (_focusedIndex == 1) {
          _updateAudio(
            (_audio + direction * _audioCtrl.step).clamp(
              _audioCtrl.minVal,
              _audioCtrl.maxVal,
            ),
          );
        }
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

    // Chỉ điều chỉnh giá trị nếu phần tử đang focus là Slider
    _adjustFocusedSlider(-1);
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

    // Chỉ điều chỉnh giá trị nếu phần tử đang focus là Slider
    _adjustFocusedSlider(1);
  }

  void _handleGamepadA() async {
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
        } else if (_focusedIndex == 8) {
          _cyclePreset(
            RtssOsdLayout.values,
            _rtssOsdMetrics.layout,
            1,
            _updateRtssOsdLayout,
          );
        } else if (_focusedIndex == 9) {
          _toggleMetricFps();
        } else if (_focusedIndex == 10) {
          _toggleMetricTdp();
        } else if (_focusedIndex == 11) {
          _toggleMetricCpuTemp();
        } else if (_focusedIndex == 12) {
          _toggleMetricCpuUsage();
        } else if (_focusedIndex == 13) {
          _toggleMetricRam();
        } else if (_focusedIndex == 14) {
          _toggleMetricBattery();
        } else if (_focusedIndex == 15) {
          _toggleMetricFan();
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
          await OverlayController.instance.hideOverlay();
          VirtualKeyboardService.toggleKeyboard(fromGamepad: true);
        } else if (_focusedIndex == 1) {
          OverlayController.instance.hideOverlay();
          BridgeService.instance.launchTaskManager();
        } else if (_focusedIndex == 2) {
          OverlayController.instance.hideOverlay();
          BridgeService.instance.launchDisplaySettings();
        } else if (_focusedIndex == 3) {
          SystemOptimizer.trimMemory();
        } else if (_focusedIndex == 4) {
          _toggleAutoStart(!_autoStartEnabled);
        } else if (_focusedIndex == 5) {
          _overlayHotkeyKey.currentState?.startRecording();
        } else if (_focusedIndex == 6) {
          _virtualKeyboardHotkeyKey.currentState?.startRecording();
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

  void _updateTdp(int val) {
    setState(() {
      _tdp = val;
      _tdpAuto = false;
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
    widget.config.set("hardware.rtss.fps_limit", val);
    if (val > 0 && !_isRtssRunning) {
      _startRtss().then((_) {
        _rtssCtrl.setValue(val);
      });
    } else {
      _rtssCtrl.setValue(val);
    }
  }

  void _toggleRtssOsd() {
    final next = !_rtssOsdEnabled;
    setState(() => _rtssOsdEnabled = next);
    widget.config.set("hardware.rtss.osd_enabled", next);
    if (next) {
      if (!_isRtssRunning) {
        _startRtss().then((_) {
          _rtssCtrl.setOsdEnabled(next);
          _refreshOsdText();
        });
      } else {
        _rtssCtrl.setOsdEnabled(next);
        _refreshOsdText();
      }
    } else {
      _rtssCtrl.setOsdEnabled(next);
      _rtssCtrl.clearOsdText();
    }
  }

  void _refreshOsdText() {
    if (_isRtssRunning && _rtssOsdEnabled) {
      final text = RtssOsdFormatter.format(
        config: _rtssOsdMetrics,
        fps: _liveFps,
        liveTdp: _liveTdp,
        liveFan: _liveFan,
        cpuTemp: _tdpCtrl.getLiveCpuTemp(),
        cpuUsage: _telemetryData.cpuUsagePercent.toDouble(),
        ramUsedGb: _telemetryData.ramUsedGb,
        batteryPercent: _telemetryData.batteryPercent,
      );
      _rtssCtrl.updateOsdText(text);
    }
  }

  void _updateRtssOsdLayout(RtssOsdLayout layout) {
    setState(() => _rtssOsdMetrics = _rtssOsdMetrics.copyWith(layout: layout));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
  }

  void _toggleMetricFps() {
    setState(() => _rtssOsdMetrics =
        _rtssOsdMetrics.copyWith(showFps: !_rtssOsdMetrics.showFps));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
  }

  void _toggleMetricTdp() {
    setState(() => _rtssOsdMetrics =
        _rtssOsdMetrics.copyWith(showTdp: !_rtssOsdMetrics.showTdp));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
  }

  void _toggleMetricCpuTemp() {
    setState(() => _rtssOsdMetrics =
        _rtssOsdMetrics.copyWith(showCpuTemp: !_rtssOsdMetrics.showCpuTemp));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
  }

  void _toggleMetricCpuUsage() {
    setState(() => _rtssOsdMetrics =
        _rtssOsdMetrics.copyWith(showCpuUsage: !_rtssOsdMetrics.showCpuUsage));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
  }

  void _toggleMetricRam() {
    setState(() => _rtssOsdMetrics =
        _rtssOsdMetrics.copyWith(showRam: !_rtssOsdMetrics.showRam));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
  }

  void _toggleMetricBattery() {
    setState(() => _rtssOsdMetrics =
        _rtssOsdMetrics.copyWith(showBattery: !_rtssOsdMetrics.showBattery));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
  }

  void _toggleMetricFan() {
    setState(() => _rtssOsdMetrics =
        _rtssOsdMetrics.copyWith(showFan: !_rtssOsdMetrics.showFan));
    _rtssOsdMetrics.saveToConfig(widget.config);
    _refreshOsdText();
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

  void _updateOverlayHotkey(String device, String hotkey) {
    setState(() {
      _overlayHotkeyDevice = device;
      _overlayHotkey = hotkey;
    });

    if (device == 'keyboard') {
      widget.config.set("hotkey.toggle_overlay", hotkey);
      widget.config.set("gamepad.overlay_combo", "");
      HotkeyService.updateHotkeys(overlayHotkey: hotkey);
      GamepadService.updateCombos(overlayCombo: "");
      BridgeService.instance.setHotkey('overlay', hotkey, 'keyboard');
    } else if (device == 'gamepad') {
      widget.config.set("gamepad.overlay_combo", hotkey);
      widget.config.set("hotkey.toggle_overlay", "");
      GamepadService.updateCombos(overlayCombo: hotkey);
      HotkeyService.updateHotkeys(overlayHotkey: "");
      BridgeService.instance.setHotkey('overlay', hotkey, 'gamepad');
    } else {
      widget.config.set("hotkey.toggle_overlay", "");
      widget.config.set("gamepad.overlay_combo", "");
      HotkeyService.updateHotkeys(overlayHotkey: "");
      GamepadService.updateCombos(overlayCombo: "");
      BridgeService.instance.setHotkey('overlay', "", 'keyboard');
    }
  }

  void _updateVirtualKeyboardHotkey(String device, String hotkey) {
    setState(() {
      _virtualKeyboardHotkeyDevice = device;
      _virtualKeyboardHotkey = hotkey;
    });

    if (device == 'keyboard') {
      widget.config.set("hotkey.toggle_keyboard", hotkey);
      widget.config.set("gamepad.keyboard_combo", "");
      HotkeyService.updateHotkeys(keyboardHotkey: hotkey);
      GamepadService.updateCombos(keyboardCombo: "");
      BridgeService.instance.setHotkey('keyboard', hotkey, 'keyboard');
    } else if (device == 'gamepad') {
      widget.config.set("gamepad.keyboard_combo", hotkey);
      widget.config.set("hotkey.toggle_keyboard", "");
      GamepadService.updateCombos(keyboardCombo: hotkey);
      HotkeyService.updateHotkeys(keyboardHotkey: "");
      BridgeService.instance.setHotkey('keyboard', hotkey, 'gamepad');
    } else {
      widget.config.set("hotkey.toggle_keyboard", "");
      widget.config.set("gamepad.keyboard_combo", "");
      HotkeyService.updateHotkeys(keyboardHotkey: "");
      GamepadService.updateCombos(keyboardCombo: "");
      BridgeService.instance.setHotkey('keyboard', "", 'keyboard');
    }
  }


  Future<void> _toggleTouchscreen() async {
    await TouchscreenService.toggleTouchscreen();
    if (mounted) {
      setState(() {
        _touchEnabled = TouchscreenService.isEnabled;
      });
    }
  }

  Future<void> _handleInstallRtss() async {
    setState(() {
      _isInstallingRtss = true;
      _rtssInstallMsg = 'Đang kích hoạt trình cài đặt RTSS...';
    });

    await RtssInstallerService.installRtss(
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
    }
  }

  Future<void> _startRtss() async {
    await RtssService.instance.ensureRunning();
    if (mounted) {
      setState(() {
        _isRtssRunning = _rtssCtrl.isAvailable();
      });
      if (_isRtssRunning) {
        _rtssCtrl.setOsdEnabled(_rtssOsdEnabled);
        _rtssCtrl.setValue(_fpsLimit);
        _rtssCtrl.setOsdZoom(_rtssOsdZoom);
        _rtssCtrl.setOsdPosition(_rtssOsdPosition);
        _refreshOsdText();
      }
    }
  }

  void _toggleAutoStart(bool val) async {
    setState(() => _autoStartEnabled = val);
    await AutostartService.instance.setEnabled(val);
    if (mounted) {
      setState(() => _autoStartEnabled = AutostartService.instance.isEnabled);
    }
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
          getItemKey: _getItemKey,
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
          osdMetrics: _rtssOsdMetrics,
          onOsdLayoutChanged: _updateRtssOsdLayout,
          onToggleMetricFps: _toggleMetricFps,
          onToggleMetricTdp: _toggleMetricTdp,
          onToggleMetricCpuTemp: _toggleMetricCpuTemp,
          onToggleMetricCpuUsage: _toggleMetricCpuUsage,
          onToggleMetricRam: _toggleMetricRam,
          onToggleMetricBattery: _toggleMetricBattery,
          onToggleMetricFan: _toggleMetricFan,
          getItemKey: _getItemKey,
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
          getItemKey: _getItemKey,
        );
      case 3:
        return SettingsTab(
          scrollController: _scrollController,
          focusedIndex: _focusedIndex,
          autoStartEnabled: _autoStartEnabled,
          onToggleAutoStart: _toggleAutoStart,
          onVirtualKeyboard: () async {
            await OverlayController.instance.hideOverlay();
            VirtualKeyboardService.toggleKeyboard();
          },
          onTaskManager: () {
            OverlayController.instance.hideOverlay();
            BridgeService.instance.launchTaskManager();
          },
          onDisplaySettings: () {
            OverlayController.instance.hideOverlay();
            BridgeService.instance.launchDisplaySettings();
          },
          onTrimMemory: () {
            SystemOptimizer.trimMemory();
          },
          onClosePanel: () => OverlayController.instance.hideOverlay(),
          isRtssRunning: _isRtssRunning,
          activeGame: _activeGame,
          isTdpHardwareActive: _tdpCtrl.isAvailable(),
          isHvciBlocked: _tdpCtrl.isHvciBlocked(),
          isZBandActive: true,
          isGamepadConnected: GamepadService.isConnected,
          overlayHotkeyDevice: _overlayHotkeyDevice,
          overlayHotkey: _overlayHotkey,
          onOverlayHotkeyChanged: _updateOverlayHotkey,
          virtualKeyboardHotkeyDevice: _virtualKeyboardHotkeyDevice,
          virtualKeyboardHotkey: _virtualKeyboardHotkey,
          onVirtualKeyboardHotkeyChanged: _updateVirtualKeyboardHotkey,
          scale: _scale,
          onScaleChanged: _updateScale,
          widthPercent: _widthPercent,
          onWidthPercentChanged: _updateWidthPercent,
          getItemKey: _getItemKey,
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
