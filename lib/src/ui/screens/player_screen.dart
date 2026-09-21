import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/playback_item.dart';
import '../../services/mini_player_preferences.dart';
import '../../state/app_controller.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.item,
  });

  final AppController controller;
  final PlaybackItem item;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _normalMinimumSize = Size(900, 600);
  static const _detailedMiniSize = Size(620, 420);
  static const _detailedMiniMinimumSize = Size(460, 310);
  static const _videoOnlyMiniSize = Size(520, 300);
  static const _videoOnlyMiniMinimumSize = Size(320, 180);

  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final MiniPlayerPreferences _miniPreferences = const MiniPlayerPreferences();

  bool _miniMode = false;
  bool _buffering = true;
  bool _playing = false;
  bool _hoveringVideoOnly = false;
  double _volume = 100;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _playbackError;
  Size? _previousWindowSize;
  Tracks _tracks = const Tracks();
  Track _selectedTracks = const Track();
  MiniPlayerLayout _miniLayout = MiniPlayerLayout.detailed;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _subscriptions.add(_player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    }));
    _subscriptions.add(_player.stream.error.listen((value) {
      if (value.trim().isEmpty) return;
      if (mounted) setState(() => _playbackError = value.trim());
    }));
    _subscriptions.add(_player.stream.tracks.listen((value) {
      if (mounted) setState(() => _tracks = value);
    }));
    _subscriptions.add(_player.stream.track.listen((value) {
      if (mounted) setState(() => _selectedTracks = value);
    }));
    _subscriptions.add(_player.stream.playing.listen((value) {
      if (mounted) setState(() => _playing = value);
    }));
    _subscriptions.add(_player.stream.position.listen((value) {
      if (mounted) setState(() => _position = value);
    }));
    _subscriptions.add(_player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    }));
    _subscriptions.add(_player.stream.volume.listen((value) {
      if (mounted) setState(() => _volume = value);
    }));

    unawaited(_loadMiniPreference());
    unawaited(_open());
  }

  Future<void> _loadMiniPreference() async {
    final layout = await _miniPreferences.readLayout();
    if (mounted) setState(() => _miniLayout = layout);
  }

  Future<void> _open() async {
    if (mounted) {
      setState(() {
        _playbackError = null;
        _buffering = true;
      });
    }

    try {
      await widget.controller.recordPlayback(widget.item);
      await _player.open(Media(widget.item.streamUrl), play: true);
      if (!widget.item.isLive &&
          widget.item.startPosition > const Duration(seconds: 5)) {
        await _player.seek(widget.item.startPosition);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _playbackError = 'Could not start this stream: $error');
      }
    }
  }

  Future<void> _retry() async {
    await _player.stop();
    await _open();
  }

  Future<void> _toggleMiniPlayer() async {
    if (!Platform.isWindows) return;

    if (!_miniMode) {
      _previousWindowSize = await windowManager.getSize();
      await windowManager.setAlwaysOnTop(true);
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
    setState(() {
      _miniLayout = next;
      _hoveringVideoOnly = false;
    });
    await _miniPreferences.saveLayout(next);
    await _applyMiniWindowSize();
  }

  Future<void> _applyMiniWindowSize() async {
    if (!Platform.isWindows) return;
    final detailed = _miniLayout == MiniPlayerLayout.detailed;
    await windowManager.setMinimumSize(
      detailed ? _detailedMiniMinimumSize : _videoOnlyMiniMinimumSize,
    );
    await windowManager.setSize(
      detailed ? _detailedMiniSize : _videoOnlyMiniSize,
      animate: true,
    );
  }

  Future<void> _restoreWindow() async {
    if (!Platform.isWindows || !_miniMode) return;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(_normalMinimumSize);
    if (_previousWindowSize != null) {
      await windowManager.setSize(_previousWindowSize!, animate: true);
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

  String? get _displaySubtitle {
    if (!widget.item.isLive) return widget.item.subtitle;
    final id = widget.item.id.replaceFirst('live:', '');
    for (final channel in widget.controller.channels) {
      if (channel.id == id) {
        return widget.controller.nowProgram(channel)?.title ??
            widget.item.subtitle;
      }
    }
    return widget.item.subtitle;
  }

  @override
  void dispose() {
    final position = _player.state.position;
    final duration = _player.state.duration;
    unawaited(
      widget.controller.recordPlayback(
        widget.item,
        position: position,
        duration: duration,
      ),
    );
    unawaited(_restoreWindow());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_miniMode && Platform.isWindows) {
      return _miniLayout == MiniPlayerLayout.detailed
          ? _buildDetailedMiniPlayer()
          : _buildVideoOnlyMiniPlayer();
    }

    return _buildFullPlayer();
  }

  Widget _buildFullPlayer() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final favorite = widget.controller.isFavorite(widget.item);
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.title,
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
            actions: [
              IconButton(
                tooltip: 'Audio and subtitles',
                onPressed: _showTrackPicker,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip:
                    favorite ? 'Remove from favorites' : 'Add to favorites',
                onPressed: () =>
                    widget.controller.toggleFavorite(widget.item),
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
              const SizedBox(width: 8),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
            _buildVideo(useBuiltInControls: false, fit: BoxFit.cover),
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
                              child: Text(
                                widget.item.title,
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
    BoxFit fit = BoxFit.contain,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Video(
            controller: _videoController,
            fit: fit,
            controls: useBuiltInControls ? AdaptiveVideoControls : NoVideoControls,
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
                  _playbackError!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retry,
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

  @override
  Widget build(BuildContext context) {
    final canSeek = duration.inMilliseconds > 0;
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
