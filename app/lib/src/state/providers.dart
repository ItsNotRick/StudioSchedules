import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/feed_repository.dart';
import '../data/mock_feed.dart';
import '../domain/models.dart';

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

class FeedNotifier extends Notifier<MockFeed> {
  @override
  MockFeed build() {
    _load();
    return MockFeed.build(ref.watch(todayProvider));
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final repo = FeedRepository(database: db);
    final realFeed = await repo.loadFeed();
    state = realFeed;
  }

  Future<void> refresh() async {
    final db = ref.read(appDatabaseProvider);
    final repo = FeedRepository(database: db);
    final realFeed = await repo.loadFeed();
    state = realFeed;
  }
}

final feedProvider = NotifierProvider<FeedNotifier, MockFeed>(FeedNotifier.new);

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
  final feed = ref.watch(feedProvider);
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
  final feed = ref.watch(feedProvider);
  final filter = ref.watch(filterProvider);
  return feed.series
      .where((s) =>
          s.startDate == date &&
          filter.acceptsTemplate(getTemplate(s.templateId)))
      .toList();
});

/// All series still worth showing (in progress or upcoming) that pass the active filter.
final upcomingSeriesProvider = Provider<List<WorkshopSeries>>((ref) {
  final feed = ref.watch(feedProvider);
  final filter = ref.watch(filterProvider);
  final today = ref.watch(todayProvider);
  return feed.series
      .where((s) =>
          s.endDate.compareTo(today) >= 0 &&
          filter.acceptsTemplate(getTemplate(s.templateId)))
      .toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
});

class SavedSlots extends Notifier<Set<SavedSlot>> {
  final Set<SavedSlot> _addedBeforeLoad = {};
  final Set<SavedSlot> _removedBeforeLoad = {};
  bool _isLoaded = false;

  @override
  Set<SavedSlot> build() {
    _addedBeforeLoad.clear();
    _removedBeforeLoad.clear();
    _isLoaded = false;
    _loadFromDb();
    return {...seedSavedSlots};
  }

  Future<void> _loadFromDb() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final dbSlots = await db.getAllSavedSlots();
      final loaded = dbSlots
          .map((s) => SavedSlot(
                templateId: s.templateId,
                weekday: s.targetWeekday,
                startMin: s.targetStartMin,
                instructor:
                    (s.label.isNotEmpty && s.label != s.templateId) ? s.label : null,
              ))
          .toSet();
      _isLoaded = true;
      state = ({...state, ...loaded, ..._addedBeforeLoad})
        ..removeAll(_removedBeforeLoad);
    } catch (_) {
      _isLoaded = true;
    }
  }

  bool isSaved(ClassSession s) => state.any((slot) => slot.matches(s));

  void toggleFor(ClassSession s) {
    final existingMatches = state.where((slot) => slot.matches(s)).toList();
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
      final slot = SavedSlot(
        templateId: s.templateId,
        weekday: s.serviceDate.weekday,
        startMin: s.startMin,
        instructor: s.instructor,
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
    if (slot.instructor == null || slot.instructor!.isEmpty) return base;
    final cleanInst =
        slot.instructor!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '${base}_$cleanInst';
  }

  void _persistSlotToggle(SavedSlot slot, bool isAdded) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final id = _slotDbId(slot);
      if (isAdded) {
        await db.insertOrUpdateSlot(SavedRegimenSlotsCompanion.insert(
          id: id,
          templateId: slot.templateId,
          targetWeekday: slot.weekday,
          targetStartMin: slot.startMin,
          label: slot.instructor ?? slot.templateId,
          createdAt: DateTime.now(),
        ));
      } else {
        await db.deleteSlot(id);
        // Also delete legacy key without instructor suffix if present
        final legacyId = '${slot.templateId}_${slot.weekday}_${slot.startMin}';
        if (legacyId != id) {
          await db.deleteSlot(legacyId);
        }
      }
    } catch (_) {}
  }
}

final savedSlotsProvider =
    NotifierProvider<SavedSlots, Set<SavedSlot>>(SavedSlots.new);

class SavedSeries extends Notifier<Set<String>> {
  final Set<String> _addedBeforeLoad = {};
  final Set<String> _removedBeforeLoad = {};
  bool _isLoaded = false;

  @override
  Set<String> build() {
    _addedBeforeLoad.clear();
    _removedBeforeLoad.clear();
    _isLoaded = false;
    _loadFromDb();
    return {...seedSavedSeries};
  }

  Future<void> _loadFromDb() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final val = await db.getSetting('saved_series');
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

  void _persist(Set<String> series) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.setSetting('saved_series', series.join(','));
    } catch (_) {}
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

/// Resolves every saved slot for the week starting [weekStart].
final resolvedRegimenProvider =
    Provider.family<List<ResolvedSlot>, ServiceDate>((ref, weekStart) {
  final feed = ref.watch(feedProvider);
  final saved = ref.watch(savedSlotsProvider);
  final out = <ResolvedSlot>[];
  for (final slot in saved) {
    final date = weekStart.addDays(slot.weekday - 1);
    final matches = feed.sessions
        .where(slot.matches)
        .where((s) => s.serviceDate == date)
        .toList();
    // Prefer scheduled sessions over cancelled/removed if multiple match
    matches.sort((a, b) => a.status.index.compareTo(b.status.index));
    final session = matches.isEmpty ? null : matches.first;
    final health = switch (session) {
      null => SlotHealth.notOnSchedule,
      ClassSession(status: SessionStatus.removed) => SlotHealth.removed,
      ClassSession(status: SessionStatus.cancelled) => SlotHealth.cancelled,
      ClassSession(isSubstitute: true) => SlotHealth.substitute,
      _ => SlotHealth.ok,
    };
    out.add(ResolvedSlot(slot, date, session, health));
  }
  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.slot.startMin.compareTo(b.slot.startMin);
  });
  return out;
});
