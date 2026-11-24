import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/feed.dart';
import '../../domain/models.dart';
import '../common.dart';
import '../detail_sheet.dart';

const gridStartMin = 8 * 60;
const gridEndMin = 24 * 60;
const hourHeight = 68.0;
const gridHeight = (gridEndMin - gridStartMin) / 60 * hourHeight;

double yFor(int minutes) => (minutes - gridStartMin) / 60 * hourHeight;

/// A block to draw on a time grid: either a drop-in session or a series day.
class GridItem {
  GridItem.session(ClassSession s)
      : session = s,
        series = null,
        studioId = s.studioId,
        start = s.startMin,
        end = s.endMin;

  GridItem.series(WorkshopSeries s)
      : session = null,
        series = s,
        studioId = s.studioId,
        start = s.startMin,
        end = s.startMin + s.durationMin;

  final ClassSession? session;
  final WorkshopSeries? series;
  final StudioId studioId;
  final int start;
  final int end;

  String get title => session != null
      ? session!.title ?? getTemplate(session!.templateId).title
      : series!.title;
  ClassTemplate get template =>
      getTemplate(session?.templateId ?? series!.templateId);
}

/// Assigns overlapping items to side-by-side lanes.
/// Returns (lane, laneCount) per item, in input order.
List<(int, int)> layoutLanes(List<GridItem> items) {
  final idx = List.generate(items.length, (i) => i)
    ..sort((a, b) => items[a].start.compareTo(items[b].start));
  final result = List.filled(items.length, (0, 1));
  var cluster = <int>[];
  var laneEnds = <int>[];
  var clusterEnd = -1;

  void flush() {
    for (final i in cluster) {
      result[i] = (result[i].$1, laneEnds.length);
    }
    cluster = [];
    laneEnds = [];
  }

  for (final i in idx) {
    final it = items[i];
    if (it.start >= clusterEnd && cluster.isNotEmpty) flush();
    var lane = laneEnds.indexWhere((e) => e <= it.start);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(it.end);
    } else {
      laneEnds[lane] = it.end;
    }
    result[i] = (lane, 1);
    cluster.add(i);
    clusterEnd = cluster.isEmpty ? it.end : (it.end > clusterEnd ? it.end : clusterEnd);
  }
  if (cluster.isNotEmpty) flush();
  return result;
}

/// Left-hand hour labels + horizontal hour lines.
class HourGutter extends StatelessWidget {
  const HourGutter({super.key, this.width = 44});
  final double width;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return SizedBox(
      width: width,
      height: gridHeight,
      child: Stack(children: [
        for (var m = gridStartMin; m <= gridEndMin; m += 60)
          Positioned(
            top: yFor(m) - 7,
            right: 6,
            child: Text(formatTime(m), style: style),
          ),
      ]),
    );
  }
}

class HourLines extends StatelessWidget {
  const HourLines({super.key, this.nowMin});
  final int? nowMin;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).dividerColor;
    return Stack(children: [
      for (var m = gridStartMin; m <= gridEndMin; m += 60)
        Positioned(top: yFor(m), left: 0, right: 0, child: Container(height: 1, color: c)),
      if (nowMin != null && nowMin! >= gridStartMin && nowMin! <= gridEndMin)
        Positioned(
          top: yFor(nowMin!),
          left: 0,
          right: 0,
          child: Container(height: 2, color: Colors.redAccent),
        ),
    ]);
  }
}

/// Lays out [items] in a column of width [width].
List<Widget> buildBlocks(BuildContext context, List<GridItem> items, double width,
    {bool compact = false, List<(int, int)>? precomputedLanes}) {
  final lanes = precomputedLanes ?? layoutLanes(items);
  return [
    for (var i = 0; i < items.length; i++)
      () {
        const minBlockHeight = 18.0;
        final rawTop = yFor(items[i].start) + 1;
        final rawBottom = yFor(items[i].end) - 1;
        final top = rawTop.clamp(0.0, gridHeight - minBlockHeight);
        final bottom = rawBottom.clamp(top + minBlockHeight, gridHeight);
        final lane = lanes[i].$1;
        final laneCount = lanes[i].$2;
        final laneWidth = math.max(0.0, width / laneCount - 2);
        return Positioned(
          top: top,
          height: bottom - top,
          left: width / laneCount * lane + 1,
          width: laneWidth,
          child: GridBlock(items[i], compact: compact || laneCount > 2),
        );
      }(),
  ];
}

class GridBlock extends StatelessWidget {
  const GridBlock(this.item, {super.key, this.compact = false});
  final GridItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = studios[item.studioId]!.color;
    final on = onStudioColor(item.studioId);
    final s = item.session;
    final cancelled = s?.isCancelled ?? false;
    final isSeries = item.series != null;
    final strike = cancelled ? TextDecoration.lineThrough : null;

    return Material(
      color: cancelled ? color.withValues(alpha: 0.25) : color.withValues(alpha: isSeries ? 0.7 : 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: isSeries ? BorderSide(color: on, width: 1.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => s != null ? showSessionDetail(context, s) : showSeriesDetail(context, item.series!),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = (constraints.maxWidth < 24 || constraints.maxHeight < 28)
                ? 2.0
                : 4.0;
            final innerH = math.max(0.0, constraints.maxHeight - pad * 2);
            final showMeta = innerH >= 32;
            final showFooter = !compact && innerH >= 52;
            final titleMaxLines = innerH < 24 ? 1 : (compact ? 2 : 2);
            return Padding(
              padding: EdgeInsets.all(pad),
              child: DefaultTextStyle(
                style: TextStyle(
                    color: cancelled ? Colors.black54 : on,
                    fontSize: compact ? 10 : 12,
                    decoration: strike),
                overflow: TextOverflow.ellipsis,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showMeta)
                      Text(
                        [
                          if (isSeries) 'SERIES',
                          if (cancelled) 'CANCELLED',
                          if (s?.isSubstitute ?? false) 'SUB',
                          item.template.rawLevelLabel,
                        ].join(' · '),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Flexible(
                      child: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showFooter)
                      Text(
                        '${studios[item.studioId]!.shortName} · ${formatTime(item.start)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
