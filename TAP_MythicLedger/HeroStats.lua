-- TAP: Mythic Ledger - HeroStats.lua
-- The single source of truth for the Overview "hero" summary tiles: which icon each metric
-- uses, and the WoW-quality color scale that maps a value to a color + a plain-language
-- rating. UI.lua reads ML.HERO_STATS / ML.HeroStatStyle only - no thresholds live in the UI.
--
-- Colors are WoW item-quality inspired so the scale reads intuitively to players (green good,
-- blue better, purple great, orange exceptional, gold elite, red concerning). Every value maps
-- to a rating word too, so the cards never rely on color alone (accessibility).

local ADDON, ML = ...
local Util = ML.Util

----------------------------------------------------------------------
-- Palette (WoW item-quality inspired). Hex strings; the UI kit's color
-- helpers accept "RRGGBB" anywhere a color is expected.
----------------------------------------------------------------------
-- Canonical metric color scale: F (worst) -> D -> C -> B -> A -> S (best), plus N (neutral/unrated).
-- ASIDE FROM M+ SCORE (which keeps Blizzard's own rarity color), EVERY metric/grade color in the
-- module resolves through here. Two variants keep both themes legible - bright green/orange and mid-grey
-- wash out on the wrong background - picked per render by TierColor() from the live theme's bg luminance.
local TIER_DARK = {   -- the requested scale, as-is (designed for a dark bg)
    F = "666666",  -- grey
    D = "1eff00",  -- green
    C = "0070ff",  -- blue
    B = "a335ee",  -- purple
    A = "ff8000",  -- orange
    S = "e268a8",  -- pink
    N = "8a8f99",  -- neutral / unrated (a touch lighter than F so avg-time stays legible)
}
local TIER_LIGHT = {  -- same hues, darkened where the dark values wash out on a light bg
    F = "555a63",  -- grey
    D = "12930b",  -- darker green (bright green is unreadable on light)
    C = "0a5fd0",  -- blue
    B = "8626c9",  -- purple
    A = "cf6800",  -- orange
    S = "c0417f",  -- pink
    N = "555a63",  -- neutral / unrated
}

-- Light mode when the theme's background is bright (daylight / parchment palettes).
local function isLightTheme()
    local theme = _G.TAP and _G.TAP.uiTheme
    local bg = theme and theme.C and theme.C.bg
    if type(bg) ~= "table" then return false end
    return (0.299 * (bg[1] or 0) + 0.587 * (bg[2] or 0) + 0.114 * (bg[3] or 0)) > 0.55
end
ML.IsLightTheme = isLightTheme

-- tier: "F"/"D"/"C"/"B"/"A"/"S"/"N". Returns a "RRGGBB" hex for the CURRENT theme (light or dark).
-- forceDark = always use the bright dark-theme variant (for text over the forced-dark dungeon-art cards).
function ML.TierColor(tier, forceDark)
    local t = (not forceDark and isLightTheme()) and TIER_LIGHT or TIER_DARK
    return t[tier] or t.F
end

-- Quality name -> tier letter. The stat scales below still read Q.<name>; these values remap every
-- scale onto the F..S ramp at once (each resolved to a theme hex by TierColor at eval time).
local Q = {
    poor = "F", common = "F", uncommon = "D", rare = "C", epic = "B",
    legendary = "A", artifact = "S", danger = "F", neutral = "N",
}
ML.QUALITY_COLORS = Q

-- Rating words (do not rely on color alone - shown in the tooltip / accessible label).
local R = {
    poor        = "Poor",
    neutral     = "Neutral",
    good        = "Good",
    veryGood    = "Very Good",
    excellent   = "Excellent",
    exceptional = "Exceptional",
    elite       = "Elite",
    concerning  = "Concerning",
    none        = "No data",
}

----------------------------------------------------------------------
-- Tier evaluators. Each stat's scale is ONE ordered list of tiers; the
-- color, the rating, and the tooltip scale text all derive from it, so a
-- threshold is written exactly once.
--   desc: first tier where value >= tier.min   (higher is better)
--   asc:  first tier where value <  tier.max    (lower is better)
----------------------------------------------------------------------
local function evalDesc(tiers, value)
    for _, t in ipairs(tiers) do
        if value >= t.min then return t end
    end
    return tiers[#tiers]
end

local function evalAsc(tiers, value)
    for _, t in ipairs(tiers) do
        if value < t.max then return t end
    end
    return tiers[#tiers]
end

-- Timed % may arrive as a fraction (0.64) or a percentage (64). Normalise to 0-100.
local function asPercent(v)
    if type(v) ~= "number" then return v end
    if v <= 1 then return v * 100 end
    return v
end

----------------------------------------------------------------------
-- Hero-stat configuration. `icon` is a bundled Tabler icon name (white TGA,
-- tintable). `eval(value)` returns color(hex), rating, and its matched tier.
-- `scale` is the ordered tier list used for the tooltip. `note` is extra
-- guidance (e.g. "lower is better"). `neutralValue` (avg time) is unrated.
----------------------------------------------------------------------
local HERO_STATS = {}

local function descStat(cfg)
    cfg.eval = function(value)
        if type(value) ~= "number" then return ML.TierColor(Q.poor), R.none, nil end
        local t = evalDesc(cfg.scale, value)
        return ML.TierColor(t.color), t.rating, t
    end
    return cfg
end

local function ascStat(cfg)
    cfg.eval = function(value)
        if type(value) ~= "number" then return ML.TierColor(Q.poor), R.none, nil end
        local t = evalAsc(cfg.scale, value)
        return ML.TierColor(t.color), t.rating, t
    end
    return cfg
end

HERO_STATS.runs = descStat({
    key = "runs", label = "Runs", icon = "route",
    desc = "Total Mythic+ runs recorded in scope.",
    scale = {
        { min = 250, color = Q.legendary, rating = R.exceptional, text = "250+" },
        { min = 100, color = Q.epic,      rating = R.excellent,   text = "100-249" },
        { min = 50,  color = Q.rare,      rating = R.veryGood,    text = "50-99" },
        { min = 25,  color = Q.uncommon,  rating = R.good,        text = "25-49" },
        { min = 10,  color = Q.common,    rating = R.neutral,     text = "10-24" },
        { min = 0,   color = Q.poor,      rating = R.poor,        text = "0-9" },
    },
})

-- Timed uses the activity scale but is deliberately capped at Epic purple so a big
-- lifetime total doesn't paint another orange card next to Runs (kept intentional and
-- documented; see the design brief). The tooltip shows the same capped scale.
HERO_STATS.timed = descStat({
    key = "timed", label = "Timed", icon = "circle-check",
    desc = "Runs completed within the timer.",
    scale = {
        { min = 100, color = Q.epic,     rating = R.excellent, text = "100+" },
        { min = 50,  color = Q.rare,     rating = R.veryGood,  text = "50-99" },
        { min = 25,  color = Q.uncommon, rating = R.good,      text = "25-49" },
        { min = 10,  color = Q.common,   rating = R.neutral,   text = "10-24" },
        { min = 0,   color = Q.poor,     rating = R.poor,      text = "0-9" },
    },
})

HERO_STATS.timedPercent = descStat({
    key = "timedPercent", label = "Timed %", icon = "target",
    desc = "Share of completed runs that beat the timer.",
    normalize = asPercent,
    scale = {
        { min = 98, color = Q.artifact,  rating = R.elite,       text = "98%+" },
        { min = 90, color = Q.legendary, rating = R.exceptional, text = "90-97%" },
        { min = 80, color = Q.epic,      rating = R.excellent,   text = "80-89%" },
        { min = 70, color = Q.rare,      rating = R.veryGood,    text = "70-79%" },
        { min = 60, color = Q.uncommon,  rating = R.good,        text = "60-69%" },
        { min = 0,  color = Q.danger,    rating = R.concerning,  text = "Under 60%" },
    },
})

HERO_STATS.highestTimed = descStat({
    key = "highestTimed", label = "Highest Timed", icon = "trophy",
    desc = "Highest key level completed within the timer.",
    scale = {
        { min = 17, color = Q.artifact,  rating = R.elite,       text = "+17 or higher" },
        { min = 14, color = Q.legendary, rating = R.exceptional, text = "+14 to +16" },
        { min = 11, color = Q.epic,      rating = R.excellent,   text = "+11 to +13" },
        { min = 8,  color = Q.rare,      rating = R.veryGood,    text = "+8 to +10" },
        { min = 5,  color = Q.uncommon,  rating = R.good,        text = "+5 to +7" },
        { min = 0,  color = Q.common,    rating = R.neutral,     text = "+2 to +4" },
    },
})

HERO_STATS.averageKey = descStat({
    key = "averageKey", label = "Avg Key", icon = "key",
    desc = "Average difficulty of completed runs.",
    scale = {
        { min = 14, color = Q.artifact,  rating = R.elite,       text = "+14 or higher" },
        { min = 12, color = Q.legendary, rating = R.exceptional, text = "+12 to +13.9" },
        { min = 10, color = Q.epic,      rating = R.excellent,   text = "+10 to +11.9" },
        { min = 7,  color = Q.rare,      rating = R.veryGood,    text = "+7 to +9.9" },
        { min = 4,  color = Q.uncommon,  rating = R.good,        text = "+4 to +6.9" },
        { min = 0,  color = Q.poor,      rating = R.poor,        text = "Below +4" },
    },
})

-- Raw average duration can't say "good" or "bad" (dungeon timers differ), so it stays
-- neutral until per-dungeon timer normalisation exists. See getNormalizedTimeColor below.
HERO_STATS.averageTime = {
    key = "averageTime", label = "Avg Time", icon = "clock",
    desc = "Average dungeon duration.",
    note = "Not rated - dungeon timers differ, so raw time isn't good or bad on its own.",
    neutralValue = true,
    eval = function(value)
        return ML.TierColor(Q.neutral), R.neutral, nil
    end,
}

-- YOUR OWN deaths per run (not whole-party). A great player almost never dies: under 0.1/run is
-- elite, averaging a death every key (~1.0) is already below par, and 1.5+ is a real problem.
HERO_STATS.averageDeaths = ascStat({
    key = "averageDeaths", label = "Avg Deaths", icon = "skull",
    desc = "Your average deaths per run.",
    note = "Lower is better - this counts only your own deaths.",
    scale = {
        { max = 0.1,       color = Q.artifact,  rating = R.elite,       text = "Under 0.10" },
        { max = 0.35,      color = Q.legendary, rating = R.exceptional, text = "0.10 - 0.34" },
        { max = 0.7,       color = Q.epic,      rating = R.excellent,   text = "0.35 - 0.69" },
        { max = 1.0,       color = Q.uncommon,  rating = R.good,        text = "0.70 - 0.99" },
        { max = 1.5,       color = Q.poor,      rating = R.poor,        text = "1.00 - 1.49" },
        { max = math.huge, color = Q.danger,    rating = R.concerning,  text = "1.50 or more" },
    },
})

HERO_STATS.returning = descStat({
    key = "returning", label = "Regulars", icon = "users",
    desc = "Party members you've grouped with more than once.",
    scale = {
        { min = 40, color = Q.legendary, rating = R.exceptional, text = "40+" },
        { min = 20, color = Q.epic,      rating = R.excellent,   text = "20-39" },
        { min = 10, color = Q.rare,      rating = R.veryGood,    text = "10-19" },
        { min = 5,  color = Q.uncommon,  rating = R.good,        text = "5-9" },
        { min = 1,  color = Q.common,    rating = R.neutral,     text = "1-4" },
        { min = 0,  color = Q.poor,      rating = R.poor,        text = "0" },
    },
})

HERO_STATS.playersMet = descStat({
    key = "playersMet", label = "Players Met", icon = "user-plus",
    desc = "Distinct party members you've grouped with in scope.",
    scale = {
        { min = 200, color = Q.legendary, rating = R.exceptional, text = "200+" },
        { min = 100, color = Q.epic,      rating = R.excellent,   text = "100-199" },
        { min = 50,  color = Q.rare,      rating = R.veryGood,    text = "50-99" },
        { min = 20,  color = Q.uncommon,  rating = R.good,        text = "20-49" },
        { min = 1,   color = Q.common,    rating = R.neutral,     text = "1-19" },
        { min = 0,   color = Q.poor,      rating = R.poor,        text = "0" },
    },
})

ML.HERO_STATS = HERO_STATS

----------------------------------------------------------------------
-- Supporting subtext for each Overview card: the "smart" comparison line(s) under the value
-- (e.g. "Best: Siegehold +15", "Range: +5 to +15", "Last 10: 0.6"). Kept here beside the scales
-- so all Overview-card content decisions live in one file. `o` is History.Overview(); scopeLabel
-- is a human season label ("This season" / "All seasons"). Returns:
--   { sub = "one supporting line", footer = { "line", "line" } }
-- `sub` feeds the Clean / Panel styles (one line); `footer` feeds the data-rich Compact style.
----------------------------------------------------------------------
local function pct(n) return math.floor((n or 0) * 100 + 0.5) end

function ML.HeroStatSubtext(key, o, scopeLabel)
    o = o or {}
    local last10 = o.last10 or {}
    if key == "runs" then
        local wk = string.format("This week: %d run%s", o.thisWeekRuns or 0, (o.thisWeekRuns == 1) and "" or "s")
        return { sub = scopeLabel, footer = { scopeLabel, wk } }

    elseif key == "timed" then
        local p = Util.safeDiv(o.timed, o.runs)
        local line = p and (pct(p) .. "% of all runs") or "No runs yet"
        return { sub = line, footer = { line, string.format("Depleted: %d", o.depleted or 0) } }

    elseif key == "timedPercent" then
        local line = (last10.timedPct and last10.n > 0)
            and string.format("Last %d: %d%%", last10.n, pct(last10.timedPct)) or "Not enough runs"
        return { sub = line, footer = { line } }

    elseif key == "highestTimed" then
        local line = o.highestTimed
            and ("Best: " .. (o.highestTimedDungeon and (o.highestTimedDungeon .. " ") or "") .. "+" .. o.highestTimed)
            or "None timed yet"
        return { sub = line, footer = { line } }

    elseif key == "averageKey" then
        local line = (o.keyMin and o.keyMax) and string.format("Range: +%d to +%d", o.keyMin, o.keyMax) or "No runs yet"
        return { sub = line, footer = { line } }

    elseif key == "averageTime" then
        local best = o.bestTime and ("Best: " .. Util.duration(o.bestTime)) or "No timed runs"
        return { sub = best, footer = { best, o.bestTimeDungeon or "" } }

    elseif key == "averageDeaths" then
        local line = (last10.avgDeaths and last10.n > 0)
            and string.format("Last %d: %.2f", last10.n, last10.avgDeaths) or "No data"
        return { sub = line, footer = { line } }

    elseif key == "returning" then
        return { sub = "Grouped with 2+ times", footer = { "Grouped with 2+ times" } }

    elseif key == "playersMet" then
        return { sub = "Unique teammates", footer = { "Unique teammates" } }
    end
    return { sub = nil, footer = {} }
end

----------------------------------------------------------------------
-- Future work: normalised time color. Only usable once per-run dungeon
-- timers are recorded and we can compute (elapsed / dungeon timer). Kept
-- here so the threshold policy lives with the rest of the scale.
----------------------------------------------------------------------
function ML.getNormalizedTimeColor(timerUsagePercent)
    if type(timerUsagePercent) ~= "number" then return ML.TierColor("N"), R.neutral end
    if timerUsagePercent < 70  then return ML.TierColor("A"), R.exceptional end
    if timerUsagePercent < 80  then return ML.TierColor("B"), R.excellent end
    if timerUsagePercent < 90  then return ML.TierColor("C"), R.veryGood end
    if timerUsagePercent <= 100 then return ML.TierColor("D"), R.good end
    if timerUsagePercent <= 110 then return ML.TierColor("F"), R.neutral end
    return ML.TierColor("F"), R.concerning
end

----------------------------------------------------------------------
-- Resolve a hero stat + value to everything the UI needs to draw one tile:
--   color (hex) · rating (word) · icon · label · tipData (rich, color-coded)
-- `formatted` is the already-formatted display string (kept in the UI so the
-- existing data source / formatting is untouched).
----------------------------------------------------------------------
-- Dim a "RRGGBB" hex toward the card grey so inactive scale rows recede and the
-- active band pops. t = 0 keeps the color, 1 = full grey. Returns an { r, g, b } table.
local function dimHex(hex, t)
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then return hex end
    r, g, b = r / 255, g / 255, b / 255
    local gr = 0.42
    return { r + (gr - r) * t, g + (gr - g) * t, b + (gr - b) * t }
end

function ML.HeroStatStyle(key, value, formatted)
    local cfg = HERO_STATS[key]
    if not cfg then
        return { color = Q.neutral, rating = R.neutral, icon = nil, label = key or "?" }
    end
    local v = value
    if cfg.normalize and type(v) == "number" then v = cfg.normalize(v) end
    local color, rating, active = cfg.eval(v)

    -- Rich, color-coded tooltip: description, this value's rating in its color, then the
    -- full scale where every band is drawn in ITS quality color (active band marked + bright,
    -- others dimmed). Color never carries meaning alone - the rating word is always shown.
    local lines = { { text = cfg.desc, color = "subtext" } }
    if formatted ~= nil then
        lines[#lines + 1] = { blank = true }
        lines[#lines + 1] = { left = "Value", right = tostring(formatted) .. "   " .. rating,
            lcolor = "subtext", rcolor = color }
    end
    if cfg.scale then
        lines[#lines + 1] = { sep = true }
        for _, t in ipairs(cfg.scale) do
            local on = (t == active)
            local hex = ML.TierColor(t.color)                 -- t.color is a tier letter -> theme hex
            local col = on and hex or dimHex(hex, 0.55)
            lines[#lines + 1] = {
                left = (on and "> " or "     ") .. t.text,
                right = t.rating, lcolor = col, rcolor = col,
            }
        end
    end
    if cfg.note then
        lines[#lines + 1] = { blank = true }
        lines[#lines + 1] = { text = cfg.note, color = (key == "averageDeaths") and "e6cc80" or "subtext" }
    end

    -- Meter fill: where this value's band sits on its scale (0 = worst band, 1 = best band).
    -- Tier 1 in every scale is the BEST band (highest min / lowest deaths), so index 1 -> 1.0.
    -- nil for unscaled/neutral metrics (Avg Time) and for no-data.
    local fraction
    if cfg.scale and active then
        local idx, n = 1, #cfg.scale
        for i, t in ipairs(cfg.scale) do if t == active then idx = i break end end
        fraction = (n > 1) and (n - idx) / (n - 1) or 1
        if fraction < 0.08 then fraction = 0.08 end   -- keep a sliver visible even at the worst band
    end

    return {
        color  = color,
        rating = rating,
        icon   = cfg.icon,
        label  = cfg.label,
        fraction = fraction,
        tipData = { icon = nil, title = cfg.label, lines = lines },
    }
end
