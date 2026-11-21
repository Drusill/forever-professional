"""Window and recipe list tests: the addon driven through /fp and its widgets, with real data."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ALTS, Addon, lua_list, plain  # noqa: E402

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

    def rail(self, line):
        return next(b for b in lua_list(self.UI.railButtons) if b.line == line)

    def test_rail_groups_shown_character(self):
        known, other = self.UI.RailOrder(None)
        self.assertEqual(lua_list(known), [171, 182])
        self.assertEqual(lua_list(other), [164, 185, 333, 202, 129, 165, 197, 356, 186, 393])
        self.assertEqual(self.rail(171).skill.text, "120")
        self.assertEqual(self.rail(164).group, "other")
        self.assertFalse(self.rail(164).skill.shown)
        self.assertLess(Addon.call(self.rail(182), "GetPoint")[-1], 0)   # stacked below the logo

    def test_rail_click_selects(self):
        Addon.call(self.rail(185), "Click")
        self.assertEqual(self.UI.state.line, 185)
        self.assertTrue(self.rail(185).marker.shown)
        self.assertFalse(self.rail(171).marker.shown)

    def test_rail_tooltip(self):
        self.a.g.enter(self.rail(171))
        self.assertEqual(lua_list(self.a.g.GameTooltip.lines)[:2], ["Alchemy", "Skill 120 / 150"])

    def test_header(self):
        h = self.UI.header
        self.assertEqual((h.name.text, h.skillText.text, h.recipesText.text), ("Alchemy", "120 / 150", "3 / 179"))
        self.assertTrue(h.skillBar.shown)
        self.assertFalse(h.notLearned.shown)
        self.UI.SelectProfession(185)
        self.assertFalse(h.skillBar.shown)
        self.assertTrue(h.notLearned.shown)

    def test_no_journal_background_and_selector_in_header(self):
        textures = [r.texture for r in lua_list(self.a.g.ForeverProfessionalFrame.regions)]
        self.assertNotIn(r"Interface\EncounterJournal\UI-EJ-JournalBG", textures)
        self.assertTrue(self.a.lua.eval("rawequal")(self.UI.charButton.parent, self.UI.header))

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

    def test_every_profession_rail_button(self):
        for b in lua_list(self.UI.railButtons):
            self.a.call(b, "Click")
            self.assertEqual(self.UI.state.line, b.line)
            self.assertEqual(len(self.recipe_ids()), len(list(self.a.ns.Data.Recipes[b.line].keys())))
            self.assertTrue(b.marker.shown)

    def test_new_recipe_learned_refreshes_open_window(self):
        self.UI.SetFilter("learned")
        self.a.run('fire("NEW_RECIPE_LEARNED", 3230)')
        self.assertIn(3230, self.recipe_ids())

    def test_unknown_profession_message(self):
        self.a.slash("basketweaving")
        self.assertTrue(any("basketweaving" in p for p in self.a.printed()))


DRU_ROGUE = "Player-1-0000000B"


class AltViewTest(unittest.TestCase):
    def setUp(self):
        self.a = open_addon(ALTS + "; " + LEARNED)
        self.UI = self.a.ns.UI
        self.total = len(list(self.a.ns.Data.Recipes[171].keys()))

    def rail(self, line):
        return next(b for b in lua_list(self.UI.railButtons) if b.line == line)

    def counter(self):
        return self.UI.header.recipesText.text

    def recipe_ids(self):
        return [e.id for e in lua_list(self.UI.entries) if e.kind == "recipe"]

    def test_alt_tabs_and_counter(self):
        self.UI.SetChar(DRU_ROGUE)
        self.assertEqual(self.rail(171).skill.text, "290")
        self.assertEqual(self.rail(182).group, "other")
        self.assertEqual(self.counter(), f"1 / {self.total}")

    def test_alt_learned_filter_and_checks(self):
        self.UI.SetChar(DRU_ROGUE)
        self.UI.SetFilter("learned")
        self.assertEqual(self.recipe_ids(), [7255])
        rows = [r for r in lua_list(self.UI.list.rows) if r.shown and r.entry.kind == "recipe"]
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0].check.texture.endswith("ReadyCheck-Ready"))

    def test_alt_detail_status(self):
        self.UI.SetChar(DRU_ROGUE)
        self.UI.SelectRecipe(7255)
        self.assertIn("Learned", plain(self.UI.detail.status.text))
        self.assertNotIn("Not learned", plain(self.UI.detail.status.text))
        self.UI.SetChar(None)
        self.assertIn("Not learned", plain(self.UI.detail.status.text))

    def test_set_char_self_or_unknown_is_nil(self):
        self.UI.SetChar("Player-1-0000000A")
        self.assertIsNone(self.UI.state.char)
        self.UI.SetChar("Player-9-X")
        self.assertIsNone(self.UI.state.char)

    def test_live_refresh_keeps_alt_view(self):
        self.UI.SetChar(DRU_ROGUE)
        self.a.run('fire("NEW_RECIPE_LEARNED", 1251753)')
        self.assertEqual(self.counter(), f"1 / {self.total}")
        self.assertTrue(self.a.g.ForeverProfessionalDB.chars["Player-1-0000000A"].learned[1251753])
        self.UI.SetChar(None)
        self.assertEqual(self.counter(), f"4 / {self.total}")

    def test_forget_viewed_alt_resets_view(self):
        self.UI.SetChar(DRU_ROGUE)
        self.a.slash("forget 3")
        self.assertIsNone(self.UI.state.char)
        self.assertEqual(self.rail(171).skill.text, "120")

    def test_rail_follows_alt(self):
        self.UI.SetChar("Player-1-0000000D")   # Paly: Alchemy, Cooking
        self.assertEqual(lua_list(self.UI.RailOrder("Player-1-0000000D")[0]), [171, 185])
        self.assertEqual(self.rail(185).group, "known")

    def test_rail_alt_without_professions(self):
        self.UI.SetChar("Player-1-0000000E")   # Banco
        self.assertTrue(all(b.group == "other" for b in lua_list(self.UI.railButtons)))
        self.assertTrue(self.UI.header.notLearned.shown)


class SelectorTest(unittest.TestCase):
    def setUp(self):
        self.a = open_addon(ALTS + "; " + LEARNED)
        self.UI = self.a.ns.UI
        self.button = self.UI.charButton

    def click(self, w):
        Addon.call(w, "Click")

    def menu_rows(self):
        return [r for r in lua_list(self.UI.charMenu.rows) if r.shown]

    def row(self, label):
        return next(r for r in self.menu_rows() if plain(r.label.text) == label)

    def test_button_shows_viewed_character(self):
        self.assertEqual(plain(self.button.label.text), "Tester")
        self.assertEqual(self.button.faction.texture, r"Interface\TargetingFrame\UI-PVP-Horde")
        self.UI.SetChar("Player-1-0000000D")
        self.assertEqual(plain(self.button.label.text), "Paly")
        self.assertEqual(self.button.faction.texture, r"Interface\TargetingFrame\UI-PVP-Alliance")

    def test_menu_lists_characters(self):
        self.assertFalse(self.UI.charMenu.shown)
        self.click(self.button)
        self.assertTrue(self.UI.charMenu.shown)
        labels = [plain(r.label.text) for r in self.menu_rows()]
        self.assertEqual(labels, ["Tester (you)", "Banco", "Dru (Rogue)", "Dru (Druid)", "Paly"])
        self.assertEqual(self.row("Paly")["class"].text, "Paladin")

    def test_pick_row_switches_and_closes(self):
        self.click(self.button)
        self.click(self.row("Dru (Rogue)"))
        self.assertEqual(self.UI.state.char, "Player-1-0000000B")
        self.assertFalse(self.UI.charMenu.shown)
        alchemy = next(b for b in lua_list(self.UI.railButtons) if b.line == 171)
        self.assertEqual(alchemy.skill.text, "290")
        self.click(self.button)
        self.click(self.row("Tester (you)"))
        self.assertIsNone(self.UI.state.char)

    def test_button_toggles_menu(self):
        self.click(self.button)
        self.click(self.button)
        self.assertFalse(self.UI.charMenu.shown)

    def test_menu_hides_with_window(self):
        self.click(self.button)
        self.a.slash("")
        self.assertFalse(self.UI.charMenu.shown)



if __name__ == "__main__":
    unittest.main()
