import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from unittest import mock

SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import build_feed  # noqa: E402
from scrapers.danznik_scraper import _parse_sessions  # noqa: E402

WIDGET_MARKUP = """
<div class="bw-session" id="39227368" data-bw-widget-mbo-class-name="midtown_swings_lindy_100">
 <div class="bw-session__basics"><div class="bw-session__info">
  <time class="hc_starttime" datetime="2026-12-01T20:00"> 8:00 PM</time>
  <time class="hc_endtime" datetime="2026-12-01T21:00"> 9:00 PM</time>
  <div class="bw-session__name"><span class="bw-session__type" style="display: none;">Swing / Lindy Hop - </span>Midtown Swings - Lindy 100 </div>
  <div class="bw-session__level" style="">Beginner</div>
  <div class="bw-session__staff" style=""> AJ Howard </div>
 </div></div>
 <div class="bw-session__details"><div class="bw-session__expanded">
  <div class="bw-session__description" data-more="More" style="">
   <div><strong>Lindy Hop with Gaby &amp; AJ</strong><br>Level: Beginner (100)</div><div>&nbsp;</div>
   <p>Perfect for beginners.</p>
   <ul><li>6-count</li><li>8-count</li></ul>
   <p><strong>PRICING</strong></p><div>$30 drop-in</div><div>Members get 20% off</div>
   <div>---</div>
   <p>WHAT IS LINDY HOP?</p><p>The original swing dance.</p>
   <p>*DanzPass Eligible*</p>
  </div>
 </div></div>
</div>
<div class="bw-session" id="39227369">
 <time class="hc_starttime" datetime="2026-12-01T21:00"> 9:00 PM</time>
 <time class="hc_endtime" datetime="2026-12-01T23:00"> 11:00 PM</time>
 <div class="bw-session__name">Midtown Swings Social</div>
 <div class="bw-session__staff" style=""> Midtown Swings </div>
 <div class="bw-session__details"><div class="bw-session__expanded">
  <div class="bw-session__description" style=""> </div>
 </div></div>
</div>
"""


class DanznikWidgetDescriptionTests(unittest.TestCase):
    def test_description_keeps_lines_and_drops_pricing_and_danzpass(self):
        lindy, social = _parse_sessions(WIDGET_MARKUP, set())
        self.assertEqual(lindy["classDescription"], "\n".join([
            "Lindy Hop with Gaby & AJ",
            "Level: Beginner (100)",
            "Perfect for beginners.",
            "• 6-count",
            "• 8-count",
            "WHAT IS LINDY HOP?",
            "The original swing dance.",
        ]))
        self.assertNotIn("classDescription", social)


LONG_CLASS_TEXT = (
    "Perfect for beginners, the Lindy 100 course will provide you with the basic "
    "fundamentals of swing, rotating through 6-count, 8-count and Charleston."
)


class StudioClassDescriptionFeedTests(unittest.TestCase):
    def build(self, danznik_sessions=None, danznik_error=None, cached_sessions=()):
        now_ny = datetime.now(build_feed.NY_TZ)
        self.date = (now_ny - timedelta(days=now_ny.weekday())).strftime("%Y-%m-%d")
        with tempfile.TemporaryDirectory() as tmpdir:
            data_dir = os.path.join(tmpdir, "data")
            src_dir = os.path.join(tmpdir, "src")
            os.makedirs(data_dir)
            os.makedirs(src_dir)
            files = {
                "templates.json": {"templates": [], "series": []},
                "studios.json": {"studios": []},
                "instructor_descriptions.json": {
                    "bdc": {"aj howard": {"default": "AJ's BDC teacher blurb."}},
                },
                "schedule.json": {"templates": [], "sessions": [
                    {**c, "serviceDate": self.date} for c in cached_sessions
                ]},
            }
            for name, content in files.items():
                with open(os.path.join(data_dir, name), "w", encoding="utf-8") as f:
                    json.dump(content, f)

            danznik = (
                mock.patch.object(build_feed, "scrape_danznik_schedule", side_effect=danznik_error)
                if danznik_error else
                mock.patch.object(build_feed, "scrape_danznik_schedule", return_value=[
                    {**s, "serviceDate": self.date} for s in danznik_sessions
                ])
            )
            with (
                mock.patch.object(build_feed, "__file__", os.path.join(src_dir, "build_feed.py")),
                mock.patch.object(build_feed, "scrape_bdc_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_steps_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_ailey_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_peridance_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_pmt_schedule", return_value=[]),
                danznik,
            ):
                feed, _ = build_feed.generate_live_feed()
        return {s["id"]: s for s in feed["sessions"]}

    def session(self, sid, **extra):
        return {
            "id": sid, "studioId": "danznik", "rawClassTitle": "Midtown Swings - Lindy 100",
            "startMin": 1200, "endMin": 1260, "instructor": "AJ Howard", **extra,
        }

    def test_studio_class_description_beats_teacher_blurb(self):
        sessions = self.build(danznik_sessions=[
            self.session("with_text", classDescription=LONG_CLASS_TEXT),
            self.session("without_text"),
        ])
        self.assertEqual(sessions["with_text"]["description"], LONG_CLASS_TEXT)
        # No class text from the studio: the teacher's blurb is still used.
        self.assertEqual(sessions["without_text"]["description"], "AJ's BDC teacher blurb.")

    def test_short_class_note_yields_to_teacher_blurb_but_fills_gaps(self):
        note = "All levels welcome. Pace may vary depending on the flow of the class."
        sessions = self.build(danznik_sessions=[
            self.session("with_teacher", classDescription=note),
            self.session("no_teacher", classDescription=note, instructor="Big Mike"),
        ])
        self.assertEqual(sessions["with_teacher"]["description"], "AJ's BDC teacher blurb.")
        self.assertEqual(sessions["no_teacher"]["description"], note)

    def test_cached_description_survives_failed_scrape(self):
        sessions = self.build(
            danznik_error=RuntimeError("down"),
            cached_sessions=[{
                **self.session("cached"), "templateId": "danznik_lindy",
                "description": LONG_CLASS_TEXT,
            }],
        )
        self.assertEqual(sessions["cached"]["description"], LONG_CLASS_TEXT)


if __name__ == "__main__":
    unittest.main()
