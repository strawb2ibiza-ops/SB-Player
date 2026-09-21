import 'package:flutter/material.dart';

import '../branding/sb_brand.dart';

class SbLogo extends StatelessWidget {
  const SbLogo({
    super.key,
    this.symbolSize = 64,
    this.showWordmark = true,
    this.showTagline = false,
    this.compact = false,
  });

  final double symbolSize;
  final bool showWordmark;
  final bool showTagline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final symbol = _SbSymbol(size: symbolSize);
    if (!showWordmark) return symbol;

    final wordmark = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          'SB Player',
          style: TextStyle(
            color: SbBrand.textPrimary,
            fontSize: symbolSize * 0.42,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.1,
            height: 1,
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: symbolSize * 0.12),
          Text(
            SbBrand.tagline,
            style: TextStyle(
              color: SbBrand.textMuted,
              fontSize: symbolSize * 0.17,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ],
    );

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          symbol,
          SizedBox(width: symbolSize * 0.20),
          wordmark,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        symbol,
        SizedBox(height: symbolSize * 0.12),
        wordmark,
      ],
    );
  }
}

class _SbSymbol extends StatelessWidget {
  const _SbSymbol({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          'S  B',
          style: TextStyle(
            fontSize: size,
            height: 0.9,
            fontWeight: FontWeight.w900,
            letterSpacing: -size * 0.13,
            color: SbBrand.electricBlue,
            shadows: [
              Shadow(
                color: SbBrand.electricBlue.withValues(alpha: 0.45),
                blurRadius: size * 0.22,
              ),
              Shadow(
                color: SbBrand.purple.withValues(alpha: 0.28),
                blurRadius: size * 0.38,
              ),
              Shadow(
                color: Colors.black.withValues(alpha: 0.9),
                blurRadius: size * 0.05,
                offset: Offset(0, size * 0.055),
              ),
            ],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: SbBrand.horizontalBrandGradient.createShader,
          child: Text(
            'S  B',
            style: TextStyle(
              fontSize: size,
              height: 0.9,
              fontWeight: FontWeight.w900,
              letterSpacing: -size * 0.13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
