-- TAP: Mythic Ledger - Diag.lua
-- API self-check. Probes every Blizzard/Details entry point the module relies on and reports
-- present/missing plus live values, so the whole stat pipeline can be validated WITHOUT running a
-- full key: hit a target dummy for a few seconds, then run it - the Blizzard meter's current-fight
-- data (and Details') shows up here. Surfaced via `/tap ledger apicheck` and the Debug page.

local ADDON, ML = ...
local API  = ML.API
local Util = ML.Util

local Diag = {}
ML.Diag = Diag

local OK   = "|cff33ff33OK|r"
local MISS = "|cffff5555MISSING|r"
local NA   = "|cff888888n/a|r"

local function has(ns, fn) return type(ns) == "table" and type(ns[fn]) == "function" end

function Diag.Run(emit)
    local out = {}
    local function line(s) out[#out + 1] = s; if emit then emit(s) end end
    local function fnrow(ns, nsname, fn)
        line(string.format("  [%s] %s.%s", has(ns, fn) and OK or MISS, nsname, fn))
    end

    line("== Mythic Ledger API self-check ==")

    -- Challenge mode --------------------------------------------------
    local CM = _G.C_ChallengeMode
    line("C_ChallengeMode: " .. (type(CM) == "table" and OK or MISS))
    for _, fn in ipairs({ "GetActiveChallengeMapID", "GetActiveKeystoneInfo", "GetMapUIInfo",
        "GetChallengeCompletionInfo", "GetCompletionInfo", "GetAffixInfo", "GetMapTable" }) do
        fnrow(CM, "C_ChallengeMode", fn)
    end
    line(string.format("  current season = %s", tostring(API.GetCurrentSeason())))
    local pool = API.GetSeasonMapPool()
    line(string.format("  season dungeon pool = %d map(s)", #pool))
    if pool[1] then
        local mi = API.GetMapInfo(pool[1])
        line(string.format("  first dungeon = %s (timer %s)", mi and mi.name or "?",
            mi and Util.duration(mi.timeLimit) or "?"))
    end
    local activeMap = API.GetActiveMapID()
    line(string.format("  active challenge map = %s%s", tostring(activeMap),
        activeMap and "" or "  (nil expected unless you're in a key)"))
    local ks = API.GetActiveKeystone()
    line(string.format("  active keystone = %s", (ks and ks.level) and ("+" .. ks.level)
        or "none  (expected outside a key)"))

    -- Mythic Plus -----------------------------------------------------
    line("C_MythicPlus: " .. (type(_G.C_MythicPlus) == "table" and OK or MISS))
    fnrow(_G.C_MythicPlus, "C_MythicPlus", "GetCurrentSeason")
    fnrow(_G.C_MythicPlus, "C_MythicPlus", "RequestMapInfo")

    -- Blizzard damage meter (WORKS ON A TARGET DUMMY) -----------------
    local DM = _G.C_DamageMeter
    line("C_DamageMeter (Blizzard provider): " .. (type(DM) == "table" and OK or MISS))
    for _, fn in ipairs({ "IsDamageMeterAvailable", "GetCombatSessionFromType", "GetAvailableCombatSessions" }) do
        fnrow(DM, "C_DamageMeter", fn)
    end
    local availOk = has(DM, "IsDamageMeterAvailable") and select(2, pcall(DM.IsDamageMeterAvailable))
    line(string.format("  IsDamageMeterAvailable() = %s", tostring(availOk)))
    local ST = _G.Enum and _G.Enum.DamageMeterSessionType
    local MT = _G.Enum and _G.Enum.DamageMeterType
    line(string.format("  Enum.DamageMeterSessionType = %s   Enum.DamageMeterType = %s",
        ST and OK or MISS, MT and OK or MISS))
    if has(DM, "GetCombatSessionFromType") and ST and MT then
        for _, st in ipairs({ { "Current", ST.Current }, { "Overall", ST.Overall } }) do
            local ok, session = pcall(DM.GetCombatSessionFromType, st[2], MT.DamageDone)
            if ok and type(session) == "table" and type(session.combatSources) == "table" then
                line(string.format("  %s/DamageDone -> %d source(s), duration %s", st[1],
                    #session.combatSources, Util.duration(ML.ReadNum(session.durationSeconds))))
                local top = session.combatSources[1]
                if top then
                    line(string.format("    top source: %s  dmg=%s dps=%s  guid=%s", tostring(top.name),
                        Util.shortNum(ML.ReadNum(top.totalAmount)), Util.shortNum(ML.ReadNum(top.amountPerSecond)),
                        tostring(top.sourceGUID)))
                end
            else
                line(string.format("  %s/DamageDone -> no data (hit a dummy for a few seconds, then re-run)", st[1]))
            end
        end
    end

    -- Boss icons / Encounter Journal ----------------------------------
    if API.EJDiag then
        local ej = API.EJDiag()
        line(string.format("Encounter Journal: loaded=%s funcs=%s tiers=%s",
            tostring(ej.ejLoaded), tostring(ej.ejFuncs), tostring(ej.numTiers)))
        line(string.format("  icon cache: ready=%s tries=%d  byId=%d byName=%d bg=%d",
            tostring(ej.ready), ej.tries, ej.byId, ej.byName, ej.bg))
        local sampleRun, sampleBoss
        for _, r in ipairs((ML.DB and ML.DB.Runs and ML.DB.Runs()) or {}) do
            if r.bosses and r.bosses[1] then sampleRun, sampleBoss = r, r.bosses[1]; break end
        end
        if sampleBoss then
            line(string.format("  sample boss: name=%q id=%s -> icon=%s   dungeon=%q -> bg=%s",
                tostring(sampleBoss.name), tostring(sampleBoss.id),
                tostring(API.BossIcon(sampleBoss.name, sampleBoss.id)),
                tostring(sampleRun.dungeonName), tostring(API.DungeonBackground(sampleRun.dungeonName))))
        else
            line("  (no stored run with boss splits to sample)")
        end
    end

    -- Selected provider + roster --------------------------------------
    local prov = ML.Providers.Select()
    line(string.format("Active provider = %s", prov:GetName()))
    local me = API.PlayerContext()
    line(string.format("You: %s  spec=%s  role=%s  guid=%s", tostring(me.fullName), tostring(me.specId),
        tostring(me.role), tostring(me.guid)))
    line(string.format("Readable group members: %d", #API.GroupMembers()))

    return table.concat(out, "\n")
end

-- Run the SELECTED provider against the current fight and print the normalized stat block it would
-- save. Great on a target dummy with Details! (its "overall" holds the dummy fight); the Blizzard
-- provider reads the Overall session, which may be empty until a real run completes.
function Diag.ProbeCapture(emit)
    local function line(s) if emit then emit(s) else print(ML.PREFIX .. s) end end
    local ctx = { player = API.PlayerContext(), party = API.GroupMembers() }
    local prov = ML.Providers.Select()
    line(string.format("Probing %s against current combat...", prov:GetName()))
    local stats = prov:GetRunStats(ctx)
    if not stats then line("  no data (provider's overall session is empty outside a run)"); return end
    local function show(who, s)
        line(string.format("  %s: dmg=%s dps=%s heal=%s hps=%s int=%s dsp=%s deaths=%s", who,
            Util.shortNum(s.damage), Util.shortNum(s.dps), Util.shortNum(s.healing), Util.shortNum(s.hps),
            Util.numOr(s.interrupts, "%d"), Util.numOr(s.dispels, "%d"), Util.numOr(s.deaths, "%d")))
    end
    show("you", stats.player)
    for _, m in ipairs(stats.party or {}) do if not m.isPlayer then show(m.name or "?", m) end end
end

-- Recursively render a value's shape for API discovery. Depth- and width-capped so it can be pointed
-- at an unknown Blizzard struct without flooding chat, and every access is pcall-guarded so a Secret-
-- wrapped or protected field never errors. Midnight Secret scalars are unwrapped for display where we
-- can (ML.ReadStr/ReadNum); if a value stays opaque it's shown as its raw type, which is itself the
-- answer we're looking for ("the per-spell detail is here but Secret-locked" vs "not handed to us").
local function dumpValue(line, label, val, depth, indent)
    indent = indent or "  "
    local t = type(val)
    if t ~= "table" then
        local shown = val
        if t ~= "string" and t ~= "number" and t ~= "boolean" then
            shown = (ML.ReadStr and ML.ReadStr(val)) or (ML.ReadNum and ML.ReadNum(val))
            if shown == nil then shown = "<opaque/Secret>" end
        end
        line(string.format("%s%s = (%s) %s", indent, tostring(label), t, tostring(shown)))
        return
    end
    line(string.format("%s%s = {", indent, tostring(label)))
    if depth <= 0 then line(indent .. "  ...(depth cap)"); return end
    local n = 0
    local okIter = pcall(function()
        for k, v in pairs(val) do
            n = n + 1
            if n > 40 then line(indent .. "  ...(more fields)"); break end
            dumpValue(line, k, v, depth - 1, indent .. "  ")
        end
    end)
    if not okIter then line(indent .. "  <could not iterate>") end
end

-- ProbeMeterDetail: the gating experiment for per-event attribution. Clicking a meter row in-game
-- shows a full per-spell breakdown (what you took avoidable damage from, what killed you, what you
-- kicked/dispelled) - but that's rendered inside Blizzard's meter UI. This dumps, for the LOCAL
-- player, the ENTIRE row struct the API hands us for each of those metrics, plus every function the
-- C_DamageMeter namespace exposes and every DamageMeterType. If a per-spell detail table (or a
-- detail-accessor function) exists on the addon side, it shows here; if the rows are just totals,
-- the breakdown lives only in the protected UI and attribution isn't reachable without it. The detail
-- only populates OUT of combat (per live observation), so run it after a fight, not during.
function Diag.ProbeMeterDetail(emit)
    local out = {}
    local function line(s) out[#out + 1] = s; if emit then emit(s) else print(ML.PREFIX .. s) end end

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        line("|cffe0a030NOTE:|r you're in combat - the per-row detail only populates OUT of combat. Leave combat and re-run.")
    end

    local dm = _G.C_DamageMeter
    if type(dm) ~= "table" then line("C_DamageMeter " .. MISS); return table.concat(out, "\n") end

    -- (1) Every function the namespace exposes. A GetCombatSession*Detail / *SpellData / *Breakdown
    -- accessor - the thing that would feed the drill-down - would appear here if it's public.
    line("== C_DamageMeter functions ==")
    local fns = {}
    pcall(function() for k, v in pairs(dm) do if type(v) == "function" then fns[#fns + 1] = k end end end)
    table.sort(fns)
    for _, k in ipairs(fns) do line("  " .. k) end

    -- (2) Every metric the client knows about (so we're not blind to a detail-only metric type).
    local ST = _G.Enum and _G.Enum.DamageMeterSessionType
    local MT = _G.Enum and _G.Enum.DamageMeterType
    line("== Enum.DamageMeterType ==")
    if type(MT) == "table" then
        local mts = {}
        pcall(function() for k, v in pairs(MT) do mts[#mts + 1] = string.format("%s=%s", tostring(k), tostring(v)) end end)
        table.sort(mts)
        line("  " .. table.concat(mts, "  "))
    else
        line("  " .. MISS)
    end

    -- (3) The whole local-player row for each attribution metric, both sessions, structure and all.
    if type(dm.GetCombatSessionFromType) == "function" and type(ST) == "table" and type(MT) == "table" then
        local metrics = {
            { "AvoidableDamageTaken", MT.AvoidableDamageTaken },
            { "DamageTaken",          MT.DamageTaken },
            { "Deaths",               MT.Deaths },
            { "Interrupts",           MT.Interrupts },
            { "Dispels",              MT.Dispels },
        }
        for _, sess in ipairs({ { "Overall", ST.Overall }, { "Current", ST.Current } }) do
            for _, m in ipairs(metrics) do
                if m[2] ~= nil and sess[2] ~= nil then
                    local ok, session = pcall(dm.GetCombatSessionFromType, sess[2], m[2])
                    if ok and type(session) == "table" and type(session.combatSources) == "table" then
                        local rows = session.combatSources
                        local pick = rows[1]
                        for _, src in ipairs(rows) do if src.isLocalPlayer then pick = src; break end end
                        line(string.format("== %s / %s -> %d row(s) ==", sess[1], m[1], #rows))
                        if pick then dumpValue(line, "yourRow", pick, 4, "  ") else line("  (no rows)") end
                    end
                end
            end
        end
    end

    return table.concat(out, "\n")
end

-- ProbeMeterSource: follow-up to ProbeMeterDetail. The top-level rows are per-source TOTALS only; the
-- per-spell breakdown you see in the drill-down must come from the two accessors we never call -
-- GetCombatSessionSourceFromType / GetCombatSessionSourceFromID - and, for deaths, from the row's
-- deathRecapID handle. We don't know their signatures, so this tries the plausible argument shapes
-- (2-arg local-player, 3-arg by-GUID, 3-arg by-index, by-session-ID) and deep-dumps whatever comes
-- back. Every call is pcall-guarded and dumped 6 levels deep so a nested spell list is captured. Run
-- OUT of combat, right after a run while the Overall session still holds it.
function Diag.ProbeMeterSource(emit)
    local out = {}
    local function line(s) out[#out + 1] = s; if emit then emit(s) else print(ML.PREFIX .. s) end end

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        line("|cffe0a030NOTE:|r run OUT of combat, right after a key (the Overall session must still hold the run).")
    end

    local dm = _G.C_DamageMeter
    if type(dm) ~= "table" then line("C_DamageMeter " .. MISS); return table.concat(out, "\n") end
    local ST = _G.Enum and _G.Enum.DamageMeterSessionType
    local MT = _G.Enum and _G.Enum.DamageMeterType
    if type(ST) ~= "table" or type(MT) ~= "table" then line("Enum " .. MISS); return table.concat(out, "\n") end
    local sess = ST.Overall or 0
    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    line(string.format("your GUID = %s", tostring(myGUID)))

    -- Try a call, label it, and deep-dump any table result (or report nil / the error).
    local function try(label, fn, ...)
        if type(fn) ~= "function" then line("  " .. label .. " -> (no such function)"); return end
        local packed = { pcall(fn, ...) }
        local ok = packed[1]
        if not ok then line(string.format("  %s -> ERROR: %s", label, tostring(packed[2]))); return end
        local nret = #packed - 1
        if nret == 0 or packed[2] == nil then line("  " .. label .. " -> nil"); return end
        line(string.format("  %s -> (%d return value%s)", label, nret, nret == 1 and "" or "s"))
        for i = 2, #packed do dumpValue(line, "ret" .. (i - 1), packed[i], 6, "    ") end
    end

    -- (0) What sessions exist, and their IDs (needed for the *FromID accessors).
    line("== GetAvailableCombatSessions() ==")
    try("GetAvailableCombatSessions()", dm.GetAvailableCombatSessions)

    -- (1) The Source-from-Type accessor, across argument shapes, for the metrics whose breakdown we want.
    local metrics = {
        { "AvoidableDamageTaken", MT.AvoidableDamageTaken },
        { "Interrupts",           MT.Interrupts },
        { "Dispels",              MT.Dispels },
        { "DamageTaken",          MT.DamageTaken },
    }
    for _, m in ipairs(metrics) do
        line(string.format("== GetCombatSessionSourceFromType / %s ==", m[1]))
        try("(Overall, type)",           dm.GetCombatSessionSourceFromType, sess, m[2])
        try("(Overall, type, myGUID)",   dm.GetCombatSessionSourceFromType, sess, m[2], myGUID)
        try("(Overall, type, index=1)",  dm.GetCombatSessionSourceFromType, sess, m[2], 1)
    end

    -- (2) Deaths: resolve the deathRecapID handle off the death row, then try to expand it every way.
    line("== Deaths: resolve deathRecapID ==")
    local okD, deaths = pcall(dm.GetCombatSessionFromType, sess, MT.Deaths)
    if okD and type(deaths) == "table" and type(deaths.combatSources) == "table" then
        local row = deaths.combatSources[1]
        for _, r in ipairs(deaths.combatSources) do if r.isLocalPlayer then row = r; break end end
        if row then
            local rid, rguid = row.deathRecapID, row.sourceGUID
            line(string.format("  using deathRecapID=%s sourceGUID=%s (%s)", tostring(rid), tostring(rguid), tostring(row.name)))
            try("SourceFromType(Overall, Deaths, myGUID)",  dm.GetCombatSessionSourceFromType, sess, MT.Deaths, myGUID)
            try("SourceFromType(Overall, Deaths, rguid)",   dm.GetCombatSessionSourceFromType, sess, MT.Deaths, rguid)
            try("SourceFromID(deathRecapID)",               dm.GetCombatSessionSourceFromID, rid)
            try("SourceFromID(deathRecapID, rguid)",        dm.GetCombatSessionSourceFromID, rid, rguid)
            try("SessionFromID(deathRecapID)",              dm.GetCombatSessionFromID, rid)
        else
            line("  (no death rows in the Overall session - re-run after a key where someone died)")
        end
    else
        line("  (Deaths session unavailable)")
    end

    return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- Attribution readout. Now that we know the shape, this turns the raw C_DamageMeter source records
-- into the human-readable "what you took avoidable damage from / what you kicked / what you dispelled"
-- view - the foundation for per-spell scoring. READ-ONLY; nothing here feeds the live pipeline yet.
----------------------------------------------------------------------

-- Melee / auto-attack spellIDs. A death dominated by these (on a non-tank) is a threat/positioning
-- read, not a mechanic - but only a FLAG, never a verdict (fixate/soak/cleave also land as melee).
local MELEE_SPELLS = { [6603] = true }   -- 6603 = "Auto Attack"; extend as we confirm creature-melee IDs

local function spellName(id)
    id = ML.ReadNum(id)
    if not id then return "?" end
    local n
    if _G.C_Spell and _G.C_Spell.GetSpellName then n = _G.C_Spell.GetSpellName(id) end
    if not n and _G.GetSpellInfo then n = _G.GetSpellInfo(id) end
    return (n and n ~= "" and n) or ("spell:" .. tostring(id))
end

-- Normalize one GetCombatSessionSourceFromType(...) record into a flat spell list. Returns
-- { total, max, spells = { { spellID, amount, aps, overkill, isDeadly, srcName, isMob, isPet,
-- classification } } } or nil. `sessionType` is an Enum.DamageMeterSessionType value.
local function readSourceSpells(dm, sessionType, meterType, guid)
    if type(dm) ~= "table" or type(dm.GetCombatSessionSourceFromType) ~= "function" then return nil end
    if meterType == nil or not guid then return nil end
    local ok, src = pcall(dm.GetCombatSessionSourceFromType, sessionType, meterType, guid)
    if not ok or type(src) ~= "table" or type(src.combatSpells) ~= "table" then return nil end
    local spells = {}
    for _, s in ipairs(src.combatSpells) do
        local d = (type(s.combatSpellDetails) == "table" and s.combatSpellDetails) or {}
        spells[#spells + 1] = {
            spellID        = ML.ReadNum(s.spellID),
            amount         = ML.ReadNum(s.totalAmount),
            aps            = ML.ReadNum(s.amountPerSecond),
            overkill       = ML.ReadNum(s.overkillAmount),
            isDeadly       = s.isDeadly and true or false,
            srcName        = ML.ReadStr(d.unitName),
            isMob          = d.isMob and true or false,
            isPet          = d.isPet and true or false,
            classification = ML.ReadStr(d.classification),
        }
    end
    return { total = ML.ReadNum(src.totalAmount), max = ML.ReadNum(src.maxAmount), spells = spells }
end
Diag.ReadSourceSpells = readSourceSpells

-- Build the set of spellIDs the AvoidableDamageTaken bucket lists for a source - the RELIABLE avoidable
-- signal (the per-spell isAvoidable flag reads false even here, so we go by bucket membership instead).
local function avoidableSet(dm, sessionType, guid)
    local set = {}
    local rec = readSourceSpells(dm, sessionType, _G.Enum and _G.Enum.DamageMeterType and _G.Enum.DamageMeterType.AvoidableDamageTaken, guid)
    if rec then for _, s in ipairs(rec.spells) do if s.spellID then set[s.spellID] = s.amount end end end
    return set
end

function Diag.ProbeAttribution(emit)
    local out = {}
    local function line(s) out[#out + 1] = s; if emit then emit(s) else print(ML.PREFIX .. s) end end
    local dm = _G.C_DamageMeter
    local MT = _G.Enum and _G.Enum.DamageMeterType
    local ST = _G.Enum and _G.Enum.DamageMeterSessionType
    if type(dm) ~= "table" or type(MT) ~= "table" or type(ST) ~= "table" then
        line("C_DamageMeter/Enum " .. MISS); return table.concat(out, "\n")
    end
    local sessionType = ST.Overall or 0
    local guid = _G.UnitGUID and _G.UnitGUID("player")
    local me = API.PlayerContext and API.PlayerContext()
    local role = me and me.role
    line(string.format("== Attribution (you: %s, role %s) ==", tostring(me and me.fullName or "?"), tostring(role)))

    -- Avoidable damage taken: named, sourced, sorted biggest-first.
    local avoid = readSourceSpells(dm, sessionType, MT.AvoidableDamageTaken, guid)
    if avoid and #avoid.spells > 0 then
        table.sort(avoid.spells, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
        line(string.format("Avoidable damage taken (%s total):", Util.shortNum(avoid.total)))
        for _, s in ipairs(avoid.spells) do
            line(string.format("  %8s  %-22s %s (%s)", Util.shortNum(s.amount),
                (s.srcName and s.srcName ~= "" and s.srcName) or "?", spellName(s.spellID), tostring(s.spellID)))
        end
    else
        line("Avoidable damage taken: none recorded")
    end

    -- Interrupts: enemy spellID you kicked + how many times (totalAmount is a COUNT here).
    local kicks = readSourceSpells(dm, sessionType, MT.Interrupts, guid)
    if kicks and #kicks.spells > 0 then
        table.sort(kicks.spells, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
        line(string.format("Interrupts (%s total):", Util.shortNum(kicks.total)))
        for _, s in ipairs(kicks.spells) do
            line(string.format("  x%-3s %s (%s)", tostring(s.amount or 0), spellName(s.spellID), tostring(s.spellID)))
        end
    else
        line("Interrupts: none recorded")
    end

    -- Dispels: debuff spellID you removed + count.
    local disp = readSourceSpells(dm, sessionType, MT.Dispels, guid)
    if disp and #disp.spells > 0 then
        table.sort(disp.spells, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
        line(string.format("Dispels (%s total):", Util.shortNum(disp.total)))
        for _, s in ipairs(disp.spells) do
            line(string.format("  x%-3s %s (%s)", tostring(s.amount or 0), spellName(s.spellID), tostring(s.spellID)))
        end
    else
        line("Dispels: none recorded")
    end

    -- Top damage taken, tagged: [AVOID] via bucket membership, [MELEE] via spellID, [FATAL] via isDeadly.
    local taken = readSourceSpells(dm, sessionType, MT.DamageTaken, guid)
    if taken and #taken.spells > 0 then
        local avoidIDs = avoidableSet(dm, sessionType, guid)
        table.sort(taken.spells, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
        line(string.format("Top damage taken (%s total):", Util.shortNum(taken.total)))
        for i, s in ipairs(taken.spells) do
            if i > 8 then break end
            local tags = {}
            if s.spellID and avoidIDs[s.spellID] then tags[#tags + 1] = "AVOID" end
            if s.spellID and MELEE_SPELLS[s.spellID] then tags[#tags + 1] = (role ~= "TANK") and "MELEE!" or "MELEE" end
            if s.isDeadly then tags[#tags + 1] = "FATAL" end
            line(string.format("  %8s  %-22s %s (%s)%s", Util.shortNum(s.amount),
                (s.srcName and s.srcName ~= "" and s.srcName) or "?", spellName(s.spellID), tostring(s.spellID),
                #tags > 0 and ("  [" .. table.concat(tags, "][") .. "]") or ""))
        end
    end

    return table.concat(out, "\n")
end

-- ProbeDeathRecap: exercise the REAL capture path (Providers.ReadDeathRecaps -> C_DeathRecap.
-- GetRecapEvents) against the live meter and show the parsed recap + how ClassifyDeaths buckets it. Any
-- death populates it (a target-dummy / fall death works), so it validates the whole pipeline without a
-- key. Run right after dying, out of combat.
function Diag.ProbeDeathRecap(emit)
    local out = {}
    local function line(s) out[#out + 1] = s; if emit then emit(s) else print(ML.PREFIX .. s) end end
    local DR = _G.C_DeathRecap
    line("C_DeathRecap = " .. type(DR))
    if type(DR) == "table" then
        local fns = {}
        for k, v in pairs(DR) do if type(v) == "function" then fns[#fns + 1] = k end end
        table.sort(fns)
        line("  functions: " .. table.concat(fns, ", "))
    end

    local ctx = { player = API.PlayerContext and API.PlayerContext(),
                  party = (API.GroupMembers and API.GroupMembers()) or {}, petOwners = {} }
    local recaps = ML.Providers.ReadDeathRecaps and ML.Providers.ReadDeathRecaps(ctx)
    if not recaps then
        line("ReadDeathRecaps -> nil (no deaths in the meter yet, or C_DeathRecap unavailable). Die once, then re-run.")
        return table.concat(out, "\n")
    end

    local myGUID = ctx.player and ctx.player.guid
    for guid, deaths in pairs(recaps) do
        line(string.format("== %s: %d death(s) ==", (guid == myGUID) and "YOU" or tostring(guid), #deaths))
        for di, d in ipairs(deaths) do
            line(string.format("  death %d  recapID=%s  maxHP=%s  events=%d", di, tostring(d.recapID),
                tostring(d.maxHP), #d.events))
            for _, e in ipairs(d.events) do
                line(string.format("      %-22s %-20s amt=%-9s over=%-7s hp=%s",
                    (e.name and e.name ~= "" and e.name) or spellName(e.id),
                    tostring(e.ev), tostring(e.amt), tostring(e.over), tostring(e.hp)))
            end
        end
    end

    -- Classification preview for the local player, exactly as finalize would compute it. Build the kick
    -- set from the current dungeon (nil outside a key -> no missed-kick classification, e.g. at a dummy).
    if myGUID and recaps[myGUID] then
        local attrib = ML.Providers.ReadAttribution and ML.Providers.ReadAttribution(ctx)
        local kickSet
        local Cfg = ML.Scoring and ML.Scoring.Config
        local dName
        if _G.C_ChallengeMode and _G.C_ChallengeMode.GetActiveChallengeMapID then
            local id = _G.C_ChallengeMode.GetActiveChallengeMapID()
            local mi = id and API.GetMapInfo and API.GetMapInfo(id)
            dName = mi and mi.name
        end
        local cat = Cfg and Cfg.SeasonDungeon and dName and Cfg.SeasonDungeon(dName)
        if cat and type(cat.kicks) == "table" then
            kickSet = {}
            for _, e in ipairs(cat.kicks) do if e.id then kickSet[e.id] = true end end
        end
        local dc = ML.Providers.ClassifyDeaths(attrib and attrib[myGUID], recaps[myGUID],
            ctx.player.role, #recaps[myGUID], kickSet)
        if dc then
            line(string.format("== classification (you): avoidable=%d  kickable=%d  threat=%d  other=%d ==",
                dc.avoidable, dc.kickable or 0, dc.threat, dc.other))
            for _, f in ipairs(dc.fatal or {}) do
                line(string.format("   death -> %-9s  (avoid %d%%, kick %d%%, melee %d%%; finished by %s)",
                    f.cause, f.avoidPct or 0, f.kickPct or 0, f.meleePct or 0,
                    (f.killer and f.killer ~= "" and f.killer) or spellName(f.killerId)))
            end
        end
    end
    return table.concat(out, "\n")
end
