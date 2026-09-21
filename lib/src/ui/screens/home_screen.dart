import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/content_section.dart';
import '../../models/epg_program.dart';
import '../../models/iptv_channel.dart';
import '../../models/library_entry.dart';
import '../../models/playback_item.dart';
import '../../state/app_controller.dart';
import '../branding/sb_brand.dart';
import '../widgets/account_manager_dialog.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/channel_tile.dart';
import '../widgets/epg_timeline.dart';
import '../widgets/library_tile.dart';
import '../widgets/poster_card.dart';
import '../widgets/sb_logo.dart';
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
  DateTime _guideAnchor = _roundedGuideTime(DateTime.now());
  Timer? _guideClock;
  Timer? _searchDebounce;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.loadEpg());
    });
    _guideClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.controller.section == ContentSection.guide) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _guideClock?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
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

  void _jumpGuideToNow() {
    setState(() => _guideAnchor = _roundedGuideTime(DateTime.now()));
  }

  void _shiftGuide(Duration offset) {
    setState(() => _guideAnchor = _guideAnchor.add(offset));
  }

  void _selectGuideDay(int offset) {
    final day = DateTime.now().add(Duration(days: offset));
    setState(() {
      _guideAnchor = DateTime(
        day.year,
        day.month,
        day.day,
        _guideAnchor.hour,
        _guideAnchor.minute,
      );
    });
  }

  Future<void> _showProgrammeDetails(
    IptvChannel channel,
    EpgProgram programme,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        final live = programme.isLiveAt(DateTime.now());
        return Dialog(
          alignment: Alignment.centerRight,
          insetPadding: const EdgeInsets.fromLTRB(64, 18, 18, 18),
          backgroundColor: SbBrand.elevated,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: SbBrand.electricBlue.withValues(alpha: 0.28),
            ),
          ),
          child: SizedBox(
            width: 430,
            height: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: channel.logoUrl == null
                            ? const Icon(
                                Icons.live_tv_outlined,
                                color: SbBrand.brightBlue,
                              )
                            : Image.network(
                                channel.logoUrl!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.live_tv_outlined,
                                  color: SbBrand.brightBlue,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          channel.name,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (live)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x24FF405B),
                        borderRadius: BorderRadius.all(Radius.circular(5)),
                      ),
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          'LIVE',
                          style: TextStyle(
                            color: SbBrand.liveError,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  if (live) const SizedBox(height: 10),
                  Text(
                    programme.title,
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_guideTime(programme.start)}–${_guideTime(programme.stop)}',
                    style: const TextStyle(
                      color: SbBrand.brightBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        programme.description?.trim().isNotEmpty == true
                            ? programme.description!.trim()
                            : 'No programme description is available.',
                        style:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: programme.description
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? SbBrand.textPrimary
                                      : SbBrand.textMuted,
                                  height: 1.55,
                                ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _play(widget.controller.playbackForChannel(channel));
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(live ? 'Watch live' : 'Watch channel'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAccounts() {
    return showDialog<void>(
      context: context,
      builder: (context) => AccountManagerDialog(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const SbLogo(
          symbolSize: 30,
          compact: true,
          showTagline: false,
        ),
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
              if (value == 'accounts') {
                unawaited(_showAccounts());
              } else if (value == 'logout') {
                unawaited(controller.logout());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(controller.account?.expiresAt == null
                    ? controller.account?.label ?? 'Account'
                    : 'Expires ${_date(controller.account!.expiresAt!)}'),
              ),
              const PopupMenuDivider(),
              if (!controller.config.isLocked)
                const PopupMenuItem(
                  value: 'accounts',
                  child: Text('Manage accounts'),
                ),
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
                collapsed: _sidebarCollapsed,
                onToggle: () => setState(
                  () => _sidebarCollapsed = !_sidebarCollapsed,
                ),
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
                              onChanged: _onSearchChanged,
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
      case ContentSection.home:
        return _buildHome(controller);
      case ContentSection.live:
        return _buildLive(controller);
      case ContentSection.guide:
        return _buildGuide(controller);
      case ContentSection.movies:
        return _buildMovies(controller);
      case ContentSection.series:
        return _buildSeries(controller);
      case ContentSection.continueWatching:
        return _buildLibrary(
          controller,
          controller.continueWatching.where((entry) {
            final query = _search.text.trim().toLowerCase();
            return query.isEmpty ||
                entry.title.toLowerCase().contains(query) ||
                (entry.subtitle?.toLowerCase().contains(query) ?? false);
          }).toList(growable: false),
          empty: 'Nothing to continue yet.',
        );
      case ContentSection.favorites:
        return _buildLibrary(controller, controller.visibleLibrary(controller.favorites, _search.text), empty: 'No favorites yet.');
      case ContentSection.recent:
        return _buildLibrary(controller, controller.visibleLibrary(controller.recent, _search.text), empty: 'Nothing watched yet.');
    }
  }

  Widget _buildHome(AppController controller) {
    final continueItems = controller.continueWatching;
    final recentItems = controller.visibleLibrary(controller.recent, '');
    final hero = continueItems.isNotEmpty
        ? continueItems.first
        : (recentItems.isNotEmpty ? recentItems.first : null);
    final liveChannels = controller.channels.where((channel) {
      return controller.nowProgram(channel) != null;
    }).take(6).toList(growable: false);
    final newMovies = controller.recentlyAddedMovies;
    final newSeries = controller.recentlyAddedSeries;

    return ListView(
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        SizedBox(
          height: 330,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hero?.artworkUrl != null)
                  Image.network(
                    hero!.artworkUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (_, _, _) =>
                        const BrandBackdrop(child: SizedBox.expand()),
                  )
                else
                  const BrandBackdrop(child: SizedBox.expand()),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xF2040509),
                        Color(0xA8040509),
                        Color(0x10040509),
                      ],
                      stops: [0, .46, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(34, 30, 34, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'SB PLAYER',
                        style: TextStyle(
                          color: SbBrand.brightBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hero?.title ?? 'Premium watching, made easy.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  fontSize: 38,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hero?.subtitle?.trim().isNotEmpty == true
                            ? hero!.subtitle!
                            : SbBrand.tagline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: SbBrand.textMuted,
                            ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (hero != null)
                            FilledButton.icon(
                              onPressed: () => _play(hero.toPlaybackItem()),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                hero.durationSeconds > 0 &&
                                        hero.positionSeconds > 0
                                    ? 'Continue watching'
                                    : 'Play',
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                unawaited(_changeSection(ContentSection.live)),
                            icon: const Icon(Icons.live_tv_outlined),
                            label: const Text('Browse Live TV'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (continueItems.isNotEmpty) ...[
          const SizedBox(height: 26),
          _HomeShelf(
            title: 'Pick Up Where You Left Off',
            entries: continueItems.take(10).toList(growable: false),
            onTap: (entry) => _play(entry.toPlaybackItem()),
          ),
        ],
        if (newMovies.isNotEmpty) ...[
          const SizedBox(height: 26),
          _PosterShelf(
            title: 'Recently Added Movies',
            count: newMovies.length,
            builder: (index) {
              final movie = newMovies[index];
              final item = controller.playbackForMovie(movie);
              return PosterCard(
                title: movie.name,
                imageUrl: movie.posterUrl,
                rating: movie.rating,
                favorite: controller.isFavorite(item),
                onFavorite: () => controller.toggleFavorite(item),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MovieDetailsScreen(
                        controller: controller,
                        movie: movie,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
        if (newSeries.isNotEmpty) ...[
          const SizedBox(height: 26),
          _PosterShelf(
            title: 'Recently Added Series',
            count: newSeries.length,
            builder: (index) {
              final series = newSeries[index];
              return PosterCard(
                title: series.name,
                imageUrl: series.coverUrl,
                rating: series.rating,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SeriesDetailsScreen(
                        controller: controller,
                        series: series,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
        if (liveChannels.isNotEmpty) ...[
          const SizedBox(height: 26),
          Text(
            'On Now',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: liveChannels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final channel = liveChannels[index];
                final item = controller.playbackForChannel(channel);
                final now = controller.nowProgram(channel)!;
                final next = controller.nextProgram(channel);
                return SizedBox(
                  width: 390,
                  child: ChannelTile(
                    channel: channel,
                    channelNumber: controller.channels.indexOf(channel) + 1,
                    nowText: now.title,
                    nextText: next?.title,
                    isFavorite: controller.isFavorite(item),
                    onFavorite: () => controller.toggleFavorite(item),
                    onTap: () => _play(item),
                  ),
                );
              },
            ),
          ),
        ],
        if (recentItems.isNotEmpty) ...[
          const SizedBox(height: 26),
          _HomeShelf(
            title: 'Recently Watched',
            entries: recentItems.take(8).toList(growable: false),
            onTap: (entry) => _play(entry.toPlaybackItem()),
          ),
        ],
      ],
    );
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
            final now = controller.nowProgram(channel);
            final next = controller.nextProgram(channel);
            final nowTime = DateTime.now();
            final duration = now?.stop.difference(now.start).inSeconds ?? 0;
            final elapsed =
                now == null ? 0 : nowTime.difference(now.start).inSeconds;
            final progress = duration <= 0
                ? null
                : (elapsed / duration).clamp(0.0, 1.0);
            return ChannelTile(
              channel: channel,
              channelNumber: index + 1,
              nowText: now?.title,
              nextText: next?.title,
              nowProgress: progress,
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Back 2 hours',
              onPressed: () => _shiftGuide(const Duration(hours: -2)),
              icon: const Icon(Icons.chevron_left),
            ),
            FilledButton.tonalIcon(
              onPressed: _jumpGuideToNow,
              icon: const Icon(Icons.schedule),
              label: const Text('Now'),
            ),
            PopupMenuButton<int>(
              tooltip: 'Choose day',
              onSelected: _selectGuideDay,
              itemBuilder: (context) => [
                for (var day = 0; day < 7; day++)
                  PopupMenuItem(
                    value: day,
                    child: Text(_dayMenuLabel(day)),
                  ),
              ],
              child: Chip(
                avatar: const Icon(Icons.calendar_today, size: 17),
                label: Text(_guideDayLabel(_guideAnchor)),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Forward 2 hours',
              onPressed: () => _shiftGuide(const Duration(hours: 2)),
              icon: const Icon(Icons.chevron_right),
            ),
            Text(
              '${_guideTime(_guideAnchor)} + 2 hours',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: controller.epgLoading
                  ? null
                  : () => controller.loadEpg(force: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh guide'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: EpgTimeline(
            controller: controller,
            channels: channels,
            anchor: _guideAnchor,
            onPlayChannel: (channel) =>
                _play(controller.playbackForChannel(channel)),
            onProgrammeSelected: _showProgrammeDetails,
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
        final columns = width > 1750 ? 5 : width > 1050 ? 4 : width > 760 ? 3 : width > 520 ? 2 : 2;
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
        final columns = width > 1750 ? 5 : width > 1050 ? 4 : width > 760 ? 3 : width > 520 ? 2 : 2;
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
      case ContentSection.home:
        return 'Search SB Player';
      case ContentSection.live:
        return 'Search channels';
      case ContentSection.guide:
        return 'Search TV guide';
      case ContentSection.movies:
        return 'Search movies';
      case ContentSection.series:
        return 'Search series';
      case ContentSection.continueWatching:
        return 'Search Continue Watching';
      case ContentSection.favorites:
        return 'Search favorites';
      case ContentSection.recent:
        return 'Search recent';
    }
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _guideTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _guideDayLabel(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(value.year, value.month, value.day);
    final difference = selected.difference(today).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    return _date(value);
  }

  String _dayMenuLabel(int offset) {
    if (offset == 0) return 'Today';
    if (offset == 1) return 'Tomorrow';
    final date = DateTime.now().add(Duration(days: offset));
    return _date(date);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.collapsed,
    required this.onToggle,
    required this.onSection,
  });

  final AppController controller;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<ContentSection> onSection;

  @override
  Widget build(BuildContext context) {
    final width = collapsed ? 82.0 : 245.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: SbBrand.elevated,
        border: Border(
          right: BorderSide(
            color: SbBrand.electricBlue.withValues(alpha: 0.16),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              collapsed ? 14 : 16,
              16,
              collapsed ? 14 : 12,
              10,
            ),
            child: Row(
              children: [
                if (!collapsed)
                  const Expanded(
                    child: SbLogo(
                      symbolSize: 24,
                      compact: true,
                      showTagline: false,
                    ),
                  ),
                if (collapsed)
                  const Expanded(
                    child: Center(
                      child: SbLogo(
                        symbolSize: 26,
                        showWordmark: false,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggle,
                  icon: Icon(
                    collapsed
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
              children: [
                _NavButton(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  collapsed: collapsed,
                  selected: controller.section == ContentSection.home,
                  onTap: () => onSection(ContentSection.home),
                ),
                _NavButton(
                  icon: Icons.live_tv_outlined,
                  label: 'Live TV',
                  collapsed: collapsed,
                  selected: controller.section == ContentSection.live,
                  onTap: () => onSection(ContentSection.live),
                ),
                _NavButton(
                  icon: Icons.calendar_view_week_outlined,
                  label: 'TV Guide',
                  collapsed: collapsed,
                  selected: controller.section == ContentSection.guide,
                  onTap: () => onSection(ContentSection.guide),
                ),
                if (controller.supportsOnDemand) ...[
                  _NavButton(
                    icon: Icons.movie_outlined,
                    label: 'Movies',
                    collapsed: collapsed,
                    selected: controller.section == ContentSection.movies,
                    onTap: () => onSection(ContentSection.movies),
                  ),
                  _NavButton(
                    icon: Icons.tv_outlined,
                    label: 'Series',
                    collapsed: collapsed,
                    selected: controller.section == ContentSection.series,
                    onTap: () => onSection(ContentSection.series),
                  ),
                ],
                const Divider(height: 24),
                _NavButton(
                  icon: Icons.play_circle_outline,
                  label: 'Continue Watching',
                  collapsed: collapsed,
                  selected:
                      controller.section == ContentSection.continueWatching,
                  onTap: () => onSection(ContentSection.continueWatching),
                ),
                _NavButton(
                  icon: Icons.favorite_border,
                  label: 'Favorites',
                  collapsed: collapsed,
                  selected: controller.section == ContentSection.favorites,
                  onTap: () => onSection(ContentSection.favorites),
                ),
                _NavButton(
                  icon: Icons.history,
                  label: 'Recent',
                  collapsed: collapsed,
                  selected: controller.section == ContentSection.recent,
                  onTap: () => onSection(ContentSection.recent),
                ),
                if (!collapsed && controller.activeCategories.isNotEmpty) ...[
                  const Divider(height: 28),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: Text(
                      'CATEGORIES',
                      style: TextStyle(
                        color: SbBrand.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.25,
                      ),
                    ),
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
          _AccountFooter(
            controller: controller,
            collapsed: collapsed,
          ),
        ],
      ),
    );
  }
}

class _AccountFooter extends StatelessWidget {
  const _AccountFooter({
    required this.controller,
    required this.collapsed,
  });

  final AppController controller;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final username = controller.account?.username?.trim();
    final displayName = username?.isNotEmpty == true
        ? username!
        : controller.activeProfile?.name ?? 'Account';
    final edition =
        controller.config.isLocked ? 'SB Edition' : 'Open Edition';

    return Container(
      padding: EdgeInsets.all(collapsed ? 11 : 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: SbBrand.electricBlue.withValues(alpha: 0.14),
          ),
        ),
      ),
      child: collapsed
          ? Tooltip(
              message: '$displayName • $edition',
              child: const CircleAvatar(
                radius: 20,
                backgroundColor: SbBrand.panelBlue,
                child: Icon(
                  Icons.person_outline,
                  color: SbBrand.brightBlue,
                ),
              ),
            )
          : Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: SbBrand.panelBlue,
                  child: Icon(
                    Icons.person_outline,
                    color: SbBrand.brightBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        edition,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: SbBrand.electricBlue.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected
                ? SbBrand.electricBlue.withValues(alpha: 0.46)
                : Colors.transparent,
          ),
        ),
        leading: Icon(
          icon,
          color: selected ? SbBrand.brightBlue : SbBrand.textMuted,
        ),
        title: collapsed
            ? null
            : Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? SbBrand.textPrimary
                      : SbBrand.textMuted,
                ),
              ),
        contentPadding: collapsed
            ? const EdgeInsets.symmetric(horizontal: 16)
            : const EdgeInsets.symmetric(horizontal: 12),
        horizontalTitleGap: 10,
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
      ContentSection.home => 'Home',
      ContentSection.live => 'Live TV',
      ContentSection.guide => 'TV Guide',
      ContentSection.movies => 'Movies',
      ContentSection.series => 'Series',
      ContentSection.continueWatching => 'Continue Watching',
      ContentSection.favorites => 'Favorites',
      ContentSection.recent => 'Recent',
    };
    return Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900));
  }
}


class _PosterShelf extends StatelessWidget {
  const _PosterShelf({
    required this.title,
    required this.count,
    required this.builder,
  });

  final String title;
  final int count;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        SizedBox(
          height: 330,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) => SizedBox(
              width: 205,
              child: builder(index),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeShelf extends StatelessWidget {
  const _HomeShelf({
    required this.title,
    required this.entries,
    required this.onTap,
  });

  final String title;
  final List<LibraryEntry> entries;
  final ValueChanged<LibraryEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return SizedBox(
                width: 290,
                child: Card(
                  child: InkWell(
                    onTap: () => onTap(entry),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (entry.artworkUrl != null)
                          Image.network(
                            entry.artworkUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const BrandBackdrop(child: SizedBox.expand()),
                          )
                        else
                          const BrandBackdrop(child: SizedBox.expand()),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                SbBrand.black.withValues(alpha: .88),
                              ],
                              stops: const [.2, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (entry.subtitle?.isNotEmpty == true) ...[
                                const SizedBox(height: 3),
                                Text(
                                  entry.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (entry.durationSeconds > 0) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: entry.progress.clamp(0, 1),
                                    minHeight: 3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

DateTime _roundedGuideTime(DateTime value) {
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute < 30 ? 0 : 30,
  );
}
