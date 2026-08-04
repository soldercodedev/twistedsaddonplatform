-- TAP: Mythic Ledger - History.lua
-- Derived data built from the raw run records: per-character aggregates, per-party-member
-- summaries (the "who you've run with" index), personal bests, and the statistics/recap queries
-- the UI and RecapService consume. Everything here is rebuildable from DB.runs; user annotations
-- (notes / tags / favorite) live in the PERSISTENT DB.playerMeta store so a rebuild never loses
-- them. Averages are always kept per-role so we never mix healer HPS with DPS damage.

local ADDON, ML = ...
local API    = ML.API
local DB     = ML.DB
local Util   = ML.Util
local STATUS = ML.STATUS

local History = {}
ML.History = History

local ROLE_METRICS = { "damage", "dps", "damageTaken", "healing", "hps",
                       "interrupts", "dispels", "crowdControls", "deaths" }

----------------------------------------------------------------------
-- Aggregate helpers.
----------------------------------------------------------------------
local function emptyTotals() return { runs = 0, completed = 0, timed = 0, depleted = 0, abandoned = 0 } end

local function bumpTotals(t, status)
    t.runs = t.runs + 1
    if status == STATUS.ABANDONED then
        t.abandoned = t.abandoned + 1
    else
        t.completed = t.completed + 1
        if status == STATUS.TIMED then t.timed = t.timed + 1
        elseif status == STATUS.DEPLETED then t.depleted = t.depleted + 1 end
    end
end

-- Accumulate metric sum+count into a stats bucket (nil metrics are skipped, never counted as 0).
local function accStats(bucket, stats)
    if type(stats) ~= "table" then return end
    for _, k in ipairs(ROLE_METRICS) do
        local v = stats[k]
        if type(v) == "number" then
            bucket[k .. "_sum"] = (bucket[k .. "_sum"] or 0) + v
            bucket[k .. "_n"]   = (bucket[k .. "_n"] or 0) + 1
        end
    end
end

local function avgOf(bucket, k)
    if type(bucket) ~= "table" then return nil end
    local n = bucket[k .. "_n"]
    if not n or n == 0 then return nil end
    return bucket[k .. "_sum"] / n
end
History.avgOf = avgOf

local function timedPct(t)
    return Util.safeDiv(t.timed, t.completed)
end
History.timedPct = timedPct

----------------------------------------------------------------------
-- Character aggregates (the runner).
----------------------------------------------------------------------
local function characterFor(run)
    local c = run.character or {}
    local key = c.fullName or c.guid or "?"
    local chars = DB.Characters()
    local rec = chars[key]
    if not rec then
        rec = {
            key = key, guid = c.guid, name = c.name, realm = c.realm, fullName = c.fullName,
            classFile = c.classFile, classId = c.classId,
            totals = emptyTotals(), byRole = {},
            highestTimed = nil, highestCompleted = nil,
            levelSum = 0, levelN = 0, stats = {}, dungeons = {}, lastSeenAt = nil,
        }
        chars[key] = rec
    end
    return rec
end

local function ingestCharacter(run)
    local rec = characterFor(run)
    bumpTotals(rec.totals, run.status)
    rec.lastSeenAt = math.max(rec.lastSeenAt or 0, run.completedAt or run.startedAt or 0)
    rec.classFile = run.character and run.character.classFile or rec.classFile
    local role = run.character and run.character.role
    if role then
        rec.byRole[role] = rec.byRole[role] or { totals = emptyTotals(), stats = {} }
        bumpTotals(rec.byRole[role].totals, run.status)
        accStats(rec.byRole[role].stats, run.playerStats)
    end
    if run.status ~= STATUS.ABANDONED and type(run.level) == "number" then
        rec.levelSum = rec.levelSum + run.level; rec.levelN = rec.levelN + 1
        if not rec.highestCompleted or run.level > rec.highestCompleted then rec.highestCompleted = run.level end
        if run.status == STATUS.TIMED and (not rec.highestTimed or run.level > rec.highestTimed) then
            rec.highestTimed = run.level
        end
    end
    accStats(rec.stats, run.playerStats)
    if run.mapId then
        rec.dungeons[run.mapId] = rec.dungeons[run.mapId] or { name = run.dungeonName, runs = 0, timed = 0 }
        rec.dungeons[run.mapId].runs = rec.dungeons[run.mapId].runs + 1
        if run.status == STATUS.TIMED then rec.dungeons[run.mapId].timed = rec.dungeons[run.mapId].timed + 1 end
    end
end

----------------------------------------------------------------------
-- Party-member summaries (people you've run with).
----------------------------------------------------------------------
local function playerSummaryFor(identityKey, member)
    local index = DB.PlayerIndex()
    local rec = index[identityKey]
    if not rec then
        local meta = DB.PlayerMeta()[identityKey] or {}
        rec = {
            identityKey = identityKey,
            guid = member.guid, name = member.name, realm = member.realm, fullName = member.fullName,
            classId = member.classId, classFile = member.classFile,
            lastKnownSpecId = member.specId, lastKnownRole = member.role, lastKnownItemLevel = member.itemLevel,
            guildName = member.guildName,
            firstSeenAt = nil, lastSeenAt = nil,
            totals = emptyTotals(),
            byRole = {}, bySpec = {}, byDungeon = {}, bySeason = {},
            highestTimed = nil, levelSum = 0, levelN = 0,
            stats = {},   -- role-agnostic accumulation (for quick counts like avg deaths)
            notes = meta.notes or "", tags = meta.tags or {}, favorite = meta.favorite and true or false,
        }
        index[identityKey] = rec
    end
    return rec
end

local function ingestPlayers(run)
    for _, m in ipairs(run.party or {}) do
        if not m.isPlayer then
            local key = API.IdentityKey(m)
            if key then   -- refuse to key on an unqualified name (would merge different realms)
                local rec = playerSummaryFor(key, m)
                local at = run.completedAt or run.startedAt or 0
                rec.firstSeenAt = rec.firstSeenAt and math.min(rec.firstSeenAt, at) or at
                rec.lastSeenAt  = math.max(rec.lastSeenAt or 0, at)
                -- Freshen last-known identity where the run has better info.
                rec.guid = m.guid or rec.guid
                rec.classId = m.classId or rec.classId
                rec.classFile = m.classFile or rec.classFile
                rec.guildName = m.guildName or rec.guildName
                if m.specId then rec.lastKnownSpecId = m.specId end
                if m.specIcon then rec.lastKnownSpecIcon = m.specIcon end
                if m.role then rec.lastKnownRole = m.role end
                if m.itemLevel then rec.lastKnownItemLevel = m.itemLevel end

                bumpTotals(rec.totals, run.status)
                accStats(rec.stats, m.stats)
                if run.status ~= STATUS.ABANDONED and type(run.level) == "number" then
                    rec.levelSum = rec.levelSum + run.level; rec.levelN = rec.levelN + 1
                    if run.status == STATUS.TIMED and (not rec.highestTimed or run.level > rec.highestTimed) then
                        rec.highestTimed = run.level
                    end
                end
                local role = m.role
                if role then
                    rec.byRole[role] = rec.byRole[role] or { totals = emptyTotals(), stats = {} }
                    bumpTotals(rec.byRole[role].totals, run.status)
                    accStats(rec.byRole[role].stats, m.stats)
                end
                -- Per-SPEC breakdown (a player who's switched specs gets one bucket per spec played).
                if m.specId then
                    rec.bySpec = rec.bySpec or {}
                    local sb = rec.bySpec[m.specId]
                        or { specId = m.specId, role = m.role, classFile = m.classFile, totals = emptyTotals(), stats = {} }
                    if m.specIcon then sb.specIcon = m.specIcon end
                    if m.role then sb.role = m.role end
                    if m.classFile then sb.classFile = m.classFile end
                    bumpTotals(sb.totals, run.status)
                    accStats(sb.stats, m.stats)
                    rec.bySpec[m.specId] = sb
                end
                if run.mapId then
                    rec.byDungeon[run.mapId] = rec.byDungeon[run.mapId] or { name = run.dungeonName, runs = 0, timed = 0 }
                    rec.byDungeon[run.mapId].runs = rec.byDungeon[run.mapId].runs + 1
                    if run.status == STATUS.TIMED then rec.byDungeon[run.mapId].timed = rec.byDungeon[run.mapId].timed + 1 end
                end
                if run.seasonId then
                    rec.bySeason[run.seasonId] = rec.bySeason[run.seasonId] or { runs = 0, timed = 0 }
                    rec.bySeason[run.seasonId].runs = rec.bySeason[run.seasonId].runs + 1
                    if run.status == STATUS.TIMED then rec.bySeason[run.seasonId].timed = rec.bySeason[run.seasonId].timed + 1 end
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Personal bests (for the runner). Cross-key comparisons are avoided: "fastest" is tracked per
-- key level, and role-specific bests are kept apart.
----------------------------------------------------------------------
local function updateBests(run)
    local pb = DB.PersonalBests()
    local newBests = {}
    local function better(field, value, payload, cmp)
        if type(value) ~= "number" then return end
        local cur = pb[field]
        if not cur or cmp(value, cur.value) then
            pb[field] = payload
            payload.value = value
            newBests[#newBests + 1] = field
        end
    end
    local gt = function(a, b) return a > b end
    local lt = function(a, b) return a < b end
    local ps = run.playerStats or {}

    if run.status == STATUS.TIMED and type(run.level) == "number" then
        better("highestTimedKey", run.level, { level = run.level, runId = run.id, dungeon = run.dungeonName }, gt)
        -- Fastest completion PER key level (never compared across levels).
        pb.fastestByLevel = pb.fastestByLevel or {}
        local cur = pb.fastestByLevel[run.level]
        if run.duration and (not cur or run.duration < cur.duration) then
            pb.fastestByLevel[run.level] = { duration = run.duration, runId = run.id, dungeon = run.dungeonName }
            newBests[#newBests + 1] = "fastestByLevel"
        end
    end
    if run.status ~= STATUS.ABANDONED then
        -- YOUR deaths (0 on a clean tracked run), not the whole party's - matches the sibling PBs (ps.*).
        local myDeaths = (type(ps.deaths) == "number" and ps.deaths)
            or (((type(ps.dps) == "number") or (type(ps.damage) == "number")
                 or (type(ps.hps) == "number") or (type(ps.healing) == "number")) and 0) or nil
        better("lowestDeaths", myDeaths, { runId = run.id, dungeon = run.dungeonName, level = run.level }, lt)
        better("highestDPS", ps.dps, { runId = run.id, dungeon = run.dungeonName, level = run.level }, gt)
        better("highestHPS", ps.hps, { runId = run.id, dungeon = run.dungeonName, level = run.level }, gt)
        better("mostInterrupts", ps.interrupts, { runId = run.id, dungeon = run.dungeonName, level = run.level }, gt)
        better("mostDispels", ps.dispels, { runId = run.id, dungeon = run.dungeonName, level = run.level }, gt)
    end
    -- Fastest boss kill splits (per encounter id).
    pb.fastestBoss = pb.fastestBoss or {}
    for _, boss in ipairs(run.bosses or {}) do
        if type(boss.killDuration) == "number" and boss.id then
            local cur = pb.fastestBoss[boss.id]
            if not cur or boss.killDuration < cur.duration then
                pb.fastestBoss[boss.id] = { duration = boss.killDuration, name = boss.name, runId = run.id }
            end
        end
    end
    run._newBests = newBests
    return newBests
end

----------------------------------------------------------------------
-- Public ingest / rebuild.
----------------------------------------------------------------------
function History.IngestRun(run)
    if not DB.Ready() then return end
    ingestCharacter(run)
    ingestPlayers(run)
end

function History.OnRunSaved(run)
    History.IngestRun(run)
    updateBests(run)
    -- Re-decide the crown (best-scoring run per dungeon+key+spec): a new higher-scoring run takes it and
    -- the previous holder is un-flagged. The run was already scored at finalize, so its summary is ready.
    if DB.MarkBestRuns then DB.MarkBestRuns() end
end

function History.RebuildAll()
    local root = DB.root
    if not root then return end
    root.characters = {}
    root.playerIndex = {}
    root.personalBests = {}
    local runs = root.runs
    table.sort(runs, function(a, b)
        return (a.completedAt or a.startedAt or 0) < (b.completedAt or b.startedAt or 0)
    end)
    for _, run in ipairs(runs) do
        History.IngestRun(run)
        updateBests(run)
    end
    if DB.MarkKeepers then DB.MarkKeepers() end   -- best-per-dungeon + top-10 (retention keepers)
    if DB.MarkBestRuns then DB.MarkBestRuns() end -- crown: best score per dungeon+key+spec
    ML.Log("Rebuilt caches: %d character(s), %d player(s)", Util.count(root.characters), Util.count(root.playerIndex))
end

----------------------------------------------------------------------
-- User annotations (persist in DB.playerMeta AND update the live summary).
----------------------------------------------------------------------
local function metaFor(identityKey)
    local m = DB.PlayerMeta()
    m[identityKey] = m[identityKey] or {}
    return m[identityKey]
end

function History.SetPlayerNote(identityKey, text)
    metaFor(identityKey).notes = text or ""
    local rec = DB.PlayerIndex()[identityKey]; if rec then rec.notes = text or "" end
end
function History.SetPlayerFavorite(identityKey, fav)
    metaFor(identityKey).favorite = fav and true or false
    local rec = DB.PlayerIndex()[identityKey]; if rec then rec.favorite = fav and true or false end
end
function History.SetPlayerTags(identityKey, tags)
    metaFor(identityKey).tags = tags or {}
    local rec = DB.PlayerIndex()[identityKey]; if rec then rec.tags = tags or {} end
end

----------------------------------------------------------------------
-- Queries used by the UI + recap.
----------------------------------------------------------------------
-- Distinct season ids present in the data, newest first.
function History.SeasonsPresent()
    local set = {}
    for _, r in ipairs(DB.Runs()) do if r.seasonId then set[r.seasonId] = true end end
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list, function(a, b) return a > b end)
    return list
end

-- Filter runs. opts: seasonId, character(fullName), mapId, role, keyMin, keyMax, status,
-- provider, playerKey(identityKey of a party member), from, to. Nil fields are ignored.
function History.FilterRuns(opts)
    opts = opts or {}
    local out = {}
    for _, r in ipairs(DB.Runs()) do
        local ok = true
        if opts.seasonId and r.seasonId ~= opts.seasonId then ok = false end
        if ok and opts.character and (not r.character or r.character.fullName ~= opts.character) then ok = false end
        if ok and opts.mapId and r.mapId ~= opts.mapId then ok = false end
        if ok and opts.status and r.status ~= opts.status then ok = false end
        if ok and opts.provider and r.provider ~= opts.provider then ok = false end
        if ok and opts.keyMin and (type(r.level) ~= "number" or r.level < opts.keyMin) then ok = false end
        if ok and opts.keyMax and (type(r.level) ~= "number" or r.level > opts.keyMax) then ok = false end
        if ok and opts.from and (r.completedAt or r.startedAt or 0) < opts.from then ok = false end
        if ok and opts.to and (r.completedAt or r.startedAt or 0) > opts.to then ok = false end
        if ok and opts.role and (not r.character or r.character.role ~= opts.role) then ok = false end
        if ok and opts.playerKey then
            local found = false
            for _, m in ipairs(r.party or {}) do
                if not m.isPlayer and API.IdentityKey(m) == opts.playerKey then found = true; break end
            end
            if not found then ok = false end
        end
        if ok then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        return (a.completedAt or a.startedAt or 0) > (b.completedAt or b.startedAt or 0)
    end)
    return out
end

-- Your OWN death count for a run, for averages. A clean run records NO death rows, so a tracked player
-- who didn't die reads back `nil` - but that means ZERO deaths, not "no data". So: return the number if
-- present; return 0 when the run clearly tracked your combat (you have real damage/healing numbers, i.e.
-- the meter was live and simply logged no deaths); return nil only when the run genuinely wasn't tracked.
-- Without this, clean runs are excluded and "avg deaths" is skewed toward only the runs you died in.
local function playerDeaths(r)
    local ps = r and r.playerStats
    if not ps then return nil end
    if type(ps.deaths) == "number" then return ps.deaths end
    if type(ps.dps) == "number" or type(ps.damage) == "number"
        or type(ps.hps) == "number" or type(ps.healing) == "number" then return 0 end
    return nil
end
History.PlayerDeaths = playerDeaths   -- exposed so UI-side summaries use YOUR deaths, not the party's

-- Overview stats for a season (nil = all seasons).
function History.Overview(seasonId, character)
    local runs = History.FilterRuns({ seasonId = seasonId, character = character })
    local o = {
        runs = #runs, timed = 0, completed = 0, depleted = 0, abandoned = 0,
        highestTimed = nil, highestTimedDungeon = nil, levelSum = 0, levelN = 0,
        durationSum = 0, durationN = 0, deathsSum = 0, deathsN = 0,
        keyMin = nil, keyMax = nil, bestTime = nil, bestTimeDungeon = nil, thisWeekRuns = 0,
        dungeonCount = {}, charCount = {}, returning = 0,
    }
    local seen = {}
    local weekAgo = time() - 7 * 86400
    local recent = {}   -- completed runs, for a "last N" window
    for _, r in ipairs(runs) do
        if r.status == STATUS.ABANDONED then o.abandoned = o.abandoned + 1
        else
            o.completed = o.completed + 1
            recent[#recent + 1] = r
            if r.status == STATUS.TIMED then o.timed = o.timed + 1 else o.depleted = o.depleted + 1 end
            if type(r.level) == "number" then
                o.levelSum = o.levelSum + r.level; o.levelN = o.levelN + 1
                if not o.keyMin or r.level < o.keyMin then o.keyMin = r.level end
                if not o.keyMax or r.level > o.keyMax then o.keyMax = r.level end
                if r.status == STATUS.TIMED and (not o.highestTimed or r.level > o.highestTimed) then
                    o.highestTimed = r.level; o.highestTimedDungeon = r.dungeonName
                end
            end
            if type(r.duration) == "number" then o.durationSum = o.durationSum + r.duration; o.durationN = o.durationN + 1 end
            if r.status == STATUS.TIMED and type(r.duration) == "number"
                and (not o.bestTime or r.duration < o.bestTime) then
                o.bestTime = r.duration; o.bestTimeDungeon = r.dungeonName
            end
        end
        -- AVG DEATHS reflects YOUR OWN deaths per run (from your combat stats), not the whole party.
        -- Clean runs count as 0 (not skipped) - see playerDeaths - so the average isn't skewed high.
        local myDeaths = playerDeaths(r)
        if type(myDeaths) == "number" then o.deathsSum = o.deathsSum + myDeaths; o.deathsN = o.deathsN + 1 end
        if (r.completedAt or r.startedAt or 0) >= weekAgo then o.thisWeekRuns = o.thisWeekRuns + 1 end
        if r.mapId then
            local d = o.dungeonCount[r.mapId] or { name = r.dungeonName, mapId = r.mapId, n = 0, highestTimed = nil }
            d.n = d.n + 1
            if r.dungeonName then d.name = r.dungeonName end
            if r.status == STATUS.TIMED and type(r.level) == "number"
                and (not d.highestTimed or r.level > d.highestTimed) then d.highestTimed = r.level end
            o.dungeonCount[r.mapId] = d
        end
        local cc = r.character
        local ck = cc and cc.fullName
        if ck then
            local c = o.charCount[ck] or { n = 0, fullName = ck, name = cc.name, realm = cc.realm, classFile = cc.classFile }
            c.n = c.n + 1
            if cc.classFile then c.classFile = cc.classFile end
            o.charCount[ck] = c
        end
        for _, m in ipairs(r.party or {}) do
            if not m.isPlayer then
                local k = API.IdentityKey(m)
                if k then seen[k] = (seen[k] or 0) + 1 end
            end
        end
    end
    o.timedPct = Util.safeDiv(o.timed, o.completed)
    o.avgLevel = Util.safeDiv(o.levelSum, o.levelN)
    o.avgDuration = Util.safeDiv(o.durationSum, o.durationN)
    o.avgDeaths = Util.safeDiv(o.deathsSum, o.deathsN)
    -- Last-10 completed runs (by recency): timed % and your avg deaths, for the card subtext lines.
    table.sort(recent, function(a, b) return (a.completedAt or 0) > (b.completedAt or 0) end)
    local n10, timed10, dSum10, dN10 = 0, 0, 0, 0
    for i = 1, math.min(10, #recent) do
        local r = recent[i]; n10 = n10 + 1
        if r.status == STATUS.TIMED then timed10 = timed10 + 1 end
        local md = playerDeaths(r)   -- clean run = 0, not "no data"
        if type(md) == "number" then dSum10 = dSum10 + md; dN10 = dN10 + 1 end
    end
    o.last10 = { n = n10, timedPct = Util.safeDiv(timed10, n10), avgDeaths = Util.safeDiv(dSum10, dN10) }
    -- Returning players = distinct party members seen more than once (in scope).
    -- Players met = distinct party members seen at all (in scope).
    o.playersMet = 0
    for _, n in pairs(seen) do o.playersMet = o.playersMet + 1; if n > 1 then o.returning = o.returning + 1 end end
    -- Most-played dungeon / character. Keep the rich record (name, mapId, runs, highest timed key /
    -- class) for the Overview hero cards, plus a plain string for anything that just wants a label.
    local bestD, bestDN
    for _, d in pairs(o.dungeonCount) do if not bestDN or d.n > bestDN then bestDN = d.n; bestD = d end end
    o.topDungeonInfo = bestD
    o.topDungeon = bestD and bestD.name
    local bestC, bestCN
    for _, c in pairs(o.charCount) do if not bestCN or c.n > bestCN then bestCN = c.n; bestC = c end end
    o.topCharInfo = bestC
    o.topCharacter = bestC and (bestC.name or bestC.fullName)
    return o
end

-- Per-dungeon aggregates for a season.
function History.DungeonStats(seasonId, character)
    local map = {}
    for _, r in ipairs(History.FilterRuns({ seasonId = seasonId, character = character })) do
        if r.mapId then
            local d = map[r.mapId]
            if not d then
                d = { mapId = r.mapId, name = r.dungeonName, totals = emptyTotals(),
                      highestTimed = nil, highestCompleted = nil, bestTime = nil, timeSum = 0, timeN = 0,
                      deathsSum = 0, deathsN = 0,
                      mates = {}, bestDps = nil, worstDps = nil, bestHps = nil }
                map[r.mapId] = d
            end
            bumpTotals(d.totals, r.status)
            if r.status ~= STATUS.ABANDONED and type(r.level) == "number" then
                if not d.highestCompleted or r.level > d.highestCompleted then d.highestCompleted = r.level end
                if r.status == STATUS.TIMED and (not d.highestTimed or r.level > d.highestTimed) then d.highestTimed = r.level end
            end
            if r.status == STATUS.TIMED and type(r.duration) == "number" then
                if not d.bestTime or r.duration < d.bestTime then d.bestTime = r.duration end
                d.timeSum = d.timeSum + r.duration; d.timeN = d.timeN + 1
            end
            local myDeaths = playerDeaths(r)   -- YOUR deaths per run for the average, not the whole party's
            if type(myDeaths) == "number" then d.deathsSum = d.deathsSum + myDeaths; d.deathsN = d.deathsN + 1 end
            -- Your own best/worst performance in this dungeon (from your own stats).
            if r.status ~= STATUS.ABANDONED then
                local ps = r.playerStats
                if ps then
                    if type(ps.dps) == "number" then
                        if not d.bestDps or ps.dps > d.bestDps then d.bestDps = ps.dps end
                        if not d.worstDps or ps.dps < d.worstDps then d.worstDps = ps.dps end
                    end
                    if type(ps.hps) == "number" and (not d.bestHps or ps.hps > d.bestHps) then d.bestHps = ps.hps end
                end
            end
            -- Who you run this dungeon with most (distinct party members, by run count here).
            for _, m in ipairs(r.party or {}) do
                if not m.isPlayer then
                    local k = API.IdentityKey(m)
                    if k then
                        local mate = d.mates[k]
                        if not mate then mate = { name = m.name or "?", classFile = m.classFile, n = 0 }; d.mates[k] = mate end
                        mate.n = mate.n + 1
                        if m.classFile then mate.classFile = m.classFile end
                    end
                end
            end
        end
    end
    local list = {}
    for _, d in pairs(map) do
        d.timedPct = timedPct(d.totals)
        d.avgTime = Util.safeDiv(d.timeSum, d.timeN)
        d.avgDeaths = Util.safeDiv(d.deathsSum, d.deathsN)
        -- Resolve the most-frequent party member for the at-a-glance tooltip.
        local topMate, topN
        for _, mate in pairs(d.mates) do
            if not topN or mate.n > topN then topN = mate.n; topMate = mate end
        end
        d.topMate = topMate
        list[#list + 1] = d
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

-- Per-boss aggregates for one dungeon across all its runs in scope. For each encounter: how many
-- times pulled (engaged), killed, wiped, party deaths on it, and your kill DPS spread (best / low /
-- avg) plus kill-time (best / avg). Sorted by the boss's typical position in the dungeon.
function History.DungeonBosses(mapId, seasonId, character)
    if not mapId then return {} end
    local map, order = {}, {}
    for _, r in ipairs(History.FilterRuns({ mapId = mapId, seasonId = seasonId, character = character })) do
        for _, e in ipairs(r.bosses or {}) do
            local key = e.id or e.name
            if key then
                local b = map[key]
                if not b then
                    b = { id = e.id, name = e.name, engaged = 0, kills = 0, wipes = 0, deaths = 0,
                          timeSum = 0, timeN = 0, bestTime = nil,
                          dpsSum = 0, dpsN = 0, bestDps = nil, lowDps = nil, orderSum = 0, orderN = 0 }
                    map[key] = b; order[#order + 1] = b
                end
                b.engaged = b.engaged + (e.attempts or 0)
                b.kills   = b.kills + (e.kills or 0)
                b.wipes   = b.wipes + (e.wipes or 0)
                b.deaths  = b.deaths + (e.deaths or 0)
                if type(e.killDuration) == "number" then
                    b.timeSum = b.timeSum + e.killDuration; b.timeN = b.timeN + 1
                    if not b.bestTime or e.killDuration < b.bestTime then b.bestTime = e.killDuration end
                end
                if type(e.killDps) == "number" and e.killDps > 0 then
                    b.dpsSum = b.dpsSum + e.killDps; b.dpsN = b.dpsN + 1
                    if not b.bestDps or e.killDps > b.bestDps then b.bestDps = e.killDps end
                    if not b.lowDps or e.killDps < b.lowDps then b.lowDps = e.killDps end
                end
                if type(e.order) == "number" then b.orderSum = b.orderSum + e.order; b.orderN = b.orderN + 1 end
            end
        end
    end
    for _, b in ipairs(order) do
        b.avgTime  = Util.safeDiv(b.timeSum, b.timeN)
        b.avgDps   = Util.safeDiv(b.dpsSum, b.dpsN)
        b.avgOrder = (b.orderN > 0) and (b.orderSum / b.orderN) or 999
    end
    table.sort(order, function(a, b) return a.avgOrder < b.avgOrder end)
    return order
end

-- Per-spec breakdown for one character (computed live from raw runs, so it always reflects the
-- full history even before a cache rebuild). seasonId nil = all seasons. Sorted by run count.
function History.CharacterSpecBreakdown(fullName, seasonId)
    if not fullName then return {} end
    local specs, order = {}, {}
    for _, r in ipairs(DB.Runs()) do
        local c = r.character
        if c and c.fullName == fullName and (not seasonId or r.seasonId == seasonId) then
            local sid = c.specId or 0
            local sp = specs[sid]
            if not sp then
                sp = { specId = c.specId, specName = c.specName, role = c.role,
                       totals = emptyTotals(), levelSum = 0, levelN = 0, highestTimed = nil }
                specs[sid] = sp; order[#order + 1] = sp
            end
            bumpTotals(sp.totals, r.status)
            if r.status ~= STATUS.ABANDONED and type(r.level) == "number" then
                sp.levelSum = sp.levelSum + r.level; sp.levelN = sp.levelN + 1
                if r.status == STATUS.TIMED and (not sp.highestTimed or r.level > sp.highestTimed) then
                    sp.highestTimed = r.level
                end
            end
        end
    end
    for _, sp in ipairs(order) do
        sp.avgLevel = Util.safeDiv(sp.levelSum, sp.levelN)
        sp.timedPct = timedPct(sp.totals)
    end
    table.sort(order, function(a, b) return (a.totals.runs or 0) > (b.totals.runs or 0) end)
    return order
end

-- Deep per-character report for the character-details page: overall totals + your best/worst
-- performance, a per-SPEC breakdown (with role-appropriate averages, for comparing specs), and a
-- per-DUNGEON breakdown - all computed in a single pass over the (optionally season-scoped) runs.
function History.CharacterDetail(fullName, seasonId)
    if not fullName then return nil end
    local o = { totals = emptyTotals(), levelSum = 0, levelN = 0, durSum = 0, durN = 0,
                deathsSum = 0, deathsN = 0, highestTimed = nil, bestDps = nil, worstDps = nil,
                bestHps = nil, stats = {}, classFile = nil, firstSeenAt = nil, lastSeenAt = nil }
    local specs, specOrder = {}, {}
    local duns, dunOrder = {}, {}
    for _, r in ipairs(DB.Runs()) do
        local c = r.character
        if c and c.fullName == fullName and (not seasonId or r.seasonId == seasonId) then
            o.classFile = c.classFile or o.classFile
            local at = r.completedAt or r.startedAt or 0
            o.lastSeenAt = math.max(o.lastSeenAt or 0, at)
            o.firstSeenAt = o.firstSeenAt and math.min(o.firstSeenAt, at) or at
            bumpTotals(o.totals, r.status)
            local ps = r.playerStats or {}
            local myDeaths = playerDeaths(r)   -- YOUR deaths for the averages below, not the whole party's
            accStats(o.stats, ps)
            if r.status ~= STATUS.ABANDONED then
                if type(r.level) == "number" then
                    o.levelSum = o.levelSum + r.level; o.levelN = o.levelN + 1
                    if r.status == STATUS.TIMED and (not o.highestTimed or r.level > o.highestTimed) then o.highestTimed = r.level end
                end
                if type(r.duration) == "number" then o.durSum = o.durSum + r.duration; o.durN = o.durN + 1 end
                if type(ps.dps) == "number" then
                    if not o.bestDps or ps.dps > o.bestDps then o.bestDps = ps.dps end
                    if not o.worstDps or ps.dps < o.worstDps then o.worstDps = ps.dps end
                end
                if type(ps.hps) == "number" and (not o.bestHps or ps.hps > o.bestHps) then o.bestHps = ps.hps end
            end
            if type(myDeaths) == "number" then o.deathsSum = o.deathsSum + myDeaths; o.deathsN = o.deathsN + 1 end

            -- Per spec (role-appropriate averages let you compare specs on the same toon).
            local sid = c.specId or 0
            local sp = specs[sid]
            if not sp then
                sp = { specId = c.specId, specName = c.specName, role = c.role, totals = emptyTotals(),
                       levelSum = 0, levelN = 0, highestTimed = nil, stats = {}, deathsSum = 0, deathsN = 0 }
                specs[sid] = sp; specOrder[#specOrder + 1] = sp
            end
            bumpTotals(sp.totals, r.status)
            accStats(sp.stats, ps)
            if sp.role == nil and c.role then sp.role = c.role end
            if r.status ~= STATUS.ABANDONED and type(r.level) == "number" then
                sp.levelSum = sp.levelSum + r.level; sp.levelN = sp.levelN + 1
                if r.status == STATUS.TIMED and (not sp.highestTimed or r.level > sp.highestTimed) then sp.highestTimed = r.level end
            end
            if type(myDeaths) == "number" then sp.deathsSum = sp.deathsSum + myDeaths; sp.deathsN = sp.deathsN + 1 end

            -- Per dungeon.
            if r.mapId then
                local dd = duns[r.mapId]
                if not dd then
                    dd = { mapId = r.mapId, name = r.dungeonName, totals = emptyTotals(), highestTimed = nil,
                           bestTime = nil, timeSum = 0, timeN = 0, deathsSum = 0, deathsN = 0 }
                    duns[r.mapId] = dd; dunOrder[#dunOrder + 1] = dd
                end
                bumpTotals(dd.totals, r.status)
                if r.status == STATUS.TIMED and type(r.level) == "number" and (not dd.highestTimed or r.level > dd.highestTimed) then dd.highestTimed = r.level end
                if r.status == STATUS.TIMED and type(r.duration) == "number" then
                    if not dd.bestTime or r.duration < dd.bestTime then dd.bestTime = r.duration end
                    dd.timeSum = dd.timeSum + r.duration; dd.timeN = dd.timeN + 1
                end
                if type(myDeaths) == "number" then dd.deathsSum = dd.deathsSum + myDeaths; dd.deathsN = dd.deathsN + 1 end
            end
        end
    end
    o.timedPct = timedPct(o.totals)
    o.avgLevel = Util.safeDiv(o.levelSum, o.levelN)
    o.avgDuration = Util.safeDiv(o.durSum, o.durN)
    o.avgDeaths = Util.safeDiv(o.deathsSum, o.deathsN)
    for _, sp in ipairs(specOrder) do
        sp.avgLevel = Util.safeDiv(sp.levelSum, sp.levelN)
        sp.timedPct = timedPct(sp.totals)
        sp.avgDeaths = Util.safeDiv(sp.deathsSum, sp.deathsN)
        sp.avgDps = avgOf(sp.stats, "dps")
        sp.avgHps = avgOf(sp.stats, "hps")
        sp.avgInterrupts = avgOf(sp.stats, "interrupts")
    end
    table.sort(specOrder, function(a, b) return (a.totals.runs or 0) > (b.totals.runs or 0) end)
    for _, dd in ipairs(dunOrder) do
        dd.timedPct = timedPct(dd.totals)
        dd.avgTime = Util.safeDiv(dd.timeSum, dd.timeN)
        dd.avgDeaths = Util.safeDiv(dd.deathsSum, dd.deathsN)
    end
    table.sort(dunOrder, function(a, b) return (a.totals.runs or 0) > (b.totals.runs or 0) end)
    o.specs, o.dungeons = specOrder, dunOrder
    return o
end

function History.CharacterList()
    local list = {}
    for _, c in pairs(DB.Characters()) do list[#list + 1] = c end
    table.sort(list, function(a, b) return (a.totals.runs or 0) > (b.totals.runs or 0) end)
    return list
end

function History.PlayerList()
    local list = {}
    for _, p in pairs(DB.PlayerIndex()) do list[#list + 1] = p end
    table.sort(list, function(a, b) return (a.totals.runs or 0) > (b.totals.runs or 0) end)
    return list
end

function History.PlayerSummary(identityKey) return DB.PlayerIndex()[identityKey] end

-- Reverse lookup: a "Name-Realm" -> the identityKey (guid) of a player you've run with, or nil. For
-- surfaces that only give a name (LFG / who / guild / friends / chat) rather than a unit GUID. Cached and
-- rebuilt only when the number of known players changes (a name is stable once recorded).
--
-- Matching is realm-normalization-insensitive. We store fullName from UnitName, whose realm keeps its
-- display punctuation (spaces + apostrophes, e.g. "Twisting Nether", "Zul'jin"), but callers like LFG hand
-- back the *normalized* realm that strips both ("TwistingNether", "Zuljin"). So we index and query on a
-- canonical key: drop whitespace and apostrophes, lower-case. (Character names carry no such punctuation,
-- so the "-" separator is safe to keep.)
local nameToKey, nameToKeyN
local function nameKey(full) return (full:gsub("[%s']", "")):lower() end
function History.PlayerByName(fullName)
    if type(fullName) ~= "string" or fullName == "" then return nil end
    local idx = DB.PlayerIndex()
    local n = 0; for _ in pairs(idx) do n = n + 1 end
    if nameToKeyN ~= n or not nameToKey then
        nameToKey = {}
        for key, rec in pairs(idx) do if rec.fullName then nameToKey[nameKey(rec.fullName)] = key end end
        nameToKeyN = n
    end
    return nameToKey[nameKey(fullName)]
end

-- Average Mythic Ledger performance score for a player across your shared runs -> avgOverall, letterGrade
-- (or nil if the scorer isn't available / no scored runs). Uses the persisted per-run score summaries.
function History.AvgScore(identityKey)
    local Store = ML.Scoring and ML.Scoring.Store
    local Score = ML.Scoring and ML.Scoring.Score
    if not (identityKey and Store and Store.Summary) then return nil end
    local sum, n = 0, 0
    for _, r in ipairs(History.FilterRuns({ playerKey = identityKey })) do
        local sc = Store.Summary(r)[identityKey]
        if sc and type(sc.overall) == "number" then sum = sum + sc.overall; n = n + 1 end
    end
    if n == 0 then return nil end
    local avg = sum / n
    return avg, (Score and Score.Grade and Score.Grade(avg)) or nil
end

-- Weekly trend for the current scope: rolling 7-day buckets (by completedAt), newest bucket = the current
-- (possibly partial) week. Per week: run count, avg key level, timed %, YOUR avg Ledger score, and YOUR avg
-- deaths. Returns up to `maxWeeks` buckets OLDEST-FIRST, each { weeksAgo, runs, avgLevel, timedPct, avgScore,
-- avgDeaths } (a metric is nil for a week with no qualifying runs). Read-only - reuses the persisted per-run
-- score summaries (no rescore here).
function History.WeeklyTrend(seasonId, character, maxWeeks)
    maxWeeks = math.max(2, maxWeeks or 4)
    local Store = ML.Scoring and ML.Scoring.Store
    local now, WEEK = time(), 7 * 86400
    local buckets = {}
    for _, r in ipairs(History.FilterRuns({ seasonId = seasonId, character = character })) do
        local t = r.completedAt or r.startedAt or 0
        local wi = (t > 0) and math.floor((now - t) / WEEK) or nil
        if wi and wi >= 0 and wi < maxWeeks then
            local b = buckets[wi]
            if not b then
                b = { runs = 0, levelSum = 0, levelN = 0, timed = 0, completed = 0,
                      scoreSum = 0, scoreN = 0, deathsSum = 0, deathsN = 0 }
                buckets[wi] = b
            end
            b.runs = b.runs + 1
            if r.status ~= STATUS.ABANDONED then
                b.completed = b.completed + 1
                if r.status == STATUS.TIMED then b.timed = b.timed + 1 end
                if type(r.level) == "number" then b.levelSum = b.levelSum + r.level; b.levelN = b.levelN + 1 end
            end
            local md = playerDeaths(r)   -- YOUR deaths (clean run = 0), not the whole party's
            if type(md) == "number" then b.deathsSum = b.deathsSum + md; b.deathsN = b.deathsN + 1 end
            if Store and Store.Summary and r.character and r.character.guid then
                local sc = Store.Summary(r)[r.character.guid]
                if sc and type(sc.overall) == "number" then b.scoreSum = b.scoreSum + sc.overall; b.scoreN = b.scoreN + 1 end
            end
        end
    end
    local out = {}
    for wi = maxWeeks - 1, 0, -1 do   -- oldest -> newest
        local b = buckets[wi]
        out[#out + 1] = {
            weeksAgo  = wi,
            runs      = b and b.runs or 0,
            avgLevel  = b and Util.safeDiv(b.levelSum, b.levelN) or nil,
            timedPct  = b and Util.safeDiv(b.timed, b.completed) or nil,
            avgScore  = b and Util.safeDiv(b.scoreSum, b.scoreN) or nil,
            avgDeaths = b and Util.safeDiv(b.deathsSum, b.deathsN) or nil,
        }
    end
    return out
end

-- Seconds until the next Mythic+ weekly reset (nil if the API is unavailable).
function History.SecondsUntilReset()
    local f = _G.C_DateAndTime and _G.C_DateAndTime.GetSecondsUntilWeeklyReset
    if not f then return nil end
    local ok, s = pcall(f)
    if ok and type(s) == "number" and s > 0 then return s end
    return nil
end

-- Start (epoch seconds) of the CURRENT reset week: derived from the reset countdown when available, else a
-- rolling 7-day window.
function History.WeekStart()
    local s = History.SecondsUntilReset()
    if s then return time() + s - 7 * 86400 end
    return time() - 7 * 86400
end

-- Per-character Great Vault progress THIS reset week. The vault's three Mythic+ slots come from your 1st,
-- 4th, and 8th highest COMPLETED keys (timed OR depleted both count), so per character we collect this
-- week's completed key levels, sort them high-first, and keep the top 8. "All 10s" = the 8th is +10.
-- Returns one entry per known character: { fullName, name, classFile, keys (top 8, desc), count, slot1,
-- slot4, slot8 }. Read-only.
function History.WeeklyVault()
    local weekStart = History.WeekStart()
    local out = {}
    for _, c in ipairs(History.CharacterList()) do
        local keys = {}
        for _, r in ipairs(History.FilterRuns({ character = c.fullName, from = weekStart })) do
            if r.status ~= STATUS.ABANDONED and type(r.level) == "number" then
                keys[#keys + 1] = r.level
            end
        end
        table.sort(keys, function(a, b) return a > b end)
        local top = {}
        for i = 1, math.min(8, #keys) do top[i] = keys[i] end
        out[#out + 1] = {
            fullName = c.fullName, name = c.name, classFile = c.classFile,
            keys = top, count = #keys, slot1 = top[1], slot4 = top[4], slot8 = top[8],
        }
    end
    return out
end

-- Runs shared with a specific party member (most recent first).
function History.PlayerRuns(identityKey)
    return History.FilterRuns({ playerKey = identityKey })
end

----------------------------------------------------------------------
-- Recap statistics: computed live from the runs so season scoping is exact. Averages are limited
-- to the member's most-recent role, so we never blend cross-role numbers.
----------------------------------------------------------------------
function History.RecapStats(identityKey, seasonId)
    local runs = History.FilterRuns({ playerKey = identityKey, seasonId = seasonId })
    if #runs == 0 then return nil end
    local s = { runs = 0, timed = 0, highestTimed = nil, lastRole = nil, lastSpecId = nil,
                lastClassFile = nil, lastItemLevel = nil, lastRun = nil, roleBucket = {}, minLevel = nil, maxLevel = nil }
    -- runs are newest-first; the first is the "last seen".
    for i, r in ipairs(runs) do
        local m
        for _, pm in ipairs(r.party or {}) do
            if not pm.isPlayer and API.IdentityKey(pm) == identityKey then m = pm; break end
        end
        if m then
            s.runs = s.runs + 1
            if r.status == STATUS.TIMED then
                s.timed = s.timed + 1
                if type(r.level) == "number" and (not s.highestTimed or r.level > s.highestTimed) then s.highestTimed = r.level end
            end
            if type(r.level) == "number" then
                s.minLevel = s.minLevel and math.min(s.minLevel, r.level) or r.level
                s.maxLevel = s.maxLevel and math.max(s.maxLevel, r.level) or r.level
            end
            if i == 1 then
                s.lastRole = m.role
                s.lastSpecId = m.specId
                s.lastClassFile = m.classFile
                s.lastRun = { status = r.status, level = r.level, dungeon = r.dungeonName, at = r.completedAt or r.startedAt }
            end
            -- Most-recent KNOWN item level (runs are newest-first; inspect can miss on any single run).
            if not s.lastItemLevel and m.itemLevel then s.lastItemLevel = m.itemLevel end
            -- Accumulate stats bucketed by the role played in THAT run.
            local role = m.role or "UNKNOWN"
            s.roleBucket[role] = s.roleBucket[role] or {}
            accStats(s.roleBucket[role], m.stats)
        end
    end
    s.timedPct = Util.safeDiv(s.timed, s.runs)
    -- Averages for the member's last-known role only (role-appropriate).
    local bucket = s.roleBucket[s.lastRole or "UNKNOWN"]
    s.avg = {
        dps        = avgOf(bucket, "dps"),
        hps        = avgOf(bucket, "hps"),
        damage     = avgOf(bucket, "damage"),
        healing    = avgOf(bucket, "healing"),
        deaths     = avgOf(bucket, "deaths"),
        interrupts = avgOf(bucket, "interrupts"),
        dispels    = avgOf(bucket, "dispels"),
    }
    s.mixedLevels = (s.minLevel and s.maxLevel and (s.maxLevel - s.minLevel) >= 3) or false
    return s
end
