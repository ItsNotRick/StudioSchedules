import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/data/feed_repository.dart';
import 'package:nyc_dance_calendar/src/data/mock_feed.dart';
import 'package:nyc_dance_calendar/src/domain/models.dart';
import 'package:nyc_dance_calendar/src/services/calendar_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FeedRepository loads live schedule and registers templates', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    expect(feed.sessions, isNotEmpty);
    expect(feed.windowStart, isNotNull);
    expect(feed.today, isNotNull);

    // Verify all 5 studios are present in the sessions
    final studioIds = feed.sessions.map((s) => s.studioId).toSet();
    expect(studioIds.contains(StudioId.bdc), isTrue);
    expect(studioIds.contains(StudioId.steps), isTrue);
    expect(studioIds.contains(StudioId.ailey), isTrue);
    expect(studioIds.contains(StudioId.peridance), isTrue);
    expect(studioIds.contains(StudioId.pmt), isTrue);

    // Verify templatesById contains registered templates
    for (final s in feed.sessions) {
      final tpl = templatesById[s.templateId];
      expect(tpl, isNotNull, reason: 'Template ${s.templateId} must be resolved');
      expect(tpl!.studioId, equals(s.studioId));
    }
  });

  test('CalendarExportService cleans week labels correctly', () {
    expect(CalendarExportService.dateClean('Week of Oct 12 - Oct 18, 2026'),
        equals('Week_of_Oct_12___Oct_18__2026'));
  });
}
