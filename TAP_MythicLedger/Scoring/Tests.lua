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
-- Default dungeonName is a real season dungeon (Skyreach) so ScoreRun's interrupt/dispel distribution has
-- a supply profile to draw from; tests that need other content set run.dungeonName explicitly.
local function run(duration, level, party)
    return { duration = duration, level = level, mapId = 1, seasonId = 14, party = party,
             provider = "BLIZZARD", dungeonName = "Skyreach" }
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

    local fury = member("Fury", 72, "DAMAGER", dpsStats({ interrupts = 6, avoid = 3e7, deaths = 0 }), true)
    local partyProtPal = { fury, member("PP", 66, "TANK", tankStats({ interrupts = 10 })), member("H", 257, "HEALER", healStats()) }

    -- (2) Prot Paladin with a huge interrupt total: capped, doesn't blow past 100 in-category.
    local ppScore = Score.ScoreRun(run(1800, 12, partyProtPal)).byGuid["PP"]
    check(ppScore.categories.interrupts.score <= 100 + 1e-6, "Prot Pal interrupt category <= 100")
    check(ppScore.overall <= 100 and ppScore.overall >= 0, "Prot Pal overall in [0,100]")

    -- (13/14) A TRACKED eligible interrupter who landed ZERO kicks now scores a real low, NOT neutral:
    -- the confidence blend that used to lift a weak interrupt score toward neutral has been removed (no
    -- benefit of the doubt). The category is still APPLICABLE (weight kept, never redistributed to hide it).
    local zeroRun = run(1800, 12, { member("Z", 72, "DAMAGER", dpsStats({ interrupts = 0, avoid = 3e7, deaths = 0 }), true),
        member("H", 257, "HEALER", healStats()) })
    local zScore = Score.ScoreRun(zeroRun).byGuid["Z"]
    check(zScore.categories.interrupts.applicable, "zero-interrupt eligible player still applicable (14)")
    check(zScore.categories.interrupts.score < 15, "tracked zero-kick interrupter scores a real low, not neutral (13)")

    -- (18/19) Death penalties escalate and cap.
    local d1 = Scoring.Categories.Deaths({ deaths = 1 })
    local d3 = Scoring.Categories.Deaths({ deaths = 3 })
    local d9 = Scoring.Categories.Deaths({ deaths = 9 })
    check(d1.penalty == 25 and d1.score == 75, "1 death -> -25")
    check(d3.penalty == 75 and d3.score == 25, "3 deaths -> -75")
    check(d9.penalty == Cfg.deaths.maxPenalty, "many deaths -> capped at max penalty")
    -- Cause-weighted deaths (v38): with a breakdown, penalise by cause (avoidable 30 / other 10 / threat 5).
    local dcw = Scoring.Categories.Deaths({ deaths = 3, deathCauses = { avoidable = 1, threat = 1, other = 1 } })
    check(dcw.penalty == 45 and dcw.score == 55, "cause-weighted: 1 avoid + 1 threat + 1 other -> -45")
    local dca = Scoring.Categories.Deaths({ deaths = 4, deathCauses = { avoidable = 4, threat = 0, other = 0 } })
    check(dca.penalty == Cfg.deaths.maxPenalty and dca.score == 0, "cause-weighted: 4 avoidable -> capped")
    local dct = Scoring.Categories.Deaths({ deaths = 2, deathCauses = { avoidable = 0, threat = 2, other = 0 } })
    check(dct.penalty == 10 and dct.score == 90, "cause-weighted: 2 threat deaths -> only -10")
    local dck = Scoring.Categories.Deaths({ deaths = 2, deathCauses = { avoidable = 0, threat = 0, kickable = 1, other = 1 } })
    check(dck.penalty == 20 and dck.score == 80, "cause-weighted: 1 missed-kick + 1 other -> -20 (kickable == other)")

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
        dispels    = { applicable = true, score = 90,  weight = 0.12, actual = 3, expected = 3 },    } }
    local rvS = Review.Build(strong)
    check(#rvS.improvements == 0, "strong player -> no improvements")
    check(#rvS.strengths >= 4, "strong player -> multiple strengths")

    local weak = { grade = "D", overall = 52, role = "DAMAGER", categories = {
        throughput = { applicable = true, score = 60, weight = 0.27, detail = { dps = { ratio = 0.70, weight = 1 } } },
        survival   = { applicable = true, score = 30, weight = 0.25, detail = { avoidableShare = 0.15 } },
        deaths     = { applicable = true, score = 50, weight = 0.18, deaths = 2, penalty = 50 },
        interrupts = { applicable = true, score = 70, weight = 0.18, actual = 3, expected = 4.5 },
        dispels    = { applicable = false, reason = "no dispel" },    } }
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
        dispels    = { applicable = false, reason = "none" },    } }
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
    -- Via the full run so the interrupt distribution runs (a lone Wind Shear kicker gets the whole supply).
    local rsScore = Score.ScoreRun(run(1800, 12, { rsMem })).byGuid["RS"]
    check(rsScore.categories.interrupts.applicable == true, "Resto Shaman interrupt is SCORED (the healer kick exception)")
    check((rsScore.categories.interrupts.weight or 0) > 0, "Resto Shaman interrupt carries weight (not redistributed away)")
    check((rsScore.categories.interrupts.expected or 0) > 0, "Resto Shaman has a real Wind Shear kick target")

    -- (28) Missing spec id (real captures without an inspect) is recovered from class+role: a Shaman
    -- Healer with NO specId still resolves to Restoration and is scored on its Wind Shear kick.
    local noSpec = { guid = "NS", name = "NS", classFile = "SHAMAN", role = "HEALER", isPlayer = true,
        stats = { healing = 5.4e8, hps = 450000, damageTaken = 3e7, interrupts = 2 } }
    local nsNorm = Scoring.Normalize.Player(run(1800, 12, { noSpec }), noSpec)
    check(nsNorm.specID == 264, "Shaman+Healer with no specId resolves to Restoration (264)")
    local nsScore = Score.ScoreRun(run(1800, 12, { noSpec })).byGuid["NS"]
    check(nsScore.categories.interrupts.applicable == true, "recovered Resto Shaman IS scored on interrupts")
    check(Cap.ResolveSpec("HUNTER", "DAMAGER") == nil, "ambiguous class+role (Hunter DPS) is not guessed")
    check(Cap.ResolveSpec("SHAMAN", "HEALER") == 264, "unambiguous class+role (Shaman Healer) resolves")

    -- Season-data harness: ensure a season profile exists (in-game MidnightS1 is loaded; the standalone
    -- lua5.1 harness may not have it) and give us temp-dungeon helpers on the ACTIVE profile so Distribute
    -- (which reads Config.SeasonDungeon) sees our test content.
    Scoring.SeasonData = Scoring.SeasonData or {}
    if not next(Scoring.SeasonData) then Scoring.SeasonData["__test"] = { dungeons = {} } end
    local SP = Cfg.SeasonProfile()
    local function setDungeon(name, data) SP.dungeons[Cfg.NormDungeon(name)] = data end
    local function clearDungeon(name) SP.dungeons[Cfg.NormDungeon(name)] = nil end
    local Dist = Scoring.Distribute

    -- (29) Dispel eligibility via the DISTRIBUTION: an enrage/soothe-only Shiv Rogue in a dungeon whose
    -- season profile has NO enrage/purge supply (only a friendly Magic debuff) draws ~0 -> Cat.Dispel N/A.
    check(next(Cfg.DispelTypeSet(Cap.Get(259).dispel)) == "enrage", "Rogue Shiv dispel type set = {enrage}")
    setDungeon("No Enrage Test", { trash = { partyDebuffFrequencies = { magic = 1.0 } } })
    local rgD = Dist.Dispels({ { playerGUID = "RG", specID = 259, role = "DAMAGER", dispels = 0 } },
        { duration = 1800, dungeonName = "No Enrage Test" })
    check((not rgD["RG"]) or rgD["RG"].expected < 0.5,
        "enrage-only Shiv with no enrage supply -> ~0 expected (Cat.Dispel N/A)")
    clearDungeon("No Enrage Test")
    -- Cat-level N/A shapes: no distribution -> noModel; a ~0 share -> coveredByTeam. Neither is a zero.
    local naNoModel = Scoring.Categories.Dispel({ specID = 257, role = "HEALER", dispels = 2 }, {}, 5, nil)
    check(naNoModel.applicable == false and naNoModel.noModel, "no distribution -> Dispel N/A (noModel), not a 0")
    local naCovered = Scoring.Categories.Dispel({ specID = 257, role = "HEALER", dispels = 2 }, {}, 5, { expected = 0.1 })
    check(naCovered.applicable == false and naCovered.coveredByTeam, "share redistributed to ~0 -> Dispel N/A (coveredByTeam)")

    -- (30) Per-SCHOOL dispel demand scales the supply: magic frequency 1.4 -> 40% more expected than 1.0
    -- for the same lone Magic dispeller (share is 100% either way; only the pool grows).
    setDungeon("Magic10", { trash = { partyDebuffFrequencies = { magic = 1.0 } } })
    setDungeon("Magic14", { trash = { partyDebuffFrequencies = { magic = 1.4 } } })
    local m10 = Dist.Dispels({ { playerGUID = "P", specID = 264, role = "HEALER", dispels = 0 } },
        { duration = 1800, dungeonName = "Magic10" })
    local m14 = Dist.Dispels({ { playerGUID = "P", specID = 264, role = "HEALER", dispels = 0 } },
        { duration = 1800, dungeonName = "Magic14" })
    check(m10["P"] and m14["P"] and approx(m14["P"].baseExpected, m10["P"].baseExpected * 1.40, 1e-6),
        "magic frequency 1.4 raises expected dispels 40% vs 1.0")
    clearDungeon("Magic10"); clearDungeon("Magic14")

    -- (31) Interrupt SUPPLY = trash + the bosses actually killed (per-source scaled); an unkilled boss is
    -- excluded (its block never enters the sum), so boss-time is handled implicitly.
    setDungeon("Kick Supply Test", { trash = { interruptFrequency = 1.0 },
        bosses = { [111] = { interruptFrequency = 2.0 }, [222] = { interruptFrequency = 5.0 } } })
    local ksRun = { duration = 1800, dungeonName = "Kick Supply Test", bosses = { { id = 111, totalTime = 60 } } }
    local ks = Dist.Interrupts({ { playerGUID = "K", specID = 72, role = "DAMAGER", interrupts = 3 } }, ksRun)
    local sc = Cfg.supplyScale
    check(ks["K"] and approx(ks["K"].dungeonSupply, 1.0 * sc.trashKick + 2.0 * sc.bossKick, 1e-6),
        "kick supply = trash + killed-boss frequency x scale (unkilled boss 222 excluded)")
    clearDungeon("Kick Supply Test")

    -- (31b) A killed boss's dispellable debuffs add to the dispel supply (boss-time implicit): the same
    -- lone Magic dispeller expects MORE when a magic-debuff boss is killed than on trash alone.
    setDungeon("Dispel Supply Test", { trash = { partyDebuffFrequencies = { magic = 1.0 } },
        bosses = { [333] = { partyDebuffFrequencies = { magic = 2.0 } } } })
    local dsWith = Dist.Dispels({ { playerGUID = "H", specID = 257, role = "HEALER", dispels = 0 } },
        { duration = 1800, dungeonName = "Dispel Supply Test", bosses = { { id = 333, totalTime = 60 } } })
    local dsTrash = Dist.Dispels({ { playerGUID = "H", specID = 257, role = "HEALER", dispels = 0 } },
        { duration = 1800, dungeonName = "Dispel Supply Test", bosses = {} })
    check(dsWith["H"] and dsTrash["H"] and dsWith["H"].baseExpected > dsTrash["H"].baseExpected + 1e-6,
        "killed boss's debuffs raise dispel supply above trash-only")
    clearDungeon("Dispel Supply Test")

    -- (32) A TRACKED player who recorded no interrupt data is scored a real 0 (no benefit of the doubt),
    -- while a genuinely UNTRACKED player (no combat numbers at all) stays neutral (data outage, not a
    -- no-show). Fury warrior: same spec, one tracked-with-0-kicks, one fully blind.
    local trackedZero = Scoring.Normalize.Player(run(1800, 12, { member("TZ", 72, "DAMAGER", dpsStats({ interrupts = nil }), true) }),
        member("TZ", 72, "DAMAGER", dpsStats({ interrupts = nil }), true))
    check(trackedZero.interrupts == 0, "tracked run, no interrupt rows -> interrupts normalised to 0 (not nil)")
    local untracked = Scoring.Normalize.Player(run(1800, 12, { member("UT", 72, "DAMAGER", {}, true) }),
        member("UT", 72, "DAMAGER", {}, true))
    check(untracked.interrupts == nil, "untracked run (no combat data) -> interrupts stay nil (neutral fallback)")

    -- (33) Workload distribution - SNIPING: two equal-capacity kickers, one lands everything, the other 0.
    -- The over-performer keeps their base (curve caps them at 100 - no reward); the sniped one's expected
    -- is redistributed toward zero (not docked for kicks a teammate stole).
    setDungeon("Dist Kick Test", { trash = { interruptFrequency = 1.0 } })
    local drun = { duration = 1800, dungeonName = "Dist Kick Test" }
    local snipe = Dist.Interrupts({ { playerGUID = "A", specID = 72, role = "DAMAGER", interrupts = 12 },
                                    { playerGUID = "B", specID = 72, role = "DAMAGER", interrupts = 0 } }, drun)
    check(snipe["A"] and snipe["B"], "both kickers appear in the interrupt distribution")
    check(math.abs(snipe["A"].expected - snipe["A"].baseExpected) < 1e-6, "over-performer keeps base expected (capped by curve, not rewarded)")
    check(snipe["B"].expected < snipe["B"].baseExpected - 0.5, "sniped kicker's expected is redistributed DOWN (not docked)")
    check(snipe["B"].expected < 0.5, "fully-sniped kicker -> expected ~0 -> Cat.Interrupt will N/A them")

    -- (34) CAPABILITY SHARE: adding a second capable kicker lowers each one's fair share (workload spreads).
    local solo = Dist.Interrupts({ { playerGUID = "X", specID = 72, role = "DAMAGER", interrupts = 5 } }, drun)
    local duo = Dist.Interrupts({ { playerGUID = "X", specID = 72, role = "DAMAGER", interrupts = 5 },
                                 { playerGUID = "Y", specID = 72, role = "DAMAGER", interrupts = 5 } }, drun)
    check(duo["X"].baseExpected < solo["X"].baseExpected - 1e-6, "a second kicker lowers X's fair share of kicks")
    clearDungeon("Dist Kick Test")

    -- (35) DISPEL per-SCHOOL split: two Magic dispellers split the Magic supply, so each expects less than
    -- one alone would (only members who can cleanse a school share that school's workload).
    setDungeon("Dist D Test", { trash = { partyDebuffFrequencies = { magic = 1.0 } } })
    local ddrun = { duration = 1800, dungeonName = "Dist D Test" }
    local d1 = Dist.Dispels({ { playerGUID = "P1", specID = 257, role = "HEALER", dispels = 3 } }, ddrun)     -- Holy Priest (Magic)
    local d2 = Dist.Dispels({ { playerGUID = "P1", specID = 257, role = "HEALER", dispels = 3 },
                             { playerGUID = "P2", specID = 264, role = "HEALER", dispels = 3 } }, ddrun)      -- + Resto Shaman (Magic)
    check(d1["P1"] and d1["P1"].baseExpected > 0, "solo Magic dispeller gets the whole Magic supply")
    check(d2["P1"].baseExpected < d1["P1"].baseExpected - 1e-6, "a second Magic dispeller lowers P1's Magic share")
    clearDungeon("Dist D Test")

    -- (36) SEASON DATA INTEGRITY: every catalog tier/dtype and supply key across all loaded seasons must be
    -- one the display + scoring layers recognize. An unknown value never errors - it silently drops to
    -- "Spare"/grey (display) or zero supply (scoring) - so this is the only guard against a typo from the
    -- catalog generator or a hand edit. Runs after the test dungeons above are cleared, so it sees real data.
    do
        local problems = ML.ValidateSeasonData and ML.ValidateSeasonData() or {}
        check(#problems == 0, "season data uses only known tiers/schools/keys"
            .. (#problems > 0 and string.format(" (%d issue(s), e.g. %s)", #problems, problems[1]) or ""))
    end

    printer(string.format("|cffa06cf0Scoring tests|r: %d passed, %d failed", passed, failed))
    for _, l in ipairs(lines) do printer("  " .. l) end
    return { passed = passed, failed = failed, lines = lines }
end
