# Data pipeline

Builds the addon's baked data in `ForeverProfessional/Data/` from pinned upstream sources. These are the facts the game client won't tell an addon: the full recipe list, skill thresholds, categories, and where each recipe comes from. Names, icons, reagents and learned status are read live in game.

Needs Python 3.9+ and `git` (standard library only, nothing to `pip install`).

## Run

From the repo root:

```
python tools/build_data.py            # download what's missing, then build
python tools/build_data.py update     # move the pins to the newest upstream data, then build
python tools/build_data.py build      # build from tools/.cache only, no network
python -m unittest discover tools/tests
```

Each build writes:
- `ForeverProfessional/Data/*.lua`: the data files (include `Data/Data.xml` from the addon TOC)
- `tools/REPORT.md`: coverage numbers and the list of gaps to fix

`update` also rewrites `tools/sources.lock.json`. Commit the lock, the data and the report together.

Use `--whatstraining "<AddOns>\WhatsTraining\Crafting\Recipes\Camelot"` to build from your installed copy of WhatsTraining instead of the pinned commit.

## Sources

| Source | What we take | Licence | Pin |
|---|---|---|---|
| [WhatsTraining](https://github.com/fusionpit/WhatsTraining) `Crafting/Recipes/Camelot` | Recipe list, learn skill, source types, trainer cost, vendor NPCs, quests, reputation and Merchant's Favor gates, bound flag, faction side | MIT | commit |
| [ForeverDB](https://github.com/foreverfraddons/forever-db) `forever.json.gz` | Drop NPCs and rates, object and container drops, vendors, quest rewards, recipe item ↔ spell, NPC / object / quest names, factions, map positions, localized names | GPL-3.0 | `meta.hash` (only the rolling `latest` release carries the file) |
| [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) `.contrib/.db/forever/.config/.wago/SkillLineAbility` | Skill thresholds (yellow / grey), category ID, auto-learned flag | MIT; Blizzard game data | commit + client build |
| [wago.tools](https://wago.tools) `TradeSkillCategory` | Category names and tree | Blizzard game data | client build. Optional: if it can't be fetched, the build keeps category IDs and the addon caches names in game |

ForeverDB is GPL-3.0, so the addon is GPL-3.0 (see `LICENSE`).

## Merge rules

- **Recipe list:** WhatsTraining. Profession rank spells (Journeyman, Expert…) go to `Ranks.lua`, not the recipe list.
- **Thresholds:** orange = WhatsTraining's learn skill; yellow = `TrivialSkillLineRankLow`; grey = `TrivialSkillLineRankHigh`; green = their midpoint.
- **Recipe item:** WhatsTraining's `teach`, plus any recipe item ForeverDB's ItemEffect says teaches the spell.
- **Vendors:** union of WhatsTraining and ForeverDB. An NPC that sells the item is never also listed as a drop (ForeverDB sometimes lists vendors as 0% drops).
- **Drops, objects, containers:** ForeverDB. The 12 best rates are kept, plus a total. Rate `nil` means unknown; that's every new Forever drop so far.
- **Quests:** union of WhatsTraining and ForeverDB, with quest givers from ForeverDB.
- **Source types (`src`):** `auto` (learned with the profession: AcquireMethod 1), `trainer`, `vendor`, `quest`, `drop`, `object`, `container`, `crafted`, `worldObject`.
- **`unverified`:** WhatsTraining claims a source type but no NPC or quest is known. The type is kept so the UI can say "Vendor (unknown)".
- **`unknown`:** no source at all.
- **Positions:** the uiMap with the most spawn points, first point, in 0–100 coordinates. Dungeon bosses with no map point get `instance` (the instance map ID) instead.
- **Overrides:** `tools/overrides.json` is applied last and wins (see its `_readme`). Put hand-verified fixes there, with `_evidence`.

## Data format

See the docstring at the top of `fpdata/emit_lua.py`. A recipe line looks like this:

```lua
[1255143] = { learn = 35, yellow = 40, green = 40, grey = 40, cat = 2560, creates = 252427, teach = 252764,
  bound = false, src = { "trainer", "vendor" }, trainer = 500, vendors = { 258306 }, new = true },
```

and its vendor in `NPCs.lua`:

```lua
[258306] = { name = "Granny Finespindle", sub = "Leatherworking Recipes", faction = "A", map = 1455, x = 39.2, y = 33.6, areas = { 1537 } },
```

## Layout

```
tools/
  build_data.py        CLI
  sources.lock.json    pins
  overrides.json       hand fixes
  REPORT.md            generated
  fpdata/              fetch, parsers (Lua tables, CSV, ForeverDB), merge, Lua emitter, report
  tests/               unit tests (python -m unittest discover tools/tests)
  .cache/              downloads (git-ignored)
```
