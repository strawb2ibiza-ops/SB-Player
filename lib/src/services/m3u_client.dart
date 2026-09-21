import 'package:http/http.dart' as http;

import 'm3u_parser.dart';

class M3uClient {
  M3uClient({http.Client? client, M3uParser? parser})
      : _client = client ?? http.Client(),
        _parser = parser ?? const M3uParser();

  final http.Client _client;
  final M3uParser _parser;

  Future<M3uPlaylist> load(String playlistUrl) async {
    final uri = Uri.tryParse(playlistUrl.trim());
    if (uri == null || !uri.hasScheme || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('Enter a valid HTTP or HTTPS M3U URL.');
    }

    final response = await _client.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Playlist returned HTTP ${response.statusCode}.');
    }
    return _parser.parse(response.body);
  }

  void dispose() => _client.close();
}
