import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';
import 'hardware_base.dart';

typedef _SetDllDirectoryC = Int32 Function(Pointer<Utf16> lpPathName);
typedef _SetDllDirectoryDart = int Function(Pointer<Utf16> lpPathName);

typedef _InitRyzenAdjC = Pointer<Void> Function();
typedef _InitRyzenAdjDart = Pointer<Void> Function();

typedef _SetLimitC = Int32 Function(Pointer<Void> handle, Uint32 value);
typedef _SetLimitDart = int Function(Pointer<Void> handle, int value);

typedef _TableOpC = Int32 Function(Pointer<Void> handle);
typedef _TableOpDart = int Function(Pointer<Void> handle);

typedef _GetFloatValueC = Float Function(Pointer<Void> handle);
typedef _GetFloatValueDart = double Function(Pointer<Void> handle);

/// Điều khiển TDP cho CPU/APU Handheld (AMD APU qua RyzenAdj DLL).
class TdpController extends HardwareController {
  static const _logger = AppLogger('TdpControl');

  int _currentTdp;
  DynamicLibrary? _ryzenDll;
  Pointer<Void>? _ryzenHandle;
  bool _isHardwareActive = false;

  _SetLimitDart? _setStapmLimit;
  _SetLimitDart? _setFastLimit;
  _SetLimitDart? _setSlowLimit;

  _TableOpDart? _initTable;
  _TableOpDart? _refreshTable;
  _GetFloatValueDart? _getStapmValue;
  _GetFloatValueDart? _getFastValue;
  _GetFloatValueDart? _getSlowValue;
  _GetFloatValueDart? _getTctlTempValue;

  TdpController({
    super.minVal = 5,
    super.maxVal = 35,
    super.step = 1,
    int defaultVal = 15,
  })  : _currentTdp = defaultVal,
        super(
          name: "TDP",
          unit: "W",
        ) {
    _initRyzenAdj();
  }

  /// Tự động đồng bộ các tệp driver giữa thư mục bin và thư mục gốc của tệp thực thi.
  /// Thư viện WinRing0 yêu cầu tệp WinRing0x64.sys nằm cùng thư mục với tiến trình gọi chính (GetModuleFileName).
  void _ensureDriversSynchronized(String exeDir) {
    try {
      final binDir = '$exeDir\\bin';
      final criticalFiles = [
        'WinRing0x64.sys',
        'WinRing0x64.dll',
        'ryzenadj.dll',
        'libryzenadj.dll',
        'inpoutx64.dll',
      ];

      for (final fileName in criticalFiles) {
        final rootFile = File('$exeDir\\$fileName');
        final binFile = File('$binDir\\$fileName');

        // Nếu có trong bin mà chưa có ngoài root, tự động copy ra root
        if (binFile.existsSync() && !rootFile.existsSync()) {
          binFile.copySync(rootFile.path);
          _logger.info('Tự động đồng bộ driver $fileName ra thư mục gốc thực thi.');
        }
        // Nếu có ngoài root mà chưa có trong bin, tự động copy vào bin
        else if (rootFile.existsSync() && !binFile.existsSync()) {
          if (!Directory(binDir).existsSync()) {
            Directory(binDir).createSync(recursive: true);
          }
          rootFile.copySync(binFile.path);
          _logger.info('Tự động đồng bộ driver $fileName vào thư mục bin.');
        }
      }
    } catch (e) {
      _logger.warning('Lỗi khi tự động đồng bộ tệp driver: $e');
    }
  }

  void _initRyzenAdj() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _ensureDriversSynchronized(exeDir);

    final candidatePaths = [
      '$exeDir\\ryzenadj.dll',
      '$exeDir\\libryzenadj.dll',
      '$exeDir\\bin\\ryzenadj.dll',
      '$exeDir\\bin\\libryzenadj.dll',
      'bin/ryzenadj.dll',
      'bin/libryzenadj.dll',
      'lib/ryzenadj.dll',
      'ryzenadj.dll',
      'libryzenadj.dll',
      r'C:\Program Files\RyzenAdj\ryzenadj.dll',
      r'C:\Program Files\RyzenAdj\libryzenadj.dll',
    ];

    String? foundPath;
    for (final p in candidatePaths) {
      if (File(p).existsSync()) {
        foundPath = p;
        break;
      }
    }

    if (foundPath != null) {
      try {
        final absPath = File(foundPath).absolute.path;
        final dirPath = File(absPath).parent.path;

        // Bổ sung cả thư mục chứa DLL và thư mục gốc thực thi vào danh sách tìm kiếm DLL của Windows
        try {
          final kernel32 = DynamicLibrary.open('kernel32.dll');
          final setDllDirectory = kernel32
              .lookupFunction<_SetDllDirectoryC, _SetDllDirectoryDart>(
                'SetDllDirectoryW',
              );
          final dirPtr = dirPath.toNativeUtf16();
          setDllDirectory(dirPtr);
          calloc.free(dirPtr);
        } catch (_) {}

        _ryzenDll = DynamicLibrary.open(absPath);
        final initFunc = _ryzenDll!
            .lookupFunction<_InitRyzenAdjC, _InitRyzenAdjDart>('init_ryzenadj');
        _setStapmLimit = _ryzenDll!
            .lookupFunction<_SetLimitC, _SetLimitDart>('set_stapm_limit');
        _setFastLimit = _ryzenDll!
            .lookupFunction<_SetLimitC, _SetLimitDart>('set_fast_limit');
        _setSlowLimit = _ryzenDll!
            .lookupFunction<_SetLimitC, _SetLimitDart>('set_slow_limit');

        // Nạp các hàm đọc bảng cảm biến đo đạc thời gian thực (PM Table Telemetry)
        try {
          _initTable = _ryzenDll!
              .lookupFunction<_TableOpC, _TableOpDart>('init_table');
          _refreshTable = _ryzenDll!
              .lookupFunction<_TableOpC, _TableOpDart>('refresh_table');
          _getStapmValue = _ryzenDll!
              .lookupFunction<_GetFloatValueC, _GetFloatValueDart>(
                'get_stapm_value',
              );
          _getFastValue = _ryzenDll!
              .lookupFunction<_GetFloatValueC, _GetFloatValueDart>(
                'get_fast_value',
              );
          _getSlowValue = _ryzenDll!
              .lookupFunction<_GetFloatValueC, _GetFloatValueDart>(
                'get_slow_value',
              );
          _getTctlTempValue = _ryzenDll!
              .lookupFunction<_GetFloatValueC, _GetFloatValueDart>(
                'get_tctl_temp_value',
              );
        } catch (e) {
          _logger.warning('Một số hàm đọc PM Table không hỗ trợ trên phiên bản DLL này: $e');
        }

        _ryzenHandle = initFunc();
        if (_ryzenHandle != null && _ryzenHandle != nullptr) {
          _isHardwareActive = true;
          // Khởi tạo bảng cảm biến PM Table trên SMU
          try {
            _initTable?.call(_ryzenHandle!);
          } catch (_) {}

          _logger.info(
            'Khởi tạo thành công kết nối phần cứng RyzenAdj DLL ($absPath) và PM Table.',
          );
        } else {
          _logger.warning(
            'Đã tìm thấy $absPath nhưng không thể mở handle (cần quyền Administrator để nạp Ring 0 Driver). Chuyển sang mô phỏng.',
          );
        }
      } catch (e) {
        _logger.warning(
          'Không thể nạp ryzenadj.dll: $e. Sử dụng chế độ mô phỏng.',
        );
      }
    } else {
      _logger.info(
        'Chưa phát hiện ryzenadj.dll. Hoạt động ở chế độ mô phỏng an toàn.',
      );
    }
  }

  @override
  bool isAvailable() => _isHardwareActive;

  @override
  int getValue() => _currentTdp;

  /// Đọc công suất tiêu thụ thực tế tức thời (Watt) trực tiếp từ bảng cảm biến PM Table của AMD SMU.
  double? getLiveTdp() {
    if (!_isHardwareActive || _ryzenHandle == null || _ryzenHandle == nullptr) {
      return null;
    }
    try {
      final res = _refreshTable?.call(_ryzenHandle!);
      if (res == 0) {
        final stapm = _getStapmValue?.call(_ryzenHandle!);
        if (stapm != null && !stapm.isNaN && stapm > 0 && stapm < 150) {
          return stapm;
        }
        final fast = _getFastValue?.call(_ryzenHandle!);
        if (fast != null && !fast.isNaN && fast > 0 && fast < 150) {
          return fast;
        }
        final slow = _getSlowValue?.call(_ryzenHandle!);
        if (slow != null && !slow.isNaN && slow > 0 && slow < 150) {
          return slow;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Đọc nhiệt độ CPU thực tế (°C) trực tiếp từ cảm biến Tctl của AMD SMU.
  double? getLiveCpuTemp() {
    if (!_isHardwareActive || _ryzenHandle == null || _ryzenHandle == nullptr) {
      return null;
    }
    try {
      final temp = _getTctlTempValue?.call(_ryzenHandle!);
      if (temp != null && !temp.isNaN && temp > 0 && temp < 120) {
        return temp;
      }
    } catch (_) {}
    return null;
  }

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentTdp = target;
    final mw = target * 1000;

    if (_isHardwareActive && _ryzenHandle != null && _ryzenHandle != nullptr) {
      try {
        _setStapmLimit?.call(_ryzenHandle!, mw);
        _setFastLimit?.call(_ryzenHandle!, mw);
        _setSlowLimit?.call(_ryzenHandle!, mw);
        _logger.info('Đã áp dụng TDP phần cứng: $target W ($mw mW).');
        return true;
      } catch (e) {
        _logger.error('Lỗi khi thiết lập TDP qua RyzenAdj DLL', e);
        return false;
      }
    }

    _logger.info('Đã thiết lập TDP (Mô phỏng): $target W.');
    return true;
  }
}
