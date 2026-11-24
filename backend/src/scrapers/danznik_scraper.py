"""
Danznik Studios NYC live schedule scraper.
Fetches the Mindbody (Healcode v1) schedule widget embedded on
https://www.danznik.com/studios/nyc/schedule/ for two consecutive 7-day
pages (14-day rolling window). The widget only lists the "Danznik NYC"
location (240 W 37th St); the Westchester studio is not included.
"""

import re
import json
import time
import html as html_lib
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from typing import List, Dict, Any, Optional

DANZNIK_WIDGET_ID = "e2178160965d"
DANZNIK_MARKUP_URL = f"https://widgets.mindbodyonline.com/widgets/schedules/{DANZNIK_WIDGET_ID}/load_markup"
DANZNIK_SCHEDULE_URL = "https://www.danznik.com/studios/nyc/schedule/"
NY_TZ = ZoneInfo("America/New_York")

def _text(fragment: str) -> str:
    """Strips tags, unescapes entities and collapses whitespace."""
    return ' '.join(html_lib.unescape(re.sub(r'<[^>]+>', ' ', fragment)).split())

def _field(block: str, css_class: str) -> Optional[str]:
    m = re.search(rf'<div class="{css_class}"[^>]*>(.*?)</div>', block, re.S)
    return m.group(1) if m else None

def _parse_sessions(markup: str, seen: set) -> List[Dict[str, Any]]:
    sessions: List[Dict[str, Any]] = []
    blocks = re.split(r'(?=<div class="bw-session[ "])', markup)
    for block in blocks[1:]:
        root_m = re.match(r'<div class="(bw-session[^"]*)"[^>]*\bid="(\d+)"', block)
        if not root_m:
            continue
        root_classes, mbo_id = root_m.group(1), root_m.group(2)
        is_cancelled = "cancel" in root_classes.lower()

        start_m = re.search(r'class="hc_starttime" datetime="([^"]+)"', block)
        end_m = re.search(r'class="hc_endtime" datetime="([^"]+)"', block)
        name_html = _field(block, "bw-session__name")
        if not start_m or not name_html:
            continue

        # The name div is prefixed with a hidden "<visit type> - " span.
        name = _text(re.sub(r'<span class="bw-session__type"[^>]*>.*?</span>', '', name_html, flags=re.S))
        if not name:
            continue

        try:
            start_dt = datetime.strptime(start_m.group(1), "%Y-%m-%dT%H:%M")
            end_dt = datetime.strptime(end_m.group(1), "%Y-%m-%dT%H:%M") if end_m else start_dt + timedelta(minutes=60)
        except ValueError as e:
            print(f"Warning: skipping Danznik session '{name}' with malformed time: {e}")
            continue

        service_date = start_dt.strftime("%Y-%m-%d")
        start_min = start_dt.hour * 60 + start_dt.minute
        duration = int((end_dt - start_dt).total_seconds() // 60)
        if duration <= 0:
            duration = 60

        staff = _text(_field(block, "bw-session__staff") or "") or "Staff"
        is_sub = re.search(r'\(\s*sub(stitute)?\s*\)', staff, re.I) is not None
        instructor = re.sub(r'\s*\(\s*sub(stitute)?\s*\)', '', staff, flags=re.I).strip() or "Staff"
        # Danznik suffixes some teacher names with the location ("Tatiana Keegan NYC").
        instructor = re.sub(r'\s+NYC$', '', instructor)

        level = _text(_field(block, "bw-session__level") or "")
        # Studio's own class category ("West Coast Swing", "Mixed Ballroom"),
        # printed as a hidden "<category> - " prefix on the name.
        category_m = re.search(r'<span class="bw-session__type"[^>]*>(.*?)</span>', name_html, re.S)
        category = _text(category_m.group(1)).rstrip(" -") if category_m else ""

        session_id = f"danznik_{service_date}_{start_min}_{mbo_id}"
        if session_id in seen:
            continue
        seen.add(session_id)

        session = {
            "id": session_id,
            "studioId": "danznik",
            "rawClassTitle": name,
            "serviceDate": service_date,
            "startMin": start_min,
            "endMin": start_min + duration,
            "tz": "America/New_York",
            "instructor": instructor,
            "isSubstitute": is_sub,
            "status": "cancelled" if is_cancelled else "scheduled",
            "bookingUrl": DANZNIK_SCHEDULE_URL,
        }
        if level:
            session["rawLevel"] = level
        if category:
            session["rawCategory"] = category
        sessions.append(session)
    return sessions

def _fetch_week(start_date: str) -> str:
    query = urllib.parse.urlencode({"options[start_date]": start_date})
    req = urllib.request.Request(
        f"{DANZNIK_MARKUP_URL}?{query}",
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Referer": DANZNIK_SCHEDULE_URL,
        },
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            return payload.get("class_sessions", "")
        except Exception as e:
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
            else:
                raise e
    return ""

def scrape_danznik_schedule() -> List[Dict[str, Any]]:
    today = datetime.now(NY_TZ).date()
    all_sessions: List[Dict[str, Any]] = []
    seen: set = set()
    for offset in (0, 7):
        start_date = (today + timedelta(days=offset)).strftime("%Y-%m-%d")
        all_sessions.extend(_parse_sessions(_fetch_week(start_date), seen))
    all_sessions.sort(key=lambda s: (s["serviceDate"], s["startMin"]))
    return all_sessions

if __name__ == "__main__":
    results = scrape_danznik_schedule()
    print(f"Scraped {len(results)} live classes from Danznik Studios NYC:")
    for s in results:
        sub_str = " [SUB]" if s.get("isSubstitute") else ""
        print(f"  [{s['serviceDate']} {s['startMin']//60:02d}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}{sub_str} ({s['endMin']-s['startMin']}m) <{s.get('rawLevel', '')} / {s.get('rawCategory', '')}>")
