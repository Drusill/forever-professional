-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Per-character cache of professions and learned recipes, kept in ForeverProfessionalDB.chars
-- so other characters' recipes can be shown later.
local _, ns = ...

function ns.CharKey()
    return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

-- Character record, created on demand. Record:
-- { name, realm, class, faction, updated, professions = {[line]={skill,max}}, learned = {[spellID]=true} }
function ns.GetChar(key)
    if not ns.db then return nil end
    key = key or ns.CharKey()
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

function ns.UpdateCharInfo()
    local c = ns.GetChar()
    if not c then return end
    c.name = UnitName("player")
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
