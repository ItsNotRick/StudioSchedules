"""
Peridance Center live schedule scraper.
Fetches https://go.mindbodyonline.com/book/widgets/schedules/view/f936462b7be/schedule,
extracts session types, instructors, and scheduled session instances from the
Mindbody Branded Web Next.js payload.
"""

import urllib.request
from typing import List, Dict, Any

try:
    from scrapers.mindbody_widget import parse_mindbody_widget_sessions
except ImportError:
    from mindbody_widget import parse_mindbody_widget_sessions

PERIDANCE_WIDGET_URL = "https://go.mindbodyonline.com/book/widgets/schedules/view/f936462b7be/schedule"


def scrape_peridance_schedule() -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        PERIDANCE_WIDGET_URL,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8")

    return parse_mindbody_widget_sessions(
        html,
        studio_id="peridance",
        id_prefix="peri",
        booking_url="https://www.peridance.com/open-classes",
        exclude_virtual=False,
        strip_in_studio_prefix=False,
    )

if __name__ == "__main__":
    results = scrape_peridance_schedule()
    print(f"Scraped {len(results)} live classes from Peridance:")
    for s in results[:10]:
        sub_str = " [SUB]" if s.get("isSubstitute") else ""
        print(f"  [{s['serviceDate']} {s['startMin']//60:02d}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}{sub_str}")
