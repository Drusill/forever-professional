# Alt Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show other characters' professions in the window, list who knows or can learn a recipe in the detail pane and on recipe item tooltips, and let stale characters be forgotten.

**Architecture:** `Characters.lua` owns the character cache (now keyed by GUID) and all frame-free queries (`ListChars`, `CharName`, `RecipeOwners`, `OwnerLines`, `ForgetChar`). The UI passes `UI.state.char` (nil = logged-in character) to every `IsLearned`/`CharSkill` call. A new `Tooltip.lua` hooks item tooltips through `TooltipDataProcessor` and reuses `OwnerLines`.

**Tech Stack:** Lua 5.1 (WoW Forever client, interface 16001), Python 3.12 `unittest` + `lupa` tests against `tests/wow_mock.lua`.

**Spec:** `docs/superpowers/specs/2026-11-20-alt-support-design.md`

## Global Constraints

- Work on `develop`, one commit per task, don't push. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Run `mise exec -- python -m unittest discover tests` after every change; the whole suite must stay green.
- New Lua files go in the TOC with ` [AllowLoadGameType camelot][ExcludeLoadGameType classic]`.
- Never edit `ForeverProfessional/Data/`, `tools/`, or the community addons. Never call Blizzard profession filter setters.
- Every user-visible string goes through `Locale.lua` (`L.*`).
- Every file starts with the GPL header line and `local _, ns = ...`.
- Item/spell names stay live (not baked).

## Plan-level decision (deviation from the spec)

The spec says `ns.CharKey()` falls back to the old `realm-name` key when `UnitGUID` is nil. That fallback would
create a `-Tester` record before login that later shows up as a duplicate alt. **`ns.CharKey()` returns nil when
there is no GUID, and `ns.GetChar()` then returns nil** (callers already handle nil). Raised with the user at handoff.

## Shared test fixture

Task 1 adds `ALTS` to `tests/harness.py`, used by Tasks 2–7. The logged-in mock character is
`Player-1-0000000A` "Tester", MAGE, Horde, level 60, Alchemy 120/150, Herbalism 90/150.

```python
ALTS = """
ForeverProfessionalDB = { version = 2, chars = {
  ["Player-1-0000000B"] = { guid = "Player-1-0000000B", name = "Dru", class = "ROGUE", faction = "Horde", level = 40,
    updated = 1795000000, professions = { [171] = { skill = 290, max = 300 } }, learned = { [7255] = true } },
  ["Player-1-0000000C"] = { guid = "Player-1-0000000C", name = "Dru", class = "DRUID", faction = "Horde", level = 30,
    updated = 1795000000, professions = { [171] = { skill = 150, max = 225 }, [185] = { skill = 50, max = 75 } }, learned = {} },
  ["Player-1-0000000D"] = { guid = "Player-1-0000000D", name = "Paly", class = "PALADIN", faction = "Alliance", level = 50,
    updated = 1795000000, professions = { [171] = { skill = 285, max = 300 }, [185] = { skill = 30, max = 75 } }, learned = {} },
  ["Player-1-0000000E"] = { guid = "Player-1-0000000E", name = "Banco", class = "SHAMAN", faction = "Horde", level = 10,
    updated = 1795000000, professions = {}, learned = {} },
} }
"""
```

Real recipes used (from the baked data):

| Recipe | Line | learn | teach | Vendors | Why |
|---|---|---|---|---|---|
| 1251753 | 171 | 280 | 250999 | Horde only | vendor hint for Paly; low for Tester and Dru (Druid) |
| 7255 | 171 | 100 | 6053 | A, AH, H | known by Dru (Rogue); no hint |
| 2795 | 185 | 25 | 2889 | Alliance, `side = "Alliance"` | Horde characters excluded |
| 9513 | 185 | — | {18160, 7678} | — | list `teach` |
| 23066 | 202 | 150 | 18647 | Horde | nobody has Engineering |

`ListChars` order for this fixture: Tester, Banco, Dru (0B), Dru (0C), Paly.

## Review Focus

- **UI or tooltip used before `PLAYER_LOGIN` (no GUID yet):** no error, and no stray record is created. Test: Task 1 `test_no_guid_no_record`.
- **Forgetting the character currently shown in the window:** the view falls back to the logged-in character without errors. Test: Task 4 `test_forget_viewed_alt_resets_view`.
- **Record with missing fields** (no class, faction or professions): label falls back to the plain name in white, and queries skip it. Test: Task 2 `test_label_for_incomplete_record`.
- **Same name and same class twice:** the two must still be told apart. Test: Task 2 `test_same_name_same_class_numbered`.
- **Same recipe item hovered again after the tooltip is cleared:** the lines appear again, exactly once each time. Test: Task 7 `test_lines_again_after_clear`.

Strip colour codes in assertions with `re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", s)` (define `plain(s)` in `harness.py` in Task 1).

---

### Task 1: GUID key, migration, mock additions

**Files:**
- Modify: `ForeverProfessional/Characters.lua` (`CharKey`, `GetChar`, `UpdateCharInfo`)
- Modify: `ForeverProfessional/Core.lua` (`DEFAULTS.version`, `InitDB`)
- Modify: `tests/wow_mock.lua`, `tests/harness.py`, `tests/test_addon.py` (`CharacterCacheTest`)
- Modify: `AGENTS.md` (client facts: realm and name)
- Test: `tests/test_chars.py` (new)

**Interfaces:**
- Produces: `ns.CharKey() -> string|nil` (the GUID); record fields `guid, name, realm, class, faction, level, updated, professions, learned`; `db.version == 2`; harness `ALTS`, `plain(s)`.
- Mock produces: `mock.guid = "Player-1-0000000A"` (settable to nil), `UnitGUID("player")`, `UnitFullName("player") -> "Tester", ""`, `UnitLevel("player") -> mock.level or 60`, `RAID_CLASS_COLORS[class].colorStr` for the 9 classic classes, `LOCALIZED_CLASS_NAMES_MALE[class]`.

- [ ] **Step 1: Write the failing tests**

`tests/test_chars.py` `KeyTest`:
- `test_key_is_guid`: after `login()`, `ns.CharKey() == "Player-1-0000000A"`, `chars["Player-1-0000000A"].guid == "Player-1-0000000A"`, `.name == "Tester"`, `.level == 60`.
- `test_same_name_kept_apart`: login with `ALTS`, then set `mock.guid = "Player-1-0000000F"` and fire `PLAYER_LOGIN` again: both `…A` and `…F` exist, both named "Tester".
- `test_migration_drops_name_keys`: setup `ForeverProfessionalDB = { version = 1, chars = { ["-Dru"] = {…}, ["Realm-Tester"] = {…}, ["CAMWOW US2 Realm 8 PvP-Salvador"] = {…} } }`; after login only `Player-1-0000000A` remains and `db.version == 2`.
- `test_migration_runs_once`: `ALTS` (version 2) keeps all four alts after login.
- `test_no_guid_no_record`: setup `mock.guid = nil`; fire `ADDON_LOADED` only; `ns.CharKey()` is nil, `ns.IsLearned(2329)` is false, `ns.CharSkill(171)` is nil, `chars` stays empty.

Update `CharacterCacheTest`: `char()` reads `chars["Player-1-0000000A"]`; `test_other_characters_kept` seeds `version = 2` and key `Player-1-0000000B`.

- [ ] **Step 2: Run them, expect failures** (`KeyError`/nil key): `mise exec -- python -m unittest tests.test_chars tests.test_addon -v`

- [ ] **Step 3: Implement**
- `ns.CharKey()` returns `UnitGUID and UnitGUID("player")` or nil. `GetChar(key)` returns nil when both `key` and `CharKey()` are nil.
- `UpdateCharInfo` also sets `c.guid = key`, `c.level = UnitLevel("player")`.
- `DEFAULTS.version = 2`. In `InitDB`, when `(db.version or 1) < 2`, delete every `chars` key not matching `^Player%-`, then set `db.version = 2`. A fresh DB starts at 2.
- AGENTS.md client facts: one bullet saying `GetRealmName`/`GetNormalizedRealmName` return `""`, `UnitName`/`UnitFullName` give the first name only (two characters can share it), and characters are keyed by `UnitGUID("player")`.

- [ ] **Step 4: Run the full suite, expect PASS**: `mise exec -- python -m unittest discover tests`

- [ ] **Step 5: Commit**: `git commit -m "Characters: key by GUID, drop old realm-name entries"`

---

### Task 2: Character list, names and recipe owners

**Files:**
- Modify: `ForeverProfessional/Characters.lua`, `ForeverProfessional/Locale.lua`
- Test: `tests/test_chars.py`

**Interfaces:**
- Consumes: Task 1 key and record.
- Produces:
  - `ns.ListChars() -> { {key=string, char=record}, … }`: logged-in character first, then by `name`, then by `key`.
  - `ns.CharName(key) -> string`: plain name; `"Dru (Rogue)"` when another cached character has the same name (class from `LOCALIZED_CLASS_NAMES_MALE`); `"Dru (Rogue) 2"` for the second one in `ListChars` order when name and class both repeat; `"?"` if the record has no name.
  - `ns.CharLabel(key) -> string`: `CharName` wrapped in `|c<colorStr>…|r`, plain white `|cffffffff` when the class is unknown.
  - `ns.RecipeOwners(line, spellID) -> { known = {key…}, learnable = { {key=, hint=string|nil}… }, low = { {key=, skill=number}… } }`, each list in `ListChars` order, following the spec's rules (known regardless of profession; otherwise needs `professions[line]`; skip on `rec.side ~= char.faction`; `skill >= (rec.learn or 0)` learnable else low; hint when every vendor's NPC faction is the other side's letter).
  - `L.VENDORS_ONLY = "(%s vendors only)"` (formatted with `L.HORDE`/`L.ALLIANCE`).

- [ ] **Step 1: Write the failing tests** (`OwnersTest`, logged in with `ALTS`; `names(keys)` maps keys through `CharName`)
- `test_list_order`: `[CharName(e.key) for e in ListChars()] == ["Tester", "Banco", "Dru (Rogue)", "Dru (Druid)", "Paly"]`.
- `test_label_class_colour`: `CharLabel("Player-1-0000000B")` starts with `"|c" + RAID_CLASS_COLORS.ROGUE.colorStr` and `plain()` gives `"Dru (Rogue)"`.
- `test_label_for_incomplete_record`: a record `{ name = "Old" }` (no class/faction/professions/learned) → `plain(CharLabel) == "Old"`, label starts with `|cffffffff`; `RecipeOwners(171, 7255)` doesn't error and doesn't list it.
- `test_same_name_same_class_numbered`: add a second ROGUE "Dru" `Player-1-0000000G` → names `"Dru (Rogue)"` (…0B) and `"Dru (Rogue) 2"` (…0G).
- `test_owners_vendor_hint`: `RecipeOwners(171, 1251753)`: known `[]`; learnable `[(…0B, nil), (…0D, "(Horde vendors only)")]`; low `[(…0A, 120), (…0C, 150)]`.
- `test_owners_known`: `RecipeOwners(171, 7255)`: known `[…0B]`; learnable keys `[…0A, …0C, …0D]`, all hints nil; low `[]`.
- `test_owners_side_locked`: `RecipeOwners(185, 2795)`: learnable keys `[…0D]`; Dru (Druid) appears nowhere.
- `test_owners_nobody`: `RecipeOwners(202, 23066)`: all three lists empty.

- [ ] **Step 2: Run, expect failures** (nil function): `mise exec -- python -m unittest tests.test_chars -v`
- [ ] **Step 3: Implement** the functions above in `Characters.lua` and the string in `Locale.lua`.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "Characters: list, names and who knows or can learn a recipe"`

---

### Task 3: `/fp chars` and `/fp forget`

**Files:**
- Modify: `ForeverProfessional/Characters.lua` (`ForgetChar`), `ForeverProfessional/Core.lua` (slash), `ForeverProfessional/Locale.lua`, `README.md` (usage)
- Test: `tests/test_chars.py`

**Interfaces:**
- Consumes: `ListChars`, `CharLabel` (Task 2).
- Produces: `ns.ForgetChar(arg) -> status, detail` with status `"removed"` (detail = removed record), `"self"`, `"none"`, or `"ambiguous"` (detail = list of `{index=number, key=string}`). `arg` is an index into `ListChars()` or a name compared case-insensitively against `char.name`. After a removal, `ns.UI.Refresh()` is called if the UI exists.
- Strings: `L.CHARS_LINE = "%d. %s - %s, level %d - %s - updated %s"` (number, label, faction, level, professions or `L.NO_PROFESSIONS`, `date("%Y-%m-%d", updated)`), `L.NO_PROFESSIONS = "no professions"`, `L.FORGOTTEN = "Forgot %s."`, `L.FORGET_SELF = "You can't forget the character you're logged in on."`, `L.FORGET_NONE = "No character \"%s\". Type /fp chars for the list."`, `L.FORGET_AMBIGUOUS = "Several characters match \"%s\"; use the number:"`, `L.FORGET_USAGE`; `L.HELP` gains `/fp chars` and `/fp forget <number|name>` after the minimap part. Professions in a chars line: `Alchemy 290, Cooking 50` (baked `ns.Data.Professions[line].name`, sorted by name).

- [ ] **Step 1: Write the failing tests** (`SlashTest`, `ALTS`; `out()` = `[plain(p) for p in a.printed()]`)
- `test_chars_lists_everyone`: `/fp chars` prints 5 numbered lines; line 3 contains `"3. Dru (Rogue) - Horde, level 40 - Alchemy 290 - updated "`; line 2 contains `"no professions"`.
- `test_forget_by_number`: `/fp forget 5` → Paly gone from `chars`, output contains `"Forgot Paly."`.
- `test_forget_by_name_case_insensitive`: `/fp forget banco` → `…0E` removed.
- `test_forget_ambiguous`: `/fp forget dru` → nothing removed; output lists `"3. Dru (Rogue)"` and `"4. Dru (Druid)"`.
- `test_forget_self_refused`: `/fp forget 1` and `/fp forget tester` → `…0A` still there, refusal printed.
- `test_forget_unknown`: `/fp forget 99` and `/fp forget zed` → `FORGET_NONE` printed.
- `test_forget_without_argument`: `/fp forget` → usage printed.

- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement** `ForgetChar`, then the `chars` / `forget` branches in the slash handler next to `minimap` (command word matched case-insensitively, argument trimmed). README: add both commands to the usage section.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "/fp chars lists cached characters, /fp forget removes one"`

---

### Task 4: Viewed character threaded through the UI

**Files:**
- Modify: `ForeverProfessional/UI/Window.lua` (`UI.state`, `UI.SetChar`, `RefreshTabs`, `RefreshCounter`, `Refresh`), `ForeverProfessional/UI/RecipeList.lua` (`RefreshList`, `RenderRow`, `RenderList`), `ForeverProfessional/UI/Detail.lua` (`RefreshDetail`)
- Test: `tests/test_ui.py` (new class `AltViewTest`)

**Interfaces:**
- Consumes: `ns.GetChar`, `ns.IsLearned(id, key)`, `ns.CharSkill(line, key)`.
- Produces: `UI.state.char` (nil = logged-in character); `UI.SetChar(key|nil)`: stores nil when `key` is nil, equals `ns.CharKey()`, or isn't in the cache; keeps line and selection; calls `UI.Refresh()`. `UI.Refresh()` resets `state.char` to nil when that record no longer exists.

- [ ] **Step 1: Write the failing tests** (`ALTS` + `mock.learned = { [2329]=true, [3170]=true, [7183]=true }`, window open)
- `test_alt_tabs_and_counter`: `SetChar("Player-1-0000000B")` → Alchemy tab `"Skill 290 / 300"`, Herbalism tab `"Not learned"`, counter `"1 / {total} learned"`.
- `test_alt_learned_filter_and_checks`: with the alt, `SetFilter("learned")` → `recipe_ids() == [7255]` and its row shows `ReadyCheck-Ready`.
- `test_alt_detail_status`: alt selected, `SelectRecipe(7255)` → `detail.status.text` contains `"Learned"`; back to `SetChar(nil)` → contains `"Not learned"`.
- `test_set_char_self_or_unknown_is_nil`: `SetChar("Player-1-0000000A")` and `SetChar("Player-9-X")` leave `state.char` nil.
- `test_live_refresh_keeps_alt_view`: alt shown; fire `NEW_RECIPE_LEARNED 1251753` → counter still `"1 / …"`, Tester's record has 1251753; `SetChar(nil)` → counter `"4 / …"`.
- `test_forget_viewed_alt_resets_view`: `SetChar("…0B")`, `/fp forget 3` → `state.char` nil and Alchemy tab `"Skill 120 / 150"`.

- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement**: pass `UI.state.char` as the key argument at every `IsLearned`/`CharSkill` call site in the three UI files (the list's `isLearned` callback included); add `UI.SetChar`.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "Window: show any cached character's recipes and skills"`

---

### Task 5: Character selector

**Files:**
- Modify: `ForeverProfessional/UI/Window.lua` (selector button, popup, tab offset, `OnHide`), `ForeverProfessional/Locale.lua`
- Test: `tests/test_ui.py` (new class `SelectorTest`)

**Interfaces:**
- Consumes: `ListChars`, `CharLabel`, `UI.SetChar`.
- Produces:
  - `UI.charButton`: a Button at the top of `f.tabPanel`, 28px high, full tab width, with `.faction` (texture), `.label` (FontString = `CharLabel` of the viewed character), and an arrow. Click toggles `UI.charMenu`.
  - `UI.charMenu`: a popup panel (`UI.Panel`) anchored under the button, strata above the window, with `.rows[i]` (Buttons) rebuilt from `ListChars()` on every open. Each row has `.key`, `.faction`, `.label` (`CharLabel`, plus `" " .. L.YOU` for the logged-in character) and `.class` (localized class).
  - Faction textures: `Interface\TargetingFrame\UI-PVP-Horde` / `-Alliance`, tex coords `0, 0.6, 0, 0.6`; no texture (hidden) for an unknown faction.
  - Tabs anchor at `TOPLEFT, 6, -40 - (index - 1) * 40`.
  - `L.YOU = "(you)"`.

- [ ] **Step 1: Write the failing tests** (`ALTS`, window open)
- `test_button_shows_viewed_character`: `plain(UI.charButton.label.text) == "Tester"`, faction texture ends with `UI-PVP-Horde`; after `SetChar("…0D")` label `"Paly"` and texture ends with `UI-PVP-Alliance`.
- `test_menu_lists_characters`: click the button → `charMenu.shown`; shown rows' plain labels `["Tester (you)", "Banco", "Dru (Rogue)", "Dru (Druid)", "Paly"]`; Paly row `.class.text == "Paladin"`.
- `test_pick_row_switches_and_closes`: click the "Dru (Rogue)" row → `state.char == "Player-1-0000000B"`, menu hidden, Alchemy tab `"Skill 290 / 300"`; open again and click "Tester (you)" → `state.char` nil.
- `test_button_toggles_menu`: two clicks → hidden again.
- `test_menu_hides_with_window`: open menu, `/fp` (hide window) → menu not shown.
- `test_tabs_below_selector`: first tab `GetPoint` y offset is `-40`; last (12th) tab's y offset minus 38 stays above `-(UI.HEIGHT - UI.TITLE_H - UI.PAD)`.

- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement** the button and popup with the Window's existing helpers (`UI.Panel`, highlight texture as the tabs); close the popup in the frame's `OnHide`; refresh the button label in `UI.Refresh`.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "Window: character selector above the profession tabs"`

---

### Task 6: Characters section in the detail pane

**Files:**
- Modify: `ForeverProfessional/Characters.lua` (`OwnerLines`), `ForeverProfessional/UI/Detail.lua` (`UI.DetailLines`), `ForeverProfessional/Locale.lua`
- Test: `tests/test_detail.py` (new class `OwnersDetailTest`), `tests/test_chars.py`

**Interfaces:**
- Consumes: `RecipeOwners`, `CharLabel`.
- Produces: `ns.OwnerLines(line, spellID) -> {string…}`: up to three lines in the order known, learnable, low, omitting empty groups; names joined with `", "`. Learnable entries are `label` or `label .. " " .. hint`; low entries are `label .. " " .. skill .. " / " .. rec.learn`. Returns `{}` when all three groups are empty. Prefix colours are the builder's call.
- Strings: `L.CHARACTERS = "Characters"`, `L.KNOWN_BY = "Known by: %s"`, `L.LEARNABLE_BY = "Learnable by: %s"`, `L.SKILL_TOO_LOW = "Skill too low: %s"`, `L.NO_CHARACTER = "No character has this profession"`.
- `UI.DetailLines` adds `{kind="section", text=L.CHARACTERS}` after the recipe item section and before Sources, then one `{kind="text", indent=1}` per `OwnerLines` entry, or a single `L.NO_CHARACTER` line.

- [ ] **Step 1: Write the failing tests**
- `test_chars.py` `test_owner_lines`: `[plain(s) for s in OwnerLines(171, 1251753)] == ["Learnable by: Dru (Rogue), Paly (Horde vendors only)", "Skill too low: Tester 120 / 280, Dru (Druid) 150 / 280"]`; `OwnerLines(171, 7255)[0]` plain `"Known by: Dru (Rogue)"`; `OwnerLines(202, 23066) == []`.
- `test_detail.py` `test_characters_section_order`: select 1251753 (line 171) with `ALTS`; in `UI.detail.rendered`, the `Characters` section index is after `Recipe item` and before `Sources`, and the two plain texts above follow it.
- `test_no_character_line`: select 23066 (line 202) → the line after `Characters` is `"No character has this profession"`.

- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement** `OwnerLines` and the section.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "Detail pane: which characters know or can learn the recipe"`

---

### Task 7: Recipe item tooltips

**Files:**
- Create: `ForeverProfessional/Tooltip.lua` (TOC entry after `Model.lua`, before `UI\Window.lua`)
- Modify: `ForeverProfessional/ForeverProfessional_Camelot.toc`, `tests/wow_mock.lua`, `README.md` (features)
- Test: `tests/test_tooltip.py` (new)

**Interfaces:**
- Consumes: `ns.OwnerLines` (Task 6).
- Produces: `ns.RecipeForItem(itemID) -> { {line, spellID}… } | nil` (index from every `teach`, number or list, built on first call); `ns.AddRecipeLines(tooltip, itemID)` (adds the lines, used by both hook paths).
- Mock additions: `Enum.TooltipDataType = { Item = 0, Spell = 1 }`; `TooltipDataProcessor.AddTooltipPostCall(type, fn)` storing into `mock.postCalls[type]`; `ItemRefTooltip` built like `GameTooltip`; on both tooltips `SetItemByID(id)` clears `lines`, runs the `OnTooltipCleared` script, sets `item`, then calls every `mock.postCalls[0]` with `(self, { type = 0, id = id })`; `GetItem()` returns `"Item " .. id, "item:" .. id`; `SetOwner` also runs `OnTooltipCleared`.

Behaviour (spec): register through `TooltipDataProcessor` inside `pcall`, else `HookScript("OnTooltipSetItem")` on `GameTooltip` and `ItemRefTooltip`; act only on those two tooltips; item ID from `data.id`, else parsed from `tooltip:GetItem()`'s link; dedupe with `tooltip.fpItem`, cleared by a `HookScript("OnTooltipCleared")`; whole handler in `pcall`; `tooltip:Show()` after adding. One block per `{line, spellID}`. Nothing added when `OwnerLines` is empty.

- [ ] **Step 1: Write the failing tests** (`ALTS`, logged in; `lines(tt)` = `[plain(l) for l in lua_list(tt.lines)]`)
- `test_registered_once`: `len(mock.postCalls[0]) == 1` (the mock starts empty).
- `test_vendor_recipe_item`: `GameTooltip:SetItemByID(250999)` → lines contain `"Learnable by: Dru (Rogue), Paly (Horde vendors only)"` and `"Skill too low: Tester 120 / 280, Dru (Druid) 150 / 280"`.
- `test_known_by`: `SetItemByID(6053)` → contains `"Known by: Dru (Rogue)"`.
- `test_list_teach_index`: `RecipeForItem(7678)` and `RecipeForItem(18160)` both `== [(185, 9513)]`; `RecipeForItem(2447)` is nil.
- `test_not_a_recipe_item`: `SetItemByID(2447)` → no lines.
- `test_nobody_has_profession`: `SetItemByID(18647)` → no lines.
- `test_once_per_item`: call the registered post call again with the same tooltip and data → line count unchanged.
- `test_lines_again_after_clear`: `SetItemByID(250999)` twice → the "Learnable by" line appears exactly once after each.
- `test_item_ref_tooltip`: `ItemRefTooltip:SetItemByID(6053)` → contains the Known-by line.
- `test_other_tooltip_ignored`: call the post call with a fresh widget `{ lines = {} }` → nothing added.
- `test_errors_swallowed`: replace `ns.OwnerLines` with a function that errors; `SetItemByID(250999)` raises nothing.
- `test_fallback_hook`: setup `TooltipDataProcessor = nil` → `GameTooltip.scripts.OnTooltipSetItem` exists; set `GameTooltip.item = 6053` and run it → contains the Known-by line.

- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement** `Tooltip.lua`, the TOC line and the mock additions. README: mention the alt features (selector, Characters section, tooltips).
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "Tooltips: who knows or can learn a recipe item"`

---

## After Task 7

Run the full suite once more, then hand the user the spec's in-game checklist (full client restart, since the TOC changed).
