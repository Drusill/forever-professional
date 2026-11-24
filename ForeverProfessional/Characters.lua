-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Per-character cache of professions and learned recipes, kept in ForeverProfessionalDB.chars.
local _, ns = ...

-- Characters are keyed by GUID: on Forever the realm name is empty and UnitName gives only the first
-- name, so two characters can share a name. nil until the GUID is known (before login).
function ns.CharKey()
    return UnitGUID and UnitGUID("player") or nil
end

-- Character record, created on demand. Record:
-- { guid, name, realm, class, faction, level, updated, professions = {[line]={skill,max}}, learned = {[spellID]=true} }
function ns.GetChar(key)
    if not ns.db then return nil end
    key = key or ns.CharKey()
    if not key then return nil end
    local c = ns.db.chars[key]
    if not c and key == ns.CharKey() then
        c = { learned = {}, professions = {} }
        ns.db.chars[key] = c
    end
    return c
end

function ns.IsLearned(spellID, key)
    local c = ns.GetChar(key)
    return c and c.learned and c.learned[spellID] or false
end

function ns.CharSkill(line, key)
    local c = ns.GetChar(key)
    local p = c and c.professions and c.professions[line]
    return p and p.skill, p and p.max
end

-- Whether a character with this skill (nil: no profession) and faction can learn the recipe now.
-- Learned status is the caller's to check. Shared by LearnableCount and the Learnable now filter.
function ns.CanLearnNow(rec, skill, faction)
    if not skill or skill < (rec.learn or 0) then return false end
    return not (rec.side and rec.side ~= faction)
end

-- Recipes of a profession the character could learn now: not learned, has the profession with
-- enough skill, and not locked to the other faction.
function ns.LearnableCount(line, key)
    local c = ns.GetChar(key)
    local prof = c and c.professions and c.professions[line]
    if not prof then return 0 end
    local skill, n = prof.skill or 0, 0
    for spellID, rec in pairs(ns.Data.Recipes[line] or {}) do
        if not (c.learned and c.learned[spellID]) and ns.CanLearnNow(rec, skill, c.faction) then
            n = n + 1
        end
    end
    return n
end

-- "Horde", "Alliance", or nil when the character isn't cached.
function ns.CharFaction(key)
    local c = ns.GetChar(key)
    return c and c.faction or nil
end

-- Other characters ------------------------------------------------------------------------------

-- Every cached character as { key, char }: the logged-in one first, then by name, then by key.
function ns.ListChars()
    local out = {}
    if not ns.db then return out end
    local me = ns.CharKey()
    for key, c in pairs(ns.db.chars) do out[#out + 1] = { key = key, char = c } end
    table.sort(out, function(a, b)
        if (a.key == me) ~= (b.key == me) then return a.key == me end
        local an, bn = a.char.name or "", b.char.name or ""
        if an ~= bn then return an < bn end
        return a.key < b.key
    end)
    return out
end

local function ClassName(class)
    return class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end
ns.ClassName = ClassName

-- Plain display name. Names aren't unique on Forever (first name only): a shared name gets the class,
-- "Dru (Rogue)", and a shared name and class also gets a number, "Dru (Rogue) 2", ranked by key (GUID)
-- so the number names the same character whoever is logged in.
function ns.CharName(key)
    local c = ns.db and ns.db.chars[key]
    if not c then return "?" end
    local name = c.name or "?"
    local sameName, rank = false, 1
    for k, other in pairs(ns.db.chars) do
        if other.name == c.name and k ~= key then
            sameName = true
            if other.class == c.class and k < key then rank = rank + 1 end
        end
    end
    if not sameName then return name end
    local class = ClassName(c.class)
    if class then name = name .. " (" .. class .. ")" end
    if rank > 1 then name = name .. " " .. rank end
    return name
end

-- CharName in the class colour (white when the class is unknown).
function ns.CharLabel(key)
    local c = ns.db and ns.db.chars[key]
    local color = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    return "|c" .. (color and color.colorStr or "ffffffff") .. ns.CharName(key) .. "|r"
end

local OTHER_SIDE = { Horde = "A", Alliance = "H" }

-- Hint for a character of `faction` when every vendor of the recipe belongs to the other faction.
local function VendorHint(rec, faction)
    local other = OTHER_SIDE[faction]
    if not (other and rec.vendors and #rec.vendors > 0) then return nil end
    for _, id in ipairs(rec.vendors) do
        local npc = ns.Data.NPCs and ns.Data.NPCs[id]
        if not npc or npc.faction ~= other then return nil end
    end
    return ns.L.VENDORS_ONLY:format(other == "A" and ns.L.ALLIANCE or ns.L.HORDE)
end

-- Who knows a recipe, who could learn it now, and who has the profession but too little skill.
-- { known = {key...}, learnable = {{key, hint}...}, low = {{key, skill}...} }, each in ListChars order.
-- A recipe locked to the other faction (rec.side) isn't learnable at all.
function ns.RecipeOwners(line, spellID)
    local out = { known = {}, learnable = {}, low = {} }
    local rec = ns.Data.Recipes[line] and ns.Data.Recipes[line][spellID]
    if not rec then return out end
    for _, e in ipairs(ns.ListChars()) do
        local c = e.char
        local prof = c.professions and c.professions[line]
        if c.learned and c.learned[spellID] then
            out.known[#out.known + 1] = e.key
        elseif prof and not (rec.side and rec.side ~= c.faction) then
            local skill = prof.skill or 0
            if skill >= (rec.learn or 0) then
                out.learnable[#out.learnable + 1] = { key = e.key, hint = VendorHint(rec, c.faction) }
            else
                out.low[#out.low + 1] = { key = e.key, skill = skill }
            end
        end
    end
    return out
end

-- Up to three groups for the detail pane: known by, learnable by, skill too low, each as
-- { group = "known"|"learnable"|"low", text }. Empty groups are left out.
function ns.OwnerGroups(line, spellID)
    local L = ns.L
    local rec = ns.Data.Recipes[line] and ns.Data.Recipes[line][spellID]
    local o = ns.RecipeOwners(line, spellID)
    local out = {}
    local function Add(group, color, fmt, names)
        if #names > 0 then
            out[#out + 1] = { group = group, text = color .. fmt:format("|r" .. table.concat(names, ", ")) }
        end
    end
    local known, learnable, low = {}, {}, {}
    for _, key in ipairs(o.known) do known[#known + 1] = ns.CharLabel(key) end
    for _, e in ipairs(o.learnable) do
        learnable[#learnable + 1] = ns.CharLabel(e.key) .. (e.hint and (" " .. e.hint) or "")
    end
    for _, e in ipairs(o.low) do
        low[#low + 1] = ("%s %d / %d"):format(ns.CharLabel(e.key), e.skill, rec and rec.learn or 0)
    end
    Add("known", "|cff40c040", L.KNOWN_BY, known)
    Add("learnable", "|cffffd200", L.LEARNABLE_BY, learnable)
    Add("low", "|cff909090", L.SKILL_TOO_LOW, low)
    return out
end

-- The same groups as plain display lines, for item tooltips; {} when no cached character knows or
-- could learn the recipe.
function ns.OwnerLines(line, spellID)
    local out = {}
    for _, g in ipairs(ns.OwnerGroups(line, spellID)) do out[#out + 1] = g.text end
    return out
end

-- Materials calculator --------------------------------------------------------------------------

-- Live context for Model.PlanMaterials. "Me" is always the logged-in character, whichever character the
-- window shows: inventory comes from its bags and bank (C_Item.GetItemCount counts the bank away from it).
function ns.PlanContext()
    local me = ns.CharKey()
    return {
        reagents = ns.Model.Reagents,
        have = function(itemID)
            return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, true)) or 0
        end,
        knownBy = function(line, spellID)
            local out = { me = false, alts = {} }
            for _, key in ipairs(ns.RecipeOwners(line, spellID).known) do
                if key == me then out.me = true else out.alts[#out.alts + 1] = key end
            end
            return out
        end,
        mode = function(itemID) return ns.db and ns.db.craftModes[itemID] end,
    }
end

-- Save "craft" or "buy" for an item in every plan; nil goes back to the default.
function ns.SetCraftMode(itemID, mode)
    if mode ~= "craft" and mode ~= "buy" then mode = nil end
    ns.db.craftModes[itemID] = mode
    ns.MarkTrackedDirty()
end

function ns.ResetCraftModes()
    wipe(ns.db.craftModes)
    ns.MarkTrackedDirty()
end

-- Who crafts something: "You", the first alt's name (" +N" for more), or "Nobody"; and that kind.
function ns.CrafterText(known)
    local L = ns.L
    if known and known.me then return L.CALC_YOU, "me" end
    local alts = known and known.alts or {}
    if #alts > 0 then
        local text = ns.CharLabel(alts[1])
        if #alts > 1 then text = text .. " +" .. (#alts - 1) end
        return text, "alt"
    end
    return L.CALC_NOBODY, "nobody"
end

-- Tracked recipes -------------------------------------------------------------------------------
-- An account-wide, ordered list in ns.db.tracked: { {spellID, line, quantity, unit}... }. Our own list:
-- Blizzard's recipe tracking is never touched.

local TRACKED_MAX = 999

local function TrackedRecipe(line, spellID)
    return ns.Data.Recipes[line] and ns.Data.Recipes[line][spellID]
end

-- A clean copy of a saved entry, or nil when it can't be used (unknown recipe, bad quantity).
local function NormalizeTracked(e)
    if type(e) ~= "table" or type(e.spellID) ~= "number" or type(e.quantity) ~= "number" then return nil end
    local rec = TrackedRecipe(e.line, e.spellID)
    if not rec or e.quantity < 1 then return nil end
    local unit = (e.unit == "items" and ns.Model.MakesSeveral(rec)) and "items" or "crafts"
    return { spellID = e.spellID, line = e.line, quantity = math.min(TRACKED_MAX, math.floor(e.quantity)), unit = unit }
end

-- The combined plan of the tracked recipes and its per-recipe shares, cached until an input changes:
-- the list, a craft/buy choice, the bags, what a character knows, or the cached characters.
local trackedPlan, trackedShares

function ns.MarkTrackedDirty()
    trackedPlan, trackedShares = nil, nil
end

-- Every change to the list goes through here.
function ns.TrackedChanged()
    ns.MarkTrackedDirty()
    if ns.UI and ns.UI.Refresh and ns.UI.IsShown and ns.UI.IsShown() then ns.UI.Refresh() end
end

-- The usable entries, in tracking order, as normalized copies.
function ns.TrackedList()
    local out = {}
    for _, e in ipairs(ns.db and ns.db.tracked or {}) do
        local n = NormalizeTracked(e)
        if n then out[#out + 1] = n end
    end
    return out
end

-- Index of a spell's saved entry in ns.db.tracked.
local function TrackedIndex(spellID)
    for i, e in ipairs(ns.db.tracked) do
        if type(e) == "table" and e.spellID == spellID then return i end
    end
end

function ns.GetTracked(spellID)
    local i = TrackedIndex(spellID)
    return i and NormalizeTracked(ns.db.tracked[i]) or nil
end

-- Track a recipe, or update it in place when it's already tracked.
function ns.TrackRecipe(line, spellID, quantity, unit)
    local entry = NormalizeTracked({ spellID = spellID, line = line, quantity = quantity or 1, unit = unit })
    if not entry then return end
    local i = TrackedIndex(spellID)
    ns.db.tracked[i or (#ns.db.tracked + 1)] = entry
    ns.TrackedChanged()
end

function ns.UntrackRecipe(spellID)
    local i = TrackedIndex(spellID)
    if not i then return end
    table.remove(ns.db.tracked, i)
    ns.TrackedChanged()
end

-- A new number for a tracked recipe; 0 or less untracks it.
function ns.SetTrackedQuantity(spellID, n)
    local e = ns.GetTracked(spellID)
    n = tonumber(n)
    if not (e and n) then return end
    if n <= 0 then return ns.UntrackRecipe(spellID) end
    ns.TrackRecipe(e.line, spellID, n, e.unit)
end

-- Crafts or items: the number stays, its meaning changes (as in the calculator).
function ns.SetTrackedUnit(spellID, unit)
    local e = ns.GetTracked(spellID)
    if e then ns.TrackRecipe(e.line, spellID, e.quantity, unit) end
end

-- Drop the saved entries ns.TrackedList skips (recipes removed from the data, bad values).
function ns.PruneTracked()
    if not ns.db then return end
    ns.db.tracked = ns.TrackedList()
end

-- Plan roots for the tracked recipes, in list order; Items mode rounds up to whole crafts.
function ns.TrackedRoots()
    local roots = {}
    for _, e in ipairs(ns.TrackedList()) do
        local crafts = e.quantity
        if e.unit == "items" then crafts = ns.Model.CraftsFor(TrackedRecipe(e.line, e.spellID), e.quantity) end
        roots[#roots + 1] = { spellID = e.spellID, line = e.line, crafts = crafts }
    end
    return roots
end

-- plan, shares (Model.PlanShares) for everything tracked; nil when nothing is.
function ns.TrackedPlan()
    if not trackedPlan then
        local roots = ns.TrackedRoots()
        if #roots == 0 then return nil end
        trackedPlan = ns.Model.PlanMaterials(roots, ns.PlanContext())
        trackedShares = ns.Model.PlanShares(trackedPlan)
    end
    return trackedPlan, trackedShares
end

ns.On("BAG_UPDATE_DELAYED", function() ns.MarkTrackedDirty() end)

-- "1 craft", "4 crafts", "1 item", "10 items".
function ns.TrackedText(entry)
    local L, q = ns.L, entry.quantity
    if entry.unit == "items" then
        return q == 1 and L.TRACKED_ITEM_ONE or L.TRACKED_ITEMS:format(q)
    end
    return q == 1 and L.TRACKED_CRAFT_ONE or L.TRACKED_CRAFTS:format(q)
end

-- /fp chars and /fp forget ------------------------------------------------------------------------

local function ProfessionSummary(c)
    local parts = {}
    for line, p in pairs(c.professions or {}) do
        local prof = ns.Data.Professions[line]
        if prof then parts[#parts + 1] = prof.name .. " " .. (p.skill or 0) end
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or ns.L.NO_PROFESSIONS
end

function ns.PrintChars()
    local L = ns.L
    for i, e in ipairs(ns.ListChars()) do
        local c = e.char
        local faction = c.faction == "Horde" and L.HORDE or c.faction == "Alliance" and L.ALLIANCE or c.faction or "?"
        local updated = c.updated and date("%Y-%m-%d", c.updated) or "?"
        ns.Print(L.CHARS_LINE:format(i, ns.CharLabel(e.key), faction, tostring(c.level or "?"),
            ProfessionSummary(c), updated))
    end
end

-- Remove a character by its number in ListChars (as /fp chars prints it) or by name (any case).
-- Returns "removed", record, label | "self" | "none" | "ambiguous", { {index, key}... }.
function ns.ForgetChar(arg)
    arg = strtrim(arg or "")
    local list, matches = ns.ListChars(), {}
    local n = tonumber(arg)
    if n then
        if list[n] then matches[1] = { index = n, key = list[n].key } end
    else
        local lower = arg:lower()
        for i, e in ipairs(list) do
            if (e.char.name or ""):lower() == lower then matches[#matches + 1] = { index = i, key = e.key } end
        end
    end
    if #matches == 0 then return "none" end
    if #matches > 1 then return "ambiguous", matches end
    local key = matches[1].key
    if key == ns.CharKey() then return "self" end
    local label, c = ns.CharLabel(key), ns.db.chars[key]
    ns.db.chars[key] = nil
    ns.MarkTrackedDirty()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    return "removed", c, label
end

function ns.ForgetCommand(arg)
    local L = ns.L
    if strtrim(arg or "") == "" then
        ns.Print(L.FORGET_USAGE)
        return
    end
    local status, detail, label = ns.ForgetChar(arg)
    if status == "removed" then
        ns.Print(L.FORGOTTEN:format(label))
    elseif status == "self" then
        ns.Print(L.FORGET_SELF)
    elseif status == "ambiguous" then
        ns.Print(L.FORGET_AMBIGUOUS:format(arg))
        for _, m in ipairs(detail) do ns.Print(("%d. %s"):format(m.index, ns.CharLabel(m.key))) end
    else
        ns.Print(L.FORGET_NONE:format(arg))
    end
end

-- Logged-in character -------------------------------------------------------------------------

function ns.UpdateCharInfo()
    local c = ns.GetChar()
    if not c then return end
    c.guid = ns.CharKey()
    c.name = UnitName("player")
    c.level = UnitLevel and UnitLevel("player") or nil
    c.realm = GetRealmName()
    c.class = select(2, UnitClass("player"))
    c.faction = UnitFactionGroup("player")
    local profs = ns.GetPlayerProfessions()
    local out = {}
    for line, p in pairs(profs) do out[line] = { skill = p.skill, max = p.max } end
    c.professions = out
    c.updated = time()
end

-- Rebuild the learned set from C_SpellBook.IsSpellKnown over every baked recipe, so recipes of
-- professions the character dropped are caught too. Returns the number of learned recipes.
function ns.ScanLearned()
    local c = ns.GetChar()
    if not c or not (C_SpellBook and C_SpellBook.IsSpellKnown) then return 0 end
    local learned, n = {}, 0
    for _, recipes in pairs(ns.Data.Recipes or {}) do
        for spellID in pairs(recipes) do
            if C_SpellBook.IsSpellKnown(spellID) then
                learned[spellID] = true
                n = n + 1
            end
        end
    end
    c.learned = learned
    c.updated = time()
    return n
end

local function Refresh()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function ns.UpdateCharacter()
    ns.UpdateCharInfo()
    ns.ScanLearned()
    ns.MarkTrackedDirty()
    Refresh()
end

-- SKILL_LINES_CHANGED fires on every skill-up: coalesce into one update.
local pending = false
local function ScheduleUpdate(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 1, function()
        pending = false
        ns.UpdateCharacter()
    end)
end
ns.ScheduleCharacterUpdate = ScheduleUpdate

ns.On("PLAYER_LOGIN", function()
    if not ns.db then ns.InitDB() end
    ns.PruneTracked()
    ns.UpdateCharacter()
    -- The spellbook isn't always complete at login; scan again shortly after.
    ScheduleUpdate(3)
end)

ns.On("NEW_RECIPE_LEARNED", function(recipeID)
    local c = ns.GetChar()
    if c and recipeID then
        c.learned[recipeID] = true
        c.updated = time()
    end
    ns.MarkTrackedDirty()
    Refresh()
end)

ns.On("SKILL_LINES_CHANGED", function() ScheduleUpdate(1) end)
ns.On("LEARNED_SPELL_IN_TAB", function() ScheduleUpdate(1) end)
ns.On("LEARNED_SPELL_IN_SKILL_LINE", function() ScheduleUpdate(1) end)
