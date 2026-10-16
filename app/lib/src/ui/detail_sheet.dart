import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mock_feed.dart';
import '../domain/models.dart';
import '../state/providers.dart';
import 'common.dart';

/// Opens the booking URL in the external browser so the Mindbody login
/// persists between bookings (Q16).
Future<void> openBooking(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

void showSessionDetail(BuildContext context, ClassSession session) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _SessionDetail(session: session, controller: controller),
    ),
  );
}

void showSeriesDetail(BuildContext context, WorkshopSeries series) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _SeriesDetail(series: series, controller: controller),
    ),
  );
}

void showSeriesList(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Consumer(builder: (context, ref, _) {
        final list = ref.watch(upcomingSeriesProvider);
        return ListView(controller: controller, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Beginner series',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
                'Multi-week series must be booked as a block before week 1. '
                'They are hidden from the drop-in calendar after their start date.'),
          ),
          for (final s in list) SeriesCard(s),
          const SizedBox(height: 24),
        ]);
      }),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.child);
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          child,
        ]),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text, {this.trailing});
  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).hintColor),
          const SizedBox(width: 8),
          Flexible(child: Text(text)),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      );
}

class _SessionDetail extends ConsumerWidget {
  const _SessionDetail({required this.session, required this.controller});
  final ClassSession session;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tpl = templatesById[session.templateId]!;
    final studio = studios[session.studioId]!;
    final saved = ref.watch(savedSlotsProvider).any((s) => s.matches(session));
    final theme = Theme.of(context);
    final feed = ref.watch(feedProvider);
    final filter = ref.watch(filterProvider);

    // "Pairs well with":
    // 1. Same-studio classes starting immediately after this one ends (gap == 0) or later (gap <= 90).
    // 2. Cross-studio classes reachable in time via walk/subway within 90 min.
    final allReachable = feed.sessions.where((o) {
      if (o.id == session.id || o.serviceDate != session.serviceDate) return false;
      if (o.status != SessionStatus.scheduled) return false;
      final gap = o.startMin - session.endMin;
      if (gap < 0 || gap > 90) return false;
      if (o.studioId == session.studioId) return true; // Same studio includes immediate start (gap == 0)
      return commuteBetween(session.studioId, o.studioId).minutes + 5 <= gap;
    }).toList()
      ..sort((a, b) => a.startMin.compareTo(b.startMin));

    // Prefer classes that match the active filter if any match, otherwise show all reachable classes
    final filtered = allReachable
        .where((o) => filter.acceptsTemplate(templatesById[o.templateId]!))
        .toList();
    final reachable = filtered.isNotEmpty ? filtered : allReachable;

    final sameStudio = reachable.where((o) => o.studioId == session.studioId).toList();
    final crossStudio = reachable.where((o) => o.studioId != session.studioId).toList();

    // Include immediate same-studio classes in addition to cross-studio commute options
    final pairs = <ClassSession>[];
    if (sameStudio.isNotEmpty && crossStudio.isNotEmpty) {
      pairs.addAll(sameStudio.take(2));
      pairs.addAll(crossStudio.take(2));
      pairs.sort((a, b) => a.startMin.compareTo(b.startMin));
    } else {
      pairs.addAll(reachable.take(4));
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StudioBadge(session.studioId),
          LevelPill(tpl),
          Text(tpl.tier.label, style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        Text(tpl.title, style: theme.textTheme.headlineSmall),
        if (session.isCancelled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.red.withValues(alpha: 0.1),
              child: const Text('This class has been cancelled by the studio.',
                  style: TextStyle(color: Colors.red)),
            ),
          ),
        const SizedBox(height: 12),
        _InfoRow(Icons.event,
            '${formatDate(session.serviceDate)} · ${formatRange(session.startMin, session.endMin)}'),
        _InfoRow(Icons.place_outlined, '${studio.address} · ${studio.neighborhood}'),
        _InfoRow(
          Icons.person_outline,
          session.instructor,
          trailing: session.isSubstitute
              ? StatusChip(
                  label: () {
                    for (final s in tpl.slots) {
                      if (s.weekday == session.serviceDate.weekday && s.startMin == session.startMin) {
                        return 'Sub for ${s.regularInstructor}';
                      }
                    }
                    return 'Substitute';
                  }(),
                  color: Colors.orange.shade800,
                  icon: Icons.swap_horiz)
              : null,
        ),
        const _InfoRow(Icons.confirmation_number_outlined, 'Drop-in · book per class'),
        _Section('About this class', Text(tpl.description)),
        if (tpl.prerequisiteNotes != null) _Section('Who it\'s for', Text(tpl.prerequisiteNotes!)),
        if (tpl.attireNotes != null) _Section('What to wear', Text(tpl.attireNotes!)),
        _Section(
          'Genres',
          Wrap(spacing: 6, children: [
            for (final g in tpl.allGenres)
              Chip(
                avatar: Icon(g.icon, size: 16),
                label: Text(g.label),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ),
        if (pairs.isNotEmpty)
          _Section(
            'Pairs well with (back-to-back)',
            Column(children: [
              for (final o in pairs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: StudioBadge(o.studioId, dense: true),
                  title: Text(templatesById[o.templateId]!.title),
                  subtitle: Text(
                    '${formatTime(o.startMin)}'
                    '${o.instructor.isNotEmpty ? ' · with ${o.instructor}' : ''}'
                    ' · ${o.startMin == session.endMin ? 'Starts right after' : '${o.startMin - session.endMin} min gap'}'
                    ' · ${commuteBetween(session.studioId, o.studioId)}',
                  ),
                  trailing: LevelPill(templatesById[o.templateId]!),
                  onTap: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    showSessionDetail(nav.context, o);
                  },
                ),
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: session.isCancelled ? null : () => openBooking(context, session.bookingUrl),
          icon: const Icon(Icons.open_in_new),
          label: Text('Book on ${studio.shortName}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.read(savedSlotsProvider.notifier).toggleFor(session),
          icon: Icon(saved ? Icons.bookmark_remove : Icons.bookmark_add_outlined),
          label: Text(saved
              ? 'Remove from my week'
              : 'Add every ${weekdayLong[session.serviceDate.weekday - 1]} ${formatTime(session.startMin)} to my week'),
        ),
        const SizedBox(height: 8),
        Text('Prototype · mock data', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _SeriesDetail extends ConsumerWidget {
  const _SeriesDetail({required this.series, required this.controller});
  final WorkshopSeries series;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tpl = templatesById[series.templateId]!;
    final studio = studios[series.studioId]!;
    final saved = ref.watch(savedSeriesProvider).contains(series.id);
    final theme = Theme.of(context);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const StatusChip(label: 'SERIES', color: Colors.deepPurple, icon: Icons.repeat),
          StudioBadge(series.studioId),
          LevelPill(tpl),
        ]),
        const SizedBox(height: 8),
        Text(series.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        _InfoRow(Icons.date_range,
            '${formatDate(series.startDate)} → ${formatDate(series.endDate)} · ${series.sessionCount} weeks'),
        _InfoRow(Icons.schedule,
            '${weekdayLong[series.weekday - 1]}s ${formatRange(series.startMin, series.startMin + series.durationMin)}'),
        _InfoRow(Icons.place_outlined, '${studio.address} · ${studio.neighborhood}'),
        _InfoRow(Icons.person_outline, series.instructor),
        _InfoRow(Icons.sell_outlined, series.price),
        _InfoRow(
          series.enrollmentOpen ? Icons.lock_open : Icons.lock_outline,
          series.enrollmentOpen
              ? 'Enrollment open — book the full series before week 1'
              : 'Enrollment closed — this series is in progress',
        ),
        _Section('About this series', Text(tpl.description)),
        if (tpl.prerequisiteNotes != null) _Section('Who it\'s for', Text(tpl.prerequisiteNotes!)),
        if (tpl.attireNotes != null) _Section('What to wear', Text(tpl.attireNotes!)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: series.enrollmentOpen ? () => openBooking(context, series.bookingUrl) : null,
          icon: const Icon(Icons.open_in_new),
          label: Text('Enroll on ${studio.shortName}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.read(savedSeriesProvider.notifier).toggle(series.id),
          icon: Icon(saved ? Icons.bookmark_remove : Icons.bookmark_add_outlined),
          label: Text(saved ? 'Remove from my week' : 'I\'m enrolled — show sessions in my week'),
        ),
      ],
    );
  }
}
