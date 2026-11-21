-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Right pane: the selected recipe's output, reagents, recipe item and sources, with map waypoints.
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI

local Hex = UI.HexColor

local ICON = 18
local BUTTON_W = 74
local INDENT = 14
local DETAIL_HEADER_H = 76   -- pinned recipe header above the scroll area
local SCALE_W, SCALE_CAP = 150, 6

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

-- Widgets ----------------------------------------------------------------------------------------

local function CreateLine(index)
    local line = CreateFrame("Button", nil, detail.child)
    line.index = index
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(ICON, ICON)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetJustifyH("LEFT")
    line.text:SetJustifyV("TOP")
    line.text:SetWordWrap(true)

    line.waypoint = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
    line.waypoint:SetSize(BUTTON_W, 18)
    line.waypoint:SetPoint("TOPRIGHT", 0, 1)
    line.waypoint:SetText(L.WAYPOINT)
    line.waypoint:SetScript("OnClick", function(self) UI.SetWaypoint(self:GetParent().wp) end)

    line:SetScript("OnEnter", function(self)
        if self.item and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.item)
            GameTooltip:Show()
        end
    end)
    line:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return line
end

-- Pinned header: output icon, name, "Creates …", chips and the difficulty scale.
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
    detail.scroll, detail.child, detail.lines = scroll, child, {}
    detail.empty = CreateEmpty(parent)
end

-- Re-fit the fixed-width parts to the pane after a resize (RefreshDetail re-renders the lines).
function UI.LayoutDetail()
    if not detail.child then return end
    detail.child:SetWidth(ContentWidth())
end

-- Rendering --------------------------------------------------------------------------------------

-- Build the list of display lines for a recipe (header excluded).
function UI.DetailLines(spellID, rec)
    local out = {}
    local function Add(l) out[#out + 1] = l end

    local s = UI.GetSchematic(spellID)
    if s and s.reagentSlotSchematics and #s.reagentSlotSchematics > 0 then
        Add({ kind = "section", text = L.REAGENTS })
        for _, slot in ipairs(s.reagentSlotSchematics) do
            local r = slot.reagents and slot.reagents[1]
            if r and r.itemID then
                Add({ kind = "item", item = r.itemID, prefix = (slot.quantityRequired or 1) .. "x", indent = 1 })
            end
        end
    end

    local teach = rec.teach
    if teach then
        Add({ kind = "section", text = L.RECIPE_ITEM })
        if type(teach) == "table" then
            for _, id in ipairs(teach) do Add({ kind = "item", item = id, indent = 1 }) end
        else
            Add({ kind = "item", item = teach, indent = 1 })
        end
    end

    Add({ kind = "section", text = L.CHARACTERS })
    local owners = ns.OwnerLines(UI.state.line, spellID)
    if #owners == 0 then owners = { L.NO_CHARACTER } end
    for _, text in ipairs(owners) do Add({ kind = "text", text = text, indent = 1 }) end

    Add({ kind = "section", text = L.SOURCES })
    for _, l in ipairs(M.SourceLines(rec)) do
        if l.kind == "section" then l.kind = "subsection" end
        if l.indent then l.indent = l.indent + 1 end
        Add(l)
    end
    return out
end

local function RenderLine(line, l, y, width, pending)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", detail.child, "TOPLEFT", 0, -y)
    line:SetWidth(width)
    line.item, line.wp = nil, nil
    local x = (l.indent or 0) * INDENT
    local font, text, height = "GameFontHighlightSmall", l.text or "", 14
    local hasIcon = false

    if l.kind == "section" then
        font = "GameFontNormal"
        y = y + 6
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", detail.child, "TOPLEFT", 0, -y)
    elseif l.kind == "subsection" then
        font = "GameFontNormalSmall"
    elseif l.kind == "note" then
        text = "|cffff8040" .. text .. "|r"
    elseif l.kind == "item" then
        local name, cached = ItemName(l.item)
        if not cached and not requested[l.item] then pending[#pending + 1] = l.item end
        text = ItemColor(l.item) .. name .. "|r"
        if l.prefix then text = l.prefix .. " " .. text end
        if l.suffix then text = text .. " - " .. l.suffix end
        line.item = l.item
        line.icon:SetTexture(M.ItemIcon(l.item) or M.QUESTION_ICON)
        hasIcon = true
    end

    line.icon:SetShown(hasIcon)
    if hasIcon then
        line.icon:ClearAllPoints()
        line.icon:SetPoint("TOPLEFT", x, 0)
        x = x + ICON + 4
        height = ICON
    end

    line.wp = l.waypoint
    line.waypoint:SetShown(l.waypoint ~= nil)
    local textWidth = width - x - (l.waypoint and (BUTTON_W + 4) or 0)

    line.text:SetFontObject(_G[font])
    line.text:ClearAllPoints()
    line.text:SetPoint("TOPLEFT", x, hasIcon and -3 or 0)
    line.text:SetWidth(textWidth)
    line.text:SetText(text)
    height = math.max(height, (line.text:GetStringHeight() or 14) + (hasIcon and 3 or 0), l.waypoint and 18 or 0)
    line:SetHeight(height)
    line:Show()
    return y + height + 3
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
    local name, cached = ItemName(output)
    if not cached and not requested[output] then pending[#pending + 1] = output end
    local text = ItemColor(output) .. name .. "|r"
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
    local y = 4
    local lines = UI.DetailLines(spellID, rec)
    for i, l in ipairs(lines) do
        local line = detail.lines[i] or CreateLine(i)
        detail.lines[i] = line
        y = RenderLine(line, l, y, width, pending)
    end
    for i = #lines + 1, #detail.lines do detail.lines[i]:Hide() end
    detail.child:SetHeight(y + 8)
    UI.UpdateScrollBar(detail.scroll, y + 8, UI.DetailVisibleHeight())
    detail.rendered = lines
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
