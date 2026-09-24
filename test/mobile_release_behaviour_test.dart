import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sb_player/src/config/app_config.dart';
import 'package:sb_player/src/models/library_entry.dart';
import 'package:sb_player/src/models/playback_item.dart';
import 'package:sb_player/src/models/series_item.dart';
import 'package:sb_player/src/models/vod_item.dart';
import 'package:sb_player/src/services/library_store.dart';
import 'package:sb_player/src/services/playback_preferences.dart';
import 'package:sb_player/src/services/secure_account_store.dart';
import 'package:sb_player/src/services/tv_pairing_service.dart';
import 'package:sb_player/src/state/app_controller.dart';

class _MemoryLibraryStore extends LibraryStore {
  _MemoryLibraryStore();

  List<LibraryEntry> savedFavorites = <LibraryEntry>[];
  List<LibraryEntry> savedRecent = <LibraryEntry>[];

  @override
  Future<List<LibraryEntry>> loadFavorites() async =>
      List<LibraryEntry>.from(savedFavorites);

  @override
  Future<List<LibraryEntry>> loadRecent() async =>
      List<LibraryEntry>.from(savedRecent);

  @override
  Future<void> saveFavorites(List<LibraryEntry> entries) async {
    savedFavorites = List<LibraryEntry>.from(entries);
  }

  @override
  Future<void> saveRecent(List<LibraryEntry> entries) async {
    savedRecent = List<LibraryEntry>.from(entries);
  }
}

AppController _controller(_MemoryLibraryStore library) {
  final controller = AppController(
    config: const AppConfig(
      mode: DistributionMode.sbLocked,
      providerBaseUrl: 'https://example.test',
      appName: 'SB Player',
    ),
    accountStore: const SecureAccountStore(),
    libraryStore: library,
  );
  controller.enterUiCaptureMode();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Continue Watching saves and restores a movie resume position', () async {
    final library = _MemoryLibraryStore();
    final controller = _controller(library);
    const movie = VodItem(
      id: '42',
      name: 'Resume Test',
      categoryId: '1',
      streamUrl: 'https://example.test/movie/user/pass/42.mp4',
    );

    final first = controller.playbackForMovie(movie);
    await controller.recordPlayback(
      first,
      position: const Duration(seconds: 123),
      duration: const Duration(seconds: 600),
    );

    expect(controller.continueWatching, hasLength(1));
    expect(controller.continueWatching.single.positionSeconds, 123);
    expect(
      controller.playbackForMovie(movie).startPosition,
      const Duration(seconds: 123),
    );

    controller.dispose();
  });

  test('completed playback is removed from Continue Watching', () async {
    final library = _MemoryLibraryStore();
    final controller = _controller(library);
    const movie = VodItem(
      id: '43',
      name: 'Completion Test',
      categoryId: '1',
      streamUrl: 'https://example.test/movie/user/pass/43.mp4',
    );

    final item = controller.playbackForMovie(movie);
    await controller.recordPlayback(
      item,
      position: const Duration(seconds: 580),
      duration: const Duration(seconds: 600),
    );

    expect(controller.continueWatching, isEmpty);
    expect(controller.playbackForMovie(movie).startPosition, Duration.zero);

    controller.dispose();
  });

  test('provider labels are simplified before playback is shown', () {
    final library = _MemoryLibraryStore();
    final controller = _controller(library);

    const movie = VodItem(
      id: '80',
      name: 'EN - Example Movie (2026) 4K',
      categoryId: '1',
      streamUrl: 'https://example.test/movie/80.mp4',
    );
    expect(controller.displayMovieTitle(movie), 'Example Movie (2026)');
    expect(controller.playbackForMovie(movie).title, 'Example Movie (2026)');

    const series = SeriesItem(
      id: '100',
      name: 'EN - South Park (1997) 4K',
      categoryId: '9',
    );
    const episode = SeriesEpisode(
      id: '501',
      title: 'EN - South Park (1997) 4K - S11E03',
      season: 11,
      episodeNumber: 3,
      streamUrl: 'https://example.test/series/501.mp4',
    );

    expect(controller.displaySeriesTitle(series), 'South Park (1997)');
    final playback = controller.playbackForEpisode(series, episode);
    expect(playback.title, 'South Park (1997)');
    expect(playback.subtitle, 'Season 11 • Episode 3');

    controller.dispose();
  });

  test('episode autoplay queue preserves the full following order', () {
    final library = _MemoryLibraryStore();
    final controller = _controller(library);
    const series = SeriesItem(
      id: '100',
      name: 'Queue Test',
      categoryId: '9',
      coverUrl: 'https://images.example.test/show.jpg',
    );
    const episodes = <SeriesEpisode>[
      SeriesEpisode(
        id: '501',
        title: 'Episode 1',
        season: 1,
        episodeNumber: 1,
        streamUrl: 'https://example.test/series/user/pass/501.mp4',
      ),
      SeriesEpisode(
        id: '502',
        title: 'Episode 2',
        season: 1,
        episodeNumber: 2,
        streamUrl: 'https://example.test/series/user/pass/502.mp4',
      ),
      SeriesEpisode(
        id: '601',
        title: 'Episode 1',
        season: 2,
        episodeNumber: 1,
        streamUrl: 'https://example.test/series/user/pass/601.mp4',
      ),
    ];

    final playback = controller.playbackForEpisode(
      series,
      episodes.first,
      followingEpisodes: episodes.skip(1).toList(),
    );

    expect(playback.title, 'Episode 1');
    expect(playback.next?.title, 'Episode 2');
    expect(playback.next?.next?.title, 'Episode 1');
    expect(playback.next?.next?.next, isNull);

    controller.dispose();
  });

  test('episode playback carries provider subtitles to the player', () {
    final library = _MemoryLibraryStore();
    final controller = _controller(library);
    const series = SeriesItem(
      id: '100',
      name: 'Subtitle Test',
      categoryId: '9',
    );
    const episode = SeriesEpisode(
      id: '501',
      title: 'Pilot',
      season: 1,
      episodeNumber: 1,
      streamUrl: 'https://example.test/series/user/pass/501.mp4',
      subtitles: <SeriesSubtitle>[
        SeriesSubtitle(
          url: 'https://example.test/subtitles/501-en.vtt',
          title: 'English',
          language: 'en',
        ),
      ],
    );

    final playback = controller.playbackForEpisode(series, episode);

    expect(playback.externalSubtitles, hasLength(1));
    expect(playback.externalSubtitles.single.language, 'en');
    expect(
      playback.externalSubtitles.single.url,
      'https://example.test/subtitles/501-en.vtt',
    );

    controller.dispose();
  });

  test('subtitle preference survives a settings round trip', () async {
    const prefs = PlaybackPreferences();

    await prefs.saveSubtitleMatch(language: 'EN', title: 'English');
    final restored = await prefs.readSubtitlePreference();

    expect(restored.matches(language: 'en', title: null), isTrue);
    expect(restored.matches(language: 'fr', title: 'English'), isTrue);

    await prefs.saveSubtitleOff();
    expect((await prefs.readSubtitlePreference()).isOff, isTrue);

    await prefs.saveSubtitleAuto();
    expect((await prefs.readSubtitlePreference()).isAuto, isTrue);
  });

  test('library history persists in normal preferences', () async {
    const store = LibraryStore();
    final entries = <LibraryEntry>[
      LibraryEntry(
        id: 'scope|movie:1',
        title: 'Saved Movie',
        streamUrl: 'https://example.test/movie/1.mp4',
        kind: PlaybackKind.movie,
        updatedAt: DateTime.utc(2026, 9, 24),
        positionSeconds: 100,
        durationSeconds: 500,
      ),
    ];

    await store.saveRecent(entries);
    final restored = await store.loadRecent();

    expect(restored, hasLength(1));
    expect(restored.single.positionSeconds, 100);
    expect(restored.single.durationSeconds, 500);
  });

  test('TV pairing accepts only the trusted SB Player endpoint', () {
    final encodedEndpoint = Uri.encodeComponent(TvPairingRequest.trustedEndpoint);
    final valid = TvPairingRequest.parse(
      'sbplayer://pair?id=abc&token=def&code=123456&endpoint=$encodedEndpoint',
    );

    expect(valid.pairingId, 'abc');
    expect(valid.code, '123456');

    final evilEndpoint = Uri.encodeComponent('https://example.test/pair');
    expect(
      () => TvPairingRequest.parse(
        'sbplayer://pair?id=abc&token=def&endpoint=$evilEndpoint',
      ),
      throwsFormatException,
    );
  });
}
