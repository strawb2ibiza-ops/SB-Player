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
    this.externalSubtitles = const [],
  });

  final String id;
  final String title;
  final String streamUrl;
  final PlaybackKind kind;
  final String? subtitle;
  final String? artworkUrl;
  final Duration startPosition;
  final PlaybackItem? next;
  final List<PlaybackSubtitle> externalSubtitles;

  bool get isLive => kind == PlaybackKind.live;
}


class PlaybackSubtitle {
  const PlaybackSubtitle({
    required this.url,
    this.title,
    this.language,
  });

  final String url;
  final String? title;
  final String? language;
}
