import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/iptv_profile.dart';

class AccountProfilesStore {
  const AccountProfilesStore();

  static const _profilesKey = 'sb_player.open_profiles.v1';
  static const _activeProfileKey = 'sb_player.active_profile.v1';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<List<IptvProfile>> loadProfiles() async {
    try {
      final raw = await _storage.read(key: _profilesKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        await _storage.delete(key: _profilesKey);
        return const [];
      }
      final profiles = <IptvProfile>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          final profile =
              IptvProfile.fromJson(Map<String, dynamic>.from(item));
          if (profile.id.isNotEmpty) profiles.add(profile);
        } catch (_) {
          // Ignore malformed entries without losing the remaining profiles.
        }
      }
      profiles.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return profiles;
    } catch (_) {
      try {
        await _storage.delete(key: _profilesKey);
      } catch (_) {
        // Ignore cleanup failures and continue without saved profiles.
      }
      return const [];
    }
  }

  Future<void> saveProfiles(List<IptvProfile> profiles) {
    return _storage.write(
      key: _profilesKey,
      value: jsonEncode(
        profiles.map((profile) => profile.toJson()).toList(growable: false),
      ),
    );
  }

  Future<String?> readActiveProfileId() {
    return _storage.read(key: _activeProfileKey);
  }

  Future<void> setActiveProfileId(String? id) {
    if (id == null || id.isEmpty) {
      return _storage.delete(key: _activeProfileKey);
    }
    return _storage.write(key: _activeProfileKey, value: id);
  }
}
