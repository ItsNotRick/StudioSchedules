import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/main.dart';
import 'package:nyc_dance_calendar/src/data/database/app_database.dart';
import 'package:nyc_dance_calendar/src/data/feed.dart';
import 'package:nyc_dance_calendar/src/domain/models.dart';
import 'package:nyc_dance_calendar/src/state/providers.dart';
import 'package:nyc_dance_calendar/src/ui/detail_sheet.dart';
import 'package:nyc_dance_calendar/src/ui/teacher_notes.dart';
import 'package:nyc_dance_calendar/src/ui/views/teachers_view.dart';

ClassSession _session(String id, String instructor, {String? key, int startMin = 600}) {
  final today = getTodayInNewYork();
  return ClassSession(
    id: id,
    templateId: 'fixture_ballet',
    studioId: StudioId.bdc,
    serviceDate: today,
    startMin: startMin,
    endMin: startMin + 90,
    instructor: instructor,
    instructorKey: key,
    isSubstitute: false,
    status: SessionStatus.scheduled,
    bookingUrl: 'https://example.com',
  );
}

final _ana = _session('ana', 'Ana Lopez');
final _staff = _session('staff', 'Staff', startMin: 700);
final _kathy = _session('kathy', 'Kathy Sullivan', key: 'kathryn sullivan', startMin: 800);
final _kathryn = _session('kathryn', 'Kathryn Sullivan', key: 'kathryn sullivan', startMin: 900);

Feed _feed() {
  final today = getTodayInNewYork();
  registerTemplates([
    ClassTemplate(
      id: 'fixture_ballet',
      studioId: StudioId.bdc,
      title: 'Fixture Ballet',
      rawLevelLabel: 'BEGINNER',
      tier: Tier.beginner,
      primaryGenre: Genre.ballet,
      slots: const [],
      description: '',
      catalogUrl: '',
    ),
  ]);
  return Feed(
    today: today,
    windowStart: today.startOfWeek,
    sessions: [_ana, _staff, _kathy, _kathryn],
    series: const [],
    instructorAliases: const {'kathy sullivan': 'kathryn sullivan', 'kathryn sullivan': 'kathryn sullivan'},
  );
}

class _FakeFeedNotifier extends FeedNotifier {
  @override
  Future<Feed> build() async => _feed();
}

late AppDatabase _db;

Widget _app() => ProviderScope(
      overrides: [
        feedProvider.overrideWith(_FakeFeedNotifier.new),
        appDatabaseProvider.overrideWithValue(_db),
      ],
      child: const NYCStudioCalendarApp(),
    );

Future<void> _openSheet(WidgetTester tester, ClassSession s) async {
  final context = tester.element(find.byType(CalendarHomeScreen));
  showSessionDetail(context, s);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  });
  tearDown(() async => _db.close());

  testWidgets('class sheet offers notes for real teachers but not for Staff', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await _openSheet(tester, _staff);
    expect(find.byType(TeacherNotesSection), findsOneWidget);
    expect(find.textContaining('Your notes on'), findsNothing);
    Navigator.of(tester.element(find.byType(TeacherNotesSection))).pop();
    await tester.pumpAndSettle();

    await _openSheet(tester, _ana);
    expect(find.text('Your notes on Ana Lopez'), findsOneWidget);
    expect(find.text('Add a note about Ana Lopez'), findsOneWidget);
  });

  testWidgets('writing a note from a class autosaves and shows it on the sheet', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openSheet(tester, _ana);

    await tester.tap(find.text('Add a note about Ana Lopez'));
    await tester.pumpAndSettle();
    expect(find.byType(TeacherNoteEditorPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Counts in 7s');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final notes = await _db.teacherNotesDao.getAll();
    expect(notes.single.body, 'Counts in 7s');
    expect(notes.single.names, ['Ana Lopez']);
    expect(find.text('Counts in 7s'), findsOneWidget); // preview on the sheet
  });

  testWidgets('leaving a cleared note asks before deleting it', (tester) async {
    final created = await _db.teacherNotesDao.create(listedName: 'Ana Lopez', body: 'old note');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openSheet(tester, _ana);

    // Keep: the last saved text stays.
    await tester.tap(find.text('old note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('You cleared your note on Ana Lopez.'), findsOneWidget);
    await tester.tap(find.text('Keep note'));
    await tester.pumpAndSettle();
    expect(find.byType(TeacherNoteEditorPage), findsNothing);
    expect((await _db.teacherNotesDao.getById(created.id))?.body, 'old note');

    // Delete: the note is removed.
    await tester.tap(find.text('old note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(TeacherNoteEditorPage), findsNothing);
    expect(await _db.teacherNotesDao.getById(created.id), isNull);
    expect(find.text('Add a note about Ana Lopez'), findsOneWidget);
  });

  testWidgets('notes under two spellings show together and can be combined', (tester) async {
    await _db.teacherNotesDao.create(listedName: 'Kathy Sullivan', body: 'A');
    await _db.teacherNotesDao.create(listedName: 'Kathryn Sullivan', body: 'B');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openSheet(tester, _kathy);

    expect(find.text('Written as Kathy Sullivan'), findsOneWidget);
    expect(find.text('Written as Kathryn Sullivan'), findsOneWidget);
    await tester.tap(find.text('Combine 2 notes'));
    await tester.pumpAndSettle();

    expect(find.text('Combining notes'), findsOneWidget);
    expect(await _db.teacherNotesDao.getAll(), hasLength(2)); // nothing changes yet
    await tester.enterText(find.byType(TextField), 'A + B');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final all = await _db.teacherNotesDao.getAll();
    expect(all.single.body, 'A + B');
    expect(all.single.names, ['Kathy Sullivan', 'Kathryn Sullivan']);

    // Back in edit mode with the field's text tracked: typing the original
    // pre-filled text back in is a real change and autosaves.
    await tester.enterText(find.byType(TextField), 'A\n\nB');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect((await _db.teacherNotesDao.getAll()).single.body, 'A\n\nB');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeacherNoteEditorPage), findsNothing);
    expect((await _db.teacherNotesDao.getAll()).single.body, 'A\n\nB');
  });

  testWidgets('Teachers tab lists notes first, then the schedule, and hides calendar chrome',
      (tester) async {
    await _db.teacherNotesDao.create(listedName: 'Kathy Sullivan', body: 'counts in 7s');
    await _db.teacherNotesDao.create(listedName: 'Old Teacher', body: 'moved away');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Teachers'));
    await tester.pumpAndSettle();
    expect(find.byType(TeachersView), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    expect(find.text('NYC Solo Dance Calendar'), findsNothing);

    expect(find.text('Kathryn Sullivan'), findsOneWidget); // one entry for both spellings
    expect(find.text('Old Teacher'), findsOneWidget);
    expect(find.textContaining('Not on the current schedule'), findsOneWidget);
    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('Staff'), findsNothing);

    await tester.enterText(find.byType(TextField), 'kathy');
    await tester.pumpAndSettle();
    expect(find.text('Kathryn Sullivan'), findsOneWidget);
    expect(find.text('Ana Lopez'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pumpAndSettle();
    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('Kathryn Sullivan'), findsNothing);

    await tester.tap(find.text('Ana Lopez'));
    await tester.pumpAndSettle();
    expect(find.byType(TeacherDetailPage), findsOneWidget);
    expect(find.text('Add a note about Ana Lopez'), findsOneWidget);
    expect(find.text('1 upcoming class'), findsOneWidget);
  });
}
