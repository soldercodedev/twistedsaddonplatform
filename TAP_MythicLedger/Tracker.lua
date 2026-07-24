-- TAP: Mythic Ledger - Tracker.lua
-- The Mythic+ run lifecycle state machine. Detects real challenge-mode runs, captures dungeon /
-- keystone / character / party metadata, tracks boss encounters, waits (bounded) for the provider
-- to finalize stats, saves each run EXACTLY once, and recovers an in-progress run across a reload
-- or disconnect. Only Retail Mythic+ challenge runs are recorded - nothing else.

local ADDON, ML = ...
local API       = ML.API
local DB        = ML.DB
local Providers = ML.Providers
local STATE     = ML.STATE
local STATUS    = ML.STATUS
local STAT_KEYS = Providers.STAT_KEYS

local Tracker = {}
ML.Tracker = Tracker

----------------------------------------------------------------------
-- Working state (runtime only; the persisted recovery record lives in DB.activeRun).
----------------------------------------------------------------------
local state       = STATE.IDLE
local current     = nil    -- in-progress run working table
local encounters  = nil    -- encounterId -> boss tracking record
local provider    = nil
local retries     = 0
local combatWaits = 0      -- finalize deferrals while still in combat (key completed mid-trash-pull)
local finalizeTimer, rosterTimer
local frame
local runT0                -- GetTime() at run start, so boss kills can be stamped seconds-into-run
local runStartScore        -- your M+ score at run start, to compute this run's score gain

-- Pet -> owner GUID map, built LIVE across the whole run. C_DamageMeter attributes a pet's interrupts
-- (and pet dispels like Devour Magic) to the PET's sourceGUID, not the player - and a pet that dies and
-- resummons gets a NEW sourceGUID, so one end-of-run read would fragment a Warlock's kicks across
-- several pet rows and drop them (a pet isn't a group member). We sample every pet as it appears (on
-- UNIT_PET + at each stat read) and keep the mapping so finalize can fold each pet row into its owner.
local petOwners = {}
local PET_UNITS = { player = "pet", party1 = "partypet1", party2 = "partypet2",
                    party3 = "partypet3", party4 = "partypet4" }
local function samplePets()
    for ownerUnit, petUnit in pairs(PET_UNITS) do
        if UnitExists(petUnit) then
            local pg = ML.ReadStr(UnitGUID(petUnit))
            local og = ML.ReadStr(UnitGUID(ownerUnit))
            if pg and og then petOwners[pg] = og end
        end
    end
end

-- Live pet->owner GUID map for the active run, so a surface that builds its OWN provider ctx (the
-- death report) can fold pet rows into their owners exactly like the finalize path does.
function Tracker.PetOwners() return petOwners end

local function setState(s)
    if state ~= s then ML.Log("state %s -> %s", state, s) end
    state = s
end
function Tracker.GetState() return state end
function Tracker.Current() return current end

----------------------------------------------------------------------
-- Helpers.
----------------------------------------------------------------------

local function statBlock(src)
    local s = {}
    for _, k in ipairs(STAT_KEYS) do s[k] = src and src[k] or nil end
    return s
end

-- Merge captured roster identity with provider stat blocks into the saved party array. `attrib` is the
-- optional per-GUID attribution map (Providers.ReadAttribution) - per-spell breakdowns for the run log;
-- `recaps` is the optional per-GUID death-recap map (Providers.ReadDeathRecaps) - raw fatal-hit timelines.
local function mergePartyStats(roster, stats, capture, attrib, recaps)
    local byGuid, byName = {}, {}
    if stats then
        for _, e in ipairs(stats.party or {}) do
            if e.guid then byGuid[e.guid] = e end
            if e.fullName then byName[e.fullName] = e end
        end
    end
    local function hasData(s) return s and (s.damage or s.healing or s.dps or s.hps or s.damageTaken) end
    local out = {}
    for _, m in ipairs(roster or {}) do
        local matched = (m.guid and byGuid[m.guid]) or (m.fullName and byName[m.fullName])
        local src
        if m.isPlayer then
            -- Prefer the dedicated player block, but if it's empty (e.g. the provider couldn't
            -- resolve the player) fall back to the party-matched entry so we never blank the player.
            local pl = stats and stats.player
            src = (hasData(pl) and pl) or matched or pl
        else
            src = matched
        end
        out[#out + 1] = {
            guid = m.guid, name = m.name, realm = m.realm, fullName = m.fullName,
            classFile = m.classFile, classId = m.classId, role = m.role,
            -- Prefer the live roster spec; else whatever the provider resolved; else the live-INSPECTED
            -- spec (Inspect.lua captured it via GetInspectSpecialization). This is how a pug's real spec
            -- lands on the record when they don't broadcast it, so scoring runs on the actual spec.
            specId = m.specId or (src and src.specId)
                or (capture and m.guid and capture[m.guid] and capture[m.guid].specID),
            specIcon = src and src.specIcon,
            guildName = m.guildName, isPlayer = m.isPlayer and true or false,
            mplusScore = m.mplusScore,
            -- Equipped item level: live-captured for self; for teammates it comes from the run-start group
            -- inspect (capture map), so it fills in for pugs who don't broadcast it.
            itemLevel = m.itemLevel or (capture and m.guid and capture[m.guid] and capture[m.guid].itemLevel),
            -- Live talent-inspection verdict for this member's dispel: true = has it, false = confirmed
            -- NOT talented, nil = unknown. Gates the dispel scorer (see Scoring/Categories.Dispel).
            dispelTalent = capture and m.guid and capture[m.guid] and capture[m.guid].hasTool,
            -- Talent METADATA (not read by scoring yet) - captured for future class+spec+ilvl+hero-tree
            -- expectation modelling. heroTree = {id,name}; talents = purchased spell ids; talentCount.
            heroTree = m.heroTree or (capture and m.guid and capture[m.guid] and capture[m.guid].heroTree),
            talents = m.talents or (capture and m.guid and capture[m.guid] and capture[m.guid].talents),
            talentCount = m.talentCount or (capture and m.guid and capture[m.guid] and capture[m.guid].talentCount),
            stats = statBlock(src),
            -- Per-spell breakdown for the run log (what they dealt/healed/took/avoided/kicked/dispelled).
            -- nil when the meter source API isn't available (e.g. the abandoned/metadata path).
            attribution = attrib and m.guid and attrib[m.guid] or nil,
            -- Raw death-recap timelines (fatal-hit lists) for this member, for death classification and
            -- later inspection. nil for a clean run / when the recap wasn't captured.
            deathRecaps = recaps and m.guid and recaps[m.guid] or nil,
        }
    end
    return out
end

local function playerStatsOf(party)
    for _, m in ipairs(party or {}) do if m.isPlayer then return m.stats end end
    return nil
end

-- The provider context. Providers read ctx.player (the local player identity, for the "player"
-- stat block + per-boss DPS) and ctx.party (the roster). The run stores the player identity under
-- `character`, so we surface it as `player` here - otherwise ctx.player is nil and the local
-- player gets no stats and no per-boss DPS.
local function runCtx()
    if not current then return nil end
    samplePets()   -- catch any current pets right before a stat read (cheap; <=5 units)
    return { player = current.character, party = current.party, petOwners = petOwners }
end

local function sumDeaths(party)
    local total, any = 0, false
    for _, m in ipairs(party or {}) do
        local d = m.stats and m.stats.deaths
        if type(d) == "number" then total = total + d; any = true end
    end
    return any and total or nil
end

local function finalizeBosses()
    local list = {}
    for _, e in pairs(encounters or {}) do
        list[#list + 1] = {
            id = e.id, name = e.name, attempts = e.attempts or 0, wipes = e.wipes or 0,
            kills = e.kills or 0, killDuration = e.killDuration, totalTime = e.totalTime,
            order = e.order, deaths = e.deaths or 0, killDps = e.killDps, atSec = e.killedAt,
            topDps = e.topDps, topHps = e.topHps, lowAvoid = e.lowAvoid, deathList = e.deathList,
            perMember = e.perMember,
        }
    end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return list
end

-- Running total of party deaths so far this run. Diffing this across an encounter's start/end
-- attributes deaths to that boss (trash deaths between bosses are excluded). Primary source is
-- C_DamageMeter (the CLEU counters are restricted in Midnight); falls back to them on old clients.
local function partyDeathTotal()
    if not current then return 0 end
    -- Prefer the game's authoritative M+ death counter (reliable); the C_DamageMeter Deaths metric is
    -- unreliable in Midnight (it undercounts / reports 0), which is why a real death could show as 0.
    local cm = Providers.ChallengeModeDeaths and Providers.ChallengeModeDeaths()
    if type(cm) == "number" then return cm end
    local m = Providers.ReadPartyDeaths and Providers.ReadPartyDeaths(runCtx())
    if type(m) == "number" then return m end
    return 0   -- no combat-log fallback in Midnight; deaths come from ChallengeModeDeaths / C_DamageMeter above
end

local function persistRecovery()
    if not current then return end
    DB.SetActiveRun({
        runId     = current.id,
        mapId     = current.mapId,
        level     = current.level,
        startedAt = current.startedAt,
        seasonId  = current.seasonId,
        charGuid  = current.character and current.character.guid,
    })
end

local function cancelTimers()
    if finalizeTimer then finalizeTimer:Cancel(); finalizeTimer = nil end
    if rosterTimer then rosterTimer:Cancel(); rosterTimer = nil end
end

local function cleanup()
    cancelTimers()
    current, encounters, provider, retries, combatWaits = nil, nil, nil, 0, 0
end

----------------------------------------------------------------------
-- Begin a run.
----------------------------------------------------------------------
local function buildRun()
    local mapId = API.GetActiveMapID()
    if not mapId then return nil end   -- not a real challenge; refuse to create a run
    local ks = API.GetActiveKeystone() or {}
    local mapInfo = API.GetMapInfo(mapId) or {}
    local party = API.GroupMembers()
    return {
        id            = DB.NewRunId(),
        mapId         = mapId,
        challengeMapId = mapId,
        dungeonName   = mapInfo.name,
        timeLimit     = mapInfo.timeLimit,
        level         = ks.level,
        affixes       = ks.affixes or {},
        affixNames    = API.GetAffixNames(ks.affixes or {}),
        seasonId      = API.GetCurrentSeason(),
        expansionId   = API.GetExpansionLevel(),
        startedAt     = time(),
        character     = API.PlayerContext(),
        party         = party,
        provider      = nil,
        providerVersion = nil,
        bosses        = {},
        combat        = {},   -- { {startSec, stopSec}, ... } in-combat segments for the timeline
        notes         = "",
        tags          = {},
    }
end

-- Talent-inspect the group and record each member's dispel capability (guid -> hasTool bool/nil) on the
-- run, so the dispel scorer can gate expectations: a player we can't confirm has a TALENT-GATED dispel
-- is scored N/A, never docked. Best-effort + async; run start (everyone clustered at the door) is the
-- ideal window. Merges results across calls, preferring a known verdict over an earlier unknown.
local function captureDispels()
    if not (current and ML.Inspect and ML.Inspect.CaptureGroup) then return end
    ML.Inspect.CaptureGroup(function(map)
        if not (current and type(map) == "table") then return end
        local cur = current.dispelCapture or {}
        -- carry a good previous value forward when the new capture is missing it (a later inspect can
        -- read the dispel verdict but momentarily miss ilvl/hero/talents, or vice-versa).
        local CARRY = { "itemLevel", "heroTree", "talents", "talentCount" }
        for guid, v in pairs(map) do
            local prev = cur[guid]
            if v.hasTool ~= nil or prev == nil then
                if prev then
                    for _, f in ipairs(CARRY) do if prev[f] and not v[f] then v[f] = prev[f] end end
                end
                cur[guid] = v
            elseif prev then
                for _, f in ipairs(CARRY) do if v[f] and not prev[f] then prev[f] = v[f] end end
            end
        end
        current.dispelCapture = cur
    end)
end

function Tracker.BeginRun()
    if state == STATE.ACTIVE or state == STATE.COMPLETING then return end
    local run = buildRun()
    if not run then return end
    current = run
    runT0 = GetTime()
    runStartScore = API.MythicRating("player")
    encounters = {}
    petOwners = {}; samplePets()   -- fresh pet->owner map for this run; seed with whatever's out now
    provider = Providers.Select()
    run.provider = provider:GetSource()
    run.providerVersion = provider:GetVersion()    local ok = pcall(function() provider:BeginRun(run) end)
    if not ok then ML.Log("provider:BeginRun errored (continuing)") end
    setState(STATE.ACTIVE)
    persistRecovery()
    captureDispels()   -- talent-inspect the group now, while everyone's clustered at the start
    local pc = run.character
    ML.Log("Run started: %s +%s | provider=%s avail=%s | party=%d | player guid=%s",
        tostring(run.dungeonName), tostring(run.level), run.provider,
        tostring(provider.IsAvailable and provider:IsAvailable()), #(run.party or {}),
        (pc and pc.guid) and "yes" or "NO")
end

----------------------------------------------------------------------
-- Party + boss tracking during the run.
----------------------------------------------------------------------
local function refreshRoster()
    if state ~= STATE.ACTIVE or not current then return end
    current.party = API.GroupMembers()
end

function Tracker.OnRosterUpdate()
    if state ~= STATE.ACTIVE then return end
    -- Throttle: coalesce a burst of GROUP_ROSTER_UPDATE into one refresh.
    if rosterTimer then return end
    rosterTimer = C_Timer.NewTimer(1.0, function()
        rosterTimer = nil
        refreshRoster()
        captureDispels()   -- re-capture: picks up late joiners / anyone unknown (e.g. after a reload)
    end)
end

-- Diff each member's cumulative damage/heal/avoid/deaths across a fight window (baseMap -> endMap over
-- `dur` seconds) into the encounter's per-boss totals: top DPS/HPS, lowest avoidable, the player's kill
-- DPS, per-member DPS/HPS, and who died. Shared by the real kill path AND the dev dummy sim so both
-- exercise the identical maths. Mutates `e`.
local function computeBossCombat(e, baseMap, endMap, dur, party, playerGuid)
    if not (baseMap and endMap and dur and dur > 0) then return end
    local topName, topClass, topDps
    local hpsName, hpsClass, topHps
    local lowName, lowClass, lowAvoid
    e.deathList = e.deathList or {}
    e.perMember = {}   -- every member's DPS/HPS on this boss (for the "everyone" tooltip)
    for _, m in ipairs(party or {}) do
        local guid = m.guid
        if guid then
            local base, now = baseMap[guid] or {}, endMap[guid] or {}
            local dDelta = (now.deaths or 0) - (base.deaths or 0)   -- who died on this boss
            for _ = 1, dDelta do
                e.deathList[#e.deathList + 1] = { name = m.name, classFile = m.classFile, specId = m.specId, role = m.role }
            end
            local dmgDelta = (now.damage or 0) - (base.damage or 0)
            local healDelta = (now.heal or 0) - (base.heal or 0)
            -- CURRENT session reset between snapshots (combat dropped & restarted) -> end < start; the
            -- fight's contribution is then just the post-reset accumulated total.
            if dmgDelta < 0 then dmgDelta = now.damage or 0 end
            if healDelta < 0 then healDelta = now.heal or 0 end
            local dps = (dmgDelta > 0) and (dmgDelta / dur) or 0
            local hps = (healDelta > 0) and (healDelta / dur) or 0
            local avDelta = (now.avoid or 0) - (base.avoid or 0); if avDelta < 0 then avDelta = 0 end
            e.perMember[#e.perMember + 1] = { name = m.name, classFile = m.classFile, role = m.role, dps = dps, hps = hps }
            if dmgDelta > 0 then
                if not topDps or dps > topDps then topDps, topName, topClass = dps, m.name, m.classFile end
                if guid == playerGuid and (not e.killDps or dps > e.killDps) then e.killDps = dps end
            end
            if healDelta > 0 and (not topHps or hps > topHps) then topHps, hpsName, hpsClass = hps, m.name, m.classFile end
            if not lowAvoid or avDelta < lowAvoid then lowAvoid, lowName, lowClass = avDelta, m.name, m.classFile end
        end
    end
    table.sort(e.perMember, function(a, b2) return (a.dps or 0) > (b2.dps or 0) end)
    if topName then e.topDps = { name = topName, classFile = topClass, dps = topDps } end
    if hpsName then e.topHps = { name = hpsName, classFile = hpsClass, hps = topHps } end
    if lowName then e.lowAvoid = { name = lowName, classFile = lowClass, amount = lowAvoid } end
end

-- The meter's per-source numbers are SECRET (unreadable; arithmetic throws) once you're locked INTO
-- combat, and readable again when combat DROPS. But ENCOUNTER_START fires at the EDGE of the pull -
-- before the combat lock - so it's still readable there. The flow:
--   * ENCOUNTER_START -> read the starting cumulative (edge of combat, still readable) = this boss's BASE.
--                        Safety net: fall back to the last out-of-combat snapshot if that read is empty.
--   * ENCOUNTER_END   -> mark the boss pending (record its kill duration); do NOT read - locked in combat.
--   * combat DROPS     -> read the now-readable cumulative; diff base->now = the fight's contribution.
-- ENCOUNTER_START only fires for real bosses, so this is inherently boss-only (trash never triggers it).
local oocDamageMap = {}
local function readOverallMap()
    return (Providers.ReadPartyDamageMap and Providers.ReadPartyDamageMap(runCtx())) or {}
end
-- Called on every combat-END (meter readable): refresh the snapshot + finalise any boss awaiting calc.
local function settleBossesAtCombatEnd()
    local newMap = readOverallMap()
    oocDamageMap = newMap
    if not current then return end
    local pg = current.character and current.character.guid
    for _, e in pairs(encounters or {}) do
        if e._pendingCalc then
            e._pendingCalc = nil
            if e._baseMap and e._killDur and e._killDur > 0 then
                computeBossCombat(e, e._baseMap, newMap, e._killDur, current.party or {}, pg)
                ML.Log("boss totals @combat-end: %s | topDPS=%s (%s) topHPS=%s (%s) yourKillDPS=%s", tostring(e.name),
                    e.topDps and string.format("%.0f", e.topDps.dps) or "nil", tostring(e.topDps and e.topDps.name),
                    e.topHps and string.format("%.0f", e.topHps.hps) or "nil", tostring(e.topHps and e.topHps.name),
                    e.killDps and string.format("%.0f", e.killDps) or "nil")
            end
            e._baseMap = nil
        end
    end
end

function Tracker.OnEncounterStart(encId, name)
    if state ~= STATE.ACTIVE or not encId then return end
    local e = encounters[encId]
    if not e then
        e = { id = encId, name = name, attempts = 0, wipes = 0, kills = 0, totalTime = 0,
              deaths = 0, order = (Tracker._encSeq or 0) + 1 }
        Tracker._encSeq = e.order
        encounters[encId] = e
    end
    e._startedAt = GetTime()
    e._deathBase = partyDeathTotal()   -- baseline so we can attribute this attempt's deaths to the boss
    -- Snapshot the starting cumulative NOW: ENCOUNTER_START fires at the edge of the pull, before the
    -- combat lock, so the meter is still readable and this captures the pre-boss totals. If it comes back
    -- empty (already locked in), fall back to the last out-of-combat snapshot. End read = next combat drop.
    local snap = readOverallMap()
    e._baseMap = (next(snap) ~= nil and snap) or oocDamageMap or {}
    e._pendingCalc = nil
end

function Tracker.OnEncounterEnd(encId, name, success)
    if state ~= STATE.ACTIVE or not encId then return end
    local e = encounters[encId]
    if not e then
        e = { id = encId, name = name, attempts = 0, wipes = 0, kills = 0, totalTime = 0,
              deaths = 0, order = (Tracker._encSeq or 0) + 1 }
        Tracker._encSeq = e.order
        encounters[encId] = e
    end
    local dur = e._startedAt and (GetTime() - e._startedAt) or nil
    e.attempts = e.attempts + 1
    if dur then e.totalTime = (e.totalTime or 0) + dur end
    -- Attribute deaths that happened during this attempt (start->end delta) to the boss.
    local ddelta = partyDeathTotal() - (e._deathBase or partyDeathTotal())
    if ddelta > 0 then e.deaths = (e.deaths or 0) + ddelta end
    e._deathBase = nil
    -- ENCOUNTER_END success is 1/0 (0 is truthy in Lua) - test explicitly.
    if success == true or success == 1 then
        e.kills = e.kills + 1
        e.killedAt = GetTime() - (runT0 or GetTime())   -- seconds into the run, for the timeline
        if dur and (not e.killDuration or dur < e.killDuration) then e.killDuration = dur end
        -- Still IN COMBAT here -> the meter is Secret/unreadable. Defer the per-boss diff to the next
        -- combat-END (settleBossesAtCombatEnd), which reads base->now and fills topDPS/HPS/killDPS.
        e._killDur = dur
        e._pendingCalc = true
    else
        e.wipes = e.wipes + 1
    end
    e._startedAt = nil
end

-- DEV/TEST: reproduce boss-combat totals at a TARGET DUMMY, mirroring the real path. The meter is only
-- readable OUT of combat, so: call ONCE out of combat (baseline snapshot), hit the dummy, LEAVE combat,
-- call AGAIN out of combat (diff -> per-boss totals via the SAME computeBossCombat the kill path uses).
-- Solo is fine (party = just you). Wired to /mldev boss.
local devBoss
function Tracker.DevBossSim()
    if not (Providers and Providers.ReadPartyDamageMap and API and API.GroupMembers) then
        print("|cffff5555Boss sim:|r damage provider unavailable."); return
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        print("|cffe0a030Boss sim:|r you're IN COMBAT - the meter is unreadable in combat. Do this out of combat.")
        return
    end
    local party = API.GroupMembers() or {}
    local selfM
    for _, m in ipairs(party) do if m.isPlayer then selfM = m end end
    selfM = selfM or party[1]
    if not (selfM and selfM.guid) then print("|cffff5555Boss sim:|r no player found in roster."); return end
    local ctx = { player = selfM, party = party }
    local S = (ML.Util and ML.Util.shortNum) or tostring

    if not devBoss then   -- START (out of combat): baseline snapshot
        devBoss = { t = GetTime(), map = Providers.ReadPartyDamageMap(ctx) or {} }
        print("|cffa06cf0Boss sim STARTED|r - hit the dummy, then LEAVE combat and /mldev boss again.")
        return
    end

    -- FINISH (out of combat): diff the window through the real per-boss maths.
    local d = devBoss; devBoss = nil
    local dur = GetTime() - d.t
    local endMap = Providers.ReadPartyDamageMap(ctx) or {}
    local e = { name = "Target Dummy" }
    computeBossCombat(e, d.map, endMap, dur, ctx.party, selfM.guid)

    print(string.format("|cffa06cf0Boss sim RESULT|r  window=%.1fs", dur))
    local b, n = d.map[selfM.guid] or {}, endMap[selfM.guid] or {}
    local raw = (n.damage or 0) - (b.damage or 0); if raw < 0 then raw = n.damage or 0 end
    print(string.format("  you (%s): %s damage = %s DPS", tostring(selfM.name), S(raw), S(dur > 0 and raw / dur or 0)))
    if e.perMember and #e.perMember > 0 then
        for _, pm in ipairs(e.perMember) do print(string.format("  %s  DPS %s / HPS %s", tostring(pm.name), S(pm.dps), S(pm.hps))) end
    elseif raw <= 0 then
        print("  |cffe0a030no damage recorded|r - did you start it BEFORE hitting, and finish OUT of combat?")
    end
    if e.topDps then print(string.format("  topDPS = %s (%s)   yourKillDPS = %s", S(e.topDps.dps), tostring(e.topDps.name), S(e.killDps or 0))) end
end

-- Combat vs downtime segments for the run timeline. Toggled by PLAYER_REGEN_DISABLED / _ENABLED.
-- Each closed segment is { startSec, stopSec } relative to the run start.
function Tracker.OnCombatChange(inCombat)
    if state ~= STATE.ACTIVE or not current then return end
    local t = GetTime() - (runT0 or GetTime())
    if inCombat then
        current._combatOpen = t
    else
        -- Combat dropped: the meter is READABLE now. Refresh the out-of-combat cumulative snapshot and
        -- finalise any boss that ended during this combat - this is where per-boss totals get computed.
        settleBossesAtCombatEnd()
        if current._combatOpen then
            current.combat = current.combat or {}
            current.combat[#current.combat + 1] = { current._combatOpen, t }
            current._combatOpen = nil
        end
    end
end

----------------------------------------------------------------------
-- Completion: wait (bounded) for provider data to finalize, then save once.
----------------------------------------------------------------------
local function finalizeRun(stats)
    local run = current
    if not run then return end
    -- Close any still-open combat segment (the key usually completes right after a fight).
    if run._combatOpen then
        run.combat = run.combat or {}
        run.combat[#run.combat + 1] = { run._combatOpen, (GetTime() - (runT0 or GetTime())) }
        run._combatOpen = nil
    end

    local comp = API.GetCompletion()
    run.completedAt = time()
    if comp then
        run.level          = comp.level or run.level
        run.mapId          = comp.mapId or run.mapId
        run.challengeMapId = run.mapId
        run.duration       = comp.durationSec or run.duration
        run.onTime         = comp.onTime
        run.keystoneUpgrade = comp.upgradeLevels
    end
    if not run.duration and run.startedAt then run.duration = run.completedAt - run.startedAt end
    if not run.timeLimit then
        local mi = API.GetMapInfo(run.mapId); run.timeLimit = mi and mi.timeLimit
    end
    if run.timeLimit and run.duration then
        run.timeRemaining = run.timeLimit - run.duration   -- positive = under the timer
    end
    if run.onTime ~= nil then
        run.status = run.onTime and STATUS.TIMED or STATUS.DEPLETED
    elseif run.timeRemaining ~= nil then
        run.status = (run.timeRemaining >= 0) and STATUS.TIMED or STATUS.DEPLETED
    else
        run.status = STATUS.DEPLETED
    end

    -- Capture ALL per-spell meter detail (per party GUID) from C_DamageMeter's source accessors before we
    -- build the records - out of combat here, so source GUIDs read as plain strings. `attrib` = per-metric
    -- breakdowns; `recaps` = raw death-recap fatal-hit timelines. Both stored raw in the run log so no run
    -- ever has to be re-played for a missing piece; both nil-safe (nil on the abandoned/metadata path).
    local attrib = Providers.ReadAttribution and Providers.ReadAttribution(runCtx())
    local recaps = Providers.ReadDeathRecaps and Providers.ReadDeathRecaps(runCtx())
    run.party           = mergePartyStats(run.party, stats, run.dispelCapture, attrib, recaps)
    -- Clean-run deaths: the meter records no death rows for someone who didn't die, so their count comes
    -- back nil. For a player the meter actually TRACKED (real combat numbers), that means ZERO deaths,
    -- not "no data" - store 0 so scoring reads "no deaths" (a confident zero) everywhere instead of "no
    -- death data recorded". Untracked members (no combat stats) stay nil = genuinely unknown.
    for _, m in ipairs(run.party or {}) do
        local s = m.stats
        if s and s.deaths == nil and (type(s.dps) == "number" or type(s.damage) == "number"
            or type(s.hps) == "number" or type(s.healing) == "number") then
            s.deaths = 0
        end
    end
    -- Classify each member's deaths (avoidable / threat / missed-kick / other) from their captured
    -- attribution + death recaps now that the death counts are normalised. `kickSet` = this dungeon's
    -- interruptible casts (season catalog), so a death to a cast that should have been kicked is named.
    if Providers.ClassifyDeaths then
        local kickSet
        local Cfg = ML.Scoring and ML.Scoring.Config
        local cat = Cfg and Cfg.SeasonDungeon and Cfg.SeasonDungeon(run.dungeonName)
        if cat and type(cat.kicks) == "table" then
            kickSet = {}
            for _, e in ipairs(cat.kicks) do if e.id then kickSet[e.id] = true end end
        end
        for _, m in ipairs(run.party or {}) do
            local n = m.stats and m.stats.deaths
            if type(n) == "number" and n > 0 then
                m.deathCauses = Providers.ClassifyDeaths(m.attribution, m.deathRecaps, m.role, n, kickSet)
            end
        end
    end
    if attrib then
        local nAttr, nRec = 0, 0
        for _ in pairs(attrib) do nAttr = nAttr + 1 end
        if recaps then for _, list in pairs(recaps) do nRec = nRec + #list end end
        ML.Log("attribution: per-spell detail for %d player(s); death recaps captured: %d", nAttr, nRec)
    end
    run.provider        = (stats and stats.source) or run.provider
    run.providerVersion = (stats and stats.sourceVersion) or run.providerVersion
    run.playerStats     = playerStatsOf(run.party)   -- reflects the normalised 0s
    -- Prefer the game's authoritative M+ death total (reliable); fall back to the meter sum.
    run.deaths          = (Providers.ChallengeModeDeaths and Providers.ChallengeModeDeaths()) or sumDeaths(run.party)
    -- The LAST boss's kill completes the key, which flips state out of ACTIVE before combat drops - so
    -- its combat-end settle is skipped and it would finalize with no per-boss totals. Finalization runs
    -- ~1.5s later (out of combat, meter readable), so settle any still-pending boss here before we bake
    -- the boss list.
    settleBossesAtCombatEnd()
    run.bosses          = finalizeBosses()
    run.confidence      = "full"

    -- M+ score: re-read each member's score now that the run has scored, and set the player's gain.
    local scoreByGuid = {}
    for _, mm in ipairs(API.GroupMembers()) do
        if mm.guid and mm.mplusScore then scoreByGuid[mm.guid] = mm.mplusScore end
    end
    for _, mem in ipairs(run.party) do
        if mem.guid and scoreByGuid[mem.guid] then mem.mplusScore = scoreByGuid[mem.guid] end
    end
    local pc = run.character
    if pc then
        pc.mplusScore = (pc.guid and scoreByGuid[pc.guid]) or pc.mplusScore or API.MythicRating("player")
        if pc.mplusScore and runStartScore then run.scoreGain = pc.mplusScore - runStartScore end
    end

    -- Prime the Scoring Store so the compact per-run summary is persisted (the Store owns scoring
    -- persistence + retroactive rescore on a version bump; we don't store scores on the raw run).
    if ML.Scoring and ML.Scoring.Store and ML.Scoring.Store.Full then
        pcall(ML.Scoring.Store.Full, run)
    end

    -- Diagnostics (visible with debug on): the player's captured DPS and the run's total party deaths.
    local ps = run.playerStats
    ML.Log("finalize: provider=%s playerDPS=%s dmg=%s int=%s dsp=%s | runDeaths=%s",
        tostring(run.provider), tostring(ps and ps.dps), tostring(ps and ps.damage),
        tostring(ps and ps.interrupts), tostring(ps and ps.dispels), tostring(run.deaths))

    setState(STATE.COMPLETED)
    local inserted = DB.AddRun(run)   -- de-duplicates + runs History.OnRunSaved internally
    -- Saving flips this party to "returning"; mark them seen so a post-run roster update can't re-toast
    -- the whole group as if you'd just met them (see Recap.MarkGroupSeen).
    if ML.Recap and ML.Recap.MarkGroupSeen then pcall(ML.Recap.MarkGroupSeen, run.party) end
    if inserted then
        if DB.Settings().postRunSummary and ML.UI and ML.UI.QueuePostRun then
            pcall(ML.UI.QueuePostRun, run)
        end
        ML.Print("Saved %s +%d (%s).", tostring(run.dungeonName), tonumber(run.level) or 0,
            run.status == STATUS.TIMED and "timed" or "depleted")
    end
    DB.ClearActiveRun()
    cleanup()
    setState(STATE.IDLE)
end

-- Cap on how long we'll wait for combat to drop before finalizing anyway (seconds, 1s/poll). Generous:
-- a trash mop-up to reach 100% forces after the last boss can run a while, but must not wedge the save.
local MAX_COMBAT_WAITS = 60

local function stillInCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) or false
end

local function tryFinalize()
    -- The Midnight meter only reads reliably OUT of combat - in-combat sources come back Secret-wrapped,
    -- so a read here returns empty (or the local player only), which is exactly the "no metrics" bug when
    -- a key COMPLETES MID-TRASH (the last boss didn't finish the forces, so we're still fighting when
    -- CHALLENGE_MODE_COMPLETED fires). Defer the read until combat actually drops, bounded so a stuck
    -- combat flag can't wedge the save forever. The normal case (key completes right after a boss) just
    -- passes straight through once combat clears.
    if stillInCombat() and provider and provider:GetSource() ~= ML.SOURCE.NONE
        and combatWaits < MAX_COMBAT_WAITS then
        combatWaits = combatWaits + 1
        if combatWaits == 1 or combatWaits % 5 == 0 then
            ML.Log("finalize deferred: still in combat (%ds)", combatWaits)
        end
        finalizeTimer = C_Timer.NewTimer(1.0, tryFinalize)
        return
    end

    retries = retries + 1
    local ctx = runCtx()
    local stats
    if provider then stats = provider:GetRunStats(ctx) end
    -- Retry a few times while a real meter is expected but not ready yet (settling after combat drops).
    if not stats and provider and provider:GetSource() ~= ML.SOURCE.NONE and retries < 4 then
        ML.Log("provider data not ready (try %d); retrying", retries)
        finalizeTimer = C_Timer.NewTimer(1.0, tryFinalize)
        return
    end
    if not stats then stats = Providers.Metadata:GetRunStats(ctx) end  -- guaranteed non-nil
    finalizeRun(stats)
end

function Tracker.CompleteRun()
    if not current then
        -- Completion event with no tracked run (e.g. joined mid-key): capture a metadata record.
        if API.GetActiveMapID() or API.GetCompletion() then
            current = buildRun() or {}
            if not current.id then current.id = DB.NewRunId() end
            encounters = encounters or {}
        else
            return
        end
    end
    if state == STATE.COMPLETING or state == STATE.COMPLETED then return end
    setState(STATE.COMPLETING)
    retries, combatWaits = 0, 0
    -- Brief settle delay so Details!/Blizzard finalize the overall segment before we read it (and, if the
    -- key completed mid-trash, tryFinalize then waits for combat to actually drop before reading).
    finalizeTimer = C_Timer.NewTimer(1.5, tryFinalize)
end

----------------------------------------------------------------------
-- Abandonment.
----------------------------------------------------------------------
function Tracker.AbandonRun(reason)
    if not current then return end
    if not DB.Settings().trackAbandoned then
        ML.Log("Abandoned run discarded (tracking off): %s", tostring(reason))
        DB.ClearActiveRun(); cleanup(); setState(STATE.IDLE)
        return
    end
    local run = current    run.completedAt = time()
    run.duration    = run.completedAt - (run.startedAt or run.completedAt)
    run.status      = STATUS.ABANDONED
    run.confidence  = "partial"
    local stats = Providers.Metadata:GetRunStats(run)
    run.party       = mergePartyStats(run.party, stats, run.dispelCapture)
    run.playerStats = playerStatsOf(run.party)
    run.deaths      = sumDeaths(run.party)
    run.bosses      = finalizeBosses()
    setState(STATE.ABANDONED)
    DB.AddRun(run)   -- de-duplicates + runs History.OnRunSaved internally
    if ML.Recap and ML.Recap.MarkGroupSeen then pcall(ML.Recap.MarkGroupSeen, run.party) end
    DB.ClearActiveRun(); cleanup(); setState(STATE.IDLE)
    ML.Log("Abandoned run saved: %s +%s", tostring(run.dungeonName), tostring(run.level))
end

----------------------------------------------------------------------
-- Reload / disconnect recovery.
----------------------------------------------------------------------
-- Rebuild a minimal working run from a recovery record + live API (pre-reload metrics are lost).
local function restoreFromRecord(rec)
    local run = buildRun() or {}
    run.id        = rec.runId or run.id or DB.NewRunId()
    run.startedAt = rec.startedAt or run.startedAt
    run.seasonId  = rec.seasonId or run.seasonId
    current = run
    encounters = {}
    petOwners = {}; samplePets()   -- pre-reload pet history is lost; seed from whatever's out now
    provider = Providers.Select()
    run.provider = provider:GetSource()    setState(STATE.ACTIVE)
    persistRecovery()
    ML.Log("Recovered in-progress run: %s +%s", tostring(run.dungeonName), tostring(run.level))
end

function Tracker.OnEnteringWorld()
    local rec = DB.ActiveRun()
    local activeMap = API.GetActiveMapID()
    if activeMap then
        if rec and rec.mapId == activeMap then
            if not current then restoreFromRecord(rec) end
        elseif not current then
            -- In a challenge with no recovery record (started before the module was ready).
            Tracker.BeginRun()
        end
        return
    end
    -- No active challenge. If we had one pending, decide its fate.
    if rec then
        local comp = API.GetCompletion()
        if comp and comp.mapId == rec.mapId then
            restoreFromRecord(rec)
            finalizeRun(Providers.Metadata:GetRunStats(runCtx()))
        else
            Tracker.OfferAbandonRecovery(rec)
        end
    end
end

-- Offer to save an unrecoverable in-progress run as abandoned, or discard it.
function Tracker.OfferAbandonRecovery(rec)
    local theme = _G.TAP and _G.TAP.uiTheme
    local function saveIt()
        restoreFromRecord(rec)
        Tracker.AbandonRun("recovery")
    end
    local function discard()
        DB.ClearActiveRun()
        ML.Log("Discarded unrecoverable run record")
    end
    if not DB.Settings().trackAbandoned then discard(); return end
    if DB.Settings().confirmAbandonSave and theme and theme.Confirm then
        theme:Confirm({
            title = "Unfinished Mythic+ run",
            message = "A Mythic+ run was in progress last session but is no longer active. Save it as "
                .. "an abandoned run, or discard it?",
            variant = "warning", confirmLabel = "Save as abandoned", cancelLabel = "Discard",
            onConfirm = saveIt, onCancel = discard,
        })
    else
        saveIt()
    end
end

----------------------------------------------------------------------
-- Event driver (registered by the module's OnEnable; torn down by OnDisable).
----------------------------------------------------------------------
local EVENTS = {
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "ENCOUNTER_START", "ENCOUNTER_END",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PET",
}

local function onEvent(_, event, a1, a2, a3, a4, a5)
    if event == "PLAYER_REGEN_DISABLED" then
        Tracker.OnCombatChange(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Tracker.OnCombatChange(false)
    elseif event == "UNIT_PET" then
        -- A group member's pet changed (summon / dismiss / death-resummon). Record the new pet's GUID
        -- so its meter interrupts can be folded back to the owner, even after the pet later dies.
        if state == STATE.ACTIVE then samplePets() end
    elseif event == "CHALLENGE_MODE_START" then
        Tracker.BeginRun()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        Tracker.CompleteRun()
    elseif event == "CHALLENGE_MODE_RESET" then
        Tracker.AbandonRun("reset")
    elseif event == "GROUP_ROSTER_UPDATE" then
        Tracker.OnRosterUpdate()
    elseif event == "ENCOUNTER_START" then
        Tracker.OnEncounterStart(a1, a2)          -- encounterID, encounterName, difficultyID, groupSize
    elseif event == "ENCOUNTER_END" then
        -- args: encounterID, encounterName, difficultyID, groupSize, success (1 = kill, 0 = wipe).
        Tracker.OnEncounterEnd(a1, a2, a5)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Defer a moment so challenge/keystone APIs are populated after a zone-in/reload.
        C_Timer.After(2, function() pcall(Tracker.OnEnteringWorld) end)
    end
end

function Tracker.Start()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
    end
    for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
    -- Catch a run already in progress when the module is enabled mid-session.
    C_Timer.After(1, function()
        if state == STATE.IDLE and API.GetActiveMapID() then pcall(Tracker.OnEnteringWorld) end
    end)
    ML.Log("Tracker started")
end

function Tracker.Stop()
    if frame then frame:UnregisterAllEvents() end
    cancelTimers()    -- Keep `current`/recovery record intact so a re-enable (or reload) can still finalize it.
    ML.Log("Tracker stopped")
end
