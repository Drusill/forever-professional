# AGENTS.md

Instructions for coding agents working in this repo. Read this first, then `README.md`, `tools/README.md` and `tools/REPORT.md`.

## Project

**ForeverProfessional** is a World of Warcraft: Forever addon for professions: AtlasLoot for recipes, styled like the Dungeon Journal. It lets you browse every recipe of every profession, see which ones each character knows, and find exactly where to get the rest (trainer, vendor, drop, quest, with map waypoints). License: **GPL-3.0-or-later**.

## Layout

| Path | What |
|---|---|
| `ForeverProfessional/` | The addon (the folder that goes into `Interface\AddOns`) |
| `ForeverProfessional/Data/` | **Generated** baked data. Never edit by hand |
| `ForeverProfessional/*.lua`, `UI/` | Addon code: `Core` (events, DB, `/fp`), `Characters` (learned cache, the material plan's live context and saved craft/buy choices), `Model` (frame-free logic: recipe list, reagent reading, item → recipe index, material plans), `Tooltip` (recipe item tooltips), `UI/Widgets` (flat panel, filter toggle, popup, check row, toggle button, chips, slots, skill bar, item names and async loading, profession theme and source icons), `UI/Window` (rail, header, toolbar, filter menu, character menu, resizing), `UI/RecipeList` (two-line rows), `UI/Detail` (pinned header, sections, source cards), `UI/Calculator` (materials calculator panel over the detail pane), `UI/Minimap` (minimap button, compartment entry) |
| `tests/` | Addon tests: `wow_mock.lua` (mock client API), `harness.py` (loads the real TOC and data through `lupa`), `test_*.py` |
| `tools/` | Offline data pipeline (Python, stdlib only): `python tools/build_data.py` |
| `tools/overrides.json` | Hand-verified data fixes, applied last by the pipeline |
| `tools/REPORT.md` | Generated coverage report and list of data gaps |
| `ForeverProfessional/NOTICES.txt` | Third-party licence notices for the baked data (the MIT texts must ship) |
| `.pkgmeta`, `.github/`, `CHANGELOG.md` | Release packaging and CI: see **Releasing** |
| `docs/logo/` | CurseForge avatar (SVG source, 400px PNG) |
| `docs/ideas.md` | Ideas not built yet, and the decided ones with their GitHub issue: check it before planning a feature |

## Rules

- **Never modify the community addons** in `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`. They are read-only references (WhatsTraining for TOC conventions and recipe data, ForeverDungeonJournal for Journal-style frames).
- **Never hand-edit `ForeverProfessional/Data/`.** Data fixes go in `tools/overrides.json`, then rebuild. Ask before changing anything under `tools/`.
- Work on `develop`, or on a feature branch off it. Commit small, working steps with clear messages. Don't push unless asked.
- **Planned features are GitHub issues.** Start at the pinned roadmap issue (#8): it gives the priority order and dependencies. Ask the maintainer an issue's open questions before designing, then write its spec and plan under `docs/superpowers/`. Branch from `develop` as `feat/<issue>-<slug>` (`fix/` and `docs/` for those kinds of work) and open the pull request into `develop` with `Closes #<issue>`; the issue closes when the release merge reaches `main`.
- Run the tests after each change.
- **Follow Blizzard's [UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534).** The addon stays free and its code readable: data files stay plain Lua tables, never compressed or encoded. No ads, and no donation requests in game: a donation link may go on the download page, never in the TOC or the UI.
- Use only the in-game API. Never automate gameplay, and don't bundle Blizzard art or sound: reference client textures and atlases by name.

## Commands

Python 3.12 via `mise` (`mise.toml`).

```
python tools/build_data.py            # fetch pinned sources if missing, then build the data
python tools/build_data.py update     # move the pins to the newest upstream data, then build
python -m unittest discover tools/tests
python -m unittest discover tests     # addon tests; need `pip install -r requirements-dev.txt` (lupa)
python -m unittest discover .github/scripts    # release script tests
```

If `python` isn't on the PATH, prefix with `mise exec --`. The addon tests read the TOC, so a new Lua file must be listed there (with the camelot suffix) before its tests can see it.

## Releasing

Published on CurseForge as project **1822577** (`## X-Curse-Project-ID` in the TOC). Releases come from `main`: merging a pull request from `develop` into `main` runs `.github/workflows/release.yml`. The version is the first `## ForeverProfessional X.Y.Z` heading in `CHANGELOG.md`. If tag `vX.Y.Z` already exists, nothing is released. Otherwise the run tests, tags the merge commit and runs the [BigWigs packager](https://github.com/BigWigsMods/packager), which builds the zip by the rules in `.pkgmeta` and uploads it to CurseForge and as a GitHub release. A version like `0.2.0-beta1` or `0.2.0-alpha1` uploads a beta or alpha file instead. A version that isn't above the newest tag fails the run. The decisions live in `.github/scripts/release_version.py`; `.github/scripts/package.sh` runs the packager, and `test.yml` runs it without uploading on every pull request. Needs the repo secret `CF_API_TOKEN` (from https://authors.curseforge.com/#/settings/api-tokens).

`.github/workflows/test.yml` runs every test suite on pull requests into `main` and `develop` and on pushes to `develop`. On a pull request into `main`, its run summary says whether merging releases ("Merging releases 0.2.0" or "Merging won't release").

1. On `develop`, rewrite `CHANGELOG.md` with the new version heading and this release's notes only, for players: it becomes the CurseForge changelog, and CurseForge rejects files without one.
2. When the client's interface number changes, update `## Interface` (and the client facts below).
3. When the user asks, push `develop` and open a pull request into `main`; check its summary says "Merging releases" with the right version.
4. Merge with **Create a merge commit**, never squash or rebase: a merge commit keeps `develop`'s commits in `main`'s history, so the next pull request shows only new changes.
5. If the run fails, use **Re-run failed jobs**: the tag step accepts its own tag, and a version that already has a GitHub release uploads nothing. The packager uploads to CurseForge first: if its log shows the CurseForge upload succeeded and only the GitHub release failed, don't re-run (that would upload the version again); create the GitHub release for the tag by hand.

A merge with no version change (docs, CI) releases nothing. A ruleset on `main` enforces this: changes arrive only through a pull request that passes the `test` check, merged with a merge commit; force pushes and deleting `main` are blocked. It doesn't require the branch to be up to date, since `develop` never contains `main`'s merge commits.

The packager replaces `@project-version@` in the TOC with the tag, so a linked dev copy shows the raw token in game; that's expected. The zip holds `ForeverProfessional/` (addon files, `NOTICES.txt`, and `LICENSE` from the repo root); everything else is in `.pkgmeta`'s `ignore`. A new top-level file or folder must be added there, or it ships.

In-game testing: link the addon folder into the game once:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ForeverProfessional" "<repo>\ForeverProfessional"
```

TOC changes need a full client restart; `/reload` doesn't pick them up. Errors come back from the user via BugGrabber/BugSack.

## Client facts (verified in game, client 1.60.1 build 70959)

- Interface **16001**, retail-style API. Classic globals (`GetItemInfo`, `GetSpellInfo`, `GetTradeSkillInfo`…) are gone; use `C_Item`, `C_Spell`, `C_TradeSkillUI`. Lua 5.1.
- **TOC:** the client loads `<Addon>_Camelot.toc` ("Camelot" is Forever's internal codename). Ship `ForeverProfessional_Camelot.toc`; don't rely on `_Forever.toc`. Copy the `camelot` load-condition convention from WhatsTraining's TOC.
- **Character identity:** `GetRealmName()` and `GetNormalizedRealmName()` return `""`, and `UnitName`/`UnitFullName` give only the first name (two characters can both be "Dru"). Key characters by `UnitGUID("player")` (`Player-6934-0008D960`).
- `WOW_PROJECT_ID` is **18**, not 1. Detect Forever with `select(4, GetBuildInfo())` in 16000–16999.
- `C_TradeSkillUI.GetRecipeSchematic(spellID, false)` works with the profession window closed, for unlearned recipes and other professions: output item and reagents. Read it through `Model.Schematic` / `Model.Reagents` (cached per spell).
- `C_Item.GetItemCount(id, true)` counts the bank while away from it (checked 2026-11-23). The global `GetItemCount` is gone.
- **Learned status:** `C_SpellBook.IsSpellKnown(spellID)` is correct. `GetRecipeInfo().learned` is not reliable with the window closed.
- `GetProfessions()` + `GetProfessionInfo()` give the player's professions and skill without a window. `GetAllProfessionTradeSkillLines` also returns Forever child lines (2937 Alchemy, 2938 Blacksmithing…) and two "Test Profession [DNT]" entries to ignore.
- Unlearned recipes can't be shown in Blizzard's profession window, and `GetRecipeSourceText` returns nothing. That's why the catalog is baked.
- **Never call Blizzard's profession filter setters** (`SetShowUnlearned` etc.): they change the user's profession window.
- The minimap is the retail-style one: round, 198×198, `GetMinimapShape` is nil unless a minimap addon squares it. The **addon compartment** (`AddonCompartmentFrame`) exists and is shown, and TOC-declared `## AddonCompartmentFunc` / `FuncOnEnter` / `FuncOnLeave` entries appear in it.
- **Don't bundle LibDataBroker-1.1 or LibDBIcon-1.0** (or CallbackHandler-1.0, which they need). LibDataBroker is "All Rights Reserved" (no license upstream), and the Ace3-style BSD licence of the other two forbids stand-alone redistribution, which GPL-3.0 doesn't allow. That's why the minimap button is hand-rolled.
- Category names are only readable in game while that profession's window is open; the baked `Categories.lua` covers them.
- Items load async: `Item:CreateFromItemID(id):ContinueOnItemLoad(cb)`. Cached items fire the callback **synchronously**; handle both. New Forever item IDs (250000+) work. Invalid IDs show up as a nil name, not an error.
- The Encounter Journal is disabled (`EncounterJournalDisabled`), but its art is available: atlases `adventureguide-*`, `loottab-*`, `UI-EJ-*`, textures under `Interface\EncounterJournal\`, plus the Professions atlases. Build our own frames with them.
- **Profession art** (checked in game): every profession has its skill bar art, `Skillbar_Fill_Flipbook_<Kit>` (a flipbook: 2 columns of 34px rows) plus `Skillbar_Flare_<Kit>`, for Kit in Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, FirstAid, Fishing, Herbalism, Leatherworking, Mining, Skinning, Tailoring (and `DefaultBlue`, fill only), with `Professions-skillbar-bg/frame/mask`. The Professions book is `ProfessionsFrame` (not `ProfessionsBookFrame`); its cards are `Profession-overview-Card-<Kit>` (664×141, the nine primary professions) and `Profession-overview-card-generic-<Kit>` (225×274, Cooking, Fishing, First Aid).
- `SetResizeBounds`, `CreateColor` and `Texture:SetGradient` exist. Atlases `VignetteLoot` and `VignetteKill` exist (the latter is too faint at 14px).
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

Saved variables (`ForeverProfessionalDB`, account-wide): `chars` (per character), `filter`, `filters`, `collapsed`, `window`, the minimap settings, and `craftModes = { [itemID] = "craft" | "buy" }`, the materials calculator's switches.

## Data sources (for context)

WhatsTraining (MIT) gives the recipe list, source types, costs and gates. ForeverDB (GPL-3.0) gives drops, vendors, quests, NPC names, positions and locales. AllTheThings' copy of the Forever client tables (MIT) gives thresholds and category IDs, and wago.tools gives category names. Wowhead is for manual verification only; scraping it is against its terms.
