import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/database/teacher_notes_dao.dart';
import '../data/feed_repository.dart';
import '../data/feed.dart';
import '../domain/models.dart';
import '../domain/teachers.dart';

export '../domain/models.dart'
    show isEasternDst, getTodayInNewYork, getNowMinInNewYork;

/// Database provider for offline-first caching and saved regimen persistence.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// "Today" in NY.
final todayProvider = Provider<ServiceDate>(
  (ref) => getTodayInNewYork(),
);

/// Loads the schedule feed. The bundled or cached feed is shown as soon as
/// it's read; the remote feed is then checked in the background and replaces
/// it if newer. Call `ref.invalidate(feedProvider)` to retry after an error.
class FeedNotifier extends AsyncNotifier<Feed> {
  @override
  Future<Feed> build() async {
    final repo = FeedRepository(database: ref.read(appDatabaseProvider));
    final local = await repo.loadFeed(fetchRemote: false);
    _checkRemote(repo);
    return local;
  }

  Future<void> _checkRemote(FeedRepository repo) async {
    try {
      final latest = await repo.loadFeed();
      if (ref.mounted) state = AsyncData(latest);
    } catch (e) {
      // Keep showing the local feed.
    }
  }
}

final feedProvider = AsyncNotifierProvider<FeedNotifier, Feed>(
  FeedNotifier.new,
  // No automatic retry: a failure means the bundled asset is unreadable,
  // which retrying won't fix. The error view offers a manual retry.
  retry: (retryCount, error) => null,
);

/// The loaded feed, or an empty one while loading or after an error. The home
/// screen shows loading and error states itself, so views can read this
/// without handling them.
final currentFeedProvider = Provider<Feed>((ref) {
  return ref.watch(feedProvider).value ?? Feed.empty(ref.watch(todayProvider));
});

class SelectedDate extends Notifier<ServiceDate> {
  @override
  ServiceDate build() => ref.watch(todayProvider);

  void select(ServiceDate d) => state = d;
}

final selectedDateProvider =
    NotifierProvider<SelectedDate, ServiceDate>(SelectedDate.new);

class FilterState {
  const FilterState({
    required this.studios,
    required this.genres,
  });

  final Set<StudioId> studios;
  final Set<Genre> genres; // empty = all genres

  FilterState copyWith({
    Set<StudioId>? studios,
    Set<Genre>? genres,
  }) =>
      FilterState(
        studios: studios ?? this.studios,
        genres: genres ?? this.genres,
      );

  bool acceptsTemplate(ClassTemplate t) =>
      studios.contains(t.studioId) &&
      (genres.isEmpty || t.allGenres.any(genres.contains));
}

class Filter extends Notifier<FilterState> {
  @override
  FilterState build() => FilterState(
        studios: StudioId.values.toSet(),
        genres: const {},
      );

  void toggleStudio(StudioId id) {
    final s = {...state.studios};
    s.contains(id) ? s.remove(id) : s.add(id);
    state = state.copyWith(studios: s);
  }

  void toggleGenre(Genre g) {
    final s = {...state.genres};
    s.contains(g) ? s.remove(g) : s.add(g);
    state = state.copyWith(genres: s);
  }
}

final filterProvider = NotifierProvider<Filter, FilterState>(Filter.new);

/// Visible drop-in sessions for a date (removed tombstones are hidden;
/// cancelled sessions stay visible, struck through).
final sessionsForDateProvider =
    Provider.family<List<ClassSession>, ServiceDate>((ref, date) {
  final feed = ref.watch(currentFeedProvider);
  final filter = ref.watch(filterProvider);
  return feed.sessions
      .where((s) =>
          s.serviceDate == date &&
          s.status != SessionStatus.removed &&
          filter.acceptsTemplate(getTemplate(s.templateId)))
      .toList();
});

/// Series whose first session is on [date] and that pass the filter.
final seriesStartingOnProvider =
    Provider.family<List<WorkshopSeries>, ServiceDate>((ref, date) {
  final feed = ref.watch(currentFeedProvider);
  final filter = ref.watch(filterProvider);
  return feed.series
      .where((s) =>
          s.startDate == date &&
          filter.acceptsTemplate(getTemplate(s.templateId)))
      .toList();
});

/// All series still worth showing (in progress or upcoming) that pass the active filter.
final upcomingSeriesProvider = Provider<List<WorkshopSeries>>((ref) {
  final feed = ref.watch(currentFeedProvider);
  final filter = ref.watch(filterProvider);
  final today = ref.watch(todayProvider);
  return feed.series
      .where((s) =>
          s.endDate.compareTo(today) >= 0 &&
          filter.acceptsTemplate(getTemplate(s.templateId)))
      .toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
});

/// Builds the [SavedSlot] to persist when saving [s]. When [s] is currently
/// taught by a substitute, resolves the underlying regular teacher (from
/// [ClassSession.regularInstructor] or a unique non-sub occurrence on another
/// date) instead of storing the substitute as the regular teacher; falls back
/// to a slot-level bookmark (`instructor: null`) if ambiguous.
///
/// [resolver] maps the regular teacher's name to the same key the feed uses
/// (through its alias map), so the slot matches later weeks under any spelling.
@visibleForTesting
SavedSlot buildSavedSlotForSession(
  ClassSession s,
  Iterable<ClassSession> allSessions, {
  TeacherResolver? resolver,
}) {
  if (!s.isSubstitute) {
    return SavedSlot(
      templateId: s.templateId,
      weekday: s.serviceDate.weekday,
      startMin: s.startMin,
      instructor: s.instructor,
      instructorKey: s.matchKey,
    );
  }

  final explicitRegular = s.regularInstructor?.trim();
  if (explicitRegular != null && explicitRegular.isNotEmpty) {
    return SavedSlot(
      templateId: s.templateId,
      weekday: s.serviceDate.weekday,
      startMin: s.startMin,
      instructor: explicitRegular,
      instructorKey: (resolver ?? TeacherResolver.empty).keyFor(explicitRegular),
    );
  }

  final concurrentOnDate = allSessions
      .where((o) =>
          o.id != s.id &&
          o.serviceDate == s.serviceDate &&
          o.templateId == s.templateId &&
          o.startMin == s.startMin)
      .map((o) => o.matchKey)
      .toSet();

  final candidates = allSessions.where((o) =>
      o.serviceDate != s.serviceDate &&
      o.templateId == s.templateId &&
      o.serviceDate.weekday == s.serviceDate.weekday &&
      o.startMin == s.startMin &&
      !o.isSubstitute &&
      !concurrentOnDate.contains(o.matchKey)).toList();

  if (candidates.map((o) => o.matchKey).toSet().length == 1) {
    final reg = candidates.first;
    return SavedSlot(
      templateId: s.templateId,
      weekday: s.serviceDate.weekday,
      startMin: s.startMin,
      instructor: reg.instructor,
      instructorKey: reg.matchKey,
    );
  }

  return SavedSlot(
    templateId: s.templateId,
    weekday: s.serviceDate.weekday,
    startMin: s.startMin,
  );
}

class SavedSlots extends Notifier<Set<SavedSlot>> {
  final Set<SavedSlot> _addedBeforeLoad = {};
  final Set<SavedSlot> _removedBeforeLoad = {};
  bool _isLoaded = false;
  Future<void> _writeQueue = Future.value();

  @override
  Set<SavedSlot> build() {
    _addedBeforeLoad.clear();
    _removedBeforeLoad.clear();
    _isLoaded = false;
    _writeQueue = Future.value();
    _loadFromDb();
    return {};
  }

  void _enqueueWrite(Future<void> Function() op) {
    _writeQueue = _writeQueue.then((_) => op()).catchError((_) {});
  }

  Future<void> _loadFromDb() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final dbSlots = await db.getAllSavedSlots();
      if (!ref.mounted) return;

      final canonicalSlots = <SavedSlot, SavedSlot>{};
      final staleIds = <String>{};
      final toUpsert = <SavedSlot>{};

      for (final row in dbSlots) {
        final slot = SavedSlot(
          templateId: row.templateId,
          weekday: row.targetWeekday,
          startMin: row.targetStartMin,
          instructor:
              (row.label.isNotEmpty && row.label != row.templateId)
                  ? row.label
                  : null,
          instructorKey: row.instructorKey,
        );
        final canonicalId = _slotDbId(slot);
        final existing = canonicalSlots[slot];
        if (existing == null) {
          canonicalSlots[slot] = slot;
          if (row.id != canonicalId) {
            staleIds.add(row.id);
            toUpsert.add(slot);
          }
        } else {
          final existingCanonicalId = _slotDbId(existing);
          if (row.id != existingCanonicalId) {
            staleIds.add(row.id);
          } else {
            canonicalSlots[slot] = slot;
          }
        }
      }

      toUpsert.removeAll(_removedBeforeLoad);
      if (staleIds.isNotEmpty || toUpsert.isNotEmpty) {
        _enqueueWrite(() async {
          for (final s in toUpsert) {
            await db.insertOrUpdateSlot(SavedRegimenSlotsCompanion.insert(
              id: _slotDbId(s),
              templateId: s.templateId,
              targetWeekday: s.weekday,
              targetStartMin: s.startMin,
              label: s.instructor ?? s.templateId,
              instructorKey: Value(s.instructorKey),
              createdAt: DateTime.now(),
            ));
          }
          await db.deleteSlotsByIds(staleIds);
        });
      }

      final loaded = canonicalSlots.values.toSet();
      _isLoaded = true;
      state = ({...state, ...loaded, ..._addedBeforeLoad})
        ..removeAll(_removedBeforeLoad);
    } catch (_) {
      _isLoaded = true;
    }
  }

  /// True if a saved slot resolves to [s], including when [s] is taught by a
  /// substitute for the saved teacher.
  bool isSaved(ClassSession s) => _claiming(s).isNotEmpty;

  List<SavedSlot> _claiming(ClassSession s) =>
      slotsClaiming(s, ref.read(currentFeedProvider).sessions, state).toList();

  void toggleFor(ClassSession s) {
    final existingMatches = _claiming(s);
    final next = {...state};
    if (existingMatches.isNotEmpty) {
      for (final m in existingMatches) {
        next.remove(m);
        if (!_isLoaded) {
          _addedBeforeLoad.remove(m);
          _removedBeforeLoad.add(m);
        }
        _persistSlotToggle(m, false);
      }
      state = next;
    } else {
      final slot = buildSavedSlotForSession(
        s,
        ref.read(currentFeedProvider).sessions,
        resolver: ref.read(teacherResolverProvider),
      );
      next.add(slot);
      if (!_isLoaded) {
        _removedBeforeLoad.remove(slot);
        _addedBeforeLoad.add(slot);
      }
      state = next;
      _persistSlotToggle(slot, true);
    }
  }

  void remove(SavedSlot slot) {
    if (!_isLoaded) {
      _addedBeforeLoad.remove(slot);
      _removedBeforeLoad.add(slot);
    }
    state = {...state}..remove(slot);
    _persistSlotToggle(slot, false);
  }

  static String _slotDbId(SavedSlot slot) {
    final base = '${slot.templateId}_${slot.weekday}_${slot.startMin}';
    final key = slot.teacherKey;
    if (key == null || key.isEmpty) return base;
    return '${base}_${Uri.encodeComponent(key)}';
  }

  void _persistSlotToggle(SavedSlot slot, bool isAdded) {
    _enqueueWrite(() async {
      final db = ref.read(appDatabaseProvider);
      final id = _slotDbId(slot);
      if (isAdded) {
        await db.insertOrUpdateSlot(SavedRegimenSlotsCompanion.insert(
          id: id,
          templateId: slot.templateId,
          targetWeekday: slot.weekday,
          targetStartMin: slot.startMin,
          label: slot.instructor ?? slot.templateId,
          instructorKey: Value(slot.instructorKey),
          createdAt: DateTime.now(),
        ));
      } else {
        final idsToDelete = <String>{id};
        // Also remove pre-migration display-name id if this slot has an instructor.
        if (slot.instructor != null && slot.instructor!.isNotEmpty) {
          final cleanInst =
              slot.instructor!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (cleanInst.isNotEmpty) {
            idsToDelete.add(
              '${slot.templateId}_${slot.weekday}_${slot.startMin}_$cleanInst',
            );
          }
        }
        await db.deleteSlotsByIds(idsToDelete);
      }
    });
  }
}

final savedSlotsProvider =
    NotifierProvider<SavedSlots, Set<SavedSlot>>(SavedSlots.new);

class SavedSeries extends Notifier<Set<String>> {
  final Set<String> _addedBeforeLoad = {};
  final Set<String> _removedBeforeLoad = {};
  bool _isLoaded = false;
  Future<void> _writeQueue = Future.value();

  @override
  Set<String> build() {
    _addedBeforeLoad.clear();
    _removedBeforeLoad.clear();
    _isLoaded = false;
    _writeQueue = Future.value();
    _loadFromDb();
    return {};
  }

  void _enqueueWrite(Future<void> Function() op) {
    _writeQueue = _writeQueue.then((_) => op()).catchError((_) {});
  }

  Future<void> _loadFromDb() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final val = await db.getSetting('saved_series');
      if (!ref.mounted) return;
      final loaded = (val != null && val.isNotEmpty)
          ? val.split(',').where((s) => s.isNotEmpty).toSet()
          : <String>{};
      final merged = ({...state, ...loaded, ..._addedBeforeLoad})
        ..removeAll(_removedBeforeLoad);
      _isLoaded = true;
      state = merged;
      if (_addedBeforeLoad.isNotEmpty || _removedBeforeLoad.isNotEmpty) {
        _persist(merged);
      }
    } catch (_) {
      _isLoaded = true;
    }
  }

  void toggle(String id) {
    final next = {...state};
    if (next.contains(id)) {
      next.remove(id);
      if (!_isLoaded) {
        _addedBeforeLoad.remove(id);
        _removedBeforeLoad.add(id);
      }
    } else {
      next.add(id);
      if (!_isLoaded) {
        _removedBeforeLoad.remove(id);
        _addedBeforeLoad.add(id);
      }
    }
    state = next;
    if (_isLoaded) {
      _persist(next);
    }
  }

  void _persist(Set<String> series) {
    _enqueueWrite(() async {
      final db = ref.read(appDatabaseProvider);
      await db.setSetting('saved_series', series.join(','));
    });
  }
}

final savedSeriesProvider =
    NotifierProvider<SavedSeries, Set<String>>(SavedSeries.new);

/// Result of resolving a saved slot against a given week's feed (Q9/Q10).
enum SlotHealth { ok, substitute, cancelled, removed, notOnSchedule }

class ResolvedSlot {
  const ResolvedSlot(this.slot, this.date, this.session, this.health);
  final SavedSlot slot;
  final ServiceDate date;
  final ClassSession? session;
  final SlotHealth health;
}

SlotHealth slotHealth(SlotMatch? match) => switch (match) {
      null => SlotHealth.notOnSchedule,
      SlotMatch(session: ClassSession(status: SessionStatus.removed)) =>
        SlotHealth.removed,
      SlotMatch(session: ClassSession(status: SessionStatus.cancelled)) =>
        SlotHealth.cancelled,
      SlotMatch(isSubstitute: true) => SlotHealth.substitute,
      _ => SlotHealth.ok,
    };

/// Resolves every saved slot for the week starting [weekStart].
final resolvedRegimenProvider =
    Provider.family<List<ResolvedSlot>, ServiceDate>((ref, weekStart) {
  final feed = ref.watch(currentFeedProvider);
  final saved = ref.watch(savedSlotsProvider);
  final out = <ResolvedSlot>[];
  for (final slot in saved) {
    final date = weekStart.addDays(slot.weekday - 1);
    final match = resolveSlot(slot, date, feed.sessions, saved);
    out.add(ResolvedSlot(slot, date, match?.session, slotHealth(match)));
  }
  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.slot.startMin.compareTo(b.slot.startMin);
  });
  return out;
});

// ---------------------------------------------------------------------------
// Teacher notes (docs/teacher-notes-design.md §7.1)

/// Resolves scraped instructor names to teacher keys for the displayed feed.
/// Every note read and write uses this, so they always agree.
final teacherResolverProvider = Provider<TeacherResolver>((ref) {
  final feed = ref.watch(currentFeedProvider);
  return TeacherResolver.build(
    aliases: feed.instructorAliases,
    sessions: feed.sessions,
    placeholders: feed.placeholderInstructors,
  );
});

final teacherNotesDaoProvider = Provider<TeacherNotesDao>(
  (ref) => ref.watch(appDatabaseProvider).teacherNotesDao,
);

/// Every saved note, oldest first. Updates after each committed write.
final allTeacherNotesProvider = StreamProvider<List<TeacherNote>>(
  (ref) => ref.watch(teacherNotesDaoProvider).watchAll(),
  // A failing local query won't fix itself on a timer.
  retry: (retryCount, error) => null,
);

/// Notes belonging to the teacher [key] under the displayed feed, oldest
/// first. Empty while notes are loading.
final notesForTeacherProvider =
    Provider.autoDispose.family<List<TeacherNote>, String>((ref, key) {
  final resolver = ref.watch(teacherResolverProvider);
  final notes = ref.watch(allTeacherNotesProvider).value ?? const <TeacherNote>[];
  return notesForTeacher(key, notes, resolver);
});

/// The Teachers tab: everyone on the current schedule plus anyone with notes.
final teacherDirectoryProvider = Provider<List<TeacherEntry>>((ref) {
  final feed = ref.watch(currentFeedProvider);
  return buildTeacherDirectory(
    sessions: feed.sessions,
    notes: ref.watch(allTeacherNotesProvider).value ?? const [],
    resolver: ref.watch(teacherResolverProvider),
    today: ref.watch(todayProvider),
  );
});
