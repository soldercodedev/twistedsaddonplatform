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
