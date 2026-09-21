import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/playback_item.dart';
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
  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _miniMode = false;
  bool _buffering = true;
  String? _playbackError;
  Size? _previousWindowSize;
  Tracks _tracks = const Tracks();
  Track _selectedTracks = const Track();

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
    unawaited(_open());
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
      if (!widget.item.isLive && widget.item.startPosition > const Duration(seconds: 5)) {
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
      await windowManager.setSize(const Size(560, 360));
    } else {
      await windowManager.setAlwaysOnTop(false);
      if (_previousWindowSize != null) {
        await windowManager.setSize(_previousWindowSize!);
      }
    }
    if (mounted) setState(() => _miniMode = !_miniMode);
  }

  Future<void> _restoreWindow() async {
    if (!Platform.isWindows || !_miniMode) return;
    await windowManager.setAlwaysOnTop(false);
    if (_previousWindowSize != null) {
      await windowManager.setSize(_previousWindowSize!);
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
                      selected: _tracks.subtitle[i].id == _selectedTracks.subtitle.id,
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

  @override
  void dispose() {
    final position = _player.state.position;
    final duration = _player.state.duration;
    unawaited(widget.controller.recordPlayback(
      widget.item,
      position: position,
      duration: duration,
    ));
    unawaited(_restoreWindow());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (widget.item.subtitle != null)
                  Text(
                    widget.item.subtitle!,
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
                tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
                onPressed: () => widget.controller.toggleFavorite(widget.item),
                icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
              ),
              if (Platform.isWindows)
                IconButton(
                  tooltip: _miniMode ? 'Restore window' : 'Always-on-top mini player',
                  onPressed: _toggleMiniPlayer,
                  icon: Icon(_miniMode ? Icons.close_fullscreen : Icons.picture_in_picture_alt),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Video(controller: _videoController),
                ),
                if (_buffering && _playbackError == null)
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x55000000), shape: BoxShape.circle),
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
                        const Text('Playback problem', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
            ),
          ),
        );
      },
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
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
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
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
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
