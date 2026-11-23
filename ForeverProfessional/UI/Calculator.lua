-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Materials calculator: a panel over the detail pane that plans one recipe with Model.PlanMaterials and
-- draws its shopping list, craft steps and reagent tree. The plan is the model's; this file only draws.
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI
local Hex = UI.HexColor

local TOP_H = 100              -- header, quantity and tab rows above the scroll area
local ROW_H, ROW_SLOT = 24, 20
local INDENT = 12
local INFO_W, SWITCH_W, RIGHT_W, PAD = 70, 46, 50, 6
local QTY_MAX = 999
local BACK_ICON = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local CHECK_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CRAFTER_COLORS = { me = "40c040", alt = "ffd100", nobody = "909090" }

local calc

-- Column positions of a row at an indent depth: the name takes what the fixed columns leave.
function UI.CalcRowLayout(width, depth)
    local x = (depth or 0) * INDENT
    local nameX = x + ROW_SLOT + PAD
    local rightX = width - RIGHT_W
    local switchX = rightX - PAD - SWITCH_W
    local infoX = switchX - PAD - INFO_W
    return { x = x, nameX = nameX, nameW = infoX - PAD - nameX, infoX = infoX, switchX = switchX, rightX = rightX }
end

function UI.CalcVisibleHeight()
    return UI.Height() - UI.HEADER_H - 2 * UI.GAP - TOP_H - 8
end

-- Rows ------------------------------------------------------------------------------------------------

local used = 0

local function CreateRow()
    local r = CreateFrame("Frame", nil, calc.child)
    r:SetHeight(ROW_H)
    r.slot = UI.CreateSlot(r, ROW_SLOT)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetJustifyH("RIGHT")
    r.info:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetJustifyH("RIGHT")
    r.right:SetWordWrap(false)
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetSize(14, 14)
    r.check:SetTexture(CHECK_ICON)
    r.switch = UI.CreateToggleButton(r, "", function(b) UI.ToggleCraftMode(b.item) end)
    r.switch:SetHeight(18)
    return r
end

local function TakeRow(y, width, depth)
    used = used + 1
    local r = calc.rows[used]
    if not r then
        r = CreateRow()
        calc.rows[used] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", calc.child, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r:Show()
    local lay = UI.CalcRowLayout(width, depth)
    r.slot:ClearAllPoints()
    r.slot:SetPoint("LEFT", r, "LEFT", lay.x, 0)
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r, "LEFT", lay.nameX, 0)
    r.name:SetWidth(lay.nameW)
    r.info:ClearAllPoints()
    r.info:SetPoint("LEFT", r, "LEFT", lay.infoX, 0)
    r.info:SetWidth(INFO_W)
    r.switch:ClearAllPoints()
    r.switch:SetPoint("LEFT", r, "LEFT", lay.switchX, 0)
    r.right:ClearAllPoints()
    r.right:SetPoint("LEFT", r, "LEFT", lay.rightX, 0)
    r.right:SetWidth(RIGHT_W)
    r.check:ClearAllPoints()
    r.check:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.info:SetText("")
    r.right:SetText("")
    r.check:Hide()
    r.switch:Hide()
    r.switch.item = nil
    return r
end

local function HideUnusedRows()
    for i = used + 1, #calc.rows do calc.rows[i]:Hide() end
    used = 0
end

local function Colored(hex, text) return "|cff" .. hex .. text .. "|r" end

-- Shopping: bought and raw items with have / need, what's left to buy or a check.
local function RenderShopping(plan, y, width, pending)
    for _, e in ipairs(plan.shopping) do
        local r = TakeRow(y, width, 0)
        r.slot:SetItem(e.item)
        r.name:SetText(UI.ItemText(e.item, pending))
        r.info:SetText(Colored(e.have >= e.need and "40c040" or "ffffff", L.CALC_HAVE_NEED:format(e.have, e.need)))
        if e.buy > 0 then r.right:SetText(L.CALC_BUY_N:format(e.buy)) else r.check:Show() end
        calc.rendered[#calc.rendered + 1] = { kind = "shop", item = e.item, need = e.need, have = e.have, buy = e.buy }
        y = y + ROW_H
    end
    return y
end

-- Panel -----------------------------------------------------------------------------------------------

local function Summary(rec, root)
    if not rec.creates then return "" end
    if calc.unitKey == "items" then
        local extra = root.makes - calc.quantity
        if root.crafts == 1 then return L.CALC_EXTRA_ONE:format(extra) end
        return L.CALC_EXTRA:format(root.crafts, extra)
    end
    if root.crafts == 1 then return L.CALC_MAKES_ONE:format(root.makes) end
    return L.CALC_MAKES:format(root.crafts, root.makes)
end

function UI.RefreshCalculator()
    if not (calc and calc:IsShown()) then return end
    local spellID, line = calc.spellID, calc.line
    local rec = ns.Data.Recipes[line] and ns.Data.Recipes[line][spellID]
    if not rec then
        UI.CloseCalculator()
        return
    end
    calc.renders = (calc.renders or 0) + 1

    local multi = rec.creates ~= nil and (M.Yield(rec) > 1 or type(rec.count) == "table")
    calc.unit:SetShown(multi)
    if not multi then calc.unitKey = "crafts" end
    local crafts = calc.unitKey == "items" and M.CraftsFor(rec, calc.quantity) or calc.quantity
    local plan = M.PlanMaterials({ { spellID = spellID, line = line, crafts = crafts } }, ns.PlanContext())
    calc.plan = plan
    local root = plan.roots[1]

    calc.icon:SetTexture(M.RecipeIcon(spellID, rec))
    calc.title:SetText(M.RecipeDisplayName(spellID))
    local who, kind = ns.CrafterText(root.known)
    if kind ~= "alt" then who = Colored(CRAFTER_COLORS[kind], who) end
    calc.who:SetText(L.CALC_WHO:format(who))
    calc.summary:ClearAllPoints()
    calc.summary:SetPoint("LEFT", multi and calc.unit or calc.qty, "RIGHT", 8, 0)
    calc.summary:SetText(Summary(rec, root))

    local toBuy = 0
    for _, e in ipairs(plan.shopping) do if e.buy > 0 then toBuy = toBuy + 1 end end
    calc.tabs:SetCount("shopping", toBuy)
    calc.tabs:SetCount("steps", #plan.steps)
    calc.reset:SetShown(next(ns.db.craftModes) ~= nil)

    local width = UI.DetailContentWidth()
    calc.child:SetWidth(width)
    calc.rendered = {}
    local pending, y = {}, 0
    local message
    if not root.reagents then
        message = L.CALC_NO_REAGENTS
    elseif calc.tab == "shopping" and toBuy == 0 then
        message = L.CALC_HAVE_ALL
    end
    calc.message:SetShown(message ~= nil)
    if message then
        calc.message:SetText(message)
        y = 24
    end
    if root.reagents then
        if calc.tab == "shopping" then y = RenderShopping(plan, y, width, pending)
        elseif calc.tab == "steps" and UI.RenderCalcSteps then y = UI.RenderCalcSteps(plan, y, width, pending)
        elseif calc.tab == "tree" and UI.RenderCalcTree then y = UI.RenderCalcTree(plan, y, width, pending) end
    end
    HideUnusedRows()
    calc.child:SetHeight(y + 8)
    UI.UpdateScrollBar(calc.scroll, y + 8, UI.CalcVisibleHeight())

    UI.LoadItems(pending, function() return calc:IsShown() and calc.spellID == spellID end, UI.RefreshCalculator)
end

-- Number of crafts or items wanted, 1 to 999; anything else is ignored.
function UI.SetCalcQuantity(n)
    n = tonumber(n)
    if not (calc and n) then return end
    n = math.max(1, math.min(QTY_MAX, math.floor(n)))
    calc.quantity = n
    if calc.qty:GetText() ~= tostring(n) then calc.qty:SetText(tostring(n)) end
    UI.RefreshCalculator()
end

function UI.SetCalcUnit(key)
    if not calc then return end
    calc.unitKey = key == "items" and "items" or "crafts"
    calc.unit:SetSelected(calc.unitKey)
    UI.RefreshCalculator()
end

function UI.SetCalcTab(key)
    if not calc then return end
    calc.tab = key
    calc.tabs:SetSelected(key)
    calc.scroll:SetVerticalScroll(0)
    UI.RefreshCalculator()
end

function UI.OpenCalculator(spellID)
    if not (calc and spellID and UI.state.line) then return end
    calc.spellID, calc.line = spellID, UI.state.line
    calc.quantity, calc.unitKey, calc.tab = 1, "crafts", "shopping"
    calc.unit:SetSelected("crafts")
    calc.tabs:SetSelected("shopping")
    calc.qty:SetText("1")
    calc:Show()
    calc.scroll:SetVerticalScroll(0)
    UI.RefreshCalculator()
end

function UI.CloseCalculator()
    if calc then calc:Hide() end
end

function UI.IsCalculatorShown()
    return calc ~= nil and calc:IsShown()
end

local function CreateQuantityBox(parent)
    local q = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    q:SetSize(44, 22)
    q:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    q:SetBackdropColor(Hex("090807"))
    q:SetBackdropBorderColor(Hex(UI.COLORS.line2))
    q:SetFontObject(GameFontHighlightSmall)
    q:SetJustifyH("CENTER")
    q:SetAutoFocus(false)
    q:SetNumeric(true)
    q:SetMaxLetters(3)
    q:SetScript("OnTextChanged", function(self)
        local n = tonumber(self:GetText() or "")
        if n and n ~= calc.quantity then UI.SetCalcQuantity(n) end
    end)
    -- Empty or invalid text goes back to the last valid number.
    local function Restore(self)
        self:ClearFocus()
        if self:GetText() ~= tostring(calc.quantity) then self:SetText(tostring(calc.quantity)) end
    end
    q:SetScript("OnEditFocusLost", Restore)
    q:SetScript("OnEnterPressed", Restore)
    q:SetScript("OnEscapePressed", Restore)
    return q
end

function UI.CreateCalculator(parent)
    calc = UI.Panel(parent, 1)
    UI.calc = calc
    calc:SetAllPoints(parent)
    calc:SetFrameLevel(parent:GetFrameLevel() + 20)
    calc:EnableMouse(true)
    calc.rows, calc.rendered = {}, {}
    calc.quantity, calc.unitKey, calc.tab = 1, "crafts", "shopping"

    calc.back = UI.CreateIconButton(calc, BACK_ICON, L.CALC_BACK, function() UI.CloseCalculator() end)
    calc.back:SetPoint("TOPLEFT", 8, -8)
    calc.back.icon:SetRotation(math.pi)
    calc.icon = calc:CreateTexture(nil, "ARTWORK")
    calc.icon:SetSize(20, 20)
    calc.icon:SetPoint("LEFT", calc.back, "RIGHT", 8, 0)
    calc.who = calc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    calc.who:SetPoint("TOPRIGHT", -10, -14)
    calc.who:SetJustifyH("RIGHT")
    calc.title = calc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    calc.title:SetPoint("LEFT", calc.icon, "RIGHT", 6, 0)
    calc.title:SetPoint("RIGHT", calc.who, "LEFT", -8, 0)
    calc.title:SetJustifyH("LEFT")
    calc.title:SetWordWrap(false)

    calc.qtyLabel = calc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    calc.qtyLabel:SetPoint("TOPLEFT", 10, -45)
    calc.qtyLabel:SetText(L.CALC_QUANTITY)
    calc.qtyLabel:SetTextColor(Hex(UI.COLORS.muted))
    calc.qty = CreateQuantityBox(calc)
    calc.qty:SetPoint("LEFT", calc.qtyLabel, "RIGHT", 6, 0)
    calc.unit = UI.CreateSegmented(calc, {
        { key = "crafts", label = L.CALC_CRAFTS },
        { key = "items", label = L.CALC_ITEMS },
    }, function(key) UI.SetCalcUnit(key) end)
    calc.unit:SetPoint("LEFT", calc.qty, "RIGHT", 8, 0)
    calc.summary = calc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    calc.summary:SetJustifyH("LEFT")
    calc.summary:SetTextColor(Hex(UI.COLORS.muted))

    calc.tabs = UI.CreateSegmented(calc, {
        { key = "shopping", label = L.CALC_SHOPPING },
        { key = "steps", label = L.CALC_STEPS },
        { key = "tree", label = L.CALC_TREE },
    }, function(key) UI.SetCalcTab(key) end)
    calc.tabs:SetPoint("TOPLEFT", 8, -68)
    calc.reset = UI.CreateToggleButton(calc, L.CALC_RESET, function()
        ns.ResetCraftModes()
        UI.RefreshCalculator()
    end)
    calc.reset:SetPoint("TOPRIGHT", -8, -68)

    calc.rule = calc:CreateTexture(nil, "BORDER")
    calc.rule:SetPoint("TOPLEFT", 1, -(TOP_H - 4))
    calc.rule:SetPoint("TOPRIGHT", -1, -(TOP_H - 4))
    calc.rule:SetHeight(1)
    calc.rule:SetColorTexture(Hex(UI.COLORS.line))

    local scroll = CreateFrame("ScrollFrame", "ForeverProfessionalCalcScroll", calc, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -TOP_H)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", "ForeverProfessionalCalcContent", scroll)
    child:SetSize(UI.DetailContentWidth(), 1)
    scroll:SetScrollChild(child)
    UI.StyleScroll(scroll)
    calc.scroll, calc.child = scroll, child
    calc.message = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    calc.message:SetPoint("TOPLEFT", 0, -4)
    calc.message:SetJustifyH("LEFT")
    calc:Hide()
end

-- After a size change: redraw for the new width.
function UI.LayoutCalculator()
    if calc and calc:IsShown() then UI.RefreshCalculator() end
end
