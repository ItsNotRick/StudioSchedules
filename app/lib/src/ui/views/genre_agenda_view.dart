import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_feed.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../detail_sheet.dart';

/// Prototype A — day agenda grouped by primary genre, with sticky
/// collapsible headers and series-starting cards on top.
class GenreAgendaView extends ConsumerStatefulWidget {
  const GenreAgendaView({super.key});

  @override
  ConsumerState<GenreAgendaView> createState() => _GenreAgendaViewState();
}

class _GenreAgendaViewState extends ConsumerState<GenreAgendaView> {
  final _collapsed = <Genre>{};

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedDateProvider);
    final sessions = ref.watch(sessionsForDateProvider(date));
    final starting = ref.watch(seriesStartingOnProvider(date));
    final openSeries =
        ref.watch(upcomingSeriesProvider).where((s) => s.enrollmentOpen).length;

    final byGenre = <Genre, List<ClassSession>>{};
    for (final s in sessions) {
      byGenre.putIfAbsent(templatesById[s.templateId]!.primaryGenre, () => []).add(s);
    }
    final genres = Genre.values.where(byGenre.containsKey).toList();

    return CustomScrollView(
      slivers: [
        if (openSeries > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ActionChip(
                avatar: const Icon(Icons.repeat, size: 16),
                label: Text('$openSeries beginner series open for enrollment'),
                onPressed: () => showSeriesList(context),
              ),
            ),
          ),
        if (starting.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Series starting today',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          SliverList.list(children: [for (final s in starting) SeriesCard(s)]),
        ],
        if (sessions.isEmpty && starting.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState('No classes match your filters on this day.\n'
                'Try turning off "Zero-experience only".'),
          ),
        for (final g in genres) ...[
          SliverToBoxAdapter(
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: InkWell(
                onTap: () => setState(() => _collapsed.contains(g)
                    ? _collapsed.remove(g)
                    : _collapsed.add(g)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(g.icon, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(g.label,
                            style: Theme.of(context).textTheme.titleSmall)),
                    Text('${byGenre[g]!.length}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 4),
                    Icon(_collapsed.contains(g)
                        ? Icons.expand_more
                        : Icons.expand_less),
                  ]),
                ),
              ),
            ),
          ),
          if (!_collapsed.contains(g))
            SliverList.builder(
              itemCount: byGenre[g]!.length,
              itemBuilder: (_, i) => SessionCard(byGenre[g]![i]),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
