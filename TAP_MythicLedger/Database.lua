-- TAP: Mythic Ledger - Database.lua
-- Account-wide SavedVariables: the schema, recursive defaults, a versioned migration framework,
-- run storage with composite-key de-duplication, retention, and the ADDON_LOADED bootstrap.
-- Raw run records are kept separate from derived summaries (characters / playerIndex / caches),
-- which History.lua rebuilds. No raw combat events are ever stored here.

local ADDON, ML = ...
local Util = ML.Util
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
        confirmAbandonSave = true,
        retentionRuns      = 0,        -- 0 = keep everything; otherwise cap newest N
        cardStyle          = "COMPACT", -- Overview stat cards: CLEAN / PANEL / COMPACT
        scoreboardScale    = 1.05,      -- end-of-run scoreboard size (capped to fit the screen)
        scoreboardFont     = "",        -- font key for the scoreboard ("" = use the UI font)
        scoreboardSound    = true,      -- play a sound when the scoreboard opens
        scoreboardSoundKey = "VictoryFanfare", -- which sound (see UIF.SOUNDS)
        scoreboardSoundWhen = "END",    -- END = end-of-run popup only; ALWAYS = every time it's viewed
        debug              = false,
        recap = {
            enabled           = true,
            display           = "CHAT",     -- CHAT / TOAST / BOTH / OFF
            trigger           = "JOIN",     -- JOIN (roster change) / READY (ready check) / BOTH
            minShared         = 1,
            history           = "SEASON",   -- SEASON / ALL
            detail            = "COMPACT",  -- COMPACT / DETAILED / OFF
            includeAverages   = true,
            includeLastResult = false,
            includeNotes      = false,      -- notes are NEVER shown automatically unless opted in
            joinDelay         = 3,          -- seconds after joining before recaps may fire
            sound             = true,       -- play a sound (once) when returning players are found
            soundKey          = "Applause", -- which sound (see UIF.SOUNDS)
        },
    },
    runs          = {},   -- array of finalized run records (raw-ish, but no combat events)
    activeRun     = nil,  -- reload/disconnect recovery record for an in-progress run
    characters    = {},   -- derived: charKey -> character aggregate (rebuilt by History)
    playerIndex   = {},   -- derived: identityKey -> party-member summary (rebuilt by History)
    playerMeta    = {},   -- PERSISTENT user annotations: identityKey -> { notes, tags, favorite }
    personalBests = {},   -- derived: keyed personal bests (rebuilt by History)
    summaryCache  = {},   -- derived: assorted page caches, invalidatable
    migrations    = {},   -- log of applied migrations { version, at }
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
    -- [2] = function(root) ... end,   -- future schema bumps land here
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
    if type(root.settings) ~= "table" then root.settings = {} end
    CopyDefaults(DEFAULTS, root)
    runMigrations(root)
    root.schemaVersion = ML.SCHEMA_VERSION
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
    ML._debugEcho = root.settings.debug and true or false
    ML.Log("DB ready: %d run(s), schema v%d", #root.runs, root.schemaVersion)
end

----------------------------------------------------------------------
-- Accessors.
----------------------------------------------------------------------
function DB.Ready() return ML._initialized and DB.root ~= nil end
function DB.Settings() return DB.root and DB.root.settings or DEFAULTS.settings end
function DB.Recap() return DB.Settings().recap end
function DB.Runs() return DB.root and DB.root.runs or {} end
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
DB.RunFingerprint = runFingerprint

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
    if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
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

-- Trim to the newest `cap` runs - but NEVER drop a pinned keeper (best-per-dungeon). Only
-- un-pinned runs are destroyed, oldest first; if keepers alone exceed the cap, they all stay.
function DB.ApplyRetention()
    local cap = tonumber(DB.Settings().retentionRuns) or 0
    if cap <= 0 then return end
    local runs = DB.root.runs
    if #runs <= cap then return end
    DB.MarkKeepers()
    table.sort(runs, function(a, b)
        return (a.completedAt or a.startedAt or 0) < (b.completedAt or b.startedAt or 0)
    end)
    local removeCount, i = #runs - cap, 1
    while removeCount > 0 and i <= #runs do
        if not runs[i].pinned then table.remove(runs, i); removeCount = removeCount - 1
        else i = i + 1 end   -- keepers survive; step over them
    end
    if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    ML.Log("Retention applied: %d run(s) kept (cap %d, keepers protected)", #runs, cap)
end

function DB.WipeHistory()
    if not DB.root then return end
    DB.root.runs = {}
    DB.root.characters = {}
    DB.root.playerIndex = {}
    DB.root.personalBests = {}
    DB.root.summaryCache = {}
    DB.root.activeRun = nil
    DB.root._runSeq = 0
    if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    ML.Log("History wiped")
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
