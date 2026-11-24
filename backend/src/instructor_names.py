"""Instructor name helpers shared by build_feed.py and manage_aliases.py.

normalize_instructor() is mirrored by normalizeInstructor() in
app/lib/src/domain/models.dart; keep them identical. The app receives the
alias map and the placeholder list through the feed ("instructorAliases",
"placeholderInstructors").
"""

import re
from collections import defaultdict
from typing import Any, Dict, List


def normalize_instructor(name: str) -> str:
    """Matching key for an instructor name.

    Must stay identical to normalizeInstructor() in app/lib/src/domain/models.dart:
    collapse whitespace, drop quote characters, lowercase, trim.
    """
    collapsed = ' '.join(name.split())
    return re.sub(r'[\"\']', '', collapsed).lower().strip()


# Normalized names that stand for "no particular teacher". They are never
# registered as aliases, and the app shows no teacher notes for them.
PLACEHOLDER_INSTRUCTORS = (
    "staff",
    "tba",
    "tbd",
    "guest artist",
    "special guest",
    "substitute teacher",
    "various teachers",
)


def is_placeholder_instructor(name: str) -> bool:
    return normalize_instructor(name) in PLACEHOLDER_INSTRUCTORS


def build_canonical_lookup(registry: Dict[str, Any]) -> Dict[str, str]:
    """Maps every normalized alias (and canonical name) to the normalized
    canonical name of its registry entry.

    Published in the feed as "instructorAliases" and used for each session's
    "instructorKey". Unregistered names are absent: their key is the
    normalized name itself.
    """
    lookup: Dict[str, str] = {}
    for rec in registry.values():
        canonical = normalize_instructor(rec.get("canonicalName", ""))
        if not canonical:
            continue
        names = {normalize_instructor(a) for a in rec.get("aliases", [])}
        names.add(canonical)
        for name in names:
            if name:
                lookup[name] = canonical
    return dict(sorted(lookup.items()))


def alias_registry_problems(registry: Dict[str, Any]) -> List[str]:
    """Returns human-readable problems that would make keys ambiguous.

    - an alias (or canonical name) listed under more than one entry, which
      build_canonical_lookup() would resolve by file order;
    - a chain, where an entry's canonical name is an alias of another entry;
    - a placeholder name registered as an alias.
    """
    problems: List[str] = []
    owners: Dict[str, set] = defaultdict(set)
    for entry_id, rec in registry.items():
        canonical = normalize_instructor(rec.get("canonicalName", ""))
        if not canonical:
            problems.append(f"{entry_id}: missing canonicalName")
        names = {normalize_instructor(a) for a in rec.get("aliases", [])}
        if canonical:
            names.add(canonical)
        for name in names:
            if name:
                owners[name].add(entry_id)
            if name in PLACEHOLDER_INSTRUCTORS:
                problems.append(f"{entry_id}: placeholder name {name!r} registered as an alias")
    for name, ids in sorted(owners.items()):
        if len(ids) > 1:
            problems.append(f"{name!r} is listed under several entries: {', '.join(sorted(ids))}")

    lookup = build_canonical_lookup(registry)
    for name, canonical in lookup.items():
        if lookup.get(canonical, canonical) != canonical:
            problems.append(
                f"chain: {name!r} -> {canonical!r} -> {lookup[canonical]!r}"
            )
    return problems
