"""The options window: tooltip blocks and the minimap button, /fp options."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list, plain  # noqa: E402

KEYS = ["minimap", "tooltipOwners", "tooltipTracked", "tooltipUsedIn", "tooltipUsedInNames"]


def logged_in(setup=None):
    a = Addon(setup=setup)
    a.login()
    return a


class OptionsTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.UI = self.a.ns.UI
        self.db = self.a.g.ForeverProfessionalDB

    def window(self):
        return self.a.g.ForeverProfessionalOptions

    def open(self):
        self.a.slash("options")
        return self.window()

    def row(self, key):
        return self.window().rows[key]

    def click(self, key):
        r = self.row(key)
        r.scripts.OnClick(r)

    def test_slash_toggles(self):
        self.assertIsNone(self.window())
        self.assertTrue(self.open().shown)
        self.a.slash("Options")
        self.assertFalse(self.window().shown)

    def test_rows_in_order_all_checked(self):
        w = self.open()
        self.assertEqual([r.key for r in lua_list(w.order)], KEYS)
        for key in KEYS:
            self.assertTrue(self.row(key).checked, key)
            self.assertTrue(self.row(key).enabled, key)
            self.assertNotEqual(plain(self.row(key).label.text or ""), "", key)

    def test_reflects_saved_state(self):
        a = logged_in("ForeverProfessionalDB = { minimapHidden = true, tooltipTracked = false }")
        a.slash("options")
        rows = a.g.ForeverProfessionalOptions.rows
        self.assertFalse(rows.minimap.checked)
        self.assertFalse(rows.tooltipTracked.checked)
        self.assertTrue(rows.tooltipOwners.checked)

    def test_tooltip_rows_write_settings(self):
        self.open()
        for key in KEYS[1:]:
            self.click(key)
            self.assertIs(self.db[key], False, key)
            self.assertFalse(self.row(key).checked, key)
            self.click(key)
            self.assertIs(self.db[key], True, key)

    def test_minimap_row(self):
        self.open()
        btn = self.a.g.ForeverProfessionalMinimapButton
        printed = len(self.a.printed())
        self.click("minimap")
        self.assertIs(self.db.minimapHidden, True)
        self.assertFalse(btn.shown)
        self.click("minimap")
        self.assertIs(self.db.minimapHidden, False)
        self.assertTrue(btn.shown)
        self.assertEqual(len(self.a.printed()), printed)   # no chat message from the window

    def test_names_row_follows_used_in(self):
        self.open()
        self.click("tooltipUsedIn")
        self.assertFalse(self.row("tooltipUsedInNames").enabled)
        self.click("tooltipUsedIn")
        self.assertTrue(self.row("tooltipUsedInNames").enabled)

    def test_names_row_disabled_when_saved_off(self):
        a = logged_in("ForeverProfessionalDB = { tooltipUsedIn = false }")
        a.slash("options")
        self.assertFalse(a.g.ForeverProfessionalOptions.rows.tooltipUsedInNames.enabled)

    def test_used_in_row_starts_and_stops_the_build(self):
        a = logged_in("ForeverProfessionalDB = { tooltipUsedIn = false }")
        U = a.ns.UsedIn
        self.assertFalse(U.Building())
        a.slash("options")
        rows = a.g.ForeverProfessionalOptions.rows
        rows.tooltipUsedIn.scripts.OnClick(rows.tooltipUsedIn)
        self.assertTrue(U.Building())
        rows.tooltipUsedIn.scripts.OnClick(rows.tooltipUsedIn)
        self.assertFalse(U.Building())

    def test_escape_closes(self):
        self.open()
        self.assertIn("ForeverProfessionalOptions", lua_list(self.a.g.UISpecialFrames))

    def test_close_button(self):
        w = self.open()
        w.close.scripts.OnClick(w.close)
        self.assertFalse(w.shown)

    def test_movable(self):
        w = self.open()
        self.assertIsNotNone(w.scripts.OnDragStart)

    def test_rows_fit(self):
        w = self.open()
        self.assertLessEqual(w.width, 1024)
        self.assertLessEqual(w.height, 768)
        self.assertLessEqual(w.contentBottom, w.height)
        for key in KEYS:
            r = self.row(key)
            used = r.indent + 24 + self.a.call(r.label, "GetStringWidth")
            self.assertLessEqual(used, w.width - 2 * w.pad, key)

    def test_help_lists_options(self):
        self.a.slash("help")
        self.assertIn("/fp options", self.a.printed()[-1])


class OpenFromTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.a.slash("")          # open the main window, so its header exists
        self.UI = self.a.ns.UI
        self.L = self.a.ns.L

    def options_shown(self):
        w = self.a.g.ForeverProfessionalOptions
        return bool(w and w.shown)

    def test_gear_left_of_close(self):
        gear = self.UI.optionsButton
        point, rel, rel_point, x, _ = self.a.call(gear, "GetPoint")
        self.assertEqual((point, rel_point), ("RIGHT", "LEFT"))
        self.assertTrue(self.a.lua.eval("rawequal")(rel, self.a.g.ForeverProfessionalFrame.close))
        point, rel, *_ = self.a.call(self.UI.charButton, "GetPoint")
        self.assertTrue(self.a.lua.eval("rawequal")(rel, gear))
        gear.scripts.OnClick(gear)
        self.assertTrue(self.options_shown())
        gear.scripts.OnClick(gear)
        self.assertFalse(self.options_shown())

    def test_gear_icon(self):
        self.assertEqual(self.UI.optionsButton.icon.texture, r"Interface\Buttons\UI-OptionsButton")

    def test_gear_tooltip(self):
        self.a.g.enter(self.UI.optionsButton)
        self.assertEqual(lua_list(self.a.g.GameTooltip.lines), [self.L.OPTIONS_BUTTON])

    def test_header_fits_minimum_width(self):
        # An estimate, as in the #4 spec (the mock doesn't measure fonts): the large name font ~8px a letter,
        # small text ~6px, "Tracked 99" at most. Left to right: icon, name, Tracked, Skill, Recipes, character,
        # gear, close. Checked in game at the minimum width too.
        names = [p.name for p in self.a.ns.Data.Professions.values()]
        name_w = 8 * max(len(n) for n in names)
        tracked_w = 16 + 6 * len(self.L.TRACKED_N % 99)
        used = (14 + 34 + 10 + name_w + 16 + tracked_w + 16 + 150 + 16 + 150 + 14 + 150 + 6
                + self.UI.optionsButton.width + 2 + 32 + 6)
        self.assertLessEqual(used, self.UI.MIN_W - self.UI.RAIL_W - 1)

    def test_minimap_right_click(self):
        btn = self.a.g.ForeverProfessionalMinimapButton
        shown = self.a.g.ForeverProfessionalFrame.shown
        self.a.call(btn, "Click", "RightButton")
        self.assertTrue(self.options_shown())
        self.assertEqual(self.a.g.ForeverProfessionalFrame.shown, shown)
        self.a.call(btn, "Click", "LeftButton")
        self.assertNotEqual(self.a.g.ForeverProfessionalFrame.shown, shown)

    def test_minimap_registers_right_clicks(self):
        btn = self.a.g.ForeverProfessionalMinimapButton
        self.assertIn("RightButtonUp", lua_list(btn.clicks))

    def test_minimap_tooltip_mentions_right_click(self):
        self.a.g.enter(self.a.g.ForeverProfessionalMinimapButton)
        self.assertIn(self.L.MINIMAP_RIGHT_CLICK, lua_list(self.a.g.GameTooltip.lines))

    def test_compartment_right_click(self):
        click = self.a.g.ForeverProfessional_OnAddonCompartmentClick
        shown = self.a.g.ForeverProfessionalFrame.shown
        click("ForeverProfessional", "RightButton")
        self.assertTrue(self.options_shown())
        self.assertEqual(self.a.g.ForeverProfessionalFrame.shown, shown)
        click("ForeverProfessional", "LeftButton")
        self.assertNotEqual(self.a.g.ForeverProfessionalFrame.shown, shown)


if __name__ == "__main__":
    unittest.main()
