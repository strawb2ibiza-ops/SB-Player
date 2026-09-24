import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'm3u_parser.dart';

class M3uClient {
  M3uClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<M3uPlaylist> load(String playlistUrl) async {
    final uri = Uri.tryParse(playlistUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw const FormatException('Enter a valid HTTP or HTTPS M3U URL.');
    }

    late http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/x-mpegURL,audio/x-mpegurl,text/plain,*/*',
          'User-Agent': 'SBPlayer/0.6.8',
          'Connection': 'keep-alive',
        },
      ).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw Exception('Could not load the M3U playlist.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Playlist returned HTTP ${response.statusCode}.');
    }
    final body = response.body;
    return Isolate.run(
      () => _parseM3uBody(body),
      debugName: 'sb-player-m3u-parse',
    );
  }

  void dispose() => _client.close();
}

M3uPlaylist _parseM3uBody(String body) => const M3uParser().parse(body);
