import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Biểu đồ đường cong nhiệt độ - tốc độ quạt (Fan Curve Graph)
/// Hiển thị đường cong tương tác, các điểm mốc nhiệt độ và chấm chỉ báo thời gian thực.
class FanCurveGraph extends StatelessWidget {
  final List<List<int>> points;
  final int? liveTemp;
  final int liveFan;
  final bool isCustom;
  final int selectedPointIndex;
  final ValueChanged<int>? onSelectPoint;
  final bool isFocused;

  const FanCurveGraph({
    super.key,
    required this.points,
    this.liveTemp,
    required this.liveFan,
    this.isCustom = false,
    this.selectedPointIndex = 0,
    this.onSelectPoint,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
      padding: const EdgeInsets.fromLTRB(10, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isFocused ? AppTheme.accent : AppTheme.cardBorder,
          width: isFocused ? 1.5 : 1.0,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.ssid_chart_rounded,
                size: AppTheme.scaled(14),
                color: AppTheme.fan,
              ),
              const SizedBox(width: 6),
              Text(
                "ĐƯỜNG CONG TẢN NHIỆT",
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTheme.scaled(10),
                  letterSpacing: 0.6,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (liveTemp != null ? AppTheme.fan : AppTheme.warning).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: liveTemp != null ? AppTheme.fan : AppTheme.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      liveTemp != null ? "$liveTemp°C • $liveFan%" : "HVCI (!) • $liveFan%",
                      style: TextStyle(
                        fontSize: AppTheme.scaled(10),
                        fontWeight: FontWeight.w800,
                        color: liveTemp != null ? AppTheme.fan : AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRect(
              child: CustomPaint(
                size: Size.infinite,
                painter: _FanCurvePainter(
                  points: points,
                  liveTemp: liveTemp,
                  liveFan: liveFan,
                  isCustom: isCustom,
                  selectedPointIndex: selectedPointIndex,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("30°C", style: AppTheme.hint.copyWith(fontSize: 9)),
              Text("50°C", style: AppTheme.hint.copyWith(fontSize: 9)),
              Text("70°C", style: AppTheme.hint.copyWith(fontSize: 9)),
              Text("90°C", style: AppTheme.hint.copyWith(fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FanCurvePainter extends CustomPainter {
  final List<List<int>> points;
  final int? liveTemp;
  final int liveFan;
  final bool isCustom;
  final int selectedPointIndex;

  _FanCurvePainter({
    required this.points,
    this.liveTemp,
    required this.liveFan,
    required this.isCustom,
    required this.selectedPointIndex,
  });

  static const double minTemp = 30.0;
  static const double maxTemp = 90.0;
  static const double minFan = 0.0;
  static const double maxFan = 100.0;

  double _tempToX(double temp, double width) {
    final clamped = temp.clamp(minTemp, maxTemp);
    return ((clamped - minTemp) / (maxTemp - minTemp)) * width;
  }

  double _fanToY(double fan, double height) {
    final clamped = fan.clamp(minFan, maxFan);
    return height - ((clamped - minFan) / (maxFan - minFan)) * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppTheme.cardBorder.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;

    // 1. Grid lines (horizontal for 25%, 50%, 75%)
    for (int pct in [25, 50, 75]) {
      final y = _fanToY(pct.toDouble(), size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isEmpty) return;

    // 2. Build curve path
    final path = Path();
    final fillPath = Path();

    final sorted = List<List<int>>.from(points)..sort((a, b) => a[0].compareTo(b[0]));

    final startX = _tempToX(minTemp, size.width);
    final firstPointX = _tempToX(sorted.first[0].toDouble(), size.width);
    final firstPointY = _fanToY(sorted.first[1].toDouble(), size.height);

    path.moveTo(startX, firstPointY);
    path.lineTo(firstPointX, firstPointY);

    fillPath.moveTo(startX, size.height);
    fillPath.lineTo(startX, firstPointY);
    fillPath.lineTo(firstPointX, firstPointY);

    for (int i = 0; i < sorted.length; i++) {
      final x = _tempToX(sorted[i][0].toDouble(), size.width);
      final y = _fanToY(sorted[i][1].toDouble(), size.height);
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    final lastX = _tempToX(maxTemp, size.width);
    final lastPointY = _fanToY(sorted.last[1].toDouble(), size.height);
    path.lineTo(lastX, lastPointY);
    fillPath.lineTo(lastX, lastPointY);
    fillPath.lineTo(lastX, size.height);
    fillPath.close();

    // 3. Fill Gradient under curve
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.fan.withValues(alpha: 0.35),
          AppTheme.fan.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 4. Draw Line Stroke
    final strokePaint = Paint()
      ..color = AppTheme.fan
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 5. Draw point dots
    for (int i = 0; i < sorted.length; i++) {
      final x = _tempToX(sorted[i][0].toDouble(), size.width);
      final y = _fanToY(sorted[i][1].toDouble(), size.height);
      final isSelected = isCustom && i == selectedPointIndex;

      if (isSelected) {
        // Outer glowing ring
        final ringPaint = Paint()
          ..color = AppTheme.primary
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(Offset(x, y), 8, ringPaint);
      }

      final dotPaint = Paint()
        ..color = isSelected ? AppTheme.primary : AppTheme.fan
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), isSelected ? 5.0 : 3.5, dotPaint);

      final innerDot = Paint()
        ..color = AppTheme.background
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), isSelected ? 2.5 : 1.5, innerDot);
    }

    // 6. Draw Live Temperature Indicator Dot (Pulsing / Glowing)
    if (liveTemp != null && liveTemp! > 0) {
      final liveX = _tempToX(liveTemp!.toDouble(), size.width);
      final liveY = _fanToY(liveFan.toDouble(), size.height);

      // Outer glow
      final glowPaint = Paint()
        ..color = AppTheme.accent.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(liveX, liveY), 9, glowPaint);

      // Core dot
      final corePaint = Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(liveX, liveY), 4.5, corePaint);

      final centerWhite = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(liveX, liveY), 2.0, centerWhite);
    }
  }

  @override
  bool shouldRepaint(covariant _FanCurvePainter oldDelegate) {
    return oldDelegate.liveTemp != liveTemp ||
        oldDelegate.liveFan != liveFan ||
        oldDelegate.points != points ||
        oldDelegate.selectedPointIndex != selectedPointIndex ||
        oldDelegate.isCustom != isCustom;
  }
}
