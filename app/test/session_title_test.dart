import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/domain/models.dart';

ClassSession _s(String? rawTitle) => ClassSession(
      id: 'x',
      templateId: 'ailey_contemporaryModern_open_contemporary',
      studioId: StudioId.ailey,
      serviceDate: const ServiceDate(2026, 11, 11),
      startMin: 1170,
      endMin: 1260,
      instructor: 'Brinda Guha',
      rawTitle: rawTitle,
      isSubstitute: false,
      status: SessionStatus.scheduled,
      bookingUrl: 'https://ailey.org',
    );

void main() {
  test('title keeps the studio name in full', () {
    expect(_s('Open Contemporary Indian').title, 'Open Contemporary Indian');
    expect(_s('Open Ballet (Pointe Optional)').title,
        'Open Ballet (Pointe Optional)');
  });

  test('title drops the "with <teacher>" suffix and extra spaces', () {
    expect(_s('Beg THEATER  with Daniel Booda').title, 'Beg THEATER');
  });

  test('title is null without a raw title, so callers use the template', () {
    expect(_s(null).title, isNull);
    expect(_s('   ').title, isNull);
  });
}
