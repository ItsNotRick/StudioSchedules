"""
Peridance Center live schedule scraper.
Fetches https://go.mindbodyonline.com/book/widgets/schedules/view/f936462b7be/schedule,
extracts session types, instructors, and scheduled session instances from the
Mindbody Branded Web Next.js payload.
"""

import re
import urllib.request
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any

PERIDANCE_WIDGET_URL = "https://go.mindbodyonline.com/book/widgets/schedules/view/f936462b7be/schedule"

def scrape_peridance_schedule() -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        PERIDANCE_WIDGET_URL,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8")

    quote_str = chr(92) + chr(34)
    q = re.escape(quote_str)

    # In Mindbody Branded Web, classes are serialized in JSON blocks:
    # {"id":"cinst_...","name":"...","startDateTime":"...","duration":90,"endDateTime":"...","staff":[{"displayLabel":"..."}],"cancelled":false}
    sess_re = re.compile(
        rf'{q}id{q}:{q}(cinst_[^{q}]+){q},'
        rf'{q}name{q}:{q}([^{q}]+){q}.*?'
        rf'{q}startDateTime{q}:{q}([^{q}]+){q},'
        rf'{q}duration{q}:([0-9]+),.*?'
        rf'{q}displayLabel{q}:{q}([^{q}]+){q}'
    )

    # Check for cancellation
    cancel_pat = re.compile(rf'{q}id{q}:{q}(cinst_[^{q}]+){q}.*?{q}cancelled{q}:true')
    cancelled_ids = set(cancel_pat.findall(html))

    sessions: List[Dict[str, Any]] = []
    seen_ids = set()

    for m in sess_re.finditer(html):
        cid, name, sdt, dur_str, instructor = m.groups()
        if cid in seen_ids:
            continue
        seen_ids.add(cid)

        if cid in cancelled_ids:
            continue

        dur = int(dur_str)

        # Parse UTC timestamp
        try:
            clean_sdt = sdt.split(".")[0].replace("Z", "")
            dt_utc = datetime.strptime(clean_sdt, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
            # America/New_York is UTC-4 during EDT
            edt = timezone(timedelta(hours=-4))
            dt_local = dt_utc.astimezone(edt)
            service_date = dt_local.strftime("%Y-%m-%d")
            start_min = dt_local.hour * 60 + dt_local.minute
        except Exception:
            service_date = sdt[:10]
            start_min = 600

        is_sub = "sub" in instructor.lower()

        clean_instructor = instructor.replace(r"\"", '"').strip()
        # Clean up any trailing studio affiliation text, e.g. "Peniel Guerrier | DJONIBA DANCE CENTRE"
        clean_name = name.replace(r"\"", '"').strip()

        session_id = f"peri_{service_date}_{start_min}_{cid[-8:]}"

        sessions.append({
            "id": session_id,
            "studioId": "peridance",
            "rawClassTitle": clean_name,
            "serviceDate": service_date,
            "startMin": start_min,
            "endMin": start_min + dur,
            "tz": "America/New_York",
            "instructor": clean_instructor,
            "isSubstitute": is_sub,
            "bookingUrl": "https://www.peridance.com/open-classes"
        })

    return sessions

if __name__ == "__main__":
    results = scrape_peridance_schedule()
    print(f"Scraped {len(results)} live classes from Peridance:")
    for s in results[:10]:
        sub_str = " [SUB]" if s.get("isSubstitute") else ""
        print(f"  [{s['serviceDate']} {s['startMin']//60:02d}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}{sub_str}")
