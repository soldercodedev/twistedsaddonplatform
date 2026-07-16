-- TAP: Mythic Ledger - Scoring/Learned.lua
-- Learned throughput baselines: same-spec historical MEDIANS built from the saved runs, so the
-- rough static reference in Config gets replaced by "what this spec actually does" as data grows.
-- This implements the Scoring.GetLearnedMedian hook that Baselines.lua blends in (static -> learned,
-- weighted by sample count). It reads DB.Runs directly (it lives in the ML module, so DB access is
-- fine) and caches the medians until the run set changes.
--
-- Bucketing (most specific first): spec + metric + season + key-bracket  ->  spec + metric + season
-- -> spec + metric (all seasons). We use the most specific bucket that has >= minBucketSamples; the
-- blend in Baselines then scales trust by that bucket's sample count. Median (not mean) resists
-- outliers; p25/p75 are kept for future UI/percentile bands.

local ADDON, ML = ...
local Scoring = ML.Scoring
local DB   = ML.DB
local Cfg  = Scoring.Config
local Base = Scoring.Baselines
local Cap  = Scoring.Capability

local Learned = {}
Scoring.Learned = Learned

local cache   -- key -> { values, median, n, p25, p75 } ; nil => needs rebuild

local function metricFor(role) return (role == "HEALER") and "hps" or "dps" end
local function keyOf(specID, metric, season, bracket)
    return table.concat({ specID or 0, metric or "?", season == nil and "*" or season,
                          bracket == nil and "*" or bracket }, "|")
end

-- Drop the cache; it lazily rebuilds on the next query. Call when the run set changes.
function Learned.Invalidate() cache = nil end

local function median(sorted)
    local n = #sorted
    if n == 0 then return nil end
    if n % 2 == 1 then return sorted[(n + 1) / 2] end
    return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

local function build()
    cache = {}
    local STATUS = ML.STATUS
    local function add(key, v)
        local b = cache[key]; if not b then b = { values = {} }; cache[key] = b end
        b.values[#b.values + 1] = v
    end
    for _, r in ipairs(DB.Runs()) do
        if r.status ~= STATUS.ABANDONED then
            local bracket = Base.KeyBracket(r.level)
            for _, m in ipairs(r.party or {}) do
                local specID = m.specId or m.specID
                local role = m.role or (specID and Cap.Get(specID).role)
                local metric = metricFor(role)
                local val = m.stats and m.stats[metric]
                if specID and type(val) == "number" and val > 0 then
                    add(keyOf(specID, metric, r.seasonId, bracket), val)   -- primary
                    add(keyOf(specID, metric, r.seasonId, nil), val)       -- by season (all key levels)
                    add(keyOf(specID, metric, nil, nil), val)              -- by spec (all seasons)
                end
            end
        end
    end
    for _, b in pairs(cache) do
        table.sort(b.values)
        b.n = #b.values
        b.median = median(b.values)
        if b.n >= 4 then
            b.p25 = b.values[math.max(1, math.floor(b.n * 0.25))]
            b.p75 = b.values[math.min(b.n, math.ceil(b.n * 0.75))]
        end
    end
end

-- The engine hook Baselines.lua calls. query = { metric, specID, seasonId, keyBracket, ... }.
-- Returns median, sampleCount for the most specific bucket with enough samples, else nil.
function Scoring.GetLearnedMedian(query)
    if not query or not query.specID then return nil end
    if not cache then build() end
    local minB = Cfg.learned.minBucketSamples or 3
    local candidates = {
        keyOf(query.specID, query.metric, query.seasonId, query.keyBracket),
        keyOf(query.specID, query.metric, query.seasonId, nil),
        keyOf(query.specID, query.metric, nil, nil),
    }
    for _, k in ipairs(candidates) do
        local b = cache[k]
        if b and (b.n or 0) >= minB then return b.median, b.n end
    end
    return nil
end

-- Debug/inspection: the resolved learned bucket for a spec (nil if none yet).
function Learned.Inspect(specID, metric, seasonId, keyBracket)
    if not cache then build() end
    return cache[keyOf(specID, metric, seasonId, keyBracket)]
end
