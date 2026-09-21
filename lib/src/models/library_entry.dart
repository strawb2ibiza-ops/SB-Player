import 'dart:convert';

import 'playback_item.dart';

class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.title,
    required this.streamUrl,
    required this.kind,
    required this.updatedAt,
    this.artworkUrl,
    this.subtitle,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
  });

  final String id;
  final String title;
  final String streamUrl;
  final PlaybackKind kind;
  final DateTime updatedAt;
  final String? artworkUrl;
  final String? subtitle;
  final int positionSeconds;
  final int durationSeconds;

  double get progress => durationSeconds <= 0 ? 0 : positionSeconds / durationSeconds;

  PlaybackItem toPlaybackItem() => PlaybackItem(
        id: id,
        title: title,
        streamUrl: streamUrl,
        kind: kind,
        subtitle: subtitle,
        artworkUrl: artworkUrl,
        startPosition: Duration(seconds: positionSeconds),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'streamUrl': streamUrl,
        'kind': kind.name,
        'updatedAt': updatedAt.toIso8601String(),
        'artworkUrl': artworkUrl,
        'subtitle': subtitle,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
      };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        streamUrl: '${json['streamUrl'] ?? ''}',
        kind: PlaybackKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => PlaybackKind.live,
        ),
        updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
        artworkUrl: _nullable(json['artworkUrl']),
        subtitle: _nullable(json['subtitle']),
        positionSeconds: int.tryParse('${json['positionSeconds'] ?? 0}') ?? 0,
        durationSeconds: int.tryParse('${json['durationSeconds'] ?? 0}') ?? 0,
      );

  String encode() => jsonEncode(toJson());

  static LibraryEntry decode(String value) =>
      LibraryEntry.fromJson(jsonDecode(value) as Map<String, dynamic>);

  static String? _nullable(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }
}
