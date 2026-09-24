import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sb_player/src/services/m3u_client.dart';
import 'package:sb_player/src/services/m3u_parser.dart';

void main() {
  test('parses groups, logos, epg ids and url-tvg', () {
    const body = '''#EXTM3U url-tvg="https://example.test/epg.xml"
#EXTINF:-1 tvg-id="bbc1" tvg-name="BBC One" tvg-logo="https://example.test/bbc.png" group-title="UK",BBC One HD
https://example.test/live/1.m3u8
#EXTINF:-1 group-title="Sports",Sports One
https://example.test/live/2.ts
''';

    final result = const M3uParser().parse(body);
    expect(result.epgUrl, 'https://example.test/epg.xml');
    expect(result.channels, hasLength(2));
    expect(result.channels.first.name, 'BBC One');
    expect(result.channels.first.categoryId, 'UK');
    expect(result.channels.first.epgId, 'bbc1');
    expect(result.channels[1].categoryId, 'Sports');
  });

  test('keeps channel ids unique when tvg-id values repeat', () {
    const body = '''#EXTM3U
#EXTINF:-1 tvg-id="shared" group-title="One",Channel One
https://example.test/live/1.m3u8
#EXTINF:-1 tvg-id="shared" group-title="Two",Channel Two
https://example.test/live/2.m3u8
''';

    final result = const M3uParser().parse(body);

    expect(result.channels, hasLength(2));
    expect(result.channels[0].epgId, 'shared');
    expect(result.channels[1].epgId, 'shared');
    expect(result.channels[0].id, isNot(result.channels[1].id));
  });

  test('M3U client downloads and parses off the UI isolate', () async {
    final client = M3uClient(
      client: MockClient((request) async {
        expect(request.headers['User-Agent'], 'SBPlayer/0.6.8');
        return http.Response(
          '''#EXTM3U
#EXTINF:-1 tvg-id="one" group-title="UK",Channel One
https://example.test/live/1.m3u8
''',
          200,
        );
      }),
    );

    final result = await client.load('https://example.test/list.m3u');

    expect(result.channels, hasLength(1));
    expect(result.channels.single.name, 'Channel One');
    expect(result.channels.single.categoryId, 'UK');
    client.dispose();
  });

}
