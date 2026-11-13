"""
Ailey Extension live schedule scraper.
Fetches https://ailey.org/calendar?view=month&classType=studio,
parses the Next.js stream payload for all live classes, and extracts
class title, level, start/end time, instructor, substitute status,
and direct Mindbody booking URLs.
Supports rolling multi-month coverage for full 14-day windows.
"""

import re
import time
import urllib.request
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

AILEY_CALENDAR_URL = "https://ailey.org/calendar?view=month&classType=studio"

BROWSER_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://ailey.org/",
    "Sec-Ch-Ua": '"Chromium";v="128", "Not;A=Brand";v="24", "Google Chrome";v="128"',
    "Sec-Ch-Ua-Mobile": "?0",
    "Sec-Ch-Ua-Platform": '"macOS"',
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "same-origin",
    "Sec-Fetch-User": "?1",
    "Upgrade-Insecure-Requests": "1"
}

def _fetch_month_classes(url: str) -> List[Dict[str, Any]]:
    req = urllib.request.Request(url, headers=BROWSER_HEADERS)
    html = ""
    last_err: Optional[Exception] = None

    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=75) as resp:
                html = resp.read().decode("utf-8")
            if html:
                break
        except Exception as e:
            last_err = e
            if attempt == 2:
                print(f"Warning: Ailey fetch failed after 3 attempts on {url}: {e}")
                raise e
            backoff = 3 * (attempt + 1)
            print(f"Ailey fetch attempt {attempt + 1} failed ({e}), retrying in {backoff}s...")
            time.sleep(backoff)

    sessions_by_id: Dict[str, Dict[str, Any]] = {}

    parts = html.split("self.__next_f.push([1,")
    for p in parts[1:]:
        if "instructor" not in p:
            continue
        norm_p = p.replace(r'\\\"', '"').replace(r'\"', '"')
        blocks = norm_p.split('"title":"')
        for i in range(1, len(blocks)):
            b = blocks[i]
            title_end = b.find('"')
            if title_end == -1:
                continue
            title = b[:title_end].strip()

            start_m = re.search(r'"start":\s*"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"', b)
            if not start_m:
                continue
            start_iso = start_m.group(1)

            end_m = re.search(r'"end":\s*"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"', b)
            end_iso = end_m.group(1) if end_m else ""

            if '"canceled":true' in b or '"cancelled":true' in b:
                continue

            inst_m = re.search(r'"instructor":\s*"([^"]+)"', b)
            instructor = inst_m.group(1).strip() if inst_m else "Staff"

            lvl_m = re.search(r'"level":\s*"([^"]*)"', b)
            level = lvl_m.group(1).strip() if lvl_m else ""

            is_sub = '"isSubstitute":true' in b

            # Mindbody URL is located in the cta href in the preceding block tail
            prev_tail = blocks[i-1][-500:]
            url_m = re.search(r'https://clients\.mindbodyonline\.com[^"]+', prev_tail.replace(r'\u0026', '&'))
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

            clean_title = ' '.join(title.replace("&#x27;", "'").replace("&amp;", "&").split())
            has_level_in_title = re.search(
                r'\b(beg|beginner|abs\s*beg|absolute|adv\s*beg|advanced|intro|basic|open|int|intermediate)\b',
                clean_title,
                re.I,
            ) is not None
            if level and level.lower() != "open" and not has_level_in_title:
                full_title = f"{clean_title} ({level.title()})"
            else:
                full_title = clean_title

            clean_t = re.sub(r'[^a-z0-9]', '', clean_title.lower())[:10]
            clean_inst = re.sub(r'[^a-z0-9]', '', instructor.lower())[:8]
            session_id = f"ailey_{service_date}_{start_min}_{clean_t}_{clean_inst}"

            if session_id not in sessions_by_id:
                sessions_by_id[session_id] = {
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
                }

    return list(sessions_by_id.values())

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

    # 2. Check if our 14-day rolling window crosses into next month
    today = datetime.now()
    if (today + timedelta(days=14)).month != today.month:
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
