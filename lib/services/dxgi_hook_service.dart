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

/// Dịch vụ quản lý DXGI Borderless Hook (Phương án 2).
/// Can thiệp vào DirectX SwapChain của Game để cưỡng bức chạy ở chế độ Cửa sổ Không viền (Borderless Windowed / iFlip),
/// giúp Quick Settings Overlay hiển thị đè lên game 100% mượt mà và không bao giờ bị văng hoặc minimize.
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

  /// Khởi tạo và nạp thư viện dxgi_hook.dll
  void init(ConfigManager config) {
    _config = config;
    _loadLibrary();

    if (_isAvailable && isEnabled) {
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
          _logger.info('Đã nạp thành công thư viện DXGI Hook từ: $path');
          break;
        }
      } catch (e) {
        // Thử đường dẫn tiếp theo
      }
    }

    if (_lib == null) {
      _logger.warning('Không tìm thấy hoặc không thể nạp dxgi_hook.dll');
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
      _logger.info('Khởi tạo thành công các API điều khiển DXGI Borderless Hook');
    } catch (e) {
      _logger.error('Lỗi khi liên kết hàm từ dxgi_hook.dll', e);
      _isAvailable = false;
    }
  }

  /// Báo cho Hook biết trạng thái mở/đóng của Overlay để ngắt (Mute) gamepad vào game
  void setOverlayActive(bool active) {
    if (!_isAvailable || _setOverlayActive == null) return;
    try {
      _setOverlayActive!(active ? 1 : 0);
    } catch (e) {
      _logger.error('Lỗi khi cập nhật SetOverlayActive: $e');
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
        _logger.info('Đã kích hoạt Global DXGI Borderless Hook thành công');
      } else {
        _logger.warning('Kích hoạt Global DXGI Borderless Hook thất bại');
      }
      notifyListeners();
      return result;
    } catch (e) {
      _logger.error('Lỗi khi kích hoạt Global DXGI Hook', e);
      return false;
    }
  }

  /// Tắt Global Windows Hook
  bool uninstallGlobalHook() {
    if (!_isAvailable || _uninstallGlobalHook == null) return false;
    try {
      final result = _uninstallGlobalHook!() != 0;
      if (result) {
        _logger.info('Đã gỡ bỏ Global DXGI Borderless Hook');
      }
      notifyListeners();
      return result;
    } catch (e) {
      _logger.error('Lỗi khi gỡ bỏ Global DXGI Hook', e);
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
      _logger.info('Chèn DXGI Hook vào tiến trình PID $processId: ${result ? "Thành công" : "Thất bại"}');
      return result;
    } catch (e) {
      _logger.error('Lỗi khi chèn DXGI Hook vào PID $processId', e);
      return false;
    }
  }

  /// Rút DXGI Hook khỏi tiến trình cụ thể qua PID
  bool ejectProcess(int processId) {
    if (!_isAvailable || _ejectHook == null) return false;
    try {
      return _ejectHook!(processId) != 0;
    } catch (e) {
      _logger.error('Lỗi khi rút DXGI Hook khỏi PID $processId', e);
      return false;
    }
  }

  /// Cưỡng bức chuyển đổi một cửa sổ Game thành Không viền Toàn màn hình
  bool makeWindowBorderless(int hwnd) {
    if (!_isAvailable || _makeWindowBorderless == null) return false;
    try {
      return _makeWindowBorderless!(hwnd) != 0;
    } catch (e) {
      _logger.error('Lỗi khi gọi MakeWindowBorderless cho HWND $hwnd', e);
      return false;
    }
  }
}
