class SeriesItem {
  const SeriesItem({
    required this.id,
    required this.name,
    required this.categoryId,
    this.coverUrl,
    this.plot,
    this.rating,
    this.releaseDate,
  });

  final String id;
  final String name;
  final String categoryId;
  final String? coverUrl;
  final String? plot;
  final double? rating;
  final String? releaseDate;
}

class SeriesEpisode {
  const SeriesEpisode({
    required this.id,
    required this.title,
    required this.season,
    required this.episodeNumber,
    required this.streamUrl,
    this.extension,
    this.plot,
    this.duration,
    this.imageUrl,
    this.subtitles = const [],
  });

  final String id;
  final String title;
  final int season;
  final int episodeNumber;
  final String streamUrl;
  final String? extension;
  final String? plot;
  final String? duration;
  final String? imageUrl;
  final List<SeriesSubtitle> subtitles;
}

class SeriesDetails {
  const SeriesDetails({
    required this.series,
    required this.seasons,
  });

  final SeriesItem series;
  final Map<int, List<SeriesEpisode>> seasons;
}


class SeriesSubtitle {
  const SeriesSubtitle({
    required this.url,
    this.title,
    this.language,
  });

  final String url;
  final String? title;
  final String? language;
}
