import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/logger.dart';
import 'native_window_service.dart';

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

typedef _SetOverlayHookModeC = Void Function(Int32 mode);
typedef _SetOverlayHookModeDart = void Function(int mode);

typedef _GetOverlayHookModeC = Int32 Function();
typedef _GetOverlayHookModeDart = int Function();

typedef _SetSharedTextureHandleC = Void Function(IntPtr handle);
typedef _SetSharedTextureHandleDart = void Function(int handle);

typedef _GetSharedTextureHandleC = IntPtr Function();
typedef _GetSharedTextureHandleDart = int Function();

typedef _CreateOverlaySharedTextureC = Int32 Function(Uint32 width, Uint32 height);
typedef _CreateOverlaySharedTextureDart = int Function(int width, int height);

typedef _ReleaseOverlaySharedTextureC = Void Function();
typedef _ReleaseOverlaySharedTextureDart = void Function();

typedef _UpdateOverlaySharedTextureFromHwndC = Int32 Function(IntPtr hWnd);
typedef _UpdateOverlaySharedTextureFromHwndDart = int Function(int hWnd);

/// Chế độ hoạt động của Overlay Hook:
/// - `dxgiBorderless`: Phương án 2 - Cưỡng bức game thành Cửa sổ Không viền (Borderless Windowed / iFlip), cửa sổ Flutter đè lên mượt mà.
/// - `sharedTexture`: Phương án 3 - Direct3D Shared Texture Injection (OBS / Discord style), vẽ trực tiếp kết cấu vào BackBuffer tại Present.
enum OverlayHookMode {
  dxgiBorderless,
  sharedTexture,
}

/// Dịch vụ quản lý DXGI Hook (Phương án 2 & Phương án 3 trong note.md).
/// Hỗ trợ cả DXGI Borderless Hook và Direct3D Shared Texture Injection.
class DxgiHookService extends ChangeNotifier {
  static const _logger = AppLogger('DxgiHookService');
  static final DxgiHookService instance = DxgiHookService._();

  DxgiHookService._();

  DynamicLibrary? _lib;
  ConfigManager? _config;

  _InstallGlobalDxgiHookDart? _installGlobalHook;
  _UninstallGlobalDxgiHookDart? _uninstallGlobalHook;
  _IsGlobalDxgiHookActiveDart? _isGlobalHookActive;
  _InjectDxgiHookDart? _injectHook;
  _EjectDxgiHookDart? _ejectHook;
  _MakeWindowBorderlessDart? _makeWindowBorderless;
  _SetOverlayActiveDart? _setOverlayActive;
  _IsOverlayActiveDart? _isOverlayActive;
  _SetOverlayHookModeDart? _setOverlayHookMode;
  _GetOverlayHookModeDart? _getOverlayHookMode;
  _SetSharedTextureHandleDart? _setSharedTextureHandle;
  _GetSharedTextureHandleDart? _getSharedTextureHandle;
  _CreateOverlaySharedTextureDart? _createOverlaySharedTexture;
  _ReleaseOverlaySharedTextureDart? _releaseOverlaySharedTexture;
  _UpdateOverlaySharedTextureFromHwndDart? _updateOverlaySharedTextureFromHwnd;

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

  /// Trạng thái bật/tắt trong file config
  bool get isEnabled => _config?.get("dxgi_hook.enabled", true) ?? true;

  /// Chế độ Hook hiện tại
  OverlayHookMode get hookMode {
    final modeStr = _config?.get("dxgi_hook.mode", "dxgiBorderless");
    return OverlayHookMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => OverlayHookMode.dxgiBorderless,
    );
  }

  /// Lấy mã chế độ Hook thực tế đang lưu trong DLL qua FFI
  int get activeNativeHookMode {
    if (!_isAvailable || _getOverlayHookMode == null) return 0;
    try {
      return _getOverlayHookMode!();
    } catch (_) {
      return 0;
    }
  }

  /// Khởi tạo và nạp thư viện dxgi_hook.dll
  void init(ConfigManager config) {
    _config = config;
    _loadLibrary();

    if (_isAvailable) {
      final physicalSize = NativeWindowService.getPhysicalScreenSize();
      createOverlaySharedTexture(physicalSize.width.toInt(), physicalSize.height.toInt());
      setHookMode(hookMode);
      if (isEnabled) {
        installGlobalHook();
      }
    }
  }

  /// Chuyển đổi giữa chế độ DXGI Borderless và Direct3D Shared Texture Injection
  void setHookMode(OverlayHookMode mode) {
    _config?.set("dxgi_hook.mode", mode.name);
    if (_isAvailable && _setOverlayHookMode != null) {
      try {
        final modeInt = mode == OverlayHookMode.sharedTexture ? 1 : 0;
        _setOverlayHookMode!(modeInt);
        _logger.info('Switched Hook mode to: ${mode.name} (Code: $modeInt)');
      } catch (e) {
        _logger.error('Error calling SetOverlayHookMode: $e');
      }
    }
    notifyListeners();
  }

  /// Cập nhật con trỏ GPU Shared Texture Handle cho Direct3D Shared Texture Injection
  void setSharedTextureHandle(int handle) {
    if (!_isAvailable || _setSharedTextureHandle == null) return;
    try {
      _setSharedTextureHandle!(handle);
      _logger.info('Updated SharedTextureHandle: 0x${handle.toRadixString(16)}');
    } catch (e) {
      _logger.error('Error calling SetSharedTextureHandle: $e');
    }
  }

  /// Khởi tạo kết cấu GPU Direct3D 11 dùng chung trên máy Host (Flutter)
  bool createOverlaySharedTexture(int width, int height) {
    if (!_isAvailable || _createOverlaySharedTexture == null) return false;
    try {
      return _createOverlaySharedTexture!(width, height) != 0;
    } catch (e) {
      _logger.error('Error calling CreateOverlaySharedTexture: $e');
      return false;
    }
  }

  /// Giải phóng kết cấu GPU Direct3D 11 dùng chung trên máy Host
  void releaseOverlaySharedTexture() {
    if (!_isAvailable || _releaseOverlaySharedTexture == null) return;
    try {
      _releaseOverlaySharedTexture!();
    } catch (e) {
      _logger.error('Error calling ReleaseOverlaySharedTexture: $e');
    }
  }

  /// Chụp trực tiếp khung hình từ cửa sổ Flutter và nạp vào GPU VRAM Shared Texture
  bool updateSharedTextureFromHwnd(int hWnd) {
    if (!_isAvailable || _updateOverlaySharedTextureFromHwnd == null || hWnd == 0) return false;
    try {
      return _updateOverlaySharedTextureFromHwnd!(hWnd) != 0;
    } catch (e) {
      _logger.error('Error calling UpdateOverlaySharedTextureFromHwnd: $e');
      return false;
    }
  }

  /// Lấy con trỏ GPU Shared Texture Handle hiện tại từ nhân đồ họa
  int getSharedTextureHandle() {
    if (!_isAvailable || _getSharedTextureHandle == null) return 0;
    try {
      return _getSharedTextureHandle!();
    } catch (_) {
      return 0;
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

      try {
        _setOverlayHookMode = _lib!.lookupFunction<_SetOverlayHookModeC, _SetOverlayHookModeDart>(
          'SetOverlayHookMode',
        );
        _getOverlayHookMode = _lib!.lookupFunction<_GetOverlayHookModeC, _GetOverlayHookModeDart>(
          'GetOverlayHookMode',
        );
        _setSharedTextureHandle = _lib!.lookupFunction<_SetSharedTextureHandleC, _SetSharedTextureHandleDart>(
          'SetSharedTextureHandle',
        );
        _getSharedTextureHandle = _lib!.lookupFunction<_GetSharedTextureHandleC, _GetSharedTextureHandleDart>(
          'GetSharedTextureHandle',
        );
        _createOverlaySharedTexture = _lib!.lookupFunction<_CreateOverlaySharedTextureC, _CreateOverlaySharedTextureDart>(
          'CreateOverlaySharedTexture',
        );
        _releaseOverlaySharedTexture = _lib!.lookupFunction<_ReleaseOverlaySharedTextureC, _ReleaseOverlaySharedTextureDart>(
          'ReleaseOverlaySharedTexture',
        );
        _updateOverlaySharedTextureFromHwnd = _lib!.lookupFunction<_UpdateOverlaySharedTextureFromHwndC, _UpdateOverlaySharedTextureFromHwndDart>(
          'UpdateOverlaySharedTextureFromHwnd',
        );
      } catch (e) {
        _logger.warning('DLL does not export Shared Texture APIs yet: $e');
      }

      _isAvailable = true;
      _logger.info('Initialized DXGI Hook & Shared Texture control APIs successfully');
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
      if (active && hookMode == OverlayHookMode.sharedTexture) {
        final hwnd = NativeWindowService.getWindowHandle();
        if (hwnd != 0) {
          updateSharedTextureFromHwnd(hwnd);
        }
      }
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

  /// Bật / Tắt trạng thái hoạt động của Hook và lưu cấu hình
  void setEnabled(bool enable) {
    _config?.set("dxgi_hook.enabled", enable);
    if (enable) {
      installGlobalHook();
    } else {
      uninstallGlobalHook();
    }
    notifyListeners();
  }

  /// Chuyển đổi trạng thái Bật / Tắt
  void toggle() {
    setEnabled(!isEnabled);
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
