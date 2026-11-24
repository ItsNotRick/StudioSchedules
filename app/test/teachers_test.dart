import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/data/feed_repository.dart';
import 'package:nyc_dance_calendar/src/domain/models.dart';
import 'package:nyc_dance_calendar/src/domain/teachers.dart';

const _day = ServiceDate(2026, 11, 25);

ClassSession _session(
  String id,
  String instructor, {
  String? key,
  StudioId studio = StudioId.steps,
  ServiceDate date = _day,
  SessionStatus status = SessionStatus.scheduled,
}) =>
    ClassSession(
      id: id,
      templateId: 'tpl',
      studioId: studio,
      serviceDate: date,
      startMin: 600,
      endMin: 690,
      instructor: instructor,
      instructorKey: key,
      isSubstitute: false,
      status: status,
      bookingUrl: 'https://example.com',
    );

TeacherNote _note(int id, String body, List<String> names, {int minute = 0}) => TeacherNote(
      id: id,
      body: body,
      names: names,
      revision: 1,
      createdAt: DateTime(2026, 11, 1, 12, minute),
      updatedAt: DateTime(2026, 11, 1, 12, minute),
    );

const _kathyAlias = {'kathy sullivan': 'kathryn sullivan', 'kathryn sullivan': 'kathryn sullivan'};

void main() {
  group('TeacherResolver', () {
    test('uses the alias map, else the normalized name', () {
      final r = TeacherResolver.build(aliases: _kathyAlias, sessions: const []);
      expect(r.keyFor('Kathy  Sullivan'), 'kathryn sullivan');
      expect(r.keyFor('Ana Lopez'), 'ana lopez');
    });

    test('session keys win over the alias map', () {
      final r = TeacherResolver.build(
        aliases: {'ronald k. alexander': 'something else'},
        sessions: [_session('a', 'Ronald K. Alexander', key: 'ronald alexander')],
      );
      expect(r.keyFor('Ronald K. Alexander'), 'ronald alexander');
    });

    test('a feed with instructorKey but no alias map still matches sessions', () {
      final sessions = [
        _session('a', 'Kathy Sullivan', key: 'kathryn sullivan'),
        _session('b', 'Kathryn Sullivan', key: 'kathryn sullivan'),
        _session('c', 'Ana Lopez'),
      ];
      final r = TeacherResolver.build(aliases: const {}, sessions: sessions);
      for (final s in sessions) {
        expect(r.keyFor(s.instructor), s.matchKey);
      }
    });

    test('placeholders', () {
      final r = TeacherResolver.build(aliases: const {}, sessions: const []);
      expect(r.isPlaceholder(r.keyFor('STAFF')), isTrue);
      expect(r.isPlaceholder(r.keyFor('Guest Artist')), isTrue);
      expect(r.isPlaceholder(''), isTrue);
      expect(r.isPlaceholder(r.keyFor('Staffan Larsson')), isFalse);
      final custom = TeacherResolver.build(aliases: const {}, sessions: const [], placeholders: ['q']);
      expect(custom.isPlaceholder('q'), isTrue);
      expect(custom.isPlaceholder('staff'), isFalse);
    });
  });

  group('note ownership', () {
    final kathy = _note(1, 'counts in 7s', ['Kathy Sullivan']);
    final kathryn = _note(2, 'lots of floor work', ['Kathryn Sullivan'], minute: 5);

    test('before an alias exists the notes belong to different teachers', () {
      final r = TeacherResolver.build(aliases: const {}, sessions: const []);
      expect(notesForTeacher('kathy sullivan', [kathy, kathryn], r).map((n) => n.id), [1]);
      expect(notesForTeacher('kathryn sullivan', [kathy, kathryn], r).map((n) => n.id), [2]);
    });

    test('adding an alias shows both notes under one teacher, oldest first', () {
      final r = TeacherResolver.build(aliases: _kathyAlias, sessions: const []);
      expect(notesForTeacher('kathryn sullivan', [kathryn, kathy], r).map((n) => n.id), [1, 2]);
      expect(notesForTeacher('kathy sullivan', [kathy, kathryn], r), isEmpty);
    });

    test('a note whose names resolve to two teachers shows under both', () {
      final shared = _note(3, 'shared', ['Kathy Sullivan', 'Kathryn Sullivan']);
      final r = TeacherResolver.build(aliases: const {}, sessions: const []);
      expect(notesForTeacher('kathy sullivan', [shared], r), [shared]);
      expect(notesForTeacher('kathryn sullivan', [shared], r), [shared]);
    });

    test('flip-flopping alias maps only regroups, never changes notes', () {
      final notes = [kathy, kathryn];
      final withAlias = TeacherResolver.build(aliases: _kathyAlias, sessions: const []);
      final without = TeacherResolver.build(aliases: const {}, sessions: const []);
      for (final r in [withAlias, without, withAlias, without]) {
        notesForTeacher('kathryn sullivan', notes, r);
      }
      expect(notes, [kathy, kathryn]);
      expect(notesForTeacher('kathy sullivan', notes, without), [kathy]);
    });
  });

  test('combinedBody drops blanks and duplicates, oldest first', () {
    expect(
      combinedBody([
        _note(1, 'A', ['x']),
        _note(2, '  ', ['x']),
        _note(3, 'B', ['x']),
        _note(4, 'A', ['x']),
      ]),
      'A\n\nB',
    );
  });

  group('buildTeacherDirectory', () {
    test('lists schedule teachers and note-only teachers, skips placeholders', () {
      final sessions = [
        _session('a', 'Kathy Sullivan', key: 'kathryn sullivan', studio: StudioId.steps),
        _session('b', 'Kathryn Sullivan', key: 'kathryn sullivan', studio: StudioId.peridance),
        _session('c', 'Kathryn Sullivan', key: 'kathryn sullivan', studio: StudioId.peridance),
        _session('d', 'Staff', key: 'staff'),
        _session('e', 'Ana Lopez', date: const ServiceDate(2026, 11, 20)), // past
        _session('f', 'Ana Lopez', status: SessionStatus.cancelled),
        _session('g', 'Gone Teacher', status: SessionStatus.removed),
      ];
      final notes = [
        _note(1, 'counts in 7s', ['Kathy Sullivan']),
        _note(2, 'left in October', ['Old Teacher']),
      ];
      final r = TeacherResolver.build(aliases: _kathyAlias, sessions: sessions);
      final dir = buildTeacherDirectory(sessions: sessions, notes: notes, resolver: r, today: _day);

      expect(dir.map((e) => e.key), ['ana lopez', 'kathryn sullivan', 'old teacher']);

      final kathryn = dir[1];
      expect(kathryn.displayName, 'Kathryn Sullivan'); // most common spelling
      expect(kathryn.studios, {StudioId.steps, StudioId.peridance});
      expect(kathryn.upcomingSessions.map((s) => s.id), ['a', 'b', 'c']);
      expect(kathryn.notes.map((n) => n.id), [1]);
      expect(kathryn.onSchedule, isTrue);

      final ana = dir[0];
      expect(ana.upcomingSessions, isEmpty); // past and cancelled only
      expect(ana.onSchedule, isTrue);

      final old = dir[2];
      expect(old.displayName, 'Old Teacher');
      expect(old.onSchedule, isFalse);
      expect(old.studios, isEmpty);
    });
  });

  group('feed parsing', () {
    test('alias map and placeholders are parsed defensively', () {
      expect(FeedRepository.parseInstructorAliases(null), isEmpty);
      expect(FeedRepository.parseInstructorAliases({'a': 'b', 'c': 3}), {'a': 'b'});
      expect(FeedRepository.parsePlaceholderInstructors(null), defaultPlaceholderInstructors);
      expect(FeedRepository.parsePlaceholderInstructors([' Staff ', 4, '']), ['staff']);
    });
  });
}
