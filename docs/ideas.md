# Ideas

Features and decisions for ForeverProfessional that aren't built yet, including ones carried over from the early chats in the Claude app. When an idea is decided, move it into AGENTS.md or a design doc under `docs/superpowers/specs/`; when it ships, delete it here.

## Ideas

- **Harvest vendor data from what players see.** On `MERCHANT_SHOW` the client gives the NPC ID (`UnitGUID("npc")`), its location, and the recipes for sale with prices (verified in the spike: Sumi in Orgrimmar sells Plans: Hardened Iron Shortsword). Use it to fill in missing vendor info for recipes the baked data doesn't cover.
- **Save translated category names.** Category names are only readable in game while that profession's window is open (the spike got the full tree for Blacksmithing, Tailoring, Cooking and Enchanting that way). The baked `Categories.lua` is enUS; the addon could save the client's localized names whenever a player opens a profession window.

## Decided, not built yet

## Open questions

- **Competitor:** My Forever Recipe Book (CurseForge, a 0.17.0 beta last updated Oct 7 at the time) is a spellbook-style book with trainers, vendors, drops, quests, NPC locations, prices, drop rates and map pins. The Journal/AtlasLoot design is our main way to stand out; keep an eye on what it adds.
