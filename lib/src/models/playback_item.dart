enum PlaybackKind { live, movie, episode }

class PlaybackItem {
  const PlaybackItem({
    required this.id,
    required this.title,
    required this.streamUrl,
    required this.kind,
    this.subtitle,
    this.artworkUrl,
    this.startPosition = Duration.zero,
    this.next,
  });

  final String id;
  final String title;
  final String streamUrl;
  final PlaybackKind kind;
  final String? subtitle;
  final String? artworkUrl;
  final Duration startPosition;
  final PlaybackItem? next;

  bool get isLive => kind == PlaybackKind.live;
}
