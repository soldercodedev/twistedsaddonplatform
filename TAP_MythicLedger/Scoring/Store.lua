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

-- Session memo of the FULL, explainable score for a run - the heaviest per-run structure (every category
-- with its detail tables, the explanation strings, inputs, baseline...). Full scores are deterministic
-- and cheap to recompute, so we DON'T keep them all: the memo is bounded to the most-recently-viewed runs
-- (LRU). That stops memory from climbing as you browse the whole history; the tiny COMPACT summaries
-- (overall/grade) stay fully cached in summaryCache. Eviction only drops a memo entry, never real data.
local FULL_MEMO_CAP = 20          -- keep ~20 most-recently-viewed full scores; recompute beyond that
local fullMemo = {}               -- runId -> { version, result, seq }
local fullCount, fullSeq = 0, 0
local function memoWipe() wipe(fullMemo); fullCount, fullSeq = 0, 0 end
local function memoDel(id) if id and fullMemo[id] then fullMemo[id] = nil; fullCount = fullCount - 1 end end
local function memoGet(id)
    local m = fullMemo[id]
    if m and m.version == Cfg.version then fullSeq = fullSeq + 1; m.seq = fullSeq; return m.result end
    return nil
end
local function memoPut(id, result)
    fullSeq = fullSeq + 1
    if not fullMemo[id] then fullCount = fullCount + 1 end
    fullMemo[id] = { version = Cfg.version, result = result, seq = fullSeq }
    if fullCount > FULL_MEMO_CAP then         -- evict least-recently-used (n is tiny, a linear scan is fine)
        local oldId, oldSeq
        for k, v in pairs(fullMemo) do if not oldSeq or v.seq < oldSeq then oldSeq, oldId = v.seq, k end end
        memoDel(oldId)
    end
end

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

----------------------------------------------------------------------
-- FROZEN scores. A COMPACTED run (Archive.lua) has had its review-only detail stripped, so it can no
-- longer be rescored honestly - Score.ScoreRun would still return a structurally valid result, just
-- computed from missing inputs, which is the worst kind of wrong. Before stripping, the run's score is
-- frozen here and that becomes its permanent answer.
--
-- This deliberately lives in its OWN root table, NOT in summaryCache: scoreCache() throws the whole
-- cache away whenever the engine version changes (see below), which is exactly the event a frozen score
-- has to survive.
----------------------------------------------------------------------
local function frozenStore(create)
    if not DB.root then return nil end
    if not DB.root.frozenScores and create then DB.root.frozenScores = {} end
    return DB.root.frozenScores
end
local function frozenFor(runId)
    local fz = runId and frozenStore(false)
    local e = fz and fz[runId]
    return (type(e) == "table" and type(e.by) == "table") and e.by or nil
end

-- Freeze a run's CURRENT score as its permanent one. Call BEFORE stripping the run. Returns the frozen
-- summary, or nil if the run could not be scored (in which case the caller must not strip it).
function Store.Freeze(run)
    if not (run and run.id and DB.root) then return nil end
    local by = Store.Summary(run)
    if not (by and next(by)) then return nil end
    local fz = frozenStore(true)
    fz[run.id] = { v = Cfg.version, at = time and time() or 0, by = by }
    return by
end
function Store.IsFrozen(runId) return frozenFor(runId) ~= nil end
function Store.Unfreeze(runId)
    local fz = frozenStore(false)
    if fz and runId then fz[runId] = nil end
end

-- Full, explainable score set for a run (memoised this session; recomputed on version change).
-- A compacted run returns nil: its inputs are gone, so there is no honest per-category explanation to
-- give. Callers render the frozen overall/grade and say the detail was not retained.
function Store.Full(run)
    if not run then return nil end
    if run._c and frozenFor(run.id) then return nil end
    local id = run.id or tostring(run)
    local cached = memoGet(id)
    if cached then return cached end
    local result = Score.ScoreRun(run)
    memoPut(id, result)
    local sc = scoreCache()
    if sc and run.id then sc.runs[run.id] = compact(result) end
    return result
end

-- Compact per-run summary { guid -> {overall,grade,role,specID} }; persisted, self-heals if stale.
-- A frozen score wins over everything: it is the answer that was true when the detail still existed.
function Store.Summary(run)
    if not run then return {} end
    local frz = frozenFor(run.id)
    if frz then return frz end
    if run.id then
        local sc = scoreCache()
        if sc and sc.runs[run.id] then return sc.runs[run.id] end
    end
    return compact(Store.Full(run))
end

-- Retroactively (re)score EVERY saved run - the migration path for scoring-logic / version changes.
-- Clears caches, recomputes, and rewrites the persisted summaries. Returns count, version.
function Store.RescoreAll()
    memoWipe()
    local sc = scoreCache()
    if sc then sc.runs = {} end
    local n, frozen = 0, 0
    for _, run in ipairs(DB.Runs()) do
        local frz = frozenFor(run.id)
        if frz then
            -- Compacted run: its scoring inputs were stripped, so rescoring it would quietly invent a
            -- different number. Carry the frozen answer into the rebuilt cache instead.
            if sc and run.id then sc.runs[run.id] = frz end
            frozen = frozen + 1
        else
            local result = Score.ScoreRun(run)
            if result and run.id and sc then sc.runs[run.id] = compact(result); n = n + 1 end
        end
    end
    if frozen > 0 and ML.Log then ML.Log("Scoring: kept %d frozen score(s) (compacted runs)", frozen) end
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
    if runId then memoDel(runId) else memoWipe() end
end

-- Drop ALL cached scores - the session memo AND the persisted per-run summaries - WITHOUT recomputing
-- here (recompute happens lazily on next render). Lets an in-memory tuning edit (which changes the season
-- data but NOT Config.version, so the caches would otherwise stay valid) flow straight through to the UI:
-- the next time a run is shown, its score is recomputed from the CURRENT config/season numbers. The dev
-- Season Tuner calls this after every edit; RescoreAll is the heavier, eager sibling that also repersists
-- and re-marks best runs.
function Store.InvalidateAll()
    memoWipe()
    local sc = scoreCache()
    if sc then sc.runs = {} end
end
Scoring.InvalidateScores = Store.InvalidateAll

-- Drop persisted per-run summaries for runs that no longer exist. `summaryCache.scores.runs` is keyed by
-- run id and only ever grows on the write path (Store.Full), so deleting or retention-pruning a run would
-- otherwise leave its summary orphaned until the next Config.version bump. Call after any run removal;
-- one cheap pass, no recompute.
function Store.PruneOrphans()
    if not DB.root then return end
    local live = {}
    for _, run in ipairs(DB.Runs()) do if run.id then live[run.id] = true end end
    local sc = DB.root.summaryCache and DB.root.summaryCache.scores
    if type(sc) == "table" and type(sc.runs) == "table" then
        for id in pairs(sc.runs) do if not live[id] then sc.runs[id] = nil end end
    end
    -- Frozen scores follow the same rule. A COMPACTED run is still in DB.Runs(), so its freeze is kept;
    -- only a genuinely deleted (or archived-away) run drops its frozen entry, which is correct - there is
    -- nothing left for it to describe.
    local fz = DB.root.frozenScores
    if type(fz) == "table" then
        for id in pairs(fz) do if not live[id] then fz[id] = nil end end
    end
end
