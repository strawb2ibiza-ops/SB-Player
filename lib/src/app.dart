import 'dart:io';

import 'package:flutter/material.dart';

import 'models/content_section.dart';
import 'state/app_controller.dart';
import 'ui/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/splash_screen.dart';

class SbPlayerApp extends StatefulWidget {
  const SbPlayerApp({super.key, required this.controller, this.tvMode = false});

  final AppController controller;
  final bool tvMode;

  @override
  State<SbPlayerApp> createState() => _SbPlayerAppState();
}

class _SbPlayerAppState extends State<SbPlayerApp> {
  late final Future<void> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _restoreWithMinimumSplash();
  }

  Future<void> _restoreWithMinimumSplash() async {
    await Future.wait<void>([
      widget.controller.restoreSession(),
      Future<void>.delayed(const Duration(milliseconds: 900)),
    ]);
    if (Platform.environment['SB_PLAYER_UI_CAPTURE'] == '1') {
      widget.controller.enterUiCaptureMode();
      final section = Platform.environment['SB_PLAYER_CAPTURE_SECTION'];
      final match = ContentSection.values.where((value) => value.name == section);
      if (match.isNotEmpty) await widget.controller.selectSection(match.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.controller.config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SplashScreen();
          }

          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              if (widget.controller.signedIn) {
                return HomeScreen(controller: widget.controller, tvMode: widget.tvMode);
              }
              return LoginScreen(controller: widget.controller, tvMode: widget.tvMode);
            },
          );
        },
      ),
    );
  }
}
