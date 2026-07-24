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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (5) and dispels (10) observed in this dungeon.
            kicks = {
                { id = 468966, name = "Polymorph", tier = "Must kick", npc = "Arcane Magister", npcId = 232369 },
                { id = 1254294, name = "Pyroblast", tier = "Must kick", npc = "Blazing Pyromancer", npcId = 251861 },
                { id = 1248327, name = "Shadow Bolt", tier = "Must kick", npc = "Dreadful Voidwalker", npcId = 234064 },
                { id = 1264693, name = "Terror Wave", tier = "Must kick", npc = "Void Terror", npcId = 249086 },
                { id = 468962, name = "Arcane Bolt", tier = "Should kick", npc = "Arcane Magister", npcId = 232369 },
            },
            dispels = {
                { id = 1282055, name = "Ethereal Shackles", tier = "High", dtype = "Magic", npc = "Arcane Sentry", npcId = 234062, counts = true },
                { id = 1214038, name = "Ethereal Shackles", tier = "High", dtype = "Magic", npc = "Arcanotron Custos", npcId = 231861, counts = true },
                { id = 1248689, name = "Hastening Ward", tier = "High (remove)", dtype = "Magic", npc = "Seranel Sunlash", npcId = 231863, counts = true },
                { id = 1255187, name = "Holy Fire", tier = "High", dtype = "Magic", npc = "Lightward Healer", npcId = 234486, counts = true },
                { id = 468966, name = "Polymorph", tier = "High", dtype = "Disease/Magic", npc = "Arcane Magister", npcId = 232369, counts = true },
                { id = 1245068, name = "Consuming Void", tier = "Medium", dtype = "Curse/Magic/Poison", npc = "Void Terror", npcId = 249086 },
                { id = 1284627, name = "Umbral Splinters", tier = "Conditional", dtype = "Magic", npc = "Degentrius", npcId = 231865 },
                { id = 1252909, name = "Arcane Blade", tier = "When needed", dtype = "Magic", npc = "" },
                { id = 1265561, name = "Arcane Blade", tier = "When needed", dtype = "Enrage/Magic", npc = "Sunblade Enforcer", npcId = 234124 },
                { id = 1254306, name = "Power Word: Shield", tier = "When needed", dtype = "Magic", npc = "Lightward Healer", npcId = 234486 },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 0.57,   -- only high/must dispels expected
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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (4) and dispels (2) observed in this dungeon.
            kicks = {
                { id = 152953, name = "Blinding Light", tier = "Must kick", npc = "Blinding Sun Priestess", npcId = 79462 },
                { id = 1255377, name = "Repel", tier = "Must kick", npc = "Driving Gale-Caller", npcId = 78932 },
                { id = 154396, name = "Solar Blast", tier = "Must kick", npc = "High Sage Viryx", npcId = 76266 },
                { id = 1254669, name = "Solar Bolt", tier = "Should kick", npc = "Initiate of the Rising Sun", npcId = 79466 },
            },
            dispels = {
                { id = 1254670, name = "Rushing Winds", tier = "High (remove)", dtype = "Enrage/Magic", npc = "Outcast Warrior", npcId = 76205, counts = true },
                { id = 1273356, name = "Solar Barrier", tier = "High (remove)", dtype = "Magic", npc = "Blinding Sun Priestess", npcId = 79462, counts = true },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 1.0,   -- only high/must dispels expected
            trash = { interruptFrequency = 1.15,     -- per-min (obs: ~1.25 trash kicks/min, n=2 real +2/+11; held slightly under; was 0.335 est)
                -- No DEFENSIVE cleanse demand here (v39): every counts=true dispel in the catalog is an
                -- OFFENSIVE enemy buff - Solar Barrier (purge) and Rushing Winds (soothe). The old
                -- partyDebuffFrequencies { magic = 0.08 } was a leftover estimate with no party-debuff content
                -- behind it, so it handed defensive-only healers (Holy Paladin, Resto Druid...) a phantom
                -- cleanse target and scored them 0 for nothing to dispel. Offensive purge/soothe only until a
                -- real party magic debuff is observed here (re-derive from logs via tools/logparse).
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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (5) and dispels (5) observed in this dungeon.
            kicks = {
                { id = 396640, name = "Healing Touch", tier = "Critical", npc = "Ancient Branch", npcId = 196548 },
                { id = 388392, name = "Monotonous Lecture", tier = "Must kick", npc = "Unruly Textbook", npcId = 196044 },
                { id = 1270294, name = "Mystic Brand", tier = "Must kick", npc = "Spectral Invoker", npcId = 196202 },
                { id = 388862, name = "Surge", tier = "Must kick", npc = "Corrupted Manafiend", npcId = 196045 },
                { id = 1279627, name = "Arcane Bolt", tier = "Should kick", npc = "Spectral Invoker", npcId = 196202 },
            },
            dispels = {
                { id = 388392, name = "Monotonous Lecture", tier = "Highest", dtype = "Curse/Magic", npc = "Unruly Textbook", npcId = 196044, counts = true },
                { id = 374350, name = "Energy Bomb", tier = "High", dtype = "Magic", npc = "Echo of Doragosa", npcId = 190609, counts = true },
                { id = 389033, name = "Lasher Toxin", tier = "High (remove)", dtype = "Poison", npc = "Hungry Lasher", npcId = 196642, counts = true },
                { id = 390938, name = "Agitation", tier = "When needed", dtype = "Enrage", npc = "Aggravated Skitterfly", npcId = 197406 },
                { id = 377389, name = "Raging Screech", tier = "When needed", dtype = "Enrage", npc = "Alpha Eagle", npcId = 192333 },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 0.59,   -- only high/must dispels expected
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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (8) and dispels (7) observed in this dungeon.
            kicks = {
                { id = 1278893, name = "Death Bolt", tier = "Must kick", npc = "Krick", npcId = 252621 },
                { id = 1271074, name = "Icy Blast", tier = "Must kick", npc = "Dreadpulse Lich", npcId = 252563 },
                { id = 1271479, name = "Netherburst", tier = "Must kick", npc = "Arcanist Cadaver", npcId = 252603 },
                { id = 1262941, name = "Plague Bolt", tier = "Must kick", npc = "Scourge Plaguespreader", npcId = 254691 },
                { id = 1264186, name = "Shadowbind", tier = "Must kick", npc = "Shade of Krick", npcId = 255037 },
                { id = 1258436, name = "Ice Bolt", tier = "Should kick", npc = "Rimebone Coldwraith", npcId = 252566 },
                { id = 1258997, name = "Plungegrip", tier = "Should kick", npc = "Plungetalon Gargoyle", npcId = 252606 },
                { id = 1258431, name = "Shadow Bolt", tier = "Should kick", npc = "Gloombound Shadebringer", npcId = 252567 },
            },
            dispels = {
                { id = 1261921, name = "Cryoshards", tier = "High", dtype = "Magic", npc = "Forgemaster Garfrost", npcId = 252635, counts = true },
                { id = 1258437, name = "Permeating Cold", tier = "High", dtype = "Magic", npc = "Rimebone Coldwraith", npcId = 252566, counts = true },
                { id = 1258459, name = "Rotting Strikes", tier = "High", dtype = "Disease", npc = "Rotting Ghoul", npcId = 252558, counts = true },
                { id = 1258997, name = "Plungegrip", tier = "Medium", dtype = "?", npc = "Plungetalon Gargoyle", npcId = 252606 },
                { id = 1264186, name = "Shadowbind", tier = "Medium", dtype = "?", npc = "Shade of Krick", npcId = 255037 },
                { id = 1258448, name = "Necromantic Infusion", tier = "When needed", dtype = "Magic", npc = "Deathwhisper Necrolyte", npcId = 252551 },
                { id = 1259132, name = "Plague Frenzy", tier = "When needed", dtype = "Enrage/Magic", npc = "Lumbering Plaguehorror", npcId = 252555 },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 0.66,   -- 84% of dispels are high/must (curated: Rotting Strikes/Permeating Cold/Cryoshards)
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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (6) and dispels (5) observed in this dungeon.
            kicks = {
                { id = 1262526, name = "Abyssal Enhancement", tier = "Must kick", npc = "Dire Voidbender", npcId = 122404 },
                { id = 248831, name = "Dread Screech", tier = "Must kick", npc = "Shadewing", npcId = 125340 },
                { id = 244750, name = "Mind Blast", tier = "Must kick", npc = "Viceroy Nezhar", npcId = 122056 },
                { id = 1277340, name = "Shadowmend", tier = "Must kick", npc = "Ruthless Riftstalker", npcId = 122413 },
                { id = 1262523, name = "Summon Voidcaller", tier = "Must kick", npc = "Dark Conjurer", npcId = 122405 },
                { id = 1262510, name = "Umbral Bolt", tier = "Should kick", npc = "Dark Conjurer", npcId = 122405 },
            },
            dispels = {
                { id = 1280330, name = "Rift Essence", tier = "High", dtype = "Magic", npc = "Rift Warden", npcId = 122571, counts = true },
                { id = 1262509, name = "Chains of Subjugation", tier = "Medium", dtype = "Movement", npc = "Merciless Subjugator", npcId = 124171 },
                { id = 245742, name = "Shadow Pounce", tier = "Conditional", dtype = "Bleed/Curse/Disease/Poison", npc = "Darkfang", npcId = 122319 },
                { id = 1262526, name = "Abyssal Enhancement", tier = "When needed", dtype = "Enrage/Magic", npc = "Dire Voidbender", npcId = 122404 },
                { id = 1264036, name = "Battle Rage", tier = "When needed", dtype = "Enrage/Magic", npc = "Shadowguard Champion", npcId = 122403 },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 0.46,   -- only high/must dispels expected
            trash = { interruptFrequency = 2.2,      -- per-min (v45: recalibrated to observed 2.19 kicks/min over 14 real runs)
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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (10) and dispels (7) observed in this dungeon.
            kicks = {
                { id = 1256008, name = "Hex", tier = "Must kick", npc = "Ritual Hexxer", npcId = 248685 },
                { id = 1257716, name = "Reanimation", tier = "Must kick", npc = "Reanimated Warrior", npcId = 248692 },
                { id = 1256015, name = "Shadow Bolt", tier = "Must kick", npc = "Ritual Hexxer", npcId = 248685 },
                { id = 1263292, name = "Shrink", tier = "Must kick", npc = "Umbral Shadowbinder", npcId = 254740 },
                { id = 1259255, name = "Spirit Rend", tier = "Must kick", npc = "Tormented Shade", npcId = 249036 },
                { id = 1266381, name = "Hooked Snare", tier = "Should kick", npc = "Keen Headhunter", npcId = 242964 },
                { id = 1259182, name = "Piercing Screech", tier = "Should kick", npc = "Gloomwing Bat", npcId = 253473 },
                { id = 1264327, name = "Shadowfrost Blast", tier = "Should kick", npc = "Hollow Soulrender", npcId = 249024 },
                { id = 1254010, name = "Eternal Suffering", tier = "unset", npc = "Malignant Soul", npcId = 251674 },
                { id = 1250708, name = "Necrotic Convergence", tier = "unset", npc = "Vordaza", npcId = 248595 },
            },
            dispels = {
                { id = 1260709, name = "Vilebranch Sting", tier = "High", dtype = "Disease/Magic", npc = "Muro'jin", npcId = 247570, counts = true },
                { id = 1271623, name = "Frost Nova", tier = "Medium", dtype = "Disease/Magic", npc = "Hollow Soulrender", npcId = 249024 },
                { id = 1256008, name = "Hex", tier = "Medium", dtype = "Disease/Magic", npc = "Ritual Hexxer", npcId = 248685 },
                { id = 1262411, name = "Ritual Firebrand", tier = "Medium", dtype = "Disease/Magic", npc = "Hex Guardian", npcId = 253302 },
                { id = 1259255, name = "Spirit Rend", tier = "Conditional", dtype = "Magic", npc = "Tormented Shade", npcId = 249036 },
                { id = 1255765, name = "Blood Frenzy", tier = "When needed", dtype = "Enrage/Magic", npc = "Frenzied Berserker", npcId = 248684 },
                { id = 1270079, name = "Grim Ward", tier = "When needed", dtype = "Magic", npc = "Grim Skirmisher", npcId = 248690 },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 0.4,   -- floored: only 4% of dispels here are high/must (mostly gated buffs + medium debuffs)
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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (6) and dispels (4) observed in this dungeon.
            kicks = {
                { id = 1257601, name = "Divine Guile", tier = "Critical", npc = "Fractured Image", npcId = 251568 },
                { id = 1285445, name = "Arcane Explosion", tier = "Must kick", npc = "Corewright Arcanist", npcId = 241644 },
                { id = 1258681, name = "Nullify", tier = "Must kick", npc = "Grand Nullifier", npcId = 251853 },
                { id = 1282722, name = "Nullify", tier = "Must kick", npc = "Grand Nullifier", npcId = 251031 },
                { id = 1263892, name = "Holy Bolt", tier = "Should kick", npc = "Lightwrought", npcId = 254926 },
                { id = 1271094, name = "Umbra Bolt", tier = "Should kick", npc = "Nexus Adept", npcId = 248708 },
            },
            dispels = {
                { id = 1249815, name = "Transference", tier = "High", dtype = "Magic", npc = "Corewright Arcanist", npcId = 241644, counts = true },
                { id = 1269283, name = "Suppression Field", tier = "Medium", dtype = "Movement", npc = "Flux Engineer", npcId = 241647 },
                { id = 1277557, name = "Burning Radiance", tier = "Conditional", dtype = "Magic", npc = "Lightwrought", npcId = 254926 },
                { id = 1263783, name = "Holy Echo", tier = "When needed", dtype = "Magic", npc = "Flarebat", npcId = 254928 },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 0.44,   -- 44% high/must (Transference removed 100% of the time)
            trash = { interruptFrequency = 1.63,     -- per-min (v45: recalibrated to observed 1.63 kicks/min over 11 real runs)
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
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (8) and dispels (8) observed in this dungeon.
            kicks = {
                { id = 1216592, name = "Chain Lightning", tier = "Must kick", npc = "Phantasmal Mystic", npcId = 232146 },
                { id = 1251981, name = "Chain Lightning", tier = "Must kick", npc = "Phantasmal Mystic", npcId = 234061 },
                { id = 473794, name = "Poison Blades", tier = "Must kick", npc = "Ardent Cutthroat", npcId = 232171 },
                { id = 472724, name = "Shadow Bolt", tier = "Must kick", npc = "Kalis", npcId = 231626 },
                { id = 1216819, name = "Fungal Bolt", tier = "Should kick", npc = "Bloated Lasher", npcId = 236894 },
                { id = 1216135, name = "Spirit Bolt", tier = "Should kick", npc = "Restless Steward", npcId = 232070 },
                { id = 473657, name = "Shadow Bolt", tier = "Spare", npc = "Devoted Woebringer", npcId = 232175 },
                { id = 473663, name = "Pulsing Shriek", tier = "unset", npc = "Devoted Woebringer", npcId = 232175 },
            },
            dispels = {
                { id = 473795, name = "Poison Blades", tier = "Highest", dtype = "Poison", npc = "Ardent Cutthroat", npcId = 232171, counts = true },
                { id = 1216298, name = "Soul Torment", tier = "Highest", dtype = "Magic", npc = "Restless Steward", npcId = 232070, counts = true },
                { id = 1216860, name = "Bolstering Flames", tier = "High (remove)", dtype = "Magic", npc = "Territorial Dragonhawk", npcId = 232056, counts = true },
                { id = 1253834, name = "Curse of Darkness", tier = "High", dtype = "Curse", npc = "Kalis", npcId = 231626, counts = true },
                { id = 1215803, name = "Curse of Darkness", tier = "High", dtype = "Curse", npc = "Dark Entity", npcId = 236153, counts = true },
                { id = 1216825, name = "Poison Spray", tier = "High", dtype = "Poison", npc = "Creeping Spindleweb", npcId = 232067, counts = true },
                { id = 468659, name = "Throw Axe", tier = "Conditional", dtype = "Bleed/Curse/Disease/Poison", npc = "Spectral Axethrower", npcId = 232148 },
                { id = 1216459, name = "Ephemeral Bloodlust", tier = "When needed", dtype = "Enrage", npc = "Phantasmal Mystic", npcId = 232146 },
            },
            -- <<< CATALOG <<<
            dispelDemandScale = 0.83,   -- only high/must dispels expected
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
