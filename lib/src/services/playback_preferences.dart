import 'package:shared_preferences/shared_preferences.dart';

class PlaybackPreferences {
  static const _autoPipKey = 'playback.auto_pip';

  Future<bool> readAutoPip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoPipKey) ?? true;
  }

  Future<void> saveAutoPip(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPipKey, value);
  }
}
