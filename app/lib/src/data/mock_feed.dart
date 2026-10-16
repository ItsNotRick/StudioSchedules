/// Realistic-shaped MOCK data for the view prototypes.
///
/// Studio addresses are best-effort and must be verified. Instructor names
/// are fictional placeholders. Class titles/levels are plausible examples,
/// not a scrape of real schedules.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models.dart';

const studios = <StudioId, Studio>{
  StudioId.bdc: Studio(
    id: StudioId.bdc,
    name: 'Broadway Dance Center',
    shortName: 'BDC',
    address: '322 W 45th St',
    neighborhood: 'Hell\'s Kitchen',
    color: Color(0xFFC62828), // crimson
    lat: 40.7598,
    lng: -73.9891,
  ),
  StudioId.steps: Studio(
    id: StudioId.steps,
    name: 'Steps on Broadway',
    shortName: 'Steps',
    address: '2121 Broadway',
    neighborhood: 'Upper West Side',
    color: Color(0xFF3949AB), // indigo
    lat: 40.7806,
    lng: -73.9810,
  ),
  StudioId.ailey: Studio(
    id: StudioId.ailey,
    name: 'Ailey Extension',
    shortName: 'Ailey',
    address: '405 W 55th St',
    neighborhood: 'Hell\'s Kitchen',
    color: Color(0xFFF9A825), // amber
    lat: 40.7668,
    lng: -73.9867,
  ),
  StudioId.peridance: Studio(
    id: StudioId.peridance,
    name: 'Peridance Center',
    shortName: 'Peridance',
    address: '126 E 13th St',
    neighborhood: 'Union Square',
    color: Color(0xFF00897B), // teal
    lat: 40.7334,
    lng: -73.9887,
  ),
  StudioId.pmt: Studio(
    id: StudioId.pmt,
    name: 'PMT House of Dance',
    shortName: 'PMT',
    address: 'W 25th St (verify)',
    neighborhood: 'Flatiron',
    color: Color(0xFF7B1FA2), // purple
    lat: 40.7437,
    lng: -73.9905,
  ),
};

const _homepages = {
  StudioId.bdc: 'https://www.broadwaydancecenter.com',
  StudioId.steps: 'https://www.stepsnyc.com',
  StudioId.ailey: 'https://www.ailey.org',
  StudioId.peridance: 'https://www.peridance.com',
  StudioId.pmt: 'https://www.pmthouseofdance.com',
};

int _t(int h, [int m = 0]) => h * 60 + m;

TemplateSlot _s(int weekday, int start, int dur, String teacher) => TemplateSlot(
      weekday: weekday,
      startMin: start,
      durationMin: dur,
      regularInstructor: teacher,
    );

const _balletAttire =
    'Form-fitting clothing; ballet slippers or socks. Hair secured away from the face.';
const _sneakerAttire = 'Comfortable clothes you can move in; clean sneakers.';
const _barefootAttire = 'Form-fitting clothing; barefoot or socks.';

final templates = <ClassTemplate>[
  // ---------------- BDC
  ClassTemplate(
    id: 'bdc_basic_ballet',
    studioId: StudioId.bdc,
    title: 'Basic Ballet',
    rawLevelLabel: 'BASIC',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.ballet,
    slots: [
      _s(1, _t(9), 90, 'Dana R.'),
      _s(3, _t(9), 90, 'Dana R.'),
      _s(6, _t(10), 90, 'Lena M.'),
    ],
    description:
        'An introduction to ballet vocabulary at the barre and in the center: posture, turnout, pliés, tendus and simple across-the-floor combinations.',
    prerequisiteNotes: 'No prior experience required.',
    attireNotes: _balletAttire,
    catalogUrl: _homepages[StudioId.bdc]!,
  ),
  ClassTemplate(
    id: 'bdc_basic_jazz',
    studioId: StudioId.bdc,
    title: 'Basic Jazz',
    rawLevelLabel: 'BASIC',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.jazzTheater,
    slots: [_s(2, _t(18), 90, 'Marcus T.'), _s(4, _t(18), 90, 'Marcus T.')],
    description:
        'Isolations, basic jazz walks, pas de bourrée, simple turns and a short combination.',
    prerequisiteNotes: 'No prior experience required.',
    attireNotes: 'Jazz shoes or sneakers; clothing you can move in.',
    catalogUrl: _homepages[StudioId.bdc]!,
  ),
  ClassTemplate(
    id: 'bdc_basic_hiphop',
    studioId: StudioId.bdc,
    title: 'Basic Hip Hop',
    rawLevelLabel: 'BASIC',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.hipHopStreet,
    slots: [_s(1, _t(18, 30), 90, 'Jay K.'), _s(5, _t(19), 90, 'Jay K.')],
    description:
        'Grooves, bounce and rock, foundational party steps and a beginner-paced combo.',
    prerequisiteNotes: 'No prior experience required.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.bdc]!,
  ),
  ClassTemplate(
    id: 'bdc_beg_heels',
    studioId: StudioId.bdc,
    title: 'Beginner Heels',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.commercialHeels,
    tags: {Genre.jazzTheater},
    slots: [_s(3, _t(19, 30), 90, 'Sasha V.')],
    description:
        'Walks, poses and floor work in heels with an emphasis on balance and safe technique.',
    prerequisiteNotes: 'Some movement experience helpful.',
    attireNotes: 'Heels with ankle support (or sneakers for first class); knee pads optional.',
    catalogUrl: _homepages[StudioId.bdc]!,
  ),
  ClassTemplate(
    id: 'bdc_beg_theater',
    studioId: StudioId.bdc,
    title: 'Beginner Theater Dance',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.jazzTheater,
    slots: [_s(6, _t(13), 90, 'Owen P.')],
    description: 'Broadway-style choreography with storytelling and character work.',
    attireNotes: 'Jazz shoes or sneakers.',
    catalogUrl: _homepages[StudioId.bdc]!,
  ),
  ClassTemplate(
    id: 'bdc_advbeg_tap',
    studioId: StudioId.bdc,
    title: 'Adv Beg Tap',
    rawLevelLabel: 'ADV BEG',
    tier: Tier.advancedBeginner,
    primaryGenre: Genre.tap,
    slots: [_s(4, _t(17, 30), 90, 'Ruth A.')],
    description: 'Shuffles, flaps, paddle-and-rolls and time steps at a moderate tempo.',
    prerequisiteNotes: 'Comfortable with basic tap steps.',
    attireNotes: 'Tap shoes required.',
    catalogUrl: _homepages[StudioId.bdc]!,
  ),
  // ---------------- Steps
  ClassTemplate(
    id: 'steps_basic_tap',
    studioId: StudioId.steps,
    title: 'Basic Tap',
    rawLevelLabel: 'BASIC',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.tap,
    slots: [_s(1, _t(18), 90, 'Gwen H.'), _s(6, _t(12), 90, 'Gwen H.')],
    description: 'Toe, heel, shuffle, flap and ball-change—building rhythm from scratch.',
    prerequisiteNotes: 'No prior experience required.',
    attireNotes: 'Tap shoes (loaners sometimes available—call ahead).',
    catalogUrl: _homepages[StudioId.steps]!,
  ),
  ClassTemplate(
    id: 'steps_basic_ballet',
    studioId: StudioId.steps,
    title: 'Basic Ballet',
    rawLevelLabel: 'BASIC',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.ballet,
    slots: [
      _s(2, _t(10), 90, 'Irina S.'),
      _s(4, _t(10), 90, 'Irina S.'),
      _s(7, _t(11), 90, 'Paul D.'),
    ],
    description:
        'Slow-paced barre with detailed alignment cues, followed by simple center work.',
    prerequisiteNotes: 'No prior experience required.',
    attireNotes: _balletAttire,
    catalogUrl: _homepages[StudioId.steps]!,
  ),
  ClassTemplate(
    id: 'steps_beg_contemp',
    studioId: StudioId.steps,
    title: 'Beginner Contemporary',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.contemporaryModern,
    slots: [_s(3, _t(18, 30), 90, 'Noa B.')],
    description: 'Floor work, release technique and weight shifts with a short phrase.',
    attireNotes: _barefootAttire,
    catalogUrl: _homepages[StudioId.steps]!,
  ),
  ClassTemplate(
    id: 'steps_beg_theater',
    studioId: StudioId.steps,
    title: 'Beginner Theater Jazz',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.jazzTheater,
    slots: [_s(5, _t(18), 90, 'Owen P.')],
    description: 'Classic musical-theater jazz technique and a show-tune combination.',
    attireNotes: 'Jazz shoes or sneakers.',
    catalogUrl: _homepages[StudioId.steps]!,
  ),
  ClassTemplate(
    id: 'steps_advbeg_ballet',
    studioId: StudioId.steps,
    title: 'Adv Beg Ballet',
    rawLevelLabel: 'ADV BEG',
    tier: Tier.advancedBeginner,
    primaryGenre: Genre.ballet,
    slots: [_s(1, _t(10, 30), 90, 'Irina S.'), _s(3, _t(10, 30), 90, 'Paul D.')],
    description: 'Full barre and center including petit allegro and pirouette prep.',
    prerequisiteNotes: '6+ months of regular ballet classes recommended.',
    attireNotes: _balletAttire,
    catalogUrl: _homepages[StudioId.steps]!,
  ),
  ClassTemplate(
    id: 'steps_absbeg_tap_series',
    studioId: StudioId.steps,
    title: 'Absolute Beginner Tap Series',
    rawLevelLabel: 'ABS BEG',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.tap,
    slots: const [],
    description:
        'A 4-week progressive series for first-time tappers. Each week builds on the last.',
    prerequisiteNotes: 'For students who have never tapped. Enroll before week 1.',
    attireNotes: 'Tap shoes required.',
    catalogUrl: _homepages[StudioId.steps]!,
  ),
  // ---------------- Ailey
  ClassTemplate(
    id: 'ailey_intro_horton',
    studioId: StudioId.ailey,
    title: 'Intro to Horton',
    rawLevelLabel: 'INTRO',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.contemporaryModern,
    slots: [_s(1, _t(18, 30), 90, 'Keisha W.'), _s(6, _t(11), 90, 'Keisha W.')],
    description:
        'Flat backs, lateral T, fortifications and the foundational shapes of Horton modern technique.',
    prerequisiteNotes: 'For students who have never taken a dance class.',
    attireNotes: _barefootAttire,
    catalogUrl: _homepages[StudioId.ailey]!,
  ),
  ClassTemplate(
    id: 'ailey_absbeg_ballet',
    studioId: StudioId.ailey,
    title: 'Absolute Beginner Ballet',
    rawLevelLabel: 'ABS BEG',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.ballet,
    slots: [_s(2, _t(18, 30), 90, 'Elena F.'), _s(7, _t(12), 90, 'Elena F.')],
    description: 'Barre fundamentals with plenty of repetition and individual corrections.',
    prerequisiteNotes: 'Little to no prior experience.',
    attireNotes: _balletAttire,
    catalogUrl: _homepages[StudioId.ailey]!,
  ),
  ClassTemplate(
    id: 'ailey_beg_west_african',
    studioId: StudioId.ailey,
    title: 'Beginner West African',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.africanDiaspora,
    tags: {Genre.worldCultural},
    slots: [_s(4, _t(19), 90, 'Kofi A.')],
    description: 'Traditional rhythms and movement with live drumming.',
    attireNotes: 'Loose clothing; barefoot. A lappa (wrap skirt) is welcome.',
    catalogUrl: _homepages[StudioId.ailey]!,
  ),
  ClassTemplate(
    id: 'ailey_beg_hiphop',
    studioId: StudioId.ailey,
    title: 'Beginner Hip Hop',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.hipHopStreet,
    slots: [_s(3, _t(18), 75, 'Tre L.')],
    description: 'Foundations, musicality and a beginner-friendly routine.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.ailey]!,
  ),
  ClassTemplate(
    id: 'ailey_beg_dunham',
    studioId: StudioId.ailey,
    title: 'Beginner Dunham',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.africanDiaspora,
    tags: {Genre.contemporaryModern},
    slots: [_s(6, _t(14), 90, 'Nia C.')],
    description: 'Katherine Dunham technique: progressions, isolations and polyrhythm.',
    attireNotes: _barefootAttire,
    catalogUrl: _homepages[StudioId.ailey]!,
  ),
  // ---------------- Peridance
  ClassTemplate(
    id: 'peri_beg_contemp',
    studioId: StudioId.peridance,
    title: 'Beginner Contemporary',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.contemporaryModern,
    slots: [_s(1, _t(19), 90, 'Mika O.'), _s(4, _t(12), 90, 'Lia G.')],
    description: 'Grounded movement, spirals and inversions introduced gradually.',
    attireNotes: _barefootAttire,
    catalogUrl: _homepages[StudioId.peridance]!,
  ),
  ClassTemplate(
    id: 'peri_beg_ballet',
    studioId: StudioId.peridance,
    title: 'Beginner Ballet',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.ballet,
    slots: [_s(2, _t(12), 90, 'Anna K.'), _s(5, _t(10), 90, 'Anna K.')],
    description: 'Classical barre and center for students with some exposure.',
    attireNotes: _balletAttire,
    catalogUrl: _homepages[StudioId.peridance]!,
  ),
  ClassTemplate(
    id: 'peri_beg_afro',
    studioId: StudioId.peridance,
    title: 'Beginner Afro',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.africanDiaspora,
    tags: {Genre.hipHopStreet},
    slots: [_s(7, _t(14), 75, 'Ade O.')],
    description: 'Afrobeats grooves and footwork with a high-energy routine.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.peridance]!,
  ),
  ClassTemplate(
    id: 'peri_absbeg_contemp_ws',
    studioId: StudioId.peridance,
    title: 'Absolute Beginner Contemporary Workshop',
    rawLevelLabel: 'ABS BEG',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.contemporaryModern,
    slots: const [],
    description:
        'Six-week progressive workshop for adults with no dance background. Ends with an informal showing.',
    prerequisiteNotes: 'Zero experience. Must enroll before week 1.',
    attireNotes: _barefootAttire,
    catalogUrl: _homepages[StudioId.peridance]!,
  ),
  ClassTemplate(
    id: 'peri_absbeg_ballet_ws',
    studioId: StudioId.peridance,
    title: 'Absolute Beginner Ballet Workshop',
    rawLevelLabel: 'ABS BEG',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.ballet,
    slots: const [],
    description: 'Six-week ballet series starting from first position.',
    prerequisiteNotes: 'Zero experience. Must enroll before week 1.',
    attireNotes: _balletAttire,
    catalogUrl: _homepages[StudioId.peridance]!,
  ),
  ClassTemplate(
    id: 'peri_absbeg_hiphop_ws',
    studioId: StudioId.peridance,
    title: 'Absolute Beginner Hip Hop Workshop',
    rawLevelLabel: 'ABS BEG',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.hipHopStreet,
    slots: const [],
    description: 'Five-week hip hop series: grooves, footwork and one routine learned over time.',
    prerequisiteNotes: 'Zero experience. Must enroll before week 1.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.peridance]!,
  ),
  // ---------------- PMT
  ClassTemplate(
    id: 'pmt_basic_house',
    studioId: StudioId.pmt,
    title: 'Basic House',
    rawLevelLabel: 'BASIC',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.hipHopStreet,
    slots: [_s(2, _t(19), 75, 'Rico S.'), _s(6, _t(15), 75, 'Rico S.')],
    description: 'Jacking, the basic box, shuffles and loose footwork to house music.',
    prerequisiteNotes: 'No prior experience required.',
    attireNotes: 'Sneakers with smooth soles; loose clothing.',
    catalogUrl: _homepages[StudioId.pmt]!,
  ),
  ClassTemplate(
    id: 'pmt_basic_hiphop',
    studioId: StudioId.pmt,
    title: 'Basic Hip Hop',
    rawLevelLabel: 'BASIC',
    tier: Tier.zeroExperience,
    primaryGenre: Genre.hipHopStreet,
    slots: [_s(1, _t(19, 30), 75, 'Bea N.'), _s(4, _t(19, 30), 75, 'Bea N.')],
    description: 'Hip hop foundations and grooves at a slower pace.',
    prerequisiteNotes: 'No prior experience required.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.pmt]!,
  ),
  ClassTemplate(
    id: 'pmt_beg_waacking',
    studioId: StudioId.pmt,
    title: 'Beginner Waacking',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.hipHopStreet,
    tags: {Genre.commercialHeels},
    slots: [_s(3, _t(20), 75, 'Vee J.')],
    description: 'Arm rolls, posing and musicality from the waacking tradition.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.pmt]!,
  ),
  ClassTemplate(
    id: 'pmt_beg_dancehall',
    studioId: StudioId.pmt,
    title: 'Beginner Dancehall',
    rawLevelLabel: 'BEG',
    tier: Tier.beginner,
    primaryGenre: Genre.africanDiaspora,
    tags: {Genre.hipHopStreet, Genre.worldCultural},
    slots: [_s(5, _t(20), 75, 'Shanice P.')],
    description: 'Classic and new-school Jamaican dancehall steps.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.pmt]!,
  ),
  ClassTemplate(
    id: 'pmt_advbeg_popping',
    studioId: StudioId.pmt,
    title: 'Adv Beg Popping',
    rawLevelLabel: 'ADV BEG',
    tier: Tier.advancedBeginner,
    primaryGenre: Genre.hipHopStreet,
    slots: [_s(7, _t(16), 75, 'Leo F.')],
    description: 'Hits, fresno, waves and dime stops.',
    prerequisiteNotes: 'Some hip hop experience.',
    attireNotes: _sneakerAttire,
    catalogUrl: _homepages[StudioId.pmt]!,
  ),
];

final templatesById = {for (final t in templates) t.id: t};

const _subPool = ['Alex Q.', 'Brooke Y.', 'Chris Z.', 'Devon U.'];

/// The full feed (what `schedule.json` + `templates.json` + `series.json`
/// would contain), generated relative to [today] for a 14-day window.
class MockFeed {
  MockFeed._(this.today, this.windowStart, this.sessions, this.series);

  factory MockFeed.build(ServiceDate today) {
    final week0 = today.startOfWeek;
    final sessions = <ClassSession>[];

    // Explicit overrides to guarantee every state appears in the demo.
    final overrides = <String, (bool sub, SessionStatus status)>{
      _key('ailey_intro_horton', week0.addDays(5), _t(11)): (true, SessionStatus.scheduled),
      _key('pmt_basic_house', week0.addDays(5), _t(15)): (false, SessionStatus.cancelled),
      _key('steps_basic_tap', week0.addDays(7), _t(18)): (true, SessionStatus.scheduled),
      _key('bdc_basic_hiphop', week0.addDays(11), _t(19)): (false, SessionStatus.removed),
      _key('bdc_basic_ballet', week0.addDays(9), _t(9)): (false, SessionStatus.cancelled),
    };

    for (var ti = 0; ti < templates.length; ti++) {
      final tpl = templates[ti];
      for (var si = 0; si < tpl.slots.length; si++) {
        final slot = tpl.slots[si];
        for (var d = 0; d < 14; d++) {
          final date = week0.addDays(d);
          if (date.weekday != slot.weekday) continue;
          final id = _key(tpl.id, date, slot.startMin);
          final h = (ti * 31 + d * 7 + si * 3) % 17;
          var isSub = h == 5;
          var status = h == 11 && d > 2 ? SessionStatus.cancelled : SessionStatus.scheduled;
          final o = overrides[id];
          if (o != null) (isSub, status) = o;
          sessions.add(ClassSession(
            id: id,
            templateId: tpl.id,
            studioId: tpl.studioId,
            serviceDate: date,
            startMin: slot.startMin,
            endMin: slot.startMin + slot.durationMin,
            instructor: isSub ? _subPool[(ti + d) % _subPool.length] : slot.regularInstructor,
            isSubstitute: isSub,
            status: status,
            bookingUrl: _homepages[tpl.studioId]!,
          ));
        }
      }
    }
    sessions.sort((a, b) {
      final c = a.serviceDate.compareTo(b.serviceDate);
      return c != 0 ? c : a.startMin.compareTo(b.startMin);
    });

    final series = <WorkshopSeries>[
      WorkshopSeries(
        id: 'peri_ws_ballet_fall',
        templateId: 'peri_absbeg_ballet_ws',
        studioId: StudioId.peridance,
        title: 'Absolute Beginner Ballet Workshop',
        startDate: week0.addDays(-14),
        sessionCount: 6,
        weekday: 1,
        startMin: _t(17, 30),
        durationMin: 90,
        instructor: 'Anna K.',
        enrollmentOpen: false,
        price: '\$165 / 6 wks',
        bookingUrl: _homepages[StudioId.peridance]!,
      ),
      WorkshopSeries(
        id: 'peri_ws_hiphop',
        templateId: 'peri_absbeg_hiphop_ws',
        studioId: StudioId.peridance,
        title: 'Absolute Beginner Hip Hop Workshop',
        startDate: week0.addDays(5),
        sessionCount: 5,
        weekday: 6,
        startMin: _t(16),
        durationMin: 75,
        instructor: 'Jules R.',
        enrollmentOpen: true,
        price: '\$140 / 5 wks',
        bookingUrl: _homepages[StudioId.peridance]!,
      ),
      WorkshopSeries(
        id: 'peri_ws_contemp',
        templateId: 'peri_absbeg_contemp_ws',
        studioId: StudioId.peridance,
        title: 'Absolute Beginner Contemporary Workshop',
        startDate: week0.addDays(8),
        sessionCount: 6,
        weekday: 2,
        startMin: _t(19, 30),
        durationMin: 90,
        instructor: 'Mika O.',
        enrollmentOpen: true,
        price: '\$165 / 6 wks',
        bookingUrl: _homepages[StudioId.peridance]!,
      ),
      WorkshopSeries(
        id: 'steps_ws_tap',
        templateId: 'steps_absbeg_tap_series',
        studioId: StudioId.steps,
        title: 'Absolute Beginner Tap Series',
        startDate: week0.addDays(10),
        sessionCount: 4,
        weekday: 4,
        startMin: _t(19),
        durationMin: 90,
        instructor: 'Gwen H.',
        enrollmentOpen: true,
        price: '\$120 / 4 wks',
        bookingUrl: _homepages[StudioId.steps]!,
      ),
    ];

    return MockFeed._(today, week0, sessions, series);
  }

  static String _key(String tplId, ServiceDate d, int start) => '${tplId}_${d}_$start';

  final ServiceDate today;
  final ServiceDate windowStart;
  final List<ClassSession> sessions;
  final List<WorkshopSeries> series;

  ServiceDate get windowEnd => windowStart.addDays(13);
}

/// Seed regimen so "My Week" demonstrates every change state.
final seedSavedSlots = <SavedSlot>{
  SavedSlot(templateId: 'ailey_intro_horton', weekday: 6, startMin: _t(11)), // sub this Sat
  SavedSlot(templateId: 'pmt_basic_house', weekday: 6, startMin: _t(15)), // cancelled this Sat
  SavedSlot(templateId: 'bdc_basic_hiphop', weekday: 5, startMin: _t(19)), // removed next Fri
  SavedSlot(templateId: 'steps_basic_tap', weekday: 1, startMin: _t(18)), // sub next Mon
  SavedSlot(templateId: 'bdc_basic_ballet', weekday: 3, startMin: _t(9)), // cancelled next Wed
  SavedSlot(templateId: 'steps_basic_ballet', weekday: 5, startMin: _t(10)), // stale: slot no longer exists
};

const seedSavedSeries = <String>{'peri_ws_hiphop'};

// ---------------------------------------------------------------------------
// Commute estimate (rough; production would use a routing API or a lookup table).

class Commute {
  const Commute(this.minutes, this.mode);
  final int minutes;
  final String mode; // 'walk' | 'subway' | 'same studio'
  @override
  String toString() => mode == 'same studio' ? 'same studio' : '~$minutes min $mode';
}

Commute commuteBetween(StudioId a, StudioId b) {
  if (a == b) return const Commute(0, 'same studio');
  final sa = studios[a]!, sb = studios[b]!;
  const r = 6371.0;
  final dLat = (sb.lat - sa.lat) * math.pi / 180;
  final dLng = (sb.lng - sa.lng) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(sa.lat * math.pi / 180) *
          math.cos(sb.lat * math.pi / 180) *
          math.pow(math.sin(dLng / 2), 2);
  final km = 2 * r * math.asin(math.sqrt(h));
  final walk = (km * 1.3 * 1000 / 80).round();
  if (walk <= 20) return Commute(walk, 'walk');
  return Commute((10 + km * 2.5).round(), 'subway');
}
