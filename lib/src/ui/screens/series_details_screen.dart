import 'package:flutter/material.dart';

import '../../models/series_item.dart';
import '../../state/app_controller.dart';
import 'player_screen.dart';

class SeriesDetailsScreen extends StatefulWidget {
  const SeriesDetailsScreen({
    super.key,
    required this.controller,
    required this.series,
  });

  final AppController controller;
  final SeriesItem series;

  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  late Future<SeriesDetails> _details;
  int? _selectedSeason;

  @override
  void initState() {
    super.initState();
    _details = widget.controller.fetchSeriesDetails(widget.series);
  }

  void _retry() {
    setState(() {
      _selectedSeason = null;
      _details = widget.controller.fetchSeriesDetails(widget.series);
    });
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(controller.displaySeriesTitle(series))),
      body: FutureBuilder<SeriesDetails>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 42),
                    const SizedBox(height: 12),
                    const Text('Could not load this series.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final details = snapshot.data!;
          final seasons = details.seasons.keys.toList()..sort();
          final orderedEpisodes = <SeriesEpisode>[
            for (final season in seasons) ...details.seasons[season]!,
          ];
          if (seasons.isEmpty) {
            return const Center(child: Text('No episodes were returned by the provider.'));
          }

          final selectedSeason = _selectedSeason != null &&
                  details.seasons.containsKey(_selectedSeason)
              ? _selectedSeason!
              : seasons.first;
          final selectedEpisodes =
              details.seasons[selectedSeason] ?? const <SeriesEpisode>[];

          void playEpisode(SeriesEpisode episode) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  controller: controller,
                  item: controller.playbackForEpisode(
                    series,
                    episode,
                    followingEpisodes: (() {
                      final index = orderedEpisodes.indexOf(episode);
                      if (index < 0 || index + 1 >= orderedEpisodes.length) {
                        return const <SeriesEpisode>[];
                      }
                      return orderedEpisodes.skip(index + 1).toList(growable: false);
                    })(),
                  ),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _SeriesHeader(
                series: series,
                controller: controller,
                onPlay: selectedEpisodes.isEmpty
                    ? null
                    : () => playEpisode(selectedEpisodes.first),
              ),
              const SizedBox(height: 24),
              Text(
                'Seasons',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 102,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final season = seasons[index];
                    final episodes = details.seasons[season] ?? const <SeriesEpisode>[];
                    final selected = season == selectedSeason;
                    final image = episodes
                        .where((episode) => episode.imageUrl?.isNotEmpty == true)
                        .map((episode) => episode.imageUrl!)
                        .firstOrNull;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedSeason = season),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 170,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: selected
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white.withValues(alpha: 0.10),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: SizedBox(
                                width: 64,
                                height: 82,
                                child: image == null
                                    ? const ColoredBox(
                                        color: Color(0xFF11182A),
                                        child: Icon(Icons.tv_rounded),
                                      )
                                    : Image.network(
                                        image,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const ColoredBox(
                                          color: Color(0xFF11182A),
                                          child: Icon(Icons.tv_rounded),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Season $season',
                                    maxLines: 2,
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${episodes.length} episodes',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Season $selectedSeason episodes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              for (final episode in selectedEpisodes)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => playEpisode(episode),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 128,
                              height: 72,
                              child: episode.imageUrl == null
                                  ? const ColoredBox(
                                      color: Color(0xFF11182A),
                                      child: Icon(Icons.play_circle_outline),
                                    )
                                  : Image.network(
                                      episode.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const ColoredBox(
                                        color: Color(0xFF11182A),
                                        child: Icon(Icons.play_circle_outline),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.displayEpisodeTitle(episode),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                if (episode.duration?.isNotEmpty == true) ...[
                                  const SizedBox(height: 4),
                                  Text(episode.duration!, style: Theme.of(context).textTheme.bodySmall),
                                ],
                                if (episode.plot?.isNotEmpty == true) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    episode.plot!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.play_circle_fill_rounded, size: 32),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({required this.series, required this.controller, required this.onPlay});
  final SeriesItem series;
  final AppController controller;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 150,
          height: 220,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.06),
          ),
          child: series.coverUrl == null
              ? const Icon(Icons.movie_filter_outlined, size: 50)
              : Image.network(
                  series.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.movie_filter_outlined, size: 50),
                ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(controller.displaySeriesTitle(series), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              if (series.releaseDate != null) ...[
                const SizedBox(height: 6),
                Text(series.releaseDate!),
              ],
              if (series.rating != null) ...[
                const SizedBox(height: 6),
                Text('★ ${series.rating!.toStringAsFixed(1)}'),
              ],
              if (series.plot != null) ...[
                const SizedBox(height: 14),
                Text(series.plot!, maxLines: 5, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNullSeries<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
