"""
Aggregator and sync builder for NYC Solo Dance Calendar.
Runs live scrapers for BDC, Steps, Ailey, Peridance, PMT, and Danznik,
keeps every scheduled class (all levels, styles, and non-dance classes),
assigns each a level tier and genre, matches to curated templates,
and outputs versioned static JSON feed files for offline-first Flutter consumption.
"""

import os
import sys
import json
import re
import html as html_lib
import shutil
import hashlib
import unicodedata
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from typing import Dict, List, Any, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from scrapers.bdc_scraper import scrape_bdc_schedule
from scrapers.steps_scraper import scrape_steps_schedule
from scrapers.ailey_scraper import scrape_ailey_schedule
from scrapers.peridance_scraper import scrape_peridance_schedule
from scrapers.pmt_scraper import scrape_pmt_schedule
from scrapers.danznik_scraper import scrape_danznik_schedule
from instructor_names import (
    PLACEHOLDER_INSTRUCTORS,
    alias_registry_problems,
    build_canonical_lookup,
    normalize_instructor,
)

NY_TZ = ZoneInfo("America/New_York")

# Studio notices that appear in a schedule feed but are not classes.
NOT_A_CLASS_REGEX = re.compile(r'\b(is\s+closed|closed\s+today|studio\s+closed)\b', re.I)

ADV_BEG_REGEX = re.compile(
    r'\b(adv\.?\s*beg(inner)?|adv/beg|beg/adv|advanced\s+beg(inner)?)\b',
    re.I,
)
INT_REGEX = re.compile(r'\b(intermediate|inter|int)\b', re.I)
ADV_REGEX = re.compile(r'\b(adv|advanced|pro|professional|pre-pro)\b', re.I)
BEG_REGEX = re.compile(r'\b(beg|beginners?)\b', re.I)
ALL_LEVELS_REGEX = re.compile(r'\b(all[\s-]+levels?|open\s+levels?|open)\b', re.I)
AGE_REGEX = re.compile(r'\bages?\s*\d+(\s*[-–]\s*\d+|\+)?', re.I)

def match_template(
    templates: List[Dict[str, Any]],
    auto_tpl_ids: set,
    studio_id: str,
    tier: str,
    raw_title: str,
    clean_title: str,
) -> Optional[Dict[str, Any]]:
    """Pick the template a scraped class belongs to, or None.

    Hand-curated templates (templates.json) match on any of their
    matchPatterns, exactly or as a whole-word phrase inside the raw title, and
    the longest pattern wins. That lets a curator deliberately fold variants
    ("Abs Beg Ballet", "Intro to Ballet") into one template.

    Auto-created templates (ids in auto_tpl_ids) only match their exact
    title. Otherwise the first title seen ("Open Contemporary") would swallow
    every longer, different class containing it ("Open Contemporary Indian").
    """
    norm_clean = clean_title.lower()
    norm_raw = raw_title.lower()
    matched_tpl = None
    best_pat_len = -1
    for t in templates:
        if t["studioId"] != studio_id or t.get("tier") != tier:
            continue
        is_auto = t["id"] in auto_tpl_ids
        for pat in t.get("matchPatterns", [t["title"]]):
            norm_pat = ' '.join(pat.lower().split())
            if norm_pat == norm_clean or norm_pat == norm_raw:
                return t
            if is_auto:
                continue
            if re.search(rf'(?:^|\b){re.escape(norm_pat)}(?:\b|$)', norm_raw):
                if len(norm_pat) > best_pat_len:
                    matched_tpl = t
                    best_pat_len = len(norm_pat)
    return matched_tpl

def auto_template_id(studio_id: str, genre: str, tier: str, clean_title: str,
                     tpl_lookup: Dict[str, Dict[str, Any]]) -> str:
    """Stable id for an auto-created template.

    The slug is cut at 30 chars to keep existing ids (and saved slots) stable;
    if that collides with a template for a different title or tier, a short
    hash of the full title + tier is appended so the two classes stay separate.
    """
    slug = re.sub(r'[^a-z0-9]+', '_', clean_title.lower()).strip('_')
    tpl_id = f"{studio_id}_{genre}_{slug[:30]}"

    def _collides(existing: Optional[Dict[str, Any]]) -> bool:
        return existing is not None and (
            existing["title"].lower() != clean_title.lower()
            or existing.get("tier") != tier
        )

    if not _collides(tpl_lookup.get(tpl_id)):
        return tpl_id

    digest = hashlib.sha1(f"{clean_title.lower()}|{tier}".encode()).hexdigest()[:6]
    base_hashed = f"{tpl_id}_{digest}"
    candidate = base_hashed
    counter = 2
    while _collides(tpl_lookup.get(candidate)):
        candidate = f"{base_hashed}_{counter}"
        counter += 1
    return candidate

def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path: str, data: Any):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def is_not_a_class(raw_title: str) -> bool:
    """True for schedule entries that are studio notices ("BDC IS CLOSED TODAY")."""
    return NOT_A_CLASS_REGEX.search(raw_title) is not None

# Genre rules, checked in order; the first match wins. Genre ids must match
# the Genre enum in app/lib/src/domain/models.dart.
GENRE_RULES: List[Tuple[str, re.Pattern]] = [
    # Anything with "ballroom" in the title is Ballroom, whatever else it says.
    ("ballroom", re.compile(r'\bballroom\b')),
    # Non-dance classes: fitness, wellness, conditioning, voice, acting, acro.
    ("misc", re.compile(
        r'\b(yoga|pilates|gyrokinesis|gyrotonic|zumba|cardio|aerobics|fitness|workout|'
        r'conditioning|strength|flexibility|stretch|lastics|alignment|meditation|healing|'
        r'floor[\s-]*barre|barre\s+[àa]\s+terre|tumbling|acro|acrobatics|voice|singing|acting)\b')),
    ("ballet", re.compile(r'ballet|pointe')),
    # A barre class that isn't ballet is a barre workout.
    ("misc", re.compile(r'\bbarre\b')),
    ("tap", re.compile(r'\btap\b')),
    ("contemporaryModern", re.compile(
        r'contemp|modern|horton|graham|lyrical|dunham|lim[oó]n|cunningham|taylor|countertechnique')),
    ("jazzTheater", re.compile(r'jazz|theater|theatre|broadway|jack cole|cole floor')),
    ("commercialHeels", re.compile(r'heels|commercial|burlesque')),
    ("africanDiaspora", re.compile(r'african|haitian|diaspora|afro|sabar')),
    ("social", re.compile(
        r'swing|lindy|west coast|\bwcs\b|hustle|salsa|mambo|zouk|bachata|kizomba|balboa|charleston')),
    # Every other partner dance.
    ("ballroom", re.compile(
        r'\blatin\b|american rhythm|\bsmooth\b|tango|waltz|foxtrot|quickstep|cha[\s-]?cha|rumba|'
        r'paso doble|\bjive\b|bolero|date night|couples|partner')),
    ("worldCultural", re.compile(r'world|flamenco|belly|samba|folk|capoeira|cultural|bhangra|bollywood')),
    ("hipHopStreet", re.compile(
        r'hip hop|hip-hop|hiphop|street|break|popping|locking|waacking|vogue|voguing|house|choreo|'
        r'urban|groove|krump|freestyle|dancehall|reggaeton|moptop|litefeet|tutting')),
]

def _genre_from_text(text: str) -> str:
    t = ' '.join(text.lower().split())
    for genre, rx in GENRE_RULES:
        if rx.search(t):
            return genre
    return "other"

def infer_genre(title: str, category: Optional[str] = None) -> str:
    """Genre for a class title.

    Only the part before " with " / " w/ " is read, so an instructor's name
    ("... with Taylor Smith") can't decide the genre. [category] is the
    studio's own class category when its scraper provides one (Danznik's
    "West Coast Swing", "Mixed Ballroom"); it is used when the title alone
    matches no genre.
    """
    class_part = re.split(r'\s+(?:with|w/)\s+', title, maxsplit=1, flags=re.I)[0]
    genre = _genre_from_text(class_part)
    if genre == "other" and category:
        genre = _genre_from_text(category)
    return genre

# Studio-provided level field (Ailey's and Danznik's feeds), checked in order.
STUDIO_LEVEL_TIERS: List[Tuple[re.Pattern, str]] = [
    (re.compile(r'\badv\w*\.?\s*/?\s*beg', re.I), "advancedBeginner"),
    (re.compile(r'\b(abs\w*|basic|intro\w*)\b', re.I), "zeroExperience"),
    (re.compile(r'\b(all[\s-]*levels?|open)\b', re.I), "allLevels"),
    (re.compile(r'\bint', re.I), "intermediate"),
    (re.compile(r'\badv', re.I), "advanced"),
    (re.compile(r'\bbeg', re.I), "beginner"),
]

def infer_tier(title: str, studio_level: Optional[str] = None) -> Tuple[str, str]:
    """(tier, raw level label) for a class.

    Tier ids must match the Tier enum in app/lib/src/domain/models.dart. A
    level the studio states in its own field wins over the title; the
    title's shorter label ("ABS BEG") is kept when both agree.
    """
    title_tier, title_label = _tier_from_title(title)
    if studio_level:
        for rx, tier in STUDIO_LEVEL_TIERS:
            if rx.search(studio_level):
                if tier == title_tier and title_label:
                    return title_tier, title_label
                return tier, ' '.join(studio_level.upper().split())
    return title_tier, title_label or "ALL LEVELS"

def _tier_from_title(title: str) -> Tuple[str, Optional[str]]:
    """(tier, label) read from the title; label is None when the title
    states no level at all (tier then defaults to allLevels)."""
    t = ' '.join(title.lower().split())
    if ADV_BEG_REGEX.search(t):
        return "advancedBeginner", "ADV/BEG"
    if any(k in t for k in ["absolute", "abs beg", "abs. beg", "intro", "101", "basic"]):
        label = "BASIC"
        if "abs" in t or "absolute" in t:
            label = "ABS BEG"
        elif "intro" in t:
            label = "INTRO"
        return "zeroExperience", label
    if INT_REGEX.search(t):
        return "intermediate", "INT/ADV" if ADV_REGEX.search(t) else "INTERMEDIATE"
    if ADV_REGEX.search(t):
        return "advanced", "ADVANCED"
    if BEG_REGEX.search(t):
        return "beginner", "BEGINNER"
    age = AGE_REGEX.search(t)
    if age:
        # Kids/teen classes: show the age range as the level label.
        return "allLevels", ' '.join(age.group(0).upper().split())
    all_levels = ALL_LEVELS_REGEX.search(t)
    if all_levels:
        return "allLevels", "OPEN" if all_levels.group(0).startswith("open") else "ALL LEVELS"
    return "allLevels", None

AILEY_TECHNIQUES_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "ailey_techniques.json")

# Words a technique name may carry that class titles usually drop
# ("Afro-Brazilian Dance" is scheduled as "Beg Afro-Brazilian").
_TECHNIQUE_NAME_SUFFIXES = (" dance technique", " technique", " dance", " for adults")


def _normalize_for_match(text: str) -> str:
    """Lowercases, strips accents and ®, unifies apostrophes, and treats hyphens as
    spaces ("Limón" -> "limon", "Hip-Hop" -> "hip hop")."""
    text = unicodedata.normalize("NFKD", text.replace("®", ""))
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.replace("\u2019", "'").replace("\u2018", "'").replace("-", " ").lower()
    return " ".join(text.split())


def _technique_match_keys(name: str) -> List[str]:
    keys = [_normalize_for_match(name)]
    for suffix in _TECHNIQUE_NAME_SUFFIXES:
        if keys[-1].endswith(suffix) and len(keys[-1]) > len(suffix):
            keys.append(keys[-1][: -len(suffix)].strip())
    return keys


_ailey_technique_index: Optional[List[Tuple[str, str]]] = None


def load_ailey_techniques(path: str = AILEY_TECHNIQUES_PATH) -> List[Tuple[str, str]]:
    """Returns [(match key, description)] from ailey_techniques.json, longest key first.

    The file is written by extract_ailey_techniques.py from each page under
    https://www.ailey.org/classes/techniques/.
    """
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        techniques = json.load(f).get("techniques", [])
    index = []
    for tech in techniques:
        description = (tech.get("description") or "").strip()
        if not description:
            continue
        for key in _technique_match_keys(tech.get("name", "")):
            if key:
                index.append((key, description))
    index.sort(key=lambda kd: len(kd[0]), reverse=True)
    return index


def match_ailey_technique(title: str, index: List[Tuple[str, str]]) -> str:
    """Returns the description of the longest technique name found in [title], or "".

    Longest wins, so "Open Contemporary Indian" gets Contemporary Indian Dance,
    not Contemporary, and "Hip Hop Cardio" gets Hip Hop Cardio, not Hip Hop.
    """
    t = _normalize_for_match(title)
    for key, description in index:
        if re.search(r"(?<![a-z])" + re.escape(key) + r"(?![a-z])", t):
            return description
    return ""


def get_generic_studio_description(studio_id: str, title: str, genre: str) -> str:
    """
    Returns the studio's own verbatim description of the class's style, or "" so the
    UI falls back to 'A description has not been provided for this class.'
    Only Ailey describes classes by style; see load_ailey_techniques().
    """
    global _ailey_technique_index
    if studio_id == "ailey":
        if _ailey_technique_index is None:
            _ailey_technique_index = load_ailey_techniques()
        return match_ailey_technique(title, _ailey_technique_index)
    return ""

# A studio class description shorter than this is treated as a level/logistics
# note ("All levels welcome. Pace may vary...") and yields to a teacher blurb.
MIN_CLASS_DESCRIPTION_CHARS = 120

# Template fields used only while building the feed, never by the app.
INTERNAL_TEMPLATE_FIELDS = {"matchPatterns"}

def public_template(t: Dict[str, Any]) -> Dict[str, Any]:
    """Returns a copy of template [t] without build-only fields."""
    return {k: v for k, v in t.items() if k not in INTERNAL_TEMPLATE_FIELDS}

def generate_live_feed() -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    templates_path = os.path.join(base_dir, "data", "templates.json")
    studios_path = os.path.join(base_dir, "data", "studios.json")
    descriptions_path = os.path.join(base_dir, "data", "instructor_descriptions.json")
    instructors_reg_path = os.path.join(base_dir, "data", "instructors.json")

    templates_data = load_json(templates_path)
    studios_data = load_json(studios_path)
    instructor_descriptions = load_json(descriptions_path) if os.path.exists(descriptions_path) else {}
    instructors_reg = load_json(instructors_reg_path) if os.path.exists(instructors_reg_path) else {}

    # Build alias lookup mapping any normalized name to all its known aliases
    # (used to find teacher descriptions under any spelling).
    alias_lookup: Dict[str, List[str]] = {}
    for cid, rec in instructors_reg.items():
        all_aliases = [normalize_instructor(a) for a in rec.get("aliases", [])]
        can_name = normalize_instructor(rec.get("canonicalName", ""))
        if can_name and can_name not in all_aliases:
            all_aliases.append(can_name)
        for a in all_aliases:
            alias_lookup[a] = all_aliases

    # Maps any normalized alias to the normalized canonical name. Emitted as
    # each session's "instructorKey" so the app can match a saved slot even
    # when a scraper prints a different spelling ("Kathy" vs "Kathryn"), and
    # published whole as "instructorAliases" so the app can resolve names it
    # stored earlier (teacher notes) against the current registry.
    canonical_lookup = build_canonical_lookup(instructors_reg)
    for problem in alias_registry_problems(instructors_reg):
        print(f"WARNING: instructors.json: {problem}")

    templates = list(templates_data["templates"])
    series = templates_data.get("series", [])
    studios = studios_data["studios"]

    schedule_path = os.path.join(base_dir, "data", "schedule.json")
    previous_sessions = []
    previous_templates = []
    if os.path.exists(schedule_path):
        try:
            prev_feed = load_json(schedule_path)
            previous_sessions = prev_feed.get("sessions", [])
            previous_templates = prev_feed.get("templates", [])
        except Exception:
            pass

    # Studio scraper registry
    scrapers = [
        ("bdc", scrape_bdc_schedule),
        ("steps", scrape_steps_schedule),
        ("ailey", scrape_ailey_schedule),
        ("peridance", scrape_peridance_schedule),
        ("pmt", scrape_pmt_schedule),
        ("danznik", scrape_danznik_schedule),
    ]

    # Window dates: 14-day rolling window anchored to current week's Monday in NYC
    today_dt = datetime.now(NY_TZ)
    current_monday_dt = today_dt - timedelta(days=today_dt.weekday())
    window_start = current_monday_dt.strftime("%Y-%m-%d")
    window_end = (current_monday_dt + timedelta(days=13)).strftime("%Y-%m-%d")

    all_scraped_sessions: List[Dict[str, Any]] = []
    scraper_stats = {}
    curated_ids = {t["id"] for t in templates}
    prev_tpl_lookup = {t["id"]: t for t in previous_templates}
    prev_auto_ids = {
        (t["studioId"], t["title"].lower(), t.get("tier")): t["id"]
        for t in previous_templates
        if t["id"] not in curated_ids
    }
    for t in templates:
        prev_tpl_lookup[t["id"]] = t

    for studio_id, fn in scrapers:
        try:
            sessions = fn()
            if not sessions:
                raise ValueError("No sessions returned from live scraper")
            all_scraped_sessions.extend(sessions)
            scraper_stats[studio_id] = len(sessions)
            print(f"Scraped {len(sessions)} raw sessions from {studio_id.upper()}")
        except Exception as e:
            print(f"Error scraping {studio_id.upper()}: {e}")
            cached = [
                s for s in previous_sessions
                if s.get("studioId") == studio_id
                and window_start <= s.get("serviceDate", "") <= window_end
            ]
            if cached:
                for c in cached:
                    fallback_title = (
                        c.get("rawClassTitle")
                        or prev_tpl_lookup.get(c["templateId"], {}).get("title")
                        or c["templateId"]
                    )
                    fallback_sess = {
                        "id": c["id"],
                        "studioId": studio_id,
                        "rawClassTitle": fallback_title,
                        "serviceDate": c["serviceDate"],
                        "startMin": c["startMin"],
                        "endMin": c["endMin"],
                        "instructor": c.get("instructor", "Staff"),
                        "isSubstitute": c.get("isSubstitute", False),
                        "status": c.get("status", "scheduled"),
                        "bookingUrl": c.get("bookingUrl", ""),
                        "rawLevel": c.get("rawLevel"),
                        "rawCategory": c.get("rawCategory"),
                    }
                    if c.get("regularInstructor"):
                        fallback_sess["regularInstructor"] = c["regularInstructor"]
                    # Keep the description the cached session already showed, so a
                    # studio's own class text survives a failed scrape.
                    if c.get("description"):
                        fallback_sess["classDescription"] = c["description"]
                    all_scraped_sessions.append(fallback_sess)
                scraper_stats[studio_id] = len(cached)
                print(f"Preserved {len(cached)} cached sessions for {studio_id.upper()}")
            else:
                scraper_stats[studio_id] = 0

    normalized_sessions: List[Dict[str, Any]] = []
    review_queue: List[Dict[str, Any]] = []
    queued_tpl_ids = set()
    tpl_lookup = {t["id"]: t for t in templates}
    # Templates created below during this run (not hand-curated); they only
    # match their exact title. See match_template().
    auto_tpl_ids: set = set()

    dates_seen = set()

    for sess in all_scraped_sessions:
        raw_title = ' '.join(html_lib.unescape(sess["rawClassTitle"]).split())
        studio_id = sess["studioId"]
        service_date = sess["serviceDate"]
        dates_seen.add(service_date)

        if is_not_a_class(raw_title):
            continue

        studio_level = sess.get("rawLevel")
        studio_category = sess.get("rawCategory")
        tier, raw_level_label = infer_tier(raw_title, studio_level)
        genre = infer_genre(raw_title, studio_category)
        clean_title = ' '.join(raw_title.split(" with ")[0].split())

        matched_tpl = match_template(
            templates, auto_tpl_ids, studio_id, tier, raw_title, clean_title)

        # If not matched, generate an on-the-fly dynamic template
        if not matched_tpl:
            # Reuse the id this class had in the previous feed so saved slots
            # survive a genre change; otherwise derive a fresh one.
            dynamic_tpl_id = prev_auto_ids.get((studio_id, clean_title.lower(), tier))
            reused = tpl_lookup.get(dynamic_tpl_id) if dynamic_tpl_id else None
            if not dynamic_tpl_id or (
                reused
                and (reused["title"].lower() != clean_title.lower() or reused.get("tier") != tier)
            ):
                dynamic_tpl_id = auto_template_id(
                    studio_id, genre, tier, clean_title, {**prev_tpl_lookup, **tpl_lookup})

            if dynamic_tpl_id not in tpl_lookup:
                new_tpl = {
                    "id": dynamic_tpl_id,
                    "studioId": studio_id,
                    "title": clean_title,
                    "matchPatterns": [clean_title],
                    "rawLevelLabel": raw_level_label,
                    "tier": tier,
                    "primaryGenre": genre,
                    "tags": [],
                    "slots": [],
                    "description": get_generic_studio_description(studio_id, clean_title, genre),
                    "prerequisiteNotes": "Welcoming drop-in class. Check studio guidelines before class.",
                    "attireNotes": "Comfortable clothes you can move in; appropriate dance shoes.",
                    "catalogUrl": sess.get("bookingUrl", "")
                }
                templates.append(new_tpl)
                tpl_lookup[dynamic_tpl_id] = new_tpl
                auto_tpl_ids.add(dynamic_tpl_id)

            matched_tpl = tpl_lookup[dynamic_tpl_id]

            # Log to review queue for curators (deduplicated per dynamic template)
            if dynamic_tpl_id not in queued_tpl_ids:
                queued_tpl_ids.add(dynamic_tpl_id)
                review_queue.append({
                    "studioId": studio_id,
                    "rawClassTitle": raw_title,
                    "assignedTemplateId": dynamic_tpl_id,
                    "assignedTier": tier,
                    "assignedGenre": genre,
                    "detectedAt": datetime.now(timezone.utc).isoformat()
                })

        instructor_clean = ' '.join(html_lib.unescape(sess.get("instructor", "Staff")).split())
        norm_inst = normalize_instructor(instructor_clean)
        candidate_names = [norm_inst]
        if norm_inst in alias_lookup:
            for a in alias_lookup[norm_inst]:
                if a not in candidate_names:
                    candidate_names.append(a)

        studio_descs = instructor_descriptions.get(studio_id, {})
        # 0. The studio's own description of this exact class, when its schedule
        #    provides one (Danznik, PMT), beats any teacher blurb. A one-line note
        #    ("No experience needed.") only fills in when no teacher blurb exists.
        studio_class_desc = (sess.get("classDescription") or "").strip()
        session_desc = (
            studio_class_desc if len(studio_class_desc) >= MIN_CLASS_DESCRIPTION_CHARS else None
        )

        # 1. Look for description under current studio for any known alias
        if not session_desc:
            for name_key in candidate_names:
                if name_key in studio_descs:
                    inst_blurbs = studio_descs[name_key]
                    matched_blurb = None
                    for key, blurb in inst_blurbs.items():
                        if key not in ("default", "raw", "source") and (key in raw_title.lower() or key in matched_tpl["title"].lower()):
                            matched_blurb = blurb
                            break
                    session_desc = matched_blurb or inst_blurbs.get("default")
                    if session_desc:
                        break

        # 2. Look across other studios if instructor teaches across studios and has a philosophy/blurb
        if not session_desc:
            for other_studio, other_descs in instructor_descriptions.items():
                if other_studio == studio_id:
                    continue
                for name_key in candidate_names:
                    if name_key in other_descs:
                        inst_blurbs = other_descs[name_key]
                        session_desc = inst_blurbs.get("default")
                        if session_desc:
                            break
                if session_desc:
                    break

        if not session_desc and studio_class_desc:
            session_desc = studio_class_desc

        # rawClassTitle (plus rawLevel / rawCategory when the studio provides
        # them) stays in the output: if a scraper fails on the next run,
        # cached sessions are re-classified from it (see fallback above).
        session_record = {
            "id": sess["id"],
            "templateId": matched_tpl["id"],
            "studioId": studio_id,
            "rawClassTitle": raw_title,
            "serviceDate": service_date,
            "startMin": sess["startMin"],
            "endMin": sess["endMin"],
            "instructor": instructor_clean,
            "instructorKey": canonical_lookup.get(norm_inst, norm_inst),
            "isSubstitute": sess.get("isSubstitute", False),
            "status": sess.get("status", "scheduled"),
            "bookingUrl": sess.get("bookingUrl", "")
        }
        if sess.get("regularInstructor"):
            session_record["regularInstructor"] = ' '.join(
                html_lib.unescape(sess["regularInstructor"]).split()
            )
        if studio_level:
            session_record["rawLevel"] = studio_level
        if studio_category:
            session_record["rawCategory"] = studio_category
        if session_desc:
            session_record["description"] = session_desc

        normalized_sessions.append(session_record)

    # Filter sessions to the 14-day rolling window
    normalized_sessions = [
        s for s in normalized_sessions
        if window_start <= s["serviceDate"] <= window_end
    ]

    # Sort sessions chronologically
    normalized_sessions.sort(key=lambda s: (s["serviceDate"], s["startMin"]))

    feed = {
        "version": "1.1.0",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "windowStart": window_start,
        "studios": studios,
        "templates": [public_template(t) for t in templates],
        "series": series,
        "sessions": normalized_sessions,
        "instructorAliases": canonical_lookup,
        "placeholderInstructors": list(PLACEHOLDER_INSTRUCTORS),
        "scraperStats": scraper_stats
    }

    return feed, review_queue

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_path = os.path.join(base_dir, "data", "schedule.json")
    review_queue_path = os.path.join(base_dir, "data", "review_queue.json")
    app_asset_path = os.path.join(os.path.dirname(base_dir), "app", "assets", "feed", "schedule.json")

    print("Building NYC Solo Dance Calendar live feed...")
    feed, review_queue = generate_live_feed()

    if not feed["sessions"]:
        print("Error: generated feed contains 0 sessions; aborting overwrite.", file=sys.stderr)
        sys.exit(1)

    save_json(output_path, feed)
    save_json(review_queue_path, review_queue)

    # Sync to Flutter app bundled assets
    if os.path.exists(os.path.dirname(app_asset_path)):
        shutil.copyfile(output_path, app_asset_path)
        print(f"Synced feed to Flutter asset: {app_asset_path}")

    print(f"Generated static schedule feed with {len(feed['sessions'])} live sessions across {len(feed['templates'])} templates.")
    print(f"Review queue contains {len(review_queue)} newly classified items.")

if __name__ == "__main__":
    main()
