import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/epg_program.dart';

class XmlTvService {
  XmlTvService({http.Client? client}) : _client = client ?? http.Client();

  static final RegExp _offsetPattern = RegExp(r'([+-])(\d{2})(\d{2})');

  final http.Client _client;

  Future<Map<String, List<EpgProgram>>> load(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw const FormatException('Enter a valid HTTP or HTTPS EPG URL.');
    }
    late http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw Exception('Could not load the TV guide.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('EPG returned HTTP ${response.statusCode}.');
    }

    late XmlDocument document;
    try {
      document = XmlDocument.parse(response.body);
    } on XmlParserException {
      throw const FormatException('The TV guide returned invalid XML.');
    }
    final output = <String, List<EpgProgram>>{};

    for (final node in document.findAllElements('programme')) {
      final channel = node.getAttribute('channel');
      final start = _parseXmlTvDate(node.getAttribute('start'));
      final stop = _parseXmlTvDate(node.getAttribute('stop'));
      if (channel == null || start == null || stop == null) continue;

      final title = node.findElements('title').firstOrNull?.innerText.trim();
      if (title == null || title.isEmpty) continue;
      final description = node.findElements('desc').firstOrNull?.innerText.trim();

      output.putIfAbsent(channel, () => []).add(
            EpgProgram(
              channelId: channel,
              title: title,
              start: start,
              stop: stop,
              description: description?.isEmpty == true ? null : description,
            ),
          );
    }

    for (final entries in output.values) {
      entries.sort((a, b) => a.start.compareTo(b.start));
    }
    return output;
  }

  DateTime? _parseXmlTvDate(String? raw) {
    if (raw == null || raw.length < 14) return null;
    final datePart = raw.substring(0, 14);
    final year = int.tryParse(datePart.substring(0, 4));
    final month = int.tryParse(datePart.substring(4, 6));
    final day = int.tryParse(datePart.substring(6, 8));
    final hour = int.tryParse(datePart.substring(8, 10));
    final minute = int.tryParse(datePart.substring(10, 12));
    final second = int.tryParse(datePart.substring(12, 14));
    if ([year, month, day, hour, minute, second].contains(null)) return null;

    final suffix = raw.substring(14);
    final offsetMatch = _offsetPattern.firstMatch(suffix);
    if (offsetMatch == null) {
      return DateTime(year!, month!, day!, hour!, minute!, second!);
    }

    final utc = DateTime.utc(year!, month!, day!, hour!, minute!, second!);
    final minutes =
        int.parse(offsetMatch.group(2)!) * 60 + int.parse(offsetMatch.group(3)!);
    final signed = offsetMatch.group(1) == '+' ? minutes : -minutes;
    return utc.subtract(Duration(minutes: signed)).toLocal();
  }

  void dispose() => _client.close();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
