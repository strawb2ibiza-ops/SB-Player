import 'package:shared_preferences/shared_preferences.dart';

class SubtitlePreference {
  const SubtitlePreference._(this.mode, {this.language, this.title});

  const SubtitlePreference.auto() : this._('auto');
  const SubtitlePreference.off() : this._('off');
  const SubtitlePreference.match({String? language, String? title})
      : this._('match', language: language, title: title);

  final String mode;
  final String? language;
  final String? title;

  bool get isAuto => mode == 'auto';
  bool get isOff => mode == 'off';

  bool matches({String? language, String? title}) {
    if (mode != 'match') return false;
    final wantedLanguage = _normalize(this.language);
    final wantedTitle = _normalize(this.title);
    final candidateLanguage = _normalize(language);
    final candidateTitle = _normalize(title);

    if (wantedLanguage.isNotEmpty && candidateLanguage == wantedLanguage) {
      return true;
    }
    return wantedTitle.isNotEmpty && candidateTitle == wantedTitle;
  }

  static String _normalize(String? value) =>
      (value ?? '').trim().toLowerCase();
}

class PlaybackPreferences {
  const PlaybackPreferences();

  static const _autoPipKey = 'playback.auto_pip';
  static const _subtitleModeKey = 'playback.subtitle.mode';
  static const _subtitleLanguageKey = 'playback.subtitle.language';
  static const _subtitleTitleKey = 'playback.subtitle.title';

  Future<bool> readAutoPip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoPipKey) ?? true;
  }

  Future<void> saveAutoPip(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPipKey, value);
  }

  Future<SubtitlePreference> readSubtitlePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_subtitleModeKey) ?? 'auto';
    if (mode == 'off') return const SubtitlePreference.off();
    if (mode != 'match') return const SubtitlePreference.auto();
    return SubtitlePreference.match(
      language: prefs.getString(_subtitleLanguageKey),
      title: prefs.getString(_subtitleTitleKey),
    );
  }

  Future<void> saveSubtitleAuto() => _saveSubtitle(
        const SubtitlePreference.auto(),
      );

  Future<void> saveSubtitleOff() => _saveSubtitle(
        const SubtitlePreference.off(),
      );

  Future<void> saveSubtitleMatch({
    String? language,
    String? title,
  }) =>
      _saveSubtitle(
        SubtitlePreference.match(language: language, title: title),
      );

  Future<void> _saveSubtitle(SubtitlePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleModeKey, preference.mode);
    if (preference.language?.trim().isNotEmpty == true) {
      await prefs.setString(
        _subtitleLanguageKey,
        preference.language!.trim(),
      );
    } else {
      await prefs.remove(_subtitleLanguageKey);
    }
    if (preference.title?.trim().isNotEmpty == true) {
      await prefs.setString(_subtitleTitleKey, preference.title!.trim());
    } else {
      await prefs.remove(_subtitleTitleKey);
    }
  }
}
