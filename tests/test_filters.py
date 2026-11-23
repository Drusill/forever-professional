"""Recipe list filters: predicates in Model.lua, the saved filters in the window and the filter menu."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ALTS, Addon, lua_list  # noqa: E402

LEARNED = "mock.learned = { [2329] = true, [3170] = true, [7183] = true }"


def open_addon(setup=LEARNED):
    a = Addon(setup=setup)
    a.login()
    a.slash("")
    return a


def recipe_ids(entries):
    return [e.id for e in lua_list(entries) if e.kind == "recipe"]


class PinTest(unittest.TestCase):
    """All / Learned / Missing and LearnableCount, as they were before the filters."""

    def setUp(self):
        self.a = open_addon()
        self.UI = self.a.ns.UI
        self.total = len(list(self.a.ns.Data.Recipes[171].keys()))

    def test_segmented_pinned(self):
        self.UI.SetFilter("learned")
        self.assertEqual(sorted(recipe_ids(self.UI.entries)), [2329, 3170, 7183])
        self.assertEqual(self.UI.matchCount, 3)
        self.UI.SetFilter("missing")
        ids = recipe_ids(self.UI.entries)
        self.assertEqual(len(ids), self.total - 3)
        self.assertNotIn(2329, ids)
        self.assertEqual(self.UI.matchCount, self.total - 3)
        self.UI.SetFilter("all")
        self.assertEqual(len(recipe_ids(self.UI.entries)), self.total)
        self.assertEqual(self.UI.matchCount, self.total)

    def test_learnable_count_pinned(self):
        learned = {2329, 3170, 7183}
        expected = sum(1 for i, r in self.a.ns.Data.Recipes[171].items()
                       if i not in learned and (r.learn or 0) <= 120 and r.side in (None, "Horde"))
        self.assertEqual(self.a.ns.LearnableCount(171), expected)


class PredicateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = Addon(setup=LEARNED)
        cls.a.login()
        cls.a.g._ns = cls.a.ns
        cls.M = cls.a.ns.Model
        cls.total = len(list(cls.a.ns.Data.Recipes[171].keys()))

    def flat(self, predicates_lua):
        """Flatten Alchemy with the predicates built by a Lua expression (a list, or nil)."""
        return self.a.run(f"""
            local M = _ns.Model
            return M.Flatten(M.BuildTree(171), {{ predicates = {predicates_lua},
                isLearned = function(id) return _ns.IsLearned(id) end }})""")

    def test_learned_predicate(self):
        self.assertIsNone(self.M.LearnedPredicate("all"))
        learned, missing = self.M.LearnedPredicate("learned"), self.M.LearnedPredicate("missing")
        self.assertTrue(learned(1, None, True))
        self.assertFalse(learned(1, None, False))
        self.assertTrue(missing(1, None, False))
        self.assertFalse(missing(1, None, True))

    def test_flatten_with_predicates(self):
        entries, count, learned = self.flat('{ M.LearnedPredicate("learned") }')
        self.assertEqual(sorted(recipe_ids(entries)), [2329, 3170, 7183])
        self.assertEqual((count, learned), (3, 3))

    def test_flatten_and_of_predicates(self):
        entries, count, _ = self.flat('{ M.LearnedPredicate("learned"), function(id) return id == 2329 end }')
        self.assertEqual(recipe_ids(entries), [2329])
        self.assertEqual(count, 1)

    def test_flatten_empty_predicates(self):
        for preds in ("{}", "nil"):
            _, count, learned = self.flat(preds)
            self.assertEqual((count, learned), (self.total, 3))

    def test_predicates_get_the_recipe(self):
        entries, _, _ = self.flat("{ function(id, rec) return rec.creates == 2454 end }")
        self.assertEqual(recipe_ids(entries), [2329])

    def test_filter_counts_predicates(self):
        counts = self.a.run("""
            local isLearned = function(id) return _ns.IsLearned(id) end
            local a, b = _ns.Model.FilterCounts(171, isLearned, { function(id) return id == 2329 end })
            local c, d = _ns.Model.FilterCounts(171, isLearned)
            return a, b, c, d""")
        self.assertEqual(counts, (1, 1, self.total, 3))

    def test_can_learn_now(self):
        can = self.a.run("""
            local f = _ns.CanLearnNow
            return f({ learn = 120 }, 120, "Horde"), f({ learn = 121 }, 120, "Horde"), f({}, 0, "Horde"),
                f({ learn = 1 }, nil, "Horde"), f({ learn = 1, side = "Alliance" }, 300, "Horde"),
                f({ learn = 1, side = "Alliance" }, 300, "Alliance")""")
        self.assertEqual(can, (True, False, True, False, False, True))


FILTERS = "mock.learned = { [2329] = true, [3171] = true, [6617] = true }"
FILTERS_LEARNED = {2329, 3171, 6617}
SOURCE_KEY = {"trainer": "trainer", "auto": "trainer", "vendor": "vendor", "drop": "drop", "quest": "quest"}
SOURCES = ("trainer", "vendor", "drop", "quest", "other", "unknown")


def source_keys(rec):
    """Python mirror of Model.SourceKeys."""
    src = list(rec.src.values()) if rec.src else []
    return {SOURCE_KEY.get(s, "other") for s in src} or {"unknown"}


def lua_set(keys):
    return "{ " + ", ".join(f"{k} = true" for k in keys) + " }"


class MenuModelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = Addon(setup=FILTERS)
        cls.a.login()
        cls.a.g._ns = cls.a.ns
        cls.M = cls.a.ns.Model
        cls.recs = dict(cls.a.ns.Data.Recipes[171].items())

    def ids(self, keys=(), segmented="all", search="", skill=120, faction="Horde", line=171):
        entries, _, _ = self.a.run(f"""
            local M = _ns.Model
            local preds = M.FilterPredicates({lua_set(keys)}, {{ skill = {skill or "nil"}, faction = "{faction}" }})
            table.insert(preds, 1, M.LearnedPredicate("{segmented}") or function() return true end)
            return M.Flatten(M.BuildTree({line}), {{ predicates = preds, search = "{search}",
                isLearned = function(id) return _ns.IsLearned(id) end }})""")
        return set(recipe_ids(entries))

    def where(self, test):
        return {i for i, r in self.recs.items() if test(i, r)}

    def learnable(self, i, r):
        return i not in FILTERS_LEARNED and (r.learn or 0) <= 120 and r.side in (None, "Horde")

    def test_source_keys(self):
        cases = {7183: {"trainer"}, 6617: {"vendor"}, 3230: {"drop", "other"}, 1251744: {"quest"},
                 11452: {"unknown"}}
        for spell, keys in cases.items():
            got = {k for k, v in self.M.SourceKeys(self.recs[spell]).items() if v}
            self.assertEqual(got, keys, spell)

    def test_groups(self):
        groups = [(g.key, lua_list(g["items"])) for g in lua_list(self.M.FILTER_GROUPS)]
        self.assertEqual(groups, [("status", ["skillups", "learnable"]), ("source", list(SOURCES)),
                                  ("new", ["new"])])
        self.assertTrue(self.M.FILTER_GROUPS[1].needsProfession)

    def test_skillups(self):
        self.assertEqual(self.ids(["skillups"]), {3171, 6617})

    def test_learnable(self):
        ids = self.ids(["learnable"])
        self.assertEqual(ids, self.where(self.learnable))
        self.assertIn(3173, ids)
        self.assertNotIn(11452, ids)
        self.assertNotIn(2329, ids)

    def test_learnable_matches_learnable_count(self):
        for line in (171, 182):
            skill, _ = self.a.ns.CharSkill(line)
            self.assertEqual(len(self.ids(["learnable"], skill=skill, line=line)),
                             self.a.ns.LearnableCount(line), line)

    def test_status_or(self):
        self.assertEqual(self.ids(["skillups", "learnable"]), {3171, 6617} | self.where(self.learnable))

    def test_each_source(self):
        for key in SOURCES:
            expected = self.where(lambda i, r: key in source_keys(r))
            self.assertTrue(expected, key)
            self.assertEqual(self.ids([key]), expected, key)

    def test_sources_or(self):
        self.assertEqual(self.ids(["vendor", "drop"]),
                         self.where(lambda i, r: source_keys(r) & {"vendor", "drop"}))

    def test_new(self):
        expected = self.where(lambda i, r: r.new)
        self.assertTrue(expected)
        self.assertEqual(self.ids(["new"]), expected)

    def test_and_across_groups(self):
        self.assertEqual(self.ids(["vendor", "new"]),
                         self.where(lambda i, r: r.new and "vendor" in source_keys(r)))
        self.assertEqual(self.ids(["skillups", "vendor"]), {6617})

    def test_with_search(self):
        self.assertEqual(self.ids(["vendor"], search="Spell 6617"), {6617})
        self.assertEqual(self.ids(["vendor"], search="Spell 3171"), set())

    def test_with_segmented(self):
        self.assertEqual(self.ids(["learnable"], segmented="learned"), set())
        self.assertEqual(self.ids(["skillups"], segmented="missing"), set())
        self.assertEqual(self.ids(["learnable"], segmented="missing"), self.ids(["learnable"]))

    def test_status_skipped_without_skill(self):
        n = self.a.run("return #_ns.Model.FilterPredicates({ skillups = true, vendor = true }, {})")
        self.assertEqual(n, 1)
        self.assertEqual(self.ids(["skillups", "learnable"], skill=None), set(self.recs))

    def test_active_filter_count(self):
        count = self.a.run("""
            local f = _ns.Model.ActiveFilterCount
            local four = { skillups = true, vendor = true, drop = true, new = true }
            return f(four, true), f(four, false), f({ bogus = true }, true), f({}, true), f(nil, true)""")
        self.assertEqual(count, (4, 3, 0, 0, 0))


class WindowFilterTest(unittest.TestCase):
    def setUp(self):
        self.a = open_addon(FILTERS)
        self.UI = self.a.ns.UI
        self.L = self.a.ns.L
        self.recs = dict(self.a.ns.Data.Recipes[171].items())

    def ids(self):
        return set(recipe_ids(self.UI.entries))

    def vendor_ids(self):
        return {i for i, r in self.recs.items() if "vendor" in source_keys(r)}

    def segment_counts(self):
        b = {x.key: x for x in lua_list(self.UI.filterButtons)}
        return tuple(int(b[k].count.text) for k in ("all", "learned", "missing"))

    def test_set_option_filters_list(self):
        self.UI.SetFilterOption("skillups", True)
        self.assertEqual(self.ids(), {3171, 6617})
        self.assertTrue(self.a.g.ForeverProfessionalDB.filters.skillups)
        self.UI.SetFilterOption("skillups", False)
        self.assertEqual(self.ids(), set(self.recs))
        self.assertIsNone(self.a.g.ForeverProfessionalDB.filters.skillups)

    def test_saved_across_reload(self):
        a = open_addon('ForeverProfessionalDB = { version = 2, filters = { vendor = true } }; ' + FILTERS)
        self.assertEqual(set(recipe_ids(a.ns.UI.entries)), self.vendor_ids())

    def test_unknown_saved_keys_ignored(self):
        a = open_addon('ForeverProfessionalDB = { version = 2, filters = { bogus = true, vendor = true } }; '
                       + FILTERS)
        self.assertEqual(set(recipe_ids(a.ns.UI.entries)), self.vendor_ids())

    def test_segmented_counts_follow_menu_not_search(self):
        total = len(self.recs)
        self.assertEqual(self.segment_counts(), (total, 3, total - 3))
        self.UI.SetFilterOption("vendor", True)
        vendors = len(self.vendor_ids())
        self.assertEqual(self.segment_counts(), (vendors, 1, vendors - 1))
        self.UI.SetSearch("Spell 6617")
        self.assertEqual(self.segment_counts(), (vendors, 1, vendors - 1))
        self.assertEqual(self.ids(), {6617})

    def test_header_stat_unchanged(self):
        self.UI.SetFilterOption("vendor", True)
        self.assertEqual(self.UI.header.recipesText.text, f"3 / {len(self.recs)}")

    def test_category_counts_follow_filters(self):
        self.UI.SetFilterOption("vendor", True)
        top = [e for e in lua_list(self.UI.entries) if e.kind == "header" and e.depth == 0]
        self.assertEqual(sum(e.count for e in top), len(self.vendor_ids()))
        self.assertEqual(self.UI.matchCount, len(self.vendor_ids()))

    def test_status_ignored_without_profession(self):
        self.UI.SetFilterOption("skillups", True)
        self.UI.SelectProfession(185)   # Tester has no Cooking
        self.assertEqual(self.ids(), set(self.a.ns.Data.Recipes[185].keys()))
        self.assertTrue(self.a.g.ForeverProfessionalDB.filters.skillups)
        self.UI.SelectProfession(171)
        self.assertEqual(self.ids(), {3171, 6617})

    def test_faction_rule_with_alts(self):
        a = open_addon(ALTS + "; " + FILTERS)
        UI = a.ns.UI
        UI.SetFilterOption("learnable", True)
        UI.SelectProfession(185)
        UI.SetChar("Player-1-0000000D")   # Paly, Alliance, Cooking 30
        self.assertIn(2795, recipe_ids(UI.entries))
        UI.SetChar("Player-1-0000000C")   # Dru (Druid), Horde, Cooking 50
        ids = recipe_ids(UI.entries)
        self.assertTrue(ids)
        self.assertNotIn(2795, ids)

    def test_filters_keep_collapsed(self):
        self.UI.ToggleCategory(2449)
        self.UI.SetFilterOption("vendor", True)
        header = next(e for e in lua_list(self.UI.entries) if e.kind == "header" and e.cat == 2449)
        self.assertTrue(header.collapsed)

    def test_empty_state_filtered(self):
        self.UI.SetFilter("missing")
        self.UI.SetFilterOption("skillups", True)
        self.assertEqual(self.ids(), set())
        empty = self.UI.list.empty
        self.assertTrue(empty.shown)
        self.assertEqual(empty.text, self.L.NO_RESULTS_FILTERED)
        clear = self.UI.list.clearButton
        self.assertTrue(clear.shown)
        Addon.call(clear, "Click")
        self.assertEqual(list(self.a.g.ForeverProfessionalDB.filters.keys()), [])
        self.assertEqual(self.UI.state.filter, "missing")
        self.assertEqual(len(self.ids()), len(self.recs) - 3)
        self.assertFalse(empty.shown)
        self.assertFalse(clear.shown)

    def test_empty_state_plain(self):
        self.UI.SetSearch("zzzz")
        self.assertTrue(self.UI.list.empty.shown)
        self.assertEqual(self.UI.list.empty.text, self.L.NO_RESULTS)
        self.assertFalse(self.UI.list.clearButton.shown)


if __name__ == "__main__":
    unittest.main()
