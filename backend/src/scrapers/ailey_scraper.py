"""
Ailey Extension live schedule scraper.
Fetches https://ailey.org/calendar?view=month&classType=studio,
parses the Next.js stream payload for all live classes, and extracts
class title, level, start/end time, instructor, substitute status,
and direct Mindbody booking URLs.
Supports rolling multi-month coverage for full 14-day windows.
"""

import re
import urllib.request
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

AILEY_CALENDAR_URL = "https://ailey.org/calendar?view=month&classType=studio"

def _fetch_month_classes(url: str) -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Referer": "https://ailey.org/"
        }
    )
    html = ""
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                html = resp.read().decode("utf-8")
            if html:
                break
        except Exception as e:
            if attempt == 2:
                raise e
            import time
            time.sleep(2)

    sep = chr(92) + '\"title' + chr(92) + '\":' + chr(92) + '\"'
    sessions: List[Dict[str, Any]] = []

    for p in html.split("self.__next_f.push([1,"):
        if "instructor" in p and len(p) > 200000:
            blocks = p.split(sep)
            for i in range(1, len(blocks)):
                b = blocks[i]
                title_end = b.find(chr(92) + '\"')
                if title_end == -1:
                    continue
                title = b[:title_end].strip()

                clean_b = b.replace(chr(92), "")
                start_m = re.search(r'\"start\":\s*\"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\"', clean_b)
                if not start_m:
                    continue
                start_iso = start_m.group(1)

                end_m = re.search(r'\"end\":\s*\"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\"', clean_b)
                end_iso = end_m.group(1) if end_m else ""

                if '"canceled":true' in clean_b:
                    continue

                inst_m = re.search(r'\"instructor\":\s*\"([^\"]+)\"', clean_b)
                instructor = inst_m.group(1).strip() if inst_m else "Staff"

                lvl_m = re.search(r'\"level\":\s*\"([^\"]*)\"', clean_b)
                level = lvl_m.group(1).strip() if lvl_m else ""

                is_sub = '"isSubstitute\":true' in clean_b

                # Mindbody URL is located in the cta href in the preceding block tail
                prev_tail = blocks[i-1][-500:]
                url_m = re.search(r'https://clients\.mindbodyonline\.com[^\"]+', prev_tail.replace(r'\u0026', '&').replace(chr(92), ""))
                booking_url = url_m.group(0) if url_m else "https://ailey.org/classes"

                try:
                    s_dt = datetime.fromisoformat(start_iso)
                    e_dt = datetime.fromisoformat(end_iso) if end_iso else s_dt
                except Exception:
                    continue

                service_date = s_dt.strftime("%Y-%m-%d")
                start_min = s_dt.hour * 60 + s_dt.minute
                end_min = e_dt.hour * 60 + e_dt.minute
                if end_min <= start_min:
                    end_min = start_min + 90

                clean_title = title.replace("&#x27;", "'").replace("&amp;", "&").strip()
                full_title = f"{clean_title} ({level.title()})" if level and level.lower() != "open" else clean_title

                session_id = f"ailey_{service_date}_{start_min}_{clean_title[:8].replace(' ', '').lower()}"

                sessions.append({
                    "id": session_id,
                    "studioId": "ailey",
                    "rawClassTitle": full_title,
                    "rawLevel": level,
                    "serviceDate": service_date,
                    "startMin": start_min,
                    "endMin": end_min,
                    "tz": "America/New_York",
                    "instructor": instructor,
                    "isSubstitute": is_sub,
                    "bookingUrl": booking_url
                })
            break

    return sessions

def scrape_ailey_schedule() -> List[Dict[str, Any]]:
    all_sessions: List[Dict[str, Any]] = []
    seen = set()

    # 1. Scrape current month
    try:
        current_month = _fetch_month_classes(AILEY_CALENDAR_URL)
        for s in current_month:
            if s["id"] not in seen:
                seen.add(s["id"])
                all_sessions.append(s)
    except Exception as e:
        print(f"Error fetching current month from Ailey: {e}")

    # 2. Check if we need next month (e.g. today is past the 20th of the month)
    today = datetime.now()
    if today.day >= 18:
        # Compute first day of next month
        if today.month == 12:
            next_month_start = f"{today.year + 1}-01-01"
        else:
            next_month_start = f"{today.year}-{today.month + 1:02d}-01"
        next_url = f"{AILEY_CALENDAR_URL}&start={next_month_start}"
        try:
            next_month = _fetch_month_classes(next_url)
            for s in next_month:
                if s["id"] not in seen:
                    seen.add(s["id"])
                    all_sessions.append(s)
        except Exception as e:
            print(f"Error fetching next month from Ailey: {e}")

    all_sessions.sort(key=lambda s: (s["serviceDate"], s["startMin"]))
    return all_sessions

if __name__ == "__main__":
    results = scrape_ailey_schedule()
    print(f"Scraped {len(results)} live classes from Alvin Ailey Extension:")
    for s in results[:10]:
        sub_str = " [SUB]" if s["isSubstitute"] else ""
        print(f"  [{s['serviceDate']} {s['startMin']//60:02d}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}{sub_str}")
