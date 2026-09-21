import 'package:flutter_test/flutter_test.dart';
import 'package:sb_player/src/models/iptv_account.dart';
import 'package:sb_player/src/models/iptv_profile.dart';

void main() {
  test('saved IPTV profile round-trips through JSON', () {
    final profile = IptvProfile(
      id: 'profile-1',
      name: 'Living room',
      account: const IptvAccount(
        type: AccountType.xtream,
        label: 'Xtream',
        serverUrl: 'https://example.test',
        username: 'viewer',
        password: 'secret',
      ),
      updatedAt: DateTime.utc(2026, 9, 21),
    );

    final restored = IptvProfile.fromJson(profile.toJson());

    expect(restored.id, profile.id);
    expect(restored.name, 'Living room');
    expect(restored.account.type, AccountType.xtream);
    expect(restored.account.serverUrl, 'https://example.test');
    expect(restored.account.username, 'viewer');
    expect(restored.updatedAt, profile.updatedAt);
  });

  test('profile subtitle identifies provider and username', () {
    final profile = IptvProfile(
      id: 'profile-2',
      name: 'Sports',
      account: const IptvAccount(
        type: AccountType.xtream,
        label: 'Xtream',
        serverUrl: 'https://tv.example.test',
        username: 'ava',
      ),
      updatedAt: DateTime.utc(2026, 9, 21),
    );

    expect(profile.subtitle, 'tv.example.test • ava');
  });
}
