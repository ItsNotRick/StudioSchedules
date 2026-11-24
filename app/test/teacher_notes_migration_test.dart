import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/data/database/app_database.dart';

void main() {
  test('upgrading a v2 database adds teacher_notes and keeps existing data', () async {
    final db = AppDatabase(DatabaseConnection(
      NativeDatabase.memory(setup: (raw) {
        // The v2 schema, as shipped before teacher notes.
        raw.execute('''
          CREATE TABLE cached_feeds (
            "key" TEXT NOT NULL, json_payload TEXT NOT NULL, updated_at INTEGER NOT NULL,
            PRIMARY KEY ("key"));
          CREATE TABLE saved_regimen_slots (
            id TEXT NOT NULL, template_id TEXT NOT NULL, target_weekday INTEGER NOT NULL,
            target_start_min INTEGER NOT NULL, label TEXT NOT NULL, instructor_key TEXT NULL,
            created_at INTEGER NOT NULL, PRIMARY KEY (id));
          CREATE TABLE user_settings (
            "key" TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY ("key"));
          INSERT INTO user_settings ("key", value) VALUES ('saved_series', 's1,s2');
          INSERT INTO saved_regimen_slots VALUES ('slot1', 'tpl', 3, 1170, 'Ana Lopez', 'ana lopez', 0);
          PRAGMA user_version = 2;
        ''');
      }),
      closeStreamsSynchronously: true,
    ));
    addTearDown(db.close);

    expect(await db.getSetting('saved_series'), 's1,s2');
    final slots = await db.getAllSavedSlots();
    expect(slots.single.instructorKey, 'ana lopez');

    final created = await db.teacherNotesDao.create(listedName: 'Ana Lopez', body: 'hello');
    expect((await db.teacherNotesDao.getById(created.id))!.body, 'hello');

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 3);
  });
}
