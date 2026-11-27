# Class Descriptions Audit

**Date:** 2026-11-24 · **Feed audited:** `backend/data/schedule.json` (generated 2026-11-24T19:36Z, 1,256 sessions) · **Description cache:** `backend/data/instructor_descriptions.json` (last regenerated 2026-11-12)

## How the app picks a description

On the class detail sheet ([detail_sheet.dart:213](../app/lib/src/ui/detail_sheet.dart)) the "About this class" text is chosen in this order:

1. **`session.description`**, the teacher's blurb, set in [build_feed.py:487-526](../backend/src/build_feed.py):
   1. the teacher's entry for **this studio** in `instructor_descriptions.json`
   2. otherwise **any other studio's** entry for a teacher with the same name ([build_feed.py:503](../backend/src/build_feed.py))
2. **`template.description`**, shown with the prefix *"Studio's style description:"*. Only Ailey has these (`AILEY_TECHNIQUE_DESCRIPTIONS`, [build_feed.py:239](../backend/src/build_feed.py)).
3. Otherwise the placeholder: *"A description has not been provided for this class."*

## Coverage today

| Studio | Sessions | Teacher blurb | Studio style blurb | Placeholder | Blurb from a **different** studio |
|---|---:|---:|---:|---:|---:|
| BDC | 414 | 280 | 0 | 134 (32%) | some (e.g. Chris Jarosz → Peridance) |
| Steps | 407 | 13 | 0 | **394 (97%)** | **all 13** |
| Ailey | 163 | 14 | 119 | 30 (18%) | **all 14** |
| Peridance | 133 | 33 | 0 | 100 (75%) | some (e.g. Sue Samuels → BDC) |
| PMT | 86 | 10 | 0 | 76 (88%) | most |
| Danznik | 53 | 0 | 0 | **53 (100%)** | – |

## Method

I took 5–15 class/teacher pairs per studio from the current feed: some with a description and some with the placeholder. For each one I fetched the studio's own page (teacher faculty pages, technique pages, class/event pages) and compared it with what the app shows. BDC now serves a Cloudflare challenge to plain HTTP clients, so I checked those pages in a real browser.

---

## Findings by studio

### Broadway Dance Center: mostly right, but often stale or the wrong section

| Class (teacher) | App shows | BDC website | Verdict |
|---|---|---|---|
| Adv Beg BALLET (Yuka Kawazu) | "Class Descriptions Ballet This class emphasizes placement…" | Same text | ✅ Correct, but the "Class Descriptions Ballet" heading text is glued onto the front |
| Adv Beg SOULFUL LYRICAL JAZZ (Nijawwon Matthews) | His **Int CONTEMPORARY JAZZ** blurb | The page has an Int Contemporary Jazz section and a *Soulful Lyrical Jazz* heading with no text under it | ⚠️ Wrong class. The app shows a different class's description with no warning |
| Int JAZZ (Dylan Pearce) | His "Theater" blurb | The page has only a Theater section | ⚠️ Closest available, but labelled as a different style |
| All Levels SAMPOORNA YOGA (Renata Bonar) | Whole page dump starting with "CHAKRA YOGA…" | The page has separate **Chakra Yoga**, **Holistic Healing Yoga** and **Sampoorna Yoga** sections | ❌ Should show only the Sampoorna section. The class-matching code never fires (see root cause 3) |
| Int STREET JAZZ (Destiny Nguyen) | Placeholder | Full Street Jazz description | ❌ Missing (stale cache) |
| Int Adv HIP-HOP/STREET STYLES (Marley Lubin) | Placeholder | Full Street Styles description | ❌ Missing (stale cache) |
| Adv Beg JUMPS AND TURNS (Alexx Stachowiak) | Placeholder | Contemporary Jazz description | ❌ Missing (stale cache) |
| Adv Beg STREET JAZZ *with Neil Schwartz* (sub: David Cartahena Lee) | Placeholder | Both Neil Schwartz and David Cartahena Lee have Street Jazz descriptions | ❌ Missing. The sub has no cached blurb, and the regular teacher named in the title isn't tried |
| All Levels HEELS TECHNIQUE *with Sissa Strain* (listed as "Staff") | Placeholder | Sissa Strain has a description | ❌ Missing. "Staff" is used even though the title names the teacher |
| Beg THEATER (Marjorie Failoni) | Placeholder | No description block | ✅ Correct |

Of 15 BDC teachers who currently show the placeholder, **10 have a description on their BDC faculty page** (Jaime Torres, Ross Thompson, Orit Hirsch, Eliah James Furlong, Kelly MacMillan, David Cartahena Lee, Ana Estrada, Brady Rowan, Sissa Strain, Victoria Biro). The other 5 have none (Alexa Luke, Dre Torres, Inmi Song Thomas, Mike Camire, Thea Erichsen). 21 BDC sessions are listed as "Staff".

### Steps on Broadway: the studio has teacher descriptions, the app uses none of them

| Class (teacher) | App shows | Steps website (`stepsnyc.com/faculty/<slug>/`) | Verdict |
|---|---|---|---|
| Adv/Beg Theater Jazz (Oren Korenblum) | His **BDC TAP** blurb | His Steps page has a tap paragraph **and** a dedicated *"In Oren Korenblum's Theatre Jazz class…"* paragraph | ❌ Wrong class and wrong studio |
| Int Contemporary (Emily Bufferd) | Her BDC blurb, starting "Beg Lyrical 2-5 years training…" | Steps "Class Description" with no BDC level text | ⚠️ Wrong studio, and the level text is wrong for this class |
| Beg Tap (Danielle Jackman) | Her BDC Tap blurb | Same text on Steps | ✅ Content matches, but it came from BDC |
| Adv/Beg Street Jazz (Robert Taylor Jr.) | His **Peridance HipHop** blurb | – | ⚠️ Wrong style (hip hop text on a street jazz class) |
| Beg Ballet (Kathy Sullivan) | Her Peridance blurb | Steps slug `kathy-sullivan` returns 404 | ⚠️ Probably fine; wrong studio source |
| (Debbie Roshe) | Placeholder | "Debbie's class emphasizes dynamics and quick direction changes…" | ❌ Missing |

Root issues:
- The Steps extractor looks for `class="faculty-bio|entry-content"` ([extract_teacher_descriptions.py:210](../backend/src/extract_teacher_descriptions.py)), which no longer matches Steps' markup. The pages have a plain **"Class Description"** heading.
- The 5 "Steps" entries in the cache are keyed by the first 20 characters of the description (`"this class is for mo"`, `"cardio dance is a fu"`, …) instead of by teacher name, so they can never match a session.
- **284 of 407 Steps sessions have instructor "Staff"**, and their titles look like `"Virtual 90 Adv/Int Jazz"`. The Steps scraper is losing the teacher name, which blocks any teacher-based lookup. This is a scraper bug outside the description code, but it decides Steps coverage.

### Ailey Extension: generic text, often for the wrong technique

Ailey publishes a description page for **every technique** it teaches (about 30, listed at `ailey.org/classes/techniques/<slug>`). The app hard-codes 10 of them. Every other class falls back to a genre-level guess:

| Class | App shows | Ailey's own technique page | Verdict |
|---|---|---|---|
| Beg Horton, Beg Graham, Beg Ballet | Horton / Graham / Ballet text | Same (ballet is cut to its first two sentences) | ✅ Correct |
| Open **Afro-Cuban** Folkloric | "**West African** classes at Ailey Extension…" | Afro-Cuban page: "…movements representing the Orishas…" | ❌ Wrong technique |
| **Sabar** | West African text | Sabar page: "…national dance of Senegal… live Sabar drumming… taught barefoot" | ❌ Wrong technique |
| Open **Afro-Haitian** | West African text | Has its own page | ❌ Wrong technique |
| Open **Limón** | Generic Contemporary text | Limón page: "…fall and recovery, a conscious use of breath…" | ❌ Wrong technique |
| Abs Beg **Dunham** | Generic Contemporary text | Dunham page: "…Katherine Dunham… Dunham walk… rocking horse" | ❌ Wrong technique |
| Beg **Cuban Modern**, Open **Contemporary Indian** | Generic Contemporary text | Both have their own pages | ❌ Wrong technique |
| Beg **Dancehall**, Beg **House** | **Hip hop** text | Dancehall page: "…Jamaican and Caribbean dance cultures…" | ❌ Wrong technique |
| Beg **Broadway Dance** | Jazz text | Broadway page: "…choreography set to songs from your favorite musicals…" | ❌ Wrong technique |
| Hip Hop Cardio | Hip hop text | Has its own page | ⚠️ Near miss |
| Zumba®, Beg Heels, Masala Bhangra®, Salsa, NY Style Mambo, Stretch and Alignment | Placeholder | Each has its own page (e.g. Zumba: "dance-fitness program that combines salsa, samba, merengue…") | ❌ Missing |
| Beg Ballet (Yuka Kawazu) | Her **BDC** ballet blurb | – | ⚠️ Cross-studio |
| Beg House (Miyabi Wright) | Her **Peridance** House blurb | – | ⚠️ Cross-studio, though the content fits |
| Beg Afro'Dance (Judith McCarty) | Her **BDC** Afro dance blurb | – | ⚠️ Cross-studio, though the content fits |
| Adv Beg Ballet (Ronald K. Alexander) | Peridance **"Basic Ballet… little or no experience"** | – | ❌ Wrong level text on an Adv Beg class |

The style text is accurate where the technique matches, but the substring/genre fallback in `get_generic_studio_description` ([build_feed.py:252](../backend/src/build_feed.py)) presents a different technique's description as fact. In this feed, 25 of the 119 Ailey sessions with a style blurb (21%) get theirs from the pure genre guess. More get a substring near-miss on top of that: "Contemporary Indian" matches "contemporary", "Commercial Jazz" matches "jazz", and "Hip Hop Cardio" matches "hip hop", even though each has its own Ailey page.

### Peridance: extractor works, but the cache is stale and other studios' blurbs win

| Class (teacher) | App shows | Peridance faculty page | Verdict |
|---|---|---|---|
| Open House (Sekou Heru), Beg Popping (Sun Kim), Beg Horton (Katrina Perrin) | "CLASS DESCRIPTION: …" | Same text | ✅ Correct (the "CLASS DESCRIPTION:" label is part of the text) |
| Inter Contemporary (Evelyn Chen) | Placeholder | Full description ("…coordination, crawling patterns, brain games…") | ❌ Missing |
| Inter Ballet (Billy Blanken) | Placeholder | Full description | ❌ Missing |
| Adv Ballet (Michelle Thompson) | Placeholder | Separate *Ballet* and *Contemporary Ballet* descriptions | ❌ Missing |
| Inter Dynamic Sequencing (Adam Barruch) | Placeholder | Full description | ❌ Missing |
| Inter Broadway Jazz (Sue Samuels) | Her **BDC** blurb | Her Peridance page has its own description of the same class | ⚠️ Wrong studio, though the content is close |
| Beg House (Tony McGregor) | Placeholder | "Coming soon!" | ✅ Correct |

None of the four missing teachers is in the cache at all. The extractor only sees teachers who were in `schedule.json` on 2026-11-12, and it isn't run as part of the feed build.

### PMT House of Dance: class-level descriptions keyed to teachers

PMT publishes descriptions **per class** on `/breakin-classes`. The extractor ([extract_teacher_descriptions.py:243](../backend/src/extract_teacher_descriptions.py)) attaches them to hard-coded teacher names:

| Class (teacher) | App shows | PMT website | Verdict |
|---|---|---|---|
| Open Level Breaking Fundamentals (Heat Rock) | "Description: Come join Heat Rock…" | Same | ✅ Correct |
| Breakin'101 – For Beginners (**Bboy Theatrics**) | Placeholder | "…ideal for the COMPLETE BEGINNER. With 2-3 teachers on hand…" | ❌ Missing: the description is keyed to "pavan thimmaiah" / "lars kong", and those entries aren't even in the cache |
| Adv. Beg. Breaking (Richard Maguire) | Placeholder | "This class is the next step for those fully versed in the basics…" | ❌ Missing: never extracted |
| Open Reggaeton (David Machicado) | His **BDC** Reggaeton blurb | – | ⚠️ Cross-studio, though the content fits |
| Open Popping (Jon Lock) | His **Peridance** popping blurb | – | ⚠️ Cross-studio, though the content fits |
| Hip hop, jazz, contemporary, heels classes | Placeholder | No class descriptions found on the PMT site | ✅ Correct |

### Danznik Studios NYC: rich descriptions online, none in the app

Danznik has detailed per-level text on its class pages (`danznik.com/e/<slug>/`), and the app shows the placeholder for all 53 sessions:

| Class | Danznik website |
|---|---|
| Midtown Swings – Lindy 100 / 150 / 200 | `/e/midtown-swings/`: separate descriptions for each level, with prerequisites ("Completion of at least 1–2 months of the Lindy 100 series") |
| Swingiversity (Level 1 / 2) | `/e/swingiversity/`: Level 101 and 201 descriptions. The site says 101 is led by Kat Tan, but the feed lists Galen Chen |
| Intro Class: West Coast Swing w/ House of West | `/e/west-coast-swing-intro/`: a 30-minute class covering a listed set of patterns |
| West Coast Swing w/ Jes Ann Nail (Levels 1–3), Novice Competitor Training (L4) | `/e/next-level-west-coast-swing/`: level guide and descriptions |
| Beginner Ballroom [Community Class] | `/e/beginner-ballroom/`: "Learn the foundational technique behind… Waltz, Foxtrot and Tango…" |
| Brazilian Zouk Foundations / Beyond Foundations | `/studios/nyc/brazilian-zouk/`: style description |

There is no Danznik extractor.

---

## Root causes

> **Priority:** cause 4 (broken or missing collectors) is the one that matters. Causes 1–3, 5 and 6 are expected behaviour or minor, and are listed only for completeness. In the per-studio tables above, ⚠️ rows that only flag a cross-studio source can be read as acceptable.

### Primary: broken or missing collectors

The studios publish good descriptions that we don't collect:

| Studio | Where the descriptions are | What we collect | Gap |
|---|---|---|---|
| **Danznik** | Per-class, per-level sections on `danznik.com/e/<slug>/` (Lindy 100/150/200, Swingiversity 101/201, Intro WCS, WCS Levels 1–4, Ballroom Fundamentals) plus style pages (`/studios/nyc/brazilian-zouk/`) | Nothing: no extractor | 53/53 sessions show the placeholder |
| **Steps** | "Class Description" section on each `stepsnyc.com/faculty/<slug>/` page (1,000 faculty URLs in `faculty-sitemap.xml`) | The selector `faculty-bio\|entry-content` ([extract_teacher_descriptions.py:210](../backend/src/extract_teacher_descriptions.py)) matches nothing. The 5 cached entries are keyed by description text, not teacher, so they never match | 0 Steps-sourced descriptions |
| **Ailey** | One page per technique at `ailey.org/classes/techniques/<slug>`, about 30 in all. The text is in `SliceBody_body` | 10 techniques hand-copied into `AILEY_TECHNIQUE_DESCRIPTIONS` ([build_feed.py:239](../backend/src/build_feed.py)); `"ailey": {}` in the extractor | About 20 techniques missing; those classes get the wrong technique's text or nothing |
| **PMT** | Per-class "Description" blocks on `/breakin-classes` (Breakin' 101, Breaking Fundamentals, Adv. Beginner Breaking, Essential Sessions) | Two blocks, keyed to hard-coded teacher names ([extract_teacher_descriptions.py:243](../backend/src/extract_teacher_descriptions.py)) | Breakin' 101 and Adv. Beg. Breaking show nothing |

Three of the four (Danznik, Ailey, PMT) describe the **class**, not the teacher, so their collectors should key by class title (or technique) and attach to templates, not to `instructor_descriptions.json`. Steps works like BDC and Peridance: per-teacher pages.

### Secondary (expected behaviour or minor)

1. **Cross-studio fallback ([build_feed.py:503](../backend/src/build_feed.py)).** If a teacher has no blurb at the current studio, the app shows their blurb from any other studio. That blurb describes *another studio's class*: often another style (Oren Korenblum TAP → Theater Jazz) or another level (Ronald Alexander "Basic Ballet" → Adv Beg Ballet). Nothing in the app says where the text came from. This accounts for all Ailey and Steps teacher blurbs.
2. **Stale, manually run extractor.** `extract_teacher_descriptions.py` isn't part of the feed build. Its BDC/Peridance teacher lists come from the schedule as it was on 2026-11-12, so newer teachers are missing. BDC is also now behind Cloudflare, so a plain `urllib` re-run would silently return nothing.
3. **Per-class matching is dead code.** [build_feed.py:496](../backend/src/build_feed.py) looks for class-specific sub-keys, but the extractor only ever writes `default`/`raw`/`source`, so there are 0 sub-keys in the cache. Teachers with several classes (Renata Bonar, Nijawwon Matthews, April Cook, Michelle Thompson, Oren Korenblum) always get the whole page, or the first section.
4. *(Primary cause; see above.)*
5. **Lookup only by the listed instructor.** "Staff" rows and substitutes get no description, even when the class title names the regular teacher ("…with Sissa Strain", "…with Neil Schwartz").
6. **Formatting noise.** Text starts with scraped headings: "Class Descriptions Ballet …", "CLASS DESCRIPTION: …", "Description: …". On the Ailey style blurbs, the "Studio's style description:" prefix makes it clearer that the text isn't class-specific, which is good.

## Recommendations

### Do these: build or fix the collectors

1. ✅ **Done (2026-11-27), by a better route than planned:** Danznik's Mindbody schedule widget, which `danznik_scraper.py` already downloads, carries the studio's own description of each session under "View details". The scraper now passes it through as `classDescription`, and `build_feed.py` uses it ahead of any teacher blurb. On the live schedule, 53 of 55 sessions get one; the Midtown Swings Social has none. No page mapping is needed, and the text is refreshed on every feed build. Pricing and "DanzPass Eligible" lines are dropped because they go stale. Original plan: **Danznik: new class-description collector.** Read each `/e/<slug>/` page's "Class Description(s)" sections, split by level heading ("Lindy 100", "Level 101", "Level 1: Ballroom Fundamentals"…), and match them to feed titles such as "Midtown Swings - Lindy 100" and "Swingiversity (Level 1)". Use the style page (e.g. Brazilian Zouk) when no class section matches.
2. ✅ **Done (2026-11-25):** `extract_ailey_techniques.py` writes `backend/data/ailey_techniques.json` (30/30 techniques), and `build_feed.py` matches the longest technique name. 59 of 62 current Ailey titles now match; the three that don't are the toddler classes, which have no technique page. Original plan: **Ailey: collect every technique page.** Walk the links on `/classes/techniques/`, take the first `SliceBody_body` paragraph(s) up to the level guide, and key them by technique. Match the longest technique name in the class title (so "Contemporary Indian" beats "Contemporary"), then replace the hard-coded `AILEY_TECHNIQUE_DESCRIPTIONS`.
3. ✅ **Done (2026-11-27):** the extractor now reads both faculty sitemaps (1,255 pages; the old code only read the first 1,000) and takes the text after the "Class Description" label. That gives 157 teachers, and the five text-keyed entries are gone. On today's live schedule, 87 of 240 Steps sessions get the teacher's own Steps text (before: 0), and 18 still borrow another studio's. Spot checks show the remaining misses mostly have no class description on their Steps page. Four schedule names differ from the page names and need alias entries via `manage_aliases.py`: Kat Ponza → Katharine Ponza, Goddertz → Charles Goddertz, Hebach → Susan Hebach, Jermaine Spivey → Jermaine Maurice Spivey. The extractor also takes studio names now (`extract_teacher_descriptions.py steps`), and keeps a studio's existing entries when its crawl returns nothing, so BDC's Cloudflare block can't wipe them. Original plan: **Steps: fix the faculty extractor.** Take the text after the "Class Description" heading on each sitemap URL and key it by teacher name/slug, like BDC. Delete the five text-keyed entries.
4. **PMT: collect class descriptions by title.** Read every "Description" block on `/breakin-classes` and key it by the class name it sits under, not by teacher.

### Optional, lower priority

- Split multi-class faculty pages into per-class sub-keys so the existing matching at [build_feed.py:496](../backend/src/build_feed.py) has something to match.
- Re-run the BDC/Peridance extractor to pick up teachers added since 2026-11-12. BDC needs a fetch method that gets past Cloudflare.
- Strip scraped heading prefixes ("Class Descriptions <Style>", "CLASS DESCRIPTION:", "Description:").
