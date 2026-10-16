import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/feed_repository.dart';
import '../data/mock_feed.dart';
import '../domain/models.dart';

/// "Today" in NY. Prototype uses the device date; production would derive it
/// from `DateTime.now().toUtc()` + the America/New_York offset (Q13).
final todayProvider = Provider<ServiceDate>(
  (ref) => ServiceDate.fromDateTime(DateTime.now()),
);

class FeedNotifier extends Notifier<MockFeed> {
  @override
  MockFeed build() {
    _load();
    return MockFeed.build(ref.watch(todayProvider));
  }

  Future<void> _load() async {
    final repo = FeedRepository();
    final realFeed = await repo.loadFeed();
    state = realFeed;
  }

  Future<void> refresh() async {
    final repo = FeedRepository();
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
    required this.entryOnly,
  });

  final Set<StudioId> studios;
  final Set<Genre> genres; // empty = all genres
  final bool entryOnly;

  Set<Tier> get tiers =>
      entryOnly ? {Tier.zeroExperience} : Tier.values.toSet();

  FilterState copyWith({
    Set<StudioId>? studios,
    Set<Genre>? genres,
    bool? entryOnly,
  }) =>
      FilterState(
        studios: studios ?? this.studios,
        genres: genres ?? this.genres,
        entryOnly: entryOnly ?? this.entryOnly,
      );

  bool acceptsTemplate(ClassTemplate t) =>
      studios.contains(t.studioId) &&
      tiers.contains(t.tier) &&
      (genres.isEmpty || t.allGenres.any(genres.contains));
}

class Filter extends Notifier<FilterState> {
  @override
  FilterState build() => FilterState(
        studios: StudioId.values.toSet(),
        genres: const {},
        entryOnly: true, // default: zero-experience tier only
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

  void setEntryOnly(bool v) => state = state.copyWith(entryOnly: v);
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
          filter.acceptsTemplate(templatesById[s.templateId]!))
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
          filter.acceptsTemplate(templatesById[s.templateId]!))
      .toList();
});

/// All series still worth showing (in progress or upcoming).
final upcomingSeriesProvider = Provider<List<WorkshopSeries>>((ref) {
  final feed = ref.watch(feedProvider);
  return feed.series.where((s) => s.endDate.compareTo(feed.today) >= 0).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
});

class SavedSlots extends Notifier<Set<SavedSlot>> {
  @override
  Set<SavedSlot> build() => {...seedSavedSlots};

  bool isSaved(ClassSession s) => state.any((slot) => slot.matches(s));

  void toggleFor(ClassSession s) {
    final slot = SavedSlot(
      templateId: s.templateId,
      weekday: s.serviceDate.weekday,
      startMin: s.startMin,
    );
    final next = {...state};
    next.contains(slot) ? next.remove(slot) : next.add(slot);
    state = next;
  }

  void remove(SavedSlot slot) => state = {...state}..remove(slot);
}

final savedSlotsProvider =
    NotifierProvider<SavedSlots, Set<SavedSlot>>(SavedSlots.new);

class SavedSeries extends Notifier<Set<String>> {
  @override
  Set<String> build() => {...seedSavedSeries};

  void toggle(String id) {
    final next = {...state};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = next;
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
    final match = feed.sessions.where(slot.matches).where((s) => s.serviceDate == date);
    final session = match.isEmpty ? null : match.first;
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
