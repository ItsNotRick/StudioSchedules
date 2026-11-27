import json
import os
import sys
import tempfile
import unittest

SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import build_feed  # noqa: E402
from extract_ailey_techniques import (  # noqa: E402
    parse_technique_description,
    parse_technique_index,
)

INDEX_HTML = """
<a class="CardMedia_mediaLink" href="/classes/techniques/dunham"><picture></picture></a>
<a aria-label="Dunham" target="_self" href="/classes/techniques/dunham"><h4 class="LinkCard_title__x">Dunham</h4></a>
<a aria-label="Afro&#x27;Dance" href="/classes/techniques/afrodance"><h4 class="LinkCard_title__x">Afro&#x27;Dance</h4></a>
<a aria-label="Dunham" href="/classes/techniques/dunham"><h4 class="LinkCard_title__x">Dunham</h4></a>
"""

TECHNIQUE_HTML = """
<div class="SliceBody_body__a"><h3>Instructors</h3><p>Marcea Daiter</p></div>
<div class="SliceBody_body__b"><h2>Afro-Brazilian Dance</h2><p>Afro-Brazilian dance is
full of <em>soulful</em> movement.</p><div><p>Second paragraph.</p></div>
<p>Our classes are defined by the following so you can determine which level is best.</p></div>
<div class="SliceBody_body__c"><p>Every donation to AILEY furthers the vision.</p></div>
"""


class AileyTechniqueExtractorTests(unittest.TestCase):
    def test_index_lists_each_technique_once_with_decoded_name(self):
        self.assertEqual(parse_technique_index(INDEX_HTML), [
            {"slug": "dunham", "name": "Dunham"},
            {"slug": "afrodance", "name": "Afro'Dance"},
        ])

    def test_description_skips_instructors_heading_and_level_guide(self):
        self.assertEqual(
            parse_technique_description(TECHNIQUE_HTML, "Afro-Brazilian Dance"),
            "Afro-Brazilian dance is full of soulful movement. Second paragraph.",
        )


class AileyTechniqueMatchTests(unittest.TestCase):
    def setUp(self):
        techniques = [
            {"name": "Contemporary", "description": "CONTEMPORARY"},
            {"name": "Contemporary Indian Dance", "description": "CONTEMPORARY INDIAN"},
            {"name": "Hip Hop", "description": "HIP HOP"},
            {"name": "Hip Hop Cardio", "description": "HIP HOP CARDIO"},
            {"name": "Limón", "description": "LIMON"},
            {"name": "Afro-Cuban Dance", "description": "AFRO-CUBAN"},
            {"name": "Afro'Dance", "description": "AFRODANCE"},
            {"name": "Cuban Modern Dance Technique", "description": "CUBAN MODERN"},
            {"name": "Zumba®", "description": "ZUMBA"},
            {"name": "Pilates", "description": "PILATES"},
        ]
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
            json.dump({"techniques": techniques}, f)
            self.path = f.name
        self.index = build_feed.load_ailey_techniques(self.path)

    def tearDown(self):
        os.unlink(self.path)

    def match(self, title):
        return build_feed.match_ailey_technique(title, self.index)

    def test_longest_technique_name_wins(self):
        self.assertEqual(self.match("Open Contemporary Indian"), "CONTEMPORARY INDIAN")
        self.assertEqual(self.match("Hip Hop Cardio"), "HIP HOP CARDIO")
        self.assertEqual(self.match("Beg Cuban Modern Dance"), "CUBAN MODERN")
        self.assertEqual(self.match("Open Afro-Cuban Folkloric"), "AFRO-CUBAN")

    def test_spelling_variants_match(self):
        self.assertEqual(self.match("Beg Limon"), "LIMON")
        self.assertEqual(self.match("Ages 9-11 Hip-Hop for Kids"), "HIP HOP")
        self.assertEqual(self.match("Beg Afro’Dance"), "AFRODANCE")
        self.assertEqual(self.match("Zumba®"), "ZUMBA")
        self.assertEqual(self.match("Romana’s Mat Pilates"), "PILATES")

    def test_unknown_technique_gets_no_description(self):
        self.assertEqual(self.match("Ages 2-3 Tiny Steps 1A"), "")
        self.assertEqual(self.match("Beg Contemporaryish"), "")

    def test_other_studios_get_no_style_description(self):
        self.assertEqual(build_feed.get_generic_studio_description("bdc", "Beg Horton", "x"), "")


if __name__ == "__main__":
    unittest.main()
