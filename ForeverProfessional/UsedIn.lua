-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- "Used in" reagent lines: the reverse reagent index (Model.NewUsedInIndex), read live after login a batch
-- per frame so login doesn't hitch, and its cost for /fp debug.
local _, ns = ...

local UsedIn = {
    BATCH = 40,   -- recipes read per frame
    DELAY = 5,    -- seconds after PLAYER_LOGIN, past the login burst and the character rescan
}
ns.UsedIn = UsedIn

local builder        -- the index, created on the first Start
local running = false
local chain = 0      -- bumped by Start / Stop / Finish, so a stale timer chain ends itself

local function NewStats()
    return { frames = 0, read = 0, missing = 0, items = 0, entries = 0, totalMs = 0, slowestMs = 0,
        wallSeconds = 0, memBefore = 0, memAfter = 0 }
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

local function Begin()
    if builder then return end
    UsedIn.stats = NewStats()
    UsedIn.stats.memBefore = collectgarbage("count")
    UsedIn.stats.started = GetTime()
    builder = ns.Model.NewUsedInIndex()
end

-- One batch, timed. Returns true when the index is complete.
local function StepOnce()
    local s = UsedIn.stats
    local t0 = debugprofilestop()
    local done = builder:Step(UsedIn.BATCH)
    local ms = debugprofilestop() - t0
    s.frames = s.frames + 1
    s.totalMs = s.totalMs + ms
    if ms > s.slowestMs then s.slowestMs = ms end
    s.read, s.missing, s.items, s.entries = builder.read, builder.missing, builder.items, builder.entries
    if done then
        running = false
        s.wallSeconds = GetTime() - s.started
        s.memAfter = collectgarbage("count")
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

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(UsedIn.DELAY, function()
        if ns.Setting("tooltipUsedIn") then UsedIn.Start() end
    end)
end)
