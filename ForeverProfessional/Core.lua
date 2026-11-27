-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
local addonName, ns = ...
local L = ns.L

ns.name = addonName
ns.Data = ns.Data or {}

function ns.Print(msg)
    local text = "|cff8080ff" .. L.TITLE .. "|r " .. tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        print(text)
    end
end

-- Events ---------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}
ns.eventFrame = eventFrame

-- Register fn for event. Unknown events throw on RegisterEvent, so that's pcall'd.
function ns.On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    list[#list + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end)

-- Saved variables ------------------------------------------------------------

local DEFAULTS = {
    version = 2,
    window = {},      -- saved position
    collapsed = {},   -- [categoryID or "other"] = true
    chars = {},       -- [GUID] = character record (Characters.lua)
    filter = "all",
    filters = {},     -- filter menu: [item key from Model.FILTER_GROUPS] = true
    craftModes = {},  -- materials calculator: [itemID] = "craft" | "buy", overriding the default
    tracked = {},     -- tracked recipes, in order: { {spellID, line, quantity, unit = "crafts"|"items"}... }
    minimapAngle = 225,     -- minimap button position, degrees (0 = right, 90 = top)
    minimapHidden = false,
    -- Options window: item tooltip blocks, each on by default.
    tooltipOwners = true,        -- recipe items: who knows or can learn the recipe
    tooltipTracked = true,       -- "Needed for" lines of tracked recipes
    tooltipUsedIn = true,        -- reagents: "Used in" lines (and the index behind them)
    tooltipUsedInNames = true,   -- reagents: Shift lists the recipes
}

-- A saved setting, or its default before the saved variables load (or when the key is missing).
function ns.Setting(key)
    local db = ns.db
    if db and db[key] ~= nil then return db[key] end
    return DEFAULTS[key]
end

function ns.InitDB()
    if type(ForeverProfessionalDB) ~= "table" then ForeverProfessionalDB = {} end
    local db = ForeverProfessionalDB
    -- Version 2 keys characters by GUID: drop the old "Realm-Name" entries (they collide on Forever).
    -- Each character rebuilds its entry on its next login.
    if db.version and db.version < 2 then
        for key in pairs(db.chars or {}) do
            if not tostring(key):match("^Player%-") then db.chars[key] = nil end
        end
        db.version = 2
    end
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = type(v) == "table" and {} or v end
    end
    ns.db = db
    return db
end

ns.On("ADDON_LOADED", function(name)
    if name == addonName then ns.InitDB() end
end)

-- Professions ----------------------------------------------------------------

local childToRoot

-- Map any skill line (classic root ID or a Forever child line such as 2937) to the root
-- line used by ns.Data.Professions. Child lines are found through the category tree.
function ns.RootLine(line)
    if not line then return nil end
    local profs = ns.Data.Professions or {}
    if profs[line] then return line end
    if not childToRoot then
        childToRoot = {}
        local cats = ns.Data.Categories or {}
        for _, c in pairs(cats) do
            if c.line and c.parent and not profs[c.line] and not childToRoot[c.line] then
                local root, guard = c, 0
                while root.parent and cats[root.parent] and guard < 20 do
                    root, guard = cats[root.parent], guard + 1
                end
                if root.line and profs[root.line] then childToRoot[c.line] = root.line end
            end
        end
    end
    return childToRoot[line]
end

-- Returns { [rootLine] = { skill, max, name, index } } and the lines in GetProfessions() order.
function ns.GetPlayerProfessions()
    local out, order = {}, {}
    if not (GetProfessions and GetProfessionInfo) then return out, order end
    local indices = { GetProfessions() }
    local n = select("#", GetProfessions())
    for i = 1, n do
        local index = indices[i]
        if index then
            local name, _, skill, maxSkill, _, _, skillLine = GetProfessionInfo(index)
            local line = ns.RootLine(skillLine)
            if line and not out[line] then
                out[line] = { skill = skill or 0, max = maxSkill or 0, name = name, index = index }
                order[#order + 1] = line
            end
        end
    end
    return out, order
end

-- Find a profession line by (partial, case-insensitive) name.
function ns.FindProfession(text)
    text = (text or ""):lower()
    if text == "" then return nil end
    local best
    for line, p in pairs(ns.Data.Professions or {}) do
        local name = p.name:lower()
        if name == text then return line end
        if name:find(text, 1, true) and (not best or line < best) then best = line end
    end
    return best
end

-- Slash command ----------------------------------------------------------------

SLASH_FOREVERPROFESSIONAL1 = "/fp"
SLASH_FOREVERPROFESSIONAL2 = "/foreverprofessional"
SlashCmdList.FOREVERPROFESSIONAL = function(msg)
    msg = strtrim and strtrim(msg or "") or (msg or "")
    if msg == "help" then
        ns.Print(L.HELP)
        return
    end
    if msg:lower() == "minimap" then
        if ns.MinimapButton then ns.MinimapButton.ToggleHidden() end
        return
    end
    if msg:lower() == "options" then
        if ns.UI and ns.UI.ToggleOptions then ns.UI.ToggleOptions() end
        return
    end
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower()
    if cmd == "chars" then
        ns.PrintChars()
        return
    elseif cmd == "forget" then
        ns.ForgetCommand(rest)
        return
    elseif cmd == "debug" then
        for _, line in ipairs(ns.UsedIn.DebugLines()) do ns.Print(line) end
        return
    end
    if not ns.UI then return end
    if msg == "" then
        ns.UI.Toggle()
        return
    end
    local line = ns.FindProfession(msg)
    if line then
        ns.UI.Show(line)
    else
        ns.Print(L.UNKNOWN_PROFESSION:format(msg))
    end
end
