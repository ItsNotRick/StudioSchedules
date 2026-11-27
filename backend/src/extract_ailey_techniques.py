"""
Collects Ailey Extension's per-technique class descriptions.

Ailey describes classes by technique (Horton, Dunham, Sabar, Zumba®, ...), one
page per technique under https://www.ailey.org/classes/techniques/. This script
walks the index, copies each page's description verbatim, and writes
backend/data/ailey_techniques.json, which build_feed.py uses to describe Ailey
classes. Run it by hand when Ailey adds or rewrites a technique page:

    python3 backend/src/extract_ailey_techniques.py
"""

import html as html_lib
import json
import os
import re
import sys
import urllib.request
from html.parser import HTMLParser
from typing import Dict, List, Optional

INDEX_URL = "https://www.ailey.org/classes/techniques/"
BASE_URL = "https://www.ailey.org"
DATA_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "data", "ailey_techniques.json"))
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")

# Text that follows the description on every page: the level guide.
LEVEL_GUIDE_MARKER = "Our classes are defined"

# Index cards look like:
#   <a aria-label="Dunham" ... href="/classes/techniques/dunham"><h4 ...>Dunham</h4></a>
TECHNIQUE_LINK_REGEX = re.compile(
    r'<a[^>]*href="/classes/techniques/([a-z0-9-]+)"[^>]*>\s*<h4[^>]*>(.*?)</h4>', re.S)


def fetch_url(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def normalize_space(text: str) -> str:
    return " ".join(html_lib.unescape(text).split())


class _SliceBodyCollector(HTMLParser):
    """Collects the text of every <div class="SliceBody_body__...">, nesting-safe."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: List[str] = []
        self._depth = 0  # >0 while inside a SliceBody div
        self._parts: List[str] = []

    def handle_starttag(self, tag, attrs):
        if self._depth:
            if tag == "div":
                self._depth += 1
            elif tag in ("p", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6"):
                self._parts.append(" ")
            return
        if tag == "div" and "SliceBody_body" in (dict(attrs).get("class") or ""):
            self._depth = 1
            self._parts = []

    def handle_endtag(self, tag):
        if self._depth and tag == "div":
            self._depth -= 1
            if not self._depth:
                self.blocks.append(normalize_space("".join(self._parts)))

    def handle_data(self, data):
        if self._depth:
            self._parts.append(data)


def parse_technique_index(index_html: str) -> List[Dict[str, str]]:
    """Returns [{"slug", "name"}] for each technique card, in page order."""
    seen = set()
    techniques = []
    for slug, raw_name in TECHNIQUE_LINK_REGEX.findall(index_html):
        name = normalize_space(re.sub(r"<[^>]+>", " ", raw_name))
        if slug in seen or not name:
            continue
        seen.add(slug)
        techniques.append({"slug": slug, "name": name})
    return techniques


def parse_technique_description(page_html: str, name: str = "") -> Optional[str]:
    """Returns the technique's description, without the level guide, instructor list,
    or a leading heading that repeats the technique name."""
    collector = _SliceBodyCollector()
    collector.feed(page_html)
    for block in collector.blocks:
        if not block or block.startswith("Instructors") or block.startswith(LEVEL_GUIDE_MARKER):
            continue
        description = block.split(LEVEL_GUIDE_MARKER)[0].strip()
        if name and description.lower().startswith(name.lower()):
            rest = description[len(name):].lstrip()
            # Drop "Afro-Brazilian Dance Afro-Brazilian dance is..." style headings.
            if rest.lower().startswith(name.split()[0].lower()):
                description = rest
        if len(description) > 40:
            return description
    return None


def main() -> int:
    index_html = fetch_url(INDEX_URL)
    techniques = parse_technique_index(index_html)
    if not techniques:
        print("No technique links found on the index page; leaving the data file unchanged.")
        return 1

    results = []
    for tech in techniques:
        url = f"{BASE_URL}/classes/techniques/{tech['slug']}"
        try:
            description = parse_technique_description(fetch_url(url), tech["name"])
        except Exception as e:  # keep going; one bad page shouldn't drop the rest
            print(f"  ! {tech['name']}: {e}")
            continue
        if not description:
            print(f"  ! {tech['name']}: no description found")
            continue
        results.append({**tech, "url": url, "description": description})
        print(f"  ✓ {tech['name']}")

    if len(results) < len(techniques) // 2:
        print(f"Only {len(results)}/{len(techniques)} pages parsed; leaving the data file unchanged.")
        return 1

    with open(DATA_PATH, "w", encoding="utf-8") as f:
        json.dump({"source": INDEX_URL, "techniques": results}, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Saved {len(results)}/{len(techniques)} Ailey technique descriptions to {DATA_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
