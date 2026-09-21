import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/content_section.dart';
import '../models/epg_program.dart';
import '../models/iptv_account.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../models/library_entry.dart';
import '../models/playback_item.dart';
import '../models/series_item.dart';
import '../models/vod_item.dart';
import '../services/library_store.dart';
import '../services/m3u_client.dart';
import '../services/secure_account_store.dart';
import '../services/xmltv_service.dart';
import '../services/xtream_client.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.config,
    required this.accountStore,
    this.libraryStore = const LibraryStore(),
    XtreamClient? xtreamClient,
    M3uClient? m3uClient,
    XmlTvService? xmlTvService,
  })  : _xtreamClient = xtreamClient ?? XtreamClient(),
        _m3uClient = m3uClient ?? M3uClient(),
        _xmlTvService = xmlTvService ?? XmlTvService();

  final AppConfig config;
  final SecureAccountStore accountStore;
  final LibraryStore libraryStore;
  final XtreamClient _xtreamClient;
  final M3uClient _m3uClient;
  final XmlTvService _xmlTvService;

  IptvAccount? account;

  List<IptvCategory> liveCategories = const [];
  List<IptvChannel> channels = const [];
  List<IptvCategory> movieCategories = const [];
  List<VodItem> movies = const [];
  List<IptvCategory> seriesCategories = const [];
  List<SeriesItem> series = const [];

  List<LibraryEntry> favorites = const [];
  List<LibraryEntry> recent = const [];
  Map<String, List<EpgProgram>> epg = const {};

  ContentSection section = ContentSection.live;
  String liveCategoryId = '__all__';
  String movieCategoryId = '__all__';
  String seriesCategoryId = '__all__';

  bool loading = false;
  bool contentLoading = false;
  bool epgLoading = false;
  bool _moviesLoaded = false;
  bool _seriesLoaded = false;
  bool _epgLoaded = false;
  String? error;

  bool get signedIn => account != null;
  bool get supportsOnDemand => account?.type == AccountType.xtream;

  List<IptvCategory> get activeCategories {
    switch (section) {
      case ContentSection.live:
      case ContentSection.guide:
        return liveCategories;
      case ContentSection.movies:
        return movieCategories;
      case ContentSection.series:
        return seriesCategories;
      case ContentSection.favorites:
      case ContentSection.recent:
        return const [];
    }
  }

  String get activeCategoryId {
    switch (section) {
      case ContentSection.live:
      case ContentSection.guide:
        return liveCategoryId;
      case ContentSection.movies:
        return movieCategoryId;
      case ContentSection.series:
        return seriesCategoryId;
      case ContentSection.favorites:
      case ContentSection.recent:
        return '__all__';
    }
  }

  Future<void> restoreSession() async {
    await _loadLibrary();
    final stored = await accountStore.read();
    if (stored == null) return;
    account = stored;
    loading = true;
    notifyListeners();
    try {
      await _loadAccount(stored);
    } catch (_) {
      account = null;
      await accountStore.clear();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> signInXtream({
    required String username,
    required String password,
    String? serverUrl,
  }) async {
    return _guard(() async {
      final server = config.isLocked ? config.providerBaseUrl : (serverUrl ?? '');
      if (config.isLocked && server.contains('replace-me.invalid')) {
        throw Exception('SB provider endpoint has not been configured in this build.');
      }
      final authenticated = await _xtreamClient.authenticate(
        serverUrl: server,
        username: username.trim(),
        password: password,
        label: config.isLocked ? 'SB' : 'Xtream',
      );
      account = authenticated;
      await accountStore.save(authenticated);
      await _loadAccount(authenticated);
    });
  }

  Future<bool> signInM3u(String playlistUrl) async {
    if (config.isLocked) {
      error = 'M3U accounts are disabled in the SB Edition.';
      notifyListeners();
      return false;
    }
    return _guard(() async {
      final playlist = await _m3uClient.load(playlistUrl);
      final next = IptvAccount(
        type: AccountType.m3u,
        label: 'M3U',
        playlistUrl: playlistUrl.trim(),
        epgUrl: playlist.epgUrl,
      );
      account = next;
      await accountStore.save(next);
      _resetCatalogs();
      _setM3uChannels(playlist.channels);
    });
  }

  Future<void> selectSection(ContentSection value) async {
    if (!supportsOnDemand &&
        (value == ContentSection.movies || value == ContentSection.series)) {
      return;
    }
    section = value;
    error = null;
    notifyListeners();

    if (value == ContentSection.movies && !_moviesLoaded) {
      await _loadMovies();
    } else if (value == ContentSection.series && !_seriesLoaded) {
      await _loadSeries();
    }
  }

  void selectCategory(String categoryId) {
    switch (section) {
      case ContentSection.live:
      case ContentSection.guide:
        liveCategoryId = categoryId;
        break;
      case ContentSection.movies:
        movieCategoryId = categoryId;
        break;
      case ContentSection.series:
        seriesCategoryId = categoryId;
        break;
      case ContentSection.favorites:
      case ContentSection.recent:
        return;
    }
    notifyListeners();
  }

  List<IptvChannel> visibleChannels(String search) {
    final query = search.trim().toLowerCase();
    return channels.where((channel) {
      final categoryMatches = liveCategoryId == '__all__' || channel.categoryId == liveCategoryId;
      final searchMatches = query.isEmpty || channel.name.toLowerCase().contains(query);
      return categoryMatches && searchMatches;
    }).toList(growable: false);
  }

  List<VodItem> visibleMovies(String search) {
    final query = search.trim().toLowerCase();
    return movies.where((item) {
      final categoryMatches = movieCategoryId == '__all__' || item.categoryId == movieCategoryId;
      final searchMatches = query.isEmpty || item.name.toLowerCase().contains(query);
      return categoryMatches && searchMatches;
    }).toList(growable: false);
  }

  List<SeriesItem> visibleSeries(String search) {
    final query = search.trim().toLowerCase();
    return series.where((item) {
      final categoryMatches = seriesCategoryId == '__all__' || item.categoryId == seriesCategoryId;
      final searchMatches = query.isEmpty || item.name.toLowerCase().contains(query);
      return categoryMatches && searchMatches;
    }).toList(growable: false);
  }

  List<LibraryEntry> visibleLibrary(List<LibraryEntry> entries, String search) {
    final query = search.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries
        .where((entry) => entry.title.toLowerCase().contains(query) ||
            (entry.subtitle?.toLowerCase().contains(query) ?? false))
        .toList(growable: false);
  }

  Future<SeriesDetails> fetchSeriesDetails(SeriesItem item) async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) {
      throw Exception('Series are only available for Xtream accounts.');
    }
    return _xtreamClient.fetchSeriesDetails(current, item);
  }

  PlaybackItem playbackForChannel(IptvChannel channel) => PlaybackItem(
        id: 'live:${channel.id}',
        title: channel.name,
        streamUrl: channel.streamUrl,
        kind: PlaybackKind.live,
        artworkUrl: channel.logoUrl,
        subtitle: nowProgram(channel)?.title,
      );

  PlaybackItem playbackForMovie(VodItem movie) => PlaybackItem(
        id: 'movie:${movie.id}',
        title: movie.name,
        streamUrl: movie.streamUrl,
        kind: PlaybackKind.movie,
        artworkUrl: movie.posterUrl,
        subtitle: movie.releaseDate,
        startPosition: _savedPosition('movie:${movie.id}'),
      );

  PlaybackItem playbackForEpisode(SeriesItem seriesItem, SeriesEpisode episode) =>
      PlaybackItem(
        id: 'episode:${episode.id}',
        title: episode.title,
        streamUrl: episode.streamUrl,
        kind: PlaybackKind.episode,
        artworkUrl: episode.imageUrl ?? seriesItem.coverUrl,
        subtitle: '${seriesItem.name} • S${episode.season} E${episode.episodeNumber}',
        startPosition: _savedPosition('episode:${episode.id}'),
      );

  bool isFavorite(PlaybackItem item) => favorites.any((entry) => entry.id == item.id);

  Future<void> toggleFavorite(PlaybackItem item) async {
    final existing = favorites.indexWhere((entry) => entry.id == item.id);
    final next = [...favorites];
    if (existing >= 0) {
      next.removeAt(existing);
    } else {
      next.insert(0, _entryFromPlayback(item));
    }
    favorites = next;
    notifyListeners();
    await libraryStore.saveFavorites(favorites);
  }

  Future<void> recordPlayback(
    PlaybackItem item, {
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    var savedPosition = position;
    if (!item.isLive && duration.inSeconds > 0 && position.inSeconds / duration.inSeconds > 0.95) {
      savedPosition = Duration.zero;
    }

    final entry = _entryFromPlayback(
      item,
      position: savedPosition,
      duration: duration,
    );

    recent = [entry, ...recent.where((value) => value.id != item.id)].take(50).toList();

    final favoriteIndex = favorites.indexWhere((value) => value.id == item.id);
    if (favoriteIndex >= 0) {
      final next = [...favorites];
      next[favoriteIndex] = entry;
      favorites = next;
      await libraryStore.saveFavorites(favorites);
    }

    notifyListeners();
    await libraryStore.saveRecent(recent);
  }

  EpgProgram? nowProgram(IptvChannel channel, {DateTime? at}) {
    final id = channel.epgId;
    if (id == null) return null;
    final programmes = epg[id];
    if (programmes == null) return null;
    final time = at ?? DateTime.now();
    for (final programme in programmes) {
      if (programme.isLiveAt(time)) return programme;
    }
    return null;
  }

  EpgProgram? nextProgram(IptvChannel channel, {DateTime? at}) {
    final id = channel.epgId;
    if (id == null) return null;
    final programmes = epg[id];
    if (programmes == null) return null;
    final time = at ?? DateTime.now();
    for (final programme in programmes) {
      if (programme.start.isAfter(time)) return programme;
    }
    return null;
  }

  List<EpgProgram> programmesForChannel(
    IptvChannel channel, {
    DateTime? from,
    int limit = 6,
  }) {
    final id = channel.epgId;
    if (id == null) return const [];
    final programmes = epg[id];
    if (programmes == null) return const [];
    final time = from ?? DateTime.now();
    return programmes
        .where((programme) => programme.stop.isAfter(time))
        .take(limit)
        .toList(growable: false);
  }

  Future<void> loadEpg() async {
    if (_epgLoaded || epgLoading) return;
    final url = account?.epgUrl;
    if (url == null || url.isEmpty) return;
    epgLoading = true;
    notifyListeners();
    try {
      epg = await _xmlTvService.load(url);
      _epgLoaded = true;
    } catch (_) {
      // EPG is optional. Playback and catalog browsing must remain usable.
    } finally {
      epgLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (account == null) return;
    await _guard(() => _loadAccount(account!));
  }

  Future<void> logout() async {
    account = null;
    _resetCatalogs();
    section = ContentSection.live;
    error = null;
    await accountStore.clear();
    notifyListeners();
  }

  Future<void> _loadLibrary() async {
    favorites = await libraryStore.loadFavorites();
    recent = await libraryStore.loadRecent();
  }

  Future<void> _loadAccount(IptvAccount value) async {
    _resetCatalogs();
    if (value.type == AccountType.xtream) {
      final results = await Future.wait([
        _xtreamClient.fetchLiveCategories(value),
        _xtreamClient.fetchLiveChannels(value),
      ]);
      liveCategories = results[0] as List<IptvCategory>;
      channels = results[1] as List<IptvChannel>;
    } else {
      final playlist = await _m3uClient.load(value.playlistUrl!);
      _setM3uChannels(playlist.channels);
      if (playlist.epgUrl != null && playlist.epgUrl != value.epgUrl) {
        account = IptvAccount(
          type: value.type,
          label: value.label,
          playlistUrl: value.playlistUrl,
          epgUrl: playlist.epgUrl,
        );
        await accountStore.save(account!);
      }
    }
    liveCategoryId = '__all__';
    section = ContentSection.live;
    notifyListeners();
  }

  Future<void> _loadMovies() async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) return;
    contentLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _xtreamClient.fetchVodCategories(current),
        _xtreamClient.fetchVodStreams(current),
      ]);
      movieCategories = results[0] as List<IptvCategory>;
      movies = results[1] as List<VodItem>;
      _moviesLoaded = true;
      movieCategoryId = '__all__';
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      contentLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadSeries() async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) return;
    contentLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _xtreamClient.fetchSeriesCategories(current),
        _xtreamClient.fetchSeries(current),
      ]);
      seriesCategories = results[0] as List<IptvCategory>;
      series = results[1] as List<SeriesItem>;
      _seriesLoaded = true;
      seriesCategoryId = '__all__';
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      contentLoading = false;
      notifyListeners();
    }
  }

  Duration _savedPosition(String id) {
    for (final item in recent) {
      if (item.id == id) return Duration(seconds: item.positionSeconds);
    }
    return Duration.zero;
  }

  LibraryEntry _entryFromPlayback(
    PlaybackItem item, {
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    return LibraryEntry(
      id: item.id,
      title: item.title,
      streamUrl: item.streamUrl,
      kind: item.kind,
      updatedAt: DateTime.now(),
      artworkUrl: item.artworkUrl,
      subtitle: item.subtitle,
      positionSeconds: position.inSeconds,
      durationSeconds: duration.inSeconds,
    );
  }

  void _setM3uChannels(List<IptvChannel> loaded) {
    channels = loaded;
    final groups = <String>{};
    for (final channel in loaded) {
      groups.add(channel.categoryId);
    }
    liveCategories = groups
        .map((name) => IptvCategory(id: name, name: name))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    liveCategoryId = '__all__';
  }

  void _resetCatalogs() {
    liveCategories = const [];
    channels = const [];
    movieCategories = const [];
    movies = const [];
    seriesCategories = const [];
    series = const [];
    epg = const {};
    liveCategoryId = '__all__';
    movieCategoryId = '__all__';
    seriesCategoryId = '__all__';
    _moviesLoaded = false;
    _seriesLoaded = false;
    _epgLoaded = false;
    contentLoading = false;
    epgLoading = false;
  }

  Future<bool> _guard(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _xtreamClient.dispose();
    _m3uClient.dispose();
    _xmlTvService.dispose();
    super.dispose();
  }
}
