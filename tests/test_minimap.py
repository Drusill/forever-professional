"""Minimap button, /fp minimap and the addon compartment entry."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon  # noqa: E402


class SavedDefaultsTest(unittest.TestCase):
    def test_existing_save_gets_minimap_defaults(self):
        a = Addon(setup='ForeverProfessionalDB = { version = 1, filter = "learned" }')
        a.login()
        db = a.g.ForeverProfessionalDB
        self.assertEqual(db.minimapAngle, 225)
        self.assertIs(db.minimapHidden, False)
        self.assertEqual(db.filter, "learned")


if __name__ == "__main__":
    unittest.main()
