import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:native_picture_in_picture/native_picture_in_picture.dart';
import 'package:native_picture_in_picture/pip_event.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/playback_item.dart';
import '../../services/mini_player_preferences.dart';
import '../../services/playback_preferences.dart';
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

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  static const _normalMinimumSize = Size(900, 600);
  static const _detailedMiniSize = Size(620, 420);
  static const _detailedMiniMinimumSize = Size(460, 310);
  static const _videoOnlyMiniSize = Size(520, 300);
  static const _videoOnlyMiniMinimumSize = Size(320, 180);

  late PlaybackItem _item;
  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  DateTime _lastPositionRebuild = DateTime.fromMillisecondsSinceEpoch(0);
  static const MethodChannel _iosPipChannel =
      MethodChannel('sb_player/media_kit_pip');
  static const MethodChannel _androidPipChannel =
      MethodChannel('sb_player/android_pip');

  final MiniPlayerPreferences _miniPreferences = const MiniPlayerPreferences();
  final PlaybackPreferences _playbackPreferences = const PlaybackPreferences();
  NativePictureInPicture? _nativePip;
  StreamSubscription<PipEvent>? _pipSubscription;
  bool _pipReady = false;
  bool _pipPreparing = false;
  String? _pipError;
  Timer? _checkpointTimer;
  Duration _lastCheckpointPosition = Duration.zero;

  bool _disposing = false;
  bool _miniMode = false;
  bool _buffering = true;
  bool _playing = false;
  bool _hoveringVideoOnly = false;
  bool _reconnecting = false;
  double _volume = 100;
  double _lastNonZeroVolume = 100;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _playbackError;
  Size? _previousWindowSize;
  Offset? _previousWindowPosition;
  Tracks _tracks = const Tracks();
  Track _selectedTracks = const Track();
  MiniPlayerLayout _miniLayout = MiniPlayerLayout.detailed;
  _VideoDisplayMode _displayMode = _VideoDisplayMode.auto;
  bool _autoPipEnabled = true;
  SubtitlePreference _subtitlePreference = const SubtitlePreference.auto();
  bool _subtitlePreferenceApplied = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _player = Player();
    _videoController = VideoController(_player);
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isIOS) {
      _iosPipChannel.setMethodCallHandler(_handleIosPipMethodCall);
    }
    _checkpointTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_checkpointPlayback()),
    );
    _subscriptions.add(_player.stream.buffering.listen((value) {
      if (_disposing) return;
      if (mounted) setState(() => _buffering = value);
    }));
    _subscriptions.add(_player.stream.error.listen((value) {
      if (_disposing || value.trim().isEmpty) return;
      _handlePlaybackFailure();
    }));
    _subscriptions.add(_player.stream.completed.listen((value) {
      if (_disposing || !value) return;
      if (_item.isLive) {
        _handlePlaybackFailure();
        return;
      }
      final next = _item.next;
      if (next != null) unawaited(_playNext(next));
    }));
    _subscriptions.add(_player.stream.tracks.listen((value) {
      if (mounted) setState(() => _tracks = value);
      unawaited(_applySubtitlePreference());
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
      _position = value;
      if (!mounted) return;
      final now = DateTime.now();
      if (now.difference(_lastPositionRebuild) >=
          const Duration(milliseconds: 250)) {
        _lastPositionRebuild = now;
        setState(() {});
      }
    }));
    _subscriptions.add(_player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    }));
    _subscriptions.add(_player.stream.volume.listen((value) {
      if (value > 0) _lastNonZeroVolume = value;
      if (mounted) setState(() => _volume = value);
    }));

    unawaited(_loadMiniPreference());
    unawaited(_loadPlaybackPreferences());
    unawaited(_open());
    // Android PiP now uses the existing Flutter/media_kit surface through
    // Activity Picture-in-Picture. Do not initialize a second player/stream.
  }

  Future<void> _prepareNativePip() async {
    if (_pipPreparing) return;
    if (mounted) {
      setState(() {
        _pipPreparing = true;
        _pipError = null;
      });
    }

    final pip = NativePictureInPicture();
    try {
      final supported = await pip.isPipSupported();
      if (!supported) {
        if (mounted) {
          setState(() {
            _pipPreparing = false;
            _pipReady = false;
            _pipError = 'Picture-in-Picture is not supported on this device.';
          });
        }
        await pip.dispose();
        return;
      }

      await pip.initialize(_item.streamUrl);
      await pip.setAutoPipEnabled(_autoPipEnabled);

      await _pipSubscription?.cancel();
      _pipSubscription = pip.onPipEvent.listen((event) async {
        if (event == PipEvent.willStart) {
          await pip.seekTo(_player.state.position);
          if (_player.state.playing) await pip.play();
          await _player.pause();
        } else if (event == PipEvent.restoreUI || event == PipEvent.didStop) {
          final position = await pip.getPosition();
          await pip.pause();
          if (!_item.isLive) await _player.seek(position);
          await _player.play();
        }
      });

      await _nativePip?.dispose();
      _nativePip = pip;
      if (mounted) {
        setState(() {
          _pipPreparing = false;
          _pipReady = true;
          _pipError = null;
        });
      }
    } catch (error) {
      await pip.dispose();
      if (mounted) {
        setState(() {
          _pipPreparing = false;
          _pipReady = false;
          _pipError = error.toString();
        });
      }
    }
  }

  Future<void> _startNativePip() async {
    if (Platform.isIOS) {
      await _startIosNativePip();
      return;
    }

    if (Platform.isAndroid) {
      try {
        final supported =
            await _androidPipChannel.invokeMethod<bool>('isSupported') ?? false;
        if (!supported) {
          throw StateError('Picture-in-Picture is not supported on this device.');
        }
        final started =
            await _androidPipChannel.invokeMethod<bool>('startPiP') ?? false;
        if (!started) {
          throw StateError('Android rejected the Picture-in-Picture request.');
        }
        if (mounted) {
          setState(() {
            _pipReady = true;
            _pipError = null;
          });
        }
      } catch (error) {
        // Fallback for older Android hosts: use the legacy plugin only when
        // Activity PiP is unavailable. The normal v0.6.8 path never opens a
        // second provider stream.
        try {
          await _prepareNativePip();
          final fallback = _nativePip;
          if (_pipReady && fallback != null) {
            await fallback.seekTo(_player.state.position);
            if (_player.state.playing) await fallback.play();
            await fallback.startPiP();
            return;
          }
        } catch (_) {
          // Surface the primary native PiP failure below.
        }
        if (mounted) {
          setState(() => _pipError = error.toString());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start Picture-in-Picture: $error')),
          );
        }
      }
    }
  }

  Future<void> _startIosNativePip() async {
    if (_pipPreparing) return;
    if (mounted) {
      setState(() {
        _pipPreparing = true;
        _pipError = null;
      });
    }

    try {
      final supported =
          await _iosPipChannel.invokeMethod<bool>('SBPlayerPiP.IsSupported') ??
              false;
      if (!supported) {
        throw StateError(
          'Picture-in-Picture is not available on this iPhone/iOS version.',
        );
      }

      final handle = await _player.handle;
      final accepted = await _iosPipChannel.invokeMethod<bool>(
            'SBPlayerPiP.Start',
            <String, dynamic>{'handle': handle.toString()},
          ) ??
          false;
      if (!accepted) {
        throw StateError('The active video surface could not enter PiP.');
      }

      if (mounted) {
        setState(() {
          _pipPreparing = false;
          _pipReady = true;
          _pipError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _pipPreparing = false;
          _pipReady = false;
          _pipError = error.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Picture-in-Picture unavailable: $error')),
        );
      }
    }
  }

  Future<dynamic> _handleIosPipMethodCall(MethodCall call) async {
    if (call.method != 'SBPlayerPiP.Event') return null;
    final raw = call.arguments;
    if (raw is! Map) return null;
    final event = '${raw['event'] ?? ''}';

    switch (event) {
      case 'setPlaying':
        final shouldPlay = raw['value'] == true;
        if (shouldPlay) {
          await _player.play();
        } else {
          await _player.pause();
        }
        break;
      case 'skip':
        final seconds = (raw['value'] as num?)?.round() ?? 0;
        if (seconds != 0) await _seekRelative(seconds);
        break;
      case 'didStart':
        if (mounted) {
          setState(() {
            _pipPreparing = false;
            _pipReady = true;
            _pipError = null;
          });
        }
        break;
      case 'didStop':
      case 'restore':
        if (mounted) setState(() => _pipReady = false);
        unawaited(_checkpointPlayback(force: true));
        break;
      case 'failed':
        final message = '${raw['value'] ?? 'Picture-in-Picture failed.'}';
        if (mounted) {
          setState(() {
            _pipPreparing = false;
            _pipReady = false;
            _pipError = message;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Picture-in-Picture failed: $message')),
          );
        }
        break;
    }
    return null;
  }

  Future<void> _checkpointPlayback({bool force = false}) async {
    if (_item.isLive || _duration.inSeconds <= 0 || _position.inSeconds <= 1) {
      return;
    }
    if (!force &&
        (_position - _lastCheckpointPosition).abs() <
            const Duration(seconds: 5)) {
      return;
    }
    _lastCheckpointPosition = _position;
    await widget.controller.recordPlayback(
      _item,
      position: _position,
      duration: _duration,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_checkpointPlayback(force: true));
    }

    if (Platform.isIOS &&
        _autoPipEnabled &&
        _playing &&
        state == AppLifecycleState.inactive) {
      unawaited(_startIosNativePip());
    }
  }

  Future<void> _loadPlaybackPreferences() async {
    final autoPip = await _playbackPreferences.readAutoPip();
    final subtitlePreference =
        await _playbackPreferences.readSubtitlePreference();
    _autoPipEnabled = autoPip;
    _subtitlePreference = subtitlePreference;
    _subtitlePreferenceApplied = false;
    if (Platform.isAndroid) {
      try {
        await _androidPipChannel.invokeMethod<void>('setAutoPip', autoPip);
      } catch (_) {
        // Older Android builds can ignore this until the next app update.
      }
    }
    await _applySubtitlePreference();
  }

  Future<void> _loadMiniPreference() async {
    final layout = await _miniPreferences.readLayout();
    if (mounted) setState(() => _miniLayout = layout);
  }

  Future<void> _open({Duration? resumeAt}) async {
    if (mounted) {
      setState(() {
        _playbackError = null;
        _buffering = true;
      });
    }

    try {
      final target = resumeAt ?? _item.startPosition;
      final shouldResume =
          !_item.isLive && target > const Duration(seconds: 5);

      // On iOS, some IPTV VOD sources ignore a seek issued immediately after
      // open(play: true). Open paused, wait until metadata is available, seek,
      // verify the position, and only then start playback.
      await _player.open(
        Media(
          _item.streamUrl,
          start: shouldResume ? target : null,
        ),
        play: !shouldResume,
      );

      if (shouldResume) {
        // media_kit can pass the resume point to mpv before demux starts. Keep
        // the explicit seek loop as a fallback for IPTV origins that ignore it.
        if (_player.state.position < target - const Duration(seconds: 3)) {
          await _seekToResumePoint(target);
        }
        await _player.play();

        // A few providers only become fully seekable after playback begins.
        // Correct once more if the first decoded frame still came from 0.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (_player.state.position < target - const Duration(seconds: 3)) {
          await _player.seek(target);
        }
      }
      _subtitlePreferenceApplied = false;
      await _applySubtitlePreference();
    } catch (_) {
      _handlePlaybackFailure();
    }
  }

  Future<void> _seekToResumePoint(Duration requested) async {
    var target = requested;
    var knownDuration = _player.state.duration;

    if (knownDuration.inSeconds <= 0) {
      try {
        knownDuration = await _player.stream.duration
            .firstWhere((value) => value.inSeconds > 0)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Some providers report duration late. Still try the saved seek point.
      }
    }

    if (knownDuration > const Duration(seconds: 1) &&
        target >= knownDuration) {
      target = knownDuration - const Duration(seconds: 1);
    }

    for (var attempt = 0; attempt < 4; attempt++) {
      await _player.seek(target);
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 250 : 450),
      );
      if (_player.state.position >= target - const Duration(seconds: 3)) {
        return;
      }
    }
  }

  Future<void> _playNext(PlaybackItem next) async {
    if (_disposing) return;
    await widget.controller.recordPlayback(
      _item,
      position: _duration,
      duration: _duration,
    );
    if (!mounted) return;
    setState(() {
      _item = next;
      _position = Duration.zero;
      _duration = Duration.zero;
      _lastCheckpointPosition = Duration.zero;
      _subtitlePreferenceApplied = false;
      _playbackError = null;
    });
    await _nativePip?.dispose();
    _nativePip = null;
    _pipReady = false;
    await _open();
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
    if (_disposing || !mounted) return;
    setState(() {
      _playbackError = _item.isLive
          ? 'The live stream was interrupted.'
          : 'Playback stopped unexpectedly.';
    });
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= 5 || _reconnectTimer?.isActive == true) return;
    const delays = <int>[1, 2, 4, 8, 12];
    final delaySeconds = delays[_reconnectAttempts.clamp(0, delays.length - 1).toInt()];
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
      if (!mounted) return;
      // Switch Flutter to the compact layout before changing native geometry.
      // Avoid animated native resizing: every animation frame forces the video
      // texture to resize and was causing a large playback/UI stall.
      setState(() => _miniMode = true);
      await windowManager.setAlwaysOnTop(true);
      await _applyMiniChrome();
      await _applyMiniWindowSize();
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
    if (!mounted) return;
    setState(() {
      _miniLayout = next;
      _hoveringVideoOnly = false;
    });
    await _miniPreferences.saveLayout(next);
    if (!mounted || !_miniMode) return;
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
    await windowManager.setSize(size, animate: false);
    if (saved != null) {
      await windowManager.setPosition(saved.position, animate: false);
    }
  }

  Future<void> _applyMiniChrome() async {
    if (!Platform.isWindows) return;
    await windowManager.setTitleBarStyle(
      _miniLayout == MiniPlayerLayout.videoOnly
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: _miniLayout != MiniPlayerLayout.videoOnly,
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
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(_normalMinimumSize);
    if (_previousWindowSize != null) {
      await windowManager.setSize(_previousWindowSize!, animate: false);
    }
    if (_previousWindowPosition != null) {
      await windowManager.setPosition(_previousWindowPosition!, animate: false);
    }
  }

  Future<void> _applySubtitlePreference() async {
    if (_subtitlePreferenceApplied) return;
    final preference = _subtitlePreference;

    try {
      if (preference.isOff) {
        await _player.setSubtitleTrack(SubtitleTrack.no());
        _subtitlePreferenceApplied = true;
        return;
      }

      if (preference.isAuto) {
        await _player.setSubtitleTrack(SubtitleTrack.auto());
        _subtitlePreferenceApplied = true;
        return;
      }

      for (final track in _item.externalSubtitles) {
        if (!preference.matches(
          language: track.language,
          title: track.title,
        )) {
          continue;
        }
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            track.url,
            title: track.title,
            language: track.language,
          ),
        );
        _subtitlePreferenceApplied = true;
        return;
      }

      for (final track in _tracks.subtitle) {
        if (track.id == 'auto' || track.id == 'no') continue;
        if (!preference.matches(
          language: track.language,
          title: track.title,
        )) {
          continue;
        }
        await _player.setSubtitleTrack(track);
        _subtitlePreferenceApplied = true;
        return;
      }
    } catch (_) {
      // Track discovery can race stream startup. The tracks listener retries.
    }
  }

  Future<void> _rememberSubtitleOff() async {
    _subtitlePreference = const SubtitlePreference.off();
    _subtitlePreferenceApplied = true;
    await _playbackPreferences.saveSubtitleOff();
  }

  Future<void> _rememberSubtitleTrack({
    String? language,
    String? title,
  }) async {
    _subtitlePreference =
        SubtitlePreference.match(language: language, title: title);
    _subtitlePreferenceApplied = true;
    await _playbackPreferences.saveSubtitleMatch(
      language: language,
      title: title,
    );
  }

  Future<void> _showSubtitlePicker() async {
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
                Text('Subtitles', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                ListTile(
                  leading: const Icon(Icons.subtitles_off_outlined),
                  title: const Text('Off'),
                  selected: _selectedTracks.subtitle.id == 'no',
                  onTap: () async {
                    await _player.setSubtitleTrack(SubtitleTrack.no());
                    await _rememberSubtitleOff();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
                if (_tracks.subtitle.isEmpty &&
                    _item.externalSubtitles.isEmpty)
                  const ListTile(
                    title: Text('No subtitle tracks were supplied with this stream.'),
                  ),
                for (var i = 0; i < _item.externalSubtitles.length; i++)
                  ListTile(
                    leading: const Icon(Icons.closed_caption_rounded),
                    title: Text(
                      _item.externalSubtitles[i].title ??
                          _item.externalSubtitles[i].language ??
                          'Subtitle ${i + 1}',
                    ),
                    subtitle: const Text('Provider subtitle'),
                    onTap: () async {
                      final track = _item.externalSubtitles[i];
                      await _player.setSubtitleTrack(
                        SubtitleTrack.uri(
                          track.url,
                          title: track.title,
                          language: track.language,
                        ),
                      );
                      await _rememberSubtitleTrack(
                        language: track.language,
                        title: track.title,
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                if (_tracks.subtitle.isNotEmpty)
                  for (var i = 0; i < _tracks.subtitle.length; i++)
                    _SubtitleTrackTile(
                      track: _tracks.subtitle[i],
                      index: i,
                      selected:
                          _tracks.subtitle[i].id == _selectedTracks.subtitle.id,
                      onTap: () async {
                        final track = _tracks.subtitle[i];
                        await _player.setSubtitleTrack(track);
                        if (track.id == 'no') {
                          await _rememberSubtitleOff();
                        } else if (track.id == 'auto') {
                          _subtitlePreference =
                              const SubtitlePreference.auto();
                          _subtitlePreferenceApplied = true;
                          await _playbackPreferences.saveSubtitleAuto();
                        } else {
                          await _rememberSubtitleTrack(
                            language: track.language,
                            title: track.title,
                          );
                        }
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
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCastOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cast_connected_rounded),
                title: const Text('SB Player TV'),
                subtitle: const Text(
                  'Use the linked-TV remote for the full SB Player TV experience.',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Open TV Remote from Settings to control your linked SB Player TV.',
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Platform.isIOS
                      ? Icons.airplay_rounded
                      : Icons.cast_rounded,
                ),
                title: Text(
                  Platform.isIOS ? 'AirPlay / Screen Mirroring' : 'Cast / Screen share',
                ),
                subtitle: const Text(
                  'Use your phone’s system casting controls for TVs without SB Player installed.',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'System casting is available from your phone’s device controls. Native in-app receiver discovery is coming next.',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
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
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _checkpointTimer?.cancel();
    _reconnectTimer?.cancel();

    // Use the last values emitted by media_kit instead of Player.state here.
    // Native teardown can zero Player.state before dispose runs on iOS.
    if (!_item.isLive && _duration.inSeconds > 0 && _position.inSeconds > 0) {
      unawaited(
        widget.controller.recordPlayback(
          _item,
          position: _position,
          duration: _duration,
        ),
      );
    }

    if (Platform.isIOS) {
      _iosPipChannel.setMethodCallHandler(null);
      unawaited(_iosPipChannel.invokeMethod<void>('SBPlayerPiP.Stop').catchError((_) {}));
    }
    unawaited(_restoreWindow());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_pipSubscription?.cancel());
    unawaited(_nativePip?.dispose());
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
            title: Column(
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
            actions: [
              if (Platform.isIOS || Platform.isAndroid)
                IconButton(
                  tooltip: _pipPreparing
                      ? 'Preparing Picture-in-Picture…'
                      : (_pipError == null
                          ? 'Picture-in-Picture'
                          : 'Retry Picture-in-Picture'),
                  onPressed: _pipPreparing ? null : _startNativePip,
                  icon: Icon(
                    _pipError == null
                        ? Icons.picture_in_picture_alt
                        : Icons.refresh,
                  ),
                ),
              if (Platform.isIOS || Platform.isAndroid)
                IconButton(
                  tooltip: 'Cast / mirror to TV',
                  onPressed: _showCastOptions,
                  icon: const Icon(Icons.cast_rounded),
                ),
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
                tooltip: 'Subtitles',
                onPressed: _showSubtitlePicker,
                icon: Icon(
                  _tracks.subtitle.isEmpty && _item.externalSubtitles.isEmpty
                      ? Icons.closed_caption_disabled_outlined
                      : Icons.closed_caption_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Audio tracks',
                onPressed: _showTrackPicker,
                icon: const Icon(Icons.graphic_eq_rounded),
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
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            minimum: const EdgeInsets.only(bottom: 8),
            child: Center(child: _buildVideo(useBuiltInControls: true)),
          ),
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
                          _item.title,
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
            // Keep the entire video surface draggable in borderless mini mode.
            // Controls rendered above this layer still receive their own clicks.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => unawaited(windowManager.startDragging()),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
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
                      ? 'Reconnecting automatically… attempt $_reconnectAttempts of 5'
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
