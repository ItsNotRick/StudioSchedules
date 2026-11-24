import 'dart:math';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/data/database/app_database.dart';
import 'package:nyc_dance_calendar/src/data/database/teacher_notes_dao.dart';
import 'package:nyc_dance_calendar/src/domain/teachers.dart';

AppDatabase _memoryDb() =>
    AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));

final _noAlias = TeacherResolver.build(aliases: const {}, sessions: const []);
final _kathyAlias = TeacherResolver.build(
  aliases: const {'kathy sullivan': 'kathryn sullivan', 'kathryn sullivan': 'kathryn sullivan'},
  sessions: const [],
);

void main() {
  late AppDatabase db;
  late TeacherNotesDao dao;

  setUp(() {
    db = _memoryDb();
    dao = db.teacherNotesDao;
  });
  tearDown(() => db.close());

  test('create stores the body and the spelling', () async {
    final r = await dao.create(listedName: 'Kathy Sullivan', body: 'counts in 7s');
    expect(r.revision, 1);
    final n = (await dao.getById(r.id))!;
    expect(n.body, 'counts in 7s');
    expect(n.names, ['Kathy Sullivan']);
  });

  test('blank bodies are rejected', () async {
    expect(() => dao.create(listedName: 'A', body: '  \n'), throwsArgumentError);
  });

  test('save adds a new spelling and bumps the revision', () async {
    final c = await dao.create(listedName: 'Kathy Sullivan', body: 'v1');
    final s = await dao.save(
      id: c.id,
      baseRevision: c.revision,
      body: 'v2',
      listedName: 'Kathryn Sullivan',
      forKey: 'kathryn sullivan',
      resolver: _kathyAlias,
    );
    expect(s.conflict, isFalse);
    expect(s.splitOffId, isNull);
    expect(s.revision, 2);
    final n = (await dao.getById(c.id))!;
    expect(n.body, 'v2');
    expect(n.names, ['Kathy Sullivan', 'Kathryn Sullivan']);
  });

  test('a stale revision saves a new note and leaves the old one alone', () async {
    final c = await dao.create(listedName: 'Ana Lopez', body: 'original');
    await dao.save(
        id: c.id, baseRevision: 1, body: 'edited elsewhere', listedName: 'Ana Lopez', forKey: 'ana lopez', resolver: _noAlias);
    final s = await dao.save(
        id: c.id, baseRevision: 1, body: 'my stale edit', listedName: 'Ana Lopez', forKey: 'ana lopez', resolver: _noAlias);
    expect(s.conflict, isTrue);
    expect(s.id, isNot(c.id));
    final all = await dao.getAll();
    expect(all.map((n) => n.body), ['edited elsewhere', 'my stale edit']);
  });

  test('saving a deleted note saves a new note', () async {
    final c = await dao.create(listedName: 'Ana Lopez', body: 'x');
    await dao.deleteNote(c.id);
    final s = await dao.save(
        id: c.id, baseRevision: 1, body: 'still typing', listedName: 'Ana Lopez', forKey: 'ana lopez', resolver: _noAlias);
    expect(s.conflict, isTrue);
    expect((await dao.getAll()).single.body, 'still typing');
  });

  test('saving a note shared by two teachers splits it (copy-on-write)', () async {
    // Written while Kathy and Kathryn were known to be one person...
    final c = await dao.create(listedName: 'Kathy Sullivan', body: 'shared text');
    final s1 = await dao.save(
        id: c.id,
        baseRevision: 1,
        body: 'shared text',
        listedName: 'Kathryn Sullivan',
        forKey: 'kathryn sullivan',
        resolver: _kathyAlias);
    // ...then the alias was removed, and the user edits from a Kathryn class.
    final s2 = await dao.save(
        id: c.id,
        baseRevision: s1.revision,
        body: 'shared text + kathryn only',
        listedName: 'Kathryn Sullivan',
        forKey: 'kathryn sullivan',
        resolver: _noAlias);
    expect(s2.splitOffId, isNotNull);

    final edited = (await dao.getById(c.id))!;
    expect(edited.names, ['Kathryn Sullivan']);
    expect(edited.body, 'shared text + kathryn only');

    final copy = (await dao.getById(s2.splitOffId!))!;
    expect(copy.names, ['Kathy Sullivan']);
    expect(copy.body, 'shared text');
  });

  test('combine keeps the oldest note with all spellings', () async {
    final a = await dao.create(listedName: 'Kathy Sullivan', body: 'A');
    final b = await dao.create(listedName: 'Kathryn Sullivan', body: 'B');
    final r = await dao.combine(rows: [(b.id, 1), (a.id, 1)], body: 'A\n\nB');
    expect(r, isNotNull);
    expect(r!.id, a.id);
    final all = await dao.getAll();
    expect(all, hasLength(1));
    expect(all.single.body, 'A\n\nB');
    expect(all.single.names, ['Kathy Sullivan', 'Kathryn Sullivan']);
  });

  test('combine changes nothing if a note changed', () async {
    final a = await dao.create(listedName: 'Kathy Sullivan', body: 'A');
    final b = await dao.create(listedName: 'Kathryn Sullivan', body: 'B');
    await dao.save(
        id: b.id, baseRevision: 1, body: 'B2', listedName: 'Kathryn Sullivan', forKey: 'kathryn sullivan', resolver: _noAlias);
    expect(await dao.combine(rows: [(a.id, 1), (b.id, 1)], body: 'A\n\nB'), isNull);
    expect((await dao.getAll()).map((n) => n.body), ['A', 'B2']);
  });

  test('50 autosaves leave one note with no repeated text', () async {
    var r = await dao.create(listedName: 'Ana Lopez', body: 'n');
    for (var i = 1; i <= 50; i++) {
      r = await dao.save(
          id: r.id,
          baseRevision: r.revision,
          body: 'note v$i',
          listedName: 'Ana Lopez',
          forKey: 'ana lopez',
          resolver: _noAlias);
      expect(r.conflict, isFalse);
    }
    final all = await dao.getAll();
    expect(all.single.body, 'note v50');
    expect(all.single.revision, 51);
    expect(all.single.names, ['Ana Lopez']);
  });

  test('watchAll emits after each committed write', () async {
    final emissions = <List<String>>[];
    final sub = dao.watchAll().listen((ns) => emissions.add(ns.map((n) => n.body).toList()));
    await pumpEventQueue();
    final c = await dao.create(listedName: 'Ana Lopez', body: 'one');
    await pumpEventQueue();
    await dao.save(id: c.id, baseRevision: 1, body: 'two', listedName: 'Ana Lopez', forKey: 'ana lopez', resolver: _noAlias);
    await pumpEventQueue();
    await sub.cancel();
    expect(emissions, [
      <String>[],
      ['one'],
      ['two'],
    ]);
  });

  test('random edits, alias changes and combines never lose text', () async {
    final rng = Random(42);
    const names = ['Kathy Sullivan', 'Kathryn Sullivan', 'Ana Lopez', 'Ana  Lopez'];
    final resolvers = [_noAlias, _kathyAlias];
    // Bodies that must exist, as a multiset.
    final expected = <String>[];
    // Revisions the "editor" last saw, sometimes stale on purpose.
    final seen = <int, int>{};
    var counter = 0;

    for (var step = 0; step < 300; step++) {
      final all = await dao.getAll();
      final resolver = resolvers[rng.nextInt(2)];
      final op = all.isEmpty ? 0 : rng.nextInt(10);
      final body = 'text ${counter++}';

      if (op < 3) {
        final r = await dao.create(listedName: names[rng.nextInt(names.length)], body: body);
        seen[r.id] = r.revision;
        expected.add(body);
      } else if (op < 9) {
        final n = all[rng.nextInt(all.length)];
        final listed = n.names[rng.nextInt(n.names.length)];
        final base = rng.nextInt(5) == 0 ? (seen[n.id] ?? 0) - 1 : n.revision;
        final r = await dao.save(
          id: n.id,
          baseRevision: base,
          body: body,
          listedName: listed,
          forKey: resolver.keyFor(listed),
          resolver: resolver,
        );
        seen[r.id] = r.revision;
        expected.add(body);
        // Only a successful, unsplit save replaces the old text.
        if (!r.conflict && r.splitOffId == null) expected.remove(n.body);
      } else {
        final key = resolver.keyFor(all.first.latestName);
        final group = notesForTeacher(key, all, resolver);
        if (group.length >= 2) {
          final combined = combinedBody(group);
          final r = await dao.combine(rows: [for (final g in group) (g.id, g.revision)], body: combined);
          expect(r, isNotNull);
          for (final g in group) {
            expected.remove(g.body);
          }
          expected.add(combined);
        }
      }

      final now = await dao.getAll();
      expect(now.map((n) => n.body).toList()..sort(), (List.of(expected)..sort()), reason: 'step $step');
      for (final n in now) {
        expect(n.names, isNotEmpty);
        expect(n.body.trim(), isNotEmpty);
      }
    }
  });
}
