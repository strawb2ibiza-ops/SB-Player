import 'package:flutter/material.dart';

import '../branding/sb_brand.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/sb_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scale = Tween(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackdrop(
        dense: true,
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SbLogo(
                    symbolSize: 118,
                    showTagline: true,
                  ),
                  SizedBox(height: 36),
                  SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: SbBrand.electricBlue,
                      backgroundColor: Color(0x3318A0FF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
