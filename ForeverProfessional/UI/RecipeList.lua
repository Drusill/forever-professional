-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Middle pane: recipes under collapsible category headers. Only the visible rows exist; they are
-- re-pointed at entries as the list scrolls.
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI

local ROW_H = 22
local INDENT = 12
UI.ROW_H = ROW_H

local CHECK_YES = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CHECK_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"

local function VisibleHeight()
    return UI.HEIGHT - (UI.TITLE_H + UI.BAR_H + 4) - (UI.PAD + 22) - 8
end

local function CreateRow(list, index)
    local row = CreateFrame("Button", nil, list.child)
    row:SetHeight(ROW_H)
    row:SetPoint("RIGHT", list.child, "RIGHT", 0, 0)
    row.index = index

    row.headerBg = row:CreateTexture(nil, "BACKGROUND")
    row.headerBg:SetAllPoints()
    if not UI.SetAtlas(row.headerBg, "loottab-set-background") then
        row.headerBg:SetColorTexture(0.35, 0.25, 0.1, 0.5)
    end

    row.selectedTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.selectedTex:SetAllPoints()
    row.selectedTex:SetColorTexture(1, 0.82, 0, 0.18)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.expand = row:CreateTexture(nil, "ARTWORK")
    row.expand:SetSize(14, 14)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)

    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(14, 14)
    row.check:SetPoint("RIGHT", -4, 0)

    row.range = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.range:SetPoint("RIGHT", row.check, "LEFT", -6, 0)
    row.range:SetJustifyH("RIGHT")

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetPoint("RIGHT", row.range, "LEFT", -6, 0)

    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.kind == "header" then
            UI.ToggleCategory(e.cat)
        else
            UI.SelectRecipe(e.id)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local e = self.entry
        if not (e and e.kind == "recipe" and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, e.id) then
            GameTooltip:SetText(M.RecipeDisplayName(e.id))
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

function UI.CreateList(parent)
    local scroll = CreateFrame("ScrollFrame", "ForeverProfessionalListScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", "ForeverProfessionalListContent", scroll)
    child:SetSize(UI.LIST_W - 34, 1)
    scroll:SetScrollChild(child)

    local list = { scroll = scroll, child = child, rows = {} }
    UI.list = list
    local visible = math.ceil(VisibleHeight() / ROW_H) + 1
    for i = 1, visible do list.rows[i] = CreateRow(list, i) end
    scroll:HookScript("OnVerticalScroll", function() UI.RenderList() end)

    list.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    list.empty:SetPoint("TOP", 0, -30)
    list.empty:SetText(L.NO_RESULTS)
    list.empty:Hide()
    return list
end

-- Rebuild the entries from the model, then render.
function UI.RefreshList(resetScroll)
    local s = UI.state
    if not (UI.list and s.line) then return end
    local tree = M.BuildTree(s.line)
    UI.entries, UI.matchCount = M.Flatten(tree, {
        filter = s.filter,
        search = s.search,
        collapsed = ns.db.collapsed,
        isLearned = function(id) return ns.IsLearned(id) end,
    })
    local list = UI.list
    local height = #UI.entries * ROW_H
    list.child:SetHeight(math.max(1, height))
    local maxScroll = math.max(0, height - VisibleHeight())
    if resetScroll or list.scroll:GetVerticalScroll() > maxScroll then
        list.scroll:SetVerticalScroll(resetScroll and 0 or maxScroll)
    end
    list.empty:SetShown(#UI.entries == 0)
    if UI.frame and UI.frame.counter and UI.RefreshCounter then UI.RefreshCounter() end
    UI.RenderList()
end

local function RenderRow(row, e, skill)
    row.entry = e
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", UI.list.child, "TOPLEFT", 0, -(row.entryIndex - 1) * ROW_H)
    row:SetPoint("RIGHT", UI.list.child, "RIGHT", 0, 0)
    local x = 4 + e.depth * INDENT
    if e.kind == "header" then
        row.headerBg:Show()
        row.selectedTex:Hide()
        row.expand:Show()
        row.expand:SetTexture(e.collapsed and PLUS or MINUS)
        row.expand:ClearAllPoints()
        row.expand:SetPoint("LEFT", x, 0)
        row.icon:Hide()
        row.check:Hide()
        row.label:SetFontObject(GameFontNormal)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.expand, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row.range, "LEFT", -6, 0)
        row.label:SetText(e.name or "?")
        row.range:SetText(("|cffb0b0b0%d/%d|r"):format(e.learned, e.count))
    else
        local rec = ns.Data.Recipes[UI.state.line][e.id]
        local learned = ns.IsLearned(e.id)
        row.headerBg:Hide()
        row.selectedTex:SetShown(e.id == UI.state.selected)
        row.expand:Hide()
        row.icon:Show()
        row.icon:SetTexture(M.RecipeIcon(e.id, rec))
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", x, 0)
        row.check:Show()
        row.check:SetTexture(learned and CHECK_YES or CHECK_NO)
        row.label:SetFontObject(GameFontHighlight)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row.range, "LEFT", -6, 0)
        row.label:SetText(M.Colored(M.Difficulty(rec, skill), M.RecipeDisplayName(e.id)))
        row.range:SetText(M.RangeText(rec, skill))
    end
    row:Show()
end

-- Point the row pool at the entries currently scrolled into view.
function UI.RenderList()
    local list = UI.list
    if not (list and UI.entries) then return end
    local first = math.floor((list.scroll:GetVerticalScroll() or 0) / ROW_H) + 1
    local skill = ns.CharSkill(UI.state.line)
    for i, row in ipairs(list.rows) do
        local index = first + i - 1
        local e = UI.entries[index]
        if e then
            row.entryIndex = index
            RenderRow(row, e, skill)
        else
            row.entry = nil
            row:Hide()
        end
    end
end
