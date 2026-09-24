import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_entry.dart';

class LibraryStore {
  const LibraryStore();

  static const _favoritesKey = 'sb_player.favorites.v1';
  static const _recentKey = 'sb_player.recent.v1';

  FlutterSecureStorage get _legacySecureStorage =>
      const FlutterSecureStorage();

  Future<List<LibraryEntry>> loadFavorites() => _load(_favoritesKey);
  Future<List<LibraryEntry>> loadRecent() => _load(_recentKey);

  Future<void> saveFavorites(List<LibraryEntry> entries) =>
      _save(_favoritesKey, entries);

  Future<void> saveRecent(List<LibraryEntry> entries) =>
      _save(_recentKey, entries);

  Future<void> _save(String key, List<LibraryEntry> entries) async {
    try {
      final encoded = jsonEncode(
        entries.map((entry) => entry.toJson()).toList(growable: false),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, encoded);
    } catch (_) {
      // Library persistence is best-effort and must not interrupt playback.
    }
  }

  Future<List<LibraryEntry>> _load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var value = prefs.getString(key);

      // v0.6.8 and earlier stored non-sensitive library/history JSON in
      // secure storage. Migrate it once so playback checkpoints no longer
      // perform expensive Keychain/encrypted-storage writes every few seconds.
      if (value == null || value.isEmpty) {
        try {
          final legacy = await _legacySecureStorage.read(key: key);
          if (legacy?.isNotEmpty == true) {
            value = legacy;
            await prefs.setString(key, legacy!);
            await _legacySecureStorage.delete(key: key);
          }
        } catch (_) {
          // A missing/unavailable legacy secure store is not fatal.
        }
      }

      if (value == null || value.isEmpty) return const [];
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        await prefs.remove(key);
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map((item) => LibraryEntry.fromJson(Map<String, dynamic>.from(item)))
          .where((entry) => entry.id.isNotEmpty && entry.streamUrl.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {
        // Ignore storage cleanup failures.
      }
      return const [];
    }
  }
}
