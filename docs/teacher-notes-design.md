# Teacher Notes — Design

Status: proposed (rev 2, after design review) · Base: `origin/main` @ `7b383b1` · Branch: `claude/teacher-notes-feature-71dde7`

## 1. Goal

Let the user write and save private notes about a teacher. A note follows the
teacher, not the class: it appears on every class that teacher teaches, at any
studio, and in a new **Teachers** tab (fourth bottom tab, right of My Regimen).

### In scope (v1)
- Free-text notes about a teacher, stored in the app's local database.
- Viewing and editing from the class detail sheet (`_SessionDetail`).
- A Teachers tab: teachers with notes first, then everyone on the current
  schedule, with search. Tapping a teacher opens their notes and upcoming
  classes.
- Notes keep working when aliases in `backend/data/instructors.json` change.

### Out of scope (v1)
- Sync, sharing, accounts.
- Class-scoped notes (room is left for them; see §10).
- The series sheet: the feed has no series today
  (`backend/data/templates.json` has `"series": []`).
- A "Notes on the regular teacher" link on subbed classes: no template sets
  `regularInstructor`, so the app never knows who is being subbed for.
- Rich text, photos, ratings, tags.

## 2. Current state (relevant pieces)

| Area | Today |
|---|---|
| Teacher identity | `ClassSession.instructor` (display string) and `instructorKey` from the feed. The key is the normalized canonical name for registered teachers, otherwise the normalized scraped name. `matchKey => instructorKey ?? normalizeInstructor(instructor)`. |
| Normalization | `normalize_instructor()` (Python) and `normalizeInstructor()` (Dart) must stay identical. |
| Registry | 40 entries in `instructors.json`; 16 of about 244 distinct feed names are registered. `manage_aliases.py` grows it over time. |
| Bundled feed | `app/assets/feed/schedule.json` (generated 2026-11-13) has **no `instructorKey`** on any of its 636 sessions, so every `matchKey` today is the fallback. It has to be regenerated. |
| Remote feed | The default URL in `FeedRepository.effectiveFeedUrl` points to a raw `gh-pages` branch that doesn't exist for this repo. CI deploys through the Pages actions. Unless `FEED_URL` is set, devices only get feeds through app releases. Tracked separately. |
| DB | Drift `schemaVersion = 2`, with a `MigrationStrategy`. `DateTime` is stored as **Unix seconds** (there's no `build.yaml`). |
| State pattern | `SavedSlots` and `SavedSeries` keep the in-memory set as the source of truth, with load-race bookkeeping. |
| Home | The `CalendarViewType` enum (all references are in `main.dart`) drives the NavigationBar, the body switch, and the "Switch Prototype View" popup. The AppBar `bottom` (WeekStrip and FilterRail) and the date subtitle are on every tab. `FeedErrorView` only appears if the bundled asset can't be read. |
| Detail sheet | A modal `DraggableScrollableSheet`. The `session` is captured when the sheet opens; the teacher is one `_InfoRow`. |

## 3. Core idea: nothing changes notes in the background

A note row stores its **text** and the **scraped names it was written under**.
It never stores a teacher key. Which teacher a note belongs to is **worked out
when the note is read**, using the alias map from the feed currently shown:

> A note belongs to teacher *K* if **any** of its names resolves to *K*.

So:

- **An alias is added** (Kathy → Kathryn): the Kathy note and the Kathryn note
  both now belong to `kathryn sullivan`. The teacher shows **two notes**, and
  the user can combine them (§7.3). Nothing is merged automatically.
- **An alias is removed or split**: a note whose names now resolve to two
  teachers shows up under **both**. The first time it's edited from one of
  them, it is **split into two copies** (copy-on-write, §6.3).
- **An alias map arrives out of order or flip-flops**: notes appear grouped
  differently until the next feed. No rows are changed, so nothing can be
  corrupted.

### Why this replaced rev 1

Rev 1 merged and re-keyed notes in the background, inside the feed-cache
transaction. The review found that this:

- **lost or duplicated text** when an autosave raced a merge (the `updatedAt`
  check is only accurate to the second);
- could **freeze the feed cache** if re-keying kept failing;
- could break the unique-key rule partway through applying a plan, and drop
  stored spellings when merged rows were deleted;
- **permanently mixed two people's notes** if a wrong alias was live for even
  one 3-hour CI cycle.

All of these came from rows changing while the user wasn't looking. Rev 2
removes that entirely. The cost is that a teacher can occasionally show more
than one note, which only happens after an alias change and is resolved with
one tap.

## 4. Feed change (backend)

`build_feed.py` adds two top-level fields:

```json
"instructorAliases": {
  "kathy sullivan": "kathryn sullivan",
  "kathryn sullivan": "kathryn sullivan",
  "boog soulfire": "jazzy j",
  "jazzy j (boog soulfire)": "jazzy j",
  "jazzy j": "jazzy j"
},
"placeholderInstructors": ["staff", "tba", "tbd", "guest artist", "special guest", "substitute teacher", "various teachers"]
```

- `instructorAliases` is the existing `canonical_lookup`. Keys and values are
  both `normalize_instructor()` output.
- `placeholderInstructors` is one list shared by Python and Dart. Move the
  exclusion list in `manage_aliases.py` (~line 220) into a shared constant, add
  `staff`, `tba` and `tbd`, and emit it in the feed. The client falls back to a
  built-in copy of the list if the field is missing.
- Bump the feed `version` to `1.1.0`. Both fields are optional for the client.
- **Regenerate and commit the bundled asset** so it has `instructorKey` and
  the new fields.
- New pytest checks on the registry:
  - every alias appears in exactly one entry;
  - the map is idempotent: `m[m[k]] == m[k]`, so there are no chains.

  `canonical_lookup` is last-wins today, so a duplicated alias would otherwise
  be resolved quietly by file order.

## 5. Teacher resolution (client)

```dart
class TeacherResolver {
  /// Built from the displayed feed.
  factory TeacherResolver.fromFeed(Feed feed);
  String keyFor(String listedName);   // alias lookup on normalized name, else normalized name
  bool isPlaceholder(String key);
}
```

The map is built as
`{...feed.instructorAliases, for s in feed.sessions: normalizeInstructor(s.instructor): s.matchKey}`.
Session entries win when the two disagree. Why:

- It guarantees `keyFor(s.instructor) == s.matchKey` for every displayed
  session, even with a feed that has `instructorKey` but no
  `instructorAliases`. (Without this, about 9 current spellings, such as
  "Ronald K. Alexander", would resolve differently on read and on write.)
- It absorbs the client's second HTML-unescape (`feed_repository.dart` ~230),
  because the map is built from the same parsed string that gets stored.

There's one resolver for the whole app, `teacherResolverProvider`, derived from
`currentFeedProvider`. Every read and every write goes through it, so reads
and writes never disagree.

## 6. Data model and data layer

### 6.1 Table (Drift v3)

```dart
class TeacherNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get body => text()();
  TextColumn get namesJson => text()();       // JSON list of scraped names, e.g. ["Kathy Sullivan","Kathryn Sullivan"]
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
```

- One table. There's no key column, no unique index, no child table, no
  foreign keys, and no uuid (an integer autoincrement avoids adding a
  dependency).
- The names are stored as JSON because they're only ever read with their row,
  and the table holds tens of rows.
- `revision` is incremented on every write. Lost-update checks use
  `revision`, never timestamps.
- **Migration:** `schemaVersion => 3`; add `if (from < 3) await m.createTable(teacherNotes);`
  inside the existing `onUpgrade`. Nothing to copy over.

### 6.2 `TeacherNotesDao`

```dart
Stream<List<TeacherNote>> watchAll();
Future<SaveResult> create({required String listedName, required String body});
Future<SaveResult> save({required int id, required int baseRevision, required String body,
                         required String listedName, required TeacherResolver r, required String forKey});
Future<SaveResult> combine({required List<(int id, int rev)> rows, required String body});
Future<void> deleteNote(int id);
```

Every write method runs in **one `transaction()`** and returns
`SaveResult(id, revision)`.

### 6.3 `save` (the only complicated method)

Inside one transaction:

1. Load row `id`. If it's gone, or `revision != baseRevision`, **don't
   overwrite**. Insert the text as a new row with
   `names = [listedName]` and return that row's id. The teacher now shows two
   notes and the user can combine them. Text is never lost. (With no
   background writers, this only happens if the same note is open in two
   editors.)
2. Add `listedName` to the names if it's missing, so spellings accumulate:
   editing at Peridance adds "Kathryn Sullivan" to a note written as
   "Kathy Sullivan" at Steps.
3. **Copy-on-write split:** if the names now resolve to more than one key, the
   names that resolve to `forKey` stay on this row with the new body. The
   others move to a new row that gets the **old** body. Each teacher keeps the
   text written while they were thought to be the same person, and only
   `forKey`'s copy gets the edit.
4. Write `body`, `revision + 1`, `updatedAt = now`.

`combine` checks every `(id, revision)` it's given (on a mismatch, nothing
changes and it returns a conflict so the UI reloads). It then writes the body
the user confirmed and the union of names into the oldest row, and deletes the
rest.

## 7. State and UI

### 7.1 Providers

```dart
final teacherResolverProvider = Provider((ref) => TeacherResolver.fromFeed(ref.watch(currentFeedProvider)));
final allTeacherNotesProvider = StreamProvider((ref) => ref.watch(appDatabaseProvider).teacherNotesDao.watchAll());

/// Notes belonging to [key] under the displayed map, oldest first.
final notesForTeacherProvider = Provider.autoDispose.family<List<TeacherNote>, String>((ref, key) {
  final r = ref.watch(teacherResolverProvider);
  final all = ref.watch(allTeacherNotesProvider).value ?? const [];
  return all.where((n) => n.names.any((x) => r.keyFor(x) == key)).toList();
});

final teacherDirectoryProvider = Provider<List<TeacherEntry>>(...); // §7.4
```

- There's one Drift stream for the whole table, and everything else is
  derived in Dart (tens of rows). When the feed or alias map changes, notes
  regroup automatically.
- None of the `_addedBeforeLoad` bookkeeping is needed.
- Families are `autoDispose`.

### 7.2 Class detail sheet

- Below the instructor `_InfoRow`, add a section **"Your notes on <name>"**,
  keyed by `session.matchKey`:
  - **0 notes:** an outlined "Add a note" button.
  - **1 note:** a preview of up to 4 lines, with "Edit". The full text is
    available to screen readers.
  - **2 or more notes:** stacked previews, each labeled with the spelling it
    was written under ("as Kathy Sullivan"), and a "Combine" link.
- Hidden when the key is a placeholder.
- On a subbed class, the notes shown are the **substitute's** (whoever is
  actually teaching).

### 7.3 Editor, `TeacherNoteEditorPage`

A full-screen route on the **root** navigator, opened from the sheet or the
Teachers tab. Arguments: `teacherKey`, `listedName`, `displayName`, and
optionally the note `id`.

- **Combining:** if the teacher has two or more notes, the editor opens with a
  banner ("You wrote 2 notes for this teacher under different spellings"). It
  offers **Combine**, which pre-fills the bodies (identical ones collapsed,
  oldest first) for the user to review, and **Edit separately**. Combining
  only happens when the user saves that combined text.
- **Autosave:**
  - Save 600 ms after the last keystroke.
  - Only one save is in flight at a time; later edits are combined into the
    next save.
  - Adopt the returned `id` and `revision` after each save.
  - Flush only when there are unsaved changes, and clear the "unsaved" flag
    before awaiting the save.
  - Flush on `PopScope` pop and on `AppLifecycleState.paused`.
  - Capture the DAO in `initState`. Riverpod 3 throws if `ref` is used in
    `dispose`.
- **Autosave never deletes.** A blank body isn't saved. If the user clears a
  saved note and leaves, a dialog asks **Delete** or **Keep note** (keeping
  leaves the last saved text). There's also an explicit Delete action with
  the same confirmation. This is a dialog rather than an Undo snackbar:
  when the editor is opened from the class sheet, a snackbar appears on the
  home Scaffold behind the sheet's modal barrier, where it can't be tapped.
- The "Saving…" / "Saved" status is announced to screen readers through a
  `Semantics(liveRegion: true)`.
- The editor loads its row(s) once. Nothing changes them in the background, so
  it never needs to reload from the stream while open.

### 7.4 Teachers tab

- Add `teachers('Teachers', Icons.people_outline)` to `CalendarViewType` and a
  `bool get isCalendar` getter. No rename. When `!isCalendar`:
  - the AppBar title is "Teachers" (no date or EDT/EST line);
  - hide `bottom` (WeekStrip and FilterRail), the Today button and the series
    action;
  - leave the tab out of the "Switch Prototype View" popup.
- The feed gate stays as it is. It only blocks when the bundled asset can't
  be read, and then the whole app is unusable anyway.
- **Directory**, built from:
  - every non-placeholder `matchKey` in the current feed. The display name is
    the most common `instructor` string for that key; the entry also shows
    studios and upcoming sessions;
  - every key that only has notes. The display name is the note's most recent
    spelling, labeled "Not on the current schedule".
- Layout:
  1. a search field;
  2. **Your notes:** teachers with notes, newest note first, with a one-line
     preview and a "2 notes" badge when there's more than one;
  3. **On the schedule:** A–Z, with studio badges and a class count.
- Tapping a teacher opens a `TeacherDetailPage` showing their notes (the same
  component as the sheet) and their upcoming classes in the 14-day window.
  Tapping a class opens `showSessionDetail`.

## 8. Privacy and backup

Android Auto Backup (the manifest doesn't set `allowBackup="false"`) and the
iOS Documents/iCloud backup both include the SQLite file. **Decision: keep
backups on**, so notes survive a phone switch. Say so in the editor's empty
state ("Notes are private to you and included in your device backup"). If
that's not wanted, exclude the DB file from backup instead; both are small
platform changes.

## 9. Testing

- **Resolver:**
  - Prefers session entries over the alias map.
  - A feed with `instructorKey` but no `instructorAliases` still gives
    `keyFor(s.instructor) == s.matchKey`.
  - Placeholders are detected.
  - **Bundled-feed contract:** for every parsed session,
    `keyFor(s.instructor) == s.matchKey`. Needs the regenerated asset.
- **Ownership:**
  - An alias add gives two notes for one key.
  - A split shows one row under both keys.
  - A map that flips A→B→A→B changes no rows.
- **DAO** (in-memory DB, `closeStreamsSynchronously: true`):
  - Saving adds the spelling.
  - A revision mismatch inserts a new row and the old row is unchanged.
  - A copy-on-write split gives the edited key the new body and the other key
    the old body.
  - A `combine` conflict changes nothing.
  - 50 autosaves in a row produce no extra rows and no repeated text.
- **Property test:** with random edits, alias-map changes and combines, no
  saved text is ever lost except by an explicit delete, and no row has a blank
  body or no names. (A spelling *can* appear on more than one row: a conflict
  save or a second "Add a note" creates a new row with the same name, which
  is why a teacher can show several notes.)
- **Migration:** build a v2 database with raw SQL, open it as v3, and check
  that `teacher_notes` exists and the existing tables are untouched.
- **Contract:** a shared fixture of raw → normalized names
  (`test/fixtures/instructor_names.json`) checked by both pytest and a Dart
  test. Plus the registry checks in §4.
- **Widget** (override `appDatabaseProvider` with an in-memory DB):
  - the sheet hides notes for "Staff" and shows "2 notes" plus Combine;
  - leaving a cleared note asks first, and Keep / Delete both work;
  - the editor flushes on pop.

## 10. Room for class notes later

Use a separate table, `class_notes (templateId PK, body, revision, updatedAt)`,
keyed by `templateId`. Templates are hand-curated and stable; session ids
change every week, and slots change when the schedule shifts. It needs none of
the alias handling.

## 11. Rollout

0. *(Prerequisite, tracked separately)* Point the default feed URL at the
   deployed Pages feed so alias changes reach devices between releases.
1. Backend: emit `instructorAliases` and `placeholderInstructors`, add the
   registry tests, regenerate the bundled asset.
2. App data layer: schema v3, DAO, `TeacherResolver`, providers, tests.
3. App UI: the detail sheet section, the editor, the Teachers tab.

Each step can ship on its own. Step 2 works with an old feed because the
resolver falls back to session keys.

## 12. Risks and open questions

- The Python and Dart normalization can still drift apart, which would make
  stored spellings resolve differently. The shared fixture and the
  bundled-feed contract test are the guards.
- After an alias change, a teacher can show two notes until the user combines
  them. This is the intended trade-off; watch whether users find it confusing.
- Single-word names (Q, Chio, Blue) or company names may belong to different
  people at different studios. They're treated as one teacher unless
  `denied_aliases.json` and a registry split say otherwise.
- Backups are on (§8). Revisit if notes start holding sensitive information.
