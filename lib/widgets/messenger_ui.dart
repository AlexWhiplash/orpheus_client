import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Общие детали мессенджера в визуальной системе Orpheus v1: списки, шапки,
/// разделители дней. Только оформление — никакой логики.

/// Аватар — скруглённый квадрат цвета из [AppAvatarColors] с первой буквой имени.
class MessengerAvatar extends StatelessWidget {
  const MessengerAvatar({
    super.key,
    required this.name,
    this.size = 48,
    this.radius,
    this.fontSize,
  });

  final String name;
  final double size;

  /// По умолчанию ~ треть стороны (11 на 34 в макете).
  final double? radius;
  final double? fontSize;

  String get letter => name.isNotEmpty ? name[0].toUpperCase() : '?';

  /// Оттенок из [AppAvatarColors], приглушённый до стали канона (как в макете:
  /// тёмные синие/лиловые/зелёные плитки, а не яркие).
  static Color colorFor(String name) {
    final hsl = HSLColor.fromColor(AppAvatarColors.fromName(name));
    return hsl.withSaturation(0.26).withLightness(0.27).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorFor(name),
        borderRadius: BorderRadius.circular(radius ?? size * 0.32),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: fontSize ?? size * 0.36,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          height: 1,
        ),
      ),
    );
  }
}

/// Маленькая квадратная кнопка в шапке экрана: поверхность, радиус 8.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 18,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            minimumSize: const Size(size, size),
            fixedSize: const Size(size, size),
          ),
          icon: Icon(icon, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Разделитель дня в переписке: моноширинный, прописными, с разрядкой.
class ChatDaySeparator extends StatelessWidget {
  const ChatDaySeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          label.toUpperCase(),
          style: AppTypography.mono(
            fontSize: 11,
            color: AppColors.textTertiary,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

/// Счётчик непрочитанного — мятная капсула.
class UnreadCountPill extends StatelessWidget {
  const UnreadCountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.action,
        borderRadius: BorderRadius.all(Radius.circular(11)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.onAction,
          height: 1,
        ),
      ),
    );
  }
}

/// Строка присутствия под именем: «в сети» мятным, иначе приглушённо.
class PresenceLabel extends StatelessWidget {
  const PresenceLabel({
    super.key,
    required this.isOnline,
    required this.onlineText,
    required this.offlineText,
    this.fontSize = 11.5,
  });

  final bool isOnline;
  final String onlineText;
  final String offlineText;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      (isOnline ? onlineText : offlineText).toLowerCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.mono(
        fontSize: fontSize,
        color: isOnline ? AppColors.action : AppColors.textTertiary,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// Тонкий разделитель строк списка с отступом под аватар.
class ListRowDivider extends StatelessWidget {
  const ListRowDivider({super.key, this.indent = 76});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(height: 1, color: AppColors.divider),
    );
  }
}
