"""Character cache: GUID keys, migration, alt queries and the /fp chars and /fp forget commands."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ALTS, Addon, lua_list, plain  # noqa: E402

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


B, C, D, E = "Player-1-0000000B", "Player-1-0000000C", "Player-1-0000000D", "Player-1-0000000E"


class OwnersTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.ns = self.a.ns

    def name(self, key):
        return self.ns.CharName(key)

    def owners(self, line, spell):
        o = self.ns.RecipeOwners(line, spell)
        known = lua_list(o.known)
        learnable = [(e.key, e.hint) for e in lua_list(o.learnable)]
        low = [(e.key, e.skill) for e in lua_list(o.low)]
        return known, learnable, low

    def test_list_order(self):
        names = [self.name(e.key) for e in lua_list(self.ns.ListChars())]
        self.assertEqual(names, ["Tester", "Banco", "Dru (Rogue)", "Dru (Druid)", "Paly"])

    def test_label_class_colour(self):
        label = self.ns.CharLabel(B)
        self.assertTrue(label.startswith("|c" + self.a.g.RAID_CLASS_COLORS.ROGUE.colorStr))
        self.assertEqual(plain(label), "Dru (Rogue)")

    def test_label_for_incomplete_record(self):
        a = logged_in(ALTS + '; ForeverProfessionalDB.chars["Player-1-00000010"] = { name = "Old" }')
        label = a.ns.CharLabel("Player-1-00000010")
        self.assertEqual(plain(label), "Old")
        self.assertTrue(label.startswith("|cffffffff"))
        o = a.ns.RecipeOwners(171, 7255)
        keys = lua_list(o.known) + [e.key for e in lua_list(o.learnable)] + [e.key for e in lua_list(o.low)]
        self.assertNotIn("Player-1-00000010", keys)

    def test_same_name_same_class_numbered(self):
        a = logged_in(ALTS + '; ForeverProfessionalDB.chars["Player-1-0000000G"] = '
                      '{ name = "Dru", class = "ROGUE", faction = "Horde", professions = {}, learned = {} }')
        self.assertEqual(a.ns.CharName(B), "Dru (Rogue)")
        self.assertEqual(a.ns.CharName("Player-1-0000000G"), "Dru (Rogue) 2")

    def test_owners_vendor_hint(self):
        known, learnable, low = self.owners(171, 1251753)
        self.assertEqual(known, [])
        self.assertEqual(learnable, [(B, None), (D, "(Horde vendors only)")])
        self.assertEqual(low, [(ME, 120), (C, 150)])

    def test_owners_known(self):
        known, learnable, low = self.owners(171, 7255)
        self.assertEqual(known, [B])
        self.assertEqual(learnable, [(ME, None), (C, None), (D, None)])
        self.assertEqual(low, [])

    def test_owners_side_locked(self):
        known, learnable, low = self.owners(185, 2795)
        self.assertEqual([k for k, _ in learnable], [D])
        self.assertNotIn(C, known + [k for k, _ in learnable] + [k for k, _ in low])

    def test_owners_nobody(self):
        self.assertEqual(self.owners(202, 23066), ([], [], []))


if __name__ == "__main__":
    unittest.main()
