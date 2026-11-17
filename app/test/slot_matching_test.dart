import 'package:flutter_test/flutter_test.dart';
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
}
