import 'package:flutter/material.dart';

import '../branding/sb_brand.dart';
import 'provider_image.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.subtitle,
    this.rating,
    this.favorite = false,
    this.onFavorite,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final double? rating;
  final VoidCallback onTap;
  final bool favorite;
  final VoidCallback? onFavorite;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.025 : 1,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              if (_hovered)
                BoxShadow(
                  color: SbBrand.electricBlue.withValues(alpha: 0.28),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: widget.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                SbBrand.panelBlue,
                                SbBrand.panel,
                              ],
                            ),
                          ),
                          child: ProviderImage(
                            url: widget.imageUrl,
                            fit: BoxFit.cover,
                            fallback: const _MissingPoster(),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.transparent,
                                    SbBrand.black.withValues(alpha: 0.68),
                                  ],
                                  stops: const [0, 0.62, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.onFavorite != null)
                          Positioned(
                            top: 7,
                            right: 7,
                            child: IconButton.filled(
                              tooltip: widget.favorite
                                  ? 'Remove favorite'
                                  : 'Add favorite',
                              onPressed: widget.onFavorite,
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    SbBrand.black.withValues(alpha: 0.72),
                                foregroundColor: widget.favorite
                                    ? SbBrand.liveError
                                    : Colors.white,
                              ),
                              icon: Icon(
                                widget.favorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 19,
                              ),
                            ),
                          ),
                        if (_hovered)
                          const Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xB8040509),
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: widget.title,
                          waitDuration: const Duration(milliseconds: 350),
                          child: Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SbBrand.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (widget.subtitle != null ||
                            widget.rating != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            [
                              if (widget.subtitle != null &&
                                  widget.subtitle!.isNotEmpty)
                                widget.subtitle!,
                              if (widget.rating != null)
                                '★ ${widget.rating!.toStringAsFixed(1)}',
                            ].join('  •  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
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
      ),
    );
  }
}

class _MissingPoster extends StatelessWidget {
  const _MissingPoster();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_outlined,
            size: 44,
            color: SbBrand.brightBlue,
          ),
          SizedBox(height: 8),
          Text(
            'SB',
            style: TextStyle(
              color: SbBrand.textMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
