-- Sample IDs taken from WhatsTraining's Camelot (Forever) recipe data.
-- spell = recipe spell ID, creates = crafted item, teach = recipe item that teaches it.
local _, ns = ...

ns.SampleRecipes = {
    -- Alchemy (171)
    { label = "Alchemy / classic trainer",   spell = 2329,    creates = 2454 },
    { label = "Alchemy / classic drop",      spell = 3230,    creates = 2457,   teach = 2553 },
    { label = "Alchemy / NEW drop",          spell = 1250793, creates = 250344, teach = 250380 },
    { label = "Alchemy / NEW vendor (rep)",  spell = 1250794, creates = 250345, teach = 250381 },
    { label = "Alchemy / NEW quest+trainer", spell = 1230564, creates = 279956 },
    -- Other professions
    { label = "Blacksmithing / trainer",     spell = 2662,    creates = 2852 },
    { label = "Blacksmithing / NEW vendor",  spell = 1252262, creates = 250513, teach = 251365 },
    { label = "Tailoring / NEW drop",        spell = 1257376, creates = 253901, teach = 253902 },
    { label = "Leatherworking / NEW drop",   spell = 1255131, creates = 252493 },
    { label = "Cooking / NEW vendor",        spell = 1249963, creates = 249871, teach = 249885 },
    { label = "Engineering / NEW drop",      spell = 1293088, creates = 274048, teach = 274049 },
    { label = "Enchanting / NEW drop (enchant, no item)", spell = 1248458, teach = 249474 },
}

-- Items to load asynchronously: a mix of classic and new Forever IDs.
ns.SampleItems = {
    2454, 2553,                     -- classic
    250344, 250380, 250345, 250381, -- new Alchemy output + recipe items
    253901, 253902, 274048, 249474, -- new Tailoring / Engineering / Enchanting
    279956, 247754,                 -- new
    999999999,                      -- invalid on purpose (expect "empty")
}

-- QuestieDB probes: recipe items whose drop / vendor source we want.
ns.SampleQuestie = {
    { item = 250380, want = "npcDrops" },   -- NEW drop
    { item = 2553,   want = "npcDrops" },   -- classic drop
    { item = 250381, want = "vendors" },    -- NEW vendor (ACA)
    { item = 253902, want = "npcDrops" },   -- NEW Tailoring drop
}

ns.SampleAtlases = {
    -- Encounter Journal (Blizzard_EncounterJournal on the forever branch)
    "adventureguide-pane-large", "adventureguide-pane-small", "adventureguide-ring",
    "adventureguide-rewardring", "loottab-background", "loottab-set-background",
    "loottab-set-itemborder-green", "ui-ej-memoryframe", "ui-journeys-bg",
    -- Professions
    "Professions-Slot-Frame", "Professions-Slot-bg", "Profession-Background-Template2",
    "Professions-QualityPane-bg-top", "Professions-Recrafting-Panel",
    "Professions-Equipment-Divider", "common-insideframe",
    -- control
    "this-atlas-does-not-exist",
}

ns.SampleTextureFiles = {
    "Interface\\EncounterJournal\\UI-EJ-JournalBG",
    "Interface\\EncounterJournal\\UI-EJ-BACKGROUND-Default",
    "Interface\\EncounterJournal\\UI-EJ-BOSS-Default",
    "Interface\\EncounterJournal\\UI-EJ-LOREBG-Default",
    "Interface\\EncounterJournal\\UI-EncounterJournalTextures",
    "Interface\\EncounterJournal\\UI-EJ-Icons",
    "Interface\\EncounterJournal\\UI-EJ-BossModelPaperFrame",
    "Interface\\Does\\Not\\Exist",
}

ns.ApiPresence = {
    "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetRecipeSchematic",
    "C_TradeSkillUI.GetRecipeSourceText", "C_TradeSkillUI.GetFilteredRecipeIDs",
    "C_TradeSkillUI.SetShowUnlearned", "C_TradeSkillUI.GetShowUnlearned",
    "C_TradeSkillUI.GetCategories", "C_TradeSkillUI.GetCategoryInfo",
    "C_TradeSkillUI.GetProfessionInfoByRecipeID", "C_TradeSkillUI.GetAllProfessionTradeSkillLines",
    "C_TradeSkillUI.GetProfessionInfoBySkillLineID", "C_TradeSkillUI.IsRecipeProfessionLearned",
    "C_TradeSkillUI.GetRecipeOutputItemData", "C_TradeSkillUI.GetRecipeLink",
    "C_TradeSkillUI.OpenRecipe", "C_TradeSkillUI.OpenTradeSkill", "C_TradeSkillUI.IsTradeSkillReady",
    "C_SpellBook.IsSpellKnown", "C_Spell.GetSpellInfo", "C_Spell.RequestLoadSpellData",
    "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.IsItemDataCachedByID",
    "C_Item.RequestLoadItemDataByID", "C_TooltipInfo.GetItemByID", "C_TooltipInfo.GetRecipeResultItem",
    "C_MerchantFrame.GetItemInfo", "GetMerchantItemID", "GetMerchantNumItems",
    "C_Map.SetUserWaypoint", "C_Map.CanSetUserWaypointOnMap", "C_Map.GetBestMapForUnit",
    "C_Map.GetAreaInfo", "C_SuperTrack.SetSuperTrackedUserWaypoint",
    "C_Texture.GetAtlasInfo", "C_GameRules.IsGameRuleActive", "C_EncounterJournal.GetInstanceInfo",
    "C_Reputation.GetFactionDataByID", "C_SkillInfo.GetSkillLineInfoByID",
    "GetProfessions", "GetProfessionInfo",
    -- Classic-era globals (expected MISSING on Forever)
    "GetTradeSkillInfo", "GetNumTradeSkills", "GetCraftInfo", "GetItemInfo", "GetSpellInfo",
    "Item.CreateFromItemID", "Spell.CreateFromSpellID",
}
