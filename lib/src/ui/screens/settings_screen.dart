import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/playback_preferences.dart';
import '../../state/app_controller.dart';
import '../widgets/account_manager_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final value = await _prefs.readAutoPip();
    if (mounted) setState(() { _autoPip = value; _loaded = true; });
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
        const ListTile(title: Text('Account'), leading: Icon(Icons.person_outline)),
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
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}
