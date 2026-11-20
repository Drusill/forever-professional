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

function M.Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    return ("%dg %ds %dc"):format(g, s, c)
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

-- Difficulty ------------------------------------------------------------------------------

M.COLORS = {
    red = "ff2020", orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "808080",
    neutral = "ffd200",
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
-- SourceLines returns display lines:
--   { kind = "section", text }             section title
--   { kind = "text", text, indent, waypoint = { map, x, y, name } }
--   { kind = "item", item = itemID, suffix, indent }   item name resolved by the UI
--   { kind = "note", text }                warning / gap

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

-- Join the non-empty arguments (any of them may be nil) with " - ".
local function Join(...)
    local out = {}
    for i = 1, select("#", ...) do
        local p = select(i, ...)
        if p and p ~= "" then out[#out + 1] = p end
    end
    return table.concat(out, " - ")
end

local function Rate(chance)
    if chance then return ("%s%%"):format((("%.2f"):format(chance):gsub("%.?0+$", ""))) end
    return L.RATE_UNKNOWN
end

local TYPE_LABEL = {
    vendor = L.TYPE_VENDOR, drop = L.TYPE_DROP, quest = L.TYPE_QUEST, trainer = L.TYPE_TRAINER,
    object = L.TYPE_OBJECT, container = L.TYPE_CONTAINER,
}

function M.NPCLine(npcID, extra, indent)
    local npc = ns.Data.NPCs and ns.Data.NPCs[npcID]
    local name = M.NPCName(npcID)
    local label = name
    if npc and npc.sub then label = label .. " <" .. npc.sub .. ">" end
    local zone = M.ZoneName(npc)
    if zone then zone = zone .. Coords(npc) end
    if npc and npc.instance and not npc.map then zone = (zone or "") .. " (" .. L.INSTANCE .. ")" end
    local faction = npc and FACTION_TAG[npc.faction]
    return { kind = "text", text = Join(label, extra, faction, zone), indent = indent or 1,
        waypoint = Waypoint(npc, name) }
end

function M.SourceLines(rec)
    local lines = {}
    local function Add(line) lines[#lines + 1] = line end
    local src = rec.src or {}

    if Has(src, "auto") then Add({ kind = "text", text = L.SRC_AUTO, indent = 0 }) end

    if rec.trainer then
        Add({ kind = "text", text = L.SRC_TRAINER_COST:format(M.Money(rec.trainer)), indent = 0 })
    elseif Has(src, "trainer") then
        Add({ kind = "text", text = L.SRC_TRAINER, indent = 0 })
    end

    if rec.vendors and #rec.vendors > 0 then
        Add({ kind = "section", text = L.SRC_VENDORS })
        for _, id in ipairs(rec.vendors) do Add(M.NPCLine(id)) end
    end

    if rec.drops and #rec.drops > 0 then
        Add({ kind = "section", text = L.SRC_DROPS })
        for _, d in ipairs(rec.drops) do Add(M.NPCLine(d[1], Rate(d[2]))) end
        if rec.dropTotal and rec.dropTotal > #rec.drops then
            Add({ kind = "text", text = L.MORE:format(rec.dropTotal - #rec.drops), indent = 1 })
        end
    end

    if rec.objects and #rec.objects > 0 then
        Add({ kind = "section", text = L.SRC_OBJECTS })
        for _, o in ipairs(rec.objects) do
            local obj = ns.Data.Objects and ns.Data.Objects[o[1]]
            local name = M.ObjectName(o[1])
            local zone = M.ZoneName(obj)
            if zone then zone = zone .. Coords(obj) end
            Add({ kind = "text", text = Join(name, Rate(o[2]), zone), indent = 1, waypoint = Waypoint(obj, name) })
        end
        if rec.objectTotal and rec.objectTotal > #rec.objects then
            Add({ kind = "text", text = L.MORE:format(rec.objectTotal - #rec.objects), indent = 1 })
        end
    end

    if rec.containers and #rec.containers > 0 then
        Add({ kind = "section", text = L.SRC_CONTAINERS })
        for _, c in ipairs(rec.containers) do
            Add({ kind = "item", item = c[1], suffix = Rate(c[2]), indent = 1 })
        end
        if rec.containerTotal and rec.containerTotal > #rec.containers then
            Add({ kind = "text", text = L.MORE:format(rec.containerTotal - #rec.containers), indent = 1 })
        end
    end

    if rec.quests and #rec.quests > 0 then
        Add({ kind = "section", text = L.SRC_QUESTS })
        for _, qid in ipairs(rec.quests) do
            local q = ns.Data.Quests and ns.Data.Quests[qid]
            local name = M.QuestName(qid)
            if q and q.level and q.level > 0 then name = L.QUEST_LEVEL:format(q.level, name) end
            Add({ kind = "text", text = name, indent = 1 })
            for _, npcID in ipairs(q and q.npcs or {}) do
                local line = M.NPCLine(npcID, nil, 2)
                line.text = L.QUEST_GIVER:format(line.text)
                Add(line)
            end
        end
    end

    if Has(src, "crafted") then Add({ kind = "text", text = L.SRC_CRAFTED, indent = 0 }) end
    if Has(src, "worldObject") then Add({ kind = "text", text = L.SRC_WORLDOBJECT, indent = 0 }) end

    for _, t in ipairs(rec.unverified or {}) do
        Add({ kind = "note", text = L.UNVERIFIED:format(TYPE_LABEL[t] or t) })
    end
    if rec.unknown then Add({ kind = "note", text = L.SRC_UNKNOWN }) end

    -- Requirements
    local req = {}
    if rec.rep then
        req[#req + 1] = L.REP:format(M.FactionName(rec.rep[1]), M.StandingName(rec.rep[2]))
    end
    if rec.favor then req[#req + 1] = L.FAVOR:format(rec.favor) end
    if rec.side then
        req[#req + 1] = L.SIDE_ONLY:format(rec.side == "Alliance" and L.ALLIANCE or rec.side == "Horde" and L.HORDE or rec.side)
    end
    if #req > 0 then
        Add({ kind = "section", text = L.REQUIREMENTS })
        for _, r in ipairs(req) do Add({ kind = "text", text = r, indent = 1 }) end
    end

    return lines
end
