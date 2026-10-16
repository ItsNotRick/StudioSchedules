import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

class CachedFeeds extends Table {
  TextColumn get key => text()();
  TextColumn get jsonPayload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

class SavedRegimenSlots extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text()();
  IntColumn get targetWeekday => integer()();
  IntColumn get targetStartMin => integer()();
  TextColumn get label => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class UserSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [CachedFeeds, SavedRegimenSlots, UserSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  // Cached feed operations
  Future<void> saveFeedJson(String key, String jsonPayload) {
    return into(cachedFeeds).insertOnConflictUpdate(
      CachedFeedsCompanion.insert(
        key: key,
        jsonPayload: jsonPayload,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<String?> getFeedJson(String key) async {
    final query = select(cachedFeeds)..where((tbl) => tbl.key.equals(key));
    final result = await query.getSingleOrNull();
    return result?.jsonPayload;
  }

  // Saved regimen slots
  Future<List<SavedRegimenSlot>> getAllSavedSlots() {
    return select(savedRegimenSlots).get();
  }

  Future<void> insertOrUpdateSlot(SavedRegimenSlotsCompanion slot) {
    return into(savedRegimenSlots).insertOnConflictUpdate(slot);
  }

  Future<int> deleteSlot(String id) {
    return (delete(savedRegimenSlots)..where((tbl) => tbl.id.equals(id))).go();
  }

  // User settings
  Future<void> setSetting(String key, String value) {
    return into(userSettings).insertOnConflictUpdate(
      UserSettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<String?> getSetting(String key) async {
    final query = select(userSettings)..where((tbl) => tbl.key.equals(key));
    final row = await query.getSingleOrNull();
    return row?.value;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'nyc_dance_calendar.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
