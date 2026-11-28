# "Used in" Reagent Tooltip Implementation Plan

> Steps use checkbox (`- [x]`) syntax for tracking. Implement task by task, test first.

**Goal:** Item tooltips say which professions of your characters use an item as a reagent, how many of those recipes are known, and list them with Shift. A background index, built live after login, backs the lines. A small options window turns the tooltip lines and the minimap button on and off. `/fp debug` prints the index cost.

**Architecture:** `Model.lua` adds a raw reagent reader (`M.ReagentItems`) and a frame-free, batch-driven index builder (`M.NewUsedInIndex`). `UsedIn.lua` (new) drives the build over frames after login, keeps the stats, and turns an item into per-profession groups and tooltip lines. `Tooltip.lua` adds the block after the tracked lines, gates each block by its setting, and redraws on Shift. `UI/Options.lua` (new) is the options window. `Core.lua` gets the defaults and the `/fp options` and `/fp debug` commands.

**Tech Stack:** Lua 5.1 (WoW Forever client, interface 16001), Python 3.12 `unittest` + `lupa` tests against `tests/wow_mock.lua`.

**Spec:** `docs/superpowers/specs/2026-11-27-used-in-tooltip-design.md` (issue #6)

## Global Constraints

- Branch `feat/6-used-in-tooltip` (off `develop`), one commit per task, don't push. Conventional Commits, no `Co-Authored-By` or AI attribution (user rule). The pull request into `develop` says `Closes #6`, and is opened only when the user asks.
- Run `mise exec -- python -m unittest discover tests` after every change; the whole suite must stay green.
- Test first: watch each new test fail before writing the code. Pin before refactoring shared code (Task 1): `ReagentsTest` in `tests/test_calculator.py` and the existing `tests/test_tooltip.py` / `tests/test_tracked.py` tooltip tests pass unmodified.
- Two new Lua files, each listed in the TOC with ` [AllowLoadGameType camelot][ExcludeLoadGameType classic]`: `UsedIn.lua` after `Characters.lua` and before `Tooltip.lua` (Task 5), and `UI\Options.lua` after `UI\Tracked.lua` (Task 9). TOC changes need a full client restart in game.
- Never edit `ForeverProfessional/Data/`, `tools/`, or the community addons. No new top-level folders.
- The mock behaves like the client: `C_Item` getters throw on nil. Guard nil item IDs.
- Every user-visible string goes through `Locale.lua` (`L.*`). Item and spell names stay live.
- Reuse, don't re-implement: recipe names through `M.RecipeDisplayName`; knowing a recipe through `c.learned`; `side` checks the way `ns.RecipeOwners` does (`rec.side and rec.side ~= c.faction`); check rows through `UI.CreateCheckRow`; panels through `UI.Panel`; the gear through `UI.CreateIconButton`; showing and hiding the minimap button through the existing minimap code (extract a setter from `ToggleHidden`, don't copy it).
- Logic is frame-free and tested in `Model.lua` / `UsedIn.lua`; the UI only draws.
- lupa quirks: two wrappers of one Lua table don't compare equal; two return values come back as a tuple; prefer the Edit tool over shell heredocs.

## Shared test fixture

`tests/test_used_in.py` (new, Task 3). With `mock.onlySchematics = true` and these `mock.schematics` (real
spell IDs, so `ns.Data.Recipes` has them; the exact lines are read from the data in `setUp`, not
hardcoded):

| Spell | Recipe (line) | Slots |
|---|---|---|
| 2963 | Bolt of Linen Cloth (Tailoring 197) | 2589 ×2 |
| 3275 | Linen Bandage (First Aid 129) | 2589 ×1 |
| 2387 | Linen Cloak (Tailoring) | 2996 ×1, 2320 ×1 |
| 3915 | Brown Linen Shirt (Tailoring) | 2996 ×1, 2320 ×1 |
| 7183 | Elixir of Minor Defense (Alchemy 171) | 2452 ×1, 2589 ×1 (Linen made up, to put it in Alchemy) |
| 2795 | Beer Basted Boar Ribs (Cooking 185), `side = "Alliance"` | 2589 ×1 (made up) |

A slot with alternatives is written `{itemID, count, alt1, alt2...}` (mock extension, Task 2). All six spell
IDs are in `Data/Recipes` (checked 2026-11-27).

Characters (the test's own saved variables): the logged-in Tester (Horde) holds Tailoring and knows 2963; alt
Dru (Horde) holds First Aid, Alchemy and Cooking and knows 3275; Paly (Alliance) holds Cooking. Expected for
Linen Cloth 2589 (Tester's Tailoring first, then by profession name):

- `Used in 1 Tailoring recipe (1 known)`
- `Used in 1 Alchemy recipe (0 known)`
- `Used in 1 Cooking recipe (0 known)` (the Alliance recipe counts because Paly holds Cooking)
- `Used in 1 First Aid recipe (1 known)`

Without Paly, the Alliance recipe drops out, and Cooking, now with no countable recipe, has no line. A group
with 0 countable recipes is never shown.

## Review Focus

- **No hitch and no full schematics in memory:** `M.schematics` stays empty after a full build (Task 3 `test_schematics_untouched`); `Step(n)` reads at most n (`test_batch_size`).
- **The counting rules:** alts, the faction rule, professions nobody holds (Task 6).
- **A tooltip error never breaks someone else's tooltip:** Task 7 `test_used_in_error_swallowed`.
- **Refactors keep behaviour:** Task 1's pins, plus `tests/test_tooltip.py`, `tests/test_tracked.py` and `tests/test_minimap.py` unmodified.
- **Settings:** a saved `false` survives login (Task 4); every checkbox applies right away (Task 9).

---

### Task 1: Pin shared behaviour

**Files:**
- Test: `tests/test_tooltip.py` (`test_block_order_recipe_and_tracked`: a recipe item that is also a tracked reagent shows blank, owner lines, blank, tracked lines, in that order)
- Test: `tests/test_calculator.py` (`test_reagents_first_of_slot`: a slot with two reagents yields only the first from `M.Reagents`; needs the mock's alternative slots from Task 2, so this test lands in Task 2 instead if the mock can't express it yet)
- Test: `tests/test_minimap.py` (`test_left_click_toggles_only`: a right click today does nothing)

- [x] **Step 1:** Write the pins. They must pass against current code (they pin, they don't drive). Check each can fail by breaking the code briefly.
- [x] **Step 2:** Full suite, expect PASS.
- [x] **Step 3: Commit**: `test: pin tooltip order, reagent reading and minimap clicks`

### Task 2: Mock support

**Files:**
- Modify: `tests/wow_mock.lua`: `mock.schematics` slots accept alternatives `{itemID, count, alt...}`; `IsShiftKeyDown()` returns `mock.shift`; tooltips get `IsShown`, `Show`, `Hide`, `GetOwner`, and `RefreshData` (clears, then re-runs the item post-calls for `self.item`) unless `mock.noRefreshData`.
- Test: `tests/test_addon.py` (or the closest mock test file): one test per mock addition.

- [x] **Step 1:** Failing tests for the mock additions. **Step 2:** Implement. **Step 3:** Full suite.
- [x] **Step 4: Commit**: `test(mock): reagent alternatives, Shift and tooltip refresh`

### Task 3: Reagent reader and index builder (`Model.lua`)

**Interfaces:**
- `M.ReagentItems(spellID) -> { itemID... } | nil`: every reagent of every slot, distinct, slot order; uses `M.schematics[spellID]` when it's a table, else `pcall(GetRecipeSchematic, spellID, false)` without caching.
- `M.NewUsedInIndex() -> builder` with `Step(n) -> done`, `Done()`, `Lookup(itemID) -> { {line, spellID}... } | nil`, and counters `read`, `missing`, `items`, `entries`. Queue order: lines ascending, spells ascending. Lists sorted by line, `learn`, spell ID when the last step finishes.

- [x] **Step 1: Failing tests** (`tests/test_used_in.py`, `IndexTest`):
  - `test_reagent_items_all_slots_and_alternatives`, `test_reagent_items_distinct`, `test_reagent_items_missing` (nil), `test_reagent_items_uses_cache` (`mock.schematicCalls` unchanged for a spell already in `M.schematics`).
  - `test_schematics_untouched`: after a full build, `next(M.schematics) == nil`.
  - `test_batch_size`: `Step(10)` raises `read` by 10 and calls the API at most 10 times.
  - `test_index_lookup`: Linen 2589 → the fixture's recipes, sorted; an unused item → nil; `missing` counts recipes without schematics.
  - `test_done_once`: `Step` after done returns true and reads nothing.
- [x] **Step 2:** Run, expect failures. **Step 3:** Implement. **Step 4:** Full suite.
- [x] **Step 5: Commit**: `feat(model): reverse reagent index built in batches`

### Task 4: Settings defaults

**Files:** `Core.lua` (`DEFAULTS`: `tooltipOwners`, `tooltipTracked`, `tooltipUsedIn`, `tooltipUsedInNames` = true; `ns.Setting(key)` reading `ns.db`, true when there's no db yet), tests in `tests/test_addon.py`.

- [x] **Step 1: Failing tests:** defaults true; a saved `false` stays false after login; `ns.Setting` before `InitDB`.
- [x] **Step 2–4:** Run, implement, full suite.
- [x] **Step 5: Commit**: `feat(core): tooltip settings`

### Task 5: Background build and stats (`UsedIn.lua`, new)

**Interfaces:** `ns.UsedIn.Start()`, `ns.UsedIn.Stop()`, `ns.UsedIn.Ready()`, `ns.UsedIn.Finish()` (synchronous, for tests and `/fp debug`), `ns.UsedIn.stats` (spec's list), `ns.UsedIn.BATCH = 40`. Login schedules `Start` after 5 s when `tooltipUsedIn` is on. The chain re-arms with `C_Timer.After(0, step)`.

- [x] **Step 1: Failing tests** (`BuildTest`): nothing built before the delay; after `flush()` rounds the build progresses by `BATCH` per round; not started with the setting off; `Stop` halts the chain; `Start` twice doesn't run two chains; stats filled (frames, read, missing, items, entries, total and slowest ms ≥ 0, memory numbers present).
- [x] **Step 2:** Run, expect failures. **Step 3:** Add `UsedIn.lua` to the TOC, implement. **Step 4:** Full suite.
- [x] **Step 5: Commit**: `feat(used-in): build the reagent index over frames after login`

### Task 6: Groups (`UsedIn.lua`)

**Interface:** `ns.UsedInGroups(itemID)` as in the spec; nil until ready.

- [x] **Step 1: Failing tests** (`GroupsTest`, the fixture): the three groups and their order; known counts by alt; the Alliance recipe with and without Paly; a recipe known by a character despite its side counts; a profession nobody holds has no group; recipes sorted by `learn` then name; nil before ready.
- [x] **Step 2–4:** Run, implement, full suite.
- [x] **Step 5: Commit**: `feat(used-in): count recipes per profession your characters hold`

### Task 7: Tooltip lines (`UsedIn.lua`, `Tooltip.lua`, `Locale.lua`)

**Interface:** `ns.UsedInLines(itemID, shift) -> { {text, r, g, b}... }`; `Tooltip.lua` adds them after the tracked block with a blank line; owner and tracked blocks gated by `tooltipOwners` / `tooltipTracked`.

- [x] **Step 1: Failing tests** (through `GameTooltip:SetItemByID`): the fixture's three lines after "Tracked total"; singular; "(0 known)"; the hint as the last line; with `mock.shift` the names (white known, grey unknown) under each group; 12 recipes → 10 names + `  and 2 more`; `tooltipUsedInNames` off → no hint, no names even with Shift; `tooltipUsedIn` off → no block; not ready → no block; `tooltipOwners` / `tooltipTracked` off hide their blocks; an error inside `ns.UsedInLines` is swallowed and reported (`test_used_in_error_swallowed`); an enchant-like recipe without `creates` doesn't trip the nil guard.
- [x] **Step 2–4:** Run, implement, full suite.
- [x] **Step 5: Commit**: `feat(tooltip): "Used in" lines with Shift recipe names`

### Task 8: Shift redraw (`Tooltip.lua`)

- [x] **Step 1: Failing tests:** `fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)` with a shown item tooltip and `mock.shift = true` → names appear (via `RefreshData`); with `mock.noRefreshData` → the owner's `OnEnter` runs; `"LCTRL"` → nothing; a hidden tooltip → nothing; registration wrapped in `pcall`.
- [x] **Step 2–4:** Run, implement, full suite.
- [x] **Step 5: Commit**: `feat(tooltip): redraw item tooltips when Shift changes`

### Task 9: Options window (`UI/Options.lua`, new; `Core.lua`; `UI/Minimap.lua`; `Locale.lua`)

**Interfaces:** `UI.ToggleOptions()`, `UI.ShowOptions()`, `UI.HideOptions()`; `MB.SetHidden(hidden)` extracted from `MB.ToggleHidden` (which then calls it); `/fp options`.

- [x] **Step 1: Failing tests** (`tests/test_options.py`): `/fp options` shows and hides it; five rows in the spec's order with the right checked state; clicking each writes its variable (minimap row shows and hides the button, the `/fp minimap` chat message isn't printed from the window); the Shift row disabled while "Used in" is off and enabled again when it's on; turning "Used in" on with no index starts the build; listed in `UISpecialFrames`; fits a 1024×768 `UIParent`; `/fp minimap` still works (existing tests unmodified).
- [x] **Step 2:** Run, expect failures. **Step 3:** Add `UI\Options.lua` to the TOC, implement. **Step 4:** Full suite.
- [x] **Step 5: Commit**: `feat(ui): options window`

### Task 10: Open options from the gear and right-clicks (`UI/Window.lua`, `UI/Minimap.lua`)

- [x] **Step 1: Failing tests:** a gear button left of the close button opens options and has an "Options" tooltip; the header still fits at 900 wide (charButton, Tracked and Skill don't overlap); minimap right click opens options and left click still toggles the window; the minimap tooltip has "Right-click: options"; `ForeverProfessional_OnAddonCompartmentClick("ForeverProfessional", "RightButton")` opens options, `"LeftButton"` toggles the window.
- [x] **Step 2–4:** Run, implement, full suite. Update Task 1's `test_left_click_toggles_only` pin to the new behaviour in this commit, with the reason in the commit body.
- [x] **Step 5: Commit**: `feat(ui): open options from the window and the minimap`

### Task 11: `/fp debug` (`Core.lua`, `UsedIn.lua`, `Locale.lua`)

- [x] **Step 1: Failing tests:** before start → "Used in index: not started" (or "off" when the setting is off); during → "building, n / 2158 recipes"; after → one line per stat (total ms, slowest batch ms, frames, wall seconds, read, missing, items, entries, memory KB before / after), and "first hover: n ms" once an item tooltip was shown after ready; `/fp help` lists `/fp options` and `/fp debug`.
- [x] **Step 2–4:** Run, implement, full suite.
- [x] **Step 5: Commit**: `feat(core): /fp debug prints the reagent index cost`

### Task 12: Docs

**Files:** `README.md` (Features / How to use: "Used in" lines, Shift, the options window and how to open it, `/fp options`, `/fp debug`); `AGENTS.md` (Layout: `UsedIn`, `UI/Options`, `Model` gains the reagent index; saved variables: the four tooltip settings; client facts only once checked in game). Don't touch `CHANGELOG.md` or `docs/ideas.md`.

- [x] **Step 1:** Update both files. **Step 2:** Full suite.
- [x] **Step 3: Commit**: `docs: describe the "Used in" tooltip and the options window`

---

## After Task 12

Run the full suite, then give the user the in-game checklist below (new Lua files: full client restart). Open
the pull request into `develop` only when the user asks, with `Closes #6`.

## In-game checklist (draft, finalized after Task 12)

1. Full client restart, then log in. No BugSack errors.
2. Wait about 10 s, then type `/fp debug`: the index is done; note total ms, slowest batch ms (≤ 8), frames, missing (expected 0), items, memory.
3. Hover Linen Cloth (or any cloth/herb/ore): one "Used in" line per profession your characters hold, known counts plausible, the hint last.
4. Hold Shift while hovering, then release it: the names appear and disappear without moving the mouse (bag item, merchant item, chat link).
5. Hover a tracked reagent: tracked block first, "Used in" after it.
6. `/fp debug` again: "first hover" ms (≤ 2).
7. Open options from `/fp options`, the gear, a right-click on the minimap button and on the compartment entry. Toggle each checkbox and re-hover: lines go and come back; the minimap button hides and shows; the Shift row greys out with "Used in" off.
8. `/reload`: the settings are kept.
9. On an alt of the other faction, a faction-locked recipe's reagent counts only when a character of that faction holds the profession.

## Implementation notes

- Task 1: the minimap right-click pin already existed (`test_right_click_does_nothing`); the `M.Reagents` first-of-slot pin needed the Task 2 mock, so it landed there (`test_reagents_first_of_slot`). The tooltip order pin was checked by swapping the two blocks: it fails.
- `UsedIn.lua` sits after `Model.lua` in the TOC (not right after `Characters.lua`); it only uses Model at runtime.
- `MB.SetHidden` already existed; nothing was extracted from `ToggleHidden`.
- Mock: `AddLine` records colours (`tooltip.colors`); `Click` honours `RegisterForClicks` like the client; a test plays a client without `RefreshData` by setting it to `false` (unknown mock methods are no-ops, so `nil` can't express it).
- `ns.UsedInLines` returns `{}` before the index is ready, and `ns.UsedInGroups` returns `nil`. Groups with no countable recipe aren't shown.
- `/fp debug` reports addon memory (`UpdateAddOnMemoryUsage` + `GetAddOnMemoryUsage`, at the start and the end of the build only) when the client has it, else `collectgarbage("count")`, labelled "every addon, rough". It also reports the slowest hover, not just the first.
- Dropped from Task 7: the enchant nil-guard test. The "Used in" path calls no `C_Item` getter.
- Header fit at 900px (Task 10) is an estimate (8px a letter for the name, 6px for small text, "Tracked 99"): about 8px spare. In-game checklist item 7 checks it.
- Commits: spec and plan `9eece21`, Task 1 `30deb3d`, Task 2 `55dca0c`, Task 3 `deff77d`, Task 4 `1fc943f`, Task 5 `8606f63`, Task 6 `41f0f64`, Task 7 `233656b`, Task 8 `8bc9d4a`, Task 9 `6f93dcb`, Task 10 `a52d87e`, Task 11 `0129e4c`, Task 12 (this commit).

## Task 13: build cost after the first in-game check

First `/fp debug` in game: 148.3 ms over 54 frames, slowest frame 43.18 ms (target ≤ 8), 2158 recipes, 0 without reagents, 527 items, 7105 entries, addon memory 5847 → 21402 KB (+15555, target well under 1 MB), first hover 0.24 ms, slowest hover 0.54 ms. Steps 9 to 11 of the checklist passed (options, `/reload`, Horde-only 23066 Red Firework).

- [x] Pin first: `test_lists_in_learn_order` (spell order differs from learn order) passed before the change.
- [x] Failing tests: queue in learn order, flat storage per item, frame budget, slowest recipe, `/fp debug` slowest-recipe and memory-now lines, `/fp debug gc`, help.
- [x] Queue ordered by line, learn, spell ID: the end-of-build sort (the likely 43 ms frame) is gone. Listing the queue is timed as a frame.
- [x] Each frame reads one recipe at a time until `BATCH = 100` or `BUDGET_MS = 4`.
- [x] One flat `{line, spellID...}` array per item instead of a table per entry, and one reused scratch list instead of two tables per recipe.
- [x] `/fp debug` shows the slowest recipe and the memory now; `/fp debug gc` collects garbage first, so the kept memory is measurable. Most of the +15.5 MB is expected to be the client's schematic tables waiting for the collector: the addon can't avoid creating them.
- [x] Full suite: 515 tests pass.

In game: full client restart is not needed (no TOC change), `/reload` is enough. Wait about 10 s, then `/fp debug`: slowest frame ≤ 8 ms, and the slowest recipe line. Then `/fp debug gc`: memory after a full garbage collection, well under 1 MB over the build start.

## Task 14: setup frame and the index's own memory

Second check in game: 96.5 ms over 25 frames, slowest frame 10.19 ms, slowest recipe 2.77 ms (spell 1244431), 1.4 s wall; addon memory 5849 → 19407 KB right after the build, 6664 KB a little later without forcing a collection (the +13.5 MB was garbage), 7866 KB after `/fp debug gc` (+2017 KB over the build start, which counts everything the addon allocated since, not only the index); first hover 0.01 ms.

- A batch frame can't pass 4 ms + the slowest recipe (6.8 ms), so the 10.19 ms frame was the setup: the queue sort called a Lua comparator per comparison.
- [x] Failing tests: setup timed as `setupMs` and shown in `/fp debug`; `/fp debug gc` reports "Index kept" from a second copy, leaving the real index and its stats alone, with two collections.
- [x] The queue sorts one number per recipe, `learn * span + spellID` (span above the line's largest spell ID; largest in the data 1,328,948, largest learn 320, so exact in a double).
- [x] Full suite: 517 tests pass.

In game (`/reload`): `/fp debug` → slowest frame ≤ 8 ms and "Listing the recipes" ms; `/fp debug gc` → "Index kept" well under 1 MB.

Third check in game: 70.9 ms over 24 frames, slowest frame 4.04 ms, listing the recipes 3.47 ms, slowest recipe 0.42 ms, 1.2 s wall; index kept 581 KB; first hover 0.00 ms, slowest hover 0.01 ms. Every cost target passes. The verified client facts are in AGENTS.md.
