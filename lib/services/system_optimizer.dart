import 'dart:ffi';
import '../core/logger.dart';

typedef _EmptyWorkingSetC = Int32 Function(IntPtr hProcess);
typedef _EmptyWorkingSetDart = int Function(int hProcess);

typedef _GetCurrentProcessC = IntPtr Function();
typedef _GetCurrentProcessDart = int Function();

/// Bộ tối ưu hóa tài nguyên hệ thống dành riêng cho máy Handheld (GPD Win 4).
class SystemOptimizer {
  static const _logger = AppLogger('SystemOptimizer');

  static _EmptyWorkingSetDart? _emptyWorkingSet;
  static _GetCurrentProcessDart? _getCurrentProcess;
  static bool _initialized = false;

  static void _init() {
    if (_initialized) return;
    try {
      final psapi = DynamicLibrary.open('psapi.dll');
      _emptyWorkingSet = psapi.lookupFunction<_EmptyWorkingSetC, _EmptyWorkingSetDart>(
        'EmptyWorkingSet',
      );

      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _getCurrentProcess = kernel32.lookupFunction<_GetCurrentProcessC, _GetCurrentProcessDart>(
        'GetCurrentProcess',
      );
      _initialized = true;
    } catch (e) {
      _logger.warning('Không thể khởi tạo hàm giải phóng RAM EmptyWorkingSet: $e');
    }
  }

  /// Ép Windows giải phóng toàn bộ RAM rảnh rỗi của tiến trình (Trim Working Set).
  /// Giúp app chạy ngầm chỉ tốn khoảng ~15MB-20MB RAM trên GPD Win 4.
  static void trimMemory() {
    _init();
    if (_emptyWorkingSet != null && _getCurrentProcess != null) {
      try {
        final hProcess = _getCurrentProcess!();
        final result = _emptyWorkingSet!(hProcess);
        if (result != 0) {
          _logger.info('Đã giải phóng bộ nhớ RAM tiến trình thành công (Trim Working Set).');
        }
      } catch (e) {
        _logger.warning('Lỗi khi giải phóng RAM: $e');
      }
    }
  }
}
