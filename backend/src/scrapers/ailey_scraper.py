"""
Ailey Extension live schedule scraper.
Fetches https://ailey.org/classes, parses EventCard components across the
Next.js server-rendered schedule, extracts class title, technique, time, level,
instructor, substitute status, and direct Mindbody booking URLs.
"""

import re
import urllib.request
from datetime import datetime
from typing import List, Dict, Any, Optional

AILEY_CLASSES_URL = "https://ailey.org/classes"

def parse_time_to_minutes(time_str: str) -> Optional[int]:
    m = re.match(r'([0-9]{1,2}):([0-9]{2})\s*(am|pm)', time_str.strip().lower())
    if not m:
        return None
    h = int(m.group(1))
    mins = int(m.group(2))
    ampm = m.group(3)
    if ampm == 'pm' and h != 12:
        h += 12
    elif ampm == 'am' and h == 12:
        h = 0
    return h * 60 + mins

def scrape_ailey_schedule() -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        AILEY_CLASSES_URL,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8")

    cards = html.split("EventCard_container__")
    sessions: List[Dict[str, Any]] = []

    year = datetime.now().year

    for card in cards[1:]:
        # Title
        title_m = re.search(r'<a[^>]*class="[^"]*EventCard_title[^"]*"[^>]*>([^<]+)</a>', card)
        if not title_m:
            continue
        raw_title = title_m.group(1).strip()

        # Date & Booking URL
        date_url_m = re.search(r'href="(https://clients\.mindbodyonline\.com/ws\.asp\?[^\"]+)"', card)
        booking_url = date_url_m.group(1).replace("&amp;", "&") if date_url_m else "https://ailey.org/classes"

        # Date parsing from sDate param in booking_url (e.g. sDate=10/16/2026)
        sdate_m = re.search(r'sDate=([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})', booking_url)
        if sdate_m:
            m_num = int(sdate_m.group(1))
            d_num = int(sdate_m.group(2))
            y_num = int(sdate_m.group(3))
            service_date = f"{y_num}-{m_num:02d}-{d_num:02d}"
        else:
            # Fallback to dateSpan text like "Oct 16"
            date_span_m = re.search(r'class="EventCard_dateSpan[^\"]*">([^<]+)</span>', card)
            if date_span_m:
                try:
                    dt = datetime.strptime(f"{date_span_m.group(1).strip()} {year}", "%b %d %Y")
                    service_date = dt.strftime("%Y-%m-%d")
                except Exception:
                    service_date = datetime.now().strftime("%Y-%m-%d")
            else:
                service_date = datetime.now().strftime("%Y-%m-%d")

        # Time
        time_m = re.search(r'class="InfoEyebrow_content[^\"]*">([0-9]{1,2}:[0-9]{2}\s*(?:AM|PM))</p>', card, re.I)
        time_str = time_m.group(1).strip() if time_m else "12:00PM"
        start_min = parse_time_to_minutes(time_str) or 720
        end_min = start_min + 90  # Ailey classes standard duration: 75-90 min

        # Instructor and substitute check
        inst_m = re.search(r'class="EventCard_instructor[^\"]*">(.*?)</p>', card)
        is_sub = False
        teacher = "Staff"
        if inst_m:
            raw_inst = inst_m.group(1)
            is_sub = "(sub)" in raw_inst.lower()
            clean_inst = re.sub(r'<[^>]+>|<!--.*?-->|\(sub\)', '', raw_inst).strip()
            clean_inst = clean_inst.replace("&#x27;", "'").replace("&amp;", "&")
            teacher = clean_inst if clean_inst else "Staff"

        # Level tag
        level_m = re.search(r'EventCard_level[^\"]*\"[^>]*>([^<]+)</div>', card)
        level_label = level_m.group(1).strip() if level_m else ""

        clean_title = raw_title.replace("&#x27;", "'").replace("&amp;", "&")
        full_title = f"{clean_title} ({level_label})" if level_label and level_label != "Open" else clean_title

        # Stable Session ID
        session_id = f"ailey_{service_date}_{start_min}_{raw_title[:8].replace(' ', '').lower()}"

        sessions.append({
            "id": session_id,
            "studioId": "ailey",
            "rawClassTitle": full_title,
            "rawLevel": level_label,
            "serviceDate": service_date,
            "startMin": start_min,
            "endMin": end_min,
            "tz": "America/New_York",
            "instructor": teacher,
            "isSubstitute": is_sub,
            "bookingUrl": booking_url
        })

    return sessions

if __name__ == "__main__":
    results = scrape_ailey_schedule()
    print(f"Scraped {len(results)} live classes from Ailey Extension:")
    for s in results[:10]:
        sub_str = " [SUB]" if s["isSubstitute"] else ""
        print(f"  [{s['serviceDate']} {s['startMin']//60}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}{sub_str}")
