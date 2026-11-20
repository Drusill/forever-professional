-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Main window: frame, Encounter Journal art, profession tabs, filter bar and search box.
local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

UI.WIDTH, UI.HEIGHT = 1040, 640
UI.PAD = 12
UI.TITLE_H = 40
UI.TAB_W = 190
UI.LIST_W = 400
UI.BAR_H = 30

UI.state = { line = nil, filter = "all", search = "", selected = nil }

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

-- Art helpers -------------------------------------------------------------------------------

-- Set an atlas only if the client has it; returns false so the caller can fall back.
function UI.SetAtlas(tex, atlas)
    if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(atlas) then return false end
    return (pcall(tex.SetAtlas, tex, atlas)) and true or false
end

function UI.Panel(parent, alpha)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    p:SetBackdropColor(0, 0, 0, alpha or 0.45)
    p:SetBackdropBorderColor(0.6, 0.5, 0.35, 0.9)
    return p
end

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

function UI.DefaultProfession()
    local _, order = ns.GetPlayerProfessions()
    return order[1] or UI.ProfessionOrder()[1]
end

-- Frame ------------------------------------------------------------------------------------

function UI.SavePosition()
    local point, _, relPoint, x, y = UI.frame:GetPoint()
    if point and ns.db then ns.db.window = { point = point, relPoint = relPoint, x = x, y = y } end
end

local function RestorePosition(f)
    f:ClearAllPoints()
    local w = ns.db and ns.db.window
    if w and w.point then
        f:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function CreateTab(parent, line, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(UI.TAB_W - 12, 38)
    b:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 40)

    b.selectedTex = b:CreateTexture(nil, "BACKGROUND")
    b.selectedTex:SetAllPoints()
    if not UI.SetAtlas(b.selectedTex, "loottab-set-background") then
        b.selectedTex:SetColorTexture(1, 0.82, 0, 0.18)
    end
    b.selectedTex:Hide()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(30, 30)
    b.icon:SetPoint("LEFT", 4, 0)
    b.icon:SetTexture(PROFESSION_ICONS[line] or "Interface\\Icons\\INV_Misc_QuestionMark")

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.label:SetPoint("RIGHT", -4, 0)
    b.label:SetJustifyH("LEFT")

    b.skill = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.skill:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 1)
    b.skill:SetJustifyH("LEFT")

    b.line = line
    b:SetScript("OnClick", function() UI.SelectProfession(line) end)
    return b
end

local function CreateFilterButton(parent, key, label, x)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(78, 22)
    b:SetPoint("LEFT", x, 0)
    b:SetText(label)
    b.key = key
    b:SetScript("OnClick", function() UI.SetFilter(key) end)
    return b
end

function UI.Create()
    if UI.frame then return UI.frame end
    if not ns.db then ns.InitDB() end
    UI.state.filter = ns.db.filter or "all"

    local f = CreateFrame("Frame", "ForeverProfessionalFrame", UIParent, "BackdropTemplate")
    UI.frame = f
    f:Hide()
    f:SetSize(UI.WIDTH, UI.HEIGHT)
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
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, edgeSize = 26,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetBackdropColor(0.06, 0.05, 0.04, 0.97)
    RestorePosition(f)
    tinsert(UISpecialFrames, f:GetName())

    -- Encounter Journal background (the journal inset region of the texture).
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 8, -8)
    bg:SetPoint("BOTTOMRIGHT", -8, 8)
    bg:SetTexture("Interface\\EncounterJournal\\UI-EJ-JournalBG")
    bg:SetTexCoord(0, 0.7686, 0, 0.8301)
    bg:SetVertexColor(0.55, 0.55, 0.55, 1)
    f.bg = bg

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", UI.PAD + 8, -16)
    f.title:SetText(L.TITLE)

    f.close = CreateFrame("Button", "ForeverProfessionalFrameClose", f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -6, -6)
    f.close:SetScript("OnClick", function() UI.Hide() end)

    -- Left: profession tabs
    local tabs = UI.Panel(f, 0.35)
    tabs:SetPoint("TOPLEFT", UI.PAD, -UI.TITLE_H)
    tabs:SetPoint("BOTTOMLEFT", UI.PAD, UI.PAD)
    tabs:SetWidth(UI.TAB_W)
    f.tabPanel = tabs
    UI.tabs = {}
    for i, line in ipairs(UI.ProfessionOrder()) do
        UI.tabs[#UI.tabs + 1] = CreateTab(tabs, line, i)
    end

    -- Filter bar above the list
    local listX = UI.PAD + UI.TAB_W + 8
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", listX, -UI.TITLE_H)
    bar:SetSize(UI.LIST_W, UI.BAR_H)
    f.bar = bar
    UI.filterButtons = {
        CreateFilterButton(bar, "all", L.FILTER_ALL, 0),
        CreateFilterButton(bar, "learned", L.FILTER_LEARNED, 80),
        CreateFilterButton(bar, "missing", L.FILTER_MISSING, 160),
    }

    local search = CreateFrame("EditBox", "ForeverProfessionalSearchBox", bar, "InputBoxTemplate")
    search:SetSize(UI.LIST_W - 252, 20)
    search:SetPoint("LEFT", 252, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    search.placeholder:SetPoint("LEFT", 2, 0)
    search.placeholder:SetText(L.SEARCH)
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

    -- Middle: recipe list
    local listPanel = UI.Panel(f, 0.4)
    listPanel:SetPoint("TOPLEFT", listX, -(UI.TITLE_H + UI.BAR_H + 4))
    listPanel:SetPoint("BOTTOMLEFT", listX, UI.PAD + 22)
    listPanel:SetWidth(UI.LIST_W)
    f.listPanel = listPanel
    UI.CreateList(listPanel)

    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.counter:SetPoint("BOTTOMLEFT", listX + 4, UI.PAD + 5)
    f.counter:SetJustifyH("LEFT")

    -- Right: detail pane
    local detail = UI.Panel(f, 0.4)
    detail:SetPoint("TOPLEFT", listX + UI.LIST_W + 8, -UI.TITLE_H)
    detail:SetPoint("BOTTOMRIGHT", -UI.PAD, UI.PAD)
    f.detailPanel = detail
    if UI.CreateDetail then UI.CreateDetail(detail) end

    f:SetScript("OnShow", function() UI.Refresh() end)
    return f
end

-- State changes ------------------------------------------------------------------------------

function UI.SelectProfession(line)
    if not ns.Data.Professions[line] then return end
    local s = UI.state
    if s.line ~= line then
        s.line = line
        s.selected = nil
        if UI.list then UI.list.scroll:SetVerticalScroll(0) end
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

-- Refresh --------------------------------------------------------------------------------------

function UI.IsShown()
    return UI.frame and UI.frame:IsShown() or false
end

function UI.RefreshTabs()
    for _, b in ipairs(UI.tabs) do
        b.label:SetText(UI.ProfessionName(b.line))
        local skill, max = ns.CharSkill(b.line)
        if skill then
            b.skill:SetText(L.SKILL:format(skill, max or 0))
            b.skill:SetTextColor(1, 1, 1)
        else
            b.skill:SetText(L.NOT_LEARNED_PROF)
            b.skill:SetTextColor(0.5, 0.5, 0.5)
        end
        b.selectedTex:SetShown(b.line == UI.state.line)
        if b.line == UI.state.line then b:LockHighlight() else b:UnlockHighlight() end
    end
end

function UI.RefreshFilterButtons()
    for _, b in ipairs(UI.filterButtons) do
        if b.key == UI.state.filter then b:LockHighlight() else b:UnlockHighlight() end
    end
end

function UI.RefreshCounter()
    local recipes = ns.Data.Recipes[UI.state.line] or {}
    local total, learned = 0, 0
    for id in pairs(recipes) do
        total = total + 1
        if ns.IsLearned(id) then learned = learned + 1 end
    end
    UI.frame.counter:SetText(L.COUNT:format(learned, total))
end

function UI.Refresh()
    if not UI.IsShown() then return end
    if not UI.state.line then UI.state.line = UI.DefaultProfession() end
    UI.RefreshTabs()
    UI.RefreshFilterButtons()
    UI.RefreshCounter()
    UI.RefreshList()
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
