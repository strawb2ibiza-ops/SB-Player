import 'package:flutter/material.dart';

import '../../models/iptv_channel.dart';
import '../branding/sb_brand.dart';

class ChannelTile extends StatefulWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.channelNumber,
    this.nowText,
    this.nextText,
    this.nowProgress,
    this.isFavorite = false,
    this.onFavorite,
  });

  final IptvChannel channel;
  final VoidCallback onTap;
  final int? channelNumber;
  final String? nowText;
  final String? nextText;
  final double? nowProgress;
  final bool isFavorite;
  final VoidCallback? onFavorite;

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            if (_hovered)
              BoxShadow(
                color: SbBrand.electricBlue.withValues(alpha: 0.24),
                blurRadius: 22,
              ),
          ],
        ),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (widget.channelNumber != null) ...[
                    SizedBox(
                      width: 34,
                      child: Text(
                        widget.channelNumber.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SbBrand.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: SbBrand.panelBlue,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            SbBrand.electricBlue.withValues(alpha: 0.16),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.channel.logoUrl == null
                        ? const Icon(
                            Icons.live_tv_outlined,
                            color: SbBrand.brightBlue,
                          )
                        : Image.network(
                            widget.channel.logoUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.live_tv_outlined,
                              color: SbBrand.brightBlue,
                            ),
                          ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: widget.channel.name,
                                waitDuration: const Duration(milliseconds: 350),
                                child: Text(
                                  widget.channel.name,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const _LiveBadge(),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.nowText == null
                              ? 'Live channel'
                              : 'Now  •  ${widget.nowText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.nowText == null
                                ? SbBrand.textMuted
                                : SbBrand.textPrimary,
                          ),
                        ),
                        if (widget.nowProgress != null) ...[
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: widget.nowProgress!.clamp(0, 1),
                              minHeight: 3,
                              backgroundColor:
                                  SbBrand.textMuted.withValues(alpha: 0.16),
                              valueColor: const AlwaysStoppedAnimation(
                                SbBrand.electricBlue,
                              ),
                            ),
                          ),
                        ],
                        if (widget.nextText != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Next  •  ${widget.nextText}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onFavorite != null)
                    IconButton(
                      tooltip: widget.isFavorite
                          ? 'Remove favorite'
                          : 'Add favorite',
                      onPressed: widget.onFavorite,
                      icon: Icon(
                        widget.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: widget.isFavorite
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
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SbBrand.liveError.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: SbBrand.liveError.withValues(alpha: 0.46),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          'LIVE',
          style: TextStyle(
            color: SbBrand.liveError,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}
