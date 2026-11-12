"""
Aggregator and sync builder for NYC Solo Dance Calendar.
Runs live scrapers for BDC, Steps, Ailey, Peridance, and PMT,
filters for solo entry & beginner dance classes, matches to curated templates,
and outputs versioned static JSON feed files for offline-first Flutter consumption.
"""

import os
import sys
import json
import re
import html as html_lib
import shutil
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from typing import Dict, List, Any, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from scrapers.bdc_scraper import scrape_bdc_schedule
from scrapers.steps_scraper import scrape_steps_schedule
from scrapers.ailey_scraper import scrape_ailey_schedule
from scrapers.peridance_scraper import scrape_peridance_schedule
from scrapers.pmt_scraper import scrape_pmt_schedule

NY_TZ = ZoneInfo("America/New_York")

PARTNER_KEYWORDS = [
    "salsa", "bachata", "tango", "ballroom", "swing", "hustle", "kizomba", "zouk", "partnering", "partner"
]

NON_SOLO_OR_FITNESS = [
    "cardio", "zumba", "yoga", "pilates", "gyrokinesis", "conditioning",
    "virtual", "livestream", "zoom", "online",
    "kids", "youth", "teen", "pre-teen", "toddler", "children", "junior",
    "masterclass", "audition", "revelations", "halloween", "mini ball",
    "barre à terre", "floor-barre", "floor barre", "barre", "stretch",
    "pre-pro", "professional"
]

ADV_BEG_REGEX = re.compile(
    r'\b(adv\.?\s*beg(inner)?|adv/beg|beg/adv|advanced\s+beg(inner)?)\b',
    re.I,
)
INT_ADV_REGEX = re.compile(
    r'\b(intermediate|inter|int|adv|advanced)\b',
    re.I,
)
BEG_OPEN_REGEX = re.compile(
    r'\b(basic|beg|beginner|intro|101|absolute|abs\s*beg|open)\b',
    re.I,
)
AGE_RESTRICTION_REGEX = re.compile(
    r'\b(ages?\s*\d+\s*[-–to]+\s*\d+|ages?\s*\d+\+?|\btots?\b|\bpro\b)',
    re.I,
)

def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path: str, data: Any):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def classify_session(raw_title: str, extra_ignore: Optional[Dict[str, List[str]]] = None) -> Tuple[bool, str]:
    """Determines if a class is an adult solo beginner/entry dance class."""
    t = ' '.join(raw_title.lower().split())

    partner_list = list(PARTNER_KEYWORDS)
    if extra_ignore and "partnerKeywords" in extra_ignore:
        for pk in extra_ignore["partnerKeywords"]:
            if pk.lower() not in partner_list:
                partner_list.append(pk.lower())

    # Partner check
    for p in partner_list:
        if p in t:
            return False, f"partner: {p}"

    # Fitness / Virtual / Youth check
    for f in NON_SOLO_OR_FITNESS:
        if f in t:
            return False, f"fitness/virtual/youth: {f}"

    if AGE_RESTRICTION_REGEX.search(t):
        return False, "age/pro restriction"

    # Adv Beg check
    is_adv_beg = ADV_BEG_REGEX.search(t) is not None

    # Pure Intermediate or Advanced check
    if not is_adv_beg:
        if INT_ADV_REGEX.search(t):
            return False, "intermediate/advanced"

    # Beginner, Basic, Intro, Open check
    has_beg = BEG_OPEN_REGEX.search(t) is not None
    if has_beg or is_adv_beg:
        return True, "keep"

    return False, "unclassified"

def infer_genre(title: str) -> str:
    t = title.lower()
    if "ballet" in t or "pointe" in t:
        return "ballet"
    if "tap" in t:
        return "tap"
    if "contemporary" in t or "modern" in t or "horton" in t or "graham" in t or "lyrical" in t or "dunham" in t or "limón" in t or "limon" in t or "cunningham" in t or "taylor" in t:
        return "contemporaryModern"
    if "jazz" in t or "theater" in t or "theatre" in t or "broadway" in t:
        return "jazzTheater"
    if "heels" in t or "commercial" in t:
        return "commercialHeels"
    if "african" in t or "haitian" in t or "diaspora" in t or "afro" in t:
        return "africanDiaspora"
    if "world" in t or "flamenco" in t or "belly" in t or "samba" in t or "tango" in t or "salsa" in t or "bachata" in t or "mambo" in t or "folk" in t or "capoeira" in t or "cultural" in t:
        return "worldCultural"
    if any(k in t for k in ["hip hop", "hip-hop", "hiphop", "street", "break", "popping", "locking", "waacking", "vogue", "voguing", "house", "choreo", "urban", "groove", "krump", "freestyle", "dancehall", "reggaeton", "moptop", "litefeet"]):
        return "hipHopStreet"
    return "other"

def infer_tier(title: str) -> Tuple[str, str]:
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
    return "beginner", "BEGINNER"

# Verbatim technique descriptions scraped directly from https://ailey.org/classes/techniques/
AILEY_TECHNIQUE_DESCRIPTIONS = {
    "ballet": "A form of dance dating back to Renaissance Italy, ballet technique has been adapted and finessed over centuries. Ballet technique is designed to develop symmetry, balance, flexibility, strength, the graceful carriage of the arms, intricate footwork, an elongated and centered midline, and virtuosity in pirouettes and jumps.",
    "horton": "Created by Lester Horton (Alvin Ailey's mentor) in the 1940s and is comprised of detailed exercises called Studies, which include Projections, Locomotions, Preludes, Rhythms, Improvisations, and Fortifications. The fortifications establish a framework of movement mechanics, muscular development and coordination, elasticity and range, rhythm and timing of phrasing, and movement quality.",
    "graham": "Developed by modern dance pioneer Martha Graham, Graham technique is centered around the contraction and release of the diaphragm, where the dancer's breath becomes the motor for movement. Graham technique utilizes floor work to strengthen the use of the torso in contractions and spiraling actions, before moving to standing and traveling patterns that move across the floor.",
    "contemporary": "Contemporary dance encompasses a range of different techniques and movement vocabularies being practiced today. Contemporary classes often include floor work, sequencing of the spine, a focus on breath and alignment, phrase material, improvisation, fall and recovery, and working with gravity to find release.",
    "hip hop": "Hip hop utilizes elements from popping, locking, and breaking to create a unique and popular street style. This class challenges every dancer with dynamic movement and combinations focused on rhythm and musicality, encouraging individual style while staying true to hip hop’s foundations.",
    "west african": "West African classes at Ailey Extension bring together body, mind, and spirit in an energetic union of music, dance, and the oral traditions of West African cultures. Every class is accompanied by live drumming to provide students with an understanding of the relationship between music and dance.",
    "afro-brazilian": "Afro-Brazilian dance is full of spontaneous, soulful, and dynamic movement that will energize your body and spirit. This class presents sequences and exercises to prepare the body for uplifting and exciting dances from northern Brazil.",
    "jazz": "Jazz technique utilizes the elongated lines and extensions of ballet, the core-driven power of modern dance, and the dynamic syncopation of Broadway dance and street styles. It is a technically demanding style that encourages dancers to find their individual flair within the movement.",
    "vogue": "Vogue, which originated in the Harlem balls, emulates the poses of fashion magazines but also draws from hieroglyphic imagery and martial arts. In this class, students master the five key elements to voguing—catwalk, spins and dips, floor work, hand work, and duckwalk.",
    "pilates": "Pilates is a system of repetitive exercises performed on a yoga mat or other equipment to promote strength, stability, and flexibility. Pilates exercises develop the body through muscular effort that stems from the core."
}

def get_generic_studio_description(studio_id: str, title: str, genre: str) -> str:
    """
    Returns authentic verbatim class/style descriptions scraped directly from the studio website.
    If no authentic website description exists, returns empty string so UI falls back to
    'A description has not been provided for this class.'
    Zero AI summaries or synthetic filler.
    """
    t_lower = title.lower()
    if studio_id == "ailey":
        for k, desc in AILEY_TECHNIQUE_DESCRIPTIONS.items():
            if k in t_lower:
                return desc
        genre_to_tech = {
            "ballet": "ballet",
            "contemporaryModern": "contemporary",
            "hipHopStreet": "hip hop",
            "africanDiaspora": "west african",
            "jazzTheater": "jazz",
        }
        tech_key = genre_to_tech.get(genre, genre)
        if tech_key in AILEY_TECHNIQUE_DESCRIPTIONS:
            return AILEY_TECHNIQUE_DESCRIPTIONS[tech_key]

    # No authentic studio-wide description scraped from website
    return ""

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
    alias_lookup: Dict[str, List[str]] = {}
    for cid, rec in instructors_reg.items():
        all_aliases = [re.sub(r'[\"\']', '', a).lower().strip() for a in rec.get("aliases", [])]
        can_name = re.sub(r'[\"\']', '', rec.get("canonicalName", "")).lower().strip()
        if can_name and can_name not in all_aliases:
            all_aliases.append(can_name)
        for a in all_aliases:
            alias_lookup[a] = all_aliases

    ignore_rules = templates_data.get("ignoreRules", {})
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
    ]

    all_scraped_sessions: List[Dict[str, Any]] = []
    scraper_stats = {}
    prev_tpl_lookup = {t["id"]: t for t in previous_templates}
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
            cached = [s for s in previous_sessions if s.get("studioId") == studio_id]
            if cached:
                for c in cached:
                    fallback_title = (
                        c.get("rawClassTitle")
                        or prev_tpl_lookup.get(c["templateId"], {}).get("title")
                        or c["templateId"]
                    )
                    all_scraped_sessions.append({
                        "id": c["id"],
                        "studioId": studio_id,
                        "rawClassTitle": fallback_title,
                        "serviceDate": c["serviceDate"],
                        "startMin": c["startMin"],
                        "endMin": c["endMin"],
                        "instructor": c.get("instructor", "Staff"),
                        "isSubstitute": c.get("isSubstitute", False),
                        "bookingUrl": c.get("bookingUrl", "")
                    })
                scraper_stats[studio_id] = len(cached)
                print(f"Preserved {len(cached)} cached sessions for {studio_id.upper()}")
            else:
                scraper_stats[studio_id] = 0

    normalized_sessions: List[Dict[str, Any]] = []
    review_queue: List[Dict[str, Any]] = []
    queued_tpl_ids = set()
    tpl_lookup = {t["id"]: t for t in templates}

    dates_seen = set()

    for sess in all_scraped_sessions:
        raw_title = ' '.join(html_lib.unescape(sess["rawClassTitle"]).split())
        studio_id = sess["studioId"]
        service_date = sess["serviceDate"]
        dates_seen.add(service_date)

        is_solo_beg, reason = classify_session(raw_title, ignore_rules)
        if not is_solo_beg:
            continue

        tier, raw_level_label = infer_tier(raw_title)
        genre = infer_genre(raw_title)
        clean_title = ' '.join(raw_title.split(" with ")[0].split())

        # Try to match an existing template of the same studio and tier
        matched_tpl = None
        best_pat_len = -1
        for t in templates:
            if t["studioId"] == studio_id and t.get("tier") == tier:
                for pat in t.get("matchPatterns", [t["title"]]):
                    norm_pat = ' '.join(pat.lower().split())
                    norm_clean = clean_title.lower()
                    norm_raw = raw_title.lower()
                    if norm_pat == norm_clean or norm_pat == norm_raw:
                        matched_tpl = t
                        best_pat_len = 10000
                        break
                    if re.search(rf'(?:^|\b){re.escape(norm_pat)}(?:\b|$)', norm_raw):
                        if len(norm_pat) > best_pat_len:
                            matched_tpl = t
                            best_pat_len = len(norm_pat)
            if best_pat_len == 10000:
                break

        # If not matched, generate an on-the-fly dynamic template
        if not matched_tpl:
            slug = re.sub(r'[^a-z0-9]+', '_', clean_title.lower()).strip('_')
            dynamic_tpl_id = f"{studio_id}_{genre}_{slug[:30]}"

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
        norm_inst = re.sub(r'[\"\']', '', instructor_clean).lower().strip()
        candidate_names = [norm_inst]
        if norm_inst in alias_lookup:
            for a in alias_lookup[norm_inst]:
                if a not in candidate_names:
                    candidate_names.append(a)

        studio_descs = instructor_descriptions.get(studio_id, {})
        session_desc = None

        # 1. Look for description under current studio for any known alias
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

        session_record = {
            "id": sess["id"],
            "templateId": matched_tpl["id"],
            "studioId": studio_id,
            "rawClassTitle": raw_title,
            "serviceDate": service_date,
            "startMin": sess["startMin"],
            "endMin": sess["endMin"],
            "tz": "America/New_York",
            "instructor": instructor_clean,
            "isSubstitute": sess.get("isSubstitute", False),
            "status": "scheduled",
            "bookingUrl": sess.get("bookingUrl", "")
        }
        if session_desc:
            session_record["description"] = session_desc

        normalized_sessions.append(session_record)

    # Window dates: 14-day rolling window anchored to current week's Monday in NYC
    today_dt = datetime.now(NY_TZ)
    current_monday_dt = today_dt - timedelta(days=today_dt.weekday())
    window_start = current_monday_dt.strftime("%Y-%m-%d")
    window_end = (current_monday_dt + timedelta(days=13)).strftime("%Y-%m-%d")

    # Filter sessions to the 14-day rolling window
    normalized_sessions = [
        s for s in normalized_sessions
        if window_start <= s["serviceDate"] <= window_end
    ]

    # Sort sessions chronologically
    normalized_sessions.sort(key=lambda s: (s["serviceDate"], s["startMin"]))

    feed = {
        "version": "1.0.0",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "windowStart": window_start,
        "windowEnd": window_end,
        "studios": studios,
        "templates": templates,
        "series": series,
        "sessions": normalized_sessions,
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
