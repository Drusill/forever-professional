"""The mock client itself: features the addon tests rely on."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list  # noqa: E402


class MockTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon()
        self.a.login()

    def test_schematic_slot_alternatives(self):
        self.a.run("mock.schematics[2963] = { {2589, 2, 2592, 4306} }; "
                   "_s = C_TradeSkillUI.GetRecipeSchematic(2963, false)")
        slot = self.a.g._s.reagentSlotSchematics[1]
        self.assertEqual([r.itemID for r in lua_list(slot.reagents)], [2589, 2592, 4306])
        self.assertEqual(slot.quantityRequired, 2)

    def test_shift(self):
        self.assertFalse(self.a.lua.eval("IsShiftKeyDown()"))
        self.a.run("mock.shift = true")
        self.assertTrue(self.a.lua.eval("IsShiftKeyDown()"))

    def test_tooltip_owner(self):
        self.a.run("_o = CreateFrame('Frame'); GameTooltip:SetOwner(_o, 'ANCHOR_RIGHT')")
        self.assertTrue(self.a.lua.eval("rawequal(GameTooltip:GetOwner(), _o)"))

    def test_tooltip_line_colors(self):
        self.a.run("GameTooltip:SetOwner(UIParent); GameTooltip:AddLine('x', 0.5, 0.6, 0.7, true); "
                   "GameTooltip:AddLine('y')")
        colors = lua_list(self.a.g.GameTooltip.colors)
        self.assertEqual(list(colors[0].values()), [0.5, 0.6, 0.7])
        self.assertEqual(list(colors[1].values()), [])

    def test_refresh_data_reruns_post_calls(self):
        self.a.run("_n = 0; TooltipDataProcessor.AddTooltipPostCall(0, function() _n = _n + 1 end); "
                   "GameTooltip:SetItemByID(2589); GameTooltip:AddLine('extra'); GameTooltip:RefreshData()")
        self.assertEqual(self.a.g._n, 2)
        self.assertNotIn("extra", lua_list(self.a.g.GameTooltip.lines))


if __name__ == "__main__":
    unittest.main()
