# Alt support: design

Date: 2026-11-20. Status: awaiting approval.

## Intent

ForeverProfessional caches every character's professions and learned recipes, but only ever shows the
logged-in one. Alt support makes that cache useful in three places:

1. **Window:** look at an alt's professions as if logged in on it (✓/✗, tab skills, counts, colours).
2. **Detail pane:** for one recipe, see which characters know it and which could learn it now.
3. **Recipe item tooltips:** at a vendor or the Auction House, tell which alt needs a Plans/Pattern/Formula.

Plus a way to drop stale characters from the cache.

## Goals, non-goals, anti-goals

- Goals: the four features above, covered by tests, plus a fix for the character key.
- Non-goals: remembering the selected character between sessions; editing an alt's data by hand;
  cross-account data; reading an alt's data without logging into it (the cache is all we have).
- Anti-goals: anything that touches Blizzard's profession window or filters; tooltip code that can throw
  into other addons' tooltips; showing the same character twice.

## Findings that shaped this

- **The current key is broken.** `ns.CharKey()` is `GetRealmName() .. "-" .. UnitName("player")`. On Forever
  `GetRealmName()` and `GetNormalizedRealmName()` both return `""` (checked in game), and the realm was once
  readable (the saved data holds a `CAMWOW US2 Realm 8 PvP-Salvador` next to `-Salvador`). `UnitName` and
  `UnitFullName` return only the first name: "Dru Sill" and "Dru Silla" both report `"Dru"` and overwrite
  each other's entry `-Dru`.
- `UnitGUID("player")` is unique and stable: `Player-6934-0008D960` vs `Player-6934-00082E5F` for the two Drus.
- Item tooltips: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` with `data.id`
  is used on this client by ForeverDungeonJournal, Auctionator, EnhanceQoL and Questie. ForeverDungeonJournal
  pcalls it, falls back to `GameTooltip:HookScript("OnTooltipSetItem")`, and dedupes with a flag cleared on
  `OnTooltipCleared`.
- Every `rep` faction in the recipe data is neutral (Argent Dawn, Timbermaw, Thorium Brotherhood, Cenarion
  Circle, Zandalar, Forever's new factions…), so only vendors can make a recipe faction-specific in practice.
- WoW chat has no tab completion for addon slash arguments.

## Decisions (made with the user)

- **All realms.** Every cached character on the account is listed.
- **Both factions.** "Learnable by" excludes a character only when the recipe is locked to the other faction
  (`rec.side`). It adds a hint such as `(Alliance vendors only)` when every vendor of the recipe belongs to the
  other faction.
- **Selector at the top of the profession column**, a dropdown with faction icon and class-coloured name.
- **Key by GUID** (user saw the evidence; the alternative, full name + normalized realm, fails here because
  both are ambiguous).

## Approaches considered

| | Key | Trade-off |
|---|---|---|
| **Chosen** | `UnitGUID("player")` | Unique and stable across realm renames and first-name clashes. Keys aren't readable, so `/fp chars` numbers the list. |
| Rejected | name + normalized realm (Syndicator's) | Realm is `""` and names are first-name only on this client: Dru Sill and Dru Silla collide. |

| | Selector widget | Trade-off |
|---|---|---|
| **Chosen (builder's call)** | Our own button + popup list of rows | Matches the Journal styling, works in the mock, no dependency on the newer Menu API. |
| Rejected | `WowStyle1DropdownTemplate` + `SetupMenu` | Exists on this client (Baganator uses it), but needs heavy mocking and looks like Blizzard's menus. |

## Design

### Character records (`Characters.lua`)

- `ns.CharKey()` returns `UnitGUID("player")`, or the old `realm-name` string only if the GUID is nil.
- Record: `{ guid, name, realm, class, faction, level, updated, professions = {[line]={skill,max}}, learned }`.
  `level` is new (shown in `/fp chars`).
- **Migration:** `InitDB` bumps `db.version` to 2 and deletes every `chars` key that doesn't start with
  `Player-`. Each character rebuilds on its next login. Nothing reads alts yet, so nothing is lost but a login.
- `ns.ListChars()` → array of `{ key, char }`: logged-in character first, then by name, then key (stable order,
  used by the selector, `/fp chars` numbers and the detail/tooltip lines).
- `ns.CharLabel(key)` → name in class colour; when another cached character has the same name, append the
  localized class: `Dru (Rogue)`. Class colours from `C_ClassColor.GetClassColor` or `RAID_CLASS_COLORS`,
  names from `LOCALIZED_CLASS_NAMES_MALE`.
- `ns.RecipeOwners(line, spellID)` → `{ known = {key…}, learnable = {{key, hint}…}, low = {{key, skill}…} }`:
  - known: `learned[spellID]`.
  - otherwise, only characters with `professions[line]`:
    - skip if `rec.side` is set and differs from the character's faction;
    - `skill >= (rec.learn or 0)` → learnable, else low (with their skill);
    - hint: if `rec.vendors` is non-empty and every vendor's `ns.Data.NPCs[id].faction` is the other faction's
      letter (`"A"` for a Horde character, `"H"` for an Alliance one), hint = `L.VENDORS_ONLY` formatted with
      the faction. Vendors with unknown or `"AH"` faction mean no hint.
- `ns.ForgetChar(arg)` → number (index in `ListChars`) or name (case-insensitive). Refuses the logged-in
  character (it would come straight back). A name matching several characters prints them with their numbers
  instead of guessing.

### Window state and the key flow

- `UI.state.char`: `nil` means the logged-in character. Not saved; resets on `/reload`.
- Every `ns.IsLearned(id)` and `ns.CharSkill(line)` in `UI/Window.lua`, `UI/RecipeList.lua` and `UI/Detail.lua`
  becomes `ns.IsLearned(id, UI.state.char)` / `ns.CharSkill(line, UI.state.char)`: tabs, counter, list
  `isLearned`, row ✓/✗ and colours, detail title colour, status and range.
- Switching character keeps the current profession tab and selection and refreshes everything.
- **Live refresh:** the logged-in character's record keeps updating from events as today, whatever is shown.
  `UI.Refresh` just repaints with the selected character, so an alt view is unaffected (and the "Known by"
  lines pick up the logged-in character's new recipes).
- If the viewed character is forgotten, `UI.state.char` goes back to `nil`.

### Selector (`UI/Window.lua` or a new `UI/CharSelect.lua`)

At the top of the profession column; tabs move down 34px (12 tabs use 486 of the column's 588px, so they fit).

```
+------------------+-------------------------------------+
| [H] Dru (Rogue) v| [All][Learned][Missing] [Search   ] |
|------------------+-------------------------------------|
| [ic] Alchemy     | - Elixirs                   3/40    |
|      Skill 120/  |   [i] Elixir of ...  1-55   v       |
+------------------+-------------------------------------+
popup:
  [H] Salvador      Paladin   (you)
  [H] Dru           Rogue
  [H] Dru           Druid
  [H] Alberto       Priest
```

Faction icon: `Interface\TargetingFrame\UI-PVP-Horde` / `-Alliance` (to verify in game; text tag fallback).
The popup closes on a pick, on a second click of the button, and when the window hides.

### Detail pane (`UI/Detail.lua`)

A new `Characters` section after the recipe item, before Sources, built by `UI.DetailLines` from
`ns.RecipeOwners` (so it's testable without frames):

```
Characters
  Known by: Salvador, Dru (Rogue)
  Learnable by: Alberto (Alliance vendors only)
  Skill too low: Dru (Druid) 120 / 165
```

Empty groups are omitted. If no cached character has the profession, the line reads
"No character has this profession".

### Tooltips (new `Tooltip.lua`, loaded after `Model.lua`)

- Reverse index `itemID → { {line, spellID}… }` from every `teach` (number or list), built on first use.
- Registration at file load: pcall `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, …)`,
  fall back to `HookScript("OnTooltipSetItem")` on `GameTooltip` and `ItemRefTooltip`.
- Handler, all inside pcall: only `GameTooltip` and `ItemRefTooltip`; item ID from `data.id`, else
  `tooltip:GetItem()`'s link; nothing to do if it isn't a recipe item; dedupe with `tooltip.fpItem`, cleared on
  `OnTooltipCleared`; add the same three lines as the detail pane (one block per spell if an item teaches
  several), then `tooltip:Show()`. Nothing is added when no cached character has the profession.

### Slash commands (`Core.lua`)

- `/fp chars`: numbered list, e.g. `2. Dru (Rogue) - Horde, level 24 - Alchemy 120, Herbalism 75 - updated 3 days ago`.
- `/fp forget <number|name>`: as `ns.ForgetChar`, then refresh the window. Help text updated.

### Strings

All new text goes in `Locale.lua` (`KNOWN_BY`, `LEARNABLE_BY`, `SKILL_TOO_LOW`, `VENDORS_ONLY`, `CHARACTERS`,
`NO_CHARACTER`, `YOU`, chars/forget messages).

## Testing

Test first, one step at a time, `mise exec -- python -m unittest discover tests` after each.

- Mock: configurable `UnitGUID`, `UnitFullName`, `UnitLevel`, `UnitClass`/`UnitFactionGroup`,
  `RAID_CLASS_COLORS`, `LOCALIZED_CLASS_NAMES_MALE`, `Enum.TooltipDataType`, `TooltipDataProcessor`
  (records callbacks so tests can fire them), `ItemRefTooltip`, `OnTooltipCleared`.
- Alts seeded through `Addon(setup="ForeverProfessionalDB = { version = 2, chars = { ... } }")`.
- Covered: GUID key and migration, two same-name characters kept apart, `ListChars` order, `CharLabel`
  disambiguation, `RecipeOwners` (known/learnable/low, `side` exclusion, vendor hint on a real recipe with
  one-faction vendors), selector switching (tabs, counter, ✓/✗, detail status), live refresh while an alt is
  shown, detail lines, tooltip lines and dedupe, `/fp chars`, `/fp forget` by number, by name, ambiguous name
  and the logged-in character.

## Steps (one commit each, on `develop`, no push)

1. Mock additions + GUID key + migration.
2. `ListChars`, `CharLabel`, `RecipeOwners`.
3. `/fp chars` and `/fp forget`.
4. `UI.state.char` threaded through Window, RecipeList, Detail.
5. Selector.
6. Detail "Characters" section.
7. `Tooltip.lua` (TOC entry with the camelot suffix).
8. README/AGENTS updates (GUID key, new commands).

## Left to the builder

Exact pixel layout of the selector and popup, colours of the three detail lines, wording of chat messages,
and which real recipes the tests use.

## In-game checklist (after implementation)

Full client restart (TOC changes), then:

1. Log in on two characters with professions (the two Drus are ideal), then on a third.
2. `/fp chars`: all three listed once, numbered, with no old `-Name` entries.
3. `/fp`: the selector shows you; pick an alt: tab skills, ✓/✗, All/Learned/Missing counts and colours change;
   pick yourself again: back to live data.
4. Learn a recipe or skill up while an alt is shown: the view stays on the alt; switch back and it's there.
5. Select a recipe: the Characters section lists Known by / Learnable by / Skill too low correctly.
6. Hover a recipe item at a vendor and in the AH: the same lines appear once (not doubled), also on a chat link.
7. Check the faction icon renders in the selector.
8. `/fp forget <n>` on one alt: gone from `/fp chars`, the selector and tooltips; `/fp forget` on yourself is refused.
