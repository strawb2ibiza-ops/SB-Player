import 'package:flutter_test/flutter_test.dart';
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
}
