-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Frame-free logic: category tree, filtering, difficulty colours and source descriptions.
local _, ns = ...
local L = ns.L

local M = {}
ns.Model = M

M.OTHER = "other"

-- Names -----------------------------------------------------------------------------

function M.RecipeName(spellID)
    if C_Spell then
        if C_Spell.GetSpellName then
            local n = C_Spell.GetSpellName(spellID)
            if n then return n end
        end
        if C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and info.name then return info.name end
        end
    end
    return nil
end

function M.RecipeDisplayName(spellID)
    return M.RecipeName(spellID) or ("#" .. spellID)
end

local function localized(kind, id)
    local loc = ns.Data.Locale
    return loc and loc[kind] and loc[kind][id]
end

function M.NPCName(id)
    local n = ns.Data.NPCs and ns.Data.NPCs[id]
    return localized("npc", id) or (n and n.name) or ("NPC #" .. id)
end

function M.ObjectName(id)
    local o = ns.Data.Objects and ns.Data.Objects[id]
    return localized("obj", id) or (o and o.name) or ("Object #" .. id)
end

function M.QuestName(id)
    local q = ns.Data.Quests and ns.Data.Quests[id]
    return localized("quest", id) or (q and q.name) or ("Quest #" .. id)
end

-- Zone name for an NPC or object record: uiMap name, else its first area, else its instance.
function M.ZoneName(rec)
    if not rec then return nil end
    if rec.map and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(rec.map)
        if info and info.name and info.name ~= "" then return info.name end
    end
    if rec.areas and rec.areas[1] and C_Map and C_Map.GetAreaInfo then
        local name = C_Map.GetAreaInfo(rec.areas[1])
        if name and name ~= "" then return name end
    end
    if rec.instance and GetRealZoneText then
        local ok, name = pcall(GetRealZoneText, rec.instance)
        if ok and name and name ~= "" then return name end
    end
    return nil
end

function M.FactionName(id)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
        if ok and data and data.name then return data.name end
    end
    if GetFactionInfoByID then
        local ok, name = pcall(GetFactionInfoByID, id)
        if ok and name then return name end
    end
    return "Faction #" .. id
end

function M.StandingName(standing)
    return _G["FACTION_STANDING_LABEL" .. tostring(standing)] or tostring(standing)
end

-- Coin text with the money icons, zero units left out ("1s", not "0g 1s 0c"). Built by hand:
-- the client's GetCoinTextureString isn't there on Forever.
local COIN = "%d|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"

function M.Money(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = COIN:format(g, "Gold") end
    if s > 0 then parts[#parts + 1] = COIN:format(s, "Silver") end
    if c > 0 or #parts == 0 then parts[#parts + 1] = COIN:format(c, "Copper") end
    return table.concat(parts, " ")
end

-- Icons, read live (works for uncached items too).
function M.ItemIcon(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then return icon end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local icon = select(5, C_Item.GetItemInfoInstant(itemID))
        if icon then return icon end
    end
    return nil
end

function M.SpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(spellID)
        if icon then return icon end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.iconID end
    end
    return nil
end

M.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function M.RecipeIcon(spellID, rec)
    return (rec and M.ItemIcon(rec.creates)) or M.SpellIcon(spellID) or M.QUESTION_ICON
end

-- Category tree -------------------------------------------------------------------------
-- node = { id, name, order, children = {node...}, recipes = {spellID...} }

local function SortTree(node)
    table.sort(node.children, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return (a.name or "") < (b.name or "")
    end)
    local recipes = ns.Data.Recipes[node.line] or {}
    local names = {}
    for _, id in ipairs(node.recipes) do names[id] = M.RecipeName(id) or "" end
    table.sort(node.recipes, function(a, b)
        local ra, rb = recipes[a], recipes[b]
        local la, lb = ra and ra.learn or 0, rb and rb.learn or 0
        if la ~= lb then return la < lb end
        if names[a] ~= names[b] then return names[a] < names[b] end
        return a < b
    end)
    for _, child in ipairs(node.children) do
        child.line = node.line
        SortTree(child)
    end
end

function M.BuildTree(line)
    local recipes = ns.Data.Recipes and ns.Data.Recipes[line] or {}
    local cats = ns.Data.Categories or {}
    local root = { id = "root", line = line, children = {}, recipes = {} }
    local nodes = {}
    local other

    local function OtherNode()
        if not other then
            other = { id = M.OTHER, name = L.OTHER, order = math.huge, children = {}, recipes = {} }
            root.children[#root.children + 1] = other
        end
        return other
    end

    -- Node for a category; nil when the category is unknown or is the profession root.
    local function NodeFor(catID, depth)
        if nodes[catID] then return nodes[catID] end
        local c = cats[catID]
        if not c or not c.parent or depth > 20 then return nil end
        local parent = NodeFor(c.parent, depth + 1) or root
        local node = { id = catID, name = c.name, order = c.order or 0, children = {}, recipes = {} }
        parent.children[#parent.children + 1] = node
        nodes[catID] = node
        return node
    end

    for spellID, rec in pairs(recipes) do
        local node = rec.cat and NodeFor(rec.cat, 0) or OtherNode()
        node.recipes[#node.recipes + 1] = spellID
    end
    SortTree(root)
    return root
end

-- Flatten the tree into display entries:
--   { kind = "header", cat, name, depth, count, learned, collapsed }
--   { kind = "recipe", id, depth }
-- opts: filter ("all" | "learned" | "missing"), search (text), collapsed ({[cat]=true}), isLearned (fn).
-- Returns entries, matching recipe count, matching learned count.
function M.Flatten(tree, opts)
    opts = opts or {}
    local filter = opts.filter or "all"
    local isLearned = opts.isLearned or function() return false end
    local search = opts.search and strtrim(opts.search):lower() or ""
    if search == "" then search = nil end
    local collapsed = opts.collapsed or {}

    local function Match(id)
        local learned = isLearned(id) and true or false
        if filter == "learned" and not learned then return false end
        if filter == "missing" and learned then return false end
        if search then
            local name = M.RecipeName(id)
            if not name or not name:lower():find(search, 1, true) then return false end
        end
        return true, learned
    end

    local function Walk(node, depth)
        local body, count, learnedCount = {}, 0, 0
        for _, id in ipairs(node.recipes) do
            local ok, learned = Match(id)
            if ok then
                count = count + 1
                if learned then learnedCount = learnedCount + 1 end
                body[#body + 1] = { kind = "recipe", id = id, depth = depth }
            end
        end
        for _, child in ipairs(node.children) do
            local sub, c, l = Walk(child, depth + 1)
            if c > 0 then
                count, learnedCount = count + c, learnedCount + l
                local isCollapsed = (not search) and collapsed[child.id] and true or false
                body[#body + 1] = { kind = "header", cat = child.id, name = child.name, depth = depth,
                    count = c, learned = l, collapsed = isCollapsed }
                if not isCollapsed then
                    for _, e in ipairs(sub) do body[#body + 1] = e end
                end
            end
        end
        return body, count, learnedCount
    end

    return Walk(tree, 0)
end

-- Every category id of a tree, at any depth, in tree order (for collapse all / expand all).
function M.CategoryIDs(tree)
    local out = {}
    local function Walk(node)
        for _, child in ipairs(node.children or {}) do
            out[#out + 1] = child.id
            Walk(child)
        end
    end
    Walk(tree)
    return out
end

-- Recipe count of a profession and how many isLearned(id) says are learned.
function M.FilterCounts(line, isLearned)
    local total, learned = 0, 0
    for id in pairs(ns.Data.Recipes and ns.Data.Recipes[line] or {}) do
        total = total + 1
        if isLearned(id) then learned = learned + 1 end
    end
    return total, learned
end

-- Difficulty ------------------------------------------------------------------------------

M.COLORS = {
    red = "ff2020", orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "808080",
    neutral = "ffffff",
}

-- Colour of a recipe for the given skill; "neutral" when the skill is unknown.
function M.Difficulty(rec, skill)
    if not skill then return "neutral" end
    if rec.learn and skill < rec.learn then return "red" end
    if not rec.grey then return "orange" end
    if rec.yellow and skill < rec.yellow then return "orange" end
    if rec.green and skill < rec.green then return "yellow" end
    if skill < rec.grey then return "green" end
    return "grey"
end

local function Colored(color, text)
    return "|cff" .. M.COLORS[color] .. tostring(text) .. "|r"
end
M.Colored = Colored

-- "learn yellow green grey", each in its colour. The learn value is red when it's out of reach.
function M.RangeText(rec, skill)
    local parts = {}
    if rec.learn then
        parts[#parts + 1] = Colored((skill and skill < rec.learn) and "red" or "orange", rec.learn)
    end
    if rec.grey then
        if rec.yellow then parts[#parts + 1] = Colored("yellow", rec.yellow) end
        if rec.green then parts[#parts + 1] = Colored("green", rec.green) end
        parts[#parts + 1] = Colored("grey", rec.grey)
    end
    return table.concat(parts, " ")
end

-- Sources ---------------------------------------------------------------------------------
-- Shared helpers for the rows' primary source and the detail pane's source cards (below).

local function Has(list, value)
    if not list then return false end
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end
M.Has = Has

local FACTION_TAG = {
    A = "|cff4a9eff" .. L.ALLIANCE .. "|r",
    H = "|cffff4040" .. L.HORDE .. "|r",
}

local function Waypoint(rec, name)
    if rec and rec.map and rec.x and rec.y then
        return { map = rec.map, x = rec.x, y = rec.y, name = name }
    end
end

local function Coords(rec)
    if rec and rec.x and rec.y then return (" (%.1f, %.1f)"):format(rec.x, rec.y) end
    return ""
end

local function Rate(chance)
    if chance then return ("%s%%"):format((("%.2f"):format(chance):gsub("%.?0+$", ""))) end
    return L.RATE_UNKNOWN
end

local TYPE_LABEL = {
    vendor = L.TYPE_VENDOR, drop = L.TYPE_DROP, quest = L.TYPE_QUEST, trainer = L.TYPE_TRAINER,
    object = L.TYPE_OBJECT, container = L.TYPE_CONTAINER,
}

-- Detail pane order: what you need first depends on whether the recipe is known.
function M.DetailOrder(learned)
    if learned then return { "reagents", "characters", "sources" } end
    return { "sources", "characters", "reagents" }
end

-- Rows ------------------------------------------------------------------------------------
-- The recipe list's second line: learn level and the easiest way to get a missing recipe.

M.SEP = " · "

local SIDE_LETTER = { Alliance = "A", Horde = "H" }

-- Can a character of `faction` ("Horde"/"Alliance"/nil) use this NPC? Unknown factions count as usable.
function M.Usable(npcID, faction)
    local npc = ns.Data.NPCs and ns.Data.NPCs[npcID]
    local f = npc and npc.faction
    if not f or f == "AH" or not faction then return true end
    return f == SIDE_LETTER[faction]
end

-- Easiest first.
local PRIMARY_ORDER = { "auto", "trainer", "vendor", "quest", "drop", "object", "container", "crafted", "worldObject" }

local function Count(list, total)
    if total then return total end
    return list and #list or 0
end

-- Number of source entries of type t (a type claimed only through `unverified` counts 1).
local function Entries(rec, t)
    local n = 0
    if t == "auto" or t == "crafted" or t == "worldObject" then n = 1
    elseif t == "trainer" then n = 1
    elseif t == "vendor" then n = Count(rec.vendors)
    elseif t == "quest" then n = Count(rec.quests)
    elseif t == "drop" then n = Count(rec.drops, rec.dropTotal)
    elseif t == "object" then n = Count(rec.objects, rec.objectTotal)
    elseif t == "container" then n = Count(rec.containers, rec.containerTotal)
    end
    return math.max(n, 1)
end

-- "Name (Zone)", or just the name when the zone is unknown.
local function NPCWhere(npcID)
    local name = M.NPCName(npcID)
    local zone = M.ZoneName(ns.Data.NPCs and ns.Data.NPCs[npcID])
    if zone then return ("%s (%s)"):format(name, zone) end
    return name
end

-- The first NPC usable by `faction`, else the first one with the other side's name appended.
local function PickNPC(ids, faction)
    for _, id in ipairs(ids) do
        if M.Usable(id, faction) then return NPCWhere(id) end
    end
    local id = ids[1]
    local npc = ns.Data.NPCs and ns.Data.NPCs[id]
    local side = npc and (npc.faction == "A" and L.ALLIANCE or npc.faction == "H" and L.HORDE)
    return NPCWhere(id) .. (side and (M.SEP .. side) or "")
end

local function ContainerName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    return name or L.A_CONTAINER
end

local function PrimaryText(rec, t, faction)
    local function Unverified() return L.UNVERIFIED:format(TYPE_LABEL[t] or t) end
    if t == "auto" then return L.SRC_AUTO_SHORT end
    if t == "crafted" then return L.SRC_CRAFTED end
    if t == "worldObject" then return L.SRC_WORLDOBJECT end
    if t == "trainer" then
        return rec.trainer and L.ROW_TRAINER:format(M.Money(rec.trainer)) or L.SRC_TRAINER
    end
    if t == "vendor" then
        if not (rec.vendors and rec.vendors[1]) then return Unverified() end
        return L.ROW_VENDOR:format(PickNPC(rec.vendors, faction))
    end
    if t == "drop" then
        if not (rec.drops and rec.drops[1]) then return Unverified() end
        local ids = {}
        for i, d in ipairs(rec.drops) do ids[i] = d[1] end
        return L.ROW_DROP:format(PickNPC(ids, faction))
    end
    if t == "quest" then
        if not (rec.quests and rec.quests[1]) then return Unverified() end
        return L.ROW_QUEST:format(M.QuestName(rec.quests[1]))
    end
    if t == "object" then
        if not (rec.objects and rec.objects[1]) then return Unverified() end
        return L.ROW_OBJECT:format(M.ObjectName(rec.objects[1][1]))
    end
    if t == "container" then
        if not (rec.containers and rec.containers[1]) then return Unverified() end
        return L.ROW_CONTAINER:format(ContainerName(rec.containers[1][1]))
    end
end

-- The easiest source of a recipe for a character of `faction`:
-- { type, text, more } where `more` counts the record's other source entries.
function M.PrimarySource(rec, faction)
    local src = rec.src or {}
    local primary, total = nil, 0
    for _, t in ipairs(PRIMARY_ORDER) do
        if Has(src, t) or (t == "trainer" and rec.trainer) then
            primary = primary or t
            total = total + Entries(rec, t)
        end
    end
    if not primary then return { type = "unknown", text = L.SRC_UNKNOWN, more = 0 } end
    return { type = primary, text = PrimaryText(rec, primary, faction), more = math.max(0, total - 1) }
end

-- Source cards ---------------------------------------------------------------------------
-- The detail pane's "Where to get it":
--   { teach = {itemID...}, cards = {card...}, requirements = {string...}, notes = {string...} }
--   card = { type, title, detail, waypoint = {map, x, y, name}, item = itemID, instance = boolean }
-- Cards follow PRIMARY_ORDER (easiest first); vendors and drops list what `faction` can use first.

-- Join the non-empty arguments with M.SEP.
local function JoinSep(...)
    local out = {}
    for i = 1, select("#", ...) do
        local p = select(i, ...)
        if p and p ~= "" then out[#out + 1] = p end
    end
    return table.concat(out, M.SEP)
end

-- ids reordered so the ones `faction` can use come first, data order kept within each group.
local function UsableFirst(entries, faction, idOf)
    local first, rest = {}, {}
    for _, e in ipairs(entries) do
        if M.Usable(idOf(e), faction) then first[#first + 1] = e else rest[#rest + 1] = e end
    end
    for _, e in ipairs(rest) do first[#first + 1] = e end
    return first
end

local function ZoneAt(rec)
    local zone = M.ZoneName(rec)
    return zone and (zone .. Coords(rec)) or nil
end

local function NPCCard(kind, npcID, rate)
    local npc = ns.Data.NPCs and ns.Data.NPCs[npcID]
    local name = M.NPCName(npcID)
    local title = (npc and npc.sub) and (name .. " <" .. npc.sub .. ">") or name
    return {
        type = kind, title = title,
        detail = JoinSep(rate, npc and FACTION_TAG[npc.faction], ZoneAt(npc)),
        waypoint = Waypoint(npc, name),
        instance = (npc and npc.instance and not npc.map) and true or false,
    }
end

local function MoreCard(shown, total)
    if total and total > shown then return { type = "more", title = L.MORE:format(total - shown) } end
end

function M.SourceCards(rec, faction)
    local out = { teach = {}, cards = {}, requirements = {}, notes = {} }
    local cards = out.cards
    local function Add(card) if card then cards[#cards + 1] = card end end
    local src = rec.src or {}

    if type(rec.teach) == "table" then
        for _, id in ipairs(rec.teach) do out.teach[#out.teach + 1] = id end
    elseif rec.teach then
        out.teach[1] = rec.teach
    end

    if Has(src, "auto") then Add({ type = "auto", title = L.SRC_AUTO }) end
    if rec.trainer or Has(src, "trainer") then
        Add({ type = "trainer", title = L.SRC_TRAINER, detail = rec.trainer and M.Money(rec.trainer) or nil })
    end
    for _, id in ipairs(UsableFirst(rec.vendors or {}, faction, function(id) return id end)) do
        Add(NPCCard("vendor", id))
    end
    for _, qid in ipairs(rec.quests or {}) do
        local q = ns.Data.Quests and ns.Data.Quests[qid]
        local title = M.QuestName(qid)
        if q and q.level and q.level > 0 then title = L.QUEST_LEVEL:format(q.level, title) end
        local names, where, waypoint = {}, nil, nil
        for _, npcID in ipairs(q and q.npcs or {}) do
            names[#names + 1] = M.NPCName(npcID)
            local npc = ns.Data.NPCs and ns.Data.NPCs[npcID]
            if not waypoint then
                waypoint = Waypoint(npc, M.NPCName(npcID))
                if waypoint then where = npc end
            end
        end
        Add({
            type = "quest", title = title,
            detail = JoinSep(#names > 0 and L.QUEST_GIVER:format(table.concat(names, ", ")) or nil, ZoneAt(where)),
            waypoint = waypoint,
        })
    end
    if rec.drops and #rec.drops > 0 then
        for _, d in ipairs(UsableFirst(rec.drops, faction, function(d) return d[1] end)) do
            Add(NPCCard("drop", d[1], Rate(d[2])))
        end
        Add(MoreCard(#rec.drops, rec.dropTotal))
    end
    if rec.objects and #rec.objects > 0 then
        for _, o in ipairs(rec.objects) do
            local obj = ns.Data.Objects and ns.Data.Objects[o[1]]
            local name = M.ObjectName(o[1])
            Add({ type = "object", title = name, detail = JoinSep(Rate(o[2]), ZoneAt(obj)), waypoint = Waypoint(obj, name) })
        end
        Add(MoreCard(#rec.objects, rec.objectTotal))
    end
    if rec.containers and #rec.containers > 0 then
        for _, c in ipairs(rec.containers) do
            Add({ type = "container", item = c[1], detail = Rate(c[2]) })
        end
        Add(MoreCard(#rec.containers, rec.containerTotal))
    end
    if Has(src, "crafted") then Add({ type = "crafted", title = L.SRC_CRAFTED }) end
    if Has(src, "worldObject") then Add({ type = "worldObject", title = L.SRC_WORLDOBJECT }) end

    for _, t in ipairs(rec.unverified or {}) do
        out.notes[#out.notes + 1] = L.UNVERIFIED:format(TYPE_LABEL[t] or t)
    end
    if rec.unknown then out.notes[#out.notes + 1] = L.SRC_UNKNOWN end

    local req = out.requirements
    if rec.rep then req[#req + 1] = L.REP:format(M.FactionName(rec.rep[1]), M.StandingName(rec.rep[2])) end
    if rec.favor then req[#req + 1] = L.FAVOR:format(rec.favor) end
    if rec.side then
        req[#req + 1] = L.SIDE_ONLY:format(rec.side == "Alliance" and L.ALLIANCE or rec.side == "Horde" and L.HORDE or rec.side)
    end
    return out
end

-- Second line of a recipe row. Learned: the four thresholds. Missing: "Learn N · <source> · +N more",
-- with the learn level in red when the character's skill is known and too low.
function M.RowSubtitle(rec, skill, learned, faction)
    if learned then return M.RangeText(rec, skill) end
    local parts = {}
    if rec.learn and rec.learn > 0 then
        local text = L.LEARN:format(rec.learn)
        if skill and skill < rec.learn then text = Colored("red", text) end
        parts[#parts + 1] = text
    end
    local p = M.PrimarySource(rec, faction)
    parts[#parts + 1] = p.text
    if p.more > 0 then parts[#parts + 1] = L.MORE:format(p.more) end
    return table.concat(parts, M.SEP)
end
