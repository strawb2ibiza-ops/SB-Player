class IptvChannel {
  const IptvChannel({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.categoryId,
    this.logoUrl,
    this.epgId,
  });

  final String id;
  final String name;
  final String streamUrl;
  final String categoryId;
  final String? logoUrl;
  final String? epgId;
}
