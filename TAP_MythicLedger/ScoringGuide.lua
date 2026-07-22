-- TAP: Mythic Ledger - ScoringGuide.lua
-- A read-only, in-game "How Scoring Works" reference page, registered as its own left-menu entry under
-- Modules (like the Dungeon Guide). EVERYTHING here is pulled LIVE from ML.Scoring.Config (weights, the
-- grade ladder, the ilvl + healer-floor knobs, snipe forgiveness, ...), so the page can never drift from
-- the real engine. Reference only - it does not affect scoring. Uses the standard PageHeading, a 2-column
-- responsive card Grid, and the same grade-color ramp (ML.TierColor) as the score cards.

local ADDON, ML = ...
local Suite = _G.TAP
local UIF   = _G.UIFoundry
if not (Suite and UIF) then return end

local Guide = {}
ML.ScoringGuide = Guide

-- Category palette (matches the review's per-metric colors). Gold is the "real-world factor" accent.
local MET = { throughput = "a06cf0", survival = "e0d070", deaths = "e0655a", interrupts = "e0a0e0", dispels = "6fb0e0" }
local GOLD = "c9a76a"
local EN = "-"   -- plain separator

-- A weight fraction -> "35%" / "12.5%" (drop a trailing .0).
local function pctStr(f)
    local v = (f or 0) * 100
    if math.abs(v - math.floor(v + 0.5)) < 0.05 then return string.format("%d%%", math.floor(v + 0.5)) end
    return string.format("%.1f%%", v)
end
-- The theme hex for a grade letter (S+/A/B/... -> its tier color), same ramp the score cards use.
local function gradeHex(grade)
    return (ML.TierColor and ML.TierColor((grade or "?"):sub(1, 1))) or GOLD
end

-- A content card: accent left edge, title (+ optional right chip), a wrapped body, and an optional
-- guardrail line. We draw the TEXT first (OVERLAY layer) then the background Box afterwards (BACKGROUND,
-- so it sits UNDER the text), letting the card auto-size to its measured text. Returns the BOTTOM y (most
-- negative) - single-column callers subtract their own gap; b:Grid adds the row gap.
local function card(b, C, x, y, w, accent, title, chip, body, guard)
    local pad = 14
    local ix, iw = x + pad, w - pad * 2
    local cy = y - pad
    b:Label(title, ix, cy, C.text, 14)
    if chip then
        local fs = b:Label(chip, ix, cy, b.theme:Color(accent, C.accent), 12)
        b:put(fs, x + w - pad - (fs:GetStringWidth() or 30), cy)
    end
    cy = cy - 24
    if body then
        local _, bh = b:Wrap(body, ix, cy, iw, C.subtext, 12)
        cy = cy - (bh + (guard and 8 or 4))
    end
    if guard then
        local _, gh = b:Wrap("|cff8fd9a8Guardrail " .. EN .. " |r" .. guard, ix, cy, iw, C.subtext, 11)
        cy = cy - (gh + 4)
    end
    local total = (y - cy) + pad
    b:Box(x, y, w, total, 0.45, 0, C.card)
    b:Box(x, y, 3, total, 0.95, 1, b.theme:Color(accent, C.accent))
    return y - total
end

-- Turn a list of card-arg tables into b:Grid cell closures (each renders one card in its column).
local function cellsFor(b, C, defs)
    local cells = {}
    for _, d in ipairs(defs) do
        cells[#cells + 1] = function(cx, cwid, cty)
            return card(b, C, cx, cty, cwid, d.accent, d.title, d.chip, d.body, d.guard)
        end
    end
    return cells
end

-- The page. Signature matches a module Settings render: (mod, b, x, y, w, win).
local function renderGuide(mod, b, x, y, w, win)
    local C = b.theme.C
    local Cfg = ML.Scoring and ML.Scoring.Config
    if not Cfg then
        b:Wrap("The scoring engine isn't loaded yet.", x, y, w - 20, C.subtext, 12)
        return y - 30
    end
    local W = (Cfg.roleWeights and Cfg.roleWeights.DAMAGER) or {}

    -- Standard page header.
    y = b:PageHeading(x, y,
        "How Scoring Works",
        "A plain-language guide to how every run is graded. Each player gets a report card of 5 metrics, blended by "
        .. "weight into an overall score and letter grade - built from what your group and spec could actually do this run.",
        w)

    -- Weight bar (full width) - a large, bold hero bar; segments left-to-right in weight order.
    y = b:Section("THE 5 METRICS", x, y); y = y - 32
    local barOrder = { "throughput", "survival", "deaths", "interrupts", "dispels" }
    local bx, barH, barFont = x, 46, 17
    for _, k in ipairs(barOrder) do
        local seg = w * (W[k] or 0)
        local segW = math.max(2, seg - 3)
        b:Box(bx, y, segW, barH, 0.95, 1, b.theme:Color(MET[k], C.accent))
        local fs = b:Label(pctStr(W[k]), bx, y - (barH - barFont) / 2, { 1, 1, 1 }, barFont)
        fs:SetFont(b.theme.FONT, barFont, "OUTLINE")   -- white with a thin black border
        fs:SetWidth(segW); fs:SetJustifyH("CENTER")
        bx = bx + seg
    end
    y = y - barH - 20

    -- Metric cards (2-column responsive grid), in the SAME left-to-right order as the bar (by weight).
    local metricDefs = {
        { accent = MET.throughput, title = "Throughput", chip = pctStr(W.throughput),
          body = "Are you pulling your weight? DPS are judged on damage; healers mostly on healing; tanks on a blend of both (they deal damage AND self-heal). We compare what you did to your fair share of the group's output.",
          guard = "A teammate out-performing never raises your bar: their extra is stripped from the group total, and going over your own share simply caps at 100." },
        { accent = MET.survival, title = "Survival", chip = pctStr(W.survival),
          body = "What percentage of YOUR damage taken was avoidable (stuff to sidestep)? The lower the better - a small grace band, then it drops fast. Standing in the bad hurts your Survival, not your healer.",
          guard = "This one is entirely your own: nobody else's play can move it, and a teammate in the fire hurts THEIR Survival, not yours." },
        { accent = MET.deaths, title = "Deaths", chip = pctStr(W.deaths),
          body = string.format("Start at 100, lose %d per death. When we can tell how you died we weight it: an avoidable death (fall, fire, standing in it) hurts most, an unlucky one less, a lost-threat melee least. The finishing blow decides the type.",
              (Cfg.deaths and Cfg.deaths.perExtra) or 25),
          guard = "Only YOUR deaths count - never party deaths. A teammate face-planting five times doesn't touch your grade." },
        { accent = MET.interrupts, title = "Interrupts (Kicks)", chip = pctStr(W.interrupts),
          body = "Each dungeon offers a rough number of kickable casts. We split it across the party by how often each person's kick is up - a short-cooldown kicker is expected to do more. No interrupt for your spec? Skipped, not failed.",
          guard = "If a teammate kicks everything first, your expected kicks drop - you're never docked for a kick gone before your cooldown came up." },
        { accent = MET.dispels, title = "Dispels", chip = pctStr(W.dispels),
          body = "Same idea as kicks, for cleansing debuffs off friends and purging/soothing enemies. We only ever expect the TYPES your spec can remove - a Holy Paladin cleanses Magic off a friend but can't purge it off an enemy.",
          guard = "If the group already handled the one or two dispels that came up, a tiny share becomes N/A instead of a 0." },
    }
    y = b:Grid(x, y, cellsFor(b, C, metricDefs), { columns = 2, gap = 16, rowGap = 12, width = w, minColWidth = 300 })

    -- Real-world factors (2-column grid).
    y = b:Section("WHAT SHAPES YOUR EXPECTATIONS", x, y); y = y - 30
    local IA = (Cfg.throughput and Cfg.throughput.ilvlAdjust) or {}
    local OF = (Cfg.throughput and Cfg.throughput.outcomeFloor) or {}
    local factorDefs = {
        { accent = GOLD, title = "Your group, not a leaderboard",
          body = "Your bar is your fair share of what your group actually produced this run - not a fixed target. Undergeared group, low numbers, low bar. There's no arbitrary static baseline." },
        { accent = GOLD, title = "Your class & spec",
          body = "We know exactly what each spec can do. A spec with no interrupt is never expected to kick; a spec that can't dispel a type is never asked to. You're only graded on what your character can actually do." },
        { accent = GOLD, title = "Each dungeon is different",
          body = "Every dungeon has its own supply of kickable casts and dispellable effects, measured from real runs. A dungeon with nothing to dispel won't dock anyone for not dispelling. (See the Dungeon Guide.)" },
        { accent = GOLD, title = "Item level",
          body = string.format("Throughput is the one place gear really changes output, so your damage expectation is nudged by your item level vs the group average (about %s%% per item level, capped at +/-%d%%). The lowest-geared player isn't punished for output their gear can't reach.",
              string.format("%.2g", (IA.perIlvl or 0.01) * 100), math.floor(((IA.clampHi or 1.2) - 1) * 100 + 0.5)) },
        { accent = GOLD, title = "Group composition",
          body = string.format("More dispellers or kickers means a smaller share each. Support specs (like Augmentation) are judged as support, not personal damage. Carrying a slacker only helps them partway (forgiveness %d%%).",
              math.floor((Cfg.snipeForgiveness or 0.5) * 100 + 0.5)) },
        { accent = GOLD, title = "The healer safety net",
          body = string.format("Healers and tanks are judged on the damage the group HAD to survive, not a share of healing. Time the key with no deaths and the healing half is lifted to a full %d.", OF.target or 100),
          guard = "Damage from standing in avoidable stuff is mostly forgiven for the healer - it hits the stander's own Survival, not your healing target." },
    }
    y = b:Grid(x, y, cellsFor(b, C, factorDefs), { columns = 2, gap = 16, rowGap = 12, width = w, minColWidth = 300 })

    -- Grade ladder (live, colored by tier).
    y = b:Section("GRADES", x, y); y = y - 30
    local gx, gy, chipW, chipH = x, y, 88, 36
    for _, g in ipairs(Cfg.grades or {}) do
        if gx + chipW > x + w then gx = x; gy = gy - chipH - 8 end
        local hex = gradeHex(g.grade)
        b:Box(gx, gy, chipW - 8, chipH, 0.5, 0, C.card)
        b:Box(gx, gy, 3, chipH, 0.95, 1, b.theme:Color(hex, C.accent))
        b:Label(g.grade, gx + 10, gy - 9, b.theme:Color(hex, C.text), 15)
        b:Label(g.min .. "+", gx + 10, gy - 25, C.subtext, 10)
        gx = gx + chipW
    end
    y = gy - chipH - 12
    do
        local _, gh = b:Wrap("|cffffffffS+|r is a flawless run " .. EN .. " every metric that applied to you scored a perfect 100.", x, y, w - 20, C.subtext, 11)
        y = y - gh - 12
    end

    -- Tank note (full width) + footer.
    y = card(b, C, x, y, w, MET.deaths, "For tanks", nil,
        "Your review also flags teammate deaths that came from a mob you lost or never had threat on " .. EN .. " shown for awareness, it is NOT part of your score.", nil) - 12

    local _, fh = b:Wrap(string.format(
        "This is exactly how the current engine (v%d) scores your runs " .. EN .. " honest, spec-aware feedback to help you improve. It's never a ranking, and it's never shared anywhere.",
        Cfg.version or 0), x, y, w - 20, C.subtext, 11)
    return y - fh - 20
end

Guide.Render = renderGuide

----------------------------------------------------------------------
-- Register as its own left-menu entry (under Modules). Read-only reference: always renders (even when the
-- Ledger is toggled off) and has no lifecycle of its own.
----------------------------------------------------------------------
Suite:RegisterModule({
    id       = "scoringGuide",
    title    = "Scoring Guide",
    desc     = "How every run is graded, in plain language - the 5 metrics, the real-world factors (gear, spec, "
            .. "dungeon, group), the fairness guardrails, and the grade ladder. Read-only reference.",
    icon     = "help-circle",
    addon    = ML.ADDON,
    default  = true,
    fullPage = true,
    rendersWhenDisabled = true,
    OnEnable   = function() end,
    OnDisable  = function() end,
    OnSelect   = function() end,
    OnDeselect = function() end,
    Settings   = renderGuide,
})
