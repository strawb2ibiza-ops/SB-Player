import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/library_entry.dart';
import '../../models/playback_item.dart';
import '../branding/sb_brand.dart';
import 'brand_backdrop.dart';
import 'provider_image.dart';

/// Compact resume card used by Home and Continue Watching.
///
/// Desktop hover starts a muted preview inside the thumbnail only, so the
/// surrounding layout stays stable and avoids rebuilding the whole card.
class ResumeCard extends StatefulWidget {
  const ResumeCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.favorite = false,
    this.onFavorite,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;
  final bool favorite;
  final VoidCallback? onFavorite;

  @override
  State<ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<ResumeCard> {
  Timer? _hoverTimer;
  Player? _previewPlayer;
  VideoController? _previewController;
  bool _hovered = false;
  bool _previewVisible = false;
  int _previewGeneration = 0;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    final player = _previewPlayer;
    _previewPlayer = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  void _onEnter(PointerEnterEvent _) {
    if (!_hovered) setState(() => _hovered = true);
    if (widget.entry.kind == PlaybackKind.live) return;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 650), _startPreview);
  }

  void _onExit(PointerExitEvent _) {
    _hoverTimer?.cancel();
    _previewGeneration++;
    final player = _previewPlayer;
    _previewPlayer = null;
    _previewController = null;
    if (mounted) {
      setState(() {
        _hovered = false;
        _previewVisible = false;
      });
    }
    if (player != null) unawaited(player.dispose());
  }

  Future<void> _startPreview() async {
    if (!mounted || !_hovered || _previewPlayer != null) return;
    final generation = ++_previewGeneration;
    final player = Player();
    final controller = VideoController(player);
    _previewPlayer = player;
    _previewController = controller;

    try {
      await player.setVolume(0);
      await player.open(Media(widget.entry.streamUrl), play: true);
      if (widget.entry.positionSeconds > 0) {
        await player.seek(Duration(seconds: widget.entry.positionSeconds));
      }
      if (!mounted || !_hovered || generation != _previewGeneration) {
        await player.dispose();
        return;
      }
      setState(() => _previewVisible = true);
    } catch (_) {
      if (identical(_previewPlayer, player)) {
        _previewPlayer = null;
        _previewController = null;
      }
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final remaining = entry.durationSeconds > entry.positionSeconds
        ? entry.durationSeconds - entry.positionSeconds
        : 0;

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: AnimatedScale(
        scale: _hovered ? 1.01 : 1,
        duration: const Duration(milliseconds: 140),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onFocusChange: (focused) {
              if (!focused) return;
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: 0.5,
              );
            },
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_previewVisible && _previewController != null)
                            Video(
                              controller: _previewController!,
                              controls: NoVideoControls,
                              fit: BoxFit.cover,
                            )
                          else
                            ProviderImage(
                              url: entry.artworkUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 320,
                              cacheHeight: 240,
                              fallback: const BrandBackdrop(
                                child: SizedBox.expand(),
                              ),
                            ),
                          if (_hovered && !_previewVisible)
                            const Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xB8040509),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 25,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: entry.title,
                          waitDuration: const Duration(milliseconds: 350),
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: SbBrand.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Tooltip(
                          message: entry.subtitle?.isNotEmpty == true
                              ? entry.subtitle!
                              : entry.title,
                          child: Text(
                            _hovered && entry.positionSeconds > 0
                                ? (remaining > 0
                                    ? 'Resume at ${_time(entry.positionSeconds)} • ${_time(remaining)} left'
                                    : 'Resume at ${_time(entry.positionSeconds)}')
                                : (entry.subtitle?.isNotEmpty == true
                                    ? entry.subtitle!
                                    : 'Continue watching'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (entry.durationSeconds > 0) ...[
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: entry.progress.clamp(0.0, 1.0),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onFavorite != null)
                    IconButton(
                      tooltip: widget.favorite
                          ? 'Remove favorite'
                          : 'Add favorite',
                      onPressed: widget.onFavorite,
                      icon: Icon(
                        widget.favorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: widget.favorite
                            ? SbBrand.liveError
                            : SbBrand.textMuted,
                      ),
                    ),
                  Icon(
                    Icons.play_circle_fill_rounded,
                    color: _hovered
                        ? SbBrand.brightBlue
                        : SbBrand.electricBlue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _time(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
