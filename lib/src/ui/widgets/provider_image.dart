import 'package:flutter/material.dart';

/// Network image loader tuned for IPTV/provider artwork.
///
/// Provider catalogues often contain a mixture of http/https artwork URLs and
/// occasionally return a dead CDN URL before another usable candidate. This
/// widget tries each candidate plus the opposite HTTP scheme before falling
/// back to the supplied placeholder.
class ProviderImage extends StatelessWidget {
  const ProviderImage({
    super.key,
    this.url,
    this.urls = const <String>[],
    required this.fallback,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String? url;
  final List<String> urls;
  final Widget fallback;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates();
    if (candidates.isEmpty) return fallback;
    return _buildCandidate(candidates, 0);
  }

  Widget _buildCandidate(List<String> candidates, int index) {
    if (index >= candidates.length) return fallback;
    return Image.network(
      candidates[index],
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: true,
      headers: const <String, String>{
        'User-Agent': 'SBPlayer/0.6.9',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      },
      errorBuilder: (_, _, _) => _buildCandidate(candidates, index + 1),
    );
  }

  List<String> _candidates() {
    final result = <String>[];
    final seen = <String>{};

    void add(String? raw) {
      final value = raw?.trim().replaceAll('&amp;', '&') ?? '';
      if (value.isEmpty || !seen.add(value)) return;
      result.add(value);

      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasAuthority) return;
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return;
      final alternate =
          uri.replace(scheme: scheme == 'https' ? 'http' : 'https').toString();
      if (seen.add(alternate)) result.add(alternate);
    }

    add(url);
    for (final candidate in urls) {
      add(candidate);
    }
    return result;
  }
}
