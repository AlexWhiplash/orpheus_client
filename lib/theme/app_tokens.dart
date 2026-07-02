import 'package:flutter/material.dart';

/// Единые UI-токены Orpheus — Quiet Premium.
///
/// Философия: серебро как основа, зелёный как акцент действия.
/// Минимализм без скуки.
class AppColors {
  // ═══════════════════════════════════════════════════════════════
  // BACKGROUNDS — глубокий тёмный, но не мёртвый чёрный
  // ═══════════════════════════════════════════════════════════════
  static const Color bg = Color(0xFF0B0D10);
  static const Color surface = Color(0xFF12161C);
  static const Color surface2 = Color(0xFF171D25);
  static const Color surfaceElevated =
      Color(0xFF1C222B); // Для карточек с фокусом

  // ═══════════════════════════════════════════════════════════════
  // TEXT — тёплое серебро, не холодный серый
  // ═══════════════════════════════════════════════════════════════
  static const Color textPrimary = Color(0xFFE8EEF6);
  static const Color textSecondary = Color(0xFF9AA7B6);
  static const Color textTertiary = Color(0xFF6E7B8A);

  // ═══════════════════════════════════════════════════════════════
  // PRIMARY — тёплое серебро с характером
  // Не мёртвый серый, а "лунное серебро" с лёгким тёплым оттенком
  // ═══════════════════════════════════════════════════════════════
  static const Color primary = Color(0xFFCDD6E0); // Тёплое серебро
  static const Color primaryLight =
      Color(0xFFE2E8F0); // Светлое серебро для hover
  static const Color primaryDark =
      Color(0xFFA8B5C4); // Приглушённое для disabled

  // ═══════════════════════════════════════════════════════════════
  // ACTION — зелёный для ключевых CTA
  // Это "действие", "безопасность", "вперёд"
  // ═══════════════════════════════════════════════════════════════
  static const Color action = Color(0xFF6AD394); // Мятный зелёный
  static const Color actionLight = Color(0xFF8ADBA8);
  static const Color actionDark = Color(0xFF4CAF7A);

  // ═══════════════════════════════════════════════════════════════
  // ACCENT — серебро для декоративных элементов, иконок
  // ═══════════════════════════════════════════════════════════════
  static const Color accent = Color(0xFFB9C7D6); // Серебристый

  // ═══════════════════════════════════════════════════════════════
  // SEMANTICS — состояния
  // ═══════════════════════════════════════════════════════════════
  static const Color success = Color(0xFF6AD394);
  static const Color info = Color(0xFF4A90D9);
  static const Color warning = Color(0xFFF2B84B);
  static const Color danger = Color(0xFFE57373);

  // ═══════════════════════════════════════════════════════════════
  // LINES — еле заметные, воздушные
  // ═══════════════════════════════════════════════════════════════
  static Color divider = Colors.white.withOpacity(0.06);
  static Color outline = Colors.white.withOpacity(0.10);
  static Color outlineFocus = const Color(0xFF6AD394).withOpacity(0.5);
}

class AppRadii {
  static const BorderRadius sm = BorderRadius.all(Radius.circular(14));
  static const BorderRadius md = BorderRadius.all(Radius.circular(18));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(24));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(32));
}

class AppSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppTypography {
  static TextTheme textTheme(TextTheme base) {
    final t = base.apply(fontFamily: 'Inter');
    return t.copyWith(
      // Titles
      titleLarge: t.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 0.1,
        height: 1.25,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.05,
        height: 1.25,
      ),
      titleSmall: t.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.02,
        height: 1.3,
      ),
      // Body
      bodyLarge: t.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: t.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      ),
      bodySmall: t.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
        height: 1.45,
      ),
      // Labels
      labelLarge: t.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        height: 1.2,
      ),
      labelMedium: t.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      labelSmall: t.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
    );
  }
}

class AppShadows {
  /// Мягкая тень — почти невидимая, но даёт глубину.
  static List<BoxShadow> soft({double opacity = 0.18}) {
    return [
      BoxShadow(
        color: Colors.black.withOpacity(opacity),
        blurRadius: 24,
        spreadRadius: -10,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Свечение для активных элементов.
  static List<BoxShadow> glow(Color color, {double opacity = 0.25}) {
    return [
      BoxShadow(
        color: color.withOpacity(opacity),
        blurRadius: 20,
        spreadRadius: -4,
      ),
    ];
  }
}

/// Генератор цвета аватара на основе имени.
class AppAvatarColors {
  /// Генерирует цвет на основе имени контакта.
  static Color fromName(String name) {
    if (name.isEmpty) return AppColors.surface2;
    final hash = name.hashCode;
    final hue = (hash.abs() % 360).toDouble();
    // Приглушённая насыщенность и средняя яркость — не кричит
    return HSLColor.fromAHSL(1.0, hue, 0.40, 0.42).toColor();
  }

  /// Возвращает пару цветов для градиента.
  static List<Color> gradientFromName(String name) {
    final baseColor = fromName(name);
    final hsl = HSLColor.fromColor(baseColor);
    return [
      hsl.withLightness((hsl.lightness + 0.06).clamp(0.0, 1.0)).toColor(),
      hsl.withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0)).toColor(),
    ];
  }
}
