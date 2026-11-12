/// Domain models for the NYC Solo Dance Calendar prototype.
///
/// These mirror the approved feed shape (see design_decisions.md):
/// hand-curated [ClassTemplate]s, dated [ClassSession]s, and separate
/// [WorkshopSeries]. Plain immutable classes are used for the prototype;
/// production code would use `freezed` + `json_serializable`.
library;

import 'package:flutter/material.dart';

enum StudioId { bdc, steps, ailey, peridance, pmt }

class Studio {
  const Studio({
    required this.id,
    required this.name,
    required this.shortName,
    required this.address,
    required this.neighborhood,
    required this.color,
    required this.lat,
    required this.lng,
  });

  final StudioId id;
  final String name;
  final String shortName;
  final String address;
  final String neighborhood;
  final Color color;
  final double lat;
  final double lng;
}

/// Three hand-assigned tiers (Q4). The studio's raw label is always shown.
enum Tier {
  zeroExperience('Zero experience'),
  beginner('Beginner'),
  advancedBeginner('Adv. beginner');

  const Tier(this.label);
  final String label;
}

/// Extensible genre vocabulary (Q5). Templates carry a primary genre + tags.
enum Genre {
  ballet('Ballet', Icons.self_improvement),
  contemporaryModern('Contemporary / Modern', Icons.waves),
  jazzTheater('Jazz / Theater', Icons.theater_comedy),
  tap('Tap', Icons.music_note),
  hipHopStreet('Hip-Hop / Street', Icons.graphic_eq),
  commercialHeels('Commercial / Heels', Icons.star_outline),
  africanDiaspora('African / Afro-diasporic', Icons.public),
  worldCultural('World / Cultural', Icons.language),
  other('Other', Icons.category_outlined);

  const Genre(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum SessionStatus { scheduled, cancelled, removed }

/// A calendar date in America/New_York, independent of device timezone (Q13).
@immutable
class ServiceDate implements Comparable<ServiceDate> {
  const ServiceDate(this.year, this.month, this.day);

  factory ServiceDate.fromDateTime(DateTime d) =>
      ServiceDate(d.year, d.month, d.day);

  /// Parses `YYYY-MM-DD`.
  factory ServiceDate.parse(String s) {
    final p = s.split('-').map(int.parse).toList();
    return ServiceDate(p[0], p[1], p[2]);
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// 1 = Monday ... 7 = Sunday.
  int get weekday => _utc.weekday;

  ServiceDate addDays(int n) =>
      ServiceDate.fromDateTime(_utc.add(Duration(days: n)));

  ServiceDate get startOfWeek => addDays(-(weekday - 1));

  int daysUntil(ServiceDate other) => other._utc.difference(_utc).inDays;

  @override
  int compareTo(ServiceDate other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) =>
      other is ServiceDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// One recurring weekly slot of a template, with its regular teacher.
class TemplateSlot {
  const TemplateSlot({
    required this.weekday,
    required this.startMin,
    required this.durationMin,
    required this.regularInstructor,
  });

  final int weekday; // 1 = Mon
  final int startMin; // minutes after local midnight (NY wall clock)
  final int durationMin;
  final String regularInstructor;
}

/// Hand-curated class definition (Q2). Classified once, by a human.
class ClassTemplate {
  const ClassTemplate({
    required this.id,
    required this.studioId,
    required this.title,
    required this.rawLevelLabel,
    required this.tier,
    required this.primaryGenre,
    this.tags = const {},
    required this.slots,
    required this.description,
    this.prerequisiteNotes,
    this.attireNotes,
    required this.catalogUrl,
  });

  final String id;
  final StudioId studioId;
  final String title;
  final String rawLevelLabel; // e.g. "BASIC", "ABS BEG", "INTRO"
  final Tier tier;
  final Genre primaryGenre;
  final Set<Genre> tags;
  final List<TemplateSlot> slots;
  final String description;
  final String? prerequisiteNotes;
  final String? attireNotes;
  final String catalogUrl;

  Set<Genre> get allGenres => {primaryGenre, ...tags};
}

/// A dated occurrence, as scraped from Mindbody (Q7, Q13).
class ClassSession {
  const ClassSession({
    required this.id,
    required this.templateId,
    required this.studioId,
    required this.serviceDate,
    required this.startMin,
    required this.endMin,
    required this.instructor,
    this.description,
    required this.isSubstitute,
    required this.status,
    required this.bookingUrl,
    this.tz = 'America/New_York',
  });

  final String id; // Mindbody class-instance id
  final String templateId;
  final StudioId studioId;
  final ServiceDate serviceDate;
  final int startMin;
  final int endMin;
  final String tz;
  final String instructor;
  final String? description;
  final bool isSubstitute;
  final SessionStatus status;
  final String bookingUrl;

  int get durationMin => endMin - startMin;
  bool get isCancelled => status == SessionStatus.cancelled;
}

/// Multi-week series that must be bought as a block (Q6).
class WorkshopSeries {
  const WorkshopSeries({
    required this.id,
    required this.templateId,
    required this.studioId,
    required this.title,
    required this.startDate,
    required this.sessionCount,
    required this.weekday,
    required this.startMin,
    required this.durationMin,
    required this.instructor,
    required this.enrollmentOpen,
    required this.price,
    required this.bookingUrl,
  });

  final String id;
  final String templateId;
  final StudioId studioId;
  final String title;
  final ServiceDate startDate;
  final int sessionCount;
  final int weekday;
  final int startMin;
  final int durationMin;
  final String instructor;
  final bool enrollmentOpen;
  final String price;
  final String bookingUrl;

  ServiceDate get endDate => startDate.addDays(7 * (sessionCount - 1));

  /// 1-based week number if [d] is a session date of this series.
  int? weekNumberOn(ServiceDate d) {
    final diff = startDate.daysUntil(d);
    if (diff < 0 || diff % 7 != 0) return null;
    final n = diff ~/ 7 + 1;
    return n <= sessionCount ? n : null;
  }
}

/// A device-local "regimen" entry: a recurring weekly slot (Q10).
@immutable
class SavedSlot {
  const SavedSlot({
    required this.templateId,
    required this.weekday,
    required this.startMin,
    this.instructor,
  });

  final String templateId;
  final int weekday;
  final int startMin;
  final String? instructor;

  bool matches(ClassSession s) =>
      s.templateId == templateId &&
      s.serviceDate.weekday == weekday &&
      s.startMin == startMin &&
      (instructor == null || s.instructor == instructor);

  @override
  bool operator ==(Object other) =>
      other is SavedSlot &&
      other.templateId == templateId &&
      other.weekday == weekday &&
      other.startMin == startMin &&
      other.instructor == instructor;

  @override
  int get hashCode => Object.hash(templateId, weekday, startMin, instructor);
}

// ---------------------------------------------------------------------------
// America/New_York timezone helpers (independent of device timezone).

/// Determines if US Eastern Daylight Time (EDT) is active for a given UTC datetime.
bool isEasternDst([DateTime? utcNow]) {
  final utc = utcNow ?? DateTime.now().toUtc();
  if (utc.month < 3 || utc.month > 11) return false;
  if (utc.month > 3 && utc.month < 11) return true;
  if (utc.month == 3) {
    // 2nd Sunday in March
    final firstDayWeekday = DateTime.utc(utc.year, 3, 1).weekday;
    final secondSundayDay = (7 - firstDayWeekday) % 7 + 8;
    return utc.day > secondSundayDay ||
        (utc.day == secondSundayDay && utc.hour >= 7);
  } else {
    // 1st Sunday in November
    final firstDayWeekday = DateTime.utc(utc.year, 11, 1).weekday;
    final firstSundayDay = (7 - firstDayWeekday) % 7 + 1;
    return utc.day < firstSundayDay ||
        (utc.day == firstSundayDay && utc.hour < 6);
  }
}

/// Returns the current date in America/New_York (independent of local device timezone).
ServiceDate getTodayInNewYork() {
  final utc = DateTime.now().toUtc();
  final offsetHours = isEasternDst(utc) ? -4 : -5;
  final nyTime = utc.add(Duration(hours: offsetHours));
  return ServiceDate(nyTime.year, nyTime.month, nyTime.day);
}

/// Returns current minutes after midnight in America/New_York.
int getNowMinInNewYork() {
  final utc = DateTime.now().toUtc();
  final offsetHours = isEasternDst(utc) ? -4 : -5;
  final nyTime = utc.add(Duration(hours: offsetHours));
  return nyTime.hour * 60 + nyTime.minute;
}

// ---------------------------------------------------------------------------
// Formatting helpers (NY wall-clock; no timezone conversion in the UI layer).

String formatTime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final ampm = h < 12 ? 'am' : 'pm';
  return m == 0 ? '$h12$ampm' : '$h12:${m.toString().padLeft(2, '0')}$ampm';
}

String formatRange(int start, int end) =>
    '${formatTime(start)}–${formatTime(end)}';

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDate(ServiceDate d) =>
    '${weekdayShort[d.weekday - 1]} ${monthShort[d.month - 1]} ${d.day}';
