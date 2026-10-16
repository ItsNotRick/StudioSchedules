import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_feed.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../detail_sheet.dart';

/// Prototype D — Personal weekly training planner & regimen tracker.
/// Shows recurring saved slots resolved against the selected week,
/// highlighting substitutions, cancellations, and schedule shifts.
class MyWeekView extends ConsumerWidget {
  const MyWeekView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final weekStart = selectedDate.startOfWeek;
    final resolvedSlots = ref.watch(resolvedRegimenProvider(weekStart));
    final savedSeriesIds = ref.watch(savedSeriesProvider);
    final feed = ref.watch(feedProvider);

    final enrolledSeries = feed.series
        .where((s) => savedSeriesIds.contains(s.id))
        .toList();

    // Group resolved slots by weekday
    final byWeekday = <int, List<ResolvedSlot>>{};
    for (final r in resolvedSlots) {
      byWeekday.putIfAbsent(r.slot.weekday, () => []).add(r);
    }

    final hasAny = resolvedSlots.isNotEmpty || enrolledSeries.isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Week of ${formatDate(weekStart)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Text(
                        '${resolvedSlots.length} recurring slots · ${enrolledSeries.length} active series',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Exported 14-day schedule to device calendar!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: const Text('Export', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!hasAny)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              'No saved classes in your training regimen yet.\n'
              'Browse the schedule and tap "Add to my week" to build your routine.',
            ),
          ),
        if (enrolledSeries.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Enrolled Series',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          SliverList.list(
            children: [
              for (final s in enrolledSeries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SeriesCard(s),
                ),
            ],
          ),
        ],
        for (var day = 1; day <= 7; day++) ...[
          if (byWeekday.containsKey(day)) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Row(
                  children: [
                    Text(
                      weekdayLong[day - 1],
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatDate(weekStart.addDays(day - 1)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: byWeekday[day]!.length,
              itemBuilder: (context, i) {
                final resolved = byWeekday[day]![i];
                return _RegimenSlotCard(resolved: resolved);
              },
            ),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _RegimenSlotCard extends ConsumerWidget {
  const _RegimenSlotCard({required this.resolved});
  final ResolvedSlot resolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tpl = templatesById[resolved.slot.templateId]!;
    final studio = studios[tpl.studioId]!;
    final session = resolved.session;
    final theme = Theme.of(context);

    Widget? statusBadge;
    String? statusSubtitle;
    Color? borderColor;

    switch (resolved.health) {
      case SlotHealth.ok:
        borderColor = studio.color;
        break;
      case SlotHealth.substitute:
        borderColor = Colors.orange.shade800;
        statusBadge = StatusChip(
          label: 'Teacher Substitute',
          color: Colors.orange.shade800,
          icon: Icons.swap_horiz,
        );
        statusSubtitle = 'Regular teacher: ${tpl.slots.firstWhere((s) => s.weekday == resolved.slot.weekday && s.startMin == resolved.slot.startMin, orElse: () => tpl.slots.first).regularInstructor}';
        break;
      case SlotHealth.cancelled:
        borderColor = Colors.red;
        statusBadge = const StatusChip(
          label: 'Class Cancelled',
          color: Colors.red,
          icon: Icons.block,
        );
        statusSubtitle = 'Cancelled by studio for this date';
        break;
      case SlotHealth.removed:
        borderColor = Colors.grey;
        statusBadge = const StatusChip(
          label: 'Removed from Schedule',
          color: Colors.grey,
          icon: Icons.warning_amber_rounded,
        );
        statusSubtitle = 'Studio removed this recurring slot';
        break;
      case SlotHealth.notOnSchedule:
        borderColor = Colors.grey.shade400;
        statusBadge = const StatusChip(
          label: 'Not on Timetable',
          color: Colors.grey,
          icon: Icons.help_outline,
        );
        statusSubtitle = 'No matching session found on studio calendar';
        break;
    }

    final strike = resolved.health == SlotHealth.cancelled ||
            resolved.health == SlotHealth.removed
        ? TextDecoration.lineThrough
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: session != null ? () => showSessionDetail(context, session) : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: borderColor, width: 5)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatTime(resolved.slot.startMin),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            decoration: strike,
                          ),
                        ),
                        Text(
                          session != null ? '${session.durationMin} min' : '90 min',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StudioBadge(tpl.studioId, dense: true),
                            LevelPill(tpl),
                            ?statusBadge,
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tpl.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            decoration: strike,
                          ),
                        ),
                        Text(
                          session != null
                              ? 'Teacher: ${session.instructor}'
                              : 'Instructor TBA',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: resolved.health == SlotHealth.substitute
                                ? FontWeight.bold
                                : null,
                            color: resolved.health == SlotHealth.substitute
                                ? Colors.orange.shade900
                                : null,
                          ),
                        ),
                        if (statusSubtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            statusSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: resolved.health == SlotHealth.cancelled
                                  ? Colors.red
                                  : Colors.grey.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark_remove, size: 20),
                    tooltip: 'Remove from regimen',
                    onPressed: () =>
                        ref.read(savedSlotsProvider.notifier).remove(resolved.slot),
                  ),
                ],
              ),
              if (session != null && resolved.health == SlotHealth.ok) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => openBooking(context, session.bookingUrl),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: Text(
                      'Book on ${studio.shortName}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
