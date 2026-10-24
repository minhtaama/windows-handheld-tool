import 'dart:async';
import 'bridge_service.dart';

/// Chứa dữ liệu đo đạc tài nguyên hệ thống trong chu kỳ 1 giây.
class SystemTelemetryData {
  final String timeString;
  final String dateString;
  final int? batteryPercent;
  final bool hasBattery;
  final bool isCharging;
  final bool isAcOnline;
  final int cpuUsagePercent;
  final String cpuName;
  final double ramUsedGb;
  final double ramTotalGb;
  final int ramUsagePercent;
  final int? cpuTemp;
  final int? liveTdp;
  final int liveFan;
  final int? liveFps;
  final String? activeGame;
  final bool isTdpHardwareActive;
  final bool isHvciBlocked;

  const SystemTelemetryData({
    required this.timeString,
    required this.dateString,
    required this.batteryPercent,
    required this.hasBattery,
    required this.isCharging,
    required this.isAcOnline,
    required this.cpuUsagePercent,
    required this.cpuName,
    required this.ramUsedGb,
    required this.ramTotalGb,
    required this.ramUsagePercent,
    this.cpuTemp,
    this.liveTdp,
    this.liveFan = 50,
    this.liveFps,
    this.activeGame,
    this.isTdpHardwareActive = false,
    this.isHvciBlocked = false,
  });

  factory SystemTelemetryData.initial() {
    return const SystemTelemetryData(
      timeString: '--:--',
      dateString: '--/--/----',
      batteryPercent: null,
      hasBattery: false,
      isCharging: false,
      isAcOnline: true,
      cpuUsagePercent: 0,
      cpuName: 'AMD Ryzen Processor',
      ramUsedGb: 0.0,
      ramTotalGb: 16.0,
      ramUsagePercent: 0,
      cpuTemp: null,
      liveTdp: null,
      liveFan: 50,
      liveFps: null,
      activeGame: null,
      isTdpHardwareActive: false,
      isHvciBlocked: false,
    );
  }
}

/// Dịch vụ thu thập thông số hệ thống Windows: Giờ, Pin, CPU, RAM và Nhiệt độ.
/// Trong mô hình Web, dữ liệu được truyền từ dịch vụ Python thông qua BridgeService.
class SystemTelemetryService {
  static final SystemTelemetryService instance = SystemTelemetryService._();

  SystemTelemetryService._() {
    BridgeService.instance.telemetryStream.listen((data) {
      _latest = data;
    });
  }

  SystemTelemetryData _latest = SystemTelemetryData.initial();
  SystemTelemetryData get latest => _latest;

  SystemTelemetryData getSnapshot() => _latest;

  Stream<SystemTelemetryData> get telemetryStream => BridgeService.instance.telemetryStream;

  void dispose() {}
}
