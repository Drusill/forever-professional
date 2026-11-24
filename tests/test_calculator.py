"""Materials calculator: reagent reading, the reverse index and the material plan in Model.lua, the player's
plan context in Characters.lua, and the calculator panel."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list, plain  # noqa: E402

# {spellID: [(itemID, count), ...]}: real reagents from the client's SpellReagents table (build 1.60.1.71037).
REAGENTS = {
    3932: [(4363, 1), (4359, 2), (2841, 1), (2592, 1)],   # Engineering: Target Dummy -> 4366
    3926: [(4359, 2), (2840, 1), (2589, 2)],              # Engineering: Copper Modulator -> 4363
    3922: [(2840, 1)],                                    # Engineering: Handful of Copper Bolts -> 4359
    3938: [(2841, 2), (2880, 1)],                         # Engineering: Bronze Tube -> 4371
    2657: [(2770, 1)],                                    # Mining: Copper Bar -> 2840
    3304: [(2771, 1)],                                    # Mining: Tin Bar -> 3576
    2659: [(2840, 1), (3576, 1)],                         # Mining: Bronze Bar -> 2841, makes 2
    3931: [(4364, 3), (2589, 1)],                         # Engineering: Coarse Dynamite -> 4365, makes {1, 3}
    3929: [(2836, 1)],                                    # Engineering: Coarse Blasting Powder -> 4364
    12584: [(3577, 1)],                                   # Engineering: Gold Power Core -> 10558, makes 3
    3308: [(2776, 1)],                                    # Mining: Gold Bar -> 3577 (learn 155)
    11479: [(3575, 1)],                                   # Alchemy: Transmute Iron to Gold -> 3577 (learn 225)
    3307: [(2772, 1)],                                    # Mining: Iron Bar -> 3575
    13240: [(10577, 1), (3860, 1), (10505, 3)],           # Engineering: The Mortar: Reloaded -> 10577 (itself)
    12716: [(10559, 2), (3860, 4), (10505, 5), (10558, 1), (7068, 1)],   # Engineering: Goblin Mortar -> 10577
    17559: [(7082, 1)], 17560: [(7078, 1)], 17561: [(7076, 1)], 17562: [(7080, 1)],   # Alchemy essence ring
    17563: [(12808, 1)], 17564: [(7080, 1)], 17565: [(12803, 1)], 17566: [(7076, 1)],
    2329: [(2449, 1), (765, 1), (3371, 1)],               # Alchemy: Elixir of Lion's Strength, no intermediate
}
TRANSMUTES = [17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566]

MINA = "Player-1-0000000F"
# Logged-in Tester knows the Engineering parts; alt Mina (Horde Warrior, Mining 175) knows the smelts.
CALC = """
ForeverProfessionalDB = { version = 2, chars = {
  ["Player-1-0000000F"] = { guid = "Player-1-0000000F", name = "Mina", class = "WARRIOR", faction = "Horde",
    level = 30, updated = 1795000000, professions = { [186] = { skill = 175, max = 225 } },
    learned = { [2657] = true, [2659] = true, [3304] = true, [3307] = true, [3308] = true } },
} }
mock.learned = { [3922] = true, [3926] = true, [3932] = true }
"""


def seed(a, reagents=REAGENTS):
    """Give each listed spell its real reagents; unlisted spells have no schematic."""
    rows = ", ".join("[%d] = { %s }" % (spell, ", ".join("{ %d, %d }" % r for r in items))
                     for spell, items in reagents.items())
    a.run("mock.onlySchematics = true; mock.schematics = { %s }" % rows)


def pairs(t):
    return [(e.item, e.count) for e in lua_list(t)]


class ReagentsTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(setup=CALC)
        self.a.login()
        seed(self.a)
        self.M = self.a.ns.Model

    def test_reagents_from_schematic(self):
        self.assertEqual(pairs(self.M.Reagents(3932)), [(4363, 1), (4359, 2), (2841, 1), (2592, 1)])

    def test_reagents_missing(self):
        self.assertIsNone(self.M.Reagents(999999))

    def test_schematic_cached(self):
        before = self.a.mock.schematicCalls or 0
        self.M.Reagents(3926)
        self.M.Reagents(3926)
        self.assertEqual(self.a.mock.schematicCalls, before + 1)

    def test_item_count_mock(self):
        self.a.run("mock.bags[2589] = 1; mock.bank[2589] = 2")
        count = self.a.g.C_Item.GetItemCount
        self.assertEqual(count(2589), 1)
        self.assertEqual(count(2589, True), 3)
        self.assertEqual(count(2770, True), 0)


def makers(t):
    return [(e.line, e.spellID) for e in lua_list(t)] if t is not None else None


class IndexTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = Addon()
        cls.M = cls.a.ns.Model
        cls.R = cls.a.ns.Data.Recipes

    def test_recipes_creating_single(self):
        self.assertEqual(makers(self.M.RecipesCreating(2840)), [(186, 2657)])

    def test_recipes_creating_several(self):
        self.assertEqual(makers(self.M.RecipesCreating(3577)), [(186, 3308), (171, 11479)])
        self.assertEqual([s for _, s in makers(self.M.RecipesCreating(7080))], [17561, 17563])
        self.assertEqual([s for _, s in makers(self.M.RecipesCreating(10577))], [12716, 13240])

    def test_recipes_creating_none(self):
        self.assertIsNone(self.M.RecipesCreating(2770))

    def test_index_matches_data(self):
        expected = 0
        for line in self.R.keys():
            for spell, rec in self.R[line].items():
                if rec.creates:
                    expected += 1
                    self.assertIn((line, spell), makers(self.M.RecipesCreating(rec.creates)))
        items = {rec.creates for line in self.R.keys() for rec in self.R[line].values() if rec.creates}
        self.assertEqual(sum(len(makers(self.M.RecipesCreating(i))) for i in items), expected)

    def test_yield(self):
        for line, spell, n in [(202, 3932, 1), (186, 2659, 2), (202, 3931, 1), (202, 12584, 3)]:
            self.assertEqual(self.M.Yield(self.R[line][spell]), n, spell)

    def test_crafts_for(self):
        self.assertEqual(self.M.CraftsFor(self.R[202][12584], 7), 3)
        self.assertEqual(self.M.CraftsFor(self.R[186][2659], 3), 2)
        self.assertEqual(self.M.CraftsFor(self.R[202][3931], 6), 6)
        self.assertEqual(self.M.CraftsFor(self.R[202][3932], 0), 0)


LINES = {3932: 202, 3926: 202, 3922: 202, 3938: 202, 3931: 202, 3929: 202, 12584: 202, 13240: 202,
         12716: 202, 2657: 186, 3304: 186, 2659: 186, 3308: 186, 3307: 186, 11479: 171, 2329: 171,
         **{s: 171 for s in TRANSMUTES}}
# Who knows what in the hand-built context: "me" is the logged-in character.
KNOWN = {3922: ["me"], 3926: ["me"], 3932: ["me"],
         2657: [MINA], 2659: [MINA], 3304: [MINA], 3307: [MINA], 3308: [MINA]}


def lua_ctx(a, known=None, have=None, modes=None):
    """A plan context built by hand: reagents from the mock, the rest from Python dicts."""
    known = KNOWN if known is None else known
    known_src = ", ".join("[%d] = { %s }" % (s, ", ".join('"%s"' % k for k in ks)) for s, ks in known.items())
    have_src = ", ".join("[%d] = %d" % kv for kv in (have or {}).items())
    modes_src = ", ".join('[%d] = "%s"' % kv for kv in (modes or {}).items())
    return a.run("""
        local known, have, modes = { %s }, { %s }, { %s }
        return {
            reagents = _ns.Model.Reagents,
            have = function(id) return have[id] or 0 end,
            knownBy = function(line, id)
                local out = { me = false, alts = {} }
                for _, k in ipairs(known[id] or {}) do
                    if k == "me" then out.me = true else out.alts[#out.alts + 1] = k end
                end
                return out
            end,
            mode = function(id) return modes[id] end,
        }""" % (known_src, have_src, modes_src))


def run_plan(a, roots, ctx):
    """roots: [(spellID, crafts)...]."""
    a.g._ctx = ctx
    src = ", ".join("{ spellID = %d, line = %d, crafts = %d }" % (s, LINES.get(s, 0), n) for s, n in roots)
    return a.run("return _ns.Model.PlanMaterials({ %s }, _ctx)" % src)


class PlanBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = Addon(setup=CALC)
        cls.a.login()
        cls.a.g._ns = cls.a.ns
        cls.M = cls.a.ns.Model

    def setUp(self):
        self.a.run("_ns.Model.schematics = {}")
        seed(self.a)

    def plan(self, roots, **ctx):
        return run_plan(self.a, roots, lua_ctx(self.a, **ctx))

    @staticmethod
    def crafted(p):
        return {k: v for k, v in p["items"].items() if v.kind == "craft"}


class PlanTest(PlanBase):
    def test_one_level(self):
        p = self.plan([(2329, 1)])
        self.assertEqual(sorted(p["items"].keys()), [765, 2449, 3371])
        for n in p["items"].values():
            self.assertEqual((n.kind, n.need, n.switchable), ("raw", 1, False))

    def test_nested(self):
        p = self.plan([(3932, 1)])
        expected = {  # item: (kind, spellID, need, crafts, level)
            4363: ("craft", 3926, 1, 1, 1), 4359: ("craft", 3922, 4, 4, 2), 2841: ("craft", 2659, 1, 1, 1),
            2840: ("craft", 2657, 6, 6, 3), 3576: ("craft", 3304, 1, 1, 2),
            2589: ("raw", None, 2, None, 2), 2592: ("raw", None, 1, None, 1),
            2770: ("raw", None, 6, None, 4), 2771: ("raw", None, 1, None, 3),
        }
        self.assertEqual(sorted(p["items"].keys()), sorted(expected))
        for item, want in expected.items():
            n = p["items"][item]
            self.assertEqual((n.kind, n.spellID, n.need, n.crafts, n.level), want, item)
        self.assertEqual(p["items"][2841].surplus, 1)
        root = p.roots[1]
        self.assertEqual((root.spellID, root.crafts, root.makes, root.item, root.known.me), (3932, 1, 1, 4366, True))

    def test_shared_summed(self):
        self.assertEqual(self.plan([(3932, 1)])["items"][2840].need, 6)

    def test_scales(self):
        p = self.plan([(3932, 10)])
        self.assertEqual(p["items"][4359].need, 40)
        self.assertEqual((p["items"][2841].need, p["items"][2841].crafts, p["items"][2841].surplus), (10, 5, 0))
        self.assertEqual(p["items"][2840].need, 55)

    def test_multi_output_rounded_on_total(self):
        p = self.plan([(3932, 1), (3932, 1)])
        self.assertEqual((p["items"][2841].need, p["items"][2841].crafts, p["items"][2841].surplus), (2, 1, 0))
        p = self.plan([(3932, 1), (3938, 1)])
        self.assertEqual((p["items"][2841].need, p["items"][2841].crafts, p["items"][2841].surplus), (3, 2, 1))

    def test_known_by_alt_and_nobody(self):
        p = self.plan([(3932, 1)])
        self.assertFalse(p["items"][2840].known.me)
        self.assertEqual(lua_list(p["items"][2840].known.alts), [MINA])
        known = {k: v for k, v in KNOWN.items() if v != [MINA]}
        p = self.plan([(3932, 1)], known=known)
        for item in (2840, 2841):
            self.assertEqual((p["items"][item].kind, p["items"][item].switchable), ("buy", True), item)
        for item in (2770, 2771, 3576):   # below the bought bars
            self.assertNotIn(item, p["items"].keys())

    def test_several_makers_alt(self):
        n = self.plan([(12584, 1)])["items"][3577]
        self.assertEqual((n.kind, n.spellID, n.line), ("craft", 3308, 186))

    def test_several_makers_me_first(self):
        p = self.plan([(12584, 1)], known={**KNOWN, 11479: ["me"]})
        self.assertEqual((p["items"][3577].kind, p["items"][3577].spellID), ("craft", 11479))
        self.assertEqual((p["items"][3575].kind, p["items"][3575].spellID), ("craft", 3307))
        self.assertEqual(p["items"][2772].kind, "raw")
        self.assertNotIn(2776, p["items"].keys())

    def test_several_makers_lowest_skill(self):
        n = self.plan([(12584, 1)], known={}, modes={3577: "craft"})["items"][3577]
        self.assertEqual((n.kind, n.spellID), ("craft", 3308))

    def test_several_makers_tie_spell_id(self):
        n = self.plan([(17562, 1)], known={}, modes={7080: "craft"})["items"][7080]
        self.assertEqual((n.kind, n.spellID), ("craft", 17561))

    def test_default_buy_when_nobody_knows(self):
        n = self.plan([(12584, 1)], known={})["items"][3577]
        self.assertEqual((n.kind, n.switchable, bool(n.cycle)), ("buy", True, False))

    def test_switch_buy(self):
        p = self.plan([(3932, 1)], modes={2840: "buy"})
        n = p["items"][2840]
        self.assertEqual((n.kind, n.need, n.buy, n.mode), ("buy", 6, 6, "buy"))
        self.assertNotIn(2770, p["items"].keys())

    def test_switch_craft_on_raw_ignored(self):
        self.assertEqual(self.plan([(3932, 1)], modes={2592: "craft"})["items"][2592].kind, "raw")

    def test_bad_mode_ignored(self):
        n = self.plan([(3932, 1)], modes={2840: "bogus"})["items"][2840]
        self.assertEqual((n.kind, n.mode), ("craft", None))

    def test_cycle_two_step(self):
        known = {s: ["me"] for s in TRANSMUTES}
        n = self.plan([(17563, 1)], known=known, modes={12808: "craft"})["items"][12808]
        self.assertEqual((n.kind, n.cycle), ("buy", True))

    def assert_no_item_in_own_subtree(self, p, root_item):
        def walk(item, path):
            n = p["items"][item]
            if n.kind != "craft":
                return
            for r in lua_list(n.reagents):
                self.assertNotIn(r.item, path | {item}, "cycle through %d" % r.item)
                walk(r.item, path | {item})
        for r in lua_list(p.roots[1].reagents):
            walk(r.item, {root_item})

    def test_cycle_ring_all_craft(self):
        known = {s: ["me"] for s in TRANSMUTES}
        modes = {i: "craft" for i in (7076, 7078, 7080, 7082, 12803, 12808)}
        p = self.plan([(17562, 1)], known=known, modes=modes)
        self.assertEqual((p["items"][7080].kind, p["items"][7080].spellID), ("craft", 17561))
        self.assertEqual((p["items"][7076].kind, p["items"][7076].spellID), ("craft", 17560))
        self.assertEqual((p["items"][7078].kind, p["items"][7078].cycle), ("buy", True))
        self.assert_no_item_in_own_subtree(p, 7082)

    def test_root_output_as_reagent(self):
        n = self.plan([(13240, 1)])["items"][10577]
        self.assertEqual((n.kind, n.cycle, n.switchable), ("buy", True, False))

    def test_unreadable_root(self):
        p = self.plan([(999999, 1)])
        self.assertIsNone(p.roots[1].reagents)
        self.assertEqual(len(p["items"]), 0)

    def test_unreadable_maker_is_unusable(self):
        self.a.run("_ns.Model.schematics = {}")
        seed(self.a, {k: v for k, v in REAGENTS.items() if k != 2657})
        n = self.plan([(3932, 1)])["items"][2840]
        self.assertEqual((n.kind, bool(n.cycle)), ("buy", False))

    def test_schematic_read_once(self):
        before = self.a.mock.schematicCalls or 0
        self.plan([(3932, 1)])
        self.assertEqual(self.a.mock.schematicCalls - before, 6)   # 3932, 3926, 3922, 2659, 2657, 3304



def tree_children(node):
    return [(c.item, c.count) for c in lua_list(node.children)] if node.children else []


class OutputTest(PlanBase):
    def test_shopping(self):
        p = self.plan([(3932, 1)])
        self.assertEqual([(e.item, e.need, e.have, e.buy) for e in lua_list(p.shopping)],
                         [(2589, 2, 0, 2), (2592, 1, 0, 1), (2770, 6, 0, 6), (2771, 1, 0, 1)])

    def test_steps_order(self):
        p = self.plan([(3932, 1)])
        steps = lua_list(p.steps)
        self.assertEqual([s.item for s in steps], [2840, 3576, 4359, 2841, 4363, 4366])
        self.assertEqual([s.crafts for s in steps], [6, 1, 4, 1, 1, 1])
        self.assertEqual([s.spellID for s in steps], [2657, 3304, 3922, 2659, 3926, 3932])
        done = set()
        for s in steps:
            for r in lua_list(self.M.Reagents(s.spellID)):
                if p["items"][r.item] and p["items"][r.item].kind == "craft":
                    self.assertIn(r.item, done, "%d before %d" % (s.item, r.item))
            done.add(s.item)

    def test_inventory_intermediate(self):
        p = self.plan([(3932, 1)], have={4359: 3})
        self.assertEqual((p["items"][4359].have, p["items"][4359].crafts), (3, 1))
        self.assertEqual(p["items"][2840].need, 3)
        self.assertEqual(p["items"][2770].buy, 3)

    def test_inventory_used_once(self):
        p = self.plan([(3932, 1)], have={2840: 1})
        self.assertEqual((p["items"][2840].net, p["items"][2840].crafts), (5, 5))
        self.assertEqual(p["items"][2770].buy, 5)

    def test_inventory_raw(self):
        p = self.plan([(3932, 1)], have={2589: 2})
        self.assertIn((2589, 2, 2, 0), [(e.item, e.need, e.have, e.buy) for e in lua_list(p.shopping)])

    def test_inventory_covers_intermediate(self):
        p = self.plan([(3932, 1)], have={4363: 1})
        self.assertEqual(p["items"][4363].crafts, 0)
        self.assertEqual(p["items"][4359].need, 2)
        self.assertNotIn(4363, [s.item for s in lua_list(p.steps)])
        self.assertNotIn(2589, [e.item for e in lua_list(p.shopping)])

    def test_root_output_not_subtracted(self):
        p = self.plan([(3932, 1)], have={4366: 5})
        self.assertEqual(lua_list(p.steps)[-1].crafts, 1)

    def test_tree(self):
        root = self.plan([(3932, 1)]).tree[1]
        self.assertEqual((root.item, root.count, root.spellID), (4366, 1, 3932))
        self.assertEqual(tree_children(root), [(4363, 1), (4359, 2), (2841, 1), (2592, 1)])
        kids = {c.item: c for c in lua_list(root.children)}
        self.assertEqual(tree_children(kids[4363]), [(4359, 2), (2840, 1), (2589, 2)])
        self.assertEqual(tree_children(kids[2841]), [(2840, 1), (3576, 1)])
        self.assertEqual(tree_children(kids[2592]), [])

    def test_tree_bought_has_no_children(self):
        root = self.plan([(3932, 1)], modes={2841: "buy"}).tree[1]
        bronze = next(c for c in lua_list(root.children) if c.item == 2841)
        self.assertEqual(tree_children(bronze), [])

    def test_tree_cap(self):
        self.a.run("_ns.Model.PLAN_TREE_MAX = 5")
        try:
            p = self.plan([(3932, 1)])
        finally:
            self.a.run("_ns.Model.PLAN_TREE_MAX = 400")
        nodes, more = 0, 0

        def walk(n):
            nonlocal nodes, more
            if n.more:
                more += 1
                return
            nodes += 1
            for c in lua_list(n.children) if n.children else []:
                walk(c)
        walk(p.tree[1])
        self.assertLessEqual(nodes, 5)
        self.assertEqual(more, 1)
        self.assertEqual(p["items"][2770].need, 6)   # totals still complete


class ContextTest(unittest.TestCase):
    def setUp(self, setup=CALC):
        self.a = Addon(setup=setup)
        self.a.login()
        self.a.g._ns = self.a.ns
        self.ns = self.a.ns
        seed(self.a)

    def plan(self, roots=((3932, 1),)):
        return run_plan(self.a, roots, self.ns.PlanContext())

    def test_context_plan_matches_fixture(self):
        p = self.plan()
        kinds = {i: (n.kind, n.need) for i, n in p["items"].items()}
        self.assertEqual(kinds, {4363: ("craft", 1), 4359: ("craft", 4), 2841: ("craft", 1), 2840: ("craft", 6),
                                 3576: ("craft", 1), 2589: ("raw", 2), 2592: ("raw", 1), 2770: ("raw", 6),
                                 2771: ("raw", 1)})
        self.assertTrue(p["items"][4363].known.me)
        self.assertEqual(lua_list(p["items"][2840].known.alts), [MINA])
        self.assertTrue(p.roots[1].known.me)

    def test_context_have_counts_bank(self):
        self.a.run("mock.bags[4359] = 1; mock.bank[4359] = 2")
        n = self.plan()["items"][4359]
        self.assertEqual((n.have, n.crafts), (3, 1))

    def test_set_craft_mode(self):
        self.ns.SetCraftMode(2840, "buy")
        self.assertEqual(self.ns.db.craftModes[2840], "buy")
        self.assertEqual(self.plan()["items"][2840].kind, "buy")
        self.ns.SetCraftMode(2840, None)
        self.assertIsNone(self.ns.db.craftModes[2840])
        self.assertEqual(self.plan()["items"][2840].kind, "craft")

    def test_reset_craft_modes(self):
        modes = self.ns.db.craftModes
        self.ns.SetCraftMode(2840, "buy")
        self.ns.SetCraftMode(2592, "craft")
        self.ns.ResetCraftModes()
        self.assertEqual(list(self.ns.db.craftModes.keys()), [])
        self.assertTrue(self.a.lua.eval("rawequal")(modes, self.ns.db.craftModes))

    def test_saved_across_reload(self):
        self.setUp(CALC + "ForeverProfessionalDB.craftModes = { [2840] = 'buy' }")
        self.assertEqual(self.plan()["items"][2840].kind, "buy")

    def test_bad_saved_modes_ignored(self):
        self.setUp(CALC + "ForeverProfessionalDB.craftModes = { [2840] = 'bogus', [4359] = 5 }")
        p = self.plan()
        self.assertEqual((p["items"][2840].kind, p["items"][4359].kind), ("craft", "craft"))

    def test_crafter_text(self):
        text = self.ns.CrafterText
        known = self.a.lua.eval("function(me, ...) return { me = me, alts = { ... } } end")
        self.assertEqual(text(known(True)), ("You", "me"))
        t, kind = text(known(False, MINA))
        self.assertEqual((plain(t), kind), ("Mina", "alt"))
        t, kind = text(known(False, MINA, "Player-1-0000000E"))
        self.assertEqual((plain(t), kind), ("Mina +1", "alt"))
        self.assertEqual(text(known(False)), ("Nobody", "nobody"))

    def test_logged_in_is_me_even_when_alt_shown(self):
        self.a.slash("")
        self.ns.UI.SetChar(MINA)
        known = self.ns.PlanContext().knownBy(202, 3926)
        self.assertTrue(known.me)


class PanelBase(unittest.TestCase):
    setup = CALC

    def setUp(self):
        self.a = Addon(setup=self.setup)
        self.a.login()
        self.a.g._ns = self.a.ns
        seed(self.a)
        self.a.slash("")
        self.ns, self.UI = self.a.ns, self.a.ns.UI
        self.L = self.ns.L
        self.open(3932)

    def open(self, spell, line=None):
        self.UI.SelectProfession(line or LINES[spell])
        self.UI.SelectRecipe(spell)
        self.a.call(self.UI.detail.header.calcButton, "Click")
        self.c = self.UI.calc

    def rows(self, kind):
        return [r for r in lua_list(self.c.rendered) if r.kind == kind]

    def shop(self):
        return [(r.item, r.need, r.have, r.buy) for r in self.rows("shop")]

    def tab_count(self, key):
        return self.c.tabs.buttons[key].count.text


class PanelTest(PanelBase):
    def test_calculate_button_opens(self):
        self.assertEqual(self.UI.detail.header.calcButton.label.text, "Calculate")
        self.assertTrue(self.c.shown)
        self.assertEqual(self.c.spellID, 3932)
        self.assertEqual(self.c.title.text, "Spell 3932")
        self.assertEqual(self.c.tab, "shopping")
        self.assertEqual(self.c.qty.text, "1")

    def test_who(self):
        self.assertEqual(plain(self.c.who.text), "Who: You")
        self.open(2657)
        self.assertEqual(plain(self.c.who.text), "Who: Mina")
        self.open(3929)
        self.assertEqual(plain(self.c.who.text), "Who: Nobody")

    def test_shopping_rows(self):
        self.assertEqual(self.shop(), [(2589, 2, 0, 2), (2592, 1, 0, 1), (2770, 6, 0, 6), (2771, 1, 0, 1)])
        self.assertEqual(self.tab_count("shopping"), "4")

    def test_quantity(self):
        self.UI.SetCalcQuantity(10)
        self.assertEqual(self.c.qty.text, "10")
        self.assertIn((2770, 55, 0, 55), self.shop())
        self.a.call(self.c.qty, "SetText", "3")          # typing
        self.assertIn((2770, 17, 0, 17), self.shop())
        for bad in ("abc", ""):
            self.a.call(self.c.qty, "SetText", bad)
            self.assertIn((2770, 17, 0, 17), self.shop())
            self.c.qty.scripts.OnEditFocusLost(self.c.qty)
            self.assertEqual(self.c.qty.text, "3")
        self.UI.SetCalcQuantity(1000)
        self.assertEqual(self.c.qty.text, "999")

    def test_unit_hidden_for_single_yield(self):
        self.assertFalse(self.c.unit.shown)
        self.assertEqual(self.c.summary.text, "1 craft, makes 1")

    def test_unit_items(self):
        self.open(2659)
        self.assertTrue(self.c.unit.shown)
        self.UI.SetCalcUnit("items")
        self.UI.SetCalcQuantity(3)
        self.assertEqual(self.c.plan.roots[1].crafts, 2)
        self.assertEqual(self.c.summary.text, "2 crafts, 1 extra")
        self.UI.SetCalcUnit("crafts")
        self.assertEqual(self.c.summary.text, "3 crafts, makes 6")

    def test_reopen_resets_quantity_and_unit(self):
        self.open(2659)
        self.UI.SetCalcUnit("items")
        self.UI.SetCalcQuantity(5)
        self.open(2659)
        self.assertEqual((self.c.unitKey, self.c.qty.text), ("crafts", "1"))

    def test_unit_range(self):
        self.open(3931)
        self.assertTrue(self.c.unit.shown)
        self.UI.SetCalcUnit("items")
        self.UI.SetCalcQuantity(6)
        self.assertEqual(self.c.plan.roots[1].crafts, 6)

    def test_enchant_no_output(self):
        enchants = self.ns.Data.Recipes[333]
        spell = min(k for k, v in enchants.items() if not v.creates)
        self.open(spell, 333)
        self.assertTrue(self.c.shown)
        self.assertFalse(self.c.unit.shown)
        self.assertEqual(self.c.summary.text, "")

    def test_enchant_steps_and_tree(self):
        # An enchant makes no item: its step and tree rows show the recipe instead of an item slot.
        enchants = self.ns.Data.Recipes[333]
        spell = min(k for k, v in enchants.items() if not v.creates)
        seed(self.a, {**REAGENTS, spell: [(10940, 1)]})
        self.open(spell, 333)
        self.UI.SetCalcTab("steps")
        steps = self.rows("step")
        self.assertEqual([r.item for r in steps], [None])
        self.assertIsNone(steps[0].widget.slot.item)
        self.UI.SetCalcTab("tree")
        self.assertEqual([(r.item, r.depth) for r in self.rows("node")], [(None, 0), (10940, 1)])

    def test_have_all(self):
        self.a.run("mock.bags[2589] = 2; mock.bags[2592] = 1; mock.bags[2770] = 6; mock.bags[2771] = 1")
        self.UI.RefreshCalculator()
        self.assertTrue(self.c.message.shown)
        self.assertEqual(self.c.message.text, self.L.CALC_HAVE_ALL)
        self.assertEqual(self.tab_count("shopping"), "0")

    def test_no_reagents(self):
        spell = min(k for k in self.ns.Data.Recipes[202].keys() if k not in REAGENTS)
        self.open(spell, 202)
        self.assertEqual(self.c.message.text, self.L.CALC_NO_REAGENTS)
        self.assertEqual(lua_list(self.c.rendered), [])

    def test_back(self):
        self.a.call(self.c.back, "Click")
        self.assertFalse(self.c.shown)
        self.assertEqual(self.UI.detail.current, 3932)

    def test_closes_on_other_recipe_and_hide(self):
        self.UI.SelectRecipe(3926)
        self.assertFalse(self.c.shown)
        self.open(3932)
        self.UI.SelectProfession(186)
        self.assertFalse(self.c.shown)
        self.open(3932)
        self.a.slash("")
        self.assertFalse(self.c.shown)

    def test_unlearned_recipe(self):
        self.open(3938)
        self.assertEqual(plain(self.c.who.text), "Who: Nobody")
        self.assertIn(2880, [r.item for r in self.rows("shop")])


def flat_tree(node, depth=0):
    """(item, depth, count) in depth-first order, as the Tree tab draws it."""
    out = [(node.item, depth, node.count)]
    for c in lua_list(node.children) if node.children else []:
        out.extend(flat_tree(c, depth + 1))
    return out


class PanelTabsTest(PanelBase):
    def row(self, kind, item):
        return next(r for r in self.rows(kind) if r.item == item)

    def widget(self, kind, item):
        return self.row(kind, item).widget

    def test_steps_tab(self):
        self.UI.SetCalcTab("steps")
        steps = self.rows("step")
        self.assertEqual([r.item for r in steps], [2840, 3576, 4359, 2841, 4363, 4366])
        self.assertEqual([r.crafts for r in steps], [6, 1, 4, 1, 1, 1])
        self.assertEqual([plain(r.crafter) for r in steps], ["Mina", "Mina", "You", "Mina", "You", "You"])
        self.assertEqual(self.tab_count("steps"), "6")
        self.assertEqual([bool(r.switch) for r in steps], [True] * 5 + [False])
        self.assertEqual(self.widget("step", 2840).switch.label.text, "Buy")

    def test_tree_tab(self):
        self.UI.SetCalcTab("tree")
        nodes = self.rows("node")
        self.assertEqual([(r.item, r.depth, r.count) for r in nodes], flat_tree(self.c.plan.tree[1]))
        self.assertEqual(nodes[0].item, 4366)
        self.assertEqual(plain(self.row("node", 2592).info), "Raw")
        self.assertEqual(plain(self.row("node", 4363).info), "You")
        self.assertEqual(plain(self.row("node", 2841).info), "Mina")

    def test_switch_in_tree(self):
        self.UI.SetCalcTab("tree")
        self.a.call(self.widget("node", 2841).switch, "Click")
        self.assertEqual(self.ns.db.craftModes[2841], "buy")
        self.assertNotIn(3576, [r.item for r in self.rows("node")])
        self.assertEqual(self.widget("node", 2841).switch.label.text, "Craft")
        self.assertEqual(plain(self.row("node", 2841).info), "Buy")
        self.UI.SetCalcTab("shopping")
        self.assertIn(2841, [r.item for r in self.rows("shop")])

    def test_switch_in_shopping(self):
        self.ns.SetCraftMode(2841, "buy")
        self.UI.RefreshCalculator()
        w = self.widget("shop", 2841)
        self.assertTrue(w.switch.shown)
        self.assertEqual(w.switch.label.text, "Craft")
        self.assertFalse(self.widget("shop", 2770).switch.shown)   # raw: nothing to switch
        self.a.call(w.switch, "Click")
        self.assertEqual(self.ns.db.craftModes[2841], "craft")
        self.assertNotIn(2841, [r.item for r in self.rows("shop")])

    def test_reset(self):
        self.assertFalse(self.c.reset.shown)
        self.UI.SetCalcTab("tree")
        self.a.call(self.widget("node", 2841).switch, "Click")
        self.assertTrue(self.c.reset.shown)
        self.a.call(self.c.reset, "Click")
        self.assertEqual(list(self.ns.db.craftModes.keys()), [])
        self.assertFalse(self.c.reset.shown)
        self.assertIn(3576, [r.item for r in self.rows("node")])

    def test_cycle_note(self):
        self.open(13240)
        self.UI.SetCalcTab("tree")
        # The root row is a Goblin Mortar too; the reagent one sits under it.
        row = next(r for r in self.rows("node") if r.item == 10577 and r.depth == 1)
        self.assertEqual(row.note, self.L.CALC_CYCLE)
        self.assertFalse(row.switch)
        self.assertIn(self.L.CALC_CYCLE, row.widget.name.text)

    def test_have_tooltip(self):
        self.a.g.enter(self.widget("shop", 2770))
        self.assertIn(self.L.CALC_HAVE_TOOLTIP, lua_list(self.a.g.GameTooltip.lines))

    def test_bag_update(self):
        self.a.run("mock.bags[2770] = 6")
        self.a.run('fire("BAG_UPDATE_DELAYED")')
        self.assertIn((2770, 6, 6, 0), self.shop())
        self.UI.CloseCalculator()
        renders = self.c.renders
        self.a.run('fire("BAG_UPDATE_DELAYED")')
        self.assertEqual(self.c.renders, renders)

    def test_refresh_redraws(self):
        renders = self.c.renders
        self.ns.UpdateCharacter()
        self.assertTrue(self.c.shown)
        self.assertGreater(self.c.renders, renders)

    def test_fits_minimum_window(self):
        self.a.call(self.UI.frame, "SetSize", 900, 540)
        inner = self.UI.DetailPanelWidth() - 16
        self.assertGreaterEqual(self.UI.CalcRowLayout(self.UI.DetailContentWidth(), 7).nameW, 100)
        self.open(2659)   # with the Crafts / Items switch
        text_w = self.a.call   # font strings report the mock's string width (6px a character)
        qty_row = (10 + text_w(self.c.qtyLabel, "GetStringWidth") + 6 + self.c.qty.width + 8
                   + self.c.unit.width + 8 + text_w(self.c.summary, "GetStringWidth"))
        self.assertLessEqual(qty_row, inner)
        self.assertLessEqual(self.c.tabs.width + 8 + self.c.reset.width, inner)
        self.assertGreaterEqual(self.UI.CalcVisibleHeight(), 300)

if __name__ == "__main__":
    unittest.main()
