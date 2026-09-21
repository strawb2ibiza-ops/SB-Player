import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/content_section.dart';
import '../models/epg_program.dart';
import '../models/iptv_account.dart';
import '../models/iptv_category.dart';
import '../models/iptv_profile.dart';
import '../models/iptv_channel.dart';
import '../models/library_entry.dart';
import '../models/playback_item.dart';
import '../models/series_item.dart';
import '../models/vod_item.dart';
import '../services/account_profiles_store.dart';
import '../services/epg_cache_service.dart';
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
    this.profileStore = const AccountProfilesStore(),
    XtreamClient? xtreamClient,
    M3uClient? m3uClient,
    XmlTvService? xmlTvService,
    EpgCacheService epgCacheService = const EpgCacheService(),
  })  : _epgCacheService = epgCacheService,
        _xtreamClient = xtreamClient ?? XtreamClient(),
        _m3uClient = m3uClient ?? M3uClient(),
        _xmlTvService = xmlTvService ?? XmlTvService();

  final AppConfig config;
  final SecureAccountStore accountStore;
  final LibraryStore libraryStore;
  final AccountProfilesStore profileStore;
  final EpgCacheService _epgCacheService;
  final XtreamClient _xtreamClient;
  final M3uClient _m3uClient;
  final XmlTvService _xmlTvService;

  IptvAccount? account;
  List<IptvProfile> profiles = const [];
  String? activeProfileId;

  IptvProfile? get activeProfile {
    final id = activeProfileId;
    if (id == null) return null;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

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
    await _epgCacheService.cleanupLegacyCache();
    await _loadLibrary();

    IptvAccount? stored;
    if (!config.isLocked) {
      profiles = await profileStore.loadProfiles();
      activeProfileId = await profileStore.readActiveProfileId();
      stored = activeProfile?.account;
    }

    stored ??= await accountStore.read();
    if (stored == null) {
      notifyListeners();
      return;
    }

    loading = true;
    notifyListeners();
    try {
      if (!config.isLocked && activeProfile == null) {
        await _saveOpenProfile(stored);
      }

      await _loadAccount(stored);
      await accountStore.save(account!);

      if (!config.isLocked) {
        await _updateActiveProfileAccount(account!);
      }
      await _migrateLegacyLibraryToCurrentScope();
    } catch (_) {
      account = null;
      activeProfileId = null;
      if (!config.isLocked) {
        await profileStore.setActiveProfileId(null);
      }
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

      await _loadAccount(authenticated);
      await accountStore.save(account!);

      if (!config.isLocked) {
        await _saveOpenProfile(account!);
      }
      await _migrateLegacyLibraryToCurrentScope();
    });
  }

  Future<bool> signInM3u(String playlistUrl) async {
    if (config.isLocked) {
      error = 'M3U accounts are disabled in the SB Edition.';
      notifyListeners();
      return false;
    }

    return _guard(() async {
      final next = IptvAccount(
        type: AccountType.m3u,
        label: 'M3U',
        playlistUrl: playlistUrl.trim(),
      );

      await _loadAccount(next);
      await accountStore.save(account!);
      await _saveOpenProfile(account!);
      await _migrateLegacyLibraryToCurrentScope();
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
    final prefix = '$_libraryScope|';
    final query = search.trim().toLowerCase();
    return entries.where((entry) {
      if (!entry.id.startsWith(prefix)) return false;
      if (query.isEmpty) return true;
      return entry.title.toLowerCase().contains(query) ||
          (entry.subtitle?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  Future<SeriesDetails> fetchSeriesDetails(SeriesItem item) async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) {
      throw Exception('Series are only available for Xtream accounts.');
    }
    return _xtreamClient.fetchSeriesDetails(current, item);
  }

  PlaybackItem playbackForChannel(IptvChannel channel) => PlaybackItem(
        id: _scopedContentId('live', channel.id),
        title: channel.name,
        streamUrl: channel.streamUrl,
        kind: PlaybackKind.live,
        artworkUrl: channel.logoUrl,
        subtitle: nowProgram(channel)?.title,
      );

  PlaybackItem playbackForMovie(VodItem movie) {
    final id = _scopedContentId('movie', movie.id);
    return PlaybackItem(
      id: id,
      title: movie.name,
      streamUrl: movie.streamUrl,
      kind: PlaybackKind.movie,
      artworkUrl: movie.posterUrl,
      subtitle: movie.releaseDate,
      startPosition: _savedPosition(id),
    );
  }

  PlaybackItem playbackForEpisode(
    SeriesItem seriesItem,
    SeriesEpisode episode,
  ) {
    final id = _scopedContentId('episode', episode.id);
    return PlaybackItem(
      id: id,
      title: episode.title,
      streamUrl: episode.streamUrl,
      kind: PlaybackKind.episode,
      artworkUrl: episode.imageUrl ?? seriesItem.coverUrl,
      subtitle:
          '${seriesItem.name} • S${episode.season} E${episode.episodeNumber}',
      startPosition: _savedPosition(id),
    );
  }

  bool isFavorite(PlaybackItem item) =>
      favorites.any((entry) => entry.id == item.id);

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
    if (!item.isLive &&
        duration.inSeconds > 0 &&
        position.inSeconds / duration.inSeconds > 0.95) {
      savedPosition = Duration.zero;
    }

    final entry = _entryFromPlayback(
      item,
      position: savedPosition,
      duration: duration,
    );

    final prefix = '$_libraryScope|';
    final currentScope = [
      entry,
      ...recent.where(
        (value) => value.id.startsWith(prefix) && value.id != item.id,
      ),
    ].take(50);

    recent = [
      ...currentScope,
      ...recent.where((value) => !value.id.startsWith(prefix)),
    ];

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
    if (programmes == null || programmes.isEmpty) return null;

    final time = at ?? DateTime.now();
    final nextIndex = _lowerBoundProgrammeStart(
      programmes,
      time,
      strictlyAfter: true,
    );
    final currentIndex = nextIndex - 1;
    if (currentIndex < 0) return null;

    final current = programmes[currentIndex];
    return current.isLiveAt(time) ? current : null;
  }

  EpgProgram? nextProgram(IptvChannel channel, {DateTime? at}) {
    final id = channel.epgId;
    if (id == null) return null;
    final programmes = epg[id];
    if (programmes == null || programmes.isEmpty) return null;

    final time = at ?? DateTime.now();
    final index = _lowerBoundProgrammeStart(
      programmes,
      time,
      strictlyAfter: true,
    );
    return index < programmes.length ? programmes[index] : null;
  }

  List<EpgProgram> programmesForChannel(
    IptvChannel channel, {
    DateTime? from,
    int limit = 6,
  }) {
    final id = channel.epgId;
    if (id == null || limit <= 0) return const [];
    final programmes = epg[id];
    if (programmes == null || programmes.isEmpty) return const [];

    final time = from ?? DateTime.now();
    var index = _lowerBoundProgrammeStart(programmes, time);
    if (index > 0 && programmes[index - 1].stop.isAfter(time)) {
      index -= 1;
    }
    return programmes.skip(index).take(limit).toList(growable: false);
  }

  List<EpgProgram> programmesForWindow(
    IptvChannel channel, {
    required DateTime start,
    required DateTime end,
  }) {
    final id = channel.epgId;
    if (id == null || !end.isAfter(start)) return const [];
    final programmes = epg[id];
    if (programmes == null || programmes.isEmpty) return const [];

    var index = _lowerBoundProgrammeStart(programmes, start);
    while (index > 0 && programmes[index - 1].stop.isAfter(start)) {
      index -= 1;
    }

    final output = <EpgProgram>[];
    for (; index < programmes.length; index++) {
      final programme = programmes[index];
      if (!programme.start.isBefore(end)) break;
      if (programme.stop.isAfter(start)) output.add(programme);
    }
    return output;
  }

  int _lowerBoundProgrammeStart(
    List<EpgProgram> programmes,
    DateTime time, {
    bool strictlyAfter = false,
  }) {
    var low = 0;
    var high = programmes.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final start = programmes[mid].start;
      final belongsBefore =
          strictlyAfter ? !start.isAfter(time) : start.isBefore(time);
      if (belongsBefore) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  Future<void> loadEpg({bool force = false}) async {
    if ((_epgLoaded && !force) || epgLoading) return;
    final url = account?.epgUrl;
    if (url == null || url.isEmpty) return;
    epgLoading = true;
    notifyListeners();
    try {
      if (!force) {
        final cached = await _epgCacheService.load(url);
        if (cached != null) {
          epg = cached;
          _epgLoaded = true;
          return;
        }
      }

      final fresh = await _xmlTvService.load(url);
      epg = fresh;
      _epgLoaded = true;
      await _epgCacheService.save(url, fresh);
    } catch (_) {
      // EPG is optional. Playback and catalog browsing must remain usable.
    } finally {
      epgLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final current = account;
    if (current == null) return;

    final refreshed = await _guard(() async {
      await _loadAccount(current);
      await accountStore.save(account!);
      if (!config.isLocked) {
        await _updateActiveProfileAccount(account!);
      }
    });

    if (refreshed) unawaited(loadEpg());
  }

  Future<bool> switchProfile(String profileId) async {
    if (config.isLocked || profileId == activeProfileId) return false;

    IptvProfile? selected;
    for (final profile in profiles) {
      if (profile.id == profileId) {
        selected = profile;
        break;
      }
    }
    if (selected == null) return false;
    final profile = selected;

    final switched = await _guard(() async {
      await _loadAccount(profile.account);
      activeProfileId = profile.id;
      await profileStore.setActiveProfileId(profile.id);
      await accountStore.save(account!);
      await _updateActiveProfileAccount(account!);
      await _migrateLegacyLibraryToCurrentScope();
    });

    if (switched) unawaited(loadEpg());
    return switched;
  }

  Future<void> renameProfile(String profileId, String name) async {
    if (config.isLocked) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    profiles = [
      for (final profile in profiles)
        if (profile.id == profileId)
          profile.copyWith(name: trimmed, updatedAt: DateTime.now())
        else
          profile,
    ];
    await profileStore.saveProfiles(profiles);
    notifyListeners();
  }

  Future<void> removeProfile(String profileId) async {
    if (config.isLocked) return;

    final exists = profiles.any((profile) => profile.id == profileId);
    if (!exists) return;

    final removingActive = activeProfileId == profileId;
    if (removingActive && profiles.length > 1) {
      final replacement =
          profiles.firstWhere((profile) => profile.id != profileId);
      final switched = await switchProfile(replacement.id);
      if (!switched) return;
    }

    profiles = profiles
        .where((profile) => profile.id != profileId)
        .toList(growable: false);
    await profileStore.saveProfiles(profiles);
    await _removeLibraryScope('profile:$profileId');

    if (removingActive && profiles.isEmpty) {
      await beginAddAccount();
    } else {
      notifyListeners();
    }
  }

  Future<void> beginAddAccount() async {
    if (config.isLocked) return;
    account = null;
    activeProfileId = null;
    _resetCatalogs();
    section = ContentSection.live;
    error = null;
    await profileStore.setActiveProfileId(null);
    await accountStore.clear();
    notifyListeners();
  }

  Future<void> logout() async {
    account = null;
    activeProfileId = null;
    _resetCatalogs();
    section = ContentSection.live;
    error = null;
    if (!config.isLocked) {
      await profileStore.setActiveProfileId(null);
    }
    await accountStore.clear();
    notifyListeners();
  }

  Future<void> _loadLibrary() async {
    favorites = await libraryStore.loadFavorites();
    recent = await libraryStore.loadRecent();
  }

  Future<void> _saveOpenProfile(IptvAccount value) async {
    if (config.isLocked) return;

    IptvProfile? existing;
    for (final profile in profiles) {
      if (_sameProfileAccount(profile.account, value)) {
        existing = profile;
        break;
      }
    }

    final now = DateTime.now();
    final next = IptvProfile(
      id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
      name: existing?.name ?? _defaultProfileName(value),
      account: value,
      updatedAt: now,
    );

    profiles = [
      next,
      ...profiles.where((profile) => profile.id != next.id),
    ];
    activeProfileId = next.id;
    await profileStore.saveProfiles(profiles);
    await profileStore.setActiveProfileId(next.id);
  }

  Future<void> _updateActiveProfileAccount(IptvAccount value) async {
    final id = activeProfileId;
    if (id == null) return;
    profiles = [
      for (final profile in profiles)
        if (profile.id == id)
          profile.copyWith(account: value, updatedAt: DateTime.now())
        else
          profile,
    ];
    await profileStore.saveProfiles(profiles);
  }

  bool _sameProfileAccount(IptvAccount left, IptvAccount right) {
    if (left.type != right.type) return false;
    if (left.type == AccountType.xtream) {
      return left.serverUrl == right.serverUrl &&
          left.username == right.username;
    }
    return left.playlistUrl == right.playlistUrl;
  }

  String _defaultProfileName(IptvAccount value) {
    final source =
        value.type == AccountType.xtream ? value.serverUrl : value.playlistUrl;
    final host = Uri.tryParse(source ?? '')?.host;
    if (host?.isNotEmpty == true) return host!;
    return value.type == AccountType.xtream ? 'Xtream account' : 'M3U playlist';
  }

  Future<void> _loadAccount(IptvAccount value) async {
    IptvAccount resolvedAccount = value;
    List<IptvCategory> loadedCategories;
    List<IptvChannel> loadedChannels;

    if (value.type == AccountType.xtream) {
      late List<IptvCategory> categories;
      late List<IptvChannel> liveChannels;
      await Future.wait<void>([
        _xtreamClient.fetchLiveCategories(value).then((value) {
          categories = value;
        }),
        _xtreamClient.fetchLiveChannels(value).then((value) {
          liveChannels = value;
        }),
      ]);
      loadedCategories = categories;
      loadedChannels = liveChannels;
    } else {
      final playlist = await _m3uClient.load(value.playlistUrl!);
      loadedChannels = playlist.channels;
      loadedCategories = _categoriesFromChannels(loadedChannels);

      if (playlist.epgUrl != null && playlist.epgUrl != value.epgUrl) {
        resolvedAccount = IptvAccount(
          type: value.type,
          label: value.label,
          playlistUrl: value.playlistUrl,
          epgUrl: playlist.epgUrl,
        );
      }
    }

    _resetCatalogs();
    account = resolvedAccount;
    liveCategories = loadedCategories;
    channels = loadedChannels;
    liveCategoryId = '__all__';
    section = ContentSection.live;
  }

  Future<void> _loadMovies() async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) return;
    contentLoading = true;
    error = null;
    notifyListeners();
    try {
      late List<IptvCategory> categories;
      late List<VodItem> loadedMovies;
      await Future.wait<void>([
        _xtreamClient.fetchVodCategories(current).then((value) {
          categories = value;
        }),
        _xtreamClient.fetchVodStreams(current).then((value) {
          loadedMovies = value;
        }),
      ]);
      movieCategories = categories;
      movies = loadedMovies;
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
      late List<IptvCategory> categories;
      late List<SeriesItem> loadedSeries;
      await Future.wait<void>([
        _xtreamClient.fetchSeriesCategories(current).then((value) {
          categories = value;
        }),
        _xtreamClient.fetchSeries(current).then((value) {
          loadedSeries = value;
        }),
      ]);
      seriesCategories = categories;
      series = loadedSeries;
      _seriesLoaded = true;
      seriesCategoryId = '__all__';
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      contentLoading = false;
      notifyListeners();
    }
  }

  String get _libraryScope {
    if (config.isLocked) {
      final current = account;
      if (current == null) return 'sb:pending';
      final identity =
          '${current.serverUrl ?? config.providerBaseUrl}|${current.username ?? ''}';
      final digest = sha256.convert(utf8.encode(identity)).toString();
      return 'sb:${digest.substring(0, 16)}';
    }

    final id = activeProfileId;
    return id == null ? 'profile:pending' : 'profile:$id';
  }

  String _scopedContentId(String kind, String id) =>
      '$_libraryScope|$kind:$id';

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

  LibraryEntry _rekeyLibraryEntry(LibraryEntry entry, String id) {
    return LibraryEntry(
      id: id,
      title: entry.title,
      streamUrl: entry.streamUrl,
      kind: entry.kind,
      updatedAt: entry.updatedAt,
      artworkUrl: entry.artworkUrl,
      subtitle: entry.subtitle,
      positionSeconds: entry.positionSeconds,
      durationSeconds: entry.durationSeconds,
    );
  }

  Future<void> _migrateLegacyLibraryToCurrentScope() async {
    if (account == null || (!config.isLocked && activeProfileId == null)) return;
    final prefix = '$_libraryScope|';

    var favoritesChanged = false;
    var recentChanged = false;

    favorites = [
      for (final entry in favorites)
        if (_isLegacyLibraryId(entry.id))
          (() {
            favoritesChanged = true;
            return _rekeyLibraryEntry(entry, '$prefix${entry.id}');
          })()
        else
          entry,
    ];

    recent = [
      for (final entry in recent)
        if (_isLegacyLibraryId(entry.id))
          (() {
            recentChanged = true;
            return _rekeyLibraryEntry(entry, '$prefix${entry.id}');
          })()
        else
          entry,
    ];

    if (favoritesChanged) await libraryStore.saveFavorites(favorites);
    if (recentChanged) await libraryStore.saveRecent(recent);
  }

  bool _isLegacyLibraryId(String id) =>
      id.startsWith('live:') ||
      id.startsWith('movie:') ||
      id.startsWith('episode:');

  Future<void> _removeLibraryScope(String scope) async {
    final prefix = '$scope|';
    final nextFavorites =
        favorites.where((entry) => !entry.id.startsWith(prefix)).toList();
    final nextRecent =
        recent.where((entry) => !entry.id.startsWith(prefix)).toList();

    final favoritesChanged = nextFavorites.length != favorites.length;
    final recentChanged = nextRecent.length != recent.length;
    favorites = nextFavorites;
    recent = nextRecent;

    if (favoritesChanged) await libraryStore.saveFavorites(favorites);
    if (recentChanged) await libraryStore.saveRecent(recent);
  }

  List<IptvCategory> _categoriesFromChannels(List<IptvChannel> loaded) {
    final groups = <String>{};
    for (final channel in loaded) {
      groups.add(channel.categoryId);
    }
    return groups
        .map((name) => IptvCategory(id: name, name: name))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
