"""Materials calculator: reagent reading, the reverse index and the material plan in Model.lua, the player's
plan context in Characters.lua, and the calculator panel."""
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Addon, lua_list  # noqa: E402

# {spellID: [(itemID, count), ...]}: real reagents from the client's SpellReagents table (build 1.60.1.71037).
REAGENTS = {
    3932: [(4363, 1), (4359, 2), (2841, 1), (2592, 1)],   # Engineering: Target Dummy -> 4366
    3926: [(4359, 2), (2840, 1), (2589, 2)],              # Engineering: Copper Modulator -> 4363
    3922: [(2840, 1)],                                    # Engineering: Handful of Copper Bolts -> 4359
    3938: [(2841, 2), (2880, 1)],                         # Engineering: Bronze Tube -> 4371
    2657: [(2770, 1)],                                    # Mining: Copper Bar -> 2840
    3304: [(2771, 1)],                                    # Mining: Tin Bar -> 3576
    2659: [(2840, 1), (3576, 1)],                         # Mining: Bronze Bar -> 2841, makes 2
    3931: [(4364, 3), (2589, 1)],                         # Engineering: Coarse Dynamite -> 4365, makes {1, 3}
    3929: [(2836, 1)],                                    # Engineering: Coarse Blasting Powder -> 4364
    12584: [(3577, 1)],                                   # Engineering: Gold Power Core -> 10558, makes 3
    3308: [(2776, 1)],                                    # Mining: Gold Bar -> 3577 (learn 155)
    11479: [(3575, 1)],                                   # Alchemy: Transmute Iron to Gold -> 3577 (learn 225)
    3307: [(2772, 1)],                                    # Mining: Iron Bar -> 3575
    13240: [(10577, 1), (3860, 1), (10505, 3)],           # Engineering: The Mortar: Reloaded -> 10577 (itself)
    12716: [(10559, 2), (3860, 4), (10505, 5), (10558, 1), (7068, 1)],   # Engineering: Goblin Mortar -> 10577
    17559: [(7082, 1)], 17560: [(7078, 1)], 17561: [(7076, 1)], 17562: [(7080, 1)],   # Alchemy essence ring
    17563: [(12808, 1)], 17564: [(7080, 1)], 17565: [(12803, 1)], 17566: [(7076, 1)],
    2329: [(2449, 1), (765, 1), (3371, 1)],               # Alchemy: Elixir of Lion's Strength, no intermediate
}
TRANSMUTES = [17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566]

MINA = "Player-1-0000000F"
# Logged-in Tester knows the Engineering parts; alt Mina (Horde Warrior, Mining 175) knows the smelts.
CALC = """
ForeverProfessionalDB = { version = 2, chars = {
  ["Player-1-0000000F"] = { guid = "Player-1-0000000F", name = "Mina", class = "WARRIOR", faction = "Horde",
    level = 30, updated = 1795000000, professions = { [186] = { skill = 175, max = 225 } },
    learned = { [2657] = true, [2659] = true, [3304] = true, [3307] = true, [3308] = true } },
} }
mock.learned = { [3922] = true, [3926] = true, [3932] = true }
"""


def seed(a, reagents=REAGENTS):
    """Give each listed spell its real reagents; unlisted spells have no schematic."""
    rows = ", ".join("[%d] = { %s }" % (spell, ", ".join("{ %d, %d }" % r for r in items))
                     for spell, items in reagents.items())
    a.run("mock.onlySchematics = true; mock.schematics = { %s }" % rows)


def pairs(t):
    return [(e.item, e.count) for e in lua_list(t)]


class ReagentsTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(setup=CALC)
        self.a.login()
        seed(self.a)
        self.M = self.a.ns.Model

    def test_reagents_from_schematic(self):
        self.assertEqual(pairs(self.M.Reagents(3932)), [(4363, 1), (4359, 2), (2841, 1), (2592, 1)])

    def test_reagents_missing(self):
        self.assertIsNone(self.M.Reagents(999999))

    def test_schematic_cached(self):
        before = self.a.mock.schematicCalls or 0
        self.M.Reagents(3926)
        self.M.Reagents(3926)
        self.assertEqual(self.a.mock.schematicCalls, before + 1)

    def test_item_count_mock(self):
        self.a.run("mock.bags[2589] = 1; mock.bank[2589] = 2")
        count = self.a.g.C_Item.GetItemCount
        self.assertEqual(count(2589), 1)
        self.assertEqual(count(2589, True), 3)
        self.assertEqual(count(2770, True), 0)


if __name__ == "__main__":
    unittest.main()
