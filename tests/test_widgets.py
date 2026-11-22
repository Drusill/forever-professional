"""Widgets.lua tests: theme, flat panel, filter toggle, chips, slots and bars."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list  # noqa: E402


class WidgetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = Addon()
        cls.a.login()
        cls.a.g._ns = cls.a.ns
        cls.UI = cls.a.ns.UI

    def setUp(self):
        self.a.run("mock.missingAtlases = {}")
        self.parent = self.a.run('return CreateFrame("Frame", nil, UIParent)')

    def test_theme_for_every_profession(self):
        for line in self.a.ns.Data.Professions.keys():
            t = self.UI.Theme(line)
            self.assertTrue(t.kit)
            self.assertEqual(len(t.accent), 6)
            self.assertEqual(len(lua_list(t.bar)), 2)
        self.assertEqual(self.UI.Theme(164).accent, "ff8a1f")
        self.assertEqual(lua_list(self.UI.Theme(164).bar), ["d4400c", "ffe680"])

    def test_watermark_for_every_profession(self):
        for line in self.a.ns.Data.Professions.keys():
            self.assertTrue(self.UI.Theme(line).watermark, line)
        self.assertEqual(self.UI.Theme(164).watermark, "Profession-overview-Card-Blacksmithing")
        self.assertEqual(self.UI.Theme(185).watermark, "Profession-overview-card-generic-Cooking")

    def test_hex_color(self):
        self.assertEqual(self.UI.HexColor("ff8000"), (1.0, 128 / 255, 0.0))

    def test_skill_bar_game_art_and_fallback(self):
        bar = self.UI.CreateSkillBar(self.parent, 150, 8)
        Addon.call(bar, "SetTheme", 164)
        self.assertEqual(bar.fill.atlas, "Skillbar_Fill_Flipbook_Blacksmithing")
        self.assertFalse(bar.usesFallback)
        self.a.run('mock.missingAtlases["Skillbar_Fill_Flipbook_Blacksmithing"] = true')
        Addon.call(bar, "SetTheme", 164)
        self.assertTrue(bar.usesFallback)

    def test_skill_bar_progress_clamps(self):
        bar = self.UI.CreateSkillBar(self.parent, 150, 8)
        Addon.call(bar, "SetProgress", 215, 225)
        self.assertAlmostEqual(bar.clip.width, bar.innerWidth * 215 / 225, places=3)
        Addon.call(bar, "SetProgress", 300, 225)
        self.assertAlmostEqual(bar.clip.width, bar.innerWidth, places=3)
        Addon.call(bar, "SetProgress", 0, 0)   # no error, empty
        self.assertLess(bar.clip.width, 1)

    def test_segmented(self):
        picked, sel, count = self.a.run('''
            local picked
            local c = _ns.UI.CreateSegmented(UIParent, {{key="all",label="All"},{key="learned",label="Learned"}},
                function(k) picked = k end)
            c:SetSelected("all"); c:SetCount("learned", 3); c.buttons.learned:Click()
            return picked, c.buttons.all.selected, c.buttons.learned.count:GetText()''')
        self.assertEqual((picked, sel, count), ("learned", True, "3"))

    def test_chip_slot_icon_button_panel(self):
        chip = self.UI.CreateChip(self.parent)
        Addon.call(chip, "SetChip", "Learned", "good")
        self.assertEqual((chip.text.text, chip.style), ("Learned", "good"))
        slot = self.UI.CreateSlot(self.parent, 28)
        Addon.call(slot, "SetItem", 2447, 4)
        self.assertEqual(slot.count.text, "4")
        slot.scripts.OnEnter(slot)
        self.assertEqual(self.a.g.GameTooltip.item, 2447)
        Addon.call(slot, "SetItem", 2447, 1)
        self.assertEqual(slot.count.text, "")
        self.assertEqual(self.UI.Panel(self.parent).backdrop.edgeSize, 1)

    def test_icon_button_click_and_tooltip(self):
        clicked = self.a.run('''
            local n = 0
            local b = _ns.UI.CreateIconButton(UIParent, "x", "Collapse all", function() n = n + 1 end)
            b:Click(); enter(b)
            return n''')
        self.assertEqual(clicked, 1)
        self.assertEqual(lua_list(self.a.g.GameTooltip.lines), ["Collapse all"])

    def test_source_icons_cover_every_type(self):
        for t in ("auto", "trainer", "vendor", "quest", "drop", "object", "container", "crafted",
                  "worldObject", "more", "unknown", "check"):
            self.assertIsNotNone(self.UI.SOURCE_ICONS[t], t)
        self.assertEqual(self.UI.SOURCE_ICONS.drop, r"Interface\TargetingFrame\UI-TargetingFrame-Skull")
        self.assertEqual(self.UI.SOURCE_ICONS.object, "atlas:VignetteLoot")
        self.assertEqual(self.UI.SOURCE_ICONS.container, "atlas:VignetteLoot")

    def test_set_icon_atlas_and_fallback(self):
        tex = self.a.run('return CreateFrame("Frame", nil, UIParent):CreateTexture()')
        self.UI.SetIcon(tex, "atlas:VignetteKill")
        self.assertEqual((tex.atlas, tex.texture), ("VignetteKill", None))
        self.a.run('mock.missingAtlases["VignetteKill"] = true')
        self.UI.SetIcon(tex, "atlas:VignetteKill")
        self.assertEqual((tex.atlas, tex.texture), (None, r"Interface\TargetingFrame\UI-TargetingFrame-Skull"))
        self.UI.SetIcon(tex, r"Interface\GossipFrame\VendorGossipIcon")
        self.assertEqual(tex.texture, r"Interface\GossipFrame\VendorGossipIcon")

    def test_file_icon_after_atlas_resets_texcoords(self):
        tex = self.a.run('return CreateFrame("Frame", nil, UIParent):CreateTexture()')
        self.UI.SetIcon(tex, "atlas:VignetteLoot")
        self.UI.SetIcon(tex, self.UI.SOURCE_ICONS.vendor)
        self.assertEqual(lua_list(tex.texcoord), [0, 1, 0, 1])

    def test_progress_bar(self):
        bar = self.UI.CreateProgressBar(self.parent, 100, 4)
        Addon.call(bar, "SetProgress", 1, 4)
        self.assertAlmostEqual(bar.fill.width, 25, places=3)
        Addon.call(bar, "SetProgress", 5, 0)
        self.assertLess(bar.fill.width, 1)


if __name__ == "__main__":
    unittest.main()
