-- TAP: Mythic Ledger - Archive.lua
-- COMPACTION: strip a run's review-only detail and keep the run itself. A compacted run still appears
-- in every list, still charts on Progression, and still shows its score and grade; what goes is the
-- deep run-review material (death recap, avoidable breakdown, kick/dispel breakdown, combat timeline).
-- Measured on a real database: 29.1 KB per run full, 3.7 KB compacted.
--
-- Compaction must never move a score. That rests on two things: the fields scoring reads are kept (see
-- the manifest below), and the score is frozen via Store.Freeze BEFORE anything is stripped, so a later
-- engine version cannot rescore a run whose inputs are gone. Plan() is pure and every destructive entry
-- point runs off it, so a confirm dialog can never promise something different from what happens.

local ADDON, ML = ...
local DB = ML.DB

local Archive = {}
ML.Archive = Archive

----------------------------------------------------------------------
-- The strip manifest. One table per level, so what compaction destroys is auditable in one place
-- rather than scattered across assignment lines; each entry names who read the field, so the claim
-- "nothing needs this" can be re-checked rather than trusted.
----------------------------------------------------------------------
local DROP_RUN = {
    combat         = "run-detail timeline only (UI renderRunTimeline)",
    dispelCapture  = "redundant once specId is folded onto the member (Normalize's retroactive fallback)",
    tags           = "written at save, never read anywhere",
    challengeMapId = "exact duplicate of mapId",
}
local DROP_MEMBER = {
    deathRecaps = "raw per-hit timelines; only feed ClassifyMemberDeaths, which we freeze into deathCauses first",
    attribution = "per-spell breakdown; display-only once deathCauses is frozen",
}
-- boss id / totalTime / killDuration are absent on purpose: Distribute time-scales the whole interrupt
-- and dispel supply off them, so dropping them WOULD move scores.
local DROP_BOSS = {
    perMember = "per-member dps/hps split, shown only on the run-review boss card",
    deathList = "who died to this boss, display-only",
    lowAvoid  = "cleanest-player callout, display-only",
}

----------------------------------------------------------------------
-- Rough serialized-byte estimate, used to quote a saving before the work and to size the per-season
-- table. Same shape of walk as Diag.MemoryReport's, but its own copy - this one has to run per-run.
----------------------------------------------------------------------
local function sizeOf(v, seen)
    local t = type(v)
    if t == "number" then return 8
    elseif t == "boolean" then return 4
    elseif t == "string" then return #v + 3
    elseif t == "table" then
        seen = seen or {}
        if seen[v] then return 0 end
        seen[v] = true
        local s = 2
        for k, val in pairs(v) do s = s + sizeOf(k, seen) + sizeOf(val, seen) + 2 end
        return s
    end
    return 0
end
Archive.SizeOf = sizeOf

function Archive.IsCompact(run) return run and run._c and true or false end

----------------------------------------------------------------------
-- Selection. The POLICY (which runs count as old) lives in Database - DB.OutsideWindow - so trimming
-- and deleting can never disagree about it. This file only decides whether a given run CAN be trimmed.
-- opts: { seasonId = id } restricts to one season, for the per-season buttons.
----------------------------------------------------------------------
-- Would a trim pass touch this run? Returns true, or false plus the reason it was skipped.
-- Only the user's own locks stop a trim. retentionKeepTop deliberately does NOT: it guards against
-- DELETION, and a trimmed run is still present, still crowned and still scored - there is nothing for
-- it to defend. (Honouring it here would exempt roughly half a real history and undo most of the win.)
function Archive.Eligible(run, opts, sc, days, cur, expac, now)
    if type(run) ~= "table" then return false, "invalid" end
    if Archive.IsCompact(run) then return false, "already" end
    if DB.IsLocked(run) then return false, "locked" end
    if opts.seasonId then
        if run.seasonId ~= opts.seasonId then return false, "other-season" end
        return true
    end
    if DB.OutsideWindow(run, sc, days, cur, expac, now) then return true end
    return false, "in-window"
end

-- PURE. What a trim pass would do, without doing any of it. This is both the confirm-dialog source and
-- the test instrument, so the dialog and the work can never disagree.
function Archive.Plan(opts)
    opts = opts or {}
    local out = { compact = 0, locked = 0, already = 0, skipped = 0, bytes = 0, runs = {} }
    if not DB.root then return out end
    local sc, days, cur, expac, now = DB.WindowParams()
    -- The settings page previews a STAGED policy that hasn't been committed yet, so let it override.
    if opts.scope then sc = opts.scope end
    if opts.days then days = tonumber(opts.days) or days end
    -- Resolve player-level locks first so "locked" is accurate.
    if DB.MarkProtected then DB.MarkProtected() end
    for _, run in ipairs(DB.Runs()) do
        local ok, why = Archive.Eligible(run, opts, sc, days, cur, expac, now)
        if ok then
            out.compact = out.compact + 1
            out.runs[#out.runs + 1] = run
            out.bytes = out.bytes + Archive.Estimate(run)
        elseif why == "locked" then out.locked = out.locked + 1
        elseif why == "already" then out.already = out.already + 1
        else out.skipped = out.skipped + 1 end
    end
    return out
end

-- Bytes this one run would give back (sum of everything the manifest drops).
function Archive.Estimate(run)
    local n = 0
    for f in pairs(DROP_RUN) do n = n + sizeOf(run[f]) end
    for _, m in ipairs(run.party or {}) do
        for f in pairs(DROP_MEMBER) do n = n + sizeOf(m[f]) end
    end
    for _, bs in ipairs(run.bosses or {}) do
        for f in pairs(DROP_BOSS) do n = n + sizeOf(bs[f]) end
    end
    return n
end

----------------------------------------------------------------------
-- The strip itself.
----------------------------------------------------------------------
-- Compact ONE run. Returns bytes freed, or nil plus a reason if it refused. The step order below is
-- load-bearing: everything frozen or rescued needs the detail that step 4 destroys.
function Archive.CompactRun(run)
    if type(run) ~= "table" then return nil, "invalid" end
    if Archive.IsCompact(run) then return nil, "already" end
    local before = Archive.Estimate(run)

    -- 1. Freeze the score. If it can't be scored we must NOT strip it - there would be no answer left.
    local Store = ML.Scoring and ML.Scoring.Store
    if not (Store and Store.Freeze) then return nil, "no-store" end
    if not Store.Freeze(run) then return nil, "unscorable" end

    -- 2. Freeze death causes while the raw recaps still exist. Normalize prefers member.deathCauses
    --    when recaps are gone, so this is what keeps the Death category stable forever.
    local Providers = ML.Providers
    if Providers and Providers.ClassifyMemberDeaths then
        for _, m in ipairs(run.party or {}) do
            local deaths = m.stats and m.stats.deaths
            if type(deaths) == "number" and deaths > 0 and not m.deathCauses then
                local ok, causes = pcall(Providers.ClassifyMemberDeaths, run, m)
                if ok and causes then m.deathCauses = causes end
            end
        end
    end

    -- 3. Rescue the live-inspected spec before its table goes (Scoring/Normalize's fallback).
    local cap = (type(run.dispelCapture) == "table") and run.dispelCapture or nil
    if cap then
        for _, m in ipairs(run.party or {}) do
            if not (m.specId or m.specID) and m.guid then
                local c = cap[m.guid]
                if type(c) == "table" and type(c.specID) == "number" and c.specID > 0 then m.specId = c.specID end
            end
        end
    end

    -- 4. Strip.
    for f in pairs(DROP_RUN) do run[f] = nil end
    for _, m in ipairs(run.party or {}) do
        for f in pairs(DROP_MEMBER) do m[f] = nil end
    end
    for _, bs in ipairs(run.bosses or {}) do
        for f in pairs(DROP_BOSS) do bs[f] = nil end
    end
    run._c = 1   -- tier marker: compacted. Numeric so a future deeper tier stays expressible.
    return before
end

-- Run a compaction pass. Returns { runs, bytes, locked, already }.
-- Destructive, but only ever within what Plan() reported.
function Archive.Compact(opts)
    local plan = Archive.Plan(opts)
    local done, bytes = 0, 0
    for _, run in ipairs(plan.runs) do
        local freed = Archive.CompactRun(run)
        if freed then done = done + 1; bytes = bytes + freed end
    end
    if done > 0 then
        -- Nothing stripped feeds the derived caches, but bests and crowns are re-derived anyway so
        -- nothing downstream is left holding a stale reference.
        if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    end
    ML.Log("Compacted %d run(s), freed ~%.2f MB (%d locked, %d already compact)",
        done, bytes / 1048576, plan.locked, plan.already)
    return { runs = done, bytes = bytes, locked = plan.locked, already = plan.already }
end

----------------------------------------------------------------------
-- Convenience wrappers used by the settings page.
----------------------------------------------------------------------
-- One explicit season, from the per-season buttons.
function Archive.PlanSeason(seasonId) return Archive.Plan({ seasonId = seasonId }) end
function Archive.CompactSeason(seasonId) return Archive.Compact({ seasonId = seasonId }) end

----------------------------------------------------------------------
-- AUTOMATIC pass, run once per login.
--
-- There is deliberately NO rollover special-case. The policy is continuous - "anything outside the
-- full-detail window" - so when a season ends its runs simply fall outside a SEASON window and the
-- ordinary pass picks them up. A separate rollover branch would be a second code path computing the
-- same answer, which is how the two-policy tangle started.
--
-- The one guard: a SEASON window cannot be judged until the season API answers (it reports -1 for a
-- while after login), so bail and let DB.Init's retry call us again rather than acting on a guess.
----------------------------------------------------------------------
function Archive.AutoRun()
    if not DB.root then return end
    if not DB.Settings().retentionAuto then return end   -- manual-only: never act without an Apply click
    local scope, _, cur = DB.WindowParams()
    if scope == "SEASON" and not cur then return end     -- season unknown yet; caller retries

    local last = DB.root.lastSeenSeason
    if cur then DB.root.lastSeenSeason = cur end
    if type(last) == "number" and cur and last > 0 and last ~= cur then
        ML.Log("Season rollover: %d -> %d", last, cur)
    end

    if DB.ApplyRetention then
        local res = DB.ApplyRetention()
        if type(res) == "table" and (res.trimmed > 0 or res.removed > 0) then
            local bits = {}
            if res.trimmed > 0 then
                bits[#bits + 1] = string.format("trimmed %d run%s (%.1f MB back)",
                    res.trimmed, res.trimmed == 1 and "" or "s", res.bytes / 1048576)
            end
            if res.removed > 0 then
                bits[#bits + 1] = string.format("removed %d run%s", res.removed, res.removed == 1 and "" or "s")
            end
            ML.Print("History policy ran: %s. Change it in Settings > Tracking.", table.concat(bits, " and "))
        end
    end
end
