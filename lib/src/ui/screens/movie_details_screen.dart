import 'package:flutter/material.dart';

import '../../models/vod_item.dart';
import '../../state/app_controller.dart';
import '../branding/sb_brand.dart';
import 'player_screen.dart';

class MovieDetailsScreen extends StatelessWidget {
  const MovieDetailsScreen({
    super.key,
    required this.controller,
    required this.movie,
  });

  final AppController controller;
  final VodItem movie;

  void _play(BuildContext context) {
    final item = controller.playbackForMovie(movie);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(controller: controller, item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final item = controller.playbackForMovie(movie);
        final favorite = controller.isFavorite(item);
        final resume = item.startPosition > const Duration(seconds: 10);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(movie.name),
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (movie.posterUrl != null)
                Opacity(
                  opacity: 0.22,
                  child: Image.network(
                    movie.posterUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB8040509),
                      Color(0xF2040509),
                      SbBrand.black,
                    ],
                    stops: [0, 0.58, 1],
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final poster = _Poster(url: movie.posterUrl);
                  final details = _Details(
                    movie: movie,
                    resumePosition: item.startPosition,
                    favorite: favorite,
                    onFavorite: () => controller.toggleFavorite(item),
                    onPlay: () => _play(context),
                  );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(30, 118, 30, 36),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 300, child: poster),
                                  const SizedBox(width: 36),
                                  Expanded(child: details),
                                ],
                              )
                            : Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Center(
                                    child: SizedBox(
                                      width: 260,
                                      child: poster,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  details,
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: resume
              ? FloatingActionButton.extended(
                  backgroundColor: SbBrand.electricBlue,
                  foregroundColor: Colors.white,
                  onPressed: () => _play(context),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    'Resume ${_formatDuration(item.startPosition)}',
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Card(
        child: url == null
            ? const Center(child: Icon(Icons.movie_outlined, size: 72))
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.movie_outlined, size: 72)),
              ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.movie,
    required this.resumePosition,
    required this.favorite,
    required this.onFavorite,
    required this.onPlay,
  });

  final VodItem movie;
  final Duration resumePosition;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      if (movie.releaseDate?.isNotEmpty ?? false) movie.releaseDate!,
      if (movie.duration?.isNotEmpty ?? false) movie.duration!,
      if (movie.rating != null) '★ ${movie.rating!.toStringAsFixed(1)}',
    ];
    final resume = resumePosition > const Duration(seconds: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          movie.name,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(metadata.join('  •  '), style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow),
              label: Text(resume ? 'Resume ${_formatDuration(resumePosition)}' : 'Play'),
            ),
            OutlinedButton.icon(
              onPressed: onFavorite,
              icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
              label: Text(favorite ? 'Favorited' : 'Add to favorites'),
            ),
          ],
        ),
        if (movie.plot?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 28),
          Text(
            'Overview',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            movie.plot!.trim(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ],
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
