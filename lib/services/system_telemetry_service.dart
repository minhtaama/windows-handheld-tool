import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import '../core/logger.dart';

// 1. Cấu trúc Win32 SYSTEM_POWER_STATUS
final class SystemPowerStatus extends Struct {
  @Uint8()
  external int acLineStatus;
  @Uint8()
  external int batteryFlag;
  @Uint8()
  external int batteryLifePercent;
  @Uint8()
  external int systemStatusFlag;
  @Uint32()
  external int batteryLifeTime;
  @Uint32()
  external int batteryFullLifeTime;
}

typedef _GetSystemPowerStatusC = Int32 Function(Pointer<SystemPowerStatus> lpSystemPowerStatus);
typedef _GetSystemPowerStatusDart = int Function(Pointer<SystemPowerStatus> lpSystemPowerStatus);

// 2. Cấu trúc Win32 MEMORYSTATUSEX
final class MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

typedef _GlobalMemoryStatusExC = Int32 Function(Pointer<MemoryStatusEx> lpBuffer);
typedef _GlobalMemoryStatusExDart = int Function(Pointer<MemoryStatusEx> lpBuffer);

// 3. Cấu trúc Win32 FILETIME & GetSystemTimes cho CPU
final class FileTime extends Struct {
  @Uint32()
  external int dwLowDateTime;
  @Uint32()
  external int dwHighDateTime;
}

typedef _GetSystemTimesC = Int32 Function(
  Pointer<FileTime> lpIdleTime,
  Pointer<FileTime> lpKernelTime,
  Pointer<FileTime> lpUserTime,
);
typedef _GetSystemTimesDart = int Function(
  Pointer<FileTime> lpIdleTime,
  Pointer<FileTime> lpKernelTime,
  Pointer<FileTime> lpUserTime,
);

// 4. Các hàm định dạng Thời gian & Ngày tháng chuẩn Windows Locale
typedef _GetTimeFormatWC = Int32 Function(
  Uint32 locale,
  Uint32 dwFlags,
  Pointer<Void> lpTime,
  Pointer<Utf16> lpFormat,
  Pointer<Utf16> lpTimeStr,
  Int32 cchTime,
);
typedef _GetTimeFormatWDart = int Function(
  int locale,
  int dwFlags,
  Pointer<Void> lpTime,
  Pointer<Utf16> lpFormat,
  Pointer<Utf16> lpTimeStr,
  int cchTime,
);

typedef _GetDateFormatWC = Int32 Function(
  Uint32 locale,
  Uint32 dwFlags,
  Pointer<Void> lpDate,
  Pointer<Utf16> lpFormat,
  Pointer<Utf16> lpDateStr,
  Int32 cchDate,
);
typedef _GetDateFormatWDart = int Function(
  int locale,
  int dwFlags,
  Pointer<Void> lpDate,
  Pointer<Utf16> lpFormat,
  Pointer<Utf16> lpDateStr,
  int cchDate,
);

/// Dữ liệu đo đạc tài nguyên hệ thống tức thời
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
      cpuName: 'Processor',
      ramUsedGb: 0.0,
      ramTotalGb: 0.0,
      ramUsagePercent: 0,
    );
  }
}

/// Dịch vụ thu thập thông số hệ thống Windows: Giờ chuẩn cài đặt Windows, Pin, CPU và RAM.
/// Vận hành hoàn toàn qua Win32 API FFI trực tiếp (First Principles) không gây overhead CPU.
class SystemTelemetryService {
  static const _logger = AppLogger('SystemTelemetryService');
  static final SystemTelemetryService instance = SystemTelemetryService._();

  SystemTelemetryService._() {
    _initFfi();
    _initCpuName();
  }

  bool _initialized = false;
  late final _GetSystemPowerStatusDart _getPowerStatus;
  late final _GlobalMemoryStatusExDart _getMemStatus;
  late final _GetSystemTimesDart _getSystemTimes;
  late final _GetTimeFormatWDart _getTimeFormat;
  late final _GetDateFormatWDart _getDateFormat;

  // Bộ đệm bộ nhớ dùng lại để tránh cấp phát lặp lại trong chu kỳ đo 1s
  late final Pointer<SystemPowerStatus> _powerBuffer;
  late final Pointer<MemoryStatusEx> _memBuffer;
  late final Pointer<FileTime> _idleTimeBuffer;
  late final Pointer<FileTime> _kernelTimeBuffer;
  late final Pointer<FileTime> _userTimeBuffer;
  late final Pointer<Utf16> _timeStringBuffer;
  late final Pointer<Utf16> _dateStringBuffer;

  int _prevIdle = 0;
  int _prevKernel = 0;
  int _prevUser = 0;
  bool _hasPrevCpuSample = false;
  int _cachedCpuUsage = 0;

  String _cachedCpuName = 'Processor';

  void _initFfi() {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _getPowerStatus = kernel32.lookupFunction<_GetSystemPowerStatusC, _GetSystemPowerStatusDart>('GetSystemPowerStatus');
      _getMemStatus = kernel32.lookupFunction<_GlobalMemoryStatusExC, _GlobalMemoryStatusExDart>('GlobalMemoryStatusEx');
      _getSystemTimes = kernel32.lookupFunction<_GetSystemTimesC, _GetSystemTimesDart>('GetSystemTimes');
      _getTimeFormat = kernel32.lookupFunction<_GetTimeFormatWC, _GetTimeFormatWDart>('GetTimeFormatW');
      _getDateFormat = kernel32.lookupFunction<_GetDateFormatWC, _GetDateFormatWDart>('GetDateFormatW');

      _powerBuffer = calloc<SystemPowerStatus>();
      _memBuffer = calloc<MemoryStatusEx>();
      _idleTimeBuffer = calloc<FileTime>();
      _kernelTimeBuffer = calloc<FileTime>();
      _userTimeBuffer = calloc<FileTime>();
      _timeStringBuffer = calloc<Uint16>(64).cast<Utf16>();
      _dateStringBuffer = calloc<Uint16>(64).cast<Utf16>();

      _initialized = true;
      _logger.info('Khởi tạo thành công Win32 Telemetry FFI');
    } catch (e) {
      _logger.error('Lỗi khi nạp Win32 API kernel32.dll', e);
    }
  }

  void _initCpuName() {
    try {
      final result = Process.runSync('reg', [
        'query',
        r'HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0',
        '/v',
        'ProcessorNameString',
      ]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'\r?\n'));
        for (final line in lines) {
          if (line.contains('ProcessorNameString')) {
            final parts = line.split(RegExp(r'\s+REG_SZ\s+'));
            if (parts.length >= 2) {
              _cachedCpuName = parts[1].trim();
              break;
            }
          }
        }
      }
    } catch (_) {}
  }

  int _fileTimeToU64(FileTime ft) {
    return (ft.dwHighDateTime << 32) | (ft.dwLowDateTime & 0xFFFFFFFF);
  }

  /// Thu thập ảnh chụp (Snapshot) tài nguyên hệ thống tức thời
  SystemTelemetryData getSnapshot() {
    if (!_initialized) {
      return SystemTelemetryData.initial();
    }

    // 1. Đọc Thời gian & Ngày tháng theo Locale & Setting người dùng của Windows
    String timeStr = '--:--';
    String dateStr = '--/--/----';
    try {
      // 0x0400 = LOCALE_USER_DEFAULT
      final tRes = _getTimeFormat(0x0400, 0, nullptr, nullptr, _timeStringBuffer, 64);
      if (tRes > 0) {
        timeStr = _timeStringBuffer.toDartString();
      }
      final dRes = _getDateFormat(0x0400, 0, nullptr, nullptr, _dateStringBuffer, 64);
      if (dRes > 0) {
        dateStr = _dateStringBuffer.toDartString();
      }
    } catch (_) {}

    // 2. Đọc Thông tin Pin & Trạng thái sạc
    int? batteryPercent;
    bool hasBattery = false;
    bool isCharging = false;
    bool isAcOnline = true;

    try {
      final pRes = _getPowerStatus(_powerBuffer);
      if (pRes != 0) {
        final rawPercent = _powerBuffer.ref.batteryLifePercent;
        final acStatus = _powerBuffer.ref.acLineStatus;
        final flag = _powerBuffer.ref.batteryFlag;

        isAcOnline = (acStatus == 1);
        // Cờ 8 là BATTERY_FLAG_CHARGING
        isCharging = (flag & 8) != 0 || (isAcOnline && rawPercent < 100);

        // Cờ 128 là BATTERY_FLAG_NO_BATTERY, 255 là giá trị không xác định (máy bàn)
        if (flag != 128 && rawPercent != 255) {
          hasBattery = true;
          batteryPercent = rawPercent.clamp(0, 100);
        }
      }
    } catch (_) {}

    // 3. Đọc Bộ nhớ RAM
    double ramUsedGb = 0.0;
    double ramTotalGb = 0.0;
    int ramUsagePercent = 0;

    try {
      _memBuffer.ref.dwLength = sizeOf<MemoryStatusEx>();
      final mRes = _getMemStatus(_memBuffer);
      if (mRes != 0) {
        ramUsagePercent = _memBuffer.ref.dwMemoryLoad;
        final totalBytes = _memBuffer.ref.ullTotalPhys;
        final availBytes = _memBuffer.ref.ullAvailPhys;
        ramTotalGb = totalBytes / (1024 * 1024 * 1024);
        ramUsedGb = (totalBytes - availBytes) / (1024 * 1024 * 1024);
      }
    } catch (_) {}

    // 4. Đo Tỷ lệ % Tải CPU (CPU Usage) qua GetSystemTimes
    try {
      final cRes = _getSystemTimes(_idleTimeBuffer, _kernelTimeBuffer, _userTimeBuffer);
      if (cRes != 0) {
        final currIdle = _fileTimeToU64(_idleTimeBuffer.ref);
        final currKernel = _fileTimeToU64(_kernelTimeBuffer.ref);
        final currUser = _fileTimeToU64(_userTimeBuffer.ref);

        if (_hasPrevCpuSample) {
          final idleDelta = currIdle - _prevIdle;
          final kernelDelta = currKernel - _prevKernel;
          final userDelta = currUser - _prevUser;

          final total = kernelDelta + userDelta;
          final active = total - idleDelta;

          if (total > 0 && active >= 0) {
            _cachedCpuUsage = (active * 100 / total).clamp(0, 100).round();
          }
        }

        _prevIdle = currIdle;
        _prevKernel = currKernel;
        _prevUser = currUser;
        _hasPrevCpuSample = true;
      }
    } catch (_) {}

    return SystemTelemetryData(
      timeString: timeStr,
      dateString: dateStr,
      batteryPercent: batteryPercent,
      hasBattery: hasBattery,
      isCharging: isCharging,
      isAcOnline: isAcOnline,
      cpuUsagePercent: _cachedCpuUsage,
      cpuName: _cachedCpuName,
      ramUsedGb: ramUsedGb,
      ramTotalGb: ramTotalGb,
      ramUsagePercent: ramUsagePercent,
    );
  }

  void dispose() {
    if (_initialized) {
      calloc.free(_powerBuffer);
      calloc.free(_memBuffer);
      calloc.free(_idleTimeBuffer);
      calloc.free(_kernelTimeBuffer);
      calloc.free(_userTimeBuffer);
      calloc.free(_timeStringBuffer);
      calloc.free(_dateStringBuffer);
      _initialized = false;
    }
  }
}
