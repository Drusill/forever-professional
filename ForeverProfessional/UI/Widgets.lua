-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Shared widgets in the flat Professions style: panel, filter toggle, icon button, chip, item slot,
-- progress bar and the profession skill bar, plus the per-profession theme and the source icons.
-- Widgets don't read addon state.
local _, ns = ...
local M = ns.Model

local UI = ns.UI or {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"

UI.COLORS = {
    window = "0d0b09", panel = "15120e", panelHeader = "1c1813",
    line = "2e271d", line2 = "3d3326",
    gold = "ffd100", muted = "9a8f7a", dim = "6d6455",
    bronze = "a8601f", field = "0e0c09",
}

function UI.HexColor(hex)
    hex = tostring(hex or "ffffff")
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local Hex = UI.HexColor

-- Theme ----------------------------------------------------------------------------------------
-- kit: suffix of the game's Skillbar_Fill_Flipbook_<kit> art. accent: rail marker, glow and fallback bar.
-- bar: fallback gradient when the kit art is missing. watermark: the profession's card from the
-- Professions book (a wide banner for primary professions, a tall card for secondary ones).

local CARD = "Profession-overview-Card-"
local GENERIC = "Profession-overview-card-generic-"

UI.THEME = {
    [164] = { kit = "Blacksmithing",  accent = "ff8a1f", bar = { "d4400c", "ffe680" }, watermark = CARD .. "Blacksmithing" },
    [186] = { kit = "Mining",         accent = "d9a441", bar = { "6a4a22", "ffd970" }, watermark = CARD .. "Mining" },
    [185] = { kit = "Cooking",        accent = "c9d3de", bar = { "7d8b9a", "ffffff" }, watermark = GENERIC .. "Cooking" },
    [356] = { kit = "Fishing",        accent = "6aa0ff", bar = { "2f5aa8", "cfe2ff" }, watermark = GENERIC .. "Fishing" },
    [129] = { kit = "FirstAid",       accent = "6fdc2a", bar = { "3fae12", "d8ffb0" }, watermark = GENERIC .. "FirstAid" },
    [171] = { kit = "Alchemy",        accent = "3fc8c8", bar = { "1f8a8a", "a8f5f5" }, watermark = CARD .. "Alchemy" },
    [333] = { kit = "Enchanting",     accent = "e8508a", bar = { "b02a3a", "f0c040" }, watermark = CARD .. "Enchanting" },
    [202] = { kit = "Engineering",    accent = "c8a050", bar = { "5a4a30", "e0c070" }, watermark = CARD .. "Engineering" },
    [165] = { kit = "Leatherworking", accent = "b07040", bar = { "6a3a1a", "d09060" }, watermark = CARD .. "Leatherworking" },
    [197] = { kit = "Tailoring",      accent = "6a5ae8", bar = { "2a2a9a", "8a8af0" }, watermark = CARD .. "Tailoring" },
    [182] = { kit = "Herbalism",      accent = "6aa83a", bar = { "2f5a1a", "9ad060" }, watermark = CARD .. "Herbalism" },
    [393] = { kit = "Skinning",       accent = "5aa090", bar = { "2a5a50", "8ac8b8" }, watermark = CARD .. "Skinning" },
}
local DEFAULT_THEME = { kit = "DefaultBlue", accent = "ffd100", bar = { "a8601f", "ffd100" } }

function UI.Theme(line)
    return UI.THEME[line] or DEFAULT_THEME
end

-- Icon per source type (Model.PrimarySource / SourceCards types) and the learned check, picked in
-- game: the gossip glyphs for trainer/vendor/quest, the target frame's skull for drops and the
-- minimap's treasure chest for objects and containers. "atlas:<name>" values go through UI.SetIcon.
UI.SOURCE_ICONS = {
    auto = "Interface\\GossipFrame\\TrainerGossipIcon",
    trainer = "Interface\\GossipFrame\\TrainerGossipIcon",
    vendor = "Interface\\GossipFrame\\VendorGossipIcon",
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    drop = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    object = "atlas:VignetteLoot",
    container = "atlas:VignetteLoot",
    crafted = "Interface\\Icons\\INV_Misc_Gear_01",
    worldObject = "Interface\\Icons\\INV_Misc_Gear_01",
    more = "Interface\\Icons\\INV_Misc_Gear_01",
    unknown = M.QUESTION_ICON,
    check = "Interface\\RaidFrame\\ReadyCheck-Ready",
}

local function AtlasExists(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    return C_Texture.GetAtlasInfo(name)
end

-- Width / height of an atlas, nil when the client doesn't have it.
function UI.AtlasAspect(name)
    local info = name and AtlasExists(name)
    if not (info and info.width and info.height and info.height > 0) then return nil end
    return info.width / info.height
end

-- Show an atlas at its natural aspect within maxW x maxH; false (and hidden) when it's missing.
function UI.FitAtlas(tex, name, maxW, maxH)
    local aspect = UI.AtlasAspect(name)
    if not (aspect and UI.SetAtlas(tex, name)) then
        tex:Hide()
        return false
    end
    local w, h = maxW, maxW / aspect
    if h > maxH then w, h = maxH * aspect, maxH end
    tex:SetSize(w, h)
    tex:Show()
    return true
end

-- Set an atlas only if the client has it; returns false so the caller can fall back.
function UI.SetAtlas(tex, atlas)
    if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(atlas) then return false end
    return (pcall(tex.SetAtlas, tex, atlas)) and true or false
end

-- Plain files for the atlas icons, in case the client lacks the atlas.
local ICON_FALLBACK = {
    ["atlas:VignetteKill"] = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    ["atlas:VignetteLoot"] = "Interface\\Icons\\INV_Box_01",
}

-- Show a SOURCE_ICONS value on a texture: "atlas:<name>" or a file path.
function UI.SetIcon(tex, value)
    if type(value) == "string" and value:sub(1, 6) == "atlas:" then
        if UI.SetAtlas(tex, value:sub(7)) then return end
        value = ICON_FALLBACK[value] or M.QUESTION_ICON
    end
    tex:SetTexture(value)
end

-- Horizontal gradient between two hex colours; a flat colour when gradients aren't available.
local function Gradient(tex, from, to)
    tex:SetTexture(WHITE)
    tex:SetVertexColor(1, 1, 1, 1)
    local r1, g1, b1 = Hex(from)
    local r2, g2, b2 = Hex(to)
    local ok = CreateColor and pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
    if not ok then tex:SetVertexColor(r2, g2, b2, 1) end
end

-- Panel ----------------------------------------------------------------------------------------

local function FlatBackdrop(frame, bg, border, alpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local r, g, b = Hex(bg)
    frame:SetBackdropColor(r, g, b, alpha or 1)
    r, g, b = Hex(border)
    frame:SetBackdropBorderColor(r, g, b, 1)
end

function UI.Panel(parent, alpha)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    FlatBackdrop(p, UI.COLORS.panel, UI.COLORS.line, alpha or 0.96)
    return p
end

-- Filter toggle (joined segments) ------------------------------------------------------------------

local SEGMENT_PAD = 8

function UI.CreateSegmented(parent, items, onSelect)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    FlatBackdrop(c, UI.COLORS.field, UI.COLORS.line2)
    c:SetHeight(22)
    c.buttons, c.order = {}, {}
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, c)
        b.key = item.key
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.label:SetText(item.label)
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.count:SetText("")
        if i > 1 then
            b.divider = b:CreateTexture(nil, "ARTWORK")
            b.divider:SetWidth(1)
            b.divider:SetPoint("TOPLEFT")
            b.divider:SetPoint("BOTTOMLEFT")
            b.divider:SetColorTexture(Hex(UI.COLORS.line2))
        end
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function(self) if onSelect then onSelect(self.key) end end)
        c.buttons[item.key] = b
        c.order[i] = b
    end

    function c:Layout()
        local x = 1
        for _, b in ipairs(self.order) do
            local countW = (b.count:GetText() or "") ~= "" and (b.count:GetStringWidth() + 4) or 0
            local w = SEGMENT_PAD + b.label:GetStringWidth() + countW + SEGMENT_PAD
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -1)
            b:SetSize(w, self:GetHeight() - 2)
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", b, "LEFT", SEGMENT_PAD, 0)
            b.count:ClearAllPoints()
            b.count:SetPoint("LEFT", b.label, "RIGHT", 4, 0)
            x = x + w
        end
        self:SetWidth(x + 1)
    end

    function c:SetSelected(key)
        for _, b in ipairs(self.order) do
            b.selected = (b.key == key)
            if b.selected then
                b.bg:SetColorTexture(Hex("3a2b10"))
                b.label:SetTextColor(Hex(UI.COLORS.gold))
            else
                b.bg:SetColorTexture(Hex(UI.COLORS.field))
                b.label:SetTextColor(Hex(UI.COLORS.muted))
            end
        end
    end

    function c:SetCount(key, n)
        local b = self.buttons[key]
        if not b then return end
        b.count:SetText(n and tostring(n) or "")
        self:Layout()
    end

    c:SetSelected(items[1] and items[1].key)
    c:Layout()
    return c
end

-- Icon button ----------------------------------------------------------------------------------------

function UI.CreateIconButton(parent, texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    FlatBackdrop(b, UI.COLORS.field, UI.COLORS.line2)
    b:SetSize(23, 23)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(texture)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.tooltip = tooltip
    b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    b:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.tooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

-- Chip -------------------------------------------------------------------------------------------------

local CHIP_STYLES = {
    good = { text = "6fdc6f", border = "2a5a2a", bg = "0d1f0d" },
    bad = { text = "ff7262", border = "6a2a20", bg = "261009" },
    neutral = { text = "9a8f7a", border = "3d3326", bg = "0e0c09" },
}

function UI.CreateChip(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetHeight(16)
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetPoint("CENTER", 0, 0)
    function c:SetChip(text, style)
        local s = CHIP_STYLES[style] or CHIP_STYLES.neutral
        self.style = CHIP_STYLES[style] and style or "neutral"
        FlatBackdrop(self, s.bg, s.border)
        self.text:SetText(text or "")
        self.text:SetTextColor(Hex(s.text))
        self:SetWidth((self.text:GetStringWidth() or 0) + 16)
    end
    return c
end

-- Item slot ---------------------------------------------------------------------------------------------

function UI.CreateSlot(parent, size)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(size, size)
    s.border = s:CreateTexture(nil, "BACKGROUND")
    s.border:SetAllPoints()
    s.border:SetColorTexture(Hex("5a4a32"))
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.count = s:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    s.count:SetPoint("BOTTOMRIGHT", -2, 2)
    s.count:SetJustifyH("RIGHT")

    function s:SetItem(itemID, count)
        self.item = itemID
        self.icon:SetTexture(M.ItemIcon(itemID) or M.QUESTION_ICON)
        self.count:SetText((count and count > 1) and tostring(count) or "")
        local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c and c.r then
            self.border:SetColorTexture(c.r, c.g, c.b, 1)
        else
            self.border:SetColorTexture(Hex("5a4a32"))
        end
    end

    s:SetScript("OnEnter", function(self)
        if not (self.item and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.item)
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return s
end

-- Bars --------------------------------------------------------------------------------------------------

local function Fraction(value, max)
    if not (max and max > 0 and value) then return 0 end
    return math.max(0, math.min(1, value / max))
end

-- Plain bronze-to-gold bar.
function UI.CreateProgressBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height)
    bar.barWidth = width
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.9)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    Gradient(bar.fill, UI.COLORS.bronze, UI.COLORS.gold)
    function bar:SetBarWidth(w)
        self.barWidth = w
        self:SetWidth(w)
    end
    function bar:SetProgress(value, max)
        self.fraction = Fraction(value, max)
        self.fill:SetWidth(math.max(0.01, self.barWidth * self.fraction))
    end
    bar:SetProgress(0, 0)
    return bar
end

-- The game's profession skill bar: background, the profession's animated fill (clipped to the
-- progress), the flare at its edge and the thin frame. Without the fill art, a gradient in the
-- profession's colours.
local FLIPBOOK_ROW_H = 34

function UI.CreateSkillBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height)
    bar.innerWidth, bar.innerHeight = width - 4, height - 2

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    if not UI.SetAtlas(bar.bg, "Professions-skillbar-bg") then bar.bg:SetColorTexture(0, 0, 0, 0.9) end

    bar.clip = CreateFrame("Frame", nil, bar)
    bar.clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -1)
    bar.clip:SetHeight(bar.innerHeight)
    if bar.clip.SetClipsChildren then bar.clip:SetClipsChildren(true) end

    bar.fill = bar.clip:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -1)
    bar.fill:SetSize(bar.innerWidth, bar.innerHeight)

    bar.flare = bar.clip:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.flare:SetSize(math.max(8, height * 3), bar.innerHeight)
    bar.flare:SetPoint("RIGHT", bar.clip, "RIGHT", 0, 0)
    if bar.flare.SetBlendMode then bar.flare:SetBlendMode("ADD") end

    if AtlasExists("Professions-skillbar-mask") and bar.clip.CreateMaskTexture then
        local mask = bar.clip:CreateMaskTexture()
        if pcall(mask.SetAtlas, mask, "Professions-skillbar-mask") then
            mask:SetPoint("TOPLEFT", bar.fill, "TOPLEFT")
            mask:SetSize(bar.innerWidth, bar.innerHeight)
            pcall(bar.fill.AddMaskTexture, bar.fill, mask)
            pcall(bar.flare.AddMaskTexture, bar.flare, mask)
        end
    end

    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints()
    over:SetFrameLevel(bar.clip:GetFrameLevel() + 1)
    bar.frame = over:CreateTexture(nil, "OVERLAY")
    bar.frame:SetAllPoints()
    if not UI.SetAtlas(bar.frame, "Professions-skillbar-frame") then bar.frame:Hide() end

    -- Animate the fill's flipbook (2 columns of 34px rows); show its first frame if that fails.
    local function Animate(info)
        local rows = math.max(1, math.floor((info.height or FLIPBOOK_ROW_H) / FLIPBOOK_ROW_H))
        if bar.anim then bar.anim:Stop() end
        local ok = pcall(function()
            if not bar.anim then
                bar.anim = bar:CreateAnimationGroup()
                bar.flip = bar.anim:CreateAnimation("FlipBook")
                bar.flip:SetTarget(bar.fill)
                bar.flip:SetDuration(4)
                bar.anim:SetLooping("REPEAT")
            end
            bar.flip:SetFlipBookRows(rows)
            bar.flip:SetFlipBookColumns(2)
            bar.flip:SetFlipBookFrames(rows * 2)
            bar.flip:SetFlipBookFrameWidth(0)
            bar.flip:SetFlipBookFrameHeight(0)
            bar.anim:Play()
        end)
        if not ok and info.leftTexCoord then
            local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
            bar.fill:SetTexCoord(l, l + (r - l) / 2, t, t + (b - t) / rows)
        end
    end

    function bar:SetTheme(line)
        local theme = UI.Theme(line)
        local name = theme.kit and ("Skillbar_Fill_Flipbook_" .. theme.kit)
        local info = name and AtlasExists(name)
        if info then
            self.usesFallback = false
            self.fill:SetVertexColor(1, 1, 1, 1)
            self.fill:SetAtlas(name, false)
            Animate(info)
            local flare = "Skillbar_Flare_" .. theme.kit
            if AtlasExists(flare) then
                self.flare:SetAtlas(flare, false)
                self.hasFlare = true
            else
                self.hasFlare = false
            end
        else
            self.usesFallback = true
            if self.anim then self.anim:Stop() end
            self.fill:SetTexCoord(0, 1, 0, 1)
            Gradient(self.fill, theme.bar[1], theme.bar[2])
            self.hasFlare = false
        end
        self:SetProgress(self.value, self.max)
    end

    function bar:SetProgress(value, max)
        self.value, self.max = value, max
        local frac = Fraction(value, max)
        self.clip:SetWidth(math.max(0.01, self.innerWidth * frac))
        self.flare:SetShown(self.hasFlare and frac > 0 and frac < 1 or false)
    end

    bar:SetScript("OnShow", function(self)
        if self.anim and not self.usesFallback and not self.anim:IsPlaying() then self.anim:Play() end
    end)
    bar:SetProgress(0, 0)
    return bar
end
