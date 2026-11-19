"""Run ForeverProfessional_Spike against a minimal mock of the Forever API (Lua 5.1 via lupa)."""
import sys, pathlib
import lupa.lua51 as lupa

ADDON = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent / "ForeverProfessional_Spike")
lua = lupa.LuaRuntime(unpack_returned_tuples=True)

MOCK = r'''
_G.printed = {}
function print(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring(select(i,...)) end printed[#printed+1]=table.concat(t," ") end
function strtrim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
function strsplit(sep, s) local out={} for p in (s..sep):gmatch("(.-)"..sep:gsub("%-","%%-")) do out[#out+1]=p end return unpack(out) end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
tinsert = table.insert
date = os.date
function debugprofilestop() return os.clock()*1000 end
function GetBuildInfo() return "1.60.1","70959","Nov 17 2026",16001 end
function GetLocale() return "enUS" end
function UnitName(u) return u=="npc" and "Test Vendor" or "Tester" end
function GetRealmName() return "Realm" end
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Mage","MAGE" end
function UnitGUID(u) return "Creature-0-1-2-3-248196-0000" end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
UISpecialFrames = {}
SlashCmdList = {}

-- timers run when the harness calls flush()
_G.timers = {}
C_Timer = { After = function(s, fn) timers[#timers+1]=fn end }
function flush() for _=1,20 do local t=timers; timers={}; if #t==0 then return end; for _,f in ipairs(t) do f() end end end

-- frames
local frames = {}
local FrameMT = {}
FrameMT.__index = function(self, k)
  if FrameMT[k] then return FrameMT[k] end
  if type(k) == "string" and k:match("^%u") then return function() end end
  return nil
end
function FrameMT:RegisterEvent(e) self.events = self.events or {}; self.events[e]=true end
function FrameMT:SetScript(k, fn) self.scripts = self.scripts or {}; self.scripts[k]=fn end
function FrameMT:CreateTexture() return setmetatable({ GetTextureFileID=function() return 12345 end, SetTexture=function() return true end }, FrameMT) end
function FrameMT:IsShown() return self.shown end
function FrameMT:Show() self.shown = true end
function FrameMT:Hide() self.shown = false end
function FrameMT:GetName() return self.name end
function FrameMT:SetText(t) self.text = t end
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ name=name }, FrameMT); frames[#frames+1]=f
  if template then f.TitleText = setmetatable({}, FrameMT) end
  if name then _G[name]=f end
  return f
end
function fire(event, ...) for _,f in ipairs(frames) do if f.events and f.events[event] and f.scripts and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end end
ChatFontNormal = {}
BasicFrameTemplateWithInset = true

-- profession API mock
local showUnlearned = false
local learned = { [2329]=true, [3170]=true }
local all = { 2329, 3170, 3230, 1250793 }
C_TradeSkillUI = {
  GetRecipeInfo = function(id) return { learned = learned[id] or false, categoryID = 7, recipeID = id, name = "R"..id } end,
  GetRecipeSchematic = function(id) return { recipeID=id, outputItemID = 2454, quantityMin=1, quantityMax=1, reagentSlotSchematics = { { reagents = { { itemID = 765 } }, quantityRequired = 1 } } } end,
  GetRecipeSourceText = function(id) if not learned[id] then return "|cffFFD200Drop:|r Some Mob|nZone" end end,
  GetProfessionInfoByRecipeID = function() return { professionName = "Alchemy", professionID = 171 } end,
  GetAllProfessionTradeSkillLines = function() return { 171, 164 } end,
  GetProfessionInfoBySkillLineID = function(sl) return { professionName = sl==171 and "Alchemy" or "Blacksmithing" } end,
  GetBaseProfessionInfo = function() return { professionName = "Alchemy", professionID = 171, skillLevel = 50, maxSkillLevel = 75 } end,
  GetChildProfessionInfo = function() return { professionName = "Alchemy", professionID = 171 } end,
  GetFilteredRecipeIDs = function() local o={} for _,id in ipairs(all) do if learned[id] or showUnlearned then o[#o+1]=id end end return o end,
  GetCategories = function() return 7, 8 end,
  GetCategoryInfo = function(id) if id == 2425 then return { name = "Blacksmithing" } end return { name = "Cat"..id, parentCategoryID = 2425 } end,
  GetShowUnlearned = function() return showUnlearned end,
  SetShowUnlearned = function(v) showUnlearned = v end,
  IsTradeSkillReady = function() return true end,
  OpenRecipe = function() end,
}
C_Spell = { GetSpellInfo = function(id) return { name = "Spell"..id } end }
C_SpellBook = { IsSpellKnown = function(id) return learned[id] or false end }
function GetProfessions() return 1, 2, nil, nil, 5 end
function GetProfessionInfo(i) return "Prof"..i, 0, 10, 75, 0, 0, 171 end
Enum = { GameRule = { EncounterJournalDisabled = 1, DisableCampsites = 2, Other = 3 } }
C_GameRules = { IsGameRuleActive = function(v) return v == 1 end }
C_Texture = { GetAtlasInfo = function(n) if n ~= "this-atlas-does-not-exist" then return { width=10, height=10, file=1 } end end }
C_AddOns = { IsAddOnLoaded = function() return true end }

-- items: ContinueOnItemLoad fires on flush, except id 247754 (simulate timeout)
C_Item = {
  DoesItemExistByID = function(id) return id ~= 999999999 end,
  IsItemDataCachedByID = function() return false end,
  GetItemInfoInstant = function(id) return id, "Recipe", "Alchemy", "", 134939, 9, 6 end,
  GetItemInfo = function(id) return "Item"..id, "link", 2, 10, 5 end,
}
Item = { CreateFromItemID = function(self, id) return { ContinueOnItemLoad = function(_, cb) if id == 2454 then cb() elseif id ~= 247754 then C_Timer.After(0, cb) end end } end }
C_TooltipInfo = { GetItemByID = function() return { lines = { {leftText="a"}, {leftText="Binds when picked up"} } } end }

-- QuestieDB
ItemDB = { name = function(id) return "Recipe "..id end, npcDrops = function() return { 123 } end, vendors = function() return { 248196 } end }
NpcDB = { name = function() return "Mob" end, zoneID = function() return 17 end, spawns = function() return { [17] = { {50.1, 40.2} } } end }
C_Map = {
  GetBestMapForUnit = function() return 10 end, GetMapInfo = function() return { name = "Barrens" } end,
  CanSetUserWaypointOnMap = function() return true end,
  GetPlayerMapPosition = function() return { x = 0.5, y = 0.4 } end,
  SetUserWaypoint = function() end, GetAreaInfo = function() return "The Barrens" end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
UiMapPoint = { CreateFromVector2D = function() return {} end }
function GetMerchantNumItems() return 3 end
function GetMerchantItemID(i) return 250380 + i end
C_MerchantFrame = { GetItemInfo = function(i) return { name = "Recipe X"..i, price = 1000, hasExtendedCost = false, numAvailable = -1, isUsable = true } end }
'''
lua.execute(MOCK)

# load addon files with (name, ns) varargs like the client does
ns = lua.table()
for f in ["Core.lua", "Samples.lua", "Tests.lua"]:
    chunk = lua.execute("return function(src, name) return assert(loadstring(src, name)) end")((ADDON / f).read_text(), "@" + f)
    chunk("ForeverProfessional_Spike", ns)

run = lua.eval("function(code) local f = assert(loadstring(code)); return f() end")
run('fire("ADDON_LOADED","ForeverProfessional_Spike"); fire("PLAYER_LOGIN")')
run('SlashCmdList.FPSPIKE("help")')
run('SlashCmdList.FPSPIKE("all"); flush()')
run('ProfessionsFrame = CreateFrame("Frame"); ProfessionsFrame:Show(); fire("TRADE_SKILL_SHOW"); flush()')
run('ProfessionsFrame:Hide(); SlashCmdList.FPSPIKE("recipes"); SlashCmdList.FPSPIKE("categories")')
run('fire("MERCHANT_SHOW"); flush()')
run('SlashCmdList.FPSPIKE("map set"); SlashCmdList.FPSPIKE("open 2329"); flush()')
run('SlashCmdList.FPSPIKE("report")')

report = ns.BuildReport()
printed = lua.globals().printed
errors = [printed[i] for i in range(1, len(printed) + 1) if "crashed" in printed[i] or "handler error" in printed[i]]
print(report)
print("\n==== crashes/handler errors:", len(errors))
for e in errors: print("  ", e)
fails = [l for l in report.split("\n") if l.startswith("[FAIL]")]
print("==== FAIL lines in report:", len(fails))
for l in fails: print("  ", l)
