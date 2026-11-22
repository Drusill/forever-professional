-- ForeverProfessional. Licensed under the GNU GPL v3 or later.
-- Recipe item tooltips (Plans, Pattern, Formula...): which characters know the recipe, which could
-- learn it now and which need more skill, so a vendor or Auction House recipe can be matched to an alt.
local _, ns = ...

local index   -- [itemID] = { {line, spellID}... }, built on first use

function ns.RecipeForItem(itemID)
    if not index then
        index = {}
        for line, recipes in pairs(ns.Data.Recipes or {}) do
            for spellID, rec in pairs(recipes) do
                local teach = rec.teach
                if type(teach) == "number" then teach = { teach } end
                for _, item in ipairs(teach or {}) do
                    index[item] = index[item] or {}
                    table.insert(index[item], { line, spellID })
                end
            end
        end
    end
    return index[itemID]
end

-- Add the character lines for every recipe the item teaches. Returns true if anything was added.
function ns.AddRecipeLines(tooltip, itemID)
    local recipes = itemID and ns.RecipeForItem(itemID)
    if not recipes then return false end
    local added = false
    for _, r in ipairs(recipes) do
        for _, text in ipairs(ns.OwnerLines(r[1], r[2])) do
            if not added then
                tooltip:AddLine(" ")
                added = true
            end
            tooltip:AddLine(text, 1, 1, 1, true)
        end
    end
    return added
end

local function ItemIDOf(tooltip, data)
    if type(data) == "table" and type(data.id) == "number" then return data.id end
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        local id = link and link:match("item:(%d+)")
        return id and tonumber(id)
    end
end

local function OnItem(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = ItemIDOf(tooltip, data)
    if not itemID or tooltip.fpItem == itemID then return end
    tooltip.fpItem = itemID   -- cleared by OnTooltipCleared, so each new tooltip gets the lines once
    if ns.AddRecipeLines(tooltip, itemID) then tooltip:Show() end
end

-- Never let an error here break someone else's tooltip, but still report it (BugSack).
local function Safe(tooltip, data)
    local ok, err = pcall(OnItem, tooltip, data)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

local viaProcessor = false
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    viaProcessor = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, Safe)
end
for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tooltip and tooltip.HookScript then
        if not viaProcessor then
            pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self) Safe(self) end)
        end
        pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) self.fpItem = nil end)
    end
end
