import 'package:flutter/material.dart';

/// Hệ thống màu sắc và phong cách giao diện phong cách XBOX Gaming Bar cho máy Handheld.
class AppTheme {
  AppTheme._();

  // Bảng màu chuẩn XBOX Gaming Bar (Dark Acrylic / Xbox Green Accent)
  static const Color background = Color(0xF21C1C1C); // Nền tối xám khói Acrylic Xbox
  static const Color cardBackground = Color(0xFF262626); // Nền thẻ đậm chất Xbox Fluent
  static const Color cardBorder = Color(0x22FFFFFF); // Viền kính mờ tinh tế
  static const Color primaryNeon = Color(0xFF107C10); // Màu xanh Xbox Signature Green
  static const Color accentGreen = Color(0xFF2ECC71); // Màu xanh lá sáng cho điểm nhấn
  static const Color secondaryNeon = Color(0xFF108910); // Xanh Xbox thứ cấp
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA6A6A6);
  static const Color textAccent = Color(0xFF2ECC71);
  static const Color danger = Color(0xFFE81123);

  // Gradient màu Xbox
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF107C10), Color(0xFF2ECC71)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sliderGradient = LinearGradient(
    colors: [Color(0xFF107C10), Color(0xFF2ECC71)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Độ bo góc Fluent Xbox
  static const double panelRadius = 16.0;
  static const double cardRadius = 10.0;
  static const double buttonRadius = 8.0;

  // Kiểu chữ chuẩn
  static const TextStyle headerTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: 0.5,
  );

  static const TextStyle headerSubtitle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Color(0xFFE0E0E0),
  );

  static const TextStyle cardValue = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: accentGreen,
  );

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: accentGreen,
        surface: cardBackground,
      ),
    );
  }
}
