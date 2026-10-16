"""
Aggregator and sync builder for NYC Solo Dance Calendar.
Runs live scrapers for BDC, Steps, Ailey, Peridance, and PMT,
filters for solo entry & beginner dance classes, matches to curated templates,
and outputs versioned static JSON feed files for offline-first Flutter consumption.
"""

import os
import sys
import json
import shutil
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Any, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from scrapers.bdc_scraper import scrape_bdc_schedule
from scrapers.steps_scraper import scrape_steps_schedule
from scrapers.ailey_scraper import scrape_ailey_schedule
from scrapers.peridance_scraper import scrape_peridance_schedule
from scrapers.pmt_scraper import scrape_pmt_schedule

PARTNER_KEYWORDS = [
    "salsa", "bachata", "tango", "ballroom", "swing", "hustle", "kizomba", "zouk", "partnering", "partner"
]

NON_SOLO_OR_FITNESS = [
    "cardio", "zumba", "yoga", "pilates", "gyrokinesis", "conditioning",
    "virtual", "livestream", "zoom", "online", "kids", "youth", "teen", "toddler",
    "masterclass", "audition", "revelations", "halloween", "mini ball", "barre à terre"
]

def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path: str, data: Any):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def classify_session(raw_title: str) -> Tuple[bool, str]:
    """Determines if a class is an adult solo beginner/entry dance class."""
    t = raw_title.lower().strip()

    # Partner check
    for p in PARTNER_KEYWORDS:
        if p in t:
            return False, f"partner: {p}"

    # Fitness / Virtual / Youth check
    for f in NON_SOLO_OR_FITNESS:
        if f in t:
            return False, f"fitness/virtual: {f}"

    # Adv Beg check
    is_adv_beg = any(k in t for k in ["adv beg", "adv/beg", "adv. beg.", "advanced beginner", "adv. beginner", "adv beg "])

    # Pure Intermediate or Advanced check
    if not is_adv_beg:
        if any(k in t for k in ["intermediate", "inter ", "int ", "int/", "/int", "adv/int", "int/adv", "advanced", " adv "]):
            return False, "intermediate/advanced"

    # Beginner, Basic, Intro check
    has_beg = any(k in t for k in ["basic", "beg", "intro", "101", "absolute", "open"])
    if has_beg or is_adv_beg:
        return True, "keep"

    return False, "unclassified"

def infer_genre(title: str) -> str:
    t = title.lower()
    if "ballet" in t:
        return "ballet"
    if "tap" in t:
        return "tap"
    if "contemporary" in t or "modern" in t or "horton" in t or "graham" in t or "lyrical" in t or "dunham" in t:
        return "contemporaryModern"
    if "jazz" in t or "theater" in t or "broadway" in t:
        return "jazzTheater"
    if "heels" in t or "commercial" in t:
        return "commercialHeels"
    if "african" in t or "haitian" in t or "diaspora" in t or "afro" in t:
        return "africanDiaspora"
    return "hipHopStreet"

def infer_tier(title: str) -> Tuple[str, str]:
    t = title.lower()
    if any(k in t for k in ["adv beg", "adv/beg", "adv. beg.", "advanced beginner"]):
        return "advancedBeginner", "ADV/BEG"
    if any(k in t for k in ["absolute", "abs beg", "intro", "101", "basic"]):
        label = "BASIC"
        if "abs" in t or "absolute" in t:
            label = "ABS BEG"
        elif "intro" in t:
            label = "INTRO"
        return "zeroExperience", label
    return "beginner", "BEGINNER"

def generate_live_feed() -> Dict[str, Any]:
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    templates_path = os.path.join(base_dir, "data", "templates.json")
    studios_path = os.path.join(base_dir, "data", "studios.json")

    templates_data = load_json(templates_path)
    studios_data = load_json(studios_path)

    templates = list(templates_data["templates"])
    series = templates_data.get("series", [])
    studios = studios_data["studios"]

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

    for studio_id, fn in scrapers:
        try:
            sessions = fn()
            all_scraped_sessions.extend(sessions)
            scraper_stats[studio_id] = len(sessions)
            print(f"Scraped {len(sessions)} raw sessions from {studio_id.upper()}")
        except Exception as e:
            print(f"Error scraping {studio_id.upper()}: {e}")
            scraper_stats[studio_id] = 0

    normalized_sessions: List[Dict[str, Any]] = []
    review_queue: List[Dict[str, Any]] = []
    tpl_lookup = {t["id"]: t for t in templates}

    dates_seen = set()

    for sess in all_scraped_sessions:
        raw_title = sess["rawClassTitle"]
        studio_id = sess["studioId"]
        service_date = sess["serviceDate"]
        dates_seen.add(service_date)

        is_solo_beg, reason = classify_session(raw_title)
        if not is_solo_beg:
            continue

        # Try to match an existing curated template
        matched_tpl = None
        for t in templates:
            if t["studioId"] == studio_id:
                for pat in t.get("matchPatterns", [t["title"]]):
                    if pat.lower() in raw_title.lower():
                        matched_tpl = t
                        break
            if matched_tpl:
                break

        # If not matched, generate an on-the-fly dynamic template
        if not matched_tpl:
            tier, raw_level_label = infer_tier(raw_title)
            genre = infer_genre(raw_title)
            clean_title = raw_title.split(" with ")[0].strip()
            dynamic_tpl_id = f"{studio_id}_{genre}_{clean_title[:10].lower().replace(' ', '_').replace('-', '_')}"

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
                    "description": f"{clean_title} at {studio_id.upper()}.",
                    "prerequisiteNotes": "Welcoming drop-in class. Check studio guidelines before class.",
                    "attireNotes": "Comfortable clothes you can move in; appropriate dance shoes.",
                    "catalogUrl": sess.get("bookingUrl", "")
                }
                templates.append(new_tpl)
                tpl_lookup[dynamic_tpl_id] = new_tpl

            matched_tpl = tpl_lookup[dynamic_tpl_id]

            # Log to review queue for curators
            review_queue.append({
                "studioId": studio_id,
                "rawClassTitle": raw_title,
                "assignedTemplateId": dynamic_tpl_id,
                "assignedTier": tier,
                "assignedGenre": genre,
                "detectedAt": datetime.now(timezone.utc).isoformat()
            })

        normalized_sessions.append({
            "id": sess["id"],
            "templateId": matched_tpl["id"],
            "studioId": studio_id,
            "serviceDate": service_date,
            "startMin": sess["startMin"],
            "endMin": sess["endMin"],
            "tz": "America/New_York",
            "instructor": sess.get("instructor", "Staff"),
            "isSubstitute": sess.get("isSubstitute", False),
            "status": "scheduled",
            "bookingUrl": sess.get("bookingUrl", "")
        })

    # Window dates: 14-day rolling window anchored to current week's Monday
    today_dt = datetime.now()
    current_monday_dt = today_dt - timedelta(days=today_dt.weekday())
    window_start = current_monday_dt.strftime("%Y-%m-%d")
    window_end = (current_monday_dt + timedelta(days=13)).strftime("%Y-%m-%d")

    # Filter out sessions that occurred before the current week
    normalized_sessions = [s for s in normalized_sessions if s["serviceDate"] >= window_start]

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
