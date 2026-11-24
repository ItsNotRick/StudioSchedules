import 'dart:async';

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
import 'package:nyc_dance_calendar/src/ui/common.dart';
import 'package:nyc_dance_calendar/src/ui/views/genre_agenda_view.dart';
import 'package:nyc_dance_calendar/src/ui/views/my_week_view.dart';
import 'package:nyc_dance_calendar/src/ui/views/studio_columns_view.dart';

/// A one-class feed for today, so widget tests don't depend on asset I/O.
Feed fixtureFeed() {
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
    sessions: [
      ClassSession(
        id: 'fixture_session',
        templateId: 'fixture_ballet',
        studioId: StudioId.bdc,
        serviceDate: today,
        startMin: 18 * 60,
        endMin: 19 * 60 + 30,
        instructor: 'Test Teacher',
        isSubstitute: false,
        status: SessionStatus.scheduled,
        bookingUrl: 'https://example.com',
      ),
    ],
    series: const [],
  );
}

class _FakeFeedNotifier extends FeedNotifier {
  _FakeFeedNotifier(this._load);
  final Future<Feed> Function() _load;

  @override
  Future<Feed> build() => _load();
}

class _FakeSavedSlots extends SavedSlots {
  _FakeSavedSlots(this._initial);
  final Set<SavedSlot> _initial;

  @override
  Set<SavedSlot> build() => _initial;
}

class _FakeSavedSeries extends SavedSeries {
  @override
  Set<String> build() => const {};
}

Widget _app(
  Future<Feed> Function() load, {
  Set<SavedSlot> savedSlots = const {},
}) =>
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => _FakeFeedNotifier(load)),
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
          ref.onDispose(db.close);
          return db;
        }),
        savedSlotsProvider.overrideWith(() => _FakeSavedSlots(savedSlots)),
        savedSeriesProvider.overrideWith(() => _FakeSavedSeries()),
      ],
      child: const NYCStudioCalendarApp(),
    );

void main() {
  testWidgets('App launches and can toggle between calendar view prototypes',
      (WidgetTester tester) async {
    // 1. Build the widget
    await tester.pumpWidget(_app(() async => fixtureFeed()));
    await tester.pumpAndSettle();

    // 2. Verify initial view is Genre Agenda
    expect(find.text('NYC Solo Dance Calendar'), findsOneWidget);
    expect(find.byType(GenreAgendaView), findsOneWidget);

    // 3. Switch to Studio Columns view
    await tester.tap(find.text('Studio Columns'));
    await tester.pumpAndSettle();
    expect(find.byType(StudioColumnsView), findsOneWidget);
    expect(find.byType(GenreAgendaView), findsNothing);

    // 4. Switch to My Regimen view
    await tester.tap(find.text('My Regimen'));
    await tester.pumpAndSettle();
    expect(find.byType(MyWeekView), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('Shows a loading state, not placeholder classes, until the feed loads',
      (WidgetTester tester) async {
    final pending = Completer<Feed>();
    await tester.pumpWidget(_app(() => pending.future));
    await tester.pump();

    expect(find.byType(FeedLoadingView), findsOneWidget);
    expect(find.byType(GenreAgendaView), findsNothing);

    pending.complete(fixtureFeed());
    await tester.pumpAndSettle();
    expect(find.byType(FeedLoadingView), findsNothing);
    expect(find.byType(GenreAgendaView), findsOneWidget);
  });

  testWidgets('Shows an error state with a working retry when the feed fails',
      (WidgetTester tester) async {
    var attempts = 0;
    await tester.pumpWidget(_app(() async {
      attempts++;
      if (attempts == 1) throw Exception('no feed');
      return fixtureFeed();
    }));
    await tester.pumpAndSettle();

    expect(find.byType(FeedErrorView), findsOneWidget);
    expect(find.byType(GenreAgendaView), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(FeedErrorView), findsNothing);
    expect(find.byType(GenreAgendaView), findsOneWidget);
  });

  testWidgets('StudioColumnsView widens dense columns and shows late-evening sessions without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final today = getTodayInNewYork();
    registerTemplates([
      const ClassTemplate(
        id: 'steps_dense_ballet',
        studioId: StudioId.steps,
        title: 'Dense Steps Ballet',
        rawLevelLabel: 'OPEN',
        tier: Tier.allLevels,
        primaryGenre: Genre.ballet,
        slots: [],
        description: '',
        catalogUrl: '',
      ),
      const ClassTemplate(
        id: 'danznik_late_social',
        studioId: StudioId.danznik,
        title: 'Late Night Social',
        rawLevelLabel: 'OPEN',
        tier: Tier.allLevels,
        primaryGenre: Genre.social,
        slots: [],
        description: '',
        catalogUrl: '',
      ),
    ]);

    final denseFeed = Feed(
      today: today,
      windowStart: today.startOfWeek,
      sessions: [
        for (var i = 0; i < 14; i++)
          ClassSession(
            id: 'steps_overlap_$i',
            templateId: 'steps_dense_ballet',
            studioId: StudioId.steps,
            serviceDate: today,
            startMin: 12 * 60,
            endMin: 13 * 60 + 30,
            instructor: 'Teacher $i',
            isSubstitute: false,
            status: SessionStatus.scheduled,
            bookingUrl: 'https://stepsnyc.com',
          ),
        ClassSession(
          id: 'danznik_late_1',
          templateId: 'danznik_late_social',
          studioId: StudioId.danznik,
          serviceDate: today,
          startMin: 21 * 60,
          endMin: 23 * 60 + 45,
          instructor: 'Late Host',
          isSubstitute: false,
          status: SessionStatus.scheduled,
          bookingUrl: 'https://danznik.com',
        ),
      ],
      series: const [],
    );

    await tester.pumpWidget(_app(() async => denseFeed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Studio Columns'));
    await tester.pumpAndSettle();

    expect(find.byType(StudioColumnsView), findsOneWidget);
    expect(find.text('Late Night Social'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MyWeekView keeps booking button visible for substituted slots',
      (WidgetTester tester) async {
    final today = getTodayInNewYork();
    registerTemplates([
      const ClassTemplate(
        id: 'sub_tpl',
        studioId: StudioId.ailey,
        title: 'Horton Technique',
        rawLevelLabel: 'OPEN',
        tier: Tier.allLevels,
        primaryGenre: Genre.contemporaryModern,
        slots: [],
        description: '',
        catalogUrl: '',
      ),
    ]);

    final feed = Feed(
      today: today,
      windowStart: today.startOfWeek,
      sessions: [
        ClassSession(
          id: 'sub_sess',
          templateId: 'sub_tpl',
          studioId: StudioId.ailey,
          serviceDate: today,
          startMin: 18 * 60,
          endMin: 19 * 60 + 30,
          instructor: 'Sam Lee',
          instructorKey: 'sam lee',
          isSubstitute: true,
          status: SessionStatus.scheduled,
          bookingUrl: 'https://ailey.org',
        ),
      ],
      series: const [],
    );

    final slot = SavedSlot(
      templateId: 'sub_tpl',
      weekday: today.weekday,
      startMin: 18 * 60,
      instructor: 'Regular Teacher',
      instructorKey: 'regular teacher',
    );

    await tester.pumpWidget(_app(() async => feed, savedSlots: {slot}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Regimen'));
    await tester.pumpAndSettle();

    expect(find.text('Teacher Substitute'), findsOneWidget);
    expect(find.text('Book on Ailey'), findsOneWidget);
  });
}
