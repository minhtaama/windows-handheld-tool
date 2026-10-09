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

// Các hàm Win32 API được xuất bởi RTSSHooks64.dll
typedef _LoadProfileC = Void Function(Pointer<Uint8> lpProfile);
typedef _LoadProfileDart = void Function(Pointer<Uint8> lpProfile);

typedef _SaveProfileC = Void Function(Pointer<Uint8> lpProfile);
typedef _SaveProfileDart = void Function(Pointer<Uint8> lpProfile);

typedef _SetProfilePropertyC = Int32 Function(
    Pointer<Uint8> lpPropertyName, Pointer<Uint8> lpPropertyData, Uint32 dwPropertySize);
typedef _SetProfilePropertyDart = int Function(
    Pointer<Uint8> lpPropertyName, Pointer<Uint8> lpPropertyData, int dwPropertySize);

typedef _GetProfilePropertyC = Int32 Function(
    Pointer<Uint8> lpPropertyName, Pointer<Uint8> lpPropertyData, Uint32 dwPropertySize);
typedef _GetProfilePropertyDart = int Function(
    Pointer<Uint8> lpPropertyName, Pointer<Uint8> lpPropertyData, int dwPropertySize);

typedef _UpdateProfilesC = Void Function();
typedef _UpdateProfilesDart = void Function();

/// Dịch vụ kết nối và điều khiển RivaTuner Statistics Server (RTSS).
/// Sử dụng trực tiếp Win32 Named Shared Memory (RTSSSharedMemoryV2) và RTSSHooks64.dll qua Dart FFI (First Principles).
class RtssService {
  static const _logger = AppLogger('RtssService');
  static final RtssService instance = RtssService._();
  RtssService._() {
    _initFfi();
  }

  static const int _fileMapRead = 0x0004;
  static const int _fileMapAllAccess = 0x001F;
  static const int _rtssSignature = 0x53535452; // 'RTSS' trong mã ASCII Hex (Little Endian)
  static const String _osdAppOwner = 'WindowsHandheldTool';

  late final _OpenFileMappingDart _openFileMapping;
  late final _MapViewOfFileDart _mapViewOfFile;
  late final _UnmapViewOfFileDart _unmapViewOfFile;
  late final _CloseHandleDart _closeHandle;
  bool _ffiLoaded = false;

  DynamicLibrary? _rtssHooksDll;
  _LoadProfileDart? _loadProfile;
  _SaveProfileDart? _saveProfile;
  _SetProfilePropertyDart? _setProfileProperty;
  _GetProfilePropertyDart? _getProfileProperty;
  _UpdateProfilesDart? _updateProfiles;
  bool _hooksLoaded = false;

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

  void _initHooksDll() {
    if (_hooksLoaded) return;
    for (final exePath in candidateExePaths) {
      final dir = File(exePath).parent.path;
      final dllPath = '$dir\\RTSSHooks64.dll';
      if (File(dllPath).existsSync()) {
        try {
          _rtssHooksDll = DynamicLibrary.open(dllPath);
          _loadProfile = _rtssHooksDll!
              .lookupFunction<_LoadProfileC, _LoadProfileDart>('LoadProfile');
          _saveProfile = _rtssHooksDll!
              .lookupFunction<_SaveProfileC, _SaveProfileDart>('SaveProfile');
          _setProfileProperty = _rtssHooksDll!
              .lookupFunction<_SetProfilePropertyC, _SetProfilePropertyDart>(
                  'SetProfileProperty');
          _getProfileProperty = _rtssHooksDll!
              .lookupFunction<_GetProfilePropertyC, _GetProfilePropertyDart>(
                  'GetProfileProperty');
          _updateProfiles = _rtssHooksDll!
              .lookupFunction<_UpdateProfilesC, _UpdateProfilesDart>(
                  'UpdateProfiles');
          _hooksLoaded = true;
          _logger.info('Connected to RTSSHooks64.dll successfully: $dllPath');
          break;
        } catch (e) {
          _logger.warning('Failed to load functions from RTSSHooks64.dll: $e');
        }
      }
    }
  }

  Pointer<Uint8> _stringToAnsi(String str) {
    final units = str.codeUnits;
    final ptr = calloc<Uint8>(units.length + 1);
    for (int i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    return ptr;
  }

  bool _setHookProfilePropertyDword(String propertyName, int value) {
    _initHooksDll();
    if (!_hooksLoaded ||
        _loadProfile == null ||
        _setProfileProperty == null ||
        _saveProfile == null ||
        _updateProfiles == null) {
      return false;
    }

    Pointer<Uint8>? namePtr;
    Pointer<Uint8>? emptyPtr;
    Pointer<Uint32>? valPtr;
    try {
      emptyPtr = _stringToAnsi('');
      namePtr = _stringToAnsi(propertyName);
      valPtr = calloc<Uint32>();
      valPtr.value = value;

      _loadProfile!(emptyPtr);
      final res = _setProfileProperty!(namePtr, valPtr.cast<Uint8>(), 4);
      _saveProfile!(emptyPtr);
      _updateProfiles!();
      return res != 0;
    } catch (e) {
      _logger.warning('Error setting RTSS hook property $propertyName: $e');
      return false;
    } finally {
      if (emptyPtr != null) calloc.free(emptyPtr);
      if (namePtr != null) calloc.free(namePtr);
      if (valPtr != null) calloc.free(valPtr);
    }
  }

  int? _getHookProfilePropertyDword(String propertyName) {
    _initHooksDll();
    if (!_hooksLoaded || _loadProfile == null || _getProfileProperty == null) {
      return null;
    }

    Pointer<Uint8>? namePtr;
    Pointer<Uint8>? emptyPtr;
    Pointer<Uint32>? valPtr;
    try {
      emptyPtr = _stringToAnsi('');
      namePtr = _stringToAnsi(propertyName);
      valPtr = calloc<Uint32>();

      _loadProfile!(emptyPtr);
      final res = _getProfileProperty!(namePtr, valPtr.cast<Uint8>(), 4);
      if (res != 0) {
        return valPtr.value;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (emptyPtr != null) calloc.free(emptyPtr);
      if (namePtr != null) calloc.free(namePtr);
      if (valPtr != null) calloc.free(valPtr);
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
      _logger.info('RTSS is running in background.');
      return true;
    }

    for (final path in candidateExePaths) {
      if (File(path).existsSync()) {
        try {
          await Process.start(path, [], runInShell: true, mode: ProcessStartMode.detached);
          _logger.info('Auto-started RTSS from: $path');
          await Future.delayed(const Duration(milliseconds: 1500));
          return isRunning();
        } catch (e) {
          _logger.warning('Error starting RTSS: $e');
        }
      }
    }

    _logger.warning('RTSS.exe not found for auto-start.');
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

  /// Tìm đường dẫn tới thư mục ProfileTemplates của RTSS.
  String? _findProfileTemplateDirectory() {
    final candidatePaths = [
      r'C:\Program Files (x86)\RivaTuner Statistics Server\ProfileTemplates',
      r'C:\Program Files\RivaTuner Statistics Server\ProfileTemplates',
      r'D:\Program Files (x86)\RivaTuner Statistics Server\ProfileTemplates',
      r'D:\Program Files\RivaTuner Statistics Server\ProfileTemplates',
    ];

    for (final path in candidatePaths) {
      if (Directory(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// Hàm đọc giá trị INI dùng chung (DRY).
  String? _getProfileValue(String section, String key) {
    final profileDir = _findProfileDirectory();
    final templateDir = _findProfileTemplateDirectory();

    // 1. Ưu tiên đọc từ Profiles\Global
    if (profileDir != null) {
      final globalFile = File('$profileDir\\Global');
      if (globalFile.existsSync()) {
        final val = _readIniKey(globalFile, section, key);
        if (val != null) return val;
      }
    }

    // 2. Fallback đọc từ ProfileTemplates\Global
    if (templateDir != null) {
      final templateFile = File('$templateDir\\Global');
      if (templateFile.existsSync()) {
        final val = _readIniKey(templateFile, section, key);
        if (val != null) return val;
      }
    }

    return null;
  }

  String? _readIniKey(File file, String section, String key) {
    try {
      final lines = file.readAsLinesSync();
      final targetSection = '[${section.trim().toLowerCase()}]';
      bool inSection = false;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(';')) continue;
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          inSection = trimmed.toLowerCase() == targetSection;
          continue;
        }
        if (inSection) {
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx != -1) {
            final k = trimmed.substring(0, eqIdx).trim().toLowerCase();
            if (k == key.trim().toLowerCase()) {
              return trimmed.substring(eqIdx + 1).trim();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Hàm ghi cấu hình INI dùng chung vào Profiles\Global (DRY).
  bool _setProfileValues(String section, Map<String, String> keyValues) {
    final profileDir = _findProfileDirectory();
    if (profileDir == null) return false;

    final globalFile = File('$profileDir\\Global');
    try {
      List<String> lines = [];
      if (globalFile.existsSync()) {
        lines = globalFile.readAsLinesSync();
      } else {
        final templateDir = _findProfileTemplateDirectory();
        if (templateDir != null) {
          final templateFile = File('$templateDir\\Global');
          if (templateFile.existsSync()) {
            lines = templateFile.readAsLinesSync();
          }
        }
      }

      final targetSection = '[${section.trim().toLowerCase()}]';
      int sectionIdx = -1;
      int nextSectionIdx = lines.length;

      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          if (trimmed.toLowerCase() == targetSection) {
            sectionIdx = i;
          } else if (sectionIdx != -1) {
            nextSectionIdx = i;
            break;
          }
        }
      }

      if (sectionIdx == -1) {
        if (lines.isNotEmpty && lines.last.isNotEmpty) lines.add('');
        lines.add('[${section.trim()}]');
        for (final entry in keyValues.entries) {
          lines.add('${entry.key}=${entry.value}');
        }
      } else {
        final pending = Map<String, String>.from(keyValues);
        for (int i = sectionIdx + 1; i < nextSectionIdx; i++) {
          final trimmed = lines[i].trim();
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx != -1) {
            final k = trimmed.substring(0, eqIdx).trim();
            for (final pk in pending.keys.toList()) {
              if (pk.toLowerCase() == k.toLowerCase()) {
                lines[i] = '$k=${pending[pk]}';
                pending.remove(pk);
              }
            }
          }
        }
        int insertPos = nextSectionIdx;
        for (final entry in pending.entries) {
          lines.insert(insertPos++, '${entry.key}=${entry.value}');
        }
      }

      globalFile.writeAsStringSync(lines.join('\r\n'));
      return true;
    } catch (e) {
      _logger.warning('Không thể ghi file cấu hình RTSS Global (yêu cầu quyền Admin): $e');
      return false;
    }
  }

  /// Đọc mức giới hạn FPS hiện tại được cấu hình trong RTSS.
  int getFpsLimit() {
    final hookVal = _getHookProfilePropertyDword('FramerateLimit');
    if (hookVal != null) return hookVal;
    final val = _getProfileValue('Framerate', 'Limit');
    return val != null ? (int.tryParse(val) ?? 0) : 0;
  }

  /// Thiết lập mức giới hạn FPS (Framerate Limit) cho toàn bộ game trong RTSS.
  bool setFpsLimit(int fps) {
    _setHookProfilePropertyDword('FramerateLimit', fps);
    _setProfileValues('Framerate', {
      'Limit': '$fps',
      'LimitDenominator': '1',
    });
    return true;
  }

  /// Kiểm tra xem lớp phủ OSD có đang được kích hoạt hay không.
  bool isOsdEnabled() {
    final hookVal = _getHookProfilePropertyDword('EnableOSD');
    if (hookVal != null) return hookVal == 1;
    final val = _getProfileValue('OSD', 'EnableOSD');
    return val == '1';
  }

  /// Bật hoặc tắt lớp phủ OSD và thông số FPS trên màn hình game.
  /// Bật đồng thời EnableOSD (subsystem OSD) và EnableStat (vẽ FPS tích hợp của RTSS).
  bool setOsdEnabled(bool enabled) {
    final val = enabled ? 1 : 0;
    _setHookProfilePropertyDword('EnableOSD', val);
    _setHookProfilePropertyDword('EnableStat', val);
    _setProfileValues('OSD', {
      'EnableOSD': '$val',
      'EnableStat': '$val',
      'ShowForegroundStat': '$val',
    });
    return true;
  }

  /// Lấy kích thước phóng đại font chữ OSD (ZoomRatio: 1, 2, 3, 4).
  int getOsdZoom() {
    final hookVal = _getHookProfilePropertyDword('ZoomRatio');
    if (hookVal != null) return hookVal.clamp(1, 4);
    final val = _getProfileValue('OSD', 'ZoomRatio');
    return val != null ? (int.tryParse(val) ?? 2).clamp(1, 4) : 2;
  }

  /// Thiết lập kích thước phóng đại font chữ OSD.
  bool setOsdZoom(int zoom) {
    final clamped = zoom.clamp(1, 4);
    _setHookProfilePropertyDword('ZoomRatio', clamped);
    _setProfileValues('OSD', {
      'ZoomRatio': '$clamped',
    });
    return true;
  }

  /// Lấy vị trí góc màn hình hiển thị OSD.
  RtssOsdPosition getOsdPosition() {
    final hookX = _getHookProfilePropertyDword('PositionX');
    final hookY = _getHookProfilePropertyDword('PositionY');
    if (hookX != null && hookY != null) {
      for (final pos in RtssOsdPosition.values) {
        if (pos.x == hookX && pos.y == hookY) return pos;
      }
    }

    final xStr = _getProfileValue('OSD', 'PositionX');
    final yStr = _getProfileValue('OSD', 'PositionY');
    final x = int.tryParse(xStr ?? '') ?? 1;
    final y = int.tryParse(yStr ?? '') ?? 1;

    for (final pos in RtssOsdPosition.values) {
      if (pos.x == x && pos.y == y) return pos;
    }
    return RtssOsdPosition.topLeft;
  }

  /// Thiết lập vị trí góc màn hình hiển thị OSD.
  bool setOsdPosition(RtssOsdPosition position) {
    _setHookProfilePropertyDword('PositionX', position.x);
    _setHookProfilePropertyDword('PositionY', position.y);
    _setProfileValues('OSD', {
      'PositionX': '${position.x}',
      'PositionY': '${position.y}',
    });
    return true;
  }

  /// Bơm chuỗi văn bản định dạng vào ô nhớ OSD trong RTSSSharedMemoryV2.
  /// RTSS sẽ tự động render văn bản này lên màn hình trò chơi Direct3D/Vulkan/OpenGL.
  bool updateOsdText(String text) {
    if (!_ffiLoaded) return false;

    final namePtr = 'RTSSSharedMemoryV2'.toNativeUtf16();
    Pointer<Void> handle = nullptr;
    Pointer<Void> map = nullptr;

    try {
      handle = _openFileMapping(_fileMapAllAccess, 0, namePtr);
      if (handle.address == 0) return false;

      map = _mapViewOfFile(handle, _fileMapAllAccess, 0, 0, 0);
      if (map.address == 0) return false;

      final data = map.cast<Uint8>();
      final sig = data.cast<Uint32>()[0];
      if (sig != _rtssSignature) return false;

      final ver = data.cast<Uint32>()[1];
      final osdEntrySize = data.cast<Uint32>()[5];
      final osdArrOffset = data.cast<Uint32>()[6];
      final osdArrSize = data.cast<Uint32>()[7];

      if (osdEntrySize == 0 || osdArrSize == 0) return false;

      // Duyệt tìm slot của _osdAppOwner hoặc slot trống đầu tiên
      int targetSlotIndex = -1;
      for (int i = 0; i < osdArrSize; i++) {
        final entryOffset = osdArrOffset + (i * osdEntrySize);
        final entryPtr = data + entryOffset;

        final ownerBytes = <int>[];
        for (int b = 0; b < 256; b++) {
          final c = (entryPtr + 256 + b).cast<Uint8>().value;
          if (c == 0) break;
          ownerBytes.add(c);
        }
        final owner = String.fromCharCodes(ownerBytes);

        if (owner == _osdAppOwner) {
          targetSlotIndex = i;
          break;
        } else if (owner.isEmpty && targetSlotIndex == -1) {
          targetSlotIndex = i;
        }
      }

      if (targetSlotIndex == -1) return false;

      final entryOffset = osdArrOffset + (targetSlotIndex * osdEntrySize);
      final entryPtr = data + entryOffset;

      // 1. Ghi tên chủ sở hữu slot szOSDOwner (offset 256, dung lượng 256 byte)
      final ownerUnits = _osdAppOwner.codeUnits;
      for (int i = 0; i < ownerUnits.length && i < 255; i++) {
        (entryPtr + 256 + i).cast<Uint8>().value = ownerUnits[i];
      }
      (entryPtr + 256 + ownerUnits.length.clamp(0, 255)).cast<Uint8>().value = 0;

      // 2. Ghi chuỗi văn bản OSD
      // Nếu ver >= 0x00020007 dùng szOSDEx (offset 512, 4096 bytes)
      final textUnits = text.codeUnits;
      if (ver >= 0x00020007) {
        const maxLen = 4095;
        for (int i = 0; i < textUnits.length && i < maxLen; i++) {
          (entryPtr + 512 + i).cast<Uint8>().value = textUnits[i];
        }
        final endIdx = textUnits.length.clamp(0, maxLen);
        (entryPtr + 512 + endIdx).cast<Uint8>().value = 0;
      } else {
        const maxLen = 255;
        for (int i = 0; i < textUnits.length && i < maxLen; i++) {
          (entryPtr + i).cast<Uint8>().value = textUnits[i];
        }
        final endIdx = textUnits.length.clamp(0, maxLen);
        (entryPtr + endIdx).cast<Uint8>().value = 0;
      }

      // 3. Tăng trường dwOSDFrame (offset 32 trong RTSS_SHARED_MEMORY) để kích hoạt RTSS refresh ngay lập tức
      final framePtr = (data + 32).cast<Uint32>();
      framePtr.value = framePtr.value + 1;

      return true;
    } catch (e) {
      _logger.warning('Lỗi updateOsdText: $e');
      return false;
    } finally {
      if (map.address != 0) _unmapViewOfFile(map);
      if (handle.address != 0) _closeHandle(handle);
      calloc.free(namePtr);
    }
  }

  /// Xóa sạch văn bản OSD do ứng dụng bơm vào khi người dùng tắt OSD.
  bool clearOsdText() {
    if (!_ffiLoaded) return false;

    final namePtr = 'RTSSSharedMemoryV2'.toNativeUtf16();
    Pointer<Void> handle = nullptr;
    Pointer<Void> map = nullptr;

    try {
      handle = _openFileMapping(_fileMapAllAccess, 0, namePtr);
      if (handle.address == 0) return false;

      map = _mapViewOfFile(handle, _fileMapAllAccess, 0, 0, 0);
      if (map.address == 0) return false;

      final data = map.cast<Uint8>();
      final sig = data.cast<Uint32>()[0];
      if (sig != _rtssSignature) return false;

      final osdEntrySize = data.cast<Uint32>()[5];
      final osdArrOffset = data.cast<Uint32>()[6];
      final osdArrSize = data.cast<Uint32>()[7];

      for (int i = 0; i < osdArrSize; i++) {
        final entryOffset = osdArrOffset + (i * osdEntrySize);
        final entryPtr = data + entryOffset;

        final ownerBytes = <int>[];
        for (int b = 0; b < 256; b++) {
          final c = (entryPtr + 256 + b).cast<Uint8>().value;
          if (c == 0) break;
          ownerBytes.add(c);
        }
        final owner = String.fromCharCodes(ownerBytes);

        if (owner == _osdAppOwner) {
          // Xóa trắng toàn bộ entry
          for (int b = 0; b < osdEntrySize; b++) {
            (entryPtr + b).cast<Uint8>().value = 0;
          }
          final framePtr = (data + 32).cast<Uint32>();
          framePtr.value = framePtr.value + 1;
          break;
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      if (map.address != 0) _unmapViewOfFile(map);
      if (handle.address != 0) _closeHandle(handle);
      calloc.free(namePtr);
    }
  }
}

/// Các vị trí neo góc màn hình hiển thị Overlay OSD của RTSS.
enum RtssOsdPosition {
  topLeft(1, 1, 'Trái trên'),
  topRight(-1, 1, 'Phải trên'),
  bottomLeft(1, -1, 'Trái dưới'),
  bottomRight(-1, -1, 'Phải dưới');

  final int x;
  final int y;
  final String label;

  const RtssOsdPosition(this.x, this.y, this.label);
}

/// Bộ điều khiển phần cứng cho RTSS FPS Limit & OSD Overlay kế thừa từ HardwareController (DRY).
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

  /// Quản lý lớp phủ OSD
  bool isOsdEnabled() => _service.isOsdEnabled();
  bool setOsdEnabled(bool enabled) => _service.setOsdEnabled(enabled);

  int getOsdZoom() => _service.getOsdZoom();
  bool setOsdZoom(int zoom) => _service.setOsdZoom(zoom);

  RtssOsdPosition getOsdPosition() => _service.getOsdPosition();
  bool setOsdPosition(RtssOsdPosition pos) => _service.setOsdPosition(pos);

  /// Cập nhật văn bản OSD tùy biến vào Shared Memory
  bool updateOsdText(String text) => _service.updateOsdText(text);
  bool clearOsdText() => _service.clearOsdText();
}
