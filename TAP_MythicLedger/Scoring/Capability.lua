-- TAP: Mythic Ledger - Scoring/Capability.lua
-- Per-SPECIALIZATION capability profiles: the conventional interrupt (spell/CD/range), extra
-- stops/silences, and dispel access. These drive fair, spec-aware expectations so a spec is never
-- punished for lacking a tool it doesn't have, and a teammate's big interrupt total can't inflate
-- anyone else's expectation.
--
-- Research: warcraft.wiki.gg/wiki/Interrupt and /wiki/Dispel (interrupt cooldowns/ranges, dispel
-- access), cross-checked against the official "Updates to Healer Specializations in Midnight" notes.
-- MIDNIGHT HEALER CHANGE (verified 2026): interrupts were REMOVED from every healer spec EXCEPT
-- Restoration Shaman, whose Wind Shear cooldown was increased 12s -> 30s. So Preservation Evoker
-- (Quell), Mistweaver Monk (Spear Hand Strike) and Holy Paladin (Rebuke) now have NO interrupt;
-- Disc/Holy Priest and Restoration Druid already had none. Non-healer interrupts are unchanged
-- (PvE lockouts were lengthened, e.g. Pummel to 5s, but cooldowns held). Interrupt/dispel KITS are
-- otherwise among the most stable parts of class design; spell IDs are the long-standing live IDs.
-- Each record carries `confidence` and `verify` so a spell-ID/CD audit is a data edit here, not a
-- code change. See CLASS_UTILITY_RESEARCH.md.

local ADDON, ML = ...
local Scoring = ML.Scoring
local Cap = {}
Scoring.Capability = Cap

-- Interrupt templates (spellID = long-standing live id; profile keys map to Config.interruptProfiles).
local function ir(spellID, spellName, cd, range, profile, extra)
    local t = { available = true, spellID = spellID, spellName = spellName, cooldownSeconds = cd,
                rangeType = range, profile = profile, talentDependent = false }
    if extra then for k, v in pairs(extra) do t[k] = v end end
    return t
end
local IR_NONE = { available = false, profile = "NONE" }

-- Dispel templates. `defensive`/`offensive` document types; `profile` maps to Config.dispelProfiles.
local function dp(profile, spellID, spellName, defensive, offensive, extra)
    local t = { profile = profile, spellID = spellID, spellName = spellName,
                defensive = defensive or {}, offensive = offensive or {}, talentDependent = false }
    if extra then for k, v in pairs(extra) do t[k] = v end end
    return t
end
local DP_NONE = { profile = "NONE" }

-- profiles[specID] = full record. role/classFile mirror the run data so scoring never needs a lookup.
local profiles = {}
Cap.profiles = profiles

local function spec(id, classFile, name, role, rec)
    rec.specID, rec.classFile, rec.class, rec.spec, rec.role = id, classFile, nil, name, role
    rec.confidence = rec.confidence or "high"
    rec.verify = rec.verify ~= false   -- default: flagged for a 12.x spell-id/CD re-verify
    profiles[id] = rec
    return rec
end

----------------------------------------------------------------------
-- Death Knight - Mind Freeze (all). No dispel.
----------------------------------------------------------------------
spec(250, "DEATHKNIGHT", "Blood",  "TANK",    { interrupt = ir(47528, "Mind Freeze", 15, "RANGED", "STANDARD"), dispel = DP_NONE, highControl = false })
spec(251, "DEATHKNIGHT", "Frost",  "DAMAGER", { interrupt = ir(47528, "Mind Freeze", 15, "RANGED", "STANDARD"), dispel = DP_NONE })
spec(252, "DEATHKNIGHT", "Unholy", "DAMAGER", { interrupt = ir(47528, "Mind Freeze", 15, "RANGED", "STANDARD"), dispel = DP_NONE })

----------------------------------------------------------------------
-- Demon Hunter - Disrupt (all) + Consume Magic (offensive purge). Vengeance = high control (Sigil of Silence).
----------------------------------------------------------------------
spec(577, "DEMONHUNTER", "Havoc",     "DAMAGER", { interrupt = ir(183752, "Disrupt", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 278326, "Consume Magic", nil, { magic = true }, { talentDependent = true }) })
spec(581, "DEMONHUNTER", "Vengeance", "TANK",    { interrupt = ir(183752, "Disrupt", 15, "MELEE", "HIGH_CONTROL",
    { additionalStops = { { spellID = 202137, spellName = "Sigil of Silence", stopType = "SILENCE", cooldownSeconds = 90, rotationalLikelihood = "MEDIUM" } } }),
    dispel = dp("LIMITED", 278326, "Consume Magic", nil, { magic = true }, { talentDependent = true }), highControl = true, incidentalControlRisk = 0.4 })

----------------------------------------------------------------------
-- Druid - Feral/Guardian: Skull Bash (15s, in-form). Balance: Solar Beam (60s, AoE silence). Resto: NONE.
----------------------------------------------------------------------
spec(102, "DRUID", "Balance",      "DAMAGER", { interrupt = ir(78675, "Solar Beam", 60, "RANGED", "LONG_CD", { silence = true }),
    dispel = dp("LIMITED", 2782, "Remove Corruption", { curse = true, poison = true }, { enrage = true }, { talentDependent = true }) })   -- + Soothe (2908) enrage
spec(103, "DRUID", "Feral",        "DAMAGER", { interrupt = ir(106839, "Skull Bash", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 2782, "Remove Corruption", { curse = true, poison = true }, { enrage = true }, { talentDependent = true }) })   -- + Soothe (2908) enrage
spec(104, "DRUID", "Guardian",     "TANK",    { interrupt = ir(106839, "Skull Bash", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 2782, "Remove Corruption", { curse = true, poison = true }, { enrage = true }, { talentDependent = true }) })   -- + Soothe (2908) enrage
spec(105, "DRUID", "Restoration",  "HEALER",  { interrupt = IR_NONE,
    dispel = dp("STANDARD", 88423, "Nature's Cure", { magic = true, curse = true, poison = true }, {}) })

----------------------------------------------------------------------
-- Evoker - Quell (40s) for Devastation/Augmentation. Preservation LOST Quell in Midnight (healer
-- interrupt removal) -> NONE. Preservation: full-ish dispel (Naturalize). DPS: Cauterizing Flame.
----------------------------------------------------------------------
spec(1467, "EVOKER", "Devastation",  "DAMAGER", { interrupt = ir(351338, "Quell", 40, "RANGED", "LONG_CD"),
    dispel = dp("LIMITED", 374251, "Cauterizing Flame", { curse = true, disease = true, poison = true }, {}, { talentDependent = true }) })
spec(1468, "EVOKER", "Preservation", "HEALER",  { interrupt = IR_NONE,
    dispel = dp("STANDARD", 360823, "Naturalize", { magic = true, poison = true }, {}) })
spec(1473, "EVOKER", "Augmentation", "DAMAGER", { interrupt = ir(351338, "Quell", 40, "RANGED", "LONG_CD"),
    dispel = dp("LIMITED", 374251, "Cauterizing Flame", { curse = true, disease = true, poison = true }, {}, { talentDependent = true }) })

----------------------------------------------------------------------
-- Hunter - BM/MM: Counter Shot (24s). Survival: Muzzle (15s). Tranq Shot (offensive) is TALENTED in
--   Midnight (not baseline) - so its dispel is talentDependent; a hunter without it is N/A, not docked.
----------------------------------------------------------------------
spec(253, "HUNTER", "BeastMastery", "DAMAGER", { interrupt = ir(147362, "Counter Shot", 24, "RANGED", "LONG_CD"),
    dispel = dp("LIMITED", 19801, "Tranquilizing Shot", nil, { magic = true, enrage = true }, { talentDependent = true }) })
spec(254, "HUNTER", "Marksmanship", "DAMAGER", { interrupt = ir(147362, "Counter Shot", 24, "RANGED", "LONG_CD"),
    dispel = dp("LIMITED", 19801, "Tranquilizing Shot", nil, { magic = true, enrage = true }, { talentDependent = true }) })
spec(255, "HUNTER", "Survival",     "DAMAGER", { interrupt = ir(187707, "Muzzle", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 19801, "Tranquilizing Shot", nil, { magic = true, enrage = true }, { talentDependent = true }) })

----------------------------------------------------------------------
-- Mage - Counterspell (all, 24s ranged, also silences). Remove Curse + Spellsteal.
----------------------------------------------------------------------
for _, s in ipairs({ { 62, "Arcane" }, { 63, "Fire" }, { 64, "Frost" } }) do
    spec(s[1], "MAGE", s[2], "DAMAGER", { interrupt = ir(2139, "Counterspell", 24, "RANGED", "LONG_CD", { silence = true }),
        dispel = dp("LIMITED", 475, "Remove Curse", { curse = true }, { magic = true }, { talentDependent = true }) })
end

----------------------------------------------------------------------
-- Monk - Spear Hand Strike (15s) for Brewmaster/Windwalker. Mistweaver LOST it in Midnight (healer
-- interrupt removal) -> NONE, but keeps full dispel (Detox + Magic).
----------------------------------------------------------------------
spec(268, "MONK", "Brewmaster", "TANK",    { interrupt = ir(116705, "Spear Hand Strike", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 218164, "Detox", { disease = true, poison = true }, {}, { talentDependent = true }), incidentalControlRisk = 0.25 })
spec(269, "MONK", "Windwalker", "DAMAGER", { interrupt = ir(116705, "Spear Hand Strike", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 218164, "Detox", { disease = true, poison = true }, {}, { talentDependent = true }) })
spec(270, "MONK", "Mistweaver", "HEALER",  { interrupt = IR_NONE,
    dispel = dp("STANDARD", 218164, "Detox", { disease = true, magic = true, poison = true }, {}) })

----------------------------------------------------------------------
-- Paladin - Rebuke (15s) for Protection/Retribution. Holy LOST Rebuke in Midnight (healer interrupt
--           removal) -> NONE. Protection also Avenger's Shield (ranged silence) = high control.
--           Holy: full Cleanse (baseline healer dispel). Prot/Ret: Cleanse Toxins (disease/poison) is
--           TALENTED in Midnight -> talentDependent; a prot/ret without it is N/A, not docked.
----------------------------------------------------------------------
spec(65, "PALADIN", "Holy",        "HEALER",  { interrupt = IR_NONE,
    dispel = dp("STANDARD", 4987, "Cleanse", { magic = true, disease = true, poison = true }, {}) })
spec(66, "PALADIN", "Protection",  "TANK",    { interrupt = ir(96231, "Rebuke", 15, "MELEE", "HIGH_CONTROL",
    { additionalStops = { { spellID = 31935, spellName = "Avenger's Shield", stopType = "SILENCE", cooldownSeconds = 15, rotationalLikelihood = "HIGH" } } }),
    dispel = dp("LIMITED", 213644, "Cleanse Toxins", { disease = true, poison = true }, {}, { talentDependent = true }), highControl = true, incidentalControlRisk = 0.5 })
spec(70, "PALADIN", "Retribution", "DAMAGER", { interrupt = ir(96231, "Rebuke", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 213644, "Cleanse Toxins", { disease = true, poison = true }, {}, { talentDependent = true }) })

----------------------------------------------------------------------
-- Priest - Discipline/Holy: NO conventional interrupt (Mass Dispel + Purify -> HIGH_UTILITY dispel).
--          Shadow: Silence (45s) + Purify Disease/Dispel Magic.
----------------------------------------------------------------------
spec(256, "PRIEST", "Discipline", "HEALER", { interrupt = IR_NONE,
    dispel = dp("HIGH_UTILITY", 527, "Purify", { magic = true, disease = true }, { magic = true },
        { additional = { { spellID = 32375, spellName = "Mass Dispel" } } }) })
spec(257, "PRIEST", "Holy",       "HEALER", { interrupt = IR_NONE,
    dispel = dp("HIGH_UTILITY", 527, "Purify", { magic = true, disease = true }, { magic = true },
        { additional = { { spellID = 32375, spellName = "Mass Dispel" } } }) })
spec(258, "PRIEST", "Shadow",     "DAMAGER", { interrupt = ir(15487, "Silence", 45, "RANGED", "LONG_CD", { silence = true }),
    dispel = dp("LIMITED", 213634, "Purify Disease", { disease = true }, { magic = true }, { talentDependent = true }) })

----------------------------------------------------------------------
-- Rogue - Kick (all, 15s). Shiv (5938) removes an Enrage from an enemy = a real (if situational)
--   offensive dispel, so LIMITED rather than NONE.
----------------------------------------------------------------------
spec(259, "ROGUE", "Assassination", "DAMAGER", { interrupt = ir(1766, "Kick", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 5938, "Shiv", nil, { enrage = true }) })
spec(260, "ROGUE", "Outlaw",        "DAMAGER", { interrupt = ir(1766, "Kick", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 5938, "Shiv", nil, { enrage = true }) })
spec(261, "ROGUE", "Subtlety",      "DAMAGER", { interrupt = ir(1766, "Kick", 15, "MELEE", "STANDARD"),
    dispel = dp("LIMITED", 5938, "Shiv", nil, { enrage = true }) })

----------------------------------------------------------------------
-- Shaman - Wind Shear. DPS (Elemental/Enhancement) keep the 12s SHORT_CD. Restoration is the ONE
--          healer that kept an interrupt in Midnight, but its Wind Shear was slowed 12s -> 30s, so
--          Resto is now LONG_CD, not SHORT_CD. Resto: full dispel (Purify Spirit); DPS: LIMITED.
----------------------------------------------------------------------
spec(262, "SHAMAN", "Elemental",   "DAMAGER", { interrupt = ir(57994, "Wind Shear", 12, "RANGED", "SHORT_CD"),
    dispel = dp("LIMITED", 51886, "Cleanse Spirit", { curse = true }, { magic = true }, { talentDependent = true }) })
spec(263, "SHAMAN", "Enhancement", "DAMAGER", { interrupt = ir(57994, "Wind Shear", 12, "RANGED", "SHORT_CD"),
    dispel = dp("LIMITED", 51886, "Cleanse Spirit", { curse = true }, { magic = true }, { talentDependent = true }) })
spec(264, "SHAMAN", "Restoration", "HEALER",  { interrupt = ir(57994, "Wind Shear", 30, "RANGED", "LONG_CD"),
    dispel = dp("STANDARD", 77130, "Purify Spirit", { magic = true, curse = true }, { magic = true }) })

----------------------------------------------------------------------
-- Warlock - Spell Lock via Felhunter (24s, pet/talent dependent). Singe/Devour Magic dispel.
----------------------------------------------------------------------
for _, s in ipairs({ { 265, "Affliction" }, { 266, "Demonology" }, { 267, "Destruction" } }) do
    spec(s[1], "WARLOCK", s[2], "DAMAGER", { interrupt = ir(19647, "Spell Lock", 24, "RANGED", "LONG_CD", { talentDependent = true }),
        dispel = dp("LIMITED", 89808, "Singe Magic", { magic = true }, { magic = true }, { talentDependent = true }) })
end

----------------------------------------------------------------------
-- Warrior - Pummel (14s as commonly played with the Honed Reflexes talent; 15s untalented base).
--   Warriors have NO dispel/purge/soothe of any kind (confirmed), so every spec is DP_NONE.
--   Protection also has Disrupting Shout (386071) = a real 90s AoE INTERRUPT, plus Shockwave (a
--   40s AoE STUN, NOT an interrupt).
----------------------------------------------------------------------
spec(71, "WARRIOR", "Arms",       "DAMAGER", { interrupt = ir(6552, "Pummel", 14, "MELEE", "STANDARD"), dispel = DP_NONE })
spec(72, "WARRIOR", "Fury",       "DAMAGER", { interrupt = ir(6552, "Pummel", 14, "MELEE", "STANDARD"), dispel = DP_NONE })
spec(73, "WARRIOR", "Protection", "TANK",    { interrupt = ir(6552, "Pummel", 14, "MELEE", "STANDARD",
    { additionalStops = {
        { spellID = 386071, spellName = "Disrupting Shout", stopType = "INTERRUPT", aoe = true, cooldownSeconds = 90, rotationalLikelihood = "LOW" },
        { spellID = 46968,  spellName = "Shockwave",        stopType = "STUN",      aoe = true, cooldownSeconds = 40, rotationalLikelihood = "MEDIUM" },
    } }),
    dispel = DP_NONE, incidentalControlRisk = 0.25 })

----------------------------------------------------------------------
-- Dispel policy (researched, Midnight): dispels / purges / soothes are scored as a CONTRIBUTION for
-- ANY spec that actually has a dispel tool - not healers only. DPS & tanks DO dispel in M+ (Hunter
-- Tranquilizing Shot, Druid/Rogue enrage soothes, Mage Spellsteal, Shaman Purge, DH Consume Magic,
-- narrow defensive cures, ...), so zeroing them out was wrong. The profile already encodes the
-- expectation gap: healers carry the full DEFENSIVE party dispel (STANDARD / HIGH_UTILITY, higher
-- rate); everyone else gets the low-expectation LIMITED. Only classes with NO dispel of any kind -
-- Warrior and Death Knight - stay NONE (weight redistributed).
--
-- Fairness comes from the confidence blend + composition modifier, NOT from denying credit: in a run
-- with little/no dispellable content the group's total is low, so a spec that dispelled nothing is
-- pulled toward the neutral score rather than punished; a healer or extra dispeller present lowers
-- everyone else's expected count. The addon only has aggregate C_DamageMeter dispel COUNTS (no combat
-- log in Midnight), so this is a VOLUME contribution, never a "you missed the priority dispel"
-- judgement. Sources: warcraft.wiki.gg/wiki/Dispel; Wowhead "Important Dispels in Midnight S1 M+".
-- (No profile rewriting here anymore - each spec is scored on the dispel profile set above.)
--
-- TALENT-GATED (researched vs the Midnight 12.0 talent trees, 2026): in 12.0 nearly every DPS/tank
-- DEFENSIVE cleanse is a class-tree TALENT a player can skip, so the record carries talentDependent =
-- true and the scorer only expects dispels from a member CONFIRMED to have it (live talent inspection,
-- or they actually dispelled) - never a dock for a tool they didn't spec. Flagged: DH Consume Magic,
-- Druid Remove Corruption, Evoker Cauterizing Flame, Hunter Tranquilizing Shot, Mage Remove Curse, Monk
-- Detox (BrM/WW), Paladin Cleanse Toxins (Prot/Ret), Shadow Priest Purify Disease, Shaman Cleanse
-- Spirit (Ele/Enh), Warlock Singe Magic (Imp/pet-conditional). NOT gated: Rogue Shiv (auto-granted to
-- Assassination, near-universal Row-1 pick) and every baseline HEALER cure. NOTE: some flagged records
-- also bundle a BASELINE offensive purge/soothe (Druid Soothe, Mage Spellsteal, Shaman Purge, Priest
-- Dispel Magic) that the player always has - we still gate on the talented DEFENSIVE cleanse, so a
-- purge/soothe they actually cast still credits via the "dispelled >= 1" clause; we just don't
-- proactively EXPECT it. That errs toward N/A (never a dock), which is the intended direction.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Class+role -> spec index, built from the declared profiles. Lets scoring recover a usable spec when
-- the exact id is missing (real captures where an inspect didn't land): for HEALER/TANK a class has one
-- spec (or specs with an identical interrupt kit), so "Shaman + Healer" resolves to Restoration - which
-- HAS Wind Shear - instead of the blanket "unknown healer can't kick" fallback.
----------------------------------------------------------------------
local specsByClassRole = {}
for id, rec in pairs(profiles) do
    if rec.classFile and rec.role then
        specsByClassRole[rec.classFile] = specsByClassRole[rec.classFile] or {}
        local byRole = specsByClassRole[rec.classFile]
        byRole[rec.role] = byRole[rec.role] or {}
        table.insert(byRole[rec.role], id)
    end
end

-- Resolve a (classFile, role) to a representative profile, but ONLY when it's unambiguous for interrupt
-- purposes (every matching spec shares the same interrupt profile) - so we never mis-guess a Hunter DPS
-- as Survival (15s Muzzle) vs Beast Mastery (24s Counter Shot). Returns the profile record, or nil.
local function resolveByClassRole(classFile, role)
    local list = classFile and role and specsByClassRole[classFile] and specsByClassRole[classFile][role]
    if not (list and list[1]) then return nil end
    local first = profiles[list[1]]
    local firstIP = (first.interrupt and first.interrupt.profile) or "NONE"
    for i = 2, #list do
        local ip = (profiles[list[i]].interrupt and profiles[list[i]].interrupt.profile) or "NONE"
        if ip ~= firstIP then return nil end   -- specs disagree on the kit -> don't guess, use fallback
    end
    return first
end

----------------------------------------------------------------------
-- Accessors.
----------------------------------------------------------------------
-- Fallback when a spec is unknown (old data, unfamiliar id): a neutral, LOW-confidence profile keyed
-- off role so scoring degrades gracefully instead of crashing. DPS/Tank get a STANDARD interrupt
-- assumption; healers get NONE (many can't kick) to avoid unfair expectation. Dispel LIMITED.
local function fallback(role)
    return {
        specID = 0, classFile = "UNKNOWN", spec = "Unknown", role = role or "DAMAGER",
        interrupt = (role == "HEALER") and IR_NONE or ir(0, "Interrupt", 15, "MELEE", "STANDARD"),
        -- Dispels are a healer responsibility; an unknown non-healer isn't expected to dispel.
        dispel = { profile = (role == "HEALER") and "STANDARD" or "NONE" },
        confidence = "low", verify = true, isFallback = true,
    }
end

-- REPRESENTATIVE spec for a (class, role) whose specs disagree on their interrupt kit (so
-- resolveByClassRole refuses to guess). Picks the build that dominates M+, so an un-inspected pug scores
-- closer to reality than the blanket STANDARD 15s fallback. Only ambiguous DPS classes need an entry:
--   * HUNTER DAMAGER -> Beast Mastery (253): BM + MM both use LONG_CD Counter Shot (24s); Survival's 15s
--     Muzzle is rare in M+, so LONG_CD is the safer default than crediting a 15s kick.
-- (Druid DAMAGER is genuinely split - Balance LONG_CD vs Feral STANDARD - so it's left to the generic
--  fallback rather than guessing one over the other.)
local classRoleDefault = {
    HUNTER = { DAMAGER = 253 },
}
local function representative(classFile, role)
    local sp = classFile and role and classRoleDefault[classFile] and classRoleDefault[classFile][role]
    return sp and profiles[sp] or nil
end

-- Get the capability profile for a spec id. When the id is unknown, recover from class+role: first the
-- unambiguous resolve (e.g. Shaman/Healer -> Restoration), then a per-class representative for ambiguous
-- DPS (Hunter DPS -> BM/LONG_CD), then the generic role-only fallback. `classFile` enables that recovery.
function Cap.Get(specID, role, classFile)
    if specID and profiles[specID] then return profiles[specID] end
    return resolveByClassRole(classFile, role) or representative(classFile, role) or fallback(role)
end

-- The canonical spec id for a class+role when the exact spec is unknown: the unambiguous resolve, else a
-- per-class representative for ambiguous DPS, else nil.
function Cap.ResolveSpec(classFile, role)
    local rec = resolveByClassRole(classFile, role) or representative(classFile, role)
    return rec and rec.specID or nil
end

function Cap.InterruptProfile(specID, role)
    local p = Cap.Get(specID, role)
    return (p.interrupt and p.interrupt.profile) or "NONE"
end
function Cap.DispelProfile(specID, role)
    local p = Cap.Get(specID, role)
    return (p.dispel and p.dispel.profile) or "NONE"
end
function Cap.IsHighControl(specID, role)
    local p = Cap.Get(specID, role)
    return p.highControl and true or false
end

-- The OFFENSIVE dispel ability (Purge / Soothe / Spellsteal / ...) per class - the spell used to strip a
-- BUFF off an enemy or Soothe an enrage, as opposed to the per-spec DEFENSIVE dispel in the record
-- (dispel.spellName). Class-level because a class's offensive tool is the same across its specs. Used by
-- the run-review coaching so a Purge/Soothe target names the right ability + Blizzard icon/tooltip.
Cap.OFFENSIVE_ABILITIES = {
    SHAMAN      = { spellID = 370,    spellName = "Purge" },
    PRIEST      = { spellID = 528,    spellName = "Dispel Magic" },
    MAGE        = { spellID = 30449,  spellName = "Spellsteal" },
    DRUID       = { spellID = 2908,   spellName = "Soothe" },
    HUNTER      = { spellID = 19801,  spellName = "Tranquilizing Shot" },
    ROGUE       = { spellID = 5938,   spellName = "Shiv" },
    DEMONHUNTER = { spellID = 278326, spellName = "Consume Magic" },
    WARLOCK     = { spellID = 19505,  spellName = "Devour Magic" },
}
function Cap.OffensiveAbility(classFile)
    return classFile and Cap.OFFENSIVE_ABILITIES[classFile] or nil
end
