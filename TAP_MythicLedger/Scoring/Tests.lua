-- TAP: Mythic Ledger - Scoring/Tests.lua
-- Internal test harness for the scoring engine. Runs synthetic groups through the full pipeline and
-- asserts the non-negotiable invariants (weights sum to 1.0, N/A never becomes 0, teammates never
-- lower your score, confidence blends toward neutral, redistribution happens). Run in-game with
--   /run TAP_MythicLedger and ML.Scoring.RunTests(print)   (or via /mldev score - wired in dev tools),
-- and standalone under lua5.1 (see scratch harness). Returns { passed, failed, lines }.

local ADDON, ML = ...
local Scoring = ML.Scoring

local SPEC_CLASS = {
    [66] = "PALADIN", [72] = "WARRIOR", [253] = "HUNTER", [257] = "PRIEST", [256] = "PRIEST",
    [270] = "MONK", [105] = "DRUID", [251] = "DEATHKNIGHT", [258] = "PRIEST", [263] = "SHAMAN",
    [261] = "ROGUE", [581] = "DEMONHUNTER", [104] = "DRUID",
}

local function member(guid, specID, role, stats, isPlayer)
    return { guid = guid, name = guid, fullName = guid, specId = specID, role = role,
             classFile = SPEC_CLASS[specID], stats = stats or {}, isPlayer = isPlayer and true or false }
end
local function run(duration, level, party)
    return { duration = duration, level = level, mapId = 1, seasonId = 14, party = party, provider = "BLIZZARD" }
end
-- Reasonable DPS/heal defaults so throughput/survival aren't all "no data".
local function dpsStats(o)
    o = o or {}; return { damage = o.damage or 8.5e8, dps = o.dps or 900000, damageTaken = o.dtaken or 4e7,
        avoidableDamageTaken = o.avoid, healing = o.healing or 2e7, hps = o.hps, interrupts = o.interrupts,
        dispels = o.dispels, deaths = o.deaths }
end
local function tankStats(o)
    o = o or {}; return { damage = o.damage or 5e8, dps = o.dps or 500000, damageTaken = o.dtaken or 1.2e8,
        avoidableDamageTaken = o.avoid, interrupts = o.interrupts, dispels = o.dispels, deaths = o.deaths }
end
local function healStats(o)
    o = o or {}; return { healing = o.healing or 5.4e8, hps = o.hps or 450000, damageTaken = o.dtaken or 3e7,
        avoidableDamageTaken = o.avoid, interrupts = o.interrupts, dispels = o.dispels, deaths = o.deaths }
end

function Scoring.RunTests(printer)
    printer = printer or print
    local Score, Weights, Cfg = Scoring.Score, Scoring.Weights, Scoring.Config
    local passed, failed, lines = 0, 0, {}
    local function check(cond, name)
        if cond then passed = passed + 1 else failed = failed + 1; lines[#lines + 1] = "FAIL: " .. name end
    end
    local function approx(a, b, e) return math.abs((a or 0) - (b or 0)) <= (e or 1e-6) end

    -- (25) All final weights sum to 1.0 across every role x N/A combination.
    for _, role in ipairs({ "DAMAGER", "TANK", "HEALER" }) do
        for _, ap in ipairs({ {}, { interrupts = false }, { dispels = false }, { interrupts = false, dispels = false } }) do
            local w = Weights.Resolve(role, ap)
            local s = 0; for _, c in ipairs(Weights.CATS) do s = s + w[c] end
            check(approx(s, 1.0, 1e-9), string.format("weights sum=1 (%s, i=%s d=%s) got %.6f",
                role, tostring(ap.interrupts), tostring(ap.dispels), s))
        end
    end

    -- (5/6) Holy & Disc Priest: interrupt N/A (never 0), weight redistributed.
    local holy = Score.ScoreNormalized(Scoring.Normalize.Player(run(1800, 12,
        { member("Holy", 257, "HEALER", healStats({ avoid = 4e7, deaths = 0, dispels = 6 }), true) }),
        { guid = "Holy", specId = 257, role = "HEALER", stats = healStats({ avoid = 4e7, dispels = 6 }) }),
        Scoring.Composition.Summarize({}), { interrupts = 0, dispels = 6 })
    check(holy.categories.interrupts.applicable == false, "Holy Priest interrupt N/A")
    check(holy.categories.interrupts.weight == 0, "Holy Priest interrupt weight redistributed to 0")
    check(#holy.redistribution > 0, "Holy Priest logged a redistribution")

    -- (7) Midnight healer-interrupt removal: healers have NO interrupt EXCEPT Resto Shaman (Wind
    -- Shear, now 30s -> LONG_CD). Mistweaver/Holy Pal/Preservation lost theirs.
    check(Scoring.Capability.InterruptProfile(270) == "NONE", "Mistweaver interrupt NONE (Midnight)")
    check(Scoring.Capability.InterruptProfile(65)  == "NONE", "Holy Paladin interrupt NONE (Midnight)")
    check(Scoring.Capability.InterruptProfile(1468) == "NONE", "Preservation interrupt NONE (Midnight)")
    check(Scoring.Capability.InterruptProfile(264) == "LONG_CD", "Resto Shaman interrupt LONG_CD (30s Wind Shear)")

    -- (15) Resto Druid: no interrupt capability.
    check(Scoring.Capability.InterruptProfile(105) == "NONE", "Resto Druid interrupt NONE")
    -- (17) DK: no dispel capability.
    check(Scoring.Capability.DispelProfile(251) == "NONE", "Frost DK dispel NONE")
    -- (16) Priest: broad dispel; (dispel gated to healers).
    check(Scoring.Capability.DispelProfile(257) == "HIGH_UTILITY", "Holy Priest dispel HIGH_UTILITY")
    check(Scoring.Capability.DispelProfile(66) == "LIMITED", "Prot Paladin dispel LIMITED (Cleanse Toxins)")

    -- (10) High-control tank LOWERS others' expected interrupts (never raises), and never lowers score directly.
    local fury = member("Fury", 72, "DAMAGER", dpsStats({ interrupts = 6, avoid = 3e7, deaths = 0 }), true)
    local partyNoTank = { fury, member("R", 261, "DAMAGER", dpsStats({ interrupts = 4 })), member("H", 257, "HEALER", healStats()) }
    local partyProtPal = { fury, member("PP", 66, "TANK", tankStats({ interrupts = 10 })), member("H", 257, "HEALER", healStats()) }
    local nFury = Scoring.Normalize.Player(run(1800, 12, partyNoTank), fury)
    local expNoTank = select(1, Scoring.Composition.InterruptModifier(nFury, Scoring.Composition.Summarize(Scoring.Normalize.Party(run(1800,12,partyNoTank)))))
    local expProt   = select(1, Scoring.Composition.InterruptModifier(nFury, Scoring.Composition.Summarize(Scoring.Normalize.Party(run(1800,12,partyProtPal)))))
    check(expProt <= expNoTank + 1e-9, "High-control tank does not RAISE others' expected interrupts")

    -- Composition modifier always within [0.85, 1.15].
    check(expProt >= Cfg.composition.min - 1e-9 and expProt <= Cfg.composition.max + 1e-9, "comp modifier bounded")

    -- (2) Prot Paladin with a huge interrupt total: capped, doesn't blow past 100 in-category.
    local ppScore = Score.ScoreRun(run(1800, 12, partyProtPal)).byGuid["PP"]
    check(ppScore.categories.interrupts.score <= 100 + 1e-6, "Prot Pal interrupt category <= 100")
    check(ppScore.overall <= 100 and ppScore.overall >= 0, "Prot Pal overall in [0,100]")

    -- (13) Zero group interrupts -> confidence 0 -> blended to neutral for an eligible interrupter.
    local zeroRun = run(1800, 12, { member("Z", 72, "DAMAGER", dpsStats({ interrupts = 0, avoid = 3e7, deaths = 0 }), true),
        member("H", 257, "HEALER", healStats()) })
    local zScore = Score.ScoreRun(zeroRun).byGuid["Z"]
    check(zScore.categories.interrupts.applicable, "zero-interrupt eligible player still applicable (14)")
    check(approx(zScore.categories.interrupts.score, Cfg.confidence.interrupt.neutralScore, 0.5),
        "zero group interrupts -> neutral interrupt score (13)")

    -- (18/19) Death penalties escalate and cap.
    local d1 = Scoring.Categories.Deaths({ deaths = 1 })
    local d3 = Scoring.Categories.Deaths({ deaths = 3 })
    local d9 = Scoring.Categories.Deaths({ deaths = 9 })
    check(d1.penalty == 25 and d1.score == 75, "1 death -> -25")
    check(d3.penalty == 75 and d3.score == 25, "3 deaths -> -75")
    check(d9.penalty == Cfg.deaths.maxPenalty, "many deaths -> capped at max penalty")

    -- (20) High avoidable damage tanks the survival score for a DPS.
    local clean = Scoring.Categories.Survival({ role = "DAMAGER", durationSeconds = 1800, avoidableDamageTaken = 5e5, damageTaken = 3e7 })
    local dirty = Scoring.Categories.Survival({ role = "DAMAGER", durationSeconds = 1800, avoidableDamageTaken = 2e8, damageTaken = 3e8 })
    check(dirty.score < clean.score, "high avoidable damage lowers survival")

    -- (23) Missing meter data -> categories neutral, never 0, applicable where the spec allows.
    local blind = Score.ScoreNormalized(Scoring.Normalize.Player(run(1800, 12,
        { member("Blind", 72, "DAMAGER", {}, true) }), member("Blind", 72, "DAMAGER", {}, true)),
        Scoring.Composition.Summarize({}), {})
    check(blind.categories.deaths.score == Cfg.deaths.baseScore, "missing deaths -> neutral 100, not 0 penalty")
    check(blind.overall > 0, "all-missing data -> non-zero overall (neutral, not F-by-absence)")

    -- (24) Coaching review: state machine + strengths/improvements, ranked by leverage.
    local Review = Scoring.Review
    check(Review.Band(96) == "EXCELLENT" and Review.Band(60) == "SOFT" and Review.Band(40) == "WEAK",
        "review band thresholds classify correctly")

    local strong = { grade = "A", overall = 92, role = "DAMAGER", categories = {
        throughput = { applicable = true, score = 100, weight = 0.27, detail = { dps = { ratio = 1.10, weight = 1 } } },
        survival   = { applicable = true, score = 100, weight = 0.25, detail = { avoidableShare = 0.01 } },
        deaths     = { applicable = true, score = 100, weight = 0.18, deaths = 0, penalty = 0 },
        interrupts = { applicable = true, score = 100, weight = 0.18, actual = 5, expected = 4.5 },
        dispels    = { applicable = true, score = 90,  weight = 0.12, actual = 3, expected = 3 },
        roleContribution = { applicable = true, score = 95, weight = 0 },
    } }
    local rvS = Review.Build(strong)
    check(#rvS.improvements == 0, "strong player -> no improvements")
    check(#rvS.strengths >= 4, "strong player -> multiple strengths")

    local weak = { grade = "D", overall = 52, role = "DAMAGER", categories = {
        throughput = { applicable = true, score = 60, weight = 0.27, detail = { dps = { ratio = 0.70, weight = 1 } } },
        survival   = { applicable = true, score = 30, weight = 0.25, detail = { avoidableShare = 0.15 } },
        deaths     = { applicable = true, score = 50, weight = 0.18, deaths = 2, penalty = 50 },
        interrupts = { applicable = true, score = 70, weight = 0.18, actual = 3, expected = 4.5 },
        dispels    = { applicable = false, reason = "no dispel" },
        roleContribution = { applicable = true, score = 50, weight = 0 },
    } }
    local rvW = Review.Build(weak)
    check(#rvW.improvements >= 3, "weak player -> multiple improvements")
    check(rvW.improvements[1].key == "survival", "improvements ranked by leverage (survival highest)")
    check(rvW.verdicts.dispels and rvW.verdicts.dispels.na == true, "N/A category shows as N/A in verdicts")

    -- (25) Multi-stat throughput splits: a tank who hits DPS but misses HPS -> Damage praised, Healing flagged.
    local tank = { grade = "B", overall = 80, role = "TANK", categories = {
        throughput = { applicable = true, score = 82, weight = 0.16, detail = {
            dps = { value = 5e5, expected = 4.8e5, ratio = 1.04, score = 100, weight = 0.70 },
            hps = { value = 2e5, expected = 3.2e5, ratio = 0.62, score = 55,  weight = 0.30 },
        } },
        survival   = { applicable = true, score = 95, weight = 0.30, detail = { avoidableShare = 0.01 } },
        deaths     = { applicable = true, score = 100, weight = 0.18, deaths = 0, penalty = 0 },
        interrupts = { applicable = true, score = 95, weight = 0.18, actual = 6, expected = 5 },
        dispels    = { applicable = false, reason = "none" },
        roleContribution = { applicable = true, score = 90, weight = 0.06 },
    } }
    local rvT = Review.Build(tank)
    local dmgStrength, healImprove = false, false
    for _, sN in ipairs(rvT.strengths) do if (sN.label or ""):find("Damage") then dmgStrength = true end end
    for _, im in ipairs(rvT.improvements) do
        if (im.label or ""):find("Healing") and (im.note or ""):find("healing") then healImprove = true end
    end
    check(dmgStrength, "throughput split: Damage component is a strength")
    check(healImprove, "throughput split: Healing component flagged with a heal-more tip")

    -- (26) Per-spec interrupt targets scale with real kick availability, not flat profile buckets.
    local Cap = Scoring.Capability
    local function irate(sp) return (Cfg.InterruptRatePerMinute(Cap.Get(sp).interrupt)) end
    check(irate(66) > irate(72), "Prot Pal expects more kicks than Warrior (rotational Avenger's Shield)")
    check(irate(72) > irate(253), "Warrior (14s Pummel) expects more than Counter Shot Hunter (24s)")
    check(irate(66) > irate(581), "Prot Pal (frequent 15s Avenger's Shield) > DH Veng (90s Sigil of Silence)")
    check(irate(255) > irate(253), "Survival Hunter (15s Muzzle) expects more than BM Hunter (24s Counter Shot)")
    check(approx(irate(70), 0.30, 0.05), "plain 15s kicker (Ret) stays ~0.30/min - calibration preserved")

    -- (27) Resto Shaman is the ONE healer that still kicks (30s Wind Shear) - it must be SCORED (not N/A),
    -- while every OTHER healer is correctly interrupt-NONE. The "healers don't kick" default has this exception.
    for _, sp in ipairs({ 65, 105, 256, 257, 270, 1468 }) do   -- Holy Pal, Resto Druid, Disc/Holy Priest, Mistweaver, Preservation
        check(Cap.InterruptProfile(sp) == "NONE", "Healer spec " .. sp .. " has no interrupt (default rule)")
    end
    local rsMem = member("RS", 264, "HEALER", healStats({ interrupts = 3 }), true)
    local rsScore = Score.ScoreNormalized(Scoring.Normalize.Player(run(1800, 12, { rsMem }), rsMem),
        Scoring.Composition.Summarize({}), { interrupts = 12, dispels = 0 })
    check(rsScore.categories.interrupts.applicable == true, "Resto Shaman interrupt is SCORED (the healer kick exception)")
    check((rsScore.categories.interrupts.weight or 0) > 0, "Resto Shaman interrupt carries weight (not redistributed away)")
    check((rsScore.categories.interrupts.expected or 0) > 0, "Resto Shaman has a real Wind Shear kick target")

    -- (28) Missing spec id (real captures without an inspect) is recovered from class+role: a Shaman
    -- Healer with NO specId still resolves to Restoration and is scored on its Wind Shear kick.
    local noSpec = { guid = "NS", name = "NS", classFile = "SHAMAN", role = "HEALER", isPlayer = true,
        stats = { healing = 5.4e8, hps = 450000, damageTaken = 3e7, interrupts = 2 } }
    local nsNorm = Scoring.Normalize.Player(run(1800, 12, { noSpec }), noSpec)
    check(nsNorm.specID == 264, "Shaman+Healer with no specId resolves to Restoration (264)")
    local nsScore = Score.ScoreNormalized(nsNorm, Scoring.Composition.Summarize({}), { interrupts = 10 })
    check(nsScore.categories.interrupts.applicable == true, "recovered Resto Shaman IS scored on interrupts")
    check(Cap.ResolveSpec("HUNTER", "DAMAGER") == nil, "ambiguous class+role (Hunter DPS) is not guessed")
    check(Cap.ResolveSpec("SHAMAN", "HEALER") == 264, "unambiguous class+role (Shaman Healer) resolves")

    -- (29) Dungeon dispel-type gate: a dispel with no valid target type in the dungeon -> N/A, not punished.
    Cfg.dungeonDispelTypes["gatetestmagiconly"] = { curse = false, poison = false, disease = false, enrage = false }
    check(Cfg.DungeonDispelEligible("Gate Test Magic Only", { poison = true }) == false, "poison-only tool in magic-only dungeon -> not eligible")
    check(Cfg.DungeonDispelEligible("Gate Test Magic Only", { magic = true }) == true, "magic tool in magic-only dungeon -> eligible")
    check(Cfg.DungeonDispelEligible("Some Unlisted Dungeon", { poison = true }) == true, "unlisted dungeon -> never restricts")
    check(next(Cfg.DispelTypeSet(Cap.Get(259).dispel)) == "enrage", "Rogue Shiv dispel type set = {enrage}")
    -- Full scoring path: Rogue (enrage-only Shiv) in an enrage-free dungeon -> Dispel N/A.
    Cfg.dungeonDispelTypes["gatetestnoenrage"] = { enrage = false }
    local rgMem = member("RG", 259, "DAMAGER", dpsStats({ dispels = 0 }), true)
    local rgRun = run(1800, 12, { rgMem }); rgRun.dungeonName = "Gate Test No Enrage"
    local rgScore = Score.ScoreNormalized(Scoring.Normalize.Player(rgRun, rgMem), Scoring.Composition.Summarize({}), { dispels = 8 })
    check(rgScore.categories.dispels.applicable == false and rgScore.categories.dispels.dungeonGated,
        "Rogue (enrage-only) in an enrage-free dungeon -> Dispel N/A (dungeon-gated)")
    Cfg.dungeonDispelTypes["gatetestmagiconly"] = nil
    Cfg.dungeonDispelTypes["gatetestnoenrage"] = nil

    -- (30) Per-type dispel DEMAND: a present type's weight scales expected; the spec uses the MAX weight
    -- among the types it can address; unlisted/absent -> neutral 1.0.
    Cfg.dungeonDispelTypes["demandtest"] = { magic = 1.40, curse = 0.90, poison = false }
    check(Cfg.DungeonDispelDemand("Demand Test", { magic = true }) == 1.40, "magic-heavy demand weight applies (1.40)")
    check(Cfg.DungeonDispelDemand("Demand Test", { curse = true }) == 0.90, "narrow curse tool gets curse weight (0.90), not magic's")
    check(Cfg.DungeonDispelDemand("Demand Test", { magic = true, curse = true }) == 1.40, "broad tool uses MAX present-type weight")
    check(Cfg.DungeonDispelDemand("Demand Test", { poison = true }) == 1.0, "absent type -> neutral 1.0 (gate handles eligibility)")
    check(Cfg.DungeonDispelDemand("Some Unlisted Dungeon", { magic = true }) == 1.0, "unlisted dungeon -> neutral demand 1.0")
    -- Expected scales with demand end-to-end: same run, demand 1.40 -> higher expected than neutral 1.0.
    local dmMem = member("DM", 264, "HEALER", healStats({ dispels = 3 }), true)  -- Resto Shaman: magic dispel
    local baseExp = Score.ScoreNormalized(Scoring.Normalize.Player(run(1800, 12, { dmMem }), dmMem),
        Scoring.Composition.Summarize({}), { dispels = 12 }).categories.dispels.expected
    local dmRun = run(1800, 12, { dmMem }); dmRun.dungeonName = "Demand Test"
    local hiExp = Score.ScoreNormalized(Scoring.Normalize.Player(dmRun, dmMem),
        Scoring.Composition.Summarize({}), { dispels = 12 }).categories.dispels.expected
    check(hiExp and baseExp and math.abs(hiExp - baseExp * 1.40) < 1e-6, "demand 1.40 raises expected dispels 40% vs neutral")
    Cfg.dungeonDispelTypes["demandtest"] = nil

    printer(string.format("|cffa06cf0Scoring tests|r: %d passed, %d failed", passed, failed))
    for _, l in ipairs(lines) do printer("  " .. l) end
    return { passed = passed, failed = failed, lines = lines }
end
