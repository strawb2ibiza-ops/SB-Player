import 'dart:convert';

enum AccountType { xtream, m3u }

class IptvAccount {
  const IptvAccount({
    required this.type,
    required this.label,
    this.serverUrl,
    this.username,
    this.password,
    this.playlistUrl,
    this.epgUrl,
    this.expiresAt,
  });

  final AccountType type;
  final String label;
  final String? serverUrl;
  final String? username;
  final String? password;
  final String? playlistUrl;
  final String? epgUrl;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'label': label,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'playlistUrl': playlistUrl,
        'epgUrl': epgUrl,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory IptvAccount.fromJson(Map<String, dynamic> json) {
    return IptvAccount(
      type: AccountType.values.byName(json['type'] as String),
      label: json['label'] as String? ?? 'IPTV',
      serverUrl: json['serverUrl'] as String?,
      username: json['username'] as String?,
      password: json['password'] as String?,
      playlistUrl: json['playlistUrl'] as String?,
      epgUrl: json['epgUrl'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt'] as String),
    );
  }

  String encode() => jsonEncode(toJson());

  static IptvAccount decode(String value) =>
      IptvAccount.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
