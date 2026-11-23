"""Unit tests for the data pipeline. Run from the repo root: python -m unittest discover tools/tests"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fpdata import client_tables, emit_lua, merge, report, whatstraining  # noqa: E402
from fpdata.foreverdb import ForeverDB  # noqa: E402
from fpdata.luaparse import LuaParseError, Ref, parse_value  # noqa: E402

WT_SAMPLE = r'''
local _, ns = ...
ns.Recipes = ns.Recipes or {}
ns.Recipes[165] = {
    { spell = 2149, skill = 1, creates = 2302 },
    { spell = 1255143, skill = 35, creates = 252427, teach = 252764, source = { "vendor", "trainer" }, cost = 500, bound = false, vendors = { { npc = 258306, area = 1537, faction = "Alliance" } } },
    { spell = 1250796, skill = 165, creates = 250347, teach = 250383, source = { "vendor" }, merchantFavor = 120, bound = true, reputation = { 2586, 5, ns.L.FACTION_2586 }, vendors = { { npc = 248196, area = 17, faction = "Horde" } } },
    { spell = 1297126, skill = 260, creates = 275585, teach = 275586, source = { "vendor" }, bound = false }, -- no NPC known
    { spell = 28327, skill = 275, creates = 22728, teach = 22729, source = { "quest", "vendor" }, quests = { { id = 9249, level = 45 } }, vendors = { { npc = 14828, areas = { 12, 215 } } } },
    { spell = 3104, skill = 50, rank = "Journeyman", source = { "trainer" }, cost = 500, level = 10 },
}
'''


def fake_fdb():
    return ForeverDB({
        "meta": {"hash": "abc", "build": "2026-11-20"},
        "item": {"252764": ["Pattern: Moonglow Boots", None, None, None, 9, 1],
                 "273096": ["Blueprint: Tanning Rack", None, None, None, 9, 1],
                 "275586": ["Pattern: Bileblister Claws", None, None, None, 9, 1],
                 "999": ["Not a recipe", None, None, None, 4, 0]},
        "ieff": {"252764": [[402265, 0, -1], [1255143, 6, 0]],
                 "273096": [[402265, 0, -1], [1263031, 6, 0]],
                 "999": [[1263031, 6, 0]]},
        "vend": {"252764": [258306]},
        "drop": {"252764": [[258306, 0], [111, 250]], "273096": [[3886, 0]]},
        "rew": {"22729": [9249]},
        "npc": {"258306": ["Granny Finespindle", "Leatherworking Recipes", 24, 24, None],
                "3886": ["Razorclaw the Butcher", None, 22, 22, 1], "111": ["Some Mob", None, 10, 11, 0]},
        "nfac": {"258306": "A"},
        "quest": {"9249": ["Quest Name", 45, 40]},
        "qg": {"9249": ["c500"]},
        "spz": {"c258306": {"1455": [392, 336]}, "c111": {"1411": [100, 200, 110, 210], "1412": [5, 5]}},
        "spw": {"c3886": [[33, -203, 2258]]},
        "loc": {"deDE": {"npc": {"111": "Irgendein Mob"}}},
    })


def sla_rows():
    row = lambda line, low, high, cat, acq=0: [{"skillLine": line, "minRank": 1, "trivialLow": low, "trivialHigh": high,
                                                 "category": cat, "acquire": acq, "skillupLine": 0}]
    return {2149: row(165, 40, 70, 2560, 1), 1255143: row(165, 40, 40, 2560), 1263031: row(165, 125, 125, 2574),
            1250796: row(171, 170, 175, 2450), 1297126: row(165, 270, 290, 2580)}


class LuaParseTests(unittest.TestCase):
    def test_values(self):
        v, _ = parse_value('{ a = 1, b = "x\\"y", c = { 1, 2.5, -3 }, d = true, e = nil, [10] = 0x1F, f = [[long]] }')
        self.assertEqual(v, {"a": 1, "b": 'x"y', "c": [1, 2.5, -3], "d": True, "e": None, 10: 31, "f": "long"})

    def test_refs_and_comments(self):
        v, _ = parse_value("{ 2758, 5, ns.L.FACTION_2758 } -- trailing")
        self.assertEqual(v[:2], [2758, 5])
        self.assertIsInstance(v[2], Ref)
        v, _ = parse_value("{ --[[ block ]] 1, -- line\n 2 }")
        self.assertEqual(v, [1, 2])

    def test_mixed_table(self):
        v, _ = parse_value("{ 7, 8, x = 1 }")
        self.assertEqual(v, {"x": 1, 1: 7, 2: 8})

    def test_unterminated(self):
        with self.assertRaises(LuaParseError):
            parse_value("{ 1, 2")


class WhatsTrainingTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        with open(os.path.join(self.dir, "Leatherworking.lua"), "w", encoding="utf-8") as f:
            f.write(WT_SAMPLE)
        self.recipes, self.ranks = whatstraining.load(self.dir)

    def test_split_ranks(self):
        self.assertEqual(len(self.recipes), 5)
        self.assertEqual([r["spell"] for r in self.ranks], [3104])

    def test_fields(self):
        r = {x["spell"]: x for x in self.recipes}
        self.assertEqual(r[1250796]["reputation"], {"faction": 2586, "standing": 5})
        self.assertEqual(r[1250796]["merchantFavor"], 120)
        self.assertEqual(r[1255143]["vendors"], [{"npc": 258306, "areas": [1537], "faction": "Alliance"}])
        self.assertEqual(r[28327]["vendors"][0]["areas"], [12, 215])
        self.assertEqual(r[28327]["quests"][0]["id"], 9249)


class MergeTests(unittest.TestCase):
    def setUp(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "Leatherworking.lua"), "w", encoding="utf-8") as f:
            f.write(WT_SAMPLE)
        recipes, ranks = whatstraining.load(d)
        recipes.append({"spell": 1263031, "skillLine": 165, "learn": 125, "creates": 279941, "count": None,
                        "teach": None, "sources": ["drop"], "trainerCost": None, "bound": False, "side": None,
                        "merchantFavor": None, "autoLearned": False, "rank": None, "level": None,
                        "reputation": None, "vendors": [], "quests": []})
        self.cat = merge.build(recipes, ranks, fake_fdb(), sla_rows(), {}, {})
        self.r = {x["spell"]: x for x in self.cat["recipes"]}

    def test_thresholds(self):
        r = self.r[2149]
        self.assertEqual((r["learn"], r["yellow"], r["green"], r["grey"], r["category"]), (1, 40, 55, 70, 2560))
        self.assertEqual(self.r[2149]["sources"], ["auto"])

    def test_vendor_not_counted_as_drop(self):
        r = self.r[1255143]
        self.assertEqual(r["vendors"], [258306])
        self.assertEqual(r["drops"], [(111, 2.5)])
        self.assertEqual(r["sources"], ["trainer", "vendor", "drop"])

    def test_teach_from_item_effect(self):
        r = self.r[1263031]
        self.assertEqual(r["teach"], [273096])  # item 999 is not a recipe item
        self.assertEqual(r["drops"], [(3886, None)])

    def test_unverified_claim(self):
        r = self.r[1297126]
        self.assertEqual(r["unverified"], ["vendor"])
        self.assertIn("vendor", r["sources"])
        self.assertFalse(r["unknown"])

    def test_quest_from_both_sources(self):
        r = self.r[28327]
        self.assertEqual(r["quests"], [9249])
        self.assertEqual(self.cat["quests"][9249]["giverNpcs"], [500])

    def test_entities(self):
        npcs = self.cat["npcs"]
        self.assertEqual(npcs[258306]["pos"], {"map": 1455, "x": 39.2, "y": 33.6, "spawns": 1})
        self.assertEqual(npcs[111]["pos"]["map"], 1411)  # map with the most spawns
        self.assertEqual(npcs[3886]["pos"], {"instance": 33})
        self.assertEqual(npcs[248196]["faction"], "H")  # from WhatsTraining when ForeverDB has none

    def test_overrides(self):
        merge.apply_overrides(self.cat["recipes"], {"recipes": {"1297126": {"vendors": [123], "_note": "x"},
                                                                "_skip": {}}})
        r = self.r[1297126]
        self.assertEqual(r["vendors"], [123])
        self.assertEqual(r["unverified"], [])


def sample_fdb():
    return ForeverDB({
        "drop": {"500": [[1, 909], [2, 579], [3, 388], [4, 120], [5, 1000], [6, 1000], [7, 0], [8, 300], [9, 1429]]},
        "seen": {"c1": {"500": [1, 11]},   # rate came from 1 of 11 -> set aside
                 "c2": {"500": [7, 121]},  # 5.785% stored as 579, 7 drops -> kept
                 "c3": {"500": [1, 11]},   # 3.88% came from another source -> kept
                 "c5": {"500": [4, 40]},   # 4 drops -> set aside
                 "c6": {"500": [5, 50]},   # 5 drops -> kept
                 "c7": {"500": [1, 5]},    # already unknown, not counted
                 "c8": {"500": [0, 0]},    # no kills: no usable count
                 "c9": {"500": [1, 7]}},   # 14.2857% stored rounded up as 1429 -> set aside
    })


class ReportTests(unittest.TestCase):
    def section(self, text, title):
        """Lines of the report section whose heading starts with title, up to the next heading."""
        out, inside = [], False
        for line in text.splitlines():
            if line.startswith("## "):
                inside = line.startswith(title)
            if inside:
                out.append(line)
        return out

    def test_learn_above_yellow(self):
        # The learn level comes from WhatsTraining (Classic), the thresholds from Forever's client (#11).
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "Leatherworking.lua"), "w", encoding="utf-8") as f:
            f.write(WT_SAMPLE)
        recipes, ranks = whatstraining.load(d)
        fdb = fake_fdb()
        cat = merge.build(recipes, ranks, fdb, sla_rows(), {}, {})
        r = {x["spell"]: x for x in cat["recipes"]}
        r[1255143]["learn"] = 45                          # yellow 40: above
        self.assertEqual((r[2149]["learn"], r[2149]["yellow"]), (1, 40))  # below: not listed
        r[1250796]["learn"] = r[1250796]["yellow"]        # equal: not listed
        text = report.build_report(cat, {"sources": {}}, fdb)
        lines = self.section(text, "## Learn level above the yellow threshold")
        self.assertEqual(lines[0], "## Learn level above the yellow threshold (1)")
        entries = [x for x in lines if x.startswith("- ")]
        self.assertEqual(entries, ["- Leatherworking `1255143` Pattern: Moonglow Boots: learn 45, yellow 40"])


class SmallSampleTests(unittest.TestCase):
    def test_small_sample_rates(self):
        fdb = sample_fdb()
        self.assertEqual(fdb.drops(500), [(1, None), (2, 5.79), (3, 3.88), (4, 1.2),
                                          (5, None), (6, 10.0), (7, None), (8, 3.0), (9, None)])
        self.assertEqual(fdb.small_samples, {(500, 1), (500, 5), (500, 9)})

    def test_small_samples_recorded_once(self):
        fdb = sample_fdb()
        fdb.drops(500)
        fdb.drops(500)
        self.assertEqual(len(fdb.small_samples), 3)


class CategoryTests(unittest.TestCase):
    def test_tree_from_wago_csv(self):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "TradeSkillCategory.1.60.1.70959.csv")
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write("Name_lang,HordeName_lang,ID,ParentTradeSkillCategoryID,SkillLineID,OrderIndex,Flags\n"
                    "Leatherworking,,2550,0,2945,0,0\nArmor,,2559,2550,2945,1,0\nBoots,,2560,2559,2945,2,0\nUnused,,9999,0,2945,9,0\n")
        cats = client_tables.load_trade_skill_categories(client_tables.find_table(d, "TradeSkillCategory", "1.60.1.70959"))
        tree = merge.category_tree([{"category": 2560}, {"category": None}], cats)
        self.assertEqual(sorted(tree), [2550, 2559, 2560])
        self.assertEqual(tree[2560]["parent"], 2559)
        self.assertEqual(tree[2559]["name"], "Armor")


class EmitTests(unittest.TestCase):
    def test_lua_serializer(self):
        self.assertEqual(emit_lua.lua({"a": 1, "end": 2, 3: [1, None], "s": 'q"', "f": 1.5, "n": None}),
                         '{ a = 1, ["end"] = 2, [3] = { 1, nil }, s = "q\\"", f = 1.5 }')
        self.assertEqual(emit_lua.lua(2.0), "2")

    def test_recipe_table(self):
        t = emit_lua.recipe_table({"learn": 1, "yellow": 40, "green": 55, "grey": 70, "category": 2560, "teach": [7],
                                   "sources": ["drop"], "drops": [(1, 2.5), (2, None)], "dropTotal": 5,
                                   "new": True, "unknown": False})
        self.assertEqual(t["teach"], 7)
        self.assertEqual(t["drops"], [[1, 2.5], [2]])
        self.assertEqual(t["dropTotal"], 5)
        self.assertNotIn("unknown", t)

    def test_emit_files(self):
        d = tempfile.mkdtemp()
        recipes, ranks = whatstraining.load(self._wt_dir())
        cat = merge.build(recipes, ranks, fake_fdb(), sla_rows(), {}, {})
        cat["locales"] = {"deDE": {"npc": {111: "Irgendein Mob"}, "obj": {}, "quest": {}}}
        files = emit_lua.emit(cat, d, "test", {"client": "1.60.1.70959", "sources": {}})
        self.assertIn("Recipes/Leatherworking.lua", files)
        self.assertIn("Locales/deDE.lua", files)
        with open(os.path.join(d, "Data.xml"), encoding="utf-8") as f:
            xml = f.read()
        self.assertIn('<Script file="Recipes\\Leatherworking.lua"/>', xml)

    def _wt_dir(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "Leatherworking.lua"), "w", encoding="utf-8") as f:
            f.write(WT_SAMPLE)
        return d


if __name__ == "__main__":
    unittest.main()
