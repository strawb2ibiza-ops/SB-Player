import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../branding/sb_brand.dart';

class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child, this.dense = false});

  final Widget child;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: SbBrand.black),
        const _Nebula(),
        CustomPaint(painter: _StarPainter(dense: dense)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                SbBrand.black.withValues(alpha: 0.96),
                SbBrand.black.withValues(alpha: 0.68),
                SbBrand.black.withValues(alpha: 0.30),
                SbBrand.black.withValues(alpha: 0.72),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Nebula extends StatelessWidget {
  const _Nebula();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          right: -180,
          top: -160,
          width: 760,
          height: 760,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  SbBrand.purple.withValues(alpha: 0.28),
                  SbBrand.deepBlue.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 180,
          bottom: -300,
          width: 980,
          height: 980,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  SbBrand.electricBlue.withValues(alpha: 0.24),
                  SbBrand.deepBlue.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter({required this.dense});

  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(27);
    final paint = Paint();
    final count = dense ? 105 : 70;

    for (var i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 1.25 + 0.35;
      paint.color = (i % 5 == 0
              ? SbBrand.brightBlue
              : i % 11 == 0
                  ? SbBrand.purple
                  : Colors.white)
          .withValues(alpha: random.nextDouble() * 0.32 + 0.12);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      dense != oldDelegate.dense;
}
