import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum MiniPlayerLayout { detailed, videoOnly }

class MiniPlayerPreferences {
  const MiniPlayerPreferences();

  static const _layoutKey = 'sb_player.mini_player_layout.v1';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<MiniPlayerLayout> readLayout() async {
    final value = await _storage.read(key: _layoutKey);
    return MiniPlayerLayout.values.firstWhere(
      (layout) => layout.name == value,
      orElse: () => MiniPlayerLayout.detailed,
    );
  }

  Future<void> saveLayout(MiniPlayerLayout layout) {
    return _storage.write(key: _layoutKey, value: layout.name);
  }
}
