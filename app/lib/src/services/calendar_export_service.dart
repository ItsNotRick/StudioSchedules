import 'dart:io';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/mock_feed.dart';
import '../domain/models.dart';
import '../state/providers.dart';

class CalendarExportService {
  /// Prompts the native iOS/Android calendar UI to add this class session.
  /// Falls back to sharing an .ics file if native EventKit is unavailable.
  static Future<bool> addSessionToCalendar(ClassSession session) async {
    final tpl = templatesById[session.templateId];
    if (tpl == null) return false;
    final studio = studios[session.studioId]!;
    final date = session.serviceDate;

    final startH = session.startMin ~/ 60;
    final startM = session.startMin % 60;
    final endH = session.endMin ~/ 60;
    final endM = session.endMin % 60;

    final startDt = DateTime(date.year, date.month, date.day, startH, startM);
    final endDt = DateTime(date.year, date.month, date.day, endH, endM);

    final teacher = session.instructor;
    final subNote = session.isSubstitute ? ' [SUBSTITUTE TEACHER]' : '';
    final summary = '${tpl.title} (${tpl.rawLevelLabel}) at ${studio.shortName}';
    final classDesc = (session.description != null && session.description!.trim().isNotEmpty)
        ? session.description!
        : (tpl.description.trim().isNotEmpty)
            ? "Studio's style description: ${tpl.description.trim()}"
            : 'A description has not been provided for this class.';
    final desc = '$classDesc\n\n'
        'Instructor: $teacher$subNote\n'
        'Studio: ${studio.name} (${studio.address}, ${studio.neighborhood})\n'
        'Booking: ${session.bookingUrl}';

    try {
      final event = Event(
        title: summary,
        description: desc,
        location: '${studio.address}, New York, NY',
        startDate: startDt,
        endDate: endDt,
        timeZone: 'America/New_York',
        allDay: false,
        iosParams: IOSParams(
          reminder: const Duration(hours: 2),
          url: session.bookingUrl,
        ),
      );

      final ok = await Add2Calendar.addEvent2Cal(event);
      return ok;
    } catch (_) {
      // Native plugin not available in the currently running process (e.g. desktop or test environment)
      return exportSingleSessionToIcs(session);
    }
  }

  /// Builds the iCalendar RFC-5545 string for a single session.
  static String generateSingleSessionIcsContent(ClassSession session) {
    final tpl = templatesById[session.templateId];
    if (tpl == null) return '';
    final studio = studios[session.studioId]!;
    final date = session.serviceDate;

    final startH = session.startMin ~/ 60;
    final startM = session.startMin % 60;
    final endH = session.endMin ~/ 60;
    final endM = session.endMin % 60;

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

    final teacher = session.instructor;
    final subNote = session.isSubstitute ? ' [SUBSTITUTE TEACHER]' : '';
    final summary = escapeIcsText('${tpl.title} (${tpl.rawLevelLabel}) at ${studio.shortName}');
    final classDesc = (session.description != null && session.description!.trim().isNotEmpty)
        ? session.description!
        : (tpl.description.trim().isNotEmpty)
            ? "Studio's style description: ${tpl.description.trim()}"
            : 'A description has not been provided for this class.';
    final rawDesc = '$classDesc\n\n'
        'Instructor: $teacher$subNote\n'
        'Studio: ${studio.name} (${studio.address}, ${studio.neighborhood})\n'
        'Booking: ${session.bookingUrl}';
    final desc = escapeIcsText(rawDesc);

    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//NYC Solo Dance Calendar//EN');
    buffer.writeln('CALSCALE:GREGORIAN');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('X-WR-CALNAME:${tpl.title} at ${studio.shortName}');
    buffer.writeln('X-WR-TIMEZONE:America/New_York');

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

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:${session.id}@nycdancecalendar.app');
    buffer.writeln('DTSTAMP:${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z');
    buffer.writeln('DTSTART;TZID=America/New_York:$dtStart');
    buffer.writeln('DTEND;TZID=America/New_York:$dtEnd');
    buffer.writeln('SUMMARY:$summary');
    buffer.writeln('LOCATION:${studio.address}, New York, NY');
    buffer.writeln('DESCRIPTION:$desc');
    buffer.writeln('URL:${session.bookingUrl}');
    buffer.writeln('STATUS:CONFIRMED');
    buffer.writeln('END:VEVENT');

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// Exports a single session as an iCalendar (.ics) file.
  static Future<bool> exportSingleSessionToIcs(ClassSession session) async {
    final tpl = templatesById[session.templateId];
    if (tpl == null) return false;
    final studio = studios[session.studioId]!;
    final date = session.serviceDate;
    final summary = '${tpl.title} (${tpl.rawLevelLabel}) at ${studio.shortName}';

    final icsContent = generateSingleSessionIcsContent(session);
    if (icsContent.isEmpty) return false;

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/dance_class_${dateClean(session.id)}.ics');
    await file.writeAsString(icsContent);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar')],
        subject: '$summary on ${date.toString()}',
        text: 'Calendar invite for $summary on ${date.toString()}.',
      ),
    );

    return result.status == ShareResultStatus.success;
  }


  /// Builds the iCalendar RFC-5545 string for a weekly regimen and enrolled series.
  static String generateRegimenIcsContent({
    required List<ResolvedSlot> regimenSlots,
    required String weekLabel,
    List<WorkshopSeries> enrolledSeries = const [],
    ServiceDate? weekStart,
  }) {
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

    final dtStamp =
        '${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';

    for (final resolved in regimenSlots) {
      if (resolved.health == SlotHealth.cancelled ||
          resolved.health == SlotHealth.removed ||
          resolved.health == SlotHealth.notOnSchedule) {
        continue;
      }

      final session = resolved.session;
      final tpl = getTemplate(resolved.slot.templateId);
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

      final teacher = session?.instructor ?? resolved.slot.instructor ?? 'Staff';
      final subNote =
          session?.isSubstitute == true ? ' [SUBSTITUTE TEACHER]' : '';

      final summary = escapeIcsText(
          '${tpl.title} (${tpl.rawLevelLabel}) at ${studio.shortName}');
      final classDesc =
          (session?.description != null && session!.description!.trim().isNotEmpty)
              ? session.description!
              : (tpl.description.trim().isNotEmpty)
                  ? "Studio's style description: ${tpl.description.trim()}"
                  : 'A description has not been provided for this class.';
      final rawDesc = '$classDesc\n\n'
          'Instructor: $teacher$subNote\n'
          'Attire: ${tpl.attireNotes ?? "Comfortable dance attire"}\n'
          'Studio: ${studio.name} (${studio.address}, ${studio.neighborhood})\n'
          'Booking: ${session?.bookingUrl ?? tpl.catalogUrl}';
      final desc = escapeIcsText(rawDesc);

      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln(
          'UID:${resolved.slot.templateId}-${resolved.date}-${resolved.slot.startMin}@nycdancecalendar.app');
      buffer.writeln('DTSTAMP:$dtStamp');
      buffer.writeln('DTSTART;TZID=America/New_York:$dtStart');
      buffer.writeln('DTEND;TZID=America/New_York:$dtEnd');
      buffer.writeln('SUMMARY:$summary');
      buffer.writeln('LOCATION:${studio.address}, New York, NY');
      buffer.writeln('DESCRIPTION:$desc');
      buffer.writeln('URL:${session?.bookingUrl ?? tpl.catalogUrl}');
      buffer.writeln('STATUS:CONFIRMED');
      buffer.writeln('END:VEVENT');
    }

    // Export enrolled series meetings
    for (final s in enrolledSeries) {
      final studio = studios[s.studioId]!;
      final tpl = getTemplate(s.templateId);
      for (var w = 0; w < s.sessionCount; w++) {
        final date = s.startDate.addDays(7 * w);
        if (weekStart != null) {
          final weekEnd = weekStart.addDays(6);
          if (date.compareTo(weekStart) < 0 || date.compareTo(weekEnd) > 0) {
            continue;
          }
        }
        final startH = s.startMin ~/ 60;
        final startM = s.startMin % 60;
        final endMin = s.startMin + s.durationMin;
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

        final summary = escapeIcsText(
            '${s.title} (Week ${w + 1}/${s.sessionCount}) at ${studio.shortName}');
        final rawDesc = '${tpl.description.isNotEmpty ? tpl.description : s.title}\n\n'
            'Instructor: ${s.instructor}\n'
            'Studio: ${studio.name} (${studio.address}, ${studio.neighborhood})\n'
            'Booking: ${s.bookingUrl}';
        final desc = escapeIcsText(rawDesc);

        buffer.writeln('BEGIN:VEVENT');
        buffer.writeln('UID:${s.id}-wk${w + 1}@nycdancecalendar.app');
        buffer.writeln('DTSTAMP:$dtStamp');
        buffer.writeln('DTSTART;TZID=America/New_York:$dtStart');
        buffer.writeln('DTEND;TZID=America/New_York:$dtEnd');
        buffer.writeln('SUMMARY:$summary');
        buffer.writeln('LOCATION:${studio.address}, New York, NY');
        buffer.writeln('DESCRIPTION:$desc');
        buffer.writeln('URL:${s.bookingUrl}');
        buffer.writeln('STATUS:CONFIRMED');
        buffer.writeln('END:VEVENT');
      }
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// Exports the user's resolved regimen slots and enrolled series as an iCalendar (.ics) file.
  static Future<void> exportRegimenToCalendar({
    required List<ResolvedSlot> regimenSlots,
    required String weekLabel,
    List<WorkshopSeries> enrolledSeries = const [],
    ServiceDate? weekStart,
  }) async {
    final icsContent = generateRegimenIcsContent(
      regimenSlots: regimenSlots,
      weekLabel: weekLabel,
      enrolledSeries: enrolledSeries,
      weekStart: weekStart,
    );
    if (!icsContent.contains('BEGIN:VEVENT')) {
      return;
    }

    // Write to a temporary .ics file and trigger share sheet
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/dance_regimen_${dateClean(weekLabel)}.ics');
    await file.writeAsString(icsContent);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar')],
        subject: 'NYC Dance Regimen ($weekLabel)',
        text: 'Exported dance classes for $weekLabel.',
      ),
    );
  }

  /// Escapes text values according to RFC 5545 section 3.3.11.
  static String escapeIcsText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n');
  }

  static String dateClean(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
}
