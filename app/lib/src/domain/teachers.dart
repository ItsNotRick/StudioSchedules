/// Teacher identity and notes (see docs/teacher-notes-design.md).
///
/// A note stores the scraped names it was written under, never a teacher key.
/// Which teacher a note belongs to is decided when it is read, by resolving
/// its names through the [TeacherResolver] built from the displayed feed:
/// a note belongs to teacher K if any of its names resolves to K.
library;

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Resolves scraped instructor names to teacher keys using the displayed
/// feed. All note reads and writes go through one resolver, so they agree.
class TeacherResolver {
  TeacherResolver._(this._keys, this._placeholders);

  /// Builds the lookup from the feed's alias map plus every session's own
  /// key. Session entries win, which guarantees
  /// `keyFor(s.instructor) == s.matchKey` for every displayed session, even
  /// for feeds that carry `instructorKey` but no `instructorAliases`.
  factory TeacherResolver.build({
    required Map<String, String> aliases,
    required Iterable<ClassSession> sessions,
    List<String> placeholders = defaultPlaceholderInstructors,
  }) {
    final keys = <String, String>{...aliases};
    for (final s in sessions) {
      keys[normalizeInstructor(s.instructor)] = s.matchKey;
    }
    return TeacherResolver._(keys, placeholders.toSet());
  }

  /// A resolver with no alias information: keys are normalized names.
  static final empty = TeacherResolver._(const {}, defaultPlaceholderInstructors.toSet());

  final Map<String, String> _keys;
  final Set<String> _placeholders;

  /// The teacher key for a scraped name.
  String keyFor(String listedName) {
    final n = normalizeInstructor(listedName);
    return _keys[n] ?? n;
  }

  /// True for keys that mean "no particular teacher" (e.g. "staff").
  /// Notes are never shown or created for these.
  bool isPlaceholder(String key) => key.isEmpty || _placeholders.contains(key);

  /// The distinct keys [names] resolve to, in first-seen order.
  List<String> keysFor(Iterable<String> names) =>
      {for (final n in names) keyFor(n)}.toList();
}

/// A saved note. [names] are the scraped spellings it was written under,
/// oldest first; the last is the most recently added.
@immutable
class TeacherNote {
  const TeacherNote({
    required this.id,
    required this.body,
    required this.names,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String body;
  final List<String> names;

  /// Incremented by every write. Used for lost-update checks (timestamps are
  /// stored to the second, so they can't be used for that).
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True if any of this note's names resolves to [key].
  bool belongsTo(String key, TeacherResolver r) => names.any((n) => r.keyFor(n) == key);

  /// The most recently added spelling.
  String get latestName => names.last;
}

/// Notes belonging to [key], oldest first.
List<TeacherNote> notesForTeacher(
  String key,
  Iterable<TeacherNote> notes,
  TeacherResolver r,
) =>
    notes.where((n) => n.belongsTo(key, r)).toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

/// Body for combining several notes: distinct non-blank bodies, oldest
/// first, separated by a blank line.
String combinedBody(Iterable<TeacherNote> notesOldestFirst) {
  final seen = <String>{};
  final parts = <String>[];
  for (final n in notesOldestFirst) {
    final b = n.body.trim();
    if (b.isNotEmpty && seen.add(b)) parts.add(b);
  }
  return parts.join('\n\n');
}

/// One row of the Teachers tab.
@immutable
class TeacherEntry {
  const TeacherEntry({
    required this.key,
    required this.displayName,
    required this.studios,
    required this.upcomingSessions,
    required this.notes,
    required this.onSchedule,
    required this.spellings,
  });

  final String key;
  final String displayName;
  final Set<StudioId> studios;

  /// Scheduled (not cancelled or removed) sessions from today on, in order.
  final List<ClassSession> upcomingSessions;

  /// Notes belonging to this teacher, oldest first.
  final List<TeacherNote> notes;

  /// False when the teacher has notes but no session in the current feed.
  final bool onSchedule;

  /// All scraped instructor spellings seen in sessions or notes for this entry.
  final Set<String> spellings;

  DateTime? get lastNoteUpdate => notes.isEmpty
      ? null
      : notes.map((n) => n.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Every non-placeholder teacher in [sessions], plus every teacher that only
/// has notes, sorted by display name.
List<TeacherEntry> buildTeacherDirectory({
  required Iterable<ClassSession> sessions,
  required Iterable<TeacherNote> notes,
  required TeacherResolver resolver,
  required ServiceDate today,
}) {
  final sessionsByKey = <String, List<ClassSession>>{};
  for (final s in sessions) {
    if (s.status == SessionStatus.removed) continue;
    final key = s.matchKey;
    if (resolver.isPlaceholder(key)) continue;
    sessionsByKey.putIfAbsent(key, () => []).add(s);
  }

  final notesByKey = <String, List<TeacherNote>>{};
  for (final n in notes) {
    for (final key in resolver.keysFor(n.names)) {
      if (resolver.isPlaceholder(key)) continue;
      notesByKey.putIfAbsent(key, () => []).add(n);
    }
  }

  final out = <TeacherEntry>[];
  for (final key in {...sessionsByKey.keys, ...notesByKey.keys}) {
    final ss = sessionsByKey[key] ?? const <ClassSession>[];
    final ns = notesForTeacher(key, notesByKey[key] ?? const [], resolver);
    final upcoming = ss
        .where((s) => s.status == SessionStatus.scheduled && s.serviceDate.compareTo(today) >= 0)
        .toList()
      ..sort((a, b) {
        final c = a.serviceDate.compareTo(b.serviceDate);
        return c != 0 ? c : a.startMin.compareTo(b.startMin);
      });
    out.add(TeacherEntry(
      key: key,
      displayName: ss.isNotEmpty
          ? _mostCommonName(ss)
          : _latestNoteName(ns, key, resolver),
      studios: {for (final s in ss) s.studioId},
      upcomingSessions: upcoming,
      notes: ns,
      onSchedule: ss.isNotEmpty,
      spellings: {
        for (final s in ss) s.instructor,
        for (final n in ns)
          for (final name in n.names)
            if (resolver.keyFor(name) == key) name,
      },
    ));
  }
  out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return out;
}

String _mostCommonName(List<ClassSession> sessions) {
  final counts = <String, int>{};
  for (final s in sessions) {
    counts[s.instructor] = (counts[s.instructor] ?? 0) + 1;
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return ranked.first.key;
}

String _latestNoteName(
  List<TeacherNote> notes,
  String key,
  TeacherResolver resolver,
) {
  final newest = notes.reduce((a, b) => b.updatedAt.isAfter(a.updatedAt) ? b : a);
  return newest.names.lastWhere(
    (n) => resolver.keyFor(n) == key,
    orElse: () => newest.latestName,
  );
}
