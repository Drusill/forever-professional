"""Recipe item tooltips: who knows the recipe, who can learn it, who needs more skill."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ALTS, Addon, lua_list, plain  # noqa: E402

LEARNABLE = "Learnable by: Dru (Rogue), Paly (Horde vendors only)"
LOW = "Skill too low: Tester 120 / 280, Dru (Druid) 150 / 280"
KNOWN = "Known by: Dru (Rogue)"


def logged_in(setup=ALTS):
    a = Addon(setup=setup)
    a.login()
    return a


class TooltipTest(unittest.TestCase):
    def setUp(self):
        self.a = logged_in()
        self.tt = self.a.g.GameTooltip

    def lines(self, tt=None):
        return [plain(l) for l in lua_list((tt or self.tt).lines)]

    def set_item(self, item_id, tt="GameTooltip"):
        self.a.run(f"{tt}:SetItemByID({item_id})")

    def post_calls(self):
        return lua_list(self.a.mock.postCalls[0])

    def test_registered_once(self):
        self.assertEqual(len(self.post_calls()), 1)

    def test_vendor_recipe_item(self):
        self.set_item(250999)
        self.assertIn(LEARNABLE, self.lines())
        self.assertIn(LOW, self.lines())

    def test_known_by(self):
        self.set_item(6053)
        self.assertIn(KNOWN, self.lines())

    def test_list_teach_index(self):
        def pairs(item):
            return [(e[1], e[2]) for e in lua_list(self.a.ns.RecipeForItem(item))]
        self.assertEqual(pairs(7678), [(185, 9513)])
        self.assertEqual(pairs(18160), [(185, 9513)])
        self.assertIsNone(self.a.ns.RecipeForItem(2447))

    def test_not_a_recipe_item(self):
        self.set_item(2447)
        self.assertEqual(self.lines(), [])

    def test_nobody_has_profession(self):
        self.set_item(18647)
        self.assertEqual(self.lines(), [])

    def test_once_per_item(self):
        self.set_item(250999)
        count = len(self.lines())
        self.a.run("for _, fn in ipairs(mock.postCalls[0]) do fn(GameTooltip, { type = 0, id = 250999 }) end")
        self.assertEqual(len(self.lines()), count)

    def test_lines_again_after_clear(self):
        for _ in range(2):
            self.set_item(250999)
            self.assertEqual(self.lines().count(LEARNABLE), 1)

    def test_item_ref_tooltip(self):
        self.set_item(6053, "ItemRefTooltip")
        self.assertIn(KNOWN, self.lines(self.a.g.ItemRefTooltip))

    def test_other_tooltip_ignored(self):
        self.a.run("_other = CreateFrame('GameTooltip', 'OtherTooltip', UIParent); _other.lines = {}; "
                   "function _other:AddLine(t) self.lines[#self.lines + 1] = t end; "
                   "for _, fn in ipairs(mock.postCalls[0]) do fn(_other, { type = 0, id = 250999 }) end")
        self.assertEqual(lua_list(self.a.g._other.lines), [])

    def test_errors_swallowed(self):
        self.a.g._ns = self.a.ns
        self.a.run("_ns.OwnerLines = function() error('boom') end")
        self.set_item(250999)   # must not raise
        self.assertEqual(self.lines(), [])


class FallbackHookTest(unittest.TestCase):
    def test_fallback_hook(self):
        a = logged_in(ALTS + "; TooltipDataProcessor = nil")
        tt = a.g.GameTooltip
        self.assertIsNotNone(tt.scripts.OnTooltipSetItem)
        a.run("GameTooltip.item = 6053; GameTooltip.lines = {}; GameTooltip.scripts.OnTooltipSetItem(GameTooltip)")
        self.assertIn(KNOWN, [plain(l) for l in lua_list(tt.lines)])


if __name__ == "__main__":
    unittest.main()
