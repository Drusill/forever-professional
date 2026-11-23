"""Window and recipe list tests: the addon driven through /fp and its widgets, with real data."""
import math
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
        self.assertTrue(recipe_row.sub.text)

    def test_learned_check_marks(self):
        self.UI.SetFilter("learned")
        rows = [r for r in self.visible_rows() if r.entry.kind == "recipe"]
        self.assertEqual(len(rows), 3)
        for r in rows:
            self.assertEqual(r.status.texture, self.UI.SOURCE_ICONS.check)
        self.UI.SetFilter("missing")
        rows = [r for r in self.visible_rows() if r.entry.kind == "recipe"]
        self.assertTrue(rows)
        for r in rows:
            self.assertNotEqual(r.status.texture, self.UI.SOURCE_ICONS.check)

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

    def test_filter_counts_ignore_search(self):
        b = {x.key: x for x in lua_list(self.UI.filterButtons)}
        self.assertEqual([b[k].count.text for k in ("all", "learned", "missing")], ["179", "3", "176"])
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "spell 3230")
        self.assertEqual(b["all"].count.text, "179")
        self.a.call(b["learned"], "Click")
        self.assertTrue(b["learned"].selected)
        self.assertFalse(b["all"].selected)

    def test_collapse_all_and_expand_all(self):
        before = len(self.entries())
        self.a.call(self.UI.collapseAllButton, "Click")
        self.assertTrue(all(e.kind == "header" and e.collapsed for e in self.entries()))
        self.assertTrue(all(self.a.g.ForeverProfessionalDB.collapsed[e.cat] for e in self.entries()))
        self.a.call(self.UI.expandAllButton, "Click")
        self.assertEqual(len(self.entries()), before)

    def test_collapse_expand_buttons_use_header_chevrons(self):
        c, e = self.UI.collapseAllButton.icon, self.UI.expandAllButton.icon
        self.assertEqual((c.texture, c.rotation), (r"Interface\ChatFrame\ChatFrameExpandArrow", 0))
        self.assertEqual((e.texture, e.rotation), (r"Interface\ChatFrame\ChatFrameExpandArrow", -math.pi / 2))

    def test_drop_rows_show_the_skull(self):
        row = self.search(1250793)
        self.assertEqual(row.status.texture, r"Interface\TargetingFrame\UI-TargetingFrame-Skull")

    def test_header_watermark(self):
        self.a.run('mock.atlasInfo["wide-card"] = { width = 664, height = 141 }; '
                   'mock.atlasInfo["tall-card"] = { width = 225, height = 274 }')
        w = self.UI.header.watermark
        self.a.ns.UI.THEME[171].watermark = "wide-card"
        self.UI.Refresh()
        self.assertTrue(w.shown)
        self.assertEqual(w.atlas, "wide-card")
        self.assertAlmostEqual(w.width / w.height, 664 / 141, places=2)   # natural aspect
        self.assertLess(w.alpha, 0.5)                                    # faint behind the name
        self.a.ns.UI.THEME[171].watermark = "tall-card"                  # doesn't fit a 54px header
        self.UI.Refresh()
        self.assertFalse(w.shown)
        self.a.ns.UI.THEME[171].watermark = None
        self.UI.Refresh()
        self.assertFalse(w.shown)

    def test_collapse_all_then_search(self):
        self.UI.CollapseAll()
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "spell 3230")
        self.assertEqual(self.recipe_ids(), [3230])
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "")
        self.assertEqual(self.recipe_ids(), [])

    def test_search_placeholder(self):
        self.assertEqual(self.a.g.ForeverProfessionalSearchBox.placeholder.text, "Search…")
        self.assertIsNotNone(self.a.g.ForeverProfessionalSearchBox.icon)

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
        self.assertEqual(self.visible_rows()[0].expand.rotation, 0)
        self.a.call(self.visible_rows()[0], "Click")
        self.assertIsNone(self.a.g.ForeverProfessionalDB.collapsed[cat])
        self.assertEqual(len(self.entries()), before)

    def test_list_scrollbar_only_when_needed(self):
        bar = self.UI.list.scroll.ScrollBar
        self.assertTrue(self.UI.list.scroll.scrollBarHideable)
        self.UI.SelectProfession(393)   # Skinning: 3 recipes, fits
        self.assertFalse(bar.shown)
        self.UI.SelectProfession(186)   # Mining: 17 two-line rows don't fit any more
        self.assertTrue(bar.shown)
        self.UI.SelectProfession(164)   # Blacksmithing: 419 recipes
        self.assertTrue(bar.shown)
        self.assertEqual(bar.thumb.texture, r"Interface\Buttons\WHITE8X8")

    def search(self, spell):
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", f"spell {spell}")
        return next(r for r in self.visible_rows() if r.entry.kind == "recipe" and r.entry.id == spell)

    def test_row_heights_and_content_height(self):
        rows = self.visible_rows()
        self.assertEqual(rows[0].height, 24)
        self.assertEqual(next(r for r in rows if r.entry.kind == "recipe").height, 34)
        e = self.entries()
        self.assertEqual(self.UI.list.child.height, sum(24 if x.kind == "header" else 34 for x in e))

    def test_missing_row(self):
        row = self.search(7255)
        self.assertEqual(plain(row.label.text), "Spell 7255")
        self.assertEqual(plain(row.sub.text), "Learn 100 · Vendor · Kzixx (Map 1431) · +2 more")
        self.assertEqual(row.status.texture, self.UI.SOURCE_ICONS.vendor)

    def test_learned_row(self):
        row = self.search(2329)
        rec = self.a.ns.Data.Recipes[171][2329]
        self.assertEqual(row.sub.text, self.a.ns.Model.RangeText(rec, 120))
        self.assertEqual(row.status.texture, self.UI.SOURCE_ICONS.check)

    def test_learned_recipe_below_learn_level_not_red(self):
        # Learned above the baked learn level (#11): the row, its range text and the detail title aren't red.
        recs = dict(self.a.ns.Data.Recipes[171].items())
        spell = min(i for i, r in recs.items() if (r.learn or 0) > 120 and (r.grey or 0) > 120)
        self.a = open_addon(f"{LEARNED}; mock.learned[{spell}] = true")
        self.UI = self.a.ns.UI
        row = self.search(spell)
        self.assertFalse(row.label.text.startswith("|cffff2020"), row.label.text)
        rec = self.a.ns.Data.Recipes[171][spell]
        self.assertEqual(row.sub.text, self.a.ns.Model.RangeText(rec, 120, True))
        self.UI.SelectRecipe(spell)
        title = self.UI.detail.header.title.text
        self.assertFalse(title.startswith("|cffff2020"), title)

    def test_header_row(self):
        h = self.visible_rows()[0]
        self.assertEqual((h.label.text, h.expand.rotation), ("Camping", -math.pi / 2))
        self.assertRegex(h.count.text, r"^\d+/\d+$")
        self.a.call(h, "Click")
        self.assertEqual(self.visible_rows()[0].expand.rotation, 0)

    def test_scroll_with_mixed_heights(self):
        top = lua_list(self.UI.entryTop)
        for offset, expected in ((top[10], 11), (top[10] + 5, 11)):
            self.a.call(self.UI.list.scroll, "SetVerticalScroll", offset)
            self.UI.RenderList()
            self.assertEqual(self.visible_rows()[0].entryIndex, expected)

    def test_switch_profession_while_scrolled(self):
        # In game: scrolled down in one profession, clicking another redrew the old rows against
        # the new profession's recipes (BugSack: RangeText on a nil recipe).
        top = lua_list(self.UI.entryTop)
        self.a.call(self.UI.list.scroll, "SetVerticalScroll", top[40])
        Addon.call(next(b for b in lua_list(self.UI.railButtons) if b.line == 164), "Click")
        self.assertEqual(self.UI.state.line, 164)
        self.assertEqual(self.visible_rows()[0].entryIndex, 1)
        recipes = self.a.ns.Data.Recipes[164]
        self.assertTrue(all(recipes[r.entry.id] is not None for r in self.visible_rows() if r.entry.kind == "recipe"))

    def test_slash_profession_starts_at_the_top(self):
        top = lua_list(self.UI.entryTop)
        self.a.call(self.UI.list.scroll, "SetVerticalScroll", top[40])
        self.a.slash("tailor")
        self.assertEqual(self.UI.state.line, 197)
        self.assertEqual(self.visible_rows()[0].entryIndex, 1)

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


class ResizeTest(unittest.TestCase):
    def setUp(self, setup=LEARNED):
        self.a = open_addon(setup)
        self.UI = self.a.ns.UI
        self.f = self.a.g.ForeverProfessionalFrame

    def test_resizable_with_grip(self):
        self.assertTrue(self.f.resizable)
        self.assertEqual(lua_list(self.f.resizeBounds)[:2], [900, 540])
        g = self.UI.resizeGrip
        g.scripts.OnMouseDown(g, "LeftButton")
        self.assertEqual(self.f.sizing, "BOTTOMRIGHT")
        Addon.call(self.f, "SetSize", 1200, 700)
        g.scripts.OnMouseUp(g, "LeftButton")
        db = self.a.g.ForeverProfessionalDB
        self.assertEqual((db.window.w, db.window.h), (1200, 700))

    def test_resize_pins_top_left_first(self):
        # Sizing a centre-anchored window from a corner makes it leap on this client.
        g = self.UI.resizeGrip
        g.scripts.OnMouseDown(g, "LeftButton")
        point, rel, relPoint, x, y = Addon.call(self.f, "GetPoint")
        self.assertEqual((point, relPoint, x, y), ("TOPLEFT", "BOTTOMLEFT", 100, 700))
        self.assertTrue(self.a.lua.eval("rawequal")(rel, self.a.g.UIParent))

    def test_resize_does_not_rebuild_the_list(self):
        self.a.g._ns = self.a.ns
        self.a.run("_G.buildCalls = 0; local orig = _ns.Model.BuildTree; "
                   "_ns.Model.BuildTree = function(...) buildCalls = buildCalls + 1; return orig(...) end")
        Addon.call(self.f, "SetSize", 1300, 900)
        self.assertEqual(self.a.g.buildCalls, 0)
        self.assertTrue([r for r in lua_list(self.UI.list.rows) if r.shown])

    def test_rail_fits_at_minimum_height(self):
        a = open_addon(ALTS + '; ForeverProfessionalDB.chars["Player-1-0000000F"] = { guid = "Player-1-0000000F", '
                       'name = "Smith", class = "WARRIOR", faction = "Horde", level = 60, updated = 1795000000, '
                       'professions = { [164] = { skill = 215, max = 225 }, [186] = { skill = 241, max = 300 }, '
                       '[185] = { skill = 225, max = 300 }, [356] = { skill = 128, max = 150 }, '
                       '[129] = { skill = 240, max = 300 } }, learned = {} }; ' + LEARNED)
        UI = a.ns.UI
        UI.SetChar("Player-1-0000000F")
        Addon.call(a.g.ForeverProfessionalFrame, "SetSize", UI.MIN_W, UI.MIN_H)
        bottom = max(-Addon.call(b, "GetPoint")[-1] + b.height for b in lua_list(UI.railButtons))
        self.assertLessEqual(bottom, UI.MIN_H - 2)

    def test_list_width_split(self):
        self.assertEqual([self.UI.ListWidth(w) for w in (900, 1040, 1400)], [380, 418, 520])

    def test_layout_on_resize(self):
        Addon.call(self.f, "SetSize", 1400, 900)
        self.assertEqual(self.f.listPanel.width, 520)
        self.assertEqual(self.f.detailPanel.width, 1400 - 64 - 3 * 8 - 520)

    def test_pool_grows_on_taller_window(self):
        before = len(lua_list(self.UI.list.rows))
        Addon.call(self.f, "SetSize", 1040, 1060)
        self.assertGreater(len(lua_list(self.UI.list.rows)), before)

    def test_size_restored_and_clamped(self):
        def size(win):
            a = open_addon(f"ForeverProfessionalDB = {{ window = {win} }}; " + LEARNED)
            f = a.g.ForeverProfessionalFrame
            return f.width, f.height
        self.assertEqual(size("{ point='CENTER', x=0, y=0, w=1200, h=700 }"), (1200, 700))
        self.assertEqual(size("{ point='CENTER', x=0, y=0, w=5000, h=5000 }"), (1920, 1080))
        self.assertEqual(size("{ point='CENTER', x=0, y=0, w=100, h=100 }"), (900, 540))
        self.assertEqual(size("{}"), (1040, 640))


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
        self.assertEqual(rows[0].status.texture, self.UI.SOURCE_ICONS.check)

    def test_learn_neutral_without_profession(self):
        self.UI.SetChar("Player-1-0000000E")
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "spell 1251750")
        row = next(r for r in lua_list(self.UI.list.rows)
                   if r.shown and r.entry.kind == "recipe" and r.entry.id == 1251750)
        self.assertTrue(row.sub.text.startswith("Learn 180"))

    def test_alt_detail_status(self):
        self.UI.SetChar(DRU_ROGUE)
        self.UI.SelectRecipe(7255)
        self.assertEqual(self.UI.detail.header.stateChip.text.text, "Learned")
        self.UI.SetChar(None)
        self.assertEqual(self.UI.detail.header.stateChip.text.text, "Not learned")

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
