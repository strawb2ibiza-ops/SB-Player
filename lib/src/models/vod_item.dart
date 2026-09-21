class VodItem {
  const VodItem({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.categoryId,
    this.posterUrl,
    this.extension,
    this.plot,
    this.rating,
    this.releaseDate,
    this.duration,
    this.addedAt,
  });

  final String id;
  final String name;
  final String streamUrl;
  final String categoryId;
  final String? posterUrl;
  final String? extension;
  final String? plot;
  final double? rating;
  final String? releaseDate;
  final String? duration;
  final DateTime? addedAt;
}
