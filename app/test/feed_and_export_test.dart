import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

    // Verify Peridance has Beg Choreography at 5:30 PM (1050 min) on October 23
    final periChoreo = feed.sessions.where(
      (s) =>
          s.studioId == StudioId.peridance &&
          s.serviceDate == const ServiceDate(2026, 10, 23) &&
          s.startMin == 1050,
    ).toList();
    expect(periChoreo, isNotEmpty, reason: 'Peridance must have Beg Choreography at 5:30 PM on Oct 23');
    expect(periChoreo.any((s) => s.instructor.contains('Bo Belza')), isTrue);
  });

  test('CalendarExportService cleans week labels correctly', () {
    expect(CalendarExportService.dateClean('Week of Oct 12 - Oct 18, 2026'),
        equals('Week_of_Oct_12___Oct_18__2026'));
  });

  test('Pairs well with includes immediate same-studio and reachable cross-studio classes', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    // Cross-studio candidates reachable with commute buffer
    final candidateWithCross = feed.sessions.firstWhere((s) => feed.sessions.any(
      (o) => o.id != s.id && o.studioId != s.studioId && o.serviceDate == s.serviceDate && o.status == SessionStatus.scheduled &&
          (o.startMin - s.endMin) >= 0 && (o.startMin - s.endMin) <= 90 &&
          commuteBetween(s.studioId, o.studioId).minutes + 5 <= (o.startMin - s.endMin),
    ));

    final crossStudio = feed.sessions.where((o) {
      if (o.id == candidateWithCross.id || o.serviceDate != candidateWithCross.serviceDate) return false;
      if (o.studioId == candidateWithCross.studioId) return false;
      if (o.status != SessionStatus.scheduled) return false;
      final gap = o.startMin - candidateWithCross.endMin;
      if (gap < 0 || gap > 90) return false;
      return commuteBetween(candidateWithCross.studioId, o.studioId).minutes + 5 <= gap;
    }).toList();

    expect(crossStudio, isNotEmpty, reason: 'Cross-studio commute options should be found');

    // Immediate same-studio candidate
    final candidateWithImmediate = feed.sessions.firstWhere((s) => feed.sessions.any(
      (o) => o.id != s.id && o.studioId == s.studioId && o.serviceDate == s.serviceDate && o.startMin == s.endMin && o.status == SessionStatus.scheduled,
    ));

    final immediateSame = feed.sessions.where((o) {
      if (o.id == candidateWithImmediate.id || o.serviceDate != candidateWithImmediate.serviceDate) return false;
      if (o.studioId != candidateWithImmediate.studioId) return false;
      if (o.status != SessionStatus.scheduled) return false;
      return o.startMin == candidateWithImmediate.endMin;
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

  test('commuteBetween returns verified transit times', () {
    // Ailey to PMT is 25 min subway
    final aileyPmt = commuteBetween(StudioId.ailey, StudioId.pmt);
    expect(aileyPmt.minutes, equals(25));
    expect(aileyPmt.mode, equals('subway'));

    // Symmetric check
    final pmtAiley = commuteBetween(StudioId.pmt, StudioId.ailey);
    expect(pmtAiley.minutes, equals(25));
    expect(pmtAiley.mode, equals('subway'));

    // Ailey to BDC is 12 min walk
    final aileyBdc = commuteBetween(StudioId.ailey, StudioId.bdc);
    expect(aileyBdc.minutes, equals(12));
    expect(aileyBdc.mode, equals('walk'));

    // Same studio is 0 min
    final same = commuteBetween(StudioId.bdc, StudioId.bdc);
    expect(same.minutes, equals(0));
    expect(same.mode, equals('same studio'));
  });

  test('FeedRepository.unescapeHtml correctly unescapes HTML entities', () {
    expect(
      FeedRepository.unescapeHtml('Paolo &quot;Slice&quot; Peñala'),
      equals('Paolo "Slice" Peñala'),
    );
    expect(
      FeedRepository.unescapeHtml('Ja&#039;Bowen Dixon'),
      equals("Ja'Bowen Dixon"),
    );
    expect(
      FeedRepository.unescapeHtml('Jonathan &quot;Shwing&quot; Peña'),
      equals('Jonathan "Shwing" Peña'),
    );
    expect(
      FeedRepository.unescapeHtml('Rhythm &amp; Motion &lt;Dance&gt;'),
      equals('Rhythm & Motion <Dance>'),
    );
    expect(
      FeedRepository.unescapeHtml('&#65;&#66;&#67;'),
      equals('ABC'),
    );
  });

  test('Paolo Penala and all instructor names display with decoded quotes and no raw HTML entities', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    // Verify Paolo's sessions exist
    final paoloSessions = feed.sessions.where((s) => s.instructor.toLowerCase().contains('paolo')).toList();
    expect(paoloSessions, isNotEmpty, reason: 'Paolo Penala classes must be present');

    for (final s in paoloSessions) {
      // Must not contain raw &quot;
      expect(s.instructor.contains('&quot;'), isFalse);
      if (s.studioId == StudioId.bdc) {
        expect(s.instructor, equals('Paolo "Slice" Peñala'));
      } else if (s.studioId == StudioId.steps) {
        expect(s.instructor, equals('Paolo Slice Penala'));
      }
    }

    // Verify all sessions across the feed have no remaining HTML entities in instructor names
    for (final s in feed.sessions) {
      expect(s.instructor.contains('&quot;'), isFalse, reason: 'Session ${s.id} instructor has &quot;');
      expect(s.instructor.contains('&#039;'), isFalse, reason: 'Session ${s.id} instructor has &#039;');
      expect(s.instructor.contains('&amp;'), isFalse, reason: 'Session ${s.id} instructor has &amp;');
    }
  });

  test('ClassSession description field and CalendarExportService fallback work correctly', () {
    const sessionWithDesc = ClassSession(
      id: 'test_sess_1',
      templateId: 'bdc_basic_ballet',
      studioId: StudioId.bdc,
      serviceDate: ServiceDate(2026, 10, 20),
      startMin: 600,
      endMin: 690,
      instructor: 'Cara Leggio',
      description: 'Focuses on anatomical alignment, musicality, and strong technical foundations.',
      isSubstitute: false,
      status: SessionStatus.scheduled,
      bookingUrl: 'https://example.com/book',
    );

    const sessionWithoutDesc = ClassSession(
      id: 'test_sess_2',
      templateId: 'bdc_basic_ballet',
      studioId: StudioId.bdc,
      serviceDate: ServiceDate(2026, 10, 20),
      startMin: 600,
      endMin: 690,
      instructor: 'Unknown Sub',
      description: null,
      isSubstitute: true,
      status: SessionStatus.scheduled,
      bookingUrl: 'https://example.com/book',
    );

    expect(sessionWithDesc.description, isNotNull);
    expect(sessionWithDesc.description, contains('anatomical alignment'));
    expect(sessionWithoutDesc.description, isNull);

    // Verify ICS export incorporates session description when present
    final icsContent = CalendarExportService.generateSingleSessionIcsContent(sessionWithDesc);
    expect(icsContent, contains('Focuses on anatomical alignment'));

    // Verify ICS export incorporates fallback message when neither instructor nor website description is available
    final icsFallback = CalendarExportService.generateSingleSessionIcsContent(sessionWithoutDesc);
    expect(icsFallback, contains('A description has not been provided for this class.'));
  });

  test('Kathy Sullivan sessions resolve description from Kathryn Sullivan alias across studios', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    final sullivanSessions = feed.sessions.where((s) => s.instructor.toLowerCase().contains('sullivan')).toList();
    expect(sullivanSessions, isNotEmpty, reason: 'Kathy Sullivan sessions must be present');

    for (final s in sullivanSessions) {
      expect(s.instructor, equals('Kathy Sullivan'));
      expect(s.description, isNotNull);
      expect(s.description, contains('Kathy uses a contemporary approach'));
      expect(s.description, contains('Ballet Glider'));
    }
  });

  test('Jazzy J Open Popping session resolves verbatim description from Peridance faculty page', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    final jazzySessions = feed.sessions.where((s) => s.instructor.toLowerCase().contains('jazzy')).toList();
    expect(jazzySessions, isNotEmpty, reason: 'Jazzy J sessions must be present');

    for (final s in jazzySessions) {
      expect(s.instructor, equals('Jazzy J (Boog Soulfire)'));
      expect(s.description, isNotNull);
      expect(s.description, contains('A master and pioneer of Popping'));
      expect(s.description, contains('original Popping movement and technique'));
    }
  });

  test('getTemplate returns fallback template for unmapped template IDs without throwing', () {
    final unknown = getTemplate('non_existent_template_xyz');
    expect(unknown, isNotNull);
    expect(unknown.id, equals('non_existent_template_xyz'));
    expect(unknown.title, isNotEmpty);
    expect(unknown.tier, equals(Tier.beginner));
  });

  test('CalendarExportService.escapeIcsText escapes semicolons and backslashes per RFC 5545', () {
    final escaped = CalendarExportService.escapeIcsText(
      '${r'Class; Notes \ Details'}\nLine 2',
    );
    expect(escaped, contains(r'\;'));
    expect(escaped, contains(r'\\'));
    expect(escaped, contains(r'\n'));
  });

  test('FeedRepository.unescapeHtml does not double-unescape &amp;#39;', () {
    expect(
      FeedRepository.unescapeHtml('Literal &amp;#39; entity &amp; &quot;quote&quot;'),
      equals('Literal &#39; entity & "quote"'),
    );
  });

  test('Live feed preserves Adv Beg templates and excludes youth/barre/stretch leaks', () async {
    final repo = FeedRepository();
    final feed = await repo.loadFeed();

    final bdcAdvBegTitles = feed.sessions
        .where((s) => s.studioId == StudioId.bdc)
        .map((s) => getTemplate(s.templateId))
        .where((t) => t.tier == Tier.advancedBeginner)
        .map((t) => t.title)
        .toSet();

    expect(bdcAdvBegTitles, contains('Adv Beg JAZZ'));
    expect(bdcAdvBegTitles, contains('Adv Beg THEATER'));
    expect(bdcAdvBegTitles, contains('Adv Beg TAP'));
    expect(bdcAdvBegTitles, contains('Adv Beg HEELS'));

    // Ensure no youth or barre/stretch classes leaked into the adult solo dance feed
    for (final s in feed.sessions) {
      final titleLower = getTemplate(s.templateId).title.toLowerCase();
      expect(titleLower.contains('ages '), isFalse, reason: 'Youth class leaked: $titleLower');
      expect(titleLower.contains('floor-barre'), isFalse, reason: 'Floor-Barre leaked: $titleLower');
      expect(titleLower.contains('open stretch'), isFalse, reason: 'Stretch class leaked: $titleLower');
      if (s.studioId == StudioId.ailey) {
        expect(titleLower.contains('(beginner)'), isFalse, reason: 'Redundant level suffix: $titleLower');
      }
    }
  });

  test('SavedSlot disambiguates concurrent same-template classes by instructor', () {
    const sessionA = ClassSession(
      id: 'ailey_wed_1',
      templateId: 'ailey_contemporaryModern_open_contemporary',
      studioId: StudioId.ailey,
      serviceDate: ServiceDate(2026, 10, 28), // Wednesday (weekday 3)
      startMin: 1170,
      endMin: 1260,
      instructor: 'Ramita Ravi',
      isSubstitute: false,
      status: SessionStatus.scheduled,
      bookingUrl: 'https://ailey.org',
    );
    const sessionB = ClassSession(
      id: 'ailey_wed_2',
      templateId: 'ailey_contemporaryModern_open_contemporary',
      studioId: StudioId.ailey,
      serviceDate: ServiceDate(2026, 10, 28), // Wednesday (weekday 3)
      startMin: 1170,
      endMin: 1260,
      instructor: 'Jamaal Bowman',
      isSubstitute: false,
      status: SessionStatus.scheduled,
      bookingUrl: 'https://ailey.org',
    );

    const slotA = SavedSlot(
      templateId: 'ailey_contemporaryModern_open_contemporary',
      weekday: 3,
      startMin: 1170,
      instructor: 'Ramita Ravi',
    );

    expect(slotA.matches(sessionA), isTrue);
    expect(slotA.matches(sessionB), isFalse);
  });

  test('CalendarExportService.generateRegimenIcsContent exports enrolled series meetings', () {
    const series = WorkshopSeries(
      id: 'test_ws_1',
      templateId: 'bdc_basic_ballet',
      studioId: StudioId.bdc,
      title: 'Intro Ballet Series',
      startDate: ServiceDate(2026, 10, 19),
      sessionCount: 4,
      weekday: 1,
      startMin: 1080,
      durationMin: 90,
      instructor: 'Test Instructor',
      enrollmentOpen: true,
      price: '\$120',
      bookingUrl: 'https://broadwaydancecenter.com',
    );

    final ics = CalendarExportService.generateRegimenIcsContent(
      regimenSlots: const [],
      weekLabel: 'Mon Oct 19',
      enrolledSeries: const [series],
      weekStart: const ServiceDate(2026, 10, 19),
    );

    expect(ics, contains('BEGIN:VEVENT'));
    expect(ics, contains('Intro Ballet Series (Week 1/4) at BDC'));
  });

  test('FeedRepository fetches remote feed over HTTP and updates when newer', () async {
    final mockHttp = MockHttpClient((request) async {
      if (request.url.path.endsWith('schedule.json')) {
        final mockRemoteData = {
          'version': '1.0.0',
          'generatedAt': '2099-01-01T00:00:00.000Z',
          'windowStart': '2099-01-01',
          'windowEnd': '2099-01-14',
          'studios': [],
          'templates': [],
          'series': [],
          'sessions': [
            {
              'id': 'remote_test_session_1',
              'templateId': 'bdc_basic_ballet',
              'studioId': 'bdc',
              'serviceDate': '2099-01-05',
              'startMin': 600,
              'endMin': 690,
              'tz': 'America/New_York',
              'instructor': 'Remote Instructor',
              'status': 'scheduled',
              'bookingUrl': 'https://broadwaydancecenter.com',
            }
          ]
        };
        return http.Response(json.encode(mockRemoteData), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('Not found', 404);
    });

    final repo = FeedRepository(
      httpClient: mockHttp,
      feedUrl: 'https://example.com/schedule.json',
    );

    final feed = await repo.loadFeed(fetchRemote: true);
    expect(feed.sessions.any((s) => s.id == 'remote_test_session_1'), isTrue);
  });
}

class MockHttpClient extends http.BaseClient {
  MockHttpClient(this._handler);
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.fromIterable([response.bodyBytes]),
      response.statusCode,
      headers: response.headers,
    );
  }
}


