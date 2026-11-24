import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/teachers.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../teacher_notes.dart';

/// Teachers tab: teachers you have notes on, then everyone on the current
/// schedule, with search.
class TeachersView extends ConsumerStatefulWidget {
  const TeachersView({super.key});

  @override
  ConsumerState<TeachersView> createState() => _TeachersViewState();
}

class _TeachersViewState extends ConsumerState<TeachersView> {
  String _query = '';

  bool _matches(TeacherEntry e) {
    if (_query.isEmpty) return true;
    final q = normalizeInstructor(_query);
    return e.key.contains(q) ||
        normalizeInstructor(e.displayName).contains(q) ||
        e.spellings.any((s) => normalizeInstructor(s).contains(q)) ||
        e.notes.any((n) => n.names.any((s) => normalizeInstructor(s).contains(q))) ||
        e.upcomingSessions.any((s) => normalizeInstructor(s.instructor).contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref
        .watch(teacherDirectoryProvider)
        .where(_matches)
        .toList();
    final withNotes = directory.where((e) => e.notes.isNotEmpty).toList()
      ..sort((a, b) => b.lastNoteUpdate!.compareTo(a.lastNoteUpdate!));
    final others = directory
        .where((e) => e.notes.isEmpty && e.onSchedule)
        .toList();
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search teachers',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        header('Your notes'),
        if (withNotes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _query.isEmpty
                  ? 'Open any class and tap "Add a note" to save notes about its teacher.'
                  : 'No notes match.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
        for (final e in withNotes) _TeacherTile(entry: e),
        header('On the schedule'),
        if (others.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _query.isEmpty
                  ? 'No teachers on the current schedule.'
                  : 'No teachers match.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
        for (final e in others) _TeacherTile(entry: e),
      ],
    );
  }
}

String _classCount(int n) =>
    n == 1 ? '1 upcoming class' : '$n upcoming classes';

class _TeacherTile extends StatelessWidget {
  const _TeacherTile({required this.entry});
  final TeacherEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = entry.notes;
    final String subtitle;
    if (notes.isNotEmpty) {
      final preview = notes.last.body.trim().split('\n').first;
      subtitle = entry.onSchedule
          ? preview
          : 'Not on the current schedule · $preview';
    } else {
      subtitle = _classCount(entry.upcomingSessions.length);
    }
    final studioIds = entry.studios.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return ListTile(
      title: Row(
        children: [
          Flexible(
            child: Text(entry.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (notes.length > 1) ...[
            const SizedBox(width: 6),
            StatusChip(
              label: '${notes.length} notes',
              color: theme.colorScheme.primary,
              icon: Icons.notes,
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Wrap(
        spacing: 4,
        children: [for (final id in studioIds) StudioBadge(id, dense: true)],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TeacherDetailPage(
            teacherKey: entry.key,
            fallbackName: entry.displayName,
          ),
        ),
      ),
    );
  }
}

/// One teacher: their notes and their upcoming classes in the feed window.
class TeacherDetailPage extends ConsumerWidget {
  const TeacherDetailPage({
    super.key,
    required this.teacherKey,
    required this.fallbackName,
  });

  final String teacherKey;

  /// Shown if the teacher drops out of the directory while the page is open
  /// (e.g. their only note was deleted and they aren't on the schedule).
  final String fallbackName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref
        .watch(teacherDirectoryProvider)
        .where((e) => e.key == teacherKey)
        .firstOrNull;
    final name = entry?.displayName ?? fallbackName;
    final theme = Theme.of(context);
    final sessions = entry?.upcomingSessions ?? const <ClassSession>[];

    // Group upcoming classes by date.
    final byDate = <ServiceDate, List<ClassSession>>{};
    for (final s in sessions) {
      byDate.putIfAbsent(s.serviceDate, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry != null && entry.studios.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final id
                          in entry.studios.toList()
                            ..sort((a, b) => a.index.compareTo(b.index)))
                        StudioBadge(id),
                    ],
                  ),
                TeacherNotesSection(
                  teacherKey: teacherKey,
                  listedName: name,
                  displayName: name,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              sessions.isEmpty
                  ? 'No upcoming classes on the current schedule'
                  : _classCount(sessions.length),
              style: theme.textTheme.labelLarge,
            ),
          ),
          for (final MapEntry(key: date, value: list) in byDate.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text(formatDate(date), style: theme.textTheme.titleSmall),
            ),
            for (final s in list) SessionCard(s),
          ],
        ],
      ),
    );
  }
}
