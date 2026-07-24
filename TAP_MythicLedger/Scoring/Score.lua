-- TAP: Mythic Ledger - Scoring/Score.lua
-- Assembles the per-category results into an auditable PlayerScore: resolves weights (with
-- redistribution), computes the weighted overall, assigns a grade, and generates plain-language
-- explanation text. Every score carries its version, raw inputs, expected values, modifiers,
-- confidence and final weights so it can be re-explained or recalculated later.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Score = {}
Scoring.Score = Score

local Cfg  = Scoring.Config
local Cap  = Scoring.Capability
local Norm = Scoring.Normalize
local Comp = Scoring.Composition
local Base = Scoring.Baselines
local Cat  = Scoring.Categories
local Weights = Scoring.Weights

function Score.Grade(overall)
    for _, g in ipairs(Cfg.grades) do if overall >= g.min then return g.grade end end
    return "F"
end

local function round(v) return math.floor((v or 0) + 0.5) end
local function pct(v) return round((v or 0) * 100) end

-- Score a single normalized player. `summary` = group capability summary (also carries the throughput
-- share denominators); `groupTotals` = { interrupts, dispels, dps, hps } summed across the party.
-- `dist` (optional) = { interrupt = <this player's distributed kick expected or nil>, dispel = <...> }
-- from Distribute over the whole party; when present it supersedes the standalone interrupt/dispel target.
function Score.ScoreNormalized(norm, summary, groupTotals, dist, healModel, runCtx)
    groupTotals = groupTotals or {}
    local role = norm.role or "DAMAGER"
    local baseline = Base.Throughput(norm, summary, groupTotals)
    local healReq = healModel and healModel.byGuid and healModel.byGuid[norm.playerGUID]

    local cats = {}
    cats.throughput = Cat.Throughput(norm, baseline, healReq, runCtx)
    cats.interrupts = Cat.Interrupt(norm, summary, groupTotals.interrupts, dist and dist.interrupt)
    cats.dispels    = Cat.Dispel(norm, summary, groupTotals.dispels, dist and dist.dispel)
    cats.survival   = Cat.Survival(norm, runCtx)
    cats.deaths     = Cat.Deaths(norm)

    -- Tank threat deaths: how many teammate deaths came from a mob that wasn't tanked (a "threat" death =
    -- a non-tank killed by melee after losing/never having aggro). As of v45 these DOCK the tank's
    -- Survival score (Cat.Survival, via runCtx.partyThreatDeaths); we still stash the count on the Deaths
    -- card so the review can show it in context. (The healer outcome floor lives in Cat.Throughput.)
    if role == "TANK" and runCtx and (runCtx.partyThreatDeaths or 0) > 0 and cats.deaths then
        cats.deaths.groupLooseThreatDeaths = runCtx.partyThreatDeaths
    end

    local applicable = { interrupts = cats.interrupts.applicable, dispels = cats.dispels.applicable }
    local weights, redistLog = Weights.Resolve(role, applicable)

    -- Weighted overall over applicable categories (redistributed weights are already 0 for N/A ones).
    local overall, wsum = 0, 0
    for _, c in ipairs(Weights.CATS) do
        local res = cats[c]
        local wgt = weights[c] or 0
        if res and res.applicable and wgt > 0 then
            overall = overall + wgt * math.min(res.score or 0, 100)
            wsum = wsum + wgt
        end
    end
    if wsum > 0 then overall = overall / wsum end   -- guard: if any applicable weight was lost, renormalize
    overall = Cfg.clamp(overall, 0, 100)
    local grade = Score.Grade(overall)

    -- Attach final weights onto each category for the UI.
    for _, c in ipairs(Weights.CATS) do if cats[c] then cats[c].weight = weights[c] or 0 end end

    local score = {
        version = Cfg.version,
        playerGUID = norm.playerGUID, name = norm.name, role = role, specID = norm.specID,
        classFile = norm.classFile,
        overall = round(overall), overallExact = overall, grade = grade,
        categories = cats, weights = weights, redistribution = redistLog,
        baseline = baseline, dataCompleteness = norm.dataCompleteness, dataSource = norm.dataSource,
        inputs = {
            durationSeconds = norm.durationSeconds, dps = norm.dps, hps = norm.hps,
            damageDone = norm.damageDone, healing = norm.healing, damageTaken = norm.damageTaken,
            avoidableDamageTaken = norm.avoidableDamageTaken, interrupts = norm.interrupts,
            dispels = norm.dispels, deaths = norm.deaths,
        },
    }
    score.explanation = Score.Explain(score)
    return score
end

----------------------------------------------------------------------
-- Explanation. short = one line; details = per-category human sentences (auditable, no mystery).
----------------------------------------------------------------------
function Score.Explain(score)
    local cats = score.categories
    local d = {}

    -- Throughput (group-relative blend of a DPS and/or HPS component).
    local t = cats.throughput
    if t then
        local det = t.detail
        local segs = {}
        if det and det.dps then
            segs[#segs + 1] = string.format("DPS %s vs %s expected (%.2fx)",
                Scoring._short(det.dps.value), Scoring._short(det.dps.expected), det.dps.ratio or 0)
            if det.dps.ilvlFactor and math.abs(det.dps.ilvlFactor - 1) > 0.001 then
                segs[#segs] = segs[#segs] .. string.format(" [ilvl x%.2f vs group]", det.dps.ilvlFactor)
            end
        end
        if det and det.hps then
            if det.hps.requirementModel then
                segs[#segs + 1] = string.format("Healing %s vs %s required (%.2fx)",
                    Scoring._short(det.hps.value), Scoring._short(det.hps.expected), det.hps.ratio or 0)
            else
                segs[#segs + 1] = string.format("HPS %s vs %s expected (%.2fx)",
                    Scoring._short(det.hps.value), Scoring._short(det.hps.expected), det.hps.ratio or 0)
            end
        end
        if #segs > 0 then
            d[#d + 1] = string.format("Throughput: %d  (%s; group-relative; weight %d%%)",
                round(t.score), table.concat(segs, ", "), pct(t.weight))
        else
            d[#d + 1] = string.format("Throughput: %d  (%s)", round(t.score), t.note or "estimate")
        end
        if det and det.hps and det.hps.outcomeFloorRaw then
            d[#d] = d[#d] .. string.format("  Healing lifted from %d toward full marks - you timed the key with few/no deaths, so your healing was enough by definition.", round(det.hps.outcomeFloorRaw))
        end
    end

    -- Interrupts
    local i = cats.interrupts
    if i and not i.applicable then
        d[#d + 1] = "Interrupt Contribution: N/A  (" .. (i.reason or "not applicable")
            .. ") Its weight was redistributed."
    elseif i then
        if i.actual == nil then
            d[#d + 1] = string.format("Interrupt Contribution: %d  (%s)", round(i.score), i.note or "no data")
        else
            d[#d + 1] = string.format(
                "Interrupt Contribution: %d  (actual %d vs expected %.1f; profile %s; fair share %.0f%% of ~%.0f-kick supply; confidence %d%%; weight %d%%)",
                round(i.score), i.actual, i.expected or 0, i.profile or "?", (i.share or 0) * 100, i.supply or 0,
                pct(i.confidence), pct(i.weight))
            if i.missedLifeSavingKick then
                d[#d] = d[#d] .. "  You landed no interrupts and a teammate died to a kickable cast - pressing your interrupt could have prevented it."
            end
        end
    end

    -- Dispels
    local dp = cats.dispels
    if dp and not dp.applicable then
        d[#d + 1] = "Dispel Contribution: N/A  (" .. (dp.reason or "not applicable") .. ") Its weight was redistributed."
    elseif dp then
        if dp.actual == nil then
            d[#d + 1] = string.format("Dispel Contribution: %d  (%s)", round(dp.score), dp.note or "no data")
        else
            d[#d + 1] = string.format(
                "Dispel Contribution: %d  (actual %d vs expected %.1f; profile %s; confidence %d%%; weight %d%%)",
                round(dp.score), dp.actual, dp.expected or 0, dp.profile or "?", pct(dp.confidence), pct(dp.weight))
        end
    end

    -- Survival
    local s = cats.survival
    if s then
        if s.detail and s.detail.avoidableShare then
            d[#d + 1] = string.format("Survival: %d  (%.1f%% of damage taken was avoidable; weight %d%%)",
                round(s.score), (s.detail.avoidableShare or 0) * 100, pct(s.weight))
        else
            d[#d + 1] = string.format("Survival: %d  (%s; weight %d%%)", round(s.score), s.note or "estimate", pct(s.weight))
        end
    end

    -- Deaths
    local de = cats.deaths
    if de then
        if de.deaths == nil then
            d[#d + 1] = string.format("Death Impact: %d  (%s)", round(de.score), de.note or "no data")
        else
            d[#d + 1] = string.format("Death Impact: %d  (%d death(s), -%d penalty; weight %d%%)",
                round(de.score), de.deaths, de.penalty, pct(de.weight))
        end
        -- Tank threat deaths (v45): teammate deaths from a mob that wasn't tanked now DOCK Survival.
        if score.role == "TANK" and (de.groupLooseThreatDeaths or 0) > 0 then
            d[#d + 1] = string.format("Loose-mob deaths: %d teammate death(s) came from a mob you lost or never had threat on - these dock your Survival (the first each run is forgiven).",
                de.groupLooseThreatDeaths)
        end
    end

    local short = string.format("%s (%d)", score.grade, score.overall)
    return { short = short, details = d }
end

-- Compact number formatter for explanations (independent of the Util module so scoring stays standalone).
function Scoring._short(n)
    if type(n) ~= "number" then return "-" end
    local a = math.abs(n)
    if a >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if a >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return string.format("%d", round(n))
end

-- Run-level context shared by every player's score (v40): the run outcome + party deaths (for the healer
-- outcome floor) and the group's AVERAGE item level + how much of the party we could read it for (for the
-- throughput ilvl adjustment). groupAvgIlvl includes every member with a known ilvl (the player too).
function Score.RunContext(players, run)
    local partyDeaths, ilvlSum, ilvlN, n = 0, 0, 0, 0
    for _, p in ipairs(players or {}) do
        n = n + 1
        if type(p.deaths) == "number" then partyDeaths = partyDeaths + p.deaths end
        if type(p.itemLevel) == "number" then ilvlSum = ilvlSum + p.itemLevel; ilvlN = ilvlN + 1 end
    end
    local partyThreatDeaths = 0
    for _, p in ipairs(players or {}) do
        local dc = p.deathCauses
        if type(dc) == "table" and type(dc.threat) == "number" then partyThreatDeaths = partyThreatDeaths + dc.threat end
    end
    return {
        onTime = run and run.onTime and true or false,
        partyDeaths = partyDeaths,
        partyThreatDeaths = partyThreatDeaths,   -- teammate deaths from loose/lost threat (tank awareness)
        groupAvgIlvl = (ilvlN > 0) and (ilvlSum / ilvlN) or nil,
        ilvlCoverage = (n > 0) and (ilvlN / n) or 0,
    }
end

----------------------------------------------------------------------
-- Public: score an entire run. Returns { list = {score,...}, byGuid = {guid=score}, summary }.
----------------------------------------------------------------------
function Score.ScoreRun(run)
    if not run then return nil end
    local players = Norm.Party(run)
    local summary = Comp.Summarize(players)
    local groupTotals = { interrupts = 0, dispels = 0, dps = 0, hps = 0 }
    for _, p in ipairs(players) do
        if p.interrupts then groupTotals.interrupts = groupTotals.interrupts + p.interrupts end
        if p.dispels then groupTotals.dispels = groupTotals.dispels + p.dispels end
        if p.dps then groupTotals.dps = groupTotals.dps + p.dps end
        if p.hps then groupTotals.hps = groupTotals.hps + p.hps end
    end
    -- Cap each player's dps/hps contribution to the baseline at their share (over-DPSing your share
    -- shouldn't raise the bar for the team or dilute your own ratio - see Baselines.EffectiveGroupTotals).
    groupTotals = Base.EffectiveGroupTotals(players, summary, groupTotals)
    -- Distribute the interrupt/dispel workload fairly across the party (supply -> capability share ->
    -- sniping redistribution), so each player is scored against a fair share, not a flat solo estimate.
    local kickDist = Scoring.Distribute.Interrupts(players, run)
    local dispelDist = Scoring.Distribute.Dispels(players, run)
    local healModel = Scoring.Healing and Scoring.Healing.Compute(players)
    local runCtx = Score.RunContext(players, run)
    local out = { list = {}, byGuid = {}, summary = summary, version = Cfg.version }
    for _, p in ipairs(players) do
        local dist = { interrupt = kickDist[p.playerGUID], dispel = dispelDist[p.playerGUID] }
        local sc = Score.ScoreNormalized(p, summary, groupTotals, dist, healModel, runCtx)
        out.list[#out.list + 1] = sc
        if sc.playerGUID then out.byGuid[sc.playerGUID] = sc end
    end
    return out
end

-- Convenience: score just the local player (the runner) of a run.
function Score.ScorePlayer(run)
    for _, m in ipairs(run and run.party or {}) do
        if m.isPlayer then
            local players = Norm.Party(run)
            local summary = Comp.Summarize(players)
            local totals = { interrupts = 0, dispels = 0, dps = 0, hps = 0 }
            for _, p in ipairs(players) do
                if p.interrupts then totals.interrupts = totals.interrupts + p.interrupts end
                if p.dispels then totals.dispels = totals.dispels + p.dispels end
                if p.dps then totals.dps = totals.dps + p.dps end
                if p.hps then totals.hps = totals.hps + p.hps end
            end
            totals = Base.EffectiveGroupTotals(players, summary, totals)
            local kickDist = Scoring.Distribute.Interrupts(players, run)
            local dispelDist = Scoring.Distribute.Dispels(players, run)
            local healModel = Scoring.Healing and Scoring.Healing.Compute(players)
            local runCtx = Score.RunContext(players, run)
            local pn = Norm.Player(run, m)
            local dist = { interrupt = kickDist[pn.playerGUID], dispel = dispelDist[pn.playerGUID] }
            return Score.ScoreNormalized(pn, summary, totals, dist, healModel, runCtx)
        end
    end
    return nil
end

-- Run config validation at load (logs any weight-sum mistakes).
if Cfg.Validate then Cfg.Validate() end
