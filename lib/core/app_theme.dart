import 'package:flutter/material.dart';

/// Hệ thống màu sắc và phong cách giao diện Dark Cyberpunk tối ưu cho máy Handheld.
class AppTheme {
  AppTheme._();

  // Bảng màu chính (Cyberpunk Neon / Deep Dark)
  static const Color background = Color(0xFA12141D); // Nền tối 98%
  static const Color cardBackground = Color(0xB31E2230); // Thẻ chức năng mờ
  static const Color cardBorder = Color(0x1AFFFFFF); // Viền thẻ mờ
  static const Color primaryNeon = Color(0xFF00D2FF); // Xanh Neon chủ đạo
  static const Color secondaryNeon = Color(0xFF9D00FF); // Tím Cyberpunk
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF7B889B);
  static const Color textAccent = Color(0xFF00D2FF);
  static const Color danger = Color(0xFFFF4757);

  // Gradient màu
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00D2FF), Color(0xFF9D00FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sliderGradient = LinearGradient(
    colors: [Color(0xFF00D2FF), Color(0xFF7000FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Độ bo góc
  static const double panelRadius = 24.0;
  static const double cardRadius = 14.0;
  static const double buttonRadius = 12.0;

  // Kiểu chữ chuẩn
  static const TextStyle headerTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: 0.5,
  );

  static const TextStyle headerSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFFB0C0D8),
  );

  static const TextStyle cardValue = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: primaryNeon,
  );

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: primaryNeon,
        surface: cardBackground,
      ),
    );
  }
}
