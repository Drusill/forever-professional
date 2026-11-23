# Materials Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Calculate action on any recipe opens a panel over the detail pane that turns the recipe and a quantity into a shopping list of raw materials (have / need from bags and bank), the craft steps in order with who crafts each, and a reagent tree where every intermediate switches between craft and buy, saved per item.

**Architecture:** `Model.lua` owns reagent reading (`M.Schematic`, `M.Reagents`, moved from `UI/Detail.lua`), the reverse index `M.RecipesCreating`, and a frame-free `M.PlanMaterials(roots, ctx)`: pass 1 decides each item once (craft or buy, which recipe, cycle-safe), pass 2 sums needs by level, subtracts inventory once per item and rounds to whole crafts. `ctx` injects reagents, inventory, who knows what and the saved switches, so #4 and #5 reuse the same plan with several roots. `Characters.lua` builds the live context (`ns.PlanContext`) and owns the saved switches (`ns.db.craftModes`). `UI/Calculator.lua` (new) only draws.

**Tech Stack:** Lua 5.1 (WoW Forever client, interface 16001), Python 3.12 `unittest` + `lupa` tests against `tests/wow_mock.lua`.

**Spec:** `docs/superpowers/specs/2026-11-23-materials-calculator-design.md` (issue #3)

## Global Constraints

- Branch `feat/3-materials-calculator` (off `develop`), one commit per task, don't push. Conventional Commits, no `Co-Authored-By` or AI attribution (user rule). The pull request into `develop` says `Closes #3`.
- Run `mise exec -- python -m unittest discover tests` after every change; the whole suite must stay green.
- Test first: watch each new test fail before writing the code. Pin existing behaviour before refactoring shared code (Tasks 1 and 6: `tests/test_detail.py` passes unmodified).
- One new Lua file, `UI\Calculator.lua`, listed in the TOC after `UI\Detail.lua` with ` [AllowLoadGameType camelot][ExcludeLoadGameType classic]` (Task 7). TOC changes need a full client restart in game.
- Never edit `ForeverProfessional/Data/`, `tools/`, or the community addons. Never use Blizzard's recipe tracking or profession filter setters.
- Every user-visible string goes through `Locale.lua` (`L.*`). Item and spell names stay live.
- Reuse, don't re-implement: reagents only through `M.Reagents`; who knows a recipe only through `ns.RecipeOwners`; names only through `ns.CharLabel`; the learnable/known rules stay where they are.
- The plan logic is frame-free and tested in `Model`; the UI only draws.
- lupa quirks: two Python wrappers of one Lua table don't compare equal (use `rawequal` through `a.lua.eval`); you can't index a Lua table with -1 from Python; two return values come back as a tuple.
- New UI must fit the 900×540 minimum window.

## Shared test fixture

`tests/test_calculator.py` (created in Task 1). Reagents come from the client's `SpellReagents` table (build
1.60.1.71037); the test seeds them through the mock, so they don't depend on `GetRecipeSchematic`'s default.

```python
# {spellID: [(itemID, count), ...]}, real reagents
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
```

Helpers in the file: `seed(a, reagents=REAGENTS)` writes `mock.schematics` and sets `mock.onlySchematics = true`
(unlisted spells have no schematic); `plan(a, roots, **overrides)` calls `M.PlanMaterials` with
`ns.PlanContext()` (from Task 5; Tasks 3–4 build a Lua ctx by hand: `knownBy` from a Python dict
`{spellID: ("me" | key, ...)}`, `have` from a dict, `mode` from a dict); `item(p, id)` reads `p.items[id]`;
`ids(lua_list)` for lists.

Expected numbers for **3932 ×1**, default choices, nothing in bags (Tester crafts the parts, Mina the bars):

| Item | Kind | Need | Crafts | Level | Notes |
|---|---|---|---|---|---|
| 4363 Copper Modulator | craft (me, 3926) | 1 | 1 | 1 | |
| 4359 Handful of Copper Bolts | craft (me, 3922) | 4 | 4 | 2 | 2 direct + 2 in the Modulator |
| 2841 Bronze Bar | craft (Mina, 2659) | 1 | 1 | 1 | yield 2, surplus 1 |
| 2840 Copper Bar | craft (Mina, 2657) | 6 | 6 | 3 | Modulator 1 + Bolts 4 + Bronze 1 |
| 3576 Tin Bar | craft (Mina, 3304) | 1 | 1 | 2 | |
| 2589 Linen Cloth, 2592 Wool Cloth | raw | 2, 1 | | | |
| 2770 Copper Ore, 2771 Tin Ore | raw | 6, 1 | | | |

Shopping (by item ID): `2589 ×2, 2592 ×1, 2770 ×6, 2771 ×1`. Steps: `2840, 3576, 4359, 2841, 4363`, then root `3932`.

## Review Focus

- **Cycles terminate, nothing is crafted inside its own subtree.** The essence ring with every item switched to craft, Water ↔ Living Essence, and Engineering 13240 eating its own output. Tests: Task 3 `test_cycle_ring_all_craft`, `test_cycle_two_step`, `test_root_output_as_reagent`.
- **Inventory used once across branches** (3 Bolts in bags don't count in both branches). Test: Task 4 `test_inventory_used_once`.
- **Multi-output rounding on the total,** not per branch (two roots needing 1 Bronze Bar each craft it once). Test: Task 3 `test_multi_output_rounded_on_total`.
- **Detail pane unchanged** through the schematic move (Task 1) and the item-text move (Task 6): `tests/test_detail.py` unmodified, including the async item tests.
- **Saved switches with bad values** load and are ignored. Test: Task 5 `test_bad_saved_modes_ignored`.
- **Each schematic read once** per spell, however often an item recurs. Test: Task 3 `test_schematic_read_once`.
- **Fit at 900×540.** Test: Task 8 `test_fits_minimum_window`.

---

### Task 1: Reagents read in the model; mock per-spell schematics and item counts

**Files:**
- Modify: `ForeverProfessional/Model.lua` (`M.Schematic`, `M.Reagents`)
- Modify: `ForeverProfessional/UI/Detail.lua` (drop `UI.GetSchematic` and `UI.schematics`; `CreatesText` uses `M.Schematic`, the Reagents block uses `M.Reagents`)
- Modify: `tests/wow_mock.lua` (`mock.schematics`, `mock.onlySchematics`, `C_Item.GetItemCount`, `mock.bags`, `mock.bank`)
- Test: `tests/test_calculator.py` (new: fixture, `ReagentsTest`); `tests/test_detail.py` unmodified

**Interfaces:**
- Produces:
  - `M.Schematic(spellID) -> table|nil`: `pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)`, cached in `M.schematics[spellID]` (`false` when none).
  - `M.Reagents(spellID) -> { {item, count}... } | nil`: one entry per slot with `reagents[1].itemID`; `count = quantityRequired or 1`; nil without a schematic; `{}` for a schematic with no slots.
  - Mock: `mock.schematics[id] = { {item, count}, ... }` returns a schematic with those slots (`outputItemID` from `mock.outputs[id]` when a test sets it); `mock.onlySchematics = true` makes unlisted spells return nil; otherwise today's fixed schematic. `C_Item.GetItemCount(id, includeBank) = (mock.bags[id] or 0) + (includeBank and mock.bank[id] or 0)`.

- [x] **Step 1: Run the detail tests as the pin**: `mise exec -- python -m unittest tests.test_detail -v` (PASS before any change).
- [x] **Step 2: Write the failing tests** (`ReagentsTest`, login with `CALC`, `seed(a)`)
  - `test_reagents_from_schematic`: `M.Reagents(3932)` → `[(4363, 1), (4359, 2), (2841, 1), (2592, 1)]`.
  - `test_reagents_missing`: `M.Reagents(999999)` is nil with `onlySchematics`.
  - `test_schematic_cached`: two `M.Reagents(3926)` calls → `mock.schematicCalls` grows by 1.
  - `test_item_count_mock`: `mock.bags[2589] = 1; mock.bank[2589] = 2` → `GetItemCount(2589)` 1, `GetItemCount(2589, true)` 3.
- [x] **Step 3: Run, expect failures**: `mise exec -- python -m unittest tests.test_calculator -v`
- [x] **Step 4: Implement** the mock additions, `M.Schematic`, `M.Reagents`, and switch `UI/Detail.lua` to them.
- [x] **Step 5: Full suite, expect PASS** (`test_detail.py` unmodified).
- [x] **Step 6: Commit**: `git commit -m "refactor(model): read recipe reagents in the model"`

---

### Task 2: Reverse index, yield, crafts for items

**Files:**
- Modify: `ForeverProfessional/Model.lua`
- Test: `tests/test_calculator.py` (`IndexTest`)

**Interfaces:**
- Produces:
  - `M.RecipesCreating(itemID) -> { {line, spellID}... } | nil`: from `rec.creates` over every line of `ns.Data.Recipes`, built once, each list sorted by spell ID.
  - `M.Yield(rec) -> number`: `count` if a number, `count[1]` if a table, else 1.
  - `M.CraftsFor(rec, items) -> number`: `math.ceil(items / M.Yield(rec))`; 0 for `items <= 0`.

- [x] **Step 1: Write the failing tests**
  - `test_recipes_creating_single`: 2840 → `[(186, 2657)]`.
  - `test_recipes_creating_several`: 3577 → `[(186, 3308), (171, 11479)]` (sorted by spell ID); 7080 → spells `[17561, 17563]`; 10577 → `[12716, 13240]`.
  - `test_recipes_creating_none`: 2770 (Copper Ore) → nil.
  - `test_index_matches_data`: every `(line, spellID)` with `creates` appears under its item; the total of all lists equals the Python count of recipes with `creates` (2,159 − 174 at the time of writing, computed, not hard-coded).
  - `test_yield`: 3932 → 1, 2659 → 2, 3931 (`{1, 3}`) → 1, 12584 → 3.
  - `test_crafts_for`: 12584 with 7 → 3; 2659 with 3 → 2; 3931 with 6 → 6; 0 items → 0.
- [x] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_calculator -v`
- [x] **Step 3: Implement**.
- [x] **Step 4: Full suite, expect PASS**
- [x] **Step 5: Commit**: `git commit -m "feat(model): index recipes by the item they create"`

---

### Task 3: Plan choices, cycles, switches and totals

**Files:**
- Modify: `ForeverProfessional/Model.lua` (`M.PlanMaterials`, pass 1 and pass 2)
- Test: `tests/test_calculator.py` (`PlanTest`, ctx built by hand in Lua)

**Interfaces:**
- Consumes: `M.RecipesCreating`, `M.Yield` (Task 2); `ctx.reagents`, `ctx.knownBy`, `ctx.mode`, `ctx.have` (have defaults to 0 here).
- Produces: `M.PlanMaterials(roots, ctx) -> plan` with `plan.roots` and `plan.items` as in the spec.
  - Pass 1: depth-first from each root's reagents with a path set (the root's output on it). Raw → `kind = "raw"`, `switchable = false`. On the path → `kind = "buy"`, `cycle = true`, `switchable = false`. Else usable makers = readable reagents, none on the path; wanted = `ctx.mode(item)` (`"craft"`/`"buy"`, anything else ignored) or `"craft"` when a usable maker has `known.me` or `#known.alts > 0`; pick: `me`, then alts, then lowest `rec.learn or 0`, then spell ID. No usable maker while wanting craft → `kind = "buy"`, `cycle = true` if makers existed. `switchable = true` for every item with a maker not on the path. `mode` = the saved override or nil.
  - Levels: after pass 1, `level` = longest distance from a root over the chosen recipes (root reagents are level 1).
  - Pass 2: roots add `crafts × count` to their reagents' `need`; items by level, shallow first; `net = max(0, need − have)`; craft → `crafts = ceil(net / yield)`, `surplus = crafts × yield − net`, adds to reagents; buy/raw → `buy = net`. `plan.roots[i].makes = crafts × yield`; `reagents = nil` when unreadable (no items added).

- [x] **Step 1: Write the failing tests** (`seed(a)`, ctx: Tester (`me`) knows 3922, 3926, 3932; Mina knows 2657, 2659, 3304, 3307, 3308)
  - `test_one_level`: 2329 ×1 → items `{2449, 765, 3371}` all `raw`, need 1 each; no crafted items.
  - `test_nested`: 3932 ×1 → kinds, spells, levels and `need` exactly as in the fixture table.
  - `test_shared_summed`: 3932 ×1 → 2840 need 6 (three branches).
  - `test_scales`: 3932 ×10 → 4359 need 40, 2841 need 10 with crafts 5 and surplus 0, 2840 need 55 (Modulator 10 + Bolts 40 + Bronze 5 crafts).
  - `test_multi_output_rounded_on_total`: roots `{3932 ×1}, {3932 ×1}` → 2841 need 2, crafts 1, surplus 0; roots `{3932 ×1}, {3938 ×1}` → 2841 need 3, crafts 2, surplus 1.
  - `test_known_by_alt_and_nobody`: 2840 `known.alts == [MINA]`, `known.me` false; with Mina's knowledge removed from ctx: 2840, 2841, 3576 are `buy`, switchable, and 2770 / 2771 absent.
  - `test_several_makers_alt`: 12584 ×1 → 3577 `craft` via 3308 (Mina).
  - `test_several_makers_me_first`: ctx where `me` also knows 11479 → 3577 via 11479, then 3575 `craft` via 3307 (Mina), 2772 raw.
  - `test_several_makers_lowest_skill`: nobody knows either, `mode(3577) = "craft"` → via 3308 (learn 155 < 225).
  - `test_several_makers_tie_spell_id`: root 17562, nobody knows, `mode(7080) = "craft"` → via 17561 (both learn 275).
  - `test_default_buy_when_nobody_knows`: 12584 with nobody → 3577 `buy`, `switchable`, `cycle` falsy.
  - `test_switch_buy`: `mode(2840) = "buy"` on 3932 → 2840 `buy`, need 6, `mode == "buy"`; 2770 absent.
  - `test_switch_craft_on_raw_ignored`: `mode(2592) = "craft"` → 2592 stays `raw`.
  - `test_bad_mode_ignored`: `mode(2840) = "bogus"` → same as default.
  - `test_cycle_two_step`: root 17563, me knows the 8 transmutes, `mode(12808) = "craft"` → 12808 `buy`, `cycle == true` (17564 needs 7080, the root's output).
  - `test_cycle_ring_all_craft`: root 17562, me knows the 8 transmutes, every essence and Living item `"craft"` → returns; 7080 via 17561, 7076 via 17560, 7078 `buy` with `cycle`; for every crafted item, none of its chosen recipe's reagents is the item itself or one of its ancestors (walk in Python).
  - `test_root_output_as_reagent`: root 13240 → 10577 `buy`, `cycle == true`, `switchable` false.
  - `test_unreadable_root`: root 999999 (no schematic) → `plan.roots[1].reagents` nil, no items, no error.
  - `test_unreadable_maker_is_unusable`: drop 2657 from `REAGENTS` → 2840 `buy` (no usable maker), `cycle` falsy.
  - `test_schematic_read_once`: 3932 ×1 → `mock.schematicCalls` == number of distinct spells read (3932, 3926, 3922, 2659, 2657, 3304).
- [x] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_calculator -v`
- [x] **Step 3: Implement** pass 1, levels and pass 2. Comment the two passes and the cycle rule above the function.
- [x] **Step 4: Full suite, expect PASS**
- [x] **Step 5: Commit**: `git commit -m "feat(model): plan materials across crafted intermediates"`

---

### Task 4: Inventory, shopping list, steps and tree

**Files:**
- Modify: `ForeverProfessional/Model.lua` (`plan.shopping`, `plan.steps`, `plan.tree`, `M.PLAN_TREE_MAX`)
- Test: `tests/test_calculator.py` (`OutputTest`)

**Interfaces:**
- Consumes: Task 3's plan.
- Produces:
  - `plan.shopping = { {item, need, have, buy}... }`: `buy`/`raw` items with `need > 0`, by item ID.
  - `plan.steps = { {item, spellID, line, crafts, known}... }`: crafted items with `crafts > 0`, level descending then item ID; then each root (`item = rec.creates` or nil, `crafts`).
  - `plan.tree[i] = { item, count, children }` per root; a crafted node's children use `ceil(count / yield) × reagent count`; `count` before inventory; stops after `M.PLAN_TREE_MAX = 400` nodes with `{ more = true }` as the last child.

- [x] **Step 1: Write the failing tests**
  - `test_shopping`: 3932 ×1 → `[(2589, 2, 0, 2), (2592, 1, 0, 1), (2770, 6, 0, 6), (2771, 1, 0, 1)]`.
  - `test_steps_order`: items `[2840, 3576, 4359, 2841, 4363, 4366]`, crafts `[6, 1, 4, 1, 1, 1]`; each step comes after every step making one of its reagents.
  - `test_inventory_intermediate`: have 4359 = 3 → 4359 crafts 1; 2840 need 3; 2770 buy 3.
  - `test_inventory_used_once`: have 2840 = 1 → 2840 net 5, crafts 5 (not 1 subtracted per branch); 2770 buy 5.
  - `test_inventory_raw`: have 2589 = 2 → shopping keeps `(2589, 2, 2, 0)`.
  - `test_inventory_covers_intermediate`: have 4363 = 1 → no 4363 step, 4359 need 2, the Modulator's subtree gone.
  - `test_root_output_not_subtracted`: have 4366 = 5 → root crafts still 1.
  - `test_tree`: 3932 ×1 → root children items `[4363, 4359, 2841, 2592]` with counts `[1, 2, 1, 1]`; 4363's children `[4359, 2840, 2589]` with `[2, 1, 2]`; 2841's children `[2840, 3576]` with `[1, 1]`; raw nodes have no children.
  - `test_tree_bought_has_no_children`: `mode(2841) = "buy"` → the 2841 node has no children.
  - `test_tree_cap`: with `M.PLAN_TREE_MAX = 5` → node count ≤ 5 plus one `more` marker, and `plan.items` still complete.
- [x] **Step 2: Run, expect failures**
- [x] **Step 3: Implement**.
- [x] **Step 4: Full suite, expect PASS**
- [x] **Step 5: Commit**: `git commit -m "feat(model): shopping list, craft steps and reagent tree"`

---

### Task 5: Player context and saved craft/buy choices

**Files:**
- Modify: `ForeverProfessional/Core.lua` (`DEFAULTS.craftModes`)
- Modify: `ForeverProfessional/Characters.lua` (`ns.PlanContext`, `ns.SetCraftMode`, `ns.ResetCraftModes`, `ns.CrafterText`)
- Modify: `ForeverProfessional/Locale.lua` (`CALC_YOU`, `CALC_NOBODY`)
- Test: `tests/test_calculator.py` (`ContextTest`), `tests/test_addon.py` (default)

**Interfaces:**
- Consumes: `M.Reagents`, `M.PlanMaterials`, `ns.RecipeOwners`, `ns.CharKey`, `ns.CharLabel`.
- Produces:
  - `ns.db.craftModes` (default `{}`).
  - `ns.PlanContext() -> ctx`: `reagents = M.Reagents`; `have(id) = C_Item.GetItemCount(id, true) or 0`; `knownBy(line, spellID)` from `ns.RecipeOwners(...).known`: `me = true` when it holds `ns.CharKey()`, `alts` = the other keys in order; `mode(id)` = `ns.db.craftModes[id]`.
  - `ns.SetCraftMode(itemID, mode)`: stores `"craft"` / `"buy"`, removes on nil.
  - `ns.ResetCraftModes()`: empties the table (same table, `wipe`).
  - `ns.CrafterText(known) -> text, kind`: `L.CALC_YOU, "me"` / `ns.CharLabel(alts[1]) .. " +N", "alt"` (no suffix for one alt) / `L.CALC_NOBODY, "nobody"`.

- [x] **Step 1: Write the failing tests** (login with `CALC`, `seed(a)`)
  - `test_default_craft_modes`: fresh DB → `ns.db.craftModes` empty table (`test_addon.py`).
  - `test_context_plan_matches_fixture`: `PlanMaterials({3932 ×1}, ns.PlanContext())` matches the fixture table (kinds, need, crafter `me` / `[MINA]`).
  - `test_context_have_counts_bank`: `mock.bags[4359] = 1; mock.bank[4359] = 2` → `item(4359).have == 3`, crafts 1.
  - `test_set_craft_mode`: `SetCraftMode(2840, "buy")` → saved, plan has 2840 `buy`; `SetCraftMode(2840, nil)` → gone, back to craft.
  - `test_reset_craft_modes`: two modes set → `ResetCraftModes()` → empty, same table (`rawequal`).
  - `test_saved_across_reload`: setup with `craftModes = { [2840] = "buy" }` → 2840 `buy`.
  - `test_bad_saved_modes_ignored`: setup with `craftModes = { [2840] = "bogus", [4359] = 5 }` → default plan, no error.
  - `test_crafter_text`: `{me = true}` → `("You", "me")`; `{alts = [MINA]}` → plain `"Mina"`, `"alt"`; two alts → `"Mina +1"`; `{}` → `("Nobody", "nobody")`.
  - `test_logged_in_is_me_even_when_alt_shown`: `UI.SetChar(MINA)` after `/fp` → `ns.PlanContext().knownBy(202, 3926).me` still true.
- [x] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_calculator tests.test_addon -v`
- [x] **Step 3: Implement**.
- [x] **Step 4: Full suite, expect PASS**
- [x] **Step 5: Commit**: `git commit -m "feat: saved craft or buy choices and the player's plan context"`

---

### Task 6: Shared item text and async loading

**Files:**
- Modify: `ForeverProfessional/UI/Widgets.lua` (`UI.ItemText`, `UI.LoadItems`)
- Modify: `ForeverProfessional/UI/Detail.lua` (uses them; `requested`, `ItemName`, `ItemColor`, `ItemText` and the loading loop leave the file)
- Test: `tests/test_widgets.py`; `tests/test_detail.py` unmodified

**Interfaces:**
- Produces:
  - `UI.ItemText(itemID, pending) -> text`: quality-coloured name or `Item #id`, queuing an uncached, not yet requested item in `pending`.
  - `UI.LoadItems(pending, stillCurrent, redraw)`: requests each item once per session; a callback redraws only while `stillCurrent()` is true; synchronous callbacks during the loop are coalesced into one `redraw()` after it.

- [x] **Step 1: Pin**: `mise exec -- python -m unittest tests.test_detail -v` (PASS, especially `test_async_output_item`, `test_async_item_rerenders`, `test_async_item_for_old_selection_ignored`).
- [x] **Step 2: Write the failing tests** (`tests/test_widgets.py` `ItemTextTest`)
  - `test_item_text_cached`: `mock.itemNames[2589] = "Linen Cloth"` → text contains `Linen Cloth`, `pending` empty.
  - `test_item_text_uncached`: unknown item → `Item #2589`, `pending == [2589]`; once requested, a second call doesn't queue it again.
  - `test_load_items_sync_coalesced`: two cached-on-load items (sync callbacks) → `redraw` called once.
  - `test_load_items_async_stale`: `mock.asyncItems[2589] = true`, `stillCurrent` returns false at flush → no redraw.
- [x] **Step 3: Run, expect failures**
- [x] **Step 4: Implement**; `UI.RefreshDetail` passes `function() return detail.current == spellID end` and `UI.RefreshDetail`.
- [x] **Step 5: Full suite, expect PASS** (`test_detail.py` unmodified)
- [x] **Step 6: Commit**: `git commit -m "refactor(ui): share item names and async item loading"`

---

### Task 7: Calculator panel, quantity and Shopping tab

**Files:**
- Create: `ForeverProfessional/UI/Calculator.lua`
- Modify: `ForeverProfessional/ForeverProfessional_Camelot.toc` (after `UI\Detail.lua`)
- Modify: `ForeverProfessional/UI/Detail.lua` (Calculate button in the header)
- Modify: `ForeverProfessional/UI/Window.lua` (create the panel over the detail panel; close it on recipe or profession change and on window hide)
- Modify: `ForeverProfessional/Locale.lua` (panel strings from the spec)
- Test: `tests/test_calculator.py` (`PanelTest`, `open_addon(CALC)` as in `test_ui.py`, then `seed`, `SelectProfession(202)`, `SelectRecipe(3932)`)

**Interfaces:**
- Consumes: `M.PlanMaterials`, `ns.PlanContext`, `ns.CrafterText`, `M.Yield`, `M.CraftsFor`; `UI.CreateSegmented`, `UI.CreateToggleButton`, `UI.CreateIconButton`, `UI.CreateSlot`, `UI.ItemText`, `UI.LoadItems`.
- Produces:
  - `detail.header.calcButton` (label `L.CALCULATE`).
  - `UI.calc` frame: `.back`, `.title`, `.who`, `.qty` (EditBox), `.unit` (segmented `crafts`/`items`), `.summary`, `.tabs` (segmented `shopping`/`steps`/`tree`), `.reset`, `.scroll`, `.rows` (pool), `.message`.
  - `UI.OpenCalculator(spellID)`, `UI.CloseCalculator()`, `UI.SetCalcQuantity(n)`, `UI.SetCalcUnit(key)`, `UI.SetCalcTab(key)`, `UI.RefreshCalculator()`; `UI.calc.plan` holds the last plan; `UI.calc.rendered` the drawn rows as `{ kind, item, ... }` for tests (like `detail.rendered`).

- [x] **Step 1: Write the failing tests**
  - `test_calculate_button_opens`: click `calcButton` → `UI.calc.shown`, title is the recipe name, tab `shopping`, quantity `"1"`.
  - `test_who`: `plain(UI.calc.who.text) == "Who: You"`; on 2657 (Mining tab) → `"Who: Mina"`; on a recipe nobody knows → `"Who: Nobody"`.
  - `test_shopping_rows`: rows `(item, need, have, buy)` equal the fixture shopping list; tab label `"Shopping 4"`.
  - `test_quantity`: `UI.SetCalcQuantity(10)` (and typing `"10"` into `.qty`) → rows scale; `"abc"` or `""` then focus lost → back to `"10"`; `1000` clamps to 999.
  - `test_unit_hidden_for_single_yield`: 3932 → `.unit` hidden; summary `"1 craft, makes 1"`.
  - `test_unit_items`: on 2659 (Mining) → `.unit` shown; Items with 3 → root crafts 2, summary `"2 crafts, 1 extra"`; Crafts with 3 → `"3 crafts, makes 6"`.
  - `test_unit_range`: 3931 → `.unit` shown, Items 6 → 6 crafts (plans with the minimum).
  - `test_enchant_no_output`: an Enchanting recipe without `creates` (first one in `ns.Data.Recipes[333]`) → opens, `.unit` hidden, no error.
  - `test_have_all`: everything in `mock.bags` → `.message` shows `L.CALC_HAVE_ALL`; shopping tab label `"Shopping 0"`.
  - `test_no_reagents`: open on a spell with no schematic → `.message` `L.CALC_NO_REAGENTS`, no rows.
  - `test_back`: click `.back` → hidden, detail shown on the same recipe.
  - `test_closes_on_other_recipe_and_hide`: `SelectRecipe(3926)` → hidden; reopen, `/fp` to close the window → hidden.
  - `test_unlearned_recipe`: a recipe nobody knows opens and plans.
- [x] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_calculator -v`
- [x] **Step 3: Implement**; add `UI\Calculator.lua` to the TOC (the tests load the TOC).
- [x] **Step 4: Full suite, expect PASS**
- [x] **Step 5: Commit**: `git commit -m "feat(ui): materials calculator panel with shopping list"`

---

### Task 8: Steps and Tree tabs, switches, Reset, live updates

**Files:**
- Modify: `ForeverProfessional/UI/Calculator.lua`
- Modify: `ForeverProfessional/UI/Window.lua` (`UI.Refresh` redraws the panel when shown)
- Test: `tests/test_calculator.py` (`PanelTabsTest`)

**Interfaces:**
- Consumes: Task 7's panel; `ns.SetCraftMode`, `ns.ResetCraftModes`.
- Produces: step rows (`kind = "step"`, `.switch` on intermediates), tree rows (`kind = "node"`, `depth`, `.switch` on switchable items, `.note` with `L.CALC_CYCLE`), shopping rows with a `Craft` switch on bought intermediates; `BAG_UPDATE_DELAYED` handler; `UI.CalcRowLayout(width, depth) -> { nameW }` for the fit check.

- [x] **Step 1: Write the failing tests**
  - `test_steps_tab`: `SetCalcTab("steps")` → rows `[2840, 3576, 4359, 2841, 4363, 4366]` with crafts and crafter texts (`Mina`, `Mina`, `You`, `Mina`, `You`, `You`); tab label `"Steps 6"`; the root row has no switch.
  - `test_tree_tab`: rows in depth-first order with depths `[0, 1, 2, 3, 4, ...]` matching `plan.tree`; raw rows show `L.CALC_RAW`; crafted rows show their crafter.
  - `test_switch_in_tree`: click 2841's switch → `ns.db.craftModes[2841] == "buy"`, its children gone, Shopping now lists 2841; switch shows `L.CALC_CRAFT`.
  - `test_switch_in_shopping`: on the bought 2841 row, click `Craft` → mode `"craft"`, 2841 leaves Shopping.
  - `test_reset`: after a switch `.reset` is shown; click → `ns.db.craftModes` empty, `.reset` hidden, default plan.
  - `test_cycle_note`: on 13240 → the 10577 row has `.note` `L.CALC_CYCLE` and no switch.
  - `test_bag_update`: `mock.bags[2770] = 6`, `fire("BAG_UPDATE_DELAYED")` → Copper Ore row `buy` gone (✓); hidden panel → no redraw (`UI.calc.renders` counter unchanged).
  - `test_refresh_redraws`: `ns.UpdateCharacter()` while open → redrawn, still open.
  - `test_fits_minimum_window`: at 900×540, `UI.CalcRowLayout(UI.DetailContentWidth(), 7).nameW >= 100`; the header, quantity row and tabs sum to no more than the panel's inner width; the scroll area is at least 300px tall.
- [x] **Step 2: Run, expect failures**
- [x] **Step 3: Implement**.
- [x] **Step 4: Full suite, expect PASS**
- [x] **Step 5: Commit**: `git commit -m "feat(ui): craft steps, reagent tree and craft or buy switches"`

---

### Task 9: Docs

**Files:**
- Modify: `README.md` (Features / How to use: the calculator)
- Modify: `AGENTS.md` (Layout: `UI/Calculator`; `Model` gains reagent reading and the material plan; `UI/Widgets` gains item text; saved `ns.db.craftModes`; client fact: `C_Item.GetItemCount(id, true)` counts the bank away from it, the global is gone)

- [x] **Step 1:** Update both files; don't touch `CHANGELOG.md` (rewritten at release time) or `docs/ideas.md`.
- [x] **Step 2:** Full suite, expect PASS.
- [x] **Step 3: Commit**: `git commit -m "docs: describe the materials calculator"`

---

## After Task 9

Run the full suite once more, then hand the user the spec's in-game checklist (new Lua file: full client
restart), on a character whose alt knows an intermediate. Open the pull request into `develop` only when the
user asks, with `Closes #3`.

## Implementation notes

- Extra exports the UI and tests use: `plan.order` (items by level), `plan.items[id].reagents` (the chosen recipe's reagents), `plan.roots[i].item` (output, nil for enchants), `M.PlanTree(plan)`, `UI.ToggleCraftMode(itemID)`, `UI.IsCalculatorShown()`. The panel's unit field is `UI.calc.unitKey`.
- Extra strings: `CALC_EXTRA_ONE`, `CALC_HAVE_NEED`, `CALC_TIMES`, `CALC_STEP`, `CALC_MORE`.
- The shopping rows' Craft switch and the have / need tooltip landed in Task 8 with the other switches.
- Two test expectations were wrong, not the code: with Bronze Bar bought, Tin Bar leaves the plan too (only Bronze Bar uses it); in 13240's tree the root row is also a Goblin Mortar, so the cycle test picks the depth-1 row.
- A switch on an item that closes a cycle is hidden; Reset clears a saved override on such an item.
- Commits: spec and plan `34596bd`, Task 1 `5ccf05f`, Task 2 `561bcba`, Task 3 `842d5f2`, Task 4 `c9d0c27`, Task 5 `49c93d0`, Task 6 `e28045e`, Task 7 `73a6b52`, Task 8 `2b5e1d5`, Task 9 next.
- In-game checklist (2026-11-23, Salvador, Blacksmithing 241, with alts): items 1–10 pass (screenshots in the session). Checked on Target Dummy, Heavy Copper Maul, Blessed Plate Pauldrons, Runed Silver Rod, Transmute: Earth to Water and Robe of Winter Night (18436). Nit: on the deepest tree row the "Would need itself" note is cut off; the row above shows it in full.
