/// The parsed schedule feed plus the lookups the UI needs: studio details,
/// the class-template registry, and travel times between studios.
///
/// All schedule data comes from `schedule.json` (bundled asset, local cache,
/// or the remote feed). Studio details mirror `backend/data/studios.json`.
library;

import 'package:flutter/material.dart';

import '../domain/models.dart';

/// Built-in studio details, used until the feed's `studios` list is parsed
/// (and as a fallback for any studio the feed omits). The feed, generated from
/// `backend/data/studios.json`, is the source of truth.
const _fallbackStudios = <StudioId, Studio>{
  StudioId.bdc: Studio(
    id: StudioId.bdc,
    name: 'Broadway Dance Center',
    shortName: 'BDC',
    address: '322 W 45th St, 3rd Fl',
    neighborhood: 'Hell\'s Kitchen',
    color: Color(0xFFC62828), // crimson
  ),
  StudioId.steps: Studio(
    id: StudioId.steps,
    name: 'Steps on Broadway',
    shortName: 'Steps',
    address: '2121 Broadway, 3rd Fl',
    neighborhood: 'Upper West Side',
    color: Color(0xFF3949AB), // indigo
  ),
  StudioId.ailey: Studio(
    id: StudioId.ailey,
    name: 'Ailey Extension',
    shortName: 'Ailey',
    address: '405 W 55th St',
    neighborhood: 'Hell\'s Kitchen',
    color: Color(0xFFF9A825), // amber
  ),
  StudioId.peridance: Studio(
    id: StudioId.peridance,
    name: 'Peridance Center',
    shortName: 'Peridance',
    address: '126 E 13th St',
    neighborhood: 'Union Square',
    color: Color(0xFF00897B), // teal
  ),
  StudioId.pmt: Studio(
    id: StudioId.pmt,
    name: 'PMT House of Dance',
    shortName: 'PMT',
    address: '28 W 25th St, 2nd Fl',
    neighborhood: 'Flatiron',
    color: Color(0xFF7B1FA2), // purple
  ),
  StudioId.danznik: Studio(
    id: StudioId.danznik,
    name: 'Danznik Studios NYC',
    shortName: 'Danznik',
    address: '240 W 37th St, 2nd Fl',
    neighborhood: 'Garment District',
    color: Color(0xFFD81B60), // pink
  ),
};

/// Current studio details, keyed by id. Seeded from [_fallbackStudios] and
/// overwritten by [registerStudios] when a feed is parsed.
final studios = <StudioId, Studio>{..._fallbackStudios};

/// Replaces entries in [studios] with the given feed-provided studios.
void registerStudios(Iterable<Studio> feedStudios) {
  for (final s in feedStudios) {
    studios[s.id] = s;
  }
}

/// Restores [studios] to the built-in fallback values (used by tests).
@visibleForTesting
void resetStudios() {
  studios
    ..clear()
    ..addAll(_fallbackStudios);
}

/// Class templates by id, filled by [registerTemplates] when a feed is parsed.
final templatesById = <String, ClassTemplate>{};

/// The template for [id], or a generic placeholder if the feed has none.
ClassTemplate getTemplate(String id) {
  return templatesById[id] ??
      ClassTemplate(
        id: id,
        studioId: StudioId.bdc,
        title: 'Dance Class',
        rawLevelLabel: 'OPEN',
        tier: Tier.beginner,
        primaryGenre: Genre.other,
        slots: const [],
        description: '',
        catalogUrl: '',
      );
}

void registerTemplates(List<ClassTemplate> newTemplates) {
  for (final t in newTemplates) {
    templatesById[t.id] = t;
  }
}

/// One parsed feed: drop-in sessions and workshop series for a 14-day window.
class Feed {
  const Feed({
    required this.today,
    required this.windowStart,
    required this.sessions,
    required this.series,
  });

  /// A feed with no classes, used while the real feed is loading.
  Feed.empty(this.today)
      : windowStart = today.startOfWeek,
        sessions = const [],
        series = const [];

  final ServiceDate today;
  final ServiceDate windowStart;
  final List<ClassSession> sessions;
  final List<WorkshopSeries> series;

  ServiceDate get windowEnd => windowStart.addDays(13);
}

// ---------------------------------------------------------------------------
// Realistic transit times between all Manhattan dance studios (verified via Google Maps)

class Commute {
  const Commute(this.minutes, this.mode);
  final int minutes;
  final String mode; // 'walk' | 'subway' | 'same studio'
  @override
  String toString() => mode == 'same studio' ? 'same studio' : '~$minutes min $mode';
}

const _transitTable = <(StudioId, StudioId), Commute>{
  // Ailey Extension (405 W 55th St)
  (StudioId.ailey, StudioId.bdc): Commute(12, 'walk'),
  (StudioId.ailey, StudioId.steps): Commute(18, 'subway'),
  (StudioId.ailey, StudioId.peridance): Commute(28, 'subway'),
  (StudioId.ailey, StudioId.pmt): Commute(25, 'subway'),

  // Broadway Dance Center (322 W 45th St)
  (StudioId.bdc, StudioId.steps): Commute(18, 'subway'),
  (StudioId.bdc, StudioId.peridance): Commute(22, 'subway'),
  (StudioId.bdc, StudioId.pmt): Commute(20, 'subway'),

  // Steps on Broadway (2121 Broadway @ 74th St)
  (StudioId.steps, StudioId.peridance): Commute(28, 'subway'),
  (StudioId.steps, StudioId.pmt): Commute(22, 'subway'),

  // Peridance Center (126 E 13th St)
  (StudioId.peridance, StudioId.pmt): Commute(14, 'subway'),

  // Danznik Studios NYC (240 W 37th St). Estimated from distance and subway
  // routes, not yet checked against Google Maps.
  (StudioId.danznik, StudioId.bdc): Commute(12, 'walk'),
  (StudioId.danznik, StudioId.pmt): Commute(16, 'walk'),
  (StudioId.danznik, StudioId.ailey): Commute(20, 'subway'),
  (StudioId.danznik, StudioId.steps): Commute(18, 'subway'),
  (StudioId.danznik, StudioId.peridance): Commute(20, 'subway'),
};

Commute commuteBetween(StudioId a, StudioId b) {
  if (a == b) return const Commute(0, 'same studio');
  final direct = _transitTable[(a, b)];
  if (direct != null) return direct;
  final reverse = _transitTable[(b, a)];
  if (reverse != null) return reverse;
  return const Commute(25, 'subway');
}
