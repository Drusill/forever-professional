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


# Combined plan of Target Dummy 3932 x1 and Bronze Tube 3938 x1: item -> (kind, spellID, need, crafts, level).
COMBINED = {
    4363: ("craft", 3926, 1, 1, 1), 4359: ("craft", 3922, 4, 4, 2), 2841: ("craft", 2659, 3, 2, 1),
    2840: ("craft", 2657, 7, 7, 3), 3576: ("craft", 3304, 2, 2, 2),
    2589: ("raw", None, 2, None, 2), 2592: ("raw", None, 1, None, 1), 2880: ("raw", None, 1, None, 1),
    2770: ("raw", None, 7, None, 4), 2771: ("raw", None, 2, None, 3),
}
COMBINED_SHOPPING = [(2589, 2), (2592, 1), (2770, 7), (2771, 2), (2880, 1)]
COMBINED_STEPS = [2840, 3576, 4359, 2841, 4363, 4366, 4371]
# Per-root shares before inventory: item -> [(root index, need)].
SHARES = {
    2841: [(1, 1), (2, 2)], 2840: [(1, 6), (2, 1)], 2770: [(1, 6), (2, 1)], 3576: [(1, 1), (2, 1)],
    2771: [(1, 1), (2, 1)], 4363: [(1, 1)], 4359: [(1, 4)], 2589: [(1, 2)], 2592: [(1, 1)], 2880: [(2, 1)],
}


def share_pairs(shares, item_id):
    return [(s.root, s.need) for s in lua_list(shares[item_id])]


class TrackedPlanTest(Base):
    def both(self):
        track(self.a, 3932)
        track(self.a, 3938)

    def plan(self):
        p, _ = self.ns.TrackedPlan()
        return p

    def test_roots(self):
        track(self.a, 3932, 2)
        track(self.a, 2659, 3, "items")
        roots = [(r.spellID, r.line, r.crafts) for r in lua_list(self.ns.TrackedRoots())]
        self.assertEqual(roots, [(3932, 202, 2), (2659, 186, 2)])

    def test_combined_totals(self):
        self.both()
        p = self.plan()
        for item_id, (kind, spell, need, crafts, level) in COMBINED.items():
            n = item(p, item_id)
            self.assertEqual((n.kind, n.spellID, n.need, n.crafts, n.level), (kind, spell, need, crafts, level), item_id)
        self.assertEqual([(e.item, e.need) for e in lua_list(p.shopping)], COMBINED_SHOPPING)
        self.assertEqual([s.item for s in lua_list(p.steps)], COMBINED_STEPS)

    def test_inventory_once(self):
        self.a.run("mock.bags[2770] = 4")
        self.both()
        n = item(self.plan(), 2770)
        self.assertEqual((n.have, n.buy), (4, 3))

    def test_shares(self):
        self.both()
        _, shares = self.ns.TrackedPlan()
        for item_id, expected in SHARES.items():
            self.assertEqual(share_pairs(shares, item_id), expected, item_id)
        self.assertIsNone(shares[4366])
        self.assertIsNone(shares[4371])

    def test_shares_scale(self):
        track(self.a, 3932, 2)
        track(self.a, 3938)
        p, shares = self.ns.TrackedPlan()
        self.assertEqual(share_pairs(shares, 2770), [(1, 11), (2, 1)])
        self.assertEqual(item(p, 2770).need, 12)

    def test_nothing_tracked(self):
        self.assertIsNone(self.ns.TrackedPlan())

    def test_cached(self):
        self.both()
        first = self.plan()
        calls = self.a.mock.schematicCalls
        self.assertTrue(self.a.lua.eval("rawequal")(first, self.plan()))
        self.assertEqual(self.a.mock.schematicCalls, calls)

    def test_dirty_on_list_change(self):
        self.both()
        self.plan()
        self.ns.SetTrackedQuantity(3932, 2)
        self.assertEqual(item(self.plan(), 4363).need, 2)

    def test_dirty_on_craft_mode(self):
        self.both()
        self.plan()
        self.ns.SetCraftMode(2841, "buy")
        self.assertEqual(item(self.plan(), 2841).kind, "buy")
        self.ns.ResetCraftModes()
        self.assertEqual(item(self.plan(), 2841).kind, "craft")

    def test_dirty_on_bags(self):
        self.both()
        self.plan()
        self.a.run('mock.bags[2770] = 7; fire("BAG_UPDATE_DELAYED")')
        self.assertEqual(item(self.plan(), 2770).buy, 0)

    def test_dirty_on_character_update(self):
        self.both()
        self.plan()
        self.a.run("mock.learned[2657] = true")
        self.ns.UpdateCharacter()
        self.assertTrue(item(self.plan(), 2840).known.me)

    def test_dirty_on_learned(self):
        self.both()
        self.plan()
        self.a.run('fire("NEW_RECIPE_LEARNED", 2659)')
        self.assertTrue(item(self.plan(), 2841).known.me)

    def test_dirty_on_forget(self):
        self.both()
        self.plan()
        self.ns.ForgetChar("Mina")
        p = self.plan()
        self.assertEqual((item(p, 2840).kind, item(p, 2841).kind), ("buy", "buy"))
        self.assertIsNone(item(p, 3576))   # only the Bronze Bar used it

    def test_orphan_stays(self):
        track(self.a, 2657)
        self.ns.ForgetChar("Mina")
        self.assertEqual(tracked(self.a), [(2657, 186, 1, "crafts")])
        known = self.plan().roots[1].known
        self.assertFalse(known.me)
        self.assertEqual(len(known.alts), 0)


if __name__ == "__main__":
    unittest.main()
