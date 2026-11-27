-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Minimap button: click toggles the window, drag moves it around the minimap edge.
-- Hand-rolled on purpose: LibDataBroker and LibDBIcon can't be shipped under the GPL.
local _, ns = ...
local L = ns.L

local MB = {}
ns.MinimapButton = MB

-- The professions window's own icon (its portrait and first side tab). Keep in sync with the TOC's IconTexture.
local ICON = "Interface\\Icons\\INV_SideTab_Professions_c60"
local RING = 5   -- distance outside the minimap edge, the same ring LibDBIcon buttons use

-- Offset from the minimap centre for an angle in degrees (0 = right, 90 = top).
-- Minimap addons that square the minimap say so through GetMinimapShape(); follow the edge then.
function MB.Offset(angle)
    local rad = math.rad(angle)
    local x, y = math.cos(rad), math.sin(rad)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
    end
    local r = Minimap:GetWidth() / 2 + RING
    return x * r, y * r
end

function MB.UpdatePosition()
    local b = MB.button
    if not b then return end
    local x, y = MB.Offset(ns.db and ns.db.minimapAngle or 225)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Angle from the minimap centre to the cursor. GetCenter is in the minimap's own scaled
-- coordinates, GetCursorPosition in raw pixels, so divide by the minimap's effective scale.
local function CursorAngle()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

-- isButton: the minimap button (hide hint, and the drag hint while it sits on the minimap)
-- rather than the compartment entry.
function MB.ShowTooltip(owner, isButton)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(L.TITLE, 1, 0.82, 0)
    GameTooltip:AddLine(L.MINIMAP_CLICK, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_RIGHT_CLICK, 1, 1, 1)
    if isButton then
        if owner:GetParent() == Minimap then GameTooltip:AddLine(L.MINIMAP_DRAG, 1, 1, 1) end
        GameTooltip:AddLine(L.MINIMAP_HIDE_HINT, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

function MB.SetHidden(hidden)
    ns.db.minimapHidden = hidden and true or false
    if MB.button then MB.button:SetShown(not hidden) end
end

-- /fp minimap
function MB.ToggleHidden()
    local hidden = not ns.db.minimapHidden
    MB.SetHidden(hidden)
    ns.Print(hidden and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

function MB.Create()
    if MB.button then return MB.button end
    local b = CreateFrame("Button", "ForeverProfessionalMinimapButton", Minimap)
    MB.button = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and ns.UI then
            ns.UI.Toggle()
        elseif button == "RightButton" and ns.UI and ns.UI.ToggleOptions then
            ns.UI.ToggleOptions()
        end
    end)
    b:SetScript("OnEnter", function(self) MB.ShowTooltip(self, true) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        -- A minimap button bin (EnhanceQoL's, for one) re-parents the button into its grid:
        -- leave it there instead of dragging it back onto the minimap ring.
        if self:GetParent() ~= Minimap then return end
        self:SetScript("OnUpdate", function()
            ns.db.minimapAngle = CursorAngle()
            MB.UpdatePosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    MB.UpdatePosition()
    b:SetShown(not ns.db.minimapHidden)
    return b
end

ns.On("PLAYER_LOGIN", function() MB.Create() end)

-- Addon compartment (the addon list button by the minimap), declared in the TOC.
-- The client calls these with (addonName, ...); the click passes the mouse button second. A right-click
-- opens the options, any other click toggles the window.
function ForeverProfessional_OnAddonCompartmentClick(_, button)
    if not ns.UI then return end
    if button == "RightButton" and ns.UI.ToggleOptions then ns.UI.ToggleOptions() else ns.UI.Toggle() end
end

function ForeverProfessional_OnAddonCompartmentEnter(_, owner)
    MB.ShowTooltip(owner or AddonCompartmentFrame or UIParent, false)
end

function ForeverProfessional_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
