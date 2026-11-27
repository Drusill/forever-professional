-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Options window: our own small frame (not a Blizzard Settings category, which would need opening a
-- Blizzard panel from addon code). Each row is a saved setting, applied as soon as it's clicked.
local _, ns = ...
local L = ns.L
local UI = ns.UI

local W, PAD, ROW_H, HEADER_H, GAP, INDENT = 320, 14, 22, 18, 8, 18

-- Rows in display order. A row without get/set is a boolean in ns.db named by its key.
local function Rows()
    return {
        { group = L.OPTIONS_MINIMAP, key = "minimap", label = L.OPTIONS_SHOW_MINIMAP,
            get = function() return not ns.db.minimapHidden end,
            set = function(v) ns.MinimapButton.SetHidden(not v) end },
        { group = L.OPTIONS_TOOLTIPS, key = "tooltipOwners", label = L.OPTIONS_OWNERS },
        { key = "tooltipTracked", label = L.OPTIONS_TRACKED },
        { key = "tooltipUsedIn", label = L.OPTIONS_USED_IN,
            -- The index is built only while its lines are on; a stopped build resumes where it was.
            after = function(v) if v then ns.UsedIn.Start() else ns.UsedIn.Stop() end end },
        { key = "tooltipUsedInNames", label = L.OPTIONS_USED_IN_NAMES, indent = INDENT,
            enabledBy = "tooltipUsedIn" },
    }
end

local function Get(def)
    if def.get then return def.get() end
    return ns.Setting(def.key) and true or false
end

local function Set(def, v)
    if def.set then def.set(v) else ns.db[def.key] = v end
    if def.after then def.after(v) end
end

function UI.RefreshOptions()
    local f = UI.options
    if not f then return end
    for _, r in ipairs(f.order) do
        r:SetChecked(Get(r.def))
        r:SetEnabled(not r.def.enabledBy or ns.Setting(r.def.enabledBy))
    end
end

local function Create()
    local f = UI.Panel(UIParent)
    f:SetSize(W, 100)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.pad = PAD
    -- Named so Escape closes it (UISpecialFrames holds frame names).
    _G.ForeverProfessionalOptions = f
    tinsert(UISpecialFrames, "ForeverProfessionalOptions")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", PAD, -PAD)
    f.title:SetText(L.OPTIONS_TITLE)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -2, -2)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.rows, f.order = {}, {}
    local y = PAD + 24
    for _, def in ipairs(Rows()) do
        if def.group then
            if #f.order > 0 then y = y + GAP end
            local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetPoint("TOPLEFT", PAD, -y)
            h:SetText(def.group)
            y = y + HEADER_H
        end
        local r = UI.CreateCheckRow(f, function(self)
            Set(self.def, not self.checked)
            UI.RefreshOptions()
        end)
        r.def, r.key, r.indent = def, def.key, def.indent or 0
        r:SetText(def.label)
        r:SetPoint("TOPLEFT", PAD + r.indent, -y)
        r:SetPoint("RIGHT", -PAD, 0)
        f.rows[def.key] = r
        f.order[#f.order + 1] = r
        y = y + ROW_H
    end
    f.contentBottom = y + PAD
    f:SetHeight(f.contentBottom)
    f:Hide()
    return f
end

function UI.ShowOptions()
    if not ns.db then return end
    UI.options = UI.options or Create()
    UI.RefreshOptions()
    UI.options:Show()
end

function UI.HideOptions()
    if UI.options then UI.options:Hide() end
end

function UI.ToggleOptions()
    if UI.options and UI.options:IsShown() then UI.HideOptions() else UI.ShowOptions() end
end
