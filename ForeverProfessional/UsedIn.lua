-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- "Used in" reagent lines: the reverse reagent index (Model.NewUsedInIndex), read live after login a batch
-- per frame so login doesn't hitch, and its cost for /fp debug.
local _, ns = ...

local UsedIn = {
    BATCH = 100,      -- most recipes read per frame
    BUDGET_MS = 4,    -- a frame stops reading once it has spent this long
    DELAY = 5,        -- seconds after PLAYER_LOGIN, past the login burst and the character rescan
}
ns.UsedIn = UsedIn

local builder        -- the index, created on the first Start
local running = false
local chain = 0      -- bumped by Start / Stop / Finish, so a stale timer chain ends itself

local function NewStats()
    return { frames = 0, read = 0, missing = 0, items = 0, entries = 0, totalMs = 0, slowestMs = 0,
        slowestRecipeMs = 0, setupMs = 0, wallSeconds = 0, memBefore = 0, memAfter = 0 }
end
UsedIn.stats = NewStats()

function UsedIn.Ready() return builder ~= nil and builder:Done() end
function UsedIn.Building() return running end
function UsedIn.Index() return builder end

-- An item's { {line, spellID}... }, nil until the index is complete.
function UsedIn.Lookup(itemID)
    if not UsedIn.Ready() then return nil end
    return builder:Lookup(itemID)
end

-- Memory in KB and where it came from: this addon's own usage when the client reports it (the update scans
-- every addon, so it runs at the start and the end only, never per batch), else the whole Lua state.
local function Memory()
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if UpdateAddOnMemoryUsage and get then
        local ok = pcall(UpdateAddOnMemoryUsage)
        local okGet, kb = pcall(get, "ForeverProfessional")
        if ok and okGet and type(kb) == "number" then return kb, "addon" end
    end
    return collectgarbage("count"), "lua"
end

local function Begin()
    if builder then return end
    UsedIn.stats = NewStats()
    UsedIn.stats.memBefore, UsedIn.stats.memSource = Memory()
    UsedIn.stats.started = GetTime()
    -- Listing and ordering the recipes is a frame of its own, counted like the batches.
    local t0 = debugprofilestop()
    builder = ns.Model.NewUsedInIndex()
    local ms = debugprofilestop() - t0
    UsedIn.stats.frames, UsedIn.stats.totalMs, UsedIn.stats.slowestMs, UsedIn.stats.setupMs = 1, ms, ms, ms
end

-- One frame's batch: recipes one at a time, until BATCH are read or BUDGET_MS is spent, each timed so the
-- slowest recipe shows in /fp debug. Returns true when the index is complete.
local function StepOnce()
    local s = UsedIn.stats
    local t0 = debugprofilestop()
    local done, n, now = false, 0, t0
    repeat
        local r0 = debugprofilestop()
        done = builder:Step(1)
        now = debugprofilestop()
        n = n + 1
        if now - r0 > s.slowestRecipeMs then
            s.slowestRecipeMs, s.slowestRecipeSpell = now - r0, builder.last
        end
    until done or n >= UsedIn.BATCH or now - t0 >= UsedIn.BUDGET_MS
    local ms = now - t0
    s.frames = s.frames + 1
    s.totalMs = s.totalMs + ms
    if ms > s.slowestMs then s.slowestMs = ms end
    s.read, s.missing, s.items, s.entries = builder.read, builder.missing, builder.items, builder.entries
    if done then
        running = false
        s.wallSeconds = GetTime() - s.started
        s.memAfter = Memory()
    end
    return done
end

-- Build in the background, a batch per frame. Resumes a stopped build; does nothing once complete.
function UsedIn.Start()
    if running or UsedIn.Ready() then return end
    Begin()
    running = true
    chain = chain + 1
    local mine = chain
    local function tick()
        if mine ~= chain then return end
        if not StepOnce() then C_Timer.After(0, tick) end
    end
    C_Timer.After(0, tick)
end

-- Stop at the next frame; the partial index is kept for a later Start.
function UsedIn.Stop()
    running = false
    chain = chain + 1
end

-- Complete the index now, batch by batch (tests).
function UsedIn.Finish()
    if UsedIn.Ready() then return end
    Begin()
    chain = chain + 1
    running = true
    while not StepOnce() do end
end

-- Counting -----------------------------------------------------------------------------------------

-- Who holds each profession: { [line] = { [faction] = true } }, over every saved character.
local function Holders()
    local out = {}
    for _, c in pairs(ns.db and ns.db.chars or {}) do
        for line in pairs(c.professions or {}) do
            out[line] = out[line] or {}
            if c.faction then out[line][c.faction] = true end
        end
    end
    return out
end

local function KnownByAnyone(spellID)
    for _, c in pairs(ns.db and ns.db.chars or {}) do
        if c.learned and c.learned[spellID] then return true end
    end
    return false
end

local function ProfessionName(line)
    local p = ns.Data.Professions and ns.Data.Professions[line]
    return p and p.name or tostring(line)
end

-- The recipes using an item, per profession any of your characters holds:
-- { {line, total, known, recipes = { {spellID, known}... }}... }, nil until the index is complete.
-- A recipe counts when someone knows it, or it isn't locked to a side, or a holder of the profession is of
-- its side. The logged-in character's professions come first, then by name; recipes by skill, then name.
function ns.UsedInGroups(itemID)
    local uses = UsedIn.Lookup(itemID)
    if not UsedIn.Ready() then return nil end
    local out = {}
    if not uses then return out end
    local holders = Holders()
    local me = ns.GetChar()
    local mine = me and me.professions or {}
    local byLine = {}
    for _, u in ipairs(uses) do
        local sides = holders[u.line]
        local rec = sides and ns.Data.Recipes[u.line] and ns.Data.Recipes[u.line][u.spellID]
        if rec then
            local known = KnownByAnyone(u.spellID)
            if known or not rec.side or sides[rec.side] then
                local g = byLine[u.line]
                if not g then
                    g = { line = u.line, total = 0, known = 0, recipes = {} }
                    byLine[u.line] = g
                    out[#out + 1] = g
                end
                g.total = g.total + 1
                if known then g.known = g.known + 1 end
                g.recipes[#g.recipes + 1] = { spellID = u.spellID, known = known,
                    learn = rec.learn or 0, name = ns.Model.RecipeDisplayName(u.spellID) }
            end
        end
    end
    table.sort(out, function(a, b)
        local ma, mb = mine[a.line] ~= nil, mine[b.line] ~= nil
        if ma ~= mb then return ma end
        return ProfessionName(a.line) < ProfessionName(b.line)
    end)
    for _, g in ipairs(out) do
        table.sort(g.recipes, function(a, b)
            if a.learn ~= b.learn then return a.learn < b.learn end
            if a.name ~= b.name then return a.name < b.name end
            return a.spellID < b.spellID
        end)
    end
    return out
end

-- Tooltip lines --------------------------------------------------------------------------------------

UsedIn.NAMES_MAX = 10   -- recipe names listed per profession with Shift
local GREY, DIM, WHITE = { 0.75, 0.75, 0.75 }, { 0.5, 0.5, 0.5 }, { 1, 1, 1 }

local function Line(out, text, c)
    out[#out + 1] = { text = text, r = c[1], g = c[2], b = c[3] }
end

-- { {text, r, g, b}... }: "Used in" per profession; with shift, the recipe names under each (known in
-- white), else a hint that Shift lists them. Names and hint only with the tooltipUsedInNames setting.
-- {} before the index is complete or when nothing of yours uses the item.
local function TimeHover(t0)
    local s, ms = UsedIn.stats, debugprofilestop() - t0
    if not s.firstHoverMs then s.firstHoverMs = ms end
    if not s.slowestHoverMs or ms > s.slowestHoverMs then s.slowestHoverMs = ms end
end

function ns.UsedInLines(itemID, shift)
    local L, out = ns.L, {}
    if not UsedIn.Ready() then return out end
    local t0 = debugprofilestop()
    local groups = ns.UsedInGroups(itemID)
    if #groups == 0 then
        TimeHover(t0)
        return out
    end
    local names = ns.Setting("tooltipUsedInNames")
    for _, g in ipairs(groups) do
        local prof = ProfessionName(g.line)
        if g.total == 1 then
            Line(out, L.USED_IN_ONE:format(prof, g.known), GREY)
        else
            Line(out, L.USED_IN:format(g.total, prof, g.known), GREY)
        end
        if names and shift then
            for i, r in ipairs(g.recipes) do
                if i > UsedIn.NAMES_MAX then
                    Line(out, "  " .. L.NEEDED_MORE:format(#g.recipes - UsedIn.NAMES_MAX), DIM)
                    break
                end
                Line(out, "  " .. r.name, r.known and WHITE or DIM)
            end
        end
    end
    if names and not shift then Line(out, L.USED_IN_HINT, DIM) end
    TimeHover(t0)
    return out
end

-- /fp debug -------------------------------------------------------------------------------------------

local function Round(x) return math.floor(x + 0.5) end

-- What the index itself keeps, in KB: a second copy is built (synchronously) right after a full garbage
-- collection that measured `before`, then collected and measured again, so nothing else the addon
-- allocated since login is counted. The copy is dropped after.
local function MeasureIndexCopy(before)
    local copy = ns.Model.NewUsedInIndex()
    while not copy:Step(UsedIn.BATCH) do end
    collectgarbage("collect")
    local after = Memory()
    copy = nil
    return after - before
end

-- The index's state and cost, as chat lines: build time per frame, memory and the first hover. With `gc`
-- (a short freeze): "now" after a full garbage collection, then the index's own size from a second copy.
-- Right after the build, the memory count still holds the client's schematic tables waiting for the
-- collector, and the addon's memory over the build start counts everything else it allocated since.
function UsedIn.DebugLines(gc)
    local L, s, out = ns.L, UsedIn.stats, {}
    if not ns.Setting("tooltipUsedIn") then
        out[1] = L.DEBUG_OFF
        return out
    end
    if not builder then
        out[1] = L.DEBUG_NOT_STARTED:format(UsedIn.DELAY)
        return out
    end
    if not UsedIn.Ready() then
        out[1] = L.DEBUG_BUILDING:format(s.read, builder.total)
        return out
    end
    out[#out + 1] = L.DEBUG_READY
    out[#out + 1] = L.DEBUG_COST:format(s.totalMs, s.frames, s.slowestMs, s.wallSeconds)
    out[#out + 1] = L.DEBUG_SLOWEST:format(s.slowestRecipeMs, s.slowestRecipeSpell or 0, s.setupMs)
    out[#out + 1] = L.DEBUG_COUNTS:format(s.read, s.missing, s.items, s.entries)
    local before, after = Round(s.memBefore), Round(s.memAfter)
    local label = s.memSource == "addon" and L.DEBUG_ADDON_MEMORY or L.DEBUG_LUA_MEMORY
    out[#out + 1] = L.DEBUG_MEMORY:format(label, before, after, after - before)
    if gc then collectgarbage("collect") end
    local nowKB, source = Memory()
    local now = Round(nowKB)
    label = source == "addon" and L.DEBUG_ADDON_MEMORY or L.DEBUG_LUA_MEMORY
    out[#out + 1] = (gc and L.DEBUG_MEMORY_GC or L.DEBUG_MEMORY_NOW):format(label, now, now - before)
    if gc then out[#out + 1] = L.DEBUG_INDEX_KEPT:format(Round(MeasureIndexCopy(nowKB))) end
    if s.firstHoverMs then
        out[#out + 1] = L.DEBUG_HOVER:format(s.firstHoverMs, s.slowestHoverMs)
    else
        out[#out + 1] = L.DEBUG_NO_HOVER
    end
    return out
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(UsedIn.DELAY, function()
        if ns.Setting("tooltipUsedIn") then UsedIn.Start() end
    end)
end)
