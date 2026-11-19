# ForeverProfessional Spike

A throwaway addon that probes the WoW Forever (1.60.1, Interface 16001) API. It answers the open questions in the viability study before we commit to an architecture. It changes nothing in your game except one optional map pin. It only reads data and restores any profession filter it toggles.

## Install

The addon folder must sit inside your Forever AddOns folder. Pick one option.

**Option A: link it (recommended, edits stay live).** Open *Command Prompt as Administrator* and run:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ForeverProfessional_Spike" "C:\Users\cabez\Projectos\forever-professional\spike\ForeverProfessional_Spike"
```

**Option B: copy it.** Copy `spike\ForeverProfessional_Spike` into `_forever_\Interface\AddOns\`.

Then enable **ForeverProfessional Spike** in the AddOns list at character select.

## Run (about 10 minutes)

| # | Do this | What it tests |
|---|---|---|
| 1 | Log in, keep profession windows **closed**, type `/fpspike all` | Environment, recipe APIs with the window closed, async item loading, Journal/Professions art, QuestieDB lookups, map |
| 2 | Open **each profession window** you have (Cooking and First Aid count) | Runs automatically: recipe list, categories, and **whether unlearned recipes can be shown** |
| 3 | Close the window, type `/fpspike recipes` | Recipe APIs again, now also on recipes you know |
| 4 | Talk to any **vendor that sells recipes** (an Azeroth Commerce Authority vendor is ideal) | Runs automatically: can we read vendor stock, NPC ID and location? |
| 5 | *(optional)* `/fpspike map set` | Drops a map pin on your position (clear it from the map) |
| 6 | *(optional, do last)* `/fpspike open 2329` | Can an addon jump the profession window to a recipe? Might cause UI errors; `/reload` afterwards |
| 7 | `/reload`, then `/fpspike env` | Confirms SavedVariables survive (load counter > 1) |
| 8 | `/fpspike report`, then **Ctrl+A, Ctrl+C**, and paste it to Claude | — |

The results are also saved to:
`_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverProfessional_Spike.lua`

Other commands: `/fpspike help`, `/fpspike <test>` (`env`, `recipes`, `items`, `textures`, `questie`, `map`, `window`, `open`), `/fpspike reset`.

## Reading the report

Each line is tagged:
- `PASS`: the call worked and returned useful data
- `FAIL`: it errored, was missing, or returned nothing
- `WARN`: it worked partially or the result is ambiguous
- `INFO`: context only

The lines that matter most:
- **7. Profession window → `after SetShowUnlearned(true)`**: if this shows unlearned recipes, the game can supply the full catalog for professions you have.
- **2. TALLY (CLOSED)**: which recipe calls work without the window open, and for professions you don't have.
- **3. Item data**: whether new Forever item IDs (250000+) load.

## Development harness

`tests/mock_harness.py` runs the addon in Lua 5.1 against a minimal mock of the API, to catch syntax and flow errors without the game:

```
pip install lupa
python tests/mock_harness.py ForeverProfessional_Spike
```

The mock only checks that the code runs. Real API behaviour comes from step 8 above.
