// lib/theme/app_theme.dart
// Quiet Premium — серебро + зелёный акцент

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

class AppTheme {
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return baseTheme.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.action,
        brightness: Brightness.dark,
        primary: AppColors.action,
        onPrimary: Colors.black,
        secondary: AppColors.primary,
        onSecondary: Colors.black,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
        onError: Colors.white,
      ),

      // ТИПОГРАФИКА
      textTheme: AppTypography.textTheme(GoogleFonts.interTextTheme(baseTheme.textTheme)),

      // APP BAR — чистый, без лишнего
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 17,
          letterSpacing: 0.2,
        ),
      ),

      // КАРТОЧКИ
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.md,
          side: BorderSide(color: AppColors.outline, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      ),

      // ДИАЛОГИ
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lg,
          side: BorderSide(color: AppColors.outline),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
      ),

      // ПОЛЯ ВВОДА
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: AppColors.textTertiary),
        border: OutlineInputBorder(
          borderRadius: AppRadii.md,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.md,
          borderSide: BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.md,
          borderSide: BorderSide(color: AppColors.action.withOpacity(0.6), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.md,
          borderSide: BorderSide(color: AppColors.danger),
        ),
      ),

      // КНОПКИ — зелёный action как primary CTA
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.action,
          foregroundColor: Colors.black,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.action,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.outline),
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),

      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.action,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
      ),

      // NAVIGATION BAR — серебряные иконки, зелёный индикатор
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.action.withOpacity(0.15),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              color: AppColors.action,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.action, size: 24);
          }
          return const IconThemeData(color: AppColors.textTertiary, size: 24);
        }),
      ),

      // ИКОНКИ
      iconTheme: const IconThemeData(color: AppColors.textSecondary),

      // SNACKBAR
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface2,
        contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.sm),
      ),

      // DIVIDER
      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),

      // PROGRESS INDICATOR — зелёный
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.action,
        linearTrackColor: AppColors.surface,
      ),

      // SLIDER
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.action,
        inactiveTrackColor: AppColors.surface,
        thumbColor: AppColors.action,
        overlayColor: AppColors.action.withOpacity(0.15),
      ),

      // SWITCH
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.action;
          return AppColors.primaryDark;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.action.withOpacity(0.35);
          }
          return AppColors.surface2;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return AppColors.outline;
        }),
      ),

      // CHECKBOX
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.action;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.black),
        side: BorderSide(color: AppColors.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // PAGE TRANSITIONS
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
