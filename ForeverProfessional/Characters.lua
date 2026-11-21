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
-- "Dru (Rogue)", and a shared name and class also gets a number, "Dru (Rogue) 2", in ListChars order.
function ns.CharName(key)
    local c = ns.db and ns.db.chars[key]
    if not c then return "?" end
    local name = c.name or "?"
    local sameName, sameClass, rank = false, 0, 0
    for _, e in ipairs(ns.ListChars()) do
        if e.char.name == c.name then
            if e.key ~= key then sameName = true end
            if e.char.class == c.class then
                sameClass = sameClass + 1
                if e.key == key then rank = sameClass end
            end
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
