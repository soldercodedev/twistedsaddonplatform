-- TAP: Mythic Ledger - Scoring/Seasons/MidnightS1.lua
-- SEASON DATA (not engine). Per-dungeon utility "frequency" profiles that feed the interrupt/dispel
-- supply pools. One profile block per SOURCE:
--   * trash            = the whole dungeon's non-boss packs (one block).
--   * bosses[encID]    = one block per boss encounter (dungeonEncounterID == our run boss.id).
-- Each block:
--   interruptFrequency        = kick supply. UNITS DIFFER BY SOURCE (see below): TRASH is PER-MINUTE, BOSS
--                               is per-KILL. 0 = nothing to kick.
--   partyDebuffFrequencies    = DEFENSIVE dispel: dispellable DEBUFFS on players, per school
--                               (magic/curse/poison/disease). Same per-min (trash) / per-kill (boss) split.
--   targetBuffFrequencies     = OFFENSIVE dispel: on enemies - purge (a magic buff) and enrage (soothe).
-- DURATION-AWARE (2026-07): a run's supply = TRASH weight x run minutes + the per-KILL boss blocks for
-- bosses actually killed. So TRASH numbers are a PER-MINUTE density (a fast clear = fewer castable events);
-- BOSS numbers are per-kill counts (1.0 = a typical kickable/dispellable cast per pull). Trash weights are
-- CALIBRATED to 18 observed Midnight S1 runs: each dungeon's trash interruptFrequency = its observed group
-- kicks/MINUTE at +10 (n=1-5), trash dispel weights scaled toward observed dispels/min (dampened, provisional
-- - dispels are noisy). Skyreach/Nexus/Windrunner are estimates over a 20m reference (no +10 data yet).
-- All are TUNABLE knobs (/mldev tune) - refine as more runs land.
-- Adding a season: copy this file, edit the numbers, register under its season id(s).

local ADDON, ML = ...
ML.Scoring = ML.Scoring or {}
local S = ML.Scoring
S.SeasonData = S.SeasonData or {}

-- Empty-block helpers keep the boss lists terse (missing tables read as "nothing").
local function K(f) return { interruptFrequency = f or 0 } end                       -- kick-only boss
local function KD(f, debuffs) return { interruptFrequency = f or 0, partyDebuffFrequencies = debuffs } end

S.SeasonData["MidnightS1"] = {
    label = "Midnight - Season 1",
    -- C_MythicPlus season id(s) this profile covers. Empty/nil = use as the default (only season loaded).
    seasons = {},
    dungeons = {
        ----------------------------------------------------------------
        ["magistersterrace"] = {
            trash = { interruptFrequency = 1.84,     -- per-min (obs +10: ~1.8 kicks/min, ~42/run over 22.8m, n=3)
                partyDebuffFrequencies = { magic = 0.389 },   -- per-min (magic-heavy)
                targetBuffFrequencies  = { purge = 0.279 } },
            bosses = {
                [3071] = KD(0, { magic = 1.0 }),   -- Arcanotron Custos (Ethereal Shackles)
                [3072] = { interruptFrequency = 0, targetBuffFrequencies = { purge = 1.0 } },   -- Seranel Sunlash (Hastening Ward = purge buff)
                [3073] = K(0),                     -- Gemellus
                [3074] = KD(0, { magic = 1.0 }),   -- Degentrius (Umbral Splinters)
            },
        },
        ----------------------------------------------------------------
        ["skyreach"] = {
            trash = { interruptFrequency = 1.15,     -- per-min (obs: ~1.25 trash kicks/min, n=2 real +2/+11; held slightly under; was 0.335 est)
                partyDebuffFrequencies = { magic = 0.08 },
                targetBuffFrequencies  = { purge = 0.17, enrage = 0.18 } },   -- Solar Barrier/Rushing Winds purge, Wrathful Wind soothe
            bosses = {
                [1698] = K(0),     -- Ranjit (Fan of Blades = Bleed, not dispellable)
                [1699] = K(0),     -- Araknath
                [1700] = K(0),     -- Rukhran
                [1701] = K(1.0),   -- High Sage Viryx (Solar Blast)
            },
        },
        ----------------------------------------------------------------
        ["algetharacademy"] = {
            trash = { interruptFrequency = 1.036,    -- per-min (obs +10: ~1.0 kicks/min, ~23/run over 20.8m, n=5)
                partyDebuffFrequencies = { magic = 0.091 },   -- per-min (light dispel load)
                targetBuffFrequencies  = { enrage = 0.102 } },   -- Agitation / Raging Screech soothe
            bosses = {
                [2562] = K(0),                      -- Vexamus
                [2563] = KD(1.0, { poison = 1.0 }), -- Overgrown Ancient (Lasher Toxin) + add heal kick
                [2564] = K(0),                      -- Crawth
                [2565] = K(0),                      -- Echo of Doragosa
            },
        },
        ----------------------------------------------------------------
        ["pitofsaron"] = {
            trash = { interruptFrequency = 2.748,    -- per-min (obs +10: ~2.7 kicks/min, ~56/run over 19.3m, n=3 - hottest)
                partyDebuffFrequencies = { magic = 0.143, curse = 0.131 },
                targetBuffFrequencies  = { purge = 0.131, enrage = 0.118 } },   -- Necrolink/Deathless Bond purge, Plague Frenzy soothe
            bosses = {
                [1999] = KD(0, { magic = 1.0 }),     -- Forgemaster Garfrost (Cryoshards)
                [2000] = KD(1.0, { disease = 1.0 }), -- Scourgelord Tyrannus (Rotting Strikes) + Plague Bolt kick
                [2001] = KD(1.0, { curse = 1.0 }),   -- Ick and Krick (Shadowbind curse) + Death Bolt kick
            },
        },
        ----------------------------------------------------------------
        ["seatofthetriumvirate"] = {
            trash = { interruptFrequency = 1.81,     -- per-min (obs +10: ~1.8 kicks/min, ~42/run over 21.5m, n=3)
                partyDebuffFrequencies = { magic = 0.213 },
                targetBuffFrequencies  = { enrage = 0.191, purge = 0.106 } },   -- Battle Rage/Devouring Frenzy soothe, Abyssal Enhancement purge
            bosses = {
                [2065] = K(0),     -- Zuraal the Ascended
                [2066] = K(1.0),   -- Saprish (Dread Screech)
                [2067] = K(1.0),   -- Viceroy Nezhar (Mind Blast)
                [2068] = K(0),     -- L'ura
            },
        },
        ----------------------------------------------------------------
        ["maisaracaverns"] = {
            trash = { interruptFrequency = 2.294,    -- per-min (obs +10: ~2.3 kicks/min, ~66/run over 28.1m, n=1 - PROVISIONAL)
                partyDebuffFrequencies = { magic = 0.341 },   -- per-min (n=1, capped 2x - watch this)
                targetBuffFrequencies  = { purge = 0.285, enrage = 0.256 } },   -- Grim Ward purge, Blood Frenzy soothe
            bosses = {
                [3212] = KD(0, { disease = 1.0, magic = 0.5 }), -- Muro'jin and Nekraxx (Infected Pinions + Vilebranch Sting)
                [3213] = K(1.0),                                -- Vordaza (Necrotic Convergence)
                [3214] = KD(0, { magic = 1.0 }),                -- Rak'tul (Cries of the Fallen)
            },
        },
        ----------------------------------------------------------------
        ["nexuspointxenas"] = {
            trash = { interruptFrequency = 1.40,     -- per-min (obs: ~1.44 trash kicks/min, n=2 real +10; was 0.385 est)
                partyDebuffFrequencies = { magic = 0.19, curse = 0.2 },
                targetBuffFrequencies  = { purge = 0.2 } },   -- Holy Echo purge (no soothe on trash)
            bosses = {
                [3328] = K(0),     -- Chief Corewright Kasreth
                [3332] = K(1.0),   -- Corewarden Nysarra (Nullify)
                [3333] = K(0),     -- Lothraxion
            },
        },
        ----------------------------------------------------------------
        ["windrunnerspire"] = {
            trash = { interruptFrequency = 2.0,      -- per-min (obs: ~2.3 trash kicks/min, n=2 real +10; held slightly under; was 0.38 est)
                partyDebuffFrequencies = { magic = 0.17, curse = 0.2, poison = 0.21 },
                targetBuffFrequencies  = { purge = 0.1, enrage = 0.18 } },   -- new content: modest, TUNE
            bosses = {
                [3056] = K(0),                    -- Emberdawn
                [3057] = KD(1.0, { curse = 1.0 }),-- Derelict Duo (Curse of Darkness) + Shadow Bolt kick
                [3058] = K(1.0),                  -- Commander Kroluk (Chain Lightning)
                [3059] = K(0),                    -- The Restless Heart
            },
        },
    },
}
