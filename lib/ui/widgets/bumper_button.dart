import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Định nghĩa các loại nút cò và bumper trên tay cầm Handheld.
enum BumperType {
  lb,
  rb,
  lt,
  rt;

  String get label => name.toUpperCase();

  static BumperType fromString(String text) {
    switch (text.trim().toUpperCase()) {
      case 'LB':
        return BumperType.lb;
      case 'RB':
        return BumperType.rb;
      case 'LT':
        return BumperType.lt;
      case 'RT':
        return BumperType.rt;
      default:
        return BumperType.lb;
    }
  }
}

/// Widget nút hiển thị phím tắt hình dáng chuẩn nút phần cứng LB, RB, LT, RT.
class BumperButton extends StatelessWidget {
  final BumperType type;
  final String? label;
  final bool isEnabled;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const BumperButton({
    super.key,
    this.type = BumperType.lb,
    this.label,
    this.isEnabled = true,
    this.onTap,
    this.width = 44.0,
    this.height = 22.0,
  });

  /// Factory tiện lợi khởi tạo trực tiếp từ chuỗi ("LB", "RB", "LT", "RT")
  factory BumperButton.fromLabel({
    Key? key,
    required String label,
    bool isEnabled = true,
    VoidCallback? onTap,
    double width = 44.0,
    double height = 22.0,
  }) {
    return BumperButton(
      key: key,
      type: BumperType.fromString(label),
      label: label,
      isEnabled: isEnabled,
      onTap: onTap,
      width: width,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveType = label != null ? BumperType.fromString(label!) : type;
    final displayLabel = label ?? effectiveType.label;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: displayLabel,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        splashColor: AppTheme.primary.withValues(alpha: 0.2),
        highlightColor: AppTheme.primary.withValues(alpha: 0.1),
        child: CustomPaint(
          size: Size(width, height),
          painter: _BumperPainter(type: effectiveType),
          child: SizedBox(
            width: width,
            height: height,
            child: Center(
              child: Padding(
                padding: _getTextOffset(effectiveType),
                child: Text(
                  displayLabel,
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isEnabled
                        ? AppTheme.textSecondary
                        : AppTheme.textDisabled,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _getTextOffset(BumperType type) {
    switch (type) {
      case BumperType.lb:
        return const EdgeInsets.only(left: 4);
      case BumperType.rb:
        return const EdgeInsets.only(right: 4);
      case BumperType.lt:
        return const EdgeInsets.only(left: 2, top: 1);
      case BumperType.rt:
        return const EdgeInsets.only(right: 2, top: 1);
    }
  }
}

/// CustomPainter vẽ chính xác đường nét góc vát của Bumper (LB/RB) và độ dốc của Trigger (LT/RT).
class _BumperPainter extends CustomPainter {
  final BumperType type;

  _BumperPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = AppTheme.cardBackground
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = AppTheme.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = _getButtonPath(type, w, h);

    // 1. Đổ bóng nhẹ mặt sau
    canvas.drawPath(path, fillPaint);

    // 2. Vẽ viền nút vát góc
    canvas.drawPath(path, borderPaint);
  }

  Path _getButtonPath(BumperType type, double w, double h) {
    final path = Path();

    switch (type) {
      case BumperType.lb:
        // LB: Vai trái bo cong sâu và lượn dài, thuôn dẹt về phía trong
        path.moveTo(w, h - 3);
        path.quadraticBezierTo(w, h, w - 3, h);
        path.lineTo(6, h);
        path.quadraticBezierTo(1, h, 0, h - 4);
        path.lineTo(0, 12);
        path.cubicTo(0, 4, 5, 0, 18, 0); // Vai ngoài trái uốn lượn sâu và mượt
        path.lineTo(w - 3, 0);
        path.quadraticBezierTo(w, 0, w, 3);
        path.close();
        break;

      case BumperType.rb:
        // RB: Đối xứng của LB, vai phải bo cong sâu và lượn dài
        path.moveTo(0, 3);
        path.quadraticBezierTo(0, 0, 3, 0);
        path.lineTo(w - 18, 0);
        path.cubicTo(w - 5, 0, w, 4, w, 12); // Vai ngoài phải uốn lượn sâu và mượt
        path.lineTo(w, h - 4);
        path.quadraticBezierTo(w - 1, h, w - 6, h);
        path.lineTo(3, h);
        path.quadraticBezierTo(0, h, 0, h - 3);
        path.close();
        break;

      case BumperType.lt:
        // LT: Cò trái dạng báng kéo, dốc cong vào trong
        path.moveTo(w, h - 4);
        path.quadraticBezierTo(w, h, w - 4, h);
        path.lineTo(9, h);
        path.quadraticBezierTo(3, h - 1, 2, h - 6);
        path.lineTo(0, 6);
        path.quadraticBezierTo(0, 0, 6, 0);
        path.lineTo(w - 3, 0);
        path.quadraticBezierTo(w, 0, w, 3);
        path.close();
        break;

      case BumperType.rt:
        // RT: Cò phải dạng báng kéo, dốc cong vào trong
        path.moveTo(0, 3);
        path.quadraticBezierTo(0, 0, 3, 0);
        path.lineTo(w - 6, 0);
        path.quadraticBezierTo(w, 0, w, 6);
        path.lineTo(w - 2, h - 6);
        path.quadraticBezierTo(w - 3, h - 1, w - 9, h);
        path.lineTo(4, h);
        path.quadraticBezierTo(0, h, 0, h - 4);
        path.close();
        break;
    }

    return path;
  }

  @override
  bool shouldRepaint(covariant _BumperPainter oldDelegate) {
    return oldDelegate.type != type;
  }
}
