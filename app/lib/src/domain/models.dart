/// Domain models for the NYC Solo Dance Calendar prototype.
///
/// These mirror the approved feed shape (see design_decisions.md):
/// hand-curated [ClassTemplate]s, dated [ClassSession]s, and separate
/// [WorkshopSeries]. Plain immutable classes are used for the prototype;
/// production code would use `freezed` + `json_serializable`.
library;

import 'package:flutter/material.dart';

enum StudioId { bdc, steps, ailey, peridance, pmt, danznik }

class Studio {
  const Studio({
    required this.id,
    required this.name,
    required this.shortName,
    required this.address,
    required this.neighborhood,
    required this.color,
  });

  final StudioId id;
  final String name;
  final String shortName;
  final String address;
  final String neighborhood;
  final Color color;
}

/// Normalized level tiers (Q4). The studio's raw label is always shown.
enum Tier {
  zeroExperience('Basic'), // Basic, Abs Beg, Intro: zero experience needed
  beginner('Beginner'),
  advancedBeginner('Adv. beginner'),
  intermediate('Intermediate'),
  advanced('Advanced'),
  allLevels('Open / All levels');

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
  social('Social', Icons.people_outline),
  ballroom('Ballroom', Icons.nightlife),
  misc('Misc.', Icons.fitness_center),
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
    this.instructorKey,
    this.regularInstructor,
    this.rawTitle,
    this.description,
    required this.isSubstitute,
    required this.status,
    required this.bookingUrl,
  });

  final String id; // Mindbody class-instance id
  final String templateId;
  final StudioId studioId;
  final ServiceDate serviceDate;
  final int startMin;
  final int endMin;
  final String instructor;

  /// Canonical matching key from the feed (alias-resolved, normalized).
  /// Older feeds omit it; use [matchKey] rather than reading this directly.
  final String? instructorKey;

  /// Original regular teacher reported by the studio when a sub or cancellation
  /// replaces [instructor] (optional; omitted by most scrapers).
  final String? regularInstructor;

  /// The class name exactly as the studio lists it, e.g.
  /// "Adv Beg THEATER with Jason Wise". Use [title] for display.
  final String? rawTitle;
  final String? description;
  final bool isSubstitute;
  final SessionStatus status;
  final String bookingUrl;

  /// The studio's own class name, minus any " with [teacher]" suffix (the
  /// suffix names the regular teacher, which is wrong when a sub teaches).
  /// Null when the feed has no raw title; callers fall back to the template.
  String? get title {
    final raw = rawTitle;
    if (raw == null) return null;
    final t = raw.split(' with ').first.trim().split(RegExp(r'\s+')).join(' ');
    return t.isEmpty ? null : t;
  }

  /// Key used to compare this session's teacher against a saved slot.
  String get matchKey => instructorKey ?? normalizeInstructor(instructor);

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

/// Matching key for an instructor name.
///
/// Must stay identical to normalize_instructor() in backend/src/instructor_names.py:
/// collapse whitespace, drop quote characters, lowercase, trim.
String normalizeInstructor(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .join(' ')
    .replaceAll(RegExp('["\']'), '')
    .toLowerCase()
    .trim();

/// Built-in copy of PLACEHOLDER_INSTRUCTORS in
/// backend/src/instructor_names.py, used when the feed omits
/// `placeholderInstructors` (feeds older than v1.1).
const defaultPlaceholderInstructors = <String>[
  'staff',
  'tba',
  'tbd',
  'guest artist',
  'special guest',
  'substitute teacher',
  'various teachers',
];

/// A device-local "regimen" entry: a recurring weekly slot (Q10).
@immutable
class SavedSlot {
  const SavedSlot({
    required this.templateId,
    required this.weekday,
    required this.startMin,
    this.instructor,
    this.instructorKey,
  });

  final String templateId;
  final int weekday;
  final int startMin;

  /// Teacher's name as displayed when the slot was saved.
  final String? instructor;

  /// Canonical key of that teacher (see [ClassSession.matchKey]). Null for
  /// slots saved before keys existed; [teacherKey] then falls back to the
  /// normalized display name.
  final String? instructorKey;

  String? get teacherKey {
    if (instructorKey != null && instructorKey!.isNotEmpty) return instructorKey;
    if (instructor == null || instructor!.isEmpty) return null;
    return normalizeInstructor(instructor!);
  }

  /// Same class, weekday and start time, whoever teaches it.
  bool matchesSlot(ClassSession s) =>
      s.templateId == templateId &&
      s.serviceDate.weekday == weekday &&
      s.startMin == startMin;

  /// Same slot and the saved teacher (or any teacher if none was saved).
  bool matches(ClassSession s) {
    if (!matchesSlot(s)) return false;
    final key = teacherKey;
    if (key == null) return true;
    // The raw-name check keeps legacy slots (display name only) matching
    // sessions whose key was alias-resolved to a different canonical name.
    return s.matchKey == key || normalizeInstructor(s.instructor) == key;
  }

  @override
  bool operator ==(Object other) =>
      other is SavedSlot &&
      other.templateId == templateId &&
      other.weekday == weekday &&
      other.startMin == startMin &&
      other.teacherKey == teacherKey;

  @override
  int get hashCode => Object.hash(templateId, weekday, startMin, teacherKey);
}

/// The session a saved slot resolves to on one date.
class SlotMatch {
  const SlotMatch(this.session, {required this.exact});
  final ClassSession session;

  /// False when the saved teacher isn't teaching and this session was picked
  /// as the only plausible stand-in (i.e. a substitute).
  final bool exact;

  /// A stand-in, or a session the studio itself flags as subbed.
  bool get isSubstitute => !exact || session.isSubstitute;
}

/// Finds the session [slot] refers to on [date].
///
/// 1. A session taught by the saved teacher wins.
/// 2. Otherwise, among same-slot sessions not claimed exactly by another saved
///    slot, if they are all taught by one person, that's the substitute.
///    With concurrent sections, a single studio-flagged sub breaks the tie.
/// 3. Otherwise null (not on schedule / ambiguous).
SlotMatch? resolveSlot(
  SavedSlot slot,
  ServiceDate date,
  Iterable<ClassSession> sessions,
  Iterable<SavedSlot> allSaved,
) {
  final candidates = sessions
      .where((s) => s.serviceDate == date && slot.matchesSlot(s))
      .toList()
    // Prefer scheduled over cancelled/removed when duplicates exist.
    ..sort((a, b) => a.status.index.compareTo(b.status.index));
  if (candidates.isEmpty) return null;

  final exact = candidates.where(slot.matches);
  if (exact.isNotEmpty) return SlotMatch(exact.first, exact: true);

  final others = allSaved.where((o) => o != slot).toList();
  var loose = candidates
      .where((s) => !others.any((o) => o.matches(s)))
      .toList();
  // Do not claim an unflagged teacher who is known to teach another concurrent
  // section at this same (template, weekday, time) on another date.
  final knownConcurrentKeys = <String>{};
  final exactDates = sessions
      .where((s) => slot.matches(s))
      .map((s) => (s.serviceDate, s.matchKey))
      .toList();
  if (exactDates.isNotEmpty) {
    for (final s in sessions) {
      if (!slot.matchesSlot(s)) continue;
      for (final (d, myKey) in exactDates) {
        if (s.serviceDate == d && s.matchKey != myKey) {
          knownConcurrentKeys.add(s.matchKey);
        }
      }
    }
  }
  if (knownConcurrentKeys.isNotEmpty) {
    loose = loose
        .where((s) => s.isSubstitute || !knownConcurrentKeys.contains(s.matchKey))
        .toList();
  }
  if (loose.map((s) => s.matchKey).toSet().length > 1) {
    loose = loose.where((s) => s.isSubstitute).toList();
  }
  if (loose.isEmpty || loose.map((s) => s.matchKey).toSet().length > 1) {
    return null;
  }
  return SlotMatch(loose.first, exact: false);
}

/// Saved slots that resolve to [session] on its date.
Iterable<SavedSlot> slotsClaiming(
  ClassSession session,
  Iterable<ClassSession> sessions,
  Iterable<SavedSlot> allSaved,
) =>
    allSaved.where((slot) {
      if (!slot.matchesSlot(session)) return false;
      if (slot.matches(session)) return true;
      return resolveSlot(slot, session.serviceDate, sessions, allSaved)
              ?.session
              .id ==
          session.id;
    });

// ---------------------------------------------------------------------------
// America/New_York timezone helpers (independent of device timezone).

/// Determines if US Eastern Daylight Time (EDT) is active for a given UTC datetime.
bool isEasternDst([DateTime? utcNow]) {
  final utc = (utcNow ?? DateTime.now()).toUtc();
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

/// Converts a NY wall-clock [date] and [minutesAfterMidnight] into the exact
/// UTC [DateTime] instant, handling DST transitions and >= 1440 rollover.
DateTime nyWallClockToUtc(ServiceDate date, int minutesAfterMidnight) {
  final extraDays = minutesAfterMidnight ~/ 1440;
  final rem = minutesAfterMidnight % 1440;
  final d = extraDays == 0 ? date : date.addDays(extraDays);
  final h = rem ~/ 60;
  final m = rem % 60;

  bool isEdt;
  if (d.month < 3 || d.month > 11) {
    isEdt = false;
  } else if (d.month > 3 && d.month < 11) {
    isEdt = true;
  } else if (d.month == 3) {
    final firstW = DateTime.utc(d.year, 3, 1).weekday;
    final secondSun = (7 - firstW) % 7 + 8;
    isEdt = d.day > secondSun || (d.day == secondSun && h >= 2);
  } else {
    final firstW = DateTime.utc(d.year, 11, 1).weekday;
    final firstSun = (7 - firstW) % 7 + 1;
    isEdt = d.day < firstSun || (d.day == firstSun && h < 2);
  }

  final offsetHours = isEdt ? 4 : 5;
  return DateTime.utc(d.year, d.month, d.day, h, m)
      .add(Duration(hours: offsetHours));
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
  final h = (minutes ~/ 60) % 24;
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
