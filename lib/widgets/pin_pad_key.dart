import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Клавиша PIN-пада (визуальная система Orpheus v1): круглая сталь с тонкой фаской,
/// без свечения. [plain] — «текстовая» клавиша без подложки (биометрия, стереть).
class PinPadKey extends StatelessWidget {
  const PinPadKey({
    super.key,
    required this.child,
    required this.onTap,
    this.plain = false,
    this.size = 72,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool plain;
  final double size;
  final String? semanticLabel;

  /// Цифра на клавише.
  static Widget digit(String d) => Text(
        d,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 27,
          fontWeight: FontWeight.w400,
          height: 1.0,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final key = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: plain
            ? const BoxDecoration(shape: BoxShape.circle)
            : BoxDecoration(
                shape: BoxShape.circle,
                // Еле заметная ступень сверху вниз — фаска вместо свечения.
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF161B22), AppColors.surface],
                ),
                boxShadow: AppShadows.bevel(),
              ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            splashColor: AppColors.primary.withOpacity(0.10),
            highlightColor: AppColors.primary.withOpacity(0.06),
            child: Center(child: child),
          ),
        ),
      ),
    );
    if (semanticLabel == null) return key;
    return Semantics(button: true, label: semanticLabel, child: key);
  }
}

/// Точки введённых цифр: залитые серебром, пустые — тонкое кольцо.
class PinDot extends StatelessWidget {
  const PinDot({super.key, required this.filled, this.error = false});

  final bool filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.danger : AppColors.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled || error ? color : Colors.transparent,
        border: Border.all(
          color: error
              ? AppColors.danger
              : filled
                  ? AppColors.primary
                  : AppColors.textTertiary,
          width: 1.5,
        ),
      ),
    );
  }
}
