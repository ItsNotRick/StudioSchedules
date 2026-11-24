import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/data/database/app_database.dart';
import 'package:nyc_dance_calendar/src/domain/models.dart';
import 'package:nyc_dance_calendar/src/state/providers.dart';

const _tpl = 'ailey_contemporaryModern_open_contemporary';
const _wed = ServiceDate(2026, 11, 11); // Wednesday

ClassSession _session(
  String id,
  String instructor, {
  String? key,
  bool isSub = false,
  SessionStatus status = SessionStatus.scheduled,
  int startMin = 1170,
}) =>
    ClassSession(
      id: id,
      templateId: _tpl,
      studioId: StudioId.ailey,
      serviceDate: _wed,
      startMin: startMin,
      endMin: startMin + 90,
      instructor: instructor,
      instructorKey: key,
      isSubstitute: isSub,
      status: status,
      bookingUrl: 'https://ailey.org',
    );

SavedSlot _slot(String instructor, {String? key}) => SavedSlot(
      templateId: _tpl,
      weekday: 3,
      startMin: 1170,
      instructor: instructor,
      instructorKey: key ?? normalizeInstructor(instructor),
    );

SlotHealth _health(SavedSlot slot, List<ClassSession> sessions,
        [Set<SavedSlot>? saved]) =>
    slotHealth(resolveSlot(slot, _wed, sessions, saved ?? {slot}));

void main() {
  test('normalizeInstructor collapses whitespace, drops quotes, lowercases', () {
    expect(normalizeInstructor('  Kathy   "K"  Sullivan '), 'kathy k sullivan');
    expect(normalizeInstructor("Jazzy J (Boog Soulfire)"),
        'jazzy j (boog soulfire)');
  });

  test('regular teacher matches exactly and is ok', () {
    final slot = _slot('Adriana Pierce');
    expect(_health(slot, [_session('a', 'Adriana Pierce')]), SlotHealth.ok);
  });

  test('flagged substitute still matches, as substitute', () {
    final slot = _slot('Adriana Pierce');
    final sub = _session('a', 'Sam Lee', isSub: true);
    final m = resolveSlot(slot, _wed, [sub], {slot});
    expect(m?.session.id, 'a');
    expect(m?.exact, isFalse);
    expect(slotHealth(m), SlotHealth.substitute);
  });

  test('unflagged teacher change (e.g. Steps) is still a substitute', () {
    final slot = _slot('Adriana Pierce');
    expect(_health(slot, [_session('a', 'Sam Lee')]), SlotHealth.substitute);
  });

  test('alias spelling matches via canonical instructorKey', () {
    final slot = _slot('Kathryn Sullivan', key: 'kathryn sullivan');
    final s = _session('a', 'Kathy Sullivan', key: 'kathryn sullivan');
    expect(slot.matches(s), isTrue);
    expect(_health(slot, [s]), SlotHealth.ok);
  });

  test('legacy slot without a key matches by display name', () {
    const legacy = SavedSlot(
        templateId: _tpl, weekday: 3, startMin: 1170, instructor: 'Kathy Sullivan');
    final s = _session('a', 'Kathy Sullivan', key: 'kathryn sullivan');
    expect(legacy.matches(s), isTrue);
  });

  test('cancelled and removed still win over substitute', () {
    final slot = _slot('Adriana Pierce');
    expect(
        _health(slot, [_session('a', 'Sam Lee', status: SessionStatus.cancelled)]),
        SlotHealth.cancelled);
    expect(_health(slot, []), SlotHealth.notOnSchedule);
    expect(_health(slot, [_session('a', 'Sam Lee', startMin: 1200)]),
        SlotHealth.notOnSchedule);
  });

  group('concurrent sections', () {
    final brinda = _slot('Brinda Guha');
    final nicholas = _slot('Nicholas Palmquist');

    test('both saved: subbed section resolves to the sub, other stays exact', () {
      final sessions = [
        _session('x', 'Sam Lee'),
        _session('n', 'Nicholas Palmquist'),
      ];
      final saved = {brinda, nicholas};
      expect(resolveSlot(brinda, _wed, sessions, saved)?.session.id, 'x');
      expect(_health(brinda, sessions, saved), SlotHealth.substitute);
      expect(_health(nicholas, sessions, saved), SlotHealth.ok);
    });

    test('one saved, unflagged stranger: ambiguous, not matched', () {
      final sessions = [
        _session('x', 'Sam Lee'),
        _session('n', 'Nicholas Palmquist'),
      ];
      expect(_health(brinda, sessions), SlotHealth.notOnSchedule);
    });

    test('one saved, studio-flagged sub breaks the tie', () {
      final sessions = [
        _session('x', 'Sam Lee', isSub: true),
        _session('n', 'Nicholas Palmquist'),
      ];
      expect(resolveSlot(brinda, _wed, sessions, {brinda})?.session.id, 'x');
    });

    test('both sections subbed by different people: ambiguous', () {
      final sessions = [
        _session('x', 'Sam Lee', isSub: true),
        _session('y', 'Pat Kim', isSub: true),
      ];
      final saved = {brinda, nicholas};
      expect(_health(brinda, sessions, saved), SlotHealth.notOnSchedule);
    });
  });

  test('slotsClaiming finds the saved slot for a subbed session', () {
    final slot = _slot('Adriana Pierce');
    final sub = _session('a', 'Sam Lee', isSub: true);
    final other = _session('b', 'Sam Lee', startMin: 1200);
    expect(slotsClaiming(sub, [sub, other], {slot}), [slot]);
    expect(slotsClaiming(other, [sub, other], {slot}), isEmpty);
  });

    test('a slot claims only its own session among concurrent sections', () {
    final brinda = _slot('Brinda Guha');
    final b = _session('b', 'Brinda Guha');
    final n = _session('n', 'Nicholas Palmquist');
    expect(slotsClaiming(b, [b, n], {brinda}), [brinda]);
    expect(slotsClaiming(n, [b, n], {brinda}), isEmpty);
  });

  test('absent concurrent section does not claim other known regular teacher as sub', () {
    final brinda = _slot('Brinda Guha');
    const wk1 = ServiceDate(2026, 11, 11);
    const wk2 = ServiceDate(2026, 11, 18);
    final allSessions = [
      _session('b1', 'Brinda Guha'),
      _session('n1', 'Nicholas Palmquist'),
      ClassSession(
        id: 'n2',
        templateId: _tpl,
        studioId: StudioId.ailey,
        serviceDate: wk2,
        startMin: 1170,
        endMin: 1260,
        instructor: 'Nicholas Palmquist',
        isSubstitute: false,
        status: SessionStatus.scheduled,
        bookingUrl: 'https://ailey.org',
      ),
    ];
    expect(allSessions.first.serviceDate, wk1);
    expect(
      slotHealth(resolveSlot(brinda, wk2, allSessions, {brinda})),
      SlotHealth.notOnSchedule,
    );
  });

  test('buildSavedSlotForSession resolves regular teacher when saving a subbed session', () {
    const wk1 = ServiceDate(2026, 11, 11);
    const wk2 = ServiceDate(2026, 11, 18);
    final subWithExplicit = ClassSession(
      id: 'sub_explicit',
      templateId: _tpl,
      studioId: StudioId.pmt,
      serviceDate: wk1,
      startMin: 1170,
      endMin: 1260,
      instructor: 'Temp Sub',
      regularInstructor: 'Shirlene Quigley',
      isSubstitute: true,
      status: SessionStatus.scheduled,
      bookingUrl: 'https://pmt.example',
    );
    final savedExplicit = buildSavedSlotForSession(subWithExplicit, [subWithExplicit]);
    expect(savedExplicit.instructor, 'Shirlene Quigley');
    expect(savedExplicit.instructorKey, 'shirlene quigley');

    final subInferred = _session('s_sub', 'Temp Sub', isSub: true);
    final wk2Regular = ClassSession(
      id: 'wk2_reg',
      templateId: _tpl,
      studioId: StudioId.ailey,
      serviceDate: wk2,
      startMin: 1170,
      endMin: 1260,
      instructor: 'Adriana Pierce',
      instructorKey: 'adriana pierce',
      isSubstitute: false,
      status: SessionStatus.scheduled,
      bookingUrl: 'https://ailey.org',
    );
    final savedInferred = buildSavedSlotForSession(subInferred, [subInferred, wk2Regular]);
    expect(savedInferred.instructor, 'Adriana Pierce');

    final subOnly = buildSavedSlotForSession(subInferred, [subInferred]);
    expect(subOnly.instructor, isNull);
    expect(subOnly.instructorKey, isNull);
  });

  test('nyWallClockToUtc handles EST, EDT, DST boundaries, and 1440 rollover', () {
    expect(
      nyWallClockToUtc(const ServiceDate(2026, 1, 15), 18 * 60),
      DateTime.utc(2026, 1, 15, 23, 0),
    );
    expect(
      nyWallClockToUtc(const ServiceDate(2026, 7, 15), 18 * 60),
      DateTime.utc(2026, 7, 15, 22, 0),
    );
    expect(
      nyWallClockToUtc(const ServiceDate(2026, 11, 1), 30),
      DateTime.utc(2026, 11, 1, 4, 30),
    );
    expect(
      nyWallClockToUtc(const ServiceDate(2026, 11, 1), 150),
      DateTime.utc(2026, 11, 1, 7, 30),
    );
    expect(
      nyWallClockToUtc(const ServiceDate(2026, 11, 24), 1440),
      DateTime.utc(2026, 11, 25, 5, 0),
    );
    expect(formatTime(1440), '12am');
  });

  test('SavedSlots deletes alias rows without leaving zombies or deleting legacy slots', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed an instructor-less legacy slot plus a pre-migration alias-keyed row.
    const legacyId = '${_tpl}_3_1170';
    await db.insertOrUpdateSlot(SavedRegimenSlotsCompanion.insert(
      id: legacyId,
      templateId: _tpl,
      targetWeekday: 3,
      targetStartMin: 1170,
      label: _tpl,
      instructorKey: const Value(null),
      createdAt: DateTime.utc(2026, 11, 1),
    ));
    await db.insertOrUpdateSlot(SavedRegimenSlotsCompanion.insert(
      id: '${_tpl}_3_1170_kathysullivan',
      templateId: _tpl,
      targetWeekday: 3,
      targetStartMin: 1170,
      label: 'Kathy Sullivan',
      instructorKey: const Value('kathryn sullivan'),
      createdAt: DateTime.utc(2026, 11, 2),
    ));

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    container.read(savedSlotsProvider);
    await pumpEventQueue();

    const kathrynAlias = SavedSlot(
      templateId: _tpl,
      weekday: 3,
      startMin: 1170,
      instructor: 'Kathryn Sullivan',
      instructorKey: 'kathryn sullivan',
    );
    container.read(savedSlotsProvider.notifier).remove(kathrynAlias);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final remaining = await db.getAllSavedSlots();
    expect(remaining.map((r) => r.id), [legacyId]);
  });
}
