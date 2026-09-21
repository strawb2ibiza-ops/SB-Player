import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/playback_item.dart';
import '../widgets/desktop_window_controls.dart';
import '../../services/mini_player_preferences.dart';
import '../../state/app_controller.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.item,
    this.playlist = const [],
    this.playlistIndex = -1,
  });

  final AppController controller;
  final PlaybackItem item;
  final List<PlaybackItem> playlist;
  final int playlistIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  static const _normalMinimumSize = Size(900, 600);
  static const _detailedMiniSize = Size(620, 420);
  static const _detailedMiniMinimumSize = Size(460, 310);
  static const _videoOnlyMiniSize = Size(520, 300);
  static const _videoOnlyMiniMinimumSize = Size(320, 180);

  late PlaybackItem _item;
  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final MiniPlayerPreferences _miniPreferences = const MiniPlayerPreferences();

  bool _miniMode = false;
  bool _buffering = true;
  bool _playing = false;
  bool _hoveringVideoOnly = false;
  bool _reconnecting = false;
  double _volume = 100;
  double _lastNonZeroVolume = 100;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _geometrySaveTimer;
  Timer? _nextEpisodeTimer;
  int? _nextEpisodeCountdown;
  int _playlistIndex = -1;
  bool _introAutoSkipped = false;
  bool _creditsAutoHandled = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _playbackError;
  Size? _previousWindowSize;
  Offset? _previousWindowPosition;
  Tracks _tracks = const Tracks();
  Track _selectedTracks = const Track();
  MiniPlayerLayout _miniLayout = MiniPlayerLayout.detailed;
  _VideoDisplayMode _displayMode = _VideoDisplayMode.auto;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _playlistIndex = widget.playlistIndex;
    _player = Player();
    if (Platform.isWindows) windowManager.addListener(this);
    _videoController = VideoController(_player);
    _subscriptions.add(_player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    }));
    _subscriptions.add(_player.stream.error.listen((value) {
      if (value.trim().isEmpty) return;
      _handlePlaybackFailure();
    }));
    _subscriptions.add(_player.stream.tracks.listen((value) {
      if (mounted) setState(() => _tracks = value);
    }));
    _subscriptions.add(_player.stream.track.listen((value) {
      if (mounted) setState(() => _selectedTracks = value);
    }));
    _subscriptions.add(_player.stream.playing.listen((value) {
      if (value) {
        _reconnectTimer?.cancel();
        _reconnectAttempts = 0;
        _reconnecting = false;
      }
      if (mounted) setState(() => _playing = value);
    }));
    _subscriptions.add(_player.stream.position.listen((value) {
      if (mounted) setState(() => _position = value);
      _handleSmartSkips(value);
    }));
    _subscriptions.add(_player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    }));
    _subscriptions.add(_player.stream.volume.listen((value) {
      if (value > 0) _lastNonZeroVolume = value;
      if (mounted) setState(() => _volume = value);
    }));
    _subscriptions.add(_player.stream.completed.listen((value) {
      if (value) _handlePlaybackCompleted();
    }));

    unawaited(_loadMiniPreference());
    unawaited(_open());
  }

  Future<void> _loadMiniPreference() async {
    final layout = await _miniPreferences.readLayout();
    if (mounted) setState(() => _miniLayout = layout);
  }

  bool get _hasNextEpisode =>
      _playlistIndex >= 0 &&
      _playlistIndex + 1 < widget.playlist.length;

  Duration get _introSkipTarget {
    if (_duration.inSeconds <= 0) return const Duration(seconds: 75);
    final detected = (_duration.inSeconds * 0.055).round().clamp(45, 90).toInt();
    return Duration(seconds: detected);
  }

  bool get _showIntroSkip {
    if (_item.kind != PlaybackKind.episode ||
        !widget.controller.preferences.showSkipIntro ||
        _duration.inSeconds < 600) {
      return false;
    }
    return _position >= const Duration(seconds: 8) &&
        _position < _introSkipTarget;
  }

  bool get _showCreditsSkip {
    if (_item.kind != PlaybackKind.episode ||
        !widget.controller.preferences.showSkipCredits ||
        _duration.inSeconds < 600) {
      return false;
    }
    final remaining = _duration - _position;
    final threshold = Duration(
      seconds: (_duration.inSeconds * 0.045).round().clamp(65, 150).toInt(),
    );
    return remaining > Duration.zero && remaining <= threshold;
  }

  void _handleSmartSkips(Duration position) {
    if (_item.kind != PlaybackKind.episode || _duration.inSeconds < 600) {
      return;
    }

    final prefs = widget.controller.preferences;
    if (prefs.showSkipIntro &&
        prefs.autoSkipIntro &&
        !_introAutoSkipped &&
        position >= const Duration(seconds: 8) &&
        position < _introSkipTarget) {
      _introAutoSkipped = true;
      unawaited(_player.seek(_introSkipTarget));
    }

    if (prefs.showSkipCredits &&
        prefs.autoSkipCredits &&
        !_creditsAutoHandled &&
        _showCreditsSkip) {
      _creditsAutoHandled = true;
      if (_hasNextEpisode) {
        unawaited(_playNextEpisode());
      } else {
        unawaited(_player.seek(_duration - const Duration(seconds: 1)));
      }
    }
  }

  void _handlePlaybackCompleted() {
    if (_item.kind != PlaybackKind.episode ||
        !widget.controller.preferences.autoplayNextEpisode ||
        !_hasNextEpisode ||
        _nextEpisodeTimer?.isActive == true) {
      return;
    }

    var seconds = 5;
    if (mounted) setState(() => _nextEpisodeCountdown = seconds);
    _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      seconds -= 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (seconds <= 0) {
        timer.cancel();
        setState(() => _nextEpisodeCountdown = null);
        unawaited(_playNextEpisode());
      } else {
        setState(() => _nextEpisodeCountdown = seconds);
      }
    });
  }

  Future<void> _playNextEpisode() async {
    if (!_hasNextEpisode) return;

    await widget.controller.recordPlayback(
      _item,
      position: _player.state.duration,
      duration: _player.state.duration,
    );

    _playlistIndex += 1;
    final next = widget.playlist[_playlistIndex];
    _nextEpisodeTimer?.cancel();
    if (mounted) {
      setState(() {
        _item = next;
        _position = Duration.zero;
        _duration = Duration.zero;
        _nextEpisodeCountdown = null;
        _introAutoSkipped = false;
        _creditsAutoHandled = false;
        _playbackError = null;
        _buffering = true;
      });
    }
    await _player.stop();
    await _open();
  }

  void _cancelNextEpisode() {
    _nextEpisodeTimer?.cancel();
    if (mounted) setState(() => _nextEpisodeCountdown = null);
  }

  @override
  void onWindowMove() {
    _scheduleMiniGeometrySave();
  }

  @override
  void onWindowResize() {
    _scheduleMiniGeometrySave();
  }

  void _scheduleMiniGeometrySave() {
    if (!_miniMode || !Platform.isWindows) return;
    _geometrySaveTimer?.cancel();
    _geometrySaveTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_saveMiniGeometry()),
    );
  }

  Future<void> _open({Duration? resumeAt}) async {
    if (mounted) {
      setState(() {
        _playbackError = null;
        _buffering = true;
      });
    }

    try {
      await _player.open(Media(_item.streamUrl), play: true);
      final target = resumeAt ?? _item.startPosition;
      if (!_item.isLive && target > const Duration(seconds: 5)) {
        await _player.seek(target);
      }
    } catch (_) {
      _handlePlaybackFailure();
    }
  }

  Future<void> _retry({bool manual = true}) async {
    if (manual) {
      _reconnectTimer?.cancel();
      _reconnectAttempts = 0;
    }
    final resumeAt = _item.isLive
        ? null
        : (_position > const Duration(seconds: 5)
            ? _position
            : _item.startPosition);
    await _player.stop();
    await _open(resumeAt: resumeAt);
  }

  void _handlePlaybackFailure() {
    if (!mounted) return;
    setState(() {
      _playbackError = _item.isLive
          ? 'The live stream was interrupted.'
          : 'Playback stopped unexpectedly.';
    });
    if (_item.isLive) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= 3 || _reconnectTimer?.isActive == true) return;
    final delaySeconds = 2 << _reconnectAttempts;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) return;
      _reconnectAttempts += 1;
      setState(() => _reconnecting = true);
      unawaited(_retry(manual: false));
    });
  }

  Future<void> _toggleMiniPlayer() async {
    if (!Platform.isWindows) return;

    if (!_miniMode) {
      _previousWindowSize = await windowManager.getSize();
      _previousWindowPosition = await windowManager.getPosition();
      await windowManager.setAlwaysOnTop(true);
      await _applyMiniChrome();
      await _applyMiniWindowSize();
      if (mounted) setState(() => _miniMode = true);
      return;
    }

    await _restoreWindow();
    if (mounted) setState(() => _miniMode = false);
  }

  Future<void> _toggleMiniLayout() async {
    if (!Platform.isWindows || !_miniMode) return;
    final next = _miniLayout == MiniPlayerLayout.detailed
        ? MiniPlayerLayout.videoOnly
        : MiniPlayerLayout.detailed;
    await _saveMiniGeometry();
    setState(() {
      _miniLayout = next;
      _hoveringVideoOnly = false;
    });
    await _miniPreferences.saveLayout(next);
    await _applyMiniChrome();
    await _applyMiniWindowSize();
  }

  Future<void> _applyMiniWindowSize() async {
    if (!Platform.isWindows) return;
    final detailed = _miniLayout == MiniPlayerLayout.detailed;
    final minimum =
        detailed ? _detailedMiniMinimumSize : _videoOnlyMiniMinimumSize;
    final fallback = detailed ? _detailedMiniSize : _videoOnlyMiniSize;
    final saved = await _miniPreferences.readGeometry(_miniLayout);
    final size = saved == null
        ? fallback
        : Size(
            saved.size.width < minimum.width ? minimum.width : saved.size.width,
            saved.size.height < minimum.height
                ? minimum.height
                : saved.size.height,
          );

    await windowManager.setMinimumSize(minimum);
    await windowManager.setSize(size, animate: true);
    if (saved != null) {
      await windowManager.setPosition(saved.position, animate: true);
    }
  }

  Future<void> _applyMiniChrome() async {
    if (!Platform.isWindows) return;
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  }

  Future<void> _saveMiniGeometry() async {
    if (!Platform.isWindows || !_miniMode) return;
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    await _miniPreferences.saveGeometry(
      _miniLayout,
      size: size,
      position: position,
    );
  }

  Future<void> _restoreWindow() async {
    if (!Platform.isWindows || !_miniMode) return;
    await _saveMiniGeometry();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setMinimumSize(_normalMinimumSize);
    if (_previousWindowSize != null) {
      await windowManager.setSize(_previousWindowSize!, animate: true);
    }
    if (_previousWindowPosition != null) {
      await windowManager.setPosition(_previousWindowPosition!, animate: true);
    }
  }

  Future<void> _showTrackPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              children: [
                Text('Audio', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                if (_tracks.audio.isEmpty)
                  const ListTile(title: Text('No selectable audio tracks'))
                else
                  for (var i = 0; i < _tracks.audio.length; i++)
                    _AudioTrackTile(
                      track: _tracks.audio[i],
                      index: i,
                      selected: _tracks.audio[i].id == _selectedTracks.audio.id,
                      onTap: () async {
                        await _player.setAudioTrack(_tracks.audio[i]);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                const Divider(height: 30),
                Text('Subtitles', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                if (_tracks.subtitle.isEmpty)
                  const ListTile(title: Text('No selectable subtitle tracks'))
                else
                  for (var i = 0; i < _tracks.subtitle.length; i++)
                    _SubtitleTrackTile(
                      track: _tracks.subtitle[i],
                      index: i,
                      selected:
                          _tracks.subtitle[i].id == _selectedTracks.subtitle.id,
                      onTap: () async {
                        await _player.setSubtitleTrack(_tracks.subtitle[i]);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _seekFromSlider(double value) async {
    if (_duration.inMilliseconds <= 0) return;
    await _player.seek(Duration(milliseconds: value.round()));
  }

  Future<void> _seekRelative(int seconds) async {
    if (_item.isLive || _duration.inMilliseconds <= 0) return;
    final target = (_position + Duration(seconds: seconds)).inMilliseconds;
    final clamped = target.clamp(0, _duration.inMilliseconds).toInt();
    await _player.seek(Duration(milliseconds: clamped));
  }

  Future<void> _changeVolume(double delta) async {
    final next = (_volume + delta).clamp(0, 100).toDouble();
    await _player.setVolume(next);
  }

  Future<void> _toggleMute() async {
    if (_volume <= 0) {
      await _player.setVolume(_lastNonZeroVolume.clamp(1, 100).toDouble());
    } else {
      _lastNonZeroVolume = _volume;
      await _player.setVolume(0);
    }
  }

  void _cycleDisplayMode() {
    final index = _VideoDisplayMode.values.indexOf(_displayMode);
    setState(() {
      _displayMode =
          _VideoDisplayMode.values[(index + 1) % _VideoDisplayMode.values.length];
    });
  }

  Future<void> _switchLiveChannel(int delta) async {
    if (!_item.isLive || widget.controller.channels.isEmpty) return;
    final id = _contentId.replaceFirst('live:', '');
    final currentIndex =
        widget.controller.channels.indexWhere((channel) => channel.id == id);
    if (currentIndex < 0) return;

    final length = widget.controller.channels.length;
    final nextIndex = (currentIndex + delta + length) % length;
    final next = widget.controller.playbackForChannel(
      widget.controller.channels[nextIndex],
    );

    await widget.controller.recordPlayback(
      _item,
      position: _player.state.position,
      duration: _player.state.duration,
    );

    if (!mounted) return;
    setState(() {
      _item = next;
      _playbackError = null;
      _buffering = true;
    });
    await _retry();
  }

  Widget _withKeyboardShortcuts(Widget child) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () =>
            unawaited(_player.playOrPause()),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            unawaited(_seekRelative(-10)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            unawaited(_seekRelative(10)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            unawaited(_changeVolume(5)),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            unawaited(_changeVolume(-5)),
        const SingleActivator(LogicalKeyboardKey.keyM): () =>
            unawaited(_toggleMute()),
        const SingleActivator(LogicalKeyboardKey.keyA): _cycleDisplayMode,
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            unawaited(_switchLiveChannel(-1)),
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            unawaited(_switchLiveChannel(1)),
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  String get _contentId {
    final separator = _item.id.lastIndexOf('|');
    return separator < 0
        ? _item.id
        : _item.id.substring(separator + 1);
  }

  String? get _displaySubtitle {
    if (!_item.isLive) return _item.subtitle;
    final id = _contentId.replaceFirst('live:', '');
    for (final channel in widget.controller.channels) {
      if (channel.id == id) {
        return widget.controller.nowProgram(channel)?.title ??
            _item.subtitle;
      }
    }
    return _item.subtitle;
  }

  @override
  void dispose() {
    final position = _player.state.position;
    final duration = _player.state.duration;
    unawaited(
      widget.controller.recordPlayback(
        _item,
        position: position,
        duration: duration,
      ),
    );
    _reconnectTimer?.cancel();
    _geometrySaveTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    if (Platform.isWindows) windowManager.removeListener(this);
    unawaited(_restoreWindow());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _miniMode && Platform.isWindows
        ? (_miniLayout == MiniPlayerLayout.detailed
            ? _buildDetailedMiniPlayer()
            : _buildVideoOnlyMiniPlayer())
        : _buildFullPlayer();
    return _withKeyboardShortcuts(child);
  }

  Widget _buildFullPlayer() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final favorite = widget.controller.isFavorite(_item);
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: DragToMoveArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_displaySubtitle != null)
                    Text(
                      _displaySubtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            actions: [
              if (_item.isLive)
                IconButton(
                  tooltip: 'Previous channel (Page Up)',
                  onPressed: () => _switchLiveChannel(-1),
                  icon: const Icon(Icons.skip_previous),
                ),
              if (_item.isLive)
                IconButton(
                  tooltip: 'Next channel (Page Down)',
                  onPressed: () => _switchLiveChannel(1),
                  icon: const Icon(Icons.skip_next),
                ),
              PopupMenuButton<_VideoDisplayMode>(
                tooltip: 'Aspect ratio / fit (A)',
                initialValue: _displayMode,
                onSelected: (value) => setState(() => _displayMode = value),
                itemBuilder: (context) => [
                  for (final value in _VideoDisplayMode.values)
                    PopupMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                ],
                icon: const Icon(Icons.aspect_ratio),
              ),
              IconButton(
                tooltip: 'Audio and subtitles',
                onPressed: _showTrackPicker,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip:
                    favorite ? 'Remove from favorites' : 'Add to favorites',
                onPressed: () =>
                    widget.controller.toggleFavorite(_item),
                icon: Icon(
                  favorite ? Icons.favorite : Icons.favorite_border,
                ),
              ),
              if (Platform.isWindows)
                IconButton(
                  tooltip: 'Always-on-top mini player',
                  onPressed: _toggleMiniPlayer,
                  icon: const Icon(Icons.picture_in_picture_alt),
                ),
              const SizedBox(width: 4),
              const DesktopWindowControls(compact: true),
              const SizedBox(width: 4),
            ],
          ),
          body: Center(child: _buildVideo(useBuiltInControls: true)),
        );
      },
    );
  }

  Widget _buildDetailedMiniPlayer() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              color: const Color(0xFF0D121B),
              child: Row(
                children: [
                  Expanded(
                    child: DragToMoveArea(
                      child: SizedBox.expand(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (_displaySubtitle != null)
                              Text(
                                _displaySubtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Video only',
                    onPressed: _toggleMiniLayout,
                    icon: const Icon(Icons.crop_free),
                  ),
                  IconButton(
                    tooltip: 'Restore full player',
                    onPressed: _toggleMiniPlayer,
                    icon: const Icon(Icons.open_in_full),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildVideo(useBuiltInControls: false)),
            _MiniControls(
              playing: _playing,
              position: _position,
              duration: _duration,
              volume: _volume,
              onPlayPause: _player.playOrPause,
              onSeek: _seekFromSlider,
              onVolume: _player.setVolume,
              onTracks: _showTrackPicker,
              onSwitchLayout: _toggleMiniLayout,
              onRestore: _toggleMiniPlayer,
              detailed: true,
              isLive: _item.isLive,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoOnlyMiniPlayer() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onEnter: (_) => setState(() => _hoveringVideoOnly = true),
        onExit: (_) => setState(() => _hoveringVideoOnly = false),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideo(useBuiltInControls: false, forceFill: true),
            IgnorePointer(
              ignoring: !_hoveringVideoOnly,
              child: AnimatedOpacity(
                opacity: _hoveringVideoOnly ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x00000000),
                        Color(0xCC000000),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 6, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: DragToMoveArea(
                                child: Text(
                                _item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 5,
                                      color: Colors.black,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ),
                            IconButton(
                              tooltip: 'Show details',
                              onPressed: _toggleMiniLayout,
                              icon: const Icon(Icons.view_agenda_outlined),
                            ),
                            IconButton(
                              tooltip: 'Restore full player',
                              onPressed: _toggleMiniPlayer,
                              icon: const Icon(Icons.open_in_full),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _MiniControls(
                        playing: _playing,
                        position: _position,
                        duration: _duration,
                        volume: _volume,
                        onPlayPause: _player.playOrPause,
                        onSeek: _seekFromSlider,
                        onVolume: _player.setVolume,
                        onTracks: _showTrackPicker,
                        onSwitchLayout: _toggleMiniLayout,
                        onRestore: _toggleMiniPlayer,
                        detailed: false,
                        isLive: _item.isLive,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideo({
    required bool useBuiltInControls,
    bool forceFill = false,
  }) {
    final mode = forceFill ? _VideoDisplayMode.fill : _displayMode;
    final aspectRatio = switch (mode) {
      _VideoDisplayMode.auto => null,
      _VideoDisplayMode.wide => 16 / 9,
      _VideoDisplayMode.standard => 4 / 3,
      _VideoDisplayMode.fill => null,
    };
    final fit = mode == _VideoDisplayMode.fill ? BoxFit.cover : BoxFit.contain;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Video(
            controller: _videoController,
            fit: fit,
            aspectRatio: aspectRatio,
            controls:
                useBuiltInControls ? AdaptiveVideoControls : NoVideoControls,
          ),
        ),
        if (_buffering && _playbackError == null)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x55000000),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        if (_showIntroSkip)
          Positioned(
            right: 28,
            bottom: 96,
            child: FilledButton.icon(
              onPressed: () {
                _introAutoSkipped = true;
                unawaited(_player.seek(_introSkipTarget));
              },
              icon: const Icon(Icons.fast_forward_rounded),
              label: const Text('Skip Intro'),
            ),
          ),
        if (_showCreditsSkip)
          Positioned(
            right: 28,
            bottom: 96,
            child: FilledButton.icon(
              onPressed: () {
                _creditsAutoHandled = true;
                if (_hasNextEpisode) {
                  unawaited(_playNextEpisode());
                } else {
                  unawaited(
                    _player.seek(
                      _duration - const Duration(seconds: 1),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.skip_next_rounded),
              label: Text(
                _hasNextEpisode ? 'Skip Credits' : 'End credits',
              ),
            ),
          ),
        if (_nextEpisodeCountdown != null)
          Positioned(
            right: 28,
            bottom: 96,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xEE0D121B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.skip_next_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Next episode in $_nextEpisodeCountdown…',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelNextEpisode,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        if (_playbackError != null)
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'Playback problem',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _reconnecting
                      ? 'Reconnecting automatically… attempt $_reconnectAttempts of 3'
                      : _playbackError!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _retry(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry stream'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniControls extends StatelessWidget {
  const _MiniControls({
    required this.playing,
    required this.position,
    required this.duration,
    required this.volume,
    required this.onPlayPause,
    required this.onSeek,
    required this.onVolume,
    required this.onTracks,
    required this.onSwitchLayout,
    required this.onRestore,
    required this.detailed,
    required this.isLive,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final Future<void> Function() onPlayPause;
  final Future<void> Function(double) onSeek;
  final Future<void> Function(double) onVolume;
  final Future<void> Function() onTracks;
  final Future<void> Function() onSwitchLayout;
  final Future<void> Function() onRestore;
  final bool detailed;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final canSeek = !isLive && duration.inMilliseconds > 0;
    final maxPosition =
        canSeek ? duration.inMilliseconds.toDouble() : 1.0;
    final currentPosition = canSeek
        ? position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble()
        : 0.0;

    return Container(
      color: detailed ? const Color(0xFF0D121B) : Colors.black54,
      padding: EdgeInsets.fromLTRB(10, detailed ? 8 : 4, 8, detailed ? 8 : 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canSeek)
            Slider(
              value: currentPosition,
              max: maxPosition,
              onChanged: onSeek,
            ),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: onPlayPause,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              if (canSeek)
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              const Spacer(),
              const Icon(Icons.volume_up_outlined, size: 18),
              SizedBox(
                width: detailed ? 92 : 70,
                child: Slider(
                  value: volume.clamp(0, 100),
                  min: 0,
                  max: 100,
                  onChanged: onVolume,
                ),
              ),
              if (detailed)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Audio and subtitles',
                  onPressed: onTracks,
                  icon: const Icon(Icons.tune, size: 20),
                ),
              if (detailed)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Video only',
                  onPressed: onSwitchLayout,
                  icon: const Icon(Icons.crop_free, size: 20),
                ),
              if (!detailed)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Show details',
                  onPressed: onSwitchLayout,
                  icon: const Icon(Icons.view_agenda_outlined, size: 20),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Restore full player',
                onPressed: onRestore,
                icon: const Icon(Icons.open_in_full, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AudioTrackTile extends StatelessWidget {
  const _AudioTrackTile({
    required this.track,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final AudioTrack track;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: Text(_audioLabel(track, index)),
      subtitle: track.codec?.isNotEmpty == true ? Text(track.codec!) : null,
      onTap: onTap,
    );
  }
}

class _SubtitleTrackTile extends StatelessWidget {
  const _SubtitleTrackTile({
    required this.track,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final SubtitleTrack track;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: Text(_subtitleLabel(track, index)),
      onTap: onTap,
    );
  }
}

String _audioLabel(AudioTrack track, int index) {
  if (track.id == 'auto') return 'Automatic';
  if (track.id == 'no') return 'Audio off';
  final parts = [track.title, track.language]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? 'Audio track ${index + 1}' : parts.join(' • ');
}

String _subtitleLabel(SubtitleTrack track, int index) {
  if (track.id == 'auto') return 'Automatic';
  if (track.id == 'no') return 'Off';
  final parts = [track.title, track.language]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? 'Subtitle track ${index + 1}' : parts.join(' • ');
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


enum _VideoDisplayMode {
  auto('Auto fit'),
  wide('16:9'),
  standard('4:3'),
  fill('Fill / crop');

  const _VideoDisplayMode(this.label);
  final String label;
}
