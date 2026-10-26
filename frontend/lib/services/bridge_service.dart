import 'dart:async';
import 'dart:convert';
import 'dart:io' show exit;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/logger.dart';
import 'overlay_controller.dart';
import 'system_telemetry_service.dart';
import '../input/gamepad_service.dart';

/// Real-time WebSocket bridge service connecting the Flutter Desktop UI
/// with the Python (PySide6) system backend.
class BridgeService {
  static const _logger = AppLogger('BridgeService');
  static final BridgeService instance = BridgeService._();

  BridgeService._();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _mockTimer;
  Timer? _orphanTimer;

  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final StreamController<SystemTelemetryData> _telemetryController =
      StreamController<SystemTelemetryData>.broadcast();
  final StreamController<Map<String, dynamic>> _hotkeyEventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<SystemTelemetryData> get telemetryStream => _telemetryController.stream;
  Stream<Map<String, dynamic>> get hotkeyEventsStream => _hotkeyEventsController.stream;

  // Hardware states synchronized from the backend
  final ValueNotifier<int> tdp = ValueNotifier<int>(15);
  final ValueNotifier<int> fanSpeed = ValueNotifier<int>(50);
  final ValueNotifier<bool> isFanAuto = ValueNotifier<bool>(true);
  final ValueNotifier<String> fanProfile = ValueNotifier<String>('balanced');
  final ValueNotifier<List<List<int>>> fanCurve = ValueNotifier<List<List<int>>>(const [
    [40, 30],
    [50, 42],
    [60, 58],
    [70, 75],
    [80, 90],
    [85, 100],
  ]);
  final ValueNotifier<int> volume = ValueNotifier<int>(50);
  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  final ValueNotifier<int> brightness = ValueNotifier<int>(70);
  final ValueNotifier<bool> isTouchEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> autostart = ValueNotifier<bool>(false);
  final ValueNotifier<int> panelWidth = ValueNotifier<int>(420);
  final ValueNotifier<double> panelScale = ValueNotifier<double>(1.0);
  final ValueNotifier<Map<String, dynamic>> config = ValueNotifier<Map<String, dynamic>>({});

  Future<void> init() async {
    _connect();
  }

  void _connect() {
    try {
      _logger.info('Connecting to WebSocket server at ws://127.0.0.1:8765...');
      final uri = Uri.parse('ws://127.0.0.1:8765');
      _channel = WebSocketChannel.connect(uri);

      // Catch channel.ready future to avoid unhandled exception on handshake failure
      _channel!.ready.then((_) {
        _logger.info('WebSocket channel connection established.');
      }).catchError((error) {
        _logger.warning('WebSocket connection handshake failed: $error');
        _onDisconnected();
      });

      _channel!.stream.listen(
        (message) {
          if (!isConnected.value) {
            isConnected.value = true;
            _stopMockTimer();
            _cancelOrphanTimer();
            _logger.info('Connected successfully to Python WebSocket Server.');
          }
          _handleMessage(message.toString());
        },
        onError: (error) {
          _logger.warning('WebSocket stream error: $error');
          _onDisconnected();
        },
        onDone: () {
          _logger.info('WebSocket connection closed.');
          _onDisconnected();
        },
      );
    } catch (e) {
      _logger.warning('Could not open WebSocket connection: $e');
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    isConnected.value = false;
    _channel = null;
    _startMockTimer();
    _startOrphanTimer();

    // Automatically reconnect after 2 seconds
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!isConnected.value) {
        _connect();
      }
    });
  }

  /// Kills the UI process when the Python host is gone, so a stale window can
  /// never stay on screen as an invisible/transparent overlay.
  void _startOrphanTimer() {
    // Reconnect attempts call _onDisconnected repeatedly; keep the first
    // deadline instead of pushing it forward on every failed retry.
    if (_orphanTimer?.isActive ?? false) return;
    _orphanTimer = Timer(const Duration(seconds: 10), () {
      if (!isConnected.value) {
        _logger.warning('Backend unavailable for 10s; exiting UI to avoid an orphan overlay window.');
        exit(0);
      }
    });
  }

  void _cancelOrphanTimer() {
    _orphanTimer?.cancel();
    _orphanTimer = null;
  }

  void _handleMessage(String rawJson) {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = map['type'] as String?;
      final data = map['data'] as Map<String, dynamic>?;

      if (data == null) return;

      if (type == 'init') {
        _parseInitialState(data);
      } else if (type == 'telemetry') {
        _parseTelemetry(data);
      } else if (type == 'config') {
        config.value = data;
      } else if (type == 'visibility') {
        final visible = (data['visible'] as bool?) ?? false;
        OverlayController.instance.setVisibilityFromBackend(visible);
      } else if (type == 'hotkeyProgress' || type == 'hotkeyCaptured' || type == 'hotkeyCancelled') {
        _hotkeyEventsController.add({
          'type': type,
          'target': data['target'],
          'device': data['device'],
          'hotkey': data['hotkey'],
          'isDone': data['isDone'],
        });
      } else if (type == 'gamepadButton') {
        final btn = data['button'] as String?;
        if (btn != null && btn.isNotEmpty) {
          GamepadService.dispatchButton(btn);
        }
      }
    } catch (e) {
      _logger.error('Failed to parse WebSocket packet: $e');
    }
  }

  void _parseInitialState(Map<String, dynamic> data) {
    final cfg = data['config'] as Map<String, dynamic>?;
    if (cfg != null) {
      config.value = cfg;
    }

    final hw = data['hardware'] as Map<String, dynamic>?;
    if (hw != null) {
      tdp.value = (hw['tdp'] as num?)?.toInt() ?? 15;
      fanSpeed.value = (hw['fan'] as num?)?.toInt() ?? 50;
      isFanAuto.value = (hw['fan_auto'] as bool?) ?? true;
      volume.value = (hw['volume'] as num?)?.toInt() ?? 50;
      isMuted.value = (hw['is_muted'] as bool?) ?? false;
      brightness.value = (hw['brightness'] as num?)?.toInt() ?? 70;
      isTouchEnabled.value = (hw['touch_enabled'] as bool?) ?? true;
      autostart.value = (hw['autostart'] as bool?) ?? false;
      if (hw.containsKey('fan_profile')) {
        fanProfile.value = hw['fan_profile'].toString();
      }
      if (hw.containsKey('fan_curve') && hw['fan_curve'] is List) {
        fanCurve.value = (hw['fan_curve'] as List)
            .map((item) => [(item[0] as num).toInt(), (item[1] as num).toInt()])
            .toList();
      }
    }

    final telem = data['telemetry'] as Map<String, dynamic>?;
    if (telem != null) {
      _parseTelemetry(telem);
    }
  }

  void _parseTelemetry(Map<String, dynamic> data) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final batteryPct = (data['battery_percent'] as num?)?.toInt() ?? 100;
    final isCharging = (data['is_charging'] as bool?) ?? false;
    final cpuUsage = ((data['cpu_usage'] ?? data['cpu_percent']) as num?)?.toInt() ?? 0;
    final ramUsed = ((data['ram_used_gb'] as num?) ?? 0.0).toDouble();
    final ramTotal = ((data['ram_total_gb'] as num?) ?? 16.0).toDouble();
    final ramPct = ((data['ram_usage_percent'] ?? data['ram_percent']) as num?)?.toInt() ?? 0;
    final cpuTemp = (data['cpu_temp'] as num?)?.toInt();
    final liveTdp = data['live_tdp'] != null ? (data['live_tdp'] as num).toInt() : null;
    final isTdpHardwareActive = data['is_tdp_hardware_active'] as bool? ?? false;
    final isHvciBlocked = data['is_hvci_blocked'] as bool? ?? false;

    // Synchronize hardware states included in telemetry snapshots
    if (data.containsKey('is_touch_enabled')) {
      isTouchEnabled.value = data['is_touch_enabled'] as bool;
    }
    if (data.containsKey('is_fan_auto')) {
      isFanAuto.value = data['is_fan_auto'] as bool;
    }
    if (data.containsKey('fan_profile')) {
      fanProfile.value = data['fan_profile'].toString();
    }
    if (data.containsKey('fan_curve') && data['fan_curve'] is List) {
      fanCurve.value = (data['fan_curve'] as List)
          .map((item) => [(item[0] as num).toInt(), (item[1] as num).toInt()])
          .toList();
    }
    if (data.containsKey('fan_speed')) {
      fanSpeed.value = (data['fan_speed'] as num).toInt();
    }
    if (data.containsKey('volume')) {
      volume.value = (data['volume'] as num).toInt();
    }
    if (data.containsKey('brightness')) {
      brightness.value = (data['brightness'] as num).toInt();
    }

    final batterySecsLeft = data['battery_secs_left'] != null
        ? (data['battery_secs_left'] as num).toInt()
        : null;

    final telemData = SystemTelemetryData(
      timeString: timeStr,
      dateString: dateStr,
      batteryPercent: batteryPct,
      batterySecsLeft: batterySecsLeft,
      hasBattery: true,
      isCharging: isCharging,
      isAcOnline: isCharging,
      cpuUsagePercent: cpuUsage,
      cpuName: 'AMD Ryzen Processor',
      ramUsedGb: ramUsed,
      ramTotalGb: ramTotal,
      ramUsagePercent: ramPct,
      cpuTemp: cpuTemp,
      liveTdp: liveTdp,
      liveFan: (data['live_fan'] ?? data['fan_speed'] ?? fanSpeed.value) as int,
      liveFps: data['live_fps'] != null ? (data['live_fps'] as num).toInt() : null,
      activeGame: data['active_game'] as String?,
      isTdpHardwareActive: isTdpHardwareActive,
      isHvciBlocked: isHvciBlocked,
    );

    _telemetryController.add(telemData);
  }

  void installRtss() {
    _send({'action': 'installRtss'});
  }

  /// Sends an action command to the Python Backend over WebSocket.
  void _send(Map<String, dynamic> payload) {
    if (isConnected.value && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(payload));
      } catch (e) {
        _logger.error('Failed to send packet to backend: $e');
      }
    } else {
      _logger.info('[MOCK SEND] $payload');
    }
  }

  // --- Hardware control API methods ---

  void setTdp(int watts) {
    tdp.value = watts;
    _send({'action': 'setTdp', 'watts': watts});
  }

  void setFan(int percent, bool isAuto) {
    fanSpeed.value = percent;
    isFanAuto.value = isAuto;
    _send({'action': 'setFan', 'percent': percent, 'is_auto': isAuto});
  }

  void setFanCurve(String profile, [List<List<int>>? curve]) {
    fanProfile.value = profile;
    if (curve != null) {
      fanCurve.value = curve;
    }
    _send({'action': 'setFanCurve', 'profile': profile, 'curve': curve});
  }

  void setVolume(int percent) {
    volume.value = percent;
    _send({'action': 'setVolume', 'percent': percent});
  }

  void toggleMute() {
    isMuted.value = !isMuted.value;
    _send({'action': 'toggleMute'});
  }

  void setBrightness(int percent) {
    brightness.value = percent;
    _send({'action': 'setBrightness', 'percent': percent});
  }

  void toggleTouchscreen() {
    isTouchEnabled.value = !isTouchEnabled.value;
    _send({'action': 'toggleTouchscreen'});
  }

  void toggleVirtualKeyboard() {
    _send({'action': 'toggleVirtualKeyboard'});
  }

  void setFpsLimit(int limit) {
    _send({'action': 'setFpsLimit', 'limit': limit});
  }

  void updateOsdText(String text) {
    _send({'action': 'updateOsdText', 'text': text});
  }

  void clearOsdText() {
    _send({'action': 'clearOsdText'});
  }

  void setOsdMetric(String metric, bool enabled) {
    _send({'action': 'setOsdMetric', 'metric': metric, 'enabled': enabled});
  }

  void setPanelWidth(int width) {
    panelWidth.value = width;
    _send({'action': 'setPanelWidth', 'width': width});
  }

  void setPanelScale(double scale) {
    panelScale.value = scale;
    _send({'action': 'setPanelScale', 'scale': scale});
  }

  void setAutostart(bool enabled) {
    autostart.value = enabled;
    _send({'action': 'setAutostart', 'enabled': enabled});
  }

  void setHotkey(String target, String hotkey, [String device = 'keyboard']) {
    _send({
      'action': 'setHotkey',
      'target': target,
      'hotkey': hotkey,
      'device': device,
    });
  }

  void bringToFront() {
    _send({'action': 'bringToFront'});
  }

  void closeOverlay() {
    _send({'action': 'closeOverlay'});
  }

  void exitApp() {
    _send({'action': 'exitApp'});
  }

  void launchTaskManager() {
    _send({'action': 'launchTaskManager'});
  }

  void launchDisplaySettings() {
    _send({'action': 'launchDisplaySettings'});
  }

  void trimMemory() {
    _send({'action': 'trimMemory'});
  }

  void startCaptureHotkey(String target) {
    _send({'action': 'startCaptureHotkey', 'target': target});
  }

  void cancelCaptureHotkey() {
    _send({'action': 'cancelCaptureHotkey'});
  }

  // --- Standalone Mock Telemetry Mode ---
  void _startMockTimer() {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

      final mockData = SystemTelemetryData(
        timeString: timeStr,
        dateString: dateStr,
        batteryPercent: 88,
        batterySecsLeft: 5400,
        hasBattery: true,
        isCharging: false,
        isAcOnline: false,
        cpuUsagePercent: 24,
        cpuName: 'AMD Ryzen 7 7840U',
        ramUsedGb: 5.8,
        ramTotalGb: 16.0,
        ramUsagePercent: 36,
        cpuTemp: 52,
        liveTdp: 15,
        liveFan: 45,
      );

      _telemetryController.add(mockData);
    });
  }

  void _stopMockTimer() {
    _mockTimer?.cancel();
    _mockTimer = null;
  }
}
