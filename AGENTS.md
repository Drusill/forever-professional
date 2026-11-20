# AGENTS.md

Instructions for coding agents working in this repo. Read this first, then `README.md`, `tools/README.md` and `tools/REPORT.md`.

## Project

**ForeverProfessional** is a World of Warcraft: Forever addon for professions: AtlasLoot for recipes, styled like the Dungeon Journal. It lets you browse every recipe of every profession, see which ones each character knows, and find exactly where to get the rest (trainer, vendor, drop, quest, with map waypoints). License: **GPL-3.0-or-later**.

## Layout

| Path | What |
|---|---|
| `ForeverProfessional/` | The addon (the folder that goes into `Interface\AddOns`) |
| `ForeverProfessional/Data/` | **Generated** baked data. Never edit by hand |
| `ForeverProfessional/*.lua`, `UI/` | Addon code: `Core` (events, DB, `/fp`), `Characters` (learned cache), `Model` (frame-free logic), `UI/Window`, `UI/RecipeList`, `UI/Detail` |
| `tests/` | Addon tests: `wow_mock.lua` (mock client API), `harness.py` (loads the real TOC and data through `lupa`), `test_*.py` |
| `tools/` | Offline data pipeline (Python, stdlib only): `python tools/build_data.py` |
| `tools/overrides.json` | Hand-verified data fixes, applied last by the pipeline |
| `tools/REPORT.md` | Generated coverage report and list of data gaps |
| `spike/` | Throwaway in-game API probe from the viability study. Reference only |
| `spike/tests/mock_harness.py` | Runs addon Lua in Lua 5.1 against a mock WoW API through `lupa` |

## Rules

- **Never modify the community addons** in `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`. They are read-only references (WhatsTraining for TOC conventions and recipe data, ForeverDungeonJournal for Journal-style frames).
- **Never hand-edit `ForeverProfessional/Data/`.** Data fixes go in `tools/overrides.json`, then rebuild. Ask before changing anything under `tools/`.
- Work on `develop`. Commit small, working steps with clear messages. Don't push unless asked.
- Run the tests after each change.

## Commands

Python 3.12 via `mise` (`mise.toml`).

```
python tools/build_data.py            # fetch pinned sources if missing, then build the data
python tools/build_data.py update     # move the pins to the newest upstream data, then build
python -m unittest discover tools/tests
python -m unittest discover tests     # addon tests; need `pip install -r requirements-dev.txt` (lupa)
```

If `python` isn't on the PATH, prefix with `mise exec --`. The addon tests read the TOC, so a new Lua file must be listed there (with the camelot suffix) before its tests can see it.

In-game testing: link the addon folder into the game once:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ForeverProfessional" "C:\Users\cabez\Projectos\forever-professional\ForeverProfessional"
```

TOC changes need a full client restart; `/reload` doesn't pick them up. Errors come back from the user via BugGrabber/BugSack.

## Client facts (verified in game, client 1.60.1 build 70959)

- Interface **16001**, retail-style API. Classic globals (`GetItemInfo`, `GetSpellInfo`, `GetTradeSkillInfo`…) are gone; use `C_Item`, `C_Spell`, `C_TradeSkillUI`. Lua 5.1.
- **TOC:** the client loads `<Addon>_Camelot.toc` ("Camelot" is Forever's internal codename). Ship `ForeverProfessional_Camelot.toc`; don't rely on `_Forever.toc`. Copy the `camelot` load-condition convention from WhatsTraining's TOC.
- `WOW_PROJECT_ID` is **18**, not 1. Detect Forever with `select(4, GetBuildInfo())` in 16000–16999.
- `C_TradeSkillUI.GetRecipeSchematic(spellID, false)` works with the profession window closed, for unlearned recipes and other professions: output item and reagents.
- **Learned status:** `C_SpellBook.IsSpellKnown(spellID)` is correct. `GetRecipeInfo().learned` is not reliable with the window closed.
- `GetProfessions()` + `GetProfessionInfo()` give the player's professions and skill without a window. `GetAllProfessionTradeSkillLines` also returns Forever child lines (2937 Alchemy, 2938 Blacksmithing…) and two "Test Profession [DNT]" entries to ignore.
- Unlearned recipes can't be shown in Blizzard's profession window, and `GetRecipeSourceText` returns nothing. That's why the catalog is baked.
- **Never call Blizzard's profession filter setters** (`SetShowUnlearned` etc.): they change the user's profession window.
- Category names are only readable in game while that profession's window is open; the baked `Categories.lua` covers them.
- Items load async: `Item:CreateFromItemID(id):ContinueOnItemLoad(cb)`. Cached items fire the callback **synchronously**; handle both. New Forever item IDs (250000+) work. Invalid IDs show up as a nil name, not an error.
- The Encounter Journal is disabled (`EncounterJournalDisabled`), but its art is available: atlases `adventureguide-*`, `loottab-*`, `UI-EJ-*`, textures under `Interface\EncounterJournal\`, plus the Professions atlases. Build our own frames with them.
- Map pins: `C_Map.CanSetUserWaypointOnMap` is true; use `C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint`.
- Merchant data is readable on `MERCHANT_SHOW` (NPC ID from `UnitGUID("npc")`, `GetMerchantItemID`, `C_MerchantFrame.GetItemInfo`): use it to harvest missing vendor data.
- Wrap event registration in `pcall` (registering an unknown event throws). Avoid opening Blizzard panels from addon code (taint risk).

## Data format

Generated by `tools/build_data.py`. Every file does `local _, ns = ...; ns.Data = ns.Data or {}`. Load everything through `Data\Data.xml`.

- `ns.Data.Professions[skillLine] = { name, file, recipes, new }`. Skill lines are the classic IDs: 129 First Aid, 164 Blacksmithing, 165 Leatherworking, 171 Alchemy, 182 Herbalism, 185 Cooking, 186 Mining, 197 Tailoring, 202 Engineering, 333 Enchanting, 356 Fishing, 393 Skinning.
- `ns.Data.Recipes[skillLine][spellID] = { learn, yellow, green, grey, cat, creates, count, teach, bound, side, src, trainer, rep, favor, vendors, drops, dropTotal, objects, objectTotal, containers, containerTotal, quests, unverified, unknown, new }`
  - `learn/yellow/green/grey`: skill where the recipe turns orange/yellow/green/grey.
  - `teach`: recipe item ID (or a list). `creates`: output item ID. `count`: number made, or `{min, max}`.
  - `src`: source types, from `"auto"` (learned with the profession), `"trainer"`, `"vendor"`, `"quest"`, `"drop"`, `"object"`, `"container"`, `"crafted"`, `"worldObject"`.
  - `trainer`: cost in copper. `rep = { factionID, standingID }`. `favor`: Merchant's Favor required.
  - `drops = { {npcID, chance%}, {npcID} }`: no chance means unknown (true for every new Forever drop so far). The 12 best are kept; `dropTotal` gives the full count.
  - `unverified`: source types claimed without a known NPC or quest. `unknown`: no source at all. `new`: added in Forever.
- `ns.Data.Categories[id] = { name (enUS), parent, line, order }`. A recipe's `cat` is a leaf; follow `parent` up to the profession root (which has no parent). Sort siblings by `order`.
- `ns.Data.NPCs[id] = { name, sub, faction ("A"/"H"/"AH"), map (uiMapID), x, y (0–100), instance (instance map ID, for dungeon bosses), areas = {areaID…} }`. Get zone names live: `C_Map.GetMapInfo(map).name`, `C_Map.GetAreaInfo(areaID)`.
- `ns.Data.Quests[id] = { name, level, minLevel, npcs, objects }`, `ns.Data.Objects[id] = { name, map, x, y }`.
- `ns.Data.Locale = { npc = {[id]=name}, obj = {…}, quest = {…} }` exists only on non-English clients; prefer it over the enUS names.
- `ns.Data.Ranks[spellID] = { line, rank, skill, level, trainer }`: profession ranks, not recipes.
- `ns.Data.Meta`: client build and source pins.

Item, spell and recipe names, icons, quality, tooltips and reagents are **not** baked: read them live so they're localized for free.

## Data sources (for context)

WhatsTraining (MIT) gives the recipe list, source types, costs and gates. ForeverDB (GPL-3.0) gives drops, vendors, quests, NPC names, positions and locales. AllTheThings' copy of the Forever client tables (MIT) gives thresholds and category IDs, and wago.tools gives category names. Wowhead is for manual verification only; scraping it is against its terms.
