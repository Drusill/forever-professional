-- Minimal mock of the WoW Forever client API (Lua 5.1), enough to load and drive the addon.
-- Loaded by tests/harness.py before the addon files. Test state lives in the global `mock`.

mock = {
    printed = {},
    errors = {},
    learned = {},            -- [spellID] = true -> C_SpellBook.IsSpellKnown
    professions = {          -- GetProfessions() / GetProfessionInfo()
        { name = "Alchemy", icon = 136240, skill = 120, max = 150, line = 171 },
        { name = "Herbalism", icon = 136246, skill = 90, max = 150, line = 182 },
    },
    waypoints = {},
    supertracked = 0,
    timers = {},
    asyncItems = {},         -- [itemID] = true -> ContinueOnItemLoad fires on flush()
    pendingItems = {},
    uncachedSpells = {},     -- [spellID] = true -> C_Spell.GetSpellName returns nil
    frames = {},
}

function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    mock.printed[#mock.printed + 1] = table.concat(t, " ")
end

-- Lua/WoW globals ---------------------------------------------------------------
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
date, time = os.date, os.time
function debugprofilestop() return os.clock() * 1000 end
function GetBuildInfo() return "1.60.1", "70959", "Nov 17 2026", 16001 end
function GetLocale() return mock.locale or "enUS" end
function UnitName(u) return "Tester" end
function GetRealmName() return "Realm" end
function UnitFactionGroup() return "Horde", "Horde" end
function UnitClass() return "Mage", "MAGE" end
function GetTime() return os.clock() end
function geterrorhandler() return function(e) mock.errors[#mock.errors + 1] = e end end
WOW_PROJECT_ID = 18
UISpecialFrames = {}
SlashCmdList = {}
FACTION_STANDING_LABEL4, FACTION_STANDING_LABEL5 = "Neutral", "Friendly"
FACTION_STANDING_LABEL6, FACTION_STANDING_LABEL7, FACTION_STANDING_LABEL8 = "Honored", "Revered", "Exalted"

-- Timers run when the test calls flush().
C_Timer = {
    After = function(_, fn) mock.timers[#mock.timers + 1] = fn end,
    NewTimer = function(_, fn) mock.timers[#mock.timers + 1] = fn; return { Cancel = function() end } end,
}
function flush()
    for _ = 1, 20 do
        local t, items = mock.timers, mock.pendingItems
        mock.timers, mock.pendingItems = {}, {}
        if #t == 0 and #items == 0 then return end
        for _, f in ipairs(t) do f() end
        for _, f in ipairs(items) do f() end
    end
end

-- Frames ---------------------------------------------------------------------------
local Widget = {}
local WidgetMT = {
    __index = function(self, k)
        local m = Widget[k]
        if m then return m end
        -- Any other API method is a harmless no-op.
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end,
}

local function newWidget(kind, name, parent)
    local w = setmetatable({ kind = kind, name = name, parent = parent, shown = true,
        children = {}, regions = {}, scripts = {}, points = {}, width = 0, height = 0 }, WidgetMT)
    if parent and parent.children then parent.children[#parent.children + 1] = w end
    if name then _G[name] = w end
    mock.frames[#mock.frames + 1] = w
    return w
end

function Widget:GetName() return self.name end
function Widget:GetParent() return self.parent end
function Widget:SetParent(p) self.parent = p end
function Widget:GetObjectType() return self.kind end
function Widget:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Widget:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible()
    local w = self
    while w do
        if not w.shown then return false end
        w = w.parent
    end
    return true
end
function Widget:SetScript(k, fn) self.scripts[k] = fn end
function Widget:GetScript(k) return self.scripts[k] end
function Widget:HookScript(k, fn)
    local old = self.scripts[k]
    self.scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Widget:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
function Widget:UnregisterEvent(e) if self.events then self.events[e] = nil end end
function Widget:SetText(t)
    self.text = t
    if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function Widget:GetText() return self.text end
function Widget:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
function Widget:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Widget:SetTexture(t) self.texture = t; return true end
function Widget:GetTexture() return self.texture end
function Widget:SetAtlas(a) self.atlas = a; return true end
function Widget:SetColorTexture(r, g, b, a) self.texture = { r, g, b, a } end
function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:SetWidth(w) self.width = w end
function Widget:SetHeight(h) self.height = h end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:GetStringHeight() return 14 end
function Widget:GetStringWidth() return #(self.text or "") * 6 end
function Widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetPoint() local p = self.points[1]; if p then return unpack(p) end end
function Widget:GetNumPoints() return #self.points end
function Widget:SetChecked(v) self.checked = v end
function Widget:GetChecked() return self.checked end
function Widget:Enable() self.disabled = false end
function Widget:Disable() self.disabled = true end
function Widget:IsEnabled() return not self.disabled end
function Widget:SetEnabled(v) self.disabled = not v end
function Widget:GetChildren() return unpack(self.children) end
function Widget:GetRegions() return unpack(self.regions) end
function Widget:CreateTexture(name, layer)
    local t = newWidget("Texture", name, nil)
    t.parent, t.layer = self, layer
    self.regions[#self.regions + 1] = t
    return t
end
function Widget:CreateFontString(name, layer, template)
    local t = newWidget("FontString", name, nil)
    t.parent, t.layer, t.template = self, layer, template
    self.regions[#self.regions + 1] = t
    return t
end
function Widget:CreateMaskTexture(name) return self:CreateTexture(name) end
function Widget:Click(button)
    if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton", false) end
end
function Widget:SetScrollChild(c) self.scrollChild = c; c.parent = self end
function Widget:GetScrollChild() return self.scrollChild end
function Widget:SetVerticalScroll(v) self.vscroll = v end
function Widget:GetVerticalScroll() return self.vscroll or 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:SetThumbTexture(t)
    if type(t) == "string" then
        self.thumb = self.thumb or self:CreateTexture()
        self.thumb:SetTexture(t)
    else
        self.thumb = t
    end
end
function Widget:GetThumbTexture() return self.thumb end
function Widget:SetMinMaxValues(a, b) self.min, self.max = a, b end
function Widget:SetValue(v) self.value = v end
function Widget:GetValue() return self.value or 0 end
function Widget:ClearFocus() self.focus = false end
function Widget:SetFocus() self.focus = true end
function Widget:HasFocus() return self.focus end
function Widget:GetFrameLevel() return self.level or 1 end
function Widget:SetFrameLevel(l) self.level = l end
function Widget:GetEffectiveScale() return self.effectiveScale or 1 end
function Widget:GetCenter()
    if self.center then return self.center[1], self.center[2] end
    return 500, 400
end
function Widget:GetLeft() return 100 end
function Widget:GetTop() return 700 end
function Widget:SetBackdrop(b) self.backdrop = b end
function Widget:GetFontString()
    if not self.fontString then self.fontString = self:CreateFontString() end
    return self.fontString
end
function Widget:SetFontString(fs) self.fontString = fs end
function Widget:SetNormalFontObject() end

local function applyTemplate(f, template)
    if not template then return end
    for t in template:gmatch("[^,%s]+") do
        if t == "UIPanelScrollFrameTemplate" then
            f.ScrollBar = newWidget("Slider", nil, f)
        elseif t == "UIPanelButtonTemplate" or t == "UIPanelCloseButton" then
            f.Text = f:GetFontString()
        elseif t == "InputBoxTemplate" or t == "SearchBoxTemplate" then
            f.text = f.text or ""
        end
    end
end

function CreateFrame(kind, name, parent, template)
    local f = newWidget(kind, name, parent)
    f.template = template
    applyTemplate(f, template)
    if kind == "EditBox" then f.text = "" end
    return f
end

function fire(event, ...)
    for _, f in ipairs(mock.frames) do
        if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

UIParent = newWidget("Frame", "UIParent")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) mock.printed[#mock.printed + 1] = msg end }
GameTooltip = newWidget("GameTooltip", "GameTooltip", UIParent)
GameTooltip.lines = {}
function GameTooltip:SetOwner(o) self.owner = o; self.lines = {} end
function GameTooltip:SetItemByID(id) self.item = id end
function GameTooltip:SetSpellByID(id) self.spell = id end
function GameTooltip:SetHyperlink(l) self.link = l end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:SetText(t) self.lines = { t } end
-- Minimap: 198x198 like Forever's round minimap. GetMinimapShape is absent unless a test defines it.
Minimap = newWidget("Frame", "Minimap", UIParent)
Minimap.width, Minimap.height = 198, 198
Minimap.center = { 1700, 900 }
mock.cursor = { 0, 0 }       -- raw cursor position (screen pixels, before UIParent's scale)
function GetCursorPosition() return mock.cursor[1], mock.cursor[2] end

-- Drag frame with the left button and release it with the cursor at x, y.
function drag(frame, x, y)
    if frame.scripts.OnDragStart then frame.scripts.OnDragStart(frame, "LeftButton") end
    mock.cursor = { x, y }
    if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.016) end
    if frame.scripts.OnDragStop then frame.scripts.OnDragStop(frame) end
end
function enter(frame) if frame.scripts.OnEnter then frame.scripts.OnEnter(frame, false) end end
function leave(frame) if frame.scripts.OnLeave then frame.scripts.OnLeave(frame, false) end end

for _, n in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlight",
    "GameFontHighlightSmall", "GameFontHighlightLarge", "GameFontDisable", "GameFontNormalHuge", "QuestTitleFont",
    "Fancy22Font", "ChatFontNormal", "GameFontRed", "GameFontGreen" }) do
    _G[n] = {}
end

-- Professions / spells -----------------------------------------------------------------
function GetProfessions()
    local p = mock.professions
    return p[1] and 1 or nil, p[2] and 2 or nil, nil, nil, nil
end
function GetProfessionInfo(i)
    local p = mock.professions[i]
    return p.name, p.icon, p.skill, p.max, 0, 0, p.line
end

C_SpellBook = { IsSpellKnown = function(id) return mock.learned[id] or false end }
C_Spell = {
    GetSpellName = function(id)
        if mock.uncachedSpells[id] then return nil end
        return "Spell " .. id
    end,
    GetSpellInfo = function(id)
        if mock.uncachedSpells[id] then return nil end
        return { name = "Spell " .. id, iconID = 136000 + (id % 100), spellID = id }
    end,
    GetSpellTexture = function(id) return 136000 + (id % 100) end,
}

C_TradeSkillUI = {
    GetRecipeSchematic = function(id, isRecraft)
        mock.schematicCalls = (mock.schematicCalls or 0) + 1
        if mock.noSchematic then return nil end
        return {
            recipeID = id, outputItemID = 2454, quantityMin = 1, quantityMax = 1,
            reagentSlotSchematics = {
                { reagents = { { itemID = 765 } }, quantityRequired = 1 },
                { reagents = { { itemID = 2447 } }, quantityRequired = 2 },
                { reagents = { { itemID = 3371 } }, quantityRequired = 1 },
            },
        }
    end,
}

-- Items: ContinueOnItemLoad is synchronous unless mock.asyncItems[id] is set.
mock.itemNames = {}
C_Item = {
    GetItemNameByID = function(id) return mock.itemNames[id] end,
    GetItemIconByID = function(id) return 134000 + (id % 1000) end,
    GetItemQualityByID = function(id) return 1 end,
    GetItemInfoInstant = function(id) return id, "Trade Goods", "Herb", "", 134000 + (id % 1000), 7, 9 end,
    GetItemInfo = function(id) local n = mock.itemNames[id]; if n then return n, "item:" .. id, 1 end end,
    DoesItemExistByID = function(id) return true end,
    IsItemDataCachedByID = function(id) return mock.itemNames[id] ~= nil end,
}
Item = {
    CreateFromItemID = function(_, id)
        return {
            ContinueOnItemLoad = function(_, cb)
                local function load() mock.itemNames[id] = mock.itemNames[id] or ("Item " .. id); cb() end
                if mock.asyncItems[id] then mock.pendingItems[#mock.pendingItems + 1] = load else load() end
            end,
            GetItemName = function() return mock.itemNames[id] end,
            GetItemID = function() return id end,
        }
    end,
}

-- Maps / reputation --------------------------------------------------------------------------
C_Map = {
    GetMapInfo = function(id) return { mapID = id, name = "Map " .. id } end,
    GetAreaInfo = function(id) return "Area " .. id end,
    CanSetUserWaypointOnMap = function(id) return id ~= 0 end,
    SetUserWaypoint = function(point) mock.waypoints[#mock.waypoints + 1] = point end,
    ClearUserWaypoint = function() end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) if v then mock.supertracked = mock.supertracked + 1 end end }
UiMapPoint = {
    CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end,
}
C_Reputation = { GetFactionDataByID = function(id) return { factionID = id, name = "Faction " .. id } end }
function GetRealZoneText(id) return "Instance " .. tostring(id) end

C_Texture = { GetAtlasInfo = function(n) return { width = 16, height = 16, file = 1 } end }
