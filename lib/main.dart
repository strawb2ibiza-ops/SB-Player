import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/services/secure_account_store.dart';
import 'src/state/app_controller.dart';

const bool _androidTv = bool.fromEnvironment('SB_ANDROID_TV', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(900, 600),
      center: true,
      title: 'SB Player',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final config = AppConfig.fromEnvironment();
  final controller = AppController(
    config: config,
    accountStore: const SecureAccountStore(),
  );

  if (Platform.environment['SB_PLAYER_UI_CAPTURE'] == '1') {
    controller.enterUiCaptureMode();
  }

  runApp(SbPlayerApp(controller: controller, tvMode: _androidTv));
}
