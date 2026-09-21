import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';

class SbPlayerApp extends StatelessWidget {
  const SbPlayerApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: controller.config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.signedIn) {
            return HomeScreen(controller: controller);
          }
          return LoginScreen(controller: controller);
        },
      ),
    );
  }
}
