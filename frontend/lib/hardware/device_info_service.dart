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

/// Dịch vụ nhận diện phần cứng máy Handheld từ thông tin hệ thống.
class DeviceInfoService {
  static DeviceInfo? _current;

  static const DeviceInfo _defaultDevice = DeviceInfo(
    manufacturer: 'GPD',
    productName: 'GPD Win 4',
    model: HandheldModel.gpdWin4,
    displayName: 'GPD Win 4',
    isHandheld: true,
  );

  static DeviceInfo get currentDevice => _current ?? _defaultDevice;

  static Future<DeviceInfo> init() async {
    _current ??= _defaultDevice;
    return _current!;
  }
}
