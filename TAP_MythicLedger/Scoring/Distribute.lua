-- TAP: Mythic Ledger - Scoring/Distribute.lua
-- Group-relative workload distribution for interrupts and dispels. Runs ONCE per run over the whole
-- party and hands each player a fair EXPECTED count, so the per-player scorers just compare actual vs
-- expected. Three ideas, uniform across every dungeon:
--   1. SUPPLY - roughly how many kicks / dispels the run offered. Read from the SEASON UTILITY PROFILE
--      (Scoring/Seasons/*.lua): a trash block + one block per boss, each carrying a "frequency" for kicks
--      and per-school dispels. A run's supply = the trash block + the boss blocks for the bosses actually
--      killed, times a per-source scale (Config.supplyScale) - so boss-time handling is implicit and
--      exact (a boss with nothing to kick simply contributes 0). Capped by the group's cooldown capacity:
--      you can't land more than the group's cooldowns allow.
--   2. CAPABILITY SHARE - split the supply by what each spec can actually do (its interrupt cooldown; for
--      dispels, per SCHOOL among only the members who can cleanse/purge that school). More capable
--      teammates shrink your share, so their presence lowers your workload structurally.
--   3. SNIPING REDISTRIBUTION - if a teammate does MORE than their share, that work was taken from
--      others, so the under-performers' expected is reduced (never docked for a kick a teammate stole);
--      the over-performer is capped at 100 by the curve (never rewarded for the snipe).
-- Data note: Midnight gives only AGGREGATE counts (no per-cast log), so a snipe is INFERRED from the
-- actuals via (3), not observed. The calibration knobs are the season frequencies + the supply scales;
-- the whole distribution on top of them is real data.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Distribute = {}
Scoring.Distribute = Distribute

local Cap = Scoring.Capability
local Cfg = Scoring.Config

-- Redistribute overcap onto under-performers: reduce each shortfaller's expected toward their actual,
-- proportional to their shortfall, using only as much overcap as there is shortfall to absorb. Mutates
-- and returns `entries` (each { guid, base, actual, expected }). expected is never pushed below actual.
local function redistribute(entries)
    local overcap, shortfall = 0, 0
    for _, e in ipairs(entries) do
        local a = e.actual or 0
        if a > e.base then overcap = overcap + (a - e.base)
        elseif a < e.base then shortfall = shortfall + (e.base - a) end
    end
    -- snipeForgiveness in [0,1]: how much a teammate's OVER-performance is allowed to excuse an
    -- under-performer's shortfall. 1.0 = fully forgiven (a lazy player ends up judged on what they
    -- actually did - the old behavior); 0.0 = not forgiven (judged on their full capability share). The
    -- middle keeps "you weren't docked for a kick a teammate genuinely sniped when nothing was left" while
    -- still flagging someone who plainly under-used their kit even though teammates covered the pool.
    local forgive = Cfg.snipeForgiveness
    if type(forgive) ~= "number" then forgive = 1.0 end
    forgive = (forgive < 0 and 0) or (forgive > 1 and 1) or forgive
    local usable = math.min(overcap, shortfall) * forgive
    for _, e in ipairs(entries) do
        local a = e.actual or 0
        if a < e.base and shortfall > 0 then
            local mine = e.base - a
            e.expected = e.base - usable * (mine / shortfall)
        else
            e.expected = e.base
        end
    end
    return entries
end

-- Sum a season-profile "frequency" across the run: the trash block + the block of every boss actually
-- killed, each scaled by its per-source scale. `field` is a block sub-table ("partyDebuffFrequencies" /
-- "targetBuffFrequencies") or nil to read a scalar field ("interruptFrequency") straight off the block;
-- `key` selects the school within a sub-table (ignored when field is nil).
-- TIME-AWARE, per source: trash frequencies are a PER-MINUTE density (scaled by total run minutes - a
-- fast clear has less combat time and fewer castable events). Boss frequencies are per a REFERENCE fight
-- length and scaled by how long THAT boss was actually engaged (b.totalTime): a boss's mechanics recycle
-- while it's up, so a slow kill cycles more kicks/dispels than a burst, and a boss dropped before its
-- ability comes around offers almost none. A boss with no recorded fight time falls back to its base
-- (reference-length) weight so nothing regresses on older/partial records.
local function accumulate(sd, run, field, key, trashScale, bossScale)
    local total = 0
    local durMin = math.max(0, ((run and run.duration) or 0)) / 60
    local bossRef = (Cfg.supplyScale and Cfg.supplyScale.bossRefSeconds) or 90
    local function fromBlock(blk, scale)
        if not blk then return end
        local v
        if field then local sub = blk[field]; v = sub and sub[key] else v = blk[key] end
        if type(v) == "number" then total = total + v * scale end
    end
    fromBlock(sd.trash, trashScale * durMin)
    if sd.bosses and run and type(run.bosses) == "table" then
        for _, b in ipairs(run.bosses) do
            local id = b and tonumber(b.id)
            local secs = b and (tonumber(b.totalTime) or tonumber(b.killDuration))
            local timeFactor = (secs and secs > 0 and bossRef > 0) and (secs / bossRef) or 1
            fromBlock(id and sd.bosses[id], bossScale * timeFactor)
        end
    end
    return total
end

----------------------------------------------------------------------
-- Interrupts. supply = season kick frequency (trash + killed bosses) x per-source scale, capped by the
-- group's kick capacity; split by each spec's interrupt cooldown.
----------------------------------------------------------------------
function Distribute.Interrupts(players, run)
    local out = {}
    if type(players) ~= "table" then return out end
    local sd = Cfg.SeasonDungeon and Cfg.SeasonDungeon(run and run.dungeonName, run and run.seasonId)
    if not sd then return out end                              -- no season data: caller falls back to N/A
    local scale = Cfg.supplyScale or {}
    local kickMinutes = math.max(0, ((run and run.duration) or 0)) / 60

    -- Capacity per kick-capable player. A talent/pet-gated interrupt (Warlock Spell Lock) only enters the
    -- pool if we can confirm the tool (inspection) or they actually landed a kick - otherwise it's not
    -- part of the group's kick capacity (and Cat.Interrupt will N/A them).
    local entries, totalCap = {}, 0
    for _, p in ipairs(players) do
        local prof = Cap.Get(p.specID, p.role)
        local ip = prof.interrupt and prof.interrupt.profile
        local pcfg = ip and Cfg.interruptProfiles[ip]
        if pcfg and pcfg.scoreEligible then
            local confirmed = true
            if prof.interrupt.talentDependent then
                confirmed = (p.interruptTalent == true) or ((type(p.interrupts) == "number") and p.interrupts >= 1)
            end
            if confirmed then
                local rate = Cfg.InterruptRatePerMinute(prof.interrupt)
                local capacity = kickMinutes * (rate or 0)
                if capacity > 0 and p.playerGUID then
                    entries[#entries + 1] = { guid = p.playerGUID, capacity = capacity,
                                              actual = (type(p.interrupts) == "number") and p.interrupts or 0 }
                    totalCap = totalCap + capacity
                end
            end
        end
    end
    if totalCap <= 0 then return out end

    local dungeonSupply = accumulate(sd, run, nil, "interruptFrequency",
        scale.trashKick or 10, scale.bossKick or 1.5)
    local supply = math.min(dungeonSupply, totalCap)   -- casts available AND cooldown-limited

    for _, e in ipairs(entries) do
        e.share = e.capacity / totalCap
        e.base = supply * e.share
    end
    redistribute(entries)

    -- Group summary (for the run-details / scoreboard highlight AND the LONG_CD pass): every kick the party
    -- landed vs the run's kick supply (what it offered, capped by group cooldown capacity - the same value
    -- scoring uses), plus how many party deaths were attributed to a KICKABLE cast (v38 death causes). Both
    -- are surfaced per-player so Cat.Interrupt can pass a LONG_CD kicker the group covered - unless someone
    -- died to a cast that could have been kicked.
    local groupActual, partyKickDeaths = 0, 0
    for _, p in ipairs(players) do
        if type(p.interrupts) == "number" then groupActual = groupActual + p.interrupts end
        local dc = p.deathCauses
        if type(dc) == "table" and type(dc.kickable) == "number" then partyKickDeaths = partyKickDeaths + dc.kickable end
    end
    local groupCoverage = (supply > 0) and (groupActual / supply) or nil

    for _, e in ipairs(entries) do
        out[e.guid] = { expected = e.expected, baseExpected = e.base, share = e.share, capacity = e.capacity,
                        supply = supply, dungeonSupply = dungeonSupply, groupCapacity = totalCap,
                        groupActual = groupActual, groupCoverage = groupCoverage, partyKickableDeaths = partyKickDeaths }
    end
    return out, { actual = groupActual, expected = supply, dungeonSupply = dungeonSupply, groupCapacity = totalCap }
end

----------------------------------------------------------------------
-- Dispels. Supply is PER SCHOOL x AXIS (defensive cleanse vs offensive purge/soothe), summed from the
-- season profile: defensive schools from partyDebuffFrequencies, offensive from targetBuffFrequencies
-- (purge -> the magic offensive school, enrage -> soothe). Each school's supply is split only among the
-- members who can address THAT school on THAT axis. A player's base expected is the sum of their shares
-- across every school they cover, so a broad healer expects more than a single-school tool, and a school
-- only one player can touch lands entirely on them.
----------------------------------------------------------------------
local DEF_TYPES = { "magic", "curse", "poison", "disease" }
local OFF_TYPES = { "magic", "enrage" }

function Distribute.Dispels(players, run)
    local out = {}
    if type(players) ~= "table" then return out end
    local sd = Cfg.SeasonDungeon and Cfg.SeasonDungeon(run and run.dungeonName, run and run.seasonId)
    if not sd then return out end                              -- no season data: caller falls back to N/A
    local scale = Cfg.supplyScale or {}
    local dispelMinutes = math.max(0, ((run and run.duration) or 0)) / 60

    -- Per-player dispel capacity (rate x minutes) + which schools it covers on each axis. Talent-gated
    -- cleanses only count if confirmed or they dispelled (mirrors the interrupt gate + Cat.Dispel).
    local pool = {}   -- guid -> { capacity, def = {t=true}, off = {t=true}, actual }
    for _, p in ipairs(players) do
        local prof = Cap.Get(p.specID, p.role)
        local d = prof.dispel
        local dp = d and d.profile
        local pcfg = dp and Cfg.dispelProfiles[dp]
        if pcfg and pcfg.scoreEligible and p.playerGUID then
            local confirmed = true
            if d.talentDependent then
                confirmed = (p.dispelTalent == true) or ((type(p.dispels) == "number") and p.dispels >= 1)
            end
            if confirmed then
                local cap = dispelMinutes * (pcfg.ratePerMinute or 0)
                if cap > 0 then
                    pool[p.playerGUID] = { capacity = cap, def = d.defensive or {}, off = d.offensive or {},
                                           actual = (type(p.dispels) == "number") and p.dispels or 0 }
                end
            end
        end
    end
    if not next(pool) then return out end

    -- Per (axis, school) supply from the season profile (trash + killed bosses). The dispel demand is
    -- then scaled by the dungeon's PRIORITY fraction (sd.dispelDemandScale) - only high/must-priority
    -- dispels are expected, so a broad dispeller isn't docked for skipping low-value cleanses (the
    -- fraction is the observed share of dispels that were curated High/Must, floored so an under-curated
    -- dungeon doesn't collapse to zero). Default 1.0 = count everything (older profiles).
    local defSupply, offSupply = {}, {}
    local tD, bD = scale.trashDispel or 4, scale.bossDispel or 1
    local dScale = tonumber(sd.dispelDemandScale) or 1.0
    for _, t in ipairs(DEF_TYPES) do
        defSupply[t] = accumulate(sd, run, "partyDebuffFrequencies", t, tD, bD) * dScale
    end
    offSupply["magic"]  = accumulate(sd, run, "targetBuffFrequencies", "purge",  tD, bD) * dScale  -- purge = enemy magic buff
    offSupply["enrage"] = accumulate(sd, run, "targetBuffFrequencies", "enrage", tD, bD) * dScale  -- enrage = soothe

    -- base = summed expected across schools; defBase/offBase = the split by axis (for the group summary
    -- and for splitting a dual-axis dispeller's aggregate count).
    local base, defBase, offBase = {}, {}, {}
    for guid in pairs(pool) do base[guid], defBase[guid], offBase[guid] = 0, 0, 0 end

    -- One pool per (axis, school): split that school's supply among capable members by capacity.
    local function distributeSchool(axisKey, t, supplyTbl)
        local schoolSupply = supplyTbl[t] or 0
        if schoolSupply <= 0 then return end
        local capable, sumCap = {}, 0
        for guid, pl in pairs(pool) do
            local bucket = (axisKey == "def") and pl.def or pl.off
            if bucket[t] then capable[#capable + 1] = guid; sumCap = sumCap + pl.capacity end
        end
        if sumCap <= 0 then return end
        for _, guid in ipairs(capable) do
            local add = schoolSupply * (pool[guid].capacity / sumCap)
            base[guid] = base[guid] + add
            if axisKey == "def" then defBase[guid] = defBase[guid] + add
            else offBase[guid] = offBase[guid] + add end
        end
    end
    for _, t in ipairs(DEF_TYPES) do distributeSchool("def", t, defSupply) end
    for _, t in ipairs(OFF_TYPES) do distributeSchool("off", t, offSupply) end

    -- Cap each player's base at their own capacity (can't be expected to dispel more than their cooldown
    -- allows even if they cover many schools), then redistribute on the AGGREGATE dispel count.
    local entries = {}
    for guid, pl in pairs(pool) do
        entries[#entries + 1] = { guid = guid, base = math.min(base[guid], pl.capacity), actual = pl.actual }
    end
    redistribute(entries)
    for _, e in ipairs(entries) do
        out[e.guid] = { expected = e.expected, baseExpected = e.base }
    end

    -- Group per-axis summary. Expected = raw season demand per axis (what the run threw). ACTUAL is split
    -- by capability: a single-axis dispeller's whole count lands on the axis it can address; a dual-axis
    -- one (can both cleanse AND purge) is split by its own expected def/off share, since the meter reports
    -- only ONE combined dispel count per player (no cleanse-vs-purge breakdown in Midnight).
    local defExpected, offExpected = 0, 0
    for _, t in ipairs(DEF_TYPES) do defExpected = defExpected + (defSupply[t] or 0) end
    for _, t in ipairs(OFF_TYPES) do offExpected = offExpected + (offSupply[t] or 0) end
    local defActual, offActual = 0, 0
    for guid, pl in pairs(pool) do
        local a = pl.actual or 0
        local canDef, canOff = next(pl.def) ~= nil, next(pl.off) ~= nil
        if canDef and canOff then
            local db, ob = defBase[guid] or 0, offBase[guid] or 0
            local denom = db + ob
            local defShare = (denom > 0) and (db / denom) or 0.5
            defActual = defActual + a * defShare
            offActual = offActual + a * (1 - defShare)
        elseif canDef then defActual = defActual + a
        elseif canOff then offActual = offActual + a
        end
    end

    -- Per-player group coverage, restricted to the AXES this spec can address (v39, for Cat.Dispel's
    -- group-covered escape). A defensive-only healer is judged on how much of the defensive demand the group
    -- cleansed; a purge-only DPS on the offensive demand - so one axis can't "cover" the other.
    for guid, pl in pairs(pool) do
        if out[guid] then
            local canDef, canOff = next(pl.def) ~= nil, next(pl.off) ~= nil
            local relExp = (canDef and defExpected or 0) + (canOff and offExpected or 0)
            local relAct = (canDef and defActual or 0) + (canOff and offActual or 0)
            out[guid].groupCoverage = (relExp > 0) and (relAct / relExp) or nil
        end
    end
    return out, { defExpected = defExpected, offExpected = offExpected, defActual = defActual, offActual = offActual }
end

----------------------------------------------------------------------
-- Group utility summary (read-only, for the run-details page + scoreboard). Total interrupts and the two
-- dispel AXES - target-buff PURGES/soothes (offensive) and debuff CLEANSES (defensive) - each as
-- actual-vs-expected, using the SAME season supply + capability logic the per-player scoring runs on.
-- Returns nil when the dungeon has no season data (nothing to compare against). Cheap: safe to call once
-- per render.
----------------------------------------------------------------------
function Distribute.GroupUtility(run)
    if type(run) ~= "table" then return nil end
    local Norm = Scoring.Normalize
    local players = Norm and Norm.Party and Norm.Party(run)
    if type(players) ~= "table" then return nil end
    local _, ig = Distribute.Interrupts(players, run)
    local _, dg = Distribute.Dispels(players, run)
    if not (ig or dg) then return nil end
    return {
        interrupts = ig and { actual = ig.actual, expected = ig.expected } or nil,
        purge   = dg and { actual = dg.offActual, expected = dg.offExpected } or nil,   -- enemy buffs / enrage
        cleanse = dg and { actual = dg.defActual, expected = dg.defExpected } or nil,   -- player debuffs
    }
end
