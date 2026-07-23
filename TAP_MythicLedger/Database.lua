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
        retentionScope     = "ALL",    -- retention window: ALL / SEASON (current) / EXPANSION (current)
        retentionRuns      = 0,        -- 0 = no numeric cap; otherwise keep only the newest N
        retentionKeepTop   = true,     -- never prune a protected top run (best-per-dungeon, top 10, crowns)
        cardStyle          = "COMPACT", -- Overview stat cards: CLEAN / PANEL / COMPACT
        dateFormat         = "NA",      -- timestamp date part: NA (mm/dd/yy) / ISO (yyyy-mm-dd) / EU (dd/mm/yy)
        clockFormat        = "24H",     -- timestamp time part (always local): 24H (hh:mm) / 12H (h:mm AM/PM)
        scoreboardScale    = 1.05,      -- end-of-run scoreboard size (capped to fit the screen)
        scoreboardFont     = "",        -- font key for the scoreboard ("" = use the UI font)
        scoreboardSound    = true,      -- play a sound when the scoreboard opens
        scoreboardSoundKey = "VictoryFanfare", -- which sound (see UIF.SOUNDS)
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
            soundKey          = "Applause", -- which sound (see UIF.SOUNDS)
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
function DB.DeathReport() return DB.Settings().deathReport end
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

-- Enforce the retention policy. Two independent phases run in order:
--   1. SCOPE prune - drop runs that fall OUTSIDE the retained window (SEASON = current season only,
--      EXPANSION = current expansion only, ALL = keep every season/expansion).
--   2. numeric CAP - if retentionRuns > 0, trim oldest runs until at most that many remain.
-- While Keep-Top is on (the default) protected "top" runs (best key per dungeon, the top 10, and
-- crowned best-of-kind) are never dropped by either phase. Runs we can't classify (missing seasonId
-- or expansionId - e.g. history recorded before the tag existed) are KEPT, never pruned on a guess.
-- Called on every save and from the Settings "Apply" button. Destructive: only ever removes runs.
function DB.ApplyRetention()
    if not DB.root then return end
    local st = DB.Settings()
    local scope   = st.retentionScope or "ALL"
    local cap     = tonumber(st.retentionRuns) or 0
    local keepTop = st.retentionKeepTop ~= false   -- default true
    if scope == "ALL" and cap <= 0 then return end  -- nothing to enforce

    local runs = DB.root.runs
    -- Refresh keeper flags so the top-run guard is accurate before we prune anything.
    DB.MarkKeepers()
    DB.MarkBestRuns()   -- crowned best-per-(dungeon+key+spec) runs are keepers too
    local function protected(r) return keepTop and (r.pinned or r.bestOfKind) end
    local removed = 0

    -- Phase 1: SCOPE prune. Reverse iteration so table.remove is index-safe.
    if scope == "SEASON" then
        local cur = ML.API and ML.API.GetCurrentSeason and ML.API.GetCurrentSeason()
        if cur then
            for i = #runs, 1, -1 do
                local r = runs[i]
                if r.seasonId ~= nil and r.seasonId ~= cur and not protected(r) then
                    table.remove(runs, i); removed = removed + 1
                end
            end
        end
    elseif scope == "EXPANSION" then
        local cur = ML.API and ML.API.GetExpansionLevel and ML.API.GetExpansionLevel()
        if cur then
            for i = #runs, 1, -1 do
                local r = runs[i]
                if r.expansionId ~= nil and r.expansionId ~= cur and not protected(r) then
                    table.remove(runs, i); removed = removed + 1
                end
            end
        end
    end

    -- Phase 2: numeric CAP - oldest un-protected runs first.
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

    if removed > 0 and ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    ML.Log("Retention applied: scope=%s cap=%d keepTop=%s -> %d kept, %d removed",
        scope, cap, tostring(keepTop), #runs, removed)
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
