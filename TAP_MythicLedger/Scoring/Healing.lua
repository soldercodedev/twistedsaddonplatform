-- TAP: Mythic Ledger - Scoring/Healing.lua
-- The healing REQUIREMENT model. Runs ONCE per run over the whole party and hands each TANK and HEALER
-- an expected healing OUTPUT (a target) derived from the damage the group actually took, so the
-- throughput scorer judges "did you heal what the encounter dealt" instead of "your share of group HPS".
--
--   required(p)   = max(0, damageTaken(p) - avoidableDamageTaken(p))   -- unavoidable HP lost
--   output(p)     = healing(p) + absorbs(p)
--   tank target   = TankSelfCoverage(spec) x required(tank)
--   healer target = SUM over tanks[(1 - coverage_t) x required(t)]
--                 + groupSelfHealFactor x (required(nonTank) + avoidableCredit x avoidable(nonTank))
--
-- Avoidable damage a player eats is EXCLUDED from the healer's target (it hits that player's own Survival
-- score); avoidableCredit adds back a small slice so the healer is lightly on the hook for triage, not a
-- group of standers. Absorbs count as output so shield healers/tanks aren't penalised. All knobs live in
-- Config.healing / Config.TankSelfCoverage.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Healing = {}
Scoring.Healing = Healing
local Cfg = Scoring.Config

local function n0(v) return (type(v) == "number") and v or 0 end

-- Per-player output (effective healing + shields). The Blizzard meter reports effective healing already
-- (no overheal to strip); the soft-cap in Cat.Throughput guards padding.
local function outputOf(p)
    return n0(p.healing) + n0(p.absorbs)
end

-- Compute the model for a normalized party. Returns:
--   { applicable, coverage, byGuid = { [guid] = { role, requirement, output, ratio, coverage,
--     detail = {...} } } }  (only tanks & healers get an entry; DPS are untouched)
function Healing.Compute(players)
    local H = Cfg.healing or {}
    if type(players) ~= "table" or H.enabled == false then return { applicable = false } end

    -- Party-wide sums. A player with no damageTaken is "unknown" and excluded from the sums (never 0);
    -- coverage tracks how much of the party we could actually read.
    local tanks, healers = {}, {}
    local tankRequired, groupRequired, groupAvoidable = 0, 0, 0
    local known, total = 0, 0
    for _, p in ipairs(players) do
        total = total + 1
        local hasDT = type(p.damageTaken) == "number"
        if hasDT then known = known + 1 end
        local required = hasDT and math.max(0, p.damageTaken - n0(p.avoidableDamageTaken)) or nil
        if p.role == "TANK" then
            tanks[#tanks + 1] = { p = p, required = required }
            if required then tankRequired = tankRequired + required end
        else
            if required then
                groupRequired = groupRequired + required
                groupAvoidable = groupAvoidable + n0(p.avoidableDamageTaken)
            end
            if p.role == "HEALER" then healers[#healers + 1] = p end
        end
    end

    local coverage = (total > 0) and (known / total) or 0
    if coverage < (H.minPartyCoverage or 0.6) then
        -- Not enough of the party reported damage taken to trust the model this run.
        return { applicable = false, coverage = coverage, reason = "insufficient damage-taken data" }
    end

    local byGuid = {}

    -- Tanks: expected to self-cover TankSelfCoverage(spec) of their own unavoidable damage.
    local healerTankRemainder = 0
    for _, t in ipairs(tanks) do
        local cov = Cfg.TankSelfCoverage(t.p.specID)
        if t.required then healerTankRemainder = healerTankRemainder + (1 - cov) * t.required end
        if t.p.playerGUID and t.required and t.required > 0 then
            local target = cov * t.required
            local output = outputOf(t.p)
            byGuid[t.p.playerGUID] = {
                role = "TANK", requirement = target, output = output,
                ratio = (target > 0) and (output / target) or nil, coverage = coverage,
                detail = { selfCoverage = cov, required = t.required,
                           avoidable = n0(t.p.avoidableDamageTaken), absorbs = n0(t.p.absorbs) },
            }
        end
    end

    -- Healer target: the tanks' remainder + the group's unavoidable load (+ a slice of their avoidable).
    local avCredit = H.avoidableCredit or 0.25
    local selfHeal = H.groupSelfHealFactor or 0.90
    local healerTarget = healerTankRemainder
        + selfHeal * (groupRequired + avCredit * groupAvoidable)

    -- Shared evenly if (rare) there are multiple healers; each is judged against its slice.
    local nH = #healers
    if nH > 0 and healerTarget > 0 then
        local slice = healerTarget / nH
        for _, h in ipairs(healers) do
            if h.playerGUID then
                local output = outputOf(h)
                byGuid[h.playerGUID] = {
                    role = "HEALER", requirement = slice, output = output,
                    ratio = (slice > 0) and (output / slice) or nil, coverage = coverage,
                    detail = { tankRemainder = healerTankRemainder, groupRequired = groupRequired,
                               groupAvoidable = groupAvoidable, avoidableCredit = avCredit,
                               selfHealFactor = selfHeal, healers = nH },
                }
            end
        end
    end

    return { applicable = true, coverage = coverage, byGuid = byGuid,
             tankRequired = tankRequired, groupRequired = groupRequired, healerTarget = healerTarget }
end

return Healing
