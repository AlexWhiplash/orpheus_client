import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Аватар собеседника на экране звонка: стальной скруглённый квадрат ~74dp
/// с фаской, без пульсаций и свечения.
class CallAvatar extends StatelessWidget {
  const CallAvatar({
    super.key,
    required this.name,
    required this.connected,
    this.size = 74,
  });

  final String name;
  final bool connected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: connected ? AppColors.surfaceElevated : AppColors.surface2,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(
          color: connected
              ? AppColors.primaryDark.withOpacity(0.35)
              : AppColors.outline,
          width: 1,
        ),
        boxShadow: AppShadows.bevel(depth: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : "?",
        style: TextStyle(
          fontSize: size * 0.36,
          color: connected ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Индикатор голоса: пять серебряных полос знака Orpheus. Силуэт щита —
/// средняя полоса выше, крайние ниже; общий уровень «дышит» от [levels].
class CallVoiceBars extends StatelessWidget {
  const CallVoiceBars({super.key, required this.levels, this.height = 46});

  /// Уровни 0..1 (любое количество); берётся их среднее.
  final List<double> levels;
  final double height;

  static const List<double> _shield = [0.38, 0.66, 1.0, 0.66, 0.38];

  @override
  Widget build(BuildContext context) {
    final mean = levels.isEmpty
        ? 0.0
        : levels.reduce((a, b) => a + b) / levels.length;
    final level = (0.55 + 0.45 * mean.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _shield.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 5,
              height: (height * _shield[i] * level).clamp(6.0, height),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}
