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


if __name__ == "__main__":
    unittest.main()
