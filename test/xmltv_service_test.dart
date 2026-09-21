import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sb_player/src/services/xmltv_service.dart';

void main() {
  test('timezone-less XMLTV timestamps are treated as local time', () async {
    final service = XmlTvService(
      client: MockClient((request) async {
        return http.Response(
          '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20260921193000" stop="20260921203000" channel="bbc1">
    <title>Local Programme</title>
  </programme>
</tv>''',
          200,
        );
      }),
    );

    final guide = await service.load('https://example.test/epg.xml');
    final programme = guide['bbc1']!.single;

    expect(programme.start.isUtc, isFalse);
    expect(programme.start.year, 2026);
    expect(programme.start.month, 9);
    expect(programme.start.day, 21);
    expect(programme.start.hour, 19);
    expect(programme.start.minute, 30);
    service.dispose();
  });

  test('XMLTV numeric offsets are converted to the local timezone', () async {
    final service = XmlTvService(
      client: MockClient((request) async {
        return http.Response(
          '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20260921193000 +0200" stop="20260921203000 +0200" channel="bbc1">
    <title>Offset Programme</title>
  </programme>
</tv>''',
          200,
        );
      }),
    );

    final guide = await service.load('https://example.test/epg.xml');
    final programme = guide['bbc1']!.single;

    expect(programme.start.toUtc(), DateTime.utc(2026, 9, 21, 17, 30));
    expect(programme.stop.toUtc(), DateTime.utc(2026, 9, 21, 18, 30));
    service.dispose();
  });
}
