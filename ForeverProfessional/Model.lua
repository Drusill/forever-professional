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
-- opts: predicates (list of fn(id, rec, learned) -> bool, all must pass), search (text),
-- collapsed ({[cat]=true}), isLearned (fn).
-- Returns entries, matching recipe count, matching learned count.
function M.Flatten(tree, opts)
    opts = opts or {}
    local predicates = opts.predicates or {}
    local isLearned = opts.isLearned or function() return false end
    local search = opts.search and strtrim(opts.search):lower() or ""
    if search == "" then search = nil end
    local collapsed = opts.collapsed or {}
    local recipes = ns.Data.Recipes and ns.Data.Recipes[tree.line] or {}

    local function Match(id)
        local learned = isLearned(id) and true or false
        local rec = recipes[id] or {}
        for _, pass in ipairs(predicates) do
            if not pass(id, rec, learned) then return false end
        end
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

-- Recipe count of a profession and how many isLearned(id) says are learned, counting only the
-- recipes every predicate passes (nil or empty: all).
function M.FilterCounts(line, isLearned, predicates)
    local total, learned = 0, 0
    for id, rec in pairs(ns.Data.Recipes and ns.Data.Recipes[line] or {}) do
        local isIt = isLearned(id) and true or false
        local ok = true
        for _, pass in ipairs(predicates or {}) do
            if not pass(id, rec, isIt) then ok = false break end
        end
        if ok then
            total = total + 1
            if isIt then learned = learned + 1 end
        end
    end
    return total, learned
end

-- Filters ---------------------------------------------------------------------------------------
-- A predicate is fn(id, rec, learned) -> bool. Flatten and FilterCounts keep the recipes every
-- predicate passes: the All / Learned / Missing choice is one, each filter menu group another.

-- Predicate for the All / Learned / Missing choice; nil for "all".
function M.LearnedPredicate(filter)
    if filter == "learned" then return function(_, _, learned) return learned end end
    if filter == "missing" then return function(_, _, learned) return not learned end end
    return nil
end

-- The filter menu: groups in menu order. Items of a group combine with OR, groups with AND.
-- Status items need the shown character to have the profession.
M.FILTER_GROUPS = {
    { key = "status", items = { "skillups", "learnable" }, needsProfession = true },
    { key = "source", items = { "trainer", "vendor", "drop", "quest", "other", "unknown" } },
    { key = "new", items = { "new" } },
}

-- Source type -> filter menu key. Types not listed here (container, object, crafted,
-- worldObject, and any future one) are "other".
local SOURCE_KEY = { trainer = "trainer", auto = "trainer", vendor = "vendor", drop = "drop", quest = "quest" }

-- Filter menu source keys of a recipe, as a set. A recipe with no source type is "unknown".
function M.SourceKeys(rec)
    local keys, any = {}, false
    for _, t in ipairs(rec.src or {}) do
        keys[SOURCE_KEY[t] or "other"] = true
        any = true
    end
    if not any then keys.unknown = true end
    return keys
end

local SKILLUP_COLORS = { orange = true, yellow = true, green = true }

-- One test per menu item: fn(rec, learned, ctx) -> bool.
local ITEM_TESTS = {
    skillups = function(rec, learned, ctx) return learned and SKILLUP_COLORS[M.Difficulty(rec, ctx.skill, learned)] or false end,
    learnable = function(rec, learned, ctx) return not learned and ns.CanLearnNow(rec, ctx.skill, ctx.faction) end,
    new = function(rec) return rec.new and true or false end,
}
for _, key in ipairs(M.FILTER_GROUPS[2].items) do
    ITEM_TESTS[key] = function(rec) return M.SourceKeys(rec)[key] or false end
end

-- Predicates for the checked menu items (filters = {[item]=true}), one per group with a checked
-- item. ctx = { skill, faction } of the shown character; without a skill the status group is left out.
function M.FilterPredicates(filters, ctx)
    filters, ctx = filters or {}, ctx or {}
    local out = {}
    for _, group in ipairs(M.FILTER_GROUPS) do
        if ctx.skill or not group.needsProfession then
            local tests = {}
            for _, key in ipairs(group.items) do
                if filters[key] then tests[#tests + 1] = ITEM_TESTS[key] end
            end
            if #tests > 0 then
                out[#out + 1] = function(_, rec, learned)
                    for _, test in ipairs(tests) do
                        if test(rec, learned, ctx) then return true end
                    end
                    return false
                end
            end
        end
    end
    return out
end

-- Checked menu items that are in effect: status items don't count without the profession.
function M.ActiveFilterCount(filters, hasProfession)
    local n = 0
    for _, group in ipairs(M.FILTER_GROUPS) do
        if hasProfession or not group.needsProfession then
            for _, key in ipairs(group.items) do
                if filters and filters[key] then n = n + 1 end
            end
        end
    end
    return n
end

-- Difficulty ------------------------------------------------------------------------------

M.COLORS = {
    red = "ff2020", orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "808080",
    neutral = "ffffff",
}

-- Colour of a recipe for the given skill; "neutral" when the skill is unknown. A learned recipe is
-- always craftable, so the learn level only makes an unlearned recipe red.
function M.Difficulty(rec, skill, learned)
    if not skill then return "neutral" end
    if not learned and rec.learn and skill < rec.learn then return "red" end
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

-- "learn yellow green grey", each in its colour. The learn value is red when the recipe isn't learned
-- and it's out of reach.
function M.RangeText(rec, skill, learned)
    local parts = {}
    if rec.learn then
        parts[#parts + 1] = Colored((not learned and skill and skill < rec.learn) and "red" or "orange", rec.learn)
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
-- For friendly NPCs only (vendors, quest givers): on a mob the flag means who it's friendly to.
function M.Usable(npcID, faction)
    local npc = ns.Data.NPCs and ns.Data.NPCs[npcID]
    local f = npc and npc.faction
    if not f or f == "AH" or not faction then return true end
    return f == SIDE_LETTER[faction]
end

-- "A" or "H" when every giver of the quest belongs to that side, else nil (open to both or unknown).
function M.QuestFaction(qid)
    local q = ns.Data.Quests and ns.Data.Quests[qid]
    local side
    for _, npcID in ipairs(q and q.npcs or {}) do
        local npc = ns.Data.NPCs and ns.Data.NPCs[npcID]
        local f = npc and npc.faction
        if f ~= "A" and f ~= "H" then return nil end
        if side and side ~= f then return nil end
        side = f
    end
    return side
end

function M.QuestUsable(qid, faction)
    local side = M.QuestFaction(qid)
    return not side or not faction or side == SIDE_LETTER[faction]
end

local SIDE_NAME = { A = L.ALLIANCE, H = L.HORDE }

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
    local side = npc and SIDE_NAME[npc.faction]
    return NPCWhere(id) .. (side and (M.SEP .. side) or "")
end

-- The first quest usable by `faction`, else the first one with its side's name appended.
local function PickQuest(qids, faction)
    for _, qid in ipairs(qids) do
        if M.QuestUsable(qid, faction) then return M.QuestName(qid) end
    end
    local side = SIDE_NAME[M.QuestFaction(qids[1])]
    return M.QuestName(qids[1]) .. (side and (M.SEP .. side) or "")
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
        -- Drops keep data order (best chance first): a mob's faction says who it's friendly to.
        if not (rec.drops and rec.drops[1]) then return Unverified() end
        return L.ROW_DROP:format(NPCWhere(rec.drops[1][1]))
    end
    if t == "quest" then
        if not (rec.quests and rec.quests[1]) then return Unverified() end
        return L.ROW_QUEST:format(PickQuest(rec.quests, faction))
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
-- Cards follow PRIMARY_ORDER (easiest first); vendors and quests list what `faction` can use first,
-- drops keep data order (best chance first).

-- Join the non-empty arguments with M.SEP.
local function JoinSep(...)
    local out = {}
    for i = 1, select("#", ...) do
        local p = select(i, ...)
        if p and p ~= "" then out[#out + 1] = p end
    end
    return table.concat(out, M.SEP)
end

-- Entries reordered so the ones usable(e) accepts come first, data order kept within each group.
local function UsableFirst(entries, usable)
    local first, rest = {}, {}
    for _, e in ipairs(entries) do
        if usable(e) then first[#first + 1] = e else rest[#rest + 1] = e end
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
    -- The faction tag only means something for friendly NPCs; on a mob it says who it's friendly to.
    local tag = kind == "vendor" and npc and FACTION_TAG[npc.faction] or nil
    return {
        type = kind, title = title,
        detail = JoinSep(rate, tag, ZoneAt(npc)),
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
    for _, id in ipairs(UsableFirst(rec.vendors or {}, function(id) return M.Usable(id, faction) end)) do
        Add(NPCCard("vendor", id))
    end
    for _, qid in ipairs(UsableFirst(rec.quests or {}, function(qid) return M.QuestUsable(qid, faction) end)) do
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
            detail = JoinSep(#names > 0 and L.QUEST_GIVER:format(table.concat(names, ", ")) or nil,
                FACTION_TAG[M.QuestFaction(qid)], ZoneAt(where)),
            waypoint = waypoint,
        })
    end
    if rec.drops and #rec.drops > 0 then
        for _, d in ipairs(rec.drops) do
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
    if learned then return M.RangeText(rec, skill, true) end
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

-- Reagents -------------------------------------------------------------------------------------------
-- Read live: GetRecipeSchematic works with the profession window closed, for unlearned recipes and for
-- other professions. Cached per spell (false when there's no schematic).

M.schematics = {}

function M.Schematic(spellID)
    local cached = M.schematics[spellID]
    if cached ~= nil then return cached or nil end
    local s
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local ok, res = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
        if ok then s = res end
    end
    M.schematics[spellID] = s or false
    return s
end

-- { {item, count}... }, one per reagent slot (its first reagent); nil without a schematic.
function M.Reagents(spellID)
    local s = M.Schematic(spellID)
    if not s then return nil end
    local out = {}
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local r = slot.reagents and slot.reagents[1]
        if r and r.itemID then out[#out + 1] = { item = r.itemID, count = slot.quantityRequired or 1 } end
    end
    return out
end

-- Reverse index: item -> the recipes that create it, across every profession ------------------------

local creating   -- [itemID] = { {line, spellID}... }, each sorted by spell ID; built on first use

function M.RecipesCreating(itemID)
    if not creating then
        creating = {}
        for line, recipes in pairs(ns.Data.Recipes or {}) do
            for spellID, rec in pairs(recipes) do
                if rec.creates then
                    local list = creating[rec.creates] or {}
                    list[#list + 1] = { line = line, spellID = spellID }
                    creating[rec.creates] = list
                end
            end
        end
        for _, list in pairs(creating) do
            table.sort(list, function(a, b) return a.spellID < b.spellID end)
        end
    end
    return creating[itemID]
end

-- Items one craft makes: `count`, the minimum of a {min, max} range, else 1.
function M.Yield(rec)
    local c = rec and rec.count
    if type(c) == "number" then return c end
    if type(c) == "table" then return c[1] or 1 end
    return 1
end

-- Whether a craft makes more than one item, or a range: then a quantity can mean crafts or items.
function M.MakesSeveral(rec)
    return rec ~= nil and rec.creates ~= nil and (M.Yield(rec) > 1 or type(rec.count) == "table")
end

-- Whole crafts needed for `items` of the output.
function M.CraftsFor(rec, items)
    if not items or items <= 0 then return 0 end
    return math.ceil(items / M.Yield(rec))
end

-- Material plans -------------------------------------------------------------------------------------
-- M.PlanMaterials(roots, ctx) turns recipes and craft counts into totals across crafted intermediates.
--   roots = { {spellID, line, crafts}... }
--   ctx   = { reagents = fn(spellID) -> {{item, count}...}|nil, have = fn(itemID) -> n (optional),
--             knownBy = fn(line, spellID) -> {me, alts = {key...}}, mode = fn(itemID) -> "craft"|"buy"|nil }
-- Pass 1 decides each item once, depth first: raw (nothing creates it), craft (with which recipe) or buy.
-- A maker is usable when its reagents can be read and none of them is on the current path (the items being
-- crafted above it, and the root's output), so no item is ever crafted inside its own subtree. Crafting is
-- the default when someone knows a usable maker; ctx.mode overrides it. Makers rank: known by me, by an alt,
-- lowest learn skill, spell ID.
-- Then every item gets a level, its longest distance from a root, so it sits deeper than all its users.
-- Pass 2 sums needs level by level, subtracts what's in the bags once per item and rounds to whole crafts
-- on the total.

local NOBODY = { me = false, alts = {} }

local function KnownRank(known)
    if known.me then return 1 end
    if known.alts and #known.alts > 0 then return 2 end
    return 3
end

local function BetterMaker(a, b)
    local ra, rb = KnownRank(a.known), KnownRank(b.known)
    if ra ~= rb then return ra < rb end
    local la, lb = a.rec and a.rec.learn or 0, b.rec and b.rec.learn or 0
    if la ~= lb then return la < lb end
    return a.spellID < b.spellID
end

function M.PlanMaterials(roots, ctx)
    local items = {}
    local plan = { roots = {}, items = items }
    local read = {}   -- reagents per spell for this plan (false: unreadable)
    local function Reagents(spellID)
        local r = read[spellID]
        if r == nil then
            r = ctx.reagents(spellID) or false
            read[spellID] = r
        end
        return r or nil
    end
    local function Known(line, spellID)
        return (ctx.knownBy and ctx.knownBy(line, spellID)) or NOBODY
    end
    local function Mode(itemID)
        local m = ctx.mode and ctx.mode(itemID)
        if m == "craft" or m == "buy" then return m end
        return nil
    end
    local onPath = {}

    -- Usable makers of an item, best first, and whether any maker was dropped for closing a cycle.
    local function Makers(itemID)
        local usable, cycled = {}, false
        for _, m in ipairs(M.RecipesCreating(itemID) or {}) do
            local reagents = Reagents(m.spellID)
            local ok = reagents ~= nil
            for _, r in ipairs(reagents or {}) do
                if onPath[r.item] then ok, cycled = false, true end
            end
            if ok then
                local rec = ns.Data.Recipes[m.line] and ns.Data.Recipes[m.line][m.spellID]
                usable[#usable + 1] = { line = m.line, spellID = m.spellID, rec = rec, reagents = reagents,
                    known = Known(m.line, m.spellID) }
            end
        end
        table.sort(usable, BetterMaker)
        return usable, cycled
    end

    local function Decide(itemID)
        if items[itemID] then return end
        local node = { item = itemID, need = 0 }
        items[itemID] = node
        if onPath[itemID] then   -- a root's own output among its reagents
            node.kind, node.cycle, node.switchable = "buy", true, false
            return
        end
        if not M.RecipesCreating(itemID) then
            node.kind, node.switchable = "raw", false
            return
        end
        node.switchable = true
        node.mode = Mode(itemID)
        local usable, cycled = Makers(itemID)
        local best = usable[1]
        node.known = best and best.known or NOBODY
        local want = node.mode or ((best and KnownRank(best.known) < 3) and "craft" or "buy")
        if want == "craft" and best then
            node.kind, node.spellID, node.line = "craft", best.spellID, best.line
            node.yield, node.reagents = M.Yield(best.rec), best.reagents
            onPath[itemID] = true
            for _, r in ipairs(best.reagents) do Decide(r.item) end
            onPath[itemID] = nil
        else
            node.kind = "buy"
            if want == "craft" and cycled then node.cycle = true end
        end
    end

    for i, r in ipairs(roots) do
        local rec = ns.Data.Recipes[r.line] and ns.Data.Recipes[r.line][r.spellID]
        local root = { spellID = r.spellID, line = r.line, crafts = r.crafts or 1, yield = M.Yield(rec),
            item = rec and rec.creates, known = Known(r.line, r.spellID), reagents = Reagents(r.spellID) }
        root.makes = root.crafts * root.yield
        plan.roots[i] = root
        if root.item then onPath[root.item] = true end
        for _, x in ipairs(root.reagents or {}) do Decide(x.item) end
        if root.item then onPath[root.item] = nil end
    end

    -- Levels: reverse post-order is a topological order (users before what they use).
    local post, seen = {}, {}
    local function Post(itemID)
        if seen[itemID] then return end
        seen[itemID] = true
        local n = items[itemID]
        if n.kind == "craft" then
            for _, x in ipairs(n.reagents) do Post(x.item) end
        end
        post[#post + 1] = itemID
    end
    for _, root in ipairs(plan.roots) do
        for _, x in ipairs(root.reagents or {}) do
            Post(x.item)
            items[x.item].level = 1
        end
    end
    for i = #post, 1, -1 do
        local n = items[post[i]]
        if n.kind == "craft" then
            for _, x in ipairs(n.reagents) do
                local child = items[x.item]
                child.level = math.max(child.level or 0, n.level + 1)
            end
        end
    end

    -- Totals, shallow levels first.
    local order = {}
    for id in pairs(items) do order[#order + 1] = id end
    table.sort(order, function(a, b)
        local la, lb = items[a].level, items[b].level
        if la ~= lb then return la < lb end
        return a < b
    end)
    plan.order = order
    for _, root in ipairs(plan.roots) do
        for _, x in ipairs(root.reagents or {}) do
            local n = items[x.item]
            n.need = n.need + root.crafts * x.count
        end
    end
    for _, id in ipairs(order) do
        local n = items[id]
        n.have = (ctx.have and ctx.have(id)) or 0
        n.net = math.max(0, n.need - n.have)
        if n.kind == "craft" then
            n.crafts = math.ceil(n.net / n.yield)
            n.surplus = n.crafts * n.yield - n.net
            for _, x in ipairs(n.reagents) do
                local child = items[x.item]
                child.need = child.need + n.crafts * x.count
            end
        else
            n.buy = n.net
        end
    end

    -- Shopping list: bought and raw items still needed, by item ID.
    local shopping = {}
    for _, id in ipairs(order) do
        local n = items[id]
        if n.kind ~= "craft" and n.need > 0 then
            shopping[#shopping + 1] = { item = id, need = n.need, have = n.have, buy = n.buy }
        end
    end
    table.sort(shopping, function(a, b) return a.item < b.item end)
    plan.shopping = shopping

    -- Craft steps: deepest level first (everything an item needs is made before it), then the roots.
    local steps = {}
    for _, id in ipairs(order) do
        local n = items[id]
        if n.kind == "craft" and n.crafts > 0 then
            steps[#steps + 1] = { item = n.item, spellID = n.spellID, line = n.line, crafts = n.crafts, known = n.known }
        end
    end
    table.sort(steps, function(a, b)
        local la, lb = items[a.item].level, items[b.item].level
        if la ~= lb then return la > lb end
        return a.item < b.item
    end)
    for _, root in ipairs(plan.roots) do
        steps[#steps + 1] = { item = root.item, spellID = root.spellID, line = root.line, crafts = root.crafts,
            known = root.known, root = true }
    end
    plan.steps = steps

    plan.tree = M.PlanTree(plan)
    return plan
end

-- The reagent tree for display: per root, each branch's own amounts before inventory. Stops after
-- M.PLAN_TREE_MAX nodes, ending the list where it stopped with { more = true }.
M.PLAN_TREE_MAX = 400

function M.PlanTree(plan)
    local count, capped = 0, false
    local function Children(reagents, crafts)
        local out = {}
        for _, x in ipairs(reagents or {}) do
            if count >= M.PLAN_TREE_MAX then
                if not capped then
                    capped = true
                    out[#out + 1] = { more = true }
                end
                return out
            end
            count = count + 1
            local n = plan.items[x.item]
            local node = { item = x.item, count = crafts * x.count }
            if n.kind == "craft" then
                node.children = Children(n.reagents, math.ceil(node.count / n.yield))
            end
            out[#out + 1] = node
        end
        return out
    end
    local trees = {}
    for i, root in ipairs(plan.roots) do
        count = count + 1
        trees[i] = { item = root.item, spellID = root.spellID, count = root.crafts,
            children = Children(root.reagents, root.crafts) }
    end
    return trees
end
