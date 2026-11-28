# "Used in" reagent tooltip and options window: design

Date: 2026-11-27. Issue: #6. Status: draft, waiting for approval.

## Intent

A player looting or buying a material wants to know whether to keep it. The item tooltip says which
professions of their characters use it and how many of those recipes they already know, and Shift lists the
recipes. Reagent lines appear on many items, so the feature comes with a small options window to turn
tooltip lines off, which also takes the existing minimap setting.

## Goals, non-goals, anti-goals

- Goals: a reverse reagent index (item → recipes that use it) built live in the background after login;
  one "Used in" line per profession any of your characters holds; Shift lists names, redrawn live when
  Shift changes; an options window (our own frame) with five checkboxes; `/fp debug` printing the index cost
  so it can be checked in game.
- Non-goals: a reagent filter in the recipe list; prices; alt inventories; options beyond the five below;
  a Blizzard Settings category; localizing profession names (#12).
- Anti-goals: changes under `tools/` or `Data/` (no baked reagents); a login or first-hover hitch; a tooltip
  error that breaks someone else's tooltip; opening Blizzard panels from addon code; filling
  `Model.schematics` with every recipe's full schematic.

## Findings that shaped this

- 2,158 recipes across 12 professions (`Data/Recipes/*.lua`). Reagents aren't baked, and no pipeline
  source has them today (`tools/fpdata` has no reagent reader).
- `M.Schematic(spellID)` (`Model.lua:727`) caches the whole `GetRecipeSchematic` table per spell in
  `M.schematics`. `M.Reagents` (`Model.lua:740`) keeps only the first reagent of each slot. The calculator
  (#3), the tracked plan (#4) and `UI/Detail.lua:287` use them.
- `Model.RecipesCreating` (`Model.lua:755`) is the existing reverse index (item → recipes creating it), built
  synchronously on first use. It reads baked data only, so it's cheap. A reagent index needs one client API
  call per recipe.
- `Tooltip.lua` adds lines through `TooltipDataProcessor.AddTooltipPostCall(Item)` (fallback
  `OnTooltipSetItem`), once per tooltip (`tooltip.fpItem`), in `pcall` with `geterrorhandler`. Order today:
  blank line + recipe-owner lines (recipe items only), then blank line + tracked lines.
- Every character's `professions` and `learned` are saved in `ns.db.chars[GUID]`, with `faction` as
  `"Horde"` / `"Alliance"`. Six recipes are faction-locked (`side`, same spelling).
- Settings today are slash commands: `/fp minimap` flips `minimapHidden` (`UI/Minimap.lua`). There's no
  options window. `InitDB` fills missing top-level defaults, so new booleans need no `db.version` bump.
- The minimap button registers `LeftButtonUp` only. The compartment click handler ignores its arguments.
  The retail client calls it with `(addonName, buttonName, menuButtonFrame)`, which hasn't been checked on
  Forever yet.
- The mock: `debugprofilestop` and `GetTime` exist; `C_Timer.After` queues until `flush()`, which runs at most
  20 rounds; `GetRecipeSchematic` returns a fixed three-reagent schematic for every unlisted spell unless
  `mock.onlySchematics` is set; `C_Item.GetItemQualityByID(nil)` throws like the client. It has no
  `IsShiftKeyDown`, no tooltip `RefreshData` / `GetOwner` / `IsShown`, and no slot with several reagents.

## Decisions (made with the user)

1. **Live index, spread over frames.** After login, read the recipes in small batches, one batch per frame,
   until all 2,158 are read. Nothing changes under `tools/`, and names stay live and localized.
2. **Alts count.** One line per profession held by any saved character. "Known" means any character knows
   it.
3. **After the tracked block, in its own block.** Blank line, then the "Used in" lines, after "Tracked
   total".
4. **Shift lists names, capped, redrawn live.** Under each profession line: known names in white, unknown
   in grey, sorted by required skill, at most 10, then "and N more". Pressing or releasing Shift redraws a
   shown item tooltip. Without Shift, one dim hint line.
5. **Read raw, keep only IDs.** A new Model reader calls `GetRecipeSchematic` and keeps only the item IDs of
   every reagent of every slot (alternatives included), without filling `M.schematics`. If a spell is
   already in `M.schematics`, it's read from there instead of calling the API again. `M.Schematic` and
   `M.Reagents` stay unchanged, pinned by tests first.
6. **Count recipes a holder could learn.** A recipe counts when any character knows it, or when it has no
   `side`, or when a character holding that profession is of its `side`.
7. **An options window, our own frame,** styled like the main window, not a Blizzard Settings category.
8. **Five settings**, all on by default:

   | Checkbox | Saved variable | Default |
   |---|---|---|
   | Show the minimap button | `minimapHidden` (existing, inverted) | shown |
   | Recipe items: who knows or can learn it | `tooltipOwners` (new) | on |
   | Tracked recipes: "Needed for" lines | `tooltipTracked` (new) | on |
   | Reagents: "Used in" lines | `tooltipUsedIn` (new) | on |
   | ↳ Hold Shift to list the recipes | `tooltipUsedInNames` (new) | on |

9. **Opened from** `/fp options`, a gear button in the main window header left of the close button, and a
   right-click on the minimap button and the compartment entry.

## Design

### Reagent reading (`Model.lua`)

- `M.ReagentItems(spellID)` → list of distinct item IDs used by the recipe, every reagent of every slot,
  in slot order. It reads `M.schematics[spellID]` when cached, else calls `GetRecipeSchematic(spellID,
  false)` in `pcall` and doesn't cache the table. Returns `nil` when there's no schematic.
- `M.NewUsedInIndex(recipes)` → a frame-free builder over `ns.Data.Recipes`. It holds a queue of
  `{line, spellID}` ordered by line, then `learn`, then spell ID, so each item's list fills in that order
  and is never sorted. `index[itemID]` is one flat `{line, spellID, line, spellID...}` array (a table per
  entry cost about 1 MB). Counters: `read`, `missing` (no schematic), `items`, `entries`. Methods:
  `Step(n)` reads up to n queued recipes and returns true when it's done; `Done()`; `Lookup(itemID)`
  returns a new `{ {line, spellID}... }` list. Reading reuses one scratch list per build, not two tables
  per recipe. (Revised after the first in-game check: the end-of-build sort was a 43 ms frame and the
  memory grew by 15.5 MB.)
- `Model.Schematic` / `Model.Reagents` are not touched.

### Background build and counting (`UsedIn.lua`, new)

- 5 s after `PLAYER_LOGIN` (after the login burst and the existing 3 s character rescan), when
  `tooltipUsedIn` is on, start a
  `C_Timer.After(0, step)` chain: each frame reads recipes one at a time until `BATCH = 100` are read or
  `BUDGET_MS = 4` is spent. Listing and ordering the queue counts as a frame of its own. Turning the
  option on later starts the build. Turning it off stops the chain at the next frame and keeps the partial
  index.
- Stats for `/fp debug`: total build ms (sum of each frame's `debugprofilestop` delta), the slowest frame
  and the slowest single recipe (with its spell ID) in ms, the number of frames, wall time from start to
  done (`GetTime`), recipes read, missing schematics, distinct items, index entries, memory at the start
  and the end of the build (addon memory when the client reports it, else `collectgarbage("count")`), the
  memory now, and the first hover's cost in ms after the index is ready. The end count still holds the
  client's schematic tables waiting for the garbage collector: `/fp debug gc` runs a full collection
  first, so "now" is the memory the addon keeps.
- `ns.UsedInGroups(itemID)` → `{ {line, total, known, recipes = { {spellID, known}... }}... }`, nil until
  the index is done. It covers lines held by any character (`professions` keys), with recipes filtered by
  decision 6. A line left with no countable recipe gets no group. Groups for the logged-in character's professions come first, then the rest, each by profession
  name. Each group's recipes are sorted by `learn`, then name.
- `ns.UsedInLines(itemID, shift)` → `{ {text, r, g, b}... }`:
  - `Used in %d %s recipes (%d known)`, singular `Used in 1 %s recipe (%d known)`, in grey (0.75).
  - With Shift and `tooltipUsedInNames`: up to 10 names per group indented two spaces, known in white,
    unknown in grey (0.5), then `  and %d more` (the existing `L.NEEDED_MORE` with the indent).
  - Without Shift and with `tooltipUsedInNames`: one last line `Hold Shift to list the recipes` in grey
    (0.5).

### Tooltip (`Tooltip.lua`)

- Order: recipe-owner block (if `tooltipOwners`), tracked block (if `tooltipTracked`), "Used in" block (if
  `tooltipUsedIn` and the index is done). Each block starts with a blank line, as today.
- Shift refresh: a frame listens to `MODIFIER_STATE_CHANGED` (registered in `pcall`). On `LSHIFT` / `RSHIFT`,
  for each of `GameTooltip` and `ItemRefTooltip` that is shown with `fpItem` set, it calls
  `tooltip:RefreshData()` when present (it re-runs the post-calls), else runs the owner's `OnEnter`.
  Whichever one works is checked in game.

### Options window (`UI/Options.lua`, new)

- A movable flat panel (`UI.Panel`) of about 320×230, centred, closed by Escape (`UISpecialFrames`) and its
  close button. Title "ForeverProfessional", a "Minimap" group with one check row and an "Item tooltips"
  group with four, built with `UI.CreateCheckRow`. The Shift row is indented and disabled while "Used in" is
  off.
- Each row writes its saved variable and applies it right away. The minimap row shows or hides the button
  through the existing minimap code. The "Used in" row starts the build when needed. Tooltips pick up the
  change on their next draw.
- `UI.ToggleOptions()` is used by `/fp options`, the header gear button (`UI.CreateIconButton`, tooltip
  "Options") and right-clicks. The minimap button registers `RightButtonUp` too, and its tooltip gets
  "Right-click: options". The compartment handler opens options when its second argument is
  `"RightButton"`.

### Strings (`Locale.lua`)

`USED_IN`, `USED_IN_ONE`, `USED_IN_HINT`, `OPTIONS_TITLE`, `OPTIONS_MINIMAP`, `OPTIONS_TOOLTIPS`, one label per
checkbox, `OPTIONS_BUTTON`, `MINIMAP_RIGHT_CLICK`, the `/fp debug` lines, and `/fp options` / `/fp debug` in
`L.HELP`.

## Data and saved variables

No data format change. Four new top-level booleans in `ForeverProfessionalDB`, default true:
`tooltipOwners`, `tooltipTracked`, `tooltipUsedIn`, `tooltipUsedInNames`. A saved `false` stays false. No
`db.version` bump. AGENTS.md and README.md get the new settings, files and commands.

## Testing

- Pin first: the tooltip line order with a recipe item that is also tracked; `M.Reagents` / `M.Schematic`
  behaviour and caching (the existing `ReagentsTest` passes unmodified); the minimap left click.
- Index: slot alternatives, duplicates within a recipe, missing schematics, `M.schematics` left untouched,
  a cached schematic reused, batching (`Step(n)` reads n), sorting.
- Counting: known by an alt, a profession nobody holds, a faction-locked recipe with and without a holder of
  that side, a recipe known despite its side, group order.
- Text: singular and plural, "(0 known)", Shift list with the cap and "and N more", the hint, the names
  setting off, nothing before the index is done, nothing with `tooltipUsedIn` off.
- Shift refresh through `RefreshData` and through the owner's `OnEnter`; an unrelated modifier ignored.
- Options: defaults, saved false kept, every row writes and applies, the Shift row disabled with "Used in"
  off, Escape, the gear, right-clicks, `/fp options`, and fitting a 1024×768 screen.
- `/fp debug` before, during and after the build.
- Mock: `IsShiftKeyDown` (`mock.shift`), tooltip `RefreshData` / `GetOwner` / `IsShown` / `Show` / `Hide`,
  slots with several reagents.

## Cost to check in game

The issue requires a measured, acceptable cost. `/fp debug` prints the numbers. Acceptance:

- No frame slower than 8 ms (half a 60 fps frame), else lower `BUDGET_MS`. A single recipe slower than
  that can't be split: the slowest recipe line shows whether that's the cause.
- The index ready within a few seconds of login.
- The first hover after the index is done under 2 ms.
- Memory kept, measured with `/fp debug gc`: well under 1 MB over the build start.

If a batch is too slow even at small sizes, the fallback is decision 1's alternative (baking), which needs
separate approval for `tools/`.

## Risks and open checks (in game)

- `GameTooltip:RefreshData()` exists and re-runs post-calls on this client. If it doesn't, the owner's
  `OnEnter` fallback must redraw bag and merchant items.
- The compartment click passes `"RightButton"` as its second argument.
- `GetRecipeSchematic` returns the reagents for every recipe right after login (not only once a profession
  window was opened). `missing` in `/fp debug` shows it.
