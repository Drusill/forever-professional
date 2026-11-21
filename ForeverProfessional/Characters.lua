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

-- Recipes of a profession the character could learn now: not learned, has the profession with
-- enough skill, and not locked to the other faction.
function ns.LearnableCount(line, key)
    local c = ns.GetChar(key)
    local prof = c and c.professions and c.professions[line]
    if not prof then return 0 end
    local skill, n = prof.skill or 0, 0
    for spellID, rec in pairs(ns.Data.Recipes[line] or {}) do
        if not (c.learned and c.learned[spellID]) and skill >= (rec.learn or 0)
                and not (rec.side and rec.side ~= c.faction) then
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

-- Up to three display lines for the detail pane and tooltips: known by, learnable by, skill too low.
-- Empty groups are left out; {} when no cached character knows or could learn the recipe.
function ns.OwnerLines(line, spellID)
    local L = ns.L
    local rec = ns.Data.Recipes[line] and ns.Data.Recipes[line][spellID]
    local o = ns.RecipeOwners(line, spellID)
    local out = {}
    local function Add(color, fmt, names)
        if #names > 0 then out[#out + 1] = color .. fmt:format("|r" .. table.concat(names, ", ")) end
    end
    local known, learnable, low = {}, {}, {}
    for _, key in ipairs(o.known) do known[#known + 1] = ns.CharLabel(key) end
    for _, e in ipairs(o.learnable) do
        learnable[#learnable + 1] = ns.CharLabel(e.key) .. (e.hint and (" " .. e.hint) or "")
    end
    for _, e in ipairs(o.low) do
        low[#low + 1] = ("%s %d / %d"):format(ns.CharLabel(e.key), e.skill, rec and rec.learn or 0)
    end
    Add("|cff40c040", L.KNOWN_BY, known)
    Add("|cffffd200", L.LEARNABLE_BY, learnable)
    Add("|cff909090", L.SKILL_TOO_LOW, low)
    return out
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
    Refresh()
end)

ns.On("SKILL_LINES_CHANGED", function() ScheduleUpdate(1) end)
ns.On("LEARNED_SPELL_IN_TAB", function() ScheduleUpdate(1) end)
ns.On("LEARNED_SPELL_IN_SKILL_LINE", function() ScheduleUpdate(1) end)
