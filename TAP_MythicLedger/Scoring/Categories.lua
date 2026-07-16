-- TAP: Mythic Ledger - Scoring/Categories.lua
-- The per-category scorers. Each returns a self-describing result: score (0..100), applicable,
-- confidence, and the raw inputs/expected values that produced it, so the UI can explain every
-- number. None of these compare a player to teammates - only to spec-aware expectations/baselines.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Cat = {}
Scoring.Categories = Cat

local Cfg  = Scoring.Config
local Cap  = Scoring.Capability
local Comp = Scoring.Composition
local Base = Scoring.Baselines

-- Contribution curve (shared interrupts/dispels): ratio -> raw score (0..maxInternal).
local function curveScore(ratio)
    local c = Cfg.contributionCurve
    local s = Cfg.interp(c.points, ratio, "ratio", "score")
    return Cfg.clamp(s, 0, c.maxInternal)
end

-- Blend a computed score toward a neutral score by confidence in [0,1].
local function blendConfidence(score, neutral, confidence)
    return neutral + (score - neutral) * Cfg.clamp(confidence, 0, 1)
end

----------------------------------------------------------------------
-- Interrupt contribution. Expected = minutes * specRate * compModifier. Never accuracy/responsibility.
-- groupInterruptTotal (sum of available party interrupts) drives confidence (low sample -> neutral).
----------------------------------------------------------------------
function Cat.Interrupt(norm, summary, groupInterruptTotal)
    local prof = Cap.Get(norm.specID, norm.role)
    local profileKey = (prof.interrupt and prof.interrupt.profile) or "NONE"
    local pcfg = Cfg.interruptProfiles[profileKey] or Cfg.interruptProfiles.NONE

    if not pcfg.scoreEligible then
        return { applicable = false, profile = profileKey,
                 reason = "This specialization has no conventional interrupt.",
                 interrupt = prof.interrupt }
    end

    local minutes = (norm.durationSeconds or 0) / 60
    -- Per-spec expected kicks/minute from this spec's real availability (CD + rotational extra stops),
    -- not a flat per-profile number. Fall back to the coarse profile rate only if there's no CD data.
    local rate, availPerMin = Cfg.InterruptRatePerMinute(prof.interrupt)
    if not rate or rate <= 0 then rate = pcfg.ratePerMinute end
    -- Names of the extra stops that contributed to the rate (for the "how targets were set" explanation).
    local extras
    for _, stop in ipairs((prof.interrupt and prof.interrupt.additionalStops) or {}) do
        if Cfg.interrupt.countedStopTypes[stop.stopType] then extras = (extras and (extras .. ", ") or "") .. (stop.spellName or "?") end
    end
    local irSpell = prof.interrupt and prof.interrupt.spellName
    local irCD = prof.interrupt and prof.interrupt.cooldownSeconds
    local compMod, compDetail = Comp.InterruptModifier(norm, summary)
    local expected = minutes * rate * compMod
    local cconf = Cfg.confidence.interrupt
    local neutral = cconf.neutralScore

    -- No interrupt data recorded for this player -> can't grade; sit at neutral, confidence 0.
    if norm.interrupts == nil then
        return { applicable = true, profile = profileKey, score = neutral, rawScore = neutral,
                 confidence = 0, expected = expected, actual = nil, compModifier = compMod,
                 compDetail = compDetail, minutes = minutes, rate = rate, availPerMin = availPerMin,
                 interruptSpell = irSpell, interruptCD = irCD, interruptExtras = extras,
                 note = "No interrupt data was recorded for this player." }
    end

    local actual = norm.interrupts
    local ratio = (expected > 0) and (actual / expected) or (actual > 0 and 2.0 or 0)
    local raw = curveScore(ratio)
    local capped = math.min(raw, Cfg.contributionCurve.categoryCap)

    -- Confidence: enough total interrupts in the run to trust the comparison?
    local confidence = Cfg.clamp((groupInterruptTotal or 0) / cconf.minGroupSample, 0, 1)
    local final = blendConfidence(capped, neutral, confidence)

    return { applicable = true, profile = profileKey, score = final, rawScore = raw, cappedScore = capped,
             confidence = confidence, expected = expected, actual = actual, ratio = ratio,
             compModifier = compMod, compDetail = compDetail, minutes = minutes, rate = rate,
             availPerMin = availPerMin, interruptSpell = irSpell, interruptCD = irCD, interruptExtras = extras,
             neutral = neutral, groupTotal = groupInterruptTotal }
end

----------------------------------------------------------------------
-- Dispel contribution. Same shape, dispel profile/rate/neutral.
----------------------------------------------------------------------
function Cat.Dispel(norm, summary, groupDispelTotal)
    local prof = Cap.Get(norm.specID, norm.role)
    local profileKey = (prof.dispel and prof.dispel.profile) or "NONE"
    local pcfg = Cfg.dispelProfiles[profileKey] or Cfg.dispelProfiles.NONE

    if not pcfg.scoreEligible then
        return { applicable = false, profile = profileKey,
                 reason = "This specialization has no relevant dispel capability.",
                 dispel = prof.dispel }
    end

    -- Dungeon dispel-type gate: if NOTHING this spec's dispel can touch appears in this dungeon, don't
    -- expect dispels at all (N/A, weight redistributed) rather than punishing a gated tool with no
    -- valid target. Unknown dungeon = eligible (never restrict); see Config.dungeonDispelTypes.
    if not Cfg.DungeonDispelEligible(norm.dungeonName, Cfg.DispelTypeSet(prof.dispel)) then
        return { applicable = false, profile = profileKey, dungeonGated = true,
                 reason = "This dungeon has no debuffs this spec can dispel.",
                 dispel = prof.dispel }
    end

    local minutes = (norm.durationSeconds or 0) / 60
    local rate = pcfg.ratePerMinute
    local compMod, compDetail = Comp.DispelModifier(norm, summary)
    -- Dungeon dispel DEMAND: scale expected by how dispel-heavy THIS dungeon is for the types this spec
    -- can address (max weight among its present types; 1.0 when unlisted). Magic-heavy dungeons expect
    -- more dispels, light ones fewer - so a quiet run in Skyreach isn't judged against a Magisters load.
    local demand = Cfg.DungeonDispelDemand(norm.dungeonName, Cfg.DispelTypeSet(prof.dispel))
    local expected = minutes * rate * compMod * demand
    local cconf = Cfg.confidence.dispel
    local neutral = cconf.neutralScore

    if norm.dispels == nil then
        return { applicable = true, profile = profileKey, score = neutral, rawScore = neutral,
                 confidence = 0, expected = expected, actual = nil, compModifier = compMod,
                 compDetail = compDetail, minutes = minutes, rate = rate, demand = demand,
                 note = "No dispel data was recorded for this player." }
    end

    local actual = norm.dispels
    local ratio = (expected > 0) and (actual / expected) or (actual > 0 and 2.0 or 0)
    local raw = curveScore(ratio)
    local capped = math.min(raw, Cfg.contributionCurve.categoryCap)
    local confidence = Cfg.clamp((groupDispelTotal or 0) / cconf.minGroupSample, 0, 1)
    local final = blendConfidence(capped, neutral, confidence)

    return { applicable = true, profile = profileKey, score = final, rawScore = raw, cappedScore = capped,
             confidence = confidence, expected = expected, actual = actual, ratio = ratio,
             compModifier = compMod, compDetail = compDetail, minutes = minutes, rate = rate,
             demand = demand, neutral = neutral, groupTotal = groupDispelTotal }
end

----------------------------------------------------------------------
-- Throughput. GROUP-RELATIVE and role-aware: a weighted blend of a DPS component and an HPS component
-- (see baseline.mix). DPS-only for damagers; mostly-HPS for healers; a spec-scaled DPS+HPS blend for
-- tanks (healy tanks lean more on HPS). Each component compares the player's value to their expected
-- group share via the throughput curve. Healer/tank HPS is soft-capped (excess healing usually means
-- avoidable damage taken, which is penalized under Survival, not rewarded here).
----------------------------------------------------------------------
local function componentScore(value, expected, role, isHeal)
    if value == nil or not expected or expected <= 0 then return nil, nil end
    local ratio = value / expected
    -- Soft-cap overshoot on healing for tanks/healers so padding doesn't inflate the score.
    if isHeal and (role == "HEALER" or role == "TANK") then
        local sc = Cfg.throughput.healerSoftCapRatio
        if ratio > sc then ratio = sc + (ratio - sc) * 0.30 end
    end
    local s = Cfg.clamp(Cfg.interp(Cfg.throughput.curve, ratio, "ratio", "score"), 0, 100)
    return s, ratio
end

function Cat.Throughput(norm, baseline)
    baseline = baseline or Base.Throughput(norm)
    local role = norm.role or "DAMAGER"
    local mix = baseline.mix or Cfg.ThroughputMix(role, norm.specID)

    local parts, wsum = 0, 0
    local detail = {}

    if (mix.dps or 0) > 0 then
        local s, r = componentScore(norm.dps, baseline.dps, role, false)
        if s then
            parts = parts + s * mix.dps; wsum = wsum + mix.dps
            detail.dps = { value = norm.dps, expected = baseline.dps, ratio = r, score = s, weight = mix.dps }
        end
    end
    if (mix.hps or 0) > 0 then
        local s, r = componentScore(norm.hps, baseline.hps, role, true)
        if s then
            parts = parts + s * mix.hps; wsum = wsum + mix.hps
            detail.hps = { value = norm.hps, expected = baseline.hps, ratio = r, score = s, weight = mix.hps }
        end
    end

    -- No usable throughput data (nothing recorded, or the group produced no total to compare to).
    if wsum == 0 then
        return { applicable = true, score = 70, confidence = 0, mix = mix, source = baseline.source,
                 detail = detail, groupRelative = true,
                 note = "No throughput data was recorded; using a neutral estimate." }
    end

    -- Confidence: we trust group-relative comparisons; a solo/partial group (missing one metric) is a
    -- touch less certain than a full blend.
    local confidence = (wsum >= 0.99) and 0.85 or 0.7
    return { applicable = true, score = parts / wsum, confidence = confidence, mix = mix,
             source = baseline.source, detail = detail, groupRelative = true }
end

----------------------------------------------------------------------
-- Survival. Scored purely on the AVOIDABLE SHARE of total damage taken (avoidable / taken): scale-free,
-- role-agnostic. 2.5% grace = 100, dropping fast to 0 at a 25% share. Missing either input -> neutral.
----------------------------------------------------------------------
function Cat.Survival(norm)
    local taken = norm.damageTaken
    if norm.avoidableDamageTaken == nil or not taken or taken <= 0 then
        return { applicable = true, score = Cfg.survival.neutralScore, confidence = 0,
                 note = "No avoidable-damage data was recorded; using a neutral estimate.", detail = {} }
    end
    local share = norm.avoidableDamageTaken / taken
    local s = Cfg.clamp(Cfg.interp(Cfg.survival.avoidableShareCurve, share, "v", "s"), 0, 100)
    return { applicable = true, score = s, confidence = 0.7,
             detail = { avoidableShare = share, shareScore = s } }
end

----------------------------------------------------------------------
-- Death Impact (NOT responsibility). Escalating, capped penalty. Missing data -> neutral, not zero.
----------------------------------------------------------------------
function Cat.Deaths(norm)
    local d = norm.deaths
    if d == nil then
        return { applicable = true, score = Cfg.deaths.baseScore, deaths = nil, penalty = 0, confidence = 0,
                 note = "No death data was recorded." }
    end
    local pen, steps = 0, Cfg.deaths.penalties
    for i = 1, d do
        pen = pen + (steps[i] or Cfg.deaths.perExtra)
        if pen >= Cfg.deaths.maxPenalty then pen = Cfg.deaths.maxPenalty; break end
    end
    return { applicable = true, score = Cfg.deaths.baseScore - pen, deaths = d, penalty = pen, confidence = 1 }
end

----------------------------------------------------------------------
-- Role contribution. A small, honest composite of survival + utility execution (not new data). Only
-- meaningfully weighted for tanks/healers; DPS weight is 0. Kept low-impact and clearly derived.
----------------------------------------------------------------------
function Cat.RoleContribution(norm, cats)
    local vals = {}
    if cats.survival and cats.survival.applicable then vals[#vals + 1] = math.min(cats.survival.score, 100) end
    if cats.interrupts and cats.interrupts.applicable and cats.interrupts.actual ~= nil then vals[#vals + 1] = math.min(cats.interrupts.score, 100) end
    if cats.dispels and cats.dispels.applicable and cats.dispels.actual ~= nil then vals[#vals + 1] = math.min(cats.dispels.score, 100) end
    if #vals == 0 then return { applicable = true, score = 75, confidence = 0, derived = true } end
    local s = 0; for _, v in ipairs(vals) do s = s + v end
    return { applicable = true, score = s / #vals, confidence = 0.5, derived = true, from = #vals }
end
