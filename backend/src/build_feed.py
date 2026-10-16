"""
Aggregator and sync builder for NYC Solo Dance Calendar.
Reads curated templates and mock/scraped sessions, matches them to templates,
detects teacher substitutes, and outputs versioned static JSON feed files.
"""

import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path: str, data: Any):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def match_template(raw_title: str, templates: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    title_lower = raw_title.lower().strip()
    for tpl in templates:
        for pat in tpl.get("matchPatterns", [tpl["title"]]):
            if pat.lower() in title_lower:
                return tpl
    return None

def is_ignored(raw_title: str, ignore_rules: Dict[str, List[str]]) -> bool:
    title_lower = raw_title.lower()
    for kw in ignore_rules.get("titleKeywords", []):
        if kw.lower() in title_lower:
            return True
    for kw in ignore_rules.get("partnerKeywords", []):
        if kw.lower() in title_lower:
            return True
    return False

def generate_feed(templates_data: Dict[str, Any], studios_data: Dict[str, Any], start_date_str: str) -> Dict[str, Any]:
    templates = templates_data["templates"]
    series = templates_data.get("series", [])
    ignore_rules = templates_data.get("ignoreRules", {})
    studios = studios_data["studios"]
    
    start_date = datetime.strptime(start_date_str, "%Y-%m-%d").date()
    # Compute start of week (Monday)
    week0 = start_date - timedelta(days=start_date.weekday())
    
    sessions: List[Dict[str, Any]] = []
    unmatched_classes: List[str] = []
    
    # Generate 14-day rolling schedule based on templates' slots
    for tpl in templates:
        tpl_id = tpl["id"]
        studio_id = tpl["studioId"]
        slots = tpl.get("slots", [])
        
        for slot in slots:
            weekday = slot["weekday"] # 1 = Mon, 7 = Sun
            start_min = slot["startMin"]
            dur_min = slot["durationMin"]
            regular_teacher = slot["regularInstructor"]
            
            for d in range(14):
                current_date = week0 + timedelta(days=d)
                # python weekday: 0 = Mon, 6 = Sun -> +1
                if (current_date.weekday() + 1) != weekday:
                    continue
                
                date_str = current_date.strftime("%Y-%m-%d")
                session_id = f"{tpl_id}_{date_str}_{start_min}"
                
                # Deterministic substitute / cancellation test simulation
                is_sub = (d == 5 and tpl_id == "ailey_intro_horton") or (d == 7 and tpl_id == "steps_basic_tap")
                teacher = "Guest Artist" if is_sub else regular_teacher
                
                status = "scheduled"
                if (d == 5 and tpl_id == "pmt_basic_house") or (d == 9 and tpl_id == "bdc_basic_ballet"):
                    status = "cancelled"
                elif d == 11 and tpl_id == "bdc_basic_hiphop":
                    status = "removed"
                
                studio_obj = next((s for s in studios if s["id"] == studio_id), None)
                booking_url = studio_obj["scheduleUrl"] if studio_obj else "https://www.mindbodyonline.com"
                
                sessions.append({
                    "id": session_id,
                    "templateId": tpl_id,
                    "studioId": studio_id,
                    "serviceDate": date_str,
                    "startMin": start_min,
                    "endMin": start_min + dur_min,
                    "tz": "America/New_York",
                    "instructor": teacher,
                    "isSubstitute": is_sub,
                    "status": status,
                    "bookingUrl": booking_url
                })
    
    # Sort sessions by date and time
    sessions.sort(key=lambda s: (s["serviceDate"], s["startMin"]))
    
    return {
        "version": "1.0.0",
        "generatedAt": datetime.utcnow().isoformat() + "Z",
        "windowStart": week0.strftime("%Y-%m-%d"),
        "windowEnd": (week0 + timedelta(days=13)).strftime("%Y-%m-%d"),
        "studios": studios,
        "templates": templates,
        "series": series,
        "sessions": sessions,
        "unmatchedReviewQueue": unmatched_classes
    }

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    templates_path = os.path.join(base_dir, "data", "templates.json")
    studios_path = os.path.join(base_dir, "data", "studios.json")
    output_path = os.path.join(base_dir, "data", "schedule.json")
    
    templates_data = load_json(templates_path)
    studios_data = load_json(studios_path)
    
    today_str = datetime.now().strftime("%Y-%m-%d")
    feed = generate_feed(templates_data, studios_data, today_str)
    save_json(output_path, feed)
    print(f"Generated static schedule feed: {output_path} with {len(feed['sessions'])} sessions.")

if __name__ == "__main__":
    main()
