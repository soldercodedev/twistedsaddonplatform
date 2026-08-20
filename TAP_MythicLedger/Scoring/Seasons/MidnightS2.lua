-- TAP: Mythic Ledger - Scoring/Seasons/MidnightS2.lua
-- SEASON DATA (not engine) for Midnight Season 2. Same shape as MidnightS1.lua:
--   * trash            = per-MINUTE frequencies for the whole dungeon's non-boss packs.
--   * bosses[encID]    = per-KILL frequencies (dungeonEncounterID == our run boss.id).
-- interruptFrequency / partyDebuffFrequencies (defensive, per school) / targetBuffFrequencies
-- (offensive purge + enrage) feed the utility supply pools; dispelDemandScale is the observed
-- High/Must share of actioned dispels (Distribute.lua). Values are ACTIONED rates (kicks/dispels
-- the group actually lands), consistent with the S1 file and Config.supplyScale.
--
-- CALIBRATION (2026-08-20): 18 observed S2 runs (+2 to +10), 15 of them with combat logs. Trash kick
-- weights = observed boss-subtracted trash kicks/MINUTE, held slightly under on small samples; boss
-- weights = observed landed kicks/dispels per kill normalized to the 90s reference fight (x1.5
-- bossKick scale backed out). Voidscar Arena is the one dungeon still with NO logged run (meter
-- attribution only, n=1 at +2) - its numbers stay PROVISIONAL until a logged run lands.
-- All are TUNABLE knobs (/mldev tune) - refine as more runs accumulate.

local ADDON, ML = ...
ML.Scoring = ML.Scoring or {}
local S = ML.Scoring
S.SeasonData = S.SeasonData or {}

-- Empty-block helpers keep the boss lists terse (missing tables read as "nothing").
local function K(f) return { interruptFrequency = f or 0 } end                       -- kick-only boss
local function KD(f, debuffs) return { interruptFrequency = f or 0, partyDebuffFrequencies = debuffs } end

S.SeasonData["MidnightS2"] = {
    label = "Midnight - Season 2",
    -- C_MythicPlus season id(s) this profile covers (18 = Midnight Season 2 live id).
    seasons = { [18] = true },
    dungeons = {
        ----------------------------------------------------------------
        ["templeofsethraliss"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (7) and dispels (6) observed in this dungeon.
            kicks = {
                { id = 1293307, name = "Addle Mind", tier = "Must kick", npc = "Faithless Subjugator", npcId = 134364,
                  note = "5s channel that disorients its target - also cast by the add waves during Avatar of Sethraliss" },
                { id = 1291262, name = "Lightning Bolt", tier = "Must kick", npc = "Storm Adept", npcId = 134990,
                  note = "2.5s cast, ~116k nuke - the dungeon's core kick (27 landed in one +5 run)" },
                { id = 268013, name = "Flame Shock", tier = "Should kick", npc = "Twisted Hexxer", npcId = 136250,
                  note = "4s cast: 242k hit + 77k/sec Fire DoT for 8s - heavy healer strain if it lands" },
                { id = 1302158, name = "Flame Shock", tier = "Should kick", npc = "Twisted Hexxer", npcId = 268491,
                  note = "4s cast: 242k hit + 77k/sec Fire DoT for 8s - heavy healer strain if it lands" },
                { id = 267027, name = "Poison Spit", tier = "Should kick", npc = "Toxic Viper", npcId = 134389,
                  note = "4s cast: 116k + a poison DoT - kicking it preempts the cleanse" },
                { id = 1308100, name = "Poisoned Cheap Shot", tier = "Should kick", npc = "Shrouded Fang", npcId = 134602,
                  note = "stealth opener: 5s stun + 97k/sec poison on the victim" },
                { id = 1310683, name = "Venom Bolt", tier = "Should kick", npc = "Brood Tender", npcId = 139425,
                  note = "2.5s ~116k Nature bolt from Merektha's brood adds" },
            },
            dispels = {
                { id = 1310739, name = "Accumulate Charge", tier = "High (remove)", dtype = "Magic", npc = "Agitated Nimbus", npcId = 136076, counts = true,
                  note = "stacking +8% damage buff (max 3) on the Nimbus - purge it (removed 67%)" },
                { id = 1308148, name = "Cytotoxin", tier = "High", dtype = "Poison", npc = "Poisonous Viper", npcId = 135562, counts = true,
                  note = "39k/sec Poison for 10s - removed 55% of applications; the healer's main cleanse here" },
                { id = 1296052, name = "Imbued Conduction", tier = "High", dtype = "Magic", npc = "Imbued Stormcaller", npcId = 134599, counts = true,
                  note = "43k/sec Magic for 20s that STUNS the victim if it expires - dispel early, never let it run out" },
                { id = 1308100, name = "Poisoned Cheap Shot", tier = "High", dtype = "Poison", npc = "Shrouded Fang", npcId = 134602, counts = true,
                  note = "the landed opener: dispel frees the 5s stun AND stops the 97k/sec poison" },
                { id = 267027, name = "Poison Spit", tier = "Medium", dtype = "Poison", npc = "Toxic Viper", npcId = 134389,
                  note = "the landed DoT of the kickable cast - cleanse when a kick was missed" },
                { id = 1291399, name = "Serrated Charge", tier = "Medium", dtype = "Bleed", npc = "Swarming Krolusk", npcId = 264785,
                  note = "krolusk charge Bleed - only bleed-capable tools clear it (removed 19%)" },
            },
            -- <<< CATALOG <<<
            name = "Temple of Sethraliss",
            dispelDemandScale = 0.85,  -- 28 of 34 actioned dispels were High/Must
            trash = { interruptFrequency = 2.8,      -- per-min (obs 2.71 trash kicks/min, n=2 at +5)
                partyDebuffFrequencies = { poison = 0.50, magic = 0.24 },   -- Cytotoxin, Imbued Conduction
                targetBuffFrequencies  = { purge = 0.35 } },                -- Accumulate Charge (Agitated Nimbus)
            bosses = {
                [2124] = K(0),                       -- Adderis and Aspix
                [2125] = KD(1.0, { poison = 1.0 }),  -- Merektha (snake adds + Cytotoxin; obs 1 cleanse/kill)
                [2126] = K(0),                       -- Galvazzt
                [2127] = K(1.0),                     -- Avatar of Sethraliss (Faithless Subjugator adds' Addle Mind)
            },
        },
        ----------------------------------------------------------------
        ["denofnalorakk"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (8) and dispels (6) observed in this dungeon.
            kicks = {
                { id = 1297696, name = "Healing Breeze", tier = "Critical", npc = "Earthwhisper Tender", npcId = 241814,
                  note = "3.5s cast: heals the whole pack 5% max HP every 2s - the one kick that must always land (also purgeable)" },
                { id = 1297778, name = "Arc Lightning", tier = "Must kick", npc = "Stormbound Mystic", npcId = 245139,
                  note = "4s cast: 194k chain to 3 targets - contributed to two deaths in the observed +8" },
                { id = 1309919, name = "Frigid Roar", tier = "Must kick", npc = "Frigid Mauler", npcId = 241872,
                  note = "3.5s cast: party-wide -50% Haste and -50% movement for 15s" },
                { id = 1246687, name = "Lightning Bolt", tier = "Must kick", npc = "Stormbound Mystic", npcId = 245139,
                  note = "2.5s ~116k bolt - killing blow on the healer in the observed +8" },
                { id = 1241214, name = "Earth Bolt", tier = "Should kick", npc = "Earthwhisper Tender", npcId = 241814,
                  note = "2.5s ~116k bolt - the filler kick (28 landed in one run)" },
                { id = 1290205, name = "Lightning Bolt", tier = "Should kick", npc = "Loa Speaker Nanea", npcId = 244889,
                  note = "2.5s bolt during the Loa Speaker packs - kick between the Mystics' casts" },
                { id = 1239394, name = "Scavenge", tier = "Should kick", npc = "Keen-Eyed Striker", npcId = 245752,
                  note = "3s cast - the eagle dives to steal the berry bush" },
                { id = 1235829, name = "Winter's Shroud", tier = "Should kick", npc = "Fractured Shivercore", npcId = 244759,
                  note = "4s cast: 97k party Frost hit + 10% Frost vulnerability for 20s" },
            },
            dispels = {
                { id = 1239860, name = "Cryo Surge", tier = "High", dtype = "Magic", npc = "Glacial Revenant", npcId = 241876, counts = true,
                  note = "Magic: 48k splash to everyone within 4yd of the victim - removed 50%; dispel before the pack clumps" },
                { id = 1235549, name = "Glacial Torment", tier = "High", dtype = "Magic", npc = "Sentinel of Winter", npcId = 244100, counts = true,
                  note = "boss Magic DoT 68k/2s for 16s - removed 67% on the observed Sentinel kill" },
                { id = 1234846, name = "Toxic Spores", tier = "High", dtype = "Poison", npc = "The Hoardmonger", npcId = 241812, counts = true,
                  note = "stacking Poison 19k/2s from the rotten mushrooms - cleanse at stacks during Hoardmonger" },
                { id = 1238801, name = "Insatiable Hunger", tier = "Medium", dtype = "Curse", npc = "Starvation Effigy", npcId = 245567,
                  note = "stacking Curse: -15% max HP per stack for 25s - decurse when it stacks (removed 20%)" },
                { id = 1241464, name = "Glacial Tomb", tier = "Conditional", dtype = "Movement", npc = "Avatar of Determination", npcId = 241869,
                  note = "encases the player until destroyed - a freedom/root-break helps, damage breaks it too" },
                { id = 1297696, name = "Healing Breeze", tier = "When needed", dtype = "Magic", npc = "Earthwhisper Tender", npcId = 241814,
                  note = "enemy buff: no shield/enrage/haste/damage effect" },
            },
            -- <<< CATALOG <<<
            name = "Den of Nalorakk",
            dispelDemandScale = 0.6,   -- 11 of 19 actioned dispels were High/Must
            trash = { interruptFrequency = 3.0,      -- per-min (obs 3.00 trash kicks/min, n=2 at +2/+8)
                partyDebuffFrequencies = { magic = 0.30, curse = 0.09 },    -- Cryo Surge, Insatiable Hunger
                targetBuffFrequencies  = { purge = 0.05 } },                -- Healing Breeze (kick preempts)
            bosses = {
                [3207] = KD(0, { poison = 1.0 }),    -- The Hoardmonger (Toxic Spores)
                [3208] = KD(2.0, { magic = 2.5 }),   -- Sentinel of Winter (adds + Glacial Torment; obs 3 kicks + 3 cleanses/kill)
                [3209] = K(0),                       -- Nalorakk
            },
        },
        ----------------------------------------------------------------
        ["kingsrest"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (10) and dispels (8) observed in this dungeon.
            kicks = {
                { id = 270901, name = "Unholy Mending", tier = "Critical", npc = "Seneschal M'bara", npcId = 134251,
                  note = "2.5s cast: the mob heals 7% HP every 2s for 10s" },
                { id = 270920, name = "Bind Soul", tier = "Must kick", npc = "Queen Wasi", npcId = 137478,
                  note = "2.5s cast - CHARMS a player for 10s" },
                { id = 269369, name = "Deathly Roar", tier = "Must kick", npc = "Reban", npcId = 136984,
                  note = "4s cast: 118k party hit + 4s fear" },
                { id = 270492, name = "Hex", tier = "Must kick", npc = "Phantom Hex Priest", npcId = 135204,
                  note = "3.5s cast - turns a player into a dino for 5s" },
                { id = 269972, name = "Hex Volley", tier = "Must kick", npc = "Risen Hexer", npcId = 134174,
                  note = "3.5s cast: 116k + a 12s Curse DoT on the party - kick first, decurse what lands" },
                { id = 267273, name = "Poison Nova", tier = "Must kick", npc = "Zanazal the Wise", npcId = 269810,
                  note = "4s cast: party-wide Poison burst 116k/2s for 12s" },
                { id = 267763, name = "Wretched Discharge", tier = "Must kick", npc = "Half-Finished Mummy", npcId = 270502,
                  note = "4s cast: party-wide Disease DoT 116k/2s for 12s - the mummies during Mchimba cast it too" },
                { id = 1294815, name = "Shadowfrost Bolt", tier = "Should kick", npc = "Risen Hexer", npcId = 134174,
                  note = "2.5s ~116k bolt that leaves a light Magic residue" },
                { id = 1294972, name = "Soul Bolt", tier = "Should kick", npc = "Queen Wasi", npcId = 137478,
                  note = "2.5s ~116k Shadow bolt - filler kick" },
                { id = 1295125, name = "Spectral Bolt", tier = "Should kick", npc = "Phantom Hex Priest", npcId = 135204,
                  note = "2.5s ~116k Shadow bolt - the volume kick here (13 landed across 2 runs)" },
            },
            dispels = {
                { id = 269935, name = "Bound by Shadow", tier = "High (remove)", dtype = "Magic", npc = "Minion of Zul", npcId = 133943, counts = true,
                  note = "purging it KILLS the Minion outright (shield + 20% damage buff) - removed 20x across 2 runs" },
                { id = 270499, name = "Frost Shock", tier = "High", dtype = "Magic", npc = "Spectral Shaman", npcId = 135239, counts = true,
                  note = "Magic 25% slow, high volume - removed 48% (14 in the observed +10)" },
                { id = 269972, name = "Hex Volley", tier = "High", dtype = "Curse", npc = "Risen Hexer", npcId = 134174, counts = true,
                  note = "the landed 12s Curse DoT of the kickable volley - decurse what slips through" },
                { id = 276031, name = "Pit of Despair", tier = "High", dtype = "Magic", npc = "", counts = true,
                  note = "Magic fear: 6s running in fear - dispel to break it" },
                { id = 1298104, name = "Putrid Seekers", tier = "High", dtype = "Poison", npc = "Embalming Fluid", npcId = 137989, counts = true,
                  note = "Poison 39k/sec + slow - the single biggest avoidable-damage source in the dungeon (5.7M over 2 runs)" },
                { id = 267763, name = "Wretched Discharge", tier = "High", dtype = "Disease", npc = "Half-Finished Mummy", npcId = 270502, counts = true,
                  note = "the landed party Disease of the kickable cast - cleanse what slips through" },
                { id = 1306763, name = "Serpent Strike", tier = "Medium", dtype = "Poison", npc = "Queen Patlaa", npcId = 137486,
                  note = "Poison 53k/sec + 50% slow for 8s" },
                { id = 1294815, name = "Shadowfrost Bolt", tier = "Medium", dtype = "Magic", npc = "Risen Hexer", npcId = 134174,
                  note = "light Magic residue from the bolt - cleanse when free" },
            },
            -- <<< CATALOG <<<
            name = "Kings' Rest",
            dispelDemandScale = 0.9,   -- 43 of 47 actioned dispels were High/Must
            trash = { interruptFrequency = 1.55,     -- per-min (obs 1.57 trash kicks/min, n=2: +2/+10 - calmest kick dungeon)
                partyDebuffFrequencies = { magic = 0.70, poison = 0.10, curse = 0.03, disease = 0.03 },   -- Frost Shock/Pit of Despair; Putrid Seekers; Hex Volley; Wretched Discharge
                targetBuffFrequencies  = { purge = 0.70 } },   -- Bound by Shadow (Minion of Zul) - removed 20x/2 runs
            bosses = {
                [2139] = K(0),                       -- The Golden Serpent
                [2142] = KD(1.5, { poison = 0.5 }),  -- Mchimba the Embalmer (mummy adds: Wretched Discharge kick + Putrid Seekers)
                [2140] = K(1.0),                     -- The Council of Tribes
                [2143] = K(0.5),                     -- King Dazar
            },
        },
        ----------------------------------------------------------------
        ["murderrow"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (8) and dispels (8) observed in this dungeon.
            kicks = {
                { id = 1214980, name = "Health Funnel", tier = "Critical", npc = "Fel Invoker", npcId = 235268,
                  note = "30s channel: heals its target 10% max HP every 2s - kick on sight" },
                { id = 474375, name = "Chaos Bolt", tier = "Must kick", npc = "Lithiel Cinderfury", npcId = 234763,
                  note = "3s cast, 155k Chaos nuke - she spams it; kick on cooldown (5 landed on the observed kill)" },
                { id = 1214922, name = "Fel Rage", tier = "Must kick", npc = "Wrathguard Flayer", npcId = 235267,
                  note = "3.5s cast: the Flayer takes -60% damage + CC immunity for 1 MIN if it finishes" },
                { id = 1264106, name = "Felstorm", tier = "Must kick", npc = "Kystia Manaheart", npcId = 255050,
                  note = "mirror-image channel raining arena-wide fel fire ~10k/sec - kick to end it" },
                { id = 1257877, name = "Scathing Review", tier = "Must kick", npc = "Influentual Reviewer", npcId = 253081,
                  note = "interrupting it backfires the review and the Reviewer LEAVES the fight" },
                { id = 1201554, name = "Seduction", tier = "Must kick", npc = "Seductive Sayaad", npcId = 255604,
                  note = "3s cast - disorients a player for 6s" },
                { id = 1216571, name = "Fel Missiles", tier = "Should kick", npc = "Felonious Mage", npcId = 236084,
                  note = "5s missile channel - the filler kick (19 landed in one +4)" },
                { id = 1223204, name = "Felfire Burst", tier = "Should kick", npc = "Unleashed Imp", npcId = 234849,
                  note = "1.5s imp bolt - cheap filler kick" },
            },
            dispels = {
                { id = 1217633, name = "Corroding Spittle", tier = "High", dtype = "Magic", npc = "Massive Felwyrm", npcId = 236902, counts = true,
                  note = "stacking Magic Fire DoT 87k/3s (wyrms; Nibbles reapplies it all Kystia fight) - removed 75-100%" },
                { id = 1228198, name = "Corroding Spittle", tier = "High", dtype = "Magic", npc = "Nibbles", npcId = 234660, counts = true,
                  note = "stacking Magic Fire DoT 87k/3s (wyrms; Nibbles reapplies it all Kystia fight) - removed 75-100%" },
                { id = 1217973, name = "Curse of Doom", tier = "High", dtype = "Curse", npc = "Corrupted Warlock", npcId = 235265, counts = true,
                  note = "581k Shadow detonation after 10s - decurse before it pops" },
                { id = 1216590, name = "Heartstop Poison", tier = "High", dtype = "Poison", npc = "Street Sneak", npcId = 236091, counts = true,
                  note = "Poison: 24k/sec + max HP cut per stack - Zaen and the Street Sneaks keep it rolling" },
                { id = 474515, name = "Heartstop Poison", tier = "High", dtype = "Poison", npc = "Zaen Bladesorrow", npcId = 234649, counts = true,
                  note = "Poison: 24k/sec + max HP cut per stack - Zaen and the Street Sneaks keep it rolling" },
                { id = 1201554, name = "Seduction", tier = "High", dtype = "Magic", npc = "Seductive Sayaad", npcId = 255604, counts = true,
                  note = "the landed disorient - a Magic dispel frees the seduced player; kick first" },
                { id = 1216300, name = "Cutpurse", tier = "Conditional", dtype = "Bleed", npc = "Row Hooligan", npcId = 236073,
                  note = "incidental pickpocket Bleed - removed 1 of 22 applications: don't chase it" },
                { id = 474740, name = "Murder in a Row", tier = "Conditional", dtype = "Bleed", npc = "Zaen Bladesorrow", npcId = 234649,
                  note = "Zaen's hunt mark - fight mechanic, removed once across the observed kills" },
            },
            -- <<< CATALOG <<<
            name = "Murder Row",
            dispelDemandScale = 0.85,  -- 11 of 13 actioned dispels were High/Must
            trash = { interruptFrequency = 2.5,      -- per-min (obs 2.61 trash kicks/min, n=2 at +2/+4)
                partyDebuffFrequencies = { magic = 0.23, curse = 0.08, poison = 0.11 } },   -- Corroding Spittle, Curse of Doom, Heartstop Poison
            bosses = {
                [3101] = { interruptFrequency = 1.0, partyDebuffFrequencies = { magic = 2.5 } },   -- Kystia Manaheart (Felstorm kick; Nibbles' Corroding Spittle - obs 3 cleanses/kill)
                [3102] = KD(0, { poison = 1.0 }),    -- Zaen Bladesorrow (Heartstop Poison)
                [3103] = K(0),                       -- Xathuux the Annihilator
                [3105] = K(3.0),                     -- Lithiel Cinderfury (Chaos Bolt; obs 6.5 kicks/kill)
            },
        },
        ----------------------------------------------------------------
        ["altaroffangs"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (4) and dispels (3) observed in this dungeon.
            kicks = {
                { id = 1289416, name = "Envenom", tier = "Must kick", npc = "High Evolutionist", npcId = 261557,
                  note = "2.5s cast: 58k + poison DoT - the main kick (19 landed); every miss becomes a cleanse" },
                { id = 1307567, name = "Mass Envenom", tier = "Must kick", npc = "Ula'tek's Chosen", npcId = 263109,
                  note = "2.5s cast - the same poison on the WHOLE party" },
                { id = 1294557, name = "Piercing Hiss", tier = "Must kick", npc = "Primal Serpent", npcId = 261560,
                  note = "4s cast: 136k armor-ignoring hit + party -30% Haste for 6s" },
                { id = 1310358, name = "Toxic Atrophy", tier = "Must kick", npc = "The Writhing Coil", npcId = 259446,
                  note = "boss cast: stacking -20% damage done and -20% movement on the group - kick every one" },
            },
            dispels = {
                { id = 1307571, name = "Envenom", tier = "High", dtype = "Poison", npc = "High Evolutionist", npcId = 261557, counts = true,
                  note = "24k/sec Poison for 8s, huge volume (38 applications in 2 runs, removed 39%) - every missed kick lands one" },
                { id = 1294569, name = "Paralyzing Shots", tier = "High", dtype = "Magic", npc = "Twinfang Harrower", npcId = 261554, counts = true,
                  note = "Magic: 48k/sec for 20s with a stacking slow each tick - removed 67%" },
                { id = 1296069, name = "Regurgitate", tier = "High", dtype = "Disease", npc = "Rav'i", npcId = 259445, counts = true,
                  note = "Rav'i Disease: -50% movement AND -50% damage done for 25s - dispel on cooldown" },
            },
            -- <<< CATALOG <<<
            name = "Altar of Fangs",
            dispelDemandScale = 1.0,   -- every actioned dispel was High/Must
            trash = { interruptFrequency = 3.0,      -- per-min (obs +5: 3.08 trash kicks/min, n=2)
                partyDebuffFrequencies = { poison = 0.60, magic = 0.40 } },   -- Envenom, Paralyzing Shots
            bosses = {
                [3456] = KD(0, { disease = 1.0 }),   -- Rav'i (Regurgitate)
                [3457] = K(2.0),                     -- The Writhing Coil (Toxic Atrophy; obs 4 kicks/kill)
                [3458] = K(0),                       -- Zul'jan
            },
        },
        ----------------------------------------------------------------
        ["rubylifepools"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (8) and dispels (5) observed in this dungeon.
            kicks = {
                { id = 373017, name = "Blaze Volley", tier = "Must kick", npc = "Blazebound Firestorm", npcId = 189886,
                  note = "3.5s cast: 116k Fire to EVERY player" },
                { id = 384194, name = "Cinderbolt", tier = "Must kick", npc = "Primalist Cinderweaver", npcId = 190207,
                  note = "2.5s ~116k Fire bolt - killing-blow evidence in the observed +9; the signature RLP kick" },
                { id = 384197, name = "Cinderbolt", tier = "Must kick", npc = "Primalist Cinderweaver", npcId = 190207,
                  note = "2.5s ~116k Fire bolt - killing-blow evidence in the observed +9; the signature RLP kick" },
                { id = 1305955, name = "Fiery Blast", tier = "Must kick", npc = "Blazebound Destroyer", npcId = 190034,
                  note = "4s cast, 359k Fire nuke - the Destroyer's big hit (21 landed in one run)" },
                { id = 372808, name = "Frigid Shard", tier = "Must kick", npc = "Melidrussa Chillworn", npcId = 188252,
                  note = "Melidrussa's 776k tank buster, 2.5s cast - kick on cooldown (11 landed on the kill)" },
                { id = 372743, name = "Ice Shield", tier = "Must kick", npc = "Flashfrost Chillweaver", npcId = 188067,
                  note = "15s channel stacking an absorb + CC immunity onto an ally - kick or purge it" },
                { id = 371984, name = "Frostbolt", tier = "Should kick", npc = "Flashfrost Chillweaver", npcId = 188067,
                  note = "2.5s ~116k Frost bolt - filler kick" },
                { id = 392576, name = "Thunder Blast", tier = "Should kick", npc = "Tempest Channeler", npcId = 198047,
                  note = "4s cast: 388k Nature on its target - kick when nothing hotter is up" },
            },
            dispels = {
                { id = 381515, name = "Stormslam", tier = "Highest", dtype = "Magic", npc = "Erkhart Stormvein", npcId = 190485, counts = true,
                  note = "Erkhart's Magic +100% Nature taken, STACKING - removed 100%; the healer's top job on the last boss" },
                { id = 373972, name = "Blaze of Glory", tier = "High (remove)", dtype = "Magic", npc = "Ashseer Flamelasher", npcId = 190206, counts = true,
                  note = "dying whirlwind shield - purge to cut the 15s ember volley short (removed 56%)" },
                { id = 391031, name = "Stormcloud Barrier", tier = "High (remove)", dtype = "Magic", npc = "Primal Thundercloud", npcId = 197509, counts = true,
                  note = "85% max-HP absorb - purge it (removed 74%), but removal triggers a Stormcloud Detonation" },
                { id = 1305234, name = "Cold Claws", tier = "Medium", dtype = "Magic", npc = "Infused Whelp", npcId = 187894,
                  note = "stacking Magic from whelp melee - Frozen Solid at 20 stacks, cleanse at high stacks" },
                { id = 392641, name = "Rolling Thunder", tier = "Conditional", dtype = "Magic", npc = "Thunderhead", npcId = 197698,
                  note = "45s Magic DoT whose REMOVAL triggers Electrical Discharge - time the dispel, don't reflex it" },
            },
            -- <<< CATALOG <<<
            name = "Ruby Life Pools",
            dispelDemandScale = 0.8,   -- 71 of 92 actioned dispels were High/Must (mostly purges)
            trash = { interruptFrequency = 4.0,      -- per-min (obs 4.18 trash kicks/min, n=3 at +2/+8/+9 - hottest kick dungeon)
                partyDebuffFrequencies = { magic = 0.25 },     -- Cold Claws, Rolling Thunder (both timed/at-stack)
                targetBuffFrequencies  = { purge = 1.5 } },    -- Stormcloud Barrier + Blaze of Glory (obs 1.63 counted purges/min)
            bosses = {
                [2609] = K(5.0),                     -- Melidrussa Chillworn (Frigid Shard + whelp adds; obs 10 kicks/kill over 3 kills)
                [2606] = K(2.5),                     -- Kokia Blazehoof (Blazebound adds; obs 5.3 kicks/kill)
                [2623] = { interruptFrequency = 0,   -- Kyrakka and Erkhart Stormvein
                    partyDebuffFrequencies = { magic = 2.5 },     -- Stormslam (+100% Nature taken; obs 3.3 cleanses/kill)
                    targetBuffFrequencies  = { purge = 2.0 } },   -- Stormcloud Barrier during the fight
            },
        },
        ----------------------------------------------------------------
        ["theblindingvale"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- Kicks (7) and dispels (4) observed in this dungeon.
            kicks = {
                { id = 1238294, name = "Disorienting Screech", tier = "Must kick", npc = "Lightfeather Petalwing", npcId = 245484,
                  note = "4s cast - disorients the whole party for 3s" },
                { id = 1235616, name = "Light Bolt", tier = "Must kick", npc = "Kezkitt", npcId = 243029,
                  note = "the Lightblossom Trinity fight's one interrupt - groups land ~10 kicks per kill on Kezkitt's bolt" },
                { id = 1301834, name = "Light Bolt Volley", tier = "Must kick", npc = "Radiant Spellsower", npcId = 245336,
                  note = "4s cast: 175k Holy to everyone within 100yd" },
                { id = 1238063, name = "Light Bolt", tier = "Should kick", npc = "Radiant Spellsower", npcId = 245336,
                  note = "2.5s ~116k Holy bolt - filler kick" },
                { id = 1247669, name = "Lightspore Shot", tier = "Should kick", npc = "Lightspawn Lasher", npcId = 247755,
                  note = "2.5s 58k spit - cheap filler kick" },
                { id = 1238232, name = "Seed Shot", tier = "Should kick", npc = "Leafy Grovecrawler", npcId = 245460,
                  note = "2.5s ~116k Nature bolt" },
                { id = 1239821, name = "Warden's Wrath", tier = "Should kick", npc = "Lightwarden Ruia", npcId = 245912,
                  note = "Ruia's 2s filler bolt on the current target (3 kicked on the observed kill)" },
            },
            dispels = {
                { id = 1259365, name = "Bloodthorn Roots", tier = "Highest", dtype = "Magic", npc = "Bloodthorn Roots", npcId = 253571, counts = true,
                  note = "roots a player + 48k/sec until destroyed (Ikuzz mechanic) - a Magic dispel frees them instantly" },
                { id = 1238581, name = "Spiny Shield", tier = "High (remove)", dtype = "Magic", npc = "Spineshield Beetle", npcId = 245527, counts = true,
                  note = "500k absorb + thorns damage on the beetle - purge it (removed 6x at +2)" },
                { id = 1238084, name = "Spore Spines", tier = "High", dtype = "Magic", npc = "Lasher", npcId = 245410, counts = true,
                  note = "stacking Magic slow from lasher melee - the dungeon's volume cleanse (removed 75% of applications at +7/+8)" },
                { id = 1250937, name = "Toxic Spew", tier = "Medium", dtype = "Poison", npc = "Potatoad Matriarch", npcId = 249756,
                  note = "58k/1.5s Poison for 9s after the belch" },
            },
            -- <<< CATALOG <<<
            name = "The Blinding Vale",
            dispelDemandScale = 0.9,   -- 41 of 46 actioned dispels were High/Must
            trash = { interruptFrequency = 2.5,      -- per-min (obs 2.56 trash kicks/min, n=2 logged at +7/+8; the first +2 meter-only read of 1.6 was low)
                partyDebuffFrequencies = { magic = 1.1, poison = 0.15 },   -- Spore Spines (the volume cleanse - obs 1.1/min), Toxic Spew
                targetBuffFrequencies  = { purge = 0.1 } },                -- Spiny Shield (rarely up)
            bosses = {
                [3199] = K(5.0),                     -- Lightblossom Trinity (Kezkitt's Light Bolt; obs 9.5 kicks/kill)
                [3200] = KD(0, { magic = 3.0 }),     -- Ikuzz the Light Hunter (Bloodthorn Roots frees; obs 4.5/kill)
                [3201] = K(1.5),                     -- Lightwarden Ruia (Warden's Wrath; obs 3 kicks/kill)
                [3202] = K(0.5),                     -- Ziekett (obs 1 kick/kill)
            },
        },
        ----------------------------------------------------------------
        ["voidscararena"] = {
            -- >>> CATALOG (auto: tools/logparse/season_catalog.py) - reference only, not read by scoring >>>
            -- HAND-BUILT from meter attribution + per-id spell lookups (no combat log for this dungeon
            -- yet - a future season_catalog.py run with logged VA runs will replace this block).
            -- Kicks (5) and dispels (2) observed in this dungeon.
            kicks = {
                { id = 1310324, name = "Mending Void", tier = "Critical", npc = "Voidminder", npcId = 244708,
                  note = "20s channel healing its target 3% max HP every 2s - kick immediately, every miss is a healed pack" },
                { id = 1233398, name = "Mad Shriek", tier = "Must kick", npc = "Kilivore Screamer", npcId = 243766,
                  note = "3.5s cast: FEARS everyone within 60yd for 6s" },
                { id = 1298899, name = "Demoralizing Shout", tier = "Should kick", npc = "Dominated Brawler", npcId = 238883,
                  note = "4s shout - kickable filler cast" },
                { id = 1228176, name = "Lava Bolt", tier = "Should kick", npc = "Enthralled Shaman", npcId = 241496,
                  note = "2.5s ~116k Fire bolt - the volume kick here (13 landed at +2)" },
                { id = 1249621, name = "Violent Sand", tier = "Should kick", npc = "Angry Krolusk", npcId = 249590,
                  note = "3s cast: 155k to everything nearby + 40% slow for 12s" },
            },
            dispels = {
                { id = 1250043, name = "Melt Armor", tier = "High", dtype = "Magic", npc = "Sycophantic Tarasek", npcId = 243983, counts = true,
                  note = "Magic +10% Fire taken - removed every application in the observed run" },
                { id = 1310319, name = "Bolster", tier = "High (remove)", dtype = "Enrage", npc = "Longtooth Tuskarr", npcId = 243985, counts = true,
                  note = "Enrage: +50% damage done and +20% Physical taken - soothe it" },
            },
            -- <<< CATALOG <<<
            name = "Voidscar Arena",
            -- PROVISIONAL: no combat log for this dungeon yet - meter attribution only (n=1 usable,
            -- +2; a later +5 run recorded no attribution at all, so it adds nothing).
            dispelDemandScale = 1.0,   -- every actioned dispel was High/Must
            trash = { interruptFrequency = 2.6,      -- per-min (obs +2: ~2.9 trash kicks/min, meter-only n=1; held under) PROVISIONAL
                partyDebuffFrequencies = { magic = 0.7 },      -- Melt Armor (Sycophantic Tarasek)
                targetBuffFrequencies  = { enrage = 0.2 } },   -- Bolster (Longtooth Tuskarr) soothe
            bosses = {
                [3285] = K(0),                       -- Taz'Rah
                [3286] = K(0),                       -- Atroxus
                [3287] = K(0),                       -- Charonus (Unstable Singularity/Void Cascade are avoidance, not utility)
            },
        },
    },
}
