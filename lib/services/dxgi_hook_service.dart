import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/logger.dart';

// Native typedefs
typedef _InstallGlobalDxgiHookC = Int32 Function();
typedef _InstallGlobalDxgiHookDart = int Function();

typedef _UninstallGlobalDxgiHookC = Int32 Function();
typedef _UninstallGlobalDxgiHookDart = int Function();

typedef _IsGlobalDxgiHookActiveC = Int32 Function();
typedef _IsGlobalDxgiHookActiveDart = int Function();

typedef _InjectDxgiHookC = Int32 Function(Uint32 dwProcessId);
typedef _InjectDxgiHookDart = int Function(int dwProcessId);

typedef _EjectDxgiHookC = Int32 Function(Uint32 dwProcessId);
typedef _EjectDxgiHookDart = int Function(int dwProcessId);

typedef _MakeWindowBorderlessC = Int32 Function(IntPtr hWnd);
typedef _MakeWindowBorderlessDart = int Function(int hWnd);

typedef _SetOverlayActiveC = Void Function(Int32 active);
typedef _SetOverlayActiveDart = void Function(int active);

typedef _IsOverlayActiveC = Int32 Function();
typedef _IsOverlayActiveDart = int Function();

/// Dịch vụ quản lý DXGI Borderless Hook & XInput Input Muting.
/// Cưỡng bức game chạy chế độ Cửa sổ Không viền (Borderless Windowed / iFlip),
/// cho phép cửa sổ Flutter Quick Panel hiển thị đè mượt mà và ngắt phím tay cầm vào game.
class DxgiHookService extends ChangeNotifier {
  static const _logger = AppLogger('DxgiHookService');
  static final DxgiHookService instance = DxgiHookService._();

  DxgiHookService._();

  DynamicLibrary? _lib;

  _InstallGlobalDxgiHookDart? _installGlobalHook;
  _UninstallGlobalDxgiHookDart? _uninstallGlobalHook;
  _IsGlobalDxgiHookActiveDart? _isGlobalHookActive;
  _InjectDxgiHookDart? _injectHook;
  _EjectDxgiHookDart? _ejectHook;
  _MakeWindowBorderlessDart? _makeWindowBorderless;
  _SetOverlayActiveDart? _setOverlayActive;
  _IsOverlayActiveDart? _isOverlayActive;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  /// Kiểm tra xem Hook toàn hệ thống có đang hoạt động hay không
  bool get isHookActive {
    if (!_isAvailable || _isGlobalHookActive == null) return false;
    try {
      return _isGlobalHookActive!() != 0;
    } catch (_) {
      return false;
    }
  }

  /// Khởi tạo và nạp thư viện dxgi_hook.dll (Mặc định tự động kích hoạt)
  void init(ConfigManager config) {
    _loadLibrary();

    if (_isAvailable) {
      installGlobalHook();
    }
  }

  void _loadLibrary() {
    if (_lib != null) return;

    final candidates = [
      'bin/dxgi_hook.dll',
      'dxgi_hook.dll',
      '${Directory.current.path}/bin/dxgi_hook.dll',
      '${Directory.current.path}/dxgi_hook.dll',
    ];

    for (final path in candidates) {
      try {
        final file = File(path);
        if (file.existsSync() || !path.contains('/')) {
          _lib = DynamicLibrary.open(path);
          _logger.info('Loaded DXGI Hook library successfully from: $path');
          break;
        }
      } catch (e) {
        // Thử đường dẫn tiếp theo
      }
    }

    if (_lib == null) {
      _logger.warning('Could not find or load dxgi_hook.dll');
      _isAvailable = false;
      return;
    }

    try {
      _installGlobalHook = _lib!.lookupFunction<_InstallGlobalDxgiHookC, _InstallGlobalDxgiHookDart>(
        'InstallGlobalDxgiHook',
      );
      _uninstallGlobalHook = _lib!.lookupFunction<_UninstallGlobalDxgiHookC, _UninstallGlobalDxgiHookDart>(
        'UninstallGlobalDxgiHook',
      );
      _isGlobalHookActive = _lib!.lookupFunction<_IsGlobalDxgiHookActiveC, _IsGlobalDxgiHookActiveDart>(
        'IsGlobalDxgiHookActive',
      );
      _injectHook = _lib!.lookupFunction<_InjectDxgiHookC, _InjectDxgiHookDart>(
        'InjectDxgiHook',
      );
      _ejectHook = _lib!.lookupFunction<_EjectDxgiHookC, _EjectDxgiHookDart>(
        'EjectDxgiHook',
      );
      _makeWindowBorderless = _lib!.lookupFunction<_MakeWindowBorderlessC, _MakeWindowBorderlessDart>(
        'MakeWindowBorderless',
      );
      try {
        _setOverlayActive = _lib!.lookupFunction<_SetOverlayActiveC, _SetOverlayActiveDart>(
          'SetOverlayActive',
        );
        _isOverlayActive = _lib!.lookupFunction<_IsOverlayActiveC, _IsOverlayActiveDart>(
          'IsOverlayActive',
        );
      } catch (_) {}

      _isAvailable = true;
      _logger.info('Initialized DXGI Borderless Hook control APIs successfully');
    } catch (e) {
      _logger.error('Error binding functions from dxgi_hook.dll', e);
      _isAvailable = false;
    }
  }

  /// Báo cho Hook biết trạng thái mở/đóng của Overlay để ngắt (Mute) gamepad vào game
  void setOverlayActive(bool active) {
    if (!_isAvailable || _setOverlayActive == null) return;
    try {
      _setOverlayActive!(active ? 1 : 0);
    } catch (e) {
      _logger.error('Error updating SetOverlayActive: $e');
    }
  }

  /// Lấy trạng thái kích hoạt của Overlay từ shared memory
  bool get isOverlayActiveInHook {
    if (!_isAvailable || _isOverlayActive == null) return false;
    try {
      return _isOverlayActive!() != 0;
    } catch (_) {
      return false;
    }
  }

  /// Kích hoạt Global Windows Hook cho mọi game DirectX
  bool installGlobalHook() {
    if (!_isAvailable || _installGlobalHook == null) return false;
    try {
      final result = _installGlobalHook!() != 0;
      if (result) {
        _logger.info('Activated Global DXGI Borderless Hook successfully');
      } else {
        _logger.warning('Failed to activate Global DXGI Borderless Hook');
      }
      notifyListeners();
      return result;
    } catch (e) {
      _logger.error('Error activating Global DXGI Hook', e);
      return false;
    }
  }

  /// Tắt Global Windows Hook
  bool uninstallGlobalHook() {
    if (!_isAvailable || _uninstallGlobalHook == null) return false;
    try {
      final result = _uninstallGlobalHook!() != 0;
      if (result) {
        _logger.info('Removed Global DXGI Borderless Hook');
      }
      notifyListeners();
      return result;
    } catch (e) {
      _logger.error('Error removing Global DXGI Hook', e);
      return false;
    }
  }

  /// Chèn trực tiếp DXGI Hook vào một tiến trình cụ thể qua PID
  bool injectProcess(int processId) {
    if (!_isAvailable || _injectHook == null) return false;
    try {
      final result = _injectHook!(processId) != 0;
      _logger.info('Injected DXGI Hook into process PID $processId: ${result ? "Success" : "Failed"}');
      return result;
    } catch (e) {
      _logger.error('Error injecting DXGI Hook into PID $processId', e);
      return false;
    }
  }

  /// Rút DXGI Hook khỏi tiến trình cụ thể qua PID
  bool ejectProcess(int processId) {
    if (!_isAvailable || _ejectHook == null) return false;
    try {
      return _ejectHook!(processId) != 0;
    } catch (e) {
      _logger.error('Error ejecting DXGI Hook from PID $processId', e);
      return false;
    }
  }

  /// Cưỡng bức chuyển đổi một cửa sổ Game thành Không viền Toàn màn hình
  bool makeWindowBorderless(int hwnd) {
    if (!_isAvailable || _makeWindowBorderless == null) return false;
    try {
      return _makeWindowBorderless!(hwnd) != 0;
    } catch (e) {
      _logger.error('Error calling MakeWindowBorderless for HWND $hwnd', e);
      return false;
    }
  }
}
