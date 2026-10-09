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

  void _initRyzenAdj() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidatePaths = [
      'bin/ryzenadj.dll',
      'bin/libryzenadj.dll',
      '$exeDir\\bin\\ryzenadj.dll',
      '$exeDir\\bin\\libryzenadj.dll',
      '$exeDir\\ryzenadj.dll',
      '$exeDir\\libryzenadj.dll',
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

        // Bổ sung thư mục bin vào danh sách tìm kiếm DLL của Windows để nạp được WinRing0x64.dll và inpoutx64.dll
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

        _ryzenHandle = initFunc();
        if (_ryzenHandle != null && _ryzenHandle != nullptr) {
          _isHardwareActive = true;
          _logger.info(
            'Khởi tạo thành công kết nối phần cứng RyzenAdj DLL ($absPath).',
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
