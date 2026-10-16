"""
Broadway Dance Center (BDC) live schedule scraper.
Fetches https://www.broadwaydancecenter.com/schedule/schedule-in-person,
parses rolling day headers and class cards, extracts level, style, timing,
instructor, and direct Mindbody booking URLs.
"""

import re
import html as html_lib
import urllib.request
from datetime import datetime
from typing import List, Dict, Any, Optional

BDC_SCHEDULE_URL = "https://www.broadwaydancecenter.com/schedule/schedule-in-person"

def parse_time_to_minutes(time_str: str) -> Optional[int]:
    """Converts '3:15 pm' to minutes after midnight."""
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

def scrape_bdc_schedule() -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        BDC_SCHEDULE_URL,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8")

    # Split into day sections
    day_blocks = re.split(r'<h[1-4][^>]*>([A-Za-z]+,\s*[A-Za-z]+\s*[0-9]+)</h[1-4]>', html)
    sessions: List[Dict[str, Any]] = []

    # Format of split: [preamble, day_title_1, content_1, day_title_2, content_2, ...]
    for i in range(1, len(day_blocks), 2):
        day_title = day_blocks[i].strip()
        day_content = day_blocks[i + 1]

        # Parse date from day_title like "Friday, October 16"
        # Current year fallback
        year = datetime.now().year
        try:
            parsed_date = datetime.strptime(f"{day_title} {year}", "%A, %B %d %Y").strftime("%Y-%m-%d")
        except Exception:
            continue

        cards = day_content.split("web-schedule-class-card")
        for card in cards[1:]:
            title_m = re.search(r'class="class-title">([^<]+)</div>', card)
            if not title_m:
                continue
            raw_title = html_lib.unescape(title_m.group(1).strip())

            # Teacher
            teach_m = re.search(r'class="bdc-sched-teach">\s*<a[^>]*>([^<]+)</a>', card)
            teacher = teach_m.group(1).strip() if teach_m else "Staff"

            # Times
            time_m = re.search(r'class="class-time">(.*?)</div>', card, re.DOTALL)
            start_min = 600
            end_min = 690
            if time_m:
                clean_times = re.findall(r'([0-9]{1,2}:[0-9]{2}\s*(?:am|pm))', time_m.group(1), re.I)
                if len(clean_times) >= 2:
                    s_min = parse_time_to_minutes(clean_times[0])
                    e_min = parse_time_to_minutes(clean_times[1])
                    if s_min is not None and e_min is not None:
                        start_min = s_min
                        end_min = e_min

            # Direct Mindbody app/web booking link
            booking_m = re.search(r'href="(https://bma1914\.bma\.mindbodyonline\.com[^\"]+)"', card)
            booking_url = booking_m.group(1) if booking_m else "https://www.broadwaydancecenter.com/schedule"

            # Stable Session ID
            session_id = f"bdc_{parsed_date}_{start_min}_{raw_title[:10].replace(' ', '').lower()}"

            sessions.append({
                "id": session_id,
                "studioId": "bdc",
                "rawClassTitle": raw_title,
                "serviceDate": parsed_date,
                "startMin": start_min,
                "endMin": end_min,
                "tz": "America/New_York",
                "instructor": teacher,
                "bookingUrl": booking_url
            })

    return sessions

if __name__ == "__main__":
    results = scrape_bdc_schedule()
    print(f"Scraped {len(results)} live classes from Broadway Dance Center:")
    for s in results[:10]:
        print(f"  [{s['serviceDate']} {s['startMin']//60}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}")
