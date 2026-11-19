-- ForeverProfessional_Spike / Core
-- Logging, SavedVariables, the copyable report window, events and slash commands.
local ADDON, ns = ...

ns.tests = {}        -- name -> { desc, fn }
ns.testOrder = {}

local COLORS = { PASS = "ff40ff40", FAIL = "ffff4040", WARN = "ffffc040", INFO = "ff80c0ff" }

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------

-- Resolve "C_Foo.Bar" / "Item.CreateFromItemID" against _G. Returns the value or nil.
function ns.Resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

-- pcall that also traps the case where the function does not exist.
-- Returns ok, err-or-first-result, ...
function ns.Try(fn, ...)
    if type(fn) ~= "function" then return false, "function missing" end
    return pcall(fn, ...)
end

-- Short one-line dump for chat / report.
function ns.Dump(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" then
        if #v > 120 then v = v:sub(1, 117) .. "..." end
        return string.format("%q", v)
    elseif t ~= "table" then
        return tostring(v)
    end
    if depth >= 1 then return "{...}" end
    local parts, n = {}, 0
    for k, val in pairs(v) do
        n = n + 1
        if n > 12 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = tostring(k) .. "=" .. ns.Dump(val, depth + 1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Strip color codes and turn |n into " / " so source text reads on one line.
function ns.CleanText(s)
    if type(s) ~= "string" or s == "" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " / ")
    return s
end

function ns.Count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

-- Timer callbacks run outside our pcall'd test runner, so trap their errors too.
function ns.After(sec, fn)
    local function safe()
        local ok, err = pcall(fn)
        if not ok then print("|cffff4040[FP Spike]|r timer callback crashed: " .. tostring(err)) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(sec, safe) else safe() end
end

---------------------------------------------------------------------------
-- Logging into SavedVariables (sections are replaced on re-run)
---------------------------------------------------------------------------

local current -- section currently being written

function ns.Section(name, title)
    local db = ns.db
    if not db.sections[name] then
        db.order[#db.order + 1] = name
    end
    current = { title = title or name, time = date("%Y-%m-%d %H:%M:%S"), lines = {} }
    db.sections[name] = current
    print(("|cff8080ff[FP Spike]|r === %s ==="):format(current.title))
    return current
end

-- status: PASS | FAIL | WARN | INFO
function ns.Log(status, label, detail)
    local line = ("[%s] %s"):format(status, label)
    if detail ~= nil and detail ~= "" then line = line .. " :: " .. tostring(detail) end
    if current then current.lines[#current.lines + 1] = line end
    local color = COLORS[status] or "ffffffff"
    print(("|c%s[%s]|r %s%s"):format(color, status, label,
        (detail ~= nil and detail ~= "") and (" |cffaaaaaa" .. tostring(detail) .. "|r") or ""))
    if ns.reportFrame and ns.reportFrame:IsShown() then ns.RefreshReport() end
end

-- Log into a named section without making it "current" (for async callbacks).
function ns.LogTo(section, status, label, detail)
    local saved = current
    current = ns.db.sections[section] or current
    ns.Log(status, label, detail)
    current = saved
end

function ns.BuildReport()
    local db = ns.db
    local out = {}
    local version, build, date_, iface = GetBuildInfo()
    out[#out + 1] = ("ForeverProfessional Spike report | client %s (%s) %s | interface %s | locale %s")
        :format(tostring(version), tostring(build), tostring(date_), tostring(iface), GetLocale())
    out[#out + 1] = ("Character: %s-%s %s %s"):format(UnitName("player") or "?", GetRealmName() or "?",
        UnitFactionGroup("player") or "?", select(2, UnitClass("player")) or "?")
    for _, name in ipairs(db.order) do
        local s = db.sections[name]
        if s then
            out[#out + 1] = ""
            out[#out + 1] = ("## %s  (%s)"):format(s.title, s.time)
            for _, l in ipairs(s.lines) do out[#out + 1] = l end
        end
    end
    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Report window (own frame; never ShowUIPanel -> avoids taint)
---------------------------------------------------------------------------

function ns.RefreshReport()
    local f = ns.reportFrame
    if not f then return end
    f.edit:SetText(ns.BuildReport())
    f.edit:HighlightText()
end

function ns.ShowReport()
    local f = ns.reportFrame
    if not f then
        local template = BasicFrameTemplateWithInset and "BasicFrameTemplateWithInset" or nil
        f = CreateFrame("Frame", "ForeverProfessionalSpikeReport", UIParent, template)
        f:SetSize(720, 480)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.TitleText then f.TitleText:SetText("FP Spike report — Ctrl+A, Ctrl+C to copy") end
        if not template then
            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.9)
            local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT")
        end

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -30)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(660)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit

        tinsert(UISpecialFrames, f:GetName())
        ns.reportFrame = f
    end
    f:Show()
    ns.RefreshReport()
    f.edit:SetFocus()
end

---------------------------------------------------------------------------
-- Test registry + slash command
---------------------------------------------------------------------------

function ns.RegisterTest(name, desc, fn)
    ns.tests[name] = { desc = desc, fn = fn }
    ns.testOrder[#ns.testOrder + 1] = name
end

local function RunTest(name, ...)
    local t = ns.tests[name]
    if not t then
        print("|cff8080ff[FP Spike]|r unknown test '" .. tostring(name) .. "'. Type /fpspike help")
        return
    end
    local ok, err = pcall(t.fn, ...)
    if not ok then
        ns.Log("FAIL", "test '" .. name .. "' crashed", err)
    end
end

local function Help()
    print("|cff8080ff[FP Spike]|r commands:")
    print("  /fpspike all          run every test that does not need a window")
    for _, name in ipairs(ns.testOrder) do
        print(("  /fpspike %-12s %s"):format(name, ns.tests[name].desc))
    end
    print("  /fpspike report       open the copyable report")
    print("  /fpspike reset        clear stored results")
end

SLASH_FPSPIKE1 = "/fpspike"
SlashCmdList.FPSPIKE = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "help" then
        Help()
    elseif cmd == "report" then
        ns.ShowReport()
    elseif cmd == "reset" then
        wipe(ns.db.sections); wipe(ns.db.order)
        print("|cff8080ff[FP Spike]|r results cleared.")
    elseif cmd == "all" then
        for _, name in ipairs({ "env", "recipes", "categories", "items", "textures", "questie", "map" }) do
            RunTest(name)
        end
        print("|cff8080ff[FP Spike]|r Now open a profession window (window test runs automatically),")
        print("  visit a recipe vendor (merchant test runs automatically), then /fpspike report.")
    else
        RunTest(cmd, rest)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
ns.events = events
ns.eventHandlers = {}

function ns.On(event, fn)
    if not ns.eventHandlers[event] then
        ns.eventHandlers[event] = {}
        -- Registering an event that doesn't exist throws on Forever; don't let it abort the file.
        local ok, err = pcall(events.RegisterEvent, events, event)
        if not ok then
            ns.pendingWarnings = ns.pendingWarnings or {}
            ns.pendingWarnings[#ns.pendingWarnings + 1] = "event " .. event .. " not registrable: " .. tostring(err)
        end
    end
    table.insert(ns.eventHandlers[event], fn)
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = ns.eventHandlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then
            print("|cffff4040[FP Spike]|r handler error for " .. event .. ": " .. tostring(err))
        end
    end
end)

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ForeverProfessionalSpikeDB = ForeverProfessionalSpikeDB or {}
    local db = ForeverProfessionalSpikeDB
    db.sections = db.sections or {}
    db.order = db.order or {}
    db.known = db.known or {}          -- [professionName] = { recipeID, ... } from window scans
    db.loads = (db.loads or 0) + 1     -- proves SavedVariables round-trip
    ns.db = db
end)

ns.On("PLAYER_LOGIN", function()
    print(("|cff8080ff[FP Spike]|r loaded (SavedVariables load #%d). Type |cffffff00/fpspike all|r to start.")
        :format(ns.db.loads))
    if ns.pendingWarnings then
        for _, w in ipairs(ns.pendingWarnings) do print("|cffffc040[FP Spike]|r " .. w) end
    end
end)

-- Catch protected-action blocks caused by us (e.g. OpenRecipe test).
local function ActionBlocked(event, addon, func)
    if addon == ADDON then
        ns.LogTo(ns.db.order[#ns.db.order] or "env", "FAIL", event, tostring(func))
    end
end
ns.On("ADDON_ACTION_FORBIDDEN", ActionBlocked)
ns.On("ADDON_ACTION_BLOCKED", ActionBlocked)
