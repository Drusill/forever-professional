"""Window and recipe list tests: the addon driven through /fp and its widgets, with real data."""
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


class WindowTest(unittest.TestCase):
    def setUp(self):
        self.a = open_addon()
        self.UI = self.a.ns.UI

    def entries(self):
        return lua_list(self.UI.entries)

    def recipe_ids(self):
        return [e.id for e in self.entries() if e.kind == "recipe"]

    def visible_rows(self):
        return [r for r in lua_list(self.UI.list.rows) if r.shown]

    def test_slash_toggles_window(self):
        f = self.a.g.ForeverProfessionalFrame
        self.assertTrue(f.shown)
        self.a.slash("")
        self.assertFalse(f.shown)
        self.a.slash("")
        self.assertTrue(f.shown)

    def test_escape_closes(self):
        self.assertIn("ForeverProfessionalFrame", lua_list(self.a.g.UISpecialFrames))

    def test_tabs_one_per_profession(self):
        tabs = lua_list(self.UI.tabs)
        self.assertEqual(len(tabs), 12)
        names = [t.label.text for t in tabs]
        self.assertEqual(names[0], "Alchemy")  # player's name for it
        self.assertEqual(names[-4:], ["Fishing", "Herbalism", "Mining", "Skinning"])
        alchemy = tabs[0]
        self.assertEqual(alchemy.skill.text, "Skill 120 / 150")
        self.assertTrue(alchemy.selectedTex.shown)
        cooking = next(t for t in tabs if t.line == 185)
        self.assertEqual(cooking.skill.text, "Not learned")

    def test_defaults_to_first_player_profession(self):
        self.assertEqual(self.UI.state.line, 171)
        a = open_addon(LEARNED + "; mock.professions = { { name='Tailoring', skill=1, max=75, line=197 } }")
        self.assertEqual(a.ns.UI.state.line, 197)

    def test_defaults_to_first_tab_without_professions(self):
        a = open_addon("mock.professions = {}")
        self.assertEqual(a.ns.UI.state.line, 171)  # Alchemy sorts first

    def test_list_rows_rendered(self):
        rows = self.visible_rows()
        self.assertGreater(len(rows), 10)
        first = rows[0]
        self.assertEqual(first.entry.kind, "header")
        self.assertEqual(first.label.text, "Camping")
        recipe_row = next(r for r in rows if r.entry.kind == "recipe")
        self.assertIn("Spell ", recipe_row.label.text)
        self.assertIsNotNone(recipe_row.icon.texture)
        self.assertTrue(recipe_row.range.text)

    def test_learned_check_marks(self):
        self.UI.SetFilter("learned")
        rows = [r for r in self.visible_rows() if r.entry.kind == "recipe"]
        self.assertEqual(len(rows), 3)
        for r in rows:
            self.assertTrue(r.check.texture.endswith("ReadyCheck-Ready"))
        self.UI.SetFilter("missing")
        rows = [r for r in self.visible_rows() if r.entry.kind == "recipe"]
        self.assertTrue(rows)
        for r in rows:
            self.assertTrue(r.check.texture.endswith("ReadyCheck-NotReady"))

    def test_filter_buttons(self):
        total = len(list(self.a.ns.Data.Recipes[171].keys()))
        self.assertEqual(len(self.recipe_ids()), total)
        buttons = {b.key: b for b in lua_list(self.UI.filterButtons)}
        self.a.call(buttons["learned"], "Click")
        self.assertEqual(sorted(self.recipe_ids()), [2329, 3170, 7183])
        self.assertEqual(self.a.g.ForeverProfessionalDB.filter, "learned")
        self.a.call(buttons["missing"], "Click")
        self.assertEqual(len(self.recipe_ids()), total - 3)
        self.assertNotIn(2329, self.recipe_ids())
        self.a.call(buttons["all"], "Click")
        self.assertEqual(len(self.recipe_ids()), total)

    def test_counter(self):
        total = len(list(self.a.ns.Data.Recipes[171].keys()))
        self.assertEqual(self.a.g.ForeverProfessionalFrame.counter.text, f"3 / {total} learned")

    def test_search_box(self):
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "spell 3230")
        self.assertEqual(self.recipe_ids(), [3230])
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "no such recipe")
        self.assertEqual(self.recipe_ids(), [])
        self.assertTrue(self.UI.list.empty.shown)
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "")
        self.assertFalse(self.UI.list.empty.shown)
        self.assertGreater(len(self.recipe_ids()), 100)

    def test_header_click_collapses(self):
        header_row = self.visible_rows()[0]
        cat = header_row.entry.cat
        before = len(self.entries())
        self.a.call(header_row, "Click")
        self.assertTrue(self.a.g.ForeverProfessionalDB.collapsed[cat])
        self.assertLess(len(self.entries()), before)
        self.assertEqual(self.visible_rows()[0].expand.texture, r"Interface\Buttons\UI-PlusButton-Up")
        self.a.call(self.visible_rows()[0], "Click")
        self.assertIsNone(self.a.g.ForeverProfessionalDB.collapsed[cat])
        self.assertEqual(len(self.entries()), before)

    def test_list_scrollbar_only_when_needed(self):
        bar = self.UI.list.scroll.ScrollBar
        self.assertTrue(self.UI.list.scroll.scrollBarHideable)
        self.UI.SelectProfession(186)   # Mining: 17 recipes, fits
        self.assertFalse(bar.shown)
        self.UI.SelectProfession(164)   # Blacksmithing: 419 recipes
        self.assertTrue(bar.shown)
        self.assertEqual(bar.thumb.texture, r"Interface\Buttons\WHITE8X8")

    def test_scrolling_moves_rows(self):
        self.a.call(self.UI.list.scroll, "SetVerticalScroll", 10 * self.UI.ROW_H)
        self.UI.RenderList()
        first = self.visible_rows()[0]
        self.assertEqual(first.entryIndex, 11)
        self.assertEqual(first.label.text, self.visible_rows()[0].label.text)

    def test_row_pool_is_small(self):
        a = self.a
        a.slash("leatherworking")
        self.assertEqual(self.UI.state.line, 165)
        self.assertGreater(len(self.entries()), 400)
        self.assertLess(len(lua_list(self.UI.list.rows)), 40)

    def test_every_profession_tab(self):
        for tab in lua_list(self.UI.tabs):
            self.a.call(tab, "Click")
            self.assertEqual(self.UI.state.line, tab.line)
            self.assertEqual(len(self.recipe_ids()), len(list(self.a.ns.Data.Recipes[tab.line].keys())))
            self.assertTrue(tab.selectedTex.shown)

    def test_new_recipe_learned_refreshes_open_window(self):
        self.UI.SetFilter("learned")
        self.a.run('fire("NEW_RECIPE_LEARNED", 3230)')
        self.assertIn(3230, self.recipe_ids())

    def test_unknown_profession_message(self):
        self.a.slash("basketweaving")
        self.assertTrue(any("basketweaving" in p for p in self.a.printed()))


if __name__ == "__main__":
    unittest.main()
