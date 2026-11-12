"""
Deterministic Scraper for Human-Written Instructor Class Descriptions.

Crawls studio faculty pages and schedule payloads directly to extract 100% human-authored,
verbatim class descriptions as written by instructors and studios.
Contains zero AI-generated or LLM-summarized text.
"""

import os
import sys
import json
import re
import html as html_lib
import urllib.request
from typing import Dict, Any

DATA_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "instructor_descriptions.json"))
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

def fetch_url(url: str, timeout: int = 12) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="ignore")

def clean_text(html_snippet: str) -> str:
    """Removes HTML tags and normalizes whitespace while preserving exact text content and punctuation."""
    clean = re.sub(r'<[^>]+>', ' ', html_snippet)
    return html_lib.unescape(' '.join(clean.split())).strip()

def scrape_bdc_verbatim() -> Dict[str, Any]:
    print("Crawling Broadway Dance Center (BDC) faculty pages for verbatim descriptions...")
    try:
        faculty_html = fetch_url("https://www.broadwaydancecenter.com/faculty", timeout=15)
    except Exception as e:
        print(f"Error fetching BDC faculty index: {e}")
        return {}

    slugs = sorted(set(re.findall(r'href=[\"\']/faculty/([^\"\']+)[\"\']', faculty_html)))

    feed_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "schedule.json"))
    if os.path.exists(feed_path):
        with open(feed_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            for s in data.get("sessions", []):
                if s.get("studioId") == "bdc":
                    inst = s.get("instructor", "")
                    clean_name = re.sub(r'\(.*?\)|[\"\']', '', inst).strip()
                    slug = clean_name.lower().replace(" ", "-").replace(".", "")
                    slug = re.sub(r'-+', '-', slug).strip('-')
                    if slug and slug not in slugs:
                        slugs.append(slug)

    print(f"Found {len(slugs)} BDC faculty profiles. Extracting class description blocks...")
    results = {}

    for slug in slugs:
        url = f"https://www.broadwaydancecenter.com/faculty/{slug}"
        try:
            page = fetch_url(url, timeout=8)
            m = re.search(r'<div[^>]*field-faculty-class-descriptions[^>]*>(.*?)</div>\s*</div>', page, re.DOTALL)
            if m:
                clean = clean_text(m.group(1))
                if len(clean) > 20:
                    # Parse instructor name from title tag (e.g. "Annie Grove Faculty Bio | Broadway Dance Center")
                    title_m = re.search(r'<title>(.*?)(?:\|.*)?</title>', page)
                    inst_name = title_m.group(1).split('|')[0].strip() if title_m else slug.replace('-', ' ')
                    inst_name = html_lib.unescape(inst_name)
                    inst_name = re.sub(r'\s+faculty\s+bio$', '', inst_name, flags=re.I).strip()

                    entry = {
                        "default": clean,
                        "raw": clean,
                        "source": url
                    }

                    # Index by both human name and slug for resilient lookups
                    norm_name = re.sub(r'[\"\']', '', inst_name).lower().strip()
                    norm_slug = slug.replace('-', ' ').strip().lower()
                    results[norm_name] = entry
                    results[norm_slug] = entry
        except Exception:
            pass

    print(f"Extracted {len(results)} verbatim class descriptions from BDC.")
    return results

def scrape_peridance_verbatim() -> Dict[str, Any]:
    print("Crawling Peridance Center faculty profiles for verbatim CLASS DESCRIPTION blocks...")
    feed_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "schedule.json"))
    instructors_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "instructors.json"))
    instructors = set()
    if os.path.exists(feed_path):
        with open(feed_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            instructors = set(s["instructor"] for s in data.get("sessions", []) if s.get("studioId") == "peridance")

    known_slugs = [
        "chrybaby-cozie", "sun-kim", "tony-mcgregor", "bo-belza", "cebo-carr",
        "caterina-rago", "bivi-kimura", "diego-funes", "dianna-warren", "jon-lock",
        "julia-gleich", "king-kayak", "korie-genius", "luann-leonard", "martha-chapman",
        "miyabi-wright", "peter-schabel", "princess-lockerooo", "robert-taylor-jr",
        "sarah-iguchi", "sekou-heru", "tomoko-ishikawa", "yuka-kawazu", "andrea-farley-shimota",
        "bo-kyung-lee", "jeffrey-gugliotti", "huu-rock"
    ]

    # Include registered instructor aliases and faculty profile slugs
    alias_map: Dict[str, List[str]] = {}
    if os.path.exists(instructors_path):
        try:
            with open(instructors_path, "r", encoding="utf-8") as f:
                reg = json.load(f)
                for cid, rec in reg.items():
                    aliases = [a.lower().strip() for a in rec.get("aliases", [])]
                    fac_url = rec.get("facultyUrls", {}).get("peridance", "")
                    if fac_url:
                        url_slug = fac_url.rstrip("/").split("/")[-1]
                        if url_slug not in known_slugs:
                            known_slugs.append(url_slug)
                        alias_map[url_slug.replace("-", " ")] = aliases
                    for a in aliases:
                        a_slug = a.replace(" ", "-")
                        if a_slug not in known_slugs:
                            known_slugs.append(a_slug)
                        alias_map[a] = aliases
        except Exception:
            pass

    # Harvest Peridance dynamic faculty sitemap to match exact slugs (e.g. jazzy-j-(boog-soulfire))
    try:
        sitemap_xml = fetch_url("https://www.peridance.com/dynamic-faculty_p_a4086414_9ab8_4638_8a74_8e08d80c4f4a_0_5000-sitemap.xml", timeout=12)
        sitemap_slugs = re.findall(r'<loc>https://www\.peridance\.com/faculty/([^<]+)</loc>', sitemap_xml)
        for inst in instructors:
            clean_inst = re.sub(r'[^a-z0-9]', '', inst.lower())
            if not clean_inst:
                continue
            for s_slug in sitemap_slugs:
                clean_s = re.sub(r'[^a-z0-9]', '', s_slug.lower())
                if clean_inst == clean_s or (min(len(clean_inst), len(clean_s)) >= 6 and (clean_s.startswith(clean_inst) or clean_inst.startswith(clean_s))):
                    if s_slug not in known_slugs:
                        known_slugs.append(s_slug)
    except Exception as e:
        print(f"Warning: could not harvest Peridance sitemap: {e}")

    for inst in instructors:
        # Generate slug both with parens and without parens
        raw_slug = re.sub(r'[\"\']', '', inst.split("|")[0].strip()).lower().replace(" ", "-")
        raw_slug = re.sub(r'-+', '-', raw_slug).strip('-')
        if raw_slug and raw_slug not in known_slugs:
            known_slugs.append(raw_slug)

        clean_name = inst.split("|")[0].strip()
        clean_name = re.sub(r'\(.*?\)', '', clean_name).strip()
        slug = clean_name.lower().replace(" ", "-").replace("_", "").replace(".", "")
        slug = re.sub(r'-+', '-', slug).strip('-')
        if slug and slug not in known_slugs:
            known_slugs.append(slug)

    results = {}
    for slug in known_slugs:
        url = f"https://www.peridance.com/faculty/{slug}"
        try:
            page = fetch_url(url, timeout=8)
            # Find rich text element immediately following CLASS DESCRIPTION
            m = re.search(r'CLASS DESCRIPTION.*?data-testid=\"richTextElement\">(.*?)(?:</div>\s*<section|</div>\s*<div id=\"comp-m|TEACHING PHILOSOPHY)', page, re.DOTALL)
            if m:
                clean = clean_text(m.group(1))
                if len(clean) > 25 and "Coming soon!" not in clean:
                    verbatim_text = f"CLASS DESCRIPTION: {clean}"
                    entry = {
                        "default": verbatim_text,
                        "raw": clean,
                        "source": url
                    }
                    norm_slug = slug.replace("-", " ")
                    results[norm_slug] = entry
                    # Index with and without parens
                    clean_norm = re.sub(r'\(.*?\)', '', norm_slug).strip()
                    results[clean_norm] = entry

                    # Also map known display names
                    for inst in instructors:
                        inst_norm = re.sub(r'[\"\']', '', inst).lower().strip()
                        c_slug = re.sub(r'[^a-z0-9]', '', norm_slug)
                        c_inst = re.sub(r'[^a-z0-9]', '', inst_norm)
                        if c_slug and c_inst and (c_slug == c_inst or (min(len(c_slug), len(c_inst)) >= 6 and (c_slug.startswith(c_inst) or c_inst.startswith(c_slug)))):
                            results[inst_norm] = entry
                    # Map all registered aliases from instructors.json
                    if norm_slug in alias_map:
                        for a in alias_map[norm_slug]:
                            results[a] = entry
                    if clean_norm in alias_map:
                        for a in alias_map[clean_norm]:
                            results[a] = entry
        except Exception:
            pass

    print(f"Extracted {len(results)} verbatim class descriptions from Peridance.")
    return results

def scrape_steps_verbatim() -> Dict[str, Any]:
    print("Extracting verbatim class descriptions from Steps on Broadway faculty directory...")
    results = {}
    try:
        sitemap_url = "https://www.stepsnyc.com/faculty-sitemap.xml"
        xml = fetch_url(sitemap_url, timeout=12)
        urls = re.findall(r'<loc>(https://www\.stepsnyc\.com/faculty/([^/]+)/?)</loc>', xml)
        for full_url, slug in urls:
            norm_name = slug.replace("-", " ").strip().lower()
            try:
                page = fetch_url(full_url, timeout=8)
                m = re.search(r'class="(?:faculty-bio|entry-content)"[^>]*>(.*?)</div>', page, re.DOTALL)
                if m:
                    clean = clean_text(m.group(1))
                    if len(clean) > 30:
                        results[norm_name] = {
                            "default": clean,
                            "raw": clean,
                            "source": full_url
                        }
            except Exception:
                continue
    except Exception as e:
        print(f"Error extracting Steps faculty descriptions: {e}")

    print(f"Extracted {len(results)} verbatim descriptions from Steps.")
    return results

def scrape_pmt_verbatim() -> Dict[str, Any]:
    print("Extracting verbatim class descriptions from PMT House of Dance pages...")
    results = {}
    url = "https://www.pmthouseofdance.com/breakin-classes"
    try:
        html = fetch_url(url, timeout=12)
        # Breakin' 101
        m1 = re.search(r'Breakin\' 101 for Beginners.*?Description\s*(.*?)(?:CLICK HERE|Breaking Fundamentals|$)', html, re.DOTALL)
        if m1:
            clean1 = clean_text(m1.group(1))
            full1 = f"Description: {clean1}"
            entry1 = {
                "default": full1,
                "raw": clean1,
                "source": url
            }
            results["pavan thimmaiah"] = entry1
            results["lars kong"] = entry1

        # Breaking Fundamentals
        m2 = re.search(r'Breaking Fundamentals \(Open Level\).*?Description\s*(.*?)(?:CLICK HERE|$)', html, re.DOTALL)
        if m2:
            clean2 = clean_text(m2.group(1))
            full2 = f"Description: {clean2}"
            entry2 = {
                "default": full2,
                "raw": clean2,
                "source": url
            }
            results["heat rock"] = entry2
    except Exception as e:
        print(f"Error fetching PMT descriptions: {e}")

    print(f"Extracted {len(results)} verbatim descriptions from PMT.")
    return results

def main():
    print("=" * 60)
    print("Deterministic Verbatim Scraper (0% AI / 100% Human-Written)")
    print("=" * 60)

    all_data = {
        "bdc": scrape_bdc_verbatim(),
        "peridance": scrape_peridance_verbatim(),
        "steps": scrape_steps_verbatim(),
        "ailey": {}, # Ailey organizes by technique; instructors do not have individual class blurbs
        "pmt": scrape_pmt_verbatim()
    }

    os.makedirs(os.path.dirname(DATA_PATH), exist_ok=True)
    with open(DATA_PATH, "w", encoding="utf-8") as f:
        json.dump(all_data, f, indent=2, ensure_ascii=False)

    total = sum(len(d) for d in all_data.values())
    print("=" * 60)
    print(f"Saved {total} verbatim human-written class descriptions to {DATA_PATH}:")
    for st, d in all_data.items():
        print(f"  • {st.upper()}: {len(d)} descriptions")
    print("=" * 60)

if __name__ == "__main__":
    main()
