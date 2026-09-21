import 'package:flutter_test/flutter_test.dart';
import 'package:sb_player/src/models/epg_program.dart';

void main() {
  test('detects currently live programme', () {
    final programme = EpgProgram(
      channelId: 'bbc1',
      title: 'News',
      start: DateTime.utc(2026, 9, 21, 12),
      stop: DateTime.utc(2026, 9, 21, 13),
    );

    expect(programme.isLiveAt(DateTime.utc(2026, 9, 21, 12, 30)), isTrue);
    expect(programme.isLiveAt(DateTime.utc(2026, 9, 21, 13)), isFalse);
  });
}
