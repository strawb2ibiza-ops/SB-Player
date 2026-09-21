import 'package:flutter/material.dart';

import '../../models/library_entry.dart';
import '../../models/playback_item.dart';

class LibraryTile extends StatelessWidget {
  const LibraryTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onFavorite,
    this.favorite = false,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: entry.artworkUrl == null
                    ? Icon(_iconFor(entry.kind))
                    : Image.network(
                        entry.artworkUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(_iconFor(entry.kind)),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (entry.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(entry.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    if (entry.durationSeconds > 0) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: entry.progress.clamp(0, 1)),
                    ],
                  ],
                ),
              ),
              if (onFavorite != null)
                IconButton(
                  tooltip: favorite ? 'Remove favorite' : 'Add favorite',
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                ),
              const Icon(Icons.play_circle_outline),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PlaybackKind kind) {
    switch (kind) {
      case PlaybackKind.live:
        return Icons.live_tv_outlined;
      case PlaybackKind.movie:
        return Icons.movie_outlined;
      case PlaybackKind.episode:
        return Icons.tv_outlined;
    }
  }
}
