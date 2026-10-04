import 'dart:io';
import '../core/logger.dart';

/// Danh sách định danh các dòng máy Handheld PC phổ biến trên thị trường.
enum HandheldModel {
  gpdWin4,
  gpdWinMax2,
  gpdWinMini,
  gpdWin3,
  gpdPocket4,
  gpdOther,
  rogAlly,
  rogAllyX,
  legionGo,
  steamDeckLcd,
  steamDeckOled,
  ayaneo,
  msiClaw,
  onexplayer,
  aokzoe,
  genericPc,
}

/// Chứa thông tin chi tiết về phần cứng thiết bị.
class DeviceInfo {
  final String manufacturer;
  final String productName;
  final HandheldModel model;
  final String displayName;
  final bool isHandheld;

  const DeviceInfo({
    required this.manufacturer,
    required this.productName,
    required this.model,
    required this.displayName,
    required this.isHandheld,
  });

  @override
  String toString() => '$displayName ($manufacturer - $productName)';
}

/// Dịch vụ nhận diện phần cứng máy Handheld từ Windows SMBIOS/Registry.
class DeviceInfoService {
  static const _logger = AppLogger('DeviceInfoService');
  static DeviceInfo? _current;

  /// Lấy thông tin thiết bị đã nhận diện hoặc fallback mặc định.
  static DeviceInfo get currentDevice =>
      _current ??
      const DeviceInfo(
        manufacturer: 'Unknown',
        productName: 'Unknown',
        model: HandheldModel.genericPc,
        displayName: 'Windows PC',
        isHandheld: false,
      );

  /// Khởi tạo và quét nhận diện thiết bị từ Windows Registry SMBIOS.
  static Future<DeviceInfo> init() async {
    if (_current != null) return _current!;

    String systemMfr = '';
    String systemProd = '';
    String boardMfr = '';
    String boardProd = '';

    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\HARDWARE\DESCRIPTION\System\BIOS',
      ]);

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'\r?\n'));
        for (final line in lines) {
          if (!line.contains('REG_SZ')) continue;

          final parts = line.trim().split(RegExp(r'\s+REG_SZ\s+'));
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts[1].trim();

            if (key == 'SystemManufacturer') systemMfr = value;
            if (key == 'SystemProductName') systemProd = value;
            if (key == 'BaseBoardManufacturer') boardMfr = value;
            if (key == 'BaseBoardProduct') boardProd = value;
          }
        }
      }
    } catch (e) {
      _logger.error('Lỗi khi truy vấn thông tin BIOS từ Registry', e);
    }

    // Ưu tiên System info, nếu là chuỗi rác/mặc định thì dùng BaseBoard info
    final mfr = (systemMfr.isNotEmpty && systemMfr != 'Default string')
        ? systemMfr
        : boardMfr;
    final prod = (systemProd.isNotEmpty && systemProd != 'Default string')
        ? systemProd
        : boardProd;

    _current = _resolveDevice(mfr, prod);
    _logger.info(
      'Đã nhận diện thiết bị: ${_current!.displayName} '
      '[Hãng: $mfr, Sản phẩm: $prod, Handheld: ${_current!.isHandheld}]',
    );

    return _current!;
  }

  /// Phân loại model máy Handheld dựa theo SMBIOS Manufacturer và Product Name.
  static DeviceInfo _resolveDevice(String rawMfr, String rawProd) {
    final mfr = rawMfr.toUpperCase();
    final prod = rawProd.toUpperCase();

    // 1. Dòng máy GPD
    if (mfr.contains('GPD')) {
      if (prod.contains('G1618')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.gpdWin4,
          displayName: 'GPD Win 4',
          isHandheld: true,
        );
      }
      if (prod.contains('G1619')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.gpdWinMax2,
          displayName: 'GPD Win Max 2',
          isHandheld: true,
        );
      }
      if (prod.contains('G1621')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.gpdWinMini,
          displayName: 'GPD Win Mini',
          isHandheld: true,
        );
      }
      if (prod.contains('G1617')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.gpdWin3,
          displayName: 'GPD Win 3',
          isHandheld: true,
        );
      }
      if (prod.contains('G1628')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.gpdPocket4,
          displayName: 'GPD Pocket 4',
          isHandheld: true,
        );
      }
      return DeviceInfo(
        manufacturer: rawMfr,
        productName: rawProd,
        model: HandheldModel.gpdOther,
        displayName: 'GPD Handheld',
        isHandheld: true,
      );
    }

    // 2. Dòng máy ASUS ROG Ally
    if (mfr.contains('ASUS') || mfr.contains('ASUSTEK')) {
      if (prod.contains('RC72')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.rogAllyX,
          displayName: 'ROG Ally X',
          isHandheld: true,
        );
      }
      if (prod.contains('RC71') || prod.contains('ALLY')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.rogAlly,
          displayName: 'ROG Ally',
          isHandheld: true,
        );
      }
    }

    // 3. Dòng máy Lenovo Legion Go
    if (mfr.contains('LENOVO')) {
      if (prod.contains('8APU1') || prod.contains('83E1') || prod.contains('LEGION GO')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.legionGo,
          displayName: 'Lenovo Legion Go',
          isHandheld: true,
        );
      }
    }

    // 4. Dòng máy Valve Steam Deck
    if (mfr.contains('VALVE')) {
      if (prod.contains('GALILEO')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.steamDeckOled,
          displayName: 'Steam Deck OLED',
          isHandheld: true,
        );
      }
      if (prod.contains('JUPITER') || prod.contains('STEAM')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.steamDeckLcd,
          displayName: 'Steam Deck LCD',
          isHandheld: true,
        );
      }
    }

    // 5. Dòng máy AYANEO
    if (mfr.contains('AYANEO') || prod.contains('AYANEO')) {
      return DeviceInfo(
        manufacturer: rawMfr,
        productName: rawProd,
        model: HandheldModel.ayaneo,
        displayName: 'AYANEO Handheld',
        isHandheld: true,
      );
    }

    // 6. Dòng máy MSI Claw
    if (mfr.contains('MICRO-STAR') || mfr.contains('MSI')) {
      if (prod.contains('CLAW')) {
        return DeviceInfo(
          manufacturer: rawMfr,
          productName: rawProd,
          model: HandheldModel.msiClaw,
          displayName: 'MSI Claw',
          isHandheld: true,
        );
      }
    }

    // 7. Dòng máy OneXPlayer / AOKZOE
    if (mfr.contains('ONE-NETBOOK') || mfr.contains('ONEXPLAYER') || prod.contains('ONEXPLAYER')) {
      return DeviceInfo(
        manufacturer: rawMfr,
        productName: rawProd,
        model: HandheldModel.onexplayer,
        displayName: 'OneXPlayer',
        isHandheld: true,
      );
    }
    if (mfr.contains('AOKZOE') || prod.contains('AOKZOE')) {
      return DeviceInfo(
        manufacturer: rawMfr,
        productName: rawProd,
        model: HandheldModel.aokzoe,
        displayName: 'AOKZOE',
        isHandheld: true,
      );
    }

    // 8. Máy tính PC thông thường
    return DeviceInfo(
      manufacturer: rawMfr.isEmpty ? 'Unknown' : rawMfr,
      productName: rawProd.isEmpty ? 'Generic PC' : rawProd,
      model: HandheldModel.genericPc,
      displayName: rawProd.isNotEmpty ? rawProd : 'Windows PC',
      isHandheld: false,
    );
  }
}
