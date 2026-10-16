import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_feed.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common.dart';
import 'time_grid_common.dart';

/// Prototype C — one column per studio (like a resource scheduler), so
/// back-to-back options across studios are visible side by side.
class StudioColumnsView extends ConsumerWidget {
  const StudioColumnsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final today = ref.watch(todayProvider);
    final filter = ref.watch(filterProvider);
    final sessions = ref.watch(sessionsForDateProvider(date));
    final series = ref.watch(seriesStartingOnProvider(date));
    final cols = StudioId.values.where(filter.studios.contains).toList();
    final now = DateTime.now();
    final nowMin = date == today ? now.hour * 60 + now.minute : null;
    const gutter = 44.0;

    if (cols.isEmpty) return const EmptyState('Select at least one studio.');

    return LayoutBuilder(builder: (context, c) {
      final colWidth = ((c.maxWidth - gutter - 8) / cols.length).clamp(72.0, 240.0);
      final totalWidth = gutter + colWidth * cols.length + 8;

      final grid = SizedBox(
        width: totalWidth,
        child: Column(children: [
          // Sticky-ish header row.
          Row(children: [
            const SizedBox(width: gutter),
            for (final s in cols)
              SizedBox(
                width: colWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    StudioBadge(s, dense: true),
                    Text(studios[s]!.neighborhood,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
          ]),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 10, bottom: 24),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const HourGutter(width: gutter),
                for (final s in cols)
                  Container(
                    width: colWidth,
                    height: gridHeight,
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
                      color: studios[s]!.color.withValues(alpha: 0.04),
                    ),
                    child: Stack(children: [
                      Positioned.fill(child: HourLines(nowMin: nowMin)),
                      ...buildBlocks(
                        context,
                        [
                          ...sessions.where((x) => x.studioId == s).map(GridItem.session),
                          ...series.where((x) => x.studioId == s).map(GridItem.series),
                        ],
                        colWidth,
                        compact: true,
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        ]),
      );

      return totalWidth > c.maxWidth
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid)
          : grid;
    });
  }
}
