import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Унифицированная кнопка Orpheus.
///
/// Философия:
/// - Primary (зелёный) — главное действие, "вперёд", "подтвердить"
/// - Secondary (серебро с border) — альтернативное действие
/// - Tertiary (текст) — третичное действие
/// - Danger (красный) — опасное действие
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.fullWidth = true,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool fullWidth;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    final child = isLoading
        ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == AppButtonVariant.primary
                    ? Colors.black54
                    : AppColors.textSecondary,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 10),
              ],
              // Flexible + FittedBox(scaleDown): длинные RU-подписи (напр. «Отмена»,
              // «Добавить») в узких кнопках диалога ужимаются, а НЕ режутся в «...»
              // (ellipsis раньше давал «Отм…»/«Доба…»). Если подпись влезает — масштаб 1:1.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );

    // Размеры
    final size = fullWidth
        ? const Size(double.infinity, 52)
        : const Size(0, 48);
    final padding = fullWidth
        ? const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 14);

    return switch (variant) {
      AppButtonVariant.primary => ElevatedButton(
          onPressed: isDisabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.action,
            foregroundColor: Colors.black,
            disabledBackgroundColor: AppColors.action.withOpacity(0.4),
            disabledForegroundColor: Colors.black45,
            minimumSize: size,
            padding: padding,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.2,
            ),
          ),
          child: child,
        ),
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: isDisabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.primaryDark,
            side: BorderSide(
              color: isDisabled
                  ? AppColors.outline.withOpacity(0.5)
                  : AppColors.outline,
            ),
            minimumSize: size,
            padding: padding,
            shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.1,
            ),
          ),
          child: child,
        ),
      AppButtonVariant.tertiary => TextButton(
          onPressed: isDisabled ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.action,
            disabledForegroundColor: AppColors.textTertiary,
            minimumSize: fullWidth ? const Size(double.infinity, 48) : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          child: child,
        ),
      AppButtonVariant.danger => ElevatedButton(
          onPressed: isDisabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.danger.withOpacity(0.4),
            disabledForegroundColor: Colors.white54,
            minimumSize: size,
            padding: padding,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.2,
            ),
          ),
          child: child,
        ),
    };
  }
}

enum AppButtonVariant { primary, secondary, tertiary, danger }

class AppIconButton extends StatelessWidget {
  const AppIconButton({
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

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: color ?? AppColors.textSecondary),
    );
  }
}
