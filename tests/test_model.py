"""Model.lua tests on the real baked data."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list, plain  # noqa: E402

LEARNED = "mock.learned = { [2329] = true, [3170] = true, [7183] = true }"
GOLD = r"|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t"
SILVER = r"|TInterface\MoneyFrame\UI-SilverIcon:0:0:2:0|t"
COPPER = r"|TInterface\MoneyFrame\UI-CopperIcon:0:0:2:0|t"


class ModelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = Addon(setup=LEARNED)
        cls.a.login()
        cls.M = cls.a.ns.Model
        cls.recipes171 = cls.a.ns.Data.Recipes[171]
        cls.total171 = len(list(cls.recipes171.keys()))

    def flat(self, line=171, filter="all", search=None, collapsed=None):
        a = self.a
        a.g._opts = a.lua.table_from({"filter": filter, "search": search or "",
                                      "collapsed": a.lua.table_from(collapsed or {})})
        a.g._line = line
        a.g._ns = a.ns
        entries, count, learned = a.run(
            "_opts.isLearned = function(id) return _ns.IsLearned(id) end; "
            "return _ns.Model.Flatten(_ns.Model.BuildTree(_line), _opts)")
        return lua_list(entries), count, learned

    @staticmethod
    def recipe_ids(entries):
        return [e.id for e in entries if e.kind == "recipe"]

    @staticmethod
    def headers(entries, depth=0):
        return [e.name for e in entries if e.kind == "header" and e.depth == depth]

    def test_all_recipes_present(self):
        entries, count, learned = self.flat()
        self.assertEqual(count, self.total171)
        self.assertEqual(len(self.recipe_ids(entries)), self.total171)
        self.assertEqual(learned, 3)

    def test_headers_sorted_by_order_with_other_last(self):
        entries, _, _ = self.flat()
        heads = self.headers(entries)
        self.assertEqual(heads[:4], ["Camping", "Reagents", "Recovery Potions", "Potions"])
        self.assertEqual(heads[-1], "Other")
        other = next(i for i, e in enumerate(entries) if e.kind == "header" and e.cat == "other")
        self.assertIn(1251750, self.recipe_ids(entries[other:]))

    def test_recipes_sorted_by_learn_skill(self):
        entries, _, _ = self.flat()
        start = next(i for i, e in enumerate(entries) if e.kind == "header" and e.name == "Elixirs")
        learns = []
        for e in entries[start + 1:]:
            if e.kind == "header":
                break
            learns.append(self.recipes171[e.id].learn)
        self.assertGreater(len(learns), 5)
        self.assertEqual(learns, sorted(learns))

    def test_filter_learned(self):
        entries, count, learned = self.flat(filter="learned")
        self.assertEqual(sorted(self.recipe_ids(entries)), [2329, 3170, 7183])
        self.assertEqual((count, learned), (3, 3))

    def test_filter_missing(self):
        entries, count, learned = self.flat(filter="missing")
        ids = self.recipe_ids(entries)
        self.assertNotIn(2329, ids)
        self.assertIn(3230, ids)
        self.assertEqual(learned, 0)
        self.assertEqual(count, self.total171 - 3)

    def test_empty_headers_dropped(self):
        entries, _, _ = self.flat(filter="learned")
        for e in entries:
            if e.kind == "header":
                self.assertGreater(e.count, 0)

    def test_search(self):
        entries, count, _ = self.flat(search="  SPELL 3230 ")
        self.assertEqual(self.recipe_ids(entries), [3230])
        self.assertEqual(count, 1)

    def test_collapse_hides_recipes(self):
        entries, count, _ = self.flat(collapsed={2450: True})
        elixirs = next(e for e in entries if e.kind == "header" and e.cat == 2450)
        self.assertTrue(elixirs.collapsed)
        self.assertNotIn(7183, self.recipe_ids(entries))
        self.assertEqual(count, self.total171)

    def test_search_ignores_collapse(self):
        entries, _, _ = self.flat(search="spell 7183", collapsed={2450: True})
        self.assertEqual(self.recipe_ids(entries), [7183])

    def test_every_profession_builds(self):
        for line in self.a.ns.Data.Professions.keys():
            _, count, _ = self.flat(line=line)
            self.assertEqual(count, len(list(self.a.ns.Data.Recipes[line].keys())), line)

    def test_difficulty(self):
        rec = self.recipes171[3230]  # 50 / 80 / 100 / 120
        D = self.M.Difficulty
        self.assertEqual(D(rec, None), "neutral")
        self.assertEqual(D(rec, 40), "red")
        self.assertEqual(D(rec, 50), "orange")
        self.assertEqual(D(rec, 80), "yellow")
        self.assertEqual(D(rec, 100), "green")
        self.assertEqual(D(rec, 120), "grey")
        self.assertEqual(D(self.recipes171[1251750], 200), "orange")  # only a learn skill

    def test_range_text(self):
        rec = self.recipes171[3230]
        self.assertEqual(self.M.RangeText(rec, 120),
                         "|cffff804050|r |cffffff0080|r |cff40c040100|r |cff808080120|r")
        self.assertTrue(self.M.RangeText(rec, 10).startswith("|cffff202050|r"))

    def lines(self, line, spell):
        return lua_list(self.M.SourceLines(self.a.ns.Data.Recipes[line][spell]))

    def texts(self, line, spell):
        return [l.text for l in self.lines(line, spell) if l.text]

    def test_sources_trainer(self):
        self.assertIn("Trainer: 50" + COPPER, self.texts(171, 2329))

    def test_money_uses_coin_icons_and_skips_zero_units(self):
        # The client's GetCoinTextureString isn't used: in game it fell back to "0g 1s 0c".
        self.assertEqual(self.M.Money(50), "50" + COPPER)
        self.assertEqual(self.M.Money(100), "1" + SILVER)
        self.assertEqual(self.M.Money(10203), "1" + GOLD + " 2" + SILVER + " 3" + COPPER)
        self.assertEqual(self.M.Money(20000), "2" + GOLD)
        self.assertEqual(self.M.Money(0), "0" + COPPER)

    def test_sources_gated_vendor(self):
        lines = self.lines(171, 1251750)
        texts = [l.text for l in lines]
        self.assertIn("Vendors", texts)
        name = self.a.ns.Data.NPCs[248196].name
        vendor = next(l for l in lines if l.kind == "text" and l.text.startswith(name))
        self.assertIn("Map ", vendor.text)
        self.assertIsNotNone(vendor.waypoint)
        self.assertIn("Requirements", texts)
        self.assertIn("Faction 2586: Friendly", texts)
        self.assertIn("120 Merchant's Favor", texts)

    def test_sources_drop_rates(self):
        texts = self.texts(171, 1250793)
        self.assertIn("Drops", texts)
        self.assertTrue(any("rate unknown" in t for t in texts))
        texts = self.texts(171, 3230)
        self.assertTrue(any(" - 0.5%" in t for t in texts))
        self.assertTrue(any(t.startswith("+") and t.endswith("more") for t in texts))
        self.assertIn("Found in", texts)

    def test_sources_containers_are_items(self):
        items = [l for l in self.lines(171, 2335) if l.kind == "item"]
        self.assertTrue(items)
        self.assertIsNotNone(items[0].item)

    def test_sources_unknown_and_quest(self):
        notes = [l.text for l in self.lines(171, 2365) if l.kind == "note"]
        self.assertEqual(notes, ["Source unknown"])
        texts = self.texts(171, 1230564)
        self.assertIn("Quests", texts)
        self.assertTrue(any(t.startswith("Given by ") for t in texts))

    def test_sources_unverified(self):
        for line in self.a.ns.Data.Recipes.keys():
            for spell, rec in self.a.ns.Data.Recipes[line].items():
                if rec.unverified:
                    notes = [l.text for l in self.lines(line, spell) if l.kind == "note"]
                    self.assertTrue(any("(location unknown)" in n for n in notes))
                    return
        self.fail("no unverified recipe in data")

    def test_every_recipe_has_source_lines(self):
        for line in self.a.ns.Data.Recipes.keys():
            for spell in self.a.ns.Data.Recipes[line].keys():
                self.assertTrue(self.lines(line, spell), (line, spell))

    def test_localized_npc_names(self):
        a = Addon(locale="deDE")
        self.assertEqual(a.ns.Model.NPCName(48), "Skelettkrieger")


class PrimarySourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = Addon()
        cls.a.login()
        cls.M, cls.R = cls.a.ns.Model, cls.a.ns.Data.Recipes

    def setUp(self):
        self.a.mock.itemNames[6307] = None

    def ps(self, line, spell, faction="Horde"):
        p = self.M.PrimarySource(self.R[line][spell], faction)
        return p.type, plain(p.text), p.more

    def test_trainer_with_cost(self):
        self.assertEqual(self.ps(171, 2329), ("trainer", "Trainer · 50" + COPPER, 0))

    def test_trainer_before_quests(self):
        self.assertEqual(self.ps(171, 1230564), ("trainer", "Trainer · 1" + SILVER, 7))

    def test_vendor_usable_by_faction(self):
        self.assertEqual(self.ps(171, 7255, "Horde"), ("vendor", "Vendor · Kzixx (Map 1431)", 2))
        self.assertEqual(self.ps(171, 7255, "Alliance"), ("vendor", "Vendor · Xandar Goodbeard (Map 1432)", 2))
        self.assertEqual(self.ps(171, 7255, None)[1], "Vendor · Xandar Goodbeard (Map 1432)")

    def test_vendor_only_other_faction_tagged(self):
        self.assertEqual(self.ps(171, 1251753, "Alliance"), ("vendor", "Vendor · Algernon (Map 1421) · Horde", 2))

    def test_drop_counts_totals(self):
        self.assertEqual(self.ps(171, 3230), ("drop", "Drop · Councilman Hartin (Map 1421)", 546 + 14))

    def test_drop_in_dungeon(self):
        self.assertEqual(self.ps(185, 1262978), ("drop", "Drop · Cookie (Instance 36)", 0))

    def test_object_auto_crafted_world_unknown(self):
        self.assertEqual(self.ps(185, 1319313), ("object", "Found in Recipe: Raw Plated Armorfish", 0))
        self.assertEqual(self.ps(185, 2538), ("auto", "Learned with the profession", 0))
        self.assertEqual(self.ps(171, 11456)[:2], ("crafted", "Crafted"))
        self.assertEqual(self.ps(202, 22704)[:2], ("worldObject", "World object"))
        self.assertEqual(self.ps(171, 2365), ("unknown", "Source unknown", 0))

    def test_unverified_primary(self):
        t, text, _ = self.ps(197, 24903)
        self.assertEqual((t, text), ("drop", "Drop (location unknown)"))

    def test_subtitle_learned_is_range(self):
        rec = self.R[171][3230]
        self.assertEqual(self.M.RowSubtitle(rec, 120, True, "Horde"), self.M.RangeText(rec, 120))

    def test_subtitle_missing(self):
        self.assertEqual(self.M.RowSubtitle(self.R[171][1251750], 120, False, "Horde"),
                         "|cffff2020Learn 180|r · Vendor · Apothecary Durelle (Map 1413) · +1 more")
        self.assertEqual(plain(self.M.RowSubtitle(self.R[171][7255], 120, False, "Horde")),
                         "Learn 100 · Vendor · Kzixx (Map 1431) · +2 more")
        self.assertNotIn("|cff", self.M.RowSubtitle(self.R[171][1251750], None, False, "Horde").split("·")[0])

    def test_subtitle_auto_has_no_learn(self):
        self.assertEqual(self.M.RowSubtitle(self.R[185][2538], 50, False, "Horde"), "Learned with the profession")

    def test_subtitle_container_name_loads(self):
        rec = self.a.lua.eval('{ src = {"container"}, containers = {{6307, 0.27}}, learn = 60 }')
        self.assertEqual(plain(self.M.RowSubtitle(rec, 100, False, "Horde")), "Learn 60 · Contained in a container")
        self.a.mock.itemNames[6307] = "Box"
        self.assertEqual(plain(self.M.RowSubtitle(rec, 100, False, "Horde")), "Learn 60 · Contained in Box")


if __name__ == "__main__":
    unittest.main()
