import 'package:flutter/material.dart';

class AppColors {
  // Primary Red Colors - from your colors.xml
  static const Color primaryRed = Color(0xFFEF5350); // red_400
  static const Color primaryRedDark = Color.fromARGB(255, 211, 47, 47);
  static const Color primaryRedDarker = Color(0xFF8B0000); // dark red

  // Background Colors - dark red gradient only
  static const Color backgroundStart = Color.fromARGB(
    255,
    199,
    9,
    5,
  ); // Dark red
  static const Color backgroundEnd = Color.fromARGB(
    255,
    199,
    9,
    5,
  ); // Even darker red

  // Card Background - white for cards floating on dark background
  static const Color cardBackground = Color(0xFFFFFFFF); // white
  static const Color cardBackgroundLight = Color(
    0xFFF5F5F5,
  ); // light grey for contrast

  // Accent Colors
  static const Color accent = Color(0xFFFF4081); // from @color/colorAccent

  // Status Colors
  static const Color success = Color(0xFF4CAF50); // green_500
  static const Color warning = Color(0xFFFFC107); // amber_500
  static const Color error = Color(0xFFF44336); // red_500
  static const Color info = Color(0xFF2196F3); // blue_500

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color darkGrey = Color(0xFF212121);
  static const Color mediumGrey = Color(0xFF757575);
  static const Color lightGrey = Color(0xFFE0E0E0);

  // Custom Colors from your app
  static const Color fastlineColor = Color(0xFF059FE2);
  static const Color qsBlue = Color(0xFF326BBC);
  static const Color profileColor = Color(0xFF089BE7);
  static const Color profileColor2 = Color(0xFF312684);

  // Background Colors from your XML
  static const Color bgContent = Color(0xFFFFFFFF);
  static const Color bgContentTop = Color(0xFF594691);
  static const Color bgGray = Color(0xFFECEDEF);

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);
}
