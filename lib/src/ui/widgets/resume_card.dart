import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/library_entry.dart';
import '../branding/sb_brand.dart';
import 'brand_backdrop.dart';

/// Shared resume card used by Home and Continue Watching.
///
/// On pointer devices a short hover starts a muted preview at the exact saved
/// playback position. Touch devices simply keep the normal tap-to-resume card.
class ResumeCard extends StatefulWidget {
  const ResumeCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;

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
    setState(() => _hovered = true);
    if (widget.entry.kind.name == 'live') return;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 550), _startPreview);
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
        scale: _hovered ? 1.018 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_previewVisible && _previewController != null)
                  Video(
                    controller: _previewController!,
                    controls: NoVideoControls,
                    fit: BoxFit.cover,
                  )
                else if (entry.artworkUrl != null)
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
                        SbBrand.black.withValues(alpha: .9),
                      ],
                      stops: const [.18, 1],
                    ),
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
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 30),
                      ),
                    ),
                  ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 13,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: entry.title,
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (_hovered && entry.positionSeconds > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          remaining > 0
                              ? 'Resume at ${_time(entry.positionSeconds)} • ${_time(remaining)} left'
                              : 'Resume at ${_time(entry.positionSeconds)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SbBrand.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ] else if (entry.subtitle?.isNotEmpty == true) ...[
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
                            value: entry.progress.clamp(0.0, 1.0),
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
