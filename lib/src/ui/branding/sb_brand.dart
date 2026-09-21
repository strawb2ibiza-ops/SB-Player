import 'package:flutter/material.dart';

abstract final class SbBrand {
  static const black = Color(0xFF040509);
  static const elevated = Color(0xFF080B12);
  static const panel = Color(0xFF0C1426);
  static const panelBlue = Color(0xFF101D36);

  static const electricBlue = Color(0xFF18A0FF);
  static const brightBlue = Color(0xFF54C9FF);
  static const deepBlue = Color(0xFF315CFF);
  static const purple = Color(0xFF7A4DFF);

  static const textPrimary = Color(0xFFF8FAFF);
  static const textMuted = Color(0xFF96A0B5);

  static const liveError = Color(0xFFFF405B);
  static const success = Color(0xFF39D98A);
  static const reconnect = Color(0xFFFFB44A);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brightBlue, electricBlue, deepBlue, purple],
    stops: [0, 0.35, 0.68, 1],
  );

  static const horizontalBrandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brightBlue, electricBlue, deepBlue, purple],
  );

  static const String tagline = 'Premium watching, made easy.';
}
