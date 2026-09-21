import 'dart:math' as math;

import 'package:flutter/material.dart';

class SbBrand {
  const SbBrand._();

  static const black = Color(0xFF040509);
  static const elevated = Color(0xFF080B12);
  static const panel = Color(0xFF0C1426);
  static const panelBlue = Color(0xFF101D36);
  static const electricBlue = Color(0xFF18A0FF);
  static const brightBlue = Color(0xFF54C9FF);
  static const purple = Color(0xFF7A4DFF);
  static const text = Color(0xFFF8FAFF);
  static const muted = Color(0xFF96A0B5);
  static const live = Color(0xFFFF405B);
  static const success = Color(0xFF39D98A);
  static const warning = Color(0xFFFFB44A);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [electricBlue, Color(0xFF315CFF), purple],
  );

  static const tagline = 'Premium watching, made easy.';
}

class SbBrandMark extends StatelessWidget {
  const SbBrandMark({
    super.key,
    this.height = 54,
    this.showWordmark = false,
    this.showTagline = false,
    this.compact = false,
  });

  final double height;
  final bool showWordmark;
  final bool showTagline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final symbol = ShaderMask(
      shaderCallback: SbBrand.gradient.createShader,
      blendMode: BlendMode.srcIn,
      child: Text(
        compact ? 'SB' : 'S B',
        style: TextStyle(
          color: Colors.white,
          fontSize: height,
          height: 0.9,
          fontWeight: FontWeight.w900,
          letterSpacing: compact ? -4 : -2,
          shadows: const [
            Shadow(color: Color(0x9918A0FF), blurRadius: 16),
            Shadow(color: Color(0x667A4DFF), blurRadius: 28),
          ],
        ),
      ),
    );

    if (!showWordmark) return symbol;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        symbol,
        SizedBox(width: height * 0.24),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SB Player',
              style: TextStyle(
                fontSize: height * 0.46,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
            if (showTagline)
              Text(
                SbBrand.tagline,
                style: TextStyle(
                  color: SbBrand.muted,
                  fontSize: height * 0.19,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class SbGalaxyBackground extends StatelessWidget {
  const SbGalaxyBackground({
    super.key,
    required this.child,
    this.intensity = 1,
  });

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: SbBrand.black),
        Opacity(
          opacity: intensity.clamp(0, 1),
          child: const CustomPaint(painter: _GalaxyPainter()),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.72, -0.1),
              radius: 1.1,
              colors: [
                Colors.transparent,
                SbBrand.black.withValues(alpha: 0.28),
                SbBrand.black.withValues(alpha: 0.82),
              ],
              stops: const [0, 0.58, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class SbGlowBorder extends StatelessWidget {
  const SbGlowBorder({
    super.key,
    required this.child,
    this.selected = false,
    this.radius = 12,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool selected;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? SbBrand.panelBlue : SbBrand.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected
              ? SbBrand.electricBlue.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.09),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: SbBrand.electricBlue.withValues(alpha: 0.24),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }
}

class _GalaxyPainter extends CustomPainter {
  const _GalaxyPainter();

  static const _stars = <Offset>[
    Offset(.06, .12), Offset(.12, .42), Offset(.17, .76), Offset(.23, .26),
    Offset(.29, .61), Offset(.34, .09), Offset(.39, .83), Offset(.45, .35),
    Offset(.51, .67), Offset(.57, .16), Offset(.62, .47), Offset(.68, .79),
    Offset(.74, .29), Offset(.79, .56), Offset(.84, .11), Offset(.89, .72),
    Offset(.94, .38), Offset(.97, .88), Offset(.08, .91), Offset(.47, .93),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final blue = Paint()
      ..shader = RadialGradient(
        colors: [
          SbBrand.electricBlue.withValues(alpha: .28),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .28, size.height * .42),
          radius: math.min(size.width, size.height) * .58,
        ),
      );
    canvas.drawRect(Offset.zero & size, blue);

    final purple = Paint()
      ..shader = RadialGradient(
        colors: [
          SbBrand.purple.withValues(alpha: .22),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .82, size.height * .18),
          radius: math.min(size.width, size.height) * .52,
        ),
      );
    canvas.drawRect(Offset.zero & size, purple);

    for (var i = 0; i < _stars.length; i++) {
      final p = _stars[i];
      final radius = i % 5 == 0 ? 1.8 : (i % 3 == 0 ? 1.2 : .8);
      final color = i.isEven
          ? Colors.white.withValues(alpha: .34)
          : SbBrand.brightBlue.withValues(alpha: .4);
      canvas.drawCircle(
        Offset(size.width * p.dx, size.height * p.dy),
        radius,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
