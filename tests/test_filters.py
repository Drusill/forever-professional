"""Recipe list filters: predicates in Model.lua, the saved filters in the window and the filter menu."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list  # noqa: E402

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


if __name__ == "__main__":
    unittest.main()
