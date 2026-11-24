-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Materials calculator: a panel over the detail pane that plans one recipe with Model.PlanMaterials and
-- draws its shopping list, craft steps and reagent tree. The plan is the model's; this file only draws.
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI
local Hex = UI.HexColor

local TOP_H = 100              -- header, quantity and tab rows above the scroll area
local QTY_ROW_H = 26           -- the quantity row, left out by sources without one
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
    return UI.Height() - UI.HEADER_H - 2 * UI.GAP - ((calc and calc.top) or TOP_H) - 8
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
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if not (self.tooltip and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
    r.slot:Show()
    r.tooltip = nil
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

-- "You" (green), an alt's class-coloured name, or "Nobody" (grey).
local function CrafterLabel(known)
    local text, kind = ns.CrafterText(known)
    if kind ~= "alt" then text = Colored(CRAFTER_COLORS[kind], text) end
    return text
end

-- The craft / buy switch of an intermediate, labelled with what a click does. Raw items and items
-- that would need themselves have none.
local function ShowSwitch(r, n)
    if not (n and n.switchable and not n.cycle) then return false end
    r.switch.item = n.item
    r.switch:SetText(n.kind == "craft" and L.CALC_BUY or L.CALC_CRAFT)
    r.switch:Show()
    return true
end

-- Item icon and name, or the recipe's icon and name when it makes no item (enchants).
local function SetSubject(r, itemID, spellID, pending)
    if itemID then
        r.slot:SetItem(itemID)
        return UI.ItemText(itemID, pending)
    end
    r.slot:SetItem(nil)
    r.slot.icon:SetTexture(M.SpellIcon(spellID) or M.QUESTION_ICON)
    return M.RecipeDisplayName(spellID)
end

local function Add(entry)
    calc.rendered[#calc.rendered + 1] = entry
end

-- Shopping: bought and raw items with have / need, what's left to buy or a check.
local function RenderShopping(plan, y, width, pending)
    for _, e in ipairs(plan.shopping) do
        local r = TakeRow(y, width, 0)
        r.slot:SetItem(e.item)
        r.name:SetText(UI.ItemText(e.item, pending))
        r.info:SetText(Colored(e.have >= e.need and "40c040" or "ffffff", L.CALC_HAVE_NEED:format(e.have, e.need)))
        r.tooltip = L.CALC_HAVE_TOOLTIP
        if e.buy > 0 then r.right:SetText(L.CALC_BUY_N:format(e.buy)) else r.check:Show() end
        local switch = plan.items[e.item].kind == "buy" and ShowSwitch(r, plan.items[e.item])
        Add({ kind = "shop", item = e.item, need = e.need, have = e.have, buy = e.buy, switch = switch, widget = r })
        y = y + ROW_H
    end
    return y
end

-- Steps: "1. Copper Bar x6", the profession, who crafts it. Intermediates can switch to buy.
local function RenderSteps(plan, y, width, pending)
    for i, st in ipairs(plan.steps) do
        local r = TakeRow(y, width, 0)
        local label = SetSubject(r, st.item, st.spellID, pending)
        r.name:SetText(L.CALC_STEP:format(i, L.CALC_TIMES:format(label, st.crafts)))
        local prof = ns.Data.Professions[st.line]
        r.info:SetText(Colored(UI.COLORS.muted, prof and prof.name or ""))
        local crafter = CrafterLabel(st.known)
        r.right:SetText(crafter)
        local switch = not st.root and ShowSwitch(r, plan.items[st.item])
        Add({ kind = "step", item = st.item, crafts = st.crafts, crafter = crafter, switch = switch, widget = r })
        y = y + ROW_H
    end
    return y
end

-- Tree: each branch's amounts, indented; who crafts each intermediate, or Buy / Raw.
local function RenderTree(plan, y, width, pending)
    local function Node(node, depth, root)
        local r = TakeRow(y, width, depth)
        y = y + ROW_H
        if node.more then
            r.slot:Hide()
            r.name:SetText(L.CALC_MORE)
            Add({ kind = "more", depth = depth, widget = r })
            return
        end
        local entry = { kind = "node", item = node.item, depth = depth, count = node.count, widget = r }
        local label = SetSubject(r, node.item, node.spellID, pending)
        if root then
            entry.info = CrafterLabel(root.known)
        else
            local n = plan.items[node.item]
            if n.kind == "craft" then entry.info = CrafterLabel(n.known)
            elseif n.kind == "buy" then entry.info = L.CALC_BUY
            else entry.info = L.CALC_RAW end
            if n.cycle then entry.note = L.CALC_CYCLE end
            entry.switch = ShowSwitch(r, n)
        end
        local text = L.CALC_TIMES:format(label, node.count)
        if entry.note then text = text .. " " .. Colored("ff8040", entry.note) end
        r.name:SetText(text)
        r.info:SetText(entry.info)
        Add(entry)
        for _, child in ipairs(node.children or {}) do Node(child, depth + 1) end
    end
    for i, tree in ipairs(plan.tree) do Node(tree, 0, plan.roots[i]) end
    return y
end

function UI.ToggleCraftMode(itemID)
    local n = calc and calc.plan and itemID and calc.plan.items[itemID]
    if not (n and n.switchable) then return end
    ns.SetCraftMode(itemID, n.kind == "craft" and "buy" or "craft")
    UI.RefreshCalculator()
end

-- Panel -----------------------------------------------------------------------------------------------
-- The panel draws a plan source:
--   { kind, title, icon, showQuantity, tabs = { {key, label}... }, Plan = fn() -> plan|nil,
--     render = { [tab] = fn(plan, y, width, pending) -> y } (extra or replaced tabs),
--     Update = fn(plan) (optional: header and quantity row), Message = fn(plan, tab) -> text|nil (optional),
--     Counts = fn(plan) -> { [tab] = n } (optional, added to the default counts) }
-- The recipe source below is the materials calculator; UI/Tracked.lua adds the tracked recipes.

local RENDER = { shopping = RenderShopping, steps = RenderSteps, tree = RenderTree }

-- Items still to buy in a plan.
local function ToBuy(plan)
    local n = 0
    for _, e in ipairs(plan.shopping) do if e.buy > 0 then n = n + 1 end end
    return n
end
UI.CalcToBuy = ToBuy

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

local RECIPE_TABS = {
    { key = "shopping", label = L.CALC_SHOPPING },
    { key = "steps", label = L.CALC_STEPS },
    { key = "tree", label = L.CALC_TREE },
}

-- The materials calculator: one recipe, its quantity in crafts or items.
local function RecipeSource(spellID, line)
    local function Rec() return ns.Data.Recipes[line] and ns.Data.Recipes[line][spellID] end
    return {
        kind = "recipe", spellID = spellID, line = line, showQuantity = true, tabs = RECIPE_TABS,
        Valid = function() return Rec() ~= nil end,
        Plan = function()
            local rec = Rec()
            if not M.MakesSeveral(rec) then calc.unitKey = "crafts" end
            local crafts = calc.unitKey == "items" and M.CraftsFor(rec, calc.quantity) or calc.quantity
            return M.PlanMaterials({ { spellID = spellID, line = line, crafts = crafts } }, ns.PlanContext())
        end,
        Update = function(plan)
            local rec, root = Rec(), plan.roots[1]
            local multi = M.MakesSeveral(rec)
            calc.unit:SetShown(multi)
            calc.icon:SetTexture(M.RecipeIcon(spellID, rec))
            calc.title:SetText(M.RecipeDisplayName(spellID))
            calc.who:SetText(L.CALC_WHO:format(CrafterLabel(root.known)))
            calc.summary:ClearAllPoints()
            calc.summary:SetPoint("LEFT", multi and calc.unit or calc.qty, "RIGHT", 8, 0)
            calc.summary:SetText(Summary(rec, root))
        end,
        Message = function(plan)
            if not plan.roots[1].reagents then return L.CALC_NO_REAGENTS end
        end,
    }
end

-- The tab control for a source's tabs, created once per set of tabs.
local function TabsFor(source)
    calc.tabSets = calc.tabSets or {}
    local set = calc.tabSets[source.tabs]
    if not set then
        set = UI.CreateSegmented(calc, source.tabs, function(key) UI.SetCalcTab(key) end)
        calc.tabSets[source.tabs] = set
    end
    return set
end

-- Show the header rows the source uses; the tab row and the list move up without a quantity row.
local function LayoutSource(source)
    local q = source.showQuantity
    calc.qtyLabel:SetShown(q)
    calc.qty:SetShown(q)
    if not q then calc.unit:Hide() end   -- the recipe source shows it for multi-output recipes
    calc.summary:SetShown(q)
    calc.who:SetShown(q)
    for _, set in pairs(calc.tabSets) do set:SetShown(set == calc.tabs) end
    calc.top = q and TOP_H or TOP_H - QTY_ROW_H
    calc.tabs:ClearAllPoints()
    calc.tabs:SetPoint("TOPLEFT", 8, -(calc.top - 32))
    calc.reset:ClearAllPoints()
    calc.reset:SetPoint("TOPRIGHT", -8, -(calc.top - 32))
    calc.rule:ClearAllPoints()
    calc.rule:SetPoint("TOPLEFT", 1, -(calc.top - 4))
    calc.rule:SetPoint("TOPRIGHT", -1, -(calc.top - 4))
    calc.scroll:ClearAllPoints()
    calc.scroll:SetPoint("TOPLEFT", 8, -calc.top)
    calc.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
end

function UI.RefreshCalculator()
    if not (calc and calc:IsShown() and calc.source) then return end
    local source = calc.source
    if source.Valid and not source.Valid() then
        UI.CloseCalculator()
        return
    end
    calc.renders = (calc.renders or 0) + 1

    local plan = source.Plan()
    calc.plan = plan
    if source.Update then source.Update(plan) end
    if not source.Update then
        calc.title:SetText(source.title or "")
        calc.icon:SetTexture(source.icon)
    end

    local toBuy = plan and ToBuy(plan) or 0
    calc.tabs:SetCount("shopping", toBuy)
    calc.tabs:SetCount("steps", plan and #plan.steps or 0)
    for key, n in pairs(source.Counts and source.Counts(plan) or {}) do calc.tabs:SetCount(key, n) end
    calc.reset:SetShown(next(ns.db.craftModes) ~= nil)

    local width = UI.DetailContentWidth()
    calc.child:SetWidth(width)
    calc.rendered = {}
    local pending, y = {}, 0
    local message = source.Message and source.Message(plan, calc.tab)
    local blocked = message ~= nil
    if not message and plan and calc.tab == "shopping" and toBuy == 0 then message = L.CALC_HAVE_ALL end
    calc.message:SetShown(message ~= nil)
    if message then
        calc.message:SetText(message)
        y = 24
    end
    local render = (source.render and source.render[calc.tab]) or RENDER[calc.tab]
    if render and not blocked then y = render(plan, y, width, pending) end
    HideUnusedRows()
    calc.child:SetHeight(y + 8)
    UI.UpdateScrollBar(calc.scroll, y + 8, UI.CalcVisibleHeight())

    UI.LoadItems(pending, function() return calc:IsShown() and calc.source == source end, UI.RefreshCalculator)
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

-- Open the panel on any plan source, on its first tab (or `tab`).
function UI.OpenPlanPanel(source, tab)
    if not (calc and source) then return end
    calc.source = source
    calc.tabs = TabsFor(source)
    LayoutSource(source)
    calc.tab = tab or source.tabs[1].key
    calc.tabs:SetSelected(calc.tab)
    calc:Show()
    calc.scroll:SetVerticalScroll(0)
    UI.RefreshCalculator()
end

function UI.OpenCalculator(spellID)
    if not (calc and spellID and UI.state.line) then return end
    calc.spellID, calc.line = spellID, UI.state.line
    calc.quantity, calc.unitKey = 1, "crafts"
    calc.unit:SetSelected("crafts")
    calc.qty:SetText("1")
    UI.OpenPlanPanel(RecipeSource(spellID, UI.state.line))
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

    calc.tabSets = {}
    calc.tabs = TabsFor({ tabs = RECIPE_TABS })
    calc.tabs:SetPoint("TOPLEFT", 8, -68)
    calc.top = TOP_H
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

-- Have / need follows the bags and bank while the panel is open.
ns.On("BAG_UPDATE_DELAYED", function() UI.RefreshCalculator() end)
