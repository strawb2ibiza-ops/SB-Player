import 'dart:convert';

import 'package:cryptography/cryptography.dart';
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
}

class TvPairingService {
  TvPairingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<void> approve({
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
  }

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
