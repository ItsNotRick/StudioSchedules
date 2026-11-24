"""
Steps on Broadway live schedule scraper.
Fetches https://go.mindbodyonline.com/book/widgets/schedules/view/00705830e76/schedule,
extracts session names, instructors, times, and duration from the Next.js payload.
"""

import urllib.request
from typing import List, Dict, Any

try:
    from scrapers.mindbody_widget import parse_mindbody_widget_sessions
except ImportError:
    from mindbody_widget import parse_mindbody_widget_sessions

STEPS_WIDGET_URL = "https://go.mindbodyonline.com/book/widgets/schedules/view/00705830e76/schedule"


def scrape_steps_schedule() -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        STEPS_WIDGET_URL,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8")

    return parse_mindbody_widget_sessions(
        html,
        studio_id="steps",
        id_prefix="steps",
        booking_url="https://www.stepsnyc.com/classes/schedule/",
        exclude_virtual=True,
        strip_in_studio_prefix=True,
    )

if __name__ == "__main__":
    results = scrape_steps_schedule()
    print(f"Scraped {len(results)} live classes from Steps on Broadway:")
    for s in results[:10]:
        print(f"  [{s['serviceDate']} {s['startMin']//60:02d}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']} ({s['endMin']-s['startMin']}m)")
