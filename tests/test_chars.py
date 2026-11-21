"""Character cache: GUID keys, migration, alt queries and the /fp chars and /fp forget commands."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ALTS, Addon, plain  # noqa: E402

ME = "Player-1-0000000A"


def logged_in(setup=ALTS):
    a = Addon(setup=setup)
    a.login()
    return a


class KeyTest(unittest.TestCase):
    def test_key_is_guid(self):
        a = logged_in(None)
        self.assertEqual(a.ns.CharKey(), ME)
        c = a.g.ForeverProfessionalDB.chars[ME]
        self.assertEqual(c.guid, ME)
        self.assertEqual(c.name, "Tester")
        self.assertEqual(c.level, 60)

    def test_same_name_kept_apart(self):
        a = logged_in()
        a.run('mock.guid = "Player-1-0000000F"; fire("PLAYER_LOGIN"); flush()')
        chars = a.g.ForeverProfessionalDB.chars
        self.assertEqual(chars[ME].name, "Tester")
        self.assertEqual(chars["Player-1-0000000F"].name, "Tester")

    def test_migration_drops_name_keys(self):
        a = logged_in('ForeverProfessionalDB = { version = 1, chars = { '
                      '["-Dru"] = { name = "Dru", learned = {}, professions = {} }, '
                      '["Realm-Tester"] = { name = "Tester", learned = {}, professions = {} }, '
                      '["CAMWOW US2 Realm 8 PvP-Salvador"] = { name = "Salvador", learned = {}, professions = {} } } }')
        db = a.g.ForeverProfessionalDB
        self.assertEqual(list(db.chars.keys()), [ME])
        self.assertEqual(db.version, 2)

    def test_migration_runs_once(self):
        a = logged_in()
        keys = sorted(a.g.ForeverProfessionalDB.chars.keys())
        self.assertEqual(keys, [ME, "Player-1-0000000B", "Player-1-0000000C", "Player-1-0000000D", "Player-1-0000000E"])

    def test_no_guid_no_record(self):
        a = Addon(setup="mock.guid = nil")
        a.run('fire("ADDON_LOADED", "ForeverProfessional")')
        self.assertIsNone(a.ns.CharKey())
        self.assertFalse(a.ns.IsLearned(2329))
        self.assertEqual(a.ns.CharSkill(171), (None, None))
        self.assertEqual(list(a.g.ForeverProfessionalDB.chars.keys()), [])


if __name__ == "__main__":
    unittest.main()
