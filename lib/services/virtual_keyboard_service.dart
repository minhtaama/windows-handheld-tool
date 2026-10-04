import 'dart:io';
import '../core/logger.dart';

/// Dịch vụ kích hoạt bàn phím cảm ứng ảo trên máy Handheld Windows (GPD Win 4, ROG Ally).
class VirtualKeyboardService {
  static const _logger = AppLogger('VirtualKeyboard');

  static final List<String> _tabTipCandidates = [
    r'C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe',
    r'C:\Program Files (x86)\Common Files\microsoft shared\ink\TabTip.exe',
  ];

  static Future<bool> toggleKeyboard() async {
    // 1. Thử gọi TabTip.exe của Windows
    for (final path in _tabTipCandidates) {
      if (File(path).existsSync()) {
        try {
          await Process.start(path, [], runInShell: true);
          _logger.info('Đã khởi chạy bàn phím ảo TabTip: $path');
          return true;
        } catch (e) {
          _logger.warning('Không thể khởi chạy $path: $e');
        }
      }
    }

    // 2. Fallback sang bàn phím osk.exe tiêu chuẩn của Windows
    try {
      await Process.start(r'C:\Windows\System32\osk.exe', [], runInShell: true);
      _logger.info('Đã khởi chạy bàn phím ảo dự phòng osk.exe.');
      return true;
    } catch (e) {
      _logger.error('Lỗi khi mở bàn phím ảo', e);
      return false;
    }
  }
}
