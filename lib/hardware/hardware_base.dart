/// Lớp cơ sở trừu tượng cho tất cả các bộ điều khiển phần cứng Handheld (DRY).
abstract class HardwareController {
  final String name;
  final int minVal;
  final int maxVal;
  final int step;
  final String unit;

  HardwareController({
    required this.name,
    required this.minVal,
    required this.maxVal,
    required this.step,
    required this.unit,
  });

  /// Kiểm tra xem phần cứng tương ứng có khả dụng trên thiết bị hay không.
  bool isAvailable();

  /// Lấy giá trị hiện tại của phần cứng.
  int getValue();

  /// Thiết lập giá trị mới cho phần cứng.
  bool setValue(int value);

  /// Giới hạn giá trị trong khoảng hợp lệ [minVal, maxVal].
  int clamp(int value) {
    if (value < minVal) return minVal;
    if (value > maxVal) return maxVal;
    return value;
  }
}
