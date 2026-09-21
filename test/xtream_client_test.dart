import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sb_player/src/models/iptv_account.dart';
import 'package:sb_player/src/services/xtream_client.dart';

void main() {
  test('encodes credentials used in fallback live stream paths', () async {
    final client = XtreamClient(
      client: MockClient((request) async {
        expect(request.url.queryParameters['action'], 'get_live_streams');
        return http.Response(
          jsonEncode([
            {
              'stream_id': 42,
              'name': 'Test Channel',
              'category_id': '1',
              'direct_source': '',
            },
          ]),
          200,
        );
      }),
    );

    const account = IptvAccount(
      type: AccountType.xtream,
      label: 'Test',
      serverUrl: 'https://example.test',
      username: 'user/name',
      password: 'p@ss/word',
    );

    final channels = await client.fetchLiveChannels(account);

    expect(channels, hasLength(1));
    expect(
      channels.single.streamUrl,
      'https://example.test/live/user%2Fname/p%40ss%2Fword/42.ts',
    );
    client.dispose();
  });

  test('rejects malformed provider URLs before making a request', () async {
    final client = XtreamClient(
      client: MockClient((request) async {
        fail('HTTP should not be called for an invalid server URL.');
      }),
    );

    await expectLater(
      client.authenticate(
        serverUrl: 'https://',
        username: 'user',
        password: 'pass',
      ),
      throwsA(isA<XtreamException>()),
    );
    client.dispose();
  });

  test('falls back from HTTPS to HTTP and saves resolved provider URL', () async {
    final requests = <Uri>[];
    final client = XtreamClient(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.scheme == 'https') {
          return http.Response('not available', 502);
        }
        return http.Response(
          jsonEncode({
            'user_info': {
              'auth': 1,
              'status': 'Active',
              'exp_date': '0',
            },
            'server_info': {
              'server_protocol': 'http',
              'url': 'provider.example.test',
              'port': '8080',
            },
          }),
          200,
        );
      }),
    );

    final account = await client.authenticate(
      serverUrl: 'provider.example.test',
      username: 'viewer',
      password: 'secret',
    );

    expect(requests.first.scheme, 'https');
    expect(requests.last.scheme, 'http');
    expect(account.serverUrl, 'http://provider.example.test:8080');
    expect(account.epgUrl, startsWith('http://provider.example.test:8080/xmltv.php?'));
    client.dispose();
  });

  test('ignores malformed direct stream sources', () async {
    final client = XtreamClient(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'stream_id': 7,
              'name': 'Fallback Channel',
              'category_id': '1',
              'direct_source': 'http-not-a-url',
            },
          ]),
          200,
        );
      }),
    );

    const account = IptvAccount(
      type: AccountType.xtream,
      label: 'Test',
      serverUrl: 'https://example.test',
      username: 'user',
      password: 'pass',
    );

    final channels = await client.fetchLiveChannels(account);

    expect(
      channels.single.streamUrl,
      'https://example.test/live/user/pass/7.ts',
    );
    client.dispose();
  });
}
