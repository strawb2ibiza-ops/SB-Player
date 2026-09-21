import '../models/iptv_channel.dart';

class M3uPlaylist {
  const M3uPlaylist({required this.channels, this.epgUrl});
  final List<IptvChannel> channels;
  final String? epgUrl;
}

class M3uParser {
  const M3uParser();

  static final RegExp _attributePattern =
      RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

  M3uPlaylist parse(String body) {
    final lines = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final header = lines.firstWhere(
      (line) => line.trim().isNotEmpty,
      orElse: () => '',
    ).trim();
    if (!header.startsWith('#EXTM3U')) {
      throw const FormatException('Not a valid extended M3U playlist.');
    }

    final epgUrl = _extractHeaderAttribute(header, 'url-tvg') ??
        _extractHeaderAttribute(header, 'x-tvg-url');

    final channels = <IptvChannel>[];
    String? pendingInfo;
    var generatedId = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line == header) continue;
      if (line.startsWith('#EXTINF:')) {
        pendingInfo = line;
        continue;
      }
      if (line.startsWith('#')) continue;
      if (pendingInfo == null) continue;

      final info = pendingInfo;
      pendingInfo = null;
      final attributes = _parseAttributes(info);
      final comma = info.indexOf(',');
      final fallbackName = comma >= 0 ? info.substring(comma + 1).trim() : 'Channel';
      final name = attributes['tvg-name']?.trim().isNotEmpty == true
          ? attributes['tvg-name']!.trim()
          : fallbackName;
      final group = attributes['group-title']?.trim() ?? 'Other';
      final epgId = attributes['tvg-id']?.trim();

      generatedId += 1;
      channels.add(
        IptvChannel(
          id: 'm3u-$generatedId',
          name: name.isEmpty ? 'Channel $generatedId' : name,
          streamUrl: line,
          categoryId: group.isEmpty ? 'Other' : group,
          logoUrl: _emptyToNull(attributes['tvg-logo']),
          epgId: _emptyToNull(epgId),
        ),
      );
    }

    return M3uPlaylist(channels: channels, epgUrl: _emptyToNull(epgUrl));
  }

  Map<String, String> _parseAttributes(String line) {
    final result = <String, String>{};
    final expression = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');
    for (final match in expression.allMatches(line)) {
      result[match.group(1)!.toLowerCase()] = match.group(2)!;
    }
    return result;
  }

  String? _extractHeaderAttribute(String line, String key) {
    final expression = RegExp('$key="([^"]*)"', caseSensitive: false);
    return expression.firstMatch(line)?.group(1);
  }

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
