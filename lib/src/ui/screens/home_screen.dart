import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/content_section.dart';
import '../../models/library_entry.dart';
import '../../models/playback_item.dart';
import '../../state/app_controller.dart';
import '../widgets/channel_tile.dart';
import '../widgets/epg_timeline.dart';
import '../widgets/library_tile.dart';
import '../widgets/poster_card.dart';
import 'movie_details_screen.dart';
import 'player_screen.dart';
import 'series_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.loadEpg());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _changeSection(ContentSection section) async {
    _search.clear();
    await widget.controller.selectSection(section);
    if (section == ContentSection.live || section == ContentSection.guide) {
      unawaited(widget.controller.loadEpg());
    }
  }

  void _play(PlaybackItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(controller: widget.controller, item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SB Player', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (controller.epgLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          IconButton(
            tooltip: 'Refresh provider data',
            onPressed: controller.loading ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') unawaited(controller.logout());
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(controller.account?.expiresAt == null
                    ? controller.account?.label ?? 'Account'
                    : 'Expires ${_date(controller.account!.expiresAt!)}'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Row(
            children: [
              _Sidebar(
                controller: controller,
                onSection: (value) => unawaited(_changeSection(value)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,
                              decoration: InputDecoration(
                                hintText: _searchHint(controller.section),
                                prefixIcon: const Icon(Icons.search),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _SectionTitle(section: controller.section),
                        ],
                      ),
                      if (controller.error != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(controller.error!, style: const TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Expanded(child: _buildContent(controller)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(AppController controller) {
    if ((controller.loading && controller.channels.isEmpty) || controller.contentLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (controller.section) {
      case ContentSection.live:
        return _buildLive(controller);
      case ContentSection.guide:
        return _buildGuide(controller);
      case ContentSection.movies:
        return _buildMovies(controller);
      case ContentSection.series:
        return _buildSeries(controller);
      case ContentSection.favorites:
        return _buildLibrary(controller, controller.visibleLibrary(controller.favorites, _search.text), empty: 'No favorites yet.');
      case ContentSection.recent:
        return _buildLibrary(controller, controller.visibleLibrary(controller.recent, _search.text), empty: 'Nothing watched yet.');
    }
  }

  Widget _buildLive(AppController controller) {
    final channels = controller.visibleChannels(_search.text);
    if (channels.isEmpty) return const Center(child: Text('No channels found.'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1250 ? 3 : constraints.maxWidth > 720 ? 2 : 1;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 4.5 : 3.5,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final channel = channels[index];
            final item = controller.playbackForChannel(channel);
            return ChannelTile(
              channel: channel,
              nowText: controller.nowProgram(channel)?.title,
              nextText: controller.nextProgram(channel)?.title,
              isFavorite: controller.isFavorite(item),
              onFavorite: () => controller.toggleFavorite(item),
              onTap: () => _play(item),
            );
          },
        );
      },
    );
  }

  Widget _buildGuide(AppController controller) {
    final channels = controller.visibleChannels(_search.text);
    if (channels.isEmpty) {
      return const Center(child: Text('No channels found.'));
    }
    if (controller.epg.isEmpty && !controller.epgLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_view_week_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('No EPG data is available from this provider.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => controller.loadEpg(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Try loading guide'),
            ),
          ],
        ),
      );
    }

    if (controller.epgLoading && controller.epg.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Row(
          children: [
            Text(
              'Now + 4 hours',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed:
                  controller.epgLoading ? null : () => controller.loadEpg(force: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh guide'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: EpgTimeline(
            controller: controller,
            channels: channels,
            onPlayChannel: (channel) =>
                _play(controller.playbackForChannel(channel)),
          ),
        ),
      ],
    );
  }

  Widget _buildMovies(AppController controller) {
    final movies = controller.visibleMovies(_search.text);
    if (movies.isEmpty) return const Center(child: Text('No movies found.'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1300 ? 6 : width > 1000 ? 5 : width > 760 ? 4 : width > 520 ? 3 : 2;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.66,
          ),
          itemCount: movies.length,
          itemBuilder: (context, index) {
            final movie = movies[index];
            final item = controller.playbackForMovie(movie);
            return PosterCard(
              title: movie.name,
              imageUrl: movie.posterUrl,
              subtitle: movie.releaseDate,
              rating: movie.rating,
              favorite: controller.isFavorite(item),
              onFavorite: () => controller.toggleFavorite(item),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MovieDetailsScreen(controller: controller, movie: movie),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSeries(AppController controller) {
    final items = controller.visibleSeries(_search.text);
    if (items.isEmpty) return const Center(child: Text('No series found.'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1300 ? 6 : width > 1000 ? 5 : width > 760 ? 4 : width > 520 ? 3 : 2;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.66,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final series = items[index];
            return PosterCard(
              title: series.name,
              imageUrl: series.coverUrl,
              subtitle: series.releaseDate,
              rating: series.rating,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SeriesDetailsScreen(controller: controller, series: series),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLibrary(
    AppController controller,
    List<LibraryEntry> entries, {
    required String empty,
  }) {
    if (entries.isEmpty) return Center(child: Text(empty));
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final item = entry.toPlaybackItem();
        return LibraryTile(
          entry: entry,
          favorite: controller.isFavorite(item),
          onFavorite: () => controller.toggleFavorite(item),
          onTap: () => _play(item),
        );
      },
    );
  }

  String _searchHint(ContentSection section) {
    switch (section) {
      case ContentSection.live:
        return 'Search channels';
      case ContentSection.guide:
        return 'Search TV guide';
      case ContentSection.movies:
        return 'Search movies';
      case ContentSection.series:
        return 'Search series';
      case ContentSection.favorites:
        return 'Search favorites';
      case ContentSection.recent:
        return 'Search recent';
    }
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller, required this.onSection});

  final AppController controller;
  final ValueChanged<ContentSection> onSection;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 245,
      child: DecoratedBox(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                children: [
                  _NavButton(
                    icon: Icons.live_tv_outlined,
                    label: 'Live TV',
                    selected: controller.section == ContentSection.live,
                    onTap: () => onSection(ContentSection.live),
                  ),
                  _NavButton(
                    icon: Icons.calendar_view_week_outlined,
                    label: 'TV Guide',
                    selected: controller.section == ContentSection.guide,
                    onTap: () => onSection(ContentSection.guide),
                  ),
                  if (controller.supportsOnDemand) ...[
                    _NavButton(
                      icon: Icons.movie_outlined,
                      label: 'Movies',
                      selected: controller.section == ContentSection.movies,
                      onTap: () => onSection(ContentSection.movies),
                    ),
                    _NavButton(
                      icon: Icons.tv_outlined,
                      label: 'Series',
                      selected: controller.section == ContentSection.series,
                      onTap: () => onSection(ContentSection.series),
                    ),
                  ],
                  const Divider(height: 24),
                  _NavButton(
                    icon: Icons.favorite_border,
                    label: 'Favorites',
                    selected: controller.section == ContentSection.favorites,
                    onTap: () => onSection(ContentSection.favorites),
                  ),
                  _NavButton(
                    icon: Icons.history,
                    label: 'Recent',
                    selected: controller.section == ContentSection.recent,
                    onTap: () => onSection(ContentSection.recent),
                  ),
                  if (controller.activeCategories.isNotEmpty) ...[
                    const Divider(height: 28),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: Text('CATEGORIES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                    _CategoryButton(
                      label: 'All',
                      selected: controller.activeCategoryId == '__all__',
                      onTap: () => controller.selectCategory('__all__'),
                    ),
                    for (final category in controller.activeCategories)
                      _CategoryButton(
                        label: category.name,
                        selected: controller.activeCategoryId == category.id,
                        onTap: () => controller.selectCategory(category.id),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Text('SB', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                  const Spacer(),
                  Text(
                    controller.config.isLocked ? 'SB Edition' : 'Open Edition',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: onTap,
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(selected ? Icons.chevron_right : Icons.folder_outlined, size: 19),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.section});
  final ContentSection section;

  @override
  Widget build(BuildContext context) {
    final label = switch (section) {
      ContentSection.live => 'Live TV',
      ContentSection.guide => 'TV Guide',
      ContentSection.movies => 'Movies',
      ContentSection.series => 'Series',
      ContentSection.favorites => 'Favorites',
      ContentSection.recent => 'Recent',
    };
    return Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900));
  }
}
