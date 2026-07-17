-- TAP: Mythic Ledger - Scoring/Normalize.lua
-- Turns a raw run + party-member record into a NormalizedPlayerRunStats the scoring layer consumes,
-- so nothing downstream cares whether the numbers came from C_DamageMeter or metadata-only. Missing
-- values stay NIL (never coerced to 0) and dataCompleteness reports how much we actually have.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Norm = {}
Scoring.Normalize = Norm

-- Fields we grade on; presence of these drives dataCompleteness.
local SCORED_FIELDS = { "damageDone", "dps", "damageTaken", "avoidableDamageTaken",
                        "healing", "hps", "interrupts", "dispels", "deaths" }

-- Map a member's stat block (Providers naming) to the normalized names. Numbers only; nil = missing.
local function num(v) return (type(v) == "number") and v or nil end

-- Build a NormalizedPlayerRunStats from run + one party member (member.stats holds the meter block).
-- `role` falls back through member.role -> spec profile role. Returns nil if member is unusable.
function Norm.Player(run, member)
    if not (run and member) then return nil end
    local s = member.stats or {}
    local specID = member.specId or member.specID
    local role = member.role
    if not role and specID and Scoring.Capability then role = Scoring.Capability.Get(specID).role end
    -- Recover a missing spec id from class + role (common in real captures without an inspect) so a
    -- Shaman/Healer is scored as Restoration (which kicks) instead of the "unknown healer" fallback.
    if not specID and role and member.classFile and Scoring.Capability and Scoring.Capability.ResolveSpec then
        specID = Scoring.Capability.ResolveSpec(member.classFile, role)
    end

    local n = {
        playerGUID = member.guid, name = member.name or member.fullName, fullName = member.fullName,
        classID = member.classId or member.classID, classFile = member.classFile,
        specID = specID, role = role, isPlayer = member.isPlayer and true or false,
        dungeonName = run.dungeonName,   -- for the dungeon dispel-type gate (mapId is set below)
        -- Live talent-inspection verdict for a TALENT-GATED dispel (true/false/nil = has/not/unknown).
        -- Lets Categories.Dispel avoid docking a player for a dispel they never talented.
        dispelTalent = member.dispelTalent,
        -- Same idea for a TALENT/PET-GATED interrupt (Warlock Spell Lock). nil today (Spell Lock is a pet
        -- ability, not a readable talent node) - the gate falls back to "did they actually kick".
        interruptTalent = member.interruptTalent,

        durationSeconds = num(run.duration),
        damageDone   = num(s.damage),
        dps          = num(s.dps),
        damageTaken  = num(s.damageTaken),
        avoidableDamageTaken = num(s.avoidableDamageTaken),
        absorbs      = num(s.absorbs),
        healing      = num(s.healing),
        hps          = num(s.hps),
        interrupts   = num(s.interrupts),
        dispels      = num(s.dispels),
        deaths       = num(s.deaths),

        -- Context used by baselines/composition.
        level = num(run.level), mapId = run.mapId, seasonId = run.seasonId,
        dataSource = run.provider or ML.SOURCE and ML.SOURCE.NONE,
    }

    -- Clean run = the meter tracked you (real combat numbers) but logged no death rows, so deaths reads
    -- back nil. That means ZERO, not "no data" - so the Deaths category scores a confident "no deaths"
    -- (100) instead of a neutral "no death data recorded". Applies retroactively to already-saved runs
    -- too. Only when genuinely tracked; an untracked run (no combat stats at all) stays nil = unknown.
    if n.deaths == nil and (n.dps or n.damageDone or n.hps or n.healing) then n.deaths = 0 end

    -- Same for AVOIDABLE damage taken: on a tracked run, no avoidable-damage rows means you took NONE of
    -- it - a true 0, not "no data". So Survival scores a confident 0% avoidable share -> 100, instead of
    -- a neutral "no avoidable-damage data" estimate. Only when genuinely tracked (real combat numbers).
    if n.avoidableDamageTaken == nil and (n.dps or n.damageDone or n.hps or n.healing) then n.avoidableDamageTaken = 0 end

    -- Effective/active seconds is NOT stored by the meter; approximate from damage/dps when both
    -- exist (Blizzard's dps is over effective combat time). Marked as an estimate for the UI.
    if n.damageDone and n.dps and n.dps > 0 then
        n.activeSeconds = n.damageDone / n.dps
        n.activeSecondsEstimated = true
    else
        n.activeSeconds = n.durationSeconds
        n.activeSecondsEstimated = (n.durationSeconds ~= nil)
    end

    local present = 0
    for _, f in ipairs(SCORED_FIELDS) do if n[f] ~= nil then present = present + 1 end end
    n.dataCompleteness = present / #SCORED_FIELDS

    return n
end

-- Normalize every party member of a run -> array. Skips members with no identity.
function Norm.Party(run)
    local out = {}
    for _, m in ipairs(run and run.party or {}) do
        local n = Norm.Player(run, m)
        if n and (n.playerGUID or n.name) then out[#out + 1] = n end
    end
    return out
end

Norm.SCORED_FIELDS = SCORED_FIELDS
return Norm
