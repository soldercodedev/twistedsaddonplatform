-- TAP: Mythic Ledger - Database.lua
-- Account-wide SavedVariables: the schema, recursive defaults, a versioned migration framework,
-- run storage with composite-key de-duplication, retention, and the ADDON_LOADED bootstrap.
-- Raw run records are kept separate from derived summaries (characters / playerIndex / caches),
-- which History.lua rebuilds. No raw combat events are ever stored here.

local ADDON, ML = ...
local DB = {}
ML.DB = DB

----------------------------------------------------------------------
-- Default shape. CopyDefaults() only fills MISSING keys, so user data always wins.
----------------------------------------------------------------------
local DEFAULTS = {
    schemaVersion = ML.SCHEMA_VERSION,
    settings = {
        trackAbandoned     = true,
        postRunSummary     = true,
        playerTooltip      = true,      -- master: add your shared run history to a player's Blizzard tooltip
        tooltipSurfaces = {             -- which tooltip surfaces get the ledger block (each defaults on)
            unit      = true,           -- unit frames / nameplates / world
            lfg       = true,           -- group-finder search entries
            friends   = true,           -- friends list
            who       = true,           -- /who results
            guild     = true,           -- guild roster
            community = true,           -- community member lists
        },
        postRunAfterLoot   = false,     -- true = wait to pop the summary until you loot the run-end chest
        postRunDelay       = 5,         -- seconds to wait after the trigger before the summary pops (0 = instant)
        confirmAbandonSave = true,
        -- RUN HISTORY: one policy, one ladder - full detail -> trimmed -> gone.
        --   retentionScope  = how long a run keeps FULL detail
        --   retentionAction = what happens to it after that (trim the detail, or delete the run)
        --   retentionRuns   = a hard ceiling on stored runs, independent of age (always deletes)
        -- The default (ALL + no cap) means nothing ever happens, exactly as before.
        retentionScope     = "ALL",    -- full detail for: ALL / SEASON (current) / EXPANSION (current) / DAYS
        retentionDays      = 90,       -- window length when retentionScope == "DAYS"
        retentionAction    = "TRIM",   -- beyond the window: TRIM (keep the run, drop review detail) / DELETE
        retentionRuns      = 0,        -- 0 = no numeric cap; otherwise keep only the newest N
        retentionKeepTop   = true,     -- never DELETE a top run (best-per-dungeon, top 10, crowns)
        retentionAuto      = false,    -- apply on login + season rollover; off = only when you press Apply
        cardStyle          = "COMPACT", -- Overview stat cards: CLEAN / PANEL / COMPACT
        dateFormat         = "NA",      -- timestamp date part: NA (mm/dd/yy) / ISO (yyyy-mm-dd) / EU (dd/mm/yy)
        clockFormat        = "24H",     -- timestamp time part (always local): 24H (hh:mm) / 12H (h:mm AM/PM)
        scoreboardScale    = 1.05,      -- end-of-run scoreboard size (capped to fit the screen)
        scoreboardFont     = "",        -- font key for the scoreboard ("" = use the UI font)
        scoreboardSound    = true,      -- play a sound when the scoreboard opens
        scoreboardSoundKey = "VictoryFanfare", -- which sound (see TAP.SOUNDS)
        scoreboardSoundChannel = "Master",     -- sound channel for the scoreboard sound
        scoreboardSoundWhen = "END",    -- END = end-of-run popup only; ALWAYS = every time it's viewed
        debug              = false,
        recap = {
            enabled           = true,
            display           = "CHAT",     -- CHAT / TOAST / BOTH / OFF
            trigger           = "JOIN",     -- JOIN (roster change) / READY (ready check) / BOTH
            minShared         = 1,
            history           = "SEASON",   -- SEASON / ALL
            includeAverages   = true,
            includeLastResult = false,
            includeNotes      = false,      -- notes are NEVER shown automatically unless opted in
            joinDelay         = 3,          -- seconds after joining before recaps may fire
            sound             = true,       -- play a sound (once) when returning players are found
            soundKey          = "Applause", -- which sound (see TAP.SOUNDS)
            soundChannel      = "Master",   -- sound channel for the recap sound
        },
        -- On-screen post-pull DEATH REPORT: after combat drops (or at run end), flash who died since the
        -- last report and why (time in the key, killing blow, cause - including a missed kick's spell).
        deathReport = {
            enabled    = false,             -- off until opted in
            trigger    = "COMBAT",          -- COMBAT (each time combat drops) / RUN_END (once, at the finish)
            dismiss    = "AUTO",            -- AUTO (fade after `duration`) / CLICK (stays until clicked)
            duration   = 6,                 -- seconds on screen before it fades (AUTO dismissal only)
            maxLines   = 8,                 -- most deaths to list at once
            onlyMe     = false,             -- true = only report YOUR deaths
            font       = "",                -- font key ("" = the UI font)
            fontSize   = 15,
            titleColor = { 1.00, 0.82, 0.20 },     -- the header line
            textColor  = { 0.94, 0.95, 0.98 },     -- the per-death lines
            background = true,              -- draw a backing panel behind the text
            bgColor    = { 0.03, 0.04, 0.06, 0.82 },
            posPoint   = "CENTER", posX = 0, posY = 220,   -- screen anchor (drag-to-move in Settings)
        },
        -- On-screen LIVE COACH: after a boss (or a big pull) settles, score the run SO FAR with the same
        -- engine the final grade uses and flash the highest-leverage reminder(s). Uses scoring READ-ONLY.
        liveCoach = {
            enabled    = false,             -- off until opted in
            popPolicy  = "SLIP",            -- SLIP (only when below par) / QUIET (every fight, brief "on pace") / ALWAYS (every fight, praise too)
            cadence    = "BOSS",            -- BOSS (boss kills only) / ALL (bosses + big trash pulls)
            minCombat  = 10,                -- ALL cadence: min seconds a pull must last to count as "big"
            depth      = "ONE",             -- ONE (one reminder) / TWO (top 2) / MINI (headline + a strength)
            dismiss    = "AUTO",            -- AUTO (fade after `duration`) / CLICK (stays until clicked) / BOTH
            duration   = 7,
            font       = "",
            fontSize   = 15,
            titleColor = { 0.36, 0.83, 0.92 },     -- grade/header line (teal - distinct from the death report)
            textColor  = { 0.94, 0.95, 0.98 },
            fixColor   = { 0.95, 0.62, 0.30 },     -- the "focus on" reminder lines
            goodColor  = { 0.42, 0.82, 0.45 },     -- praise / "on pace" lines
            background = true,
            bgColor    = { 0.03, 0.04, 0.06, 0.85 },
            posPoint   = "CENTER", posX = 0, posY = -160,   -- screen anchor (drag-to-move in Settings)
        },
    },
    runs          = {},   -- array of finalized run records (raw-ish, but no combat events)
    activeRun     = nil,  -- reload/disconnect recovery record for an in-progress run
    characters    = {},   -- derived: charKey -> character aggregate (rebuilt by History)
    playerIndex   = {},   -- derived: identityKey -> party-member summary (rebuilt by History)
    playerMeta    = {},   -- PERSISTENT user annotations: identityKey -> { notes, tags, favorite, protected }
    personalBests = {},   -- derived: keyed personal bests (rebuilt by History)
    summaryCache  = {},   -- derived: assorted page caches, invalidatable
    -- PERSISTENT, NOT derived: the frozen score of every compacted run (Scoring/Store.Freeze). Kept out
    -- of summaryCache on purpose - that one is thrown away on an engine-version bump, which is precisely
    -- the event these have to outlive. runId -> { v, at, by = { guid -> {overall,grade,role,specID} } }.
    frozenScores  = {},
    migrations    = {},   -- log of applied migrations { version, at }
    lastSeenSeason = nil, -- last M+ season observed, so Archive.AutoRun can detect a rollover ONCE
    _runSeq       = 0,    -- monotonic counter feeding unique run ids
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ML.CopyDefaults = CopyDefaults

----------------------------------------------------------------------
-- Migration framework. Register a function per target schema version; on load we run every
-- pending one in order. Migrations must be non-destructive: never delete an incompatible record,
-- preserve unknown fields, and tolerate partially written data.
----------------------------------------------------------------------
DB.MIGRATIONS = {
    -- v2: Feign Death correction on saved runs. C_DamageMeter logged a Hunter's Feign Death as a death;
    -- strip those from recorded runs (a captured death with no killing blow that never took the hunter
    -- near-lethal - the same test the live tracker now uses), fix the count, and re-derive death causes.
    -- The Config.version bump rescores the corrected runs on load.
    [2] = function(root)
        local Providers = ML.Providers
        if not (Providers and Providers.LooksFeignDeath) then return end
        local Cfg = ML.Scoring and ML.Scoring.Config
        local function kicksFor(dungeon, seasonId)
            local cat = Cfg and Cfg.SeasonDungeon and Cfg.SeasonDungeon(dungeon, seasonId)
            if not (cat and type(cat.kicks) == "table") then return nil end
            local ks = {}
            for _, e in ipairs(cat.kicks) do if e.id then ks[e.id] = true end end
            return ks
        end
        for _, run in ipairs(root.runs or {}) do
            for _, m in ipairs((type(run) == "table" and run.party) or {}) do
                if type(m) == "table" and m.classFile == "HUNTER" and type(m.deathRecaps) == "table" then
                    local kept, feign = {}, 0
                    for _, rc in ipairs(m.deathRecaps) do
                        if type(rc) == "table" and Providers.LooksFeignDeath(rc.events, rc.maxHP) then
                            feign = feign + 1
                        else
                            kept[#kept + 1] = rc
                        end
                    end
                    if feign > 0 then
                        m.deathRecaps = (#kept > 0) and kept or nil
                        local s = m.stats
                        if type(s) == "table" and type(s.deaths) == "number" then
                            s.deaths = math.max(0, s.deaths - feign)
                        end
                        local n = (type(s) == "table" and s.deaths) or 0
                        if n > 0 and Providers.ClassifyDeaths then
                            m.deathCauses = Providers.ClassifyDeaths(m.attribution, m.deathRecaps, m.role, n, kicksFor(run.dungeonName, run.seasonId))
                        else
                            m.deathCauses = nil
                        end
                    end
                end
            end
        end
    end,
    -- v3: slim the run log. We now read only Blizzard's C_DamageMeter, and several per-spell breakdowns
    -- were stored but never read. Drop the unused per-spell lists (attribution.damageDone / healingDone /
    -- damageTaken) and the dead Details!-only `overhealing` stat. KEEP everything scoring reads: the
    -- aggregate stats (incl. damageTaken / avoidableDamageTaken), attribution.avoidable (feeds death-cause
    -- classification + the Avoidable Damage card), interrupts/dispels, deathRecaps, and boss lowAvoid.
    -- Scoring is untouched by this (the dropped fields have no readers; overhealing was always nil), so
    -- there is no Config.version bump - this is a pure storage strip.
    [3] = function(root)
        for _, run in ipairs(root.runs or {}) do
            if type(run) == "table" then
                for _, m in ipairs(run.party or {}) do
                    if type(m) == "table" then
                        if type(m.stats) == "table" then m.stats.overhealing = nil end
                        local a = m.attribution
                        if type(a) == "table" then
                            a.damageDone, a.healingDone, a.damageTaken = nil, nil, nil
                            if next(a) == nil then m.attribution = nil end
                        end
                    end
                end
            end
        end
    end,
    -- v4: trim per-boss table bloat (memory, not scoring). topDps/topHps were just the max entry of
    -- perMember, duplicated - the review derives them from perMember at render now, so drop the stored
    -- copies wherever perMember is present. Also null out empty deathList tables (an allocated table
    -- holding nothing). Display-only; scores are unaffected.
    [4] = function(root)
        for _, run in ipairs(root.runs or {}) do
            if type(run) == "table" then
                for _, b in ipairs(run.bosses or {}) do
                    if type(b) == "table" then
                        if type(b.perMember) == "table" and #b.perMember > 0 then
                            b.topDps, b.topHps = nil, nil
                        end
                        if type(b.deathList) == "table" and #b.deathList == 0 then b.deathList = nil end
                    end
                end
            end
        end
    end,
    -- v5: drop the raw talent ID arrays. They were captured "for future modelling" and stored TWICE -
    -- once per party member and again inside run.dispelCapture - which measured 4.1 MB on a 11.6 MB
    -- database (35% of the whole file) while NOTHING ever read them: no code indexes or iterates a
    -- talents array anywhere in the addon. Scoring only ever uses the DERIVED values, and every one of
    -- them is already folded onto the member at save time by mergePartyStats (Tracker.lua:98-127):
    -- specId, itemLevel, dispelTalent (from hasTool), heroTree and talentCount. So dispelCapture as a
    -- whole is redundant once saved and goes too.
    -- The one thing to preserve first: Norm.Player (Scoring/Normalize.lua:26-29) falls back to
    -- dispelCapture[guid].specID when a member has no spec, so fold that in BEFORE dropping the table,
    -- or a spec-less pug would rescore as a class guess. Scoring reads nothing else here, so there is
    -- no Config.version bump - this is a pure storage strip, like v3.
    [5] = function(root)
        for _, run in ipairs(root.runs or {}) do
            if type(run) == "table" then
                local cap = (type(run.dispelCapture) == "table") and run.dispelCapture or nil
                for _, m in ipairs(run.party or {}) do
                    if type(m) == "table" then
                        -- Rescue the inspected spec before the capture table is discarded.
                        if not (m.specId or m.specID) and cap and m.guid then
                            local c = cap[m.guid]
                            if type(c) == "table" and type(c.specID) == "number" and c.specID > 0 then
                                m.specId = c.specID
                            end
                        end
                        m.talents = nil        -- the big array; talentCount + heroTree are kept (cheap, and heroTree IS displayed)
                    end
                end
                run.dispelCapture = nil
            end
        end
    end,
}

local function runMigrations(root)
    local from = tonumber(root.schemaVersion) or 0
    local to = ML.SCHEMA_VERSION
    if from >= to then return end
    for v = from + 1, to do
        local fn = DB.MIGRATIONS[v]
        if type(fn) == "function" then
            local ok, err = pcall(fn, root)
            if ok then
                root.migrations[#root.migrations + 1] = { version = v, at = time() }
                ML.Log("Migrated schema -> v%d", v)
            else
                -- Never wipe on a failed migration; record it and stop so nothing is lost.
                root.migrations[#root.migrations + 1] = { version = v, at = time(), error = tostring(err) }
                ML.Log("Migration to v%d FAILED: %s (halting; data preserved)", v, tostring(err))
                return
            end
        end
    end
    root.schemaVersion = to
end

----------------------------------------------------------------------
-- Init (from ADDON_LOADED). Safe to call more than once.
----------------------------------------------------------------------
function DB.Init()
    _G.TAP_MythicLedgerDB = _G.TAP_MythicLedgerDB or {}
    local root = _G.TAP_MythicLedgerDB
    DB.root = root
    -- Guard against a corrupt top level: only the fields we expect are re-seeded; unknowns kept.
    if type(root.runs) ~= "table" then root.runs = {} end
    -- Seeded and defaulted FIRST so MigrateProfiles below has a fully-populated table to
    -- adopt as the Default profile; it clears root.settings once it has taken it.
    if type(root.settings) ~= "table" then root.settings = {} end
    CopyDefaults(DEFAULTS, root)
    -- Settings move into named profiles that follow the platform's binding for this character.
    -- History (runs, characters, playerIndex, playerMeta, personalBests) deliberately does NOT:
    -- it is account-wide data, and letting a profile own it would mean deleting a profile could
    -- delete a season of runs.
    DB.MigrateProfiles(root)
    -- runMigrations stamps schemaVersion itself, and ONLY on success - a failed step halts with the
    -- version left behind so the next login retries it. Do not re-stamp here: doing so marked failed
    -- migrations as done and they were never retried, silently stranding whatever the step was meant
    -- to fix.
    runMigrations(root)
    ML._initialized = true
    -- Prime C_MythicPlus so GetCurrentSeason() returns a real id (it reports -1 until requested).
    if ML.API and ML.API.RequestSeasonInfo then pcall(ML.API.RequestSeasonInfo) end
    -- Rebuild derived caches from the raw runs (History fills characters/playerIndex/bests).
    if ML.History and ML.History.RebuildAll then
        local ok, err = pcall(ML.History.RebuildAll)
        if not ok then ML.Log("History.RebuildAll failed: %s", tostring(err)) end
    end
    -- Retroactively rescore all runs if the scoring engine version changed since we last stored
    -- (no-op when already current). Keeps persisted score summaries in step with scoring-logic bumps.
    if ML.Scoring and ML.Scoring.Store and ML.Scoring.Store.EnsureCurrent then
        pcall(ML.Scoring.Store.EnsureCurrent)
    end
    -- Automatic data policy (Archive.lua). Deferred, and retried, because GetCurrentSeason() reports -1
    -- until the request fired above resolves - and this must never act on an unknown season. It also has
    -- to come after EnsureCurrent: compaction freezes each run's score, so the score must be current
    -- first. Gives up quietly if the API never answers this session.
    if ML.Archive and ML.Archive.AutoRun and C_Timer and C_Timer.After then
        local tries = 0
        local function attempt()
            tries = tries + 1
            local cur = ML.API and ML.API.GetCurrentSeason and ML.API.GetCurrentSeason()
            if type(cur) == "number" and cur > 0 then
                pcall(ML.Archive.AutoRun)
            elseif tries < 10 then
                C_Timer.After(3, attempt)
            end
        end
        C_Timer.After(5, attempt)
    end
    ML._debugEcho = DB.Settings().debug and true or false
    ML.Log("DB ready: %d run(s), schema v%d", #root.runs, root.schemaVersion)
end

----------------------------------------------------------------------
-- Accessors.
----------------------------------------------------------------------
function DB.Ready() return ML._initialized and DB.root ~= nil end

----------------------------------------------------------------------
-- Settings profiles.
--
-- Keyed by the PLATFORM's profile name, so one switch in /tap moves every add-on at once rather
-- than leaving this module on a different setup from the rest. Unknown/missing profile falls
-- back to the one named Default, seeded from the pre-profile `root.settings`.
----------------------------------------------------------------------
local DEFAULT_PROFILE = "Default"

function DB.MigrateProfiles(root)
    root = root or DB.root
    if not root then return end
    if type(root.profiles) ~= "table" then
        root.profiles = {}
        -- The old single settings table becomes Default, contents intact.
        root.profiles[DEFAULT_PROFILE] = root.settings or {}
    end
    root.settings = nil
    if type(root.profiles[DEFAULT_PROFILE]) ~= "table" then
        root.profiles[DEFAULT_PROFILE] = {}
    end
    CopyDefaults(DEFAULTS.settings, root.profiles[DEFAULT_PROFILE])
end

function DB.ProfileName()
    local S = _G.TAP
    local name = S and S.ActiveProfileName and S:ActiveProfileName() or DEFAULT_PROFILE
    return name or DEFAULT_PROFILE
end

----------------------------------------------------------------------
-- Profile lifecycle. Settings live in THIS add-on's saved variables keyed by the platform's
-- profile name, so a copy/rename/delete on the platform has to be mirrored here. Run HISTORY is
-- at the root and is deliberately never touched by any of this.
----------------------------------------------------------------------
local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = deepcopy(val) end
    return t
end

function DB.ProfileCopied(fromName, toName)
    local root = DB.root
    if not (root and root.profiles) then return end
    local src = root.profiles[fromName]
    root.profiles[toName] = src and deepcopy(src) or nil
end

function DB.ProfileRenamed(oldName, newName)
    local root = DB.root
    if not (root and root.profiles) then return end
    root.profiles[newName], root.profiles[oldName] = root.profiles[oldName], nil
end

function DB.ProfileDeleted(name)
    local root = DB.root
    if not (root and root.profiles) then return end
    root.profiles[name] = nil
end

-- Reset drops the row; DB.Settings re-seeds it from DEFAULTS on the next read.
function DB.ProfileReset(name)
    local root = DB.root
    if not (root and root.profiles) then return end
    root.profiles[name] = nil
end

function DB.Settings()
    local root = DB.root
    if not root then return DEFAULTS.settings end
    if type(root.profiles) ~= "table" then DB.MigrateProfiles(root) end
    local name = DB.ProfileName()
    local p = root.profiles[name]
    if type(p) ~= "table" then
        -- A profile this module has not seen before starts from the defaults, not from whatever
        -- the last character happened to be using.
        p = {}
        CopyDefaults(DEFAULTS.settings, p)
        root.profiles[name] = p
    end
    return p
end
function DB.Recap() return DB.Settings().recap end
function DB.DeathReport() return DB.Settings().deathReport end
function DB.LiveCoach() return DB.Settings().liveCoach end
function DB.Runs() return DB.root and DB.root.runs or {} end
function DB.CountRuns() return DB.root and #DB.root.runs or 0 end
function DB.Characters() return DB.root and DB.root.characters or {} end
function DB.PlayerIndex() return DB.root and DB.root.playerIndex or {} end
function DB.PlayerMeta()  return DB.root and DB.root.playerMeta or {} end
function DB.PersonalBests() return DB.root and DB.root.personalBests or {} end
function DB.ActiveRun() return DB.root and DB.root.activeRun end
function DB.SetActiveRun(rec) if DB.root then DB.root.activeRun = rec end end
function DB.ClearActiveRun() if DB.root then DB.root.activeRun = nil end end

-- A unique run id: monotonic sequence + timestamp, so it stays unique across sessions/chars.
function DB.NewRunId()
    if not DB.root then return "run-" .. tostring(time()) end
    DB.root._runSeq = (DB.root._runSeq or 0) + 1
    return string.format("run-%d-%d", time(), DB.root._runSeq)
end

-- Composite identity for de-duplication (a single event firing twice must not double-save).
local function runFingerprint(run)
    return table.concat({
        tostring(run.character and run.character.guid or "?"),
        tostring(run.mapId or "?"),
        tostring(run.level or "?"),
        tostring(run.startedAt or "?"),
        tostring(run.completedAt or "?"),
    }, "|")
end

function DB.RunExists(run)
    local fp = runFingerprint(run)
    for _, r in ipairs(DB.Runs()) do
        if r._fp == fp then return true end
    end
    return false
end

-- Save a finalized run EXACTLY once. Returns true if inserted, false if it was a duplicate.
function DB.AddRun(run)
    if not DB.Ready() then return false end
    run._fp = runFingerprint(run)
    if DB.RunExists(run) then
        ML.Log("Duplicate run suppressed (%s +%s)", tostring(run.dungeonName), tostring(run.level))
        return false
    end
    if not run.id then run.id = DB.NewRunId() end
    table.insert(DB.root.runs, run)
    DB.ApplyRetention()
    -- Single aggregation hook: updates characters / playerIndex and stamps run._newBests.
    if ML.History and ML.History.OnRunSaved then pcall(ML.History.OnRunSaved, run) end
    ML.Log("Saved run: %s +%s (%s)", tostring(run.dungeonName), tostring(run.level), tostring(run.status))
    return true
end

function DB.DeleteRun(id)
    local runs = DB.Runs()
    for i = #runs, 1, -1 do
        if runs[i].id == id then table.remove(runs, i) end
    end
    if ML.Scoring and ML.Scoring.Store and ML.Scoring.Store.PruneOrphans then ML.Scoring.Store.PruneOrphans() end
    if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
end

----------------------------------------------------------------------
-- USER PROTECTION. Two explicit, user-set locks that no policy may override:
--   * run.protected            - this run keeps full detail forever.
--   * playerMeta[key].protected - this player's record is kept, AND every run they appear in is locked.
-- Both are deliberately SEPARATE from run.pinned / run.bestOfKind: those are auto-heuristics that
-- MarkKeepers/MarkBestRuns recompute from scratch on every call (clearing the field first), so a user
-- value stored there would be silently wiped on the next save.
----------------------------------------------------------------------
-- Resolve player-level protection down to the runs it covers. Writes run._protectedBy (the identity key
-- that locked it). It is DERIVED, not authoritative: recomputed here on every rebuild and before every
-- policy pass, so a stale value can never outlive one login. Cheap: one pass over runs x ~5 members, and
-- IdentityKey is a pure table read (no API call).
function DB.MarkProtected()
    if not DB.root then return end
    local meta = DB.root.playerMeta or {}
    local locked, any = {}, false
    for key, m in pairs(meta) do
        if type(m) == "table" and m.protected then locked[key] = true; any = true end
    end
    local idKey = ML.API and ML.API.IdentityKey
    for _, r in ipairs(DB.root.runs) do
        r._protectedBy = nil
        if any and idKey then
            for _, m in ipairs(r.party or {}) do
                local k = idKey(m)
                if k and locked[k] then r._protectedBy = k; break end
            end
        end
    end
end

-- Is this run locked by the USER? Their own lock on the run, or one inherited from a protected player.
-- Unconditional: no other setting can override it, for either trimming or deletion.
function DB.IsLocked(r)
    return (r and (r.protected or r._protectedBy)) and true or false
end

-- May a policy DELETE this run? User locks always win; keepTop additionally spares the automatic
-- keepers (best-per-dungeon, top 10, crowns). Deliberately not consulted for TRIMMING: a trimmed run
-- is still there, still crowned and still scored, so "never remove a top run" has nothing to defend.
function DB.IsProtected(r, keepTop)
    if not r then return false end
    if DB.IsLocked(r) then return true end
    return keepTop and (r.pinned or r.bestOfKind) and true or false
end

-- Is this run OUTSIDE the "keep full detail" window? One predicate, shared by both policy actions so
-- trimming and deleting can never disagree about which runs are old. A run we cannot classify (no
-- season / expansion / timestamp) is always treated as INSIDE - never acted on from a guess.
function DB.OutsideWindow(r, scope, days, cur, expac, now)
    if type(r) ~= "table" then return false end
    if scope == "SEASON" then
        return cur ~= nil and type(r.seasonId) == "number" and r.seasonId ~= cur
    elseif scope == "EXPANSION" then
        return expac ~= nil and type(r.expansionId) == "number" and r.expansionId ~= expac
    elseif scope == "DAYS" then
        local n = tonumber(days) or 0
        if n <= 0 then return false end
        local t = r.completedAt or r.startedAt
        return type(t) == "number" and (now - t) > n * 86400
    end
    return false   -- "ALL" keeps everything at full detail
end

-- The live window parameters, resolved once.
function DB.WindowParams()
    local st = DB.Settings()
    local cur = ML.API and ML.API.GetCurrentSeason and ML.API.GetCurrentSeason()
    if type(cur) ~= "number" or cur <= 0 then cur = nil end
    local expac = ML.API and ML.API.GetExpansionLevel and ML.API.GetExpansionLevel()
    return st.retentionScope or "ALL", tonumber(st.retentionDays) or 90, cur, expac, (time and time() or 0)
end

-- Flag the "keeper" runs so retention never destroys them:
--   1. the single best TIMED run per dungeon (highest key, tie-broken by fastest time), and
--   2. the overall TOP 10 TIMED runs (by key, then time).
-- Sets run.pinned on keepers, clears it on the rest. The UI shows a crown on pinned runs.
DB.TOP_KEEP = 10
function DB.MarkKeepers()
    if not DB.root then return end
    local best, timed = {}, {}
    for _, r in ipairs(DB.root.runs) do
        r.pinned = nil
        if r.status == ML.STATUS.TIMED and type(r.level) == "number" then
            timed[#timed + 1] = r
            if r.mapId then
                local cur = best[r.mapId]
                if not cur or r.level > cur.level
                    or (r.level == cur.level and (r.duration or math.huge) < (cur.duration or math.huge)) then
                    best[r.mapId] = r
                end
            end
        end
    end
    for _, r in pairs(best) do r.pinned = true end   -- best per dungeon
    -- Top N overall.
    table.sort(timed, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.duration or math.huge) < (b.duration or math.huge)
    end)
    for i = 1, math.min(DB.TOP_KEEP, #timed) do timed[i].pinned = true end
end

-- Flag the single BEST run per (dungeon + key level + player's class/spec) by the PLAYER's overall
-- performance SCORE, so exactly one crown shows for each such combo. Spec id already implies the class
-- (1:1), so grouping by spec covers "class + spec". Score comes from the Scoring Store's cached
-- summaries; ties break toward the faster run, then the more recent. TIMED runs only (a crown means a
-- clean best). Sets run.bestOfKind on each group's winner, clears it everywhere else. Recomputed on
-- every save, cache rebuild, and rescore, so a new higher-scoring run steals the crown from the old one.
function DB.MarkBestRuns()
    if not DB.root then return end
    local Store = ML.Scoring and ML.Scoring.Store
    local best = {}   -- "mapId|level|specID" -> { run, score, duration, at }
    for _, r in ipairs(DB.root.runs) do
        r.bestOfKind = nil
        local pg = r.character and r.character.guid
        if Store and pg and r.status == ML.STATUS.TIMED and type(r.level) == "number" and r.mapId then
            local ps = Store.Summary(r)[pg]        -- { overall, grade, role, specID } for the player
            local spec, score = ps and ps.specID, ps and ps.overall
            if spec and type(score) == "number" then
                local key = r.mapId .. "|" .. r.level .. "|" .. spec
                local cur = best[key]
                local dur, at = r.duration or math.huge, r.completedAt or r.startedAt or 0
                local wins = (not cur) or score > cur.score
                    or (score == cur.score and (dur < cur.duration or (dur == cur.duration and at > cur.at)))
                if wins then best[key] = { run = r, score = score, duration = dur, at = at } end
            end
        end
    end
    for _, v in pairs(best) do v.run.bestOfKind = true end
end

-- Enforce the ONE retention policy. Two phases, in order:
--   1. WINDOW - runs outside the "keep full detail" window (retentionScope: SEASON / EXPANSION / DAYS)
--      are either TRIMMED (detail stripped, run kept - Archive.lua) or DELETED, per retentionAction.
--   2. numeric CAP - if retentionRuns > 0, DELETE the oldest until at most that many remain. A cap is
--      a ceiling on how much you store, so it always deletes; trimming would not honour it.
-- User locks (run.protected / a protected player) are never touched by either phase. Keep-Top
-- additionally spares the automatic keepers from DELETION only - a trimmed top run is still there,
-- still crowned and still scored, so there is nothing for that toggle to defend against trimming.
-- Runs we cannot classify (no season / expansion / timestamp) are KEPT, never acted on from a guess.
-- Called on every save and from the Settings "Apply" button.
function DB.ApplyRetention()
    if not DB.root then return end
    local st = DB.Settings()
    local scope   = st.retentionScope or "ALL"
    local cap     = tonumber(st.retentionRuns) or 0
    local keepTop = st.retentionKeepTop ~= false   -- default true
    local action  = st.retentionAction or "TRIM"
    -- Policy off (ALL window + no cap, the default) keeps EVERYTHING at full detail - nothing to do.
    if scope == "ALL" and cap <= 0 then return end

    local runs = DB.root.runs
    -- Refresh keeper flags so the top-run guard is accurate before we touch anything.
    DB.MarkKeepers()
    DB.MarkBestRuns()   -- crowned best-per-(dungeon+key+spec) runs are keepers too
    DB.MarkProtected()  -- resolve player-level locks down to the runs they cover
    local function protected(r) return DB.IsProtected(r, keepTop) end
    local removed, trimmed, freed = 0, 0, 0

    -- Phase 1: the WINDOW. Reverse iteration so table.remove stays index-safe.
    if scope ~= "ALL" then
        local sc, days, cur, expac, now = DB.WindowParams()
        local Arch = ML.Archive
        for i = #runs, 1, -1 do
            local r = runs[i]
            if DB.OutsideWindow(r, sc, days, cur, expac, now) then
                if action == "DELETE" then
                    if not protected(r) then table.remove(runs, i); removed = removed + 1 end
                elseif Arch and Arch.CompactRun and not DB.IsLocked(r) then
                    local bytes = Arch.CompactRun(r)
                    if bytes then trimmed = trimmed + 1; freed = freed + bytes end
                end
            end
        end
    end

    -- Phase 2: numeric CAP - only when you've set retentionRuns > 0 (0 = unlimited). Oldest un-protected first.
    if cap > 0 and #runs > cap then
        table.sort(runs, function(a, b)
            return (a.completedAt or a.startedAt or 0) < (b.completedAt or b.startedAt or 0)
        end)
        local removeCount, i = #runs - cap, 1
        while removeCount > 0 and i <= #runs do
            if not protected(runs[i]) then table.remove(runs, i); removeCount = removeCount - 1; removed = removed + 1
            else i = i + 1 end   -- keepers survive; step over them
        end
    end

    if removed > 0 or trimmed > 0 then
        if ML.Scoring and ML.Scoring.Store and ML.Scoring.Store.PruneOrphans then ML.Scoring.Store.PruneOrphans() end
        if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    end
    ML.Log("Retention applied: window=%s action=%s cap=%d keepTop=%s -> %d kept, %d removed, %d trimmed (%.2f MB)",
        scope, action, cap, tostring(keepTop), #runs, removed, trimmed, freed / 1048576)
    return { removed = removed, trimmed = trimmed, bytes = freed, kept = #runs }
end

function DB.WipeHistory()
    if not DB.root then return end
    DB.root.runs = {}
    DB.root.characters = {}
    DB.root.playerIndex = {}
    DB.root.personalBests = {}
    DB.root.summaryCache = {}
    DB.root.playerMeta = {}   -- a full wipe clears annotations too (they only survive cache REBUILDS, not this)
    DB.root.activeRun = nil
    DB.root._runSeq = 0
    if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    ML.Log("History wiped")
end

-- Dev-support cleanup: remove ONLY generated mock runs (the dev mock-data tool stamps every fake run
-- with providerVersion == "mock"), leaving your real history intact. Rebuilds derived caches once and
-- returns how many runs were removed. Used by /mldev wipe dummy to undo a mock-generate on a live DB.
function DB.WipeMockRuns()
    if not DB.root then return 0 end
    local runs = DB.root.runs
    local removed = 0
    for i = #runs, 1, -1 do
        if runs[i].providerVersion == "mock" then table.remove(runs, i); removed = removed + 1 end
    end
    if removed > 0 and ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    ML.Log("Wiped %d mock run(s)", removed)
    return removed
end

----------------------------------------------------------------------
-- ADDON_LOADED bootstrap (file scope - runs regardless of module enable state, so the UI can
-- always read history; tracking itself is gated by the module's OnEnable).
----------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == ADDON then
        local ok, err = pcall(DB.Init)
        if not ok then ML.Log("DB.Init failed: %s", tostring(err)) end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
