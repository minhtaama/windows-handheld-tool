import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(
    0xF20A0B0E,
  ); // Nền tối OLED Stealth Black Acrylic
  static const Color cardBackground = Color(
    0xFF14151B,
  ); // Nền thẻ Matte Gunmetal kim loại
  static const Color cardBorder = Color(
    0x1CFFFFFF,
  ); // Viền kính mờ titan phay xước siêu mảnh
  static const Color primary = Color(
    0xFF2E6BFF,
  ); // Xanh Electric Cobalt chuẩn console phần cứng
  static const Color accent = Color(
    0xFF5C9DFF,
  ); // Xanh Ice Cobalt phát sáng lạnh sang trọng
  static const Color secondary = Color(
    0xFF1B4DC7,
  ); // Xanh Cobalt trầm
  static const Color accent2 = Color(
    0xFFFF7A45,
  ); // Cam ánh đồng Ember Coral thể thao (TDP)
  static const Color warning = Color(
    0xFFE5A93C,
  ); // Vàng Champagne kim loại / RTSS
  static const Color danger = Color(
    0xFFFF4D4F,
  ); // Đỏ thể thao
  static const Color tabSelected = Color(
    0xFF1F222C,
  ); // Nền thẻ tab Titanium nâng khối
  static const Color tabUnselected = Color(
    0xFF0F1014,
  ); // Nền thẻ tab chưa chọn chìm phẳng
  static const Color textPrimary = Color(
    0xFFFFFFFF,
  ); // Chữ trắng tinh khiết tương phản cao
  static const Color textSecondary = Color(
    0xFF8C909C,
  ); // Chữ phụ bạc kim loại chống mỏi mắt
  static const Color textAccent = Color(
    0xFF5C9DFF,
  ); // Chữ điểm nhấn Ice Cobalt
  static const Color textDisabled = Color(
    0xFF454854,
  ); // Chữ vô hiệu hóa
  static const Color shadow = Color(0xFF000000);
  static const Color transparent = Colors.transparent;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sliderGradient = LinearGradient(
    colors: [primary, accent],
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
    color: accent,
  );

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: transparent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: cardBackground,
      ),
    );
  }
}
