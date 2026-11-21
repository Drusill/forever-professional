"""Detail pane tests: header, sections in state order, reagent grid, source cards, async items and waypoints."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ALTS, Addon, lua_list, plain  # noqa: E402

LEARNED = "mock.learned = { [2329] = true }"
COPPER = r"|TInterface\MoneyFrame\UI-CopperIcon:0:0:2:0|t"


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

    def blocks(self):
        return [(b.kind, plain(b.text or "")) for b in lua_list(self.d.rendered)]

    def sections(self):
        return [t for k, t in self.blocks() if k == "section"]

    def shown(self, pool):
        return [w for w in lua_list(pool) if w.shown]

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

    def test_order_not_learned(self):
        self.select(1251753)
        self.assertEqual(self.sections(), ["Where to get it", "Characters", "Reagents"])
        self.assertEqual(lua_list(self.d.rendered)[1].kind, "get")      # Get <recipe item> from:

    def test_order_learned_with_folded_sources(self):
        self.select(2329)
        self.assertEqual(self.sections(), ["Reagents", "Characters"])
        self.assertEqual(self.blocks()[-1], ("folded", "Where to get it · Trainer · 50" + COPPER))
        self.a.call(self.d.folded, "Click")
        self.assertIn("Where to get it", self.sections())
        self.select(2329)          # stays open for the session
        self.assertTrue(self.UI.state.sourcesOpen)

    def test_reagents_from_schematic(self):
        self.select(2329)
        reagents = next(b for b in lua_list(self.d.rendered) if b.kind == "reagents")
        items = lua_list(reagents["items"])   # .items is the lupa table's Python method
        self.assertEqual([(i.item, i.count) for i in items], [(765, 1), (2447, 2), (3371, 1)])
        slot = next(s for s in self.shown(self.d.slots) if s.item == 2447)
        self.assertEqual((slot.count.text, plain(slot.name.text)), ("2", "Item 2447"))
        self.assertTrue(self.a.mock.schematicCalls >= 1)

    def test_schematic_missing_falls_back_to_creates(self):
        self.a.run("mock.noSchematic = true")
        self.select(3230)
        self.assertIn("Item 2457", plain(self.d.header.creates.text))  # rec.creates
        self.assertNotIn("Reagents", self.sections())
        self.assertIn(2553, [b.item for b in lua_list(self.d.rendered) if b.kind == "get"])  # rec.teach

    def test_not_learned_and_drop_sources(self):
        self.select(1250793)
        self.assertEqual(self.d.header.stateChip.text.text, "Not learned")
        self.assertTrue(self.d.header.newChip.shown)
        drops = [w for w in self.shown(self.d.cardWidgets) if w.card.type == "drop"]
        self.assertTrue(drops)
        self.assertTrue(any("rate unknown" in w.detail.text for w in drops))

    def test_vendor_cards_and_waypoint(self):
        self.select(1251750)
        card = next(w for w in self.shown(self.d.cardWidgets) if w.card.type == "vendor")
        self.assertEqual(card.title.text, "Apothecary Durelle <Alchemist>")
        self.a.call(card.waypoint, "Click")
        wps = lua_list(self.a.mock.waypoints)
        self.assertEqual(wps[0].uiMapID, self.a.ns.Data.NPCs[248196].map)
        self.assertAlmostEqual(wps[0].x, self.a.ns.Data.NPCs[248196].x / 100)
        self.assertEqual(self.a.mock.supertracked, 1)
        self.assertTrue(any("Waypoint set" in p for p in self.a.printed()))
        self.assertIn(("req", "120 Merchant's Favor"), self.blocks())
        self.assertIn(("req", "Faction 2586: Friendly"), self.blocks())

    def test_waypoint_refused_on_bad_map(self):
        ok = self.UI.SetWaypoint(self.a.lua.table_from({"map": 0, "x": 1, "y": 2, "name": "x"}))
        self.assertFalse(ok)
        self.assertEqual(len(lua_list(self.a.mock.waypoints)), 0)

    def test_cards_without_coordinates_have_no_waypoint_button(self):
        self.UI.state.sourcesOpen = True
        self.select(2329)                        # trainer only
        cards = self.shown(self.d.cardWidgets)
        self.assertTrue(cards)
        self.assertFalse(any(w.waypoint.shown for w in cards))

    def test_dungeon_card(self):
        self.select(1262978, 185)
        w = next(w for w in self.shown(self.d.cardWidgets))
        self.assertFalse(w.waypoint.shown)
        self.assertTrue(w.dungeon.shown)
        self.assertEqual(w.dungeon.text, "Dungeon")

    def test_reagent_grid_columns(self):
        self.assertEqual((self.UI.ReagentColumns(440), self.UI.ReagentColumns(439)), (2, 1))
        self.select(1251753)
        slots = self.shown(self.d.slots)
        self.assertGreater(Addon.call(slots[1], "GetPoint")[3], Addon.call(slots[0], "GetPoint")[3])  # 2nd column

    def test_unknown_note_and_quest_card(self):
        self.select(2365)
        self.assertIn(("note", "Source unknown"), self.blocks())
        self.select(1230564)
        titles = [w.title.text for w in self.shown(self.d.cardWidgets)]
        self.assertIn("[6] Camping 101: Alchemy", titles)
        quest = next(w for w in self.shown(self.d.cardWidgets) if w.card.type == "quest")
        self.assertTrue(quest.detail.text.startswith("Given by "))

    def test_container_card_shows_item(self):
        self.select(2335)
        w = next(w for w in self.shown(self.d.cardWidgets) if w.card.type == "container")
        self.assertEqual(plain(w.title.text), "Item 6307")
        w.scripts.OnEnter(w)
        self.assertEqual(self.a.g.GameTooltip.item, 6307)

    def test_async_item_rerenders(self):
        self.a.run("mock.asyncItems[2447] = true")
        self.UI.SelectRecipe(2329)  # no flush yet
        names = lambda: [plain(s.name.text) for s in self.shown(self.d.slots)]  # noqa: E731
        self.assertIn("Item #2447", names())
        self.a.run("flush()")
        self.assertIn("Item 2447", names())
        self.assertNotIn("Item #2447", names())

    def test_async_item_for_old_selection_ignored(self):
        self.a.run("mock.asyncItems[2447] = true")
        self.UI.SelectRecipe(2329)
        self.UI.SelectRecipe(3170)
        self.a.run("flush()")
        self.assertEqual(self.d.current, 3170)

    def test_item_tooltip(self):
        self.select(2329)
        slot = self.shown(self.d.slots)[0]
        slot.scripts.OnEnter(slot)
        self.assertEqual(self.a.g.GameTooltip.item, slot.item)

    def test_every_recipe_renders(self):
        for line in self.a.ns.Data.Professions.keys():
            self.UI.SelectProfession(line)
            for spell in self.a.ns.Data.Recipes[line].keys():
                self.UI.SelectRecipe(spell)
                self.assertTrue(lua_list(self.d.rendered), (line, spell))
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
        return [(b.kind, plain(b.text)) for b in lua_list(self.d.rendered)]

    def test_characters_section_order(self):
        self.select(1251753, 171)
        r = self.rendered()
        sections = [t for k, t in r if k == "section"]
        self.assertEqual(sections, ["Where to get it", "Characters", "Reagents"])
        i = r.index(("section", "Characters"))
        self.assertEqual([(b.group, plain(b.text)) for b in lua_list(self.d.rendered)[i + 1:i + 3]],
                         [("learnable", "Learnable by: Dru (Rogue), Paly (Horde vendors only)"),
                          ("low", "Skill too low: Tester 120 / 280, Dru (Druid) 150 / 280")])
        dots = [w.dot for w in lua_list(self.d.ownerRows) if w.shown]
        self.assertEqual(len(dots), 2)

    def test_no_character_line(self):
        self.select(23066, 202)
        r = self.rendered()
        i = r.index(("section", "Characters"))
        self.assertEqual(r[i + 1], ("owner", "No character has this profession"))


if __name__ == "__main__":
    unittest.main()
