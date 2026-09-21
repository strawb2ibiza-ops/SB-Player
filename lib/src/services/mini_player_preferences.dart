import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum MiniPlayerLayout { detailed, videoOnly }

class MiniPlayerGeometry {
  const MiniPlayerGeometry({required this.size, required this.position});

  final Size size;
  final Offset position;

  Map<String, dynamic> toJson() => {
        'width': size.width,
        'height': size.height,
        'x': position.dx,
        'y': position.dy,
      };

  factory MiniPlayerGeometry.fromJson(Map<String, dynamic> json) {
    return MiniPlayerGeometry(
      size: Size(
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
      ),
      position: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
    );
  }
}

class MiniPlayerPreferences {
  const MiniPlayerPreferences();

  static const _layoutKey = 'sb_player.mini_player_layout.v1';
  static const _geometryPrefix = 'sb_player.mini_player_geometry.v1.';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<MiniPlayerLayout> readLayout() async {
    try {
      final value = await _storage.read(key: _layoutKey);
      return MiniPlayerLayout.values.firstWhere(
        (layout) => layout.name == value,
        orElse: () => MiniPlayerLayout.detailed,
      );
    } catch (_) {
      return MiniPlayerLayout.detailed;
    }
  }

  Future<void> saveLayout(MiniPlayerLayout layout) async {
    try {
      await _storage.write(key: _layoutKey, value: layout.name);
    } catch (_) {
      // Preferences are best-effort.
    }
  }

  Future<MiniPlayerGeometry?> readGeometry(MiniPlayerLayout layout) async {
    try {
      final value =
          await _storage.read(key: '$_geometryPrefix${layout.name}');
      if (value == null || value.isEmpty) return null;
      return MiniPlayerGeometry.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveGeometry(
    MiniPlayerLayout layout, {
    required Size size,
    required Offset position,
  }) async {
    try {
      await _storage.write(
        key: '$_geometryPrefix${layout.name}',
        value: jsonEncode(
          MiniPlayerGeometry(size: size, position: position).toJson(),
        ),
      );
    } catch (_) {
      // Preferences are best-effort.
    }
  }
}
