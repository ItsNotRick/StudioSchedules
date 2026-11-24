import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/teachers.dart';
import 'app_database.dart';

part 'teacher_notes_dao.g.dart';

/// Outcome of a write. [id] and [revision] are what the editor should hold
/// for its next save.
class SaveResult {
  const SaveResult(this.id, this.revision, {this.conflict = false, this.splitOffId});

  final int id;
  final int revision;

  /// The note changed (or was deleted) since the editor loaded it, so the
  /// text was saved as a new note instead of overwriting.
  final bool conflict;

  /// Set when saving split a note shared by several teachers: the id of the
  /// copy that kept the old text for the other teacher(s).
  final int? splitOffId;
}

/// Reads and writes teacher notes. Every write runs in one transaction and
/// never overwrites text it didn't load (see docs/teacher-notes-design.md §6).
@DriftAccessor(tables: [TeacherNotes])
class TeacherNotesDao extends DatabaseAccessor<AppDatabase> with _$TeacherNotesDaoMixin {
  TeacherNotesDao(super.db);

  /// All notes, oldest first.
  Stream<List<TeacherNote>> watchAll() {
    final q = select(teacherNotes)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]);
    return q.watch().map((rows) => rows.map(_toNote).toList());
  }

  Future<List<TeacherNote>> getAll() async {
    final q = select(teacherNotes)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]);
    return (await q.get()).map(_toNote).toList();
  }

  Future<TeacherNote?> getById(int id) async {
    final row = await (select(teacherNotes)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toNote(row);
  }

  /// Creates a note written under [listedName].
  Future<SaveResult> create({required String listedName, required String body}) {
    _checkBody(body);
    return transaction(() async {
      final id = await _insert(body: body, names: [listedName]);
      return SaveResult(id, 1);
    });
  }

  /// Saves [body] to note [id], which the editor loaded at [baseRevision]
  /// while showing teacher [forKey] for a class listed as [listedName].
  ///
  /// - If the note is gone or its revision changed, the text is saved as a
  ///   new note and nothing is overwritten ([SaveResult.conflict]).
  /// - [listedName] is added to the note's names, so spellings accumulate.
  /// - If the note's names now resolve to several teachers, it is split:
  ///   names resolving to [forKey] stay here with the new text, the others
  ///   move to a copy that keeps the old text ([SaveResult.splitOffId]).
  Future<SaveResult> save({
    required int id,
    required int baseRevision,
    required String body,
    required String listedName,
    required String forKey,
    required TeacherResolver resolver,
  }) {
    _checkBody(body);
    return transaction(() async {
      final row = await (select(teacherNotes)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null || row.revision != baseRevision) {
        final newId = await _insert(body: body, names: [listedName]);
        return SaveResult(newId, 1, conflict: true);
      }

      final names = _decodeNames(row.namesJson);
      if (!names.contains(listedName)) names.add(listedName);

      int? splitOffId;
      var keep = names;
      if (resolver.keysFor(names).length > 1) {
        keep = names.where((n) => resolver.keyFor(n) == forKey).toList();
        if (keep.isEmpty) keep = [listedName];
        final others = names.where((n) => !keep.contains(n)).toList();
        if (others.isNotEmpty) {
          splitOffId = await into(teacherNotes).insert(TeacherNotesCompanion.insert(
            body: row.body,
            namesJson: jsonEncode(others),
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
          ));
        }
      }

      final revision = row.revision + 1;
      await (update(teacherNotes)..where((t) => t.id.equals(id))).write(TeacherNotesCompanion(
        body: Value(body),
        namesJson: Value(jsonEncode(keep)),
        revision: Value(revision),
        updatedAt: Value(DateTime.now()),
      ));
      return SaveResult(id, revision, splitOffId: splitOffId);
    });
  }

  /// Combines the notes [rows] (each `(id, revision)` as loaded) into one
  /// with [body], which the user has reviewed. The oldest note is kept with
  /// the union of all names; the others are deleted. Returns null and
  /// changes nothing if any note is gone or has changed.
  Future<SaveResult?> combine({required List<(int, int)> rows, required String body}) {
    _checkBody(body);
    if (rows.length < 2) throw ArgumentError.value(rows, 'rows', 'need at least two notes');
    return transaction(() async {
      final ids = rows.map((r) => r.$1).toList();
      final loaded = await (select(teacherNotes)..where((t) => t.id.isIn(ids))).get();
      if (loaded.length != rows.length) return null;
      final byId = {for (final r in loaded) r.id: r};
      for (final (id, rev) in rows) {
        if (byId[id]?.revision != rev) return null;
      }
      loaded.sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
      final target = loaded.first;
      final names = <String>[];
      for (final r in loaded) {
        for (final n in _decodeNames(r.namesJson)) {
          if (!names.contains(n)) names.add(n);
        }
      }
      final revision = target.revision + 1;
      await (update(teacherNotes)..where((t) => t.id.equals(target.id))).write(TeacherNotesCompanion(
        body: Value(body),
        namesJson: Value(jsonEncode(names)),
        revision: Value(revision),
        updatedAt: Value(DateTime.now()),
      ));
      await (delete(teacherNotes)..where((t) => t.id.isIn(ids.where((i) => i != target.id)))).go();
      return SaveResult(target.id, revision);
    });
  }

  Future<void> deleteNote(int id) => (delete(teacherNotes)..where((t) => t.id.equals(id))).go();

  Future<int> _insert({required String body, required List<String> names}) {
    final now = DateTime.now();
    return into(teacherNotes).insert(TeacherNotesCompanion.insert(
      body: body,
      namesJson: jsonEncode(names),
      createdAt: now,
      updatedAt: now,
    ));
  }

  static void _checkBody(String body) {
    // Blank notes are deleted explicitly, never stored (design §7.3).
    if (body.trim().isEmpty) throw ArgumentError.value(body, 'body', 'must not be blank');
  }

  static List<String> _decodeNames(String json) {
    final decoded = jsonDecode(json);
    return decoded is List ? decoded.whereType<String>().toList() : <String>[];
  }

  static TeacherNote _toNote(TeacherNoteRow r) => TeacherNote(
        id: r.id,
        body: r.body,
        names: List.unmodifiable(_decodeNames(r.namesJson)),
        revision: r.revision,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );
}
