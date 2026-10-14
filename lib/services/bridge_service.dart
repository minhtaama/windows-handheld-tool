import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/logger.dart';
import 'system_telemetry_service.dart';

/// Dịch vụ cầu nối WebSocket giao tiếp thời gian thực giữa giao diện Flutter Web
/// và tiến trình dịch vụ hệ thống Python (PySide6 Backend).
class BridgeService {
  static const _logger = AppLogger('BridgeService');
  static final BridgeService instance = BridgeService._();

  BridgeService._();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _mockTimer;

  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final StreamController<SystemTelemetryData> _telemetryController =
      StreamController<SystemTelemetryData>.broadcast();

  Stream<SystemTelemetryData> get telemetryStream => _telemetryController.stream;

  // Trạng thái phần cứng phản ánh từ backend
  final ValueNotifier<int> tdp = ValueNotifier<int>(15);
  final ValueNotifier<int> fanSpeed = ValueNotifier<int>(50);
  final ValueNotifier<bool> isFanAuto = ValueNotifier<bool>(true);
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
      _logger.info('Đang kết nối WebSocket tới ws://127.0.0.1:8765...');
      final uri = Uri.parse('ws://127.0.0.1:8765');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) {
          if (!isConnected.value) {
            isConnected.value = true;
            _stopMockTimer();
            _logger.info('Đã kết nối thành công tới Python WebSocket Server.');
          }
          _handleMessage(message.toString());
        },
        onError: (error) {
          _logger.warning('Lỗi WebSocket stream: $error');
          _onDisconnected();
        },
        onDone: () {
          _logger.info('WebSocket đã đóng kết nối.');
          _onDisconnected();
        },
      );
    } catch (e) {
      _logger.warning('Không thể mở kết nối WebSocket: $e');
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    isConnected.value = false;
    _channel = null;
    _startMockTimer();

    // Tự động kết nối lại sau 2 giây
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!isConnected.value) {
        _connect();
      }
    });
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
      }
    } catch (e) {
      _logger.error('Lỗi phân tích cú pháp gói tin WS: $e');
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
    final cpuUsage = (data['cpu_usage'] as num?)?.toInt() ?? 0;
    final ramUsed = ((data['ram_used_gb'] as num?) ?? 0.0).toDouble();
    final ramTotal = ((data['ram_total_gb'] as num?) ?? 16.0).toDouble();
    final ramPct = ((data['ram_usage_percent'] as num?) ?? 0).toInt();

    // Đồng bộ lại các trạng thái phần cứng nếu có gửi kèm trong telemetry
    if (data.containsKey('is_touch_enabled')) {
      isTouchEnabled.value = data['is_touch_enabled'] as bool;
    }
    if (data.containsKey('is_fan_auto')) {
      isFanAuto.value = data['is_fan_auto'] as bool;
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

    final telemData = SystemTelemetryData(
      timeString: timeStr,
      dateString: dateStr,
      batteryPercent: batteryPct,
      hasBattery: true,
      isCharging: isCharging,
      isAcOnline: isCharging,
      cpuUsagePercent: cpuUsage,
      cpuName: 'AMD Ryzen Processor',
      ramUsedGb: ramUsed,
      ramTotalGb: ramTotal,
      ramUsagePercent: ramPct,
      cpuTemp: (data['cpu_temp'] as num?)?.toInt() ?? 45,
    );

    _telemetryController.add(telemData);
  }

  /// Gửi lệnh thao tác sang Python Backend qua WebSocket
  void _send(Map<String, dynamic> payload) {
    if (isConnected.value && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(payload));
      } catch (e) {
        _logger.error('Lỗi khi gửi gói tin sang backend: $e');
      }
    } else {
      _logger.info('[MOCK SEND] $payload');
    }
  }

  // --- Các hàm API điều khiển phần cứng ---

  void setTdp(int watts) {
    tdp.value = watts;
    _send({'action': 'setTdp', 'watts': watts});
  }

  void setFan(int percent, bool isAuto) {
    fanSpeed.value = percent;
    isFanAuto.value = isAuto;
    _send({'action': 'setFan', 'percent': percent, 'is_auto': isAuto});
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

  void setHotkey(String target, String hotkey) {
    _send({
      'action': 'setHotkey',
      'target': target,
      'hotkey': hotkey,
    });
  }

  void closeOverlay() {
    _send({'action': 'closeOverlay'});
  }

  void exitApp() {
    _send({'action': 'exitApp'});
  }

  // --- Chế độ giả lập khi chạy độc lập trên Chrome (Mock Data) ---
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
        hasBattery: true,
        isCharging: false,
        isAcOnline: false,
        cpuUsagePercent: 24,
        cpuName: 'AMD Ryzen 7 7840U',
        ramUsedGb: 5.8,
        ramTotalGb: 16.0,
        ramUsagePercent: 36,
        cpuTemp: 52,
      );

      _telemetryController.add(mockData);
    });
  }

  void _stopMockTimer() {
    _mockTimer?.cancel();
    _mockTimer = null;
  }
}
