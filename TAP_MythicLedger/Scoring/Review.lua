-- TAP: Mythic Ledger - Scoring/Review.lua
-- Turns a scored player into a plain-language coaching review: a headline, the things they did well,
-- and the highest-leverage things to work on. DETERMINISTIC - a small state classifier over the SAME
-- category results the grade is built from (no new data, no self-learning), so the review can never
-- disagree with the score. Every line is derived from a category's score + its recorded detail.
--
-- Shape returned by Review.Build(score):
--   {
--     grade, overall, band,                       -- overall state (EXCELLENT..WEAK)
--     headline = "one-line summary",
--     strengths    = { { key, label, score, band, note }, ... },        -- score desc
--     improvements = { { key, label, score, band, note, impact }, ... },-- highest leverage first
--     verdicts     = { key = { label, score, band, weight, na, reason, praise, tip }, ... },
--   }

local ADDON, ML = ...
local Scoring = ML.Scoring
local Review = {}
Scoring.Review = Review

local Cfg = Scoring.Config

local function round(v) return math.floor((v or 0) + 0.5) end

local LABELS = {
    throughput = "Throughput", interrupts = "Interrupts", dispels = "Dispels",
    survival = "Survival", deaths = "Deaths",
}

----------------------------------------------------------------------
-- The state machine: a 0..100 category (or overall) score -> named band.
----------------------------------------------------------------------
function Review.Band(score)
    local r = Cfg.review
    score = score or 0
    if score >= r.excellentMin then return "EXCELLENT" end
    if score >= r.strongMin    then return "STRONG"    end
    if score >= r.solidMin     then return "SOLID"     end
    if score >= r.softMin      then return "SOFT"      end
    return "WEAK"
end

----------------------------------------------------------------------
-- Per-category note builders. Each returns praise, tip (either may be nil). praise is shown when the
-- category is a strength; tip is shown when it's an improvement. Both read only recorded detail.
----------------------------------------------------------------------
-- Pronouns: coaching for the local player reads "you/your"; for a teammate it reads "they/their".
local function pronouns(isSelf)
    if isSelf then return { poss = "your", subj = "you" } end
    return { poss = "their", subj = "they" }
end

local function throughputNotes(t, pr)
    local d = t.detail or {}
    -- Coach on the dominant component (healers/tanks lean HPS, damagers DPS).
    local isHeal = d.hps ~= nil and (d.dps == nil or (d.hps.weight or 0) >= (d.dps.weight or 0))
    local c = isHeal and d.hps or d.dps
    if not c then return nil, nil end
    local r = c.ratio or 0
    local what = isHeal and "Healing" or "Damage"
    if r >= 1.0 then
        return string.format("%s met or beat %s expected group share (%.2fx).", what, pr.poss, r), nil
    end
    return nil, string.format("%s was %d%% under %s expected group share - chase uptime and rotation gains.",
        what, round((1 - r) * 100), pr.poss)
end

local function contribNotes(c, singular, plural, pr)
    if not c or c.applicable == false or c.actual == nil then return nil, nil end
    local a, e = c.actual, c.expected or 0
    if a >= e then
        return string.format("%d %s vs ~%.1f expected - strong coverage.", a, a == 1 and singular or plural, e), nil
    end
    return nil, string.format("%d of ~%.1f expected %s - watch %s assignments for more chances.", a, e, plural, pr.poss)
end

local function survivalNotes(s, pr)
    local share = s.detail and s.detail.avoidableShare
    if share == nil then return nil, nil end
    local grace = Cfg.survival.graceShare or 0.025
    local zero  = Cfg.survival.zeroShare  or 0.40
    if share <= grace then
        return string.format("Clean - only %.1f%% of %s damage taken was avoidable.", share * 100, pr.poss), nil
    end
    return nil, string.format("%.1f%% of %s damage taken was avoidable (%.0f%%+ zeroes this) - leave ground effects sooner.",
        share * 100, pr.poss, zero * 100)
end

local function deathNotes(de, pr)
    if de.deaths == nil then return nil, nil end
    if de.deaths == 0 then
        return string.format("No deaths - %s stayed up the whole key.", pr.subj), nil
    end
    return nil, string.format("%d death%s cost -%d. Dying is the single most costly thing %s can do - prioritize staying alive.",
        de.deaths, de.deaths == 1 and "" or "s", de.penalty or 0, pr.subj)
end

-- Build praise/tip for every category up front (keyed by category name) - used by the `verdicts` map.
local function allNotes(cats, pr)
    local n = {}
    n.throughput = { throughputNotes(cats.throughput or {}, pr) }
    n.survival   = { survivalNotes(cats.survival or {}, pr) }
    n.deaths     = { deathNotes(cats.deaths or {}, pr) }
    n.interrupts = { contribNotes(cats.interrupts, "interrupt", "interrupts", pr) }
    n.dispels    = { contribNotes(cats.dispels, "dispel", "dispels", pr) }
    return n
end

-- Expand the categories into individually coachable ITEMS. Multi-stat throughput is SPLIT into its
-- DPS and HPS components so a role with two targets (tank/healer) is judged - and coached - on each
-- separately: you can hit your damage share but miss healing, and the review says exactly that and
-- suggests more of whichever fell short. Every other category is a single item.
local function coachItems(cats, pr)
    local items = {}
    local t = cats.throughput
    if t and t.applicable ~= false then
        local det = t.detail or {}
        local comps = {}
        if det.dps then comps[#comps + 1] = { what = "Damage",  c = det.dps } end
        if det.hps then comps[#comps + 1] = { what = "Healing", c = det.hps } end
        if #comps > 0 then
            local split = #comps > 1
            for _, cc in ipairs(comps) do
                local c = cc.c
                local ratio = c.ratio or 0
                local score = math.min(c.score or t.score or 0, 100)
                local praise, tip
                if ratio >= 1.0 then
                    praise = string.format("%s met or beat %s expected group share (%.2fx).", cc.what, pr.poss, ratio)
                else
                    local verb = (cc.what == "Healing") and "put out more healing" or "chase uptime and rotation gains"
                    tip = string.format("%s was %d%% under %s expected group share - %s.",
                        cc.what, round((1 - ratio) * 100), pr.poss, verb)
                end
                items[#items + 1] = { key = "throughput",
                    label = split and ("Throughput (" .. cc.what .. ")") or "Throughput",
                    score = score, weight = (t.weight or 0) * (c.weight or 1), praise = praise, tip = tip }
            end
        else   -- estimate / no component detail: one item at the category score, no actionable note
            items[#items + 1] = { key = "throughput", label = "Throughput",
                score = math.min(t.score or 0, 100), weight = t.weight or 0 }
        end
    end
    local function simple(key, label, catRes, p, tp)
        if catRes and catRes.applicable ~= false then
            items[#items + 1] = { key = key, label = label, score = math.min(catRes.score or 0, 100),
                weight = catRes.weight or 0, praise = p, tip = tp }
        end
    end
    -- Note fns return (praise, tip); as the LAST call argument their two returns fill p, tp.
    simple("survival",   "Survival",   cats.survival,   survivalNotes(cats.survival or {}, pr))
    simple("deaths",     "Deaths",     cats.deaths,     deathNotes(cats.deaths or {}, pr))
    simple("interrupts", "Interrupts", cats.interrupts, contribNotes(cats.interrupts, "interrupt", "interrupts", pr))
    simple("dispels",    "Dispels",    cats.dispels,    contribNotes(cats.dispels, "dispel", "dispels", pr))
    return items
end

----------------------------------------------------------------------
-- Headline keyed off the overall grade (with light awareness of how much is left to fix).
----------------------------------------------------------------------
local GRADE_TIER = {
    S = 1, ["A+"] = 1, A = 1, ["A-"] = 2, ["B+"] = 2,
    B = 3, ["B-"] = 3, ["C+"] = 4, C = 4, D = 5, F = 5,
}
function Review.Headline(grade, nImprove)
    local tier = GRADE_TIER[grade] or 3
    if tier == 1 then
        return (nImprove == 0) and "Near-flawless key - nothing meaningful to fix."
            or "Excellent key - a couple of small things to sharpen."
    elseif tier == 2 then
        return "Strong performance with a clear area or two to tighten up."
    elseif tier == 3 then
        return "Solid run - real wins here, and a few concrete gains to chase."
    elseif tier == 4 then
        return "Rough key - several areas below the bar to shore up."
    end
    return "Tough run - focus on the fundamentals flagged below."
end

----------------------------------------------------------------------
-- Public: build the full review for a scored player.
----------------------------------------------------------------------
function Review.Build(score, isSelf)
    if not score or not score.categories then return nil end
    local cats = score.categories
    local rc = Cfg.review
    local pr = pronouns(isSelf)
    local notes = allNotes(cats, pr)

    local verdicts, strengths, improvements = {}, {}, {}

    -- Every category (including N/A and derived) gets a verdict entry for the full breakdown.
    for key, label in pairs(LABELS) do
        local c = cats[key]
        if c then
            if c.applicable == false then
                verdicts[key] = { label = label, na = true, reason = c.reason, weight = 0 }
            else
                local sc = math.min(c.score or 0, 100)
                local n = notes[key] or {}
                verdicts[key] = { label = label, score = round(sc), band = Review.Band(sc),
                                  weight = c.weight or 0, praise = n[1], tip = n[2] }
            end
        end
    end

    -- Strengths / improvements are drawn from the coachable ITEMS (throughput already split by stat).
    for _, it in ipairs(coachItems(cats, pr)) do
        local wgt = it.weight or 0
        if wgt > 0 and it.score >= rc.strongMin and it.praise then
            strengths[#strengths + 1] = { key = it.key, label = it.label, score = round(it.score),
                                          band = Review.Band(it.score), note = it.praise }
        end
        if wgt > 0 and it.score < rc.improveBelow and it.tip then
            improvements[#improvements + 1] = { key = it.key, label = it.label, score = round(it.score),
                                                band = Review.Band(it.score), note = it.tip, impact = wgt * (100 - it.score) }
        end
    end

    table.sort(strengths,    function(a, b) return a.score > b.score end)
    table.sort(improvements, function(a, b) return a.impact > b.impact end)

    return {
        grade = score.grade, overall = score.overall, band = Review.Band(score.overall or 0),
        headline = Review.Headline(score.grade, #improvements),
        strengths = strengths, improvements = improvements, verdicts = verdicts,
    }
end
