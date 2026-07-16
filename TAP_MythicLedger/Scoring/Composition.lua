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
    for _, p in ipairs(players or {}) do
        local prof = Cap.Get(p.specID, p.role)
        sum.shareDPS = sum.shareDPS + Cfg.ThroughputShare("dps", p.role, p.specID)
        sum.shareHPS = sum.shareHPS + Cfg.ThroughputShare("hps", p.role, p.specID)
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

-- Interrupt expectation modifier for ONE player, given the group summary. Bounded, explainable.
-- Returns modifier, detailTable.
function Comp.InterruptModifier(player, summary)
    local c = Cfg.composition.interrupt
    local prof = Cap.Get(player.specID, player.role)
    local mine = (prof.interrupt and prof.interrupt.profile) or "NONE"
    local detail = { base = c.base, factors = {} }
    local mod = c.base
    if mine == "NONE" then return 1.0, { note = "not applicable" } end

    -- OTHER interrupt-capable players (excludes me). More competition -> each of us expected slightly less.
    local others = summary.interruptCapable - 1
    if others > 0 then
        local d = others * c.perExtraInterrupter
        mod = mod + d; detail.factors[#detail.factors + 1] = { name = others .. " other interrupter(s)", delta = d }
    elseif others <= 0 then
        mod = mod + c.loneInterrupterBonus
        detail.factors[#detail.factors + 1] = { name = "lone interrupter", delta = c.loneInterrupterBonus }
    end
    -- OTHER short-cd / high-control kickers add a bit more competition.
    local aggressive = summary.shortCd + summary.highControl
    if mine == "SHORT_CD" or mine == "HIGH_CONTROL" then aggressive = aggressive - 1 end
    if aggressive > 0 then
        local d = aggressive * c.perShortCdInterrupter
        mod = mod + d; detail.factors[#detail.factors + 1] = { name = aggressive .. " short-CD/high-control kicker(s)", delta = d }
    end
    -- A high-control tank soaks casts (only counts OTHER players' high control).
    local hcTanks = summary.highControl
    if prof.highControl then hcTanks = hcTanks - 1 end
    if hcTanks > 0 then
        local d = hcTanks * c.perHighControlTank
        mod = mod + d; detail.factors[#detail.factors + 1] = { name = hcTanks .. " high-control teammate(s)", delta = d }
    end

    mod = Cfg.clamp(mod, Cfg.composition.min, Cfg.composition.max)
    detail.final = mod
    return mod, detail
end

-- Dispel expectation modifier for ONE player. Same bounded philosophy.
function Comp.DispelModifier(player, summary)
    local c = Cfg.composition.dispel
    local prof = Cap.Get(player.specID, player.role)
    local mine = (prof.dispel and prof.dispel.profile) or "NONE"
    if mine == "NONE" then return 1.0, { note = "not applicable" } end
    local detail = { base = c.base, factors = {} }
    local mod = c.base
    -- Others who can meaningfully dispel (STANDARD/HIGH_UTILITY) reduce competition-adjusted expectation.
    local strong = (summary.dispellersByProfile.STANDARD or 0) + (summary.dispellersByProfile.HIGH_UTILITY or 0)
    if mine == "STANDARD" or mine == "HIGH_UTILITY" then strong = strong - 1 end
    if strong > 0 then
        local d = strong * c.perExtraDispeller
        mod = mod + d; detail.factors[#detail.factors + 1] = { name = strong .. " other strong dispeller(s)", delta = d }
    elseif strong <= 0 and (mine == "STANDARD" or mine == "HIGH_UTILITY") then
        mod = mod + c.loneDispellerBonus
        detail.factors[#detail.factors + 1] = { name = "lone strong dispeller", delta = c.loneDispellerBonus }
    end
    mod = Cfg.clamp(mod, Cfg.composition.min, Cfg.composition.max)
    detail.final = mod
    return mod, detail
end
