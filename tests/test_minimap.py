"""Minimap button, /fp minimap and the addon compartment entry."""
import math
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list, toc_metadata  # noqa: E402

RING = 198 / 2 + 5          # the mock minimap is 198 wide; the button sits 5 outside its edge
CENTER = (1700, 900)        # the mock minimap's centre


def logged_in(setup=None):
    a = Addon(setup=setup)
    a.login()
    return a


def ring_point(angle):
    return math.cos(math.radians(angle)) * RING, math.sin(math.radians(angle)) * RING


class ButtonTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.btn = self.a.g.ForeverProfessionalMinimapButton

    def offset(self, btn=None):
        point, rel, rel_point, x, y = Addon.call(btn or self.btn, "GetPoint")
        self.assertEqual((point, rel_point), ("CENTER", "CENTER"))
        self.assertEqual(rel.name, "Minimap")
        return x, y

    def assertOffset(self, actual, expected):
        self.assertAlmostEqual(actual[0], expected[0], places=3)
        self.assertAlmostEqual(actual[1], expected[1], places=3)

    def window_shown(self):
        f = self.a.g.ForeverProfessionalFrame
        return bool(f and f.shown)

    def test_created_on_login_as_minimap_child(self):
        self.assertIsNotNone(self.btn)
        self.assertTrue(self.a.run("return ForeverProfessionalMinimapButton:GetParent() == Minimap"))
        self.assertTrue(self.btn.shown)

    def test_icon_is_the_toc_icon(self):
        icon = toc_metadata()["IconTexture"][0]
        textures = [r.texture for r in lua_list(self.btn.regions)]
        self.assertIn(icon, textures)

    def test_left_click_toggles_window(self):
        self.a.call(self.btn, "Click", "LeftButton")
        self.assertTrue(self.window_shown())
        self.a.call(self.btn, "Click", "LeftButton")
        self.assertFalse(self.window_shown())

    def test_right_click_does_nothing(self):
        self.a.call(self.btn, "Click", "RightButton")
        self.assertFalse(self.window_shown())

    def test_default_position_is_bottom_left_on_the_ring(self):
        self.assertOffset(self.offset(), ring_point(225))

    def test_drag_saves_angle_and_moves_button(self):
        self.a.g.drag(self.btn, CENTER[0] + 50, CENTER[1])
        self.assertAlmostEqual(self.a.g.ForeverProfessionalDB.minimapAngle % 360, 0, places=3)
        self.assertOffset(self.offset(), ring_point(0))

    def test_drag_converts_cursor_with_the_minimap_scale(self):
        # Edit Mode can scale the minimap cluster; the cursor comes in unscaled pixels.
        self.a.g.Minimap.effectiveScale = 2
        self.a.g.drag(self.btn, CENTER[0] * 2, (CENTER[1] + 50) * 2)
        self.assertAlmostEqual(self.a.g.ForeverProfessionalDB.minimapAngle, 90, places=3)

    def test_drag_does_nothing_once_a_button_bin_owns_the_button(self):
        # EnhanceQoL's minimap button bin re-parents collected buttons into its own grid.
        self.a.run('local bin = CreateFrame("Frame", "ButtonBin", UIParent)\n'
                   'ForeverProfessionalMinimapButton:SetParent(bin)\n'
                   'ForeverProfessionalMinimapButton:ClearAllPoints()\n'
                   'ForeverProfessionalMinimapButton:SetPoint("TOPLEFT", bin, "TOPLEFT", 4, -4)')
        self.a.g.drag(self.btn, CENTER[0] + 50, CENTER[1])
        point, rel, _, x, y = Addon.call(self.btn, "GetPoint")
        self.assertEqual((point, rel.name, x, y), ("TOPLEFT", "ButtonBin", 4, -4))
        self.assertEqual(self.a.g.ForeverProfessionalDB.minimapAngle, 225)

    def test_drag_hides_tooltip(self):
        self.a.g.enter(self.btn)
        self.a.g.drag(self.btn, CENTER[0], CENTER[1] - 50)
        self.assertFalse(self.a.g.GameTooltip.shown)

    def test_saved_angle_is_restored(self):
        a = logged_in("ForeverProfessionalDB = { minimapAngle = 90 }")
        self.assertOffset(self.offset(a.g.ForeverProfessionalMinimapButton), ring_point(90))

    def test_square_minimap_puts_45_degrees_on_the_corner(self):
        a = logged_in('ForeverProfessionalDB = { minimapAngle = 45 }\n'
                      'function GetMinimapShape() return "SQUARE" end')
        self.assertOffset(self.offset(a.g.ForeverProfessionalMinimapButton), (RING, RING))

    def test_tooltip_shows_name_and_actions(self):
        self.a.g.enter(self.btn)
        tip = self.a.g.GameTooltip
        L = self.a.ns.L
        self.assertTrue(tip.shown)
        self.assertTrue(self.a.run("return GameTooltip.owner == ForeverProfessionalMinimapButton"))
        lines = lua_list(tip.lines)
        self.assertEqual(lines[0], "ForeverProfessional")
        self.assertIn(L.MINIMAP_CLICK, lines)
        self.assertIn(L.MINIMAP_DRAG, lines)

    def test_tooltip_in_a_button_bin_drops_the_drag_hint(self):
        self.a.run('ForeverProfessionalMinimapButton:SetParent(CreateFrame("Frame", "ButtonBin", UIParent))')
        self.a.g.enter(self.btn)
        lines = lua_list(self.a.g.GameTooltip.lines)
        L = self.a.ns.L
        self.assertIn(L.MINIMAP_CLICK, lines)
        self.assertNotIn(L.MINIMAP_DRAG, lines)
        self.assertIn(L.MINIMAP_HIDE_HINT, lines)

    def test_tooltip_hides_on_leave(self):
        self.a.g.enter(self.btn)
        self.a.g.leave(self.btn)
        self.assertFalse(self.a.g.GameTooltip.shown)


class SlashMinimapTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.btn = self.a.g.ForeverProfessionalMinimapButton
        self.L = self.a.ns.L

    def test_hides_button_and_saves_flag(self):
        self.a.slash("minimap")
        self.assertFalse(self.btn.shown)
        self.assertIs(self.a.g.ForeverProfessionalDB.minimapHidden, True)
        self.assertIn(self.L.MINIMAP_HIDDEN, self.a.printed()[-1])

    def test_second_call_shows_button_again(self):
        self.a.slash("minimap")
        self.a.slash("minimap")
        self.assertTrue(self.btn.shown)
        self.assertIs(self.a.g.ForeverProfessionalDB.minimapHidden, False)
        self.assertIn(self.L.MINIMAP_SHOWN, self.a.printed()[-1])

    def test_ignores_case(self):
        self.a.slash("Minimap")
        self.assertFalse(self.btn.shown)

    def test_hidden_flag_is_restored_on_login(self):
        a = logged_in("ForeverProfessionalDB = { minimapHidden = true }")
        self.assertFalse(a.g.ForeverProfessionalMinimapButton.shown)

    def test_help_mentions_it(self):
        self.a.slash("help")
        self.assertIn("/fp minimap", self.a.printed()[-1])

    def test_tooltip_says_how_to_hide_the_button(self):
        self.a.g.enter(self.btn)
        self.assertIn(self.L.MINIMAP_HIDE_HINT, lua_list(self.a.g.GameTooltip.lines))


class CompartmentTest(unittest.TestCase):
    """The client calls the TOC's AddonCompartmentFunc* globals with (addonName, ...)."""

    def setUp(self):
        self.a = logged_in()
        self.meta = toc_metadata()
        self.L = self.a.ns.L

    def func(self, key):
        return self.a.g[self.meta[key][0]]

    def test_click_toggles_window(self):
        click = self.func("AddonCompartmentFunc")
        click("ForeverProfessional", "LeftButton")
        self.assertTrue(self.a.g.ForeverProfessionalFrame.shown)
        click("ForeverProfessional", "LeftButton")
        self.assertFalse(self.a.g.ForeverProfessionalFrame.shown)

    def test_enter_shows_tooltip_on_the_entry(self):
        entry = self.a.run('return CreateFrame("Button", "CompartmentEntry")')
        self.func("AddonCompartmentFuncOnEnter")("ForeverProfessional", entry)
        tip = self.a.g.GameTooltip
        self.assertTrue(tip.shown)
        self.assertTrue(self.a.run("return GameTooltip.owner == CompartmentEntry"))
        lines = lua_list(tip.lines)
        self.assertEqual(lines[0], "ForeverProfessional")
        self.assertIn(self.L.MINIMAP_CLICK, lines)
        self.assertNotIn(self.L.MINIMAP_DRAG, lines)

    def test_leave_hides_tooltip(self):
        entry = self.a.run('return CreateFrame("Button")')
        self.func("AddonCompartmentFuncOnEnter")("ForeverProfessional", entry)
        self.func("AddonCompartmentFuncOnLeave")("ForeverProfessional", entry)
        self.assertFalse(self.a.g.GameTooltip.shown)


class SavedDefaultsTest(unittest.TestCase):
    def test_existing_save_gets_minimap_defaults(self):
        a = Addon(setup='ForeverProfessionalDB = { version = 1, filter = "learned" }')
        a.login()
        db = a.g.ForeverProfessionalDB
        self.assertEqual(db.minimapAngle, 225)
        self.assertIs(db.minimapHidden, False)
        self.assertEqual(db.filter, "learned")


if __name__ == "__main__":
    unittest.main()
