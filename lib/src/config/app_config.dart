enum DistributionMode { open, sbLocked }

class AppConfig {
  static const sbProviderBaseUrl = 'http://line.watchsbtv.top';

  const AppConfig({
    required this.mode,
    required this.providerBaseUrl,
    required this.appName,
  });

  final DistributionMode mode;
  final String providerBaseUrl;
  final String appName;

  bool get isLocked => mode == DistributionMode.sbLocked;

  factory AppConfig.fromEnvironment() {
    const locked = bool.fromEnvironment('SB_LOCKED', defaultValue: false);
    const provider = String.fromEnvironment(
      'SB_PROVIDER_BASE_URL',
      defaultValue: sbProviderBaseUrl,
    );

    return AppConfig(
      mode: locked ? DistributionMode.sbLocked : DistributionMode.open,
      providerBaseUrl: _normalizeBaseUrl(provider),
      appName: locked ? 'SB Player' : 'SB Player',
    );
  }

  static String _normalizeBaseUrl(String input) {
    var value = input.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
