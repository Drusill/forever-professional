"""ForeverProfessional addon tests: python -m unittest discover tests"""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, addon_files, toc_metadata, lua_list  # noqa: E402


class TocTest(unittest.TestCase):
    def test_metadata(self):
        meta = toc_metadata()
        self.assertEqual(meta["Interface"], ["16001"])
        self.assertTrue(meta["SavedVariables"][0].startswith("ForeverProfessionalDB "))
        self.assertIn("[AllowLoadGameType camelot]", meta["SavedVariables"][0])

    def test_files_exist(self):
        files = addon_files()
        self.assertTrue(any(f.name == "Professions.lua" for f in files))
        for f in files:
            self.assertTrue(f.is_file(), f"missing {f}")


class LoadTest(unittest.TestCase):
    def test_loads_with_real_data(self):
        a = Addon()
        profs = a.ns.Data.Professions
        self.assertEqual(len(list(profs.keys())), 12)
        self.assertGreater(len(list(a.ns.Data.Recipes[171].keys())), 100)
        self.assertIsNone(a.ns.Data.Locale)  # enUS client: no locale table

    def test_locale_table_on_non_english_client(self):
        a = Addon(locale="deDE")
        self.assertIsNotNone(a.ns.Data.Locale.npc)

    def test_db_initialised_on_addon_loaded(self):
        a = Addon()
        a.login()
        db = a.g.ForeverProfessionalDB
        self.assertEqual(db.version, 1)
        self.assertEqual(db.filter, "all")

    def test_db_keeps_existing_values(self):
        a = Addon(setup='ForeverProfessionalDB = { filter = "missing", collapsed = { [2449] = true } }')
        a.login()
        self.assertEqual(a.g.ForeverProfessionalDB.filter, "missing")
        self.assertTrue(a.g.ForeverProfessionalDB.collapsed[2449])

    def test_player_professions(self):
        a = Addon()
        profs, order = a.ns.GetPlayerProfessions()
        self.assertEqual(lua_list(order), [171, 182])
        self.assertEqual(profs[171].skill, 120)

    def test_child_line_maps_to_root(self):
        a = Addon()
        self.assertEqual(a.ns.RootLine(2937), 171)
        self.assertEqual(a.ns.RootLine(171), 171)
        self.assertIsNone(a.ns.RootLine(999999))

    def test_find_profession(self):
        a = Addon()
        self.assertEqual(a.ns.FindProfession("alch"), 171)
        self.assertEqual(a.ns.FindProfession("Cooking"), 185)
        self.assertIsNone(a.ns.FindProfession("zzz"))


if __name__ == "__main__":
    unittest.main()
