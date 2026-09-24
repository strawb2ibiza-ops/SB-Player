import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/playback_preferences.dart';
import '../../state/app_controller.dart';
import '../widgets/account_manager_dialog.dart';
import 'link_tv_screen.dart';
import 'tv_remote_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _prefs = PlaybackPreferences();
  bool _autoPip = true;
  bool _loaded = false;
  double _uiScale = 1.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final value = await _prefs.readAutoPip();
    final uiScale = await _prefs.readUiScale();
    if (mounted) setState(() { _autoPip = value; _uiScale = uiScale; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        const ListTile(title: Text('Playback'), leading: Icon(Icons.play_circle_outline)),
        SwitchListTile(
          title: const Text('Automatically enter Picture-in-Picture'),
          subtitle: const Text('Keep video playing in a system PiP window when you leave the app.'),
          value: _autoPip,
          onChanged: !_loaded ? null : (value) async {
            setState(() => _autoPip = value);
            await _prefs.saveAutoPip(value);
          },
        ),
        const Divider(),
        const ListTile(title: Text('Appearance'), leading: Icon(Icons.display_settings_outlined)),
        ListTile(
          title: const Text('UI scale'),
          subtitle: Text('${(_uiScale * 100).round()}%'),
        ),
        Slider(
          min: 0.80,
          max: 1.25,
          divisions: 9,
          label: '${(_uiScale * 100).round()}%',
          value: _uiScale,
          onChanged: !_loaded ? null : (value) => setState(() => _uiScale = value),
          onChangeEnd: !_loaded ? null : (value) => _prefs.saveUiScale(value),
        ),
        const Divider(),
        const ListTile(title: Text('Account'), leading: Icon(Icons.person_outline)),
        if (Platform.isAndroid || Platform.isIOS)
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: const Text('Link a TV'),
            subtitle: const Text('Scan the QR code on SB Player for TV.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LinkTvScreen(controller: widget.controller),
              ),
            ),
          ),
        if (Platform.isAndroid || Platform.isIOS)
          ListTile(
            leading: const Icon(Icons.gamepad_rounded),
            title: const Text('TV Remote'),
            subtitle: const Text('Control your linked SB Player TV from this device.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TvRemoteScreen(),
              ),
            ),
          ),
        if (!widget.controller.config.isLocked)
          ListTile(
            title: const Text('Manage accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AccountManagerDialog(controller: widget.controller),
            ),
          ),
        ListTile(
          title: Text(widget.controller.account?.label ?? 'Current account'),
          subtitle: const Text('Signed in'),
        ),
        ListTile(
          title: const Text('Log out'),
          leading: const Icon(Icons.logout),
          onTap: () async {
            await widget.controller.logout();
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}
