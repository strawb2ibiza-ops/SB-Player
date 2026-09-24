import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../debug/debug_catalog.dart';
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
  })  :
        // Keep the public injection name readable for tests/callers while the
        // backing field stays private.
        // ignore: prefer_initializing_formals
        _epgCacheService = epgCacheService,
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

  Map<String, List<IptvChannel>> _channelsByCategory = const {};
  Map<String, List<VodItem>> _moviesByCategory = const {};
  Map<String, List<SeriesItem>> _seriesByCategory = const {};

  List<LibraryEntry> favorites = const [];
  List<LibraryEntry> recent = const [];
  Map<String, List<EpgProgram>> epg = const {};

  ContentSection section = ContentSection.home;
  String liveCategoryId = '__all__';
  String movieCategoryId = '__all__';
  String seriesCategoryId = '__all__';

  bool loading = false;
  bool contentLoading = false;
  bool epgLoading = false;
  bool _moviesLoaded = false;
  bool _seriesLoaded = false;
  bool _fullSeriesLoaded = false;
  final Set<String> _loadedSeriesCategoryIds = <String>{};
  bool _epgLoaded = false;
  int _catalogGeneration = 0;
  int _epgGeneration = 0;
  String? _cachedSbScopeIdentity;
  String? _cachedSbScope;
  String? error;
  List<VodItem> _recentMoviesCache = const [];
  List<SeriesItem> _recentSeriesCache = const [];
  Set<String> _favoriteIds = const <String>{};

  bool debugMode = false;

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
      case ContentSection.home:
      case ContentSection.continueWatching:
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
      case ContentSection.home:
      case ContentSection.continueWatching:
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

  void enterUiCaptureMode() {
    _resetCatalogs();
    debugMode = true;
    account = DebugCatalog.account;
    activeProfileId = null;
    liveCategories = DebugCatalog.liveCategories;
    channels = DebugCatalog.channels;
    movieCategories = DebugCatalog.movieCategories;
    movies = DebugCatalog.movies;
    seriesCategories = DebugCatalog.seriesCategories;
    series = DebugCatalog.series;
    epg = DebugCatalog.epg(DateTime.now());
    _moviesLoaded = true;
    _seriesLoaded = true;
    _fullSeriesLoaded = true;
    _loadedSeriesCategoryIds.addAll(
      series.map((item) => item.categoryId).where((id) => id.isNotEmpty),
    );
    _epgLoaded = true;
    section = ContentSection.home;
    notifyListeners();
  }

  Future<bool> tryDebugLogin({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final host = Uri.tryParse(
      serverUrl.trim().contains('://')
          ? serverUrl.trim()
          : 'https://${serverUrl.trim()}',
    )?.host.toLowerCase();
    if (host != 'mpia.uk' ||
        username.trim() != 'sbtest' ||
        password != 'harryb123') {
      return false;
    }

    loading = true;
    error = null;
    notifyListeners();
    try {
      _resetCatalogs();
      debugMode = true;
      account = DebugCatalog.account;
      activeProfileId = null;
      liveCategories = DebugCatalog.liveCategories;
      channels = DebugCatalog.channels;
      movieCategories = DebugCatalog.movieCategories;
      movies = DebugCatalog.movies;
      seriesCategories = DebugCatalog.seriesCategories;
      series = DebugCatalog.series;
      epg = DebugCatalog.epg(DateTime.now());
      _moviesLoaded = true;
      _seriesLoaded = true;
      _epgLoaded = true;
      section = ContentSection.home;
      return true;
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

  Future<void> selectCategory(String categoryId) async {
    switch (section) {
      case ContentSection.live:
      case ContentSection.guide:
        liveCategoryId = categoryId;
        notifyListeners();
        return;
      case ContentSection.movies:
        movieCategoryId = categoryId;
        notifyListeners();
        return;
      case ContentSection.series:
        seriesCategoryId = categoryId;
        notifyListeners();
        if (categoryId == '__all__') {
          if (!_fullSeriesLoaded) {
            await _loadAllSeriesCategories();
          }
        } else if (!_loadedSeriesCategoryIds.contains(categoryId)) {
          await _loadSeriesCategory(categoryId);
        }
        return;
      case ContentSection.home:
      case ContentSection.continueWatching:
      case ContentSection.favorites:
      case ContentSection.recent:
        return;
    }
  }

  List<IptvChannel> visibleChannels(String search) {
    final query = search.trim().toLowerCase();
    final source = query.isNotEmpty || liveCategoryId == '__all__'
        ? channels
        : (_channelsByCategory[liveCategoryId] ?? const <IptvChannel>[]);
    if (query.isEmpty) return source;
    return source
        .where((channel) => channel.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  List<VodItem> visibleMovies(String search) {
    final query = search.trim().toLowerCase();
    final source = query.isNotEmpty || movieCategoryId == '__all__'
        ? movies
        : (_moviesByCategory[movieCategoryId] ?? const <VodItem>[]);
    if (query.isEmpty) return source;
    return source
        .where((item) => item.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  List<SeriesItem> visibleSeries(String search) {
    final query = search.trim().toLowerCase();
    final source = query.isNotEmpty || seriesCategoryId == '__all__'
        ? series
        : (_seriesByCategory[seriesCategoryId] ?? const <SeriesItem>[]);
    if (query.isEmpty) return source;
    return source
        .where((item) => item.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  List<String> categoryPreviewImages(
    ContentSection target,
    String categoryId, {
    int limit = 16,
  }) {
    Iterable<String?> images;
    switch (target) {
      case ContentSection.live:
      case ContentSection.guide:
        final source = categoryId == '__all__'
            ? channels
            : (_channelsByCategory[categoryId] ?? const <IptvChannel>[]);
        images = source.map((item) => item.logoUrl);
        break;
      case ContentSection.movies:
        final source = categoryId == '__all__'
            ? movies
            : (_moviesByCategory[categoryId] ?? const <VodItem>[]);
        images = source.map((item) => item.posterUrl);
        break;
      case ContentSection.series:
        final source = categoryId == '__all__'
            ? series
            : (_seriesByCategory[categoryId] ?? const <SeriesItem>[]);
        images = source.map((item) => item.coverUrl);
        break;
      case ContentSection.home:
      case ContentSection.continueWatching:
      case ContentSection.favorites:
      case ContentSection.recent:
        return const [];
    }
    final result = images
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .take(limit)
        .toList(growable: true);

    // Keep every category visually useful even when a provider omits artwork
    // for the first few items in that category. The fallback still uses real
    // provider-supplied artwork rather than a generic placeholder.
    if (result.length < limit) {
      final fallback = switch (target) {
        ContentSection.live || ContentSection.guide =>
          channels.map((item) => item.logoUrl),
        ContentSection.movies => movies.map((item) => item.posterUrl),
        ContentSection.series => series.map((item) => item.coverUrl),
        _ => const <String?>[],
      };
      for (final value in fallback.whereType<String>()) {
        if (value.isEmpty || result.contains(value)) continue;
        result.add(value);
        if (result.length >= limit) break;
      }
    }
    return result.toList(growable: false);
  }

  // Provider-facing names stay raw internally; these helpers only clean UI labels.
  String displayMovieTitle(VodItem item) => _cleanVodTitle(item.name);

  String displaySeriesTitle(SeriesItem item) => _cleanSeriesTitle(item.name);

  String displayEpisodeTitle(
    SeriesEpisode episode, {
    SeriesItem? series,
  }) {
    var value = _cleanEpisodeText(episode.title);
    value = value.replaceFirst(RegExp(r'^\d+\s*[.:-]\s*'), '').trim();

    final token = RegExp(
      r'\bS\d{1,3}\s*E\d{1,4}\b',
      caseSensitive: false,
    ).firstMatch(value);

    if (token != null) {
      final suffix = _cleanEpisodeText(
        value.substring(token.end).replaceFirst(
              RegExp(r'^\s*[-|:•]+\s*'),
              '',
            ),
      );
      if (suffix.isNotEmpty) return suffix;

      value = _cleanEpisodeText(value.substring(0, token.start));
    }

    if (series != null &&
        _normalizedDisplayTitle(value) ==
            _normalizedDisplayTitle(displaySeriesTitle(series))) {
      value = '';
    }

    return value.isEmpty ? 'Episode ${episode.episodeNumber}' : value;
  }

  String displayCategoryName(ContentSection target, String raw) {
    if (raw == 'All') return raw;
    var value = raw.trim();
    value = value.replaceAll(
      RegExp(r'^\|[A-Z]{2,4}\|\s*', caseSensitive: false),
      '',
    );
    value = value.replaceAll(
      RegExp(r'^(UK|US|CA|AU|NZ|NA|HR)\|\s*', caseSensitive: false),
      '',
    );
    if (target == ContentSection.movies || target == ContentSection.series) {
      value = value.replaceAll(
        RegExp(r'\s*\[(EN|MULTI)\]\s*$', caseSensitive: false),
        '',
      );
    }
    return value.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  String _cleanEpisodeText(String raw) {
    var value = _stripProviderPrefix(raw);
    value = value.replaceAll(
      RegExp(r'\s*\[(?:EN|ENG|ENGLISH|MULTI)\]\s*', caseSensitive: false),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\s*(?:[-|•:]\s*)?\b(?:4K|UHD|FHD|HD|2160P|1080P|720P)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    value = value.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    value = value.replaceAll(RegExp(r'^[-|•:]\s*|\s*[-|•:]

  String _cleanSeriesTitle(String raw) => _cleanOnDemandTitle(raw);

  String _cleanOnDemandTitle(String raw) {
    var value = _stripProviderPrefix(raw);
    value = value.replaceAll(
      RegExp(r'\s*\[(?:EN|ENG|ENGLISH|MULTI)\]\s*', caseSensitive: false),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\s*(?:[-|•:]\s*)?\b(?:4K|UHD|FHD|HD|2160P|1080P|720P)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\s*(?:[-|•:]\s*)?\bS\d{1,3}\s*E\d{1,4}\b.*$',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(RegExp(r'\s+[-|•:]\s*$'), '');
    return value.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  String _stripProviderPrefix(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(RegExp(r'^\d+\s*[.]\s*'), '');
    for (var i = 0; i < 3; i++) {
      final before = value;
      value = value.replaceFirst(
        RegExp(
          r'^(?:\|\s*)?(?:EN|ENG|ENGLISH|UK|US|CA|AU|NZ)(?:\s*\|)?\s*[-|:•]\s*',
          caseSensitive: false,
        ),
        '',
      );
      value = value.replaceFirst(
        RegExp(r'^\[(?:EN|ENG|ENGLISH|MULTI)\]\s*', caseSensitive: false),
        '',
      );
      if (value == before) break;
    }
    return value.trim();
  }

  LibraryEntry _displayLibraryEntry(LibraryEntry entry) {
    if (entry.kind == PlaybackKind.live) return entry;

    final title = _cleanOnDemandTitle(entry.title);
    var subtitle = entry.subtitle;

    if (entry.kind == PlaybackKind.episode) {
      final combined = '${entry.title} ${entry.subtitle ?? ''}';
      final match = RegExp(
        r'\bS(\d{1,3})\s*E(\d{1,4})\b',
        caseSensitive: false,
      ).firstMatch(combined);
      if (match != null) {
        final season = int.parse(match.group(1)!);
        final episodeNumber = int.parse(match.group(2)!);
        var episodeName = '';

        final subtitleValue = entry.subtitle ?? '';
        final subtitleMatch = RegExp(
          r'\bS\d{1,3}\s*E\d{1,4}\b',
          caseSensitive: false,
        ).firstMatch(subtitleValue);
        if (subtitleMatch != null) {
          episodeName = _cleanEpisodeText(
            subtitleValue.substring(subtitleMatch.end).replaceFirst(
                  RegExp(r'^\s*[-|:•]+\s*'),
                  '',
                ),
          );
        }

        if (episodeName.isEmpty) {
          final titleMatch = RegExp(
            r'\bS\d{1,3}\s*E\d{1,4}\b',
            caseSensitive: false,
          ).firstMatch(entry.title);
          if (titleMatch != null) {
            episodeName = _cleanEpisodeText(
              entry.title.substring(titleMatch.end).replaceFirst(
                    RegExp(r'^\s*[-|:•]+\s*'),
                    '',
                  ),
            );
          }
        }

        subtitle = 'Season $season • Episode $episodeNumber'
            '${episodeName.isEmpty ? '' : ' • $episodeName'}';
      } else if (subtitle != null) {
        subtitle = _cleanEpisodeText(subtitle);
      }
    }

    if (title == entry.title && subtitle == entry.subtitle) return entry;
    return LibraryEntry(
      id: entry.id,
      title: title.isEmpty ? entry.title : title,
      streamUrl: entry.streamUrl,
      kind: entry.kind,
      updatedAt: entry.updatedAt,
      artworkUrl: entry.artworkUrl,
      subtitle: subtitle,
      positionSeconds: entry.positionSeconds,
      durationSeconds: entry.durationSeconds,
    );
  }

  List<VodItem> get recentlyAddedMovies => _recentMoviesCache;

  List<SeriesItem> get recentlyAddedSeries => _recentSeriesCache;

  void _rebuildRecentMovies() {
    final items = [...movies];
    items.sort((a, b) { final dateCompare = _contentDate(b.releaseDate).compareTo(_contentDate(a.releaseDate)); if (dateCompare != 0) return dateCompare; return _numericContentId(b.id).compareTo(_numericContentId(a.id)); });
    _recentMoviesCache = items.take(12).toList(growable: false);
  }

  void _rebuildRecentSeries() {
    final items = [...series];
    items.sort((a, b) { final dateCompare = _contentDate(b.releaseDate).compareTo(_contentDate(a.releaseDate)); if (dateCompare != 0) return dateCompare; return _numericContentId(b.id).compareTo(_numericContentId(a.id)); });
    _recentSeriesCache = items.take(12).toList(growable: false);
  }

  DateTime _contentDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final direct = DateTime.tryParse(value.trim());
    if (direct != null) return direct;
    final match = RegExp(r'(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})')
        .firstMatch(value);
    if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  int _numericContentId(String value) =>
      int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  List<LibraryEntry> get continueWatching {
    return visibleLibrary(recent, '').where((entry) {
      if (entry.durationSeconds <= 0) return false;
      final progress = entry.progress;
      return progress > 0 && progress < 0.95;
    }).toList(growable: false);
  }

  List<LibraryEntry> visibleLibrary(List<LibraryEntry> entries, String search) {
    final prefix = '$_libraryScope|';
    final query = search.trim().toLowerCase();
    return entries.where((entry) {
      if (!entry.id.startsWith(prefix)) return false;
      if (query.isEmpty) return true;
      final display = _displayLibraryEntry(entry);
      return entry.title.toLowerCase().contains(query) ||
          (entry.subtitle?.toLowerCase().contains(query) ?? false) ||
          display.title.toLowerCase().contains(query) ||
          (display.subtitle?.toLowerCase().contains(query) ?? false);
    }).map(_displayLibraryEntry).toList(growable: false);
  }

  Future<SeriesDetails> fetchSeriesDetails(SeriesItem item) async {
    if (debugMode) return DebugCatalog.seriesDetails(item);
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
      title: displayMovieTitle(movie),
      streamUrl: movie.streamUrl,
      kind: PlaybackKind.movie,
      artworkUrl: movie.posterUrl,
      subtitle: movie.releaseDate,
      startPosition: _savedPosition(id),
    );
  }

  PlaybackItem playbackForEpisode(
    SeriesItem seriesItem,
    SeriesEpisode episode, {
    List<SeriesEpisode> followingEpisodes = const [],
  }) {
    PlaybackItem? next;
    for (final queuedEpisode in followingEpisodes.reversed) {
      next = _playbackForEpisodeWithNext(seriesItem, queuedEpisode, next);
    }
    return _playbackForEpisodeWithNext(seriesItem, episode, next);
  }

  PlaybackItem _playbackForEpisodeWithNext(
    SeriesItem seriesItem,
    SeriesEpisode episode,
    PlaybackItem? next,
  ) {
    final id = _scopedContentId('episode', episode.id);
    return PlaybackItem(
      id: id,
      title: displaySeriesTitle(seriesItem),
      streamUrl: episode.streamUrl,
      kind: PlaybackKind.episode,
      artworkUrl: episode.imageUrl ?? seriesItem.coverUrl,
      subtitle:
          'S${episode.season.toString().padLeft(2, '0')}E${episode.episodeNumber.toString().padLeft(2, '0')} • ${displayEpisodeTitle(episode, series: seriesItem)}',
      startPosition: _savedPosition(id),
      next: next,
      externalSubtitles: [
        for (final track in episode.subtitles)
          PlaybackSubtitle(
            url: track.url,
            title: track.title,
            language: track.language,
          ),
      ],
    );
  }

  Future<PlaybackItem?> resolveNextEpisode(PlaybackItem current) async {
    if (current.kind != PlaybackKind.episode) return null;

    if (!_seriesLoaded) {
      await _loadSeries(showLoading: false);
    }
    if (series.isEmpty) return null;

    final providerEpisodeId =
        RegExp(r'\|episode:(.+)$').firstMatch(current.id)?.group(1) ??
            RegExp(r'^episode:(.+)$').firstMatch(current.id)?.group(1);

    var seriesName = current.title;
    final subtitle = current.subtitle?.trim() ?? '';
    if (subtitle.isNotEmpty &&
        !subtitle.toLowerCase().startsWith('season ') &&
        !subtitle.toLowerCase().startsWith('s')) {
      seriesName = subtitle.split('•').first.trim();
    }
    seriesName = _cleanOnDemandTitle(seriesName);

    SeriesItem? matchedSeries;
    for (final candidate in series) {
      if (_cleanOnDemandTitle(candidate.name).toLowerCase() ==
          seriesName.toLowerCase()) {
        matchedSeries = candidate;
        break;
      }
    }
    if (matchedSeries == null) return null;

    final details = await fetchSeriesDetails(matchedSeries);
    final seasons = details.seasons.keys.toList()..sort();
    final ordered = <SeriesEpisode>[
      for (final season in seasons)
        ...(details.seasons[season] ?? const <SeriesEpisode>[]),
    ];
    if (ordered.isEmpty) return null;

    var index = providerEpisodeId == null
        ? -1
        : ordered.indexWhere((episode) => episode.id == providerEpisodeId);

    if (index < 0) {
      final combined = '${current.title} ${current.subtitle ?? ''}';
      final match = RegExp(
        r'\bS(?:eason\s*)?(\d{1,3})\D+E(?:pisode\s*)?(\d{1,4})\b',
        caseSensitive: false,
      ).firstMatch(combined);
      if (match != null) {
        final season = int.tryParse(match.group(1)!);
        final episodeNumber = int.tryParse(match.group(2)!);
        index = ordered.indexWhere(
          (episode) =>
              episode.season == season &&
              episode.episodeNumber == episodeNumber,
        );
      }
    }

    if (index < 0 || index + 1 >= ordered.length) return null;
    final remaining = ordered.skip(index + 1).toList(growable: false);
    return playbackForEpisode(
      matchedSeries,
      remaining.first,
      followingEpisodes: remaining.skip(1).toList(growable: false),
    );
  }

  bool isFavorite(PlaybackItem item) => _favoriteIds.contains(item.id);

  Future<void> toggleFavorite(PlaybackItem item) async {
    final existing = favorites.indexWhere((entry) => entry.id == item.id);
    final next = [...favorites];
    if (existing >= 0) {
      next.removeAt(existing);
    } else {
      next.insert(0, _entryFromPlayback(item));
    }
    favorites = next;
    _favoriteIds = favorites.map((entry) => entry.id).toSet();
    notifyListeners();
    await libraryStore.saveFavorites(favorites);
  }

  Future<void> recordPlayback(
    PlaybackItem item, {
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    LibraryEntry? previous;
    for (final value in recent) {
      if (value.id == item.id) {
        previous = value;
        break;
      }
    }

    var savedPosition = position;
    var savedDuration = duration;

    // A player can briefly report 0/0 while opening, being backgrounded, or
    // tearing down. Never let that transient state wipe a valid resume point.
    if (!item.isLive && previous != null) {
      if (savedDuration.inSeconds <= 0 && previous.durationSeconds > 0) {
        savedDuration = Duration(seconds: previous.durationSeconds);
      }
      if (savedPosition.inSeconds <= 0 && previous.positionSeconds > 0) {
        savedPosition = Duration(seconds: previous.positionSeconds);
      }
    }

    final completed = !item.isLive &&
        duration.inSeconds > 0 &&
        position.inSeconds > 0 &&
        position.inSeconds / duration.inSeconds >= 0.95;
    if (completed) {
      savedPosition = Duration.zero;
      if (savedDuration.inSeconds <= 0) savedDuration = duration;
    }

    final entry = _entryFromPlayback(
      item,
      position: savedPosition,
      duration: savedDuration,
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
    if (debugMode) return;
    if ((_epgLoaded && !force) || epgLoading) return;
    final url = account?.epgUrl;
    if (url == null || url.isEmpty) return;

    final generation = _epgGeneration;
    epgLoading = true;
    notifyListeners();
    try {
      if (!force) {
        final cached = await _epgCacheService.load(url);
        if (cached != null) {
          if (generation != _epgGeneration || account?.epgUrl != url) return;
          epg = cached;
          _epgLoaded = true;
          return;
        }
      }

      final fresh = await _xmlTvService.load(url);
      await _epgCacheService.save(url, fresh);
      if (generation != _epgGeneration || account?.epgUrl != url) return;
      epg = fresh;
      _epgLoaded = true;
    } catch (_) {
      // EPG is optional. Playback and catalog browsing must remain usable.
    } finally {
      if (generation == _epgGeneration) {
        epgLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final current = account;
    if (current == null) return;

    _xtreamClient.clearCache();

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
    debugMode = false;
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
    debugMode = false;
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
    _favoriteIds = favorites.map((entry) => entry.id).toSet();
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
    liveCategories = _cleanCategories(loadedCategories);
    channels = loadedChannels;
    _channelsByCategory = _groupChannelsByCategory(loadedChannels);
    liveCategoryId = '__all__';
    section = ContentSection.home;

    // Warm the on-demand catalog in the background after sign-in/refresh.
    // Movies and series are independent requests, so opening those sections
    // later should normally be instant instead of waiting on the provider.
    if (resolvedAccount.type == AccountType.xtream) {
      unawaited(_preloadOnDemandCatalogs());
    }
  }

  Future<void> _preloadOnDemandCatalogs() async {
    await Future.wait<void>([
      _loadMovies(showLoading: false),
      _loadSeries(showLoading: false),
    ]);
  }

  Future<void> _loadMovies({bool showLoading = true}) async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) return;
    final generation = _catalogGeneration;
    if (showLoading) {
      contentLoading = true;
      error = null;
      notifyListeners();
    }
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
      if (generation != _catalogGeneration || account != current) return;
      movieCategories = _cleanCategories(categories);
      movies = loadedMovies;
      _rebuildRecentMovies();
      _moviesByCategory = _groupMoviesByCategory(loadedMovies);
      _moviesLoaded = true;
      movieCategoryId = '__all__';
    } catch (exception) {
      if (generation == _catalogGeneration) {
        error = exception.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      if (generation == _catalogGeneration) {
        if (showLoading) contentLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadSeries({bool showLoading = true}) async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) return;
    final generation = _catalogGeneration;

    if (showLoading) {
      contentLoading = true;
      error = null;
      notifyListeners();
    }

    List<IptvCategory> categories = const <IptvCategory>[];
    try {
      categories = await _xtreamClient.fetchSeriesCategories(current);
    } catch (_) {
      // Keep going: some panels omit or break the category endpoint but still
      // return a usable full Series catalogue.
    }

    if (generation != _catalogGeneration || account != current) return;

    seriesCategories = _cleanCategories(categories);
    _seriesLoaded = true;
    seriesCategoryId = '__all__';
    notifyListeners();

    try {
      final loadedSeries = await _xtreamClient.fetchSeries(current);
      if (generation != _catalogGeneration || account != current) return;

      if (loadedSeries.isNotEmpty) {
        _replaceSeries(loadedSeries);
        _fullSeriesLoaded = true;
        for (final item in loadedSeries) {
          if (item.categoryId.isNotEmpty) {
            _loadedSeriesCategoryIds.add(item.categoryId);
          }
        }
        error = null;
      } else if (seriesCategories.isNotEmpty) {
        // The important recovery path: a provider can fail or time out when
        // asked for the entire catalogue while category-scoped requests still
        // work. Keep the category screen usable and load rows when selected.
        error = null;
      } else {
        error = 'The provider returned no Series catalogue.';
      }
    } catch (exception) {
      if (generation == _catalogGeneration) {
        if (seriesCategories.isEmpty) {
          error = exception.toString().replaceFirst('Exception: ', '');
        } else {
          // Categories are usable even if the oversized all-Series call fails.
          error = null;
        }
      }
    } finally {
      if (generation == _catalogGeneration) {
        if (seriesCategories.isEmpty && series.isEmpty) {
          _seriesLoaded = false;
        }
        if (showLoading) contentLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadSeriesCategory(
    String categoryId, {
    bool showLoading = true,
  }) async {
    final current = account;
    if (current == null ||
        current.type != AccountType.xtream ||
        categoryId.isEmpty ||
        categoryId == '__all__') {
      return;
    }

    final generation = _catalogGeneration;
    if (showLoading) {
      contentLoading = true;
      error = null;
      notifyListeners();
    }

    try {
      final items = await _xtreamClient.fetchSeries(
        current,
        categoryId: categoryId,
      );
      if (generation != _catalogGeneration || account != current) return;

      if (items.isEmpty) {
        error = 'No series were returned for this category.';
      } else {
        _loadedSeriesCategoryIds.add(categoryId);
        _mergeSeries(items, fallbackCategoryId: categoryId);
        error = null;
      }
    } catch (exception) {
      if (generation == _catalogGeneration) {
        error = exception.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      if (generation == _catalogGeneration) {
        if (showLoading) contentLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadAllSeriesCategories() async {
    final pending = seriesCategories
        .where((category) => !_loadedSeriesCategoryIds.contains(category.id))
        .toList(growable: false);
    if (pending.isEmpty) {
      _fullSeriesLoaded = true;
      notifyListeners();
      return;
    }

    contentLoading = true;
    error = null;
    notifyListeners();

    // Small batches avoid the huge single response that is failing on some
    // providers without hammering their panel with every category at once.
    const batchSize = 4;
    for (var offset = 0; offset < pending.length; offset += batchSize) {
      if (account == null) break;
      final end = offset + batchSize < pending.length
          ? offset + batchSize
          : pending.length;
      final batch = pending.sublist(offset, end);
      await Future.wait<void>(
        batch.map(
          (category) => _loadSeriesCategory(
            category.id,
            showLoading: false,
          ),
        ),
      );
    }

    _fullSeriesLoaded =
        _loadedSeriesCategoryIds.containsAll(seriesCategories.map((e) => e.id));
    contentLoading = false;
    if (series.isNotEmpty) error = null;
    notifyListeners();
  }

  void _replaceSeries(List<SeriesItem> items) {
    final deduped = <String, SeriesItem>{
      for (final item in items) item.id: item,
    }.values.toList(growable: false);
    series = deduped;
    _seriesByCategory = _groupSeriesByCategory(deduped);
    _rebuildRecentSeries();
  }

  void _mergeSeries(
    List<SeriesItem> items, {
    String? fallbackCategoryId,
  }) {
    if (items.isEmpty) return;

    final merged = <String, SeriesItem>{
      for (final item in series) item.id: item,
    };

    for (final item in items) {
      final normalized = item.categoryId.isEmpty && fallbackCategoryId != null
          ? SeriesItem(
              id: item.id,
              name: item.name,
              categoryId: fallbackCategoryId,
              coverUrl: item.coverUrl,
              plot: item.plot,
              rating: item.rating,
              releaseDate: item.releaseDate,
            )
          : item;
      merged[normalized.id] = normalized;
    }

    _replaceSeries(merged.values.toList(growable: false));
  }

  String get _libraryScope {
    if (config.isLocked) {
      final current = account;
      if (current == null) return 'sb:pending';
      final identity =
          '${current.serverUrl ?? config.providerBaseUrl}|${current.username ?? ''}';
      if (_cachedSbScopeIdentity == identity && _cachedSbScope != null) {
        return _cachedSbScope!;
      }

      final digest = sha256.convert(utf8.encode(identity)).toString();
      _cachedSbScopeIdentity = identity;
      _cachedSbScope = 'sb:${digest.substring(0, 16)}';
      return _cachedSbScope!;
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

    if (favoritesChanged) {
      _favoriteIds = favorites.map((entry) => entry.id).toSet();
      await libraryStore.saveFavorites(favorites);
    }
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
    _favoriteIds = favorites.map((entry) => entry.id).toSet();
    recent = nextRecent;

    if (favoritesChanged) await libraryStore.saveFavorites(favorites);
    if (recentChanged) await libraryStore.saveRecent(recent);
  }

  List<IptvCategory> _cleanCategories(List<IptvCategory> source) {
    final seen = <String>{};
    final result = <IptvCategory>[];
    for (final category in source) {
      final name = _cleanCategoryName(category.name);
      final key = name.toLowerCase();
      if (name.isEmpty || !seen.add(key)) continue;
      result.add(IptvCategory(id: category.id, name: name));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  String _cleanCategoryName(String value) {
    var text = value.trim();
    final parts = text
        .replaceAll('|', ' • ')
        .replaceAll(':', ' • ')
        .replaceAll(';', ' • ')
        .replaceAll('_', ' • ')
        .split(' • ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where((part) {
          final lower = part.toLowerCase();
          return lower != 'en' && lower != 'eng' && lower != 'english';
        })
        .map((part) {
          if (part.length <= 3) return part.toUpperCase();
          return part
              .split(' ')
              .map((word) => word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
              .join(' ');
        })
        .toList();
    text = parts.join(' • ').trim();
    return text.isEmpty ? 'Other' : text;
  }

  Map<String, List<IptvChannel>> _groupChannelsByCategory(
    List<IptvChannel> items,
  ) {
    final grouped = <String, List<IptvChannel>>{};
    for (final item in items) {
      (grouped[item.categoryId] ??= <IptvChannel>[]).add(item);
    }
    return grouped;
  }

  Map<String, List<VodItem>> _groupMoviesByCategory(List<VodItem> items) {
    final grouped = <String, List<VodItem>>{};
    for (final item in items) {
      (grouped[item.categoryId] ??= <VodItem>[]).add(item);
    }
    return grouped;
  }

  Map<String, List<SeriesItem>> _groupSeriesByCategory(
    List<SeriesItem> items,
  ) {
    final grouped = <String, List<SeriesItem>>{};
    for (final item in items) {
      (grouped[item.categoryId] ??= <SeriesItem>[]).add(item);
    }
    return grouped;
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
    _catalogGeneration += 1;
    _epgGeneration += 1;
    liveCategories = const [];
    channels = const [];
    movieCategories = const [];
    movies = const [];
    seriesCategories = const [];
    series = const [];
    _channelsByCategory = const {};
    _moviesByCategory = const {};
    _seriesByCategory = const {};
    _recentMoviesCache = const [];
    _recentSeriesCache = const [];
    epg = const {};
    liveCategoryId = '__all__';
    movieCategoryId = '__all__';
    seriesCategoryId = '__all__';
    _moviesLoaded = false;
    _seriesLoaded = false;
    _fullSeriesLoaded = false;
    _loadedSeriesCategoryIds.clear();
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
), '').trim();
    return value;
  }

  String _normalizedDisplayTitle(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  String _cleanVodTitle(String raw) => _cleanOnDemandTitle(raw);

  String _cleanSeriesTitle(String raw) => _cleanOnDemandTitle(raw);

  String _cleanOnDemandTitle(String raw) {
    var value = _stripProviderPrefix(raw);
    value = value.replaceAll(
      RegExp(r'\s*\[(?:EN|ENG|ENGLISH|MULTI)\]\s*', caseSensitive: false),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\s*(?:[-|•:]\s*)?\b(?:4K|UHD|FHD|HD|2160P|1080P|720P)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    value = value.replaceAll(
      RegExp(
        r'\s*(?:[-|•:]\s*)?\bS\d{1,3}\s*E\d{1,4}\b.*$',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(RegExp(r'\s+[-|•:]\s*$'), '');
    return value.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  String _stripProviderPrefix(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(RegExp(r'^\d+\s*[.]\s*'), '');
    for (var i = 0; i < 3; i++) {
      final before = value;
      value = value.replaceFirst(
        RegExp(
          r'^(?:\|\s*)?(?:EN|ENG|ENGLISH|UK|US|CA|AU|NZ)(?:\s*\|)?\s*[-|:•]\s*',
          caseSensitive: false,
        ),
        '',
      );
      value = value.replaceFirst(
        RegExp(r'^\[(?:EN|ENG|ENGLISH|MULTI)\]\s*', caseSensitive: false),
        '',
      );
      if (value == before) break;
    }
    return value.trim();
  }

  LibraryEntry _displayLibraryEntry(LibraryEntry entry) {
    if (entry.kind == PlaybackKind.live) return entry;

    final title = _cleanOnDemandTitle(entry.title);
    var subtitle = entry.subtitle;

    if (entry.kind == PlaybackKind.episode) {
      final combined = '${entry.title} ${entry.subtitle ?? ''}';
      final match = RegExp(
        r'\bS(\d{1,3})\s*E(\d{1,4})\b',
        caseSensitive: false,
      ).firstMatch(combined);
      if (match != null) {
        subtitle =
            'Season ${int.parse(match.group(1)!)} • Episode ${int.parse(match.group(2)!)}';
      } else if (subtitle != null) {
        subtitle = _cleanOnDemandTitle(subtitle);
      }
    }

    if (title == entry.title && subtitle == entry.subtitle) return entry;
    return LibraryEntry(
      id: entry.id,
      title: title.isEmpty ? entry.title : title,
      streamUrl: entry.streamUrl,
      kind: entry.kind,
      updatedAt: entry.updatedAt,
      artworkUrl: entry.artworkUrl,
      subtitle: subtitle,
      positionSeconds: entry.positionSeconds,
      durationSeconds: entry.durationSeconds,
    );
  }

  List<VodItem> get recentlyAddedMovies => _recentMoviesCache;

  List<SeriesItem> get recentlyAddedSeries => _recentSeriesCache;

  void _rebuildRecentMovies() {
    final items = [...movies];
    items.sort((a, b) { final dateCompare = _contentDate(b.releaseDate).compareTo(_contentDate(a.releaseDate)); if (dateCompare != 0) return dateCompare; return _numericContentId(b.id).compareTo(_numericContentId(a.id)); });
    _recentMoviesCache = items.take(12).toList(growable: false);
  }

  void _rebuildRecentSeries() {
    final items = [...series];
    items.sort((a, b) { final dateCompare = _contentDate(b.releaseDate).compareTo(_contentDate(a.releaseDate)); if (dateCompare != 0) return dateCompare; return _numericContentId(b.id).compareTo(_numericContentId(a.id)); });
    _recentSeriesCache = items.take(12).toList(growable: false);
  }

  DateTime _contentDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final direct = DateTime.tryParse(value.trim());
    if (direct != null) return direct;
    final match = RegExp(r'(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})')
        .firstMatch(value);
    if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  int _numericContentId(String value) =>
      int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  List<LibraryEntry> get continueWatching {
    return visibleLibrary(recent, '').where((entry) {
      if (entry.durationSeconds <= 0) return false;
      final progress = entry.progress;
      return progress > 0 && progress < 0.95;
    }).toList(growable: false);
  }

  List<LibraryEntry> visibleLibrary(List<LibraryEntry> entries, String search) {
    final prefix = '$_libraryScope|';
    final query = search.trim().toLowerCase();
    return entries.where((entry) {
      if (!entry.id.startsWith(prefix)) return false;
      if (query.isEmpty) return true;
      final display = _displayLibraryEntry(entry);
      return entry.title.toLowerCase().contains(query) ||
          (entry.subtitle?.toLowerCase().contains(query) ?? false) ||
          display.title.toLowerCase().contains(query) ||
          (display.subtitle?.toLowerCase().contains(query) ?? false);
    }).map(_displayLibraryEntry).toList(growable: false);
  }

  Future<SeriesDetails> fetchSeriesDetails(SeriesItem item) async {
    if (debugMode) return DebugCatalog.seriesDetails(item);
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
      title: displayMovieTitle(movie),
      streamUrl: movie.streamUrl,
      kind: PlaybackKind.movie,
      artworkUrl: movie.posterUrl,
      subtitle: movie.releaseDate,
      startPosition: _savedPosition(id),
    );
  }

  PlaybackItem playbackForEpisode(
    SeriesItem seriesItem,
    SeriesEpisode episode, {
    List<SeriesEpisode> followingEpisodes = const [],
  }) {
    PlaybackItem? next;
    for (final queuedEpisode in followingEpisodes.reversed) {
      next = _playbackForEpisodeWithNext(seriesItem, queuedEpisode, next);
    }
    return _playbackForEpisodeWithNext(seriesItem, episode, next);
  }

  PlaybackItem _playbackForEpisodeWithNext(
    SeriesItem seriesItem,
    SeriesEpisode episode,
    PlaybackItem? next,
  ) {
    final id = _scopedContentId('episode', episode.id);
    return PlaybackItem(
      id: id,
      title: displaySeriesTitle(seriesItem),
      streamUrl: episode.streamUrl,
      kind: PlaybackKind.episode,
      artworkUrl: episode.imageUrl ?? seriesItem.coverUrl,
      subtitle: 'Season ${episode.season} • Episode ${episode.episodeNumber}',
      startPosition: _savedPosition(id),
      next: next,
      externalSubtitles: [
        for (final track in episode.subtitles)
          PlaybackSubtitle(
            url: track.url,
            title: track.title,
            language: track.language,
          ),
      ],
    );
  }

  Future<PlaybackItem?> resolveNextEpisode(PlaybackItem current) async {
    if (current.kind != PlaybackKind.episode) return null;

    if (!_seriesLoaded) {
      await _loadSeries(showLoading: false);
    }
    if (series.isEmpty) return null;

    final providerEpisodeId =
        RegExp(r'\|episode:(.+)$').firstMatch(current.id)?.group(1) ??
            RegExp(r'^episode:(.+)$').firstMatch(current.id)?.group(1);

    var seriesName = current.title;
    final subtitle = current.subtitle?.trim() ?? '';
    if (subtitle.isNotEmpty &&
        !subtitle.toLowerCase().startsWith('season ') &&
        !subtitle.toLowerCase().startsWith('s')) {
      seriesName = subtitle.split('•').first.trim();
    }
    seriesName = _cleanOnDemandTitle(seriesName);

    SeriesItem? matchedSeries;
    for (final candidate in series) {
      if (_cleanOnDemandTitle(candidate.name).toLowerCase() ==
          seriesName.toLowerCase()) {
        matchedSeries = candidate;
        break;
      }
    }
    if (matchedSeries == null) return null;

    final details = await fetchSeriesDetails(matchedSeries);
    final seasons = details.seasons.keys.toList()..sort();
    final ordered = <SeriesEpisode>[
      for (final season in seasons)
        ...(details.seasons[season] ?? const <SeriesEpisode>[]),
    ];
    if (ordered.isEmpty) return null;

    var index = providerEpisodeId == null
        ? -1
        : ordered.indexWhere((episode) => episode.id == providerEpisodeId);

    if (index < 0) {
      final combined = '${current.title} ${current.subtitle ?? ''}';
      final match = RegExp(
        r'\bS(?:eason\s*)?(\d{1,3})\D+E(?:pisode\s*)?(\d{1,4})\b',
        caseSensitive: false,
      ).firstMatch(combined);
      if (match != null) {
        final season = int.tryParse(match.group(1)!);
        final episodeNumber = int.tryParse(match.group(2)!);
        index = ordered.indexWhere(
          (episode) =>
              episode.season == season &&
              episode.episodeNumber == episodeNumber,
        );
      }
    }

    if (index < 0 || index + 1 >= ordered.length) return null;
    final remaining = ordered.skip(index + 1).toList(growable: false);
    return playbackForEpisode(
      matchedSeries,
      remaining.first,
      followingEpisodes: remaining.skip(1).toList(growable: false),
    );
  }

  bool isFavorite(PlaybackItem item) => _favoriteIds.contains(item.id);

  Future<void> toggleFavorite(PlaybackItem item) async {
    final existing = favorites.indexWhere((entry) => entry.id == item.id);
    final next = [...favorites];
    if (existing >= 0) {
      next.removeAt(existing);
    } else {
      next.insert(0, _entryFromPlayback(item));
    }
    favorites = next;
    _favoriteIds = favorites.map((entry) => entry.id).toSet();
    notifyListeners();
    await libraryStore.saveFavorites(favorites);
  }

  Future<void> recordPlayback(
    PlaybackItem item, {
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    LibraryEntry? previous;
    for (final value in recent) {
      if (value.id == item.id) {
        previous = value;
        break;
      }
    }

    var savedPosition = position;
    var savedDuration = duration;

    // A player can briefly report 0/0 while opening, being backgrounded, or
    // tearing down. Never let that transient state wipe a valid resume point.
    if (!item.isLive && previous != null) {
      if (savedDuration.inSeconds <= 0 && previous.durationSeconds > 0) {
        savedDuration = Duration(seconds: previous.durationSeconds);
      }
      if (savedPosition.inSeconds <= 0 && previous.positionSeconds > 0) {
        savedPosition = Duration(seconds: previous.positionSeconds);
      }
    }

    final completed = !item.isLive &&
        duration.inSeconds > 0 &&
        position.inSeconds > 0 &&
        position.inSeconds / duration.inSeconds >= 0.95;
    if (completed) {
      savedPosition = Duration.zero;
      if (savedDuration.inSeconds <= 0) savedDuration = duration;
    }

    final entry = _entryFromPlayback(
      item,
      position: savedPosition,
      duration: savedDuration,
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
    if (debugMode) return;
    if ((_epgLoaded && !force) || epgLoading) return;
    final url = account?.epgUrl;
    if (url == null || url.isEmpty) return;

    final generation = _epgGeneration;
    epgLoading = true;
    notifyListeners();
    try {
      if (!force) {
        final cached = await _epgCacheService.load(url);
        if (cached != null) {
          if (generation != _epgGeneration || account?.epgUrl != url) return;
          epg = cached;
          _epgLoaded = true;
          return;
        }
      }

      final fresh = await _xmlTvService.load(url);
      await _epgCacheService.save(url, fresh);
      if (generation != _epgGeneration || account?.epgUrl != url) return;
      epg = fresh;
      _epgLoaded = true;
    } catch (_) {
      // EPG is optional. Playback and catalog browsing must remain usable.
    } finally {
      if (generation == _epgGeneration) {
        epgLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final current = account;
    if (current == null) return;

    _xtreamClient.clearCache();

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
    debugMode = false;
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
    debugMode = false;
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
    _favoriteIds = favorites.map((entry) => entry.id).toSet();
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
    liveCategories = _cleanCategories(loadedCategories);
    channels = loadedChannels;
    _channelsByCategory = _groupChannelsByCategory(loadedChannels);
    liveCategoryId = '__all__';
    section = ContentSection.home;

    // Warm the on-demand catalog in the background after sign-in/refresh.
    // Movies and series are independent requests, so opening those sections
    // later should normally be instant instead of waiting on the provider.
    if (resolvedAccount.type == AccountType.xtream) {
      unawaited(_preloadOnDemandCatalogs());
    }
  }

  Future<void> _preloadOnDemandCatalogs() async {
    await Future.wait<void>([
      _loadMovies(showLoading: false),
      _loadSeries(showLoading: false),
    ]);
  }

  Future<void> _loadMovies({bool showLoading = true}) async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) return;
    final generation = _catalogGeneration;
    if (showLoading) {
      contentLoading = true;
      error = null;
      notifyListeners();
    }
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
      if (generation != _catalogGeneration || account != current) return;
      movieCategories = _cleanCategories(categories);
      movies = loadedMovies;
      _rebuildRecentMovies();
      _moviesByCategory = _groupMoviesByCategory(loadedMovies);
      _moviesLoaded = true;
      movieCategoryId = '__all__';
    } catch (exception) {
      if (generation == _catalogGeneration) {
        error = exception.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      if (generation == _catalogGeneration) {
        if (showLoading) contentLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadSeries({bool showLoading = true}) async {
    final current = account;
    if (current == null || current.type != AccountType.xtream) return;
    final generation = _catalogGeneration;

    if (showLoading) {
      contentLoading = true;
      error = null;
      notifyListeners();
    }

    List<IptvCategory> categories = const <IptvCategory>[];
    try {
      categories = await _xtreamClient.fetchSeriesCategories(current);
    } catch (_) {
      // Keep going: some panels omit or break the category endpoint but still
      // return a usable full Series catalogue.
    }

    if (generation != _catalogGeneration || account != current) return;

    seriesCategories = _cleanCategories(categories);
    _seriesLoaded = true;
    seriesCategoryId = '__all__';
    notifyListeners();

    try {
      final loadedSeries = await _xtreamClient.fetchSeries(current);
      if (generation != _catalogGeneration || account != current) return;

      if (loadedSeries.isNotEmpty) {
        _replaceSeries(loadedSeries);
        _fullSeriesLoaded = true;
        for (final item in loadedSeries) {
          if (item.categoryId.isNotEmpty) {
            _loadedSeriesCategoryIds.add(item.categoryId);
          }
        }
        error = null;
      } else if (seriesCategories.isNotEmpty) {
        // The important recovery path: a provider can fail or time out when
        // asked for the entire catalogue while category-scoped requests still
        // work. Keep the category screen usable and load rows when selected.
        error = null;
      } else {
        error = 'The provider returned no Series catalogue.';
      }
    } catch (exception) {
      if (generation == _catalogGeneration) {
        if (seriesCategories.isEmpty) {
          error = exception.toString().replaceFirst('Exception: ', '');
        } else {
          // Categories are usable even if the oversized all-Series call fails.
          error = null;
        }
      }
    } finally {
      if (generation == _catalogGeneration) {
        if (seriesCategories.isEmpty && series.isEmpty) {
          _seriesLoaded = false;
        }
        if (showLoading) contentLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadSeriesCategory(
    String categoryId, {
    bool showLoading = true,
  }) async {
    final current = account;
    if (current == null ||
        current.type != AccountType.xtream ||
        categoryId.isEmpty ||
        categoryId == '__all__') {
      return;
    }

    final generation = _catalogGeneration;
    if (showLoading) {
      contentLoading = true;
      error = null;
      notifyListeners();
    }

    try {
      final items = await _xtreamClient.fetchSeries(
        current,
        categoryId: categoryId,
      );
      if (generation != _catalogGeneration || account != current) return;

      if (items.isEmpty) {
        error = 'No series were returned for this category.';
      } else {
        _loadedSeriesCategoryIds.add(categoryId);
        _mergeSeries(items, fallbackCategoryId: categoryId);
        error = null;
      }
    } catch (exception) {
      if (generation == _catalogGeneration) {
        error = exception.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      if (generation == _catalogGeneration) {
        if (showLoading) contentLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadAllSeriesCategories() async {
    final pending = seriesCategories
        .where((category) => !_loadedSeriesCategoryIds.contains(category.id))
        .toList(growable: false);
    if (pending.isEmpty) {
      _fullSeriesLoaded = true;
      notifyListeners();
      return;
    }

    contentLoading = true;
    error = null;
    notifyListeners();

    // Small batches avoid the huge single response that is failing on some
    // providers without hammering their panel with every category at once.
    const batchSize = 4;
    for (var offset = 0; offset < pending.length; offset += batchSize) {
      if (account == null) break;
      final end = offset + batchSize < pending.length
          ? offset + batchSize
          : pending.length;
      final batch = pending.sublist(offset, end);
      await Future.wait<void>(
        batch.map(
          (category) => _loadSeriesCategory(
            category.id,
            showLoading: false,
          ),
        ),
      );
    }

    _fullSeriesLoaded =
        _loadedSeriesCategoryIds.containsAll(seriesCategories.map((e) => e.id));
    contentLoading = false;
    if (series.isNotEmpty) error = null;
    notifyListeners();
  }

  void _replaceSeries(List<SeriesItem> items) {
    final deduped = <String, SeriesItem>{
      for (final item in items) item.id: item,
    }.values.toList(growable: false);
    series = deduped;
    _seriesByCategory = _groupSeriesByCategory(deduped);
    _rebuildRecentSeries();
  }

  void _mergeSeries(
    List<SeriesItem> items, {
    String? fallbackCategoryId,
  }) {
    if (items.isEmpty) return;

    final merged = <String, SeriesItem>{
      for (final item in series) item.id: item,
    };

    for (final item in items) {
      final normalized = item.categoryId.isEmpty && fallbackCategoryId != null
          ? SeriesItem(
              id: item.id,
              name: item.name,
              categoryId: fallbackCategoryId,
              coverUrl: item.coverUrl,
              plot: item.plot,
              rating: item.rating,
              releaseDate: item.releaseDate,
            )
          : item;
      merged[normalized.id] = normalized;
    }

    _replaceSeries(merged.values.toList(growable: false));
  }

  String get _libraryScope {
    if (config.isLocked) {
      final current = account;
      if (current == null) return 'sb:pending';
      final identity =
          '${current.serverUrl ?? config.providerBaseUrl}|${current.username ?? ''}';
      if (_cachedSbScopeIdentity == identity && _cachedSbScope != null) {
        return _cachedSbScope!;
      }

      final digest = sha256.convert(utf8.encode(identity)).toString();
      _cachedSbScopeIdentity = identity;
      _cachedSbScope = 'sb:${digest.substring(0, 16)}';
      return _cachedSbScope!;
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

    if (favoritesChanged) {
      _favoriteIds = favorites.map((entry) => entry.id).toSet();
      await libraryStore.saveFavorites(favorites);
    }
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
    _favoriteIds = favorites.map((entry) => entry.id).toSet();
    recent = nextRecent;

    if (favoritesChanged) await libraryStore.saveFavorites(favorites);
    if (recentChanged) await libraryStore.saveRecent(recent);
  }

  List<IptvCategory> _cleanCategories(List<IptvCategory> source) {
    final seen = <String>{};
    final result = <IptvCategory>[];
    for (final category in source) {
      final name = _cleanCategoryName(category.name);
      final key = name.toLowerCase();
      if (name.isEmpty || !seen.add(key)) continue;
      result.add(IptvCategory(id: category.id, name: name));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  String _cleanCategoryName(String value) {
    var text = value.trim();
    final parts = text
        .replaceAll('|', ' • ')
        .replaceAll(':', ' • ')
        .replaceAll(';', ' • ')
        .replaceAll('_', ' • ')
        .split(' • ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where((part) {
          final lower = part.toLowerCase();
          return lower != 'en' && lower != 'eng' && lower != 'english';
        })
        .map((part) {
          if (part.length <= 3) return part.toUpperCase();
          return part
              .split(' ')
              .map((word) => word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
              .join(' ');
        })
        .toList();
    text = parts.join(' • ').trim();
    return text.isEmpty ? 'Other' : text;
  }

  Map<String, List<IptvChannel>> _groupChannelsByCategory(
    List<IptvChannel> items,
  ) {
    final grouped = <String, List<IptvChannel>>{};
    for (final item in items) {
      (grouped[item.categoryId] ??= <IptvChannel>[]).add(item);
    }
    return grouped;
  }

  Map<String, List<VodItem>> _groupMoviesByCategory(List<VodItem> items) {
    final grouped = <String, List<VodItem>>{};
    for (final item in items) {
      (grouped[item.categoryId] ??= <VodItem>[]).add(item);
    }
    return grouped;
  }

  Map<String, List<SeriesItem>> _groupSeriesByCategory(
    List<SeriesItem> items,
  ) {
    final grouped = <String, List<SeriesItem>>{};
    for (final item in items) {
      (grouped[item.categoryId] ??= <SeriesItem>[]).add(item);
    }
    return grouped;
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
    _catalogGeneration += 1;
    _epgGeneration += 1;
    liveCategories = const [];
    channels = const [];
    movieCategories = const [];
    movies = const [];
    seriesCategories = const [];
    series = const [];
    _channelsByCategory = const {};
    _moviesByCategory = const {};
    _seriesByCategory = const {};
    _recentMoviesCache = const [];
    _recentSeriesCache = const [];
    epg = const {};
    liveCategoryId = '__all__';
    movieCategoryId = '__all__';
    seriesCategoryId = '__all__';
    _moviesLoaded = false;
    _seriesLoaded = false;
    _fullSeriesLoaded = false;
    _loadedSeriesCategoryIds.clear();
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
