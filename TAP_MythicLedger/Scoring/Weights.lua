-- TAP: Mythic Ledger - Scoring/Weights.lua
-- Deterministic weight redistribution. When a utility category (interrupts/dispels) doesn't apply to
-- a spec, its weight is moved to categories the player CAN affect, per explicit per-role rules in
-- Config - never a silent zero, never a blanket renormalize. The result always sums to 1.0 and the
-- moves are logged so the UI can say exactly where the weight went.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Weights = {}
Scoring.Weights = Weights
local Cfg = Scoring.Config

local CATS = { "throughput", "interrupts", "dispels", "survival", "deaths" }

-- applicable: { interrupts = bool, dispels = bool } (others assumed applicable). role: TANK/HEALER/DAMAGER.
-- Returns weights (all six, sum 1.0) and a redistribution log { {from, to, amount}, ... }.
function Weights.Resolve(role, applicable)
    local base = Cfg.roleWeights[role] or Cfg.roleWeights.DAMAGER
    local w = {}
    for _, c in ipairs(CATS) do w[c] = base[c] or 0 end
    local log = {}
    applicable = applicable or {}

    local iOff = (applicable.interrupts == false) and w.interrupts > 0
    local dOff = (applicable.dispels == false) and w.dispels > 0

    local function move(from, freed, rule)
        w[from] = 0
        for to, frac in pairs(rule) do
            local amt = freed * frac
            w[to] = (w[to] or 0) + amt
            log[#log + 1] = { from = from, to = to, amount = amt }
        end
    end

    if iOff and dOff then
        -- Both utility categories gone: split their combined weight per the utilityBoth rule.
        local freed = w.interrupts + w.dispels
        w.interrupts, w.dispels = 0, 0
        local rule = Cfg.redistribution.utilityBoth[role] or Cfg.redistribution.utilityBoth.DAMAGER
        for to, frac in pairs(rule) do
            local amt = freed * frac
            w[to] = (w[to] or 0) + amt
            log[#log + 1] = { from = "interrupts+dispels", to = to, amount = amt }
        end
    else
        if iOff then move("interrupts", w.interrupts, Cfg.redistribution.interrupts[role] or Cfg.redistribution.interrupts.DAMAGER) end
        if dOff then move("dispels", w.dispels, Cfg.redistribution.dispels[role] or Cfg.redistribution.dispels.DAMAGER) end
    end

    -- Survival and Death Impact ALWAYS carry EXACTLY equal weight - for every role, and no matter which
    -- other categories applied or where redistributed weight landed (interrupt/dispel redistribution can
    -- feed survival but not deaths). Averaging the two is sum-preserving, so the total still sums to 1.0.
    if (w.survival or 0) ~= (w.deaths or 0) then
        local sd = ((w.survival or 0) + (w.deaths or 0)) / 2
        if w.survival ~= sd then log[#log + 1] = { from = "survival<->deaths", to = "equalize", amount = sd - (w.survival or 0) } end
        w.survival, w.deaths = sd, sd
    end

    -- Guard: renormalize away any float drift so the sum is exactly 1.0.
    local sum = 0; for _, c in ipairs(CATS) do sum = sum + w[c] end
    if sum > 0 and math.abs(sum - 1.0) > 1e-9 then
        for _, c in ipairs(CATS) do w[c] = w[c] / sum end
    end
    return w, log
end

Weights.CATS = CATS
