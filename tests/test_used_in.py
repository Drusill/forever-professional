"""The "Used in" reagent tooltip: the reverse reagent index in Model.lua, its background build, the
per-profession counts and the tooltip lines in UsedIn.lua."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list, plain  # noqa: E402

LINEN, BOLT, THREAD, SWIFT, WOOL = 2589, 2996, 2320, 2452, 2592

# {spellID: [(itemID, count, alternatives...)]}. Real spells; Linen in 7183 and 2795 is made up, to spread
# Linen over four professions. 2795 is Alliance-only in the data.
SCHEMATICS = {
    2963: [(LINEN, 2)],                 # Tailoring: Bolt of Linen Cloth
    3275: [(LINEN, 1)],                 # First Aid: Linen Bandage
    2387: [(BOLT, 1), (THREAD, 1)],     # Tailoring: Linen Cloak
    3915: [(BOLT, 1), (THREAD, 1)],     # Tailoring: Brown Linen Shirt
    7183: [(SWIFT, 1), (LINEN, 1)],     # Alchemy: Elixir of Minor Defense
    2795: [(LINEN, 1)],                 # Cooking: Beer Basted Boar Ribs (Alliance)
}

DRU, PALY = "Player-1-0000000B", "Player-1-0000000D"
# Logged-in Tester (Horde) holds Tailoring and knows 2963. Dru (Horde) holds First Aid, Alchemy and Cooking
# and knows 3275. Paly (Alliance) holds Cooking.
CHARS = """
ForeverProfessionalDB = { version = 2, chars = {
  ["Player-1-0000000B"] = { guid = "Player-1-0000000B", name = "Dru", class = "ROGUE", faction = "Horde",
    level = 40, updated = 1795000000, learned = { [3275] = true },
    professions = { [129] = { skill = 100, max = 150 }, [171] = { skill = 60, max = 75 },
                    [185] = { skill = 50, max = 75 } } },
  ["Player-1-0000000D"] = { guid = "Player-1-0000000D", name = "Paly", class = "PALADIN", faction = "Alliance",
    level = 50, updated = 1795000000, learned = {}, professions = { [185] = { skill = 30, max = 75 } } },
} }
mock.professions = { { name = "Tailoring", icon = 136249, skill = 60, max = 75, line = 197 } }
mock.learned = { [2963] = true }
"""


def seeded(schematics=SCHEMATICS):
    """Lua that gives each listed spell its slots; unlisted spells have no schematic."""
    rows = ", ".join("[%d] = { %s }" % (spell, ", ".join("{ %s }" % ", ".join(map(str, slot)) for slot in slots))
                     for spell, slots in schematics.items())
    return "mock.onlySchematics = true; mock.schematics = { %s }" % rows


def logged_in(setup=CHARS, schematics=SCHEMATICS):
    """Schematics are seeded before login, so a build started at login reads them."""
    a = Addon(setup=setup + "; " + seeded(schematics))
    a.login()
    return a


def build(a):
    """A finished index, built synchronously."""
    b = a.ns.Model.NewUsedInIndex()
    while not b.Step(b, 500):
        pass
    return b


class IndexTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.M = self.a.ns.Model

    def items(self, spell):
        return lua_list(self.M.ReagentItems(spell))

    def lookup(self, b, item):
        t = b.Lookup(b, item)
        return t and [(e.line, e.spellID) for e in lua_list(t)]

    def test_reagent_items_all_slots(self):
        self.assertEqual(self.items(7183), [SWIFT, LINEN])

    def test_reagent_items_alternatives_and_distinct(self):
        self.a.run("mock.schematics[2387] = { {2996, 1, 2997}, {2320, 1}, {2996, 2} }")
        self.assertEqual(self.items(2387), [BOLT, 2997, THREAD])

    def test_reagent_items_missing(self):
        self.assertIsNone(self.M.ReagentItems(999999))
        self.a.run("mock.schematics[2963] = {}")
        self.assertEqual(self.items(2963), [])

    def test_reagent_items_not_cached(self):
        self.items(2963)
        self.assertIsNone(self.M.schematics[2963])

    def test_reagent_items_uses_cache(self):
        self.M.Schematic(2963)
        before = self.a.mock.schematicCalls
        self.assertEqual(self.items(2963), [LINEN])
        self.assertEqual(self.a.mock.schematicCalls, before)

    def test_schematics_untouched(self):
        build(self.a)
        self.assertEqual(self.a.lua.eval("function(t) return next(t) end")(self.M.schematics), None)

    def test_batch_size(self):
        b = self.M.NewUsedInIndex()
        before = self.a.mock.schematicCalls or 0
        self.assertFalse(b.Step(b, 10))
        self.assertEqual(b.read, 10)
        self.assertEqual(self.a.mock.schematicCalls - before, 10)
        self.assertFalse(b.Done(b))

    def test_index_lookup(self):
        b = build(self.a)
        self.assertTrue(b.Done(b))
        self.assertEqual(self.lookup(b, LINEN), [(129, 3275), (171, 7183), (185, 2795), (197, 2963)])
        self.assertEqual(self.lookup(b, BOLT), [(197, 2387), (197, 3915)])
        self.assertIsNone(self.lookup(b, 765))

    def test_counters(self):
        b = build(self.a)
        total = sum(len(lua_list(self.a.lua.eval("function(t) local o = {} for k in pairs(t) do o[#o+1] = k end "
                                                 "return o end")(r)))
                    for r in self.a.ns.Data.Recipes.values())
        self.assertEqual(b.read, total)
        self.assertEqual(b.missing, total - len(SCHEMATICS))
        self.assertEqual(b["items"], 4)          # Linen, Bolt, Thread, Swiftthistle
        self.assertEqual(b.entries, 9)

    def test_done_reads_nothing_more(self):
        b = build(self.a)
        before = self.a.mock.schematicCalls
        self.assertTrue(b.Step(b, 10))
        self.assertEqual(self.a.mock.schematicCalls, before)


def one_frame(a):
    """Run the timers queued so far once, like one client frame."""
    a.run("local t = mock.timers; mock.timers = {}; for _, f in ipairs(t) do f() end")


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.U = self.a.ns.UsedIn

    def stats(self):
        return self.U.stats

    def test_waits_after_login(self):
        a = Addon(setup=CHARS + "; " + seeded())
        a.run(f'fire("ADDON_LOADED", "ForeverProfessional"); fire("PLAYER_LOGIN")')
        self.assertFalse(a.ns.UsedIn.Ready())
        self.assertEqual(a.ns.UsedIn.stats.frames, 0)
        self.assertEqual(a.ns.UsedIn.DELAY, 5)

    def test_started_by_login(self):
        # login() flushes 20 timer rounds: the build is under way, a batch per round, not done yet.
        read = self.stats().read
        self.assertGreater(read, 0)
        self.assertEqual(read % self.U.BATCH, 0)
        self.assertFalse(self.U.Ready())
        self.assertTrue(self.U.Building())

    def test_one_batch_per_frame(self):
        read = self.stats().read
        one_frame(self.a)
        self.assertEqual(self.stats().read, read + 40)
        self.assertEqual(self.U.BATCH, 40)

    def test_runs_to_the_end(self):
        while not self.U.Ready():
            one_frame(self.a)
        self.assertFalse(self.U.Building())
        self.assertEqual(len(lua_list(self.a.mock.timers)), 0)

    def test_not_started_when_off(self):
        a = logged_in(CHARS + "; ForeverProfessionalDB.tooltipUsedIn = false")
        self.assertEqual(a.ns.UsedIn.stats.frames, 0)
        self.assertFalse(a.ns.UsedIn.Building())

    def test_stop_and_resume(self):
        self.U.Stop()
        read = self.stats().read
        self.a.run("flush()")
        self.assertEqual(self.stats().read, read)
        self.assertFalse(self.U.Building())
        self.U.Start()
        one_frame(self.a)
        self.assertEqual(self.stats().read, read + 40)

    def test_start_twice_one_chain(self):
        self.U.Start()
        self.U.Start()
        read = self.stats().read
        one_frame(self.a)
        self.assertEqual(self.stats().read, read + 40)

    def test_finish_and_stats(self):
        self.U.Finish()
        self.assertTrue(self.U.Ready())
        s = self.stats()
        b = self.U.Index()
        self.assertEqual(s.read, b.total)
        self.assertEqual(s.missing, b.total - len(SCHEMATICS))
        self.assertEqual(s["items"], 4)
        self.assertEqual(s.entries, 9)
        self.assertGreaterEqual(s.frames, 20)
        for key in ("totalMs", "slowestMs", "wallSeconds", "memBefore", "memAfter"):
            self.assertGreaterEqual(s[key], 0, key)
        self.assertGreaterEqual(s.totalMs, s.slowestMs)

    def test_lookup_only_when_ready(self):
        self.assertIsNone(self.U.Lookup(LINEN))
        self.U.Finish()
        self.assertEqual(len(lua_list(self.U.Lookup(LINEN))), 4)


if __name__ == "__main__":
    unittest.main()
