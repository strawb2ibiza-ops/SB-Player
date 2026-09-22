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
          'Player',
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
    return SizedBox(
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: RichText(
          maxLines: 1,
          softWrap: false,
          text: const TextSpan(
            style: TextStyle(
              height: 0.9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
            children: [
              TextSpan(text: 'S', style: TextStyle(color: SbBrand.electricBlue)),
              TextSpan(text: 'B', style: TextStyle(color: SbBrand.purple)),
            ],
          ),
        ),
      ),
    );
  }
}
