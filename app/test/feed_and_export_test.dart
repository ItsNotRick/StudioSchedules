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

  test('Pairs well with includes immediate same-studio and reachable cross-studio classes', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    // Check a session at Peridance (Bo Belza, ends at 19:00 / 1140 min on Oct 16)
    final periSession = feed.sessions.firstWhere(
      (s) => s.studioId == StudioId.peridance && s.serviceDate == const ServiceDate(2026, 10, 16) && s.endMin == 1140,
    );

    // Cross-studio candidates reachable with commute buffer
    final crossStudio = feed.sessions.where((o) {
      if (o.id == periSession.id || o.serviceDate != periSession.serviceDate) return false;
      if (o.studioId == periSession.studioId) return false;
      if (o.status != SessionStatus.scheduled) return false;
      final gap = o.startMin - periSession.endMin;
      if (gap < 0 || gap > 90) return false;
      return commuteBetween(periSession.studioId, o.studioId).minutes + 5 <= gap;
    }).toList();

    expect(crossStudio, isNotEmpty, reason: 'Cross-studio commute options should be found');

    // Immediate same-studio candidate at BDC (ends at 3:00 PM / 900 min on Oct 16)
    final bdcSession = feed.sessions.firstWhere(
      (s) => s.studioId == StudioId.bdc && s.serviceDate == const ServiceDate(2026, 10, 16) && s.endMin == 900,
    );
    final immediateSame = feed.sessions.where((o) {
      if (o.id == bdcSession.id || o.serviceDate != bdcSession.serviceDate) return false;
      if (o.studioId != bdcSession.studioId) return false;
      if (o.status != SessionStatus.scheduled) return false;
      return o.startMin == bdcSession.endMin;
    }).toList();

    expect(immediateSame, isNotEmpty, reason: 'Same-studio immediate classes should be found');
  });

  test('Genre.other catch-all is recognized and populated in live feed', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    final otherTemplates = feed.sessions
        .map((s) => templatesById[s.templateId])
        .where((tpl) => tpl?.primaryGenre == Genre.other)
        .toList();

    expect(otherTemplates, isNotEmpty, reason: 'Feed must contain classes classified under Other');
    final titles = otherTemplates.map((t) => t!.title).toSet();
    expect(titles.any((t) => t.toLowerCase().contains('jump') || t.toLowerCase().contains('stretch') || t.toLowerCase().contains('barre')), isTrue);
  });
}

