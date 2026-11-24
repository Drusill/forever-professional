-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Tracked recipes: a plan source for the calculator panel (UI/Calculator.lua) with the tracked recipes and
-- their combined shopping list, craft steps and reagent tree, plus the "Tracked n" button in the window
-- header. The list and its plan live in Characters.lua; this file only draws.
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI

local ROW_H, ROW_SLOT = 26, 20
local PAD, QTY_W, CRAFTER_W, UNTRACK_W = 6, 44, 60, 16
local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local UNTRACK_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

-- Column positions of a Recipes row; columns line up whether or not a row shows the Crafts | Items switch.
function UI.TrackedRowLayout(width, unitW)
    local untrackX = width - UNTRACK_W
    local crafterX = untrackX - PAD - CRAFTER_W
    local unitX = crafterX - PAD - (unitW or 0)
    local qtyX = unitX - PAD - QTY_W
    local nameX = ROW_SLOT + PAD
    return { nameX = nameX, nameW = qtyX - PAD - nameX, qtyX = qtyX, unitX = unitX, crafterX = crafterX,
             untrackX = untrackX }
end

-- Recipes rows ------------------------------------------------------------------------------------------

local rows = {}

UI.AddCalcPool(function()
    for _, r in ipairs(rows) do r:Hide() end
end)

-- Open a tracked recipe's detail (closes the panel, like picking it in the list).
function UI.ShowTrackedRecipe(line, spellID)
    UI.SelectProfession(line)
    UI.SelectRecipe(spellID)
end

local function CreateRow()
    local r = CreateFrame("Frame", nil, UI.calc.child)
    r:SetHeight(ROW_H)
    r.slot = UI.CreateSlot(r, ROW_SLOT)
    r.slot:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.nameButton = CreateFrame("Button", nil, r)
    r.nameButton:SetHeight(ROW_H)
    r.nameButton:SetScript("OnClick", function() UI.ShowTrackedRecipe(r.line, r.spellID) end)
    r.name = r.nameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetAllPoints()
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.qty = UI.CreateQuantityBox(r, function() return r.quantity end, function(_, n)
        ns.SetTrackedQuantity(r.spellID, math.max(1, n))
    end)
    r.unit = UI.CreateSegmented(r, {
        { key = "crafts", label = L.CALC_CRAFTS },
        { key = "items", label = L.CALC_ITEMS },
    }, function(key) ns.SetTrackedUnit(r.spellID, key) end)
    r.crafter = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.crafter:SetJustifyH("RIGHT")
    r.crafter:SetWordWrap(false)
    r.crafter:SetWidth(CRAFTER_W)
    r.untrack = UI.CreateIconButton(r, UNTRACK_ICON, L.UNTRACK, function() ns.UntrackRecipe(r.spellID) end)
    r.untrack:SetSize(UNTRACK_W, UNTRACK_W)
    return r
end

local function PlaceRow(r, y, width)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", UI.calc.child, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    local lay = UI.TrackedRowLayout(width, r.unit:GetWidth())
    r.nameButton:ClearAllPoints()
    r.nameButton:SetPoint("LEFT", r, "LEFT", lay.nameX, 0)
    r.nameButton:SetWidth(lay.nameW)
    r.qty:ClearAllPoints()
    r.qty:SetPoint("LEFT", r, "LEFT", lay.qtyX, 0)
    r.unit:ClearAllPoints()
    r.unit:SetPoint("LEFT", r, "LEFT", lay.unitX, 0)
    r.crafter:ClearAllPoints()
    r.crafter:SetPoint("LEFT", r, "LEFT", lay.crafterX, 0)
    r.untrack:ClearAllPoints()
    r.untrack:SetPoint("LEFT", r, "LEFT", lay.untrackX, 0)
end

-- One row per tracked recipe: icon and name (opens it), quantity, Crafts | Items, who crafts it, untrack.
local function RenderRecipes(plan, y, width)
    for i, e in ipairs(ns.TrackedList()) do
        local r = rows[i]
        if not r then
            r = CreateRow()
            rows[i] = r
        end
        local rec = ns.Data.Recipes[e.line][e.spellID]
        r.spellID, r.line, r.quantity = e.spellID, e.line, e.quantity
        PlaceRow(r, y, width)
        r:Show()
        r.slot:SetItem(nil)
        r.slot.icon:SetTexture(M.RecipeIcon(e.spellID, rec))
        r.name:SetText(M.RecipeDisplayName(e.spellID))
        if r.qty:GetText() ~= tostring(e.quantity) then r.qty:SetText(tostring(e.quantity)) end
        r.unit:SetShown(M.MakesSeveral(rec))
        r.unit:SetSelected(e.unit)
        local root = plan.roots[i]   -- the plan's roots follow the list's order
        local crafter = UI.CrafterLabel(root and root.known)
        r.crafter:SetText(crafter)
        local rendered = UI.calc.rendered
        rendered[#rendered + 1] = { kind = "tracked", spellID = e.spellID, quantity = e.quantity, unit = e.unit,
            crafter = crafter, widget = r }
        y = y + ROW_H
    end
    return y
end

-- The tracked source ---------------------------------------------------------------------------------------

local source = {
    kind = "tracked", title = L.TRACKED_TITLE, icon = ICON, showQuantity = false,
    tabs = {
        { key = "recipes", label = L.TRACKED_RECIPES },
        { key = "shopping", label = L.CALC_SHOPPING },
        { key = "steps", label = L.CALC_STEPS },
        { key = "tree", label = L.CALC_TREE },
    },
    Plan = function()
        local plan = ns.TrackedPlan()
        return plan
    end,
    Counts = function() return { recipes = #ns.TrackedList() } end,
    Message = function(plan)
        if not plan then return L.TRACKED_EMPTY end
    end,
    render = { recipes = RenderRecipes },
}

function UI.IsTrackedShown()
    return UI.calc ~= nil and UI.calc:IsShown() and UI.calc.source == source
end

function UI.OpenTracked()
    UI.OpenPlanPanel(source)
end

function UI.ToggleTrackedPanel()
    if UI.IsTrackedShown() then UI.CloseCalculator() else UI.OpenTracked() end
end

-- Header button ---------------------------------------------------------------------------------------------

function UI.CreateTrackedButton(parent)
    local b = UI.CreateToggleButton(parent, L.TRACKED, function() UI.ToggleTrackedPanel() end)
    b:SetHeight(22)
    return b
end

-- "Tracked" or "Tracked n", highlighted while the panel is open.
function UI.RefreshTrackedButton()
    local b = UI.headerTracked
    if not b then return end
    local n = #ns.TrackedList()
    b:SetText(n > 0 and L.TRACKED_N:format(n) or L.TRACKED)
    b:SetActive(UI.IsTrackedShown())
end
