import 'dart:convert';

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
  static final RegExp _extensionPattern = RegExp(r'^[a-z0-9]{1,8}

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
    final serverInfo = decoded['server_info'];
    if (serverInfo is Map) {
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
    final data = await _getAction(account, action);
    if (data is! List) return const [];

    return data.whereType<Map>().map((item) {
      return IptvCategory(
        id: '${item['category_id'] ?? ''}',
        name: '${item['category_name'] ?? 'Other'}',
      );
    }).where((category) => category.id.isNotEmpty).toList(growable: false);
  }

  Future<List<IptvChannel>> fetchLiveChannels(IptvAccount account) async {
    final data = await _getAction(account, 'get_live_streams');
    if (data is! List) return const [];

    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;

    return data.whereType<Map>().map((item) {
      final streamId = '${item['stream_id'] ?? ''}';
      final direct = '${item['direct_source'] ?? ''}'.trim();
      final fallback = '$server/live/${_segment(username)}/${_segment(password)}/${_segment(streamId)}.ts';

      return IptvChannel(
        id: streamId,
        name: '${item['name'] ?? 'Unnamed channel'}',
        categoryId: '${item['category_id'] ?? ''}',
        logoUrl: _nullableString(item['stream_icon']),
        epgId: _nullableString(item['epg_channel_id']),
        streamUrl: _httpSource(direct) ?? fallback,
      );
    }).where((channel) => channel.id.isNotEmpty).toList(growable: false);
  }

  Future<List<VodItem>> fetchVodStreams(IptvAccount account) async {
    final data = await _getAction(account, 'get_vod_streams');
    if (data is! List) return const [];

    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;

    return data.whereType<Map>().map((item) {
      final streamId = '${item['stream_id'] ?? ''}';
      final extension = _safeExtension(item['container_extension'], 'mp4');
      final direct = '${item['direct_source'] ?? ''}'.trim();
      final fallback = '$server/movie/${_segment(username)}/${_segment(password)}/${_segment(streamId)}.$extension';

      return VodItem(
        id: streamId,
        name: '${item['name'] ?? 'Untitled'}',
        categoryId: '${item['category_id'] ?? ''}',
        posterUrl: _nullableString(item['stream_icon']),
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
    final data = await _getAction(account, 'get_series');
    if (data is! List) return const [];

    return data.whereType<Map>().map((item) {
      return SeriesItem(
        id: '${item['series_id'] ?? ''}',
        name: '${item['name'] ?? 'Untitled series'}',
        categoryId: '${item['category_id'] ?? ''}',
        coverUrl: _nullableString(item['cover']),
        plot: _nullableString(item['plot']),
        rating: _rating(item['rating_5based'] ?? item['rating']),
        releaseDate: _nullableString(item['releaseDate'] ?? item['release_date']),
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
    final rawEpisodes = data['episodes'];

    if (rawEpisodes is Map) {
      for (final entry in rawEpisodes.entries) {
        final seasonNumber = int.tryParse('${entry.key}') ?? 0;
        final values = entry.value;
        if (values is List) {
          for (final raw in values.whereType<Map>()) {
            final episode = _episodeFromMap(account, raw, fallbackSeason: seasonNumber);
            if (episode != null) {
              episodes.putIfAbsent(episode.season, () => []).add(episode);
            }
          }
        }
      }
    } else if (rawEpisodes is List) {
      for (final raw in rawEpisodes.whereType<Map>()) {
        final episode = _episodeFromMap(account, raw, fallbackSeason: 0);
        if (episode != null) {
          episodes.putIfAbsent(episode.season, () => []).add(episode);
        }
      }
    }

    for (final list in episodes.values) {
      list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }

    return SeriesDetails(series: series, seasons: episodes);
  }

  SeriesEpisode? _episodeFromMap(
    IptvAccount account,
    Map raw, {
    required int fallbackSeason,
  }) {
    final id = '${raw['id'] ?? raw['stream_id'] ?? ''}';
    if (id.isEmpty) return null;

    final extension = _safeExtension(raw['container_extension'], 'mp4');
    final season = int.tryParse('${raw['season'] ?? fallbackSeason}') ?? fallbackSeason;
    final episodeNumber = int.tryParse('${raw['episode_num'] ?? raw['episode'] ?? 0}') ?? 0;
    final info = raw['info'] is Map ? raw['info'] as Map : const <dynamic, dynamic>{};
    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;
    final direct = '${raw['direct_source'] ?? ''}'.trim();
    final fallback = '$server/series/${_segment(username)}/${_segment(password)}/${_segment(id)}.$extension';

    return SeriesEpisode(
      id: id,
      title: '${raw['title'] ?? raw['name'] ?? 'Episode $episodeNumber'}',
      season: season,
      episodeNumber: episodeNumber,
      streamUrl: _httpSource(direct) ?? fallback,
      extension: extension,
      plot: _nullableString(info['plot'] ?? raw['plot']),
      duration: _nullableString(info['duration'] ?? raw['duration']),
      imageUrl: _nullableString(info['movie_image'] ?? info['cover_big'] ?? raw['cover']),
    );
  }

  Future<dynamic> _getAction(
    IptvAccount account,
    String action, {
    Map<String, String> extra = const {},
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

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw XtreamException('Could not load data from the IPTV provider.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw XtreamException('Provider returned HTTP ${response.statusCode}.');
    }
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw XtreamException('Provider returned invalid data.');
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

  void dispose() => _client.close();
});

  final http.Client _client;

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
    final serverInfo = decoded['server_info'];
    if (serverInfo is Map) {
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
    final data = await _getAction(account, action);
    if (data is! List) return const [];

    return data.whereType<Map>().map((item) {
      return IptvCategory(
        id: '${item['category_id'] ?? ''}',
        name: '${item['category_name'] ?? 'Other'}',
      );
    }).where((category) => category.id.isNotEmpty).toList(growable: false);
  }

  Future<List<IptvChannel>> fetchLiveChannels(IptvAccount account) async {
    final data = await _getAction(account, 'get_live_streams');
    if (data is! List) return const [];

    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;

    return data.whereType<Map>().map((item) {
      final streamId = '${item['stream_id'] ?? ''}';
      final direct = '${item['direct_source'] ?? ''}'.trim();
      final fallback = '$server/live/${_segment(username)}/${_segment(password)}/${_segment(streamId)}.ts';

      return IptvChannel(
        id: streamId,
        name: '${item['name'] ?? 'Unnamed channel'}',
        categoryId: '${item['category_id'] ?? ''}',
        logoUrl: _nullableString(item['stream_icon']),
        epgId: _nullableString(item['epg_channel_id']),
        streamUrl: _httpSource(direct) ?? fallback,
      );
    }).where((channel) => channel.id.isNotEmpty).toList(growable: false);
  }

  Future<List<VodItem>> fetchVodStreams(IptvAccount account) async {
    final data = await _getAction(account, 'get_vod_streams');
    if (data is! List) return const [];

    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;

    return data.whereType<Map>().map((item) {
      final streamId = '${item['stream_id'] ?? ''}';
      final extension = _safeExtension(item['container_extension'], 'mp4');
      final direct = '${item['direct_source'] ?? ''}'.trim();
      final fallback = '$server/movie/${_segment(username)}/${_segment(password)}/${_segment(streamId)}.$extension';

      return VodItem(
        id: streamId,
        name: '${item['name'] ?? 'Untitled'}',
        categoryId: '${item['category_id'] ?? ''}',
        posterUrl: _nullableString(item['stream_icon']),
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
    final data = await _getAction(account, 'get_series');
    if (data is! List) return const [];

    return data.whereType<Map>().map((item) {
      return SeriesItem(
        id: '${item['series_id'] ?? ''}',
        name: '${item['name'] ?? 'Untitled series'}',
        categoryId: '${item['category_id'] ?? ''}',
        coverUrl: _nullableString(item['cover']),
        plot: _nullableString(item['plot']),
        rating: _rating(item['rating_5based'] ?? item['rating']),
        releaseDate: _nullableString(item['releaseDate'] ?? item['release_date']),
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
    final rawEpisodes = data['episodes'];

    if (rawEpisodes is Map) {
      for (final entry in rawEpisodes.entries) {
        final seasonNumber = int.tryParse('${entry.key}') ?? 0;
        final values = entry.value;
        if (values is List) {
          for (final raw in values.whereType<Map>()) {
            final episode = _episodeFromMap(account, raw, fallbackSeason: seasonNumber);
            if (episode != null) {
              episodes.putIfAbsent(episode.season, () => []).add(episode);
            }
          }
        }
      }
    } else if (rawEpisodes is List) {
      for (final raw in rawEpisodes.whereType<Map>()) {
        final episode = _episodeFromMap(account, raw, fallbackSeason: 0);
        if (episode != null) {
          episodes.putIfAbsent(episode.season, () => []).add(episode);
        }
      }
    }

    for (final list in episodes.values) {
      list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }

    return SeriesDetails(series: series, seasons: episodes);
  }

  SeriesEpisode? _episodeFromMap(
    IptvAccount account,
    Map raw, {
    required int fallbackSeason,
  }) {
    final id = '${raw['id'] ?? raw['stream_id'] ?? ''}';
    if (id.isEmpty) return null;

    final extension = _safeExtension(raw['container_extension'], 'mp4');
    final season = int.tryParse('${raw['season'] ?? fallbackSeason}') ?? fallbackSeason;
    final episodeNumber = int.tryParse('${raw['episode_num'] ?? raw['episode'] ?? 0}') ?? 0;
    final info = raw['info'] is Map ? raw['info'] as Map : const <dynamic, dynamic>{};
    final server = account.serverUrl!;
    final username = account.username!;
    final password = account.password!;
    final direct = '${raw['direct_source'] ?? ''}'.trim();
    final fallback = '$server/series/${_segment(username)}/${_segment(password)}/${_segment(id)}.$extension';

    return SeriesEpisode(
      id: id,
      title: '${raw['title'] ?? raw['name'] ?? 'Episode $episodeNumber'}',
      season: season,
      episodeNumber: episodeNumber,
      streamUrl: _httpSource(direct) ?? fallback,
      extension: extension,
      plot: _nullableString(info['plot'] ?? raw['plot']),
      duration: _nullableString(info['duration'] ?? raw['duration']),
      imageUrl: _nullableString(info['movie_image'] ?? info['cover_big'] ?? raw['cover']),
    );
  }

  Future<dynamic> _getAction(
    IptvAccount account,
    String action, {
    Map<String, String> extra = const {},
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

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw XtreamException('Could not load data from the IPTV provider.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw XtreamException('Provider returned HTTP ${response.statusCode}.');
    }
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw XtreamException('Provider returned invalid data.');
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

  void dispose() => _client.close();
}