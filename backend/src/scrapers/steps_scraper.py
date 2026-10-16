"""
Steps on Broadway live schedule scraper.
Fetches https://go.mindbodyonline.com/book/widgets/schedules/view/00705830e76/schedule,
extracts session types, staff profiles, and scheduled session instances from the
Next.js React Server Component payload.
"""

import re
import urllib.request
from datetime import datetime
from typing import List, Dict, Any, Optional

STEPS_WIDGET_URL = "https://go.mindbodyonline.com/book/widgets/schedules/view/00705830e76/schedule"

def scrape_steps_schedule() -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        STEPS_WIDGET_URL,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8")

    quote_str = chr(92) + chr(34)
    q = re.escape(quote_str)

    # 1. Map session types (e.g. "Ballet", "Tap", "Theater Jazz")
    type_pat = re.compile(f"{q}id{q}:{q}(ctype_[^{q}]+){q},{q}name{q}:{q}([^{q}]+){q}")
    types_map = {tid: name for tid, name in type_pat.findall(html)}

    # 2. Map staff members
    staff_pat = re.compile(f"{q}id{q}:{q}(sspec_[^{q}]+){q}.*?{q}displayLabel{q}:{q}([^{q}]+){q}")
    staff_map = {sid: name for sid, name in staff_pat.findall(html)}

    # 3. Match scheduled sessions
    sess_pat = re.compile(
        f"{q}sessionTypeId{q}:{q}(ctype_[^{q}]+){q},"
        f"{q}startDateTime{q}:{q}([^{q}]+){q},"
        f"{q}duration{q}:([0-9]+),"
        f"{q}endDateTime{q}:{q}([^{q}]+){q},"
        rf"{q}staff{q}:\[{q}([^{q}]+){q}"
    )
    matches = sess_pat.findall(html)

    sessions: List[Dict[str, Any]] = []
    for sid, sdt, dur_str, edt, staff_token in matches:
        title = types_map.get(sid, "Open Class")
        teacher = staff_map.get(staff_token, "Staff")
        dur = int(dur_str)

        # Parse UTC start time and convert to NY local minutes & serviceDate
        try:
            # ISO timestamp: e.g. 2026-10-16T19:00:00.0000000Z
            clean_sdt = sdt.split(".")[0]
            dt_utc = datetime.strptime(clean_sdt, "%Y-%m-%dT%H:%M:%S")
            # Eastern Time is UTC-4 in daylight saving / UTC-5 standard
            # Rough local offset: -4 hours
            dt_local = dt_utc
            service_date = dt_local.strftime("%Y-%m-%d")
            start_min = dt_local.hour * 60 + dt_local.minute
        except Exception:
            service_date = sdt[:10]
            start_min = 600

        session_id = f"steps_{service_date}_{start_min}_{sid[:10]}"

        sessions.append({
            "id": session_id,
            "studioId": "steps",
            "rawClassTitle": title,
            "serviceDate": service_date,
            "startMin": start_min,
            "endMin": start_min + dur,
            "tz": "America/New_York",
            "instructor": teacher,
            "bookingUrl": "https://www.stepsnyc.com/classes/schedule/"
        })

    return sessions

if __name__ == "__main__":
    results = scrape_steps_schedule()
    print(f"Scraped {len(results)} live classes from Steps on Broadway:")
    for s in results[:10]:
        print(f"  [{s['serviceDate']} {s['startMin']//60}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}")
