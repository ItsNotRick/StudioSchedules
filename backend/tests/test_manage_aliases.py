import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

import manage_aliases  # noqa: E402

PUBLISHED = {"generatedAt": "today", "sessions": [
    {"studioId": "steps", "instructor": "Kat Ponza"},
    {"studioId": "steps", "instructor": "Staff"},
]}
LOCAL = {"generatedAt": "last week", "sessions": [
    {"studioId": "steps", "instructor": "Old Name"},
]}


class ScheduleSourceTests(unittest.TestCase):
    def setUp(self):
        manage_aliases._schedule_cache.clear()
        self.tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        json.dump(LOCAL, self.tmp)
        self.tmp.close()
        self.patches = [
            mock.patch.object(manage_aliases, "SCHEDULE_PATH", self.tmp.name),
            mock.patch("builtins.print"),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        os.unlink(self.tmp.name)
        manage_aliases._schedule_cache.clear()

    def test_names_come_from_the_published_feed(self):
        resp = io.BytesIO(json.dumps(PUBLISHED).encode())
        with mock.patch("urllib.request.urlopen", return_value=resp):
            names = manage_aliases.harvest_schedule_names()
        self.assertEqual(names, {"Kat Ponza": {"steps"}})

    def test_falls_back_to_local_schedule_when_offline(self):
        with mock.patch("urllib.request.urlopen", side_effect=OSError("offline")):
            names = manage_aliases.harvest_schedule_names()
        self.assertEqual(names, {"Old Name": {"steps"}})


if __name__ == "__main__":
    unittest.main()
