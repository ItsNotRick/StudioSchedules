import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_feed.dart';
import '../domain/models.dart';
import '../state/providers.dart';
import 'detail_sheet.dart';

class StudioBadge extends StatelessWidget {
  const StudioBadge(this.id, {super.key, this.dense = false});
  final StudioId id;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = studios[id]!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 5 : 7, vertical: 2),
      decoration: BoxDecoration(
        color: s.color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        s.shortName,
        style: TextStyle(
          color: _onColor(s.color),
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _onColor(Color c) =>
    c.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;

Color onStudioColor(StudioId id) => _onColor(studios[id]!.color);

/// The studio's own level label (Q4), tinted by normalized tier.
class LevelPill extends StatelessWidget {
  const LevelPill(this.template, {super.key});
  final ClassTemplate template;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (template.tier) {
      Tier.zeroExperience => Colors.green.shade700,
      Tier.beginner => scheme.primary,
      Tier.advancedBeginner => Colors.deepOrange.shade700,
    };
    return Tooltip(
      message: template.tier.label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          template.rawLevelLabel,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

Widget? sessionStatusChip(ClassSession s) {
  if (s.isCancelled) {
    return const StatusChip(label: 'Cancelled', color: Colors.red, icon: Icons.block);
  }
  if (s.isSubstitute) {
    return StatusChip(label: 'Sub', color: Colors.orange.shade800, icon: Icons.swap_horiz);
  }
  return null;
}

/// Compact class card used by the agenda.
class SessionCard extends ConsumerWidget {
  const SessionCard(this.session, {super.key});
  final ClassSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tpl = getTemplate(session.templateId);
    final saved = ref.watch(savedSlotsProvider).any((s) => s.matches(session));
    final status = sessionStatusChip(session);
    final strike = session.isCancelled ? TextDecoration.lineThrough : null;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showSessionDetail(context, session),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: studios[session.studioId]!.color, width: 5)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 62,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(formatTime(session.startMin),
                      style: theme.textTheme.titleSmall?.copyWith(decoration: strike)),
                  Text('${session.durationMin} min', style: theme.textTheme.bodySmall),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    StudioBadge(session.studioId, dense: true),
                    LevelPill(tpl),
                    ?status,
                  ]),
                  const SizedBox(height: 4),
                  Text(tpl.title,
                      style: theme.textTheme.titleMedium?.copyWith(decoration: strike)),
                  Text(session.instructor, style: theme.textTheme.bodySmall),
                ]),
              ),
              Icon(saved ? Icons.bookmark : Icons.bookmark_border,
                  size: 20, color: saved ? theme.colorScheme.primary : theme.disabledColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal 14-day strip; dots indicate matching classes.
class WeekStrip extends ConsumerStatefulWidget {
  const WeekStrip({super.key});

  @override
  ConsumerState<WeekStrip> createState() => _WeekStripState();
}

class _WeekStripState extends ConsumerState<WeekStrip> {
  final ScrollController _scrollController = ScrollController();
  ServiceDate? _lastScrolledDate;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelectedOrToday(MockFeed feed, ServiceDate target) {
    if (!_scrollController.hasClients) return;
    final dayIndex = feed.windowStart.daysUntil(target);
    if (dayIndex >= 0) {
      double offset = dayIndex * 52.0;
      // Show target with a 1-day lead so surrounding days are visible
      offset = math.max(0.0, offset - 52.0);
      final maxExtent = _scrollController.position.maxScrollExtent;
      final clampedOffset = offset.clamp(0.0, maxExtent);
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final selected = ref.watch(selectedDateProvider);
    final today = ref.watch(todayProvider);
    final theme = Theme.of(context);

    if (_lastScrolledDate != selected) {
      _lastScrolledDate = selected;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToSelectedOrToday(feed, selected);
        }
      });
    }

    final totalDays = math.max(14, feed.windowStart.daysUntil(feed.windowEnd) + 1);

    return SizedBox(
      height: 70,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: totalDays,
        itemBuilder: (context, i) {
          final d = feed.windowStart.addDays(i);
          final isSel = d == selected;
          final isToday = d == today;
          final count = ref.watch(sessionsForDateProvider(d)).length +
              ref.watch(seriesStartingOnProvider(d)).length;
          final past = d.compareTo(today) < 0;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => ref.read(selectedDateProvider.notifier).select(d),
              child: Container(
                width: 46,
                decoration: BoxDecoration(
                  color: isSel ? theme.colorScheme.primary : null,
                  borderRadius: BorderRadius.circular(12),
                  border: isToday && !isSel
                      ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      weekdayShort[d.weekday - 1],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isSel
                            ? theme.colorScheme.onPrimary
                            : past
                                ? theme.disabledColor
                                : null,
                      ),
                    ),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isSel
                            ? theme.colorScheme.onPrimary
                            : past
                                ? theme.disabledColor
                                : null,
                      ),
                    ),
                    Text(
                      count == 0 ? '·' : '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSel
                            ? theme.colorScheme.onPrimary
                            : past
                                ? theme.disabledColor
                                : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Entry-level switch + studio chips + genre chips (Q4/Q5).
class FilterRail extends ConsumerWidget {
  const FilterRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(filterProvider);
    final n = ref.read(filterProvider.notifier);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final s in StudioId.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(studios[s]!.shortName),
                selected: f.studios.contains(s),
                selectedColor: studios[s]!.color.withValues(alpha: 0.25),
                onSelected: (_) => n.toggleStudio(s),
              ),
            ),
          const VerticalDivider(width: 16),
          for (final g in Genre.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                avatar: Icon(g.icon, size: 16),
                label: Text(g.label),
                selected: f.genres.contains(g),
                onSelected: (_) => n.toggleGenre(g),
              ),
            ),
        ],
      ),
    );
  }
}

/// Card for a multi-week series (Q6).
class SeriesCard extends ConsumerWidget {
  const SeriesCard(this.series, {super.key});
  final WorkshopSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tpl = getTemplate(series.templateId);
    final saved = ref.watch(savedSeriesProvider).contains(series.id);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
      child: InkWell(
        onTap: () => showSeriesDetail(context, series),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const StatusChip(label: 'SERIES', color: Colors.deepPurple, icon: Icons.repeat),
              StudioBadge(series.studioId, dense: true),
              LevelPill(tpl),
              series.enrollmentOpen
                  ? StatusChip(label: 'Enrollment open', color: Colors.green.shade700)
                  : const StatusChip(label: 'Closed', color: Colors.grey),
              if (saved) const Icon(Icons.bookmark, size: 16),
            ]),
            const SizedBox(height: 6),
            Text(series.title, style: theme.textTheme.titleMedium),
            Text(
              '${series.sessionCount} × ${weekdayLong[series.weekday - 1]}s '
              '${formatRange(series.startMin, series.startMin + series.durationMin)} · '
              '${formatDate(series.startDate)} → ${formatDate(series.endDate)}',
              style: theme.textTheme.bodySmall,
            ),
            Text('${series.instructor} · ${series.price}', style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_busy, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      );
}
