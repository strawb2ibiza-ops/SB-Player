import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../models/iptv_account.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../models/series_item.dart';
import '../models/vod_item.dart';

class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

class XtreamClient {
  XtreamClient({http.Client? client}) : _client = client ?? http.Client();

  static final RegExp _httpSchemePattern =
      RegExp(r'^https?://', caseSensitive: false);
  static final RegExp _extensionPattern = RegExp(r'^[a-z0-9]{1,8}$');
  final http.Client _client;
  final Map<String, Future<dynamic>> _inFlight = <String, Future<dynamic>>{};
  final Map<String, _XtreamCacheEntry> _cache = <String, _XtreamCacheEntry>{};
  static const Duration _catalogCacheTtl = Duration(minutes: 5);

  String normalizeBase(String value) {
    var result = value.trim();
    if (result.isEmpty) {
      throw XtreamException('Enter the IPTV server URL.');
    }
    final lower = result.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      result = 'https://$result';
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }

    final uri = Uri.tryParse(result);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw XtreamException('Enter a valid HTTP or HTTPS IPTV server URL.');
    }
    return result;
  }

  Future<IptvAccount> authenticate({
    required String serverUrl,
    required String username,
    required String password,
    String label = 'IPTV',
  }) async {
    final input = serverUrl.trim();
    if (input.isEmpty) {
      throw XtreamException('Enter the IPTV server URL.');
    }

    final explicitScheme = _httpSchemePattern.hasMatch(input);
    final candidates = <String>[];

    void addCandidate(String value) {
      final normalized = normalizeBase(value);
      if (!candidates.contains(normalized)) candidates.add(normalized);
    }

    if (explicitScheme) {
      addCandidate(input);
      final parsed = Uri.tryParse(input);
      if (parsed != null && parsed.scheme.toLowerCase() == 'https') {
        addCandidate(parsed.replace(scheme: 'http').toString());
      }
    } else {
      addCandidate('https://$input');
      addCandidate('http://$input');
    }

    XtreamException? lastFailure;
    for (final server in candidates) {
      try {
        return await _authenticateAt(
          server: server,
          username: username,
          password: password,
          label: label,
        );
      } on XtreamException catch (failure) {
        lastFailure = failure;
      }
    }

    throw lastFailure ??
        XtreamException('Could not connect to the IPTV provider.');
  }

  Future<IptvAccount> _authenticateAt({
    required String server,
    required String username,
    required String password,
    required String label,
  }) async {
    final uri = Uri.parse('$server/player_api.php').replace(
      queryParameters: {'username': username, 'password': password},
    );

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw XtreamException('Could not connect to the IPTV provider.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw XtreamException('Provider returned HTTP ${response.statusCode}.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw XtreamException('Provider returned invalid account data.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw XtreamException('Provider returned an unexpected response.');
    }

    final userInfo = decoded['user_info'];
    if (userInfo is! Map<String, dynamic>) {
      throw XtreamException('This server did not return Xtream account data.');
    }

    final authenticated = '${userInfo['auth']}' == '1';
    final status = '${userInfo['status'] ?? ''}'.toLowerCase();
    if (!authenticated || (status.isNotEmpty && status != 'active')) {
      throw XtreamException('The IPTV username or password was rejected.');
    }

    DateTime? expiry;
    final rawExpiry = int.tryParse('${userInfo['exp_date'] ?? ''}');
    if (rawExpiry != null && rawExpiry > 0) {
      expiry = DateTime.fromMillisecondsSinceEpoch(rawExpiry * 1000);
    }

    var resolvedServer = server;
    final inputHost = Uri.tryParse(server)?.host.toLowerCase();
    const brandedProviderHosts = <String>{
      'line.watchsbtv.top',
      'line.8kultradnscloud.ru', // Legacy SB endpoint for seamless upgrades.
    };
    final preserveInputEndpoint = brandedProviderHosts.contains(inputHost);
    final serverInfo = decoded['server_info'];
    if (serverInfo is Map && !preserveInputEndpoint) {
      final serverProtocol =
          _nullableString(serverInfo['server_protocol'])?.toLowerCase();
      final serverUrl = _nullableString(serverInfo['url']);
      final port = serverProtocol == 'https'
          ? _nullableString(serverInfo['https_port']) ??
              _nullableString(serverInfo['port'])
          : _nullableString(serverInfo['port']);
      if (serverUrl != null &&
          (serverProtocol == 'http' || serverProtocol == 'https')) {
        final host = Uri.tryParse(
          serverUrl.contains('://') ? serverUrl : '$serverProtocol://$serverUrl',
        )?.host;
        if (host?.isNotEmpty == true) {
          final parsedPort = int.tryParse(port ?? '');
          resolvedServer = Uri(
            scheme: serverProtocol,
            host: host,
            port: parsedPort != null &&
                    !((serverProtocol == 'https' && parsedPort == 443) ||
                        (serverProtocol == 'http' && parsedPort == 80))
                ? parsedPort
                : null,
          ).toString();
          resolvedServer = normalizeBase(resolvedServer);
        }
      }
    }

    final epgUri = Uri.parse('$resolvedServer/xmltv.php').replace(
      queryParameters: {'username': username, 'password': password},
    );

    return IptvAccount(
      type: AccountType.xtream,
      label: label,
      serverUrl: resolvedServer,
      username: username,
      password: password,
      epgUrl: epgUri.toString(),
      expiresAt: expiry,
    );
  }

  Future<List<IptvCategory>> fetchLiveCategories(IptvAccount account) =>
      _fetchCategories(account, 'get_live_categories');

  Future<List<IptvCategory>> fetchVodCategories(IptvAccount account) =>
      _fetchCategories(account, 'get_vod_categories');

  Future<List<IptvCategory>> fetchSeriesCategories(IptvAccount account) =>
      _fetchCategories(account, 'get_series_categories');

  Future<List<IptvCategory>> _fetchCategories(
    IptvAccount account,
    String action,
  ) async {
    final data = await _getAction(account, action, cache: true);
    final rows = _asList(data, const ['categories', 'data']);
    if (rows.isEmpty) return const [];

    return rows.whereType<Map>().map((item) {
      return IptvCategory(
        id: '${item['category_id'] ?? ''}',
        name: '${item['category_name'] ?? 'Other'}',
      );
    }).where((category) => category.id.isNotEmpty).toList(growable: false);
  }

  Future<List<IptvChannel>> fetchLiveChannels(IptvAccount account) async {
    final data = await _getAction(account, 'get_live_streams', cache: true);
    final rows = _asList(data, const ['streams', 'live_streams', 'data']);
    if (rows.isEmpty) return const [];

    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;

    return rows.whereType<Map>().map((item) {
      final streamId = '${item['stream_id'] ?? ''}';
      final direct = '${item['direct_source'] ?? ''}'.trim();
      final fallback = '$server/live/${_segment(username)}/${_segment(password)}/${_segment(streamId)}.ts';

      return IptvChannel(
        id: streamId,
        name: '${item['name'] ?? 'Unnamed channel'}',
        categoryId: '${item['category_id'] ?? ''}',
        logoUrl: _imageSource(
          account,
          item['stream_icon'] ?? item['logo'] ?? item['icon'],
        ),
        epgId: _nullableString(item['epg_channel_id']),
        streamUrl: _httpSource(direct) ?? fallback,
      );
    }).where((channel) => channel.id.isNotEmpty).toList(growable: false);
  }

  Future<List<VodItem>> fetchVodStreams(IptvAccount account) async {
    final data = await _getAction(account, 'get_vod_streams', cache: true);
    final rows = _asList(data, const ['streams', 'vod_streams', 'movies', 'data']);
    if (rows.isEmpty) return const [];

    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;

    return rows.whereType<Map>().map((item) {
      final streamId = '${item['stream_id'] ?? item['id'] ?? ''}';
      final extension = _safeExtension(item['container_extension'], 'mp4');
      final direct = '${item['direct_source'] ?? ''}'.trim();
      final fallback = '$server/movie/${_segment(username)}/${_segment(password)}/${_segment(streamId)}.$extension';

      return VodItem(
        id: streamId,
        name: '${item['name'] ?? 'Untitled'}',
        categoryId: '${item['category_id'] ?? ''}',
        posterUrl: _imageSource(
          account,
          item['stream_icon'] ??
              item['movie_image'] ??
              item['cover_big'] ??
              item['cover'] ??
              item['backdrop_path'],
        ),
        extension: extension,
        plot: _nullableString(item['plot']),
        rating: _rating(item['rating_5based'] ?? item['rating']),
        releaseDate: _nullableString(item['releasedate'] ?? item['release_date']),
        duration: _nullableString(item['duration']),
        streamUrl: _httpSource(direct) ?? fallback,
      );
    }).where((item) => item.id.isNotEmpty).toList(growable: false);
  }

  Future<List<SeriesItem>> fetchSeries(IptvAccount account) async {
    var data = await _getAction(account, 'get_series', cache: true);
    var rawItems = _asList(
      data,
      const ['series', 'shows', 'streams', 'data', 'results', 'items'],
    );

    // A few Xtream-compatible panels expose the same catalogue under this
    // alias. Only use it when the standard action returned no usable rows.
    if (rawItems.isEmpty) {
      try {
        data = await _getAction(account, 'get_series_streams', cache: true);
        rawItems = _asList(
          data,
          const ['series', 'shows', 'streams', 'data', 'results', 'items'],
        );
      } catch (_) {
        // Keep the standard empty result if the compatibility action is absent.
      }
    }

    return rawItems.whereType<Map>().map((item) {
      return SeriesItem(
        id: '${item['series_id'] ?? item['stream_id'] ?? item['id'] ?? ''}',
        name: '${item['name'] ?? item['title'] ?? 'Untitled series'}',
        categoryId: '${item['category_id'] ?? item['category'] ?? ''}',
        coverUrl: _imageSource(
          account,
          item['cover'] ??
              item['cover_big'] ??
              item['movie_image'] ??
              item['stream_icon'] ??
              item['backdrop_path'],
        ),
        plot: _nullableString(item['plot'] ?? item['description']),
        rating: _rating(item['rating_5based'] ?? item['rating']),
        releaseDate: _nullableString(
          item['releaseDate'] ?? item['release_date'] ?? item['releasedate'],
        ),
      );
    }).where((item) => item.id.isNotEmpty).toList(growable: false);
  }

  Future<SeriesDetails> fetchSeriesDetails(
    IptvAccount account,
    SeriesItem series,
  ) async {
    final data = await _getAction(
      account,
      'get_series_info',
      extra: {'series_id': series.id},
    );
    if (data is! Map) {
      throw XtreamException('Provider returned invalid series information.');
    }

    final episodes = <int, List<SeriesEpisode>>{};
    _collectSeriesEpisodes(
      account,
      data,
      episodes,
      fallbackSeason: 0,
    );

    for (final list in episodes.values) {
      final seen = <String>{};
      list.removeWhere((episode) => !seen.add(episode.id));
      list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }

    return SeriesDetails(series: series, seasons: episodes);
  }

  void _collectSeriesEpisodes(
    IptvAccount account,
    dynamic node,
    Map<int, List<SeriesEpisode>> output, {
    required int fallbackSeason,
    int depth = 0,
  }) {
    if (node == null || depth > 8) return;

    if (node is List) {
      for (final value in node) {
        if (value is Map && _looksLikeEpisode(value)) {
          final episode =
              _episodeFromMap(account, value, fallbackSeason: fallbackSeason);
          if (episode != null) {
            output.putIfAbsent(episode.season, () => []).add(episode);
          }
        } else {
          _collectSeriesEpisodes(
            account,
            value,
            output,
            fallbackSeason: fallbackSeason,
            depth: depth + 1,
          );
        }
      }
      return;
    }

    if (node is! Map) return;

    if (_looksLikeEpisode(node)) {
      final episode =
          _episodeFromMap(account, node, fallbackSeason: fallbackSeason);
      if (episode != null) {
        output.putIfAbsent(episode.season, () => []).add(episode);
      }
      return;
    }

    final localSeason = int.tryParse(
          '${node['season'] ?? node['season_number'] ?? fallbackSeason}',
        ) ??
        fallbackSeason;

    for (final key in const ['episodes', 'episode']) {
      if (!node.containsKey(key) || node[key] == null) continue;
      _collectSeriesEpisodes(
        account,
        node[key],
        output,
        fallbackSeason: localSeason,
        depth: depth + 1,
      );
      return;
    }

    var foundNumericSeason = false;
    for (final entry in node.entries) {
      final seasonNumber = int.tryParse('${entry.key}');
      if (seasonNumber == null) continue;
      foundNumericSeason = true;
      _collectSeriesEpisodes(
        account,
        entry.value,
        output,
        fallbackSeason: seasonNumber,
        depth: depth + 1,
      );
    }
    if (foundNumericSeason) return;

    for (final key in const ['data', 'results', 'items']) {
      if (!node.containsKey(key) || node[key] == null) continue;
      _collectSeriesEpisodes(
        account,
        node[key],
        output,
        fallbackSeason: localSeason,
        depth: depth + 1,
      );
      return;
    }
  }

  bool _looksLikeEpisode(Map raw) {
    final hasId = raw['id'] != null ||
        raw['stream_id'] != null ||
        raw['episode_id'] != null;
    if (!hasId) return false;
    return raw.containsKey('episode_num') ||
        raw.containsKey('episode_number') ||
        raw.containsKey('episode') ||
        raw.containsKey('season') ||
        raw.containsKey('container_extension') ||
        raw.containsKey('extension') ||
        raw.containsKey('title');
  }

  SeriesEpisode? _episodeFromMap(
    IptvAccount account,
    Map raw, {
    required int fallbackSeason,
  }) {
    final info =
        raw['info'] is Map ? raw['info'] as Map : const <dynamic, dynamic>{};
    final id =
        '${raw['id'] ?? raw['stream_id'] ?? raw['episode_id'] ?? info['id'] ?? info['stream_id'] ?? ''}';
    if (id.isEmpty) return null;

    final extension = _safeExtension(
      raw['container_extension'] ??
          raw['extension'] ??
          info['container_extension'] ??
          info['extension'],
      'mp4',
    );
    final season = int.tryParse(
          '${raw['season'] ?? raw['season_number'] ?? info['season'] ?? fallbackSeason}',
        ) ??
        fallbackSeason;
    final episodeNumber = int.tryParse(
          '${raw['episode_num'] ?? raw['episode_number'] ?? raw['episode'] ?? info['episode_num'] ?? info['episode_number'] ?? 0}',
        ) ??
        0;
    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;
    final direct =
        '${raw['direct_source'] ?? info['direct_source'] ?? ''}'.trim();
    final fallback = '$server/series/${_segment(username)}/${_segment(password)}/${_segment(id)}.$extension';

    final subtitles = _subtitleList(
      raw['subtitles'] ??
          raw['subtitle'] ??
          info['subtitles'] ??
          info['subtitle'] ??
          info['external_subtitles'],
    );

    return SeriesEpisode(
      id: id,
      title:
          '${raw['title'] ?? raw['name'] ?? info['title'] ?? info['name'] ?? 'Episode $episodeNumber'}',
      season: season,
      episodeNumber: episodeNumber,
      streamUrl: _httpSource(direct) ?? fallback,
      extension: extension,
      plot: _nullableString(info['plot'] ?? raw['plot']),
      duration: _nullableString(info['duration'] ?? raw['duration']),
      imageUrl: _imageSource(
        account,
        info['movie_image'] ??
            info['cover_big'] ??
            info['cover'] ??
            info['stream_icon'] ??
            raw['movie_image'] ??
            raw['cover_big'] ??
            raw['cover'] ??
            raw['stream_icon'],
      ),
      subtitles: subtitles,
    );
  }

  Future<dynamic> _getAction(
    IptvAccount account,
    String action, {
    Map<String, String> extra = const {},
    bool cache = false,
  }) async {
    if (account.type != AccountType.xtream ||
        account.serverUrl == null ||
        account.username == null ||
        account.password == null) {
      throw XtreamException('Incomplete Xtream account.');
    }

    final uri = Uri.parse('${account.serverUrl}/player_api.php').replace(
      queryParameters: {
        'username': account.username!,
        'password': account.password!,
        'action': action,
        ...extra,
      },
    );

    final key = uri.toString();
    if (cache) {
      final cached = _cache[key];
      if (cached != null && DateTime.now().difference(cached.createdAt) < _catalogCacheTtl) {
        return cached.value;
      }
      final pending = _inFlight[key];
      if (pending != null) return pending;
    }

    final request = _requestJson(uri);
    if (cache) _inFlight[key] = request;
    try {
      final value = await request;
      if (cache) _cache[key] = _XtreamCacheEntry(value, DateTime.now());
      return value;
    } finally {
      if (cache) _inFlight.remove(key);
    }
  }

  Future<dynamic> _requestJson(Uri uri) async {
    late http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/json,*/*',
          'User-Agent': 'SBPlayer/0.6.9',
          'Connection': 'keep-alive',
        },
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw XtreamException('Could not load data from the IPTV provider.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw XtreamException('Provider returned HTTP ${response.statusCode}.');
    }
    try {
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      return await Isolate.run(
        () => jsonDecode(body),
        debugName: 'sb-player-xtream-json',
      );
    } catch (_) {
      throw XtreamException('Provider returned invalid data.');
    }
  }

  List<SeriesSubtitle> _subtitleList(dynamic value) {
    if (value == null) return const [];
    final result = <SeriesSubtitle>[];

    void add(dynamic raw, {String? fallbackLanguage}) {
      if (raw is String) {
        final url = _httpSource(raw.trim());
        if (url != null) {
          result.add(SeriesSubtitle(
            url: url,
            language: fallbackLanguage,
            title: fallbackLanguage,
          ));
        }
        return;
      }
      if (raw is Map) {
        final candidate = _nullableString(
          raw['url'] ?? raw['file'] ?? raw['src'] ?? raw['path'],
        );
        final url = candidate == null ? null : _httpSource(candidate);
        if (url == null) return;
        result.add(SeriesSubtitle(
          url: url,
          language: _nullableString(raw['language'] ?? raw['lang']) ??
              fallbackLanguage,
          title: _nullableString(raw['title'] ?? raw['label'] ?? raw['name']),
        ));
      }
    }

    if (value is List) {
      for (final raw in value) {
        add(raw);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        if (entry.value is List) {
          for (final raw in entry.value as List) {
            add(raw, fallbackLanguage: '${entry.key}');
          }
        } else {
          add(entry.value, fallbackLanguage: '${entry.key}');
        }
      }
    } else {
      add(value);
    }

    final seen = <String>{};
    return result.where((item) => seen.add(item.url)).toList(growable: false);
  }

  List<dynamic> _asList(
    dynamic value,
    List<String> keys, {
    int depth = 0,
  }) {
    if (value is List) return value;
    if (value is! Map || depth > 8) return const <dynamic>[];

    for (final key in keys) {
      if (!value.containsKey(key)) continue;
      final nested = _asList(value[key], keys, depth: depth + 1);
      if (nested.isNotEmpty) return nested;
    }

    final values = value.values.toList(growable: false);
    if (values.isNotEmpty && values.every((entry) => entry is Map)) {
      return values;
    }

    // Some compatible panels group rows by category or numeric ID and mix
    // metadata alongside those groups. Flatten those nested containers.
    final flattened = <dynamic>[];
    for (final entry in values) {
      if (entry is List) {
        flattened.addAll(entry);
      } else if (entry is Map) {
        final nested = _asList(entry, keys, depth: depth + 1);
        if (nested.isNotEmpty) flattened.addAll(nested);
      }
    }
    return flattened;
  }

  String? _imageSource(IptvAccount account, dynamic value) {
    dynamic candidate = value;
    if (candidate is List) {
      candidate = candidate.cast<dynamic>().firstWhere(
            (entry) => _nullableString(entry) != null,
            orElse: () => null,
          );
    }
    var text = _nullableString(candidate);
    if (text == null) return null;
    text = text.replaceAll('&amp;', '&').trim();

    final base = Uri.tryParse(account.serverUrl ?? '');
    if (text.startsWith('//')) {
      final scheme = base?.scheme.isNotEmpty == true ? base!.scheme : 'https';
      text = '$scheme:$text';
    }

    final absolute = Uri.tryParse(text);
    if (absolute != null &&
        absolute.hasAuthority &&
        {'http', 'https'}.contains(absolute.scheme.toLowerCase())) {
      return absolute.toString();
    }

    if (base == null || !base.hasAuthority) return null;
    try {
      final origin = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
      );
      return origin.resolve(text).toString();
    } catch (_) {
      return null;
    }
  }

  String? _httpSource(String value) {
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return value;
  }

  String _segment(String value) => Uri.encodeComponent(value);

  String _safeExtension(dynamic value, String fallback) {
    final extension = _nullableString(value)?.toLowerCase();
    if (extension == null) return fallback;
    return _extensionPattern.hasMatch(extension) ? extension : fallback;
  }

  double? _rating(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}');
  }

  String? _nullableString(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  void dispose() {
    clearCache();
    _inFlight.clear();
    _client.close();
  }
}

class _XtreamCacheEntry {
  const _XtreamCacheEntry(this.value, this.createdAt);
  final dynamic value;
  final DateTime createdAt;
}
