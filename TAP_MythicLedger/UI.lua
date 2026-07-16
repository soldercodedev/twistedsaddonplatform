-- TAP: Mythic Ledger - UI.lua
-- The module's single page, an internal tab bar (Overview / Runs / Dungeons / Characters /
-- Players / Bests / Settings / Debug) with Run-Details and Player-Details sub-views, plus the
-- post-run summary modal. Tables are Lua-sorted/filtered row loops rendered into the suite's
-- shared scroll frame (UIFoundry has no table widget), styled with the shared Builder widgets.

local ADDON, ML = ...
local API     = ML.API
local DB      = ML.DB
local History = ML.History
local Util    = ML.Util
local STATUS  = ML.STATUS
local DASH    = ML.DASH

local UI = {}
ML.UI = UI

-- Module-local view state (reset via OnSelect / detail back buttons).
local view = { tab = "overview", season = "current", detailRun = nil, detailPlayer = nil, detailDungeon = nil, detailCharacter = nil, review = nil }
-- Per-run player-review target (object refs, so it works for both saved and unsaved/preview runs).
local reviewRunRef, reviewMemberRef = nil, nil
local runFilter    = { character = nil, mapId = nil, status = nil, playerKey = nil }
local runSort      = { key = "date", dir = "desc" }
local playerFilter = { search = "", role = nil, favorite = false, minShared = 1 }
local playerSort   = { key = "runs", dir = "desc" }
local dungeonSort  = { key = "name", dir = "asc" }
local retentionPending = nil   -- staged retention cap; committed only via the Settings "Apply" button
local charSort     = { key = "runs", dir = "desc" }
local statsFilter  = { season = "current", character = nil, mapId = nil, minKey = 0 }

-- Forward declarations: this score-helper cluster is defined much lower (near the scoreboard code)
-- but is used earlier by renderRunDetails (the run-details party table). Declaring the locals up here
-- lets those earlier closures capture them as upvalues; without this they resolved to nil globals
-- (settings error "attempt to call a nil value" at the first one, runScores).
local runScores, gradeColor, memberScore, scoreTipLines, renderPlayerReview

-- Generic in-place sort of a list by a key-extractor map + a sort-state {key,dir}.
local function applySort(list, st, extractors, tiebreak)
    local ex = extractors[st.key] or extractors[next(extractors)]
    local desc = (st.dir == "desc")
    table.sort(list, function(a, bb)
        local av, bv = ex(a) or 0, ex(bb) or 0
        if av == bv and tiebreak then return tiebreak(a, bb) end
        if desc then return av > bv else return av < bv end
    end)
    return list
end

----------------------------------------------------------------------
-- Pagination. One page state per table; the pager renders prev/next + "Page x / y" on the header
-- line and returns the [first, last] slice to render. Page is clamped so a filter change can't
-- strand you on an empty page.
----------------------------------------------------------------------
local PAGE_SIZES = { 10, 15, 20, 30, 50 }
local pageState = { runs = 1, dungeons = 1, characters = 1, players = 1, size = 20 }

-- Draw a pager bar on its own line: "Per page" dropdown (left) + prev / "Page x / y" / next
-- (right). Drawn both above and below each table. Returns the [first, last] slice to render.
local function pagerBar(b, C, x, y, rowW, total, which, win)
    local size = pageState.size or 20
    local pages = math.max(1, math.ceil(total / size))
    local p = math.min(math.max(1, pageState[which] or 1), pages)
    pageState[which] = p

    b:Label("Per page", x, y - 6, C.subtext, 11)
    local ppChoices = {}
    for _, n in ipairs(PAGE_SIZES) do ppChoices[#ppChoices + 1] = { n, tostring(n) } end
    b.theme:SetTip(b:Dropdown(x + 64, y), "Rows per page", "How many rows to show per page."):SetChoices(
        70, ppChoices, function() return pageState.size end,
        function(v) pageState.size = v; pageState[which] = 1; win:Refresh() end)

    local cx = x + rowW - 150
    b.theme:SetTip(b:Button(cx, y, 26, "", "ghost", function() pageState[which] = math.max(1, p - 1); win:Refresh() end,
        { icon = "chevron-left", iconSize = 13, height = 22 }), "Previous page")
    local lbl = b:Label(string.format("Page %d / %d", p, pages), cx + 32, y - 6, C.text, 11)
    lbl:SetWidth(84); lbl:SetJustifyH("CENTER")
    b.theme:SetTip(b:Button(cx + 122, y, 26, "", "ghost", function() pageState[which] = math.min(pages, p + 1); win:Refresh() end,
        { icon = "chevron-right", iconSize = 13, height = 22 }), "Next page")

    return (p - 1) * size + 1, math.min(total, p * size)
end

-- Debounced page refresh: coalesces rapid changes (e.g. a slider drag) into one refresh shortly
-- after they stop. Refreshing on every value change would rebuild the page mid-drag and drop the
-- slider being dragged - so filter sliders schedule instead of refreshing immediately.
local refreshTimer
local function scheduleRefresh(win)
    if refreshTimer then refreshTimer:Cancel() end
    refreshTimer = C_Timer.NewTimer(0.2, function()
        refreshTimer = nil
        if win and win.Refresh then win:Refresh() end
    end)
end

local TABS = {
    { "overview", "Overview" }, { "runs", "Runs" }, { "dungeons", "Dungeons" },
    { "characters", "Characters" }, { "players", "Players" }, { "bests", "Bests" },
    { "settings", "Settings" }, { "debug", "Debug" },
}

----------------------------------------------------------------------
-- Small render helpers.
----------------------------------------------------------------------
-- Safe current-season read: the season API can be unavailable early in load / before RequestMapInfo,
-- so never let a nil here crash a render - fall back to "no season filter" (all).
local function currentSeason()
    return (API and API.GetCurrentSeason and API.GetCurrentSeason()) or nil
end

local function scopeSeason()
    if view.season == "all" then return nil end
    if view.season == "current" then return currentSeason() end
    return view.season
end

local function seasonChoices()
    local c = { { "current", "Current Season" }, { "all", "All Seasons" } }
    for _, id in ipairs(History.SeasonsPresent()) do
        c[#c + 1] = { id, ML.SeasonLabel(id) }
    end
    return c
end

local function statusBadgeVariant(status)
    if status == STATUS.TIMED then return "success" end
    if status == STATUS.DEPLETED then return "warning" end
    return "neutral"
end

local function statusText(status)
    if status == STATUS.TIMED then return "Timed" end
    if status == STATUS.DEPLETED then return "Depleted" end
    if status == STATUS.ABANDONED then return "Abandoned" end
    return "?"
end

local function classColorText(classFile, name)
    local rc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if rc then return string.format("|cff%02x%02x%02x%s|r", rc.r * 255, rc.g * 255, rc.b * 255, name or "") end
    return name or ""
end

-- Localized "Spec Class" (or class, or dash) from a stats/member-ish record.
local function specClassLabel(classFile, specId)
    local classLoc = classFile and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile)
    local specName
    if specId and GetSpecializationInfoByID then
        local ok, _id, nm = pcall(GetSpecializationInfoByID, specId)
        if ok then specName = ML.ReadStr(nm) end
    end
    if specName and classLoc then return specName .. " " .. classLoc end
    return classLoc or DASH
end

-- Role-relevant primary metric (value string) for a stat block.
local function primaryMetric(role, stats)
    if not stats then return DASH end
    if role == "HEALER" then return Util.shortNum(stats.hps) end
    return Util.shortNum(stats.dps)
end

-- Attach a hover tooltip to a widget and return it, for inline wrapping:
--   T(b, b:Button(...), "Title", "Body")
local function T(b, widget, title, body)
    if widget and b.theme and b.theme.SetTip then b.theme:SetTip(widget, title, body) end
    return widget
end

-- A clean "admin" filter toolbar: a subtle raised, bordered panel with an accent rail that holds
-- label-above-control form groups. Groups flow across as many columns as fit (each >= ~150px),
-- wrapping to new rows. Every field is:
--   { label = "Season", build = function(fieldX, controlY, controlW) ...draw the control... end }
-- The stacked label + fixed control row also fixes the old slider value-readout collision (give
-- the slider `ApplyStyle{ hideValue = true }` and put its value in the label). Returns the y below.
local function filterBar(b, C, x, y, w, fields)
    local leftInset, rightInset, padTop, padBot, gap = 18, 14, 12, 12, 18
    local labelDrop, ctrlH = 15, 26
    local rowStep = labelDrop + ctrlH + 12
    local avail = w - leftInset - rightInset
    local cols = math.max(1, math.min(#fields, math.floor((avail + gap) / (150 + gap))))
    local colW = math.floor((avail - gap * (cols - 1)) / cols)
    local rows = math.ceil(#fields / cols)
    local barH = padTop + (rows - 1) * rowStep + labelDrop + ctrlH + padBot

    -- Panel: raised fill, 1px border, and a left accent rail (all behind the control frames).
    b:Box(x, y, w, barH, 0.6, -3, C.card)
    b:Box(x, y, w, 1, 0.85, -1, C.border)                    -- top
    b:Box(x, y - barH + 1, w, 1, 0.85, -1, C.border)         -- bottom
    b:Box(x, y, 1, barH, 0.85, -1, C.border)                 -- left
    b:Box(x + w - 1, y, 1, barH, 0.85, -1, C.border)         -- right
    b:Box(x, y, 3, barH, 0.95, -1, C.accent)                 -- accent rail

    local innerX = x + leftInset
    local topLabelY = y - padTop
    for i, f in ipairs(fields) do
        local r = math.floor((i - 1) / cols)
        local c = (i - 1) % cols
        local fx = innerX + c * (colW + gap)
        local ly = topLabelY - r * rowStep
        b:Heading(f.label, fx, ly, "overline")
        f.build(fx, ly - labelDrop, colW)
    end
    return y - barH - 10
end

----------------------------------------------------------------------
-- Icon + header helpers (eye candy). Glyphs are non-interactive, so the row underneath keeps its
-- hover/click; the row's tooltip carries the class/spec/detail text.
----------------------------------------------------------------------
local CLASS_ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"

local function classGlyph(b, x, y, size, classFile)
    local coords = classFile and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[classFile]
    if coords then b:Tex(x, y, size, size, CLASS_ICON_TEX, coords)
    else b:Tex(x, y, size, size, "user", nil, { 0.5, 0.5, 0.56 }) end
end

local function specIconID(specId)
    if specId and GetSpecializationInfoByID then
        local ok, _id, _n, _d, icon = pcall(GetSpecializationInfoByID, specId)
        if ok then return ML.ReadNum(icon) end
    end
    return nil
end
local function specGlyph(b, x, y, size, specId, specIcon)
    local icon = specIcon or specIconID(specId)
    if icon then b:Tex(x, y, size, size, icon) end
end

local function classRGB(classFile)
    local c = classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
    return c and { c.r, c.g, c.b } or nil
end

-- Class colour as an "RRGGBB" hex (for tipData lcolor/rcolor), or nil.
local function classHexOf(classFile)
    local c = classRGB(classFile)
    return c and string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) or nil
end

-- A boss/creature portrait, bare: no border, no backing. EJ creature icons are WIDE 2:1 banners
-- (Blizzard's Encounter Journal draws them at 128x64 with full texcoords), NOT squares - drawing them
-- square stretched the art. We draw an explicit w x h (callers pass a 2:1 rect) with full texcoords
-- (0,1,0,1): native aspect, no crop, no squish.
local function framedIcon(b, x, yTop, w, h, tex)
    if tex then b:Tex(x, yTop, w, h, tex, nil, nil, 2)                              -- full texture, native 2:1
    else b:Tex(x, yTop, w, h, "user", nil, { 0.5, 0.5, 0.56 }, 2) end
end

-- Small LFG role icon (tank / healer / dps) for a role token, or nothing for an unknown role.
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local function roleIcon(b, x, y, size, role)
    if not role or role == "NONE" or not GetTexCoordsForRoleSmallCircle then return end
    local l, r, t, bt = GetTexCoordsForRoleSmallCircle(role)
    if l then b:Tex(x, y, size, size, ROLE_TEX, { l, r, t, bt }) end
end

-- A little drawn gravestone (grey slab with a carved skull) - we have no bundled gravestone icon.
local function gravestone(b, x, yTop, w, h)
    b:Box(x - 1, yTop + 1, w + 2, h + 2, 1, 0, { 0.16, 0.17, 0.20 })          -- border/shadow
    b:Box(x, yTop, w, h, 1, 0, { 0.55, 0.57, 0.63 })                          -- stone slab
    b:Tex(x + w * 0.16, yTop - h * 0.14, w * 0.68, h * 0.68, "skull", nil, { 0.22, 0.23, 0.27 })
end

-- The specialization's own name (e.g. "Fire"), or nil if the spec isn't known.
local function specName(specId)
    if specId and GetSpecializationInfoByID then
        local ok, _id, nm = pcall(GetSpecializationInfoByID, specId)
        if ok then return ML.ReadStr(nm) end
    end
    return nil
end

local function dungeonGlyph(b, x, y, size, mapId)
    local mi = mapId and API.GetMapInfo(mapId)
    if mi and mi.texture then b:Tex(x, y, size, size, mi.texture)
    else b:Tex(x, y, size, size, "map", nil, { 0.55, 0.6, 0.72 }) end
end

-- Louder static column header: uppercase accent label.
local function hdr(b, C, cx, y, label) b:Label(label:upper(), cx, y, C.accent, 11) end

-- Clickable, sortable column header: a clean uppercase accent label with a sort arrow when active,
-- plus a transparent hover-highlight hit region over it (no button chrome). Toggles asc/desc.
local function sortHdr(b, C, cx, y, wCol, label, key, st, win)
    local active = (st.key == key)
    local arrow = active and (st.dir == "desc" and "  v" or "  ^") or ""
    b:Label(label:upper() .. arrow, cx, y, C.accent, 11)
    b:Hit(cx - 4, y + 5, (wCol or 60) + 8, 20, function()
        if st.key == key then st.dir = (st.dir == "desc") and "asc" or "desc"
        else st.key = key; st.dir = "desc" end
        win:Refresh()
    end, label, "Sort by " .. label:lower() .. ".")
end

----------------------------------------------------------------------
-- Tab bar + season selector.
----------------------------------------------------------------------
local TAB_TIPS = {
    overview = "Season totals and highlights at a glance.",
    runs = "Every recorded run, with filters and sorting.",
    dungeons = "Per-dungeon timed %, best times, and best keys.",
    characters = "Your runs broken down by character.",
    players = "Everyone you've run keys with - searchable and sortable.",
    bests = "Your personal bests (kept per key level and role).",
    settings = "Tracking, provider, recap, and data options.",
    debug = "Live diagnostics and a copyable summary.",
}

local function renderTabBar(b, C, x, y, w, win)
    local tw, gap = 84, 4
    for i, t in ipairs(TABS) do
        local isA = (view.tab == t[1]) and not view.detailRun and not view.detailPlayer
        T(b, b:Button(x + (i - 1) * (tw + gap), y, tw, t[2], isA and "primary" or "default", function()
            view.tab = t[1]; view.detailRun = nil; view.detailPlayer = nil
            if win then win:Refresh() end
        end), t[2], TAB_TIPS[t[1]])
    end
    y = y - 28
    b:Box(x, y + 2, #TABS * (tw + gap) - gap, 2, 0.5, 0, C.accent)
    return y - 14
end

local function renderSeasonSelector(b, C, x, y, w, win)
    b:Label("Season", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 56, y), "Season", "Scope every stat on this page to a season, or show all seasons.")
        :SetChoices(200, seasonChoices(),
        function() return view.season end,
        function(v) view.season = v; if win then win:Refresh() end end)
    return y - 34
end

----------------------------------------------------------------------
-- Overview.
----------------------------------------------------------------------
local function renderOverview(b, C, x, y, w, win)
    y = renderSeasonSelector(b, C, x, y, w, win)
    local o = History.Overview(scopeSeason())
    local prov = ML.Providers.Select()

    -- Summary cards: icon + WoW-quality colour scale (ML.HERO_STATS) + a supporting subtext line
    -- (ML.HeroStatSubtext). The visual style is user-selectable in Settings (Clean/Panel/Compact).
    -- We pass the raw metric (for the colour scale) and the already-formatted display string.
    local style = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[DB.Settings().cardStyle] or "panel"
    local scopeLabel = scopeSeason() and "This season" or "All seasons"
    local th = (style == "panel" and 100) or (style == "compact" and 104) or 96
    local tw, gx, gy = 150, 162, th + 12
    local function tile(col, row, key, value, formatted)
        local s = ML.HeroStatStyle(key, value, formatted)
        local sub = ML.HeroStatSubtext(key, o, scopeLabel)
        b:StatTile(x + col * gx, y - row * gy, {
            style = style, label = s.label, value = formatted or DASH,
            width = tw, height = th,
            accent = s.color, icon = s.icon, tipData = s.tipData,
            sub = sub.sub, footer = sub.footer,
        })
    end
    tile(0, 0, "runs",          o.runs,         tostring(o.runs))
    tile(1, 0, "timed",         o.timed,        tostring(o.timed))
    tile(2, 0, "timedPercent",  o.timedPct,     o.timedPct and Util.percent(o.timedPct) or DASH)
    tile(3, 0, "highestTimed",  o.highestTimed, o.highestTimed and ("+" .. o.highestTimed) or DASH)
    tile(0, 1, "averageKey",    o.avgLevel,     o.avgLevel and string.format("+%.1f", o.avgLevel) or DASH)
    tile(1, 1, "averageTime",   o.avgDuration,  o.avgDuration and Util.duration(o.avgDuration) or DASH)
    tile(2, 1, "averageDeaths", o.avgDeaths,    o.avgDeaths and string.format("%.2f", o.avgDeaths) or DASH)
    tile(3, 1, "returning",     o.returning,    tostring(o.returning))
    y = y - 2 * gy - 6

    b:Section("AT A GLANCE", x, y); y = y - 28
    local function line(lbl, val)
        b:Label(lbl, x, y - 2, C.subtext); b:Label(val or DASH, x + 220, y - 2, C.text)
        y = y - 22
    end
    line("Most-played dungeon", o.topDungeon)
    line("Most-played character", o.topCharacter)
    line("Active stat provider", prov and prov:GetName() or "Metadata-only")
    line("Depleted / Abandoned", string.format("%d / %d", o.depleted, o.abandoned))
    return y - 8
end

----------------------------------------------------------------------
-- Runs list.
----------------------------------------------------------------------
local function sortedRuns()
    local runs = History.FilterRuns({
        seasonId = scopeSeason(), character = runFilter.character, mapId = runFilter.mapId,
        status = runFilter.status, playerKey = runFilter.playerKey,
    })
    local key, dir = runSort.key, runSort.dir
    local mult = (dir == "desc") and 1 or -1
    table.sort(runs, function(a, bb)
        local av, bv
        if key == "date" then av, bv = (a.completedAt or 0), (bb.completedAt or 0)
        elseif key == "key" then av, bv = (a.level or 0), (bb.level or 0)
        elseif key == "duration" then av, bv = (a.duration or 0), (bb.duration or 0)
        elseif key == "deaths" then av, bv = (a.deaths or -1), (bb.deaths or -1)
        else av, bv = (a.completedAt or 0), (bb.completedAt or 0) end
        if av == bv then return (a.completedAt or 0) > (bb.completedAt or 0) end
        return (av > bv) == (mult == 1)
    end)
    return runs
end

local STATUS_HEX = { TIMED = "33dd66", DEPLETED = "e0a030", ABANDONED = "9098a8" }

-- Rich tooltip data for a run row: dungeon icon header + colour-coded stat lines + party list.
local function runTipData(r)
    local mi = r.mapId and API.GetMapInfo(r.mapId)
    local timeStr = Util.duration(r.duration)
    if r.timeRemaining then
        timeStr = timeStr .. "  (" .. (r.timeRemaining >= 0 and "-" or "+") .. Util.duration(math.abs(r.timeRemaining)) .. ")"
    end
    local role = r.character and r.character.role
    local lines = {
        { left = "Result", right = statusText(r.status), rcolor = STATUS_HEX[r.status] },
        { left = "Time / Limit", right = timeStr .. " / " .. Util.duration(r.timeLimit) },
        { left = (role == "HEALER") and "Your HPS" or "Your DPS", right = primaryMetric(role, r.playerStats) },
        { left = "Deaths", right = Util.numOr(r.deaths, "%d") },
        { left = "Affixes", right = (r.affixNames and #r.affixNames > 0) and table.concat(r.affixNames, ", ") or "-" },
        { sep = true },
    }
    for _, m in ipairs(r.party or {}) do
        if not m.isPlayer then
            -- Favorites get a gold star; a saved note is shown on its own muted line beneath.
            local pkey = API.IdentityKey(m)
            local prec = pkey and DB.PlayerIndex()[pkey]
            local star = (prec and prec.favorite) and "|cffffd200*|r " or ""
            lines[#lines + 1] = { left = "  " .. star .. (m.name or "?"), right = specName(m.specId) or "-",
                lcolor = m.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.classFile]
                    and { RAID_CLASS_COLORS[m.classFile].r, RAID_CLASS_COLORS[m.classFile].g, RAID_CLASS_COLORS[m.classFile].b } or nil }
            if prec and prec.notes and prec.notes ~= "" then
                lines[#lines + 1] = { text = "     \"" .. prec.notes .. "\"", color = "subtext" }
            end
        end
    end
    lines[#lines + 1] = { blank = true }
    lines[#lines + 1] = { text = "Click to open the full run.", color = "subtext" }
    return { icon = mi and mi.texture, title = (r.dungeonName or "Run") .. "  " .. Util.keyLabel(r.level), lines = lines }
end

local function renderRunsList(b, C, x, y, w, win)
    y = renderSeasonSelector(b, C, x, y, w, win)

    b:Label("Result", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 56, y), "Result filter", "Show only timed, depleted, or abandoned runs."):SetChoices(120, {
        { "all", "All" }, { STATUS.TIMED, "Timed" }, { STATUS.DEPLETED, "Depleted" }, { STATUS.ABANDONED, "Abandoned" },
    }, function() return runFilter.status or "all" end,
       function(v) runFilter.status = (v ~= "all") and v or nil; win:Refresh() end)
    if runFilter.playerKey then
        T(b, b:Button(x + 200, y, 150, "Clear player filter", "ghost", function()
            runFilter.playerKey = nil; win:Refresh()
        end), "Clear filter", "Stop filtering the list to a single party member.")
    end
    y = y - 34

    local runs = sortedRuns()
    local rowW = w - 12
    b:Sub(string.format("RUNS (%d)", #runs), x, y); y = y - 26
    if #runs == 0 then
        b:Wrap("No runs recorded yet for this filter. Complete a Mythic+ key and it appears here automatically.",
            x, y, w - 20, C.subtext, 12)
        return y - 30
    end
    local first, last = pagerBar(b, C, x, y, rowW, #runs, "runs", win); y = y - 42

    local cIcon, cDate, cChar, cDun, cKey, cRes, cDur, cDth, cPerf =
        x + 6, x + 32, x + 118, x + 250, x + 400, x + 442, x + 532, x + 606, x + 648

    -- Header band + clean, sortable labels (no button chrome).
    b:Box(x, y + 4, rowW, 24, 0.10, 0, C.accent)
    sortHdr(b, C, cDate, y - 2, 60, "Date", "date", runSort, win)
    hdr(b, C, cChar, y - 2, "Character"); hdr(b, C, cDun, y - 2, "Dungeon")
    sortHdr(b, C, cKey, y - 2, 36, "Key", "key", runSort, win)
    hdr(b, C, cRes, y - 2, "Result")
    sortHdr(b, C, cDur, y - 2, 48, "Time", "duration", runSort, win)
    b:Tex(cDth, y - 4, 14, 14, "skull", nil, (runSort.key == "deaths") and C.accent or { 0.72, 0.74, 0.82 })
    b:Hit(cDth - 4, y + 5, 30, 20, function()
        if runSort.key == "deaths" then runSort.dir = runSort.dir == "desc" and "asc" or "desc"
        else runSort.key = "deaths"; runSort.dir = "desc" end
        win:Refresh()
    end, "Deaths", "Total party deaths - click to sort.")
    hdr(b, C, cPerf, y - 2, "DPS/HPS")
    y = y - 26

    for i = first, last do
        local r = runs[i]
        local h = 30
        local yTop = y
        local role = r.character and r.character.role
        b:Row(x, yTop, rowW, h, { index = i, tipData = runTipData(r),
            onClick = function() view.detailRun = r.id; win:Refresh() end })
        dungeonGlyph(b, cIcon, yTop - 5, 20, r.mapId)
        b:Label(Util.dateShort(r.completedAt), cDate, yTop - 10, C.subtext, 11)
        b:Label(classColorText(r.character and r.character.classFile, r.character and r.character.name or "?"),
            cChar, yTop - 10, C.text, 11)
        b:Label(r.dungeonName or DASH, cDun, yTop - 10, C.text, 11)
        -- Crown marks a protected best-per-dungeon run (never trimmed by retention).
        if r.pinned then b:Tex(cKey - 16, yTop - 10, 13, 13, "crown", nil, { 1, 0.82, 0.2 }) end
        b:Label(Util.keyLabel(r.level), cKey, yTop - 10, C.accent, 12)
        b:Badge(cRes, yTop - 9, { text = statusText(r.status), variant = statusBadgeVariant(r.status) })
        b:Label(Util.duration(r.duration), cDur, yTop - 10, C.text, 11)
        b:Label(Util.numOr(r.deaths, "%d"), cDth + 4, yTop - 10, C.text, 11)
        b:Label(primaryMetric(role, r.playerStats), cPerf, yTop - 10, C.text, 11)
        y = yTop - h - 2
    end
    y = y - 6
    pagerBar(b, C, x, y, rowW, #runs, "runs", win)
    return y - 28
end

----------------------------------------------------------------------
-- Run details.
----------------------------------------------------------------------
local function findRun(id)
    for _, r in ipairs(DB.Runs()) do if r.id == id then return r end end
    -- Fall back to the run the scoreboard was opened on (covers unsaved /mldev preview runs).
    if UI._lastScoreboardRun and UI._lastScoreboardRun.id == id then return UI._lastScoreboardRun end
    return nil
end

local function renderRunDetails(b, C, x, y, w, win)
    local r = findRun(view.detailRun)
    if not r then view.detailRun = nil; return y end
    local scores = runScores(r)   -- ML.Scoring performance grades per party member
    T(b, b:Button(x + w - 84, y, 72, "Back", "default", function() view.detailRun = nil; win:Refresh() end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the run list.")
    T(b, b:Button(x + w - 210, y, 120, "Scoreboard", "primary", function() UI.ShowScoreboard(r) end,
        { icon = "award", iconSize = 13 }), "Scoreboard", "Open the full end-of-run scoreboard for this run.")
    b:Heading((r.dungeonName or "Run") .. "  " .. Util.keyLabel(r.level), x, y, "h2"); y = y - 34
    b:Badge(x, y, { text = statusText(r.status), variant = statusBadgeVariant(r.status) })
    b:Label(Util.dateTime(r.completedAt), x + 90, y - 2, C.subtext, 11)
    y = y - 26
    local aff = (r.affixNames and #r.affixNames > 0) and table.concat(r.affixNames, ", ") or DASH
    b:Label("Affixes: " .. aff, x, y - 2, C.subtext, 11); y = y - 22
    local timeStr = Util.duration(r.duration)
    if r.timeRemaining then
        timeStr = timeStr .. "  (" .. (r.timeRemaining >= 0 and "under by " or "over by ")
            .. Util.duration(math.abs(r.timeRemaining)) .. ")"
    end
    b:Label("Time: " .. timeStr .. "   /   Limit: " .. Util.duration(r.timeLimit), x, y - 2, C.text, 11)
    y = y - 26

    -- Party table.
    b:Section("PARTY", x, y); y = y - 24
    local rowW = w - 12
    local cP, cGrade, cRole, cDmg, cDps, cDt, cHeal, cHps, cInt, cDis, cDth =
        x + 46, x + 150, x + 200, x + 262, x + 330, x + 398, x + 466, x + 534, x + 602, x + 646, x + 692
    b:Box(x, y + 4, rowW, 22, 0.12, 0, C.accent)
    hdr(b, C, cP, y - 2, "Player"); hdr(b, C, cGrade, y - 2, "Grade"); hdr(b, C, cRole, y - 2, "Role")
    hdr(b, C, cDmg, y - 2, "Dmg"); hdr(b, C, cDps, y - 2, "DPS"); hdr(b, C, cDt, y - 2, "DTkn")
    hdr(b, C, cHeal, y - 2, "Heal"); hdr(b, C, cHps, y - 2, "HPS")
    hdr(b, C, cInt, y - 2, "Int"); hdr(b, C, cDis, y - 2, "Dsp")
    b:Tex(cDth, y - 4, 14, 14, "skull", nil, { 0.72, 0.74, 0.82 })
    y = y - 24
    for i, m in ipairs(r.party or {}) do
        local s = m.stats or {}
        local h = 24
        local yTop = y
        local key = (not m.isPlayer) and API.IdentityKey(m) or nil
        local sc = memberScore(scores, m)
        local tlines = {
            { left = "Spec", right = specClassLabel(m.classFile, m.specId) },
            { left = "Role", right = ML.ROLE_LABEL[m.role] or "-" },
            { sep = true },
            { left = "Damage / DPS", right = Util.shortNum(s.damage) .. " / " .. Util.shortNum(s.dps) },
            { left = "Healing / HPS", right = Util.shortNum(s.healing) .. " / " .. Util.shortNum(s.hps) },
            { left = "Damage taken", right = Util.shortNum(s.damageTaken) },
            { left = "Avoidable taken", right = Util.shortNum(s.avoidableDamageTaken),
                rcolor = (type(s.avoidableDamageTaken) == "number" and s.avoidableDamageTaken > 0) and "e0a030" or nil },
            { left = "Interrupts / Dispels", right = Util.numOr(s.interrupts, "%d") .. " / " .. Util.numOr(s.dispels, "%d") },
            { left = "Deaths", right = Util.numOr(s.deaths, "%d"), rcolor = (type(s.deaths) == "number" and s.deaths > 0) and "e0655a" or nil },
        }
        local slines = scoreTipLines(sc)
        if slines then tlines[#tlines + 1] = { sep = true }; for _, l in ipairs(slines) do tlines[#tlines + 1] = l end end
        tlines[#tlines + 1] = { blank = true }; tlines[#tlines + 1] = { text = "Click for their run review.", color = "subtext" }
        b:Row(x, yTop, rowW, h, { index = i,
            tipData = { icon = specIconID(m.specId) or m.specIcon, minWidth = 420,
                title = (m.fullName or m.name or "?") .. (m.isPlayer and "  (you)" or ""), lines = tlines },
            onClick = function() view.review = true; reviewRunRef = r; reviewMemberRef = m; win:Refresh() end })
        classGlyph(b, x + 4, yTop - 4, 18, m.classFile)
        specGlyph(b, x + 24, yTop - 4, 18, m.specId, m.specIcon)
        b:Label(classColorText(m.classFile, m.name or "?"), cP, yTop - 7, C.text, 11)
        if sc then b:Label(sc.grade or "?", cGrade, yTop - 7, b.theme:Color(gradeColor(sc.grade)), 12)
        else b:Label(DASH, cGrade, yTop - 7, C.subtext, 10) end
        b:Label(ML.ROLE_LABEL[m.role] or DASH, cRole, yTop - 7, C.subtext, 10)
        b:Label(Util.shortNum(s.damage), cDmg, yTop - 7, C.text, 10)
        b:Label(Util.shortNum(s.dps), cDps, yTop - 7, C.text, 10)
        b:Label(Util.shortNum(s.damageTaken), cDt, yTop - 7, C.text, 10)
        b:Label(Util.shortNum(s.healing), cHeal, yTop - 7, C.text, 10)
        b:Label(Util.shortNum(s.hps), cHps, yTop - 7, C.text, 10)
        b:Label(Util.numOr(s.interrupts, "%d"), cInt, yTop - 7, C.text, 10)
        b:Label(Util.numOr(s.dispels, "%d"), cDis, yTop - 7, C.text, 10)
        b:Label(Util.numOr(s.deaths, "%d"), cDth, yTop - 7, C.text, 10)
        y = yTop - h - 1
    end
    y = y - 8

    -- Boss splits.
    if r.bosses and #r.bosses > 0 then
        b:Section("BOSS SPLITS", x, y); y = y - 26
        b:Label("Boss", x, y - 2, C.subtext, 10); b:Label("Kill", x + 220, y - 2, C.subtext, 10)
        b:Label("Attempts", x + 290, y - 2, C.subtext, 10); b:Label("Wipes", x + 366, y - 2, C.subtext, 10)
        b:Label("Total", x + 428, y - 2, C.subtext, 10); b:Label("Your DPS", x + 496, y - 2, C.subtext, 10)
        y = y - 16
        for _, boss in ipairs(r.bosses) do
            b:Label(boss.name or ("Boss " .. tostring(boss.id)), x, y - 2, C.text, 11)
            b:Label(Util.duration(boss.killDuration), x + 220, y - 2, C.text, 11)
            b:Label(tostring(boss.attempts or 0), x + 290, y - 2, C.text, 11)
            b:Label(tostring(boss.wipes or 0), x + 366, y - 2, C.text, 11)
            b:Label(Util.duration(boss.totalTime), x + 428, y - 2, C.subtext, 11)
            b:Label(boss.killDps and Util.shortNum(boss.killDps) or DASH, x + 496, y - 2, C.text, 11)
            y = y - 20
        end
        y = y - 8
    end

    -- Notes.
    b:Section("NOTES", x, y); y = y - 26
    T(b, b:EditBox(x, y, w - 40, r.notes or "", function(t) r.notes = t end),
        "Run notes", "Private notes for this run. Never shared automatically.")
    y = y - 30
    T(b, b:Button(x, y, 130, "Export Run", "default", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.ShowCopyDialog then theme:ShowCopyDialog("Export run", ML.Export.ExportRun(r) or "") end
    end, { icon = "upload", iconSize = 13 }), "Export run", "Copy this run as a share/backup string.")
    T(b, b:Button(x + 140, y, 130, "Delete Run", "danger", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        theme:Confirm({ title = "Delete run?", variant = "danger", confirmLabel = "Delete",
            message = "Permanently delete this run record?",
            onConfirm = function() DB.DeleteRun(r.id); view.detailRun = nil; win:Refresh() end })
    end, { icon = "trash", iconSize = 13 }), "Delete run", "Permanently remove this run from your ledger.")
    return y - 34
end

----------------------------------------------------------------------
-- Dungeons.
----------------------------------------------------------------------
-- Rich at-a-glance dungeon tooltip: big dungeon icon header, headline stats, your best/worst
-- performance here, and who you run it with most.
local function dungeonTipData(d)
    local mi = d.mapId and API.GetMapInfo(d.mapId)
    local lines = {
        { left = "Runs", right = tostring(d.totals.runs), rcolor = "accent" },
        { left = "Timed", right = d.timedPct and Util.percent(d.timedPct) or "-",
          rcolor = STATUS_HEX.TIMED },
        { left = "Best key", right = d.highestTimed and ("+" .. d.highestTimed) or "-", rcolor = "accent" },
        { left = "Best / Avg time", right = Util.duration(d.bestTime) .. "  /  " .. Util.duration(d.avgTime) },
        { left = "Avg deaths", right = d.avgDeaths and string.format("%.1f", d.avgDeaths) or "-" },
    }
    if d.bestDps or d.bestHps then
        lines[#lines + 1] = { sep = true }
        if d.bestDps then
            lines[#lines + 1] = { left = "Your best / worst DPS",
                right = Util.shortNum(d.bestDps) .. "  /  " .. Util.shortNum(d.worstDps) }
        end
        if d.bestHps then lines[#lines + 1] = { left = "Your best HPS", right = Util.shortNum(d.bestHps) } end
    end
    if d.topMate then
        lines[#lines + 1] = { sep = true }
        local cc = d.topMate.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.topMate.classFile]
        lines[#lines + 1] = { left = "Most run with",
            right = d.topMate.name .. "  (x" .. d.topMate.n .. ")",
            rcolor = cc and { cc.r, cc.g, cc.b } or nil }
    end
    return { icon = mi and mi.texture, title = d.name or "Dungeon", lines = lines }
end

local function renderDungeons(b, C, x, y, w, win)
    y = renderSeasonSelector(b, C, x, y, w, win)
    local list = History.DungeonStats(scopeSeason())
    applySort(list, dungeonSort, {
        name = function(d) return nil end, runs = function(d) return d.totals.runs end,
        timed = function(d) return d.timedPct end, best = function(d) return d.highestTimed end,
        besttime = function(d) return d.bestTime and -d.bestTime end, avgtime = function(d) return d.avgTime and -d.avgTime end,
        avgd = function(d) return d.avgDeaths end,
    }, function(a, bb) return (a.name or "") < (bb.name or "") end)
    local rowW = w - 12
    b:Sub(string.format("DUNGEONS (%d)", #list), x, y); y = y - 26
    if #list == 0 then b:Wrap("No dungeon data yet.", x, y, w - 20, C.subtext, 12); return y - 30 end
    local first, last = pagerBar(b, C, x, y, rowW, #list, "dungeons", win); y = y - 42
    b:Box(x, y + 4, rowW, 24, 0.12, 0, C.accent)
    sortHdr(b, C, x + 34, y - 2, 90, "Dungeon", "name", dungeonSort, win)
    sortHdr(b, C, x + 300, y - 2, 40, "Runs", "runs", dungeonSort, win)
    sortHdr(b, C, x + 360, y - 2, 56, "Timed%", "timed", dungeonSort, win)
    sortHdr(b, C, x + 430, y - 2, 50, "Best +", "best", dungeonSort, win)
    sortHdr(b, C, x + 500, y - 2, 70, "Best Time", "besttime", dungeonSort, win)
    sortHdr(b, C, x + 590, y - 2, 68, "Avg Time", "avgtime", dungeonSort, win)
    b:Tex(x + 688, y - 4, 14, 14, "skull", nil, { 0.7, 0.72, 0.8 })
    b:Hit(x + 684, y + 3, 26, 20, function()
        if dungeonSort.key == "avgd" then dungeonSort.dir = dungeonSort.dir == "desc" and "asc" or "desc"
        else dungeonSort.key = "avgd"; dungeonSort.dir = "desc" end
        win:Refresh()
    end, "Avg deaths", "Sort by average deaths.")
    y = y - 26
    for i = first, last do
        local d = list[i]
        local h = 28
        local yTop = y
        b:Row(x, yTop, rowW, h, { index = i, tipData = dungeonTipData(d),
            onClick = function() view.detailDungeon = d.mapId; win:Refresh() end })
        dungeonGlyph(b, x + 6, yTop - 5, 20, d.mapId)
        b:Label(d.name or DASH, x + 34, yTop - 9, C.text, 12)
        b:Label(tostring(d.totals.runs), x + 300, yTop - 9, C.text, 11)
        b:Label(d.timedPct and Util.percent(d.timedPct) or DASH, x + 360, yTop - 9, C.text, 11)
        b:Label(d.highestTimed and ("+" .. d.highestTimed) or DASH, x + 430, yTop - 9, C.accent, 12)
        b:Label(Util.duration(d.bestTime), x + 500, yTop - 9, C.text, 11)
        b:Label(Util.duration(d.avgTime), x + 590, yTop - 9, C.subtext, 11)
        b:Label(d.avgDeaths and string.format("%.1f", d.avgDeaths) or DASH, x + 688, yTop - 9, C.text, 11)
        y = yTop - h - 2
    end
    y = y - 6
    pagerBar(b, C, x, y, rowW, #list, "dungeons", win)
    return y - 28
end

----------------------------------------------------------------------
-- Characters.
----------------------------------------------------------------------
-- Rich character tooltip: headline totals plus a per-spec breakdown (the character record
-- tracks every run, so we can split it by the spec played each run).
local function charTipData(c)
    local classLoc = c.classFile and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.classFile]) or c.classFile)
    local tp = History.timedPct(c.totals)
    local avgK = Util.safeDiv(c.levelSum, c.levelN)
    local lines = {
        { left = "Class", right = classLoc or "-" },
        { left = "Runs", right = tostring(c.totals.runs), rcolor = "accent" },
        { left = "Timed", right = tp and Util.percent(tp) or "-", rcolor = STATUS_HEX.TIMED },
        { left = "Highest timed", right = c.highestTimed and ("+" .. c.highestTimed) or "-", rcolor = "accent" },
        { left = "Avg key", right = avgK and string.format("+%.1f", avgK) or "-" },
        { left = "Last seen", right = Util.dateShort(c.lastSeenAt) },
    }
    local specs = History.CharacterSpecBreakdown(c.fullName)
    if #specs > 0 then
        lines[#lines + 1] = { sep = true }
        lines[#lines + 1] = { text = "By spec", color = "subtext" }
        for _, sp in ipairs(specs) do
            local nm = sp.specName or specName(sp.specId) or (sp.role and (ML.ROLE_LABEL[sp.role] or sp.role)) or "Unknown"
            local right = string.format("%d run", sp.totals.runs) .. (sp.totals.runs == 1 and "" or "s")
            if sp.avgLevel then right = right .. "  ·  +" .. string.format("%.1f", sp.avgLevel) .. " avg" end
            lines[#lines + 1] = { left = "  " .. nm, right = right }
        end
    end
    lines[#lines + 1] = { blank = true }
    lines[#lines + 1] = { text = "Click to open this character.", color = "subtext" }
    return { title = c.fullName or c.name or "Character", lines = lines }
end

local function renderCharacters(b, C, x, y, w, win)
    local list = History.CharacterList()
    applySort(list, charSort, {
        name = function(c) return nil end, runs = function(c) return c.totals.runs end,
        timed = function(c) return History.timedPct(c.totals) end, high = function(c) return c.highestTimed end,
        avgkey = function(c) return Util.safeDiv(c.levelSum, c.levelN) end, last = function(c) return c.lastSeenAt end,
    }, function(a, bb) return (a.fullName or "") < (bb.fullName or "") end)
    local rowW = w - 12
    b:Sub(string.format("CHARACTERS (%d)", #list), x, y); y = y - 26
    if #list == 0 then b:Wrap("No characters yet.", x, y, w - 20, C.subtext, 12); return y - 30 end
    local first, last = pagerBar(b, C, x, y, rowW, #list, "characters", win); y = y - 42
    b:Box(x, y + 4, rowW, 24, 0.12, 0, C.accent)
    sortHdr(b, C, x + 34, y - 2, 90, "Character", "name", charSort, win)
    sortHdr(b, C, x + 300, y - 2, 40, "Runs", "runs", charSort, win)
    sortHdr(b, C, x + 360, y - 2, 56, "Timed%", "timed", charSort, win)
    sortHdr(b, C, x + 440, y - 2, 50, "High +", "high", charSort, win)
    sortHdr(b, C, x + 510, y - 2, 62, "Avg Key", "avgkey", charSort, win)
    sortHdr(b, C, x + 600, y - 2, 70, "Last Seen", "last", charSort, win)
    y = y - 26
    for i = first, last do
        local c = list[i]
        local h = 28
        local yTop = y
        b:Row(x, yTop, rowW, h, { index = i, tipData = charTipData(c),
            onClick = function() view.detailCharacter = c.fullName or c.key; win:Refresh() end })
        classGlyph(b, x + 6, yTop - 5, 20, c.classFile)
        b:Label(classColorText(c.classFile, c.fullName or c.name or "?"), x + 34, yTop - 9, C.text, 12)
        b:Label(tostring(c.totals.runs), x + 300, yTop - 9, C.text, 11)
        b:Label(History.timedPct(c.totals) and Util.percent(History.timedPct(c.totals)) or DASH, x + 360, yTop - 9, C.text, 11)
        b:Label(c.highestTimed and ("+" .. c.highestTimed) or DASH, x + 440, yTop - 9, C.accent, 12)
        local avgK = Util.safeDiv(c.levelSum, c.levelN)
        b:Label(avgK and string.format("+%.1f", avgK) or DASH, x + 510, yTop - 9, C.text, 11)
        b:Label(Util.dateShort(c.lastSeenAt), x + 600, yTop - 9, C.subtext, 11)
        y = yTop - h - 2
    end
    y = y - 6
    pagerBar(b, C, x, y, rowW, #list, "characters", win)
    return y - 28
end

----------------------------------------------------------------------
-- Players browser.
----------------------------------------------------------------------
local function filteredPlayers()
    local list = {}
    local search = (playerFilter.search or ""):lower()
    for _, p in ipairs(History.PlayerList()) do
        local ok = true
        if (p.totals.runs or 0) < (playerFilter.minShared or 1) then ok = false end
        if ok and playerFilter.role and p.lastKnownRole ~= playerFilter.role then ok = false end
        if ok and playerFilter.favorite and not p.favorite then ok = false end
        if ok and search ~= "" then
            local hay = ((p.fullName or "") .. " " .. (p.name or "") .. " " .. (p.realm or "")):lower()
            if not hay:find(search, 1, true) then ok = false end
        end
        if ok then list[#list + 1] = p end
    end
    local key, desc = playerSort.key, (playerSort.dir == "desc")
    table.sort(list, function(a, bb)
        if key == "name" or key == "spec" then
            local an = (key == "name" and (a.fullName or "") or (specName(a.lastKnownSpecId) or "")):lower()
            local bn = (key == "name" and (bb.fullName or "") or (specName(bb.lastKnownSpecId) or "")):lower()
            if desc then return an > bn else return an < bn end
        end
        local av, bv
        if key == "timed" then av, bv = (History.timedPct(a.totals) or 0), (History.timedPct(bb.totals) or 0)
        elseif key == "high" then av, bv = (a.highestTimed or 0), (bb.highestTimed or 0)
        elseif key == "last" then av, bv = (a.lastSeenAt or 0), (bb.lastSeenAt or 0)
        else av, bv = (a.totals.runs or 0), (bb.totals.runs or 0) end
        if av == bv then return (a.fullName or "") < (bb.fullName or "") end
        if desc then return av > bv else return av < bv end
    end)
    return list
end

local function renderPlayers(b, C, x, y, w, win)
    -- Controls.
    b:Label("Search", x, y - 2, C.subtext)
    T(b, b:EditBox(x + 56, y, 160, playerFilter.search or "", function(t) playerFilter.search = t; win:Refresh() end),
        "Search", "Filter by player name or realm.")
    b:Label("Role", x + 234, y - 2, C.subtext)
    T(b, b:Dropdown(x + 274, y), "Role filter", "Show only players last seen in this role."):SetChoices(110, {
        { "all", "All" }, { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "DPS" },
    }, function() return playerFilter.role or "all" end,
       function(v) playerFilter.role = (v ~= "all") and v or nil; win:Refresh() end)
    T(b, b:Toggle(x + 400, y - 1, playerFilter.favorite, function(v) playerFilter.favorite = v; win:Refresh() end),
        "Favorites only", "Show only players you've marked as favorite.")
    b:Label("Favorites", x + 448, y - 2, C.text)
    y = y - 34

    local list = filteredPlayers()
    local rowW = w - 12
    b:Sub(string.format("PLAYERS (%d)", #list), x, y); y = y - 26
    if #list == 0 then
        b:Wrap("No one to show yet. As you run keys, the people you group with are remembered here.",
            x, y, w - 20, C.subtext, 12)
        return y - 30
    end
    local first, last = pagerBar(b, C, x, y, rowW, #list, "players", win); y = y - 42
    b:Box(x, y + 4, rowW, 24, 0.12, 0, C.accent)
    sortHdr(b, C, x + 52, y - 2, 90, "Player", "name", playerSort, win)
    sortHdr(b, C, x + 250, y - 2, 80, "Spec", "spec", playerSort, win)
    sortHdr(b, C, x + 380, y - 2, 40, "Runs", "runs", playerSort, win)
    sortHdr(b, C, x + 430, y - 2, 56, "Timed%", "timed", playerSort, win)
    sortHdr(b, C, x + 500, y - 2, 50, "High +", "high", playerSort, win)
    sortHdr(b, C, x + 570, y - 2, 70, "Last Seen", "last", playerSort, win)
    y = y - 26
    for i = first, last do
        local p = list[i]
        local h = 30
        local yTop = y
        local sName = specName(p.lastKnownSpecId)
        local classLoc = p.classFile and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.classFile]) or p.classFile)
        local tipLines = {
            { left = "Spec", right = (sName and classLoc) and (sName .. " " .. classLoc) or (classLoc or "Unknown") },
            { left = "Role", right = ML.ROLE_LABEL[p.lastKnownRole] or "-" },
            (p.guildName and { left = "Guild", right = p.guildName }) or { blank = true },
            { sep = true },
            { left = "Runs together", right = tostring(p.totals.runs), rcolor = "accent" },
            { left = "Timed", right = History.timedPct(p.totals) and Util.percent(History.timedPct(p.totals)) or "-" },
            { left = "Highest timed", right = p.highestTimed and ("+" .. p.highestTimed) or "-", rcolor = "accent" },
            { left = "Last seen", right = Util.dateShort(p.lastSeenAt) },
        }
        -- Show the player's saved note, if any, wrapped in quotes on its own line.
        if p.notes and p.notes ~= "" then
            tipLines[#tipLines + 1] = { sep = true }
            tipLines[#tipLines + 1] = { text = "\"" .. p.notes .. "\"", color = "e6cc80" }
        end
        tipLines[#tipLines + 1] = { blank = true }
        tipLines[#tipLines + 1] = { text = "Click to open their history.", color = "subtext" }
        b:Row(x, yTop, rowW, h, { index = i,
            tipData = { icon = specIconID(p.lastKnownSpecId), title = p.fullName or p.name, lines = tipLines },
            onClick = function() view.detailPlayer = p.identityKey; win:Refresh() end })
        classGlyph(b, x + 6, yTop - 6, 20, p.classFile)
        specGlyph(b, x + 28, yTop - 6, 20, p.lastKnownSpecId, p.lastKnownSpecIcon)
        local star = p.favorite and "|cffffd200*|r " or ""
        b:Label(star .. classColorText(p.classFile, p.fullName or p.name or "?"), x + 52, yTop - 10, C.text, 12)
        b:Label(sName or DASH, x + 250, yTop - 10, C.subtext, 11)
        b:Label(tostring(p.totals.runs), x + 380, yTop - 10, C.text, 11)
        b:Label(History.timedPct(p.totals) and Util.percent(History.timedPct(p.totals)) or DASH, x + 430, yTop - 10, C.text, 11)
        b:Label(p.highestTimed and ("+" .. p.highestTimed) or DASH, x + 500, yTop - 10, C.accent, 12)
        b:Label(Util.dateShort(p.lastSeenAt), x + 570, yTop - 10, C.subtext, 11)
        y = yTop - h - 2
    end
    y = y - 6
    pagerBar(b, C, x, y, rowW, #list, "players", win)
    return y - 28
end

----------------------------------------------------------------------
-- Player details.
----------------------------------------------------------------------
local function renderPlayerDetails(b, C, x, y, w, win)
    local p = History.PlayerSummary(view.detailPlayer)
    if not p then view.detailPlayer = nil; return y end
    T(b, b:Button(x + w - 84, y, 72, "Back", "default", function() view.detailPlayer = nil; win:Refresh() end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the previous page.")
    b:Heading(p.fullName or p.name or "Player", x, y, "h2"); y = y - 34
    b:Label(specClassLabel(p.classFile, p.lastKnownSpecId), x, y - 2, C.text, 12)
    if p.guildName then b:Label("<" .. p.guildName .. ">", x + 220, y - 2, C.subtext, 11) end
    T(b, b:Toggle(x + 360, y - 1, p.favorite, function(v) History.SetPlayerFavorite(p.identityKey, v); win:Refresh() end),
        "Favorite", "Mark this player as a favorite for quick filtering.")
    b:Label("Favorite", x + 406, y - 2, C.text)
    y = y - 28

    local t = p.totals
    local function line(lbl, val) b:Label(lbl, x, y - 2, C.subtext); b:Label(val or DASH, x + 200, y - 2, C.text); y = y - 22 end
    b:Section("TOGETHER", x, y); y = y - 26
    line("Runs together", tostring(t.runs))
    line("Completed / Timed", string.format("%d / %d", t.completed, t.timed))
    line("Depleted / Abandoned", string.format("%d / %d", t.depleted, t.abandoned))
    line("Timed %", History.timedPct(t) and Util.percent(History.timedPct(t)) or DASH)
    line("Highest timed", p.highestTimed and ("+" .. p.highestTimed) or DASH)
    line("Average key", Util.safeDiv(p.levelSum, p.levelN) and string.format("+%.1f", Util.safeDiv(p.levelSum, p.levelN)) or DASH)
    line("First / Last seen", Util.dateShort(p.firstSeenAt) .. "  /  " .. Util.dateShort(p.lastSeenAt))

    -- Per-role averages (kept separate so we never blend roles).
    b:Section("AVERAGES BY ROLE", x, y); y = y - 26
    for _, role in ipairs(ML.ROLES) do
        local rb = p.byRole[role]
        if rb and rb.totals.runs > 0 then
            b:Label(ML.ROLE_LABEL[role] .. string.format(" (%d)", rb.totals.runs), x, y - 2, C.accent, 11)
            local parts = {}
            local function add(lbl, v, fmt) if v ~= nil then parts[#parts + 1] = lbl .. ": " .. (fmt and fmt(v) or Util.shortNum(v)) end end
            if role == "HEALER" then
                add("HPS", History.avgOf(rb.stats, "hps"))
                add("Dispels", History.avgOf(rb.stats, "dispels"), function(v) return string.format("%.0f", v) end)
            else
                add("DPS", History.avgOf(rb.stats, "dps"))
                add("Interrupts", History.avgOf(rb.stats, "interrupts"), function(v) return string.format("%.0f", v) end)
            end
            add("Dmg taken", History.avgOf(rb.stats, "damageTaken"))
            add("Deaths", History.avgOf(rb.stats, "deaths"), function(v) return string.format("%.1f", v) end)
            b:Label(#parts > 0 and table.concat(parts, "   ") or "No stats recorded", x + 90, y - 2, C.text, 11)
            y = y - 22
        end
    end

    -- Notes.
    b:Section("NOTES", x, y); y = y - 26
    T(b, b:EditBox(x, y, w - 40, p.notes or "", function(t2) History.SetPlayerNote(p.identityKey, t2) end),
        "Player notes", "Private notes about this player. Never shown in recaps unless you opt in.")
    y = y - 32
    T(b, b:Button(x, y, 160, "View Runs Together", "primary", function()
        runFilter.playerKey = p.identityKey; view.detailPlayer = nil; view.tab = "runs"; win:Refresh()
    end), "View runs together", "Open the run list filtered to just the keys you did with this player.")
    T(b, b:Button(x + 170, y, 130, "Export Player", "default", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.ShowCopyDialog then theme:ShowCopyDialog("Export player", ML.Export.ExportPlayer(p.identityKey) or "") end
    end, { icon = "upload", iconSize = 13 }), "Export player", "Copy this player's shared history as a string.")
    return y - 34
end

----------------------------------------------------------------------
-- Personal bests.
----------------------------------------------------------------------
-- Resolve the stats-filter season control to a season id (nil = all).
local function statsSeason()
    if statsFilter.season == "all" then return nil end
    if statsFilter.season == "current" then return currentSeason() end
    return statsFilter.season
end

-- Best/worst over a filtered run set, using only the player's own stats and gating DPS/HPS by the
-- role played that run (so we never compare a tank's dps to a real dps, or blend roles).
local function computeStatBoard(runs)
    local st = {}
    local function rank(field, val, cmp, ctx)
        if type(val) ~= "number" then return end
        if not st[field] or cmp(val, st[field].v) then st[field] = { v = val, ctx = ctx } end
    end
    local gt = function(a, bb) return a > bb end
    local lt = function(a, bb) return a < bb end
    for _, r in ipairs(runs) do
        local ps = r.playerStats or {}
        local role = r.character and r.character.role
        local ctx = { dungeon = r.dungeonName, level = r.level }
        if r.status == STATUS.TIMED then
            if type(r.level) == "number" then rank("highTimed", r.level, gt, ctx) end
            if type(r.duration) == "number" then rank("fastTimed", r.duration, lt, ctx) end
        end
        if r.status ~= STATUS.ABANDONED then
            if role == "DAMAGER" then rank("highDps", ps.dps, gt, ctx); rank("lowDps", ps.dps, lt, ctx) end
            if role == "HEALER" then rank("highHps", ps.hps, gt, ctx); rank("lowHps", ps.hps, lt, ctx) end
            rank("mostInt", ps.interrupts, gt, ctx); rank("lowInt", ps.interrupts, lt, ctx)
            rank("mostDsp", ps.dispels, gt, ctx)
            if type(r.deaths) == "number" then rank("lowDeaths", r.deaths, lt, ctx); rank("mostDeaths", r.deaths, gt, ctx) end
        end
    end
    return st
end

local function renderBests(b, C, x, y, w, win)
    -- Filter toolbar (clean, admin-style: labelled form groups in a bordered panel).
    local charChoices = { { "all", "All characters" } }
    for _, c in ipairs(History.CharacterList()) do
        local nm = (c.name and c.name ~= "?" and c.name) or c.fullName or "Unknown"
        charChoices[#charChoices + 1] = { c.fullName, nm }
    end
    local dunChoices, seenD = { { "all", "All dungeons" } }, {}
    for _, r in ipairs(DB.Runs()) do
        if r.mapId and not seenD[r.mapId] then
            seenD[r.mapId] = true
            dunChoices[#dunChoices + 1] = { r.mapId, r.dungeonName or ("Map " .. r.mapId) }
        end
    end
    y = filterBar(b, C, x, y, w, {
        { label = "Season", build = function(fx, cy, cw)
            T(b, b:Dropdown(fx, cy), "Season", "Limit stats to a season."):SetChoices(cw, seasonChoices(),
                function() return statsFilter.season end, function(v) statsFilter.season = v; win:Refresh() end)
        end },
        { label = "Character", build = function(fx, cy, cw)
            T(b, b:Dropdown(fx, cy), "Character", "Limit stats to one character."):SetChoices(cw, charChoices,
                function() return statsFilter.character or "all" end,
                function(v) statsFilter.character = (v ~= "all") and v or nil; win:Refresh() end)
        end },
        { label = "Dungeon", build = function(fx, cy, cw)
            T(b, b:Dropdown(fx, cy), "Dungeon", "Limit stats to one dungeon."):SetChoices(cw, dunChoices,
                function() return statsFilter.mapId or "all" end,
                function(v) statsFilter.mapId = (v ~= "all") and v or nil; win:Refresh() end)
        end },
        { label = "Min key   " .. ((statsFilter.minKey or 0) > 0 and ("+" .. statsFilter.minKey) or "Any"), build = function(fx, cy, cw)
            local sl = T(b, b:Slider(fx, cy - 9), "Minimum key level",
                "Only count runs at or above this key level.")
            sl:Configure(cw, 0, 20, 1, function() return statsFilter.minKey or 0 end,
                function(v) statsFilter.minKey = v; scheduleRefresh(win) end, "+%d")
            sl:ApplyStyle({ hideValue = true })   -- value lives in the label, not a floating readout
        end },
    })

    local runs = History.FilterRuns({ seasonId = statsSeason(), character = statsFilter.character,
        mapId = statsFilter.mapId, keyMin = (statsFilter.minKey or 0) > 0 and statsFilter.minKey or nil })
    local st = computeStatBoard(runs)

    local function row(lbl, e, fmt, color)
        b:Label(lbl, x, y - 2, C.subtext, 11)
        local val = e and (fmt and fmt(e.v) or tostring(e.v)) or DASH
        b:Label(val, x + 200, y - 2, color or C.text, 12)
        if e and e.ctx then b:Label((e.ctx.dungeon or "") .. (e.ctx.level and ("  +" .. e.ctx.level) or ""), x + 320, y - 2, C.subtext, 10) end
        y = y - 22
    end
    local dur = function(v) return Util.duration(v) end
    local num = function(v) return Util.shortNum(v) end

    b:Section(string.format("PERSONAL BESTS  (%d run(s))", #runs), x, y); y = y - 28
    row("Highest timed key", st.highTimed, function(v) return "+" .. v end, C.accent)
    row("Fastest timed run", st.fastTimed, dur, C.accent)
    row("Highest DPS", st.highDps, num)
    row("Highest HPS", st.highHps, num)
    row("Most interrupts", st.mostInt)
    row("Most dispels", st.mostDsp)
    row("Fewest deaths (run)", st.lowDeaths)
    y = y - 8

    b:Section("NEEDS WORK", x, y); y = y - 28
    row("Most deaths (run)", st.mostDeaths, nil, { 0.95, 0.5, 0.45 })
    row("Lowest DPS", st.lowDps, num, { 0.95, 0.6, 0.45 })
    row("Lowest HPS", st.lowHps, num, { 0.95, 0.6, 0.45 })
    row("Fewest interrupts (run)", st.lowInt, nil, { 0.95, 0.6, 0.45 })
    return y - 8
end

----------------------------------------------------------------------
-- Settings.
----------------------------------------------------------------------
local function renderSettings(b, C, x, y, w, win)
    local s = DB.Settings()
    local rc = s.recap
    -- Toggle row: switch + label, always with a hover tooltip.
    local function toggle(lbl, get, set, tip)
        local tg = b:Toggle(x, y, get() and true or false, function(v) set(v); win:Refresh() end)
        b.theme:SetTip(tg, lbl, tip or lbl)
        b:Label(lbl, x + 46, y - 2, C.text); y = y - 30
    end
    -- Slider row: reserves headroom above the thumb for the value readout (v-padding), like the
    -- other modules, so the readout can't clip the control above it.
    local function slider(lbl, ctlX, sw, minv, maxv, step, fmt, get, set, tip)
        y = y - 12
        b:Label(lbl, x, y - 2, C.subtext)
        T(b, b:Slider(x + ctlX, y), lbl, tip):Configure(sw, minv, maxv, step, get, set, fmt)
        y = y - 26
    end

    b:Sub("OVERVIEW CARDS", x, y); y = y - 30
    b:Label("Card style", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Overview card style",
        "How the Overview summary cards look. Clean = flat dashboard tiles; Panel = darker WoW-style "
        .. "in-game tiles with a rank meter; Compact = data-rich cards with an extra footer line."):SetChoices(240, {
        { "CLEAN", "Clean (dashboard)" }, { "PANEL", "Panel (WoW tiles)" }, { "COMPACT", "Compact (data-rich)" },
    }, function() return s.cardStyle or "PANEL" end, function(v) s.cardStyle = v; win:Refresh() end)
    y = y - 36

    b:Sub("SCOREBOARD", x, y); y = y - 30
    slider("Scale", 90, 200, 0.5, 3.0, 0.05, "%.2fx",
        function() return s.scoreboardScale or 1.5 end, function(v) s.scoreboardScale = v end,
        "How big the end-of-run scoreboard opens (still capped to fit your screen). Also: /ledger scale <n>.")
    b:Label("Font", x, y - 2, C.subtext)
    b:FontSelect(x + 90, y, { width = 220, value = (s.scoreboardFont ~= "" and s.scoreboardFont) or "UBUNTU",
        onChange = function(key) s.scoreboardFont = key end })
    T(b, b:Button(x + 320, y, 130, "Use UI font", "default", function() s.scoreboardFont = ""; win:Refresh() end),
        "Use UI font", "Reset the scoreboard to use the same font as the rest of the UI.")
    y = y - 40

    toggle("Play a sound when the scoreboard opens", function() return s.scoreboardSound end,
        function(v) s.scoreboardSound = v end,
        "Play a sound (default: FFVII Victory Fanfare) when the scoreboard appears.")
    if s.scoreboardSound then
        b:Label("Sound", x, y - 2, C.subtext)
        T(b, b:SoundSelect(x + 90, y, { width = 200, value = s.scoreboardSoundKey or "VictoryFanfare", channel = "Master",
            onChange = function(v) s.scoreboardSoundKey = v end }), "Scoreboard sound", "The sound played when the scoreboard opens.")
        T(b, b:Button(x + 300, y, 70, "Test", "default", function()
            local theme = _G.TAP and _G.TAP.uiTheme
            if theme and theme.PlaySound then theme:PlaySound(s.scoreboardSoundKey or "VictoryFanfare", "Master") end
        end, { icon = "volume", iconSize = 13 }), "Test sound", "Preview the selected scoreboard sound.")
        y = y - 34
        b:Label("Play sound", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 90, y), "When to play the scoreboard sound",
            "End of run only = just the automatic post-run popup; Every view = also when you re-open a "
            .. "scoreboard from history."):SetChoices(200, {
            { "END", "End of run only" }, { "ALWAYS", "Every time it's viewed" },
        }, function() return s.scoreboardSoundWhen or "END" end, function(v) s.scoreboardSoundWhen = v end)
        y = y - 36
    end

    b:Sub("TRACKING", x, y); y = y - 30
    toggle("Track abandoned runs", function() return s.trackAbandoned end, function(v) s.trackAbandoned = v end,
        "Save keys you leave or reset before completion (kept apart from your timed %).")
    toggle("Show post-run summary", function() return s.postRunSummary end, function(v) s.postRunSummary = v end,
        "Pop a summary modal after each completed key (queued until out of combat).")
    toggle("Confirm before saving a recovered abandoned run", function() return s.confirmAbandonSave end, function(v) s.confirmAbandonSave = v end,
        "After a reload/disconnect with an unfinished key, ask before saving it as abandoned.")

    b:Sub("RETURNING-PLAYER RECAP  (local only - never posted to group)", x, y); y = y - 30
    toggle("Show previous-player recaps", function() return rc.enabled end, function(v) rc.enabled = v end,
        "When you group with someone you've keyed with, print a short local-only reminder.")
    b:Label("Display", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Recap display", "Where recaps appear. Local chat is only visible to you."):SetChoices(160, {
        { "CHAT", "Local chat" }, { "TOAST", "Toast" }, { "BOTH", "Both" }, { "OFF", "Off" },
    }, function() return rc.display end, function(v) rc.display = v end)
    b:Label("Detail", x + 270, y - 2, C.subtext)
    T(b, b:Dropdown(x + 320, y), "Recap detail", "How much a recap shows."):SetChoices(140, {
        { "COMPACT", "Compact" }, { "DETAILED", "Detailed" }, { "OFF", "Off" },
    }, function() return rc.detail end, function(v) rc.detail = v end)
    y = y - 34
    b:Label("History", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Recap history", "Count shared runs from the current season only, or all seasons."):SetChoices(160, {
        { "SEASON", "Current season" }, { "ALL", "All seasons" },
    }, function() return rc.history end, function(v) rc.history = v end)
    b:Label("Fires on", x + 270, y - 2, C.subtext)
    T(b, b:Dropdown(x + 340, y), "Recap trigger",
        "When a recap fires. On join = as soon as a returning player is in your group; On ready check "
        .. "= only when a ready check starts; Both = either. (It never fires on zoning in/out.)"):SetChoices(150, {
        { "JOIN", "On join" }, { "READY", "On ready check" }, { "BOTH", "Both" },
    }, function() return rc.trigger or "JOIN" end, function(v) rc.trigger = v end)
    y = y - 34
    slider("Minimum shared runs", 200, 150, 1, 10, 1, "%d",
        function() return rc.minShared or 1 end, function(v) rc.minShared = v end,
        "Only recap someone once you've done at least this many keys together.")
    toggle("Include performance averages", function() return rc.includeAverages end, function(v) rc.includeAverages = v end,
        "Add role-relevant averages (e.g. DPS/HPS, deaths) to the recap line.")
    toggle("Include last-run result", function() return rc.includeLastResult end, function(v) rc.includeLastResult = v end,
        "Append the outcome of your most recent run with that player.")
    toggle("Include personal notes (off by default)", function() return rc.includeNotes end, function(v) rc.includeNotes = v end,
        "Your private notes are NEVER shown automatically unless you turn this on.")
    toggle("Play a sound when returning players are found", function() return rc.sound end, function(v) rc.sound = v; win:Refresh() end,
        "Play a sound once per group (a single sound even if several returning players are found).")
    if rc.sound then
        b:Label("Sound", x, y - 2, C.subtext)
        T(b, b:SoundSelect(x + 90, y, { width = 200, value = rc.soundKey or "Applause", channel = "Master",
            onChange = function(v) rc.soundKey = v end }), "Recap sound", "The sound played when a returning player is detected.")
        T(b, b:Button(x + 300, y, 70, "Test", "default", function()
            local theme = _G.TAP and _G.TAP.uiTheme
            if theme and theme.PlaySound then theme:PlaySound(rc.soundKey or "Applause", "Master") end
        end, { icon = "volume", iconSize = 13 }), "Test sound", "Preview the selected recap sound.")
        y = y - 32
    end
    T(b, b:Button(x, y, 190, "Preview for current group", "default", function() ML.Recap.PreviewCurrentGroup() end),
        "Preview recaps", "Print a sample recap for everyone in your current group (ignores the once-per-session guard).")
    y = y - 40

    b:Sub("DATA", x, y); y = y - 30
    -- Retention: the slider only STAGES a cap; nothing is trimmed until Apply is clicked, so you
    -- can't accidentally destroy runs while dragging. Retention still auto-applies as new runs save.
    if retentionPending == nil then retentionPending = s.retentionRuns or 0 end
    local applied = s.retentionRuns or 0
    y = y - 12
    b:Label("Keep newest runs (0 = all)", x, y - 2, C.subtext)
    T(b, b:Slider(x + 200, y), "Keep newest runs",
        "Cap stored runs to the newest N (0 = keep everything). Your best run per dungeon (crown) and "
        .. "your top 10 runs are always protected - only ordinary runs are dropped. Click Apply to commit.")
        :Configure(170, 0, 1000, 25, function() return retentionPending end, function(v) retentionPending = v end, "%d")
    local dirty = (retentionPending ~= applied)
    T(b, b:Button(x + 400, y, 90, "Apply", dirty and "primary" or "default", function()
        s.retentionRuns = retentionPending
        DB.ApplyRetention()
        win:Refresh()
    end), "Apply retention", "Commit the retention cap and trim now. Runs are never trimmed until you click this.")
    y = y - 26
    b:Label(dirty and string.format("Currently applied: %d  (staged: %d - not yet applied)", applied, retentionPending)
        or string.format("Currently applied: %d", applied), x, y - 2,
        dirty and b.theme:Color("e0a030", C.subtext) or C.subtext, 11)
    y = y - 24
    toggle("Debug logging", function() return s.debug end, function(v) s.debug = v; ML._debugEcho = v end,
        "Echo internal diagnostics to chat and the Debug page.")
    T(b, b:Button(x, y, 140, "Export All", "default", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.ShowCopyDialog then theme:ShowCopyDialog("Export entire ledger", ML.Export.ExportAll() or "") end
    end, { icon = "upload", iconSize = 13 }), "Export all", "Copy your whole ledger as a backup/share string.")
    T(b, b:Button(x + 150, y, 140, "Import", "default", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.ShowInputDialog then
            theme:ShowInputDialog("Import ledger data", "Paste an exported string. Runs are ADDED (duplicates skipped).",
                "Import", function(txt)
                    local ok, res = ML.Export.Import(txt)
                    if ok then ML.Print("Imported %d run(s).", res); win:Refresh()
                    else return "Import failed: " .. tostring(res) end
                end)
        end
    end, { icon = "download", iconSize = 13 }), "Import", "Add runs from an exported string (duplicates are skipped).")
    T(b, b:Button(x + 300, y, 160, "Delete All History", "danger", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        theme:Confirm({ title = "Delete ALL history?", variant = "danger", confirmLabel = "Delete everything",
            message = "This permanently erases every recorded run and summary. Notes/tags are kept. This can't be undone.",
            onConfirm = function() DB.WipeHistory(); win:Refresh() end })
    end, { icon = "trash", iconSize = 13 }), "Delete all", "Permanently erase every recorded run. Notes/tags are kept.")
    return y - 40
end

----------------------------------------------------------------------
-- Debug.
----------------------------------------------------------------------
local function diagnosticText()
    local lines = {}
    local function p(s) lines[#lines + 1] = s end
    p("== Mythic Ledger diagnostics ==")
    p("Schema: v" .. tostring(DB.root and DB.root.schemaVersion) .. "  Runs: " .. #DB.Runs())
    p("Tracker state: " .. ML.Tracker.GetState())
    local cur = ML.Tracker.Current()
    p("Active run: " .. (cur and (tostring(cur.dungeonName) .. " +" .. tostring(cur.level)) or "none"))
    p("Recovery record: " .. (DB.ActiveRun() and "present" or "none"))
    for _, prov in ipairs(ML.Providers.Describe()) do
        p(string.format("Provider %s: %s%s", prov.name, prov.available and "available" or "unavailable",
            prov.version and (" v" .. prov.version) or ""))
    end
    p("Current season: " .. tostring(currentSeason()))
    p("Active map: " .. tostring(API.GetActiveMapID()))
    p("Characters: " .. Util.count(DB.Characters()) .. "  Players: " .. Util.count(DB.PlayerIndex()))
    p("API errors logged: " .. tostring(ML._apiErrors or 0))
    return table.concat(lines, "\n")
end

-- The full recent-activity log (all buffered entries), as a copyable block.
local function logText()
    local log = ML._log or {}
    if #log == 0 then return "== Mythic Ledger log ==\n(empty)" end
    local out = { "== Mythic Ledger log (" .. #log .. " entries) ==" }
    for i = 1, #log do
        out[#out + 1] = date("%Y-%m-%d %H:%M:%S", log[i].t) .. "  " .. tostring(log[i].msg)
    end
    return table.concat(out, "\n")
end

local function renderDebug(b, C, x, y, w, win)
    b:Sub("DIAGNOSTICS", x, y); y = y - 28
    local _, hh = b:Wrap(diagnosticText(), x, y, w - 20, C.text, 11)
    y = y - (hh + 10)
    T(b, b:Button(x, y, 150, "Copy diagnostics", "default", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.ShowCopyDialog then theme:ShowCopyDialog("Mythic Ledger diagnostics", diagnosticText()) end
    end, { icon = "clipboard", iconSize = 13 }), "Copy diagnostics", "Copy this diagnostic summary for a bug report.")
    T(b, b:Button(x + 160, y, 150, "Rebuild caches", "default", function()
        History.RebuildAll(); win:Refresh()
    end, { icon = "refresh", iconSize = 13 }), "Rebuild caches", "Recompute all summaries from the raw run records.")
    T(b, b:Button(x + 320, y, 150, "API self-check", "default", function()
        local txt = ML.Diag.Run()
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.ShowCopyDialog then theme:ShowCopyDialog("Mythic Ledger API self-check", txt) end
    end, { icon = "list-check", iconSize = 13 }), "API self-check",
        "Probe every live API the module uses (safe on a target dummy - validates the stat pipeline without a key).")
    y = y - 34
    T(b, b:Button(x, y, 200, "Rescore all runs", "default", function()
        if ML.Scoring and ML.Scoring.RescoreAll then
            local n = ML.Scoring.RescoreAll()
            ML.Print("Rescored %d run(s) at scoring v%d.", n or 0, (ML.Scoring.Config and ML.Scoring.Config.version) or 0)
            win:Refresh()
        end
    end, { icon = "award", iconSize = 13 }), "Rescore all runs",
        "Recompute every saved run's performance score with the current scoring logic (retroactive; "
        .. "runs automatically at login when the scoring version changes).")
    y = y - 36
    b:Sub("RECENT LOG", x, y)
    T(b, b:Button(x + w - 128, y + 3, 120, "Copy log", "default", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.ShowCopyDialog then theme:ShowCopyDialog("Mythic Ledger log", logText()) end
    end, { icon = "clipboard", iconSize = 12, height = 20 }), "Copy log", "Copy the full recent activity log for a bug report.")
    y = y - 26
    local log = ML._log or {}
    for i = #log, math.max(1, #log - 18), -1 do
        b:Label(date("%H:%M:%S", log[i].t) .. "  " .. log[i].msg, x, y - 2, C.subtext, 10)
        y = y - 16
    end
    return y - 8
end

----------------------------------------------------------------------
-- Dungeon details (click a dungeon row): a very large portal icon + headline stats, a Top Runs
-- box, then an All Runs box (paginated).
----------------------------------------------------------------------
-- One compact run row, clickable through to the full run details.
local function dungeonRunRow(b, C, x, yTop, rowW, r, i, win)
    local role = r.character and r.character.role
    b:Row(x, yTop, rowW, 26, { index = i, tipData = runTipData(r),
        onClick = function() view.detailRun = r.id; win:Refresh() end })
    b:Label(Util.dateShort(r.completedAt), x + 10, yTop - 9, C.subtext, 11)
    b:Label(classColorText(r.character and r.character.classFile, r.character and r.character.name or "?"),
        x + 100, yTop - 9, C.text, 11)
    if r.pinned then b:Tex(x + 236, yTop - 9, 12, 12, "crown", nil, { 1, 0.82, 0.2 }) end
    b:Label(Util.keyLabel(r.level), x + 252, yTop - 9, C.accent, 12)
    b:Badge(x + 294, yTop - 8, { text = statusText(r.status), variant = statusBadgeVariant(r.status) })
    b:Label(Util.duration(r.duration), x + 386, yTop - 9, C.text, 11)
    b:Label(Util.numOr(r.deaths, "%d"), x + 460, yTop - 9, C.text, 11)
    b:Label(primaryMetric(role, r.playerStats), x + 508, yTop - 9, C.text, 11)
end

-- Rich tooltip for a boss row: pulls / kills / wipes / kill rate / deaths, kill-time and your DPS spread.
local function bossTipData(bo)
    local killRate = (bo.engaged > 0) and math.floor(bo.kills / bo.engaged * 100 + 0.5) or 0
    local lines = {
        { left = "Pulls", right = tostring(bo.engaged) },
        { left = "Kills / Wipes", right = string.format("%d / %d", bo.kills, bo.wipes) },
        { left = "Kill rate", right = killRate .. "%" },
        { left = "Party deaths", right = tostring(bo.deaths), rcolor = bo.deaths > 0 and "e0a030" or nil },
        { sep = true },
        { left = "Best kill time", right = bo.bestTime and Util.duration(bo.bestTime) or DASH },
        { left = "Avg kill time", right = bo.avgTime and Util.duration(bo.avgTime) or DASH },
    }
    if bo.dpsN and bo.dpsN > 0 then
        lines[#lines + 1] = { sep = true }
        lines[#lines + 1] = { left = "Your DPS - best", right = Util.shortNum(bo.bestDps), rcolor = "33dd66" }
        lines[#lines + 1] = { left = "Your DPS - avg",  right = Util.shortNum(bo.avgDps) }
        lines[#lines + 1] = { left = "Your DPS - low",  right = Util.shortNum(bo.lowDps), rcolor = "e0a030" }
    else
        lines[#lines + 1] = { blank = true }
        lines[#lines + 1] = { text = "No per-boss DPS captured yet (needs Details! or Blizzard meter).", color = "subtext" }
    end
    return { title = bo.name or "Boss", lines = lines }
end

local function renderDungeonDetails(b, C, x, y, w, win)
    local mapId = view.detailDungeon
    local mi = API.GetMapInfo(mapId) or {}
    local rowW = w - 12
    local rows = History.FilterRuns({ mapId = mapId, seasonId = scopeSeason() })

    T(b, b:Button(x + w - 84, y, 72, "Back", "default", function() view.detailDungeon = nil; win:Refresh() end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the dungeons list.")

    -- Very large portal icon + name + headline stats.
    if mi.texture then b:Tex(x, y - 4, 96, 96, mi.texture)
    else b:Tex(x, y - 4, 96, 96, "map", nil, { 0.55, 0.6, 0.72 }) end
    b:Heading(mi.name or ("Dungeon " .. tostring(mapId)), x + 112, y, "h1")

    local n, timed, bestKey, bestTime, tSum, tN, dSum, dN = #rows, 0, nil, nil, 0, 0, 0, 0
    for _, r in ipairs(rows) do
        if r.status == STATUS.TIMED then
            timed = timed + 1
            if type(r.level) == "number" and (not bestKey or r.level > bestKey) then bestKey = r.level end
            if type(r.duration) == "number" and (not bestTime or r.duration < bestTime) then bestTime = r.duration end
        end
        if type(r.duration) == "number" then tSum = tSum + r.duration; tN = tN + 1 end
        if type(r.deaths) == "number" then dSum = dSum + r.deaths; dN = dN + 1 end
    end
    local hy = y - 30
    local function stat(col, lbl, val, color)
        b:Label(lbl, x + 112 + col * 150, hy, C.subtext, 10)
        b:Label(val or DASH, x + 112 + col * 150, hy - 16, color and b.theme:Color(color, C.text) or C.text, 14)
    end
    stat(0, "RUNS", tostring(n))
    stat(1, "TIMED", (n > 0) and Util.percent(Util.safeDiv(timed, n)) or DASH, "accent")
    stat(2, "BEST KEY", bestKey and ("+" .. bestKey) or DASH, "accent")
    hy = hy - 40
    stat(0, "BEST TIME", Util.duration(bestTime))
    stat(1, "AVG TIME", Util.duration(Util.safeDiv(tSum, tN)))
    stat(2, "AVG DEATHS", dN > 0 and string.format("%.1f", dSum / dN) or DASH)
    y = y - 108

    -- BOSSES box: per-boss engagement + your DPS spread across every run of this dungeon.
    local bosses = History.DungeonBosses(mapId, scopeSeason())
    b:Section("BOSSES", x, y); y = y - 24
    if #bosses == 0 then
        b:Label("No boss encounters recorded here yet.", x + 4, y - 2, C.subtext, 11); y = y - 22
    else
        local cols = { { "BOSS", 10 }, { "PULLS", 170 }, { "KILLS", 214 }, { "WIPES", 258 },
                       { "DEATHS", 302 }, { "BEST", 354 }, { "AVG", 422 }, { "LOW", 490 } }
        for _, h in ipairs(cols) do b:Label(h[1], x + h[2], y - 2, C.subtext, 10) end
        y = y - 20
        b:Box(x, y + 6, rowW, #bosses * 26 + 6, 0.05, 0, C.accent)
        for i, bo in ipairs(bosses) do
            b:Row(x, y, rowW, 26, { index = i, tipData = bossTipData(bo) })
            local bIcon = API.BossIcon(bo.name, bo.id)
            if bIcon then framedIcon(b, x + 8, y - 4, 36, 18, bIcon) end   -- 2:1 (36x18), centered in the 26px row
            b:Label(bo.name or "?", x + (bIcon and 52 or 10), y - 9, C.text, 11)
            b:Label(tostring(bo.engaged), x + 170, y - 9, C.text, 11)
            b:Label(tostring(bo.kills), x + 214, y - 9, b.theme:Color("33dd66", C.text), 11)
            b:Label(tostring(bo.wipes), x + 258, y - 9, C.subtext, 11)
            b:Label(tostring(bo.deaths), x + 302, y - 9,
                (bo.deaths > 0) and b.theme:Color("e0a030", C.text) or C.subtext, 11)
            b:Label(bo.bestDps and Util.shortNum(bo.bestDps) or DASH, x + 354, y - 9, C.text, 11)
            b:Label(bo.avgDps and Util.shortNum(bo.avgDps) or DASH, x + 422, y - 9, C.text, 11)
            b:Label(bo.lowDps and Util.shortNum(bo.lowDps) or DASH, x + 490, y - 9, C.subtext, 11)
            y = y - 26
        end
    end
    y = y - 16

    -- TOP RUNS box (best timed: highest key, then fastest).
    local top = {}
    for _, r in ipairs(rows) do if r.status == STATUS.TIMED then top[#top + 1] = r end end
    table.sort(top, function(a, bb)
        if (a.level or 0) ~= (bb.level or 0) then return (a.level or 0) > (bb.level or 0) end
        return (a.duration or math.huge) < (bb.duration or math.huge)
    end)
    b:Section("TOP RUNS", x, y); y = y - 24
    if #top == 0 then
        b:Label("No timed runs here yet.", x + 4, y - 2, C.subtext, 11); y = y - 20
    else
        local count = math.min(5, #top)
        b:Box(x, y + 6, rowW, count * 28 + 6, 0.05, 0, C.accent)
        for i = 1, count do
            dungeonRunRow(b, C, x, y, rowW, top[i], i, win)
            y = y - 28
        end
    end
    y = y - 14

    -- ALL RUNS box (paginated).
    b:Section(string.format("ALL RUNS (%d)", n), x, y); y = y - 24
    if n == 0 then
        b:Label("No runs recorded for this dungeon.", x + 4, y - 2, C.subtext, 11); return y - 20
    end
    local first, last = pagerBar(b, C, x, y, rowW, n, "dungeonRuns", win); y = y - 42
    b:Box(x, y + 6, rowW, (last - first + 1) * 28 + 6, 0.03, 0, C.card)
    for i = first, last do
        dungeonRunRow(b, C, x, y, rowW, rows[i], i, win)
        y = y - 28
    end
    y = y - 4
    pagerBar(b, C, x, y, rowW, n, "dungeonRuns", win)
    return y - 30
end

----------------------------------------------------------------------
-- Character details (click a character row): the deep-dive for judging one toon - headline
-- stats, a per-SPEC comparison, a per-DUNGEON breakdown, and the character's runs.
----------------------------------------------------------------------
local function renderCharacterDetails(b, C, x, y, w, win)
    local key = view.detailCharacter
    local rowW = w - 12
    local d = History.CharacterDetail(key, scopeSeason())

    T(b, b:Button(x + w - 84, y, 72, "Back", "default", function() view.detailCharacter = nil; win:Refresh() end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the characters list.")

    -- Header: class crest + name + summary line.
    local classFile = d and d.classFile
    classGlyph(b, x, y - 6, 72, classFile)
    b:Heading(classColorText(classFile, key or "Character"), x + 88, y, "h1")
    local classLoc = classFile and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile) or "?"
    local nSpecs = (d and #d.specs) or 0
    b:Label(string.format("%s  -  %d spec%s played  -  last seen %s", classLoc, nSpecs, nSpecs == 1 and "" or "s",
        (d and Util.dateShort(d.lastSeenAt)) or DASH), x + 90, y - 26, C.subtext, 11)
    y = y - 84   -- clear the 72px crest before the season selector (avoids overlap)

    y = renderSeasonSelector(b, C, x, y, w, win)

    if not d or d.totals.runs == 0 then
        b:Wrap("No runs recorded for this character in the selected scope. Try 'All Seasons'.",
            x, y, w - 20, C.subtext, 12)
        return y - 30
    end

    -- Headline stat block (two rows of four).
    local function stat(col, rowY, lbl, val, color)
        local cx = x + col * 176
        b:Label(lbl, cx, rowY, C.subtext, 10)
        b:Label(val or DASH, cx, rowY - 16, color and b.theme:Color(color, C.text) or C.text, 15)
    end
    stat(0, y, "RUNS", tostring(d.totals.runs))
    stat(1, y, "TIMED", d.timedPct and Util.percent(d.timedPct) or DASH, "33dd66")
    stat(2, y, "HIGHEST", d.highestTimed and ("+" .. d.highestTimed) or DASH, "accent")
    stat(3, y, "AVG KEY", d.avgLevel and string.format("+%.1f", d.avgLevel) or DASH)
    y = y - 44
    stat(0, y, "AVG TIME", Util.duration(d.avgDuration))
    stat(1, y, "AVG DEATHS", d.avgDeaths and string.format("%.1f", d.avgDeaths) or DASH)
    stat(2, y, "BEST DPS", d.bestDps and Util.shortNum(d.bestDps) or DASH)
    stat(3, y, "BEST HPS", d.bestHps and Util.shortNum(d.bestHps) or DASH)
    y = y - 44

    -- Average performance score across this character's runs (from the scoring engine, memoised).
    local S = ML.Scoring
    if S and S.Store and S.Store.Summary and S.Score then
        local sum, cnt = 0, 0
        for _, rr in ipairs(History.FilterRuns({ character = key, seasonId = scopeSeason() })) do
            local g = rr.character and rr.character.guid
            local ms = g and S.Store.Summary(rr)[g]
            if ms and ms.overall then sum = sum + ms.overall; cnt = cnt + 1 end
        end
        if cnt > 0 then
            local avg = sum / cnt
            local grade = S.Score.Grade(avg)
            stat(0, y, "AVG SCORE", string.format("%s  (%d)", grade, math.floor(avg + 0.5)), "accent")
        else
            stat(0, y, "AVG SCORE", DASH)
        end
    end
    y = y - 50

    -- BY SPEC: compare how the toon performs on each spec played.
    b:Section("BY SPEC", x, y); y = y - 24
    b:Box(x, y + 4, rowW, 22, 0.12, 0, C.accent)
    hdr(b, C, x + 30, y - 2, "Spec"); hdr(b, C, x + 250, y - 2, "Runs")
    hdr(b, C, x + 306, y - 2, "Timed%"); hdr(b, C, x + 380, y - 2, "Avg Key")
    hdr(b, C, x + 452, y - 2, "High"); hdr(b, C, x + 516, y - 2, "DPS/HPS")
    hdr(b, C, x + 616, y - 2, "Deaths")
    y = y - 24
    for i, sp in ipairs(d.specs) do
        b:Row(x, y, rowW, 26, { index = i })
        local icon = specIconID(sp.specId)
        if icon then b:Tex(x + 6, y - 5, 18, 18, icon) end
        local nm = sp.specName or specName(sp.specId) or (sp.role and (ML.ROLE_LABEL[sp.role] or sp.role)) or "Unknown"
        b:Label(classColorText(classFile, nm), x + 30, y - 9, C.text, 12)
        b:Label(tostring(sp.totals.runs), x + 250, y - 9, C.text, 11)
        b:Label(sp.timedPct and Util.percent(sp.timedPct) or DASH, x + 306, y - 9, C.text, 11)
        b:Label(sp.avgLevel and string.format("+%.1f", sp.avgLevel) or DASH, x + 380, y - 9, C.text, 11)
        b:Label(sp.highestTimed and ("+" .. sp.highestTimed) or DASH, x + 452, y - 9, C.accent, 12)
        local perf = (sp.role == "HEALER") and (sp.avgHps and Util.shortNum(sp.avgHps))
            or (sp.avgDps and Util.shortNum(sp.avgDps)) or nil
        b:Label(perf or DASH, x + 516, y - 9, C.text, 11)
        b:Label(sp.avgDeaths and string.format("%.1f", sp.avgDeaths) or DASH, x + 616, y - 9, C.text, 11)
        y = y - 26
    end
    y = y - 12

    -- BY DUNGEON.
    b:Section("BY DUNGEON", x, y); y = y - 24
    b:Box(x, y + 4, rowW, 22, 0.12, 0, C.accent)
    hdr(b, C, x + 34, y - 2, "Dungeon"); hdr(b, C, x + 300, y - 2, "Runs")
    hdr(b, C, x + 360, y - 2, "Timed%"); hdr(b, C, x + 430, y - 2, "Best +")
    hdr(b, C, x + 500, y - 2, "Best Time"); hdr(b, C, x + 590, y - 2, "Avg Time")
    hdr(b, C, x + 680, y - 2, "Deaths")
    y = y - 24
    for i, dd in ipairs(d.dungeons) do
        -- Click through to the full dungeon page; detailCharacter stays set so Back returns here
        -- (dispatch checks detailDungeon before detailCharacter).
        b:Row(x, y, rowW, 26, { index = i, tipTitle = dd.name, tipBody = "Open this dungeon's details.",
            onClick = function() view.detailDungeon = dd.mapId; win:Refresh() end })
        dungeonGlyph(b, x + 6, y - 5, 20, dd.mapId)
        b:Label(dd.name or DASH, x + 34, y - 9, C.text, 12)
        b:Label(tostring(dd.totals.runs), x + 300, y - 9, C.text, 11)
        b:Label(dd.timedPct and Util.percent(dd.timedPct) or DASH, x + 360, y - 9, C.text, 11)
        b:Label(dd.highestTimed and ("+" .. dd.highestTimed) or DASH, x + 430, y - 9, C.accent, 12)
        b:Label(Util.duration(dd.bestTime), x + 500, y - 9, C.text, 11)
        b:Label(Util.duration(dd.avgTime), x + 590, y - 9, C.subtext, 11)
        b:Label(dd.avgDeaths and string.format("%.1f", dd.avgDeaths) or DASH, x + 680, y - 9, C.text, 11)
        y = y - 26
    end
    y = y - 12

    -- RUNS (paginated) - each row opens the full run.
    local runs = History.FilterRuns({ character = key, seasonId = scopeSeason() })
    b:Section(string.format("RUNS (%d)", #runs), x, y); y = y - 24
    if #runs == 0 then b:Label("No runs recorded.", x + 4, y - 2, C.subtext, 11); return y - 20 end
    local first, last = pagerBar(b, C, x, y, rowW, #runs, "charRuns", win); y = y - 42
    b:Box(x, y + 6, rowW, (last - first + 1) * 28 + 6, 0.03, 0, C.card)
    for i = first, last do
        dungeonRunRow(b, C, x, y, rowW, runs[i], i, win)
        y = y - 28
    end
    y = y - 4
    pagerBar(b, C, x, y, rowW, #runs, "charRuns", win)
    return y - 30
end

----------------------------------------------------------------------
-- Dispatch.
----------------------------------------------------------------------
local TAB_RENDER = {
    overview = renderOverview, runs = renderRunsList, dungeons = renderDungeons,
    characters = renderCharacters, players = renderPlayers, bests = renderBests,
    settings = renderSettings, debug = renderDebug,
}

function UI.Render(m, b, x, y, win)
    local C = b.theme.C
    local w = b.contentWidth - 40
    if not DB.Ready() then
        b:Wrap("Mythic Ledger is still loading...", x, y, w - 20, C.subtext, 12)
        return y - 30
    end
    y = y - 4   -- the suite's module header (title + toggle + desc) sits above us; go straight to tabs

    if view.review then return renderPlayerReview(b, C, x, y, w, win) end
    if view.detailRun then return renderRunDetails(b, C, x, y, w, win) end
    if view.detailPlayer then return renderPlayerDetails(b, C, x, y, w, win) end
    if view.detailDungeon then return renderDungeonDetails(b, C, x, y, w, win) end
    if view.detailCharacter then return renderCharacterDetails(b, C, x, y, w, win) end

    y = renderTabBar(b, C, x, y, w, win)
    local fn = TAB_RENDER[view.tab] or renderOverview
    return fn(b, C, x, y, w, win)
end

function UI.ResetView()
    view.detailRun = nil; view.detailPlayer = nil; view.detailDungeon = nil; view.detailCharacter = nil
    view.review = nil; reviewRunRef = nil; reviewMemberRef = nil
    runFilter.playerKey = nil
end

-- Open the module page, optionally jumping to a tab (used by slash commands).
function UI.Show(tab)
    if tab then view.tab = tab; view.detailRun = nil; view.detailPlayer = nil; view.detailDungeon = nil; view.detailCharacter = nil
        view.review = nil; reviewRunRef = nil; reviewMemberRef = nil end
    if _G.TAP and _G.TAP.OpenWindow then _G.TAP:OpenWindow("mod:" .. ML.MODULE_ID) end
end

----------------------------------------------------------------------
-- Post-run summary (queued out of combat).
----------------------------------------------------------------------
local pendingSummary
local summaryWatcher

-- Big end-of-run scoreboard modal: a Blizzard-M+-summary-style table of every party member's
-- stats, the result header, and the boss splits. Also reachable from a past run's detail page.
local SB_STATUS_HEX = { TIMED = "33dd66", DEPLETED = "e0a030", ABANDONED = "9098a8" }

-- Performance-score (ML.Scoring) helpers, shared by the scoreboard AND the run detail so the grade
-- shows everywhere a run's party breakdown appears. Grade colour keys off the letter.
-- Aggressive, honest scale: only A/S read as green/gold ("met expectations"); B is amber ("room to
-- improve"), C orange, D/F red. The category bars and numbers derive from this same map (via a score's
-- grade), so a 79 category is the exact colour a 79 overall would show.
local GRADE_HEX = { S = "e6cc80", A = "35d15f", B = "e8c24a", C = "e0872f", D = "d75f38", F = "cf4040" }
function gradeColor(grade) return (grade and GRADE_HEX[grade:sub(1, 1)]) or "cccccc" end   -- forward-declared above

-- Score every party member of a run. Routed through Scoring.Store, which memoises per run + engine
-- version and persists a compact summary, so a Config.version bump / RescoreAll retroactively updates
-- what the UI shows. Returns the ScoreRun result { byGuid = {guid=score}, list, ... } or nil.
local scoreCache = setmetatable({}, { __mode = "k" })
function runScores(run)   -- assigns to the forward-declared local above (used earlier by renderRunDetails)
    if not run then return nil end
    if run.scores then return run.scores end   -- attached to an unsaved preview run
    local S = ML.Scoring
    if S and S.Store and S.Store.Full then
        local ok, res = pcall(S.Store.Full, run)
        return ok and res or nil
    end
    if not (S and S.Score and S.Score.ScoreRun) then return nil end
    local c = scoreCache[run]
    if c == nil then
        local ok, res = pcall(S.Score.ScoreRun, run)
        c = (ok and res) or false
        scoreCache[run] = c
    end
    return c or nil
end

-- Look up a member's score in a ScoreRun result (by GUID, then name).
function memberScore(scores, m)   -- forward-declared above
    if not scores then return nil end
    if m.guid and scores.byGuid and scores.byGuid[m.guid] then return scores.byGuid[m.guid] end
    for _, sc in ipairs(scores.list or {}) do
        if sc.name == m.name or sc.name == m.fullName then return sc end
    end
    return nil
end

-- Tooltip lines for a player's performance score (grade + per-category breakdown from the engine).
-- Colour a 0-100 score by the SAME grade scale the overall uses, so a category scoring 79 is the exact
-- colour a 79 overall would be. Aggressive: only ~A/S read green/gold; a 79 (B) is amber, not "green".
local function catScoreHex(n)
    if type(n) ~= "number" then return "8b91a0" end
    local S = ML.Scoring and ML.Scoring.Score
    return (S and S.Grade) and gradeColor(S.Grade(n)) or "cccccc"
end

-- Percent from a 0-1 fraction (weights / confidence are stored as fractions).
local function pctOf(x) return math.floor((tonumber(x) or 0) * 100 + 0.5) end

-- The live theme accent as an "rrggbb" hex (skin-overridable), for highlighting variable numbers.
local function accentHex()
    local th = _G.TAP and _G.TAP.uiTheme
    local a = th and th.C and th.C.accent
    if type(a) ~= "table" then return "4aa3ff" end
    return string.format("%02x%02x%02x",
        math.floor((a[1] or 0) * 255 + 0.5), math.floor((a[2] or 0) * 255 + 0.5), math.floor((a[3] or 0) * 255 + 0.5))
end

-- Highlight every VARIABLE number in a detail/explanation string with the theme accent, via inline WoW
-- colour codes so it renders identically in the page AND in tooltips. Catches counts, decimals, %, x
-- ratios and K/M/B-suffixed values (e.g. 94.4K, 1.01x, 22%, ~4.5, -25). Score numbers are coloured by
-- grade elsewhere and deliberately NOT run through this.
local function hlNums(str)
    if type(str) ~= "string" or str == "" then return str end
    local hex = accentHex()
    return (str:gsub("([%-~]?%d[%d%.,]*)([%%xKMB]?)", function(num, suf)
        -- Pull any trailing sentence "." / "," back OUT of the highlight (e.g. "0.91." -> 0.91 + ".").
        local core, trail = num:match("^(.-)([%.,]*)$")
        return "|cff" .. hex .. core .. suf .. "|r" .. trail
    end))
end

-- Fallback: turn the engine's plain-text explanation into rows when a score lacks structured
-- categories (old / compact records). One dim detail line per category, no per-number highlighting.
local function scoreTipLinesFromText(sc, lines)
    local details = sc.explanation and sc.explanation.details
    if not (details and #details > 0) then return lines end
    lines[#lines + 1] = { sep = true }
    for _, d in ipairs(details) do
        local label, rest = d:match("^(.-):%s*(.*)$")
        if label then
            local val = (rest:match("^([^(]*)") or rest):gsub("%s+$", "")   -- score before the "("
            local detail = rest:match("%((.*)%)")                            -- between first "(" and last ")"
            local isNA = (val == "N/A")
            lines[#lines + 1] = { left = label, right = val,
                lcolor = "cdd2db", rcolor = isNA and "8b91a0" or catScoreHex(tonumber(val)) }
            if detail and detail ~= "" then lines[#lines + 1] = { text = "    " .. hlNums(detail), color = "8b91a0" } end
        else
            lines[#lines + 1] = { text = hlNums(d), color = "8b91a0" }
        end
    end
    return lines
end

-- Tooltip for a player's performance score. Rendered straight from the structured category data so
-- each row is a clean "Category -> score" (score colour-coded) with ONE calm, dim detail line: the
-- key comparison + a quiet trailing weight. No dense parsed run-on, no gold-highlight-every-number,
-- and the internal derivation math (min x rate x comp) is left to the full audit text, not the hover.
local DETAIL_DIM = "9198a6"
function scoreTipLines(sc)   -- forward-declared above
    if not sc then return nil end
    local lines = {
        { left = "PERFORMANCE", right = string.format("%s   %d / 100", sc.grade or "?", sc.overall or 0),
          lcolor = "9aa4b8", rcolor = gradeColor(sc.grade) },
    }
    local cats = sc.categories
    if not cats then return scoreTipLinesFromText(sc, lines) end
    lines[#lines + 1] = { sep = true }

    -- One category block: bold "Label ... score" row + an optional dim detail line beneath.
    local function block(label, score, isNA, detail)
        lines[#lines + 1] = { left = label,
            right = isNA and "N/A" or tostring(math.floor((score or 0) + 0.5)),
            lcolor = "cdd2db", rcolor = isNA and "8b91a0" or catScoreHex(score) }
        if detail and detail ~= "" then lines[#lines + 1] = { text = "    " .. hlNums(detail), color = DETAIL_DIM } end
    end
    local function wt(w) return " · weight " .. pctOf(w) .. "%" end

    -- Throughput. When it blends two stats (tank/healer DPS + HPS), split each into its own indented
    -- sub-row with its own component score, so a hit-DPS-missed-HPS run is obvious at a glance.
    local t = cats.throughput
    if t then
        local det = t.detail
        local function cmp(c) return string.format("%s vs %s expected (%.2fx)", Util.shortNum(c.value), Util.shortNum(c.expected), c.ratio or 0) end
        if det and det.dps and det.hps then
            block("Throughput", t.score, false, "blended DPS + HPS" .. wt(t.weight))
            block("    Damage", det.dps.score, false, cmp(det.dps))
            block("    Healing", det.hps.score, false, cmp(det.hps))
        elseif det and (det.dps or det.hps) then
            block("Throughput", t.score, false, cmp(det.dps or det.hps) .. wt(t.weight))
        else
            block("Throughput", t.score, false, (t.note or "estimate") .. wt(t.weight))
        end
    end

    -- Interrupts
    local i = cats.interrupts
    if i then
        if not i.applicable then block("Interrupt Contribution", nil, true, i.reason or "not applicable")
        elseif i.actual == nil then block("Interrupt Contribution", i.score, false, i.note or "no data")
        else
            local conf = ((i.confidence or 1) < 1) and (" · " .. pctOf(i.confidence) .. "% conf") or ""
            block("Interrupt Contribution", i.score, false,
                string.format("%d vs %.1f expected · %s%s%s", i.actual, i.expected or 0, i.profile or "?", conf, wt(i.weight)))
        end
    end

    -- Dispels
    local dp = cats.dispels
    if dp then
        if not dp.applicable then block("Dispel Contribution", nil, true, dp.reason or "not applicable")
        elseif dp.actual == nil then block("Dispel Contribution", dp.score, false, dp.note or "no data")
        else
            local conf = ((dp.confidence or 1) < 1) and (" · " .. pctOf(dp.confidence) .. "% conf") or ""
            block("Dispel Contribution", dp.score, false,
                string.format("%d vs %.1f expected · %s%s%s", dp.actual, dp.expected or 0, dp.profile or "?", conf, wt(dp.weight)))
        end
    end

    -- Survival
    local s = cats.survival
    if s then
        local seg = (s.detail and s.detail.avoidableShare)
            and (string.format("%.1f%% of dmg taken avoidable", (s.detail.avoidableShare or 0) * 100)) or (s.note or "estimate")
        block("Survival", s.score, false, seg .. wt(s.weight))
    end

    -- Deaths
    local de = cats.deaths
    if de then
        if de.deaths == nil then block("Death Impact", de.score, false, de.note or "no data")
        else
            local seg = (de.deaths == 0) and "no deaths"
                or string.format("%d death%s · -%d penalty", de.deaths, de.deaths == 1 and "" or "s", de.penalty or 0)
            block("Death Impact", de.score, false, seg .. wt(de.weight))
        end
    end

    -- Role contribution (only when it carries weight).
    local rc = cats.roleContribution
    if rc and (rc.weight or 0) > 0 then
        block("Role Contribution", rc.score, false, "survival + utility composite" .. wt(rc.weight))
    end

    return lines
end

-- Review "state" (from Scoring.Review.Band) -> accent colour, matching the category score scale.
local BAND_HEX = { EXCELLENT = "33dd66", STRONG = "6fd06f", SOLID = "cdd2db", SOFT = "e0a030", WEAK = "e0655a" }

-- Per-run PLAYER REVIEW: a hero breakdown of one member's combat stats, a bar-charted grade
-- breakdown, and the deterministic coaching review (what went well + highest-leverage fixes).
-- Reached by clicking a party row in the run details or the scoreboard. reviewRunRef/reviewMemberRef
-- hold object refs so it works for saved runs and unsaved post-run previews alike.
function renderPlayerReview(b, C, x, y, w, win)
    local r, m = reviewRunRef, reviewMemberRef
    if not (r and m) then view.review = nil; return y end
    local theme = b.theme
    local s = m.stats or {}
    local sc = memberScore(runScores(r), m)
    local review = (sc and ML.Scoring and ML.Scoring.Review) and ML.Scoring.Review.Build(sc, m.isPlayer) or nil
    local key = (not m.isPlayer) and API.IdentityKey(m) or nil
    local LX, CW = x + 8, w - 16      -- content inset so nothing hugs the edges
    local acc = classRGB(m.classFile) or C.accent
    local gradeW = 220                -- grade tile owns the top-right; nav buttons sit to its LEFT

    -- Back (+ optional cross-run history for teammates) - left of the grade tile so they never collide.
    local btnX = x + w - gradeW - 24
    T(b, b:Button(btnX - 72, y, 72, "Back", "default", function()
        view.review = nil; reviewRunRef = nil; reviewMemberRef = nil; win:Refresh()
    end, { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the run.")
    if key then
        T(b, b:Button(btnX - 212, y, 132, "History", "default", function()
            view.review = nil; reviewRunRef = nil; reviewMemberRef = nil
            view.detailPlayer = key; view.detailRun = nil; win:Refresh()
        end), "Player history", "See this player's history across all your shared runs.")
    end

    -- Header: class/spec glyphs + name, spec/role, run, coaching headline, and a big grade tile.
    if sc then
        b:StatTile(x + w - gradeW, y, {
            style = "panel", width = gradeW, height = 100,
            label = "GRADE", value = sc.grade or "?",
            icon = "award", iconSize = 56, iconColor = theme:Color(gradeColor(sc.grade)),
            accent = acc, valueColor = theme:Color(gradeColor(sc.grade)),
            footer = { "Score " .. (sc.overall or 0) .. " / 100" },
        })
    end
    classGlyph(b, LX, y - 2, 26, m.classFile)
    specGlyph(b, LX + 32, y - 2, 26, m.specId, m.specIcon)
    b:Heading(classColorText(m.classFile, m.name or "?") .. (m.isPlayer and "  (you)" or ""), LX + 68, y, "h2")
    b:Label(specClassLabel(m.classFile, m.specId) .. "   ·   " .. (ML.ROLE_LABEL[m.role] or "-"), LX + 68, y - 32, C.subtext, 11)
    b:Label((r.dungeonName or "Run") .. "  " .. Util.keyLabel(r.level) .. "   ·   " .. Util.dateTime(r.completedAt),
        LX + 68, y - 52, C.subtext, 11)
    if review and review.headline then
        b:Wrap(review.headline, LX, y - 78, w - gradeW - 28, theme:Color(BAND_HEX[review.band] or "cdd2db", C.text), 13)
    end
    y = y - 124

    -- Hero combat-stat cards, laid out in TWO rows (4 + 3) so they breathe, using the same large
    -- class-coloured hero icons as the scoreboard. Avoidable is its share of damage taken (the survival
    -- metric), coloured by the survival score; deaths redden when non-zero.
    local survScore = sc and sc.categories and sc.categories.survival and sc.categories.survival.score
    local avoidShare = sc and sc.categories and sc.categories.survival
        and sc.categories.survival.detail and sc.categories.survival.detail.avoidableShare
    if avoidShare == nil and type(s.avoidableDamageTaken) == "number" and type(s.damageTaken) == "number" and s.damageTaken > 0 then
        avoidShare = s.avoidableDamageTaken / s.damageTaken
    end
    local heroStyle = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[DB.Settings().cardStyle] or "compact"
    local rows = {
        {
            { label = "DPS",       value = Util.shortNum(s.dps),         icon = "sword" },
            { label = "HPS",       value = Util.shortNum(s.hps),         icon = "heartbeat" },
            { label = "DMG TAKEN", value = Util.shortNum(s.damageTaken), icon = "shield" },
            { label = "AVOIDABLE", value = avoidShare and string.format("%.1f%%", avoidShare * 100) or DASH,
              icon = "shield", color = survScore and catScoreHex(survScore) or nil },
        },
        {
            { label = "INTERRUPTS", value = Util.numOr(s.interrupts, "%d"), icon = "ban" },
            { label = "DISPELS",    value = Util.numOr(s.dispels, "%d"),    icon = "sparkles" },
            { label = "DEATHS",     value = Util.numOr(s.deaths, "%d"),     icon = "skull",
              color = (type(s.deaths) == "number" and s.deaths > 0) and "e0655a" or nil },
        },
    }
    local gap, cols = 12, 4
    local cw = (CW - (cols - 1) * gap) / cols
    for _, rowTiles in ipairs(rows) do
        for i, t in ipairs(rowTiles) do
            b:StatTile(LX + (i - 1) * (cw + gap), y, {
                style = heroStyle, width = cw, height = 92, label = t.label, value = t.value,
                icon = t.icon, iconSize = 64, iconColor = acc, accent = acc,
                valueColor = t.color and theme:Color(t.color) or C.text,
            })
        end
        y = y - 100
    end
    y = y - 12

    if not sc then
        b:Wrap("No performance score is available for this run - the combat data needed to grade it wasn't captured.",
            LX, y, CW, C.subtext, 12)
        return y - 30
    end

    -- GRADE BREAKDOWN as quasi-hero cards: bold label + explanation, an aggressively-coloured bar, and a
    -- big score in the exact grade colour that score would earn as an overall. Throughput splits DPS/HPS.
    local cats = sc.categories
    local Cfg = ML.Scoring and ML.Scoring.Config
    local poss = m.isPlayer and "your" or "their"
    local Poss = m.isPlayer and "Your" or "Their"
    local didV = m.isPlayer and "you did" or "they did"
    local landedV = m.isPlayer and "you landed" or "they landed"
    local function rnd(v) return math.floor((v or 0) + 0.5) end
    local function bar(bx, by, bw, score)
        b:Box(bx, by, bw, 9, 0.16, 1, C.border)
        b:Box(bx, by, bw * math.max(0, math.min(1, (score or 0) / 100)), 9, 0.95, 2, theme:Color(catScoreHex(score)))
    end
    local BAR_X = LX + 340
    local function card(label, score, detail, na)
        local H = 54
        b:Box(LX, y, CW, H, 0.45, 0, C.card)
        b:Box(LX, y, 3, H, 0.95, 2, na and theme:Color("8b91a0") or theme:Color(catScoreHex(score)))
        b:Label(label, LX + 16, y - 16, C.text, 13)
        if detail then b:Label(hlNums(detail), LX + 16, y - 36, C.subtext, 10) end
        if na then
            b:Label("N/A", LX + CW - 84, y - 20, theme:Color("8b91a0"), 15)
        else
            bar(BAR_X, y - 30, CW - (BAR_X - LX) - 92, score)
            b:Label(tostring(rnd(score)), LX + CW - 76, y - 22, theme:Color(catScoreHex(score)), 20)
        end
        y = y - H - 8
    end

    b:Section("GRADE BREAKDOWN", LX, y); y = y - 34

    -- Throughput (split into DPS + HPS sub-bars when the role blends both).
    local t = cats.throughput
    if t then
        local det = t.detail or {}
        if det.dps and det.hps then
            local H = 84
            b:Box(LX, y, CW, H, 0.45, 0, C.card)
            b:Box(LX, y, 3, H, 0.95, 2, theme:Color(catScoreHex(t.score)))
            b:Label("Throughput", LX + 16, y - 16, C.text, 13)
            b:Label(hlNums("blended DPS + HPS · weight " .. pctOf(t.weight) .. "%"), LX + 16, y - 34, C.subtext, 10)
            b:Label(tostring(rnd(t.score)), LX + CW - 76, y - 20, theme:Color(catScoreHex(t.score)), 20)
            local function subBar(name, c, yy)
                b:Label(name, LX + 20, yy, C.subtext, 11)
                bar(LX + 120, yy - 3, 190, c.score)
                b:Label(tostring(rnd(c.score)), LX + 322, yy, theme:Color(catScoreHex(c.score)), 12)
                b:Label(hlNums(string.format("%s vs %s expected (%.2fx)", Util.shortNum(c.value), Util.shortNum(c.expected), c.ratio or 0)),
                    LX + 372, yy, C.subtext, 10)
            end
            subBar("Damage", det.dps, y - 52)
            subBar("Healing", det.hps, y - 70)
            y = y - H - 8
        else
            local c = det.dps or det.hps
            local d = c and string.format("%s vs %s expected (%.2fx) · weight %d%%",
                    Util.shortNum(c.value), Util.shortNum(c.expected), c.ratio or 0, pctOf(t.weight))
                or ((t.note or "estimate") .. " · weight " .. pctOf(t.weight) .. "%")
            card("Throughput", t.score, d)
        end
    end

    -- Interrupts / Dispels
    local function contribCard(label, cRes)
        if not cRes then return end
        if not cRes.applicable then card(label, nil, cRes.reason or "not applicable", true)
        elseif cRes.actual == nil then card(label, cRes.score, cRes.note or "no data")
        else card(label, cRes.score, string.format("%d vs %.1f expected · %s · weight %d%%",
            cRes.actual, cRes.expected or 0, cRes.profile or "?", pctOf(cRes.weight))) end
    end
    contribCard("Interrupt Contribution", cats.interrupts)
    contribCard("Dispel Contribution", cats.dispels)

    -- Survival
    local sv = cats.survival
    if sv then
        local shr = sv.detail and sv.detail.avoidableShare
        card("Survival", sv.score, shr and string.format("%.1f%% of dmg taken avoidable · weight %d%%", shr * 100, pctOf(sv.weight))
            or ((sv.note or "estimate") .. " · weight " .. pctOf(sv.weight) .. "%"))
    end

    -- Deaths
    local de = cats.deaths
    if de then
        local d = (de.deaths == nil) and (de.note or "no death data recorded")
            or ((de.deaths == 0) and ("no deaths · weight " .. pctOf(de.weight) .. "%")
            or string.format("%d death%s · -%d penalty · weight %d%%", de.deaths, de.deaths == 1 and "" or "s", de.penalty or 0, pctOf(de.weight)))
        card("Death Impact", de.score, d)
    end
    y = y - 10

    -- HOW TARGETS WERE SET: explain the expected totals the score compared against.
    b:Section("HOW TARGETS WERE SET", LX, y); y = y - 32
    local function expl(title, body)
        b:Label(hlNums(title), LX + 16, y - 2, C.text, 12)
        local _, hh = b:Wrap(hlNums(body), LX + 16, y - 20, CW - 32, C.subtext, 10)
        y = y - 22 - (hh or 12) - 8
    end
    if t and t.detail and t.detail.dps then
        expl(string.format("Damage — %s DPS target  (%s %s, %.2fx)",
                Util.shortNum(t.detail.dps.expected), didV, Util.shortNum(t.detail.dps.value), t.detail.dps.ratio or 0),
            Poss .. " modeled share of the group's total damage this run - group-relative, so it scales with the party instead of a fixed number. Meeting the share is full marks; beating it never hurts.")
    end
    if t and t.detail and t.detail.hps then
        expl(string.format("Healing — %s HPS target  (%s %s, %.2fx)",
                Util.shortNum(t.detail.hps.expected), didV, Util.shortNum(t.detail.hps.value), t.detail.hps.ratio or 0),
            Poss .. " modeled share of the group's total healing. Tanks are expected to self-sustain a portion by spec.")
    end
    local comp = (Cfg and Cfg.composition) or {}
    local iC = cats.interrupts
    if iC and iC.applicable and iC.expected then
        local kit = iC.interruptSpell and string.format("%s (%ds CD)%s", iC.interruptSpell, iC.interruptCD or 0,
            iC.interruptExtras and (" + " .. iC.interruptExtras) or "") or (iC.profile or "?")
        expl(string.format("Interrupts — ~%.1f target  (%s %s)", iC.expected, landedV, iC.actual and tostring(iC.actual) or "-"),
            string.format("Tailored to this spec's kick availability - %s gives ~%.2f interrupts/min, × %.0f min × composition %.2f. Composition adjusts for group makeup: below 1.0 when other capable kickers share the load, above 1.0 for a lone interrupter (clamped %.2f-%.2f).",
                kit, iC.rate or 0, iC.minutes or 0, iC.compModifier or 1, comp.min or 0.85, comp.max or 1.15))
    end
    local dC = cats.dispels
    if dC and dC.applicable and dC.expected then
        expl(string.format("Dispels — ~%.1f target  (%s %s)", dC.expected, didV, dC.actual and tostring(dC.actual) or "-"),
            string.format("Run length × the spec's %s dispel rate × composition %.2f (same group-makeup adjustment as interrupts).",
                dC.profile or "?", dC.compModifier or 1))
    end
    if Cfg and Cfg.survival then
        expl(string.format("Survival — %.1f%% avoidable or less = 100, %.0f%%+ = 0",
                (Cfg.survival.graceShare or 0.025) * 100, (Cfg.survival.zeroShare or 0.40) * 100),
            "Scored purely on avoidable damage as a share of " .. poss .. " total damage taken - scale-free, so it ignores key level and health pools.")
    end
    if Cfg and Cfg.deaths then
        expl("Deaths — 100 minus 25 per death",
            "Every death is heavily penalised; four deaths zero the category. Dying is the single most costly thing that can happen to a run.")
    end

    -- What went well.
    if review and #review.strengths > 0 then
        b:Section("WHAT WENT WELL", LX, y); y = y - 32
        for _, sN in ipairs(review.strengths) do
            b:Label("+", LX + 18, y - 2, theme:Color("33dd66"), 14)
            b:Label(sN.label, LX + 38, y - 2, theme:Color("6fd06f"), 12)
            local _, hh = b:Wrap(hlNums(sN.note), LX + 190, y - 2, CW - 208, C.subtext, 11)
            y = y - math.max(26, (hh or 12) + 12)
        end
        y = y - 14
    end

    -- Focus on (highest leverage first).
    if review and #review.improvements > 0 then
        b:Section("FOCUS ON", LX, y)
        b:Label("highest impact first", LX + 150, y - 1, C.subtext, 10)
        y = y - 32
        for _, im in ipairs(review.improvements) do
            b:Label(">", LX + 18, y - 2, theme:Color(catScoreHex(im.score)), 14)
            b:Label(im.label, LX + 38, y - 2, theme:Color(catScoreHex(im.score)), 12)
            local _, hh = b:Wrap(hlNums(im.note), LX + 190, y - 2, CW - 208, C.text, 11)
            y = y - math.max(26, (hh or 12) + 12)
        end
        y = y - 14
    elseif review and #review.strengths > 0 then
        b:Section("FOCUS ON", LX, y); y = y - 32
        b:Label("Nothing meaningful to fix - a clean key. Keep it up.", LX + 18, y - 2, theme:Color("6fd06f"), 12)
        y = y - 28
    end

    return y - 14
end

function UI.ShowScoreboard(run, opts)
    local theme = _G.TAP and _G.TAP.uiTheme
    if not (theme and theme.Modal and run) then return end
    local C = theme.C
    opts = opts or {}

    -- Optional scoreboard-specific font: swap the theme font just while the modal is built, then
    -- restore it (all the modal's fontstrings capture theme.FONT at creation).
    local prevFont = theme.FONT
    local sbFontKey = DB.Settings().scoreboardFont
    if sbFontKey and sbFontKey ~= "" and _G.UIFoundry and _G.UIFoundry.ResolveFontFile then
        theme.FONT = _G.UIFoundry.ResolveFontFile(theme:ResolveFont(sbFontKey))
    end

    -- Party sorted by DPS (highest first); the player's own row is marked.
    local party = {}
    for _, m in ipairs(run.party or {}) do party[#party + 1] = m end
    table.sort(party, function(a, bb)
        local ad, bd = (a.stats and a.stats.dps) or -1, (bb.stats and bb.stats.dps) or -1
        if ad == bd then return (a.name or "") < (bb.name or "") end
        return ad > bd
    end)
    local bosses = run.bosses or {}
    local scores = runScores(run)   -- ML.Scoring performance grades per member
    UI._lastScoreboardRun = run     -- so "View full run" resolves even for an unsaved preview run

    -- MVP: the highest-graded player.
    local mvp
    if scores and scores.list then
        for _, sc in ipairs(scores.list) do
            if (sc.overall or -1) > ((mvp and mvp.overall) or -1) then mvp = sc end
        end
    end

    local timelineOK = run.duration and run.duration > 0

    -- Hero highlights: the party leader for each metric (min for avoidable, max for the rest).
    local function bestOf(key, cmp)
        local bestM, bestV
        for _, m in ipairs(run.party or {}) do
            local v = m.stats and m.stats[key]
            if type(v) == "number" then
                if bestV == nil or (cmp == "min" and v < bestV) or (cmp == "max" and v > bestV) then
                    bestV, bestM = v, m
                end
            end
        end
        return bestM, bestV
    end
    local HERO_DEFS = {
        { label = "TOP DPS",        key = "dps",                  cmp = "max", fmt = Util.shortNum, icon = "sword" },
        { label = "TOP HPS",        key = "hps",                  cmp = "max", fmt = Util.shortNum, icon = "heartbeat" },
        { label = "INTERRUPTS",     key = "interrupts",           cmp = "max", fmt = function(v) return string.format("%d", v) end, icon = "ban" },
        { label = "DISPELS",        key = "dispels",              cmp = "max", fmt = function(v) return string.format("%d", v) end, icon = "sparkles" },
        { label = "LEAST AVOIDABLE",key = "avoidableDamageTaken", cmp = "min", fmt = Util.shortNum, icon = "shield" },
    }
    local heroes = {}
    for _, h in ipairs(HERO_DEFS) do
        local m, v = bestOf(h.key, h.cmp)
        if m and v and v > 0 then heroes[#heroes + 1] = { label = h.label, member = m, value = v, fmt = h.fmt, icon = h.icon } end
    end
    local heroStyle = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[DB.Settings().cardStyle] or "compact"

    local W, rowH, headerH, colH = 1520, 40, 104, 22
    local heroPart = (#heroes > 0) and 88 or 0
    local partyPart = 28   -- the "PARTY" section header above the table
    local bossPart = (#bosses > 0) and (56 + #bosses * 42) or 0
    local timePart = timelineOK and 232 or 0
    local newBest = run._newBests and #run._newBests > 0
    local bodyH = headerH + heroPart + partyPart + colH + math.max(1, #party) * rowH + bossPart + timePart + 12

    local timeStr = Util.duration(run.duration)
    local remStr = run.timeRemaining and ((run.timeRemaining >= 0 and "+" or "-") .. Util.duration(math.abs(run.timeRemaining)))

    local sb = theme:Modal({
        title = "Mythic+ Scoreboard",
        variant = run.status == STATUS.TIMED and "success" or (run.status == STATUS.ABANDONED and "danger" or "warning"),
        icon = theme:GetIcon("award"),
        width = W, bodyHeight = bodyH,
        buttons = {
            { label = "View full run", kind = "default", onClick = function(m)
                m:Close()
                if _G.TAP and _G.TAP.OpenWindow then
                    view.detailRun = run.id; view.detailPlayer = nil; view.tab = "runs"
                    _G.TAP:OpenWindow("mod:" .. ML.MODULE_ID)
                end
            end },
            { label = "Close", kind = "primary", onClick = function(m) m:Close() end },
        },
        content = function(body, modal)
            local b = theme:Builder(body, { contentWidth = W - 32 })
            local rowW = W - 32
            local x, y = 0, -2
            -- The MVP card and the hero-stat cards share one card width so they line up.
            local heroGap, heroN = 8, math.max(1, #heroes)
            local heroCW = (rowW - (heroN - 1) * heroGap) / heroN

            local mi = run.mapId and API.GetMapInfo(run.mapId)

            -- Backdrop: a solid black fill with the dungeon's own art laid over it at 25% opacity,
            -- covering the WHOLE modal (header + body + footer), not just the body. Drawn on the modal
            -- frame at BACKGROUND sublevels 2/3 - above the panel fill (sublevel 1) but below the header
            -- bar/title (ARTWORK/OVERLAY) and the body content (a child frame), so everything renders on
            -- top. Inset 2px so the modal's border still shows. Fresh per modal, so no pooling leak.
            local backdrop = (modal and modal.frame) or body
            local blackBg = backdrop:CreateTexture(nil, "BACKGROUND", nil, 2)
            blackBg:SetColorTexture(0, 0, 0, 1)
            blackBg:SetPoint("TOPLEFT", 2, -2); blackBg:SetPoint("BOTTOMRIGHT", -2, 2)
            -- Prefer the dungeon's wide Encounter-Journal background art (atmospheric, fills nicely);
            -- fall back to the small square GetMapUIInfo portal icon when the EJ art isn't available.
            local bgTex = API.DungeonBackground(run.dungeonName) or (mi and mi.texture)
            if bgTex then
                local watermark = backdrop:CreateTexture(nil, "BACKGROUND", nil, 3)
                watermark:SetTexture(bgTex); watermark:SetAlpha(0.25)
                watermark:SetPoint("TOPLEFT", 2, -2); watermark:SetPoint("BOTTOMRIGHT", -2, 2)
            end

            -- Header: dungeon portal + name + result + affixes + date.
            if mi and mi.texture then b:Tex(x, y - 4, 60, 60, mi.texture)
            else b:Tex(x, y - 4, 60, 60, "map", nil, { 0.55, 0.6, 0.72 }) end
            b:Heading((run.dungeonName or "Dungeon") .. "   " .. Util.keyLabel(run.level), x + 72, y, "h2")
            local result = statusText(run.status) .. "    " .. timeStr .. (remStr and ("   (" .. remStr .. ")") or "")
            if run.keystoneUpgrade and run.keystoneUpgrade > 0 then result = result .. "    +" .. run.keystoneUpgrade end
            b:Label(result, x + 72, y - 28, theme:Color(SB_STATUS_HEX[run.status] or "cccccc", C.text), 13)
            if run.affixNames and #run.affixNames > 0 then
                b:Label(table.concat(run.affixNames, ", "), x + 72, y - 48, C.subtext, 11)
            end
            b:Label(Util.dateTime(run.completedAt), x + 72, y - 66, C.subtext, 11)
            if newBest then b:Label("New personal best!", x + 72, y - 84, theme:Color("20C997"), 12) end

            -- MVP (top-right free space): the highest-graded player, as a hero-style card - big icon
            -- on the right + a border, matching the hero cards.
            if mvp then
                local mvcw = heroCW   -- clamp to the hero-stat card width
                local mvname = classColorText(mvp.classFile, mvp.name or "?")
                b:StatTile(x + rowW - mvcw, y, {
                    style = heroStyle, width = mvcw, height = headerH - 6,
                    label = "MVP", value = mvp.grade or "?",
                    icon = "crown", iconSize = 60, iconColor = theme:Color("f4d060"),
                    accent = classRGB(mvp.classFile) or C.accent,
                    valueColor = theme:Color(gradeColor(mvp.grade)),
                    sub = mvname, footer = { mvname, "Score " .. (mvp.overall or 0) .. " / 100" },
                })
            end
            y = y - headerH

            -- Hero highlights: one stat card per metric leader (best DPS / HPS / interrupts /
            -- dispels / least avoidable damage), styled to match the Overview page's cards.
            if #heroes > 0 then
                local gap, cw = heroGap, heroCW
                for i, h in ipairs(heroes) do
                    local cname = classColorText(h.member.classFile, h.member.name or "?")
                    local acc = classRGB(h.member.classFile) or C.accent
                    b:StatTile(x + (i - 1) * (cw + gap), y, {
                        style = heroStyle, width = cw, height = 80,
                        label = h.label, value = h.fmt(h.value),
                        icon = h.icon, iconSize = 64, iconColor = acc,   -- big class-coloured hero icon
                        accent = acc, valueColor = C.text,               -- number neutral; name class-coloured
                        sub = cname, footer = { cname },
                    })
                end
                y = y - heroPart
            end

            b:Section("PARTY", x, y); y = y - 28

            -- Column headers (spread across the widescreen board).
            local COL = { name = 66, grade = 330, score = 490, dps = 660, hps = 790, dtk = 920, deaths = 1110, int = 1220, dsp = 1310, avoid = 1400 }
            b:Label("PLAYER", x + COL.name, y - 2, C.subtext, 10)
            b:Label("GRADE", x + COL.grade, y - 2, C.subtext, 10)
            b:Label("M+ SCORE", x + COL.score, y - 2, C.subtext, 10)
            b:Label("DPS", x + COL.dps, y - 2, C.subtext, 10)
            b:Label("HPS", x + COL.hps, y - 2, C.subtext, 10)
            b:Label("DMG TAKEN", x + COL.dtk, y - 2, C.subtext, 10)
            b:Label("DEATHS", x + COL.deaths, y - 2, C.subtext, 10)
            b:Label("INT", x + COL.int, y - 2, C.subtext, 10)
            b:Label("DSP", x + COL.dsp, y - 2, C.subtext, 10)
            b:Label("AVOID", x + COL.avoid, y - 2, C.subtext, 10)
            y = y - colH

            if #party == 0 then
                b:Label("No party stats were captured for this run.", x + 4, y - 2, C.subtext, 11)
            end
            for i, m in ipairs(party) do
                local s = m.stats or {}
                local sc = memberScore(scores, m)
                local lines = {
                    { left = "Spec", right = specClassLabel(m.classFile, m.specId) },
                    { left = "Role", right = ML.ROLE_LABEL[m.role] or "-" },
                    { sep = true },
                    { left = "Damage / DPS", right = Util.shortNum(s.damage) .. " / " .. Util.shortNum(s.dps) },
                    { left = "Healing / HPS", right = Util.shortNum(s.healing) .. " / " .. Util.shortNum(s.hps) },
                    { left = "Damage taken", right = Util.shortNum(s.damageTaken) },
                    { left = "Avoidable taken", right = Util.shortNum(s.avoidableDamageTaken) },
                    { left = "Absorbs", right = Util.shortNum(s.absorbs) },
                    { left = "Interrupts / Dispels", right = Util.numOr(s.interrupts, "%d") .. " / " .. Util.numOr(s.dispels, "%d") },
                    { left = "Deaths", right = Util.numOr(s.deaths, "%d") },
                }
                local slines = scoreTipLines(sc)
                if slines then lines[#lines + 1] = { sep = true }; for _, l in ipairs(slines) do lines[#lines + 1] = l end end
                lines[#lines + 1] = { blank = true }; lines[#lines + 1] = { text = "Click for their full run review.", color = "subtext" }
                b:Row(x, y, rowW, rowH, { index = i,
                    tipData = { icon = specIconID(m.specId) or m.specIcon, minWidth = 420,
                        title = (m.fullName or m.name or "?") .. (m.isPlayer and "   (you)" or ""), lines = lines },
                    onClick = function()
                        if sb and sb.Close then sb:Close() end
                        view.review = true; reviewRunRef = run; reviewMemberRef = m
                        view.detailRun = run.id; view.detailPlayer = nil; view.tab = "runs"
                        if _G.TAP and _G.TAP.OpenWindow then _G.TAP:OpenWindow("mod:" .. ML.MODULE_ID) end
                    end })
                specGlyph(b, x + 4, y - 7, 26, m.specId, m.specIcon)
                roleIcon(b, x + 34, y - 11, 18, m.role)
                local nm = (m.isPlayer and "|cffffd200> |r" or "") .. classColorText(m.classFile, m.name or "?")
                b:Label(nm, x + COL.name, y - 16, C.text, 13)
                -- Gold crown next to the MVP (the highest-graded player), matching the MVP hero card.
                local isMVP = mvp and sc and ((sc.playerGUID and sc.playerGUID == mvp.playerGUID)
                    or (sc.name and sc.name == mvp.name))
                if isMVP then b:Tex(x + COL.name - 14, y - 15, 12, 12, "crown", nil, { 1, 0.82, 0.2 }) end
                -- Our performance grade (colour-coded) + the numeric score.
                if sc then
                    b:Label(sc.grade or "?", x + COL.grade, y - 16, theme:Color(gradeColor(sc.grade)), 14)
                    b:Label(tostring(sc.overall or 0), x + COL.grade + 40, y - 16, C.subtext, 12)
                else
                    b:Label(DASH, x + COL.grade, y - 16, C.subtext, 12)
                end
                -- M+ score, rarity-coloured; the player also shows this run's gain in green.
                if m.mplusScore then
                    b:Label(tostring(math.floor(m.mplusScore + 0.5)), x + COL.score, y - 16,
                        API.ScoreColor(m.mplusScore) or theme:Color("a0a6b4"), 13)
                    if m.isPlayer and run.scoreGain and run.scoreGain > 0 then
                        b:Label("+" .. run.scoreGain, x + COL.score + 48, y - 16, theme:Color("20C997"), 12)
                    end
                else
                    b:Label(DASH, x + COL.score, y - 16, C.subtext, 12)
                end
                b:Label(Util.shortNum(s.dps), x + COL.dps, y - 16, C.text, 12)
                b:Label(Util.shortNum(s.hps), x + COL.hps, y - 16, C.text, 12)
                b:Label(Util.shortNum(s.damageTaken), x + COL.dtk, y - 16, C.text, 12)
                b:Label(Util.numOr(s.deaths, "%d"), x + COL.deaths, y - 16,
                    (type(s.deaths) == "number" and s.deaths > 0) and theme:Color("e0655a") or C.subtext, 12)
                b:Label(Util.numOr(s.interrupts, "%d"), x + COL.int, y - 16, C.text, 12)
                b:Label(Util.numOr(s.dispels, "%d"), x + COL.dsp, y - 16, C.text, 12)
                b:Label(Util.shortNum(s.avoidableDamageTaken), x + COL.avoid, y - 16, C.subtext, 12)
                y = y - rowH
            end

            -- Boss splits: per-boss kill time, the party's top DPS / top HPS, the lowest avoidable
            -- damage taken, and party deaths - each row hoverable for the encounter's full details.
            if #bosses > 0 then
                y = y - 6
                b:Section("BOSSES", x, y); y = y - 30   -- extra padding under the underline
                b:Label("BOSS", x + 60, y - 2, C.subtext, 10)
                b:Label("TIME", x + 430, y - 2, C.subtext, 10)
                b:Label("TOP DPS", x + 540, y - 2, C.subtext, 10)
                b:Label("TOP HPS", x + 810, y - 2, C.subtext, 10)
                b:Label("LEAST AVOIDABLE", x + 1080, y - 2, C.subtext, 10)
                b:Label("DEATHS", x + 1400, y - 2, C.subtext, 10)
                y = y - 20
                local function hl(h, k) return h and (classColorText(h.classFile, h.name or "?") .. "  " .. Util.shortNum(h[k])) end
                for i, boss in ipairs(bosses) do
                    -- Tooltip: kill info + EVERY party member's DPS / HPS on this encounter.
                    local btip = {
                        { left = "Kill time", right = Util.duration(boss.killDuration) },
                        { left = "Killed at", right = boss.atSec and Util.duration(boss.atSec) or "-" },
                        { left = "Party deaths", right = tostring(boss.deaths or 0), rcolor = (boss.deaths and boss.deaths > 0) and "e0655a" or nil },
                    }
                    if boss.perMember and #boss.perMember > 0 then
                        btip[#btip + 1] = { sep = true }
                        btip[#btip + 1] = { left = "Player", right = "DPS  /  HPS", lcolor = "subtext", rcolor = "subtext" }
                        for _, pm in ipairs(boss.perMember) do
                            btip[#btip + 1] = { left = pm.name or "?",
                                right = Util.shortNum(pm.dps) .. "  /  " .. ((pm.hps and pm.hps > 0) and Util.shortNum(pm.hps) or "-"),
                                lcolor = classHexOf(pm.classFile) }
                        end
                    end
                    b:Row(x, y, rowW, 42, { index = i, tipData = {
                        icon = API.BossIcon(boss.name, boss.id), title = boss.name or "Boss", lines = btip } })
                    framedIcon(b, x + 10, y - 6, 60, 30, API.BossIcon(boss.name, boss.id))   -- 2:1 (60x30)
                    b:Label(boss.name or ("Boss " .. tostring(boss.id)), x + 80, y - 21, C.text, 12)
                    b:Label(Util.duration(boss.killDuration), x + 430, y - 21, C.subtext, 11)
                    b:Label(hl(boss.topDps, "dps") or DASH, x + 540, y - 21, C.text, 11)
                    b:Label(hl(boss.topHps, "hps") or DASH, x + 810, y - 21, C.text, 11)
                    b:Label(hl(boss.lowAvoid, "amount") or DASH, x + 1080, y - 21, C.text, 11)
                    b:Label(string.format("%d", boss.deaths or 0), x + 1400, y - 21, C.subtext, 11)
                    y = y - 42
                end
            end

            -- Timeline: the track spans the key's TIME LIMIT (the max time to still time it); if the
            -- run went over, it rescales to the run length and a gold line marks where the timer ran
            -- out. Green = in combat, red = downtime. Boss portraits sit at their kill time; a
            -- gravestone marks each death (hover for who).
            if timelineOK then
                y = y - 8
                b:Section("TIMELINE", x, y); y = y - 24
                local trackW, th = rowW, 8
                local ty = y - 106
                local tmax = math.max(run.timeLimit or run.duration, run.duration)
                local function fpos(t) local f = (t or 0) / tmax; return (f < 0 and 0) or (f > 1 and 1) or f end
                local function mx(t) return x + fpos(t) * trackW end
                local runEndF = fpos(run.duration)

                -- Your BEST time for THIS dungeon at THIS key level (includes this run).
                local bestTime
                if run.status == STATUS.TIMED and type(run.duration) == "number" then bestTime = run.duration end
                for _, rr in ipairs(DB.Runs()) do
                    if rr.mapId == run.mapId and rr.level == run.level and rr.status == STATUS.TIMED
                        and type(rr.duration) == "number" and (not bestTime or rr.duration < bestTime) then
                        bestTime = rr.duration
                    end
                end

                -- Track base: red across the run's active span; unused (timed) time stays dim.
                b:Box(x, ty, runEndF * trackW, th, 0.9, 0, theme:Color("8a3d3d"))
                if runEndF < 1 then b:Box(x + runEndF * trackW, ty, (1 - runEndF) * trackW, th, 0.35, 0, C.border) end
                -- Green combat segments over the base (sublevel 1, above the sub-0 track base).
                for _, seg in ipairs(run.combat or {}) do
                    local sf, ef = fpos(seg[1]), fpos(seg[2])
                    if ef > sf then b:Box(x + sf * trackW, ty, (ef - sf) * trackW, th, 1, 1, theme:Color("2f8f4e")) end
                end

                -- Keystone-upgrade time targets: +1 = the timer, +2 = 80% of it, +3 = 60% of it.
                -- A bold line crosses the track; a 2x label sits below it; hover shows YOUR delta.
                if run.timeLimit and run.timeLimit > 0 then
                    local ups = { { "+1", run.timeLimit, "ffd100" }, { "+2", run.timeLimit * 0.8, "ffe38a" }, { "+3", run.timeLimit * 0.6, "b6f0ff" } }
                    for _, u in ipairs(ups) do
                        local ux, hex = mx(u[2]), u[3]
                        b:Box(ux - 2, ty + 4, 4, th + 8, 1, 5, theme:Color(hex))          -- 2x-thick line/pip, ON TOP of the track (sub 5)
                        b:Label(u[1], ux - 10, ty - 14, theme:Color(hex), 18)            -- 2x label below the track
                        local delta = u[2] - (run.duration or 0)
                        local dtxt = (delta >= 0) and ("You beat this target by " .. Util.duration(delta) .. "  (earned " .. u[1] .. ").")
                            or ("You missed it by " .. Util.duration(-delta) .. ".")
                        -- Hover zone ON the line + its label (was sitting well below the track).
                        b:Hit(ux - 13, ty + 8, 26, 42, nil, u[1] .. " target  ·  " .. Util.duration(u[2]), dtxt)
                    end
                end

                -- Boss portraits above the track; each pinned to its kill time with a stem + node
                -- that sits ON TOP of the track. Hover is on the ICON.
                local bsz = 132   -- portrait WIDTH; height is bsz/2 (native 2:1)
                for _, boss in ipairs(bosses) do
                    if boss.atSec then
                        local px = mx(boss.atSec)
                        framedIcon(b, px - bsz / 2, ty + 14 + bsz / 2, bsz, bsz / 2, API.BossIcon(boss.name, boss.id))   -- 2:1 (bsz x bsz/2)
                        b:Box(px - 1, ty + 14, 2, 8, 1, 3, C.accent)    -- stem: portrait bottom -> node (sub 3)
                        b:Box(px - 4, ty + 6, 8, 8, 1, 5, C.accent)     -- node/pip ON TOP of the track (sub 5)
                        b:Hit(px - bsz / 2, ty + 14 + bsz / 2, bsz, bsz / 2, nil, boss.name or "Boss",
                            "Killed at " .. Util.duration(boss.atSec)
                            .. (boss.killDps and ("   Your DPS: " .. Util.shortNum(boss.killDps)) or ""))
                    end
                end

                -- Deaths BELOW the track: a red pip on the track, a stem down, then a gravestone
                -- (hover for who died). Nudge each right so they never overlap.
                local deaths = {}
                for _, boss in ipairs(bosses) do
                    for _, d in ipairs(boss.deathList or {}) do
                        deaths[#deaths + 1] = { atSec = boss.atSec or 0, d = d, boss = boss.name }
                    end
                end
                table.sort(deaths, function(a2, b2) return a2.atSec < b2.atSec end)
                local gw, gh, lastX = 18, 22, -1e9
                for _, dd in ipairs(deaths) do
                    local px = mx(dd.atSec)
                    if px < lastX + gw + 4 then px = lastX + gw + 4 end
                    if px > x + trackW - gw then px = x + trackW - gw end
                    lastX = px
                    b:Box(px - 1, ty, 2, 44, 1, 3, { 0.5, 0.52, 0.58 })          -- stem: track -> gravestone (sub 3)
                    b:Box(px - 5, ty - 3, 10, 10, 1, 5, theme:Color("c94f4f"))   -- red death pip ON TOP of the track (sub 5)
                    gravestone(b, px - gw / 2, ty - 44, gw, gh)
                    local d = dd.d
                    b:Row(px - gw / 2 - 2, ty - 42, gw + 4, gh + 4, { tipData = {
                        icon = specIconID(d.specId),
                        title = classColorText(d.classFile, d.name or "?"),
                        lines = {
                            { left = "Spec", right = specClassLabel(d.classFile, d.specId) },
                            { left = "Role", right = ML.ROLE_LABEL[d.role] or "-" },
                            { blank = true },
                            { text = "Fell to " .. (dd.boss or "the run"), color = "subtext" },
                        },
                    } })
                end

                -- Your best time at this level: a tall cyan line + diamond pip, drawn LAST so it sits
                -- on top of every other timeline mark.
                if bestTime then
                    local bx = mx(bestTime)
                    b:Box(bx - 1, ty + 22, 3, 66, 1, 4, theme:Color("35d0e0"))     -- tall line (sub 4, above track)
                    b:Box(bx - 6, ty + 4, 12, 12, 1, 6, theme:Color("18b8c8"))     -- diamond pip, top of everything (sub 6)
                    b:Tex(bx - 8, ty + 40, 16, 16, "crown", nil, { 1, 0.82, 0.2 }) -- gold crown = your record
                    local d2 = (run.duration or 0) - bestTime
                    local btxt = "Best at " .. Util.keyLabel(run.level) .. ": " .. Util.duration(bestTime)
                        .. (d2 > 0.5 and ("   (this run: +" .. Util.duration(d2) .. ")") or (d2 < -0.5 and "   (this run set it!)" or ""))
                    -- Hover zone ON the crown + line + pip (was sitting well below the track).
                    b:Hit(bx - 10, ty + 42, 20, 70, nil, "Your best time", btxt)
                end

                b:Label("0:00", x, ty - 76, C.subtext, 10)
                b:Label(Util.duration(tmax), x + trackW - 46, ty - 76, C.subtext, 10)
                y = ty - 90
            end
        end,
    })
    theme.FONT = prevFont   -- restore the UI font now the modal's fontstrings are built

    -- Scale the whole scoreboard by the configured target (default 1.5x), capped so it still fits
    -- the screen. Tune with /ledger scale <n>.
    local target = tonumber(DB.Settings().scoreboardScale) or 1.5
    target = math.max(0.5, math.min(3, target))
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    local fw, fh = sb.frame:GetWidth(), sb.frame:GetHeight()
    local scale = target
    if fw and fw > 0 and fh and fh > 0 then
        scale = math.max(0.5, math.min(target, (pw - 30) / fw, (ph - 30) / fh))
    end
    sb.frame:SetScale(scale)
    sb:Open()

    -- Optional celebratory sound when the scoreboard opens. "END" plays only for the end-of-run
    -- popup; "ALWAYS" plays every time the scoreboard is viewed.
    local st = DB.Settings()
    if st.scoreboardSound then
        local when = st.scoreboardSoundWhen or "END"
        if when == "ALWAYS" or opts.postRun then
            if theme.PlaySound then theme:PlaySound(st.scoreboardSoundKey or "VictoryFanfare", "Master") end
        end
    end
end

-- Post-run auto-popup (gated by the postRunSummary setting) just opens the scoreboard.
function UI.ShowPostRun(run)
    UI.ShowScoreboard(run, { postRun = true })
end

-- Watcher created + registered ONCE, lazily, but its RegisterEvent is never called from the
-- end-of-run path (which runs during the protected challenge-mode completion and taints). We flip
-- `pendingSummary` to arm it; the handler stays registered and only acts when something is pending.
local function ensureSummaryWatcher()
    if summaryWatcher then return end
    summaryWatcher = CreateFrame("Frame")
    summaryWatcher:SetScript("OnEvent", function()
        if pendingSummary then local r = pendingSummary; pendingSummary = nil; pcall(UI.ShowPostRun, r) end
    end)
    summaryWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
end
ensureSummaryWatcher()   -- at file load (clean context), not from the protected completion path

function UI.QueuePostRun(run)
    if InCombatLockdown() then
        pendingSummary = run   -- shown when PLAYER_REGEN_ENABLED fires (watcher already registered)
    else
        pcall(UI.ShowPostRun, run)
    end
end
