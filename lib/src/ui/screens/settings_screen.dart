import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/playback_preferences.dart';
import '../../state/app_controller.dart';
import '../branding/sb_brand.dart';
import '../widgets/sb_logo.dart';
import '../widgets/desktop_window_controls.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final prefs = controller.preferences;
        return Scaffold(
          appBar: AppBar(
            title: const DragToMoveArea(
              child: SizedBox(
                height: 42,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Settings'),
                ),
              ),
            ),
            actions: const [DesktopWindowControls()],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: SbLogo(
                  symbolSize: 42,
                  compact: true,
                  showTagline: false,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Playback',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              _SettingTile(
                title: 'Autoplay next episode',
                subtitle:
                    'Start the next episode automatically when one finishes.',
                value: prefs.autoplayNextEpisode,
                onChanged: (value) => controller.updatePreferences(
                  prefs.copyWith(autoplayNextEpisode: value),
                ),
              ),
              _SettingTile(
                title: 'Show Skip Intro',
                subtitle:
                    'Use conservative episode timing detection to offer a skip.',
                value: prefs.showSkipIntro,
                onChanged: (value) => controller.updatePreferences(
                  prefs.copyWith(showSkipIntro: value),
                ),
              ),
              _SettingTile(
                title: 'Auto-skip detected intros',
                subtitle:
                    'Experimental. Automatically skips when the intro window is detected.',
                value: prefs.autoSkipIntro,
                enabled: prefs.showSkipIntro,
                onChanged: (value) => controller.updatePreferences(
                  prefs.copyWith(autoSkipIntro: value),
                ),
              ),
              _SettingTile(
                title: 'Show Skip Credits',
                subtitle:
                    'Offer a credits skip near the end of episodes.',
                value: prefs.showSkipCredits,
                onChanged: (value) => controller.updatePreferences(
                  prefs.copyWith(showSkipCredits: value),
                ),
              ),
              _SettingTile(
                title: 'Auto-skip detected credits',
                subtitle:
                    'Experimental. Moves to the next episode when credits are detected.',
                value: prefs.autoSkipCredits,
                enabled: prefs.showSkipCredits,
                onChanged: (value) => controller.updatePreferences(
                  prefs.copyWith(autoSkipCredits: value),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Updates & data',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              const _InfoCard(
                title: 'Automatic profile & settings migration',
                body:
                    'SB Player keeps the same secure storage keys and installer identity between versions. Saved accounts, favourites, recent history, resume positions, mini-player geometry and playback settings are preserved when you install an update over the existing version.',
              ),
              const SizedBox(height: 12),
              const _InfoCard(
                title: 'Storage schema',
                body:
                    'Current schema: v2. Future releases can migrate older data without clearing your profiles or preferences.',
              ),
              const SizedBox(height: 28),
              Text(
                'About',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              _InfoCard(
                title: 'SB Player 0.6.0',
                body: controller.config.isLocked
                    ? 'SB Edition'
                    : 'Open Edition',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: SwitchListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: SbBrand.brightBlue,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SbBrand.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
