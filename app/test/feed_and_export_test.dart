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

    // Verify Ailey has live sessions populated
    final aileySessions = feed.sessions.where((s) => s.studioId == StudioId.ailey).toList();
    expect(aileySessions.length, greaterThan(50), reason: 'Ailey should have full month of classes');

    // Verify PMT has sessions in next week (>= 2026-10-19)
    final pmtNextWeek = feed.sessions
        .where((s) => s.studioId == StudioId.pmt && s.serviceDate.compareTo(ServiceDate(2026, 10, 19)) >= 0)
        .toList();
    expect(pmtNextWeek, isNotEmpty, reason: 'PMT must populate next week classes');

    // Verify BDC has sessions in next week (>= 2026-10-19)
    final bdcNextWeek = feed.sessions
        .where((s) => s.studioId == StudioId.bdc && s.serviceDate.compareTo(ServiceDate(2026, 10, 19)) >= 0)
        .toList();
    expect(bdcNextWeek, isNotEmpty, reason: 'BDC must populate next week classes');

    // Verify Peridance has Beg Choreography at 5:30 PM (1050 min) on October 16
    final periChoreo = feed.sessions.where(
      (s) =>
          s.studioId == StudioId.peridance &&
          s.serviceDate == const ServiceDate(2026, 10, 16) &&
          s.startMin == 1050,
    ).toList();
    expect(periChoreo, isNotEmpty, reason: 'Peridance must have Beg Choreography at 5:30 PM on Oct 16');
    expect(periChoreo.any((s) => s.instructor.contains('Bo Belza')), isTrue);
  });

  test('CalendarExportService cleans week labels correctly', () {
    expect(CalendarExportService.dateClean('Week of Oct 12 - Oct 18, 2026'),
        equals('Week_of_Oct_12___Oct_18__2026'));
  });

  test('Back-to-back pairs only match same studio starting immediately after', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    // Check a session at BDC that ends at 3:00 PM (900 min)
    final bdcSession = feed.sessions.firstWhere(
      (s) => s.studioId == StudioId.bdc && s.serviceDate == const ServiceDate(2026, 10, 16) && s.endMin == 900,
    );

    final pairs = feed.sessions.where((o) {
      if (o.id == bdcSession.id || o.serviceDate != bdcSession.serviceDate) return false;
      if (o.studioId != bdcSession.studioId) return false;
      if (o.status != SessionStatus.scheduled) return false;
      return o.startMin == bdcSession.endMin;
    }).toList();

    expect(pairs, isNotEmpty);
    for (final p in pairs) {
      expect(p.studioId, equals(bdcSession.studioId));
      expect(p.serviceDate, equals(bdcSession.serviceDate));
      expect(p.startMin, equals(bdcSession.endMin));
    }
  });
}

