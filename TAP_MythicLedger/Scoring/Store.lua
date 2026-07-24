-- TAP: Mythic Ledger - Scoring/Store.lua
-- Score persistence + retroactive recalculation. Scores are DERIVED from the raw run stats (which we
-- never overwrite), so they can always be recomputed. This module:
--   * memoises the full, explainable score for a run this session (Store.Full),
--   * persists a COMPACT per-run summary { guid -> {overall, grade, role, specID} } in the derived
--     summaryCache (small; for fast list/grade display without recompute),
--   * exposes RescoreAll() - the migration path so a scoring-logic change (Config.version bump)
--     applies retroactively to every saved run,
--   * EnsureCurrent() - rescore only when the persisted version is stale (cheap no-op otherwise).

local ADDON, ML = ...
local Scoring = ML.Scoring
local DB   = ML.DB
local Cfg  = Scoring.Config
local Score = Scoring.Score
local Store = {}
Scoring.Store = Store

local wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local fullMemo = {}   -- runId -> { version, result }

-- The persisted score cache, reset whenever the stored version doesn't match the engine version.
local function scoreCache()
    if not DB.root then return nil end
    DB.root.summaryCache = DB.root.summaryCache or {}
    local sc = DB.root.summaryCache.scores
    if type(sc) ~= "table" or sc.version ~= Cfg.version then
        sc = { version = Cfg.version, runs = {} }
        DB.root.summaryCache.scores = sc
    end
    return sc
end

local function compact(result)
    local by = {}
    if result then
        for _, s in ipairs(result.list or {}) do
            if s.playerGUID then
                by[s.playerGUID] = { overall = s.overall, grade = s.grade, role = s.role, specID = s.specID }
            end
        end
    end
    return by
end

-- Full, explainable score set for a run (memoised this session; recomputed on version change).
function Store.Full(run)
    if not run then return nil end
    local id = run.id or tostring(run)
    local m = fullMemo[id]
    if m and m.version == Cfg.version then return m.result end
    local result = Score.ScoreRun(run)
    fullMemo[id] = { version = Cfg.version, result = result }
    local sc = scoreCache()
    if sc and run.id then sc.runs[run.id] = compact(result) end
    return result
end

-- Compact per-run summary { guid -> {overall,grade,role,specID} }; persisted, self-heals if stale.
function Store.Summary(run)
    if not run then return {} end
    if run.id then
        local sc = scoreCache()
        if sc and sc.runs[run.id] then return sc.runs[run.id] end
    end
    return compact(Store.Full(run))
end

-- Retroactively (re)score EVERY saved run - the migration path for scoring-logic / version changes.
-- Clears caches, recomputes, and rewrites the persisted summaries. Returns count, version.
function Store.RescoreAll()
    wipe(fullMemo)
    local sc = scoreCache()
    if sc then sc.runs = {} end
    local n = 0
    for _, run in ipairs(DB.Runs()) do
        local result = Score.ScoreRun(run)
        if result and run.id and sc then sc.runs[run.id] = compact(result); n = n + 1 end
    end
    -- Scores just changed, so the crown may move: re-flag the best-scoring run per dungeon+key+spec.
    if DB.MarkBestRuns then DB.MarkBestRuns() end
    if ML.Log then ML.Log("Scoring: rescored %d run(s) at v%d", n, Cfg.version) end
    return n, Cfg.version
end
Scoring.RescoreAll = Store.RescoreAll

-- Call on load: rescore ALL only if the persisted score version is stale/missing (else a no-op).
function Store.EnsureCurrent()
    if not DB.root then return end
    local sc = DB.root.summaryCache and DB.root.summaryCache.scores
    if type(sc) ~= "table" or sc.version ~= Cfg.version then Store.RescoreAll() end
end

-- Drop the in-memory memo for one run (e.g. after it's edited) so it recomputes on next access.
function Store.Invalidate(runId)
    if runId then fullMemo[runId] = nil else wipe(fullMemo) end
end

-- Drop ALL cached scores - the session memo AND the persisted per-run summaries - WITHOUT recomputing
-- here (recompute happens lazily on next render). Lets an in-memory tuning edit (which changes the season
-- data but NOT Config.version, so the caches would otherwise stay valid) flow straight through to the UI:
-- the next time a run is shown, its score is recomputed from the CURRENT config/season numbers. The dev
-- Season Tuner calls this after every edit; RescoreAll is the heavier, eager sibling that also repersists
-- and re-marks best runs.
function Store.InvalidateAll()
    wipe(fullMemo)
    local sc = scoreCache()
    if sc then sc.runs = {} end
end
Scoring.InvalidateScores = Store.InvalidateAll
