import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sb_player/src/models/iptv_account.dart';
import 'package:sb_player/src/models/series_item.dart';
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

  test('loads series from map keyed provider responses', () async {
    final client = XtreamClient(
      client: MockClient((request) async {
        expect(request.url.queryParameters['action'], 'get_series');
        return http.Response(
          jsonEncode({
            '100': {
              'series_id': 100,
              'name': 'Test Series',
              'category_id': '9',
              'cover': 'https://images.example.test/series.jpg',
            },
          }),
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

    final series = await client.fetchSeries(account);

    expect(series, hasLength(1));
    expect(series.single.id, '100');
    expect(series.single.name, 'Test Series');
    client.dispose();
  });

  test('prefers explicit episode names over generic provider titles',
      () async {
    final client = XtreamClient(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'episodes': {
              '1': [
                {
                  'id': 501,
                  'episode_num': 1,
                  'title': 'South Park (1997) - S01E01',
                  'episode_name': 'Cartman Gets an Anal Probe',
                  'container_extension': 'mp4',
                },
              ],
            },
          }),
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
    const series = SeriesItem(
      id: '100',
      name: 'South Park (1997)',
      categoryId: '9',
    );

    final details = await client.fetchSeriesDetails(account, series);

    expect(
      details.seasons[1]!.single.title,
      'Cartman Gets an Anal Probe',
    );
    client.dispose();
  });

  test('loads episodes from nested series data wrappers', () async {
    final client = XtreamClient(
      client: MockClient((request) async {
        expect(request.url.queryParameters['action'], 'get_series_info');
        expect(request.url.queryParameters['series_id'], '100');
        return http.Response(
          jsonEncode({
            'info': {'name': 'Test Series'},
            'data': {
              'episodes': {
                '1': [
                  {
                    'id': 501,
                    'episode_num': 1,
                    'title': 'Pilot',
                    'container_extension': 'mkv',
                    'info': {'duration': '45:00'},
                  },
                ],
              },
            },
          }),
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
    const series = SeriesItem(
      id: '100',
      name: 'Test Series',
      categoryId: '9',
    );

    final details = await client.fetchSeriesDetails(account, series);

    expect(details.seasons.keys, contains(1));
    expect(details.seasons[1], hasLength(1));
    expect(details.seasons[1]!.single.episodeNumber, 1);
    expect(
      details.seasons[1]!.single.streamUrl,
      'https://example.test/series/user/pass/501.mkv',
    );
    client.dispose();
  });

}
