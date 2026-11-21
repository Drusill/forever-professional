-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Main window: flat frame, icon rail of professions, profession header, toolbar, list and detail panes.
local _, ns = ...
local L = ns.L

local UI = ns.UI
local Hex = UI.HexColor

UI.DEFAULT_W, UI.DEFAULT_H = 1040, 640
UI.MIN_W, UI.MIN_H = 900, 520
UI.RAIL_W = 64
UI.HEADER_H = 54
UI.GAP = 8
UI.BAR_H = 34      -- toolbar row at the top of the list panel
local LIST_SHARE, LIST_MIN, LIST_MAX = 0.44, 380, 520

-- char: the character shown (a key of ForeverProfessionalDB.chars), nil for the logged-in one. Not saved.
UI.state = { line = nil, filter = "all", search = "", selected = nil, char = nil }

local PROFESSION_ICONS = {
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [182] = "Interface\\Icons\\Trade_Herbalism",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [186] = "Interface\\Icons\\Trade_Mining",
    [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [333] = "Interface\\Icons\\Trade_Engraving",
    [356] = "Interface\\Icons\\Trade_Fishing",
    [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}
local GATHERING = { [182] = true, [186] = true, [356] = true, [393] = true }
UI.PROFESSION_ICONS = PROFESSION_ICONS
local ADDON_ICON = "Interface\\Icons\\INV_SideTab_Professions_c60"

-- Scroll frames (UIPanelScrollFrameTemplate) --------------------------------------------------

local function ScrollBarOf(scroll)
    local name = scroll.GetName and scroll:GetName()
    return scroll.ScrollBar or (name and _G[name .. "ScrollBar"])
end

-- A bronze thumb on a dark track (the template's knob shows as a grey square on Forever), and a
-- bar that hides while everything fits: the template does that itself on scroll range changes
-- when scrollBarHideable is set; UI.UpdateScrollBar sets it right away.
function UI.StyleScroll(scroll)
    scroll.scrollBarHideable = true
    local bar = ScrollBarOf(scroll)
    if not bar then return end
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", 0, 0)
    track:SetPoint("BOTTOM", 0, 0)
    track:SetWidth(6)
    track:SetColorTexture(0, 0, 0, 0.45)
    if bar.SetThumbTexture then
        bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
        if thumb then
            thumb:SetTexCoord(0, 1, 0, 1)
            thumb:SetSize(6, 28)
            thumb:SetVertexColor(0.72, 0.45, 0.16, 1)
        end
    end
end

function UI.UpdateScrollBar(scroll, contentHeight, visibleHeight)
    local bar = ScrollBarOf(scroll)
    if bar then bar:SetShown(contentHeight > visibleHeight + 1) end
end

function UI.ProfessionName(line)
    local profs = ns.GetPlayerProfessions()
    if profs[line] and profs[line].name then return profs[line].name end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, line)
        if ok and info and info.professionName and info.professionName ~= "" then return info.professionName end
    end
    local p = ns.Data.Professions[line]
    return p and p.name or tostring(line)
end

-- Crafting professions first, then gathering, each alphabetical (by the baked enUS name, so the
-- order is stable across locales).
function UI.ProfessionOrder()
    local lines = {}
    for line in pairs(ns.Data.Professions) do lines[#lines + 1] = line end
    table.sort(lines, function(a, b)
        if (GATHERING[a] or false) ~= (GATHERING[b] or false) then return not GATHERING[a] end
        return ns.Data.Professions[a].name < ns.Data.Professions[b].name
    end)
    return lines
end

-- The shown character's professions, then the rest, both in ProfessionOrder.
function UI.RailOrder(key)
    local known, other = {}, {}
    for _, line in ipairs(UI.ProfessionOrder()) do
        if ns.CharSkill(line, key) then known[#known + 1] = line else other[#other + 1] = line end
    end
    return known, other
end

function UI.DefaultProfession()
    local _, order = ns.GetPlayerProfessions()
    return order[1] or UI.ProfessionOrder()[1]
end

-- Frame ------------------------------------------------------------------------------------

function UI.SavePosition()
    local point, _, relPoint, x, y = UI.frame:GetPoint()
    if point and ns.db then
        ns.db.window = { point = point, relPoint = relPoint, x = x, y = y,
            w = UI.frame:GetWidth(), h = UI.frame:GetHeight() }
    end
end

local function ScreenSize()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not w or w <= 0 then w = 4096 end
    if not h or h <= 0 then h = 4096 end
    return w, h
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function RestorePosition(f)
    f:ClearAllPoints()
    local w = ns.db and ns.db.window
    if w and w.point then
        f:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    local sw, sh = ScreenSize()
    if w and w.w and w.h then
        f:SetSize(Clamp(w.w, UI.MIN_W, math.max(UI.MIN_W, sw)), Clamp(w.h, UI.MIN_H, math.max(UI.MIN_H, sh)))
    else
        f:SetSize(UI.DEFAULT_W, UI.DEFAULT_H)
    end
end

local function Line(parent, layer)
    local t = parent:CreateTexture(nil, layer or "BORDER")
    t:SetColorTexture(Hex(UI.COLORS.line2))
    return t
end

-- Rail ------------------------------------------------------------------------------------------

local RAIL_ICON, RAIL_ICON_SMALL = 34, 26
local RAIL_KNOWN_H, RAIL_OTHER_H = 52, 30

local function CreateRailButton(rail, line)
    local b = CreateFrame("Button", nil, rail)
    b:SetSize(UI.RAIL_W, RAIL_KNOWN_H)
    b.line = line

    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.glow:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(PROFESSION_ICONS[line] or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.skill = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.marker = b:CreateTexture(nil, "OVERLAY")
    b.marker:SetPoint("TOPLEFT", 0, -6)
    b.marker:SetPoint("BOTTOMLEFT", 0, 6)
    b.marker:SetWidth(3)
    b.marker:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.marker:Hide()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    b:SetScript("OnClick", function(self) UI.SelectProfession(self.line) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(UI.ProfessionName(self.line))
        local skill, max = ns.CharSkill(self.line, UI.state.char)
        GameTooltip:AddLine(skill and L.SKILL:format(skill, max or 0) or L.NOT_LEARNED_PROF, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

-- Size and style a rail button for its group.
local function StyleRailButton(b, known)
    b.group = known and "known" or "other"
    local size = known and RAIL_ICON or RAIL_ICON_SMALL
    b:SetHeight(known and RAIL_KNOWN_H or RAIL_OTHER_H)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOP", b, "TOP", 0, -3)
    b.icon:SetSize(size, size)
    b.icon:SetDesaturated(not known)
    b.icon:SetAlpha(known and 1 or 0.7)
    b.glow:ClearAllPoints()
    b.glow:SetPoint("CENTER", b.icon, "CENTER")
    b.glow:SetSize(size + 6, size + 6)
    b.skill:ClearAllPoints()
    b.skill:SetPoint("TOP", b.icon, "BOTTOM", 0, -1)
    b.skill:SetShown(known)
end

local function CreateRail(f)
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", 1, -1)
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    rail:SetWidth(UI.RAIL_W - 1)
    rail.bg = rail:CreateTexture(nil, "BACKGROUND")
    rail.bg:SetAllPoints()
    rail.bg:SetColorTexture(Hex("0a0907"))
    rail.edge = Line(rail)
    rail.edge:SetPoint("TOPRIGHT")
    rail.edge:SetPoint("BOTTOMRIGHT")
    rail.edge:SetWidth(1)

    rail.logo = CreateFrame("Button", nil, rail)
    rail.logo:SetSize(36, 36)
    rail.logo:SetPoint("TOP", 0, -8)
    rail.logo.icon = rail.logo:CreateTexture(nil, "ARTWORK")
    rail.logo.icon:SetAllPoints()
    rail.logo.icon:SetTexture(ADDON_ICON)
    rail.logo:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TITLE)
        GameTooltip:Show()
    end)
    rail.logo:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    rail.divider = Line(rail, "ARTWORK")
    rail.divider:SetSize(30, 1)

    UI.railButtons = {}
    for _, line in ipairs(UI.ProfessionOrder()) do
        UI.railButtons[#UI.railButtons + 1] = CreateRailButton(rail, line)
    end
    return rail
end

function UI.RefreshRail()
    local rail = UI.rail
    if not rail then return end
    local byLine = {}
    for _, b in ipairs(UI.railButtons) do byLine[b.line] = b end
    local known, other = UI.RailOrder(UI.state.char)
    local accent = UI.Theme(UI.state.line).accent
    local y = -52
    local function Place(line, isKnown)
        local b = byLine[line]
        StyleRailButton(b, isKnown)
        b:ClearAllPoints()
        b:SetPoint("TOP", rail, "TOP", 0, y)
        y = y - b:GetHeight()
        local selected = (line == UI.state.line)
        b.marker:SetShown(selected)
        b.glow:SetShown(selected)
        if selected then
            b.marker:SetVertexColor(Hex(accent))
            local r, g, bl = Hex(accent)
            b.glow:SetVertexColor(r, g, bl, 0.45)
        end
        if isKnown then
            local skill = ns.CharSkill(line, UI.state.char)
            b.skill:SetText(tostring(skill or ""))
            if selected then b.skill:SetTextColor(Hex(accent)) else b.skill:SetTextColor(Hex(UI.COLORS.muted)) end
        end
    end
    for _, line in ipairs(known) do Place(line, true) end
    rail.divider:ClearAllPoints()
    rail.divider:SetPoint("TOP", rail, "TOP", 0, y - 5)
    rail.divider:SetShown(#known > 0 and #other > 0)
    y = y - 11
    for _, line in ipairs(other) do Place(line, false) end
end

-- Header ------------------------------------------------------------------------------------------

local STAT_W = 150

local function CreateStat(header, label)
    local s = {}
    s.label = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.label:SetText(label)
    s.label:SetTextColor(Hex(UI.COLORS.muted))
    s.value = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.value:SetJustifyH("RIGHT")
    return s
end

local function CreateHeader(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", UI.RAIL_W, -1)
    h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    h:SetHeight(UI.HEADER_H)

    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    h.bg:SetVertexColor(Hex("17130e"))
    h.glow = h:CreateTexture(nil, "BACKGROUND", nil, 1)
    h.glow:SetPoint("TOPLEFT")
    h.glow:SetPoint("BOTTOMLEFT")
    h.glow:SetWidth(320)
    h.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    h.edge = Line(h)
    h.edge:SetPoint("BOTTOMLEFT")
    h.edge:SetPoint("BOTTOMRIGHT")
    h.edge:SetHeight(1)

    h.watermark = h:CreateTexture(nil, "BACKGROUND", nil, 2)
    h.watermark:SetSize(140, 140)
    h.watermark:SetPoint("CENTER", h, "CENTER", 0, -10)
    h.watermark:SetAlpha(0.07)
    h.watermark:Hide()

    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(34, 34)
    h.icon:SetPoint("LEFT", 14, 0)
    h.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    h.name = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.name:SetPoint("LEFT", h.icon, "RIGHT", 10, 0)
    h.name:SetJustifyH("LEFT")

    -- Right to left: close button, character selector, recipes, skill.
    f.close = CreateFrame("Button", "ForeverProfessionalFrameClose", h, "UIPanelCloseButton")
    f.close:SetPoint("RIGHT", h, "RIGHT", -6, 0)
    f.close:SetScript("OnClick", function() UI.Hide() end)

    UI.charButton = UI.CreateCharButton(h)
    UI.charButton:SetPoint("RIGHT", f.close, "LEFT", -6, 0)

    local recipes = CreateStat(h, L.RECIPES)
    h.recipesLabel, h.recipesText = recipes.label, recipes.value
    h.recipesBar = UI.CreateProgressBar(h, STAT_W, 4)
    h.recipesBar:SetPoint("RIGHT", UI.charButton, "LEFT", -14, -7)
    h.recipesLabel:SetPoint("BOTTOMLEFT", h.recipesBar, "TOPLEFT", 0, 3)
    h.recipesText:SetPoint("BOTTOMRIGHT", h.recipesBar, "TOPRIGHT", 0, 3)

    local skill = CreateStat(h, L.SKILL_LABEL)
    h.skillLabel, h.skillText = skill.label, skill.value
    h.skillBar = UI.CreateSkillBar(h, STAT_W, 10)
    h.skillBar:SetPoint("RIGHT", h.recipesBar, "LEFT", -16, -2)
    h.skillLabel:SetPoint("BOTTOMLEFT", h.skillBar, "TOPLEFT", 0, 3)
    h.skillText:SetPoint("BOTTOMRIGHT", h.skillBar, "TOPRIGHT", 0, 3)
    h.notLearned = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h.notLearned:SetPoint("LEFT", h.skillBar, "LEFT", 0, 0)
    h.notLearned:SetText(L.NOT_LEARNED_PROF)
    h.notLearned:Hide()
    return h
end

function UI.RefreshHeader()
    local h, line = UI.header, UI.state.line
    if not (h and line) then return end
    local theme = UI.Theme(line)
    h.icon:SetTexture(PROFESSION_ICONS[line] or "Interface\\Icons\\INV_Misc_QuestionMark")
    h.name:SetText(UI.ProfessionName(line))
    local r, g, b = Hex(theme.accent)
    if not (CreateColor and pcall(h.glow.SetGradient, h.glow, "HORIZONTAL",
            CreateColor(r, g, b, 0.22), CreateColor(r, g, b, 0))) then
        h.glow:SetVertexColor(r, g, b, 0.08)
    end
    if theme.watermark and UI.SetAtlas(h.watermark, theme.watermark) then
        h.watermark:Show()
    else
        h.watermark:Hide()
    end

    local skill, max = ns.CharSkill(line, UI.state.char)
    h.skillBar:SetTheme(line)
    h.skillBar:SetProgress(skill or 0, max or 0)
    h.skillBar:SetShown(skill ~= nil)
    h.skillText:SetShown(skill ~= nil)
    h.skillText:SetText(skill and ("%d / %d"):format(skill, max or 0) or "")
    h.notLearned:SetShown(skill == nil)

    local total, learned = 0, 0
    for id in pairs(ns.Data.Recipes[line] or {}) do
        total = total + 1
        if ns.IsLearned(id, UI.state.char) then learned = learned + 1 end
    end
    h.recipesText:SetText(("%d / %d"):format(learned, total))
    h.recipesBar:SetProgress(learned, total)
end

-- Character selector ---------------------------------------------------------------------------

local FACTION_ICON = {
    Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
}
local MENU_ROW_H = 22
local CHAR_W, MENU_W = 150, 250

local function SetFactionIcon(tex, faction)
    local file = FACTION_ICON[faction]
    if file then
        tex:SetTexture(file)
        tex:SetTexCoord(0, 0.6, 0, 0.6)
        tex:Show()
    else
        tex:Hide()
    end
end

function UI.CreateCharButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(CHAR_W, 24)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(Hex("0a0907"))
    b:SetBackdropBorderColor(Hex(UI.COLORS.line2))
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    b.faction = b:CreateTexture(nil, "ARTWORK")
    b.faction:SetSize(20, 20)
    b.faction:SetPoint("LEFT", 2, -2)
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetSize(16, 16)
    b.arrow:SetPoint("RIGHT", -4, 0)
    b.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", 26, 0)
    b.label:SetPoint("RIGHT", b.arrow, "LEFT", -4, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b:SetScript("OnClick", function() UI.ToggleCharMenu() end)
    return b
end

local function CreateCharMenu(parent, anchor)
    local m = UI.Panel(parent, 0.97)
    m:SetFrameStrata("DIALOG")
    m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    m:SetWidth(MENU_W)
    m:EnableMouse(true)
    m.rows = {}
    m:Hide()
    return m
end

local function MenuRow(m, i)
    if m.rows[i] then return m.rows[i] end
    local r = CreateFrame("Button", nil, m)
    r:SetHeight(MENU_ROW_H)
    r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * MENU_ROW_H)
    r:SetPoint("RIGHT", -6, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.faction = r:CreateTexture(nil, "ARTWORK")
    r.faction:SetSize(20, 20)
    r.faction:SetPoint("LEFT", 0, -2)
    r.class = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.class:SetPoint("RIGHT", -4, 0)
    r.class:SetJustifyH("RIGHT")
    r.class:SetTextColor(0.7, 0.7, 0.7)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", 24, 0)
    r.label:SetPoint("RIGHT", r.class, "LEFT", -6, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
        UI.CloseCharMenu()
        UI.SetChar(self.key)
    end)
    m.rows[i] = r
    return r
end

function UI.OpenCharMenu()
    local m = UI.charMenu
    if not m then return end
    local me, list = ns.CharKey(), ns.ListChars()
    for i, e in ipairs(list) do
        local r = MenuRow(m, i)
        r.key = e.key
        SetFactionIcon(r.faction, e.char.faction)
        local label = ns.CharLabel(e.key)
        if e.key == me then label = label .. " " .. L.YOU end
        r.label:SetText(label)
        r.class:SetText(ns.ClassName(e.char.class) or "")
        r:Show()
    end
    for i = #list + 1, #m.rows do m.rows[i]:Hide() end
    m:SetHeight(12 + #list * MENU_ROW_H)
    m:Show()
end

function UI.CloseCharMenu()
    if UI.charMenu then UI.charMenu:Hide() end
end

function UI.ToggleCharMenu()
    if UI.charMenu and UI.charMenu:IsShown() then UI.CloseCharMenu() else UI.OpenCharMenu() end
end

function UI.RefreshCharButton()
    local b = UI.charButton
    if not b then return end
    local key = UI.state.char or ns.CharKey()
    local c = key and ns.db and ns.db.chars[key]
    b.label:SetText(c and ns.CharLabel(key) or "")
    SetFactionIcon(b.faction, c and c.faction)
end

-- Toolbar ----------------------------------------------------------------------------------------

local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"
local COLLAPSE_ICON = "Interface\\Buttons\\UI-MinusButton-Up"
local EXPAND_ICON = "Interface\\Buttons\\UI-PlusButton-Up"

local function CreateToolbar(panel)
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 6, -6)
    bar:SetPoint("TOPRIGHT", -6, -6)
    bar:SetHeight(UI.BAR_H - 12)

    -- Right to left: expand all, collapse all, the filter toggle; the search box takes the rest.
    UI.expandAllButton = UI.CreateIconButton(bar, EXPAND_ICON, L.EXPAND_ALL, function() UI.ExpandAll() end)
    UI.expandAllButton:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    UI.collapseAllButton = UI.CreateIconButton(bar, COLLAPSE_ICON, L.COLLAPSE_ALL, function() UI.CollapseAll() end)
    UI.collapseAllButton:SetPoint("RIGHT", UI.expandAllButton, "LEFT", -4, 0)

    UI.filterControl = UI.CreateSegmented(bar, {
        { key = "all", label = L.FILTER_ALL },
        { key = "learned", label = L.FILTER_LEARNED },
        { key = "missing", label = L.FILTER_MISSING },
    }, function(key) UI.SetFilter(key) end)
    UI.filterControl:SetPoint("RIGHT", UI.collapseAllButton, "LEFT", -6, 0)
    UI.filterButtons = UI.filterControl.order

    local search = CreateFrame("EditBox", "ForeverProfessionalSearchBox", bar, "BackdropTemplate")
    search:SetPoint("LEFT", bar, "LEFT", 0, 0)
    search:SetPoint("RIGHT", UI.filterControl, "LEFT", -6, 0)
    search:SetHeight(22)
    search:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    search:SetBackdropColor(Hex("090807"))
    search:SetBackdropBorderColor(Hex(UI.COLORS.line2))
    search:SetFontObject(GameFontHighlightSmall)
    search:SetTextInsets(20, 6, 0, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search.icon = search:CreateTexture(nil, "OVERLAY")
    search.icon:SetSize(12, 12)
    search.icon:SetPoint("LEFT", 5, 0)
    search.icon:SetTexture(SEARCH_ICON)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.placeholder:SetPoint("LEFT", 20, 0)
    search.placeholder:SetText(L.SEARCH_RECIPES)
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.placeholder:SetShown(text == "")
        if text ~= UI.state.search then
            UI.state.search = text
            UI.RefreshList(true)
        end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    UI.searchBox = search
    bar.edge = Line(panel)
    bar.edge:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -UI.BAR_H)
    bar.edge:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -UI.BAR_H)
    bar.edge:SetHeight(1)
    return bar
end

-- Window ------------------------------------------------------------------------------------------

function UI.Create()
    if UI.frame then return UI.frame end
    if not ns.db then ns.InitDB() end
    UI.state.filter = ns.db.filter or "all"

    local f = CreateFrame("Frame", "ForeverProfessionalFrame", UIParent, "BackdropTemplate")
    UI.frame = f
    f:Hide()
    f:SetSize(UI.DEFAULT_W, UI.DEFAULT_H)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.SavePosition()
    end)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(Hex(UI.COLORS.window))
    f:SetBackdropBorderColor(Hex("4a3d2a"))
    RestorePosition(f)
    tinsert(UISpecialFrames, f:GetName())

    UI.rail = CreateRail(f)
    UI.header = CreateHeader(f)
    UI.charMenu = CreateCharMenu(f, UI.charButton)

    local top = -(UI.HEADER_H + UI.GAP)
    local listX = UI.RAIL_W + UI.GAP

    -- Middle: toolbar and recipe list
    local listPanel = UI.Panel(f)
    listPanel:SetPoint("TOPLEFT", listX, top)
    listPanel:SetPoint("BOTTOMLEFT", listX, UI.GAP)
    listPanel:SetWidth(UI.ListWidth(UI.Width()))
    f.listPanel = listPanel
    f.bar = CreateToolbar(listPanel)
    local listBody = CreateFrame("Frame", nil, listPanel)
    listBody:SetPoint("TOPLEFT", 0, -UI.BAR_H)
    listBody:SetPoint("BOTTOMRIGHT", 0, 0)
    f.listBody = listBody
    UI.CreateList(listBody)

    -- Right: detail pane (placed and sized by UI.Layout)
    local detail = UI.Panel(f)
    f.detailPanel = detail
    UI.PlaceDetailPanel()
    if UI.CreateDetail then UI.CreateDetail(detail) end

    -- Resizing from the bottom-right corner.
    f:SetResizable(true)
    local sw, sh = ScreenSize()
    if f.SetResizeBounds then
        f:SetResizeBounds(UI.MIN_W, UI.MIN_H, math.max(UI.MIN_W, sw), math.max(UI.MIN_H, sh))
    elseif f.SetMinResize then
        f:SetMinResize(UI.MIN_W, UI.MIN_H)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        UI.SavePosition()
    end)
    UI.resizeGrip = grip
    f:SetScript("OnSizeChanged", function() UI.Layout() end)

    f:SetScript("OnShow", function() UI.Refresh() end)
    f:SetScript("OnHide", function() UI.CloseCharMenu() end)
    UI.Layout()
    return f
end

-- Live sizes ----------------------------------------------------------------------------------------

function UI.Height()
    return (UI.frame and UI.frame:GetHeight()) or UI.DEFAULT_H
end

function UI.Width()
    return (UI.frame and UI.frame:GetWidth()) or UI.DEFAULT_W
end

-- The list's share of the width right of the rail, within its bounds; the detail pane gets the rest.
function UI.ListWidth(frameWidth)
    local avail = (frameWidth or UI.Width()) - UI.RAIL_W - 3 * UI.GAP
    return Clamp(math.floor(avail * LIST_SHARE), LIST_MIN, LIST_MAX)
end

function UI.DetailPanelWidth()
    local w = UI.Width()
    return w - UI.RAIL_W - 3 * UI.GAP - UI.ListWidth(w)
end

function UI.DetailContentWidth()
    return UI.DetailPanelWidth() - 36
end

function UI.PlaceDetailPanel()
    local f = UI.frame
    if not (f and f.detailPanel) then return end
    local x = UI.RAIL_W + UI.GAP + UI.ListWidth(UI.Width()) + UI.GAP
    f.detailPanel:ClearAllPoints()
    f.detailPanel:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(UI.HEADER_H + UI.GAP))
    f.detailPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, UI.GAP)
    f.detailPanel:SetWidth(UI.DetailPanelWidth())
end

-- Re-fit the panes to the window size.
function UI.Layout()
    local f = UI.frame
    if not (f and f.listPanel) then return end
    local listW = UI.ListWidth(UI.Width())
    f.listPanel:SetWidth(listW)
    if UI.list then UI.list.child:SetWidth(listW - 34) end
    UI.PlaceDetailPanel()
    if UI.EnsureRowPool then UI.EnsureRowPool() end
    if UI.LayoutDetail then UI.LayoutDetail() end
    if UI.IsShown() then
        UI.RefreshList()
        if UI.RefreshDetail then UI.RefreshDetail() end
    end
end

-- State changes ------------------------------------------------------------------------------

function UI.SelectProfession(line)
    if not ns.Data.Professions[line] then return end
    local s = UI.state
    if s.line ~= line then
        s.line = line
        s.selected = nil
        -- Scroll back to the top only once the new profession's entries exist: setting the scroll
        -- now would redraw the old entries against the new profession's recipes.
        UI.resetListScroll = true
    end
    UI.Refresh()
end

function UI.SetFilter(key)
    UI.state.filter = key
    if ns.db then ns.db.filter = key end
    if UI.filterButtons then UI.RefreshFilterButtons() end
    UI.RefreshList(true)
end

function UI.SetSearch(text)
    if UI.searchBox then
        UI.searchBox:SetText(text or "")
    else
        UI.state.search = text or ""
    end
end

-- Show another cached character. nil, the logged-in character's key or an unknown key all mean the
-- logged-in character (whose data keeps refreshing live). Profession and selection are kept.
function UI.SetChar(key)
    if key == ns.CharKey() or not (ns.db and ns.db.chars[key]) then key = nil end
    UI.state.char = key
    UI.Refresh()
end

function UI.SelectRecipe(spellID)
    UI.state.selected = spellID
    UI.RenderList()
    if UI.RefreshDetail then UI.RefreshDetail() end
end

function UI.ToggleCategory(cat)
    local c = ns.db.collapsed
    c[cat] = (not c[cat]) or nil
    UI.RefreshList()
end

-- Collapse or expand every category of the current profession. A search still shows all matches.
local function SetAllCollapsed(value)
    if not (ns.db and UI.state.line) then return end
    local M = ns.Model
    for _, id in ipairs(M.CategoryIDs(M.BuildTree(UI.state.line))) do
        ns.db.collapsed[id] = value or nil
    end
    UI.RefreshList()
end

function UI.CollapseAll() SetAllCollapsed(true) end
function UI.ExpandAll() SetAllCollapsed(false) end

-- Refresh --------------------------------------------------------------------------------------

function UI.IsShown()
    return UI.frame and UI.frame:IsShown() or false
end

function UI.RefreshFilterButtons()
    local c = UI.filterControl
    if not c then return end
    c:SetSelected(UI.state.filter)
    if UI.state.line then
        local total, learned = ns.Model.FilterCounts(UI.state.line, function(id) return ns.IsLearned(id, UI.state.char) end)
        c:SetCount("all", total)
        c:SetCount("learned", learned)
        c:SetCount("missing", total - learned)
    end
end

function UI.Refresh()
    if not UI.IsShown() then return end
    -- The shown character may have been forgotten.
    if UI.state.char and not (ns.db and ns.db.chars[UI.state.char]) then UI.state.char = nil end
    if not UI.state.line then UI.state.line = UI.DefaultProfession() end
    UI.RefreshCharButton()
    UI.RefreshRail()
    UI.RefreshHeader()
    UI.RefreshFilterButtons()
    UI.RefreshList(UI.resetListScroll)
    UI.resetListScroll = nil
    if UI.RefreshDetail then UI.RefreshDetail() end
end

function UI.Show(line)
    UI.Create()
    if line then UI.state.line = line; UI.state.selected = nil end
    if UI.frame:IsShown() then
        UI.Refresh()
    else
        UI.frame:Show()   -- OnShow refreshes
    end
end

function UI.Hide()
    if UI.frame then UI.frame:Hide() end
end

function UI.Toggle()
    if UI.IsShown() then UI.Hide() else UI.Show() end
end
