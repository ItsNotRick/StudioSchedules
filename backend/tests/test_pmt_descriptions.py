import os
import sys
import unittest

SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

from scrapers.pmt_scraper import _parse_class_info, _parse_pmt_table  # noqa: E402

CLASS_INFO = (
    '<div class="classDescription"><h2>Description</h2>'
    '<img src="https://clients-content.mindbodyonline.com/x/2198.jpg" alt="Adv. Beg. Hip Hop" class="classInfoImg"/>'
    '<div class="userHTML"><div>This class will explore the fundamentals of Hip Hop &amp; groove.</div> '
    '<div>&nbsp;</div><div>This class requires minimum of 1.5-3 years of experience</div></div>'
)

SCHEDULE = """
<div id="classSchedule-mainTable">
  <div class="header"><b><span>Monday</span> November 23, 2026</b></div>
  <div class="evenRow row"><div class="col-1"><div class="col col-first">6:00&nbsp;pm EST</div><div class="col"></div></div>
    <div class="col-2"><div class="col"><a href="javascript:;" name="cid2198" class="modalClassDesc">Adv. Beg. Hip Hop</a></div>
    <div class="col"><a href="javascript:;" name="bio9" class="modalBio" >Rich James</a></div>
    <div class="col">1 hour &30 minutes</div></div></div>
</div>
"""


class PmtClassDescriptionTests(unittest.TestCase):
    def test_class_info_text_keeps_paragraphs(self):
        self.assertEqual(_parse_class_info(CLASS_INFO), "\n".join([
            "This class will explore the fundamentals of Hip Hop & groove.",
            "This class requires minimum of 1.5-3 years of experience",
        ]))

    def test_placeholder_or_missing_text_gives_none(self):
        self.assertIsNone(_parse_class_info('<div class="userHTML"><div>-</div></div>'))
        self.assertIsNone(_parse_class_info('<div class="userHTML"></div>'))
        self.assertIsNone(_parse_class_info("<html>sign in</html>"))

    def test_schedule_row_records_its_class_id(self):
        (session,) = _parse_pmt_table(SCHEDULE, set())
        self.assertEqual(session["classInfoId"], "2198")
        self.assertEqual(session["rawClassTitle"], "Adv. Beg. Hip Hop")


if __name__ == "__main__":
    unittest.main()
