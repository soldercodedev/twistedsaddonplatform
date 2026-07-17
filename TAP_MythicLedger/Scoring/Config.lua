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
Config.version = 14

Config.roles = { "TANK", "HEALER", "DAMAGER" }

----------------------------------------------------------------------
-- Category weights per role (must each sum to 1.0; validated at load). Six categories:
-- throughput, interrupts, dispels, survival, deaths, roleContribution. "Utility" in the brief =
-- interrupts + dispels. When a utility category is N/A for a spec these are redistributed
-- deterministically by Weights.lua.
----------------------------------------------------------------------
-- Deaths carry a HEAVY weight (0.18): dying should visibly tank the overall, not just nudge it.
Config.roleWeights = {
    DAMAGER = { throughput = 0.27, interrupts = 0.18, dispels = 0.12, survival = 0.25, deaths = 0.18, roleContribution = 0.00 },
    TANK    = { throughput = 0.16, interrupts = 0.18, dispels = 0.12, survival = 0.30, deaths = 0.18, roleContribution = 0.06 },
    HEALER  = { throughput = 0.17, interrupts = 0.15, dispels = 0.15, survival = 0.30, deaths = 0.18, roleContribution = 0.05 },
}

-- Deterministic redistribution when a utility category is not applicable. Fractions of the freed
-- weight, per role. Must sum to 1.0 each (validated). Never dumps everything into throughput.
Config.redistribution = {
    interrupts = {
        DAMAGER = { throughput = 0.50, survival = 0.50 },
        TANK    = { survival = 0.50, roleContribution = 0.30, throughput = 0.20 },
        HEALER  = { dispels = 0.50, survival = 0.25, roleContribution = 0.25 },
    },
    dispels = {
        DAMAGER = { throughput = 0.40, survival = 0.30, interrupts = 0.30 },
        TANK    = { survival = 0.40, interrupts = 0.30, roleContribution = 0.30 },
        HEALER  = { throughput = 0.40, survival = 0.30, interrupts = 0.30 },
    },
    -- If BOTH utility categories are N/A, this flat split of their combined weight is used instead.
    utilityBoth = {
        DAMAGER = { throughput = 0.50, survival = 0.50 },
        TANK    = { survival = 0.60, roleContribution = 0.40 },
        HEALER  = { throughput = 0.45, survival = 0.35, roleContribution = 0.20 },
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
Config.interruptProfiles = {
    NONE         = { ratePerMinute = 0.00, scoreEligible = false },
    LONG_CD      = { ratePerMinute = 0.18, scoreEligible = true },   -- ~24-60s CD, ranged (Counterspell/Counter Shot/Quell/Solar Beam; Resto Shaman's 30s Wind Shear in Midnight)
    STANDARD     = { ratePerMinute = 0.30, scoreEligible = true },   -- ~15s CD single interrupt (Kick/Pummel/Rebuke/Mind Freeze/Muzzle/Spear Hand)
    SHORT_CD     = { ratePerMinute = 0.40, scoreEligible = true },   -- <=12s CD (Elemental/Enhancement Wind Shear; Resto's is now 30s -> LONG_CD)
    HIGH_CONTROL = { ratePerMinute = 0.48, scoreEligible = true },   -- 15s interrupt + strong extra ranged stop/silence used rotationally (Prot Pal, DH)
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
    kickUtil = 0.075,   -- fraction of raw interrupt AVAILABILITY that becomes an actual kick in M+
    stopLikelihood = { HIGH = 0.60, MEDIUM = 0.30, LOW = 0.10 },   -- how often a rotational extra stop is spent interrupting
    countedStopTypes = { INTERRUPT = true, SILENCE = true },        -- a STUN doesn't lock a school like a kick -> not counted
}

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

-- Dispel profiles. ratePerMinute = expected dispel CONTRIBUTIONS per minute given dispel access.
-- Most DPS have only a curse/poison/offensive-purge tool used situationally -> LIMITED. Healers with
-- full defensive dispel -> STANDARD/HIGH.
Config.dispelProfiles = {
    NONE         = { ratePerMinute = 0.00, scoreEligible = false },
    LIMITED      = { ratePerMinute = 0.10, scoreEligible = true },   -- one narrow tool (Remove Curse, Cleanse Toxins, offensive purge only)
    STANDARD     = { ratePerMinute = 0.22, scoreEligible = true },   -- full defensive dispel (healers, Mistweaver Detox)
    HIGH_UTILITY = { ratePerMinute = 0.30, scoreEligible = true },   -- broad dispel + Mass Dispel / multi-type (Priest, Preservation)
}

----------------------------------------------------------------------
-- Per-dungeon dispellable-content TYPES. Dispels are gated to schools/types (magic, curse, poison,
-- disease, enrage), and some dungeons have NOTHING a given tool can touch. A spec whose dispel type
-- doesn't appear in the dungeon shouldn't be expected to dispel: its Dispel category goes N/A (weight
-- redistributed) instead of being punished for having no valid target. COARSE by design - just which
-- of the five types appear in that dungeon, not per-spell or per-boss (we have no combat log, only
-- aggregate counts). Keyed by NORMALISED dungeon name (lowercase, letters+digits only) so it matches
-- the live API name regardless of apostrophes/spacing. Maintained per season from the M+ dispel guide.
--
-- EDITING ASYMMETRY: a wrong `true` is harmless (spec stays eligible; the confidence blend still
-- protects a genuinely quiet run), but a wrong `false` can unfairly BENCH a real dispeller. So only set
-- a type false once CONFIRMED absent; leave it true when unsure. An UNLISTED dungeon = fully eligible;
-- the table only ever RESTRICTS. Sources: Wowhead "Important Dispels in Midnight S1 M+", gerritalex.de.
----------------------------------------------------------------------
Config.dungeonDispelTypes = {
    -- ["<normname>"] = { <type> = false | <demandWeight> },  per dispel type:
    --     false   -> that type is ABSENT here. GATE: a spec whose only dispel types are all absent -> N/A.
    --     number  -> PRESENT, carrying a per-type DEMAND weight (1.0 = typical volume; >1 heavy, <1 light).
    --     omitted -> PRESENT at the default 1.0 demand.
    --
    -- PRESENCE is set false only when CONFIRMED absent from the dungeon's WHOLE dispellable inventory.
    -- Every S1 dungeon has magic content, so magic dispellers are never gated; the gate only benches a
    -- NARROW tool (curse-only Mage, enrage-only Shiv/Soothe, poison-only) where its type is absent.
    -- Cross-checked 2026-07 against gerritalex.de's full S1 debuff list and the Wowhead / masterofwarcraft
    -- dispel guides (agreed, no contradictions). Bleeds aren't standard-dispellable, so a bleed-only
    -- source does NOT make a type present (Skyreach Blade Rush, Algeth'ar Vile Bite).
    --
    -- DEMAND weights come from the COUNT of distinct dispellable debuff SOURCES of each type (a breadth
    -- proxy - the guides give inventory, not cast frequency), normalised so a typical load = 1.0. Magic is
    -- the only type with real per-dungeon spread (2-11 sources); other types sit near 1.0 where present. A
    -- spec's expected dispels scale by the MAX weight among the types it can address here (DungeonDispelDemand).
    -- These are estimates from breadth, NOT measured casts - recalibrate against real logged runs later.
    ["magistersterrace"]     = { magic = 1.40, curse = false, poison = false, disease = false, enrage = false }, -- 11 magic (Polymorph, Holy Fire, Umbral Splinters, Void Torrent, Arcane Blade...)
    ["maisaracaverns"]       = { magic = 1.20, disease = 0.90, enrage = 0.90, curse = false, poison = false },   -- 7 magic (Hex, Spirit Rend, Frost Nova) + disease (Infected Pinions) + enrage (Blood Frenzy)
    ["nexuspointxenas"]      = { magic = 0.95, curse = 1.00, poison = false, disease = false, enrage = false },  -- 3 magic (Burning Radiance, Transference) + 2 curse (Bad Omens, Creeping Void)
    ["windrunnerspire"]      = { magic = 0.85, curse = 1.00, poison = 1.05, enrage = 0.90, disease = false },    -- 2 magic (Soul Torment) + 2 curse (Curse of Darkness) + 2 poison (Poison Blades/Spray) + 1 enrage
    ["algetharacademy"]      = { magic = 0.95, poison = 0.90, enrage = 1.05, curse = false, disease = false },   -- 3 magic (Energy Bomb, Oversurge) + poison (Lasher Toxin) + 2 enrage (Agitation, Raging Screech)
    ["pitofsaron"]           = { magic = 1.10, curse = 1.00, disease = 1.05, enrage = 0.90, poison = false },    -- 5 magic (Permeating Cold) + 2 curse (Curse of Torment, Shadowbind) + 2 disease (Rotting Strikes) + 1 enrage
    ["seatofthetriumvirate"] = { magic = 1.00, enrage = 0.90, curse = false, poison = false, disease = false }, -- 4 magic (Rift Essence, Corrupting Touch, Howling Dark) + enrage (Battle Rage)
    ["skyreach"]             = { magic = 0.85, enrage = 0.90, curse = false, poison = false, disease = false }, -- 2 magic (Rushing Winds, Solar Barrier) + enrage (Wrathful Wind)
}

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

-- Does a spec's dispel (specTypes set) overlap the dungeon's dispellable content? Unknown dungeon or a
-- type not marked false -> treated as PRESENT (eligible). Empty spec set -> not eligible (nothing to do).
function Config.DungeonDispelEligible(dungeonName, specTypes)
    if type(specTypes) ~= "table" or not next(specTypes) then return false end
    local entry = Config.dungeonDispelTypes[Config.NormDungeon(dungeonName) or ""]
    if not entry then return true end            -- unlisted dungeon: never restrict
    for t in pairs(specTypes) do
        if entry[t] ~= false then return true end   -- this dispel type is present here -> overlap
    end
    return false                                  -- none of the spec's dispel types appear in this dungeon
end

-- Per-dungeon dispel DEMAND multiplier for a spec: how dispel-heavy this dungeon is for the TYPES this
-- spec can address, as a scalar on expected dispels. Uses the MAX weight among the spec's present types
-- (your busiest dispellable type sets the pace) so a broad healer isn't inflated just for covering more
-- types, and a narrow tool is judged only on its own type's load. 1.0 for an unlisted dungeon, an empty
-- spec set, or a present type with no explicit weight. Only meaningful when DungeonDispelEligible is true.
function Config.DungeonDispelDemand(dungeonName, specTypes)
    if type(specTypes) ~= "table" then return 1.0 end
    local entry = Config.dungeonDispelTypes[Config.NormDungeon(dungeonName) or ""]
    if not entry then return 1.0 end             -- unlisted dungeon: neutral demand
    local best
    for t in pairs(specTypes) do
        local v = entry[t]
        if v ~= false then                        -- a type this spec can dispel that is present here
            local w = (type(v) == "number") and v or 1.0
            if not best or w > best then best = w end
        end
    end
    return best or 1.0
end

----------------------------------------------------------------------
-- Per-dungeon dispellable effects, keyed by normalised dungeon name -> dispel type -> list of
-- { name, id, kind }. This is the granular half of the seasonal dispel DB (presence/demand is
-- Config.dungeonDispelTypes above). It lets the run-review coach a player with the exact ability icons
-- (via `id`, the real spell id -> Blizzard tooltip) and split them into what they'd DISPEL vs PURGE:
--   kind = "debuff" -> a harmful aura ON A PLAYER, removed by a DEFENSIVE dispel (Dispel)
--   kind = "buff"   -> a beneficial aura ON AN ENEMY, removed by an OFFENSIVE dispel (Purge; enrage = Soothe)
--
-- Names + spell ids sourced 2026-07 from gerritalex.de's full S1 debuff list (its JSON exposes ids).
-- The buff/debuff split is OUR classification from the mechanic: enrage is always an enemy buff; magic
-- "Ward / Shield / Barrier / Bolstering / Enhancement / Bloodlust" effects are enemy buffs you Purge;
-- everything else (CC, DoTs, curses, poisons, diseases) is a player debuff you Dispel. A handful are
-- best-guesses (Oversurge, Necromantic Infusion, Rushing Winds) - the Blizzard tooltip shows the truth
-- on hover regardless. Keep in sync with the type presence in Config.dungeonDispelTypes each season.
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
    local entry = nk and Config.dungeonDispelTypes[nk]
    if not entry then return out end             -- unlisted dungeon: no known targets
    local byType = (nk and Config.dungeonDispelDebuffs[nk]) or {}
    local defensive, offensive = dispel.defensive or {}, dispel.offensive or {}
    for _, t in ipairs(DISPEL_TYPE_ORDER) do
        if entry[t] ~= false then                 -- type present in this dungeon
            for _, e in ipairs(byType[t] or {}) do
                if e.kind == "buff" and offensive[t] then
                    out[#out + 1] = { name = e.name, id = e.id, type = t, action = (t == "enrage") and "Soothe" or "Purge" }
                elseif e.kind ~= "buff" and defensive[t] then
                    out[#out + 1] = { name = e.name, id = e.id, type = t, action = "Dispel" }
                end
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
    groupShare = {
        dps = { DAMAGER = 1.00, TANK = 0.35, HEALER = 0.08 },
        -- HPS counts for healers AND tanks (self-healing). Healer:Tank base ~ 60/40; tanks then
        -- scaled by spec "healiness" below. DPS off-heals count for very little.
        hps = { HEALER = 1.00, TANK = 0.62, DAMAGER = 0.04 },
    },
    -- Tank self-healing varies a LOT by spec; this multiplies the TANK hps share (1.0 = a standard
    -- tank). Death Strike / Fel Devastation tanks self-heal far more than a Prot Warrior.
    -- Research: warcraft.wiki.gg tank kits + Midnight tuning; refine against real logs.
    tankHealiness = {
        [250] = 1.35,   -- Blood DK       (Death Strike) - very healy
        [581] = 1.20,   -- Vengeance DH   (Soul Cleave / Fel Devastation)
        [104] = 0.95,   -- Guardian Druid (Frenzied Regen / passive)
        [268] = 0.95,   -- Brewmaster Monk(Expel Harm / Vivify; stagger is absorbs, not healing)
        [66]  = 0.85,   -- Prot Paladin   (Word of Glory)
        [73]  = 0.60,   -- Prot Warrior   (Victory Rush / Ignore Pain absorbs) - least self-healing
    },
    -- How a role's throughput blends DPS vs HPS. Tanks are overridden per-spec by healiness below.
    metricMix = {
        DAMAGER = { dps = 1.00, hps = 0.00 },
        HEALER  = { dps = 0.15, hps = 0.85 },
        TANK    = { dps = 0.60, hps = 0.40 },   -- base; healy tanks lean more on hps (see ThroughputMix)
    },
    -- Static fallback (only used if the group produced no total for a metric, e.g. metadata-only run).
    staticReference = {
        DAMAGER = { metric = "dps", value = 900000 },
        TANK    = { metric = "dps", value = 500000 },
        HEALER  = { metric = "hps", value = 450000 },
    },
    -- Healer HPS soft cap: above softCapRatio of baseline, extra HPS yields sharply less (excess
    -- healing usually = avoidable damage taken, which is penalized under survival instead).
    healerSoftCapRatio = 1.15,
}

-- A player's SHARE weight for a metric (drives the group-relative expected value). Deterministic.
function Config.ThroughputShare(metric, role, specID)
    local gs = Config.throughput.groupShare[metric]
    local base = (gs and gs[role or "DAMAGER"]) or 0
    if metric == "hps" and role == "TANK" then
        base = base * (Config.throughput.tankHealiness[specID] or 1.0)
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
-- Survival. Scored ENTIRELY on the AVOIDABLE SHARE of your total damage taken (avoidable / taken) - a
-- scale-free fraction that doesn't depend on key level, health pools, dungeon, or role, so it's the
-- one survival metric we can calibrate defensibly without learned data. There is no per-minute or
-- absolute-magnitude component: what matters is how much of everything that hit you was your fault.
----------------------------------------------------------------------
-- 2.5% grace = a perfect 100 (nobody plays truly clean), then it DOWNGRADES QUICKLY, hitting 0 once
-- 40% of your total damage taken was avoidable. Standing in the shit is exactly what this punishes.
Config.survival = {
    graceShare = 0.025,   -- avoidable share at/under this = 100 (the curve encodes it; kept for docs/UI)
    zeroShare  = 0.40,    -- avoidable share at/over this  = 0   (the curve encodes it; kept for docs/UI)
    -- Avoidable as a fraction of total damage taken (0..1). Flat 100 through the grace band, then a
    -- steep front-loaded drop to 0 at a 40% share. interp() clamps the ends (>=0.40 -> 0, <=0.025 -> 100).
    avoidableShareCurve = {
        { v = 0.000, s = 100 },
        { v = 0.025, s = 100 },   -- 2.5% grace -> still perfect
        { v = 0.05,  s = 87 },    -- ...then it bites, fast
        { v = 0.08,  s = 72 },
        { v = 0.12,  s = 55 },
        { v = 0.18,  s = 36 },
        { v = 0.25,  s = 22 },
        { v = 0.32,  s = 10 },
        { v = 0.40,  s = 0 },     -- 40% of your damage taken was avoidable -> zero
    },
    neutralScore = 80,   -- used only when avoidable or taken data is missing entirely
}

----------------------------------------------------------------------
-- Deaths. Death Impact (NOT responsibility). Escalating, capped. Score = 100 - penalty.
----------------------------------------------------------------------
-- Flat, heavy death penalty: -25 for EVERY death -> category 1=75, 2=50, 3=25, 4+=0. Combined with
-- the heavy 0.18 weight, dying is the single most costly thing you can do.
Config.deaths = {
    penalties = { 25 },   -- flat -25 for the first death...
    perExtra = 25,        -- ...and -25 for every death after (2nd, 3rd, ...)
    maxPenalty = 100,     -- 4 deaths fully zeroes the Death Impact category
    baseScore = 100,
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
