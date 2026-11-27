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


def chars(dru_learned="[3275] = true", paly=True):
    """Logged-in Tester (Horde) holds Tailoring and knows 2963. Dru (Horde) holds First Aid, Alchemy and
    Cooking and knows 3275. Paly (Alliance) holds Cooking."""
    paly_entry = """
  ["Player-1-0000000D"] = { guid = "Player-1-0000000D", name = "Paly", class = "PALADIN", faction = "Alliance",
    level = 50, updated = 1795000000, learned = {}, professions = { [185] = { skill = 30, max = 75 } } },"""
    return """
ForeverProfessionalDB = { version = 2, chars = {
  ["Player-1-0000000B"] = { guid = "Player-1-0000000B", name = "Dru", class = "ROGUE", faction = "Horde",
    level = 40, updated = 1795000000, learned = { %s },
    professions = { [129] = { skill = 100, max = 150 }, [171] = { skill = 60, max = 75 },
                    [185] = { skill = 50, max = 75 } } },%s
} }
mock.professions = { { name = "Tailoring", icon = 136249, skill = 60, max = 75, line = 197 } }
mock.learned = { [2963] = true }
""" % (dru_learned, paly_entry if paly else "")


CHARS = chars()


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


NO_PALY = chars(paly=False)


def ready(setup=CHARS, schematics=SCHEMATICS):
    a = logged_in(setup, schematics)
    a.ns.UsedIn.Finish()
    return a


def groups(a, item):
    g = a.ns.UsedInGroups(item)
    return g and [(x.line, x.total, x.known) for x in lua_list(g)]


def recipes(a, item, line):
    for g in lua_list(a.ns.UsedInGroups(item)):
        if g.line == line:
            return [(r.spellID, r.known) for r in lua_list(g.recipes)]


class GroupsTest(unittest.TestCase):
    def test_fixture_without_paly(self):
        self.assertNotIn("Paly", NO_PALY)
        self.assertIn("Dru", NO_PALY)

    def test_groups(self):
        # Tester's Tailoring first, then by name: Alchemy, Cooking (Paly is Alliance), First Aid (Dru knows it).
        a = ready()
        self.assertEqual(groups(a, LINEN), [(197, 1, 1), (171, 1, 0), (185, 1, 0), (129, 1, 1)])

    def test_other_side_recipe_needs_a_holder_of_that_side(self):
        a = ready(NO_PALY)
        self.assertEqual(groups(a, LINEN), [(197, 1, 1), (171, 1, 0), (129, 1, 1)])

    def test_known_recipe_counts_whatever_its_side(self):
        a = ready(chars(dru_learned="[3275] = true, [2795] = true", paly=False))
        self.assertIn((185, 1, 1), groups(a, LINEN))

    def test_profession_nobody_holds(self):
        a = ready(schematics={**SCHEMATICS, 3932: [(LINEN, 1)]})   # Engineering: Target Dummy
        self.assertNotIn(202, [g[0] for g in groups(a, LINEN)])

    def test_recipes_sorted_by_learn_then_name(self):
        a = ready(schematics={**SCHEMATICS, 2401: [(BOLT, 1)]})   # Tailoring, learned at 70
        self.assertEqual(recipes(a, BOLT, 197), [(2387, False), (3915, False), (2401, False)])
        self.assertEqual(recipes(a, LINEN, 197), [(2963, True)])

    def test_unused_item(self):
        a = ready()
        self.assertEqual(groups(a, 765), [])

    def test_nil_before_ready(self):
        a = logged_in()
        self.assertIsNone(a.ns.UsedInGroups(LINEN))


def tailoring_spells(n):
    """The first n Tailoring spell IDs in the data (ascending), read from the baked file."""
    import re
    text = (pathlib.Path(__file__).resolve().parent.parent / "ForeverProfessional" / "Data" / "Recipes"
            / "Tailoring.lua").read_text(encoding="utf-8")
    return sorted(int(m) for m in re.findall(r"^\s*\[(\d+)\] = \{", text, re.M))[:n]


GREY, DIM, WHITE = (0.75, 0.75, 0.75), (0.5, 0.5, 0.5), (1, 1, 1)
HINT = "Hold Shift to list the recipes"
LINEN_LINES = ["Used in 1 Tailoring recipe (1 known)", "Used in 1 Alchemy recipe (0 known)",
               "Used in 1 Cooking recipe (0 known)", "Used in 1 First Aid recipe (1 known)"]


class TooltipLinesTest(unittest.TestCase):
    def setUp(self):
        self.a = ready()

    def hover(self, item, a=None):
        a = a or self.a
        a.run(f"GameTooltip:SetOwner(UIParent); GameTooltip:SetItemByID({item})")
        tt = a.g.GameTooltip
        return [plain(l) for l in lua_list(tt.lines)]

    def colors(self, a=None):
        return [tuple(round(v, 2) for v in c.values()) for c in lua_list((a or self.a).g.GameTooltip.colors)]

    def test_lines_and_hint(self):
        self.assertEqual(self.hover(LINEN), [" "] + LINEN_LINES + [HINT])
        self.assertEqual(self.colors()[1:], [GREY] * 4 + [DIM])

    def test_plural(self):
        self.assertEqual(self.hover(BOLT), [" ", "Used in 2 Tailoring recipes (0 known)", HINT])

    def test_shift_lists_names(self):
        self.a.run("mock.shift = true")
        self.assertEqual(self.hover(LINEN), [
            " ", LINEN_LINES[0], "  Spell 2963", LINEN_LINES[1], "  Spell 7183",
            LINEN_LINES[2], "  Spell 2795", LINEN_LINES[3], "  Spell 3275"])
        self.assertEqual(self.colors()[1:], [GREY, WHITE, GREY, DIM, GREY, DIM, GREY, WHITE])

    def test_shift_cap(self):
        spells = tailoring_spells(12)
        a = ready(schematics={s: [(THREAD, 1)] for s in spells})
        a.run("mock.shift = true")
        lines = self.hover(THREAD, a)
        self.assertEqual(lines[1], "Used in 12 Tailoring recipes (0 known)")
        self.assertEqual(len(lines), 2 + 10 + 1)
        self.assertEqual(lines[-1], "  and 2 more")

    def test_names_setting_off(self):
        self.a.run("ForeverProfessionalDB.tooltipUsedInNames = false")
        self.assertEqual(self.hover(LINEN), [" "] + LINEN_LINES)
        self.a.run("mock.shift = true")
        self.assertEqual(self.hover(LINEN), [" "] + LINEN_LINES)

    def test_setting_off(self):
        self.a.run("ForeverProfessionalDB.tooltipUsedIn = false")
        self.assertEqual(self.hover(LINEN), [])

    def test_not_ready(self):
        self.assertEqual(self.hover(LINEN, logged_in()), [])

    def test_unused_item(self):
        self.assertEqual(self.hover(765), [])

    def test_after_tracked_block(self):
        self.a.g._ns = self.a.ns
        self.a.run("_ns.TrackedLines = function() return { 'Needed for: X (1)', 'Tracked total: 0 / 1' } end")
        self.assertEqual(self.hover(LINEN), [" ", "Needed for: X (1)", "Tracked total: 0 / 1", " "]
                         + LINEN_LINES + [HINT])

    def test_tracked_setting_off(self):
        self.a.g._ns = self.a.ns
        self.a.run("_ns.TrackedLines = function() return { 'Needed for: X (1)', 'Tracked total: 0 / 1' } end; "
                   "ForeverProfessionalDB.tooltipTracked = false")
        self.assertEqual(self.hover(LINEN), [" "] + LINEN_LINES + [HINT])

    def test_owner_setting_off(self):
        a = ready()
        a.run("ForeverProfessionalDB.tooltipOwners = false")
        self.assertEqual(self.hover(6053, a), [])      # a Cooking recipe item: owner lines hidden
        a.run("ForeverProfessionalDB.tooltipOwners = true")
        self.assertNotEqual(self.hover(6053, a), [])

    def test_used_in_error_swallowed(self):
        self.a.g._ns = self.a.ns
        self.a.run("_ns.UsedInLines = function() error('boom') end")
        self.assertEqual(self.hover(LINEN), [])
        errors = lua_list(self.a.mock.errors)
        self.assertEqual(len(errors), 1)
        self.assertIn("boom", errors[0])


class ShiftRedrawTest(unittest.TestCase):
    def setUp(self):
        self.a = ready()
        self.a.run("_refreshes = 0; local r = GameTooltip.RefreshData; "
                   "GameTooltip.RefreshData = function(self) _refreshes = _refreshes + 1; return r(self) end")

    def lines(self):
        return [plain(l) for l in lua_list(self.a.g.GameTooltip.lines)]

    def hover(self, item=LINEN):
        self.a.run(f"GameTooltip:SetOwner(UIParent); GameTooltip:SetItemByID({item})")

    def press(self, key="LSHIFT", down=True):
        self.a.run(f"mock.shift = {'true' if down and 'SHIFT' in key else 'false'}; "
                   f"fire('MODIFIER_STATE_CHANGED', '{key}', {1 if down else 0})")

    def test_shift_down_and_up(self):
        self.hover()
        self.assertEqual(self.lines()[-1], HINT)
        self.press()
        self.assertIn("  Spell 2963", self.lines())
        self.assertNotIn(HINT, self.lines())
        self.press(down=False)
        self.assertEqual(self.lines()[-1], HINT)
        self.assertEqual(self.a.g._refreshes, 2)

    def test_right_shift(self):
        self.hover()
        self.press("RSHIFT")
        self.assertIn("  Spell 2963", self.lines())

    def test_other_modifier_ignored(self):
        self.hover()
        self.press("LCTRL")
        self.assertEqual(self.a.g._refreshes, 0)

    def test_hidden_tooltip_ignored(self):
        self.hover()
        self.a.run("GameTooltip:Hide()")
        self.press()
        self.assertEqual(self.a.g._refreshes, 0)

    def test_item_without_used_in_ignored(self):
        self.hover(765)
        self.press()
        self.assertEqual(self.a.g._refreshes, 0)

    def test_fallback_owner_on_enter(self):
        self.a.run("GameTooltip.RefreshData = false; _entered = 0; _bag = CreateFrame('Button'); "
                   "_bag:SetScript('OnEnter', function(self) _entered = _entered + 1; "
                   "GameTooltip:SetOwner(self); GameTooltip:SetItemByID(2589) end); "
                   "_bag.scripts.OnEnter(_bag)")
        self.press()
        self.assertEqual(self.a.g._entered, 2)
        self.assertIn("  Spell 2963", self.lines())

    def test_names_setting_off_no_redraw(self):
        self.a.run("ForeverProfessionalDB.tooltipUsedInNames = false")
        self.hover()
        self.press()
        self.assertEqual(self.a.g._refreshes, 0)

    def test_redraw_error_reported(self):
        self.hover()
        self.a.run("GameTooltip.RefreshData = function() error('boom') end")
        self.press()       # must not raise
        errors = lua_list(self.a.mock.errors)
        self.assertEqual(len(errors), 1)
        self.assertIn("boom", errors[0])


if __name__ == "__main__":
    unittest.main()
