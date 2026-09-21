import 'iptv_account.dart';

class IptvProfile {
  const IptvProfile({
    required this.id,
    required this.name,
    required this.account,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final IptvAccount account;
  final DateTime updatedAt;

  IptvProfile copyWith({
    String? name,
    IptvAccount? account,
    DateTime? updatedAt,
  }) {
    return IptvProfile(
      id: id,
      name: name ?? this.name,
      account: account ?? this.account,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'account': account.toJson(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory IptvProfile.fromJson(Map<String, dynamic> json) {
    return IptvProfile(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'IPTV'}',
      account: IptvAccount.fromJson(
        Map<String, dynamic>.from(json['account'] as Map),
      ),
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
    );
  }

  String get subtitle {
    if (account.type == AccountType.xtream) {
      final host = Uri.tryParse(account.serverUrl ?? '')?.host;
      final server = host?.isNotEmpty == true ? host! : 'Xtream';
      final user = account.username?.trim();
      return user?.isNotEmpty == true ? '$server • $user' : server;
    }

    final host = Uri.tryParse(account.playlistUrl ?? '')?.host;
    return host?.isNotEmpty == true ? host! : 'M3U playlist';
  }
}
