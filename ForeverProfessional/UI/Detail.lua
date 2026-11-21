-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Right pane: a pinned recipe header (output, difficulty scale) over sections that follow the learned
-- state: where to get it, who knows it, reagents. Source cards carry map waypoints.
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI
local Hex = UI.HexColor

local ICON = 18
local SLOT = 28
local CARD_H, CARD_ICON = 40, 24
local BUTTON_W = 74
local DETAIL_HEADER_H = 76   -- pinned recipe header above the scroll area
local SCALE_W, SCALE_CAP = 150, 6
local OWNER_DOTS = { known = "40c040", learnable = "ffd100", low = "909090", none = "6d6455" }

local detail = {}
UI.detail = detail
UI.schematics = {}
local requested = {}   -- [itemID] = true once a load was asked for

local function ContentWidth()
    return UI.DetailContentWidth()
end

-- Height of the scroll frame: the panel (below the window header, inside the gaps) less the pinned
-- recipe header and the insets.
function UI.DetailVisibleHeight()
    return UI.Height() - UI.HEADER_H - 2 * UI.GAP - 16 - DETAIL_HEADER_H - 4
end

function UI.ReagentColumns(width)
    return (width or 0) >= 440 and 2 or 1
end

-- Waypoints --------------------------------------------------------------------------------

function UI.SetWaypoint(wp)
    if not (wp and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return false end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(wp.map) then
        ns.Print(L.WAYPOINT_FAILED)
        return false
    end
    local x, y = wp.x / 100, wp.y / 100
    local point
    if UiMapPoint.CreateFromCoordinates then
        point = UiMapPoint.CreateFromCoordinates(wp.map, x, y)
    elseif UiMapPoint.CreateFromVector2D and CreateVector2D then
        point = UiMapPoint.CreateFromVector2D(wp.map, CreateVector2D(x, y))
    end
    if not point then return false end
    C_Map.SetUserWaypoint(point)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    local zone = M.ZoneName({ map = wp.map }) or ""
    ns.Print(L.WAYPOINT_SET:format(wp.name or "", zone, wp.x, wp.y))
    return true
end

-- Items ----------------------------------------------------------------------------------------

local function ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if name then return name, true end
    return ("Item #%d"):format(itemID), false
end

local function ItemColor(itemID)
    local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and c.hex or "|cffffffff"
end

-- Coloured item name; an uncached item is queued in `pending` for loading.
local function ItemText(itemID, pending)
    local name, cached = ItemName(itemID)
    if not cached and not requested[itemID] then pending[#pending + 1] = itemID end
    return ItemColor(itemID) .. name .. "|r"
end

function UI.GetSchematic(spellID)
    local cached = UI.schematics[spellID]
    if cached ~= nil then return cached or nil end
    local s
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local ok, res = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
        if ok then s = res end
    end
    UI.schematics[spellID] = s or false
    return s
end

local function ShowItemTooltip(self)
    if not (self.item and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.item)
    GameTooltip:Show()
end
local function HideTooltip() if GameTooltip then GameTooltip:Hide() end end

-- Pinned header ----------------------------------------------------------------------------------
-- Output icon, name, "Creates …", chips and the difficulty scale.

local function CreateScale(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SCALE_W, 30)
    s.label = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.label:SetPoint("TOPLEFT", 0, 0)
    s.label:SetText(L.SKILL_LABEL)
    s.label:SetTextColor(Hex(UI.COLORS.muted))
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetPoint("TOPLEFT", 0, -13)
    s.track:SetSize(SCALE_W, 6)
    s.track:SetColorTexture(0, 0, 0, 0.9)
    s.segments = {}
    for i, color in ipairs({ "orange", "yellow", "green", "grey" }) do
        local t = s:CreateTexture(nil, "ARTWORK")
        t:SetHeight(6)
        t:SetColorTexture(Hex(M.COLORS[color]))
        s.segments[i] = t
    end
    s.tick = s:CreateTexture(nil, "OVERLAY")
    s.tick:SetSize(2, 12)
    s.tick:SetColorTexture(1, 1, 1, 1)
    s.nums = {}
    for i = 1, 4 do
        local n = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        n:SetPoint("TOP", s.track, "BOTTOMLEFT", (i - 1) * SCALE_W / 3, -2)
        s.nums[i] = n
    end
    s.nums[1]:ClearAllPoints()
    s.nums[1]:SetPoint("TOPLEFT", s.track, "BOTTOMLEFT", 0, -2)
    s.nums[4]:ClearAllPoints()
    s.nums[4]:SetPoint("TOPRIGHT", s.track, "BOTTOMRIGHT", 0, -2)
    return s
end

local function CreateHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT", 8, -8)
    h:SetPoint("TOPRIGHT", -8, -8)
    h:SetHeight(DETAIL_HEADER_H)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    if not (CreateColor and pcall(h.bg.SetGradient, h.bg, "VERTICAL",
            CreateColor(1, 0.82, 0, 0), CreateColor(1, 0.82, 0, 0.06))) then
        h.bg:SetVertexColor(1, 0.82, 0, 0.03)
    end
    h.rule = h:CreateTexture(nil, "BORDER")
    h.rule:SetPoint("BOTTOMLEFT")
    h.rule:SetPoint("BOTTOMRIGHT")
    h.rule:SetHeight(1)
    h.rule:SetColorTexture(Hex(UI.COLORS.line))

    h.iconBorder = h:CreateTexture(nil, "ARTWORK")
    h.iconBorder:SetSize(50, 50)
    h.iconBorder:SetPoint("TOPLEFT", 4, -6)
    h.icon = h:CreateTexture(nil, "ARTWORK", nil, 1)
    h.icon:SetSize(46, 46)
    h.icon:SetPoint("CENTER", h.iconBorder, "CENTER")

    h.scale = CreateScale(h)
    h.scale:SetPoint("TOPRIGHT", -4, -8)

    h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.title:SetPoint("TOPLEFT", h.iconBorder, "TOPRIGHT", 10, 0)
    h.title:SetPoint("RIGHT", h.scale, "LEFT", -10, 0)
    h.title:SetJustifyH("LEFT")
    h.title:SetWordWrap(false)
    h.creates = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.creates:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -3)
    h.creates:SetPoint("RIGHT", h.scale, "LEFT", -10, 0)
    h.creates:SetJustifyH("LEFT")
    h.creates:SetWordWrap(false)
    h.creates:SetTextColor(Hex(UI.COLORS.muted))

    h.stateChip = UI.CreateChip(h)
    h.stateChip:SetPoint("TOPLEFT", h.creates, "BOTTOMLEFT", 0, -5)
    h.catChip = UI.CreateChip(h)
    h.catChip:SetPoint("LEFT", h.stateChip, "RIGHT", 5, 0)
    h.newChip = UI.CreateChip(h)
    h.newChip:SetPoint("LEFT", h.catChip, "RIGHT", 5, 0)
    return h
end

-- Nothing selected: the profession's illustration and three numbers.
local function CreateEmpty(parent)
    local e = CreateFrame("Frame", nil, parent)
    e:SetAllPoints()
    e.watermark = e:CreateTexture(nil, "BACKGROUND")
    e.watermark:SetSize(260, 260)
    e.watermark:SetPoint("CENTER", 0, 20)
    e.watermark:SetAlpha(0.06)
    e.watermark:Hide()
    e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    e.hint:SetPoint("CENTER", 0, 30)
    e.hint:SetText(L.SELECT_RECIPE)
    e.stats = {}
    local boxes = {
        { key = "learned", label = L.LEARNED, color = "40c040" },
        { key = "learnable", label = L.LEARNABLE_NOW, color = UI.COLORS.gold },
        { key = "missing", label = L.FILTER_MISSING, color = UI.COLORS.muted },
    }
    for i, b in ipairs(boxes) do
        local box = UI.Panel(e, 1)
        box:SetSize(110, 46)
        box:SetPoint("TOP", e.hint, "BOTTOM", (i - 2) * 120, -16)
        box.value = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        box.value:SetPoint("TOP", 0, -7)
        box.value:SetTextColor(Hex(b.color))
        box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        box.label:SetPoint("BOTTOM", 0, 7)
        box.label:SetText(b.label)
        box.label:SetTextColor(Hex(UI.COLORS.muted))
        e.stats[b.key] = box
    end
    e:Hide()
    return e
end

function UI.CreateDetail(parent)
    detail.header = CreateHeader(parent)
    local scroll = CreateFrame("ScrollFrame", "ForeverProfessionalDetailScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -(8 + DETAIL_HEADER_H + 4))
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", "ForeverProfessionalDetailContent", scroll)
    child:SetSize(ContentWidth(), 1)
    scroll:SetScrollChild(child)
    UI.StyleScroll(scroll)
    detail.scroll, detail.child = scroll, child
    detail.lines, detail.slots, detail.cardWidgets, detail.ownerRows = {}, {}, {}, {}
    detail.empty = CreateEmpty(parent)
end

-- Re-fit the fixed-width parts to the pane after a resize (RefreshDetail re-renders the content).
function UI.LayoutDetail()
    if not detail.child then return end
    detail.child:SetWidth(ContentWidth())
end

-- Difficulty scale: orange/yellow/green segments over learn → grey plus a grey cap, the four
-- numbers, and a tick at the character's skill once it reaches the learn level.
local function RenderScale(s, rec, skill)
    local learn, grey = rec.learn or 0, rec.grey
    local widths = { 0, 0, 0, 0 }
    local span = grey and (grey - learn) or 0
    if grey and span > 0 then
        local w = SCALE_W - SCALE_CAP
        local y = math.max(learn, math.min(grey, rec.yellow or learn))
        local g = math.max(y, math.min(grey, rec.green or y))
        widths = { (y - learn) / span * w, (g - y) / span * w, (grey - g) / span * w, SCALE_CAP }
    elseif grey then
        widths[4] = SCALE_W          -- trivial from the start
    else
        widths[1] = SCALE_W          -- never turns grey
    end
    local x = 0
    for i, t in ipairs(s.segments) do
        local w = math.max(0, widths[i])
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", s.track, "TOPLEFT", x, 0)
        t:SetWidth(w)
        t:SetShown(w > 0)
        x = x + w
    end

    local values = { rec.learn, rec.grey and rec.yellow, rec.grey and rec.green, rec.grey }
    local colors = { (skill and rec.learn and skill < rec.learn) and "red" or "orange", "yellow", "green", "grey" }
    for i, n in ipairs(s.nums) do
        n:SetText(values[i] and tostring(values[i]) or "")
        n:SetTextColor(Hex(M.COLORS[colors[i]]))
    end

    local showTick = skill ~= nil and skill >= learn
    s.tick:SetShown(showTick)
    if showTick then
        local pos = SCALE_W - 2
        if grey and span > 0 and skill < grey then pos = (skill - learn) / span * (SCALE_W - SCALE_CAP) end
        s.tick:ClearAllPoints()
        s.tick:SetPoint("CENTER", s.track, "LEFT", math.max(1, math.min(SCALE_W - 1, pos)), 0)
    end
end

-- "Creates [count×] <item> · <subtype>", with the item name queued for loading when uncached.
local function CreatesText(spellID, rec, pending)
    local s = UI.GetSchematic(spellID)
    local output = (s and s.outputItemID) or rec.creates
    if not output then return nil end
    local count
    if s and s.quantityMax and s.quantityMax > 1 then
        count = s.quantityMin == s.quantityMax and tostring(s.quantityMax) or (s.quantityMin .. "-" .. s.quantityMax)
    elseif type(rec.count) == "table" then   -- { min, max }
        count = rec.count[1] .. "-" .. rec.count[2]
    elseif rec.count and rec.count > 1 then
        count = tostring(rec.count)
    end
    local text = ItemText(output, pending)
    if count then text = count .. "x " .. text end
    local subtype = C_Item and C_Item.GetItemInfoInstant and select(3, C_Item.GetItemInfoInstant(output))
    if subtype and subtype ~= "" then text = text .. M.SEP .. subtype end
    return L.CREATES_LINE:format(text), output
end

local function RenderHeader(spellID, rec, skill, learned, pending)
    local h = detail.header
    h.icon:SetTexture(M.RecipeIcon(spellID, rec))
    h.title:SetText(M.Colored(M.Difficulty(rec, skill), M.RecipeDisplayName(spellID)))
    local creates, output = CreatesText(spellID, rec, pending)
    h.creates:SetText(creates or "")
    local q = output and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(output)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then h.iconBorder:SetColorTexture(c.r, c.g, c.b, 1) else h.iconBorder:SetColorTexture(Hex("5a4a32")) end

    if learned then h.stateChip:SetChip(L.LEARNED, "good") else h.stateChip:SetChip(L.NOT_LEARNED, "bad") end
    local cat = rec.cat and ns.Data.Categories and ns.Data.Categories[rec.cat]
    h.catChip:SetChip(cat and cat.name or L.OTHER, "neutral")
    h.newChip:SetShown(rec.new and true or false)
    if rec.new then h.newChip:SetChip(L.NEW, "neutral") end
    RenderScale(h.scale, rec, skill)
end

local function RenderEmpty()
    local e, line = detail.empty, UI.state.line
    e:Show()
    if not line then return end
    local watermark = UI.Theme(line).watermark
    e.watermark:SetShown(watermark ~= nil and UI.SetAtlas(e.watermark, watermark))
    local total, learned = M.FilterCounts(line, function(id) return ns.IsLearned(id, UI.state.char) end)
    e.stats.learned.value:SetText(tostring(learned))
    e.stats.learnable.value:SetText(tostring(ns.LearnableCount(line, UI.state.char)))
    e.stats.missing.value:SetText(tostring(total - learned))
end

-- Blocks ----------------------------------------------------------------------------------------------
-- What the scroll area shows, in order:
--   section (text, toggle), reagents (items = {{item, count}}), owner (group, text), get (item),
--   card (card), req (text), note (text), folded (text)

function UI.ToggleSources()
    UI.state.sourcesOpen = not UI.state.sourcesOpen
    UI.RefreshDetail()
end

function UI.DetailBlocks(spellID, rec)
    local blocks = {}
    local function Add(b) blocks[#blocks + 1] = b end
    local learned = ns.IsLearned(spellID, UI.state.char)
    local faction = ns.CharFaction(UI.state.char)

    for _, part in ipairs(M.DetailOrder(learned)) do
        if part == "reagents" then
            local s = UI.GetSchematic(spellID)
            local items = {}
            for _, slot in ipairs(s and s.reagentSlotSchematics or {}) do
                local r = slot.reagents and slot.reagents[1]
                if r and r.itemID then items[#items + 1] = { item = r.itemID, count = slot.quantityRequired or 1 } end
            end
            if #items > 0 then
                Add({ kind = "section", text = L.REAGENTS })
                Add({ kind = "reagents", items = items })
            end
        elseif part == "characters" then
            Add({ kind = "section", text = L.CHARACTERS })
            local groups = ns.OwnerGroups(UI.state.line, spellID)
            if #groups == 0 then Add({ kind = "owner", group = "none", text = L.NO_CHARACTER }) end
            for _, g in ipairs(groups) do Add({ kind = "owner", group = g.group, text = g.text }) end
        elseif learned and not UI.state.sourcesOpen then
            Add({ kind = "folded", text = L.WHERE .. M.SEP .. M.PrimarySource(rec, faction).text })
        else
            Add({ kind = "section", text = L.WHERE, toggle = learned })
            local sc = M.SourceCards(rec, faction)
            for _, id in ipairs(sc.teach) do Add({ kind = "get", item = id }) end
            for _, r in ipairs(sc.requirements) do Add({ kind = "req", text = r }) end
            for _, c in ipairs(sc.cards) do Add({ kind = "card", card = c }) end
            for _, n in ipairs(sc.notes) do Add({ kind = "note", text = n }) end
        end
    end
    return blocks
end

-- Widget pools -------------------------------------------------------------------------------------------

local used = {}

local function Take(pool, create)
    used[pool] = (used[pool] or 0) + 1
    local w = pool[used[pool]]
    if not w then
        w = create()
        pool[used[pool]] = w
    end
    w:ClearAllPoints()
    w:Show()
    return w
end

local function HideUnused()
    for _, pool in ipairs({ detail.lines, detail.slots, detail.cardWidgets, detail.ownerRows }) do
        for i = (used[pool] or 0) + 1, #pool do pool[i]:Hide() end
    end
    wipe(used)
end

-- Text line: section titles, the folded sources line, "Get <item> from:", requirements and notes.
local function CreateTextLine()
    local line = CreateFrame("Button", nil, detail.child)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(ICON, ICON)
    line.icon:SetPoint("LEFT", 0, 0)
    line.chevron = line:CreateTexture(nil, "ARTWORK")
    line.chevron:SetSize(10, 10)
    line.chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    line.chevron:SetPoint("LEFT", 0, 0)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    line.rule = line:CreateTexture(nil, "BORDER")
    line.rule:SetHeight(1)
    line.rule:SetColorTexture(Hex(UI.COLORS.line))
    line:SetScript("OnEnter", ShowItemTooltip)
    line:SetScript("OnLeave", HideTooltip)
    line:SetScript("OnClick", function(self) if self.toggle then UI.ToggleSources() end end)
    return line
end

local function RenderTextLine(b, y, width, pending)
    local line = Take(detail.lines, CreateTextLine)
    line:SetPoint("TOPLEFT", detail.child, "TOPLEFT", 0, -y)
    line:SetWidth(width)
    line.item, line.toggle = nil, nil
    line.icon:Hide()
    line.chevron:Hide()
    line.rule:Hide()
    local x, height, font, text = 0, 16, "GameFontHighlightSmall", b.text or ""
    local color = nil
    if b.kind == "section" or b.kind == "folded" then
        y = y + 6
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", detail.child, "TOPLEFT", 0, -y)
        height, font = 18, "GameFontNormal"
        if b.kind == "folded" or b.toggle then
            line.toggle = true
            line.chevron:Show()
            line.chevron:SetRotation(b.kind == "folded" and 0 or -math.pi / 2)
            x = 14
        end
        if b.kind == "folded" then
            detail.folded = line
            color = "c9a227"
        end
    elseif b.kind == "get" then
        line.item = b.item
        line.icon:Show()
        line.icon:SetTexture(M.ItemIcon(b.item) or M.QUESTION_ICON)
        x, height = ICON + 6, ICON + 2
        text = L.GET_FROM:format(ItemText(b.item, pending))
    elseif b.kind == "req" then
        color = "e8c37a"
    elseif b.kind == "note" then
        color = "ff8040"
    end
    line:SetHeight(height)
    line.text:SetFontObject(_G[font])
    line.text:ClearAllPoints()
    line.text:SetPoint("LEFT", x, 0)
    line.text:SetText(text)
    if color then line.text:SetTextColor(Hex(color))
    elseif font == "GameFontNormal" then line.text:SetTextColor(Hex(UI.COLORS.gold))
    else line.text:SetTextColor(1, 1, 1) end
    if b.kind == "section" then
        line.rule:Show()
        line.rule:ClearAllPoints()
        line.rule:SetPoint("LEFT", line.text, "RIGHT", 8, 0)
        line.rule:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    end
    return y + height + 4
end

local function CreateSlotWidget()
    local s = UI.CreateSlot(detail.child, SLOT)
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.name:SetPoint("LEFT", s, "RIGHT", 7, 0)
    s.name:SetJustifyH("LEFT")
    s.name:SetWordWrap(false)
    return s
end

local function RenderReagents(b, y, width, pending)
    local cols = UI.ReagentColumns(width)
    local colW = math.floor(width / cols)
    for i, r in ipairs(b.items) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local s = Take(detail.slots, CreateSlotWidget)
        s:SetPoint("TOPLEFT", detail.child, "TOPLEFT", col * colW, -(y + row * (SLOT + 5)))
        s:SetItem(r.item, r.count)
        s.name:SetWidth(colW - SLOT - 14)
        s.name:SetText(ItemText(r.item, pending))
    end
    return y + math.ceil(#b.items / cols) * (SLOT + 5) + 2
end

local function CreateOwnerRow()
    local r = UI.Panel(detail.child, 1)
    r:SetHeight(24)
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("LEFT", 9, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.dot, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    return r
end

local function RenderOwner(b, y, width)
    local r = Take(detail.ownerRows, CreateOwnerRow)
    r:SetPoint("TOPLEFT", detail.child, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r.dot:SetColorTexture(Hex(OWNER_DOTS[b.group] or OWNER_DOTS.none))
    r.text:SetText(b.text or "")
    return y + 24 + 4
end

local function CreateCard()
    local w = CreateFrame("Button", nil, detail.child, "BackdropTemplate")
    w:SetHeight(CARD_H)
    w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    w:SetBackdropColor(Hex(UI.COLORS.field))
    w:SetBackdropBorderColor(Hex(UI.COLORS.line))
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetSize(CARD_ICON, CARD_ICON)
    w.icon:SetPoint("LEFT", 8, 0)
    w.waypoint = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.waypoint:SetSize(BUTTON_W, 20)
    w.waypoint:SetPoint("RIGHT", -8, 0)
    w.waypoint:SetText(L.WAYPOINT)
    w.waypoint:SetScript("OnClick", function(self) UI.SetWaypoint(self:GetParent().card.waypoint) end)
    w.dungeon = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.dungeon:SetPoint("RIGHT", -10, 0)
    w.dungeon:SetText(L.DUNGEON)
    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.title:SetPoint("TOPLEFT", w.icon, "TOPRIGHT", 9, 1)
    w.title:SetJustifyH("LEFT")
    w.title:SetWordWrap(false)
    w.detail = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.detail:SetPoint("BOTTOMLEFT", w.icon, "BOTTOMRIGHT", 9, -1)
    w.detail:SetJustifyH("LEFT")
    w.detail:SetWordWrap(false)
    w.detail:SetTextColor(Hex(UI.COLORS.muted))
    w:SetScript("OnEnter", ShowItemTooltip)
    w:SetScript("OnLeave", HideTooltip)
    return w
end

local function RenderCard(b, y, width, pending)
    local card = b.card
    if card.type == "more" then
        return RenderTextLine({ kind = "text", text = card.title }, y, width, pending)
    end
    local w = Take(detail.cardWidgets, CreateCard)
    w:SetPoint("TOPLEFT", detail.child, "TOPLEFT", 0, -y)
    w:SetWidth(width)
    w.card, w.item = card, card.item
    w.icon:SetTexture(UI.SOURCE_ICONS[card.type] or UI.SOURCE_ICONS.unknown)
    w.title:SetText(card.title or (card.item and ItemText(card.item, pending)) or "")
    w.detail:SetText(card.detail or "")
    w.waypoint:SetShown(card.waypoint ~= nil)
    w.dungeon:SetShown(card.waypoint == nil and card.instance or false)
    local right = (card.waypoint and BUTTON_W + 16) or (card.instance and 70) or 10
    local textW = width - (8 + CARD_ICON + 9) - right
    w.title:SetWidth(textW)
    w.detail:SetWidth(textW)
    return y + CARD_H + 5
end

-- Rendering ----------------------------------------------------------------------------------------------

function UI.RefreshDetail()
    if not detail.child then return end
    local spellID = UI.state.selected
    local rec = spellID and UI.state.line and ns.Data.Recipes[UI.state.line][spellID]
    detail.current = spellID
    if not rec then
        detail.scroll:Hide()
        detail.header:Hide()
        RenderEmpty()
        detail.rendered = nil
        return
    end
    detail.empty:Hide()
    detail.header:Show()
    detail.scroll:Show()

    local skill = ns.CharSkill(UI.state.line, UI.state.char)
    local learned = ns.IsLearned(spellID, UI.state.char)
    local pending = {}
    RenderHeader(spellID, rec, skill, learned, pending)

    local width = ContentWidth()
    local y = 2
    local blocks = UI.DetailBlocks(spellID, rec)
    detail.folded = nil
    for _, b in ipairs(blocks) do
        if b.kind == "reagents" then y = RenderReagents(b, y, width, pending)
        elseif b.kind == "owner" then y = RenderOwner(b, y, width)
        elseif b.kind == "card" then y = RenderCard(b, y, width, pending)
        else y = RenderTextLine(b, y, width, pending) end
    end
    HideUnused()
    detail.child:SetHeight(y + 8)
    UI.UpdateScrollBar(detail.scroll, y + 8, UI.DetailVisibleHeight())
    detail.rendered = blocks
    if detail.lastSpell ~= spellID then
        detail.scroll:SetVerticalScroll(0)
        detail.lastSpell = spellID
    end

    -- Load missing item names, then re-render if this recipe is still shown. Cached items call
    -- back synchronously: those only mark the pane dirty and it's rendered once after the loop.
    -- `requested` keeps an item from being asked for twice.
    if #pending == 0 or not (Item and Item.CreateFromItemID) then return end
    detail.loading, detail.dirty = true, false
    for _, itemID in ipairs(pending) do
        if not requested[itemID] then
            requested[itemID] = true
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                if detail.current ~= spellID then return end
                if detail.loading then detail.dirty = true else UI.RefreshDetail() end
            end)
        end
    end
    detail.loading = false
    if detail.dirty then UI.RefreshDetail() end
end
