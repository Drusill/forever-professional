-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Right pane: the selected recipe's output, reagents, recipe item and sources, with map waypoints.
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI

local ICON = 18
local BUTTON_W = 74
local INDENT = 14
local HEADER_H = 56   -- icon, title and status; the lines start below

local detail = {}
UI.detail = detail
UI.schematics = {}
local requested = {}   -- [itemID] = true once a load was asked for

local function ContentWidth()
    return UI.WIDTH - (UI.PAD + UI.TAB_W + 8 + UI.LIST_W + 8) - UI.PAD - 34
end

-- Height of the scroll frame: the panel (title bar to bottom padding) less its 8px insets.
function UI.DetailVisibleHeight()
    return UI.HEIGHT - UI.TITLE_H - UI.PAD - 16
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

function UI.CreateDetail(parent)
    local scroll = CreateFrame("ScrollFrame", "ForeverProfessionalDetailScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", "ForeverProfessionalDetailContent", scroll)
    child:SetSize(ContentWidth(), 1)
    scroll:SetScrollChild(child)
    UI.StyleScroll(scroll)
    detail.scroll, detail.child, detail.lines = scroll, child, {}

    detail.icon = child:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(40, 40)
    detail.icon:SetPoint("TOPLEFT", 0, 0)
    detail.ring = child:CreateTexture(nil, "OVERLAY")
    detail.ring:SetSize(52, 52)
    detail.ring:SetPoint("CENTER", detail.icon, "CENTER")
    if not UI.SetAtlas(detail.ring, "adventureguide-ring") then detail.ring:Hide() end

    detail.title = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detail.title:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 10, -2)
    detail.title:SetWidth(ContentWidth() - 52)
    detail.title:SetJustifyH("LEFT")

    detail.status = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.status:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -4)
    detail.status:SetWidth(ContentWidth() - 52)
    detail.status:SetJustifyH("LEFT")

    -- Rule under the header, in the panels' border colour.
    detail.divider = child:CreateTexture(nil, "ARTWORK")
    detail.divider:SetPoint("TOPLEFT", 0, -HEADER_H + 6)
    detail.divider:SetSize(ContentWidth(), 1)
    detail.divider:SetColorTexture(0.6, 0.5, 0.35, 0.6)

    detail.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    detail.empty:SetPoint("CENTER")
    detail.empty:SetText(L.SELECT_RECIPE)
end

-- Rendering --------------------------------------------------------------------------------------

-- Build the list of display lines for a recipe (header excluded).
function UI.DetailLines(spellID, rec)
    local out = {}
    local function Add(l) out[#out + 1] = l end

    local s = UI.GetSchematic(spellID)
    local output = (s and s.outputItemID) or rec.creates
    if output then
        Add({ kind = "section", text = L.CREATES })
        local count
        if s and s.quantityMax and s.quantityMax > 1 then
            count = s.quantityMin == s.quantityMax and tostring(s.quantityMax) or (s.quantityMin .. "-" .. s.quantityMax)
        elseif type(rec.count) == "table" then   -- { min, max }
            count = rec.count[1] .. "-" .. rec.count[2]
        elseif rec.count and rec.count > 1 then
            count = tostring(rec.count)
        end
        Add({ kind = "item", item = output, prefix = count and (count .. "x") or nil, indent = 1 })
    end

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

function UI.RefreshDetail()
    if not detail.child then return end
    local spellID = UI.state.selected
    local rec = spellID and UI.state.line and ns.Data.Recipes[UI.state.line][spellID]
    detail.current = spellID
    if not rec then
        detail.scroll:Hide()
        detail.empty:Show()
        detail.rendered = nil
        return
    end
    detail.empty:Hide()
    detail.scroll:Show()

    local skill = ns.CharSkill(UI.state.line, UI.state.char)
    local learned = ns.IsLearned(spellID, UI.state.char)
    detail.icon:SetTexture(M.RecipeIcon(spellID, rec))
    detail.title:SetText(M.Colored(M.Difficulty(rec, skill), M.RecipeDisplayName(spellID)))
    local status = learned and ("|cff40c040" .. L.LEARNED .. "|r") or ("|cffff4040" .. L.NOT_LEARNED .. "|r")
    status = status .. "   " .. L.SKILL_RANGE .. ": " .. M.RangeText(rec, skill)
    if rec.new then status = status .. "   |cff8080ff" .. L.NEW .. "|r" end
    detail.status:SetText(status)

    local width = ContentWidth()
    local y = HEADER_H
    local pending = {}
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
