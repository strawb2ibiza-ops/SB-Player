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
}
