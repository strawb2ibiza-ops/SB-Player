import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PlaybackPreferences {
  const PlaybackPreferences({
    this.autoplayNextEpisode = true,
    this.showSkipIntro = true,
    this.autoSkipIntro = false,
    this.showSkipCredits = true,
    this.autoSkipCredits = false,
  });

  static const storageKey = 'sb_player.preferences.v2';
  static const schemaKey = 'sb_player.storage_schema';
  static const schemaVersion = 2;

  final bool autoplayNextEpisode;
  final bool showSkipIntro;
  final bool autoSkipIntro;
  final bool showSkipCredits;
  final bool autoSkipCredits;

  PlaybackPreferences copyWith({
    bool? autoplayNextEpisode,
    bool? showSkipIntro,
    bool? autoSkipIntro,
    bool? showSkipCredits,
    bool? autoSkipCredits,
  }) {
    return PlaybackPreferences(
      autoplayNextEpisode:
          autoplayNextEpisode ?? this.autoplayNextEpisode,
      showSkipIntro: showSkipIntro ?? this.showSkipIntro,
      autoSkipIntro: autoSkipIntro ?? this.autoSkipIntro,
      showSkipCredits: showSkipCredits ?? this.showSkipCredits,
      autoSkipCredits: autoSkipCredits ?? this.autoSkipCredits,
    );
  }

  Map<String, dynamic> toJson() => {
        'autoplayNextEpisode': autoplayNextEpisode,
        'showSkipIntro': showSkipIntro,
        'autoSkipIntro': autoSkipIntro,
        'showSkipCredits': showSkipCredits,
        'autoSkipCredits': autoSkipCredits,
      };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> json) {
    return PlaybackPreferences(
      autoplayNextEpisode: json['autoplayNextEpisode'] != false,
      showSkipIntro: json['showSkipIntro'] != false,
      autoSkipIntro: json['autoSkipIntro'] == true,
      showSkipCredits: json['showSkipCredits'] != false,
      autoSkipCredits: json['autoSkipCredits'] == true,
    );
  }
}

class PlaybackPreferencesStore {
  const PlaybackPreferencesStore();

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<void> migrate() async {
    try {
      final raw = await _storage.read(key: PlaybackPreferences.schemaKey);
      final current = int.tryParse(raw ?? '') ?? 1;

      // v2 intentionally keeps all v1 account/profile/library/mini-player
      // keys in place. This version marker gives future releases a safe
      // migration path without clearing user data.
      if (current < PlaybackPreferences.schemaVersion) {
        await _storage.write(
          key: PlaybackPreferences.schemaKey,
          value: PlaybackPreferences.schemaVersion.toString(),
        );
      }
    } catch (_) {
      // Migration must never prevent the app from starting.
    }
  }

  Future<PlaybackPreferences> load() async {
    try {
      final raw = await _storage.read(key: PlaybackPreferences.storageKey);
      if (raw == null || raw.isEmpty) return const PlaybackPreferences();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const PlaybackPreferences();
      return PlaybackPreferences.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const PlaybackPreferences();
    }
  }

  Future<void> save(PlaybackPreferences preferences) async {
    try {
      await _storage.write(
        key: PlaybackPreferences.storageKey,
        value: jsonEncode(preferences.toJson()),
      );
    } catch (_) {
      // Preferences are best-effort.
    }
  }
}
