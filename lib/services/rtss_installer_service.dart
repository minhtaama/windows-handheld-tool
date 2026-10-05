import 'dart:io';

import '../core/logger.dart';
import '../hardware/rtss_service.dart';

/// Trạng thái của quá trình cài đặt RTSS.
enum RtssInstallStatus { notInstalled, installing, installed, failed }

/// Dịch vụ quản lý kiểm tra, tải và cài đặt tự động RivaTuner Statistics Server (RTSS).
class RtssInstallerService {
  static const _logger = AppLogger('RtssInstallerService');

  /// Kiểm tra xem RTSS đã được cài đặt trên máy chưa.
  static bool isInstalled() {
    return RtssService.instance.isInstalled();
  }

  /// Tự động thực hiện cài đặt RTSS qua Winget hoặc trình cài đặt có sẵn.
  /// Trả về `true` nếu cài đặt và khởi chạy RTSS thành công.
  static Future<bool> installRtss({
    void Function(String message)? onStatusUpdate,
  }) async {
    if (isInstalled()) {
      _logger.info('RTSS đã tồn tại trên máy.');
      onStatusUpdate?.call('RTSS đã được cài đặt.');
      return await RtssService.instance.ensureRunning();
    }

    onStatusUpdate?.call('Đang chuẩn bị gói cài đặt RTSS...');
    _logger.info('Bắt đầu quy trình tự động cài đặt RTSS...');

    try {
      // 1. Kiểm tra xem file cài đặt đã được tải sẵn trong thư mục Temp hay chưa
      final tempDir = Platform.environment['TEMP'] ?? '';
      final cachedSetup = File(
        '$tempDir\\WinGet\\Guru3D.RTSS.7.3.7\\extracted\\RTSSSetup737.exe',
      );

      if (cachedSetup.existsSync()) {
        onStatusUpdate?.call('Đang cài đặt RTSS từ bộ nhớ đệm...');
        _logger.info('Tìm thấy bộ cài sẵn tại: ${cachedSetup.path}');

        final psCommand =
            'Start-Process -FilePath "${cachedSetup.path}" -ArgumentList "/S" -Verb RunAs -Wait';
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          psCommand,
        ]);

        if (result.exitCode == 0 && isInstalled()) {
          onStatusUpdate?.call('Cài đặt hoàn tất! Đang khởi động RTSS...');
          return await RtssService.instance.ensureRunning();
        }
      }

      // 2. Nếu chưa có sẵn, sử dụng Winget với quyền Admin
      onStatusUpdate?.call(
        'Đang tải và cài đặt qua Windows Package Manager (Winget)...',
      );
      _logger.info('Khởi chạy winget install Guru3D.RTSS...');

      // Gọi lệnh winget kèm quyền Administrator qua PowerShell Start-Process để hiển thị UAC rõ ràng trên màn hình người dùng
      final wingetScript =
          'Start-Process winget -ArgumentList "install --id Guru3D.RTSS -h --accept-package-agreements --accept-source-agreements" -Verb RunAs -Wait';
      final wingetResult = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        wingetScript,
      ]);

      _logger.info('Winget kết thúc với exitCode: ${wingetResult.exitCode}');

      // Chờ hệ thống ghi nhận file cài đặt trong ổ đĩa
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (isInstalled()) {
          onStatusUpdate?.call('Cài đặt thành công! Đang kết nối RTSS...');
          _logger.info('Đã phát hiện RTSS trên ổ cứng sau khi cài đặt.');
          return await RtssService.instance.ensureRunning();
        }
      }

      final success = isInstalled();
      if (!success) {
        onStatusUpdate?.call('Cài đặt không thành công hoặc bị hủy.');
        _logger.warning(
          'Cài đặt RTSS thất bại: không tìm thấy file sau khi chạy lệnh.',
        );
      }
      return success;
    } catch (e, stack) {
      _logger.error('Lỗi ngoại lệ trong quá trình cài đặt RTSS', e, stack);
      onStatusUpdate?.call('Lỗi: $e');
      return false;
    }
  }
}
