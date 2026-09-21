import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/epg_program.dart';

class EpgCacheService {
  const EpgCacheService();

  static const _filePrefix = 'epg_cache_v1_';

  Future<Map<String, List<EpgProgram>>?> load(
    String sourceUrl, {
    Duration maxAge = const Duration(hours: 6),
  }) async {
    try {
      final file = await _cacheFile(sourceUrl);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      if (data['sourceUrl'] != sourceUrl) return null;

      final cachedAt = DateTime.tryParse('${data['cachedAt'] ?? ''}');
      if (cachedAt == null || DateTime.now().difference(cachedAt) > maxAge) {
        return null;
      }

      final rawChannels = data['channels'];
      if (rawChannels is! Map) return null;
      final output = <String, List<EpgProgram>>{};
      for (final entry in rawChannels.entries) {
        final value = entry.value;
        if (value is! List) continue;
        final programmes = <EpgProgram>[];
        for (final raw in value.whereType<Map>()) {
          try {
            final programme =
                EpgProgram.fromJson(Map<String, dynamic>.from(raw));
            if (programme.channelId.isNotEmpty && programme.title.isNotEmpty) {
              programmes.add(programme);
            }
          } catch (_) {
            // Ignore malformed cached entries while preserving the rest.
          }
        }
        if (programmes.isNotEmpty) {
          programmes.sort((a, b) => a.start.compareTo(b.start));
          output['${entry.key}'] = programmes;
        }
      }
      return output.isEmpty ? null : output;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String sourceUrl,
    Map<String, List<EpgProgram>> channels,
  ) async {
    try {
      final now = DateTime.now();
      final oldest = now.subtract(const Duration(hours: 6));
      final newest = now.add(const Duration(days: 7));
      final compact = <String, List<Map<String, dynamic>>>{};

      for (final entry in channels.entries) {
        final programmes = entry.value
            .where(
              (programme) =>
                  programme.stop.isAfter(oldest) &&
                  programme.start.isBefore(newest),
            )
            .map((programme) => programme.toJson())
            .toList(growable: false);
        if (programmes.isNotEmpty) compact[entry.key] = programmes;
      }

      final file = await _cacheFile(sourceUrl);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'sourceUrl': sourceUrl,
          'cachedAt': now.toIso8601String(),
          'channels': compact,
        }),
        flush: true,
      );
    } catch (_) {
      // Cache failures must never block guide loading or playback.
    }
  }

  Future<void> clear([String? sourceUrl]) async {
    try {
      if (sourceUrl != null) {
        final file = await _cacheFile(sourceUrl);
        if (await file.exists()) await file.delete();
        return;
      }

      final directory = await getApplicationSupportDirectory();
      if (!await directory.exists()) return;
      await for (final entity in directory.list()) {
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith(_filePrefix)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  Future<File> _cacheFile(String sourceUrl) async {
    final directory = await getApplicationSupportDirectory();
    final digest = sha256.convert(utf8.encode(sourceUrl)).toString();
    return File(
      '${directory.path}${Platform.pathSeparator}$_filePrefix$digest.json',
    );
  }
}
