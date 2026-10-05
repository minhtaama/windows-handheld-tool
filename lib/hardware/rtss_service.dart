import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';
import 'hardware_base.dart';

// Định nghĩa con trỏ hàm Win32 API từ kernel32.dll
typedef _OpenFileMappingC = Pointer<Void> Function(
    Uint32 dwDesiredAccess, Int32 bInheritHandle, Pointer<Utf16> lpName);
typedef _OpenFileMappingDart = Pointer<Void> Function(
    int dwDesiredAccess, int bInheritHandle, Pointer<Utf16> lpName);

typedef _MapViewOfFileC = Pointer<Void> Function(
    Pointer<Void> hFileMappingObject,
    Uint32 dwDesiredAccess,
    Uint32 dwFileOffsetHigh,
    Uint32 dwFileOffsetLow,
    IntPtr dwNumberOfBytesToMap);
typedef _MapViewOfFileDart = Pointer<Void> Function(
    Pointer<Void> hFileMappingObject,
    int dwDesiredAccess,
    int dwFileOffsetHigh,
    int dwFileOffsetLow,
    int dwNumberOfBytesToMap);

typedef _UnmapViewOfFileC = Int32 Function(Pointer<Void> lpBaseAddress);
typedef _UnmapViewOfFileDart = int Function(Pointer<Void> lpBaseAddress);

typedef _CloseHandleC = Int32 Function(Pointer<Void> hObject);
typedef _CloseHandleDart = int Function(Pointer<Void> hObject);

/// Dịch vụ kết nối và điều khiển RivaTuner Statistics Server (RTSS).
/// Sử dụng trực tiếp Win32 Named Shared Memory (RTSSSharedMemoryV2) qua Dart FFI (First Principles).
class RtssService {
  static const _logger = AppLogger('RtssService');
  static final RtssService instance = RtssService._();
  RtssService._() {
    _initFfi();
  }

  static const int _fileMapRead = 0x0004;
  static const int _rtssSignature = 0x53535452; // 'RTSS' trong mã ASCII Hex (Little Endian)

  late final _OpenFileMappingDart _openFileMapping;
  late final _MapViewOfFileDart _mapViewOfFile;
  late final _UnmapViewOfFileDart _unmapViewOfFile;
  late final _CloseHandleDart _closeHandle;
  bool _ffiLoaded = false;

  String? _cachedProfilePath;

  void _initFfi() {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _openFileMapping = kernel32
          .lookupFunction<_OpenFileMappingC, _OpenFileMappingDart>('OpenFileMappingW');
      _mapViewOfFile = kernel32
          .lookupFunction<_MapViewOfFileC, _MapViewOfFileDart>('MapViewOfFile');
      _unmapViewOfFile = kernel32
          .lookupFunction<_UnmapViewOfFileC, _UnmapViewOfFileDart>('UnmapViewOfFile');
      _closeHandle = kernel32
          .lookupFunction<_CloseHandleC, _CloseHandleDart>('CloseHandle');
      _ffiLoaded = true;
    } catch (_) {
      _ffiLoaded = false;
    }
  }

  /// Kiểm tra xem tiến trình RTSS có đang chạy trên Windows hay không.
  bool isRunning() {
    if (!_ffiLoaded) return false;

    final namePtr = 'RTSSSharedMemoryV2'.toNativeUtf16();
    try {
      final handle = _openFileMapping(_fileMapRead, 0, namePtr);
      if (handle.address != 0) {
        _closeHandle(handle);
        return true;
      }
      return false;
    } finally {
      calloc.free(namePtr);
    }
  }

  static const List<String> candidateExePaths = [
    r'C:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe',
    r'C:\Program Files\RivaTuner Statistics Server\RTSS.exe',
    r'D:\Program Files (x86)\RivaTuner Statistics Server\RTSS.exe',
    r'D:\Program Files\RivaTuner Statistics Server\RTSS.exe',
  ];

  /// Kiểm tra xem RTSS đã được cài đặt trên ổ cứng hay chưa.
  bool isInstalled() {
    for (final path in candidateExePaths) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }

  /// Đảm bảo RTSS đang chạy. Nếu chưa chạy, tự động tìm và khởi động RTSS.exe
  Future<bool> ensureRunning() async {
    if (isRunning()) {
      _logger.info('RTSS đang chạy ngầm.');
      return true;
    }

    for (final path in candidateExePaths) {
      if (File(path).existsSync()) {
        try {
          await Process.start(path, [], runInShell: true, mode: ProcessStartMode.detached);
          _logger.info('Đã tự động khởi chạy RTSS từ: $path');
          await Future.delayed(const Duration(milliseconds: 1500));
          return isRunning();
        } catch (e) {
          _logger.warning('Lỗi khi khởi chạy RTSS: $e');
        }
      }
    }

    _logger.warning('Không tìm thấy file RTSS.exe để tự động khởi động.');
    return false;
  }

  /// Đọc tốc độ khung hình (FPS) tức thời của trò chơi đang được RTSS hook.
  /// Trả về số nguyên FPS (hoặc null nếu không có game nào đang chạy hoặc RTSS tắt).
  int? getInstantaneousFps() {
    if (!_ffiLoaded) return null;

    final namePtr = 'RTSSSharedMemoryV2'.toNativeUtf16();
    Pointer<Void> handle = nullptr;
    Pointer<Void> map = nullptr;

    try {
      handle = _openFileMapping(_fileMapRead, 0, namePtr);
      if (handle.address == 0) return null;

      map = _mapViewOfFile(handle, _fileMapRead, 0, 0, 0);
      if (map.address == 0) return null;

      final data = map.cast<Uint8>();

      // Đọc Header RTSS_SHARED_MEMORY (4 byte đầu tiên: dwSignature)
      final sig = data.cast<Uint32>()[0];
      if (sig != _rtssSignature) return null;

      final appEntrySize = data.cast<Uint32>()[2];
      final appArrOffset = data.cast<Uint32>()[3];
      final appArrSize = data.cast<Uint32>()[4];

      if (appEntrySize == 0 || appArrSize == 0) return null;

      // Duyệt qua mảng AppEntry để tìm game đang hoạt động có PID khác 0
      for (int i = 0; i < appArrSize; i++) {
        final entryOffset = appArrOffset + (i * appEntrySize);
        final entryPtr = data + entryOffset;

        // dwProcessID nằm ở offset 260 sau chuỗi szProcessPath (260 byte)
        final pid = (entryPtr + 260).cast<Uint32>()[0];
        if (pid != 0) {
          // dwStatFramerate nằm ở offset 300 của AppEntry (đơn vị là fps * 10)
          final statFramerate = (entryPtr + 300).cast<Uint32>()[0];
          if (statFramerate > 0) {
            return (statFramerate / 10).round();
          }

          // Fallback: Tính từ dwStatFrames (offset 284) và delta time (offset 292 - 288)
          final statFrames = (entryPtr + 284).cast<Uint32>()[0];
          final time0 = (entryPtr + 288).cast<Uint32>()[0];
          final time1 = (entryPtr + 292).cast<Uint32>()[0];
          final delta = time1 - time0;
          if (delta > 0 && statFrames > 0) {
            return ((statFrames * 1000) / delta).round();
          }
        }
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      if (map.address != 0) _unmapViewOfFile(map);
      if (handle.address != 0) _closeHandle(handle);
      calloc.free(namePtr);
    }
  }

  /// Lấy tên file thực thi (.exe) của trò chơi đang chạy qua RTSS.
  String? getActiveGameName() {
    if (!_ffiLoaded) return null;

    final namePtr = 'RTSSSharedMemoryV2'.toNativeUtf16();
    Pointer<Void> handle = nullptr;
    Pointer<Void> map = nullptr;

    try {
      handle = _openFileMapping(_fileMapRead, 0, namePtr);
      if (handle.address == 0) return null;

      map = _mapViewOfFile(handle, _fileMapRead, 0, 0, 0);
      if (map.address == 0) return null;

      final data = map.cast<Uint8>();
      final sig = data.cast<Uint32>()[0];
      if (sig != _rtssSignature) return null;

      final appEntrySize = data.cast<Uint32>()[2];
      final appArrOffset = data.cast<Uint32>()[3];
      final appArrSize = data.cast<Uint32>()[4];

      for (int i = 0; i < appArrSize; i++) {
        final entryOffset = appArrOffset + (i * appEntrySize);
        final entryPtr = data + entryOffset;
        final pid = (entryPtr + 260).cast<Uint32>()[0];

        if (pid != 0) {
          // szProcessPath là chuỗi ANSI 260 byte ở đầu struct
          final bytes = <int>[];
          for (int b = 0; b < 260; b++) {
            final charCode = (entryPtr + b).cast<Uint8>().value;
            if (charCode == 0) break;
            bytes.add(charCode);
          }
          final fullPath = String.fromCharCodes(bytes);
          return fullPath.split(Platform.pathSeparator).last;
        }
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      if (map.address != 0) _unmapViewOfFile(map);
      if (handle.address != 0) _closeHandle(handle);
      calloc.free(namePtr);
    }
  }

  /// Tìm đường dẫn tới thư mục cấu hình Profiles của RTSS trên Windows.
  String? _findProfileDirectory() {
    if (_cachedProfilePath != null) return _cachedProfilePath;

    final candidatePaths = [
      r'C:\Program Files (x86)\RivaTuner Statistics Server\Profiles',
      r'C:\Program Files\RivaTuner Statistics Server\Profiles',
      r'D:\Program Files (x86)\RivaTuner Statistics Server\Profiles',
      r'D:\Program Files\RivaTuner Statistics Server\Profiles',
    ];

    for (final path in candidatePaths) {
      if (Directory(path).existsSync()) {
        _cachedProfilePath = path;
        return path;
      }
    }

    return null;
  }

  /// Đọc mức giới hạn FPS hiện tại được cấu hình trong RTSS Profile Global.
  int getFpsLimit() {
    final profileDir = _findProfileDirectory();
    if (profileDir == null) return 0;

    final globalFile = File('$profileDir\\Global');
    if (!globalFile.existsSync()) return 0;

    try {
      final lines = globalFile.readAsLinesSync();
      bool inFramerateSection = false;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed == '[Framerate]') {
          inFramerateSection = true;
          continue;
        }
        if (inFramerateSection) {
          if (trimmed.startsWith('[')) break;
          if (trimmed.startsWith('Limit=')) {
            final valStr = trimmed.substring('Limit='.length).trim();
            return int.tryParse(valStr) ?? 0;
          }
        }
      }
    } catch (_) {}

    return 0;
  }

  /// Thiết lập mức giới hạn FPS (Framerate Limit) cho toàn bộ game trong RTSS.
  /// [fps]: Giá trị 0 tương đương với Không giới hạn (Uncapped).
  bool setFpsLimit(int fps) {
    final profileDir = _findProfileDirectory();
    if (profileDir == null) return false;

    final globalFile = File('$profileDir\\Global');
    try {
      List<String> lines = [];
      if (globalFile.existsSync()) {
        lines = globalFile.readAsLinesSync();
      }

      int framerateSectionIdx = -1;
      int limitLineIdx = -1;

      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed == '[Framerate]') {
          framerateSectionIdx = i;
          continue;
        }
        if (framerateSectionIdx != -1) {
          if (trimmed.startsWith('[')) break;
          if (trimmed.startsWith('Limit=')) {
            limitLineIdx = i;
            break;
          }
        }
      }

      if (limitLineIdx != -1) {
        lines[limitLineIdx] = 'Limit=$fps';
      } else if (framerateSectionIdx != -1) {
        lines.insert(framerateSectionIdx + 1, 'Limit=$fps');
      } else {
        lines.add('');
        lines.add('[Framerate]');
        lines.add('Limit=$fps');
        lines.add('LimitNumerator=0');
        lines.add('LimitDenominator=0');
      }

      globalFile.writeAsStringSync(lines.join('\r\n'));
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Bộ điều khiển phần cứng cho RTSS FPS Limit kế thừa từ HardwareController (DRY).
class RtssFpsController extends HardwareController {
  final RtssService _service = RtssService.instance;

  RtssFpsController()
      : super(
          name: 'Giới hạn FPS',
          minVal: 0,
          maxVal: 120,
          step: 5,
          unit: 'FPS',
        );

  @override
  bool isAvailable() => _service.isRunning();

  @override
  int getValue() => _service.getFpsLimit();

  @override
  bool setValue(int value) => _service.setFpsLimit(clamp(value));

  /// Đọc FPS đo thực tế tức thời của game.
  int? getLiveFps() => _service.getInstantaneousFps();

  /// Tên game đang kích hoạt.
  String? getActiveGame() => _service.getActiveGameName();
}
