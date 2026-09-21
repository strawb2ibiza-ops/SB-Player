import 'package:flutter/material.dart';

import '../../models/series_item.dart';
import '../../models/playback_item.dart';
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

  @override
  void initState() {
    super.initState();
    _details = widget.controller.fetchSeriesDetails(widget.series);
  }

  void _retry() {
    setState(() {
      _details = widget.controller.fetchSeriesDetails(widget.series);
    });
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(series.name)),
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
          final episodeQueue = <PlaybackItem>[
            for (final season in seasons)
              for (final episode in details.seasons[season]!)
                controller.playbackForEpisode(series, episode),
          ];
          if (seasons.isEmpty) {
            return const Center(child: Text('No episodes were returned by the provider.'));
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _SeriesHeader(series: series),
              const SizedBox(height: 20),
              for (final season in seasons)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    initiallyExpanded: season == seasons.first,
                    title: Text('Season $season', style: const TextStyle(fontWeight: FontWeight.w800)),
                    children: [
                      for (final episode in details.seasons[season]!)
                        ListTile(
                          leading: SizedBox(
                            width: 42,
                            child: Center(
                              child: Text(
                                episode.episodeNumber.toString(),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          title: Text(episode.title),
                          subtitle: episode.duration == null ? null : Text(episode.duration!),
                          trailing: const Icon(Icons.play_circle_outline),
                          onTap: () {
                            final item =
                                controller.playbackForEpisode(series, episode);
                            final queueIndex = episodeQueue.indexWhere(
                              (value) => value.id == item.id,
                            );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlayerScreen(
                                  controller: controller,
                                  item: item,
                                  playlist: episodeQueue,
                                  playlistIndex: queueIndex,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
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
  const _SeriesHeader({required this.series});
  final SeriesItem series;

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
              Text(series.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
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
                Text(series.plot!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
