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
local Base = Scoring.Baselines

-- Contribution curve (shared interrupts/dispels): ratio -> raw score (0..maxInternal).
local function curveScore(ratio)
    local c = Cfg.contributionCurve
    local s = Cfg.interp(c.points, ratio, "ratio", "score")
    return Cfg.clamp(s, 0, c.maxInternal)
end

----------------------------------------------------------------------
-- Interrupt contribution. Expected is the player's fair share of the RUN'S KICK SUPPLY, computed once at
-- the run level (Scoring/Distribute.lua): season kick frequency (trash + killed bosses) capped by group
-- capacity, split by interrupt cooldown, with sniping redistribution. This scorer just compares actual vs
-- that expected. groupInterruptTotal (sum of available party interrupts) is surfaced as sample context.
----------------------------------------------------------------------
function Cat.Interrupt(norm, summary, groupInterruptTotal, distExpected)
    local prof = Cap.Get(norm.specID, norm.role)
    local profileKey = (prof.interrupt and prof.interrupt.profile) or "NONE"
    local pcfg = Cfg.interruptProfiles[profileKey] or Cfg.interruptProfiles.NONE

    if not pcfg.scoreEligible then
        return { applicable = false, profile = profileKey,
                 reason = "This specialization has no conventional interrupt.",
                 interrupt = prof.interrupt }
    end

    -- Capability gate (talent/pet-gated interrupts only - e.g. Warlock Spell Lock via the Felhunter):
    -- only expect a kick when we have EVIDENCE the player could do it - live inspection confirmed it
    -- (norm.interruptTalent == true) OR they actually landed at least one interrupt this run (pet kicks
    -- are attributed to the owner). Otherwise we DON'T dock them for a tool their pet/talent may not
    -- provide: N/A, weight redistributed. Baseline interrupts skip this and are always expected.
    if prof.interrupt and prof.interrupt.talentDependent then
        local didKick = (type(norm.interrupts) == "number" and norm.interrupts >= 1)
        if norm.interruptTalent ~= true and not didKick then
            local ability = (prof.interrupt and prof.interrupt.spellName) or "an interrupt"
            return { applicable = false, profile = profileKey, capabilityGated = true,
                     talentMissing = (norm.interruptTalent == false), interrupt = prof.interrupt,
                     reason = (norm.interruptTalent == false)
                         and ("Could bring " .. ability .. " but didn't - no interrupt expected here.")
                         or ("Interrupt not scored: couldn't confirm " .. ability .. " was available (pet/talent).") }
        end
    end

    -- Kit description for the "how targets were set" explanation (spell + CD + counted extra stops).
    local irSpell = prof.interrupt and prof.interrupt.spellName
    local irCD    = prof.interrupt and prof.interrupt.cooldownSeconds
    local extras
    for _, stop in ipairs((prof.interrupt and prof.interrupt.additionalStops) or {}) do
        if Cfg.interrupt.countedStopTypes[stop.stopType] then extras = (extras and (extras .. ", ") or "") .. (stop.spellName or "?") end
    end
    local cconf = Cfg.confidence.interrupt
    local neutral = cconf.neutralScore

    -- Expected comes ENTIRELY from the run-level group distribution. No distribution (a standalone call
    -- with no run context, or a dungeon we have no season profile for) -> no fair target exists, so we
    -- don't grade utility: N/A, weight redistributed (never a zero for missing model).
    if not (distExpected and type(distExpected.expected) == "number") then
        return { applicable = false, profile = profileKey, noModel = true, interrupt = prof.interrupt,
                 interruptSpell = irSpell, interruptCD = irCD, interruptExtras = extras,
                 reason = "No interrupt expectation could be computed for this run." }
    end
    -- A share redistributed to ~nothing means teammates covered the kicks here - N/A, not a zero.
    if distExpected.expected < 0.5 then
        return { applicable = false, profile = profileKey, coveredByTeam = true, interrupt = prof.interrupt,
                 interruptSpell = irSpell, interruptCD = irCD, interruptExtras = extras,
                 reason = "Teammates covered the interrupts here - no fair share fell to you." }
    end
    local expected = distExpected.expected
    local share, supply = distExpected.share, distExpected.supply

    -- No interrupt data recorded for this player -> can't grade; sit at neutral, confidence 0.
    if norm.interrupts == nil then
        return { applicable = true, profile = profileKey, score = neutral, rawScore = neutral,
                 confidence = 0, expected = expected, actual = nil, share = share, supply = supply,
                 interruptSpell = irSpell, interruptCD = irCD, interruptExtras = extras,
                 note = "No interrupt data was recorded for this player." }
    end

    local actual = norm.interrupts
    local ratio = (expected > 0) and (actual / expected) or (actual > 0 and 2.0 or 0)
    local raw = curveScore(ratio)
    local capped = math.min(raw, Cfg.contributionCurve.categoryCap)

    -- Confidence is NOT applied to interrupts: the group-distributed target is accurate (boss-time is
    -- implicit in the season supply), so a genuine 0 stays a 0. Surfaced purely as sample context.
    local confidence = Cfg.clamp((groupInterruptTotal or 0) / cconf.minGroupSample, 0, 1)

    return { applicable = true, profile = profileKey, score = capped, rawScore = raw, cappedScore = capped,
             confidence = confidence, confidenceApplied = false, expected = expected, actual = actual, ratio = ratio,
             share = share, supply = supply, capacity = distExpected.capacity,
             dungeonSupply = distExpected.dungeonSupply, groupCapacity = distExpected.groupCapacity,
             interruptSpell = irSpell, interruptCD = irCD, interruptExtras = extras,
             neutral = neutral, groupTotal = groupInterruptTotal }
end

----------------------------------------------------------------------
-- Dispel contribution. Same shape, dispel profile/rate/neutral.
----------------------------------------------------------------------
function Cat.Dispel(norm, summary, groupDispelTotal, distExpected)
    local prof = Cap.Get(norm.specID, norm.role)
    local profileKey = (prof.dispel and prof.dispel.profile) or "NONE"
    local pcfg = Cfg.dispelProfiles[profileKey] or Cfg.dispelProfiles.NONE

    if not pcfg.scoreEligible then
        return { applicable = false, profile = profileKey,
                 reason = "This specialization has no relevant dispel capability.",
                 dispel = prof.dispel }
    end

    -- Capability gate (talent-gated dispels only): a dispel that requires a talent - e.g. Hunter
    -- Tranquilizing Shot, Paladin Cleanse Toxins - only creates an expectation when we have EVIDENCE the
    -- player actually specced it: live talent inspection confirmed it (norm.dispelTalent == true) OR they
    -- recorded at least one dispel this run. Otherwise (confirmed absent, or inspection couldn't reach
    -- them) we DON'T dock them for a tool they may not have - the category is N/A, weight redistributed.
    -- Baseline dispels (healers' full cure, etc.) are always expected and skip this gate.
    if prof.dispel and prof.dispel.talentDependent then
        local didDispel = (type(norm.dispels) == "number" and norm.dispels >= 1)
        if norm.dispelTalent ~= true and not didDispel then
            local ability = prof.dispel.spellName or "a dispel"
            -- talentMissing is true ONLY when inspection confirmed the talent is absent (not merely
            -- unknown), so the UI can note "could have talented this but didn't" without overreaching.
            return { applicable = false, profile = profileKey, capabilityGated = true,
                     talentMissing = (norm.dispelTalent == false), dispel = prof.dispel,
                     reason = (norm.dispelTalent == false)
                         and ("Could talent " .. ability .. " (a dispel this spec can take) but hasn't - none expected here.")
                         or ("Dispel not scored: couldn't confirm " .. ability .. " is talented.") }
        end
    end

    -- What this spec could have dispelled/purged here (specific effects with spell ids + Dispel/Purge/
    -- Soothe action), so the run review can coach with the ability + target icons instead of "no dispels".
    local dispelTargets = Cfg.DungeonDispelTargets(norm.dungeonName, prof.dispel)
    local cconf = Cfg.confidence.dispel
    local neutral = cconf.neutralScore

    -- Expected comes ENTIRELY from the run-level group distribution: a per-SCHOOL x AXIS supply from the
    -- season profile (defensive cleanse vs offensive purge/soothe), split only among the members who can
    -- address each school, plus sniping redistribution. This is where the dual-axis fairness now lives -
    -- a purge-only spec only draws from purge/soothe supply, a cleanse-only spec only from debuff supply,
    -- so neither is penalised for work it structurally cannot do. No distribution (standalone call, or a
    -- dungeon with no season profile) -> no fair target: N/A, weight redistributed (never a zero).
    if not (distExpected and type(distExpected.expected) == "number") then
        return { applicable = false, profile = profileKey, noModel = true, dispel = prof.dispel,
                 dispelTargets = dispelTargets,
                 reason = "No dispel expectation could be computed for this run." }
    end
    -- Redistributed/allocated to ~nothing => this dungeon had nothing this spec can dispel, or teammates
    -- covered it => N/A, not a zero.
    if distExpected.expected < 0.5 then
        return { applicable = false, profile = profileKey, coveredByTeam = true, dispel = prof.dispel,
                 dispelTargets = dispelTargets,
                 reason = "No fair share of dispels here - nothing this spec could cleanse/purge, or teammates covered it." }
    end
    local expected = distExpected.expected

    if norm.dispels == nil then
        return { applicable = true, profile = profileKey, score = neutral, rawScore = neutral,
                 confidence = 0, expected = expected, actual = nil,
                 dispel = prof.dispel, dispelTargets = dispelTargets,
                 note = "No dispel data was recorded for this player." }
    end

    local actual = norm.dispels
    local ratio = (expected > 0) and (actual / expected) or (actual > 0 and 2.0 or 0)
    local raw = curveScore(ratio)
    local capped = math.min(raw, Cfg.contributionCurve.categoryCap)
    -- Confidence surfaced as sample context only; not applied - the group-distributed per-school target is
    -- accurate (boss-time implicit in the season supply), so a genuine 0 stays a 0 (matches interrupts).
    local confidence = Cfg.clamp((groupDispelTotal or 0) / cconf.minGroupSample, 0, 1)

    return { applicable = true, profile = profileKey, score = capped, rawScore = raw, cappedScore = capped,
             confidence = confidence, confidenceApplied = false, expected = expected, actual = actual, ratio = ratio,
             dispel = prof.dispel, dispelTargets = dispelTargets,
             neutral = neutral, groupTotal = groupDispelTotal }
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

function Cat.Throughput(norm, baseline, healReq)
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
        -- Tanks & healers: judge HPS against the damage-taken REQUIREMENT (healing what the encounter
        -- dealt), not a group-relative HPS share. Output includes absorbs so shield specs aren't docked.
        -- Falls back to the group-relative baseline when the model isn't applicable (missing data).
        local value, expected, model = norm.hps, baseline.hps, false
        if healReq and (healReq.requirement or 0) > 0 and healReq.output ~= nil then
            value, expected, model = healReq.output, healReq.requirement, true
        end
        local s, r = componentScore(value, expected, role, true)
        if s then
            parts = parts + s * mix.hps; wsum = wsum + mix.hps
            detail.hps = { value = value, expected = expected, ratio = r, score = s, weight = mix.hps,
                           requirementModel = model, hpsRaw = norm.hps,
                           reqDetail = model and healReq.detail or nil }
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
    local av = norm.avoidableDamageTaken
    -- A confirmed ZERO avoidable damage is a 0% share = perfect survival, regardless of total taken
    -- (0 / anything = 0). On a tracked run, "no avoidable rows" is normalized to 0 (see Normalize), so
    -- this is a confident 100, not a neutral "no data" estimate.
    if av == 0 then
        local s = Cfg.clamp(Cfg.interp(Cfg.survival.avoidableShareCurve, 0, "v", "s"), 0, 100)
        return { applicable = true, score = s, confidence = 1,
                 detail = { avoidableShare = 0, shareScore = s } }
    end
    if av == nil or not taken or taken <= 0 then
        return { applicable = true, score = Cfg.survival.neutralScore, confidence = 0,
                 note = "No avoidable-damage data was recorded; using a neutral estimate.", detail = {} }
    end
    local share = av / taken
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
    -- CAUSE-WEIGHTED (v38): when the run captured the death-recap breakdown, penalise each death by its
    -- cause - avoidable (stood in it) hurts most, threat (melee while not tanking) least. The buckets are
    -- reconciled to the death count at capture, so they sum to `d`. Runs without the breakdown (older
    -- saves) fall through to the flat per-death calc below - deliberately unchanged.
    local dc, cp = norm.deathCauses, Cfg.deaths.causePenalties
    if type(dc) == "table" and type(cp) == "table"
        and (type(dc.avoidable) == "number" or type(dc.threat) == "number"
             or type(dc.kickable) == "number" or type(dc.other) == "number") then
        local av, th, kk, ot = dc.avoidable or 0, dc.threat or 0, dc.kickable or 0, dc.other or 0
        local pen = av * (cp.avoidable or 0) + th * (cp.threat or 0) + kk * (cp.kickable or 0) + ot * (cp.other or 0)
        if pen > Cfg.deaths.maxPenalty then pen = Cfg.deaths.maxPenalty end
        return { applicable = true, score = Cfg.deaths.baseScore - pen, deaths = d, penalty = pen,
                 confidence = 1, causes = { avoidable = av, threat = th, kickable = kk, other = ot } }
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
