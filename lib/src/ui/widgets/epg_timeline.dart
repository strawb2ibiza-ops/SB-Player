import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/epg_program.dart';
import '../../models/iptv_channel.dart';
import '../../state/app_controller.dart';

class EpgTimeline extends StatelessWidget {
  const EpgTimeline({
    super.key,
    required this.controller,
    required this.channels,
    required this.onPlayChannel,
  });

  final AppController controller;
  final List<IptvChannel> channels;
  final ValueChanged<IptvChannel> onPlayChannel;

  static const double _channelWidth = 190;
  static const double _pixelsPerMinute = 3.6;
  static const double _rowHeight = 72;
  static const Duration _windowLength = Duration(hours: 4);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rounded = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 0 : 30,
    );
    final start = rounded.subtract(const Duration(minutes: 30));
    final end = start.add(_windowLength);
    final timelineWidth = _windowLength.inMinutes * _pixelsPerMinute;
    final totalWidth = _channelWidth + timelineWidth;
    final nowOffset =
        now.difference(start).inSeconds / 60 * _pixelsPerMinute;

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            children: [
              _TimelineHeader(
                start: start,
                width: timelineWidth,
                channelWidth: _channelWidth,
                pixelsPerMinute: _pixelsPerMinute,
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: channels.length,
                  itemExtent: _rowHeight,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    final programmes = controller.programmesForWindow(
                      channel,
                      start: start,
                      end: end,
                    );
                    return _TimelineRow(
                      channel: channel,
                      programmes: programmes,
                      start: start,
                      end: end,
                      timelineWidth: timelineWidth,
                      channelWidth: _channelWidth,
                      pixelsPerMinute: _pixelsPerMinute,
                      nowOffset: nowOffset,
                      onTap: () => onPlayChannel(channel),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.start,
    required this.width,
    required this.channelWidth,
    required this.pixelsPerMinute,
  });

  final DateTime start;
  final double width;
  final double channelWidth;
  final double pixelsPerMinute;

  @override
  Widget build(BuildContext context) {
    final slots = width ~/ (30 * pixelsPerMinute);
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          SizedBox(
            width: channelWidth,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CHANNEL',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
          SizedBox(
            width: width,
            child: Stack(
              children: [
                for (var index = 0; index <= slots; index++)
                  Positioned(
                    left: index * 30 * pixelsPerMinute,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 1,
                          height: 42,
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _formatTime(
                              start.add(Duration(minutes: index * 30)),
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.channel,
    required this.programmes,
    required this.start,
    required this.end,
    required this.timelineWidth,
    required this.channelWidth,
    required this.pixelsPerMinute,
    required this.nowOffset,
    required this.onTap,
  });

  final IptvChannel channel;
  final List<EpgProgram> programmes;
  final DateTime start;
  final DateTime end;
  final double timelineWidth;
  final double channelWidth;
  final double pixelsPerMinute;
  final double nowOffset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: channelWidth,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: channel.logoUrl == null
                          ? const Icon(Icons.live_tv_outlined)
                          : Image.network(
                              channel.logoUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.live_tv_outlined),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: timelineWidth,
            child: Stack(
              children: [
                for (final programme in programmes)
                  _programmeBlock(context, programme),
                if (programmes.isEmpty)
                  const Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No programme information',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                if (nowOffset >= 0 && nowOffset <= timelineWidth)
                  Positioned(
                    left: nowOffset,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _programmeBlock(BuildContext context, EpgProgram programme) {
    final visibleStart = programme.start.isBefore(start) ? start : programme.start;
    final visibleEnd = programme.stop.isAfter(end) ? end : programme.stop;
    final left =
        visibleStart.difference(start).inSeconds / 60 * pixelsPerMinute;
    final rawWidth =
        visibleEnd.difference(visibleStart).inSeconds / 60 * pixelsPerMinute;
    final width = math.max(4.0, rawWidth - 2);
    final live = programme.isLiveAt(DateTime.now());

    return Positioned(
      left: left,
      top: 6,
      width: width,
      bottom: 6,
      child: Tooltip(
        message: [
          programme.title,
          '${_formatTime(programme.start)}–${_formatTime(programme.stop)}',
          if (programme.description?.isNotEmpty == true) programme.description!,
        ].join('\n'),
        child: Material(
          color: live
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.28)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    programme.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (width >= 105)
                    Text(
                      '${_formatTime(programme.start)}–${_formatTime(programme.stop)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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

String _formatTime(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
