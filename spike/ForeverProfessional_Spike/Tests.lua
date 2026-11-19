-- ForeverProfessional_Spike / Tests
-- Every API call is wrapped: a missing function or a Lua error becomes a FAIL line, never a crash.
local _, ns = ...
local Try, Dump, Log, LogTo = ns.Try, ns.Dump, ns.Log, ns.LogTo

local function TSUI(name) return C_TradeSkillUI and C_TradeSkillUI[name] end

local function WindowOpen()
    return ProfessionsFrame ~= nil and ProfessionsFrame:IsShown()
end

local function SpellName(id)
    local ok, info = Try(C_Spell and C_Spell.GetSpellInfo, id)
    return ok and type(info) == "table" and info.name or nil
end

-- Pull first reagent "itemID x qty" and output out of a schematic.
local function DescribeSchematic(s)
    if type(s) ~= "table" then return nil end
    local slots = s.reagentSlotSchematics or {}
    local first = slots[1]
    local firstTxt = "none"
    if first and first.reagents and first.reagents[1] then
        firstTxt = ("%s x%s"):format(tostring(first.reagents[1].itemID), tostring(first.quantityRequired))
    end
    return ("output=%s qty=%s-%s slots=%d first=%s"):format(tostring(s.outputItemID),
        tostring(s.quantityMin), tostring(s.quantityMax), #slots, firstTxt)
end

---------------------------------------------------------------------------
-- 1. env
---------------------------------------------------------------------------
ns.RegisterTest("env", "client identity, API presence, professions, game rules", function()
    ns.Section("env", "1. Environment & API presence")
    local version, build, _, iface = GetBuildInfo()
    Log("INFO", "GetBuildInfo", ("%s build %s interface %s"):format(version, build, iface))
    Log(iface >= 16000 and iface < 17000 and "PASS" or "WARN", "Forever detection (16000-16999)", iface)
    Log("INFO", "WOW_PROJECT_ID", ("%s (MAINLINE=%s)"):format(tostring(WOW_PROJECT_ID), tostring(WOW_PROJECT_MAINLINE)))
    Log("INFO", "SavedVariables load counter", ns.db.loads .. " (>1 after a relog = SV round-trip works)")

    local present, missing = 0, {}
    for _, path in ipairs(ns.ApiPresence) do
        if ns.Resolve(path) ~= nil then present = present + 1 else missing[#missing + 1] = path end
    end
    Log("INFO", "API presence", ("%d/%d present"):format(present, #ns.ApiPresence))
    Log(#missing > 0 and "WARN" or "PASS", "missing APIs", table.concat(missing, ", "))

    -- Player professions without opening any window
    local ok, p1, p2, arch, fish, cook = Try(GetProfessions)
    if ok then
        for label, idx in pairs({ prof1 = p1, prof2 = p2, archaeology = arch, fishing = fish, cooking = cook }) do
            if idx then
                local ok2, name, _, rank, maxRank, _, _, skillLine = Try(GetProfessionInfo, idx)
                Log(ok2 and "PASS" or "FAIL", "GetProfessionInfo(" .. label .. ")",
                    ok2 and ("%s %s/%s skillLine=%s"):format(tostring(name), tostring(rank), tostring(maxRank), tostring(skillLine)) or name)
            end
        end
    else
        Log("FAIL", "GetProfessions", p1)
    end

    local okL, lines = Try(TSUI("GetAllProfessionTradeSkillLines"))
    if okL and type(lines) == "table" then
        local names = {}
        for i, sl in ipairs(lines) do
            if i > 20 then names[#names + 1] = "..."; break end
            local okI, info = Try(TSUI("GetProfessionInfoBySkillLineID"), sl)
            names[#names + 1] = ("%s=%s"):format(sl, okI and type(info) == "table" and info.professionName or "?")
        end
        Log("PASS", "GetAllProfessionTradeSkillLines", #lines .. " lines: " .. table.concat(names, ", "))
    else
        Log("FAIL", "GetAllProfessionTradeSkillLines", lines)
    end

    -- Game rules mentioning journal / campsite / profession / transmog
    if Enum and Enum.GameRule and C_GameRules and C_GameRules.IsGameRuleActive then
        local hits = 0
        for key, value in pairs(Enum.GameRule) do
            local k = tostring(key):lower()
            if k:find("journal") or k:find("camp") or k:find("profession") or k:find("transmog") or k:find("recipe") then
                local okR, active = Try(C_GameRules.IsGameRuleActive, value)
                Log("INFO", "GameRule " .. key, okR and tostring(active) or ("error: " .. tostring(active)))
                hits = hits + 1
            end
        end
        if hits == 0 then Log("INFO", "GameRule", "no matching rule names in Enum.GameRule") end
    else
        Log("WARN", "GameRule", "Enum.GameRule or C_GameRules.IsGameRuleActive missing")
    end
end)

---------------------------------------------------------------------------
-- 2. recipes (run with the profession window CLOSED, then optionally OPEN)
---------------------------------------------------------------------------
ns.RegisterTest("recipes", "recipe APIs on sample IDs (run with window closed)", function()
    local state = WindowOpen() and "OPEN" or "CLOSED"
    ns.Section("recipes_" .. state, "2. Recipe APIs with profession window " .. state)

    local list = {}
    for _, r in ipairs(ns.SampleRecipes) do list[#list + 1] = r end
    -- also probe a few recipes this character actually knows (captured by the window test)
    for prof, ids in pairs(ns.db.known) do
        for i = 1, math.min(2, #ids) do
            list[#list + 1] = { label = "KNOWN " .. prof, spell = ids[i] }
        end
    end

    local tally = { name = 0, known = 0, info = 0, learned = 0, schematic = 0, output = 0, source = 0, prof = 0 }
    for _, r in ipairs(list) do
        local id = r.spell
        local name = SpellName(id)
        if name then tally.name = tally.name + 1 end

        local okK, known = Try(C_SpellBook and C_SpellBook.IsSpellKnown, id)
        if okK and known then tally.known = tally.known + 1 end

        local okI, info = Try(TSUI("GetRecipeInfo"), id)
        local infoTxt
        if okI and type(info) == "table" then
            tally.info = tally.info + 1
            if info.learned then tally.learned = tally.learned + 1 end
            infoTxt = ("learned=%s cat=%s src=%s"):format(tostring(info.learned), tostring(info.categoryID), tostring(info.sourceType))
        else
            infoTxt = okI and "nil" or ("ERR " .. tostring(info))
        end

        local okS, sch = Try(TSUI("GetRecipeSchematic"), id, false)
        local schTxt = okS and DescribeSchematic(sch) or ("ERR " .. tostring(sch))
        if okS and type(sch) == "table" then
            tally.schematic = tally.schematic + 1
            if sch.outputItemID and sch.outputItemID ~= 0 then tally.output = tally.output + 1 end
            if r.creates and sch.outputItemID and sch.outputItemID ~= r.creates then
                schTxt = schTxt .. " (EXPECTED " .. r.creates .. ")"
            end
        end

        local okT, src = Try(TSUI("GetRecipeSourceText"), id)
        local srcTxt = okT and (ns.CleanText(src) or "nil") or ("ERR " .. tostring(src))
        if okT and src and src ~= "" then tally.source = tally.source + 1 end

        local okP, pinfo = Try(TSUI("GetProfessionInfoByRecipeID"), id)
        local profTxt = okP and type(pinfo) == "table" and tostring(pinfo.professionName) or "nil"
        if okP and type(pinfo) == "table" and pinfo.professionName and pinfo.professionName ~= "" then
            tally.prof = tally.prof + 1
        end

        Log(okS and type(sch) == "table" and "PASS" or "WARN",
            ("%s [%d] %s"):format(r.label, id, tostring(name)),
            ("known=%s | info: %s | schematic: %s | prof=%s"):format(tostring(okK and known), infoTxt, schTxt, profTxt))
        Log("INFO", "   source text", srcTxt)
    end

    local n = #list
    Log("INFO", "TALLY (" .. state .. ")",
        ("spellName %d/%d, IsSpellKnown %d, GetRecipeInfo %d/%d (learned %d), GetRecipeSchematic %d/%d (with output %d), SourceText %d/%d, ProfessionByRecipe %d/%d")
        :format(tally.name, n, tally.known, tally.info, n, tally.learned, tally.schematic, n, tally.output, tally.source, n, tally.prof, n))
end)

---------------------------------------------------------------------------
-- 3. items (async)
---------------------------------------------------------------------------
ns.RegisterTest("items", "async item loading + tooltip data for new Forever IDs", function()
    ns.Section("items", "3. Item data (async)")
    local pending, total = 0, #ns.SampleItems
    local loaded, failed = 0, 0

    local function finish()
        LogTo("items", "INFO", "TALLY", ("loaded %d / failed %d / total %d"):format(loaded, failed, total))
    end

    local started = false
    for _, id in ipairs(ns.SampleItems) do
        local okE, exists = Try(C_Item.DoesItemExistByID, id)
        local okC, cached = Try(C_Item.IsItemDataCachedByID, id)
        local okN, iid, itype, isub, _, icon, classID, subClassID = Try(C_Item.GetItemInfoInstant, id)
        local instant = okN and iid and ("%s/%s class=%s.%s icon=%s"):format(tostring(itype), tostring(isub),
            tostring(classID), tostring(subClassID), tostring(icon)) or "nil"

        if okE and exists == false then
            Log(id == 999999999 and "PASS" or "FAIL", ("item %d"):format(id), "DoesItemExistByID=false (instant: " .. instant .. ")")
            if id ~= 999999999 then failed = failed + 1 else loaded = loaded + 1 end
        elseif not (Item and Item.CreateFromItemID) then
            Log("FAIL", "Item:CreateFromItemID", "ItemMixin missing")
            failed = failed + 1
        else
            pending = pending + 1
            local start = debugprofilestop()
            local done = false
            local item = Item:CreateFromItemID(id)
            item:ContinueOnItemLoad(function()
                if done then return end
                done = true
                local ms = debugprofilestop() - start
                local _, name, _, quality, ilvl, reqLvl = pcall(C_Item.GetItemInfo, id)
                local tipLines = "n/a"
                local okT, data = Try(C_TooltipInfo and C_TooltipInfo.GetItemByID, id)
                if okT and type(data) == "table" and data.lines then
                    local first = data.lines[2] and data.lines[2].leftText or ""
                    tipLines = #data.lines .. " lines, line2=" .. Dump(first)
                end
                LogTo("items", name and "PASS" or "FAIL", ("item %d %s"):format(id, tostring(name)),
                    ("q=%s ilvl=%s req=%s cachedBefore=%s %.0fms | %s | tooltip %s"):format(tostring(quality),
                        tostring(ilvl), tostring(reqLvl), tostring(okC and cached), ms, instant, tipLines))
                if name then loaded = loaded + 1 else failed = failed + 1 end
                pending = pending - 1
                if pending == 0 and started then finish() end
            end)
            ns.After(6, function()
                if done then return end
                done = true
                LogTo("items", "FAIL", ("item %d"):format(id), "ContinueOnItemLoad never fired within 6s (instant: " .. instant .. ")")
                failed = failed + 1
                pending = pending - 1
                if pending == 0 and started then finish() end
            end)
        end
    end
    started = true
    if pending == 0 then finish() end
end)

---------------------------------------------------------------------------
-- 4. textures
---------------------------------------------------------------------------
ns.RegisterTest("textures", "Encounter Journal / Professions atlases and texture files", function()
    ns.Section("textures", "4. Journal & Professions art")
    local found = 0
    for _, atlas in ipairs(ns.SampleAtlases) do
        local ok, info = Try(C_Texture and C_Texture.GetAtlasInfo, atlas)
        if ok and type(info) == "table" then
            found = found + 1
            Log("PASS", "atlas " .. atlas, ("%sx%s file=%s"):format(tostring(info.width), tostring(info.height), tostring(info.file or info.filename)))
        else
            Log(atlas == "this-atlas-does-not-exist" and "PASS" or "FAIL", "atlas " .. atlas, ok and "nil (expected for control)" or info)
        end
    end
    Log("INFO", "atlases found", found .. "/" .. #ns.SampleAtlases)

    local holder = ns.texHolder or CreateFrame("Frame", nil, UIParent)
    ns.texHolder = holder
    holder:SetSize(1, 1); holder:SetPoint("TOPLEFT"); holder:SetAlpha(0)
    for _, path in ipairs(ns.SampleTextureFiles) do
        local tex = holder:CreateTexture()
        local ok, ret = pcall(tex.SetTexture, tex, path)
        local fid = tex.GetTextureFileID and tex:GetTextureFileID()
        -- Heuristic: a real file resolves to a numeric fileID; compare with the control path.
        Log(fid and "PASS" or "WARN", "file " .. path, ("SetTexture ok=%s ret=%s fileID=%s"):format(tostring(ok), tostring(ret), tostring(fid)))
    end
    Log("INFO", "note", "file results are heuristic; compare with the 'Does\\Not\\Exist' control line")
end)

---------------------------------------------------------------------------
-- 5. QuestieDB as an optional runtime source
---------------------------------------------------------------------------
ns.RegisterTest("questie", "QuestieDB ItemDB/NpcDB lookups (optional dependency)", function()
    ns.Section("questie", "5. QuestieDB runtime lookups")
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("QuestieDB")
    Log(isLoaded and "PASS" or "WARN", "QuestieDB loaded", tostring(isLoaded))
    if not isLoaded and C_AddOns then
        -- why not? (disabled, missing dependency, out of date, ...)
        local okI, name, title, notes, loadable, reason, security = Try(C_AddOns.GetAddOnInfo, "QuestieDB")
        Log("INFO", "GetAddOnInfo(QuestieDB)", ("name=%s loadable=%s reason=%s"):format(tostring(okI and name),
            tostring(loadable), tostring(reason)))
        local okE, state = Try(C_AddOns.GetAddOnEnableState, "QuestieDB", UnitName("player"))
        Log("INFO", "GetAddOnEnableState", tostring(okE and state or state) .. " (0=disabled, 2=enabled)")
        local okL, loaded, why = Try(C_AddOns.LoadAddOn, "QuestieDB")
        Log(okL and loaded and "PASS" or "WARN", "LoadAddOn(QuestieDB)", ("loaded=%s reason=%s"):format(tostring(loaded), tostring(why)))
    end
    if type(ItemDB) ~= "table" then
        Log("FAIL", "ItemDB global", "missing")
        return
    end
    for _, q in ipairs(ns.SampleQuestie) do
        local okN, name = Try(ItemDB.name, q.item)
        local okF, list = Try(ItemDB[q.want], q.item)
        local count = okF and type(list) == "table" and #list or 0
        Log(count > 0 and "PASS" or "WARN", ("ItemDB %d %s"):format(q.item, tostring(okN and name)),
            ("%s -> %s"):format(q.want, okF and Dump(list) or ("ERR " .. tostring(list))))
        if count > 0 and type(NpcDB) == "table" then
            local npc = list[1]
            local _, nname = Try(NpcDB.name, npc)
            local _, zone = Try(NpcDB.zoneID, npc)
            local _, spawns = Try(NpcDB.spawns, npc)
            local spawnTxt = "none"
            if type(spawns) == "table" then
                for z, pts in pairs(spawns) do
                    local p = type(pts) == "table" and pts[1]
                    spawnTxt = ("zone %s, %d pts, first=%s"):format(tostring(z), type(pts) == "table" and #pts or 0, Dump(p))
                    break
                end
            end
            local okA, area = Try(C_Map and C_Map.GetAreaInfo, zone)
            Log("INFO", ("   NPC %s %s"):format(tostring(npc), tostring(nname)),
                ("zoneID=%s (%s) spawns: %s"):format(tostring(zone), tostring(okA and area), spawnTxt))
        end
    end
end)

---------------------------------------------------------------------------
-- 6. map pins
---------------------------------------------------------------------------
ns.RegisterTest("map", "waypoint support ('/fpspike map set' drops a pin on you)", function(arg)
    ns.Section("map", "6. Map waypoints")
    local okM, mapID = Try(C_Map.GetBestMapForUnit, "player")
    local okI, minfo = Try(C_Map.GetMapInfo, mapID)
    Log(okM and mapID and "PASS" or "FAIL", "GetBestMapForUnit", ("%s %s"):format(tostring(mapID), okI and minfo and minfo.name or "?"))
    local okC, can = Try(C_Map.CanSetUserWaypointOnMap, mapID)
    Log(okC and can and "PASS" or "WARN", "CanSetUserWaypointOnMap", tostring(okC and can or can))
    local okP, pos = Try(C_Map.GetPlayerMapPosition, mapID, "player")
    local posTxt = okP and pos and ("%.3f, %.3f"):format(pos.x or 0, pos.y or 0) or tostring(pos)
    Log(okP and pos and "PASS" or "WARN", "GetPlayerMapPosition", posTxt)
    Log("INFO", "TomTom installed", tostring(TomTom ~= nil))

    if arg == "set" and okP and pos and UiMapPoint then
        local okW, err = Try(C_Map.SetUserWaypoint, UiMapPoint.CreateFromVector2D(mapID, pos))
        Log(okW and "PASS" or "FAIL", "SetUserWaypoint", okW and "pin placed (clear it from the map)" or err)
        if okW then
            local okS, err2 = Try(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            Log(okS and "PASS" or "FAIL", "SetSuperTrackedUserWaypoint", okS and "tracking" or err2)
        end
    end
end)

---------------------------------------------------------------------------
-- 6b. categories with the window CLOSED (uses IDs captured by the window test)
---------------------------------------------------------------------------
ns.RegisterTest("categories", "are recipe categories readable with the window closed?", function()
    local state = WindowOpen() and "OPEN" or "CLOSED"
    ns.Section("categories_" .. state, "6b. Categories with profession window " .. state)
    local cats, rc = ns.db.categories or {}, ns.db.recipeCats or {}
    if not next(cats) then
        Log("WARN", "no captured categories", "open each profession window once first, then close it and rerun")
        return
    end
    -- a) GetCategoryInfo on known category IDs
    local nCat, okCat, byProf = 0, 0, {}
    for cid, c in pairs(cats) do
        nCat = nCat + 1
        local ok, ci = Try(TSUI("GetCategoryInfo"), cid)
        local good = ok and type(ci) == "table" and ci.name and ci.name ~= ""
        if good then okCat = okCat + 1 end
        byProf[c.prof] = byProf[c.prof] or { 0, 0 }
        byProf[c.prof][1] = byProf[c.prof][1] + 1
        if good then byProf[c.prof][2] = byProf[c.prof][2] + 1 end
    end
    Log(okCat == nCat and "PASS" or (okCat > 0 and "WARN" or "FAIL"), "GetCategoryInfo(known id)", ("%d/%d returned a name"):format(okCat, nCat))
    for prof, v in pairs(byProf) do Log("INFO", "   " .. prof, ("%d/%d"):format(v[2], v[1])) end

    -- b) GetRecipeInfo(id).categoryID vs the value captured with the window open
    local nR, same, zero, byProfR = 0, 0, 0, {}
    for rid, cid in pairs(rc) do
        nR = nR + 1
        local ok, info = Try(TSUI("GetRecipeInfo"), rid)
        local now = ok and type(info) == "table" and info.categoryID or nil
        local prof = cats[cid] and cats[cid].prof or "?"
        byProfR[prof] = byProfR[prof] or { 0, 0 }
        byProfR[prof][1] = byProfR[prof][1] + 1
        if now == cid then same = same + 1; byProfR[prof][2] = byProfR[prof][2] + 1 elseif now == 0 or now == nil then zero = zero + 1 end
    end
    Log(same == nR and "PASS" or (same > 0 and "WARN" or "FAIL"), "GetRecipeInfo(id).categoryID matches",
        ("%d/%d same, %d returned 0/nil"):format(same, nR, zero))
    for prof, v in pairs(byProfR) do Log("INFO", "   " .. prof, ("%d/%d"):format(v[2], v[1])) end

    -- c) sample recipes of professions this character does NOT have
    local got = 0
    for _, r in ipairs(ns.SampleRecipes) do
        local ok, info = Try(TSUI("GetRecipeInfo"), r.spell)
        if ok and type(info) == "table" and info.categoryID and info.categoryID ~= 0 then got = got + 1 end
    end
    Log("INFO", "sample recipes (any profession) with categoryID ~= 0", got .. "/" .. #ns.SampleRecipes)
end)

---------------------------------------------------------------------------
-- 7. profession window (auto on TRADE_SKILL_SHOW)
---------------------------------------------------------------------------
local windowRunning, windowDoneFor = false, {}

local function CountRecipes(ids)
    local learned, unlearned, unlearnedIDs = 0, 0, {}
    for _, id in ipairs(ids or {}) do
        local ok, info = Try(TSUI("GetRecipeInfo"), id)
        if ok and type(info) == "table" then
            if info.learned then learned = learned + 1 else
                unlearned = unlearned + 1
                unlearnedIDs[#unlearnedIDs + 1] = id
            end
        end
    end
    return learned, unlearned, unlearnedIDs
end

local function RunWindowTest(force)
    if windowRunning then return end
    if not WindowOpen() then
        print("|cff8080ff[FP Spike]|r open a profession window first.")
        return
    end
    local okB, base = Try(TSUI("GetBaseProfessionInfo"))
    local profName = okB and type(base) == "table" and base.professionName or "?"
    if windowDoneFor[profName] and not force then return end
    windowRunning = true
    windowDoneFor[profName] = true

    local section = "window_" .. profName
    ns.Section(section, "7. Profession window: " .. profName)
    Log(okB and "PASS" or "FAIL", "GetBaseProfessionInfo", okB and ("%s id=%s %s/%s"):format(profName,
        tostring(base.professionID), tostring(base.skillLevel), tostring(base.maxSkillLevel)) or base)
    local okC, child = Try(TSUI("GetChildProfessionInfo"))
    Log(okC and "INFO" or "FAIL", "GetChildProfessionInfo", okC and type(child) == "table"
        and ("%s id=%s"):format(tostring(child.professionName), tostring(child.professionID)) or tostring(child))

    local okF, ids = Try(TSUI("GetFilteredRecipeIDs"))
    if not (okF and type(ids) == "table") then
        Log("FAIL", "GetFilteredRecipeIDs", ids)
        windowRunning = false
        return
    end
    local learned, unlearned = CountRecipes(ids)
    Log("PASS", "GetFilteredRecipeIDs (default filter)", ("%d ids: %d learned, %d unlearned"):format(#ids, learned, unlearned))

    -- remember some learned recipes for the closed-window test
    local known = {}
    for _, id in ipairs(ids) do
        local ok, info = Try(TSUI("GetRecipeInfo"), id)
        if ok and type(info) == "table" and info.learned then known[#known + 1] = id end
        if #known >= 50 then break end
    end
    ns.db.known[profName] = known

    -- categories
    local cats = { Try(TSUI("GetCategories")) }
    if cats[1] then
        local list = type(cats[2]) == "table" and cats[2] or { select(2, unpack(cats)) }
        local names = {}
        for i, cid in ipairs(list) do
            if i > 10 then names[#names + 1] = "..."; break end
            local okI, ci = Try(TSUI("GetCategoryInfo"), cid)
            names[#names + 1] = ("%s=%s"):format(tostring(cid), okI and type(ci) == "table" and tostring(ci.name) or "?")
        end
        Log("INFO", "GetCategories (top-level roots only)", #list .. ": " .. table.concat(names, ", "))
    else
        Log("FAIL", "GetCategories", cats[2])
    end

    -- real categories: each recipe's categoryID, walked up through parentCategoryID (as Blizzard does)
    ns.db.categories = ns.db.categories or {}
    ns.db.recipeCats = ns.db.recipeCats or {}
    local leaves, leafOrder = {}, {}
    for _, id in ipairs(ids) do
        local okR, info = Try(TSUI("GetRecipeInfo"), id)
        local cid = okR and type(info) == "table" and info.categoryID
        if cid and cid ~= 0 then
            ns.db.recipeCats[id] = cid
            if not leaves[cid] then
                local okI, ci = Try(TSUI("GetCategoryInfo"), cid)
                local path, guard, cur = {}, 0, (okI and type(ci) == "table") and ci or nil
                while cur and guard < 6 do
                    table.insert(path, 1, tostring(cur.name))
                    guard = guard + 1
                    local nextCat = nil
                    if cur.parentCategoryID then
                        local okP, parent = Try(TSUI("GetCategoryInfo"), cur.parentCategoryID)
                        if okP and type(parent) == "table" then nextCat = parent end
                    end
                    cur = nextCat
                end
                leaves[cid] = table.concat(path, " > ")
                leafOrder[#leafOrder + 1] = cid
                ns.db.categories[cid] = { name = okI and ci and ci.name, parent = okI and ci and ci.parentCategoryID, prof = profName }
            end
        end
    end
    local sample = {}
    for i, cid in ipairs(leafOrder) do
        if i > 15 then sample[#sample + 1] = "..."; break end
        sample[#sample + 1] = ("%d=%s"):format(cid, leaves[cid])
    end
    Log(#leafOrder > 0 and "PASS" or "FAIL", "recipe categories (via recipeInfo.categoryID + parents)",
        #leafOrder .. " leaf categories: " .. table.concat(sample, " | "))

    -- the key question: can an addon show unlearned recipes?
    local okG, orig = Try(TSUI("GetShowUnlearned"))
    Log("INFO", "GetShowUnlearned (before)", tostring(okG and orig or orig))
    local okSet, errSet = Try(TSUI("SetShowUnlearned"), true)
    Log(okSet and "INFO" or "FAIL", "SetShowUnlearned(true)", okSet and "called, waiting 1.5s for list update" or errSet)

    ns.After(1.5, function()
        local ok2, ids2 = Try(TSUI("GetFilteredRecipeIDs"))
        local l2, u2, unlearnedIDs = CountRecipes(ok2 and ids2 or {})
        local okG2, now = Try(TSUI("GetShowUnlearned"))
        LogTo(section, u2 > 0 and "PASS" or "FAIL", "after SetShowUnlearned(true)",
            ("%d ids: %d learned, %d unlearned (GetShowUnlearned now=%s)"):format(ok2 and #ids2 or 0, l2, u2, tostring(okG2 and now)))

        for i = 1, math.min(5, #unlearnedIDs) do
            local id = unlearnedIDs[i]
            local _, src = Try(TSUI("GetRecipeSourceText"), id)
            local okS, sch = Try(TSUI("GetRecipeSchematic"), id, false)
            LogTo(section, src and "PASS" or "WARN", ("   unlearned [%d] %s"):format(id, tostring(SpellName(id))),
                ("source=%s | %s"):format(ns.CleanText(src) or "nil", okS and DescribeSchematic(sch) or "schematic ERR"))
        end

        -- source text for sample recipes of OTHER professions while this window is open
        local others = 0
        for _, r in ipairs(ns.SampleRecipes) do
            local okT, src = Try(TSUI("GetRecipeSourceText"), r.spell)
            if okT and src and src ~= "" then others = others + 1 end
        end
        LogTo(section, "INFO", "GetRecipeSourceText on sample recipes (any profession)", others .. "/" .. #ns.SampleRecipes .. " returned text")

        -- restore Blizzard's default
        Try(TSUI("SetShowUnlearned"), okG and orig or false)
        LogTo(section, "INFO", "restored SetShowUnlearned", tostring(okG and orig or false))
        windowRunning = false
        print("|cff8080ff[FP Spike]|r window test done. Close the window and run |cffffff00/fpspike recipes|r again, then /fpspike report.")
    end)
end

ns.RegisterTest("window", "profession window probes (auto-runs when you open one)", function()
    RunWindowTest(true)
end)

ns.On("TRADE_SKILL_SHOW", function()
    -- give Blizzard_Professions time to build its list
    local tries = 0
    local function wait()
        tries = tries + 1
        local ok, ready = Try(TSUI("IsTradeSkillReady"))
        if (ok and ready) or tries > 10 then RunWindowTest(false) else ns.After(0.5, wait) end
    end
    ns.After(0.5, wait)
end)

---------------------------------------------------------------------------
-- 8. merchant harvesting (auto on MERCHANT_SHOW)
---------------------------------------------------------------------------
local merchantDone = {}

ns.On("MERCHANT_SHOW", function()
    ns.After(0.3, function()
        local okG, guid = Try(UnitGUID, "npc")
        local secret = issecretvalue and okG and issecretvalue(guid)
        local npcID = (okG and not secret and type(guid) == "string") and tonumber((select(6, strsplit("-", guid)))) or nil
        local key = tostring(npcID or UnitName("npc"))
        if merchantDone[key] then return end
        merchantDone[key] = true

        local section = "merchant_" .. key
        ns.Section(section, "8. Merchant: " .. tostring(UnitName("npc")) .. " (" .. key .. ")")
        Log(npcID and "PASS" or "WARN", "NPC id from UnitGUID", ("%s secret=%s"):format(tostring(npcID), tostring(secret)))
        local okM, mapID = Try(C_Map.GetBestMapForUnit, "player")
        local okP, pos = Try(C_Map.GetPlayerMapPosition, mapID, "player")
        Log("INFO", "location", ("map %s at %s"):format(tostring(mapID), okP and pos and ("%.3f, %.3f"):format(pos.x, pos.y) or "?"))

        local okN, n = Try(GetMerchantNumItems)
        Log(okN and "PASS" or "FAIL", "GetMerchantNumItems", tostring(n))
        if not okN then return end
        local recipes = 0
        for i = 1, n do
            local okID, itemID = Try(GetMerchantItemID, i)
            local okInfo, info = Try(C_MerchantFrame and C_MerchantFrame.GetItemInfo, i)
            local classID = okID and itemID and select(7, pcall(C_Item.GetItemInfoInstant, itemID))
            if classID == 9 then -- Enum.ItemClass.Recipe
                recipes = recipes + 1
                if recipes <= 8 then
                    Log("PASS", ("recipe item %s"):format(tostring(itemID)),
                        okInfo and type(info) == "table" and ("%s price=%s extCost=%s avail=%s usable=%s"):format(tostring(info.name),
                            tostring(info.price), tostring(info.hasExtendedCost), tostring(info.numAvailable), tostring(info.isUsable))
                        or ("C_MerchantFrame.GetItemInfo ERR " .. tostring(info)))
                end
            end
        end
        Log("INFO", "recipe items sold here", recipes .. " of " .. n)
    end)
end)

---------------------------------------------------------------------------
-- 9. OpenRecipe (manual; may taint)
---------------------------------------------------------------------------
ns.RegisterTest("open", "C_TradeSkillUI.OpenRecipe(<id>) — may cause UI errors, /reload after", function(arg)
    local id = tonumber(arg) or 2329
    ns.Section("open", "9. OpenRecipe(" .. id .. ")")
    local ok, err = Try(TSUI("OpenRecipe"), id)
    Log(ok and "INFO" or "FAIL", "OpenRecipe call", ok and "returned without error; did the profession window open on that recipe?" or err)
    ns.After(2, function()
        LogTo("open", WindowOpen() and "PASS" or "WARN", "ProfessionsFrame shown after 2s", tostring(WindowOpen()))
    end)
end)
