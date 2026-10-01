import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Centralized so all screens/widgets pull from the same source
class AppColors {
  static const primary = Color(0xFF2E7D32);      // Green - health/freshness
  static const secondary = Color(0xFFFB8C00);    // Orange - warmth, food
  static const danger = Color(0xFFD32F2F);       // Allergy/error red
  static const success = Color(0xFF43A047);      // Available nutrients
  static const background = Color(0xFFF7F9F7);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF1B1B1B);  // Near-black, high contrast
  static const textSecondary = Color(0xFF5F6368);
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

final appTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    error: AppColors.danger,
  ),
textTheme: TextTheme(
    bodyLarge: GoogleFonts.poppins(fontSize: 16, color: AppColors.textPrimary),
    bodyMedium: GoogleFonts.poppins(fontSize: 15, color: AppColors.textPrimary),
    bodySmall: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
    titleLarge: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleMedium: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleSmall: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    labelLarge: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
  ),
  // Every button meets the 48px minimum touch target
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size(64, 52),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(64, 52),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  iconTheme: const IconThemeData(size: 26), // Larger than Flutter's 24 default
  cardTheme: CardThemeData(
    elevation: 1,
    color: AppColors.surface,
    margin: const EdgeInsets.symmetric(vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
    ),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: GoogleFonts.poppins(
      fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.textSecondary,
    showUnselectedLabels: true,
    type: BottomNavigationBarType.fixed,
  ),
);