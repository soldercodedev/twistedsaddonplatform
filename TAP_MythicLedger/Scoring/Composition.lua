-- TAP: Mythic Ledger - Scoring/Composition.lua
-- Summarize a group's utility capability ONCE per run, then hand out small, bounded modifiers to a
-- single player's EXPECTED interrupt/dispel contribution. Rules (non-negotiable):
--   * A teammate's tools only ever LOWER your expectation (fewer casts left for you) or leave it
--     alone - never raise it, and never touch your actual score directly.
--   * A high-control tank slightly lowers everyone else's expected interrupts (it soaks casts).
--   * If you're the lone interrupter/dispeller, your expectation rises slightly.
--   * The final modifier is clamped to Config.composition.min..max (0.85..1.15) - comp nudges, never
--     dominates.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Comp = {}
Scoring.Composition = Comp

local Cap = Scoring.Capability
local Cfg = Scoring.Config

-- Build a GroupCapabilitySummary from normalized players (or raw party members with specID+role).
function Comp.Summarize(players)
    local sum = {
        interruptCapable = 0, longCd = 0, standard = 0, shortCd = 0, highControl = 0, noInterrupt = 0,
        dispelDefensive = { magic = 0, curse = 0, poison = 0, disease = 0 },
        dispelOffensive = 0, dispellersByProfile = { LIMITED = 0, STANDARD = 0, HIGH_UTILITY = 0, NONE = 0 },
        -- Throughput share denominators: sum of each metric's expected-share across the group, so a
        -- player's group-relative baseline is groupTotal(metric) * theirShare / share<Metric>.
        shareDPS = 0, shareHPS = 0,
        members = {},
    }
    -- Pre-pass: detect support/buff DPS (Augmentation) so DPS shares can be reshaped (aug down,
    -- teammates up). Stored on the summary so the per-player baseline uses the SAME adjusted shares.
    local A = Cfg.throughput.augmentation
    local augCount, nDPS = 0, 0
    for _, p in ipairs(players or {}) do
        if p.role == "DAMAGER" then
            nDPS = nDPS + 1
            if A and A.specs[p.specID] then augCount = augCount + 1 end
        end
    end
    sum.augAdjust = (augCount > 0) and { count = augCount, nNonAugDPS = nDPS - augCount } or nil

    for _, p in ipairs(players or {}) do
        local prof = Cap.Get(p.specID, p.role)
        sum.shareDPS = sum.shareDPS + Cfg.ThroughputShare("dps", p.role, p.specID, sum.augAdjust)
        sum.shareHPS = sum.shareHPS + Cfg.ThroughputShare("hps", p.role, p.specID, sum.augAdjust)
        local ip = (prof.interrupt and prof.interrupt.profile) or "NONE"
        local dp = (prof.dispel and prof.dispel.profile) or "NONE"
        local entry = { specID = p.specID, role = p.role, interruptProfile = ip, dispelProfile = dp,
                        highControl = prof.highControl and true or false, guid = p.playerGUID }
        sum.members[#sum.members + 1] = entry
        if ip == "NONE" then sum.noInterrupt = sum.noInterrupt + 1
        else
            sum.interruptCapable = sum.interruptCapable + 1
            if ip == "LONG_CD" then sum.longCd = sum.longCd + 1
            elseif ip == "STANDARD" then sum.standard = sum.standard + 1
            elseif ip == "SHORT_CD" then sum.shortCd = sum.shortCd + 1
            elseif ip == "HIGH_CONTROL" then sum.highControl = sum.highControl + 1 end
        end
        sum.dispellersByProfile[dp] = (sum.dispellersByProfile[dp] or 0) + 1
        local dd = prof.dispel and prof.dispel.defensive
        if dd then for t in pairs(dd) do if sum.dispelDefensive[t] ~= nil then sum.dispelDefensive[t] = sum.dispelDefensive[t] + 1 end end end
        if prof.dispel and prof.dispel.offensive and prof.dispel.offensive.magic then sum.dispelOffensive = sum.dispelOffensive + 1 end
    end
    return sum
end

-- (The bounded per-player interrupt/dispel composition MODIFIERS were retired in v22 - group workload
-- is distributed by Distribute.lua now. Comp.Summarize above stays; it feeds Distribute + the review.)
