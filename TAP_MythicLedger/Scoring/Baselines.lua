-- TAP: Mythic Ledger - Scoring/Baselines.lua
-- Throughput baselines are GROUP-RELATIVE and DETERMINISTIC - no self-learning. Self-learning was
-- removed on purpose: a learned median makes the SAME run score differently on two installs (each has
-- a different history), which is unacceptable for a shared/compared score. Instead we anchor every
-- expectation to the group's OWN totals for this run:
--     expected(metric, player) = groupTotal(metric) * playerShare(metric) / sum(shares over group)
-- so the baseline is scale-agnostic (works at any gear/number level) and identical everywhere given
-- the same run data. Shares come from Config.groupShare (role) x tankHealiness (spec). HPS counts for
-- healers AND tanks; DPS off-heals count for almost nothing. See Config.throughput.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Base = {}
Scoring.Baselines = Base
local Cfg = Scoring.Config

-- The primary metric a role is judged on (used by explanations / legacy callers).
function Base.Metric(role)
    return (role == "HEALER") and "hps" or "dps"
end

-- The throughput blend {dps=, hps=} for a role/spec (tanks lean on HPS by spec healiness).
function Base.Mix(role, specID)
    return Cfg.ThroughputMix(role, specID)
end

-- Cap the group totals used AS THE BASELINE so an overperformer's excess doesn't inflate everyone's
-- expected value. Each player's contribution to the group total is capped at their OWN expected share
-- (computed from the raw total); damage/healing beyond your share simply doesn't count toward the
-- baseline. Interrupt/dispel totals pass through unchanged (they drive confidence, not throughput).
-- Returns { dps, hps, interrupts, dispels }.
function Base.EffectiveGroupTotals(players, summary, raw)
    raw = raw or {}
    local out = { dps = 0, hps = 0, interrupts = raw.interrupts, dispels = raw.dispels }
    local sDPS, sHPS = (summary and summary.shareDPS) or 0, (summary and summary.shareHPS) or 0
    local gDPS, gHPS = raw.dps or 0, raw.hps or 0
    local aug = summary and summary.augAdjust
    for _, p in ipairs(players or {}) do
        local shD = Cfg.ThroughputShare("dps", p.role, p.specID, aug)
        local shH = Cfg.ThroughputShare("hps", p.role, p.specID, aug)
        local expD = (sDPS > 0 and gDPS > 0 and shD > 0) and (gDPS * shD / sDPS) or nil
        local expH = (sHPS > 0 and gHPS > 0 and shH > 0) and (gHPS * shH / sHPS) or nil
        out.dps = out.dps + (expD and math.min(p.dps or 0, expD) or (p.dps or 0))
        out.hps = out.hps + (expH and math.min(p.hps or 0, expH) or (p.hps or 0))
    end
    return out
end

-- Group-relative throughput baseline for a normalized player. Needs the group summary (for the share
-- denominators) and the group totals (dps/hps sums). Returns:
--   { dps, hps, mix = {dps,hps}, source, groupDPS, groupHPS, shareDPS, shareHPS }
-- dps/hps are this player's EXPECTED per-second value; either may be nil if the group produced none of
-- that metric (then that component is skipped, or a static fallback is used for the primary metric).
function Base.Throughput(norm, summary, groupTotals)
    local role = norm.role or "DAMAGER"
    summary = summary or {}
    groupTotals = groupTotals or {}
    local gDPS, gHPS = groupTotals.dps or 0, groupTotals.hps or 0
    local sDPS, sHPS = summary.shareDPS or 0, summary.shareHPS or 0

    local myDPSshare = Cfg.ThroughputShare("dps", role, norm.specID, summary.augAdjust)
    local myHPSshare = Cfg.ThroughputShare("hps", role, norm.specID, summary.augAdjust)

    local expDPS = (sDPS > 0 and gDPS > 0 and myDPSshare > 0) and (gDPS * myDPSshare / sDPS) or nil
    local expHPS = (sHPS > 0 and gHPS > 0 and myHPSshare > 0) and (gHPS * myHPSshare / sHPS) or nil

    -- Fallback for the PRIMARY metric only, so a metadata-only run (no group totals) still scores
    -- against something rather than dropping to a flat estimate.
    if not expDPS and not expHPS then
        local ref = Cfg.throughput.staticReference[role] or Cfg.throughput.staticReference.DAMAGER
        if ref.metric == "hps" then expHPS = ref.value else expDPS = ref.value end
    end

    return {
        dps = expDPS, hps = expHPS,
        mix = Cfg.ThroughputMix(role, norm.specID),
        source = (gDPS > 0 or gHPS > 0) and "GROUP" or "STATIC",
        groupDPS = gDPS, groupHPS = gHPS, shareDPS = sDPS, shareHPS = sHPS,
        myDPSshare = myDPSshare, myHPSshare = myHPSshare,
    }
end
