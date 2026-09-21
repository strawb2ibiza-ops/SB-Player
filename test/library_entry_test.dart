import 'package:flutter_test/flutter_test.dart';
import 'package:sb_player/src/models/library_entry.dart';
import 'package:sb_player/src/models/playback_item.dart';

void main() {
  test('library entries round-trip and restore playback position', () {
    final original = LibraryEntry(
      id: 'movie:42',
      title: 'Example Movie',
      streamUrl: 'https://example.test/movie/42.mp4',
      kind: PlaybackKind.movie,
      updatedAt: DateTime.utc(2026, 9, 21),
      positionSeconds: 615,
      durationSeconds: 3600,
    );

    final decoded = LibraryEntry.decode(original.encode());
    expect(decoded.id, original.id);
    expect(decoded.kind, PlaybackKind.movie);
    expect(decoded.positionSeconds, 615);
    expect(decoded.toPlaybackItem().startPosition, const Duration(seconds: 615));
  });
}
