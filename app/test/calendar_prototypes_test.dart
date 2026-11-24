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

Widget _app(Future<Feed> Function() load) => ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => _FakeFeedNotifier(load)),
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
          ref.onDispose(db.close);
          return db;
        }),
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
}
