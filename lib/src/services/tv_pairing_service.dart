import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/iptv_account.dart';

class TvPairingRequest {
  const TvPairingRequest({
    required this.pairingId,
    required this.token,
    required this.code,
    required this.endpoint,
  });

  static const trustedEndpoint =
      'https://ehdvyarueeaetsvzdboo.supabase.co/functions/v1/device-pairing';

  final String pairingId;
  final String token;
  final String code;
  final Uri endpoint;

  factory TvPairingRequest.parse(String raw) {
    final uri = Uri.parse(raw.trim());
    if (uri.scheme != 'sbplayer' || uri.host != 'pair') {
      throw const FormatException('This is not an SB Player TV pairing code.');
    }

    final endpointValue = uri.queryParameters['endpoint'];
    final pairingId = uri.queryParameters['id'];
    final token = uri.queryParameters['token'];
    final code = uri.queryParameters['code'] ?? '';

    if (endpointValue == null || pairingId == null || token == null) {
      throw const FormatException('The TV pairing code is incomplete.');
    }

    final endpoint = Uri.parse(endpointValue);
    if (endpoint.toString() != trustedEndpoint) {
      throw const FormatException('This pairing code is not from SB Player.');
    }

    return TvPairingRequest(
      pairingId: pairingId,
      token: token,
      code: code,
      endpoint: endpoint,
    );
  }

  TvRemoteSession toRemoteSession() => TvRemoteSession(
        pairingId: pairingId,
        token: token,
        code: code,
        endpoint: endpoint,
      );
}

class TvRemoteSession {
  const TvRemoteSession({
    required this.pairingId,
    required this.token,
    required this.code,
    required this.endpoint,
  });

  final String pairingId;
  final String token;
  final String code;
  final Uri endpoint;

  Map<String, dynamic> toJson() => {
        'pairingId': pairingId,
        'token': token,
        'code': code,
        'endpoint': endpoint.toString(),
      };

  factory TvRemoteSession.fromJson(Map<String, dynamic> json) {
    final endpoint = Uri.parse('${json['endpoint'] ?? ''}');
    if (endpoint.toString() != TvPairingRequest.trustedEndpoint) {
      throw const FormatException('Stored TV remote endpoint is invalid.');
    }
    final pairingId = '${json['pairingId'] ?? ''}'.trim();
    final token = '${json['token'] ?? ''}'.trim();
    if (pairingId.isEmpty || token.isEmpty) {
      throw const FormatException('Stored TV remote is incomplete.');
    }
    return TvRemoteSession(
      pairingId: pairingId,
      token: token,
      code: '${json['code'] ?? ''}',
      endpoint: endpoint,
    );
  }
}

class TvRemoteCommand {
  const TvRemoteCommand._(this.value);

  final String value;

  static const up = TvRemoteCommand._('up');
  static const down = TvRemoteCommand._('down');
  static const left = TvRemoteCommand._('left');
  static const right = TvRemoteCommand._('right');
  static const select = TvRemoteCommand._('select');
  static const back = TvRemoteCommand._('back');
  static const home = TvRemoteCommand._('home');
  static const playPause = TvRemoteCommand._('play_pause');
  static const refresh = TvRemoteCommand._('refresh');
}

class TvPairingService {
  TvPairingService({http.Client? client}) : _client = client ?? http.Client();

  static const _remoteStorageKey = 'sb_player.tv_remote.v1';

  final http.Client _client;
  final AesGcm _cipher = AesGcm.with256bits();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<TvRemoteSession> approve({
    required TvPairingRequest request,
    required IptvAccount account,
  }) async {
    if (account.type != AccountType.xtream) {
      throw Exception('Only Xtream accounts can be linked to the TV app right now.');
    }

    final server = account.serverUrl?.trim();
    final username = account.username?.trim();
    final password = account.password;
    if (server == null ||
        server.isEmpty ||
        username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      throw Exception('The selected account is missing its login details.');
    }

    final keyBytes = base64Url.decode(base64Url.normalize(request.token));
    if (keyBytes.length != 32) {
      throw Exception('The TV pairing key is invalid.');
    }

    final payload = utf8.encode(jsonEncode({
      'type': 'xtream',
      'serverUrl': server,
      'username': username,
      'password': password,
      'label': account.label,
    }));

    final secretBox = await _cipher.encrypt(
      payload,
      secretKey: SecretKey(keyBytes),
    );

    final encrypted = <int>[
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];

    final response = await _client
        .post(
          request.endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'approve',
            'pairingId': request.pairingId,
            'token': request.token,
            'payloadType': 'xtream',
            'ciphertext': base64UrlEncode(encrypted).replaceAll('=', ''),
            'nonce': base64UrlEncode(secretBox.nonce).replaceAll('=', ''),
          }),
        )
        .timeout(const Duration(seconds: 12));

    final decoded = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'The TV could not be linked.');
    }
    if (decoded['ok'] != true) {
      throw Exception(decoded['error'] ?? 'The TV could not be linked.');
    }

    final session = request.toRemoteSession();
    await saveRemoteSession(session);
    return session;
  }

  Future<void> sendRemoteCommand(
    TvRemoteSession session,
    TvRemoteCommand command,
  ) async {
    final response = await _client
        .post(
          session.endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'remote_command',
            'pairingId': session.pairingId,
            'token': session.token,
            'command': command.value,
          }),
        )
        .timeout(const Duration(seconds: 6));

    final decoded = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'The TV did not accept the remote command.');
    }
    if (decoded['ok'] != true) {
      throw Exception(decoded['error'] ?? 'The TV did not accept the remote command.');
    }
  }

  Future<void> saveRemoteSession(TvRemoteSession session) =>
      _storage.write(
        key: _remoteStorageKey,
        value: jsonEncode(session.toJson()),
      );

  Future<TvRemoteSession?> loadRemoteSession() async {
    try {
      final raw = await _storage.read(key: _remoteStorageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return TvRemoteSession.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      await forgetRemoteSession();
      return null;
    }
  }

  Future<void> forgetRemoteSession() =>
      _storage.delete(key: _remoteStorageKey);

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {
      // Fall through to a useful generic error.
    }
    return const <String, dynamic>{};
  }

  void dispose() => _client.close();
}
