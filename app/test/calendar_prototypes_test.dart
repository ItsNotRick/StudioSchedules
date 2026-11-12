import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/main.dart';
import 'package:nyc_dance_calendar/src/ui/common.dart';
import 'package:nyc_dance_calendar/src/ui/views/genre_agenda_view.dart';
import 'package:nyc_dance_calendar/src/ui/views/my_week_view.dart';
import 'package:nyc_dance_calendar/src/ui/views/studio_columns_view.dart';

void main() {
  testWidgets('App launches and can toggle between calendar view prototypes',
      (WidgetTester tester) async {
    // 1. Build the widget
    await tester.pumpWidget(
      const ProviderScope(child: NYCStudioCalendarApp()),
    );
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
}
