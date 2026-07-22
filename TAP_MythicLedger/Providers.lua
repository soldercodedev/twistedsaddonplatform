-- TAP: Mythic Ledger - Providers.lua
-- Combat-statistics providers behind ONE normalized interface. Source: Blizzard's built-in
-- C_DamageMeter (the only meter data available to addons in Midnight - the combat log is now
-- forbidden), falling back to metadata-only when the meter is unavailable. The rest of the module
-- never cares which provider answered; it consumes the normalized shape below and treats nil as
-- "unavailable" (never zero).

local ADDON, ML = ...
local API = ML.API
local Providers = {}
ML.Providers = Providers

----------------------------------------------------------------------
-- Normalized stat block helpers.
----------------------------------------------------------------------
local STAT_KEYS = {
    "damage", "dps", "damageTaken", "avoidableDamageTaken", "absorbs",
    "healing", "hps", "overhealing", "interrupts", "dispels", "crowdControls", "deaths",
}
Providers.STAT_KEYS = STAT_KEYS

local function emptyStats()
    return {
        damage = nil, dps = nil, damageTaken = nil, avoidableDamageTaken = nil, absorbs = nil,
        healing = nil, hps = nil, overhealing = nil,
        interrupts = nil, dispels = nil, crowdControls = nil, deaths = nil,
    }
end
Providers.emptyStats = emptyStats

----------------------------------------------------------------------
-- CombatCounters: legacy per-GUID tallies. In MIDNIGHT the combat log is RESTRICTED for addons -
-- registering COMBAT_LOG_EVENT_UNFILTERED is a forbidden action that trips a taint block (even at
-- load), and it never delivered events anyway (that was the "CLEU seen 0/0/0"). So we no longer
-- register it at all. Deaths / interrupts / dispels now come entirely from C_DamageMeter. The table
-- and its API are kept as inert stubs so callers (Tracker, backfill) don't need to change.
----------------------------------------------------------------------
local Counters = {
    active = false,
    party  = {},   -- guid -> true
    data   = {},   -- guid -> { deaths, interrupts, dispels } (stays empty; no CLEU in Midnight)
}
Providers.Counters = Counters

function Counters.Reset() wipe(Counters.data) end
function Counters.SetParty(guids)
    wipe(Counters.party)
    if type(guids) == "table" then
        for _, g in ipairs(guids) do if g then Counters.party[g] = true end end
    end
end
function Counters.Start() Counters.active = true end   -- intentionally does NOT touch the combat log
function Counters.Stop()  Counters.active = false end
function Counters.Get(guid) return Counters.data[guid] end

-- Backfill nil metrics from the counters. A no-op now that they stay empty (kept for the metadata
-- provider and any pre-Midnight client where the counters could still carry data).
local function backfillFromCounters(stats, guid)
    if not (stats and guid) then return stats end
    local c = Counters.Get(guid)
    if not c then return stats end
    if stats.deaths     == nil then stats.deaths = c.deaths end
    if stats.interrupts == nil then stats.interrupts = c.interrupts end
    if stats.dispels    == nil then stats.dispels = c.dispels end
    return stats
end
Providers.backfillFromCounters = backfillFromCounters

----------------------------------------------------------------------
-- ProviderBase - the interface every provider fulfils. Methods no-op by default.
----------------------------------------------------------------------
local Base = {}
Base.__index = Base
Providers.Base = Base

function Base.New(name, source)
    return setmetatable({ _name = name, _source = source }, Base)
end
function Base:GetName() return self._name end
function Base:GetSource() return self._source end
function Base:GetVersion() return nil end
function Base:IsAvailable() return false end
function Base:BeginRun(_) end
function Base:EndRun(_) end
function Base:Reset() end
-- GetRunStats(ctx) -> normalized { source, sourceVersion, player = {stats}, party = { {identity+stats} } } or nil
function Base:GetRunStats(_) return nil end
-- GetPlayerDamage(ctx) -> your CUMULATIVE damage-done so far this run (number), or nil. The tracker
-- samples this at each boss's start and kill and divides the delta by the fight length to get a true
-- per-boss DPS (Details' "current combat" during a key is the whole run, so a raw read = overall).
function Base:GetPlayerDamage(_) return nil end

----------------------------------------------------------------------
-- MetadataProvider - always available, supplies no meter data (source NONE). The counters still
-- backfill deaths/interrupts/dispels, so even here those are real.
----------------------------------------------------------------------
local Metadata = Base.New("Metadata", ML.SOURCE.NONE)
Providers.Metadata = Metadata
function Metadata:IsAvailable() return true end
function Metadata:GetRunStats(ctx)
    local out = { source = ML.SOURCE.NONE, sourceVersion = nil, player = emptyStats(), party = {} }
    if ctx and ctx.party then
        for _, m in ipairs(ctx.party) do
            local s = emptyStats()
            s.guid, s.name, s.realm, s.fullName = m.guid, m.name, m.realm, m.fullName
            s.classId, s.classFile, s.specId, s.role = m.classId, m.classFile, m.specId, m.role
            backfillFromCounters(s, m.guid)
            out.party[#out.party + 1] = s
        end
    end
    if ctx and ctx.player then backfillFromCounters(out.player, ctx.player.guid) end
    return out
end


----------------------------------------------------------------------
-- BlizzardProvider - the built-in Retail damage meter (C_DamageMeter, added in patch 12.0).
-- Availability: C_DamageMeter.IsDamageMeterAvailable(). Data: C_DamageMeter.GetCombatSessionFromType(
--   sessionType, type) -> { combatSources = { {sourceGUID, name, classFilename, totalAmount,
--   amountPerSecond, isLocalPlayer, ...}, ... }, durationSeconds }. sessionType uses
--   Enum.DamageMeterSessionType (0 Overall / 1 Current / 2 Expired) and `type` uses
--   Enum.DamageMeterType (DamageDone/Dps/HealingDone/Hps/Absorbs/Interrupts/Dispels/DamageTaken/
--   AvoidableDamageTaken/Deaths/EnemyDamageTaken). We read the OVERALL session (the whole run, not
--   just the last boss), never reset or reconfigure anything, and leave unsupported metrics nil.
----------------------------------------------------------------------
local Blizz = Base.New("Blizzard Meter", ML.SOURCE.BLIZZARD)
Providers.Blizzard = Blizz

local function C_DM() return _G.C_DamageMeter end

function Blizz:IsAvailable()
    local dm = C_DM()
    if type(dm) ~= "table" then return false end
    if type(dm.IsDamageMeterAvailable) == "function" then
        local ok, avail = pcall(dm.IsDamageMeterAvailable)
        if ok then return avail and true or false end
    end
    -- Older/edge builds: fall back to the presence of the session accessor.
    return type(dm.GetCombatSessionFromType) == "function"
end

-- Read the OVERALL session for each metric from C_DamageMeter, index per-source totals by GUID, and
-- assemble a normalized stat block per group member. C_DamageMeter is the only meter data addons
-- can read in Midnight. `sourceLabel` stamps out.source. Returns nil if unavailable.
local function readMeterStats(ctx, sourceLabel)
    local ok, result = pcall(function()
        local dm = C_DM()
        if type(dm) ~= "table" or type(dm.GetCombatSessionFromType) ~= "function" then return nil end
        local ST = _G.Enum and _G.Enum.DamageMeterSessionType
        local MT = _G.Enum and _G.Enum.DamageMeterType
        if type(ST) ~= "table" or type(MT) ~= "table" then return nil end
        local sessionType = ST.Overall or 0

        local perGuid = {}
        local function bucket(guid) perGuid[guid] = perGuid[guid] or {}; return perGuid[guid] end
        local function sourcesOf(metricType)
            if metricType == nil then return nil end
            local session = dm.GetCombatSessionFromType(sessionType, metricType)
            if type(session) == "table" and type(session.combatSources) == "table" then
                return session.combatSources
            end
            return nil
        end

        -- Midnight Secret-wraps src.sourceGUID (ML.ReadStr -> nil), which would silently DROP that source
        -- - including the LOCAL player, so finalize baked "playerDPS=nil" despite real live per-boss
        -- numbers. The local player stays identifiable via the non-Secret isLocalPlayer flag, so key their
        -- row under our known guid (mirrors readPartyDamageMap).
        local pGuid = ctx and ctx.player and ctx.player.guid
        local function keyOf(src)
            local g = ML.ReadStr(src.sourceGUID)
            if not g and src.isLocalPlayer and pGuid then g = pGuid end
            return g
        end

        -- Damage: totalAmount = damage, amountPerSecond = dps (Blizzard computes dps off effective
        -- combat time, so it matches the meter display - don't recompute damage/time ourselves).
        for _, src in ipairs(sourcesOf(MT.DamageDone) or {}) do
            local g = keyOf(src)
            if g then
                local d = bucket(g)
                d.damage = ML.ReadNum(src.totalAmount); d.dps = ML.ReadNum(src.amountPerSecond)
                d.specIcon = ML.ReadNum(src.specIconID)
            end
        end
        -- Healing: totalAmount = healing, amountPerSecond = hps.
        for _, src in ipairs(sourcesOf(MT.HealingDone) or {}) do
            local g = keyOf(src)
            if g then local d = bucket(g); d.healing = ML.ReadNum(src.totalAmount); d.hps = ML.ReadNum(src.amountPerSecond) end
        end
        -- Single-value metrics: one row per source, totalAmount = the value/count. These key straight
        -- by source and overwrite (one row per member).
        local single = {
            damageTaken = MT.DamageTaken, avoidableDamageTaken = MT.AvoidableDamageTaken,
            absorbs = MT.Absorbs,
        }
        for key, mt in pairs(single) do
            for _, src in ipairs(sourcesOf(mt) or {}) do
                local g = keyOf(src)
                if g then bucket(g)[key] = ML.ReadNum(src.totalAmount) end
            end
        end
        -- Interrupts & dispels can come from a PET (Warlock Spell Lock / Devour Magic, ...) whose
        -- sourceGUID isn't a group member, and a pet that died + resummoned appears as SEVERAL distinct
        -- source rows over the run. So fold any pet source into its OWNER (ctx.petOwners, mapped live by
        -- the Tracker) and ACCUMULATE across all rows for that owner, rather than overwrite/drop.
        local petOwners = (ctx and ctx.petOwners) or nil
        local folded = { interrupts = MT.Interrupts, dispels = MT.Dispels }
        for key, mt in pairs(folded) do
            for _, src in ipairs(sourcesOf(mt) or {}) do
                local g = keyOf(src)
                if g and petOwners and petOwners[g] then g = petOwners[g] end   -- pet -> owner
                local v = g and ML.ReadNum(src.totalAmount)
                if v then local d = bucket(g); d[key] = (d[key] or 0) + v end
            end
        end
        -- Deaths are DIFFERENT: the Deaths session is a LIST of death EVENTS (one row per death), not
        -- a per-source total. So COUNT rows per GUID (a player appearing twice died twice). Reading
        -- totalAmount here returned 0 and hid real deaths (a death showed as "0", not counted).
        for _, src in ipairs(sourcesOf(MT.Deaths) or {}) do
            local g = keyOf(src)
            if g then local d = bucket(g); d.deaths = (d.deaths or 0) + 1 end
        end

        -- Nothing readable anywhere (all-Secret sources, or the Overall session hasn't settled yet):
        -- return nil so finalize RETRIES rather than baking an all-empty run over real live numbers.
        if next(perGuid) == nil then return nil end

        local function statsFor(guid)
            local s = emptyStats()
            local d = guid and perGuid[guid]
            if d then for k, v in pairs(d) do s[k] = v end end
            return s
        end

        local out = { source = sourceLabel or ML.SOURCE.BLIZZARD, sourceVersion = nil, player = emptyStats(), party = {} }
        if ctx and ctx.player then out.player = statsFor(ctx.player.guid) end
        if ctx and ctx.party then
            for _, m in ipairs(ctx.party) do
                local s = statsFor(m.guid)
                s.guid, s.name, s.realm, s.fullName = m.guid, m.name, m.realm, m.fullName
                s.classId, s.classFile, s.specId, s.role = m.classId, m.classFile, m.specId, m.role
                out.party[#out.party + 1] = s
            end
        end
        return out
    end)
    if not ok then
        ML.Log("C_DamageMeter extraction failed: %s", tostring(result))
        return nil
    end
    return result
end
Providers.ReadMeterStats = readMeterStats

-- Your cumulative damage-done for the whole run (Overall DamageDone total). The tracker diffs this
-- across each boss to isolate per-boss DPS. From C_DamageMeter so it's reliable in Midnight.
local function readPlayerDamageMeter(ctx)
    if not (ctx and ctx.player) then return nil end
    local ok, dmg = pcall(function()
        local dm = C_DM()
        if type(dm) ~= "table" or type(dm.GetCombatSessionFromType) ~= "function" then return nil end
        local ST = _G.Enum and _G.Enum.DamageMeterSessionType
        local MT = _G.Enum and _G.Enum.DamageMeterType
        if type(ST) ~= "table" or type(MT) ~= "table" then return nil end
        local session = dm.GetCombatSessionFromType(ST.Overall or 0, MT.DamageDone or 0)
        if type(session) ~= "table" or type(session.combatSources) ~= "table" then return nil end
        for _, src in ipairs(session.combatSources) do
            if src.isLocalPlayer or ML.ReadStr(src.sourceGUID) == ctx.player.guid then
                return ML.ReadNum(src.totalAmount)
            end
        end
        return nil
    end)
    return ok and dmg or nil
end
Providers.ReadPlayerDamage = readPlayerDamageMeter

-- Cumulative TOTAL party deaths so far this run (Overall Deaths summed over the party GUIDs). The
-- tracker diffs this across each boss to attribute deaths to that boss.
local function readPartyDeathsMeter(ctx)
    local ok, total = pcall(function()
        local dm = C_DM()
        if type(dm) ~= "table" or type(dm.GetCombatSessionFromType) ~= "function" then return nil end
        local ST = _G.Enum and _G.Enum.DamageMeterSessionType
        local MT = _G.Enum and _G.Enum.DamageMeterType
        if type(ST) ~= "table" or type(MT) ~= "table" or MT.Deaths == nil then return nil end
        local session = dm.GetCombatSessionFromType(ST.Overall or 0, MT.Deaths)
        if type(session) ~= "table" or type(session.combatSources) ~= "table" then return nil end
        local partySet
        if ctx then
            partySet = {}
            if ctx.player and ctx.player.guid then partySet[ctx.player.guid] = true end
            for _, m in ipairs(ctx.party or {}) do if m.guid then partySet[m.guid] = true end end
        end
        local n = 0
        for _, src in ipairs(session.combatSources) do
            local g = ML.ReadStr(src.sourceGUID)
            if (not partySet) or (g and partySet[g]) then n = n + 1 end   -- each row is ONE death
        end
        return n
    end)
    return ok and total or nil
end
Providers.ReadPartyDeaths = readPartyDeathsMeter

-- AUTHORITATIVE party death total from the game's own Mythic+ death counter (the one that adds +5s to
-- the timer per death). Reliable - unlike the C_DamageMeter Deaths metric, which in Midnight often
-- reports 0/nil - but it's a TOTAL only (no per-player attribution). Available during an active key.
function Providers.ChallengeModeDeaths()
    local CM = _G.C_ChallengeMode
    if type(CM) ~= "table" or type(CM.GetDeathCount) ~= "function" then return nil end
    local ok, n = pcall(CM.GetDeathCount)   -- returns numDeaths, timeLost
    if not ok then return nil end
    return ML.ReadNum(n)
end

-- Cumulative per-source { damage, avoid } from the Overall session, keyed by GUID. The tracker
-- snapshots this at each boss's start and kill and diffs it to find that boss's top DPS and the
-- lowest avoidable damage taken across the party.
-- Which session the last readPartyDamageMap used (for diagnostics: "OVERALL" / "CURRENT" / nil), and
-- the raw enum value, so a caller can FORCE the same session on the paired read (see below).
Providers.LastDamageMapSession = nil
Providers.LastDamageMapSessionType = nil
-- `forceSession` (an Enum.DamageMeterSessionType value) pins the session instead of auto-picking. The
-- tracker MUST pin the boss-KILL read to whatever session the boss-START read used - otherwise a mid-
-- fight Overall<->Current flip diffs two different sessions (garbage deltas: wrong/negative DPS, lost
-- deaths). Pass Providers.LastDamageMapSessionType from the start snapshot.
local function readPartyDamageMap(ctx, forceSession)
    local out = {}
    pcall(function()
        local dm = C_DM()
        if type(dm) ~= "table" or type(dm.GetCombatSessionFromType) ~= "function" then return end
        local ST = _G.Enum and _G.Enum.DamageMeterSessionType
        local MT = _G.Enum and _G.Enum.DamageMeterType
        if type(ST) ~= "table" or type(MT) ~= "table" then return end

        -- Boss diffs ALWAYS span an in-combat window, and the Overall session reads FROZEN/EMPTY while
        -- combat is in progress on the live Midnight client - so a start->end Overall diff comes back
        -- all-zero (the "no per-boss DPS/HPS" bug). The CURRENT combat session DOES accumulate in combat,
        -- so pin the boss reads to it. Its one quirk is a per-combat RESET (end < start if combat dropped
        -- and restarted between the two snapshots) - computeBossCombat handles that (uses the post-reset
        -- total). Paired reads are pinned via forceSession so start and end never diff mismatched sessions.
        local sessionType, label
        if forceSession ~= nil then
            sessionType = forceSession
            label = (ST.Current ~= nil and forceSession == ST.Current) and "CURRENT" or "OVERALL"
        else
            -- Overall accumulates the whole run and updates in combat (verified: its durationSeconds
            -- ticks up mid-fight), so a start->kill diff isolates the boss. Monotonic - no per-combat
            -- reset to reconcile, unlike Current.
            sessionType, label = ST.Overall or 0, "OVERALL"
        end
        Providers.LastDamageMapSession = label
        Providers.LastDamageMapSessionType = sessionType

        -- Midnight Secret-wraps src.sourceGUID, so ML.ReadStr often returns nil and keying purely by GUID
        -- silently DROPS every source (the "0 srcs / your guid present: NO" bug). The LOCAL player is
        -- still identifiable via the non-Secret isLocalPlayer flag, so key their row under our known guid.
        local pGuid = ctx and ctx.player and ctx.player.guid
        local function keyOf(src)
            local g = ML.ReadStr(src.sourceGUID)
            if not g and src.isLocalPlayer and pGuid then g = pGuid end
            return g
        end
        local function grab(metric, key)
            if metric == nil then return end
            local s = dm.GetCombatSessionFromType(sessionType, metric)
            if type(s) ~= "table" or type(s.combatSources) ~= "table" then return end
            for _, src in ipairs(s.combatSources) do
                local g, amt = keyOf(src), ML.ReadNum(src.totalAmount)
                if g and amt then out[g] = out[g] or {}; out[g][key] = amt end
            end
        end
        grab(MT.DamageDone, "damage")
        grab(MT.HealingDone, "heal")
        grab(MT.AvoidableDamageTaken, "avoid")
        -- Deaths: COUNT rows per GUID (event list), not totalAmount - see readMeterStats.
        if MT.Deaths ~= nil then
            local s = dm.GetCombatSessionFromType(sessionType, MT.Deaths)
            if type(s) == "table" and type(s.combatSources) == "table" then
                for _, src in ipairs(s.combatSources) do
                    local g = keyOf(src)
                    if g then out[g] = out[g] or {}; out[g].deaths = (out[g].deaths or 0) + 1 end
                end
            end
        end
    end)
    return out
end
Providers.ReadPartyDamageMap = readPartyDamageMap

----------------------------------------------------------------------
-- Per-spell ATTRIBUTION (Midnight). C_DamageMeter hands addons the full per-spell breakdown per source
-- via GetCombatSessionSourceFromType(sessionType, meterType, sourceGUID): each combatSpells[] entry
-- carries spellID, totalAmount (damage - or a COUNT for interrupts/dispels), amountPerSecond,
-- overkillAmount, isDeadly, and combatSpellDetails.unitName (who dealt it). This turns the aggregate
-- stat block into named detail - what each player dealt / healed / took / avoided / kicked / dispelled,
-- and (via overkillAmount / isDeadly) what actually killed them. Read at finalize, out of combat, where
-- source GUIDs come back as plain strings. Nothing here feeds scoring; it's captured for the run log.
----------------------------------------------------------------------
local ATTR_CAP = nil                       -- FULLY UNCAPPED (user: log ALL raw spell rows for rescoring /
                                           -- tuning). topByAmt still sorts biggest-first; nil = never trim.
local MELEE_SPELLS = { [6603] = true }     -- 6603 = Auto Attack; a non-tank death to melee => threat/aggro
Providers.ATTR_CAP = ATTR_CAP
Providers.MELEE_SPELLS = MELEE_SPELLS

-- One GetCombatSessionSourceFromType(sessionType, meterType, guid) record -> normalized spell list.
-- `keepSrc` also records the dealing unit's name (useful for damage-taken / avoidable). `.ok` is only
-- present when overkillAmount>0 (the killing blow) and `.deadly` only when isDeadly - the two fatal-blow
-- signals used by death classification. Returns {} on no data (never nil, so callers can ipairs freely).
local function normSpells(getter, sessionType, meterType, guid, keepSrc)
    local out = {}
    if type(getter) ~= "function" or meterType == nil or not guid then return out end
    local ok, src = pcall(getter, sessionType, meterType, guid)
    if not ok or type(src) ~= "table" or type(src.combatSpells) ~= "table" then return out end
    for _, s in ipairs(src.combatSpells) do
        local id = ML.ReadNum(s.spellID)
        if id then
            local e = { id = id, amt = ML.ReadNum(s.totalAmount) or 0 }
            local over = ML.ReadNum(s.overkillAmount)
            if over and over > 0 then e.ok = over end
            if s.isDeadly then e.deadly = true end
            if keepSrc then
                local d = type(s.combatSpellDetails) == "table" and s.combatSpellDetails
                local nm = d and ML.ReadStr(d.unitName)
                if nm and nm ~= "" then e.src = nm end
            end
            out[#out + 1] = e
        end
    end
    return out
end

local function topByAmt(list, cap)
    table.sort(list, function(x, y) return (x.amt or 0) > (y.amt or 0) end)
    if cap and #list > cap then for i = #list, cap + 1, -1 do list[i] = nil end end
    return list
end

-- Per-GUID per-spell breakdown for the whole run. Returns { [guid] = { damageDone, healingDone,
-- damageTaken, avoidable, interrupts, dispels } } (each a capped, amount-sorted spell list) or nil if
-- the meter/source API is unavailable. Pet kicks/dispels fold into the owner (mirrors readMeterStats).
function Providers.ReadAttribution(ctx)
    local dm = C_DM()
    if type(dm) ~= "table" or type(dm.GetCombatSessionSourceFromType) ~= "function" then return nil end
    local ST = _G.Enum and _G.Enum.DamageMeterSessionType
    local MT = _G.Enum and _G.Enum.DamageMeterType
    if type(ST) ~= "table" or type(MT) ~= "table" then return nil end
    local sess = ST.Overall or 0
    local getT = dm.GetCombatSessionSourceFromType

    local guids, order = {}, {}
    local function add(g) if g and not guids[g] then guids[g] = true; order[#order + 1] = g end end
    if ctx and ctx.player then add(ctx.player.guid) end
    for _, m in ipairs((ctx and ctx.party) or {}) do add(m.guid) end
    if #order == 0 then return nil end

    local out = {}
    for _, g in ipairs(order) do
        out[g] = {
            damageDone  = topByAmt(normSpells(getT, sess, MT.DamageDone, g, false), ATTR_CAP),
            healingDone = topByAmt(normSpells(getT, sess, MT.HealingDone, g, false), ATTR_CAP),
            damageTaken = topByAmt(normSpells(getT, sess, MT.DamageTaken, g, true), ATTR_CAP),
            avoidable   = topByAmt(normSpells(getT, sess, MT.AvoidableDamageTaken, g, true), ATTR_CAP),
            interrupts  = normSpells(getT, sess, MT.Interrupts, g, false),
            dispels     = normSpells(getT, sess, MT.Dispels, g, false),
        }
    end

    -- Fold pet kicks/dispels (Warlock Spell Lock / Devour Magic, Hunter pets, ...) into the OWNER's
    -- lists - pets are separate source GUIDs, so their per-spell rows would otherwise be lost even though
    -- readMeterStats already counts them in the aggregate. Append then re-cap.
    local petOwners = ctx and ctx.petOwners
    if petOwners then
        for petGuid, owner in pairs(petOwners) do
            local dst = out[owner]
            if dst then
                for _, e in ipairs(normSpells(getT, sess, MT.Interrupts, petGuid, false)) do dst.interrupts[#dst.interrupts + 1] = e end
                for _, e in ipairs(normSpells(getT, sess, MT.Dispels, petGuid, false)) do dst.dispels[#dst.dispels + 1] = e end
            end
        end
    end
    for _, a in pairs(out) do topByAmt(a.interrupts, ATTR_CAP); topByAmt(a.dispels, ATTR_CAP) end
    return out
end

-- Normalize one C_DeathRecap.GetRecapEvents() entry. `ev` (event string) is the classifier's key signal:
-- "SWING_DAMAGE" = a melee auto, "SPELL_HEAL"/"SPELL_PERIODIC_HEAL" = a heal (skipped when finding the
-- fatal blow). spellId/spellName/amount/overkill/currentHP/timestamp complete the raw record.
local function normRecapEvent(ev)
    local evt = ML.ReadStr(ev.event)
    local nm  = ML.ReadStr(ev.spellName)
    if not nm or nm == "" then   -- melee / heal / environmental events carry no spellName - label like the game
        if evt == "SWING_DAMAGE" then nm = "Melee"
        elseif evt == "SPELL_HEAL" or evt == "SPELL_PERIODIC_HEAL" then nm = "Heal"
        elseif evt == "ENVIRONMENTAL_DAMAGE" then nm = "Environmental" end   -- fall / lava / fire / slime
    end
    return {
        id   = ML.ReadNum(ev.spellId),
        name = nm,
        amt  = ML.ReadNum(ev.amount),
        over = ML.ReadNum(ev.overkill),   -- >0 only on the killing blow; the API uses -1 as "no overkill"
        hp   = ML.ReadNum(ev.currentHP),
        ts   = ML.ReadNum(ev.timestamp),
        ev   = evt,
    }
end

-- Pull each death's RECAP via C_DeathRecap.GetRecapEvents(recapID) - the authoritative per-death hit
-- timeline (the same source the built-in meter's death view uses; confirmed against EllesmereUI). The
-- deathRecapID lives on each Overall Deaths row. C_DamageMeter's own accessors do NOT expose this - the
-- recap is a separate namespace. Events are stored RAW (chronological oldest-first, all of them) in the
-- run log for rescoring/inspection. Returns { [guid] = { { recapID, maxHP, events = { {id,name,amt,over,
-- hp,ts,ev} } } } } or nil. Note: the client typically only holds recaps for the LOCAL player's deaths,
-- so a teammate's recapID may return no events (their death then falls to reconciliation -> other).
function Providers.ReadDeathRecaps(ctx)
    local dm = C_DM()
    local DR = _G.C_DeathRecap
    if type(dm) ~= "table" or type(DR) ~= "table" or type(DR.GetRecapEvents) ~= "function" then return nil end
    local ST = _G.Enum and _G.Enum.DamageMeterSessionType
    local MT = _G.Enum and _G.Enum.DamageMeterType
    if type(ST) ~= "table" or type(MT) ~= "table" then return nil end
    local okD, deaths = pcall(dm.GetCombatSessionFromType, ST.Overall or 0, MT.Deaths)
    if not (okD and type(deaths) == "table" and type(deaths.combatSources) == "table") then return nil end

    local out, any = {}, false
    for _, row in ipairs(deaths.combatSources) do
        local guid = ML.ReadStr(row.sourceGUID)
        local rid  = ML.ReadNum(row.deathRecapID)
        if guid and rid and rid > 0 then
            local events = {}
            local ok, raw = pcall(DR.GetRecapEvents, rid)
            if ok and type(raw) == "table" then
                -- GetRecapEvents returns newest-first; store chronological (oldest-first) so the fatal
                -- blow is the LAST non-heal event - matches how the built-in recap orders its display.
                for i = #raw, 1, -1 do
                    if type(raw[i]) == "table" then events[#events + 1] = normRecapEvent(raw[i]) end
                end
            end
            local maxHP
            if type(DR.GetRecapMaxHealth) == "function" then
                local ok2, hp = pcall(DR.GetRecapMaxHealth, rid); if ok2 then maxHP = ML.ReadNum(hp) end
            end
            out[guid] = out[guid] or {}
            out[guid][#out[guid] + 1] = { recapID = rid, maxHP = maxHP, events = events }
            any = true
        end
    end
    return any and out or nil
end

-- Classify deaths from the WHOLE recap, not just the killing blow. The final hit is often only "the
-- straw" - what actually killed you is whatever got you low: avoidable damage you stood in, or
-- unmitigated melee from losing aggro (non-tank). So we sum each death's recap damage by category and
-- name the cause by DOMINANT contribution: if avoidable or melee(non-tank) makes up >= DEATH_CAUSE_SHARE
-- of the death's total damage, the larger of the two wins; otherwise the death was genuinely unavoidable
-- => other. Categories, judged per hit against the whole recap: AVOIDABLE (spellId in the run's
-- avoidable-damage bucket), THREAT (melee / SWING_DAMAGE on a non-tank), MISSED KICK (spellId in the
-- dungeon's kick catalog `kickSet` - an interruptible cast that landed instead of being kicked), else
-- OTHER. Per-hit precedence is avoidable -> threat -> kickable, so "missed kick" is carved out of what
-- used to be "other" (avoidable/threat classification is unchanged). Reconciles to `deathCount`. The
-- buckets drive the cause-weighted Death penalty in Cat.Deaths (kickable weighted the same as other).
function Providers.ClassifyDeaths(attribution, recaps, role, deathCount, kickSet)
    local DEATH_CAUSE_SHARE = 0.20   -- a category must be >=20% of a death's damage to be named its cause
    local avoidSet = {}
    if type(attribution) == "table" then
        for _, e in ipairs(attribution.avoidable or {}) do if e.id then avoidSet[e.id] = true end end
    end
    kickSet = type(kickSet) == "table" and kickSet or {}
    local nonTank = role ~= "TANK"
    local function isHeal(e)  return e.ev == "SPELL_HEAL" or e.ev == "SPELL_PERIODIC_HEAL" end
    local function isMelee(e)
        if e.ev == "SWING_DAMAGE" then return true end
        return (e.id and MELEE_SPELLS[e.id]) and true or false
    end
    local function isAvoid(e) return (e.id and avoidSet[e.id]) and true or false end
    local function isKick(e)  return (e.id and kickSet[e.id]) and true or false end
    -- Environmental damage (fall / lava / fire / slime) is the player's OWN fault - treated as avoidable.
    local function isEnviro(e) return e.ev == "ENVIRONMENTAL_DAMAGE" end

    local b = { avoidable = 0, threat = 0, kickable = 0, other = 0, fatal = {} }
    if type(recaps) == "table" and #recaps > 0 then
        for _, death in ipairs(recaps) do
            local evs = death.events or {}
            -- Killing blow (overkill>0, else most recent non-heal) - kept purely for display.
            local killer
            for i = #evs, 1, -1 do local e = evs[i]; if e.over and e.over > 0 then killer = e; break end end
            if not killer then for i = #evs, 1, -1 do if not isHeal(evs[i]) then killer = evs[i]; break end end end
            -- Sum the death's damage by category over the WHOLE recap (heals excluded). Precedence per hit:
            -- avoidable, then threat (melee), then a missed kick - so kickable carves out of "other" only.
            local dTot, dAvoid, dMelee, dKick = 0, 0, 0, 0
            for _, e in ipairs(evs) do
                if not isHeal(e) then
                    local amt = e.amt or 0; if amt < 0 then amt = 0 end
                    dTot = dTot + amt
                    if isAvoid(e) then dAvoid = dAvoid + amt
                    elseif isMelee(e) and nonTank then dMelee = dMelee + amt
                    elseif isKick(e) then dKick = dKick + amt end
                end
            end
            local avShare = dTot > 0 and (dAvoid / dTot) or 0
            local meShare = dTot > 0 and (dMelee / dTot) or 0
            local kkShare = dTot > 0 and (dKick / dTot) or 0
            -- KILLING-BLOW PRECEDENCE (v41): the FATAL hit's own nature decides the cause first, before the
            -- whole-recap share math. If the finishing blow was avoidable - or ENVIRONMENTAL (fall / lava /
            -- fire = the player's own fault) - it's an avoidable death even when earlier chip damage was
            -- threat/other. If the finishing blow was a melee auto on a non-tank, it's a threat death. Only
            -- when the killing blow is none of these do we fall back to the dominant-share classification.
            local cause
            if killer then
                if isEnviro(killer) or isAvoid(killer) then cause = "avoidable"
                elseif isMelee(killer) and nonTank then cause = "threat"
                elseif isKick(killer) then cause = "kickable" end   -- fatal blow was an un-kicked cast
            end
            if not cause then
                -- Dominant share over the whole recap; a missed kick only carves out of "other".
                if avShare >= DEATH_CAUSE_SHARE or meShare >= DEATH_CAUSE_SHARE then
                    cause = (avShare >= meShare) and "avoidable" or "threat"
                elseif kkShare >= DEATH_CAUSE_SHARE then
                    cause = "kickable"
                else
                    cause = "other"
                end
            end
            b[cause] = b[cause] + 1
            -- Display name for the fatal blow. Recaps captured before v41 stored a nil name for
            -- environmental/melee hits, so fall back to an event-type label so the review never shows blank.
            local killerName = killer and killer.name
            if killer and not killerName then
                if killer.ev == "ENVIRONMENTAL_DAMAGE" then killerName = "Environmental"
                elseif killer.ev == "SWING_DAMAGE" then killerName = "Melee" end
            end
            b.fatal[#b.fatal + 1] = {
                cause = cause,
                killer = killerName, killerId = killer and killer.id, killerEvent = killer and killer.ev,
                avoidPct = math.floor(avShare * 100 + 0.5), meleePct = math.floor(meShare * 100 + 0.5),
                kickPct = math.floor(kkShare * 100 + 0.5),
            }
        end
    end

    if type(deathCount) == "number" then
        local found = b.avoidable + b.threat + b.kickable + b.other
        if found < deathCount then
            b.other = b.other + (deathCount - found)
        elseif found > deathCount then
            local over = found - deathCount
            for _, k in ipairs({ "other", "kickable", "threat", "avoidable" }) do
                local take = math.min(over, b[k]); b[k] = b[k] - take; over = over - take
                if over <= 0 then break end
            end
        end
    end
    if (b.avoidable + b.threat + b.kickable + b.other) > 0 then return b end
    return nil
end

-- Classify one SAVED member's deaths, preferring a FRESH classification from the stored raw death
-- recaps. We persist the raw recaps precisely so classifier improvements (e.g. the Missed Kick cause)
-- apply retroactively to already-saved runs without re-playing them. Builds the dungeon kick set from
-- the run. Falls back to whatever deathCauses was frozen at capture when no recaps are stored (very old
-- runs). Both the scoring layer and the run-review card go through this, so they always agree.
function Providers.ClassifyMemberDeaths(run, member)
    if not member then return nil end
    local n = member.stats and member.stats.deaths
    if type(n) ~= "number" or n <= 0 then return nil end
    if type(member.deathRecaps) == "table" and #member.deathRecaps > 0 then
        local kickSet
        local Cfg = ML.Scoring and ML.Scoring.Config
        local cat = run and Cfg and Cfg.SeasonDungeon and Cfg.SeasonDungeon(run.dungeonName)
        if cat and type(cat.kicks) == "table" then
            kickSet = {}
            for _, e in ipairs(cat.kicks) do if e.id then kickSet[e.id] = true end end
        end
        local dc = Providers.ClassifyDeaths(member.attribution, member.deathRecaps, member.role, n, kickSet)
        if dc then return dc end
    end
    return member.deathCauses
end

function Blizz:GetRunStats(ctx)
    return readMeterStats(ctx, ML.SOURCE.BLIZZARD)
end

function Blizz:GetPlayerDamage(ctx)
    return readPlayerDamageMeter(ctx)
end

----------------------------------------------------------------------
-- Selection: the built-in C_DamageMeter is the sole stat source (Blizzard). Metadata-only is the
-- fallback when the meter isn't available. `preference` is ignored now (the setting was removed).
----------------------------------------------------------------------
function Providers.Select()
    if Blizz:IsAvailable() then return Blizz end
    return Metadata
end

-- What the Debug page shows as the live provider.
function Providers.Describe()
    return {
        { name = "Blizzard Meter (C_DamageMeter)", available = Blizz:IsAvailable(), version = nil },
        { name = "Metadata-only",                  available = true,               version = nil },
    }
end
