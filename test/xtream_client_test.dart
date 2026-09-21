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
  test('retries HTTPS port 80 as HTTP during authentication', () async {
    var requests = 0;
    final client = XtreamClient(
      client: MockClient((request) async {
        requests += 1;
        if (request.url.scheme == 'https') {
          throw const http.ClientException('TLS failed');
        }
        expect(request.url.scheme, 'http');
        expect(request.url.port, 80);
        return http.Response(
          jsonEncode({
            'user_info': {
              'auth': 1,
              'status': 'Active',
              'exp_date': null,
            },
          }),
          200,
        );
      }),
    );

    final account = await client.authenticate(
      serverUrl: 'https://example.test:80',
      username: 'user',
      password: 'pass',
    );

    expect(requests, 2);
    expect(account.serverUrl, 'http://example.test:80');
    client.dispose();
  });

}
