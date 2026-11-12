"""
PMT House of Dance live schedule scraper.
Fetches Mindbody schedule for Studio ID 727061 across both the current week
and next week (14-day rolling window), extracting scheduled classes, times,
instructors, durations, and substitute teachers.
"""

import re
import html as html_lib
import urllib.request
import urllib.parse
import http.cookiejar
from datetime import datetime, timedelta
from typing import List, Dict, Any
import time

PMT_STUDIO_ID = "727061"
PMT_MINDBODY_WS_URL = f"https://clients.mindbodyonline.com/classic/ws?studioid={PMT_STUDIO_ID}"
PMT_MINDBODY_HOME_URL = f"https://clients.mindbodyonline.com/classic/home?studioid={PMT_STUDIO_ID}"
PMT_MINDBODY_SCHEDULE_URL = "https://clients.mindbodyonline.com/classic/mainclass?fl=true&tabID=7"

def _parse_pmt_table(html: str, seen: set) -> List[Dict[str, Any]]:
    idx = html.find('<div id="classSchedule-mainTable"')
    if idx == -1:
        return []
    table_content = html[idx:]

    date_splits = re.split(r'<div class="header"[^>]*><b>(?:<span[^>]*>[a-zA-Z]+\s*</span>)?([^<]+)</b></div>', table_content)
    sessions: List[Dict[str, Any]] = []

    for i in range(1, len(date_splits), 2):
        date_str = date_splits[i].strip()
        rows_chunk = date_splits[i+1]

        try:
            dt = datetime.strptime(date_str, "%B %d, %Y")
            service_date = dt.strftime("%Y-%m-%d")
        except Exception as e:
            print(f"Warning: skipping PMT date header '{date_str}': {e}")
            continue

        row_matches = re.finditer(r'<div class="(?:evenRow|oddRow) row">(.*?)</div>\s*</div>\s*</div>', rows_chunk, re.DOTALL)
        for rm in row_matches:
            row_html = rm.group(1)

            # Start time
            time_m = re.search(r'([0-1]?[0-9]:[0-5][0-9])\s*(?:&nbsp;|\s+)*(am|pm)', row_html, re.I)
            if not time_m:
                continue
            time_str = f"{time_m.group(1)} {time_m.group(2).lower()}"
            try:
                t_obj = datetime.strptime(time_str, "%I:%M %p")
                start_min = t_obj.hour * 60 + t_obj.minute
            except Exception as e:
                print(f"Warning: skipping PMT row on {service_date} with unparseable time '{time_str}': {e}")
                continue

            col2_m = re.search(r'<div class="col-2">(.*)', row_html, re.DOTALL)
            if not col2_m:
                continue
            cols = re.findall(r'<div class="col">(.*?)</div>', col2_m.group(1), re.DOTALL)
            if not cols:
                continue

            raw_title = html_lib.unescape(re.sub(r'<[^>]+>', '', cols[0])).strip()

            # Instructor
            teacher = "Staff"
            if len(cols) > 1:
                clean_inst = re.sub(r'<a title="Regularly Scheduled[^"]*"[^>]*>.*?</a>', '', cols[1])
                teacher = re.sub(r'<[^>]+>', '', clean_inst).strip()
                teacher = html_lib.unescape(re.sub(r'\(\d+\)', '', teacher)).strip()

            # Duration
            dur = 90
            if len(cols) > 2:
                dur_text = cols[2]
                dur_m = re.search(r'(\d+)\s*hour(?:\s*&?\s*(\d+)\s*min)?|(\d+)\s*min', dur_text, re.I)
                if dur_m:
                    if dur_m.group(1):
                        h = int(dur_m.group(1))
                        m_part = int(dur_m.group(2)) if dur_m.group(2) else 0
                        dur = h * 60 + m_part
                    elif dur_m.group(3):
                        dur = int(dur_m.group(3))

            is_sub = "regularly scheduled" in row_html.lower() or "#990000" in row_html

            clean_t = re.sub(r'[^a-z0-9]', '', raw_title.lower())[:10]
            clean_teach = re.sub(r'[^a-z0-9]', '', teacher.lower())[:8]
            session_id = f"pmt_{service_date}_{start_min}_{clean_t}_{clean_teach}"
            if session_id in seen:
                continue
            seen.add(session_id)

            sessions.append({
                "id": session_id,
                "studioId": "pmt",
                "rawClassTitle": raw_title,
                "serviceDate": service_date,
                "startMin": start_min,
                "endMin": start_min + dur,
                "tz": "America/New_York",
                "instructor": teacher,
                "isSubstitute": is_sub,
                "bookingUrl": "https://www.pmthouseofdance.com/sign-up-for-classes"
            })

    return sessions

def scrape_pmt_schedule() -> List[Dict[str, Any]]:
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    opener.addheaders = [
        ("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"),
        ("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"),
        ("Accept-Language", "en-US,en;q=0.9"),
        ("Sec-Ch-Ua", '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"'),
        ("Sec-Ch-Ua-Mobile", "?0"),
        ("Sec-Ch-Ua-Platform", '"macOS"'),
        ("Referer", "https://www.pmthouseofdance.com/"),
    ]

    # Handshake with Mindbody
    for attempt in range(3):
        try:
            resp1 = opener.open(PMT_MINDBODY_WS_URL, timeout=15)
            html1 = resp1.read().decode("utf-8", errors="ignore")
            fields = {m.group(1): m.group(2) for m in re.finditer(r'<input[^>]+name=["\']([^"\']+)["\'][^>]+value=["\']([^"\']*)["\']', html1)}
            data = urllib.parse.urlencode(fields).encode("utf-8")
            req2 = urllib.request.Request(PMT_MINDBODY_HOME_URL, data=data)
            opener.open(req2, timeout=15)
            break
        except Exception as e:
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
            else:
                raise e

    # Compute next Monday for Week 2
    today = datetime.now()
    days_ahead = (7 - today.weekday()) % 7
    if days_ahead == 0:
        days_ahead = 7
    next_monday = today + timedelta(days=days_ahead)
    date_param = next_monday.strftime("%m/%d/%Y")

    urls_to_scrape = [
        PMT_MINDBODY_SCHEDULE_URL,
        f"{PMT_MINDBODY_SCHEDULE_URL}&date={date_param}"
    ]

    all_sessions: List[Dict[str, Any]] = []
    seen = set()

    for schedule_url in urls_to_scrape:
        for attempt in range(3):
            try:
                resp = opener.open(schedule_url, timeout=15)
                html = resp.read().decode("utf-8", errors="ignore")
                if '<div id="classSchedule-mainTable"' in html:
                    parsed = _parse_pmt_table(html, seen)
                    all_sessions.extend(parsed)
                    break
            except Exception as e:
                if attempt < 2:
                    time.sleep(1)
                else:
                    print(f"Error fetching PMT schedule from {schedule_url}: {e}")

    all_sessions.sort(key=lambda s: (s["serviceDate"], s["startMin"]))
    return all_sessions

if __name__ == "__main__":
    results = scrape_pmt_schedule()
    print(f"Scraped {len(results)} live classes from PMT House of Dance across 14-day rolling window:")
    dates = sorted(list(set(s['serviceDate'] for s in results)))
    print(f"Dates covered: {dates}")
    for s in results[:10]:
        sub_str = " [SUB]" if s.get("isSubstitute") else ""
        print(f"  [{s['serviceDate']} {s['startMin']//60:02d}:{s['startMin']%60:02d}] {s['rawClassTitle']} | {s['instructor']}{sub_str} ({s['endMin']-s['startMin']}m)")
