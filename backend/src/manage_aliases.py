#!/usr/bin/env python3
"""
CLI Tool & Pipeline for Discovering, Reviewing, and Managing Instructor Aliases & Nicknames.

Captures teacher nicknames (e.g. Kathryn Sullivan <-> Kathy Sullivan, Paolo "Slice" Peñala <-> Paolo Peñala)
across schedule class data and studio faculty directories (Peridance, Steps on Broadway, BDC, Ailey, PMT).
"""

import os
import sys
import json
import re
import urllib.request
import html as html_lib
from typing import Dict, List, Set, Tuple, Any, Optional

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")
INSTRUCTORS_PATH = os.path.join(DATA_DIR, "instructors.json")
DENIED_PATH = os.path.join(DATA_DIR, "denied_aliases.json")
SCHEDULE_PATH = os.path.join(DATA_DIR, "schedule.json")
DESCRIPTIONS_PATH = os.path.join(DATA_DIR, "instructor_descriptions.json")

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)

# Bidirectional dictionary of common nicknames/diminutives
COMMON_NICKNAMES = {
    "kathryn": {"kathy", "katie", "kate", "kat", "catherine", "katherine", "cathryn", "cathy"},
    "katherine": {"kathy", "katie", "kate", "kat", "catherine", "kathryn", "cathryn", "cathy"},
    "catherine": {"cathy", "katie", "kate", "kat", "katherine", "kathryn", "cathryn", "kathy"},
    "kathy": {"kathryn", "katherine", "catherine", "katie", "kate", "kat"},
    "katie": {"kathryn", "katherine", "catherine", "kathy", "kate"},
    "robert": {"bob", "bobby", "robbie", "rob", "bert"},
    "bob": {"robert", "bobby", "robbie", "rob"},
    "bobby": {"robert", "bob", "robbie", "rob"},
    "robbie": {"robert", "bob", "bobby", "rob"},
    "alexander": {"alex", "alec", "lex", "sasha"},
    "alexandra": {"alex", "lexi", "lexie", "alli", "allie", "ally", "sasha"},
    "alex": {"alexander", "alexandra", "alec"},
    "william": {"will", "bill", "billy", "liam", "willy"},
    "bill": {"william", "billy", "will"},
    "billy": {"william", "bill", "will"},
    "will": {"william", "bill", "billy"},
    "michael": {"mike", "mikey", "mick"},
    "mike": {"michael", "mikey"},
    "mikey": {"michael", "mike"},
    "james": {"jim", "jimmy", "jamie"},
    "jim": {"james", "jimmy"},
    "jimmy": {"james", "jim"},
    "daniel": {"dan", "danny"},
    "danielle": {"dani", "danny", "dan"},
    "dan": {"daniel", "danny"},
    "danny": {"daniel", "dan"},
    "christopher": {"chris", "topher"},
    "christine": {"chris", "chrissy", "tina"},
    "christina": {"chris", "chrissy", "tina"},
    "chris": {"christopher", "christine", "christina"},
    "anthony": {"tony"},
    "tony": {"anthony"},
    "matthew": {"matt", "matty"},
    "matt": {"matthew"},
    "nicholas": {"nick", "nicky"},
    "nick": {"nicholas", "nicky"},
    "joseph": {"joe", "joey"},
    "joe": {"joseph", "joey"},
    "joey": {"joseph", "joe"},
    "benjamin": {"ben", "benji", "benny"},
    "ben": {"benjamin", "benji"},
    "samuel": {"sam", "sammy"},
    "samantha": {"sam", "sammy", "sami"},
    "sam": {"samuel", "samantha"},
    "thomas": {"tom", "tommy"},
    "tom": {"thomas", "tommy"},
    "jonathan": {"jon", "jonny", "john", "johnny"},
    "john": {"jonathan", "jon", "johnny", "jack"},
    "jon": {"jonathan", "john", "jonny"},
    "johnny": {"john", "jonathan", "jon"},
    "jonny": {"jonathan", "jon", "john"},
    "elizabeth": {"liz", "lizzie", "beth", "eliza", "lisa"},
    "liz": {"elizabeth", "lizzie", "beth"},
    "margaret": {"maggie", "meg", "peggy"},
    "maggie": {"margaret", "meg"},
    "victoria": {"vicky", "vicki", "tori"},
    "vicky": {"victoria", "tori"},
    "stephanie": {"steph"},
    "steph": {"stephanie"},
    "edward": {"ed", "eddie", "ned", "ted"},
    "david": {"dave"},
    "dave": {"david"},
    "richard": {"rick", "ricky", "dick", "rich"},
    "rick": {"richard", "ricky"},
    "charles": {"charlie", "chuck"},
    "charlie": {"charles", "chuck"},
    "jeffrey": {"jeff"},
    "jeff": {"jeffrey"},
    "andrew": {"andy", "drew"},
    "andy": {"andrew", "drew"},
    "theodore": {"ted", "teddy", "theo"},
    "ted": {"theodore", "teddy"},
    "vincent": {"vince", "vinny"},
    "vince": {"vincent", "vinny"},
    "jennifer": {"jen", "jenny"},
    "jen": {"jennifer", "jenny"},
    "rebecca": {"becky", "becca"},
    "becky": {"rebecca", "becca"},
    "gabrielle": {"gabby", "gabi", "gabe"},
    "gabriel": {"gabe", "gabby"},
    "jessica": {"jess", "jessie"},
    "jess": {"jessica", "jessie"},
    "amanda": {"mandy"},
    "mandy": {"amanda"},
    "brittany": {"brit", "britt"},
    "natalie": {"nat"},
    "eleanor": {"ellie", "nora"},
    "francesca": {"frankie", "fran"},
    "jacqueline": {"jackie"},
    "jackie": {"jacqueline", "jack"},
    "valerie": {"val"},
    "veronica": {"ronnie", "roni"},
    "patricia": {"pat", "patty", "tricia", "trish"},
    "pat": {"patricia", "patrick", "patty"},
    "patrick": {"pat", "paddy"},
    "bo": {"bo-kyung", "bokyung"},
    "bo-kyung": {"bo"},
}

def load_json(path: str, default: Any = None) -> Any:
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return default if default is not None else {}

def save_json(path: str, data: Any):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def clean_name(name: str) -> str:
    """Removes HTML entities, extraneous quotes, and excess spaces."""
    n = html_lib.unescape(name)
    n = re.sub(r'[\'\"״]', '', n)
    n = re.sub(r'\s+', ' ', n).strip()
    return n

def normalize_key(name: str) -> str:
    """Produces lowercase alphanumeric string for indexing."""
    n = clean_name(name).lower()
    return re.sub(r'[^a-z0-9]', '', n)

def parse_name_parts(full_name: str) -> Tuple[str, str, str]:
    """Splits full name into (first_name, nickname_or_moniker, surname)."""
    clean = clean_name(full_name)
    # Check for moniker in quotes or parens: e.g. Paolo "Slice" Peñala
    m = re.search(r'^(.*?)\s*[\"\(\[\{](.+?)[\"\)\]\}]\s*(.*?)$', full_name)
    moniker = ""
    if m:
        first = m.group(1).strip()
        moniker = m.group(2).strip()
        last = m.group(3).strip()
        if not last and " " in first:
            parts = first.split()
            first = parts[0]
            last = " ".join(parts[1:])
        return first.lower(), moniker.lower(), last.lower()

    tokens = clean.split()
    if not tokens:
        return "", "", ""
    if len(tokens) == 1:
        return tokens[0].lower(), "", ""
    first = tokens[0].lower()
    last = tokens[-1].lower()
    # Check if there's a middle initial or suffix like Jr, III
    if last in {"jr", "sr", "ii", "iii", "iv"} and len(tokens) >= 3:
        last = tokens[-2].lower()
    return first, "", last

def are_nicknames(first1: str, first2: str) -> bool:
    """Returns True if first1 and first2 are recognized variations or nicknames of each other."""
    f1 = first1.lower().replace("-", "")
    f2 = first2.lower().replace("-", "")
    if f1 == f2:
        return True
    if f1 in COMMON_NICKNAMES and f2 in COMMON_NICKNAMES[f1]:
        return True
    if f2 in COMMON_NICKNAMES and f1 in COMMON_NICKNAMES[f2]:
        return True
    # Prefix matches of at least 3 characters (e.g. Dan / Daniel, Rob / Robert)
    if len(f1) >= 3 and len(f2) >= 3:
        if f1.startswith(f2) or f2.startswith(f1):
            return True
    return False

def levenshtein_distance(s1: str, s2: str) -> int:
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)
    prev = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        curr = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = prev[j + 1] + 1
            deletions = curr[j] + 1
            substitutions = prev[j] + (c1 != c2)
            curr.append(min(insertions, deletions, substitutions))
        prev = curr
    return prev[-1]

def harvest_schedule_names() -> Dict[str, Set[str]]:
    """Returns mapping of raw instructor name -> set of studioIds from schedule.json."""
    data = load_json(SCHEDULE_PATH, {})
    res: Dict[str, Set[str]] = {}
    for s in data.get("sessions", []):
        inst = s.get("instructor")
        if not inst:
            continue
        clean = clean_name(inst)
        if clean in {"Staff", "Guest Artist", "Special Guest", "Substitute Teacher", "Various Teachers"}:
            continue
        studio = s.get("studioId", "unknown")
        if clean not in res:
            res[clean] = set()
        res[clean].add(studio)
    return res

def harvest_faculty_data() -> Dict[str, Dict[str, Any]]:
    """
    Harvests faculty directory profiles across studios.
    Returns: { 'Slug/Name': { 'studio': str, 'name': str, 'url': str, 'hasDescription': bool } }
    """
    faculty: Dict[str, Dict[str, Any]] = {}

    # 1. Peridance Dynamic Faculty Sitemap
    peridance_sitemap = "https://www.peridance.com/dynamic-faculty_p_a4086414_9ab8_4638_8a74_8e08d80c4f4a_0_5000-sitemap.xml"
    try:
        req = urllib.request.Request(peridance_sitemap, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=12) as resp:
            xml = resp.read().decode("utf-8", errors="ignore")
            urls = re.findall(r'<loc>(https://www\.peridance\.com/faculty/([^<]+))</loc>', xml)
            for full_url, slug in urls:
                name_guess = slug.replace("-", " ").title()
                faculty[f"peridance:{slug}"] = {
                    "studio": "peridance",
                    "slug": slug,
                    "name": name_guess,
                    "url": full_url
                }
    except Exception as e:
        print(f"Warning: Could not harvest Peridance faculty sitemap: {e}")

    # 2. Steps on Broadway Faculty Sitemaps
    for sitemap_url in [
        "https://www.stepsnyc.com/faculty-sitemap.xml",
        "https://www.stepsnyc.com/faculty-sitemap2.xml"
    ]:
        try:
            req = urllib.request.Request(sitemap_url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=12) as resp:
                xml = resp.read().decode("utf-8", errors="ignore")
                urls = re.findall(r'<loc>(https://www\.stepsnyc\.com/faculty/([^/]+)/?)</loc>', xml)
                for full_url, slug in urls:
                    name_guess = slug.replace("-", " ").title()
                    faculty[f"steps:{slug}"] = {
                        "studio": "steps",
                        "slug": slug,
                        "name": name_guess,
                        "url": full_url
                    }
        except Exception:
            pass

    # 3. Broadway Dance Center Faculty
    bdc_url = "https://www.broadwaydancecenter.com/faculty"
    try:
        req = urllib.request.Request(bdc_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=12) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
            slugs = sorted(set(re.findall(r'href=[\"\']/faculty/([^\"\']+)[\"\']', html)))
            for slug in slugs:
                name_guess = slug.replace("-", " ").title()
                faculty[f"bdc:{slug}"] = {
                    "studio": "bdc",
                    "slug": slug,
                    "name": name_guess,
                    "url": f"https://www.broadwaydancecenter.com/faculty/{slug}"
                }
    except Exception:
        pass

    return faculty

def find_candidate_clusters() -> List[Dict[str, Any]]:
    """
    Finds potential nickname and alias pairs across schedule instructors and faculty profiles.
    Excludes confirmed aliases in instructors.json and denied pairs in denied_aliases.json.
    """
    instructors_reg = load_json(INSTRUCTORS_PATH, {})
    denied_pairs = load_json(DENIED_PATH, [])
    denied_set = set(tuple(sorted([pair[0].lower(), pair[1].lower()])) for pair in denied_pairs if len(pair) == 2)

    # Known aliases map
    known_alias_to_canonical = {}
    for canonical_id, data in instructors_reg.items():
        for alias in data.get("aliases", []):
            known_alias_to_canonical[clean_name(alias).lower()] = canonical_id

    schedule_instructors = harvest_schedule_names()
    faculty_profiles = harvest_faculty_data()

    # Build pool of unique person entities: { name: { 'studios': set(), 'isFaculty': bool, 'url': str } }
    pool: Dict[str, Dict[str, Any]] = {}

    for name, studios in schedule_instructors.items():
        pool[name] = {
            "name": name,
            "studios": studios,
            "isSchedule": True,
            "isFaculty": False,
            "urls": {}
        }

    for fac_id, fac in faculty_profiles.items():
        fac_name = fac["name"]
        if fac_name not in pool:
            pool[fac_name] = {
                "name": fac_name,
                "studios": {fac["studio"]},
                "isSchedule": False,
                "isFaculty": True,
                "urls": {fac["studio"]: fac["url"]}
            }
        else:
            pool[fac_name]["studios"].add(fac["studio"])
            pool[fac_name]["isFaculty"] = True
            pool[fac_name]["urls"][fac["studio"]] = fac["url"]

    descriptions_data = load_json(DESCRIPTIONS_PATH, {})

    # Group pool by surname
    by_surname: Dict[str, List[str]] = {}
    for name in pool:
        first, moniker, last = parse_name_parts(name)
        if not last or len(last) < 2:
            continue
        if last not in by_surname:
            by_surname[last] = []
        by_surname[last].append(name)

    candidates: List[Dict[str, Any]] = []
    seen_pairs = set()

    for surname, names in by_surname.items():
        if len(names) < 2:
            continue
        # Compare all pairs within surname cluster
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                n1, n2 = names[i], names[j]
                norm_pair = tuple(sorted([clean_name(n1).lower(), clean_name(n2).lower()]))
                if norm_pair in seen_pairs or norm_pair in denied_set:
                    continue
                seen_pairs.add(norm_pair)

                # Skip if already merged under same canonical entity
                c1 = known_alias_to_canonical.get(norm_pair[0])
                c2 = known_alias_to_canonical.get(norm_pair[1])
                if c1 and c2 and c1 == c2:
                    continue

                f1, m1, l1 = parse_name_parts(n1)
                f2, m2, l2 = parse_name_parts(n2)

                is_match = False
                reason = ""

                # Rule 1: Recognized nickname / diminutive
                if are_nicknames(f1, f2):
                    is_match = True
                    reason = f"Nickname match ('{f1}' <-> '{f2}') with shared surname '{surname.title()}'"

                # Rule 2: Moniker or stage name in quotes/parens
                elif m1 or m2:
                    clean1 = re.sub(r'[\"\(\[\{].*?[\"\)\]\}]', '', n1).strip()
                    clean2 = re.sub(r'[\"\(\[\{].*?[\"\)\]\}]', '', n2).strip()
                    if clean_name(clean1).lower() == clean_name(clean2).lower():
                        is_match = True
                        reason = f"Moniker variation ('{n1}' <-> '{n2}')"

                # Rule 3: Very close first name spelling (edit distance <= 1 on first name)
                elif len(f1) >= 4 and len(f2) >= 4 and levenshtein_distance(f1, f2) <= 1:
                    is_match = True
                    reason = f"Spelling variation ('{f1}' <-> '{f2}')"

                if is_match:
                    p1, p2 = pool[n1], pool[n2]
                    # Check description availability
                    has_desc1 = any(clean_name(n1).lower() in s_data for s_data in descriptions_data.values())
                    has_desc2 = any(clean_name(n2).lower() in s_data for s_data in descriptions_data.values())

                    # Suggest canonical name (favor formal name or one with faculty URL)
                    canonical_guess = n1
                    if len(f2) > len(f1) or (p2.get("isFaculty") and not p1.get("isFaculty")):
                        canonical_guess = n2

                    candidates.append({
                        "name1": n1,
                        "name2": n2,
                        "p1": p1,
                        "p2": p2,
                        "hasDesc1": has_desc1,
                        "hasDesc2": has_desc2,
                        "canonicalGuess": canonical_guess,
                        "reason": reason
                    })

    # Sort candidates so high-value ones (with descriptions) appear first
    candidates.sort(key=lambda c: (c["hasDesc1"] or c["hasDesc2"]), reverse=True)
    return candidates

def register_merge(name1: str, name2: str, canonical_name: str, studio_list: List[str], faculty_urls: Dict[str, str]):
    """Registers an approved merge into instructors.json."""
    instructors = load_json(INSTRUCTORS_PATH, {})
    canonical_id = re.sub(r'[^a-z0-9_]', '', canonical_name.lower().replace(" ", "_"))

    existing_record = None
    for cid, record in instructors.items():
        aliases = [a.lower() for a in record.get("aliases", [])]
        if name1.lower() in aliases or name2.lower() in aliases or canonical_name.lower() == record.get("canonicalName", "").lower():
            canonical_id = cid
            existing_record = record
            break

    if not existing_record:
        existing_record = {
            "canonicalName": canonical_name,
            "aliases": [],
            "studios": [],
            "facultyUrls": {}
        }

    alias_set = set(existing_record.get("aliases", []))
    alias_set.add(name1)
    alias_set.add(name2)
    alias_set.add(canonical_name)
    existing_record["aliases"] = sorted(alias_set)

    studio_set = set(existing_record.get("studios", []))
    studio_set.update(studio_list)
    existing_record["studios"] = sorted(studio_set)

    if "facultyUrls" not in existing_record:
        existing_record["facultyUrls"] = {}
    valid_studios = {"bdc", "steps", "ailey", "peridance", "pmt"}
    filtered_urls = {k: v for k, v in faculty_urls.items() if k in valid_studios and isinstance(v, str)}
    existing_record["facultyUrls"].update(filtered_urls)

    instructors[canonical_id] = existing_record
    save_json(INSTRUCTORS_PATH, instructors)
    print(f"  [SAVED] Registered '{canonical_name}' (aliases: {', '.join(existing_record['aliases'])})")

def register_denial(name1: str, name2: str):
    """Registers an explicitly denied pair into denied_aliases.json."""
    denied = load_json(DENIED_PATH, [])
    pair = sorted([name1, name2])
    if pair not in denied:
        denied.append(pair)
        save_json(DENIED_PATH, denied)
    print(f"  [SAVED] Denied merge between '{name1}' and '{name2}'")

def interactive_review():
    """Runs interactive CLI review of candidate alias clusters."""
    print("=" * 65)
    print("  NYC DANCE INSTRUCTOR ALIAS & NICKNAME REVIEW TOOL")
    print("=" * 65)
    print("Scanning schedule and studio faculty directories...")
    candidates = find_candidate_clusters()
    total = len(candidates)
    if not total:
        print("No pending candidate merges found! All instructors are mapped or verified.")
        return

    print(f"Found {total} candidate alias pair(s).\n")

    for idx, c in enumerate(candidates, 1):
        n1, n2 = c["name1"], c["name2"]
        p1, p2 = c["p1"], c["p2"]
        print("-" * 65)
        print(f"Candidate Merge [{idx}/{total}]")
        print(f"  Reason: {c['reason']}")
        print(f"  Option 1: '{n1}'")
        print(f"    Studios: {', '.join(p1['studios']) or 'unknown'}")
        print(f"    Schedule: {'YES' if p1.get('isSchedule') else 'NO'} | Faculty Profile: {'YES' if p1.get('isFaculty') else 'NO'}")
        print(f"    Class Description on file: {'YES' if c['hasDesc1'] else 'NO'}")
        print(f"  Option 2: '{n2}'")
        print(f"    Studios: {', '.join(p2['studios']) or 'unknown'}")
        print(f"    Schedule: {'YES' if p2.get('isSchedule') else 'NO'} | Faculty Profile: {'YES' if p2.get('isFaculty') else 'NO'}")
        print(f"    Class Description on file: {'YES' if c['hasDesc2'] else 'NO'}")
        print(f"  Suggested Canonical: '{c['canonicalGuess']}'")

        while True:
            choice = input("\nMerge these two names? [y]es / [n]o / [e]dit / [s]kip / [q]uit: ").strip().lower()
            if choice in {"y", "yes"}:
                all_studios = list(p1["studios"] | p2["studios"])
                all_urls = {**p1.get("urls", {}), **p2.get("urls", {})}
                register_merge(n1, n2, c["canonicalGuess"], all_studios, all_urls)
                break
            elif choice in {"n", "no"}:
                register_denial(n1, n2)
                break
            elif choice in {"e", "edit"}:
                cust_canonical = input(f"Enter Canonical Name (press enter for '{c['canonicalGuess']}'): ").strip()
                if not cust_canonical:
                    cust_canonical = c["canonicalGuess"]
                all_studios = list(p1["studios"] | p2["studios"])
                all_urls = {**p1.get("urls", {}), **p2.get("urls", {})}
                register_merge(n1, n2, cust_canonical, all_studios, all_urls)
                break
            elif choice in {"s", "skip"}:
                print("  [SKIPPED] Skipping candidate for now.")
                break
            elif choice in {"q", "quit", "exit"}:
                print("\nExiting review. Progress saved.")
                return
            else:
                print("Invalid input. Please choose [y], [n], [e], [s], or [q].")

    print("\nReview session complete!")

def list_registered():
    """Prints all registered instructors in instructors.json."""
    data = load_json(INSTRUCTORS_PATH, {})
    print(f"\nRegistered Instructors ({len(data)} total):")
    print("=" * 65)
    for cid, record in sorted(data.items()):
        print(f"• {record.get('canonicalName', cid)}")
        print(f"    Aliases: {', '.join(record.get('aliases', []))}")
        print(f"    Studios: {', '.join(record.get('studios', []))}")
        if record.get("facultyUrls"):
            print(f"    Profiles: {record.get('facultyUrls')}")
    print()

def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        if arg in {"--list", "-l"}:
            list_registered()
            return
        elif arg in {"--status", "-s"}:
            data = load_json(INSTRUCTORS_PATH, {})
            denied = load_json(DENIED_PATH, [])
            candidates = find_candidate_clusters()
            print(f"Registered Instructors: {len(data)}")
            print(f"Denied Pairs: {len(denied)}")
            print(f"Pending Candidates: {len(candidates)}")
            return
        elif arg == "--merge":
            # Direct non-interactive merge: --merge "Kathy Sullivan" "Kathryn Sullivan" [canonical]
            if len(sys.argv) >= 4:
                n1 = sys.argv[2]
                n2 = sys.argv[3]
                canonical = sys.argv[4] if len(sys.argv) >= 5 else n2
                # Look up faculty urls and studios
                pool_data = harvest_schedule_names()
                s1 = pool_data.get(clean_name(n1), set())
                s2 = pool_data.get(clean_name(n2), set())
                fac = harvest_faculty_data()
                urls = {}
                for k, v in fac.items():
                    if clean_name(v["name"]).lower() in {clean_name(n1).lower(), clean_name(n2).lower()}:
                        urls[v["studio"]] = v["url"]
                register_merge(n1, n2, canonical, list(s1 | s2), urls)
                return

    interactive_review()

if __name__ == "__main__":
    main()
