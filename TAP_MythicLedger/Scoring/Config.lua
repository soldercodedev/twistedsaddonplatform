-- TAP: Mythic Ledger - Scoring/Config.lua
-- The SINGLE source of truth for every scoring constant. Nothing in the scoring engine hardcodes a
-- threshold; it all lives here so a balance patch is a data edit, not a code change. Bump
-- Config.version whenever a formula or a default here changes (stored on every PlayerScore so old
-- runs can be recalculated - see Score.lua / ScoreVersioning).
--
-- Design north stars (see PLAYER_SCORING_SYSTEM.md):
--   * A player's score never drops because a teammate did more of anything (no group-relative ranks).
--   * Utility (interrupts/dispels) is scored as CONTRIBUTION vs a spec-specific expectation, never as
--     accuracy or responsibility - the addon only has C_DamageMeter aggregate totals (no combat log
--     in Midnight), so it cannot know interruptible/priority/assigned casts.
--   * Missing data is neutral, never zero. Low sample -> blend toward a neutral score.
--   * When a category doesn't apply to a spec, its weight is REDISTRIBUTED (never a silent zero).

local ADDON, ML = ...

ML.Scoring = ML.Scoring or {}
local Scoring = ML.Scoring

local Config = {}
Scoring.Config = Config

-- Bump on any formula/default change. Stored per score; enables recalculation + migration.
-- v2: throughput is now group-relative (no self-learning) and blends DPS+HPS; HPS scores for tanks
--     (spec-aware "healiness") as well as healers; tank throughput weight raised so healing counts.
-- v3: dispel contribution is scored for ANY dispel-capable spec (DPS/tanks too), not healers only;
--     data fixes - Warrior has no dispel, Rogue's Shiv (enrage) and Druid Soothe now count.
-- v13: per-dungeon dispel-type gate goes LIVE (Config.dungeonDispelTypes populated for Midnight S1) -
--      a narrow dispel with no valid target type in the dungeon now scores N/A instead of being punished.
-- v14: per-dungeon, per-type dispel DEMAND weights scale expected dispels (magic-heavy dungeons like
--      Magisters expect more, light ones like Skyreach fewer); a spec's expected uses the max weight
--      among the dispel types it can address there. Estimates from debuff breadth, not measured casts.
-- v15: TALENT-GATED dispels (Hunter Tranq Shot, Paladin Cleanse Toxins, Shaman Cleanse Spirit, Warlock
--      Singe Magic) no longer create a dispel expectation unless the player is CONFIRMED to have it -
--      live talent inspection captured on the run (party member dispelTalent) OR they actually dispelled.
--      Otherwise the dispel category is N/A (not a dock). Old runs (no capture) treat unknown as N/A too.
-- v16: talent-gate coverage completed (researched vs Midnight 12.0 talent trees). In 12.0 nearly EVERY
--      DPS/tank defensive cleanse is a class-tree talent, so these are now talentDependent too: DH
--      Consume Magic, Druid Remove Corruption, Evoker Cauterizing Flame, Mage Remove Curse, Monk Detox
--      (Brewmaster/Windwalker), Shadow Priest Purify Disease. Only Rogue Shiv stays baseline (auto-
--      granted to Assassination / near-universal Row-1 pick). Baseline healer cures are unaffected.
-- v17: the confidence blend is now ONE-DIRECTIONAL. Low group-sample confidence only ever pulls a
--      score UP toward neutral (forgiving a low showing when the run offered few chances); it never
--      drops a MET target below full. Fixes a met dispel/interrupt target scoring < 100 (e.g. "93")
--      on low-sample ("LIMITED") runs.
-- v18: Survival and Death Impact now weigh the SAME per role - each set to (old survival + old deaths)/2
--      (DPS 0.215/0.215, tanks & healers 0.24/0.24). Row totals unchanged (still sum to 1.0).
-- v19: Survival == Death weight is now guaranteed for EVERY resolved run, not just the base: after any
--      interrupt/dispel N/A redistribution, Weights.Resolve averages the two (sum-preserving) so they
--      stay exactly equal regardless of which categories applied. Also: a tracked run with no avoidable-
--      damage rows now counts as a TRUE 0% avoidable share -> Survival 100 (not a neutral "no data").
-- v20: STATIC, UNIFORM weights across all roles - Throughput 35%, utility (interrupts + dispels) 25%
--      COMBINED, Survival 20%, Death Impact 20%. Interrupts/dispels split the 25% EVENLY (12.5% each) when
--      both apply; if only one applies the other's share moves to it so the utility bucket stays 25%; if
--      neither applies the 25% goes to throughput + survival. roleContribution retired to 0 weight for all
--      roles (targets tuned via knobs later, not weights). Retroactive rescore.
-- v21: interrupt expectation now excludes no-kick boss encounter time + a per-dungeon trash-demand knob;
--      no interrupt/dispel data on a TRACKED run scores a real 0 (was neutral); interrupt confidence blend
--      removed. Dispel demand split into DEFENSIVE (cleanse) vs OFFENSIVE (purge/soothe) axes so a
--      single-axis spec is only measured on what it can do. Retroactive rescore.
-- v22: interrupt + dispel expected are now GROUP-DISTRIBUTED - a per-run supply (dungeon caster/dispel
--      density, capped by group cooldown capacity) split by capability share (per-school for dispels),
--      with sniping redistribution (over-performers capped, under-performers who were sniped not docked).
--      Replaces the old flat per-spec estimate + bounded composition nudge. Retroactive rescore.
-- v23: interrupt/dispel SUPPLY now comes from the season utility profile (Scoring/Seasons/*.lua) as a
--      trash block + one block per boss, so boss-time handling is implicit (no dead-time subtraction).
--      Per-encounter interruptFrequency + per-school partyDebuffFrequencies (defensive) /
--      targetBuffFrequencies (offensive purge+enrage) x per-source scale (Config.supplyScale) set the pool;
--      the capability-share + sniping distribution is unchanged. Retires dungeonInterrupt / noKickBosses /
--      dispelContentBosses / dungeonDispelTypes and the flat standalone fallback. Retroactive rescore.
-- v24: throughput role shares recalibrated from 17 observed Midnight S1 runs (85 player-rows): TANK dps
--      share 0.35 -> 0.55 and HEALER dps 0.08 -> 0.12 (tank damage was under-credited); TANK hps 0.62 ->
--      0.51 and DAMAGER hps 0.04 -> 0.09. staticReference (metadata-only fallback) dropped to observed
--      early-season medians. Group-relative + gear-agnostic as before. Retroactive rescore.
-- v25: interrupt/dispel SUPPLY + CAPACITY calibrated to the same 17 observed runs. Season trash weights
--      (Seasons/MidnightS1) set so modeled kick/dispel supply ~= observed per-dungeon totals at +10; and
--      the capacity cap raised (kickUtil 0.075 -> 0.15; dispel rates ~+40%) so a normal group's cooldowns
--      no longer clip the recalibrated supply below what groups actually land. Retroactive rescore.
-- v26: snipe redistribution is no longer all-or-nothing. New Config.snipeForgiveness (0..1, default 0.5)
--      scales how much a teammate's over-performance excuses an under-performer's shortfall, so a player
--      who plainly under-used their kit (e.g. a tank landing 5 of a ~12 share while short-CD teammates
--      over-kicked) is flagged instead of pulled to a perfect score. Retroactive rescore.
-- v27: survival curve loosened - grace 2.5% -> 3.5%, and it now hits 0 at a 50% avoidable share (was 40%).
--      Same front-loaded shape, just more forgiving. Retroactive rescore.
-- v28: interrupt/dispel supply is now DURATION-AWARE. TRASH frequencies became a per-MINUTE density
--      (multiplied by run minutes in Distribute.accumulate) so a fast clear has less combat time = fewer
--      castable events = lower supply; BOSS blocks stay per-kill. Season trash weights (MidnightS1)
--      re-expressed as observed kicks/dispels per minute; trashKick/trashDispel scales -> 1.0. Fixes fast
--      runs being judged against the same expected as slow ones. Retroactive rescore.
-- v29: BOSS supply is now time-aware too. A boss's mechanics recycle while it's up, so its kick/dispel
--      supply scales by how long the boss was actually engaged (b.totalTime) vs a reference fight length
--      (supplyScale.bossRefSeconds = 90s) - a slow kill offers more than a burst; a boss dropped before its
--      cast comes around offers almost none. Was a flat per-kill count. Retroactive rescore.
-- v30: party-member SPEC now flows into scoring. The live inspect (Inspect.lua / GetInspectSpecialization)
--      already captured pug specs but they were discarded for scoring - now they're stored on the member
--      (mergePartyStats) and preferred at scoring time (Normalize, retroactive via run.dispelCapture). For
--      an un-inspected member whose class DPS specs disagree on interrupt tier, a per-class representative
--      is used (Hunter DPS -> BM / LONG_CD) instead of the blanket STANDARD guess. Retroactive rescore.
-- v31: Skyreach + Windrunner Spire interrupt supply corrected from placeholder estimates to observed data.
--      Both trash.interruptFrequency were guesses ("no +10 data yet"): Skyreach 0.335 -> 1.15, Windrunner
--      Spire 0.38 -> 2.0 (boss-subtracted trash kicks/min ~1.25 / ~2.3 observed, held slightly under given
--      n=2 each). The old values were ~4-6x too low, so interrupt scores in those two dungeons were badly
--      inflated. Retroactive rescore.
-- v32: Augmentation Evoker (support/buff DPS) is now throughput-adjusted. An aug is expected to do only
--      half a normal DPS's personal damage (it inflates everyone else's), and the freed share is handed to
--      the teammates it pumps - split 0.35 across the non-aug DPS, 0.10 to the tank, 0.05 to the healer
--      (sums to the 0.5 the aug gave up, so the group's total expected damage is conserved and just
--      redistributed). See throughput.augmentation. Only affects groups containing an aug. Retroactive rescore.
-- v33: Nexus-Point Xenas interrupt supply corrected from placeholder to observed data. trash.interruptFrequency
--      0.385 -> 1.40 (obs ~1.44 boss-subtracted trash kicks/min, n=2 real +10). The last "no data yet" guess;
--      old value was ~3.7x too low, so interrupt scores there were badly inflated. Retroactive rescore.
-- v34: HEALING REQUIREMENT model (Scoring/Healing.lua). Tank & healer throughput HPS component now scores
--      against a damage-taken requirement instead of a group-relative HPS share: tank = self-cover
--      TankSelfCoverage(spec) of its unavoidable damage; healer = the tank's remainder + 90% of the group's
--      unavoidable damage + avoidableCredit (0.25) of the group's avoidable. Output = healing + absorbs
--      (shield specs not penalised). A group standing in bad now hits its own Survival, not the healer's
--      target. Falls back to the group-relative baseline when < 60% of the party reported damage taken.
--      Config.healing + Config.TankSelfCoverage (derived from tankHealiness). Retroactive rescore.
-- v35: Healing rebalance from 32 observed runs - tanks over-covered (output/req 1.25-1.54), healers
--      under (0.84). tankSelfCoverageBase 0.55->0.70, groupSelfHealFactor 0.90->0.80, Brewmaster
--      healiness 0.95->0.70. Dispel supply now priority-filtered (only High/Must-priority auras count
--      toward the season demand) so broad dispellers aren't punished for skipping low-value dispels.
-- v36: dispel curation pass. Per-dungeon dispelDemandScale recomputed from corrected priorities:
--      (1) added the observed dungeon dispels the guides never named (Transference, Permeating Cold,
--      Energy Bomb, Ethereal Shackles, Poison Spray, ...); (2) buff removal-rate GATE - an auto-classified
--      enemy buff only counts High-remove if the group actually removes it >=25% of the time, so trash
--      enrages nobody soothes (Raging Screech 7%, Battle Rage 8%, Grim Ward 24%) no longer inflate the
--      dispel share; (3) At-Stack DoTs (Rotting Strikes, Vilebranch Sting) weighted 0.5 in the demand -
--      removed once per stack-threshold, not per application. Scales: Pit 0.40->0.66, Algeth'ar 0.34->0.59,
--      Seat 0.65->0.46, Windrunner 0.72->0.83. Dispel <60 (good runs) 36%->24%, now accurately targeted.
--      Retroactive rescore.
-- v37: tank/interrupt calibration from the same 32 runs. Tank self-coverage per spec: Guardian healiness
--      0.95->1.15, Prot Paladin 0.85->1.00 (both over-covered 1.16-1.25 -> ~1.0-1.14); Brewmaster
--      0.70->0.58 (meter records NO absorbs for Stagger, so Brew is structurally healer-reliant; centers
--      0.75->0.90, can't fully fix without a Stagger signal). groupSelfHealFactor 0.80->0.85 to re-center
--      the healer (1.16->1.13) after the tank raise shrank its remainder. LONG_CD interrupt rate
--      0.1125->0.09 (round down - long-CD kicks are banked when the group covers). Retroactive rescore.
-- v38: Death Impact is now CAUSE-WEIGHTED when the run captured the death-recap breakdown - per death,
--      -30 (avoidable), -10 (other), -5 (threat: melee while not tanking) off the 0-100 Death category
--      (Config.deaths.causePenalties), capped at maxPenalty. Runs WITHOUT the breakdown (pre-v38 saves)
--      keep the flat -25/death calc. Deaths category weight (0.20) unchanged. Retroactive rescore.
-- v39: two accuracy fixes from beta run-log analysis (see SCORING_TUNING_IDEAS.md). (1) DISPELS: a small
--      personal dispel share on a low-volume mechanic that the GROUP actually covered no longer scores 0 -
--      it becomes N/A ("teammates covered", weight redistributed) via Config.dispelCoverage. Plus Skyreach's
--      phantom defensive magic supply was removed (its dispellable content is all offensive enemy buffs -
--      Seasons/MidnightS1), and Restoration Druid gained its baseline Soothe (offensive enrage) in
--      Capability. (2) INTERRUPTS: a LONG_CD interrupt is passed to N/A (still "recommended to press") when
--      the group already covered the run's kick supply AND nobody died to a kickable cast; the pass is
--      SUPPRESSED and flagged when the player landed 0 kicks and a kickable death occurred
--      (Config.interrupt.longCdPassCoverage). Retroactive rescore.
-- v40: two throughput fairness changes (see SCORING_TUNING_IDEAS.md finding 4 + idea 3). (1) ITEM LEVEL:
--      the DPS expectation is now scaled by a player's ilvl vs the GROUP AVERAGE - the lowest-geared
--      member isn't docked for output their gear can't reach, and out-gearing the group doesn't read as
--      skill. Bounded (+/-20%), ~1%/ilvl, DPS component only (HPS uses the damage-taken requirement), and
--      only when >=80% of the party's ilvl is known (Config.throughput.ilvlAdjust). (2) HEALER OUTCOME
--      FLOOR: a healer who TIMED the key with few deaths has demonstrably done the job, so a sub-neutral
--      throughput (the group self-covered its own damage, leaving little to heal) is lifted toward neutral
--      in proportion to how clean the run was - death-gated so a disaster run keeps its low score, and it
--      NEVER lowers a score (Config.throughput.outcomeFloor). Retroactive rescore.
-- v41: death classification (Providers.ClassifyDeaths) now gives the KILLING BLOW precedence over the
--      whole-recap damage share. If the fatal hit was avoidable - or ENVIRONMENTAL (fall / lava / fire =
--      the player's own fault, now classed avoidable) - the death is Avoidable even if earlier chip damage
--      was threat/other; a fatal melee auto on a non-tank is a Threat death. Only when the killing blow is
--      none of these does it fall back to the dominant-share classification. Affects the cause-weighted
--      Death penalty on runs that captured death recaps. Retroactive rescore.
-- v42: (1) HEALER OUTCOME FLOOR now lifts the HEALING HALF to a PERFECT 100 (was neutral 75) on a timed,
--      no-death run - moved into Cat.Throughput, applied to the HPS component only (their damage is still
--      graded). (2) New top grade "S+" for a flawless 100 (every applicable category perfect). (3) TANK
--      review now surfaces `groupLooseThreatDeaths` - teammate deaths from a mob the tank lost/never had
--      threat on - for awareness only (NOT scored, weight 0). Retroactive rescore.
-- v43: death killing-blow precedence extended to MISSED KICK - if the fatal blow was a catalogued
--      interruptible cast, the death is Kickable even when earlier avoidable/other chip damage held the
--      dominant share (completes the v41 killing-blow rule; from a reviewed reclassification). Retroactive
--      rescore.
Config.version = 43

Config.roles = { "TANK", "HEALER", "DAMAGER" }

----------------------------------------------------------------------
-- Category weights per role (must each sum to 1.0; validated at load). Six categories:
-- throughput, interrupts, dispels, survival, deaths, roleContribution. "Utility" in the brief =
-- interrupts + dispels. When a utility category is N/A for a spec these are redistributed
-- deterministically by Weights.lua.
----------------------------------------------------------------------
-- Static, uniform weights for every role (v20): Throughput 35%, utility (interrupts + dispels) 25%
-- COMBINED, Survival 20%, Death Impact 20%. Interrupts and dispels split the 25% EVENLY (12.5% each) when
-- both apply; when only ONE applies the other's share moves to it so the utility bucket stays 25% (see
-- redistribution below); when NEITHER applies the 25% goes to throughput + survival. roleContribution is
-- retired to 0 weight (its targets can be reintroduced via knobs later without touching these weights).
-- Survival and Death Impact stay EXACTLY equal (Weights.Resolve averages them after any redistribution).
Config.roleWeights = {
    DAMAGER = { throughput = 0.35, interrupts = 0.125, dispels = 0.125, survival = 0.20, deaths = 0.20, roleContribution = 0.00 },
    TANK    = { throughput = 0.35, interrupts = 0.125, dispels = 0.125, survival = 0.20, deaths = 0.20, roleContribution = 0.00 },
    HEALER  = { throughput = 0.35, interrupts = 0.125, dispels = 0.125, survival = 0.20, deaths = 0.20, roleContribution = 0.00 },
}

-- Deterministic redistribution when a utility category is not applicable. Fractions of the freed
-- weight, per role. Must sum to 1.0 each (validated). Because interrupts + dispels are ONE 25% budget,
-- an N/A on a single utility category moves its whole share to the OTHER utility category, keeping the
-- bucket at 25% on whichever applies. Only when BOTH are N/A does the 25% leave the bucket (utilityBoth).
Config.redistribution = {
    interrupts = {   -- interrupts N/A -> dispels absorbs the freed weight (utility stays 25%)
        DAMAGER = { dispels = 1.00 },
        TANK    = { dispels = 1.00 },
        HEALER  = { dispels = 1.00 },
    },
    dispels = {      -- dispels N/A -> interrupts absorbs the freed weight (utility stays 25%)
        DAMAGER = { interrupts = 1.00 },
        TANK    = { interrupts = 1.00 },
        HEALER  = { interrupts = 1.00 },
    },
    -- If BOTH utility categories are N/A, the combined 25% splits evenly to throughput and survival
    -- (survival then shares equally with deaths via the Survival==Death equalize step in Weights.Resolve).
    utilityBoth = {
        DAMAGER = { throughput = 0.50, survival = 0.50 },
        TANK    = { throughput = 0.50, survival = 0.50 },
        HEALER  = { throughput = 0.50, survival = 0.50 },
    },
}

----------------------------------------------------------------------
-- Interrupt profiles. The `profile` is now only a LABEL (shown in tooltips) and the `scoreEligible`
-- gate - the expected kick RATE is no longer this flat per-profile number. It is computed PER SPEC from
-- that spec's real interrupt availability (cooldown + rotational extra stops) by InterruptRatePerMinute
-- below, so a Prot Paladin (15s Rebuke + frequent Avenger's Shield) is expected to kick more than a
-- Warrior (14s Pummel), which is more than a Counter Shot Hunter (24s). ratePerMinute is kept only as a
-- coarse FALLBACK for records with no cooldown data. Sources: warcraft.wiki.gg/wiki/Interrupt.
----------------------------------------------------------------------
-- Tiers by INTERRUPT COOLDOWN. ratePerMinute here is a FALLBACK only (used when a record has no cooldown
-- - which no live spec has, so it's effectively documentation). Set on a time vector: SHORT (12-15s) 0.45,
-- STANDARD (15-30s) = half of SHORT (0.225), LONG (>30s) = half of STANDARD (0.1125), HIGH_CONTROL 0.60.
-- That mirrors what the live CD formula already does (rate ~ 1/cd, so double the cooldown ~= half the
-- rate). The `profile` on each spec is now just this eligibility gate + a display LABEL - the composition
-- tier nudge that once read it was retired in v22 - so re-tiering a spec changes its label, not its score.
Config.interruptProfiles = {
    NONE         = { ratePerMinute = 0.00,   scoreEligible = false },  -- no interrupt
    LONG_CD      = { ratePerMinute = 0.09,   scoreEligible = true },   -- CD > 30s (Quell 40s, Shadow Silence 45s, Solar Beam 60s). v37: 0.1125->0.09 rounded DOWN - long-CD classes reasonably bank a 45-60s kick when the group already covers kicks (obs a/e 1.5x); lower expected drops the reluctant ones to N/A rather than docking them.
    STANDARD     = { ratePerMinute = 0.225,  scoreEligible = true },   -- CD 15-30s (Counterspell / Counter Shot / Spell Lock 24s; Resto Shaman 30s Wind Shear)
    SHORT_CD     = { ratePerMinute = 0.45,   scoreEligible = true },   -- CD 12-15s (Kick / Pummel / Rebuke / Mind Freeze / Muzzle / Spear Hand; Ele/Enh Wind Shear 12s)
    HIGH_CONTROL = { ratePerMinute = 0.60,   scoreEligible = true },   -- 15s interrupt + strong rotational extra stop/silence (Prot Pal, DH Vengeance)
}

----------------------------------------------------------------------
-- Per-spec interrupt availability -> expected kicks/minute. availability = (60 / interrupt CD) plus,
-- for each ROTATIONAL extra stop of a counted type, (60 / its CD) x how-likely-it-is-used-to-interrupt.
-- kickUtil then scales raw availability down to realistic CONTRIBUTIONS (a run rarely offers a kick
-- every cooldown). Calibrated so a plain 15s kicker lands on ~0.30/min (the old STANDARD number), so
-- most specs are unchanged while genuinely-more-available kits (Prot Pal) score higher and rarer ones
-- (Shadow's 45s Silence, Balance's 60s Solar Beam) score lower - the differentiation the flat buckets lost.
----------------------------------------------------------------------
Config.interrupt = {
    -- kickUtil raised 0.075 -> 0.15 (2026-07): observed groups landed ~1.9 kicks/min (up to 2.9) with ~4
    -- interrupters over 20+ min - i.e. ~42-66 kicks/run - but the old cap sat ~24 and CLIPPED them, which
    -- also stopped the recalibrated season kick supply (Seasons/MidnightS1) from taking effect. 0.15 lifts
    -- group capacity to ~50-60 so the season supply (not the cap) is the binding limit for a normal group.
    kickUtil = 0.15,    -- fraction of raw interrupt AVAILABILITY that becomes an actual kick in M+
    stopLikelihood = { HIGH = 0.60, MEDIUM = 0.30, LOW = 0.10 },   -- how often a rotational extra stop is spent interrupting
    countedStopTypes = { INTERRUPT = true, SILENCE = true },        -- a STUN doesn't lock a school like a kick -> not counted
    -- LONG_CD "pass" (v39): a long-cooldown interrupt is reasonably banked when the group already covered
    -- the run's kicks. When a LONG_CD spec scored BELOW neutral (it under-kicked its share) AND the group
    -- landed at least this fraction of the kick supply AND no party death was attributed to a kickable cast,
    -- the interrupt category is passed to N/A (weight redistributed) instead of docking them - with a note
    -- that pressing it is still recommended. The pass is REVOKED (kept low + flagged) when the player landed
    -- ZERO kicks and a kickable death occurred (they could have stopped a lethal cast).
    longCdPassCoverage = 1.0,
}
-- CALIBRATION: per-source scale on the supply pools. TRASH frequencies are a PER-MINUTE density and are
-- multiplied by run length in Distribute.accumulate, so trashKick/trashDispel are 1.0 (the density is used
-- directly; kept as global multipliers for tuning). BOSS frequencies are per a REFERENCE fight length
-- (bossRefSeconds) and are scaled by how long each boss was actually engaged, so a longer fight (mechanics
-- recycling) offers more kicks/dispels than a fast kill. bossKick/bossDispel are the per-reference-fight
-- multipliers; bossRefSeconds is the fight length at which a boss contributes its base weight.
Config.supplyScale = { trashKick = 1.0, bossKick = 1.5, trashDispel = 1.0, bossDispel = 1, bossRefSeconds = 90 }

-- How much a teammate's OVER-performance excuses an under-performer's shortfall when the interrupt/dispel
-- workload is redistributed (Scoring/Distribute.lua). 1.0 = fully forgiven (a player who under-used their
-- kit is judged only on what they did, if teammates covered the pool); 0.0 = no forgiveness (judged on
-- their full capability share). 0.5 is the middle ground: a genuinely-sniped player still isn't docked
-- hard, but someone who plainly didn't push their button is no longer excused to a perfect score.
Config.snipeForgiveness = 0.5

-- Group-covered dispel escape (v39). On a low-volume dispel mechanic, a player whose fair share was small
-- and who dispelled nothing should NOT score 0 when the GROUP still covered the demand (a teammate handled
-- the one or two dispels that came up). When actual == 0 AND the player's expected share < shareMax AND the
-- group covered >= groupMin of the demand ON THE AXES THIS SPEC CAN ADDRESS (defensive cleanse and/or
-- offensive purge/soothe - so a DPS's offensive purge can't "cover" a healer's defensive cleanse), the
-- dispel category becomes N/A (coveredByTeam, weight redistributed) instead of a 0. Shares >= shareMax are a
-- real workload and still scored. Mirrors the interrupt sniping idea but as a clean N/A on tiny shares.
Config.dispelCoverage = { shareMax = 1.25, groupMin = 0.90 }

-- The season utility profile for the current M+ pool (registered from Scoring/Seasons/*.lua into
-- ML.Scoring.SeasonData), and a per-dungeon lookup within it. Season selection matches
-- C_MythicPlus.GetCurrentSeason() to a profile's declared season ids, else uses the sole loaded profile.
function Config.SeasonProfile()
    local all = ML.Scoring and ML.Scoring.SeasonData
    if not all then return nil end
    local cur = ML.API and ML.API.GetCurrentSeason and ML.API.GetCurrentSeason()
    local only
    for _, prof in pairs(all) do
        only = only or prof
        if cur and prof.seasons and prof.seasons[cur] then return prof end
    end
    return only
end
function Config.SeasonDungeon(dungeonName)
    local prof = Config.SeasonProfile()
    local nk = Config.NormDungeon(dungeonName)
    return (prof and prof.dungeons and nk) and prof.dungeons[nk] or nil
end

-- Expected interrupt CONTRIBUTIONS per minute for one spec's interrupt capability record (Capability.lua).
-- Returns (ratePerMinute, rawAvailabilityPerMinute). 0 if the spec has no usable interrupt / CD data.
function Config.InterruptRatePerMinute(rec)
    if not rec or rec.available == false or not rec.cooldownSeconds or rec.cooldownSeconds <= 0 then return 0, 0 end
    local ic = Config.interrupt
    local avail = 60 / rec.cooldownSeconds
    for _, stop in ipairs(rec.additionalStops or {}) do
        if ic.countedStopTypes[stop.stopType] and stop.cooldownSeconds and stop.cooldownSeconds > 0 then
            avail = avail + (60 / stop.cooldownSeconds) * (ic.stopLikelihood[stop.rotationalLikelihood or "LOW"] or 0)
        end
    end
    return avail * ic.kickUtil, avail
end

-- NOTE: per-dungeon interrupt demand, no-kick bosses, and per-axis dispel boss-time (the old
-- dungeonInterrupt / noKickBosses / InterruptDeadSeconds / dispelContentBosses / DispelDeadSeconds tables)
-- are RETIRED. The interrupt/dispel SUPPLY now comes from the season utility profile
-- (Scoring/Seasons/*.lua, via Config.SeasonDungeon) summed over the trash block + the boss blocks for the
-- bosses actually killed, so boss-time handling is implicit and exact - no separate dead-time subtraction.

-- Dispel profiles. ratePerMinute = expected dispel CONTRIBUTIONS per minute given dispel access.
-- Most DPS have only a curse/poison/offensive-purge tool used situationally -> LIMITED. Healers with
-- full defensive dispel -> STANDARD/HIGH.
-- Rates bumped ~40% (2026-07): observed groups dispelled ~0.6/min (up to ~1.8 in magic-heavy dungeons)
-- across ~2 dispellers - i.e. ~0.3/min each, into the mid-0.9/min range - so the old caps clipped the
-- recalibrated season dispel supply. High-supply dungeons stay dispeller-capacity-bound (2 dispellers
-- genuinely can't cover 20 debuffs), which is realistic; these just stop clipping the typical case.
Config.dispelProfiles = {
    NONE         = { ratePerMinute = 0.00, scoreEligible = false },
    LIMITED      = { ratePerMinute = 0.14, scoreEligible = true },   -- one narrow tool (Remove Curse, Cleanse Toxins, offensive purge only)
    STANDARD     = { ratePerMinute = 0.30, scoreEligible = true },   -- full defensive dispel (healers, Mistweaver Detox)
    HIGH_UTILITY = { ratePerMinute = 0.40, scoreEligible = true },   -- broad dispel + Mass Dispel / multi-type (Priest, Preservation)
}

-- NOTE: per-dungeon dispel-type presence/demand weights (the old Config.dungeonDispelTypes) are RETIRED.
-- Per-school dispel demand now lives in the season profile (Scoring/Seasons/*.lua) as
-- partyDebuffFrequencies (defensive) / targetBuffFrequencies (offensive purge+enrage), summed over trash +
-- boss blocks in Distribute.lua. The granular per-effect coaching DB (Config.dungeonDispelDebuffs, below)
-- still drives the run-review "what you could have cleared" callout.

-- Normalise a dungeon name to its table key (mirrors Compat's boss-name normaliser).
function Config.NormDungeon(name)
    if type(name) ~= "string" then return nil end
    local k = name:lower():gsub("[^%w]", "")
    return k ~= "" and k or nil
end

-- The set of dispel TYPES a spec's dispel record can remove (union of its defensive + offensive types).
function Config.DispelTypeSet(dispel)
    local s = {}
    if type(dispel) == "table" then
        for _, bucket in ipairs({ dispel.defensive or false, dispel.offensive or false }) do
            if type(bucket) == "table" then for t, v in pairs(bucket) do if v then s[t] = true end end end
        end
    end
    return s
end

----------------------------------------------------------------------
-- Per-dungeon dispellable effects, keyed by normalised dungeon name -> dispel type -> list of
-- { name, id, kind }. This is the granular half of the seasonal dispel DB (per-school demand now lives in
-- the season profile, Scoring/Seasons/*.lua). It lets the run-review coach a player with the exact ability
-- icons (via `id`, the real spell id -> Blizzard tooltip) and split them into what they'd DISPEL vs PURGE:
--   kind = "debuff" -> a harmful aura ON A PLAYER, removed by a DEFENSIVE dispel (Dispel)
--   kind = "buff"   -> a beneficial aura ON AN ENEMY, removed by an OFFENSIVE dispel (Purge; enrage = Soothe)
--
-- Names + spell ids sourced 2026-07 from gerritalex.de's full S1 debuff list (its JSON exposes ids).
-- The buff/debuff split is OUR classification from the mechanic: enrage is always an enemy buff; magic
-- "Ward / Shield / Barrier / Bolstering / Enhancement / Bloodlust" effects are enemy buffs you Purge;
-- everything else (CC, DoTs, curses, poisons, diseases) is a player debuff you Dispel. A handful are
-- best-guesses (Oversurge, Necromantic Infusion, Rushing Winds) - the Blizzard tooltip shows the truth
-- on hover regardless. Keep in sync with the per-school demand in the season profile each season.
----------------------------------------------------------------------
local function dbf(name, id, buff) return { name = name, id = id, kind = buff and "buff" or "debuff" } end
Config.dungeonDispelDebuffs = {
    ["algetharacademy"] = {
        magic  = { dbf("Energy Bomb", 374350), dbf("Monotonous Lecture", 388392), dbf("Oversurge", 391977, true) },
        poison = { dbf("Lasher Toxin", 389033) },
        enrage = { dbf("Agitation", 390938, true), dbf("Raging Screech", 377389, true) },
    },
    ["magistersterrace"] = {
        magic = { dbf("Polymorph", 468966), dbf("Holy Fire", 1255187), dbf("Umbral Splinters", 1284627),
                  dbf("Void Torrent", 1214714), dbf("Arcane Blade", 1252909), dbf("Consuming Void", 1245068),
                  dbf("Devouring Entropy", 1215897), dbf("Ethereal Shackles", 1214038), dbf("Void Surge", 1264693),
                  dbf("Hastening Ward", 1248689, true), dbf("Power Word: Shield", 1254306, true) },
    },
    ["maisaracaverns"] = {
        magic   = { dbf("Hex", 1256008), dbf("Spirit Rend", 1259255), dbf("Frost Nova", 1271623),
                    dbf("Cries of the Fallen", 1254175), dbf("Ritual Firebrand", 1262411), dbf("Vilebranch Sting", 1260709),
                    dbf("Grim Ward", 1270079, true) },
        disease = { dbf("Infected Pinions", 1246666) },
        enrage  = { dbf("Blood Frenzy", 1255765, true) },
    },
    ["nexuspointxenas"] = {
        magic = { dbf("Burning Radiance", 1277557), dbf("Holy Echo", 1263783), dbf("Transference", 1249815) },
        curse = { dbf("Bad Omens", 1217882), dbf("Creeping Void", 1281636) },
    },
    ["windrunnerspire"] = {
        magic  = { dbf("Soul Torment", 1216298), dbf("Bolstering Flames", 1216860, true) },
        curse  = { dbf("Curse of Darkness", 1215803) },
        poison = { dbf("Poison Blades", 473795), dbf("Poison Spray", 1216825) },
        enrage = { dbf("Ephemeral Bloodlust", 1216459, true) },
    },
    ["pitofsaron"] = {
        magic   = { dbf("Permeating Cold", 1258437), dbf("Cryoshards", 1261921), dbf("Immolate", 157736),
                    dbf("Torrent of Misery", 1258826), dbf("Necromantic Infusion", 1258448, true) },
        curse   = { dbf("Curse of Torment", 1258434), dbf("Shadowbind", 1264186) },
        disease = { dbf("Rotting Strikes", 1258459) },
        enrage  = { dbf("Plague Frenzy", 1259132, true) },
    },
    ["seatofthetriumvirate"] = {
        magic  = { dbf("Rift Essence", 1280330), dbf("Corrupting Touch", 245748), dbf("Howling Dark", 244751),
                   dbf("Abyssal Enhancement", 1262526, true) },
        enrage = { dbf("Battle Rage", 1264036, true) },
    },
    ["skyreach"] = {
        magic  = { dbf("Rushing Winds", 1254670, true), dbf("Solar Barrier", 1273356, true) },
        enrage = { dbf("Wrathful Wind", 1254678, true) },
    },
}

-- What a spec could have dispelled in this dungeon, matched precisely against its DEFENSIVE (dispel) and
-- OFFENSIVE (purge/soothe) capability: a player debuff needs the spec's defensive type; an enemy buff
-- needs its offensive type. Returns a flat list of { name, id, type, action } where action is
-- "Dispel" | "Purge" | "Soothe". `dispel` is the spec's capability dispel record. Empty when the dungeon
-- is unlisted or nothing overlaps. Drives the run-review coaching callout.
local DISPEL_TYPE_ORDER = { "magic", "curse", "poison", "disease", "enrage" }
function Config.DungeonDispelTargets(dungeonName, dispel)
    local out = {}
    if type(dispel) ~= "table" then return out end
    local nk = Config.NormDungeon(dungeonName)
    local byType = nk and Config.dungeonDispelDebuffs[nk]
    if not byType then return out end            -- unlisted dungeon: no known targets
    local defensive, offensive = dispel.defensive or {}, dispel.offensive or {}
    for _, t in ipairs(DISPEL_TYPE_ORDER) do
        for _, e in ipairs(byType[t] or {}) do   -- every listed effect of this type IS present in the dungeon
            if e.kind == "buff" and offensive[t] then
                out[#out + 1] = { name = e.name, id = e.id, type = t, action = (t == "enrage") and "Soothe" or "Purge" }
            elseif e.kind ~= "buff" and defensive[t] then
                out[#out + 1] = { name = e.name, id = e.id, type = t, action = "Dispel" }
            end
        end
    end
    return out
end

-- ALL dispellable content in a dungeon, split by AXIS and independent of who's in the group: every enemy
-- BUFF the party could purge/soothe, and every player DEBUFF it could cleanse. Each entry is
-- { name, id, type, action } (action = "Purge"/"Soothe"/"Dispel"). Drives the group-utility tile
-- tooltips ("what was dispellable here"). Empty lists for an unlisted dungeon.
function Config.DungeonDispellables(dungeonName)
    local out = { buffs = {}, debuffs = {} }
    local nk = Config.NormDungeon(dungeonName)
    local byType = nk and Config.dungeonDispelDebuffs[nk]
    if not byType then return out end
    for _, t in ipairs(DISPEL_TYPE_ORDER) do
        for _, e in ipairs(byType[t] or {}) do
            if e.kind == "buff" then
                out.buffs[#out.buffs + 1] = { name = e.name, id = e.id, type = t,
                    action = (t == "enrage") and "Soothe" or "Purge" }
            else
                out.debuffs[#out.debuffs + 1] = { name = e.name, id = e.id, type = t, action = "Dispel" }
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Contribution scoring curve. Maps ratio (actual / expected) -> score via linear interpolation.
-- SOFT-CAPPED at 1.0, exactly like throughput: MEETING your expected count = full marks (100), and
-- doing MORE plateaus at 100 (the curve clamps to the last point) - it never helps or hurts. This
-- avoids the confusing "expected reads like the target but hitting it isn't a max" gap; the only way
-- to lose points is to fall SHORT of expected. Shared by interrupts and dispels.
----------------------------------------------------------------------
Config.contributionCurve = {
    points = {
        { ratio = 0.00, score = 0 },
        { ratio = 0.40, score = 40 },
        { ratio = 0.65, score = 64 },
        { ratio = 0.80, score = 80 },
        { ratio = 0.90, score = 90 },
        { ratio = 1.00, score = 100 },   -- meeting expected = max; ratios above 1.0 stay at 100
    },
    maxInternal = 100,
    categoryCap = 100,   -- the category score handed to the weighted sum never exceeds 100.
}

----------------------------------------------------------------------
-- Confidence: blend a computed contribution score toward a NEUTRAL score when the run didn't record
-- enough total activity to grade confidently (short run, few casts, meter gaps). confidence in
-- [0,1] = clamp(groupTotal / minSample). neutral chosen slightly above midpoint: absence of evidence
-- shouldn't read as "bad", and most graded runs land in the B range.
----------------------------------------------------------------------
Config.confidence = {
    interrupt = { neutralScore = 75, minGroupSample = 15 },
    dispel    = { neutralScore = 70, minGroupSample = 8 },
    throughput = { minGroupSample = 1 },   -- throughput confidence handled via baseline sample (Baselines.lua)
}

----------------------------------------------------------------------
-- Group-composition modifier for expected utility. BOUNDED and small: comp nudges expectations, it
-- never dominates. A high-control tank/short-CD interrupter SLIGHTLY LOWERS others' expected
-- interrupt contribution (fewer casts left for them) - it never raises anyone else's expectation and
-- never directly changes another player's score.
----------------------------------------------------------------------
Config.composition = {
    min = 0.85, max = 1.15,
    interrupt = {
        base = 1.00,
        perExtraInterrupter   = -0.03,  -- each OTHER interrupt-capable player beyond the first
        perShortCdInterrupter = -0.02,  -- extra reduction for each OTHER short-CD/high-control kicker
        perHighControlTank    = -0.05,  -- a high-control tank soaks casts -> others expected slightly less
        loneInterrupterBonus  =  0.10,  -- if this player is the ONLY conventional interrupter, expect a bit more
    },
    dispel = {
        base = 1.00,
        perExtraDispeller = -0.03,      -- each OTHER player who can cover the same dispel role
        loneDispellerBonus = 0.08,
    },
}

----------------------------------------------------------------------
-- Throughput. Role-specific. DPS/tanks primarily judged on damage (per-role), healers on healing
-- with a SOFT CAP (high HPS often means the group ate avoidable damage - never auto-rewarded).
-- Scored vs a baseline (Baselines.lua: same-spec historical median when available, else static role
-- reference). ratioToScore reuses a gentle curve so 1.0x baseline ~= 85 ("meeting expectations").
----------------------------------------------------------------------
Config.throughput = {
    -- ratio (value/baseline) -> score, interpolated. SOFT-CAPPED at 1.0: meeting your expected group
    -- share = full marks (100). Doing MORE than your share neither helps nor hurts (the curve plateaus
    -- - interp clamps to the last point), and your excess is also removed from the baseline the group
    -- is measured against (see EffectiveGroupTotals), so out-DPSing your share never drags anyone down
    -- (teammates OR yourself). Underperforming your share is what costs you.
    curve = {
        { ratio = 0.00, score = 0 },
        { ratio = 0.40, score = 40 },
        { ratio = 0.65, score = 64 },
        { ratio = 0.80, score = 80 },
        { ratio = 0.90, score = 90 },
        { ratio = 1.00, score = 100 },   -- meeting expected = max; ratios above 1.0 stay at 100
    },
    -- GROUP-RELATIVE baselines (deterministic - no self-learning, so scores match across installs).
    -- Each player's EXPECTED value for a metric = groupTotal(metric) * theirShare / sum(shares).
    -- `groupShare` = the relative amount of a metric each role is expected to contribute.
    -- Calibrated against 17 observed Midnight S1 runs (85 player-rows, mostly +10): median role ratios
    -- were TANK dps 0.55 / HEALER dps 0.12 of a DPS, and TANK hps 0.51 / DAMAGER hps 0.09 of a healer -
    -- so tank DAMAGE was under-credited (0.35) and off-heals under-counted. Ratios (not absolutes) travel
    -- across gear, so this stays valid as numbers inflate. Refine as more runs accumulate.
    groupShare = {
        dps = { DAMAGER = 1.00, TANK = 0.55, HEALER = 0.12 },
        -- HPS counts for healers AND tanks (self-healing). Tanks then scaled by spec "healiness" below.
        hps = { HEALER = 1.00, TANK = 0.51, DAMAGER = 0.09 },
    },
    -- Tank self-healing varies a LOT by spec; this multiplies the TANK hps share (1.0 = a standard
    -- tank). Death Strike / Fel Devastation tanks self-heal far more than a Prot Warrior.
    -- Research: warcraft.wiki.gg tank kits + Midnight tuning; refine against real logs.
    tankHealiness = {
        [250] = 1.35,   -- Blood DK       (Death Strike) - very healy
        [581] = 1.20,   -- Vengeance DH   (Soul Cleave / Fel Devastation)
        [104] = 1.15,   -- Guardian Druid (v37: 0.95->1.15; observed self-cover 1.20, Frenzied Regen out-heals the old target)
        [268] = 0.58,   -- Brewmaster Monk(v37: 0.70->0.58 -> coverage floors at 0.45. Investigation: the meter
                        --                 records NO absorbs for Brew (Stagger self-mitigation is invisible) while
                        --                 damageTaken stays ~100M+, so Brew is structurally healer-reliant and
                        --                 under-counted. Lower expectation centers it; it can't be fully fixed
                        --                 without a Stagger signal the meter doesn't expose.)
        [66]  = 1.00,   -- Prot Paladin   (v37: 0.85->1.00; observed self-cover 1.16, Word of Glory covers more than modeled)
        [73]  = 0.60,   -- Prot Warrior   (Victory Rush / Ignore Pain absorbs) - least self-healing
    },
    -- How a role's throughput blends DPS vs HPS. Tanks are overridden per-spec by healiness below.
    metricMix = {
        DAMAGER = { dps = 1.00, hps = 0.00 },
        HEALER  = { dps = 0.15, hps = 0.85 },
        TANK    = { dps = 0.60, hps = 0.40 },   -- base; healy tanks lean more on hps (see ThroughputMix)
    },
    -- Static fallback (only used if the group produced no total for a metric, e.g. metadata-only run).
    -- Set to the observed EARLY-Midnight +10 medians (DPS ~114K / tank ~63K / healer HPS ~58K). These are
    -- absolute so they drift up with gear - only the metadata-only path uses them, so it's low-stakes; bump
    -- as the season progresses. Normal runs are group-relative and gear-agnostic.
    staticReference = {
        DAMAGER = { metric = "dps", value = 114000 },
        TANK    = { metric = "dps", value = 63000 },
        HEALER  = { metric = "hps", value = 58000 },
    },
    -- Healer HPS soft cap: above softCapRatio of baseline, extra HPS yields sharply less (excess
    -- healing usually = avoidable damage taken, which is penalized under survival instead).
    healerSoftCapRatio = 1.15,

    -- Item-level adjustment (v40). Throughput is the ONE category where gear genuinely changes output, so
    -- we nudge the DPS EXPECTATION by a player's item level vs the GROUP AVERAGE: the lowest-geared member
    -- isn't punished for output their gear can't reach, and out-gearing the group doesn't read as skill.
    -- factor = clamp(1 + perIlvl*(ilvl - groupAvg), clampLo, clampHi), applied to the DPS baseline only
    -- (HPS uses the damage-taken requirement, which gear affects far less). Bounded & small - it never
    -- dominates. Applied ONLY when we know at least minCoverage of the party's ilvl (else factor = 1).
    -- perIlvl 0.01 ~= WoW's real ~1%/ilvl gear scaling (measured 1.18%/ilvl on full-inspect beta runs).
    ilvlAdjust = { enabled = true, perIlvl = 0.01, clampLo = 0.80, clampHi = 1.20, minCoverage = 0.8 },

    -- Outcome floor (v40; v42 → full marks). A HEALER who TIMED the key with no deaths healed enough BY
    -- DEFINITION - the group lived and the key was made - so the HEALING HALF of throughput is lifted toward
    -- a PERFECT 100 (not a neutral 75) in proportion to how clean the run was. Applied to the HPS component
    -- ONLY (their damage is still graded normally); death-gated (clean = clamp(1 - partyDeaths/deathK, 0, 1))
    -- so a disaster run keeps its low score; NEVER lowers a score. lifted = raw + clean*strength*(target-raw).
    outcomeFloor = { enabled = true, roles = { HEALER = true }, target = 100, deathK = 3, strength = 1.0 },
    -- Support / buff DPS (e.g. Augmentation Evoker) do less PERSONAL damage because they inflate
    -- everyone else's. We drop their throughput bar to `selfShare` of a normal DPS and hand the freed
    -- share to the teammates they're pumping - so the aug isn't punished for buffing, and the buffed
    -- teammates aren't over-credited for numbers the aug is really producing. `redistribute` deltas are
    -- ADDED to each role's DPS share and sum to (1 - selfShare), so the group's total expected damage is
    -- conserved (the DAMAGER delta is split evenly across the non-aug DPS). DPS shares only - it's a
    -- damage buff, so HPS bars are untouched. Applied per aug present (M+ is effectively always <= 1).
    augmentation = {
        specs = { [1473] = true },   -- Augmentation Evoker
        selfShare = 0.5,             -- an aug's personal bar = half a normal DPS...
        redistribute = { DAMAGER = 0.35, TANK = 0.10, HEALER = 0.05 },  -- ...the freed 0.5 goes here
    },
}

-- A player's SHARE weight for a metric (drives the group-relative expected value). Deterministic.
-- `aug` (optional) = the run's Augmentation context { count, nNonAugDPS } from Comp.Summarize; when a
-- support/buff DPS is present it reshapes the DPS shares (aug down, teammates up) - see throughput.augmentation.
function Config.ThroughputShare(metric, role, specID, aug)
    local gs = Config.throughput.groupShare[metric]
    local base = (gs and gs[role or "DAMAGER"]) or 0
    if metric == "hps" and role == "TANK" then
        base = base * (Config.throughput.tankHealiness[specID] or 1.0)
    end
    -- Augmentation (support DPS) reshapes DPS shares only: the aug's bar drops, the freed share is
    -- handed to the teammates it buffs. Conserves the total DPS share so gDPS is redistributed, not lost.
    if metric == "dps" and aug and (aug.count or 0) > 0 then
        local A = Config.throughput.augmentation
        if role == "DAMAGER" and A.specs[specID] then
            base = base * A.selfShare                                        -- the aug itself
        elseif role == "DAMAGER" and (aug.nNonAugDPS or 0) > 0 then
            base = base + (A.redistribute.DAMAGER or 0) * aug.count / aug.nNonAugDPS
        elseif role == "TANK" then
            base = base + (A.redistribute.TANK or 0) * aug.count
        elseif role == "HEALER" then
            base = base + (A.redistribute.HEALER or 0) * aug.count
        end
    end
    return base
end

-- A tank/healer/dps throughput blend {dps=, hps=}. Tanks lean more on HPS the healier the spec is.
function Config.ThroughputMix(role, specID)
    local m = Config.throughput.metricMix[role] or Config.throughput.metricMix.DAMAGER
    if role == "TANK" then
        local heal = Config.throughput.tankHealiness[specID] or 1.0
        local hpsW = Config.clamp(m.hps * heal, 0.12, 0.55)
        return { dps = 1 - hpsW, hps = hpsW }
    end
    return { dps = m.dps, hps = m.hps }
end

----------------------------------------------------------------------
-- Healing REQUIREMENT model (Scoring/Healing.lua). Replaces the group-relative HPS baseline for
-- tanks & healers with a target derived from the damage the group actually took:
--   required(p)   = damageTaken(p) - avoidableDamageTaken(p)        (unavoidable HP lost)
--   tank target   = tankSelfCoverage(spec) x required(tank)         (tank self-covers this much)
--   healer target = (1 - coverage) x required(tank)                 (the tank's remainder)
--                 + groupSelfHealFactor x (required(nonTank) + avoidableCredit x avoidable(nonTank))
-- A group standing in bad inflates their OWN Survival penalty, not the healer's target (avoidableCredit
-- keeps the healer only lightly on the hook for others' mistakes). Output = healing + absorbs (shields
-- count; absorb healers aren't penalised). All knobs here.
----------------------------------------------------------------------
Config.healing = {
    enabled = true,
    -- Fraction of the tank's UNAVOIDABLE damage the tank is expected to self-cover (rest -> healer).
    -- Derived from tankHealiness so there's ONE source of truth: a healy tank self-covers more.
    -- v35: raised 0.55 -> 0.78 - observed tank output/requirement ran 1.25-1.54 across 32 runs (tanks
    -- vastly over-covered), while healers ran 0.84 (target too high). Raising this both lifts the tank
    -- target AND shrinks the healer's tank-remainder term: healer median 0.84 -> 1.08, tanks toward 1.0.
    tankSelfCoverageBase = 0.78,   -- a "standard" tank (healiness 1.0) self-covers 78%
    tankSelfCoverageMin  = 0.45,
    tankSelfCoverageMax  = 0.90,
    -- How much of the GROUP's avoidable damage still counts toward the healer's target (light triage);
    -- 0 = healer not responsible for standers at all, 1 = fully on the hook. 0.25 = cover ~a quarter.
    avoidableCredit = 0.25,
    -- Non-tank players self-heal / defensive more of their own damage than first modeled; the healer
    -- covers the rest. v35: 0.90 -> 0.80 (healer median 0.84). v37: 0.80 -> 0.85 to re-center - raising
    -- Guardian/ProtPal self-coverage shrank the healer's tank-remainder and pushed the healer median to
    -- 1.16 (past the soft-cap); this brings it back into the 1.05-1.10 band.
    groupSelfHealFactor = 0.85,
    -- If < this fraction of the party reported damageTaken we can't trust the model -> fall back to the
    -- group-relative HPS baseline for that run.
    minPartyCoverage = 0.60,
}

-- Tank self-coverage fraction for a spec, derived from throughput healiness (single source of truth).
function Config.TankSelfCoverage(specID)
    local h = Config.healing
    local heal = Config.throughput.tankHealiness[specID] or 1.0
    return Config.clamp(h.tankSelfCoverageBase * heal, h.tankSelfCoverageMin, h.tankSelfCoverageMax)
end

----------------------------------------------------------------------
-- Survival. Scored ENTIRELY on the AVOIDABLE SHARE of your total damage taken (avoidable / taken) - a
-- scale-free fraction that doesn't depend on key level, health pools, dungeon, or role, so it's the
-- one survival metric we can calibrate defensibly without learned data. There is no per-minute or
-- absolute-magnitude component: what matters is how much of everything that hit you was your fault.
----------------------------------------------------------------------
-- 3.5% grace = a perfect 100 (nobody plays truly clean), then it DOWNGRADES QUICKLY, hitting 0 once
-- 50% of your total damage taken was avoidable. Standing in the shit is exactly what this punishes.
Config.survival = {
    graceShare = 0.035,   -- avoidable share at/under this = 100 (the curve encodes it; kept for docs/UI)
    zeroShare  = 0.50,    -- avoidable share at/over this  = 0   (the curve encodes it; kept for docs/UI)
    -- Avoidable as a fraction of total damage taken (0..1). Flat 100 through the grace band, then a
    -- steep front-loaded drop to 0 at a 50% share. interp() clamps the ends (>=0.50 -> 0, <=0.035 -> 100).
    avoidableShareCurve = {
        { v = 0.000, s = 100 },
        { v = 0.035, s = 100 },   -- 3.5% grace -> still perfect
        { v = 0.07,  s = 87 },    -- ...then it bites, fast
        { v = 0.10,  s = 72 },
        { v = 0.15,  s = 55 },
        { v = 0.23,  s = 36 },
        { v = 0.31,  s = 22 },
        { v = 0.40,  s = 10 },
        { v = 0.50,  s = 0 },     -- 50% of your damage taken was avoidable -> zero
    },
    neutralScore = 80,   -- used only when avoidable or taken data is missing entirely
}

----------------------------------------------------------------------
-- Deaths. Death Impact (NOT responsibility). Escalating, capped. Score = 100 - penalty.
----------------------------------------------------------------------
-- Flat, heavy death penalty: -25 for EVERY death -> category 1=75, 2=50, 3=25, 4+=0. Combined with
-- the heavy 0.20 weight, dying is the single most costly thing you can do.
Config.deaths = {
    penalties = { 25 },   -- flat -25 for the first death...  (fallback: runs with no cause breakdown)
    perExtra = 25,        -- ...and -25 for every death after (2nd, 3rd, ...)
    maxPenalty = 100,     -- caps the total penalty; the Death category floors at 0
    baseScore = 100,
    -- Cause-weighted per-death penalty (v38) when the run captured the death-recap breakdown. Points off
    -- the 0-100 Death category (so x0.20 weight => -6 / -2 / -1 on the final grade per death). Avoidable
    -- deaths (stood in it) hurt most; threat deaths (melee while not tanking - lost aggro) hurt least.
    -- `kickable` = death to a cast that should have been interrupted; weighted the same as `other` for now.
    causePenalties = { avoidable = 30, other = 10, kickable = 10, threat = 5 },
}

----------------------------------------------------------------------
-- Review / coaching bands. A deterministic state classifier over category scores: each category's
-- 0..100 score maps to a named state, which drives the plain-language "did well / work on" player
-- review. No new data and no learning - it reads the SAME category results the grade is built from,
-- so the review can never disagree with the score. strongMin = counts as a strength; improveBelow =
-- flagged for improvement (candidates are ranked by weight x point-deficit, i.e. highest leverage first).
----------------------------------------------------------------------
-- Strengths and improvements split cleanly at 90: meeting expectations is a genuine 90+, and anything
-- below that is "less than ideal" and earns a concrete suggestion (e.g. a 79 survival -> "avoid damage").
Config.review = {
    excellentMin = 95,   -- met or beat expectations - effectively maxed
    strongMin    = 90,   -- >= this is a strength worth calling out (and NOT flagged for improvement)
    solidMin     = 72,   -- meeting the bar
    softMin      = 55,   -- shaky; below this is WEAK
    improveBelow = 90,   -- applicable categories under this become improvement candidates (< strongMin)
}

----------------------------------------------------------------------
-- Grades. First threshold whose min <= overall wins (evaluated high -> low).
----------------------------------------------------------------------
Config.grades = {
    { min = 100, grade = "S+" },   -- a flawless run: every applicable category scored a perfect 100
    { min = 97, grade = "S"  }, { min = 93, grade = "A+" }, { min = 89, grade = "A"  },
    { min = 85, grade = "A-" }, { min = 80, grade = "B+" }, { min = 75, grade = "B"  },
    { min = 70, grade = "B-" }, { min = 65, grade = "C+" }, { min = 60, grade = "C"  },
    { min = 50, grade = "D"  }, { min = 0,  grade = "F"  },
}

----------------------------------------------------------------------
-- Learned baselines. Blend static -> learned as comparable-sample count grows. Not abrupt.
----------------------------------------------------------------------
Config.learned = {
    minSamples = 20,          -- full confidence in the learned median at/after this many comparable runs
    minBucketSamples = 3,     -- a learned bucket needs at least this many samples before it's used at all
    -- learnedConfidence = clamp(n / minSamples). final = static*(1-c) + learnedMedian*c.
    keyBrackets = { 0, 5, 8, 11, 14, 17, 20 },        -- lower bounds; a run maps to its bracket floor
    durationBracketsMin = { 0, 20, 28, 36 },          -- minutes; lower bounds
}

-- Interpolate a value across an ordered list of {x=,y=} (or {ratio=,score=}/{v=,s=}) points.
-- Clamps to the endpoints. Shared helper so every curve behaves identically.
function Config.interp(points, x, xk, yk)
    xk, yk = xk or "ratio", yk or "score"
    if x <= points[1][xk] then return points[1][yk] end
    local last = points[#points]
    if x >= last[xk] then return last[yk] end
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if x <= b[xk] then
            local t = (x - a[xk]) / (b[xk] - a[xk])
            return a[yk] + (b[yk] - a[yk]) * t
        end
    end
    return last[yk]
end

function Config.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

-- Validate the weight tables sum to 1.0 (dev safety; logs, never errors at runtime).
function Config.Validate()
    local ok = true
    for role, w in pairs(Config.roleWeights) do
        local s = 0; for _, v in pairs(w) do s = s + v end
        if math.abs(s - 1.0) > 1e-6 then ok = false; if ML.Log then ML.Log("Scoring: roleWeights[%s] sums to %.4f (expected 1.0)", role, s) end end
    end
    for cat, byRole in pairs(Config.redistribution) do
        for role, rule in pairs(byRole) do
            local s = 0; for _, v in pairs(rule) do s = s + v end
            if math.abs(s - 1.0) > 1e-6 then ok = false; if ML.Log then ML.Log("Scoring: redistribution[%s][%s] sums to %.4f", cat, role, s) end end
        end
    end
    return ok
end
