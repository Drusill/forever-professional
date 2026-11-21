"""Detail pane tests: schematic, sources, async items and waypoints."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ALTS, Addon, lua_list, plain  # noqa: E402

LEARNED = "mock.learned = { [2329] = true }"


class DetailTest(unittest.TestCase):
    def setUp(self, setup=LEARNED):
        self.a = Addon(setup=setup)
        self.a.login()
        self.a.slash("")
        self.UI = self.a.ns.UI
        self.d = self.UI.detail

    def select(self, spell, line=171):
        if self.UI.state.line != line:
            self.UI.SelectProfession(line)
        self.UI.SelectRecipe(spell)
        self.a.run("flush()")

    def shown_lines(self):
        return [l for l in lua_list(self.d.lines) if l.shown]

    def texts(self):
        return [l.text.text for l in self.shown_lines()]

    def test_empty_until_selected(self):
        self.assertTrue(self.d.empty.shown)
        self.assertFalse(self.d.scroll.shown)

    def test_no_question_mark_placeholder(self):
        # The Journal's "no art" lore background read as a missing texture.
        for r in lua_list(self.UI.frame.detailPanel.regions):
            self.assertNotIn("LOREBG", str(r.texture))

    def test_empty_state_stats(self):
        e = self.d.empty
        self.assertTrue(e.shown)
        recs = self.a.ns.Data.Recipes[171]
        learnable = sum(1 for i, r in recs.items()
                        if i != 2329 and (r.learn or 0) <= 120 and r.side in (None, "Horde"))
        self.assertEqual([e.stats[k].value.text for k in ("learned", "learnable", "missing")],
                         ["1", str(learnable), "178"])

    def test_header_learned(self):
        self.select(2329)
        h, rec = self.d.header, self.a.ns.Data.Recipes[171][2329]
        self.assertTrue(self.a.lua.eval("rawequal")(h.parent, self.UI.frame.detailPanel))
        self.assertEqual(plain(h.title.text), "Spell 2329")
        self.assertEqual(plain(h.creates.text), "Creates Item 2454 · Herb")
        self.assertEqual((h.stateChip.text.text, h.stateChip.style), ("Learned", "good"))
        self.assertEqual(h.catChip.text.text, "Elixirs")
        self.assertFalse(h.newChip.shown)
        self.assertEqual([n.text for n in lua_list(h.scale.nums)],
                         [str(rec.learn), str(rec.yellow), str(rec.green), str(rec.grey)])
        self.assertTrue(h.scale.tick.shown)

    def test_header_not_learned_new_and_tick_hidden(self):
        self.select(1250793)
        self.assertEqual(self.d.header.stateChip.style, "bad")
        self.assertEqual(self.d.header.newChip.text.text, "New in Forever")
        self.select(1251750)                       # learn 180 > skill 120
        self.assertFalse(self.d.header.scale.tick.shown)

    def test_scale_degenerate_thresholds(self):
        for line in self.a.ns.Data.Recipes.keys():
            for spell, r in self.a.ns.Data.Recipes[line].items():
                if (r.learn or 0) == (r.grey or 0) or r.grey is None:
                    self.select(spell, line)
                    self.assertTrue(all(s.width >= 0 for s in lua_list(self.d.header.scale.segments)))

    def test_async_output_item(self):
        self.a.run("mock.asyncItems[2454] = true")
        self.UI.SelectRecipe(2329)
        self.assertIn("Item #2454", self.d.header.creates.text)
        self.a.run("flush()")
        self.assertIn("Item 2454", plain(self.d.header.creates.text))

    def test_scrollbar_hidden_when_content_fits(self):
        self.assertTrue(self.d.scroll.scrollBarHideable)
        self.select(2329)
        self.assertFalse(self.d.scroll.ScrollBar.shown)

    def test_scrollbar_shown_when_content_overflows(self):
        self.a.g._ns = self.a.ns
        line, spell = self.a.run(
            "for line, list in pairs(_ns.Data.Recipes) do for id, r in pairs(list) do "
            "if r.drops and #r.drops >= 12 and r.vendors and #r.vendors >= 3 then return line, id end "
            "end end")
        self.select(spell, line)
        self.assertGreater(self.d.child.height, self.UI.DetailVisibleHeight())
        self.assertTrue(self.d.scroll.ScrollBar.shown)
        self.select(2329, 171)
        self.assertFalse(self.d.scroll.ScrollBar.shown)

    def test_scrollbar_thumb_styled(self):
        thumb = self.d.scroll.ScrollBar.thumb
        self.assertIsNotNone(thumb)
        self.assertEqual(thumb.texture, r"Interface\Buttons\WHITE8X8")

    def test_row_click_selects(self):
        row = next(r for r in lua_list(self.UI.list.rows) if r.shown and r.entry.kind == "recipe")
        self.a.call(row, "Click")
        self.assertEqual(self.UI.state.selected, row.entry.id)
        self.assertTrue(row.selectedTex.shown)
        self.assertFalse(self.d.empty.shown)

    def test_header_and_schematic(self):
        self.select(2329)
        texts = self.texts()
        self.assertNotIn("Creates", texts)   # in the header now
        self.assertIn("Reagents", texts)
        self.assertTrue(any("2x" in t and "Item 2447" in t for t in texts))
        self.assertIn("Sources", texts)
        self.assertIn(r"Trainer: 50|TInterface\MoneyFrame\UI-CopperIcon:0:0:2:0|t", texts)
        self.assertTrue(self.a.mock.schematicCalls >= 1)

    def test_schematic_missing_falls_back_to_creates(self):
        self.a.run("mock.noSchematic = true")
        self.select(3230)
        texts = self.texts()
        self.assertIn("Item 2457", plain(self.d.header.creates.text))  # rec.creates
        self.assertNotIn("Reagents", texts)
        self.assertIn("Recipe item", texts)
        self.assertTrue(any("Item 2553" in t for t in texts))  # rec.teach

    def test_not_learned_and_drop_sources(self):
        self.select(1250793)
        self.assertEqual(self.d.header.stateChip.text.text, "Not learned")
        self.assertTrue(self.d.header.newChip.shown)
        texts = self.texts()
        self.assertIn("Drops", texts)
        self.assertTrue(any("rate unknown" in t for t in texts))

    def test_gated_vendor_and_waypoint(self):
        self.select(1251750)
        texts = self.texts()
        self.assertIn("Vendors", texts)
        self.assertIn("Requirements", texts)
        self.assertIn("120 Merchant's Favor", texts)
        self.assertIn("Faction 2586: Friendly", texts)
        line = next(l for l in self.shown_lines() if l.waypoint.shown)
        self.a.call(line.waypoint, "Click")
        wps = lua_list(self.a.mock.waypoints)
        self.assertEqual(len(wps), 1)
        npc = self.a.ns.Data.NPCs[248196]
        self.assertEqual(wps[0].uiMapID, npc.map)
        self.assertAlmostEqual(wps[0].x, npc.x / 100)
        self.assertEqual(self.a.mock.supertracked, 1)
        self.assertTrue(any("Waypoint set" in p for p in self.a.printed()))

    def test_waypoint_refused_on_bad_map(self):
        ok = self.UI.SetWaypoint(self.a.lua.table_from({"map": 0, "x": 1, "y": 2, "name": "x"}))
        self.assertFalse(ok)
        self.assertEqual(len(lua_list(self.a.mock.waypoints)), 0)

    def test_lines_without_coordinates_have_no_waypoint_button(self):
        self.select(2329)
        self.assertFalse(any(l.waypoint.shown for l in self.shown_lines()))

    def test_unknown_source(self):
        self.select(2365)
        self.assertTrue(any("Source unknown" in t for t in self.texts()))

    def test_quest_sources(self):
        self.select(1230564)
        texts = self.texts()
        self.assertIn("Quests", texts)
        self.assertTrue(any(t.startswith("Given by ") for t in texts))

    def test_async_item_rerenders(self):
        self.a.run("mock.asyncItems[2447] = true")
        self.UI.SelectRecipe(2329)  # no flush yet
        self.assertTrue(any("Item #2447" in t for t in self.texts()))
        self.a.run("flush()")
        self.assertTrue(any("Item 2447" in t for t in self.texts()))
        self.assertFalse(any("Item #2447" in t for t in self.texts()))

    def test_async_item_for_old_selection_ignored(self):
        self.a.run("mock.asyncItems[2447] = true")
        self.UI.SelectRecipe(2329)
        self.UI.SelectRecipe(3170)
        self.a.run("flush()")
        self.assertEqual(self.d.current, 3170)

    def test_item_tooltip(self):
        self.select(2329)
        line = next(l for l in self.shown_lines() if l.item)
        line.scripts.OnEnter(line)
        self.assertEqual(self.a.g.GameTooltip.item, line.item)

    def test_every_recipe_renders(self):
        for line in self.a.ns.Data.Professions.keys():
            self.UI.SelectProfession(line)
            for spell in self.a.ns.Data.Recipes[line].keys():
                self.UI.SelectRecipe(spell)
                self.assertTrue(self.shown_lines(), (line, spell))
        self.a.run("flush()")

    def test_count_range_without_schematic(self):
        self.a.run("mock.noSchematic = true")
        for line in self.a.ns.Data.Recipes.keys():
            for spell, rec in self.a.ns.Data.Recipes[line].items():
                if rec["count"] is not None and not isinstance(rec["count"], int):
                    self.select(spell, line)
                    lo, hi = rec["count"][1], rec["count"][2]
                    self.assertTrue(plain(self.d.header.creates.text).startswith(f"Creates {lo}-{hi}x "))
                    return
        self.fail("no ranged count in data")

    def test_switching_profession_clears_selection(self):
        self.select(2329)
        self.UI.SelectProfession(185)
        self.assertIsNone(self.UI.state.selected)
        self.assertTrue(self.d.empty.shown)


class OwnersDetailTest(unittest.TestCase):
    def setUp(self):
        DetailTest.setUp(self, ALTS + "; " + LEARNED)

    select = DetailTest.select

    def rendered(self):
        return [(l.kind, plain(l.text)) for l in lua_list(self.d.rendered)]

    def test_characters_section_order(self):
        self.select(1251753, 171)
        r = self.rendered()
        sections = [t for k, t in r if k == "section"]
        self.assertLess(sections.index("Recipe item"), sections.index("Characters"))
        self.assertLess(sections.index("Characters"), sections.index("Sources"))
        i = r.index(("section", "Characters"))
        self.assertEqual(r[i + 1], ("text", "Learnable by: Dru (Rogue), Paly (Horde vendors only)"))
        self.assertEqual(r[i + 2], ("text", "Skill too low: Tester 120 / 280, Dru (Druid) 150 / 280"))

    def test_no_character_line(self):
        self.select(23066, 202)
        r = self.rendered()
        i = r.index(("section", "Characters"))
        self.assertEqual(r[i + 1], ("text", "No character has this profession"))


if __name__ == "__main__":
    unittest.main()
