import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/iptv_account.dart';

class SecureAccountStore {
  const SecureAccountStore();

  static const _accountKey = 'sb_player.account.v1';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<void> save(IptvAccount account) =>
      _storage.write(key: _accountKey, value: account.encode());

  Future<IptvAccount?> read() async {
    final value = await _storage.read(key: _accountKey);
    if (value == null || value.isEmpty) return null;
    try {
      return IptvAccount.decode(value);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _accountKey);
}
