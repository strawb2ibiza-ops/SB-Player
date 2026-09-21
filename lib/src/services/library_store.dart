import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/library_entry.dart';

class LibraryStore {
  const LibraryStore();

  static const _favoritesKey = 'sb_player.favorites.v1';
  static const _recentKey = 'sb_player.recent.v1';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

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
      await _storage.write(key: key, value: encoded);
    } catch (_) {
      // Library persistence is best-effort and must not interrupt playback.
    }
  }

  Future<List<LibraryEntry>> _load(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value == null || value.isEmpty) return const [];
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        await _storage.delete(key: key);
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map((item) => LibraryEntry.fromJson(Map<String, dynamic>.from(item)))
          .where((entry) => entry.id.isNotEmpty && entry.streamUrl.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // Ignore storage cleanup failures.
      }
      return const [];
    }
  }
}
