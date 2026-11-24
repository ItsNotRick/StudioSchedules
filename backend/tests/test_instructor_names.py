"""Tests for instructor name helpers and the published alias map.

Run from the repo root:  python3 -m unittest discover -s backend/tests
"""

import json
import os
import sys
import unittest

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(BACKEND, "src"))

from instructor_names import (  # noqa: E402
    PLACEHOLDER_INSTRUCTORS,
    alias_registry_problems,
    build_canonical_lookup,
    is_placeholder_instructor,
    normalize_instructor,
)


def load(rel_path):
    with open(os.path.join(BACKEND, rel_path), encoding="utf-8") as f:
        return json.load(f)


class NormalizeInstructorTest(unittest.TestCase):
    def test_shared_fixture(self):
        # The same fixture is checked by the Dart normalizer.
        for raw, expected in load("tests/fixtures/instructor_names.json")["cases"]:
            with self.subTest(raw=raw):
                self.assertEqual(normalize_instructor(raw), expected)

    def test_placeholders_are_normalized(self):
        for p in PLACEHOLDER_INSTRUCTORS:
            self.assertEqual(normalize_instructor(p), p)
        self.assertTrue(is_placeholder_instructor("  STAFF "))
        self.assertTrue(is_placeholder_instructor("Guest Artist"))
        self.assertFalse(is_placeholder_instructor("Staffan Larsson"))


class CanonicalLookupTest(unittest.TestCase):
    def test_maps_aliases_and_canonical_to_canonical(self):
        reg = {
            "kathryn_sullivan": {
                "canonicalName": "Kathryn Sullivan",
                "aliases": ["Kathy Sullivan", "Kathryn  Sullivan"],
            }
        }
        self.assertEqual(
            build_canonical_lookup(reg),
            {"kathryn sullivan": "kathryn sullivan", "kathy sullivan": "kathryn sullivan"},
        )

    def test_entry_without_canonical_name_is_skipped(self):
        reg = {"x": {"canonicalName": "", "aliases": ["A B"]}}
        self.assertEqual(build_canonical_lookup(reg), {})

    def test_detects_alias_in_two_entries(self):
        reg = {
            "a": {"canonicalName": "Billy Bell", "aliases": ["Will Bell"]},
            "b": {"canonicalName": "Will B Bell", "aliases": ["Will Bell"]},
        }
        problems = alias_registry_problems(reg)
        self.assertTrue(any("'will bell' is listed under several entries" in p for p in problems), problems)

    def test_detects_placeholder_alias(self):
        reg = {"a": {"canonicalName": "Jo Doe", "aliases": ["Staff"]}}
        self.assertTrue(any("placeholder" in p for p in alias_registry_problems(reg)))

    def test_detects_missing_canonical_name(self):
        reg = {"a": {"aliases": ["Jo Doe"]}}
        self.assertTrue(any("missing canonicalName" in p for p in alias_registry_problems(reg)))


class RegistryTest(unittest.TestCase):
    """Invariants of the committed backend/data/instructors.json."""

    def setUp(self):
        self.registry = load("data/instructors.json")

    def test_registry_has_no_problems(self):
        self.assertEqual(alias_registry_problems(self.registry), [])

    def test_lookup_is_idempotent(self):
        lookup = build_canonical_lookup(self.registry)
        for name, canonical in lookup.items():
            with self.subTest(name=name):
                self.assertEqual(lookup.get(canonical, canonical), canonical)


class PublishedFeedTest(unittest.TestCase):
    """Checks the committed feed, if it was built with the alias map (v1.1+)."""

    def setUp(self):
        self.feed = load("data/schedule.json")
        if "instructorAliases" not in self.feed:
            self.skipTest("feed predates instructorAliases")

    def test_session_keys_match_alias_map(self):
        aliases = self.feed["instructorAliases"]
        for s in self.feed["sessions"]:
            norm = normalize_instructor(s["instructor"])
            with self.subTest(instructor=s["instructor"]):
                self.assertEqual(s["instructorKey"], aliases.get(norm, norm))

    def test_placeholders_published(self):
        self.assertEqual(self.feed["placeholderInstructors"], list(PLACEHOLDER_INSTRUCTORS))

    def test_app_asset_matches_backend_feed(self):
        asset = os.path.join(os.path.dirname(BACKEND), "app", "assets", "feed", "schedule.json")
        with open(asset, encoding="utf-8") as f:
            self.assertEqual(json.load(f), self.feed)


if __name__ == "__main__":
    unittest.main()
