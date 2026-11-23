-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Middle pane: recipes under collapsible category headers, two lines per recipe. Only the visible
-- rows exist; they are re-pointed at entries as the list scrolls. Headers and recipes have
-- different heights, so entries are placed by their running offset (UI.entryTop).
local _, ns = ...
local L = ns.L
local M = ns.Model
local UI = ns.UI
local Hex = UI.HexColor

UI.HEADER_ROW_H = 24
UI.RECIPE_ROW_H = 34
local INDENT = 12
local ICON = 26
local CHEVRON = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local OPEN, CLOSED = -math.pi / 2, 0

-- Height of the list's scroll area: below the header and the toolbar, less the panel gaps and insets.
function UI.ListVisibleHeight()
    return UI.Height() - UI.HEADER_H - 2 * UI.GAP - UI.BAR_H - 8
end

local function EntryHeight(e)
    return e.kind == "header" and UI.HEADER_ROW_H or UI.RECIPE_ROW_H
end

local function CreateRow(list, index)
    local row = CreateFrame("Button", nil, list.child)
    row:SetHeight(UI.RECIPE_ROW_H)
    row:SetPoint("RIGHT", list.child, "RIGHT", 0, 0)
    row.index = index

    -- Header look: a gold-to-dark band with a top rule.
    row.headerBg = row:CreateTexture(nil, "BACKGROUND")
    row.headerBg:SetAllPoints()
    row.headerBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    if not (CreateColor and pcall(row.headerBg.SetGradient, row.headerBg, "HORIZONTAL",
            CreateColor(0.165, 0.133, 0.086, 1), CreateColor(0.094, 0.078, 0.059, 1))) then
        row.headerBg:SetVertexColor(0.14, 0.11, 0.07, 1)
    end
    row.headerRule = row:CreateTexture(nil, "BORDER")
    row.headerRule:SetPoint("TOPLEFT")
    row.headerRule:SetPoint("TOPRIGHT")
    row.headerRule:SetHeight(1)
    row.headerRule:SetColorTexture(Hex("33291b"))

    -- Selection: a light gold tint and a gold left edge.
    row.selectedTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.selectedTex:SetAllPoints()
    row.selectedTex:SetColorTexture(1, 0.82, 0, 0.11)
    row.selectedEdge = row:CreateTexture(nil, "BORDER")
    row.selectedEdge:SetPoint("TOPLEFT")
    row.selectedEdge:SetPoint("BOTTOMLEFT")
    row.selectedEdge:SetWidth(2)
    row.selectedEdge:SetColorTexture(1, 0.82, 0, 1)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.expand = row:CreateTexture(nil, "ARTWORK")
    row.expand:SetSize(12, 12)
    row.expand:SetTexture(CHEVRON)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)

    row.status = row:CreateTexture(nil, "OVERLAY")
    row.status:SetSize(14, 14)
    row.status:SetPoint("RIGHT", -6, 0)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", -8, 0)
    row.count:SetJustifyH("RIGHT")
    row.count:SetTextColor(Hex(UI.COLORS.muted))
    row.progress = UI.CreateProgressBar(row, 34, 4)
    row.progress:SetPoint("RIGHT", row.count, "LEFT", -6, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.sub:SetTextColor(Hex(UI.COLORS.muted))

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

-- Enough rows to cover the visible height with the smaller row height, plus two partial ones.
function UI.EnsureRowPool()
    local list = UI.list
    if not list then return end
    local needed = math.ceil(UI.ListVisibleHeight() / UI.HEADER_ROW_H) + 2
    for i = #list.rows + 1, needed do list.rows[i] = CreateRow(list, i) end
end

function UI.CreateList(parent)
    local scroll = CreateFrame("ScrollFrame", "ForeverProfessionalListScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", "ForeverProfessionalListContent", scroll)
    child:SetSize(UI.ListWidth(UI.Width()) - 34, 1)
    scroll:SetScrollChild(child)
    UI.StyleScroll(scroll)

    local list = { scroll = scroll, child = child, rows = {} }
    UI.list = list
    UI.EnsureRowPool()
    scroll:HookScript("OnVerticalScroll", function() UI.RenderList() end)

    list.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    list.empty:SetPoint("TOP", 0, -30)
    list.empty:SetText(L.NO_RESULTS)
    list.empty:Hide()
    list.clearButton = UI.CreateToggleButton(parent, L.CLEAR_FILTERS, function() UI.ClearFilters() end)
    list.clearButton:SetPoint("TOP", list.empty, "BOTTOM", 0, -10)
    list.clearButton:Hide()
    return list
end

-- Index of the entry at the given scroll offset (the last entry starting at or above it).
function UI.FirstVisible(offset)
    local tops = UI.entryTop
    if not tops or #tops == 0 then return 1 end
    local lo, hi = 1, #tops
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if tops[mid] <= offset then lo = mid else hi = mid - 1 end
    end
    return lo
end

-- Rebuild the entries from the model, then render.
function UI.RefreshList(resetScroll)
    local s = UI.state
    if not (UI.list and s.line) then return end
    local tree = M.BuildTree(s.line)
    local predicates = UI.MenuPredicates()
    local learned = M.LearnedPredicate(s.filter)
    if learned then table.insert(predicates, 1, learned) end
    UI.entries, UI.matchCount = M.Flatten(tree, {
        predicates = predicates,
        search = s.search,
        collapsed = ns.db.collapsed,
        isLearned = function(id) return ns.IsLearned(id, s.char) end,
    })
    local tops, y = {}, 0
    for i, e in ipairs(UI.entries) do
        tops[i] = y
        y = y + EntryHeight(e)
    end
    UI.entryTop, UI.contentHeight = tops, y

    local list = UI.list
    local visible = UI.ListVisibleHeight()
    list.child:SetHeight(math.max(1, y))
    UI.UpdateScrollBar(list.scroll, y, visible)
    local maxScroll = math.max(0, y - visible)
    if resetScroll or list.scroll:GetVerticalScroll() > maxScroll then
        list.scroll:SetVerticalScroll(resetScroll and 0 or maxScroll)
    end
    local empty, filtered = #UI.entries == 0, UI.ActiveFilterCount() > 0
    list.empty:SetText(filtered and L.NO_RESULTS_FILTERED or L.NO_RESULTS)
    list.empty:SetShown(empty)
    list.clearButton:SetShown(empty and filtered)
    UI.RenderList()
end

-- After a size change: same entries, new visible height. Grow the pool, keep the scroll in range,
-- update the scrollbar and redraw.
function UI.RelayoutList()
    local list = UI.list
    if not list then return end
    UI.EnsureRowPool()
    if not UI.entries then return end
    local visible, height = UI.ListVisibleHeight(), UI.contentHeight or 0
    UI.UpdateScrollBar(list.scroll, height, visible)
    local maxScroll = math.max(0, height - visible)
    if list.scroll:GetVerticalScroll() > maxScroll then list.scroll:SetVerticalScroll(maxScroll) end
    UI.RenderList()
end

local function RenderHeader(row, e, x)
    row:SetHeight(UI.HEADER_ROW_H)
    row.headerBg:Show()
    row.headerRule:Show()
    row.selectedTex:Hide()
    row.selectedEdge:Hide()
    row.icon:Hide()
    row.status:Hide()
    row.sub:Hide()
    row.expand:Show()
    row.expand:SetRotation(e.collapsed and CLOSED or OPEN)
    row.expand:ClearAllPoints()
    row.expand:SetPoint("LEFT", x, 0)
    row.count:Show()
    row.count:SetText(("%d/%d"):format(e.learned, e.count))
    row.progress:Show()
    row.progress:SetProgress(e.learned, e.count)
    row.label:SetFontObject(GameFontNormal)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.expand, "RIGHT", 4, 0)
    row.label:SetPoint("RIGHT", row.progress, "LEFT", -6, 0)
    row.label:SetText(e.name or "?")
end

local function RenderRecipe(row, e, x, skill, faction)
    local rec = ns.Data.Recipes[UI.state.line][e.id]
    local learned = ns.IsLearned(e.id, UI.state.char)
    row:SetHeight(UI.RECIPE_ROW_H)
    row.headerBg:Hide()
    row.headerRule:Hide()
    local selected = (e.id == UI.state.selected)
    row.selectedTex:SetShown(selected)
    row.selectedEdge:SetShown(selected)
    row.expand:Hide()
    row.count:Hide()
    row.progress:Hide()
    row.icon:Show()
    row.icon:SetTexture(M.RecipeIcon(e.id, rec))
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", x, 0)
    row.status:Show()
    if learned then
        UI.SetIcon(row.status, UI.SOURCE_ICONS.check)
    else
        local p = M.PrimarySource(rec, faction)
        UI.SetIcon(row.status, UI.SOURCE_ICONS[p.type] or UI.SOURCE_ICONS.unknown)
    end
    row.label:SetFontObject(GameFontHighlight)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.label:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.label:SetText(M.Colored(M.Difficulty(rec, skill, learned), M.RecipeDisplayName(e.id)))
    row.sub:Show()
    row.sub:ClearAllPoints()
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.sub:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.sub:SetText(M.RowSubtitle(rec, skill, learned, faction))
end

-- Point the row pool at the entries currently scrolled into view.
function UI.RenderList()
    local list = UI.list
    if not (list and UI.entries) then return end
    local first = UI.FirstVisible(list.scroll:GetVerticalScroll() or 0)
    local skill = ns.CharSkill(UI.state.line, UI.state.char)
    local faction = ns.CharFaction(UI.state.char)
    for i, row in ipairs(list.rows) do
        local index = first + i - 1
        local e = UI.entries[index]
        if e then
            row.entryIndex = index
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -UI.entryTop[index])
            row:SetPoint("RIGHT", list.child, "RIGHT", 0, 0)
            local x = 6 + e.depth * INDENT
            if e.kind == "header" then RenderHeader(row, e, x) else RenderRecipe(row, e, x, skill, faction) end
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end
