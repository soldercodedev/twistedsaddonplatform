-- TAP: Mythic Ledger - Compat.lua
-- Centralised, defensive wrappers around every Blizzard API the module touches. ALL risky calls
-- live here: challenge-mode lifecycle, keystone/affix/completion info, season, and group roster.
-- Everything is pcall-guarded and Secret-value-safe, so callers get either clean normalized data
-- or nil - they never handle a raw API surprise or a Secret. If Midnight changes a signature,
-- this is the ONLY file that should need touching.

local ADDON, ML = ...
local UIF = _G.UIFoundry

local API = {}
ML.API = API

----------------------------------------------------------------------
-- Secret-value safety. Midnight can hand back "Secret" values that error on
-- arithmetic/compare/concat/index. CanRead() reports whether a value is safe to use; ReadNum()
-- returns it only if it's a usable number, else nil. Prefer these over touching a value directly.
----------------------------------------------------------------------
function ML.CanRead(v)
    if v == nil then return true end
    if UIF and UIF.CanRead then
        local ok, res = pcall(UIF.CanRead, v)
        if ok then return res and true or false end
    end
    -- Fallback: a Secret throws on a trivial self-compare; a normal value does not.
    return pcall(function() return v == v end)
end

function ML.ReadNum(v)
    if type(v) ~= "number" then return nil end
    if not ML.CanRead(v) then return nil end
    return v
end

function ML.ReadStr(v)
    if type(v) ~= "string" then return nil end
    if not ML.CanRead(v) then return nil end
    return v
end

-- Run fn(...) under pcall; log + return nil on error. Use for any single API call.
local function safe(label, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
    if not ok then
        ML.Log("API error in %s: %s", label, tostring(a))
        ML._apiErrors = (ML._apiErrors or 0) + 1
        return nil
    end
    return a, b, c, d, e, f, g, h, i, j, k, l, m
end
API.safe = safe

local C_CM  = _G.C_ChallengeMode
local C_MP  = _G.C_MythicPlus
local C_PI  = _G.C_PlayerInfo

-- Overall Mythic+ score. For "player" prefer C_ChallengeMode.GetOverallDungeonScore(); for any unit
-- (party members included) fall back to C_PlayerInfo.GetPlayerMythicPlusRatingSummary().currentSeasonScore.
function API.MythicRating(unit)
    unit = unit or "player"
    if unit == "player" and C_CM and type(C_CM.GetOverallDungeonScore) == "function" then
        local s = ML.ReadNum(safe("GetOverallDungeonScore", C_CM.GetOverallDungeonScore))
        if s and s > 0 then return s end
    end
    if C_PI and type(C_PI.GetPlayerMythicPlusRatingSummary) == "function" then
        local sum = safe("GetPlayerMythicPlusRatingSummary", C_PI.GetPlayerMythicPlusRatingSummary, unit)
        if type(sum) == "table" then return ML.ReadNum(sum.currentSeasonScore) end
    end
    return nil
end

-- Equipped item level (rounded). For "player" GetAverageItemLevel is always live; for any OTHER unit it
-- needs an active/completed inspect (C_PaperDollInfo.GetInspectItemLevel) -> nil until that unit has been
-- inspected (the run tracker inspects the group at run start, so teammate ilvl fills in then).
function API.ItemLevel(unit)
    unit = unit or "player"
    if unit == "player" then
        if type(GetAverageItemLevel) == "function" then
            local _, equipped = safe("GetAverageItemLevel", GetAverageItemLevel)
            local n = ML.ReadNum(equipped)
            if n and n > 0 then return math.floor(n + 0.5) end
        end
        return nil
    end
    local C_PD = _G.C_PaperDollInfo
    if C_PD and type(C_PD.GetInspectItemLevel) == "function" then
        local n = ML.ReadNum(safe("GetInspectItemLevel", C_PD.GetInspectItemLevel, unit))
        if n and n > 0 then return math.floor(n + 0.5) end
    end
    return nil
end

-- Boss portrait icons from the Encounter Journal. Built lazily once - iterating the whole Journal is
-- a bit heavy, so we cache it. EJ_* are base-API functions (no UI addon needed).
--
-- We key TWO ways because matching by boss name alone is fragile: the Journal uses typographic
-- apostrophes ("Kael'thas") while ENCOUNTER_* events use ASCII ("Kael'thas"), so a literal name
-- lookup misses (e.g. Magister's Terrace). So we key primarily by the stable DungeonEncounterID
-- (which is exactly what ENCOUNTER_END gives us and what our run records store as boss.id), and fall
-- back to a normalized name (letters/digits only, lowercased) so apostrophe/spacing drift can't break it.
local bossIconById, bossIconByName, dungeonBgByName

-- Normalize a boss name to a punctuation/case-agnostic key so the two data sources always agree.
local function normBossName(s)
    if type(s) ~= "string" then return nil end
    local k = s:lower():gsub("[^%w]", "")
    return k ~= "" and k or nil
end

-- Builds the whole Encounter-Journal cache in ONE pass: boss portrait icons (by encounter id + by
-- normalized name) AND each dungeon's wide background art (by normalized dungeon name).
local function buildBossIcons()
    local byId, byName, bgByName = {}, {}, {}
    -- EJ_* data is served by the Encounter Journal, a LOAD-ON-DEMAND addon. If it hasn't been loaded
    -- yet (e.g. the player never opened the journal this session), the functions exist but every
    -- query returns nil - so we'd build (and cache) an empty set. Force it to load first.
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
    if loader then pcall(loader, "Blizzard_EncounterJournal") end
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_SelectInstance
        and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo) then
        return byId, byName, bgByName
    end
    local savedTier = EJ_GetSelectedTier and EJ_GetSelectedTier()   -- restore the journal's tier after
    for tier = 1, EJ_GetNumTiers() do
        pcall(EJ_SelectTier, tier)
        local i = 1
        while true do
            -- instanceID, name, description, bgImage, buttonImage1, loreImage, ...
            local instanceID, iname, _, bgImage = EJ_GetInstanceByIndex(i, false)   -- false = dungeons
            if not instanceID then break end
            local ik = normBossName(iname)
            if ik and bgImage and bgImage ~= 0 and not bgByName[ik] then bgByName[ik] = bgImage end
            -- An instance's ENCOUNTERS are only queryable once it's selected (instance-level data like
            -- bgImage above is not) - without this, EJ_GetEncounterInfoByIndex returns nothing and the
            -- boss-icon cache stays empty even though the Journal is loaded.
            pcall(EJ_SelectInstance, instanceID)
            local e = 1
            while true do
                -- name, description, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID
                local name, _, journalEncounterID, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(e, instanceID)
                if not name then break end
                if journalEncounterID then
                    -- EJ_GetCreatureInfo -> id, name, desc, displayInfo, iconImage, uiModelSceneID.
                    -- The FIRST creature of an encounter doesn't always carry an icon (some older
                    -- dungeons, e.g. Magisters' Terrace, only populate it on a later index), so scan a
                    -- few indices and take the first non-zero icon instead of only checking index 1.
                    local iconImage
                    for ci = 1, 8 do
                        local ok, _, cname, _, _, img = pcall(EJ_GetCreatureInfo, ci, journalEncounterID)
                        if not ok or (ci > 1 and not cname) then break end   -- ran past the last creature
                        if img and img ~= 0 then iconImage = img; break end
                    end
                    if iconImage then
                        if dungeonEncounterID and not byId[dungeonEncounterID] then byId[dungeonEncounterID] = iconImage end
                        local nk = normBossName(name)
                        if nk and not byName[nk] then byName[nk] = iconImage end
                    end
                end
                e = e + 1
            end
            i = i + 1
        end
    end
    if savedTier and EJ_SelectTier then pcall(EJ_SelectTier, savedTier) end
    return byId, byName, bgByName
end

-- Build the EJ cache lazily, but do NOT lock it until we actually got data: the first call can land
-- before the Encounter Journal is available, and an empty cache must not be permanent. Cap retries so
-- a genuinely unavailable journal can't make every call re-scan all tiers. Shared by BossIcon +
-- DungeonBackground so the first call to either populates everything.
local bossIconsReady, bossIconTries = false, 0
local function ensureEJCache()
    if not bossIconsReady and bossIconTries < 4 then
        bossIconById, bossIconByName, dungeonBgByName = buildBossIcons()
        bossIconsReady = (next(bossIconById) ~= nil) or (next(bossIconByName) ~= nil) or (next(dungeonBgByName) ~= nil)
        bossIconTries = bossIconTries + 1
    end
end

-- The boss's portrait icon (a texture fileID), or nil. Pass the boss's encounter id (boss.id) when
-- you have it - that's the reliable key; the name is a fuzzy fallback for old records without an id.
function API.BossIcon(name, id)
    ensureEJCache()
    if id and bossIconById and bossIconById[id] then return bossIconById[id] end
    local nk = normBossName(name)
    return (nk and bossIconByName and bossIconByName[nk]) or nil
end

-- A dungeon's wide Encounter-Journal background art (a texture fileID) for a dungeon NAME, or nil.
-- Designed as a scoreboard/backdrop watermark - much better than stretching the small square
-- GetMapUIInfo portal icon. Keyed by normalized name (matches the live GetMapUIInfo dungeon name).
function API.DungeonBackground(name)
    ensureEJCache()
    local nk = normBossName(name)
    return (nk and dungeonBgByName and dungeonBgByName[nk]) or nil
end

-- Diagnostic snapshot of the Encounter-Journal state + boss-icon/bg cache (for /tap ledger apicheck).
-- Forces a build attempt. Read-only; never touches run data.
function API.EJDiag()
    ensureEJCache()
    local function count(t) local n = 0; if t then for _ in pairs(t) do n = n + 1 end end return n end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
    return {
        ejLoaded = loaded and true or false,
        ejFuncs  = (EJ_GetNumTiers and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo) and true or false,
        numTiers = EJ_GetNumTiers and EJ_GetNumTiers() or nil,
        ready    = bossIconsReady, tries = bossIconTries,
        byId     = count(bossIconById), byName = count(bossIconByName), bg = count(dungeonBgByName),
    }
end

-- The Encounter Journal is load-on-demand, so the FIRST BossIcon() call (e.g. an end-of-run
-- scoreboard before the player ever opened the Journal this session) can land before its data is
-- queryable - buildBossIcons() then returns empty and, once the retry cap is hit, that empty cache
-- is permanent for the session. That's the "boss icons vanished / never come back" bug. When the
-- Journal finishes loading its data, drop the cache and reset the retry budget so the next lookup
-- rebuilds from real data.
do
    -- pcall EVERYTHING here: RegisterEvent raises a hard Lua error on an unknown event name, and an
    -- uncaught throw at this file-scope would abort the REST of Compat.lua (leaving every API.* defined
    -- below this block nil). EJ_LOADING_UI in particular is not guaranteed to exist across versions.
    local ok, f = pcall(CreateFrame, "Frame")
    if ok and f then
        pcall(f.RegisterEvent, f, "EJ_LOADING_UI")          -- Encounter Journal data is ready (may not exist)
        pcall(f.RegisterEvent, f, "ADDON_LOADED")           -- Blizzard_EncounterJournal (LoD) just loaded
        pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")  -- pre-warm the cache before anything renders
        f:SetScript("OnEvent", function(_, ev, arg1)
            if ev == "ADDON_LOADED" and arg1 ~= "Blizzard_EncounterJournal" then return end
            if ev == "PLAYER_ENTERING_WORLD" then
                if not bossIconsReady then ensureEJCache() end   -- warm once; don't re-scan every zone-in
                return
            end
            -- Journal data (re)loaded: drop the cache, reset the retry budget, rebuild NOW that the data
            -- is queryable, and refresh any open window so already-rendered placeholder icons fill in.
            bossIconById, bossIconByName, dungeonBgByName = nil, nil, nil
            bossIconsReady, bossIconTries = false, 0
            ensureEJCache()
            if _G.TAP and _G.TAP.RefreshWindow then pcall(_G.TAP.RefreshWindow, _G.TAP) end
        end)
    end
end

-- Blizzard's rarity color for an overall M+ score ({r,g,b}), or nil.
function API.ScoreColor(score)
    score = ML.ReadNum(score)
    if not (score and C_CM and type(C_CM.GetDungeonScoreRarityColor) == "function") then return nil end
    local c = safe("GetDungeonScoreRarityColor", C_CM.GetDungeonScoreRarityColor, score)
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return nil
end

----------------------------------------------------------------------
-- Challenge-mode / keystone / affix / completion.
----------------------------------------------------------------------

-- Is a real Mythic+ challenge active right now? Returns the active challenge map id or nil.
function API.GetActiveMapID()
    if not (C_CM and C_CM.GetActiveChallengeMapID) then return nil end
    local id = safe("GetActiveChallengeMapID", C_CM.GetActiveChallengeMapID)
    return ML.ReadNum(id)
end

-- Live keystone info for the active run: { level, affixes = {ids}, charged }.
function API.GetActiveKeystone()
    if not (C_CM and C_CM.GetActiveKeystoneInfo) then return nil end
    local level, affixes, charged = safe("GetActiveKeystoneInfo", C_CM.GetActiveKeystoneInfo)
    level = ML.ReadNum(level)
    local ids = {}
    if type(affixes) == "table" then
        for _, a in ipairs(affixes) do
            local n = ML.ReadNum(a)
            if n then ids[#ids + 1] = n end
        end
    end
    return { level = level, affixes = ids, charged = charged and true or false }
end

-- Static dungeon info: { name, timeLimit, texture }. Falls back gracefully to just an id name.
local mapInfoCache = {}
function API.GetMapInfo(mapId)
    mapId = ML.ReadNum(mapId)
    if not mapId then return nil end
    if mapInfoCache[mapId] then return mapInfoCache[mapId] end
    if not (C_CM and C_CM.GetMapUIInfo) then return nil end
    local name, _, timeLimit, texture = safe("GetMapUIInfo", C_CM.GetMapUIInfo, mapId)
    local info = {
        name      = ML.ReadStr(name) or ("Dungeon " .. mapId),
        timeLimit = ML.ReadNum(timeLimit),   -- seconds
        texture   = ML.ReadNum(texture),
    }
    mapInfoCache[mapId] = info
    return info
end

function API.GetAffixName(affixId)
    affixId = ML.ReadNum(affixId)
    if not (affixId and C_CM and C_CM.GetAffixInfo) then return nil end
    local name = safe("GetAffixInfo", C_CM.GetAffixInfo, affixId)
    return ML.ReadStr(name)
end

function API.GetAffixNames(ids)
    local out = {}
    if type(ids) == "table" then
        for _, id in ipairs(ids) do out[#out + 1] = API.GetAffixName(id) or ("#" .. tostring(id)) end
    end
    return out
end

-- Normalized completion info read at CHALLENGE_MODE_COMPLETED.
-- Returns { mapId, level, durationSec, onTime, upgradeLevels } or nil. Prefers the modern
-- table-returning GetChallengeCompletionInfo (11.0.5+); falls back to the deprecated positional
-- GetCompletionInfo. Both report `time` in milliseconds.
function API.GetCompletion()
    if not C_CM then return nil end
    if type(C_CM.GetChallengeCompletionInfo) == "function" then
        local info = safe("GetChallengeCompletionInfo", C_CM.GetChallengeCompletionInfo)
        if type(info) == "table" then
            local mapId, level = ML.ReadNum(info.mapChallengeModeID), ML.ReadNum(info.level)
            local timeMs = ML.ReadNum(info.time)
            if mapId and level then
                return {
                    mapId = mapId, level = level,
                    durationSec = timeMs and (timeMs / 1000) or nil,
                    onTime = info.onTime and true or false,
                    upgradeLevels = ML.ReadNum(info.keystoneUpgradeLevels),
                }
            end
        end
    end
    if type(C_CM.GetCompletionInfo) == "function" then
        local mapId, level, timeMs, onTime, upgradeLevels = safe("GetCompletionInfo", C_CM.GetCompletionInfo)
        mapId, level, timeMs = ML.ReadNum(mapId), ML.ReadNum(level), ML.ReadNum(timeMs)
        if mapId and level then
            return {
                mapId = mapId, level = level,
                durationSec = timeMs and (timeMs / 1000) or nil,
                onTime = onTime and true or false,
                upgradeLevels = ML.ReadNum(upgradeLevels),
            }
        end
    end
    return nil
end

-- Season id, or nil when unknown. GetCurrentSeason returns -1 until RequestMapInfo() has run and
-- 0 in the off-season - both map to nil here so a run still records under "Season ?".
function API.RequestSeasonInfo()
    if C_MP and C_MP.RequestMapInfo then pcall(C_MP.RequestMapInfo) end
end

function API.GetCurrentSeason()
    if not (C_MP and C_MP.GetCurrentSeason) then return nil end
    local id = ML.ReadNum(safe("GetCurrentSeason", C_MP.GetCurrentSeason))
    if id == nil or id <= 0 then return nil end
    return id
end

-- Current expansion level (0 = Classic ... rising per expansion). Stamped on new runs so retention
-- can scope by expansion; nil when the API is unavailable (older/edge clients) so runs recorded then
-- stay unclassified and are never pruned on a guess.
function API.GetExpansionLevel()
    if type(_G.GetExpansionLevel) ~= "function" then return nil end
    local lvl = ML.ReadNum(safe("GetExpansionLevel", _G.GetExpansionLevel))
    if lvl == nil or lvl < 0 then return nil end
    return lvl
end

-- The current season's dungeon map-id pool (for the Dungeons page). Empty table if unavailable.
function API.GetSeasonMapPool()
    local out = {}
    if not (C_CM and C_CM.GetMapTable) then return out end
    local t = safe("GetMapTable", C_CM.GetMapTable)
    if type(t) == "table" then
        for _, id in ipairs(t) do
            local n = ML.ReadNum(id)
            if n then out[#out + 1] = n end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Group roster + identity. Mythic+ is always a party (<=5), never a raid.
----------------------------------------------------------------------
local function realmOf(unit)
    local _, realm = UnitName(unit)
    if realm and realm ~= "" then return realm end
    local nr = GetNormalizedRealmName and GetNormalizedRealmName()
    return (nr and nr ~= "" and nr) or GetRealmName() or "?"
end

-- Normalized member record for a unit, or nil if the unit isn't valid/readable.
function API.MemberFor(unit)
    if not UnitExists(unit) then return nil end
    local name = ML.ReadStr(UnitName(unit))
    if not name then return nil end
    local guid = ML.ReadStr(UnitGUID(unit))
    local realm = realmOf(unit)
    local _, classFile, classId = UnitClass(unit)
    local role = UnitGroupRolesAssigned(unit)
    if role == "NONE" or role == nil then role = nil end
    local guild = GetGuildInfo(unit)
    local m = {
        unit      = unit,
        guid      = ML.ReadStr(guid),
        name      = name,
        realm     = realm,
        fullName  = name .. "-" .. realm,
        classFile = ML.ReadStr(classFile),
        classId   = ML.ReadNum(classId),
        role      = ML.CanRead(role) and role or nil,
        guildName = ML.ReadStr(guild),
        specId    = API.UnitSpec(unit),   -- reliable for self; usually nil for others
        mplusScore = API.MythicRating(unit),
        itemLevel = API.ItemLevel(unit),  -- live for self; nil for others until inspected (filled at run start)
        isPlayer  = UnitIsUnit(unit, "player") and true or false,
    }
    return m
end

-- Spec id: reliable for the player, best-effort (usually nil) for others.
function API.UnitSpec(unit)
    if UnitIsUnit(unit, "player") then
        local idx = GetSpecialization and GetSpecialization()
        if idx then
            local specId = GetSpecializationInfo and GetSpecializationInfo(idx)
            return ML.ReadNum(specId)
        end
        return nil
    end
    -- Others: only available via a completed inspect; we do not force inspects. Leave nil.
    return nil
end

-- Iterate the current party (including the player) -> array of normalized member records.
function API.GroupMembers()
    local out = {}
    local me = API.MemberFor("player")
    if me then out[#out + 1] = me end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        -- M+ is never a raid, but stay safe: read raid1..raidN excluding the player.
        for i = 1, n do
            local u = "raid" .. i
            if not UnitIsUnit(u, "player") then
                local m = API.MemberFor(u)
                if m then out[#out + 1] = m end
            end
        end
    else
        for i = 1, math.max(0, n - 1) do
            local m = API.MemberFor("party" .. i)
            if m then out[#out + 1] = m end
        end
    end
    return out
end

-- Self identity for stamping a run onto the exact character that completed it.
function API.PlayerContext()
    local name = ML.ReadStr(UnitName("player")) or "?"
    local realm = realmOf("player")
    local _, classFile, classId = UnitClass("player")
    local specId = API.UnitSpec("player")
    local specName, role
    if specId then
        local idx = GetSpecialization and GetSpecialization()
        if idx then
            local _, sName, _, _, sRole = GetSpecializationInfo(idx)
            specName = ML.ReadStr(sName)
            role = ML.CanRead(sRole) and sRole or nil
        end
    end
    role = role or UnitGroupRolesAssigned("player")
    if role == "NONE" then role = nil end
    return {
        guid      = ML.ReadStr(UnitGUID("player")),
        name      = name,
        realm     = realm,
        fullName  = name .. "-" .. realm,
        classFile = ML.ReadStr(classFile),
        classId   = ML.ReadNum(classId),
        specId    = specId,
        specName  = specName,
        itemLevel = API.ItemLevel("player"),
        role      = ML.CanRead(role) and role or nil,
    }
end

-- A stable identity key for a member: GUID preferred, else Name-Realm. Never merges on a bare
-- unqualified name (that would fold different-realm players together).
function API.IdentityKey(member)
    if type(member) ~= "table" then return nil end
    if member.guid and member.guid ~= "" then return member.guid end
    if member.fullName and member.fullName:find("-", 1, true) then return member.fullName end
    return nil   -- unqualified name only -> refuse to key (caller drops it)
end

-- Whether Details! (the addon) is present and loaded.
function API.IsDetailsLoaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if not loaded then return false end
    local ok, res = pcall(loaded, "Details")
    return ok and res and true or false
end
