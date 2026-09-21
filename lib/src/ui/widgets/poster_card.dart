import 'package:flutter/material.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.subtitle,
    this.rating,
    this.favorite = false,
    this.onFavorite,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final double? rating;
  final VoidCallback onTap;
  final bool favorite;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.white.withValues(alpha: 0.05),
                    child: imageUrl == null
                        ? const Icon(Icons.movie_outlined, size: 46)
                        : Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.movie_outlined, size: 46),
                          ),
                  ),
                  if (onFavorite != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton.filledTonal(
                        tooltip: favorite ? 'Remove favorite' : 'Add favorite',
                        onPressed: onFavorite,
                        icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (subtitle != null || rating != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
                        if (rating != null) '★ ${rating!.toStringAsFixed(1)}',
                      ].join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
