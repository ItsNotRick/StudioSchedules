import json
import os
import sys
import tempfile
import unittest
from unittest import mock

SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import extract_teacher_descriptions as etd  # noqa: E402

FACULTY_PAGE = """
<html><head><title>Oren Korenblum - Steps on Broadway</title></head><body>
<nav>Classes Daily Schedule</nav>
<article id="post-50259">
 <div>
  <p class="wp-block-paragraph">Oren Korenblum is an award-winning choreographer.</p>
  <p class="wp-block-paragraph"><strong>Class Description</strong><br>Oren&#8217;s tap classes are fun.<br>
  He breaks combinations down.</p>
  <p class="wp-block-paragraph">In Oren&#8217;s Theatre Jazz class, you&#8217;ll train in jazz technique.</p>
 </div><!-- /end content grid right side-->
 <div><script>var x = "Class Description";</script><healcode-widget></healcode-widget></div>
</article>
<footer>Carol Paumgarten, Co-Founder</footer>
</body></html>
"""

BIO_ONLY_PAGE = """
<html><head><title>Fabrice Herrault - Steps on Broadway</title></head><body>
<article><div><p>Fabrice trained at the Paris Opera Ballet School.</p></div>
<!-- /end content grid right side--></article>
<footer>Class Descriptions</footer></body></html>
"""


class StepsFacultyPageTests(unittest.TestCase):
    def test_takes_text_after_class_description_label(self):
        self.assertEqual(etd.parse_steps_class_description(FACULTY_PAGE), "\n".join([
            "Oren’s tap classes are fun.",
            "He breaks combinations down.",
            "In Oren’s Theatre Jazz class, you’ll train in jazz technique.",
        ]))
        self.assertEqual(etd._steps_page_name(FACULTY_PAGE, "oren-korenblum"), "Oren Korenblum")

    def test_bio_without_class_description_gives_none(self):
        # "Class Descriptions" outside the bio (footer, scripts) must not count.
        self.assertIsNone(etd.parse_steps_class_description(BIO_ONLY_PAGE))


class ExtractorMainTests(unittest.TestCase):
    def run_main(self, argv, existing, scraped):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "instructor_descriptions.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(existing, f)
            scrapers = {st: mock.Mock(return_value=scraped.get(st, {})) for st in etd.SCRAPERS}
            with (
                mock.patch.object(etd, "DATA_PATH", path),
                mock.patch.dict(etd.SCRAPERS, scrapers),
                mock.patch("builtins.print"),
            ):
                etd.main(argv)
            with open(path, encoding="utf-8") as f:
                return json.load(f), scrapers

    def test_named_studio_is_refreshed_and_others_kept(self):
        data, scrapers = self.run_main(
            ["steps"],
            existing={"bdc": {"a": {"default": "BDC text"}}, "steps": {"old": {"default": "x"}}},
            scraped={"steps": {"oren korenblum": {"default": "Tap"}}},
        )
        self.assertEqual(data["bdc"], {"a": {"default": "BDC text"}})
        self.assertEqual(data["steps"], {"oren korenblum": {"default": "Tap"}})
        scrapers["bdc"].assert_not_called()

    def test_empty_crawl_keeps_existing_entries(self):
        # e.g. BDC behind a Cloudflare challenge returns nothing.
        data, _ = self.run_main(
            ["bdc"],
            existing={"bdc": {"a": {"default": "BDC text"}}},
            scraped={},
        )
        self.assertEqual(data["bdc"], {"a": {"default": "BDC text"}})

    def test_unknown_studio_is_rejected(self):
        with self.assertRaises(SystemExit):
            etd.main(["stpes"])


if __name__ == "__main__":
    unittest.main()
