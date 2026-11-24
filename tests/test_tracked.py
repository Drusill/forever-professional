"""Tracked recipes: the saved list and its combined plan in Characters.lua, plan shares in Model.lua, the craft
countdown, tooltip lines, the detail action row, tracking from the calculator and the Tracked panel."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list, plain  # noqa: E402
from test_calculator import CALC, LINES, MINA, seed  # noqa: E402,F401


def track(a, spell, qty=1, unit="crafts"):
    a.ns.TrackRecipe(LINES[spell], spell, qty, unit)


def tracked(a):
    return [(e.spellID, e.line, e.quantity, e.unit) for e in lua_list(a.ns.TrackedList())]


def item(p, item_id):
    return p["items"][item_id]


def first_enchant_without_output(a):
    recipes = a.ns.Data.Recipes[333]
    return min(spell for spell in recipes.keys() if recipes[spell].creates is None)


class Base(unittest.TestCase):
    setup = CALC

    def setUp(self):
        self.a = Addon(setup=self.setup)
        self.a.login()
        seed(self.a)
        self.ns = self.a.ns
        self.M = self.ns.Model


class TrackedListTest(Base):
    def test_empty_by_default(self):
        self.assertEqual(tracked(self.a), [])
        self.assertEqual(self.a.lua.eval("type")(self.ns.db.tracked), "table")

    def test_track_adds_in_order(self):
        track(self.a, 3932)
        track(self.a, 3938, 2)
        self.assertEqual(tracked(self.a), [(3932, 202, 1, "crafts"), (3938, 202, 2, "crafts")])

    def test_track_existing_updates_in_place(self):
        track(self.a, 3932)
        track(self.a, 3938)
        track(self.a, 3932, 5)
        self.assertEqual(tracked(self.a), [(3932, 202, 5, "crafts"), (3938, 202, 1, "crafts")])

    def test_untrack(self):
        track(self.a, 3932)
        track(self.a, 3938)
        self.ns.UntrackRecipe(3932)
        self.assertEqual(tracked(self.a), [(3938, 202, 1, "crafts")])
        self.ns.UntrackRecipe(3926)
        self.assertEqual(tracked(self.a), [(3938, 202, 1, "crafts")])

    def test_set_quantity(self):
        track(self.a, 3932)
        self.ns.SetTrackedQuantity(3932, 7)
        self.assertEqual(self.ns.GetTracked(3932).quantity, 7)
        self.ns.SetTrackedQuantity(3932, 1000)
        self.assertEqual(self.ns.GetTracked(3932).quantity, 999)
        self.ns.SetTrackedQuantity(3932, 0)
        self.assertIsNone(self.ns.GetTracked(3932))

    def test_units(self):
        track(self.a, 2659, 6, "items")
        track(self.a, 3932, 4, "items")
        track(self.a, 3931, 2, "items")
        self.assertEqual(tracked(self.a), [(2659, 186, 6, "items"), (3932, 202, 4, "crafts"),
                                           (3931, 202, 2, "items")])
        self.ns.SetTrackedUnit(2659, "crafts")
        self.assertEqual((self.ns.GetTracked(2659).quantity, self.ns.GetTracked(2659).unit), (6, "crafts"))

    def test_makes_several(self):
        recipes = self.ns.Data.Recipes
        self.assertFalse(self.M.MakesSeveral(recipes[202][3932]))
        self.assertTrue(self.M.MakesSeveral(recipes[186][2659]))
        self.assertTrue(self.M.MakesSeveral(recipes[202][3931]))
        self.assertFalse(self.M.MakesSeveral(recipes[333][first_enchant_without_output(self.a)]))

    BAD = CALC + """ForeverProfessionalDB.tracked = { "junk", { spellID = 999999, line = 202, quantity = 1 },
        { spellID = 3932, line = 202, quantity = "x" }, { spellID = 3938, line = 202, quantity = 2, unit = "bogus" } }"""

    def test_bad_saved_entries_skipped(self):
        a = Addon(setup=self.BAD)
        a.run('fire("ADDON_LOADED", "ForeverProfessional")')
        self.assertEqual(tracked(a), [(3938, 202, 2, "crafts")])

    def test_pruned_at_login(self):
        a = Addon(setup=self.BAD)
        a.login()
        saved = lua_list(a.ns.db.tracked)
        self.assertEqual(len(saved), 1)
        self.assertEqual((saved[0].spellID, saved[0].quantity), (3938, 2))

    def test_saved_across_reload(self):
        a = Addon(setup=CALC + "ForeverProfessionalDB.tracked = { { spellID = 2659, line = 186, quantity = 6, unit = 'items' } }")
        a.login()
        self.assertEqual(tracked(a), [(2659, 186, 6, "items")])

    def test_tracked_text(self):
        text = self.ns.TrackedText
        t = self.a.lua.eval("function(q, u) return { quantity = q, unit = u } end")
        self.assertEqual([text(t(1, "crafts")), text(t(4, "crafts")), text(t(1, "items")), text(t(10, "items"))],
                         ["1 craft", "4 crafts", "1 item", "10 items"])

    def test_never_blizzard_tracking(self):
        track(self.a, 3932)
        track(self.a, 3932, 3)
        self.ns.SetTrackedQuantity(3932, 2)
        self.ns.UntrackRecipe(3932)
        self.assertIsNone(self.a.mock.blizzardTracked)


if __name__ == "__main__":
    unittest.main()
