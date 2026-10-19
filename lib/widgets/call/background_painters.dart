import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

// Визуальная система Orpheus v1: без частиц, волн и неона.
// ParticlesPainter и WavePainter оставлены ради совместимости API (тесты),
// но больше ничего не рисуют.

/// Бывшие частицы на фоне. Ничего не рисует.
class ParticlesPainter extends CustomPainter {
  final double animationValue;
  ParticlesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Бывшие волны вокруг аватара. Ничего не рисует.
class WavePainter extends CustomPainter {
  final double animationValue;
  WavePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Тихий стальной радиальный фон: ступени bg -> surface, статичный.
/// [controller] сохранён ради совместимости API и не анимирует фон.
class CallBackground extends StatelessWidget {
  final AnimationController controller;
  const CallBackground({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.1,
          colors: [AppColors.surface2, AppColors.surface, AppColors.bg],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}
