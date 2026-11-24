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
from scrapers.mindbody_widget import parse_mindbody_widget_sessions  # noqa: E402
from scrapers.pmt_scraper import _parse_pmt_table  # noqa: E402


class MindbodyWidgetTests(unittest.TestCase):
    def test_parses_escaped_quotes_cancelled_and_staff_refs(self):
        flight_payload = "\n".join([
            '1a:{"id":"staff_99","displayLabel":"Elena Vance (sub)"}',
            json.dumps({
                "id": "cinst_1001",
                "name": 'In-Studio Hip Hop "Grooves"',
                "startDateTime": "2026-11-24T18:00:00Z",
                "duration": 60,
                "cancelled": False,
                "staff": ["$1a"],
            }),
            json.dumps({
                "id": "cinst_1002",
                "name": 'In-Studio Ballet "Foundations"',
                "description": "Line 1\nLine 2",
                "startDateTime": "2026-11-24T19:00:00Z",
                "duration": 90,
                "cancelled": True,
                "staff": [{"id": "staff_2", "displayLabel": 'Paolo "Slice" Penala'}],
            }),
            json.dumps({
                "id": "cinst_1003",
                "name": "Virtual 60 Ballet",
                "startDateTime": "2026-11-24T20:00:00Z",
                "duration": 60,
                "cancelled": False,
                "displayLabel": "Virtual Teacher",
            }),
            json.dumps({
                "id": "cinst_1004",
                "name": "Livestream Beginner Jazz",
                "startDateTime": "2026-11-24T21:00:00Z",
                "duration": 60,
                "cancelled": False,
                "displayLabel": "Stream Teacher",
            }),
        ])
        html = f"<script>self.__next_f.push([1,{json.dumps(flight_payload)}])</script>"

        steps_sessions = parse_mindbody_widget_sessions(
            html,
            studio_id="steps",
            id_prefix="steps",
            booking_url="https://www.stepsnyc.com/classes/schedule/",
            exclude_virtual=True,
            strip_in_studio_prefix=True,
        )
        self.assertEqual(len(steps_sessions), 2)

        first, second = steps_sessions
        self.assertEqual(first["rawClassTitle"], 'Hip Hop "Grooves"')
        self.assertEqual(first["instructor"], "Elena Vance")
        self.assertTrue(first["isSubstitute"])
        self.assertEqual(first["status"], "scheduled")

        self.assertEqual(second["rawClassTitle"], 'Ballet "Foundations"')
        self.assertEqual(second["instructor"], 'Paolo "Slice" Penala')
        self.assertEqual(second["status"], "cancelled")

    def test_resolves_staff_row_that_follows_a_text_row(self):
        # Text rows ("<id>:T<hexByteLen>,<bytes>") have no trailing newline, so
        # the next row starts on the same line. Multi-byte characters check
        # that the length is counted in UTF-8 bytes, not characters.
        bio = "<p>Ève-Marie trained in Montréal.\nMore bio…</p></div>"
        text_row = f"2b:T{len(bio.encode('utf-8')):x},{bio}"
        staff_row = '47:' + json.dumps(
            {"id": "sspec_47", "displayLabel": "Christa Thiesing"}
        )
        session = json.dumps({
            "id": "cinst_3001",
            "name": "In-Studio Gyrokinesis",
            "startDateTime": "2026-11-24T18:00:00Z",
            "duration": 60,
            "cancelled": False,
            "staff": ["$47"],
        })
        flight_payload = f"{text_row}{staff_row}\n5:{session}\n"
        # Split across pushes mid-row, as the live widget does.
        cut = len(text_row) + 10
        html = (
            f"<script>self.__next_f.push([1,{json.dumps(flight_payload[:cut])}])</script>"
            f"<script>self.__next_f.push([1,{json.dumps(flight_payload[cut:])}])</script>"
        )

        sessions = parse_mindbody_widget_sessions(
            html,
            studio_id="steps",
            id_prefix="steps",
            booking_url="https://www.stepsnyc.com/classes/schedule/",
            exclude_virtual=True,
            strip_in_studio_prefix=True,
        )
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["rawClassTitle"], "Gyrokinesis")
        self.assertEqual(sessions[0]["instructor"], "Christa Thiesing")

    def test_peridance_strips_trailing_underscore_and_keeps_cancelled(self):
        flight_payload = "\n".join([
            json.dumps({
                "id": "cinst_2001",
                "name": "Open House",
                "startDateTime": "2026-11-25T17:00:00Z",
                "duration": 90,
                "cancelled": True,
                "displayLabel": "Hurrikane _",
            }),
        ])
        html = f"<script>self.__next_f.push([1,{json.dumps(flight_payload)}])</script>"

        sessions = parse_mindbody_widget_sessions(
            html,
            studio_id="peridance",
            id_prefix="peri",
            booking_url="https://www.peridance.com/open-classes",
        )
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["instructor"], "Hurrikane")
        self.assertEqual(sessions[0]["status"], "cancelled")


class PmtParserTests(unittest.TestCase):
    def test_cancelled_today_preserves_regular_teacher_and_strips_dot(self):
        html = """
        <div id="classSchedule-mainTable">
          <div class="header"><b><span>Thursday</span> November 26, 2026</b></div>
          <div class="evenRow row">
            <div class="col-1"><div class="col col-first"><s>6:00&nbsp;pm  EST</s></div></div>
            <div class="col-2">
              <div class="col"><a title="Regularly Scheduled: Shirlene Quigley .">Adv. Beg. Jazz</a></div>
              <div class="col"><span style="color:#990000;">Cancelled Today</span></div>
              <div class="col">1 hour &30 minutes</div>
            </div>
          </div></div></div>
          <div class="oddRow row">
            <div class="col-1"><div class="col col-first">7:30 pm</div></div>
            <div class="col-2">
              <div class="col">Open Level House Drills</div>
              <div class="col"><span style="color:#990000;">Jungle .</span> <span class="smallTextBlack"><a title="Regularly ScheduledPavan Thimmaiah">(1)</a></span></div>
              <div class="col">2 hours &amp; 30 min</div>
            </div>
          </div></div></div>
        </div>
        """
        sessions = _parse_pmt_table(html, set())
        self.assertEqual(len(sessions), 2)

        cancelled = sessions[0]
        self.assertEqual(cancelled["status"], "cancelled")
        self.assertFalse(cancelled["isSubstitute"])
        self.assertEqual(cancelled["instructor"], "Staff")
        self.assertEqual(cancelled["endMin"] - cancelled["startMin"], 90)

        normal = sessions[1]
        self.assertEqual(normal["status"], "scheduled")
        self.assertTrue(normal["isSubstitute"])
        self.assertEqual(normal["instructor"], "Jungle")
        self.assertEqual(normal["regularInstructor"], "Pavan Thimmaiah")
        self.assertEqual(normal["endMin"] - normal["startMin"], 150)


class BuildFeedTests(unittest.TestCase):
    def test_same_title_different_tiers_get_separate_templates(self):
        tpl_lookup = {}
        beg_id = build_feed.auto_template_id(
            "danznik", "social", "beginner", "West Coast Swing", tpl_lookup
        )
        tpl_lookup[beg_id] = {
            "id": beg_id,
            "studioId": "danznik",
            "title": "West Coast Swing",
            "tier": "beginner",
        }
        int_id = build_feed.auto_template_id(
            "danznik", "social", "intermediate", "West Coast Swing", tpl_lookup
        )
        self.assertNotEqual(beg_id, int_id)

    def test_cache_fallback_excludes_expired_sessions_from_stats(self):
        now_ny = datetime.now(build_feed.NY_TZ)
        cur_monday = now_ny - timedelta(days=now_ny.weekday())
        in_window_date = cur_monday.strftime("%Y-%m-%d")
        expired_date = (cur_monday - timedelta(days=14)).strftime("%Y-%m-%d")

        with tempfile.TemporaryDirectory() as tmpdir:
            data_dir = os.path.join(tmpdir, "data")
            src_dir = os.path.join(tmpdir, "src")
            os.makedirs(data_dir)
            os.makedirs(src_dir)

            with open(os.path.join(data_dir, "templates.json"), "w", encoding="utf-8") as f:
                json.dump({"templates": [], "series": []}, f)
            with open(os.path.join(data_dir, "studios.json"), "w", encoding="utf-8") as f:
                json.dump({"studios": []}, f)
            with open(os.path.join(data_dir, "schedule.json"), "w", encoding="utf-8") as f:
                json.dump({
                    "templates": [],
                    "sessions": [
                        {
                            "id": "pmt_in_window",
                            "templateId": "pmt_jazz",
                            "studioId": "pmt",
                            "rawClassTitle": "Beg Jazz",
                            "serviceDate": in_window_date,
                            "startMin": 600,
                            "endMin": 690,
                            "instructor": "Shirlene Quigley",
                            "status": "cancelled",
                        },
                        {
                            "id": "pmt_expired",
                            "templateId": "pmt_jazz",
                            "studioId": "pmt",
                            "rawClassTitle": "Beg Jazz",
                            "serviceDate": expired_date,
                            "startMin": 600,
                            "endMin": 690,
                            "instructor": "Shirlene Quigley",
                            "status": "scheduled",
                        },
                    ],
                }, f)

            fake_build_file = os.path.join(src_dir, "build_feed.py")
            with (
                mock.patch.object(build_feed, "__file__", fake_build_file),
                mock.patch.object(build_feed, "scrape_bdc_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_steps_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_ailey_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_peridance_schedule", return_value=[]),
                mock.patch.object(build_feed, "scrape_pmt_schedule", side_effect=RuntimeError("down")),
                mock.patch.object(build_feed, "scrape_danznik_schedule", return_value=[]),
            ):
                feed, _ = build_feed.generate_live_feed()

        self.assertEqual(feed["scraperStats"]["pmt"], 1)
        self.assertEqual(len(feed["sessions"]), 1)
        self.assertEqual(feed["sessions"][0]["id"], "pmt_in_window")
        self.assertEqual(feed["sessions"][0]["status"], "cancelled")


if __name__ == "__main__":
    unittest.main()
