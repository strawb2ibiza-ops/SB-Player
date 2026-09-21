class EpgProgram {
  const EpgProgram({
    required this.channelId,
    required this.title,
    required this.start,
    required this.stop,
    this.description,
  });

  final String channelId;
  final String title;
  final DateTime start;
  final DateTime stop;
  final String? description;

  bool isLiveAt(DateTime time) =>
      !time.isBefore(start) && time.isBefore(stop);

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'title': title,
        'start': start.toIso8601String(),
        'stop': stop.toIso8601String(),
        'description': description,
      };

  factory EpgProgram.fromJson(Map<String, dynamic> json) {
    return EpgProgram(
      channelId: '${json['channelId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      start: DateTime.parse('${json['start']}'),
      stop: DateTime.parse('${json['stop']}'),
      description: _nullable(json['description']),
    );
  }

  static String? _nullable(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }
}
