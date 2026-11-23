# Materials calculator: design

Date: 2026-11-23. Issue: #3. Status: draft, waiting for approval.

## Intent

A recipe's detail lists only its direct reagents. A crafter who wants ten of something has to work out by hand
which reagents are themselves crafted, who among their characters can craft them, and how much raw material
that adds up to. A "Calculate" action turns one recipe and a quantity into a shopping list of raw materials,
the craft steps in order with the character who can do each, and a reagent tree where each intermediate can be
switched between craft and buy.

## Goals, non-goals, anti-goals

- Goals: a calculator panel over the detail pane for any recipe; a reverse index item → recipes that create it;
  a frame-free plan in `Model` that takes several root recipes, so #4 (tracked recipes) and #5 (skill-up
  planner) reuse it for combined totals; have / need from the logged-in character's bags and bank; craft/buy
  choices saved per item.
- Non-goals: several recipes in one plan in the UI (that's #4); alt inventories (the plan takes the count as a
  function, so they can plug in later); prices or "cheapest" choices (no auction data); a reverse reagent index
  ("used in", that's #6); baking reagent IDs in the pipeline.
- Anti-goals: touching Blizzard's profession window or its recipe tracking; an infinite loop or a crash on the
  data's cycles; a plan that silently drops a reagent it couldn't read.

## Findings that shaped this

Reagents aren't baked, so to size the problem the client's `SpellReagents` table (wago.tools, build
1.60.1.71037, the pipeline's pin) was joined with the baked recipes, offline and outside the repo.

- Every one of the 2,159 recipes has a reagent row. 1,618 use at least one craftable reagent; there are 164
  distinct craftable reagents. Following the shallowest maker, chains reach 7 levels (Tailoring 18436); 541
  recipes have no intermediate.
- Many chains cross professions: Blacksmithing uses Mining bars 417 times, Tailoring uses Alchemy items 266
  times. Leatherworking (677) and Tailoring (423) use their own intermediates most.
- The most used intermediates: Rugged Leather 8170 (177 recipes), Bolt of Runecloth 14048 (139), Forever's new
  Alchemy reagent 249409 (131), Heavy Leather 4234 (127), Thorium Bar 12359 (120). Light Leather 2318 (100)
  is made from Ruined Leather Scraps (Leatherworking 2881), Heavy Leather from Medium Leather.
- Only 6 items have more than one maker: Gold Bar 3577 (Mining 3308 at 155, Alchemy 11479 at 225), Truesilver
  Bar 6037 (Mining 10098 at 230, Alchemy 11480 at 225), Essence of Earth 7076 and Essence of Water 7080 (two
  transmutes each, all at 275), Gordok Ogre Suit 18258 (Tailoring 22813, Leatherworking 22815), Goblin Mortar
  10577 (Engineering 12716, and 13240, which consumes a Mortar).
- Two cycles: the elemental essence transmutes (Alchemy 17559–17566: Air → Fire → Earth → Water → Air, plus
  Water ↔ Living Essence and Earth ↔ Living Earth), and Engineering 13240 using its own output.
- Output counts: 2,061 recipes make 1; 81 make a fixed 2–200; 7 make a range (`count = {min, max}`, e.g.
  Coarse Dynamite 3931, 1–3); 174 make no item (171 enchants, 3 Engineering). 21 craftable reagents come more
  than one per craft (Bronze Bar 2841: 2).
- `UI.GetSchematic` (`UI/Detail.lua:84`) caches `GetRecipeSchematic(spellID, false)`; the Reagents section reads
  `reagentSlotSchematics[i].reagents[1].itemID` and `quantityRequired` (`UI/Detail.lua:362`).
- `ns.RecipeOwners(line, spellID).known` (`Characters.lua:130`) lists the characters who know a recipe, the
  logged-in one first (`ns.ListChars` order); `ns.CharLabel` gives class-coloured unique names.
- At the 900×540 minimum the detail panel is 432px wide (396px of scroll content) and 470px tall.
- In game (2026-11-23, checked by the user): `C_Item.GetItemCount(id, true)` counts the bank while away from
  it (`0 1` for an item only in the bank, at the bank and away); the global `GetItemCount` is gone (`nil`).
- The mock returns one fixed schematic for every spell and has no `GetItemCount`.

## Decisions (made with the user)

1. **Separate panel.** A Calculate button in the detail header opens a calculator panel over the detail pane;
   Back returns to the recipe.
2. **Tabs.** Under the quantity row, a segmented control `Shopping | Steps | Tree`, one view at a time.
3. **Several makers: known first, then skill.** Known by the logged-in character, then by a cached alt, then the
   lowest `learn`, ties by spell ID. A recipe that would close a cycle is skipped. No picker.
4. **Default craft if someone knows it.** An intermediate is crafted when the logged-in character or a cached
   alt knows a usable recipe for it, bought otherwise (tagged "nobody"). Every intermediate can be switched.
5. **Switches saved per item,** account-wide in `ns.db.craftModes`, applied in every plan (and later in #4);
   a Reset clears them.
6. **Every recipe,** learned or not; the top line says who knows it, or nobody.
7. **Crafts / Items.** One number box; a `Crafts | Items` switch shows only for recipes that make more than one
   per craft (fixed or range). Items round up to whole crafts, ranges plan with the minimum.
8. **"You" is the logged-in character,** for crafter tags and inventory alike; every other character, including
   the one shown in the selector, is named.
9. **Inventory at every level.** Bags and bank reduce the need wherever an item appears, intermediates included,
   and their subtree shrinks. Each count is used once across the whole plan. The roots' output is never
   subtracted.
10. **Bank counts** (in-game check above): have / need reads `C_Item.GetItemCount(id, true)`, labelled
    "bags and bank".

## Approaches considered

| | Totals | Trade-off |
|---|---|---|
| **Chosen** | Two passes: decide each item once (craft or buy, which recipe) in a depth-first walk, then sum needs level by level (an item after everything that uses it), subtract inventory and round to whole crafts once per item | Inventory used once (decision 9) and multi-output rounding done on the total, not per branch (two branches needing 1 Bronze Bar each craft 1, not 2). The tree view shows per-branch amounts separately. |
| Rejected | Recursive per-branch expansion, summed at the end | Simple, but rounds per branch (over-crafts multi-output items) and subtracts the same bag stack in every branch. |

| | Reagent reading | Trade-off |
|---|---|---|
| **Chosen** | `M.Schematic` / `M.Reagents` in `Model.lua` (the cache moves out of `UI/Detail.lua`), and the plan takes `reagents` as a function | The detail pane, the calculator and #6 share one cache; tests plug in fixtures. |
| Rejected | The plan calls `UI.GetSchematic` | Model would depend on UI, and #6's tooltip would load the window code's cache. |

## Design

### Reagents and the reverse index (`Model.lua`)

- `M.Schematic(spellID)`: today's `UI.GetSchematic`, moved; `pcall`ed, cached per spell (`false` for none).
- `M.Reagents(spellID) -> { {item, count}... } | nil`: one entry per reagent slot (`reagents[1].itemID`,
  `quantityRequired or 1`); nil when there's no schematic. The detail pane's Reagents section uses it.
- `M.RecipesCreating(itemID) -> { {line, spellID}... } | nil`: built on first use from `creates` across every
  profession, each list sorted by spell ID.
- `M.Yield(rec) -> number`: `count` when a number, `count[1]` for a range, else 1.
- `M.CraftsFor(rec, items) -> number`: `ceil(items / M.Yield(rec))`, at least 1 for `items >= 1`.

### The plan (`Model.lua`)

```lua
plan = M.PlanMaterials(roots, ctx)
roots = { { spellID = 3932, line = 202, crafts = 1 }, ... }
ctx = {
    reagents = function(spellID) return { {item = 4363, count = 1}, ... } or nil end,
    have     = function(itemID) return 0 end,                          -- optional
    knownBy  = function(line, spellID) return { me = true, alts = { key, ... } } end,
    mode     = function(itemID) return "craft" or "buy" or nil end,   -- optional
}
```

**Pass 1, decide.** Depth-first from each root's reagents, with the set of items on the current path (a root's
output is on its own path). Each item is decided once:

- No recipe creates it: `kind = "raw"`, not switchable.
- On the current path (only a root's own output, as in Engineering 13240): `kind = "buy"`, `cycle = true`.
- Otherwise its makers are filtered to the usable ones: reagents readable and none of them on the current path.
  The wanted mode is `ctx.mode(item)`, or by default `"craft"` when some usable maker is known by anyone.
  Crafting picks the first usable maker by decision 3. Wanted craft with no usable maker: `kind = "buy"`,
  `cycle = true` when makers existed but each closed a cycle. Every item with a maker is switchable.
- A crafted item puts itself on the path and decides its reagents; its `level` is the longest distance from a
  root, so every item sits deeper than anything that uses it.

**Pass 2, totals.** Roots add `crafts × count` to each reagent's `need`. Items are processed by `level`, shallow
first: `have = ctx.have(item)`, `net = max(0, need − have)`; a crafted item gets `crafts = ceil(net / yield)`,
`surplus = crafts × yield − net`, and adds `crafts × count` to its reagents' `need`; a bought or raw item gets
`buy = net`.

**Result:**

```lua
plan.items[itemID] = { item, kind = "craft"|"buy"|"raw", need, have, net, buy, crafts, yield, surplus,
                       spellID, line, known = {me, alts}, level, cycle, switchable, mode }   -- mode: saved override
plan.roots[i]      = { spellID, line, crafts, yield, makes, known, reagents (nil when unreadable) }
plan.shopping      = { {item, need, have, buy}... }   -- bought and raw items with need > 0, by item ID
plan.steps         = { {item, spellID, line, crafts, known}... }  -- crafted items, deepest level first, then
                                                                   -- item ID; then the roots
plan.tree[i]       = { item, count, children = {...} }  -- per root, per-branch amounts before inventory
```

The tree is display-only: each node's `count` is what its branch asks for (`ceil(count / yield)` crafts per
crafted node, before inventory), its kind comes from `plan.items`. It stops at `M.PLAN_TREE_MAX` (400) nodes,
with a `more` marker.

Reused later: #4 passes several tracked recipes as `roots` and gets one combined shopping list with each bag
count used once; #5 passes its step recipes the same way; #6 reuses `M.Reagents`.

### Character context and saved choices (`Characters.lua`, `Core.lua`)

- `DEFAULTS.craftModes = {}`: `{ [itemID] = "craft" | "buy" }`. Other values are ignored when read. New
  optional field, no `db.version` bump.
- `ns.PlanContext() -> ctx`: `reagents = M.Reagents`; `have = C_Item.GetItemCount(id, true) or 0`;
  `knownBy` from `ns.RecipeOwners(line, spellID).known`, `me` when it holds `ns.CharKey()`; `mode` from
  `ns.db.craftModes`.
- `ns.SetCraftMode(itemID, mode)` (`"craft"`, `"buy"`, or nil to clear) and `ns.ResetCraftModes()`.
- `ns.CrafterText(known) -> text, kind`: `L.CALC_YOU` (`"me"`), the first alt's `ns.CharLabel` plus ` +N` for
  more alts (`"alt"`), or `L.CALC_NOBODY` (`"nobody"`).

### Shared item text (`UI/Widgets.lua`)

`ItemText` and the async item loading move out of `UI/Detail.lua` as `UI.ItemText(itemID, pending)` and
`UI.LoadItems(pending, stillCurrent, redraw)` (one request per item for the session, synchronous callbacks
coalesced into one redraw). The detail pane and the calculator both use them.

### Calculator panel (`UI/Calculator.lua`, new)

```
[<] [icon] Target Dummy                          Who: You
Quantity [  1 ]  [Crafts|Items]   1 craft, makes 1
[Shopping 4] [Steps 5] [Tree]                [Reset choices]
-------------------------------------------------------------
[i] Copper Ore                       0 / 6        buy 6
[i] Tin Ore                          0 / 1        buy 1
[i] Linen Cloth                      2 / 2          ✓
[i] Wool Cloth                       0 / 1        buy 1
```

- `UI.calc`: a frame over the detail panel (same anchors, higher frame level, its own background), hidden by
  default. `UI.OpenCalculator(spellID)` / `UI.CloseCalculator()`. It closes on Back, when another recipe or
  profession is selected, and when the window hides.
- The detail header gets a **Calculate** button (`UI.CreateToggleButton`) on its chip row, right-aligned
  under the difficulty scale.
- Header: Back (`UI.CreateIconButton`), recipe icon and name, and `Who:` with `ns.CrafterText` of the root.
- Quantity row: a numeric edit box (1–999; empty or invalid reverts to the last valid number on focus loss),
  the `Crafts | Items` segmented control when `M.Yield(rec) > 1` or `rec.count` is a range, and a summary:
  `L.CALC_MAKES` ("1 craft, makes 1") or, in Items mode, `L.CALC_EXTRA` ("4 crafts, 2 extra"). The mode resets
  to Crafts and the quantity to 1 on open.
- Tabs (`UI.CreateSegmented`): `Shopping n` (items still to buy), `Steps n`, `Tree`. Reset choices shows when
  `ns.db.craftModes` has entries.
- Shopping rows: slot, name, `have / need` (green when have ≥ need), `buy n` or a check. Bought intermediates
  carry a `Craft` switch. Empty list: `L.CALC_HAVE_ALL`. Hovering the have / need column shows
  `L.CALC_HAVE_TOOLTIP` ("Bags and bank of the character you're playing").
- Steps rows: `1. Copper Bar ×6`, profession name, crafter (`ns.CrafterText`, coloured by kind); intermediates
  carry a `Buy` switch; the roots come last, no switch.
- Tree rows: indented 12px per level, slot, `name ×count`, crafter tag or `Buy` / `Raw`, the switch on
  switchable items, `L.CALC_CYCLE` on cycle items.
- A switch calls `ns.SetCraftMode(item, other mode)` and redraws; Reset calls `ns.ResetCraftModes()`.
- Unreadable root reagents: the panel shows `L.CALC_NO_REAGENTS` instead of the tabs' content.
- Redraws on `BAG_UPDATE_DELAYED` and from `UI.Refresh` while shown. Item names load through `UI.LoadItems`.
- At 900×540: header rows take about 96px, leaving about 360px of rows; at depth 7 the tree row's name keeps at
  least 100px.

### Strings (`Locale.lua`)

`CALCULATE = "Calculate"`, `CALC_BACK = "Back to the recipe"`, `CALC_WHO = "Who: %s"`,
`CALC_QUANTITY = "Quantity"`, `CALC_CRAFTS = "Crafts"`, `CALC_ITEMS = "Items"`,
`CALC_MAKES = "%d crafts, makes %d"` (and a singular `CALC_MAKES_ONE = "1 craft, makes %d"`),
`CALC_EXTRA = "%d crafts, %d extra"`, `CALC_SHOPPING = "Shopping"`, `CALC_STEPS = "Steps"`,
`CALC_TREE = "Tree"`, `CALC_CRAFT = "Craft"`, `CALC_BUY = "Buy"`, `CALC_RAW = "Raw"`, `CALC_YOU = "You"`,
`CALC_NOBODY = "Nobody"`, `CALC_BUY_N = "buy %d"`, `CALC_RESET = "Reset choices"`,
`CALC_HAVE_ALL = "You have everything for this."`, `CALC_HAVE_TOOLTIP = "Bags and bank of the character you're playing"`,
`CALC_CYCLE = "Would need itself: buy it"`, `CALC_NO_REAGENTS = "This recipe's reagents couldn't be read."`
(reuse existing `L.*` where one already says the same).

## Testing

Test first, one step at a time, `mise exec -- python -m unittest discover tests` after each.

- New `tests/test_calculator.py`. The detail tests (`tests/test_detail.py`) must pass unmodified through the
  schematic and item-text moves.
- Mock: `mock.schematics[spellID] = { {item, count}, ... }` gives that spell its own reagents (other spells keep
  today's fixed schematic); `C_Item.GetItemCount(id, includeBank)` returns `mock.bags[id]`, plus `mock.bank[id]`
  only with `includeBank`.
- Fixture: real recipe IDs and reagents from the client table (see the plan); characters seeded through the
  saved DB, so `ns.RecipeOwners` and `ns.PlanContext` run for real.
- Covered: one level; nested intermediates; shared reagents summed across branches; multi-output rounding on
  the total; an item made by more than one recipe (each preference step); both cycles (no infinite loop, no
  item crafted inside its own subtree); craft/buy switches and their saving; inventory subtraction at every
  level, used once; Crafts / Items; unreadable reagents; the panel's tabs, switches, Reset, Back, bag updates
  and its fit at 900×540.

## Steps

On `feat/3-materials-calculator`, one Conventional Commit each, no push:

1. Reagent reading moves to the model; mock gets per-spell schematics and item counts.
2. Reverse index, yield and crafts-for-items.
3. Plan pass 1 and pass 2: choices, cycles, switches, totals.
4. Plan outputs: inventory, shopping list, steps, tree.
5. Player context and saved craft/buy choices.
6. Shared item text and async loading.
7. Calculator panel: button, header, quantity, Shopping tab.
8. Steps and Tree tabs, switches, Reset, bag updates.
9. README and AGENTS updates.

## Left to the builder

Exact pixel layout of the panel rows and the Calculate button; textures for the check and the switches; the
colours of crafter tags (reuse `OWNER_DOTS`-style green / gold / grey); whether the tree indents with guide
lines; which extra real recipes the tests use.

## In-game checklist (after implementation)

New Lua file in the TOC: **restart the client fully** (`/reload` doesn't load it).

1. Open `/fp`, Engineering, Target Dummy (3932), or any recipe with an intermediate known by an alt. Click
   Calculate: the panel covers the detail pane; `Who:` names the crafter.
2. Shopping: raw materials with have / need; an item in your bank counts while you're away from the bank.
3. Steps: intermediates in order (a bar before the parts made from it), each with You, an alt's name, or Nobody.
4. Tree: switch an alt-crafted intermediate to Buy: it moves to Shopping, its sub-reagents disappear;
   `/reload`: still Buy; Reset choices: back to craft.
5. Type 10 in Quantity: totals scale. On a recipe that makes several (Bronze Bar, a Mining smelt), switch to
   Items, type 3: 2 crafts, 1 extra.
6. Pick up or bank a needed reagent while the panel is open: have / need updates.
7. Open Calculate on an unlearned recipe and on an enchant (no output item): both plan; the enchant shows no
   Crafts | Items switch.
8. An Alchemy transmute (e.g. Essence of Water 17563) with its intermediates switched to Craft: no freeze, the
   looping item shows "Would need itself".
9. Back returns to the recipe; picking another recipe or closing the window closes the panel.
10. At the minimum window size (900×540): the header, quantity row and tabs fit; a deep tree (Tailoring 18436)
    keeps names readable.
