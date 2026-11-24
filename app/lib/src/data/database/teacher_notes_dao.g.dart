// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'teacher_notes_dao.dart';

// ignore_for_file: type=lint
mixin _$TeacherNotesDaoMixin on DatabaseAccessor<AppDatabase> {
  $TeacherNotesTable get teacherNotes => attachedDatabase.teacherNotes;
  TeacherNotesDaoManager get managers => TeacherNotesDaoManager(this);
}

class TeacherNotesDaoManager {
  final _$TeacherNotesDaoMixin _db;
  TeacherNotesDaoManager(this._db);
  $$TeacherNotesTableTableManager get teacherNotes =>
      $$TeacherNotesTableTableManager(_db.attachedDatabase, _db.teacherNotes);
}
