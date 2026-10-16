import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/mock_feed.dart';
import '../state/providers.dart';

class CalendarExportService {
  /// Exports the user's resolved regimen slots as an iCalendar (.ics) file.
  static Future<void> exportRegimenToCalendar({
    required List<ResolvedSlot> regimenSlots,
    required String weekLabel,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//NYC Solo Dance Calendar//EN');
    buffer.writeln('CALSCALE:GREGORIAN');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('X-WR-CALNAME:NYC Solo Dance Regimen ($weekLabel)');
    buffer.writeln('X-WR-TIMEZONE:America/New_York');

    // Add VTIMEZONE for America/New_York
    buffer.writeln('BEGIN:VTIMEZONE');
    buffer.writeln('TZID:America/New_York');
    buffer.writeln('X-LIC-LOCATION:America/New_York');
    buffer.writeln('BEGIN:DAYLIGHT');
    buffer.writeln('TZOFFSETFROM:-0500');
    buffer.writeln('TZOFFSETTO:-0400');
    buffer.writeln('TZNAME:EDT');
    buffer.writeln('DTSTART:19700308T020000');
    buffer.writeln('RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU');
    buffer.writeln('END:DAYLIGHT');
    buffer.writeln('BEGIN:STANDARD');
    buffer.writeln('TZOFFSETFROM:-0400');
    buffer.writeln('TZOFFSETTO:-0500');
    buffer.writeln('TZNAME:EST');
    buffer.writeln('DTSTART:19701101T020000');
    buffer.writeln('RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU');
    buffer.writeln('END:STANDARD');
    buffer.writeln('END:VTIMEZONE');

    for (final resolved in regimenSlots) {
      if (resolved.health == SlotHealth.cancelled ||
          resolved.health == SlotHealth.removed ||
          resolved.health == SlotHealth.notOnSchedule) {
        continue;
      }

      final session = resolved.session;
      final tpl = templatesById[resolved.slot.templateId];
      if (tpl == null) continue;

      final studio = studios[tpl.studioId]!;
      final date = resolved.date;

      final startH = resolved.slot.startMin ~/ 60;
      final startM = resolved.slot.startMin % 60;
      final dur = session?.durationMin ?? 90;
      final endMin = resolved.slot.startMin + dur;
      final endH = endMin ~/ 60;
      final endM = endMin % 60;

      final dtStart = '${date.year}'
          '${date.month.toString().padLeft(2, '0')}'
          '${date.day.toString().padLeft(2, '0')}'
          'T${startH.toString().padLeft(2, '0')}'
          '${startM.toString().padLeft(2, '0')}00';

      final dtEnd = '${date.year}'
          '${date.month.toString().padLeft(2, '0')}'
          '${date.day.toString().padLeft(2, '0')}'
          'T${endH.toString().padLeft(2, '0')}'
          '${endM.toString().padLeft(2, '0')}00';

      final teacher = session?.instructor ?? 'Staff';
      final subNote = session?.isSubstitute == true ? ' [SUBSTITUTE TEACHER]' : '';

      final summary = '${tpl.title} (${tpl.rawLevelLabel}) at ${studio.shortName}';
      final desc = '${tpl.description}\\n\\n'
          'Instructor: $teacher$subNote\\n'
          'Attire: ${tpl.attireNotes ?? "Comfortable dance attire"}\\n'
          'Studio: ${studio.name} (${studio.address}, ${studio.neighborhood})\\n'
          'Booking: ${session?.bookingUrl ?? tpl.catalogUrl}';

      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:${resolved.slot.templateId}-${resolved.date}-${resolved.slot.startMin}@nycdancecalendar.app');
      buffer.writeln('DTSTAMP:${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z');
      buffer.writeln('DTSTART;TZID=America/New_York:$dtStart');
      buffer.writeln('DTEND;TZID=America/New_York:$dtEnd');
      buffer.writeln('SUMMARY:$summary');
      buffer.writeln('LOCATION:${studio.address}, New York, NY');
      buffer.writeln('DESCRIPTION:$desc');
      buffer.writeln('URL:${session?.bookingUrl ?? tpl.catalogUrl}');
      buffer.writeln('STATUS:CONFIRMED');
      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');

    // Write to a temporary .ics file and trigger share sheet
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/dance_regimen_${dateClean(weekLabel)}.ics');
    await file.writeAsString(buffer.toString());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar')],
        subject: 'NYC Dance Regimen ($weekLabel)',
        text: 'Exported dance classes for $weekLabel.',
      ),
    );
  }

  static String dateClean(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
}
