import 'package:flutter/material.dart';

/// Hệ thống màu sắc & Theme giao diện chuẩn Monochrome Matte Black & Clean White cho máy Handheld.
class AppTheme {
  AppTheme._();

  // Nền tối OLED Stealth Black Acrylic
  static const Color background = Color(0xF20A0B0E);

  // Nền thẻ Matte Gunmetal kim loại
  static const Color cardBackground = Color(0xFF14151B);

  // Viền kính mờ titan phay xước siêu mảnh
  static const Color cardBorder = Color(0x1CFFFFFF);

  // Trắng tinh khiết chuẩn Minimalist Hardware
  static const Color primary = Color(0xFFFFFFFF);

  // Trắng bạc ánh kim sang trọng
  static const Color accent = Color(0xFFE5E7EB);

  // Xám titan trầm
  static const Color secondary = Color(0xFF374151);

  // Bạc kim loại thể thao thanh lịch
  static const Color accent2 = Color(0xFFF3F4F6);

  // Vàng nhạt cảnh báo hệ thống
  static const Color warning = Color(0xFFF59E0B);

  // Đỏ cảnh báo nguy hiểm
  static const Color danger = Color(0xFFEF4444);

  // Nền thẻ tab Titanium nâng khối
  static const Color tabSelected = Color(0xFF23252E);

  // Nền thẻ tab chưa chọn chìm phẳng
  static const Color tabUnselected = Color(0xFF0F1014);

  // Chữ trắng tinh khiết tương phản cao
  static const Color textPrimary = Color(0xFFFFFFFF);

  // Chữ phụ bạc kim loại chống mỏi mắt
  static const Color textSecondary = Color(0xFF9CA3AF);

  // Chữ điểm nhấn trắng sáng
  static const Color textAccent = Color(0xFFFFFFFF);

  // Chữ vô hiệu hóa
  static const Color textDisabled = Color(0xFF4B5563);

  static const Color shadow = Color(0xFF000000);
  static const Color transparent = Colors.transparent;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFD1D5DB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sliderGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFF9CA3AF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const double panelRadius = 16.0;
  static const double cardRadius = 10.0;
  static const double buttonRadius = 8.0;

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
    color: textPrimary,
  );

  static const TextStyle cardValue = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: transparent,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        surface: cardBackground,
      ),
    );
  }
}
