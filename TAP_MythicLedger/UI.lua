-- TAP: Mythic Ledger - UI.lua
-- The module's single page, an internal tab bar (Overview / Runs / Dungeons / Characters /
-- Players / Bests / Settings / Debug) with Run-Details and Player-Details sub-views, plus the
-- post-run summary modal. Tables are Lua-sorted/filtered row loops rendered into the suite's
-- shared scroll frame (TAP has no table widget), styled with the shared Builder widgets.

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
local view = { season = "current", character = "all", detailRun = nil, detailPlayer = nil, detailDungeon = nil, detailCharacter = nil, review = nil,
    progMetric = "score", progView = "run", progRange = "all" }   -- progression chart: metric + run/week/level view + date range
-- Per-run player-review target (object refs, so it works for both saved and unsaved/preview runs).
local reviewRunRef, reviewMemberRef = nil, nil

-- Pooled hoverable GameIcons for the score-card breakdowns (real Blizzard tooltip on hover). Each
-- surface gets its OWN pool via makeIconPool() so indices never collide during a single render - the
-- group-utility, interrupt, dispel, and avoidable breakdowns can all draw at once. Returns the pooled
-- accessor plus its pool table (a caller may hide leftovers from the pool directly).
local function makeIconPool()
    local pool = {}
    return function(theme, parent, i, size)
        local gi = pool[i]
        if not gi then gi = theme:GameIcon(parent, { size = size }); pool[i] = gi end
        if gi:GetParent() ~= parent then gi:SetParent(parent) end
        gi:SetSize(size, size)
        return gi
    end, pool
end
local guIcon = makeIconPool()       -- GROUP UTILITY tiles
local kickIcon = makeIconPool()     -- INTERRUPT breakdown
local dispIcon = makeIconPool()     -- DISPEL breakdown
local avoidIcon, avoidIconPool = makeIconPool()   -- AVOIDABLE-damage breakdown (pool hidden directly, ~:3818)

-- Shared OnMouseUp for breakdown spell icons: read the catalog entry + dungeon off the FRAME rather than
-- capturing them in a fresh per-render closure. These icons are session-lived pooled frames, so a captured
-- closure would pin the whole run (and, for a preview run, its heavy score result) forever. Frame-field
-- pattern mirrors DungeonGuide's icon handler.
local function iconOpenGuide(self)
    if self._catEntry and ML.DungeonGuide and ML.DungeonGuide.SelectAndOpen then
        ML.DungeonGuide.SelectAndOpen(self._dungeon, self._catEntry)
    end
end

-- The Builder stat-tile style for the current cardStyle setting (CLEAN/PANEL/COMPACT -> clean/panel/
-- compact). Nil-safe so every stat-tile surface renders the SAME style: the call sites used to drift
-- between no fallback and `or "compact"`. In practice cardStyle is always one of the three keys (its
-- DB default is COMPACT), so this is behaviour-identical - the fallback only hardens a corrupt setting.
local TILE_STYLE = { CLEAN = "clean", PANEL = "panel", COMPACT = "compact" }
local function tileStyle() return TILE_STYLE[DB.Settings().cardStyle] or "compact" end

-- Best-effort spell display name (Blizzard API) for inline labels beside a spell icon.
local function spellNameOf(id)
    if not id then return nil end
    local n
    if _G.C_Spell and _G.C_Spell.GetSpellName then n = _G.C_Spell.GetSpellName(id) end
    if not n and _G.GetSpellInfo then n = _G.GetSpellInfo(id) end
    return n
end

-- Text/accent colors for cards with a forced-dark background (the dungeon-art hero cards). The theme's
-- own text goes DARK on light mode and vanishes over the art, so these stay light on BOTH themes.
local ON_ART, ON_ART_SUB = { 0.97, 0.98, 1.0 }, { 0.80, 0.84, 0.92 }
local ILVL_GOLD = { 0.788, 0.655, 0.416 }   -- item-level badge tint (matches the old inline "ilvl" gold)
-- A lightened accent (blended halfway to white) that reads over the dark art regardless of theme.
local function artAccent(C) return { (C.accent[1] + 1) / 2, (C.accent[2] + 1) / 2, (C.accent[3] + 1) / 2 } end
local function artAccentHex(C)
    local a = artAccent(C)
    return string.format("%02x%02x%02x", math.floor(a[1] * 255 + 0.5), math.floor(a[2] * 255 + 0.5), math.floor(a[3] * 255 + 0.5))
end

-- Fixed palette the end-of-run scoreboard renders on, so it's theme-AGNOSTIC: the scoreboard is what it
-- is on every UI theme (and always readable - its art backdrop is dark, so light-mode theme text would
-- vanish). Swapped in only while the modal is built (see ShowScoreboard); the 9 keys match every theme
-- palette so Modal / StatTile / Builder all pick it up.
local SB_PALETTE = {
    bg      = { 0.055, 0.058, 0.070 },
    sidebar = { 0.075, 0.080, 0.095 },
    panel   = { 0.092, 0.098, 0.118 },
    card    = { 0.130, 0.140, 0.165 },
    hover   = { 0.185, 0.195, 0.225 },
    border  = { 0.240, 0.250, 0.290 },
    accent  = { 0.63, 0.42, 0.94 },   -- Mythic Ledger purple (fixed, brand identity)
    text    = { 0.93, 0.95, 0.98 },
    subtext = { 0.63, 0.67, 0.75 },
}
local runFilter    = { character = nil, mapId = nil, status = nil, playerKey = nil, level = nil, role = nil }
local runSort      = { key = "date", dir = "desc" }
local dungeonRunSort = { key = "date", dir = "desc" }   -- shared sort for the character/dungeon detail run tables
local playerFilter = { search = "", role = nil, favorite = false, minShared = 1, class = nil, spec = nil }
local playerSort   = { key = "runs", dir = "desc" }
-- Measured size + policy preview for the Tracking tab. Walking every run is far too costly to repeat on
-- each render (the settings page redraws on every toggle), so the whole thing is measured in ONE pass,
-- cached, and cleared by any action that could change it.
local storageStats = nil
-- "1 run" / "3 runs". Sentences that count things go through this, so a count of 1 or 0 never produces
-- the mangled plural you get from splicing "s" into a fixed verb.
local function nRuns(n) return string.format("%d run%s", n or 0, (n == 1) and "" or "s") end
-- Staged RUN HISTORY policy. Every control writes here, and only Apply commits + enforces, so the
-- destructive half of this page can never fire from a stray click.
local retentionPending  = nil  -- staged run ceiling (0 = unlimited)
local retScopePending   = nil  -- staged full-detail window: ALL / SEASON / EXPANSION / DAYS
local retKeepTopPending = nil  -- staged "never delete a top run"
local retActionPending  = nil  -- staged action beyond the window: TRIM / DELETE
local retDaysPending    = nil  -- staged window length when the window is DAYS
local retAutoPending    = nil  -- staged "apply automatically"
local charSort     = { key = "runs", dir = "desc" }
local vaultSort    = { key = "keys", dir = "desc" }   -- Weekly Vault table (top-8 keys this reset)
local statsFilter  = { season = "current", character = nil, mapId = nil, minKey = 0 }
local dungeonFilter = { text = "" }   -- Dungeons tab type-to-filter (applied at 3+ characters)
local dungeonSearch                    -- persistent SearchBox frame - survives the builder Reset so it keeps focus

-- Forward declarations: this score-helper cluster is defined much lower (near the scoreboard code)
-- but is used earlier by renderRunDetails (the run-details party table). Declaring the locals up here
-- lets those earlier closures capture them as upvalues; without this they resolved to nil globals
-- (settings error "attempt to call a nil value" at the first one, runScores).
local runScores, gradeColor, memberScore, scoreTipLines, renderPlayerReview
-- Defined later (by the character-details page) but used earlier by the player-details page too, so
-- both render specs with the identical hero card. Forward-declared here to capture it as an upvalue.
local specHeroCard

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
local pageState = { runs = 1, dungeons = 1, characters = 1, players = 1, playerRuns = 1, size = 20 }

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
    { "overview", "Summary", "layout-grid" }, { "runs", "Runs", "list" }, { "dungeons", "Dungeons", "map" },
    { "characters", "Characters", "users" }, { "progression", "Progression", "activity" },
    { "players", "Players", "user" }, { "bests", "Bests", "trophy" },
    { "settings", "Settings", "settings" }, { "debug", "Debug", "tools" },
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

-- Overview character scope: nil = all characters, otherwise a character fullName filter.
local function scopeCharacter()
    if not view.character or view.character == "all" then return nil end
    return view.character
end

local function seasonChoices()
    local curId = currentSeason()
    local curName = curId and ML.SeasonLabel(curId)
    local c = {
        { "current", curName and ("Current Season (" .. curName .. ")") or "Current Season" },
        { "all", "All Seasons" },
    }
    for _, id in ipairs(History.SeasonsPresent()) do
        if id ~= curId then c[#c + 1] = { id, ML.SeasonLabel(id) } end   -- current is already the option above
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

-- Keystone-upgrade tier for a TIMED run: "+1" / "+2" / "+3" (the number of levels the key went up,
-- i.e. how well the timer was beaten). nil for depleted/abandoned runs and for older records that
-- predate upgrade capture.
local function upgradeTier(r)
    if r.status == STATUS.TIMED and type(r.keystoneUpgrade) == "number" and r.keystoneUpgrade > 0 then
        return "+" .. r.keystoneUpgrade
    end
    return nil
end

-- Result text WITH the keystone-upgrade tier folded in: "Timed +2" (falls back to plain "Timed"
-- when a record has no upgrade data), "Depleted", "Abandoned".
local function statusUpgradeText(r)
    local tier = upgradeTier(r)
    return tier and (statusText(r.status) .. " " .. tier) or statusText(r.status)
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

-- Reverse map: spec ICON fileID -> { name, id, role }. Some data sources (C_DamageMeter) hand us a
-- party member's spec ICON but no spec id, so GetSpecializationInfoByID can't name the spec. Build the
-- map once from the client's own class/spec tables and look the icon up to recover the name. Rebuilds
-- until it succeeds (spec tables can be empty very early in load), then caches.
local iconToSpec
local function ensureSpecIconMap()
    if iconToSpec and next(iconToSpec) then return iconToSpec end
    local map = {}
    if GetNumClasses and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        for classID = 1, (GetNumClasses() or 0) do
            for i = 1, (GetNumSpecializationsForClassID(classID) or 0) do
                local ok, id, name, _, icon, role = pcall(GetSpecializationInfoForClassID, classID, i)
                local ic = ok and ML.ReadNum(icon)
                if ic then map[ic] = { name = ML.ReadStr(name), id = id, role = role } end
            end
        end
    end
    iconToSpec = map
    return iconToSpec
end

local function classRGB(classFile)
    local c = classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
    return c and { c.r, c.g, c.b } or nil
end

-- Class color as an "RRGGBB" hex (for tipData lcolor/rcolor), or nil.
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

-- The specialization's own name (e.g. "Fire"), or nil if the spec isn't known. Resolves from the spec
-- id first; failing that (icon-only data with no id), recovers the name from the spec ICON.
local function specName(specId, specIcon)
    if specId and GetSpecializationInfoByID then
        local ok, _id, nm = pcall(GetSpecializationInfoByID, specId)
        local s = ok and ML.ReadStr(nm)
        if s and s ~= "" then return s end
    end
    if specIcon then
        local m = ensureSpecIconMap()[ML.ReadNum(specIcon) or specIcon]
        if m and m.name and m.name ~= "" then return m.name end
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
-- One labelled dropdown in a horizontal scope row. The label is anchored to the dropdown's LEFT
-- edge (vertically centred) so "Season" / "Character" always line up with the box, not float above
-- it. Returns the x just past this control so the caller can place the next one beside it.
local function scopeControl(b, C, x, y, labelText, ddW, title, tip, choices, getVal, setVal)
    local lbl = b:Label(labelText, x, y, C.subtext)
    local labelW = (lbl:GetStringWidth() or 40) + 12
    local dd = b:Dropdown(x + labelW, y)
    lbl:ClearAllPoints(); lbl:SetPoint("LEFT", dd, "LEFT", -labelW, 0)   -- centre label on the box
    T(b, dd, title, tip):SetChoices(ddW, choices, getVal, setVal)
    return x + labelW + ddW + 20
end

local function renderSeasonSelector(b, C, x, y, w, win)
    scopeControl(b, C, x, y, "Season", 200, "Season",
        "Scope every stat on this page to a season, or show all seasons.",
        seasonChoices(), function() return view.season end,
        function(v) view.season = v; if win then win:Refresh() end end)
    return y - 34
end

-- Character choices for the Overview scope row: "All Characters" plus every tracked toon,
-- class-colored. Value "all" = no character filter.
local function overviewCharChoices()
    local c = { { "all", "All Characters" } }
    for _, ch in ipairs(History.CharacterList()) do
        local nm = (ch.name and ch.name ~= "?" and ch.name) or ch.fullName or "Unknown"
        c[#c + 1] = { ch.fullName, classColorText(ch.classFile, nm) }
    end
    return c
end

-- Overview scope row: Season + Character side by side, sharing the aligned control helper.
local function renderOverviewScope(b, C, x, y, w, win)
    local nx = scopeControl(b, C, x, y, "Season", 190, "Season",
        "Scope every stat below to a season, or show all seasons.",
        seasonChoices(), function() return view.season end,
        function(v) view.season = v; if win then win:Refresh() end end)
    scopeControl(b, C, nx, y, "Character", 200, "Character",
        "Show stats for all characters combined, or focus on a single character.",
        overviewCharChoices(), function() return view.character or "all" end,
        function(v) view.character = v; if win then win:Refresh() end end)
    return y - 34
end

-- Dungeon art as a card backdrop with a COVER crop (keeps the ~2.5:1 EJ art's aspect and crops to a
-- centred band so it fills without smearing). Shared with the Dungeon Guide banner: ML.DungeonArt.
local dungeonArt = ML.DungeonArt

-- Dark base for the KPI/highlight hero cards, so they read in the same dark, art-card family as the
-- dungeon-hero cards even though they carry no background art.
local HERO_CARD_BG = { 0.05, 0.055, 0.07 }

-- The shared hero-card CHROME: 1px border, a base fill, optional dimmed dungeon art, then the accent
-- left edge - identical geometry on every hero card (stat / entity / dungeon / top-run) so the border
-- inset and edge can't drift between them. Draws only the shell; the caller fills the content. `base`
-- defaults to black; `art` (texture id) + `artAlpha` lay the background; `accent` is the left-edge color.
local function cardShell(b, C, cx, cy, cw, ch, opts)
    b:Box(cx - 1, cy + 1, cw + 2, ch + 2, 0.9, 0, C.border)          -- 1px border
    b:Box(cx, cy, cw, ch, 1, 1, opts.base or { 0, 0, 0 })            -- base fill
    if opts.art then dungeonArt(b, cx, cy, cw, ch, opts.art, opts.artAlpha or 0.42) end
    b:VRule(cx + 1, cy, cy - ch, 2, opts.accent)                     -- accent left edge
end

-- A KPI / highlight card in the STANDARD dungeon-hero visual language: dark base, 1px border, an accent
-- left edge, a large left icon, then a label + big value (+ optional sub line). This is what keeps the
-- Overview and Bests hero cards consistent with the dungeon-hero cards on the Dungeons tab. `accent`
-- (hex or {r,g,b}) tints the edge, label and (bundled) icon. Provide either `icon` (a bundled icon,
-- tinted with the accent) or `drawIcon(b, ix, iy, isz)` for a custom glyph (e.g. a class crest). The
-- value keeps its own inline color if it has one. Optional `onClick` / `tipData` (hover) wire a hit region.
local function heroStatCard(b, C, cx, cy, cw, ch, opts)
    local acc = opts.accent or C.accent
    if type(acc) == "string" then acc = b.theme:Color(acc, C.accent) end
    cardShell(b, C, cx, cy, cw, ch, { base = HERO_CARD_BG, accent = acc })
    local innerW = cw - 28   -- full text column width (14px inset each side)
    -- Every text element is width-clamped to the card so a long label / name / context line can
    -- never spill past the right border. Label + sub span the FULL width (the icon sits between them,
    -- inline with the value), so the widest strings still fit in a narrow grid cell.
    b:Label(opts.label or "", cx + 14, cy - 9, acc, 10):SetWidth(innerW)
    local isz = opts.iconSize or 40
    local vx = cx + 14
    if opts.drawIcon then opts.drawIcon(b, cx + 14, cy - 24, isz); vx = cx + 14 + isz + 12
    elseif opts.icon then b:Tex(cx + 14, cy - 24, isz, isz, opts.icon, nil, acc); vx = cx + 14 + isz + 12 end
    b:Label(opts.value or DASH, vx, cy - 34, opts.valueColor or ON_ART, opts.valueSize or 18)
        :SetWidth(math.max(10, cx + cw - 14 - vx))
    if opts.sub and opts.sub ~= "" then b:Label(opts.sub, cx + 14, cy - 66, ON_ART_SUB, 10):SetWidth(innerW) end
    if opts.onClick or opts.tipData then
        local hit = b:Hit(cx, cy, cw, ch, opts.onClick)
        if opts.tipData and b.theme.SetTipData then
            opts.tipData.anchor = opts.tipData.anchor or "ANCHOR_CURSOR"
            b.theme:SetTipData(hit, opts.tipData)
        end
    end
end

-- A reflowing grid of headline StatTiles (the player- and character-details "hero stats" row). Columns
-- fit to width; each `tile(hkey, value, formatted, opts)` places the next cell (opts overrides the
-- HeroStatStyle label/color/icon/tip). Returns the drawer plus `finish()` -> the y below the grid.
local function heroTileGrid(b, x, y, w)
    local setStyle = tileStyle()
    local style = (setStyle == "panel" or not setStyle) and "clean" or setStyle
    local th, tw, gap = 92, 150, 12
    local cols = math.max(1, math.floor((w + gap) / (tw + gap)))
    local gx, gy, idx = tw + gap, th + 12, 0
    local function tile(hkey, value, formatted, opts)
        opts = opts or {}
        local col, rowi = idx % cols, math.floor(idx / cols); idx = idx + 1
        local s = ML.HeroStatStyle(hkey, value, formatted)
        b:StatTile(x + col * gx, y - rowi * gy, {
            style = style, iconSize = 40, label = opts.label or s.label, value = formatted or DASH,
            width = tw, height = th,
            accent = opts.color or s.color, icon = opts.icon or s.icon, tipData = opts.tipData or s.tipData,
        })
    end
    return tile, function() return y - math.ceil(idx / cols) * gy - 6 end
end

-- The canonical ENTITY hero card, in the exact same visual language as the dungeon-hero cards: dark
-- base (+ optional background art), 1px border, an accent left edge, a LARGE left icon (a square
-- portrait/portal, or a 2:1 banner via iconWide), a title with an optional right-aligned accent value,
-- and up to a few subtext stat lines. This is the ONE hero-card look shared by dungeons, bosses and
-- top runs so every hero across the module reads the same. `iconTint` tints the icon (nil = full color
-- portrait/portal); `art` lays dimmed background art; `onClick` / `tipData` wire a hit region.
local function heroCard(b, C, cx, cy, cw, ch, opts)
    local acc = opts.accent or C.accent
    if type(acc) == "string" then acc = b.theme:Color(acc, C.accent) end
    cardShell(b, C, cx, cy, cw, ch, { art = opts.art, artAlpha = opts.artAlpha,
        accent = opts.art and artAccent(C) or acc })
    local isz = opts.iconSize or 48
    local ih = opts.iconWide and math.floor(isz / 2) or isz
    local tx = cx + 12
    if opts.drawIcon then
        opts.drawIcon(b, cx + 12, cy - (ch - isz) / 2, isz); tx = cx + 12 + isz + 14
    elseif opts.icon then
        b:Tex(cx + 12, cy - (ch - ih) / 2, isz, ih, opts.icon, opts.iconCoords, opts.iconTint, 1)
        tx = cx + 12 + isz + 14
    end
    b:Label(opts.title or "", tx, cy - 13, ON_ART, opts.titleSize or 16)
    if opts.titleRight then
        b:Label(opts.titleRight, cx + cw - (opts.titleRightW or 56), cy - 14, opts.art and artAccent(C) or acc, opts.titleSize or 17)
    end
    -- Item level: a compact gold badge, right-aligned on the hero-tree line and measured after layout
    -- so a long hero name can never push it off the card edge (the old inline "213 ilvl" overflowed).
    if opts.ilvl then
        local fs = b:Label(opts.ilvl, cx + cw - 12, cy - (opts.ilvlY or 53), ILVL_GOLD, 11)
        local wdt = (fs.GetStringWidth and fs:GetStringWidth()) or 26
        b:put(fs, cx + cw - 12 - wdt, cy - (opts.ilvlY or 53))
    end
    local ly = cy - 37
    for _, ln in ipairs(opts.lines or {}) do
        if ln and ln ~= "" then b:Label(ln, tx, ly, ON_ART_SUB, 11); ly = ly - 16 end
    end
    if opts.onClick or opts.tipData then
        local hit = b:Hit(cx, cy, cw, ch, opts.onClick, opts.tipTitle, opts.tipBody)
        if opts.tipData and b.theme.SetTipData then
            opts.tipData.anchor = opts.tipData.anchor or "ANCHOR_CURSOR"
            b.theme:SetTipData(hit, opts.tipData)
        end
    end
end

----------------------------------------------------------------------
-- Overview.
----------------------------------------------------------------------
local function renderOverview(b, C, x, y, w, win)
    y = renderOverviewScope(b, C, x, y, w, win)
    local charScope = scopeCharacter()
    local o = History.Overview(scopeSeason(), charScope)
    local showChar = (charScope == nil)

    local accHex = string.format("%02x%02x%02x",
        math.floor(C.accent[1] * 255 + 0.5), math.floor(C.accent[2] * 255 + 0.5), math.floor(C.accent[3] * 255 + 0.5))
    local function accent(s) return "|cff" .. accHex .. s .. "|r" end

    -- Most-played dungeon: a full-width banner across the top, its Encounter-Journal art as a dimmed
    -- backdrop (cover-cropped so the wide/short shape doesn't zoom-smear it).
    do
        local d = o.topDungeonInfo
        local bh = 96
        local aHex = artAccentHex(C)
        local function acc(s) return "|cff" .. aHex .. s .. "|r" end   -- light accent, readable over the art
        local mi = d and d.mapId and API.GetMapInfo(d.mapId)
        cardShell(b, C, x, y, w, bh, { art = d and (API.DungeonBackground(d.name) or (mi and mi.texture)),
            artAlpha = 0.5, accent = artAccent(C) })
        dungeonGlyph(b, x + 16, y - (bh - 64) / 2, 64, d and d.mapId)   -- large portal icon (like the dungeon cards)
        local tx = x + 96
        b:Label("MOST-PLAYED DUNGEON", tx, y - 13, artAccent(C), 10)
        if d then
            b:Heading(d.name or "Dungeon", tx, y - 32, "h1", { textColor = ON_ART })
            b:Label(d.highestTimed and ("Highest timed  " .. acc("+" .. d.highestTimed)) or "No timed key yet",
                tx, y - 64, ON_ART, 12)
            b:Label(acc(tostring(d.n)) .. (d.n == 1 and " run" or " runs"), tx, y - 82, ON_ART_SUB, 12)
        else
            b:Label("No runs recorded yet.", tx, y - 48, ON_ART_SUB, 12)
        end
        y = y - bh - 14
    end

    -- Summary tiles: hero cards in the dungeon-hero visual language (dark base, accent left edge, large
    -- left icon) with the WoW-quality color scale (ML.HeroStatStyle) tinting each card + a supporting
    -- subtext line (ML.HeroStatSubtext). The two highlight cards (most-played character, run outcomes)
    -- ride along in the same responsive grid so everything reads as one block.
    local scopeLabel = scopeSeason() and "This season" or "All seasons"
    local th = 80   -- hero-card proportions (label / icon+value / context rows)

    -- As many ~160px columns as fit (2-4), each stretched to share the row evenly.
    local minTile, gapx = 160, 12
    local cols = math.max(2, math.min(4, math.floor((w + gapx) / (minTile + gapx))))
    local tw = math.floor((w - gapx * (cols - 1)) / cols)
    local gx, gy = tw + gapx, th + 12
    local function cellXY(i)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        return x + col * gx, y - row * gy
    end

    local tiles = {
        { "runs",          o.runs,         tostring(o.runs) },
        { "timed",         o.timed,        tostring(o.timed) },
        { "timedPercent",  o.timedPct,     o.timedPct and Util.percent(o.timedPct) or DASH },
        { "highestTimed",  o.highestTimed, o.highestTimed and ("+" .. o.highestTimed) or DASH },
        { "averageKey",    o.avgLevel,     o.avgLevel and string.format("+%.1f", o.avgLevel) or DASH },
        { "averageTime",   o.avgDuration,  o.avgDuration and Util.duration(o.avgDuration) or DASH },
        { "averageDeaths", o.avgDeaths,    o.avgDeaths and string.format("%.2f", o.avgDeaths) or DASH },
        { "playersMet",    o.playersMet,   tostring(o.playersMet or 0) },
        { "returning",     o.returning,    tostring(o.returning) },
    }
    local idx = 0
    for _, t in ipairs(tiles) do
        idx = idx + 1
        local px, py = cellXY(idx)
        local s = ML.HeroStatStyle(t[1], t[2], t[3])
        local sub = ML.HeroStatSubtext(t[1], o, scopeLabel)
        heroStatCard(b, C, px, py, tw, th, {
            accent = s.color, icon = s.icon, label = s.label, value = t[3] or DASH,
            sub = sub.sub or (sub.footer and sub.footer[1]) or nil, tipData = s.tipData,
        })
    end

    -- Most-played character, sized to a grid cell (class crest as its icon). Skipped when a single
    -- character is already in scope; the run-outcomes card slides up to fill in.
    if showChar then
        idx = idx + 1
        local px, py = cellXY(idx)
        local c = o.topCharInfo
        heroStatCard(b, C, px, py, tw, th, {
            accent = classRGB(c and c.classFile) or C.accent,
            label = "MOST-PLAYED CHARACTER",
            drawIcon = c and function(bb, ix, iy, isz) classGlyph(bb, ix, iy, isz, c.classFile) end or nil,
            value = c and classColorText(c.classFile, c.name or c.fullName or "?") or "No runs yet",
            sub = c and (accent(tostring(c.n)) .. (c.n == 1 and " run" or " runs")) or nil,
        })
    end

    -- Run outcomes: timed / depleted / abandoned, color-coded inline.
    do
        idx = idx + 1
        local px, py = cellXY(idx)
        heroStatCard(b, C, px, py, tw, th, {
            accent = C.accent, icon = "list-check", label = "RUN OUTCOMES",
            value = string.format("|cff33dd66%d|r / |cffe0a030%d|r / |cff9098a8%d|r", o.timed, o.depleted, o.abandoned),
            sub = "timed / depleted / abandoned",
        })
    end

    local rows = math.ceil(idx / cols)
    y = y - rows * gy - 6

    -- ANALYTICS: weekly TRENDS + your hardest dungeons. New VIEWS over data already recorded - read-only,
    -- reusing the persisted per-run score summaries (Store.Summary) and the per-dungeon aggregates.
    do
        local trend = (History.WeeklyTrend and History.WeeklyTrend(scopeSeason(), charScope, 4)) or {}
        local weeksWithRuns = 0
        for _, wk in ipairs(trend) do if (wk.runs or 0) > 0 then weeksWithRuns = weeksWithRuns + 1 end end

        if weeksWithRuns >= 2 then
            y = b:Section("THIS WEEK", x, y); y = y - 30

            -- latest + previous non-nil value of a metric across the weekly series (oldest -> newest).
            local function curPrev(key)
                local cur, prev
                for i = #trend, 1, -1 do
                    local v = trend[i][key]
                    if type(v) == "number" then
                        if cur == nil then cur = v elseif prev == nil then prev = v; break end
                    end
                end
                return cur, prev
            end

            local gap, ch = 12, 68
            local cardW = math.floor((w - gap * 3) / 4)
            -- One card: dark panel + label + this-week value + a "vs last week" delta chip. `neutral` shows
            -- the delta in plain subtext (for a volume metric like run count, where more isn't "better").
            local function trendCard(slot, key, label, fmtVal, fmtDelta, higherIsGood, neutral)
                local cx = x + slot * (cardW + gap)
                b:Box(cx - 1, y + 1, cardW + 2, ch + 2, 0.9, 0, C.border)
                b:Box(cx, y, cardW, ch, 1, 1, { 0.05, 0.055, 0.07 })
                b:Label(label, cx + 10, y - 11, C.subtext, 10)
                local cur, prev = curPrev(key)
                b:Label(cur and fmtVal(cur) or DASH, cx + 10, y - 29, C.text, 17)
                if cur and prev and math.abs(cur - prev) > 1e-9 then
                    local d = cur - prev
                    local col = neutral and C.subtext
                        or (((d > 0) == higherIsGood) and { 0.42, 0.82, 0.45 } or { 0.90, 0.42, 0.42 })
                    local dfs = b:Label((d > 0 and "+" or "-") .. fmtDelta(d), cx + 10, y - 51, col, 11)
                    b:Label("vs last week", cx + 15 + (dfs:GetStringWidth() or 26), y - 51, C.subtext, 10)
                elseif cur and prev then
                    b:Label("same as last week", cx + 10, y - 51, C.subtext, 10)
                else
                    b:Label("no prior week yet", cx + 10, y - 51, C.subtext, 10)
                end
            end

            trendCard(0, "runs", "RUNS",
                function(v) return tostring(math.floor(v + 0.5)) end,
                function(d) return tostring(math.floor(math.abs(d) + 0.5)) end, true, true)
            trendCard(1, "timedPct", "TIMED %",
                function(v) return string.format("%.0f%%", v * 100) end, function(d) return string.format("%.0f%%", math.abs(d) * 100) end, true)
            trendCard(2, "avgScore", "AVG SCORE",
                function(v) return string.format("%.0f", v) end, function(d) return string.format("%.0f", math.abs(d)) end, true)
            trendCard(3, "avgDeaths", "AVG DEATHS",
                function(v) return string.format("%.1f", v) end, function(d) return string.format("%.1f", math.abs(d)) end, false)
            y = y - ch - 20
        end

        -- TROUBLE SPOTS: your hardest dungeons this scope, ranked by fail rate + your avg deaths.
        local dstats = (History.DungeonStats and History.DungeonStats(scopeSeason(), charScope)) or {}
        local trouble = {}
        for _, d in ipairs(dstats) do
            local completed = (d.totals and (d.totals.completed or 0)) or 0
            if completed >= 1 then
                local sc = (1 - (d.timedPct or 0)) * 100 + (d.avgDeaths or 0) * 12
                if sc > 0.5 then trouble[#trouble + 1] = { d = d, score = sc } end
            end
        end
        table.sort(trouble, function(a, bb) return a.score > bb.score end)
        if #trouble > 0 then
            y = b:Section("TROUBLE SPOTS", x, y); y = y - 26
            local maxScore = trouble[1].score
            for i = 1, math.min(3, #trouble) do
                local d = trouble[i].d
                b:Row(x, y, w, 24, { index = i })
                b:Label(d.name or ("map " .. tostring(d.mapId)), x + 12, y - 6, C.text, 12)
                b:Label(string.format("%.0f%% timed", (d.timedPct or 0) * 100), x + w - 330, y - 6, C.subtext, 11)
                b:Label(string.format("%.1f deaths", d.avgDeaths or 0), x + w - 210, y - 6, C.subtext, 11)
                local bx, bw = x + w - 116, 100
                b:Box(bx, y - 8, bw, 8, 0.16, 1, C.border)
                b:Box(bx, y - 8, bw * math.max(0.05, trouble[i].score / (maxScore > 0 and maxScore or 1)), 8, 0.95, 2, { 0.90, 0.45, 0.30 })
                y = y - 26
            end
        end
    end

    return y - 8
end

----------------------------------------------------------------------
-- Runs list.
----------------------------------------------------------------------
-- One run's sortable value for `key`. "metric" is the row's PRIMARY output (HPS for healers, else DPS) -
-- used by the detail tables' combined DPS/HPS column. Unknown keys (and "date") fall back to the date.
local function runSortValue(r, key)
    if key == "key" then return r.level or 0
    elseif key == "duration" then return r.duration or 0
    elseif key == "deaths" then return r.deaths or -1
    elseif key == "dps" then return r.playerStats and r.playerStats.dps or -1
    elseif key == "hps" then return r.playerStats and r.playerStats.hps or -1
    elseif key == "metric" then
        local s = r.playerStats; if not s then return -1 end
        return ((r.character and r.character.role) == "HEALER") and (s.hps or -1) or (s.dps or -1)
    end
    return r.completedAt or 0
end

-- Sort a run list in place by a { key, dir } state. Ties break toward the more recent run.
local function sortRuns(runs, sort)
    local key, mult = sort.key, (sort.dir == "desc") and 1 or -1
    table.sort(runs, function(a, bb)
        local av, bv = runSortValue(a, key), runSortValue(bb, key)
        if av == bv then return (a.completedAt or 0) > (bb.completedAt or 0) end
        return (av > bv) == (mult == 1)
    end)
    return runs
end

local function sortedRuns()
    local runs = History.FilterRuns({
        seasonId = scopeSeason(), character = runFilter.character, mapId = runFilter.mapId,
        status = runFilter.status, playerKey = runFilter.playerKey, role = runFilter.role,
        keyMin = runFilter.level, keyMax = runFilter.level,   -- a specific key level (nil = any)
    })
    return sortRuns(runs, runSort)
end

-- Distinct dungeon choices (from runs in the current season scope), for the Runs filter.
local function runsDungeonChoices()
    local seen, list = {}, {}
    for _, r in ipairs(History.FilterRuns({ seasonId = scopeSeason() })) do
        if r.mapId and not seen[r.mapId] then seen[r.mapId] = true; list[#list + 1] = { r.mapId, r.dungeonName or ("Map " .. r.mapId) } end
    end
    table.sort(list, function(a, bb) return tostring(a[2]) < tostring(bb[2]) end)
    table.insert(list, 1, { "all", "All Dungeons" })
    return list
end

-- Distinct key levels present (descending), for the Runs filter.
local function runsKeyChoices()
    local seen, levels = {}, {}
    for _, r in ipairs(History.FilterRuns({ seasonId = scopeSeason() })) do
        if type(r.level) == "number" and not seen[r.level] then seen[r.level] = true; levels[#levels + 1] = r.level end
    end
    table.sort(levels, function(a, bb) return a > bb end)
    local out = { { "all", "All Keys" } }
    for _, lv in ipairs(levels) do out[#out + 1] = { lv, "+" .. lv } end
    return out
end

local STATUS_HEX = ML.STATUS_HEX   -- shared; see Constants.lua

-- Rich tooltip data for a run row: dungeon icon header + color-coded stat lines + party list.
local function runTipData(r)
    local mi = r.mapId and API.GetMapInfo(r.mapId)
    local timeStr = Util.duration(r.duration)
    if r.timeRemaining then
        timeStr = timeStr .. "  (" .. (r.timeRemaining >= 0 and "-" or "+") .. Util.duration(math.abs(r.timeRemaining)) .. ")"
    end
    local role = r.character and r.character.role
    local lines = {
        { left = "Result", right = statusUpgradeText(r), rcolor = STATUS_HEX[r.status] },
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
            lines[#lines + 1] = { left = "  " .. star .. (m.name or "?"),
                right = (specName(m.specId) or "-") .. (m.itemLevel and ("  ·  " .. tostring(m.itemLevel)) or ""),
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
    -- Filter toolbar: Season, Result, Character, Dungeon, Key, Role - flowing across the width.
    local fields = {
        { label = "Season", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, seasonChoices(), function() return view.season end,
                function(v) view.season = v; win:Refresh() end) end },
        { label = "Result", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, {
                { "all", "All" }, { STATUS.TIMED, "Timed" }, { STATUS.DEPLETED, "Depleted" }, { STATUS.ABANDONED, "Abandoned" },
            }, function() return runFilter.status or "all" end,
               function(v) runFilter.status = (v ~= "all") and v or nil; win:Refresh() end) end },
        { label = "Character", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, overviewCharChoices(), function() return runFilter.character or "all" end,
                function(v) runFilter.character = (v ~= "all") and v or nil; win:Refresh() end) end },
        { label = "Dungeon", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, runsDungeonChoices(), function() return runFilter.mapId or "all" end,
                function(v) runFilter.mapId = (v ~= "all") and v or nil; win:Refresh() end) end },
        { label = "Key", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, runsKeyChoices(), function() return runFilter.level or "all" end,
                function(v) runFilter.level = (v ~= "all") and v or nil; win:Refresh() end) end },
        { label = "Role", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, {
                { "all", "All Roles" }, { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "DPS" },
            }, function() return runFilter.role or "all" end,
               function(v) runFilter.role = (v ~= "all") and v or nil; win:Refresh() end) end },
    }
    y = filterBar(b, C, x, y, w - 12, fields)
    if runFilter.playerKey then
        T(b, b:Button(x, y, 170, "Clear player filter", "ghost", function()
            runFilter.playerKey = nil; win:Refresh()
        end), "Clear filter", "Stop filtering the list to a single party member.")
        y = y - 32
    end

    local runs = sortedRuns()
    local rowW = w - 12
    b:Sub(string.format("RUNS (%d)", #runs), x, y); y = y - 26
    if #runs == 0 then
        b:Wrap("No runs recorded yet for this filter. Complete a Mythic+ key and it appears here automatically.",
            x, y, w - 20, C.subtext, 12)
        return y - 30
    end
    local first, last = pagerBar(b, C, x, y, rowW, #runs, "runs", win); y = y - 42

    -- Wider format: DPS and HPS get their own sortable columns.
    local cIcon, cDate, cChar, cDun, cKey, cRes, cDur, cDth, cDps, cHps =
        x + 6, x + 32, x + 140, x + 260, x + 420, x + 466, x + 560, x + 640, x + 700, x + 780

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
    sortHdr(b, C, cDps, y - 2, 40, "DPS", "dps", runSort, win)
    sortHdr(b, C, cHps, y - 2, 40, "HPS", "hps", runSort, win)
    y = y - 26

    for i = first, last do
        local r = runs[i]
        local h = 30
        local yTop = y
        b:Row(x, yTop, rowW, h, { index = i, tipData = runTipData(r),
            onClick = function() view.detailRun = r.id; win:Refresh() end })
        dungeonGlyph(b, cIcon, yTop - 5, 20, r.mapId)
        b:Label(Util.dateShort(r.completedAt), cDate, yTop - 10, C.subtext, 11)
        b:Label(classColorText(r.character and r.character.classFile, r.character and r.character.name or "?"),
            cChar, yTop - 10, C.text, 11)
        b:Label(r.dungeonName or DASH, cDun, yTop - 10, C.text, 11)
        -- Crown marks your best-SCORING run for this dungeon + key level + class/spec (one per combo).
        if r.bestOfKind then b:Tex(cKey - 16, yTop - 10, 13, 13, "crown", nil, { 1, 0.82, 0.2 }) end
        b:Label(Util.keyLabel(r.level), cKey, yTop - 10, C.accent, 12)
        b:Badge(cRes, yTop - 9, { text = statusUpgradeText(r), variant = statusBadgeVariant(r.status) })
        b:Label(Util.duration(r.duration), cDur, yTop - 10, C.text, 11)
        b:Label(Util.numOr(r.deaths, "%d"), cDth + 4, yTop - 10, C.text, 11)
        local ps = r.playerStats
        b:Label(Util.shortNum(ps and ps.dps), cDps, yTop - 10, C.text, 11)
        b:Label(Util.shortNum(ps and ps.hps), cHps, yTop - 10, C.text, 11)
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

-- Shared run TIMELINE: a horizontal track spanning the key's TIME LIMIT (rescaled to the run length
-- if it ran over, with a gold marker where the timer expired). Green = in combat, red = downtime;
-- boss PORTRAITS sit above their kill time, gravestones below each death, and the keystone +1/+2/+3
-- time targets + your best time for this key are marked. Draws its own "TIMELINE" section header and
-- returns the Y below it. Used by BOTH the run-details page and the end-of-run scoreboard, so the two
-- always read identically. `trackW` is the track width (the caller's content/row width).
local function renderRunTimeline(b, C, x, y, trackW, run)
    if not (run.duration and run.duration > 0) then return y end
    local theme = b.theme
    local bosses = run.bosses or {}
    y = y - 8
    y = b:Section("TIMELINE", x, y); y = y - 24
    local th = 8
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
    -- Green combat segments over the base.
    for _, seg in ipairs(run.combat or {}) do
        local sf, ef = fpos(seg[1]), fpos(seg[2])
        if ef > sf then b:Box(x + sf * trackW, ty, (ef - sf) * trackW, th, 1, 1, theme:Color("2f8f4e")) end
    end

    -- Keystone-upgrade time targets: +1 = the timer, +2 = 80% of it, +3 = 60% of it. A bold line
    -- crosses the track; a big label sits below it; hover shows YOUR delta to that target.
    if run.timeLimit and run.timeLimit > 0 then
        local ups = { { "+1", run.timeLimit, "ffd100" }, { "+2", run.timeLimit * 0.8, "ffe38a" }, { "+3", run.timeLimit * 0.6, "b6f0ff" } }
        for _, u in ipairs(ups) do
            local ux, hex = mx(u[2]), u[3]
            b:Box(ux - 2, ty + 4, 4, th + 8, 1, 5, theme:Color(hex))
            b:Label(u[1], ux - 10, ty - 14, theme:Color(hex), 18)
            local delta = u[2] - (run.duration or 0)
            local dtxt = (delta >= 0) and ("You beat this target by " .. Util.duration(delta) .. "  (earned " .. u[1] .. ").")
                or ("You missed it by " .. Util.duration(-delta) .. ".")
            b:Hit(ux - 13, ty + 8, 26, 42, nil, u[1] .. " target  ·  " .. Util.duration(u[2]), dtxt)
        end
    end

    -- Boss portraits above the track, each pinned to its kill time with a stem + node. Hover is on
    -- the icon. Portrait width scales with the track so it fits both the wide scoreboard and the
    -- narrower run-details page.
    local bsz = math.max(64, math.min(132, trackW / 10))
    for _, boss in ipairs(bosses) do
        if boss.atSec then
            local px = mx(boss.atSec)
            framedIcon(b, px - bsz / 2, ty + 14 + bsz / 2, bsz, bsz / 2, API.BossIcon(boss.name, boss.id))
            b:Box(px - 1, ty + 14, 2, 8, 1, 3, C.accent)
            b:Box(px - 4, ty + 6, 8, 8, 1, 5, C.accent)
            b:Hit(px - bsz / 2, ty + 14 + bsz / 2, bsz, bsz / 2, nil, boss.name or "Boss",
                "Killed at " .. Util.duration(boss.atSec)
                .. (boss.killDps and ("   Your DPS: " .. Util.shortNum(boss.killDps)) or ""))
        end
    end

    -- Deaths BELOW the track: a red pip, a stem down, then a gravestone (hover for who). Nudged
    -- right so they never overlap.
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
        b:Box(px - 1, ty, 2, 44, 1, 3, { 0.5, 0.52, 0.58 })
        b:Box(px - 5, ty - 3, 10, 10, 1, 5, theme:Color("c94f4f"))
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

    -- Your best time at this level: a tall cyan line + diamond pip + crown, drawn LAST so it sits on
    -- top of every other timeline mark.
    if bestTime then
        local bx = mx(bestTime)
        b:Box(bx - 1, ty + 22, 3, 66, 1, 4, theme:Color("35d0e0"))
        b:Box(bx - 6, ty + 4, 12, 12, 1, 6, theme:Color("18b8c8"))
        b:Tex(bx - 8, ty + 40, 16, 16, "crown", nil, { 1, 0.82, 0.2 })
        local d2 = (run.duration or 0) - bestTime
        local btxt = "Best at " .. Util.keyLabel(run.level) .. ": " .. Util.duration(bestTime)
            .. (d2 > 0.5 and ("   (this run: +" .. Util.duration(d2) .. ")") or (d2 < -0.5 and "   (this run set it!)" or ""))
        b:Hit(bx - 10, ty + 42, 20, 70, nil, "Your best time", btxt)
    end

    b:Label("0:00", x, ty - 76, C.subtext, 10)
    b:Label(Util.duration(tmax), x + trackW - 46, ty - 76, C.subtext, 10)
    return ty - 90
end

-- GROUP UTILITY strip (shared by the run-details page and the end-of-run scoreboard): the party's TOTAL
-- interrupts and the two dispel AXES - enemy-buff PURGES/soothes ("target buffs") and debuff CLEANSES -
-- each as actual / expected, from Scoring.Distribute.GroupUtility. Per-axis actual is attributed by
-- capability (a single-axis dispeller's whole count lands on its axis; a dual-axis one is split by its
-- expected share, since the meter reports only one combined dispel count). A metric with no real
-- expectation (no season data, or nobody in the group can do it) is dropped. Returns the Y below the strip.
local GU_METRICS = {
    { key = "interrupts", label = "INTERRUPTS",      icon = "ban" },
    { key = "purge",      label = "TARGET BUFFS",    icon = "sparkles" },
    { key = "cleanse",    label = "DEBUFFS",         icon = "circle-check" },
}
-- Which GU_METRICS actually have an expectation worth showing (>= 0.5). Shared by the strip and, on the
-- scoreboard, the up-front body-height calc.
local function groupUtilityItems(gu)
    local items = {}
    if type(gu) == "table" then
        for _, m in ipairs(GU_METRICS) do
            local d = gu[m.key]
            if d and type(d.expected) == "number" and d.expected >= 0.5 then items[#items + 1] = { m = m, d = d } end
        end
    end
    return items
end
local GU_TILE_H = 104  -- tile height (room for the value + the larger effect-icon row); strip also adds a header (28) + trailing gap (14)

-- Hover tooltip for a group-utility tile. The two dispel axes now render the actual effect ICONS on the
-- tile (each with its own Blizzard spell tooltip on hover), so their tile tip is a one-line descriptor;
-- interrupts have no per-spell list, so their tip explains how the estimate is formed.
local function guTileTip(key)
    if key == "purge" then
        return { title = "Target buffs - purge / soothe", minWidth = 240, lines = {
            { text = "Enemy buffs the group could strip here. Hover an icon for its spell tooltip.", color = "subtext" } } }
    elseif key == "cleanse" then
        return { title = "Debuffs - cleanse", minWidth = 240, lines = {
            { text = "Player debuffs the group could cleanse here. Hover an icon for its spell tooltip.", color = "subtext" } } }
    elseif key == "interrupts" then
        return { title = "Group interrupts", minWidth = 240, lines = {
            { text = "Kicks the party landed vs this run's interruptible-cast supply (trash + bosses "
                .. "killed), capped by the group's interrupt cooldowns.", color = "subtext" } } }
    end
end

-- Render the actual dispellable-effect icons along the bottom of a group-utility tile (purge = enemy
-- buffs to strip, cleanse = player debuffs to remove). Each icon carries the real Blizzard spell tooltip
-- on hover, and is drawn ABOVE the tile frame so hovering it fires the icon's tooltip while hovering the
-- tile background still fires the tile's own tooltip. Icons are pooled + marked transient so a re-render
-- reuses them; a school-coloured 2px border keeps them legible; effects past what the tile can fit
-- collapse to a "+N" label. `startIdx` threads the shared pool index across both tiles.
local GU_ICON_SZ = 27   -- 50% larger than the old 18px
-- Group-utility dispel tiles need RGB tables keyed by the catalog's lowercase school (e.type). Derive
-- them from the shared ML.SCHOOL_COLOR (hex, Capitalized) so the tiles match the Dungeon Guide exactly.
local GU_SCHOOL_COL = {}
for name, hex in pairs(ML.SCHOOL_COLOR) do GU_SCHOOL_COL[name:lower()] = _G.TAP.toColor(hex) end
local function renderGuIcons(b, tile, tileX, tileTopY, tileW, tileH, list, startIdx)
    local n = startIdx
    if type(list) ~= "table" or #list == 0 then return n end
    local theme, C = b.theme, b.theme.C
    local pad, step = 12, GU_ICON_SZ + 4
    local maxIcons = math.floor((tileW - 2 * pad) / step)
    if maxIcons < 1 then return n end
    local show, overflow = #list, 0
    if show > maxIcons then show, overflow = maxIcons - 1, (#list - (maxIcons - 1)) end
    local iconTop = tileTopY - (tileH - 10 - GU_ICON_SZ)
    local lvl = ((tile and tile.GetFrameLevel and tile:GetFrameLevel()) or 0) + 5
    local ix = tileX + pad
    for i = 1, show do
        local e = list[i]
        n = n + 1
        local gi = guIcon(theme, b.content, n, GU_ICON_SZ)
        local col = GU_SCHOOL_COL[e.type] or C.border
        theme:StylePanel(gi, col, col)                        -- solid 2px school-coloured border
        gi.tex:ClearAllPoints(); gi.tex:SetPoint("TOPLEFT", 2, -2); gi.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        gi.tex:SetTexCoord(unpack(theme.iconInset))
        gi:SetFrameLevel(lvl)                                 -- above the tile so its own hover tooltip fires
        gi:ClearAllPoints(); gi:SetPoint("TOPLEFT", b.content, "TOPLEFT", ix, iconTop)
        gi:SetAura(e.id); gi:Show(); b:Transient(gi)
        ix = ix + step
    end
    if overflow > 0 then b:Label("+" .. overflow, ix + 1, iconTop - 6, C.subtext, 12) end
    return n
end

local function groupUtilityStrip(b, C, x, y, w, run, style, gu)
    local D = ML.Scoring and ML.Scoring.Distribute
    gu = gu or (D and D.GroupUtility and D.GroupUtility(run))
    local items = groupUtilityItems(gu)
    if #items == 0 then return y end
    local h = GU_TILE_H
    local Cfg = ML.Scoring and ML.Scoring.Config
    local dd = (Cfg and Cfg.DungeonDispellables and Cfg.DungeonDispellables(run and run.dungeonName))
        or { buffs = {}, debuffs = {} }

    y = b:Section("GROUP UTILITY  ·  landed vs expected", x, y); y = y - 28
    local gap = 10
    local tileW = math.floor((w - gap * (#items - 1)) / #items)
    local iconN = 0
    for i, it in ipairs(items) do
        local a, e = it.d.actual or 0, it.d.expected or 0
        local frac = (e > 0) and (a / e) or 0
        local accent = (frac >= 0.9 and "33dd66") or (frac >= 0.6 and "e0a030") or "e0655a"
        local tileX = x + (i - 1) * (tileW + gap)
        local tile = b:StatTile(tileX, y, {
            style = style or "compact", width = tileW, height = h, iconSize = 22,
            label = it.m.label, icon = it.m.icon, accent = accent,
            value = string.format("%d / %d", math.floor(a + 0.5), math.floor(e + 0.5)),
            tipData = guTileTip(it.m.key),
        })
        -- The two dispel axes show the actual effect icons (real Blizzard tooltip on hover) along the tile
        -- bottom; interrupts have no per-spell list so they stay value-only.
        local list = (it.m.key == "purge" and dd.buffs) or (it.m.key == "cleanse" and dd.debuffs) or nil
        if list then iconN = renderGuIcons(b, tile, tileX, y, tileW, h, list, iconN) end
    end
    return y - h - 14
end

local function renderRunDetails(b, C, x, y, w, win)
    local r = findRun(view.detailRun)
    if not r then view.detailRun = nil; return y end
    local scores = runScores(r)   -- ML.Scoring performance grades per party member
    T(b, b:Button(x + w - 84, y, 72, "Back", "default", function() view.detailRun = nil; win:Refresh() end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the run list.")
    T(b, b:Button(x + w - 210, y, 120, "Scoreboard", "primary", function() UI.ShowScoreboard(r) end,
        { icon = "award", iconSize = 13 }), "Scoreboard", "Open the full end-of-run scoreboard for this run.")
    y = y - 40   -- clear the Back / Scoreboard button row before the full-width result banner

    -- Result hero banner: the dungeon's Encounter-Journal art as a dark backdrop, its portal glyph,
    -- and the run headline - result WITH the keystone-upgrade tier (Timed +2 / Depleted / Abandoned),
    -- time vs. the limit, affixes and date. Same visual language as the Overview hero banner.
    do
        local bh = 116   -- tall enough that the bottom affixes/date line clears the banner border
        local mi = r.mapId and API.GetMapInfo(r.mapId)
        local bg = API.DungeonBackground(r.dungeonName) or (mi and mi.texture)
        cardShell(b, C, x, y, w, bh, { art = bg, artAlpha = 0.5, accent = artAccent(C) })
        dungeonGlyph(b, x + 16, y - (bh - 64) / 2, 64, r.mapId)
        local tx = x + 96
        b:Label("MYTHIC+ RUN", tx, y - 12, artAccent(C), 10)
        b:Heading((r.dungeonName or "Run") .. "   " .. Util.keyLabel(r.level), tx, y - 30, "h2", { textColor = ON_ART })
        local timeStr = Util.duration(r.duration)
        if r.timeRemaining then
            timeStr = timeStr .. "  (" .. (r.timeRemaining >= 0 and "under by " or "over by ")
                .. Util.duration(math.abs(r.timeRemaining)) .. ")"
        end
        b:Label(statusUpgradeText(r), tx, y - 58, b.theme:Color(STATUS_HEX[r.status] or "cccccc", ON_ART), 16)
        b:Label("Time " .. timeStr .. "   /   Limit " .. Util.duration(r.timeLimit), tx, y - 80, ON_ART_SUB, 11)
        local aff = (r.affixNames and #r.affixNames > 0) and table.concat(r.affixNames, ", ") or "No affixes"
        b:Label(aff .. "   ·   " .. Util.dateTime(r.completedAt), tx, y - 96, ON_ART_SUB, 10)
        y = y - bh - 16
    end

    -- Group utility highlight: party interrupts + the two dispel axes, each landed vs expected.
    y = groupUtilityStrip(b, C, x, y, w, r)

    -- Party: one responsive HERO CARD per member (spec portrait + role badge, performance grade, and
    -- the role-relevant throughput). Click a card for that player's full run review; hover for the
    -- complete stat + score breakdown. Cards flow across as many columns as fit and wrap to new rows.
    y = b:Section("PARTY", x, y); y = y - 28   -- clear the section divider (at -18) before the hero cards
    local party = r.party or {}
    if #party == 0 then
        b:Label("No party stats were captured for this run.", x, y - 2, C.subtext, 11); y = y - 24
    else
        local minTile, gap, ch = 224, 10, 100
        local cols = math.max(1, math.min(3, math.floor((w + gap) / (minTile + gap))))
        cols = math.min(cols, #party)
        local tileW = math.floor((w - gap * (cols - 1)) / cols)
        local gx, gy = tileW + gap, ch + gap
        for i, m in ipairs(party) do
            local s = m.stats or {}
            local sc = memberScore(scores, m)
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local cx, cy = x + col * gx, y - row * gy
            local role = m.role
            local roleLbl = ML.ROLE_LABEL[role] or DASH
            local nm = classColorText(m.classFile, m.name or "?") .. (m.isPlayer and "  |cffffd200(you)|r" or "")
            local gradeStr = sc and ("|cff" .. (gradeColor(sc.grade) or "cccccc") .. (sc.grade or "?") .. "|r") or nil
            local sp = specName(m.specId, m.specIcon)
            local primary = (role == "HEALER") and ("HPS " .. Util.shortNum(s.hps)) or ("DPS " .. Util.shortNum(s.dps))
            -- Identity holds spec · role only; ilvl moved to a right-aligned gold badge (was overflowing
            -- the card), and the hero tree gets its own accent-tinted line.
            local identity = sp and (sp .. "  ·  " .. roleLbl) or roleLbl
            local heroName = m.heroTree and m.heroTree.name
            local heroLine = heroName and ("|cffb89ee6" .. heroName .. "|r") or "|cff6f6f6fNo hero tree|r"
            local lines = {
                identity,
                heroLine,
                primary .. "     DTkn " .. Util.shortNum(s.damageTaken),
                "Deaths " .. Util.numOr(s.deaths, "%d") .. "    Int " .. Util.numOr(s.interrupts, "%d")
                    .. "    Dsp " .. Util.numOr(s.dispels, "%d"),
            }
            -- Rich hover: the same full stat + score breakdown the old party table row carried.
            local tlines = {
                { left = "Spec", right = specClassLabel(m.classFile, m.specId) },
                { left = "Role", right = roleLbl },
                { left = "Item level", right = m.itemLevel and tostring(m.itemLevel) or "-" },
                { left = "Hero tree", right = (m.heroTree and m.heroTree.name) or "-" },
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
            heroCard(b, C, cx, cy, tileW, ch, {
                accent = classRGB(m.classFile) or C.accent,
                ilvl = m.itemLevel and tostring(m.itemLevel) or nil,
                iconSize = 44,
                drawIcon = function(bb, ix, iy, isz)
                    if specIconID(m.specId) or m.specIcon then specGlyph(bb, ix, iy, isz, m.specId, m.specIcon)
                    else classGlyph(bb, ix, iy, isz, m.classFile) end
                    roleIcon(bb, ix + isz - 15, iy - isz + 15, 15, role)
                end,
                title = nm, titleSize = 14, titleRight = gradeStr, titleRightW = 30,
                lines = lines,
                onClick = function() view.review = true; reviewRunRef = r; reviewMemberRef = m; win:Refresh() end,
                tipData = { icon = specIconID(m.specId) or m.specIcon, minWidth = 420,
                    title = (m.fullName or m.name or "?") .. (m.isPlayer and "  (you)" or ""), lines = tlines },
            })
        end
        local prows = math.ceil(#party / cols)
        y = y - (prows - 1) * gy - ch - 14
    end

    -- Boss splits: one responsive HERO CARD per boss, fronted by the boss PORTRAIT (a 2:1 Encounter-
    -- Journal banner). Kill time is the headline; attempts / wipes / your kill DPS follow. Hover for
    -- the full encounter breakdown incl. every member's DPS/HPS on the pull.
    if r.bosses and #r.bosses > 0 then
        y = b:Section("BOSS SPLITS", x, y); y = y - 28   -- clear the section divider before the hero cards
        local minTile, gap, ch = 240, 10, 92   -- taller card so the 3rd stat line ("Total on boss") fits
        local cols = math.max(1, math.min(3, math.floor((w + gap) / (minTile + gap))))
        cols = math.min(cols, #r.bosses)
        local tileW = math.floor((w - gap * (cols - 1)) / cols)
        local gx, gy = tileW + gap, ch + gap
        for i, boss in ipairs(r.bosses) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local cx, cy = x + col * gx, y - row * gy
            local lines = {
                "Attempts " .. tostring(boss.attempts or 0) .. "    ·    Wipes " .. tostring(boss.wipes or 0),
                boss.killDps and ("Your DPS " .. Util.shortNum(boss.killDps)) or "Your DPS " .. DASH,
                boss.totalTime and ("Total on boss " .. Util.duration(boss.totalTime)) or nil,
            }
            local btip = {
                { left = "Kill time", right = Util.duration(boss.killDuration) },
                { left = "Killed at", right = boss.atSec and Util.duration(boss.atSec) or "-" },
                { left = "Attempts / Wipes", right = tostring(boss.attempts or 0) .. " / " .. tostring(boss.wipes or 0) },
                { left = "Party deaths", right = tostring(boss.deaths or 0), rcolor = (boss.deaths and boss.deaths > 0) and "e0655a" or nil },
                { left = "Your DPS", right = boss.killDps and Util.shortNum(boss.killDps) or "-" },
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
            heroCard(b, C, cx, cy, tileW, ch, {
                icon = API.BossIcon(boss.name, boss.id), iconWide = true, iconSize = 64,
                title = boss.name or ("Boss " .. tostring(boss.id)), titleSize = 14,
                titleRight = Util.duration(boss.killDuration), titleRightW = 60,
                lines = lines,
                tipData = { icon = API.BossIcon(boss.name, boss.id), title = boss.name or "Boss", lines = btip },
            })
        end
        local brows = math.ceil(#r.bosses / cols)
        y = y - (brows - 1) * gy - ch - 14
    end

    -- Run timeline (combat / downtime, boss portraits at their kill times, deaths, and the keystone
    -- +1/+2/+3 time targets) - the same component the end-of-run scoreboard shows.
    y = renderRunTimeline(b, C, x, y, w, r)

    -- Notes.
    y = b:Section("NOTES", x, y); y = y - 26
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
    y = y - 36

    -- KEEP THIS RUN: the user's explicit lock. Exempt from every retention policy, and (once detail
    -- tiers land) from being trimmed too. Deliberately its own field, never run.pinned - MarkKeepers
    -- rewrites that automatically on every save.
    local lockRow = b:Toggle(x, y, r.protected and true or false, function(v)
        r.protected = v and true or nil
        if DB.MarkProtected then DB.MarkProtected() end
        storageStats = nil   -- the trim preview on the Tracking tab just changed
        win:Refresh()
    end)
    b.theme:SetTip(lockRow, "Keep this run",
        "Never let a retention policy remove or trim this run. It keeps full detail no matter what the "
        .. "policy says, and it is not counted against any 'keep the newest N' limit.")
    b:Label("Keep this run", x + 46, y - 2, C.text)
    if r._protectedBy then
        local who = DB.PlayerIndex()[r._protectedBy]
        b:Label("also kept: " .. ((who and who.name) or "a protected player") .. " is in this run",
            x + 190, y - 2, C.subtext, 11)
    end
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

-- A dungeon "hero" card: dimmed Encounter-Journal art over black, accent left edge, the dungeon icon +
-- name, its best-timed key, and a two-line stat readout (runs / timed% / best & avg time / avg deaths).
-- This is the STANDARD dungeon-hero card for the module. Click anywhere to open the dungeon's details.
local function dungeonHeroCard(b, C, cx, cy, cw, ch, d, win)
    local mi = d.mapId and API.GetMapInfo(d.mapId)
    cardShell(b, C, cx, cy, cw, ch, { art = API.DungeonBackground(d.name) or (mi and mi.texture),
        artAlpha = 0.40, accent = C.accent })
    local isz = 48                                                       -- large dungeon icon, vertically centred
    dungeonGlyph(b, cx + 12, cy - (ch - isz) / 2, isz, d.mapId)
    local tx = cx + 12 + isz + 12                                       -- text column clears the icon
    b:Label(d.name or DASH, tx, cy - 12, C.text, 17)
    if d.highestTimed then b:Label("+" .. d.highestTimed, cx + cw - 54, cy - 13, C.accent, 17) end
    local runs = (d.totals and d.totals.runs) or 0
    b:Label(string.format("%d run%s", runs, runs == 1 and "" or "s")
        .. "   ·   " .. (d.timedPct and Util.percent(d.timedPct) or "-") .. " timed",
        tx, cy - 36, C.subtext, 11)
    local seg = "Best " .. (d.bestTime and Util.duration(d.bestTime) or "-")
        .. "   ·   Avg " .. (d.avgTime and Util.duration(d.avgTime) or "-")
    if d.avgDeaths then seg = seg .. "   ·   " .. string.format("%.1f", d.avgDeaths) .. " deaths" end
    b:Label(seg, tx, cy - 52, C.subtext, 10)
    local hit = b:Hit(cx, cy, cw, ch, function() view.detailDungeon = d.mapId; win:Refresh() end)
    if b.theme.SetTipData then                       -- rich hover tooltip (who you run it with, best/worst DPS)
        local td = dungeonTipData(d); td.anchor = "ANCHOR_CURSOR"
        b.theme:SetTipData(hit, td)
    end
end

local function renderDungeons(b, C, x, y, w, win)
    -- Season + Character + type-to-filter on one row.
    local nx = scopeControl(b, C, x, y, "Season", 170, "Season",
        "Scope every dungeon stat to a season, or show all seasons.",
        seasonChoices(), function() return view.season end,
        function(v) view.season = v; if win then win:Refresh() end end)
    nx = scopeControl(b, C, nx, y, "Character", 180, "Character",
        "Show dungeon stats for all characters combined, or focus on a single character.",
        overviewCharChoices(), function() return view.character or "all" end,
        function(v) view.character = v; if win then win:Refresh() end end)
    -- The filter box is PERSISTENT (created once, parented to the content frame) so it isn't hidden by
    -- the builder's per-render Reset - that's what lets it keep keyboard focus while you type + it live-
    -- filters. It's shown/positioned here and hidden by UI.RenderPage whenever this list isn't the view.
    if not dungeonSearch then
        dungeonSearch = b.theme:SearchBox(b.content, { width = 260, icon = "search",
            placeholder = "Filter dungeons (type 3+ letters)…", value = dungeonFilter.text,
            onChange = function(t) dungeonFilter.text = t or ""
                if dungeonSearch._win then dungeonSearch._win:Refresh() end end })
    end
    dungeonSearch._win = win   -- keep the refresh target current even if the manager window is rebuilt
    if dungeonSearch:GetParent() ~= b.content then dungeonSearch:SetParent(b.content) end
    dungeonSearch:ClearAllPoints()
    dungeonSearch:SetPoint("TOPLEFT", b.content, "TOPLEFT", nx, y + 1)
    dungeonSearch:Show()
    y = y - 40

    local list = History.DungeonStats(scopeSeason(), scopeCharacter())
    -- Live filter: only kicks in at 3+ characters, so a stray one or two letters doesn't blank the list.
    local q = (dungeonFilter.text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local shown = list
    if #q >= 3 then
        shown = {}
        for _, d in ipairs(list) do
            if (d.name or ""):lower():find(q, 1, true) then shown[#shown + 1] = d end
        end
    end
    table.sort(shown, function(a, bb) return ((a.totals and a.totals.runs) or 0) > ((bb.totals and bb.totals.runs) or 0) end)

    local header = string.format("DUNGEONS (%d%s)", #shown,
        (#q >= 3 and #shown ~= #list) and (" of " .. #list) or "")
    b:Sub(header, x, y); y = y - 28
    if #list == 0 then b:Wrap("No dungeon data yet.", x, y, w - 20, C.subtext, 12); return y - 30 end
    if #shown == 0 then
        b:Wrap("No dungeons match \"" .. dungeonFilter.text .. "\".", x, y, w - 20, C.subtext, 12)
        return y - 30
    end

    -- Hero-card grid (2 columns when there's room).
    local cols = (w >= 720) and 2 or 1
    local gap, ch = 12, 68
    local cw = (w - (cols - 1) * gap) / cols
    for i, d in ipairs(shown) do
        local col, rowi = (i - 1) % cols, math.floor((i - 1) / cols)
        dungeonHeroCard(b, C, x + col * (cw + gap), y - rowi * (ch + gap), cw, ch, d, win)
    end
    y = y - math.ceil(#shown / cols) * (ch + gap)
    return y - 12
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

-- Keystone-level color: the game's own rarity ramp, with a band-ramp fallback (higher key = hotter).
local function keyColor(level)
    if type(level) ~= "number" then return { 0.45, 0.47, 0.55 } end
    local GK = _G.C_ChallengeMode and _G.C_ChallengeMode.GetKeystoneLevelRarityColor
    if GK then local c = GK(level); if c and c.r then return { c.r, c.g, c.b } end end
    if level >= 12 then return { 1.00, 0.50, 0.00 }
    elseif level >= 10 then return { 0.64, 0.21, 0.93 }
    elseif level >= 7 then return { 0.00, 0.44, 0.87 }
    elseif level >= 2 then return { 0.19, 1.00, 0.19 }
    else return { 0.75, 0.77, 0.82 } end
end

-- WEEKLY VAULT: per-character top-8 COMPLETED keys this reset week, sortable, with an at-a-glance status.
-- The 1st / 4th / 8th keys feed the three Great Vault slots (marked); "all 10s" = the 8th key is +10.
local function renderWeeklyVault(b, C, x, y, w, win)
    local vault = History.WeeklyVault and History.WeeklyVault()
    if not vault or #vault == 0 then return y end

    applySort(vault, vaultSort, {
        name  = function(v) return nil end,
        keys  = function(v) return v.count end,
        vault = function(v) return v.slot8 or -1 end,   -- 8th key = top vault slot; -1 sinks the <8 chars
    }, function(a, bb) return (a.fullName or "") < (bb.fullName or "") end)

    local rowW, kx, colW = w - 12, x + 300, 27
    local secs = History.SecondsUntilReset and History.SecondsUntilReset()
    local resetStr = ""
    if secs then
        resetStr = string.format("   -   resets in %dd %dh", math.floor(secs / 86400), math.floor((secs % 86400) / 3600))
    end
    b:Sub("WEEKLY VAULT  -  top 8 keys this week" .. resetStr, x, y); y = y - 28

    b:Box(x, y + 4, rowW, 24, 0.12, 0, C.accent)
    sortHdr(b, C, x + 30, y - 2, 90, "Character", "name", vaultSort, win)
    sortHdr(b, C, x + 232, y - 2, 44, "Keys", "keys", vaultSort, win)
    for i = 1, 8 do   -- column numbers; 1 / 4 / 8 (the vault reward slots) in accent
        local slot = (i == 1 or i == 4 or i == 8)
        b:Label(tostring(i), kx + (i - 1) * colW + 3, y - 2, slot and C.accent or C.subtext, 10)
    end
    sortHdr(b, C, x + rowW - 66, y - 2, 60, "Vault +", "vault", vaultSort, win)
    y = y - 26

    for i, v in ipairs(vault) do
        local h, yTop = 26, y
        local full = (v.count >= 8)
        b:Row(x, yTop, rowW, h, { index = i })
        classGlyph(b, x + 6, yTop - 4, 18, v.classFile)
        b:Label(classColorText(v.classFile, v.name or v.fullName or "?"), x + 30, yTop - 8, C.text, 12)
        local perfect = full and (v.slot8 or 0) >= 10          -- 8/8, all +10 ("all 10s") -> gold
        local cntCol = perfect and { 1.00, 0.82, 0.28 }
            or (full and { 0.42, 0.82, 0.45 })                 -- 8/8 but below +10 -> green
            or (v.count > 0 and { 0.95, 0.70, 0.30 })          -- partial -> amber (needs more runs)
            or { 0.55, 0.57, 0.62 }                            -- none this week -> gray
        b:Label(v.count .. " / 8", x + 232, yTop - 8, cntCol, 12)
        for si = 1, 8 do
            local cxp = kx + (si - 1) * colW
            if si == 1 or si == 4 or si == 8 then b:Box(cxp - 2, yTop - 1, colW, h - 2, 0.10, 0, C.accent) end
            local lvl = v.keys[si]
            b:Label(lvl and tostring(lvl) or "-", cxp + 3, yTop - 8, lvl and keyColor(lvl) or { 0.42, 0.44, 0.5 }, 12)
        end
        b:Label(v.slot8 and ("+" .. v.slot8) or "-", x + rowW - 62, yTop - 8, v.slot8 and keyColor(v.slot8) or { 0.42, 0.44, 0.5 }, 13)
        y = yTop - h - 2
    end
    return y - 14
end

local function renderCharacters(b, C, x, y, w, win)
    y = renderWeeklyVault(b, C, x, y, w, win)
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
        if ok and playerFilter.class and p.classFile ~= playerFilter.class then ok = false end
        if ok and playerFilter.spec and p.lastKnownSpecId ~= playerFilter.spec then ok = false end
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
            local an = (key == "name" and (a.fullName or "") or (specName(a.lastKnownSpecId, a.lastKnownSpecIcon) or "")):lower()
            local bn = (key == "name" and (bb.fullName or "") or (specName(bb.lastKnownSpecId, bb.lastKnownSpecIcon) or "")):lower()
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

-- Distinct classes / specs present among tracked players, for the Players filters.
local function playerClassChoices()
    local seen, list = {}, {}
    for _, p in ipairs(History.PlayerList()) do
        if p.classFile and not seen[p.classFile] then
            seen[p.classFile] = true
            local nm = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.classFile]) or p.classFile
            list[#list + 1] = { p.classFile, classColorText(p.classFile, nm), nm }
        end
    end
    table.sort(list, function(a, bb) return (a[3] or "") < (bb[3] or "") end)
    table.insert(list, 1, { "all", "All Classes" })
    return list
end
local function playerSpecChoices()
    local seen, list = {}, {}
    for _, p in ipairs(History.PlayerList()) do
        local sid = p.lastKnownSpecId
        if sid and not seen[sid] then
            seen[sid] = true
            local nm = specName(sid, p.lastKnownSpecIcon) or ("Spec " .. tostring(sid))
            list[#list + 1] = { sid, nm, nm }
        end
    end
    table.sort(list, function(a, bb) return (a[3] or "") < (bb[3] or "") end)
    table.insert(list, 1, { "all", "All Specs" })
    return list
end

local function renderPlayers(b, C, x, y, w, win)
    -- Filter toolbar: Search, Role, Class, Spec, Favorites - flowing across the width.
    local fields = {
        { label = "Search", build = function(fx, cy, cw)
            T(b, b:EditBox(fx, cy, cw, playerFilter.search or "", function(t) playerFilter.search = t; win:Refresh() end),
                "Search", "Filter by player name or realm.") end },
        { label = "Role", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, {
                { "all", "All" }, { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "DPS" },
            }, function() return playerFilter.role or "all" end,
               function(v) playerFilter.role = (v ~= "all") and v or nil; win:Refresh() end) end },
        { label = "Class", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, playerClassChoices(), function() return playerFilter.class or "all" end,
                function(v) playerFilter.class = (v ~= "all") and v or nil; win:Refresh() end) end },
        { label = "Spec", build = function(fx, cy, cw)
            b:Dropdown(fx, cy):SetChoices(cw, playerSpecChoices(), function() return playerFilter.spec or "all" end,
                function(v) playerFilter.spec = (v ~= "all") and v or nil; win:Refresh() end) end },
        { label = "Favorites", build = function(fx, cy, cw)
            T(b, b:Toggle(fx, cy - 4, playerFilter.favorite, function(v) playerFilter.favorite = v; win:Refresh() end),
                "Favorites only", "Show only players you've marked as favorite.") end },
    }
    y = filterBar(b, C, x, y, w - 12, fields)

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
        local sName = specName(p.lastKnownSpecId, p.lastKnownSpecIcon)
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
-- The clicked player's own party-member entry in a given run (spec / role / stats THAT run).
local function memberIn(run, key)
    for _, m in ipairs(run.party or {}) do
        if not m.isPlayer and API.IdentityKey(m) == key then return m end
    end
    return nil
end

-- One run-history row from the perspective of a party member: their spec badge + the run's dungeon,
-- key, result, time, and their own stats that run. Clicking opens the full run.
local function playerRunRow(b, C, x, yTop, rowW, r, key, i, win)
    local m = memberIn(r, key) or {}
    b:Row(x, yTop, rowW, 28, { index = i, tipData = runTipData(r),
        onClick = function() view.detailRun = r.id; win:Refresh() end })
    if m.specId or m.specIcon then specGlyph(b, x + 8, yTop - 5, 18, m.specId, m.specIcon)
    else classGlyph(b, x + 8, yTop - 5, 18, m.classFile) end
    b:Label(Util.dateShort(r.completedAt), x + 34, yTop - 10, C.subtext, 11)
    dungeonGlyph(b, x + 140, yTop - 5, 18, r.mapId)
    b:Label(r.dungeonName or "?", x + 164, yTop - 10, C.text, 11)
    b:Label(Util.keyLabel(r.level), x + 334, yTop - 10, C.accent, 12)
    b:Label(statusText(r.status), x + 378, yTop - 10, b.theme:Color(STATUS_HEX[r.status] or "cccccc", C.text), 11)
    b:Label(Util.duration(r.duration), x + 472, yTop - 10, C.text, 11)
    b:Label(Util.numOr(m.stats and m.stats.deaths, "%d"), x + 540, yTop - 10, C.subtext, 11)
    b:Label(primaryMetric(m.role, m.stats), x + 586, yTop - 10, C.text, 11)
end

local function renderPlayerDetails(b, C, x, y, w, win)
    local p = History.PlayerSummary(view.detailPlayer)
    if not p then view.detailPlayer = nil; return y end
    local rowW = w - 12
    -- Reset the run-history pager whenever a different player is opened.
    if view._playerRunsFor ~= view.detailPlayer then view._playerRunsFor = view.detailPlayer; pageState.playerRuns = 1 end
    T(b, b:Button(x + w - 84, y, 72, "Back", "default", function() view.detailPlayer = nil; win:Refresh() end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the previous page.")

    -- Header: class crest with a spec badge in the corner + class-colored name + spec/class/guild line.
    classGlyph(b, x, y - 6, 64, p.classFile)
    if p.lastKnownSpecId or p.lastKnownSpecIcon then
        specGlyph(b, x + 44, y - 46, 20, p.lastKnownSpecId, p.lastKnownSpecIcon)   -- spec badge over the crest corner
    end
    b:Heading(classColorText(p.classFile, p.fullName or p.name or "Player"), x + 80, y, "h1")
    local sub = specClassLabel(p.classFile, p.lastKnownSpecId)
    if p.lastKnownItemLevel then sub = sub .. "   |cffc9a76a" .. tostring(p.lastKnownItemLevel) .. " ilvl|r" end
    if p.guildName then sub = sub .. "   <" .. p.guildName .. ">" end
    b:Label(sub, x + 82, y - 26, C.subtext, 12)
    -- Favorite toggle: right-aligned under the Back button so it can't collide with the name/crest.
    T(b, b:Toggle(x + w - 150, y - 40, p.favorite, function(v) History.SetPlayerFavorite(p.identityKey, v); win:Refresh() end),
        "Favorite", "Mark this player as a favorite for quick filtering.")
    b:Label("Favorite", x + w - 106, y - 41, C.text, 11)
    y = y - 96

    -- Runs with this player (shared by the spec breakdown and the history table below).
    local runs = History.FilterRuns({ playerKey = p.identityKey })   -- newest-first

    -- KEEP: protects this player's record from being pruned AND locks every run they appear in. The
    -- run count is spelled out because this toggle reaches further than the page it sits on.
    T(b, b:Toggle(x + w - 150, y + 56, p.protected and true or false,
        function(v) History.SetPlayerProtected(p.identityKey, v); storageStats = nil; win:Refresh() end),
        "Keep this player",
        string.format("Never prune this player's record, and never let a retention policy remove or trim "
            .. "the %d run%s they appear in.", #runs, (#runs == 1) and "" or "s"))
    b:Label("Keep", x + w - 106, y + 55, C.text, 11)

    -- Headline stats as responsive hero tiles - the SAME look, sizing and reflow as the character-
    -- details page (color-scaled metrics via HeroStatStyle; the run-outcome tallies carry fixed
    -- status colors + a describing tooltip). Panel style can't host the large icon, so fall back to a
    -- large-icon-capable style there, exactly like the character page.
    local t = p.totals
    local pct = History.timedPct(t)
    local avgK = Util.safeDiv(p.levelSum, p.levelN)
    local avgD = History.avgOf(p.stats, "deaths")
    local tile, finish = heroTileGrid(b, x, y, w)
    local function outcomeOpts(label, icon, hex, desc)
        return { label = label, icon = icon, color = hex,
            tipData = { title = label, lines = { { text = desc, color = "subtext" } } } }
    end

    tile("runs",          t.runs,          tostring(t.runs))
    tile("timedPercent",  pct,             pct and Util.percent(pct) or DASH)
    tile("highestTimed",  p.highestTimed,  p.highestTimed and ("+" .. p.highestTimed) or DASH)
    tile("averageKey",    avgK,            avgK and string.format("+%.1f", avgK) or DASH)
    tile("completed",     t.completed,     tostring(t.completed),
        outcomeOpts("Completed", "circle-check", "33dd66", "Keys finished (timed or depleted)."))
    tile("depleted",      t.depleted,      tostring(t.depleted),
        outcomeOpts("Depleted", "hourglass", "e0a030", "Finished, but over the timer."))
    tile("abandoned",     t.abandoned,     tostring(t.abandoned),
        outcomeOpts("Abandoned", "logout", "9098a8", "Left or reset before completion."))
    tile("averageDeaths", avgD,            avgD and string.format("%.1f", avgD) or DASH)

    y = finish()

    b:Label(string.format("First seen %s  ·  Last seen %s", Util.dateShort(p.firstSeenAt), Util.dateShort(p.lastSeenAt)),
        x, y - 2, C.subtext, 11)
    y = y - 24

    -- SPECS PLAYED and DUNGEONS TOGETHER, rendered as the SAME hero cards as the character-details
    -- page (specHeroCard / dungeonHeroCard). Both are derived live from the shared runs in one pass, so
    -- they're correct immediately (no cache rebuild) and cover members that carry a spec icon but no id.
    local specMap, specs = {}, {}
    local dmap, dungs = {}, {}
    for _, r in ipairs(runs) do
        local m = memberIn(r, p.identityKey)
        local timedRun = (r.status == STATUS.TIMED)
        local completedRun = (r.status ~= STATUS.ABANDONED)
        local lvl = (type(r.level) == "number") and r.level or nil
        -- Per spec (keyed by the member's spec on that run).
        if m and (m.specId or m.specIcon) then
            local skey = m.specId or ("icon:" .. tostring(m.specIcon))
            local sb = specMap[skey]
            if not sb then
                sb = { specId = m.specId, specIcon = m.specIcon, role = m.role, classFile = m.classFile,
                       totals = { runs = 0 }, timed = 0, completed = 0, levelSum = 0, levelN = 0,
                       highestTimed = nil, stats = {} }
                specMap[skey] = sb; specs[#specs + 1] = sb
            end
            sb.totals.runs = sb.totals.runs + 1
            if m.specIcon then sb.specIcon = m.specIcon end
            if m.role then sb.role = m.role end
            if m.classFile then sb.classFile = m.classFile end
            if completedRun then
                sb.completed = sb.completed + 1
                if lvl then sb.levelSum = sb.levelSum + lvl; sb.levelN = sb.levelN + 1 end
                if timedRun then
                    sb.timed = sb.timed + 1
                    if lvl and (not sb.highestTimed or lvl > sb.highestTimed) then sb.highestTimed = lvl end
                end
            end
            local s = m.stats
            if type(s) == "table" then
                for _, k in ipairs({ "dps", "hps", "interrupts", "dispels", "damageTaken", "deaths" }) do
                    if type(s[k]) == "number" then
                        sb.stats[k .. "_sum"] = (sb.stats[k .. "_sum"] or 0) + s[k]
                        sb.stats[k .. "_n"] = (sb.stats[k .. "_n"] or 0) + 1
                    end
                end
            end
        end
        -- Per dungeon (the shared runs). Deaths are THIS player's deaths on the run, not the party's.
        if r.mapId then
            local dd = dmap[r.mapId]
            if not dd then
                dd = { mapId = r.mapId, name = r.dungeonName, totals = { runs = 0 }, timed = 0, completed = 0,
                       highestTimed = nil, bestTime = nil, timeSum = 0, timeN = 0, deathsSum = 0, deathsN = 0 }
                dmap[r.mapId] = dd; dungs[#dungs + 1] = dd
            end
            dd.totals.runs = dd.totals.runs + 1
            if r.dungeonName then dd.name = r.dungeonName end
            if completedRun then
                dd.completed = dd.completed + 1
                if timedRun then
                    dd.timed = dd.timed + 1
                    if lvl and (not dd.highestTimed or lvl > dd.highestTimed) then dd.highestTimed = lvl end
                    if type(r.duration) == "number" then
                        if not dd.bestTime or r.duration < dd.bestTime then dd.bestTime = r.duration end
                        dd.timeSum = dd.timeSum + r.duration; dd.timeN = dd.timeN + 1
                    end
                end
            end
            local md = m and m.stats and m.stats.deaths
            if type(md) == "number" then dd.deathsSum = dd.deathsSum + md; dd.deathsN = dd.deathsN + 1 end
        end
    end
    for _, sb in ipairs(specs) do
        sb.timedPct = Util.safeDiv(sb.timed, sb.completed)
        sb.avgLevel = Util.safeDiv(sb.levelSum, sb.levelN)
        sb.avgDps = History.avgOf(sb.stats, "dps")
        sb.avgHps = History.avgOf(sb.stats, "hps")
        sb.avgDeaths = History.avgOf(sb.stats, "deaths")
    end
    for _, dd in ipairs(dungs) do
        dd.timedPct = Util.safeDiv(dd.timed, dd.completed)
        dd.avgTime = Util.safeDiv(dd.timeSum, dd.timeN)
        dd.avgDeaths = Util.safeDiv(dd.deathsSum, dd.deathsN)
    end
    table.sort(specs, function(a, bb) return a.totals.runs > bb.totals.runs end)
    table.sort(dungs, function(a, bb) return a.totals.runs > bb.totals.runs end)

    -- SPECS PLAYED: one class/spec hero card each (class color + spec icon), like the character page.
    y = b:Section("SPECS PLAYED", x, y); y = y - 30
    if #specs == 0 then
        b:Label("No spec data recorded yet.", x + 4, y - 2, C.subtext, 11); y = y - 26
    else
        local cols = (w >= 720) and 2 or 1
        local sgap, sch = 12, 68
        local cw = (w - (cols - 1) * sgap) / cols
        for i, sp in ipairs(specs) do
            local col, rowi = (i - 1) % cols, math.floor((i - 1) / cols)
            specHeroCard(b, C, x + col * (cw + sgap), y - rowi * (sch + sgap), cw, sch, sp, sp.classFile or p.classFile)
        end
        y = y - math.ceil(#specs / cols) * (sch + sgap) - 4
    end

    -- DUNGEONS TOGETHER: one dungeon hero card each (dimmed Encounter-Journal art), like the character
    -- page. Click opens the dungeon page; detailPlayer stays set so Back returns here.
    if #dungs > 0 then
        y = b:Section("DUNGEONS TOGETHER", x, y); y = y - 30
        local cols = (w >= 720) and 2 or 1
        local dgap, dch = 12, 68
        local cw = (w - (cols - 1) * dgap) / cols
        for i, dd in ipairs(dungs) do
            local col, rowi = (i - 1) % cols, math.floor((i - 1) / cols)
            dungeonHeroCard(b, C, x + col * (cw + dgap), y - rowi * (dch + dgap), cw, dch, dd, win)
        end
        y = y - math.ceil(#dungs / cols) * (dch + dgap) - 4
    end

    -- Full run history with this player, paginated, most-recent first (runs fetched above).
    local pname = p.name or p.fullName or "Player"
    y = b:Section(string.format("RUN HISTORY WITH %s (%d)", pname:upper(), #runs), x, y); y = y - 24
    if #runs == 0 then
        b:Label("No shared runs recorded yet.", x + 4, y - 2, C.subtext, 11); y = y - 26
    else
        b:Label("DATE", x + 34, y - 2, C.subtext, 10)
        b:Label("DUNGEON", x + 164, y - 2, C.subtext, 10)
        b:Label("KEY", x + 334, y - 2, C.subtext, 10)
        b:Label("RESULT", x + 378, y - 2, C.subtext, 10)
        b:Label("TIME", x + 472, y - 2, C.subtext, 10)
        b:Label("DEATHS", x + 534, y - 2, C.subtext, 10)
        b:Label("DPS / HPS", x + 586, y - 2, C.subtext, 10)
        y = y - 18
        local first, last = pagerBar(b, C, x, y, rowW, #runs, "playerRuns", win); y = y - 42
        b:Box(x, y + 6, rowW, (last - first + 1) * 28 + 6, 0.03, 0, C.card)
        for i = first, last do
            playerRunRow(b, C, x, y, rowW, runs[i], p.identityKey, i, win)
            y = y - 28
        end
        y = y - 4
        pagerBar(b, C, x, y, rowW, #runs, "playerRuns", win); y = y - 30
    end

    -- Notes.
    y = b:Section("NOTES", x, y); y = y - 26
    T(b, b:EditBox(x, y, w - 40, p.notes or "", function(t2) History.SetPlayerNote(p.identityKey, t2) end),
        "Player notes", "Private notes about this player. Never shown in recaps unless you opt in.")
    y = y - 32
    T(b, b:Button(x, y, 160, "View Runs Together", "primary", function()
        runFilter.playerKey = p.identityKey; view.detailPlayer = nil; UI.GoToPage(win, "runs")
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
            local myDeaths = History.PlayerDeaths(r)   -- YOUR deaths (this board is your own stats), not the party's
            if type(myDeaths) == "number" then rank("lowDeaths", myDeaths, lt, ctx); rank("mostDeaths", myDeaths, gt, ctx) end
        end
    end
    return st
end

-- One "top run" hero card: wide Encounter-Journal dungeon art dimmed over black (the same treatment
-- as the Overview's most-played-dungeon card), an accent left edge, the rank, dungeon + key, result /
-- time / your DPS, the date, and your grade. Crown if it's also your best-scoring run of its kind.
-- Click anywhere on the card to open the run's full details.
local function topRunCard(b, C, cx, cy, cw, ch, rank, r, win)
    local mi = r.mapId and API.GetMapInfo(r.mapId)
    cardShell(b, C, cx, cy, cw, ch, { art = API.DungeonBackground(r.dungeonName) or (mi and mi.texture),
        artAlpha = 0.42, accent = artAccent(C) })                       -- dimmed art + light accent edge
    dungeonGlyph(b, cx + 10, cy - (ch - 40) / 2, 40, r.mapId)          -- portal icon (matches every other hero card)
    local tx = cx + 60
    b:Label("#" .. rank .. "   " .. (r.dungeonName or "Dungeon") .. "   " .. Util.keyLabel(r.level), tx, cy - 13, ON_ART, 14)
    local dps = r.playerStats and r.playerStats.dps
    local line = statusText(r.status) .. "    " .. Util.duration(r.duration)
    if type(dps) == "number" then line = line .. "    " .. Util.shortNum(dps) .. " DPS" end
    b:Label(line, tx, cy - 35, ON_ART_SUB, 11)
    -- Whose run it was (class-colored) + the date - so a crown here isn't ambiguous across characters.
    local who = r.character and classColorText(r.character.classFile, r.character.name or r.character.fullName or "?")
    b:Label((who and (who .. "   ·   ") or "") .. Util.dateShort(r.completedAt), tx, cy - 51, ON_ART_SUB, 10)
    -- Your grade (score-driven) on the right; crown if this is also your best-scoring run of its kind.
    -- Force the bright (dark-theme) grade color since the card art is always dark, even on light mode.
    local guid = r.character and r.character.guid
    local Store = ML.Scoring and ML.Scoring.Store
    local ps = guid and Store and Store.Summary(r)[guid]
    if ps and ps.grade then b:Label(ps.grade, cx + cw - 46, cy - 24, b.theme:Color(ML.TierColor(ps.grade:sub(1, 1), true)), 20) end
    if r.bestOfKind then b:Tex(cx + cw - 22, cy - 52, 12, 12, "crown", nil, { 1, 0.82, 0.2 }) end
    b:Hit(cx, cy, cw, ch, function() view.detailRun = r.id; win:Refresh() end,
        (r.dungeonName or "Run") .. "  " .. Util.keyLabel(r.level), "Open this run's full details.")
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

    -- TOP RUNS: your best keys (highest level, then fastest) as dungeon-art hero cards. Honours the
    -- filters above, so with no filters it's your overall top 10 (the retention keeper set); filtered,
    -- it's the top for that scope.
    local timed = {}
    for _, r in ipairs(runs) do
        if r.status == ML.STATUS.TIMED and type(r.level) == "number" then timed[#timed + 1] = r end
    end
    table.sort(timed, function(a, bb)
        if (a.level or 0) ~= (bb.level or 0) then return (a.level or 0) > (bb.level or 0) end
        return (a.duration or math.huge) < (bb.duration or math.huge)
    end)
    local topN = math.min(DB.TOP_KEEP or 10, #timed)
    if topN > 0 then
        y = b:Section(string.format("TOP %d RUNS", topN), x, y); y = y - 28
        local cols = (w >= 700) and 2 or 1
        local gap = 12
        local cw = (w - (cols - 1) * gap) / cols
        local ch = 66
        for i = 1, topN do
            local col, rowi = (i - 1) % cols, math.floor((i - 1) / cols)
            topRunCard(b, C, x + col * (cw + gap), y - rowi * (ch + gap), cw, ch, i, timed[i], win)
        end
        y = y - math.ceil(topN / cols) * (ch + gap) - 6
    end

    local dur = function(v) return Util.duration(v) end
    local num = function(v) return Util.shortNum(v) end

    -- PERSONAL BESTS / NEEDS WORK as hero cards in the same dungeon-hero visual language (dark base,
    -- accent left edge, large left icon). Each shows the metric, the record value, and the run it came
    -- from as subtext. Cards with no data (e.g. HPS for a pure-DPS player) are dropped so the board
    -- isn't a wall of "-".
    local th = 80
    local minTile, gapx = 170, 12
    local cols = math.max(2, math.min(4, math.floor((w + gapx) / (minTile + gapx))))
    local tw = math.floor((w - gapx * (cols - 1)) / cols)
    local gx, gy = tw + gapx, th + 12
    local function heroBoard(defs, accentCol)
        local shown = {}
        for _, d in ipairs(defs) do if d.e then shown[#shown + 1] = d end end
        for i, d in ipairs(shown) do
            local col, rowi = (i - 1) % cols, math.floor((i - 1) / cols)
            local e = d.e
            local val = d.fmt and d.fmt(e.v) or tostring(e.v)
            local ctx = e.ctx and ((e.ctx.dungeon or "") .. (e.ctx.level and ("  +" .. e.ctx.level) or "")) or nil
            heroStatCard(b, C, x + col * gx, y - rowi * gy, tw, th, {
                accent = accentCol, icon = d.icon, label = d.label, value = val,
                sub = (ctx and ctx ~= "") and ctx or nil,
            })
        end
        if #shown > 0 then y = y - math.ceil(#shown / cols) * gy end
    end

    y = b:Section(string.format("PERSONAL BESTS  (%d run(s))", #runs), x, y); y = y - 28
    heroBoard({
        { label = "Highest Timed Key", e = st.highTimed, fmt = function(v) return "+" .. v end, icon = "trophy" },
        { label = "Fastest Timed Run", e = st.fastTimed, fmt = dur, icon = "clock" },
        { label = "Highest DPS",       e = st.highDps,   fmt = num, icon = "sword" },
        { label = "Highest HPS",       e = st.highHps,   fmt = num, icon = "heartbeat" },
        { label = "Most Interrupts",   e = st.mostInt,   icon = "ban" },
        { label = "Most Dispels",      e = st.mostDsp,   icon = "sparkles" },
        { label = "Fewest Deaths",     e = st.lowDeaths, icon = "shield" },
    }, C.accent)
    y = y - 8

    y = b:Section("NEEDS WORK", x, y); y = y - 28
    heroBoard({
        { label = "Most Deaths",       e = st.mostDeaths, icon = "skull" },
        { label = "Lowest DPS",        e = st.lowDps, fmt = num, icon = "sword" },
        { label = "Lowest HPS",        e = st.lowHps, fmt = num, icon = "heartbeat" },
        { label = "Fewest Interrupts", e = st.lowInt, icon = "ban" },
    }, "E27058")
    return y - 8
end

----------------------------------------------------------------------
-- Settings.
----------------------------------------------------------------------
-- Sound-output channels a user can route a sound to (matches WoW's audio channels).
local CHANNEL_CHOICES = {
    { "Master", "Master" }, { "SFX", "Sound FX" }, { "Music", "Music" },
    { "Ambience", "Ambience" }, { "Dialog", "Dialog" },
}

-- Fixed sample roster for the "Launch test scoreboard" button (never saved to the DB).
local SAMPLE_PARTY = {
    { name = "Twisteld",    realm = "Zul'jin", classFile = "WARRIOR",     specId = 71,  role = "DAMAGER", guid = "Player-11-S0000001", isPlayer = true, guild = "Coffee Break" },
    { name = "Rockhide",    realm = "Area52",  classFile = "DEATHKNIGHT", specId = 250, role = "TANK",    guid = "Player-11-S0000002", guild = "Late Pulls" },
    { name = "Lightmender", realm = "Area52",  classFile = "SHAMAN",      specId = 264, role = "HEALER",  guid = "Player-11-S0000003", guild = "Late Pulls" },
    { name = "Spellburn",   realm = "Illidan", classFile = "MAGE",        specId = 63,  role = "DAMAGER", guid = "Player-11-S0000004", guild = "Parse Andrews" },
    { name = "Shivblade",   realm = "Zul'jin", classFile = "ROGUE",       specId = 261, role = "DAMAGER", guid = "Player-11-S0000005" },
}

local function sampleStats(role, dur)
    local st = { deaths = (role == "TANK") and 1 or 0 }
    if role == "HEALER" then
        st.healing = 1.1e7; st.hps = st.healing / dur
        st.dispels = 9; st.damage = 2.4e6; st.dps = st.damage / dur; st.interrupts = 2
    elseif role == "TANK" then
        st.damageTaken = 2.6e7; st.damage = 9.5e6; st.dps = st.damage / dur
        st.healing = 4.6e6; st.hps = st.healing / dur
        st.interrupts = 6; st.dispels = 1
    else
        st.damage = 1.7e7; st.dps = st.damage / dur; st.damageTaken = 4.2e6
        st.interrupts = 9; st.dispels = 2
    end
    st.absorbs = 8e5; st.avoidableDamageTaken = (st.damageTaken or 4e6) * 0.08
    return st
end

-- Build a believable timed +14 run with a full party, boss splits and a timeline so the scoreboard
-- renders exactly as it does for a real run. Uses the live season's first dungeon when available.
local function buildSampleRun()
    local dun = { id = 9001, name = "Test Dungeon", timer = 1800, bosses = { "The Warm-Up", "Split Check", "Final Exam" } }
    local CM = _G.C_ChallengeMode
    if CM and CM.GetMapTable and CM.GetMapUIInfo then
        local ok, ids = pcall(CM.GetMapTable)
        if ok and type(ids) == "table" and ids[1] then
            local nm, _, timeLimit = CM.GetMapUIInfo(ids[1])
            if nm then dun.id, dun.name, dun.timer = ids[1], nm, timeLimit or 1800 end
        end
    end
    local level, timer = 14, dun.timer
    local duration = timer * 0.86
    local now = time()
    local jitter = { 1.0, 0.62, 0.5, 1.12, 0.94 }   -- vary per-member throughput a little
    local party = {}
    for i, p in ipairs(SAMPLE_PARTY) do
        local stt = sampleStats(p.role, duration)
        if stt.dps then stt.dps = stt.dps * jitter[i]; stt.damage = stt.dps * duration end
        party[i] = {
            guid = p.guid, name = p.name, realm = p.realm, fullName = p.name .. "-" .. p.realm,
            classFile = p.classFile, specId = p.specId, role = p.role, guildName = p.guild,
            mplusScore = 2600 + i * 90, itemLevel = 636 + i, isPlayer = p.isPlayer and true or false, stats = stt,
        }
    end
    local topM, healM, lowM
    for _, m in ipairs(party) do
        if not topM or (m.stats.dps or 0) > (topM.stats.dps or 0) then topM = m end
        if not healM or (m.stats.hps or 0) > (healM.stats.hps or 0) then healM = m end
        if not lowM or (m.stats.avoidableDamageTaken or math.huge) < (lowM.stats.avoidableDamageTaken or math.huge) then lowM = m end
    end
    local selfStats = party[1].stats
    local nb, bosses = #dun.bosses, {}
    for i = 1, nb do
        local perMember = {}
        for _, pm in ipairs(party) do
            perMember[#perMember + 1] = { name = pm.name, classFile = pm.classFile, role = pm.role,
                dps = pm.stats.dps or 0, hps = pm.stats.hps or 0 }
        end
        table.sort(perMember, function(a, bb) return (a.dps or 0) > (bb.dps or 0) end)
        bosses[i] = { id = dun.id * 10 + i, name = dun.bosses[i], attempts = 1, wipes = 0, kills = 1,
            killDuration = 90 + i * 30, totalTime = 120 + i * 30, order = i, atSec = duration * (i / (nb + 1)),
            deaths = (i == nb) and 1 or 0, deathList = {}, perMember = perMember, killDps = selfStats.dps,
            topDps = { name = topM.name, classFile = topM.classFile, dps = topM.stats.dps or 0 },
            topHps = { name = healM.name, classFile = healM.classFile, hps = healM.stats.hps or 0 },
            lowAvoid = { name = lowM.name, classFile = lowM.classFile, amount = lowM.stats.avoidableDamageTaken or 0 } }
    end
    local combat, t = {}, 8
    while t < duration do local e = math.min(duration, t + 60); combat[#combat + 1] = { t, e }; t = e + 15 end
    local deaths = 0
    for _, m in ipairs(party) do deaths = deaths + (m.stats.deaths or 0) end
    return {
        id = "sample", mapId = dun.id, challengeMapId = dun.id, dungeonName = dun.name, combat = combat,
        timeLimit = timer, level = level, affixes = { 9, 10, 11 },
        affixNames = { "Tyrannical", "Bolstering", "Bursting" },
        seasonId = (ML.API and ML.API.GetCurrentSeason and ML.API.GetCurrentSeason()) or nil,
        expansionId = (ML.API and ML.API.GetExpansionLevel and ML.API.GetExpansionLevel()) or nil,
        startedAt = now - duration, completedAt = now, duration = duration,
        onTime = true, timeRemaining = timer - duration, keystoneUpgrade = 2, status = ML.STATUS.TIMED,
        scoreGain = 12,
        character = { guid = party[1].guid, name = party[1].name, realm = party[1].realm,
            fullName = party[1].fullName, classFile = party[1].classFile, role = party[1].role,
            specId = party[1].specId, mplusScore = party[1].mplusScore },
        party = party, playerStats = selfStats, deaths = deaths, bosses = bosses,
        provider = "NONE", providerVersion = "sample", confidence = "full", notes = "", tags = {}, _sample = true,
    }
end

-- Settings page sub-tabs. Now that the module's top-level tabs live in the sidebar, the in-body
-- top-nav is free for page-level navigation - each sub-tab shows one focused settings area full-width
-- (replacing the old cramped 2-column grid).
local settingsTab = "appearance"
local SETTINGS_TABS = {
    { "appearance",  "Appearance",   "palette" },
    { "tooltips",    "Tooltips",     "message" },
    { "scoreboard",  "Scoreboard",   "award" },
    { "deathreport", "Death Report", "skull" },
    { "livecoach",   "Live Coach",   "target" },
    { "tracking",    "Tracking",     "activity" },   -- Tracking + Data retention (2-column)
    { "regroup",     "Regroup",      "users" },
    { "misc",        "Misc",         "tools" },       -- Debug logging + minimap
}

-- Title + one-line description shown as a page heading below the sub-tab bar, matching every other
-- /tap page. Keyed by the sub-tab id above.
local SETTINGS_META = {
    appearance  = { "Appearance",   "How the ledger looks - the stat-tile style, and the date & time format used throughout." },
    tooltips    = { "Tooltips",     "Add your shared Mythic+ history with a player to their Blizzard tooltip, and choose where it appears." },
    scoreboard  = { "Scoreboard",   "The end-of-run scoreboard: how it's scaled, its font, and the sound it plays." },
    deathreport = { "Death Report", "An on-screen overlay after each pull (or at the run's end) listing who died and why." },
    livecoach   = { "Live Coach",   "After a boss (or a big pull), a quick on-screen reminder of what to work on - scored the same way your final grade is." },
    tracking    = { "Tracking",     "What gets recorded, the post-run summary, and how long your history is kept." },
    regroup     = { "Regroup",      "When you group up again with someone you've keyed with, show a short local-only recap of your history together." },
    misc        = { "Misc",         "Debug logging, and the minimap button." },
}

local function renderSettings(b, C, x, y, w, win)
    local s = DB.Settings()
    local rc = s.recap
    -- Toggle row: switch + label, always with a hover tooltip.
    local function toggle(lbl, get, set, tip)
        local tg = b:Toggle(x, y, get() and true or false, function(v) set(v); win:Refresh() end)
        b.theme:SetTip(tg, lbl, tip or lbl)
        b:Label(lbl, x + 46, y - 2, C.text); y = y - 30
    end
    -- Slider row: reserves headroom above the thumb for the value readout (it sits ABOVE the thumb),
    -- so the number clears the row above instead of hiding behind it, then draws the label + slider on
    -- one line within the current column.
    local function slider(lbl, ctlX, sw, minv, maxv, step, fmt, get, set, tip)
        y = y - 22
        b:Label(lbl, x, y - 2, C.subtext)
        T(b, b:Slider(x + ctlX, y), lbl, tip):Configure(sw, minv, maxv, step, get, set, fmt)
        y = y - 28
    end

    -- (The enable/disable toggle lives on the Platform Overview page - not repeated here.)

    -- Dock the settings sub-tab bar in the (now free) in-body top-nav; each sub-tab renders one focused
    -- area full-width. `COLW = w` so the section closures below draw single-column; `x`/`y` flow down.
    if win and win.SetTopNav then
        local items = {}
        for _, t in ipairs(SETTINGS_TABS) do items[#items + 1] = { key = t[1], label = t[2], icon = t[3] } end
        win:SetTopNav({ items = items, active = settingsTab, height = 28,
            onSelect = function(key) settingsTab = key; win:Refresh() end })
    end
    local COLW = w

    local function secTooltips()
    toggle("Show my history with a player on their tooltip", function() return s.playerTooltip ~= false end,
        function(v) s.playerTooltip = v end,
        "Adds your shared Mythic+ history (keys together, timed %, best key, averages, your notes) to a "
        .. "player's Blizzard tooltip - on party/raid frames & nameplates, the group finder, /who, the "
        .. "guild roster, community lists, and your friends list - only for people you've actually keyed with.")

    -- Per-surface toggles (only meaningful while the master switch above is on, so they show only then).
    if s.playerTooltip ~= false then
        local surf = s.tooltipSurfaces
        if type(surf) ~= "table" then surf = {}; s.tooltipSurfaces = surf end
        b:Label("Show on:", x + 20, y - 2, C.subtext); y = y - 24
        local SURFACES = {
            { "unit",      "Unit frames & nameplates", "Party/raid frames, nameplates, and world unit tooltips." },
            { "lfg",       "Group finder",             "Search-result entries in the Mythic+ group finder." },
            { "friends",   "Friends list",             "Your friends-list hover tooltip." },
            { "who",       "/who results",             "Rows in the /who results window." },
            { "guild",     "Guild roster",             "Rows in the guild roster." },
            { "community", "Communities",              "Member rows in community / club lists." },
        }
        for _, it in ipairs(SURFACES) do
            local key, lbl, tip = it[1], it[2], it[3]
            local tg = b:Toggle(x + 24, y, surf[key] ~= false, function(v) surf[key] = v; win:Refresh() end)
            b.theme:SetTip(tg, lbl, tip)
            b:Label(lbl, x + 70, y - 2, C.text); y = y - 28
        end
        y = y - 4
    end

    -- Preview: hover the chip to see a sample of the shared-history tooltip.
    b:Label("Preview", x, y - 2, C.subtext); y = y - 24
    local hb = b:Button(x, y, 120, "Hover me", "default", function() end, { icon = "eye", iconSize = 12, height = 26 })
    if b.theme.SetTipData then
        b.theme:SetTipData(hb, { title = "|cfff58cbaAshbringer|r-Illidan", minWidth = 260, lines = {
            { text = "Mythic Ledger - your shared history", color = "accent" },
            { text = "Keys together: 7      Timed: 86%" },
            { text = "Best together: Ara-Kara +18" },
            { text = "Avg score: 112      Deaths/run: 1.3" },
            { text = "Note: \"solid CC, brings lust\"", color = "subtext" },
        } })
    end
    y = y - 34
    end

    local function secStatTiles()
    b:Sub("STAT TILES", x, y); y = y - 30
    local _, swh = b:Wrap("The compact metric tiles shown on the end-of-run scoreboard, the run / player / "
        .. "character detail pages, and the season Overview. This sets their visual style.",
        x, y, COLW - 20, C.subtext, 10)
    y = y - (swh + 8)
    b:Label("Tile style", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Stat tile style",
        "How the stat tiles on the run scoreboard and detail pages look. Clean = flat dashboard tiles; "
        .. "Panel = darker WoW-style in-game tiles with a rank meter; Compact = data-rich cards with an "
        .. "extra footer line. (The Overview and Bests hero cards use a fixed style to match the dungeon cards.)"):SetChoices(210, {
        { "CLEAN", "Clean (dashboard)" }, { "PANEL", "Panel (WoW tiles)" }, { "COMPACT", "Compact (data-rich)" },
    }, function() return s.cardStyle or "COMPACT" end, function(v) s.cardStyle = v; win:Refresh() end)
    y = y - 40
    -- Live preview of two stat tiles in the currently-selected style.
    do
        local pstyle = tileStyle()
        local tileW = math.min(168, math.floor((COLW - 12) / 2))
        b:StatTile(x, y, { style = pstyle, width = tileW, height = 96, iconSize = 22,
            label = "AVG SCORE", value = "112.4", accent = "a06cf0", icon = "trophy",
            sub = "best +18", footer = { "best +18", "3 timed" } })
        b:StatTile(x + tileW + 12, y, { style = pstyle, width = tileW, height = 96, iconSize = 22,
            label = "TIMED", value = "86%", accent = "33dd66", icon = "circle-check",
            sub = "42 of 49 this season", footer = { "42 of 49", "this season" } })
        y = y - 96 - 6
        b:Label("Live preview of the selected style.", x, y - 2, C.subtext, 10)
        y = y - 18
    end
    end

    local function secDateTime()
    y = y - 12   -- breathing room below the Stat Tiles preview frame
    b:Sub("DATE & TIME", x, y); y = y - 30
    b:Label("Date format", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 100, y), "Date format",
        "How dates are written throughout the ledger. NA = mm/dd/yy, ISO = yyyy-mm-dd, EU = dd/mm/yy. "
        .. "The local time is always shown next to the date."):SetChoices(200, {
        { "NA", "NA (mm/dd/yy)" }, { "ISO", "ISO (yyyy-mm-dd)" }, { "EU", "EU (dd/mm/yy)" },
    }, function() return s.dateFormat or "NA" end, function(v) s.dateFormat = v; win:Refresh() end)
    y = y - 34
    b:Label("Clock", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 100, y), "Clock",
        "12- or 24-hour clock for the time shown next to each date. Times are always in your local timezone."):SetChoices(180, {
        { "24H", "24-hour (21:33)" }, { "12H", "12-hour (9:33 PM)" },
    }, function() return s.clockFormat or "24H" end, function(v) s.clockFormat = v; win:Refresh() end)
    y = y - 34
    b:Label("Preview:  " .. Util.dateTime(time()), x, y - 2, C.subtext, 11)
    y = y - 26
    end

    local function secScoreboard()
    toggle("Show post-run summary", function() return s.postRunSummary end, function(v) s.postRunSummary = v end,
        "Pop a summary after each completed key (queued until out of combat).")
    if s.postRunSummary then
        toggle("Show it only after looting the end chest", function() return s.postRunAfterLoot end, function(v) s.postRunAfterLoot = v end,
            "Wait to pop the summary until you loot the chest at the end of the run, instead of right when it finishes.")
        slider("Popup delay", 90, 200, 0, 30, 1, "%ds",
            function() return s.postRunDelay or 5 end, function(v) s.postRunDelay = v end,
            "How long to wait after the trigger (looting the end chest, or leaving combat) before the summary "
            .. "pops. 0 = instantly.")
    end
    slider("Scale", 90, 180, 0.5, 3.0, 0.05, "%.2fx",
        function() return s.scoreboardScale or 1.05 end, function(v) s.scoreboardScale = v end,
        "How big the end-of-run scoreboard opens (still capped to fit your screen). Also: /ledger scale <n>.")
    -- The tab is full-width, so the controls get generous widths (no wrapped dropdown menus).
    local ddW = math.max(220, math.min(340, COLW - 220))
    b:Label("Font", x, y - 2, C.subtext)
    b:FontSelect(x + 90, y, { width = ddW, value = s.scoreboardFont,
        onChange = function(key) s.scoreboardFont = TAP.IsGlobalFont(key) and "" or key end })
    T(b, b:Button(x + 90 + ddW + 12, y, 130, "Use UI font", "default", function() s.scoreboardFont = ""; win:Refresh() end),
        "Use UI font", "Reset the scoreboard to use the same font as the rest of the UI.")
    y = y - 38

    toggle("Play a sound when the scoreboard opens", function() return s.scoreboardSound end,
        function(v) s.scoreboardSound = v end,
        "Play a sound (default: FFVII Victory Fanfare) when the scoreboard appears.")
    if s.scoreboardSound then
        b:Label("Sound", x, y - 2, C.subtext)
        T(b, b:SoundSelect(x + 90, y, { width = ddW, value = s.scoreboardSoundKey or "VictoryFanfare",
            channel = s.scoreboardSoundChannel or "Master",
            onChange = function(v) s.scoreboardSoundKey = v end }), "Scoreboard sound", "The sound played when the scoreboard opens.")
        T(b, b:Button(x + 90 + ddW + 12, y, 64, "Test", "default", function()
            local theme = _G.TAP and _G.TAP.uiTheme
            if theme and theme.PlaySound then theme:PlaySound(s.scoreboardSoundKey or "VictoryFanfare", s.scoreboardSoundChannel or "Master") end
        end, { icon = "volume", iconSize = 13 }), "Test sound", "Preview the selected scoreboard sound.")
        y = y - 34
        b:Label("Channel", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 90, y), "Scoreboard sound channel",
            "Which audio channel the scoreboard sound plays on (e.g. Master, or Sound FX so it follows that "
            .. "volume slider)."):SetChoices(ddW, CHANNEL_CHOICES,
            function() return s.scoreboardSoundChannel or "Master" end, function(v) s.scoreboardSoundChannel = v end)
        y = y - 34
        b:Label("Play sound", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 90, y), "When to play the scoreboard sound",
            "End of run only = just the automatic post-run popup; Every view = also when you re-open a "
            .. "scoreboard from history."):SetChoices(ddW, {
            { "END", "End of run only" }, { "ALWAYS", "Every time it's viewed" },
        }, function() return s.scoreboardSoundWhen or "END" end, function(v) s.scoreboardSoundWhen = v end)
        y = y - 36
    end
    T(b, b:Button(x, y, 190, "Launch test scoreboard", "default", function()
        UI.ShowScoreboard(buildSampleRun(), { postRun = true })
    end, { icon = "layout-grid", iconSize = 13 }), "Test scoreboard",
        "Open the end-of-run scoreboard with a sample run so you can preview your scale, font, tile style and sound.")
    y = y - 40
    end

    -- DEATH REPORT: on-screen post-pull recap of who died and why.
    local function secDeathReport()
        local dr = s.deathReport
        if type(dr) ~= "table" then dr = {}; s.deathReport = dr end
        local fullW, baseX = COLW, x
        local halfW = math.floor((COLW - 28) / 2)
        local refreshPrev = function() if ML.DeathReport and ML.DeathReport.RefreshPreview then ML.DeathReport.RefreshPreview() end end
        local rowTop = y

        -- LEFT column: behavior. The enable switch lives here now (as "Enable Death Report"); the rest of
        -- the behavior controls appear once it's on.
        x, COLW = baseX, halfW
        b:Sub("BEHAVIOR", x, y, halfW); y = y - 30
        toggle("Enable Death Report", function() return dr.enabled end,
            function(v) dr.enabled = v; win:Refresh() end,
            "After combat drops (or at the run's end), flash a short overlay listing who died since the last "
            .. "report and why - time in the key, the killing blow, and the cause (including a missed kick's "
            .. "cast). Repost the last one to party chat with /ledger deathreport.")
        if dr.enabled then
            b:Label("When", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "When to show the report",
                "As soon as combat drops = a report after every pull (that pull's new deaths only). At the end "
                .. "of the run = one report of every death, when the key finishes."):SetChoices(220, {
                { "COMBAT", "As soon as combat drops" }, { "RUN_END", "At the end of the run" },
            }, function() return dr.trigger or "COMBAT" end, function(v) dr.trigger = v end)
            y = y - 40
            b:Label("Dismiss", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "How the report goes away",
                "Auto = it fades on its own after the time below. Click to dismiss = it stays until you "
                .. "click it (it captures the mouse while shown). Both = it fades after the time below OR "
                .. "when you click it, whichever happens first."):SetChoices(220, {
                { "AUTO", "Auto (fade after time)" }, { "CLICK", "Click to dismiss" }, { "BOTH", "Both (fade or click)" },
            }, function() return dr.dismiss or "AUTO" end, function(v) dr.dismiss = v; win:Refresh() end)
            y = y - 40
            toggle("Only report my own deaths", function() return dr.onlyMe end, function(v) dr.onlyMe = v end,
                "Show only your deaths, not the whole party's.")
            if (dr.dismiss or "AUTO") ~= "CLICK" then   -- AUTO and BOTH both auto-fade after this time
                slider("On screen for", 130, 170, 2, 20, 1, "%.0fs",
                    function() return dr.duration or 6 end, function(v) dr.duration = v end,
                    "How long the overlay stays before it fades out (also applies to Both).")
            end
            slider("Max deaths shown", 130, 170, 3, 20, 1, "%.0f",
                function() return dr.maxLines or 8 end, function(v) dr.maxLines = v end,
                "Cap how many deaths are listed at once.")
        end
        local lb = y

        if dr.enabled then
            -- RIGHT column: appearance (font / size / colors / panel).
            x, y, COLW = baseX + halfW + 28, rowTop, halfW
            b:Sub("APPEARANCE", x, y, halfW); y = y - 30
            b:Label("Font", x, y - 2, C.subtext)
            b:FontSelect(x + 90, y, { width = 200, value = dr.font,
                onChange = function(key) dr.font = TAP.IsGlobalFont(key) and "" or key; win:Refresh() end })
            y = y - 30
            T(b, b:Button(x, y, 120, "Use UI font", "default", function() dr.font = ""; win:Refresh() end),
                "Use UI font", "Use the same font as the rest of the UI.")
            y = y - 38
            slider("Text size", 130, 170, 10, 30, 1, "%.0f",
                function() return dr.fontSize or 15 end, function(v) dr.fontSize = v; win:Refresh() end, "Overlay text size.")
            b:Label("Header color", x, y - 2, C.subtext)
            b:Swatch(x + 100, y - 2, dr.titleColor or { 1, 0.82, 0.2 }, refreshPrev, "Header color", "The report's header line.")
            b:Label("Line color", x + 150, y - 2, C.subtext)
            b:Swatch(x + 230, y - 2, dr.textColor or { 0.94, 0.95, 0.98 }, refreshPrev, "Line color", "The per-death lines.")
            y = y - 34
            toggle("Draw a background panel", function() return dr.background end, function(v) dr.background = v end,
                "Draw a translucent panel behind the report text.")
            if dr.background then
                b:Label("Panel color", x + 20, y - 2, C.subtext)
                b:Swatch(x + 110, y - 2, dr.bgColor or { 0.03, 0.04, 0.06, 0.82 }, refreshPrev,
                    "Panel color", "The backing panel color (opacity is the slider below).")
                y = y - 30
                slider("Panel opacity", 130, 170, 0, 1, 0.05, "%.2f",
                    function() return (dr.bgColor and dr.bgColor[4]) or 0.82 end,
                    function(v) dr.bgColor = dr.bgColor or { 0.03, 0.04, 0.06, 0.82 }; dr.bgColor[4] = v; refreshPrev() end,
                    "How opaque the background panel is (0 = invisible).")
            end
            local rb = y

            -- Full width below both columns: live preview (all four causes) + Test / Move.
            x, y, COLW = baseX, math.min(lb, rb) - 12, fullW
            b:Sub("PREVIEW", x, y, fullW); y = y - 30
            local ph = (ML.DeathReport and ML.DeathReport.RenderPreview and ML.DeathReport.RenderPreview(b, x, y)) or 40
            y = y - ph - 14
            T(b, b:Button(x, y, 90, "Test", "default", function() if ML.DeathReport then ML.DeathReport.Test() end end,
                { icon = "eye", iconSize = 13 }), "Test", "Flash a sample death report (one of every cause) with your settings.")
            T(b, b:Button(x + 100, y, 140, "Move on screen", "default", function()
                -- The placement session hides and restores the manager itself, and `win` tells it
                -- which page to come back to.
                if ML.DeathReport then ML.DeathReport.StartMove(win) end
            end, { icon = "anchor", iconSize = 13 }), "Move on screen",
                "Opens placement mode: drag the sample where you want it, then Done (or Cancel).")
            y = y - 40
        end
    end

    local function secLiveCoach()
        local lc = s.liveCoach
        if type(lc) ~= "table" then lc = {}; s.liveCoach = lc end
        local fullW, baseX = COLW, x
        local halfW = math.floor((COLW - 28) / 2)
        local refreshPrev = function() if ML.LiveCoach and ML.LiveCoach.RefreshPreview then ML.LiveCoach.RefreshPreview() end end
        local rowTop = y

        -- LEFT column: behavior. The enable switch is here; the rest appears once it's on.
        x, COLW = baseX, halfW
        b:Sub("BEHAVIOR", x, y, halfW); y = y - 30
        toggle("Enable Live Coach", function() return lc.enabled end,
            function(v) lc.enabled = v; win:Refresh() end,
            "After a boss (or a big pull), score the run SO FAR with the same engine your final grade uses and "
            .. "flash a quick reminder of what to work on - kick more, push your DPS, heal harder, and so on. It "
            .. "never changes your score; the number shown is a 'so far' preview.")
        if lc.enabled then
            b:Label("Pop when", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "When to pop the coach",
                "Only when slipping keeps it quiet unless something is below par. The 'every fight' options also "
                .. "reassure you when you're doing well."):SetChoices(240, {
                { "SLIP", "Only when I'm slipping" }, { "QUIET", "Every fight (brief when good)" },
                { "ALWAYS", "Every fight (praise too)" },
            }, function() return lc.popPolicy or "SLIP" end, function(v) lc.popPolicy = v end)
            y = y - 40
            b:Label("After", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "What triggers it",
                "Bosses only = one nudge per boss. Bosses + big pulls also fires after a trash pack that lasted "
                .. "a while."):SetChoices(240, {
                { "BOSS", "Boss kills only" }, { "ALL", "Bosses + big trash pulls" },
            }, function() return lc.cadence or "BOSS" end, function(v) lc.cadence = v; win:Refresh() end)
            y = y - 40
            if (lc.cadence or "BOSS") == "ALL" then
                slider("Big pull is", 130, 170, 5, 30, 1, "%.0fs+",
                    function() return lc.minCombat or 10 end, function(v) lc.minCombat = v end,
                    "How long a trash pull must last to count as a 'big pull' (shorter pulls are skipped).")
            end
            b:Label("Detail", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "How much it shows",
                "One reminder = a single glanceable line. Top 2 = your two biggest fixes. Mini-review adds a "
                .. "headline and a strength."):SetChoices(240, {
                { "ONE", "One reminder" }, { "TWO", "Top 2 fixes" }, { "MINI", "Mini-review" },
            }, function() return lc.depth or "ONE" end, function(v) lc.depth = v; refreshPrev() end)
            y = y - 40
            b:Label("Dismiss", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "How it goes away",
                "Auto = fades after the time below. Click to dismiss = stays until you click it. Both = fades or "
                .. "click, whichever first."):SetChoices(240, {
                { "AUTO", "Auto (fade after time)" }, { "CLICK", "Click to dismiss" }, { "BOTH", "Both (fade or click)" },
            }, function() return lc.dismiss or "AUTO" end, function(v) lc.dismiss = v; win:Refresh() end)
            y = y - 40
            if (lc.dismiss or "AUTO") ~= "CLICK" then
                slider("On screen for", 130, 170, 2, 20, 1, "%.0fs",
                    function() return lc.duration or 7 end, function(v) lc.duration = v end,
                    "How long the coach stays before it fades out.")
            end
        end
        local lb = y

        if lc.enabled then
            -- RIGHT column: appearance.
            x, y, COLW = baseX + halfW + 28, rowTop, halfW
            b:Sub("APPEARANCE", x, y, halfW); y = y - 30
            b:Label("Font", x, y - 2, C.subtext)
            b:FontSelect(x + 90, y, { width = 200, value = lc.font,
                onChange = function(key) lc.font = TAP.IsGlobalFont(key) and "" or key; win:Refresh() end })
            y = y - 30
            T(b, b:Button(x, y, 120, "Use UI font", "default", function() lc.font = ""; win:Refresh() end),
                "Use UI font", "Use the same font as the rest of the UI.")
            y = y - 38
            slider("Text size", 130, 170, 10, 30, 1, "%.0f",
                function() return lc.fontSize or 15 end, function(v) lc.fontSize = v; win:Refresh() end, "Overlay text size.")
            b:Label("Header", x, y - 2, C.subtext)
            b:Swatch(x + 70, y - 2, lc.titleColor or { 0.36, 0.83, 0.92 }, refreshPrev, "Header color", "The grade / header line.")
            b:Label("Focus", x + 130, y - 2, C.subtext)
            b:Swatch(x + 190, y - 2, lc.fixColor or { 0.95, 0.62, 0.30 }, refreshPrev, "Focus color", "The 'work on this' lines.")
            y = y - 30
            b:Label("Praise", x, y - 2, C.subtext)
            b:Swatch(x + 70, y - 2, lc.goodColor or { 0.42, 0.82, 0.45 }, refreshPrev, "Praise color", "The 'on pace' / strength lines.")
            y = y - 34
            toggle("Draw a background panel", function() return lc.background end, function(v) lc.background = v end,
                "Draw a translucent panel behind the coach text.")
            if lc.background then
                b:Label("Panel color", x + 20, y - 2, C.subtext)
                b:Swatch(x + 110, y - 2, lc.bgColor or { 0.03, 0.04, 0.06, 0.85 }, refreshPrev,
                    "Panel color", "The backing panel color (opacity is the slider below).")
                y = y - 30
                slider("Panel opacity", 130, 170, 0, 1, 0.05, "%.2f",
                    function() return (lc.bgColor and lc.bgColor[4]) or 0.85 end,
                    function(v) lc.bgColor = lc.bgColor or { 0.03, 0.04, 0.06, 0.85 }; lc.bgColor[4] = v; refreshPrev() end,
                    "How opaque the background panel is (0 = invisible).")
            end
            local rb = y

            -- Full width below both columns: live preview + Test / Move.
            x, y, COLW = baseX, math.min(lb, rb) - 12, fullW
            b:Sub("PREVIEW", x, y, fullW); y = y - 30
            local ph = (ML.LiveCoach and ML.LiveCoach.RenderPreview and ML.LiveCoach.RenderPreview(b, x, y)) or 40
            y = y - ph - 14
            T(b, b:Button(x, y, 90, "Test", "default", function() if ML.LiveCoach then ML.LiveCoach.Test() end end,
                { icon = "eye", iconSize = 13 }), "Test", "Flash a sample coach with your current settings.")
            T(b, b:Button(x + 100, y, 140, "Move on screen", "default", function()
                -- The placement session hides and restores the manager itself, and `win` tells it
                -- which page to come back to.
                if ML.LiveCoach then ML.LiveCoach.StartMove(win) end
            end, { icon = "anchor", iconSize = 13 }), "Move on screen",
                "Opens placement mode: drag the sample where you want it, then Done (or Cancel).")
            y = y - 40
        end
    end

    local function secTracking()
    b:Sub("TRACKING", x, y); y = y - 30
    toggle("Track abandoned runs", function() return s.trackAbandoned end, function(v) s.trackAbandoned = v end,
        "Save keys you leave or reset before completion (kept apart from your timed %).")
    toggle("Confirm before saving a recovered abandoned run", function() return s.confirmAbandonSave end, function(v) s.confirmAbandonSave = v end,
        "After a reload/disconnect with an unfinished key, ask before saving it as abandoned.")
    end

    local function secRegroup()
    local fullW, baseX = COLW, x
    local halfW = math.floor((COLW - 28) / 2)
    b:Label("Local only - never posted to group.", x, y - 2, C.subtext, 10); y = y - 22
    toggle("Show a recap when a past teammate returns", function() return rc.enabled end, function(v) rc.enabled = v end,
        "When you group up again with someone you've keyed with, print a short local-only recap of your history together.")
    local rowTop = y

    -- LEFT column: when it fires + what it counts.
    x, COLW = baseX, halfW
    b:Sub("TRIGGERS", x, y, halfW); y = y - 30
    b:Label("Display", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Regroup display", "Where the recap appears. Local chat is only visible to you."):SetChoices(180, {
        { "CHAT", "Local chat" }, { "TOAST", "Toast" }, { "BOTH", "Both" }, { "OFF", "Off" },
    }, function() return rc.display end, function(v) rc.display = v end)
    y = y - 34
    b:Label("History", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Regroup history", "Count shared runs from the current season only, or all seasons."):SetChoices(180, {
        { "SEASON", "Current season" }, { "ALL", "All seasons" },
    }, function() return rc.history end, function(v) rc.history = v end)
    y = y - 34
    b:Label("Fires on", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Regroup trigger",
        "When the recap fires. On join = as soon as a returning player is in your group; On ready check "
        .. "= only when a ready check starts; Both = either. (It never fires on zoning in/out.)"):SetChoices(180, {
        { "JOIN", "On join" }, { "READY", "On ready check" }, { "BOTH", "Both" },
    }, function() return rc.trigger or "JOIN" end, function(v) rc.trigger = v end)
    y = y - 34
    slider("Minimum shared runs", 160, 130, 1, 10, 1, "%d",
        function() return rc.minShared or 1 end, function(v) rc.minShared = v end,
        "Only recap someone once you've done at least this many keys together.")
    local lb = y

    -- RIGHT column: what a recap includes + its sound.
    x, y, COLW = baseX + halfW + 28, rowTop, halfW
    b:Sub("INCLUDE", x, y, halfW); y = y - 30
    toggle("Performance averages", function() return rc.includeAverages end, function(v) rc.includeAverages = v end,
        "Add role-relevant averages (e.g. DPS/HPS, deaths) to the recap line.")
    toggle("Last-run result", function() return rc.includeLastResult end, function(v) rc.includeLastResult = v end,
        "Append the outcome of your most recent run with that player.")
    toggle("Personal notes (off by default)", function() return rc.includeNotes end, function(v) rc.includeNotes = v end,
        "Your private notes are NEVER shown automatically unless you turn this on.")
    toggle("Play a sound when found", function() return rc.sound end, function(v) rc.sound = v; win:Refresh() end,
        "Play a sound once per group (a single sound even if several returning players are found).")
    if rc.sound then
        b:Label("Sound", x, y - 2, C.subtext)
        T(b, b:SoundSelect(x + 90, y, { width = 150, value = rc.soundKey or "Applause",
            channel = rc.soundChannel or "Master",
            onChange = function(v) rc.soundKey = v end }), "Regroup sound", "The sound played when a returning player is detected.")
        T(b, b:Button(x + 248, y, 58, "Test", "default", function()
            local theme = _G.TAP and _G.TAP.uiTheme
            if theme and theme.PlaySound then theme:PlaySound(rc.soundKey or "Applause", rc.soundChannel or "Master") end
        end, { icon = "volume", iconSize = 13 }), "Test sound", "Preview the selected sound.")
        y = y - 34
        b:Label("Channel", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 90, y), "Regroup sound channel",
            "Which audio channel the sound plays on."):SetChoices(150, CHANNEL_CHOICES,
            function() return rc.soundChannel or "Master" end, function(v) rc.soundChannel = v end)
        y = y - 34
    end
    local rb = y

    -- Full width below both columns: action buttons + a live preview spanning both cells.
    x, y, COLW = baseX, math.min(lb, rb) - 12, fullW
    T(b, b:Button(x, y, 190, "Preview for current group", "default", function() ML.Recap.PreviewCurrentGroup() end),
        "Preview recaps", "Print a sample recap for everyone in your current group (ignores the once-per-session guard).")
    T(b, b:Button(x + 200, y, 150, "Test toast/message", "primary", function()
        if ML.Recap and ML.Recap.Simulate then ML.Recap.Simulate(2) end
    end, { icon = "eye", iconSize = 13 }), "Test toast/message",
        "Fire a sample recap exactly as configured (toast and/or local chat), using players from your saved history.")
    y = y - 34
    do
        b:Label("Preview:", x, y - 2, C.subtext, 11); y = y - 18
        local nameLine, lines = ML.Recap.PreviewLines(rc)
        local pad, top = 10, y
        local ty = top - pad
        b:Label(nameLine .. "|cff8b91a0:|r", x + pad, ty - 2, C.text, 12); ty = ty - 20
        for _, ln in ipairs(lines) do
            b:Label("|cff5a606c" .. "\226\128\162" .. "|r  " .. ln, x + pad + 4, ty - 2, C.text, 11); ty = ty - 17
        end
        ty = ty - pad
        b:Box(x, top, COLW - 8, top - ty, 0.06, 0, C.accent)
        y = ty - 14
    end
    end

    ----------------------------------------------------------------------
    -- RUN HISTORY. ONE section for the whole life of a run's data, because there is only one question
    -- being answered: how long do we keep it, and what happens then. It reads as a single ladder -
    --   full detail  ->  trimmed (run kept, review detail dropped)  ->  deleted
    -- with one window, one action, one set of locks and one Apply. Splitting trimming and deleting into
    -- two blocks made the user reconcile two overlapping policies that both had a window, both had a
    -- "don't touch my best runs" toggle and both had their own button.
    ----------------------------------------------------------------------
    local function secRunHistory()
    b:Sub("RUN HISTORY", x, y); y = y - 30
    local Arch = ML.Archive

    -- Everything below only STAGES a policy; nothing is trimmed or removed until Apply is pressed.
    if retentionPending   == nil then retentionPending   = s.retentionRuns or 0 end
    if retScopePending    == nil then retScopePending    = s.retentionScope or "ALL" end
    if retKeepTopPending  == nil then retKeepTopPending  = (s.retentionKeepTop ~= false) end
    if retActionPending   == nil then retActionPending   = s.retentionAction or "TRIM" end
    if retDaysPending     == nil then retDaysPending     = s.retentionDays or 90 end
    if retAutoPending     == nil then retAutoPending     = s.retentionAuto and true or false end

    -- ONE measuring pass, cached: size, per-season breakdown, trimmed/locked counts and the previews.
    -- The settings page redraws on every toggle, so nothing here may walk the database per render.
    if storageStats == nil and DB.root and Arch then
        local st = { total = Arch.SizeOf(DB.root), seasons = {}, seasonPlan = {},
                     trimmed = 0, locked = 0, lockedPlayers = 0 }
        for _, r in ipairs(DB.Runs()) do
            local sid = r.seasonId
            if sid ~= nil then
                local e = st.seasons[sid]
                if not e then e = { n = 0, bytes = 0, trimmed = 0 }; st.seasons[sid] = e end
                e.n = e.n + 1
                e.bytes = e.bytes + Arch.SizeOf(r)
                if Arch.IsCompact(r) then e.trimmed = e.trimmed + 1 end
            end
            if Arch.IsCompact(r) then st.trimmed = st.trimmed + 1 end
            if DB.IsLocked(r) then st.locked = st.locked + 1 end
        end
        for _, m in pairs(DB.PlayerMeta() or {}) do
            if type(m) == "table" and m.protected then st.lockedPlayers = st.lockedPlayers + 1 end
        end
        for sid in pairs(st.seasons) do st.seasonPlan[sid] = Arch.PlanSeason(sid) end
        storageStats = st
    end
    local stat = storageStats or { total = 0, seasons = {}, seasonPlan = {},
                                   trimmed = 0, locked = 0, lockedPlayers = 0 }

    -- Headline: what you are storing right now.
    local runsN = DB.CountRuns()
    b:Label(string.format("Storing |cfff4f6fb%s|r, about |cfff4f6fb%.1f MB|r%s.",
        nRuns(runsN), stat.total / 1048576,
        stat.trimmed > 0 and string.format("  (%s already trimmed)", nRuns(stat.trimmed)) or ""),
        x, y - 2, C.subtext, 11)
    y = y - 26

    ------------------------------------------------------------------
    -- 1. The window: how long a run keeps FULL detail.
    ------------------------------------------------------------------
    b:Label("Keep full detail for", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 150, y), "Full-detail window",
        "How long a run keeps everything. Anything older is trimmed or deleted, whichever you pick "
        .. "below. Runs with no season, expansion or date recorded are always kept."):SetChoices(210, {
        { "ALL",       "All runs (keep everything)" },
        { "SEASON",    "The current season" },
        { "EXPANSION", "The current expansion" },
        { "DAYS",      "A number of days" },
    }, function() return retScopePending end,
       function(v) retScopePending = v; win:Refresh() end)
    y = y - 34
    if retScopePending == "DAYS" then
        slider("Days to keep", 150, 200, 7, 365, 1, "%d days",
            function() return retDaysPending end,
            function(v) retDaysPending = v; win:Refresh() end,
            "Runs older than this lose their full detail.")
    end

    ------------------------------------------------------------------
    -- 2. The action: what happens to a run once it falls outside that window.
    ------------------------------------------------------------------
    if retScopePending ~= "ALL" then
        b:Label("Then", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 150, y), "What happens to older runs",
            "Trim keeps the run - date, key, result, party, your numbers, score and grade all stay, and "
            .. "it still shows in every list and chart. It only drops the deep review detail (death "
            .. "recaps, per-spell breakdowns, the combat timeline), which is about 87% of its size. "
            .. "Delete removes the run entirely."):SetChoices(210, {
            { "TRIM",   "Trim the detail (keep the run)" },
            { "DELETE", "Delete the run" },
        }, function() return retActionPending end,
           function(v) retActionPending = v; win:Refresh() end)
        y = y - 34
    end

    ------------------------------------------------------------------
    -- 3. The ceiling: a hard cap on how many runs are stored at all.
    ------------------------------------------------------------------
    local unlimited = (retentionPending or 0) <= 0
    local keepAll = b:Toggle(x, y, unlimited, function(v)
        if v then
            b.theme:Confirm({
                title = "Keep every run?",
                message = "Your runs will never be cleaned up, so over time they can add up and use more "
                    .. "memory. Keep them all anyway?",
                variant = "warning", confirmLabel = "Keep everything",
                onConfirm = function() retentionPending = 0; win:Refresh() end,
                onCancel  = function() win:Refresh() end,   -- pending stays > 0, so the toggle snaps back off
            })
        else
            retentionPending = (retentionPending and retentionPending > 0) and retentionPending or 2000
            win:Refresh()
        end
    end)
    b.theme:SetTip(keepAll, "Never delete a run",
        "Keep every run forever, however old. Trimming can still reclaim space without losing runs.")
    b:Label("Never delete a run", x + 46, y - 2, C.text)
    y = y - 34
    if not unlimited then
        slider("Store at most", 150, 200, 100, 5000, 100, "%d runs",
            function() return retentionPending end,
            function(v) retentionPending = v; win:Refresh() end,
            "A ceiling on stored runs regardless of age. Once you are over it the oldest are DELETED, "
            .. "since a ceiling is about how much you keep, not how detailed it is.")
    end

    ------------------------------------------------------------------
    -- 4. What is protected from all of the above.
    ------------------------------------------------------------------
    local kt = b:Toggle(x, y, retKeepTopPending, function(v) retKeepTopPending = v; win:Refresh() end)
    b.theme:SetTip(kt, "Never delete a top run",
        "Protect your best key per dungeon, your top 10 and every crowned run from DELETION. They can "
        .. "still be trimmed: a trimmed run is still there, still crowned and still scored, so nothing "
        .. "you would call a 'top run' is lost. To hold one at full detail, use Keep on the run itself.")
    b:Label("Never delete a top run", x + 46, y - 2, C.text)
    y = y - 34

    local autoTg = b:Toggle(x, y, retAutoPending, function(v) retAutoPending = v; win:Refresh() end)
    b.theme:SetTip(autoTg, "Apply automatically",
        "Enforce this policy on its own, at login and when a season ends. With it off, nothing ever "
        .. "happens until you press Apply.")
    b:Label("Apply automatically", x + 46, y - 2, C.text)
    y = y - 32

    if stat.locked > 0 then
        b:Label(string.format("|cff8fbf6bKept:|r %s locked%s. Never trimmed, never deleted.",
            nRuns(stat.locked),
            stat.lockedPlayers > 0 and string.format(" (including everything with %d protected player%s in it)",
                stat.lockedPlayers, stat.lockedPlayers == 1 and "" or "s") or ""),
            x, y - 2, C.subtext, 11)
        y = y - 24
    end

    ------------------------------------------------------------------
    -- 5. Apply, with a preview of exactly what it will do.
    ------------------------------------------------------------------
    local dirty = (retentionPending ~= (s.retentionRuns or 0))
        or (retScopePending ~= (s.retentionScope or "ALL"))
        or (retKeepTopPending ~= (s.retentionKeepTop ~= false))
        or (retActionPending ~= (s.retentionAction or "TRIM"))
        or (retDaysPending ~= (s.retentionDays or 90))
        or (retAutoPending ~= (s.retentionAuto and true or false))

    -- Preview the STAGED window, not the saved one, so the button describes what Apply would really do.
    local preview = (Arch and retScopePending ~= "ALL")
        and Arch.Plan({ scope = retScopePending, days = retDaysPending }) or { compact = 0, bytes = 0, locked = 0 }
    local willTrim = (retActionPending == "TRIM") and preview.compact or 0
    local overCap = 0
    if (retentionPending or 0) > 0 then overCap = math.max(0, runsN - retentionPending) end

    local what
    if retScopePending == "ALL" and overCap == 0 then
        what = "Nothing to do - you are keeping everything."
    else
        local bits = {}
        if willTrim > 0 then
            bits[#bits + 1] = string.format("trim %s (about %.1f MB back)", nRuns(willTrim), preview.bytes / 1048576)
        elseif retActionPending == "DELETE" and preview.compact > 0 then
            bits[#bits + 1] = string.format("delete %s outside the window", nRuns(preview.compact))
        end
        if overCap > 0 then bits[#bits + 1] = string.format("delete %s over the limit", nRuns(overCap)) end
        what = (#bits > 0) and ("Will " .. table.concat(bits, ", and ") .. ".") or "Nothing currently matches."
    end

    T(b, b:Button(x, y, 90, "Apply", dirty and "primary" or "default", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        local destructive = (retActionPending == "DELETE" and preview.compact > 0) or overCap > 0
        local function commit()
            s.retentionScope  = retScopePending
            s.retentionRuns   = retentionPending
            s.retentionKeepTop = retKeepTopPending
            s.retentionAction = retActionPending
            s.retentionDays   = retDaysPending
            s.retentionAuto   = retAutoPending
            local res = DB.ApplyRetention()
            storageStats = nil
            if theme and theme.Toast and type(res) == "table" then
                local msg
                if res.trimmed > 0 and res.removed > 0 then
                    msg = string.format("Trimmed %s and removed %s. %.1f MB back.",
                        nRuns(res.trimmed), nRuns(res.removed), res.bytes / 1048576)
                elseif res.trimmed > 0 then
                    msg = string.format("Trimmed %s. %.1f MB back.", nRuns(res.trimmed), res.bytes / 1048576)
                elseif res.removed > 0 then
                    msg = string.format("Removed %s.", nRuns(res.removed))
                end
                if msg then theme:Toast({ variant = "success", icon = "check", text = msg }) end
            end
            win:Refresh()
        end
        if destructive then
            theme:Confirm({
                title = "Apply this policy?", variant = "danger", confirmLabel = "Apply",
                message = what .. "\n\nDeleted runs cannot be recovered."
                    .. ((stat.locked > 0) and ("\n\n" .. nRuns(stat.locked) .. " you locked will be left alone.") or ""),
                onConfirm = commit,
            })
        else
            commit()
        end
    end), "Apply", "Commit the policy above and enforce it now. Nothing changes until you press this.")
    b:Label(dirty and "|cffe0a030staged - not yet applied|r" or what, x + 100, y - 2, C.subtext, 11)
    y = y - 30
    if dirty then b:Label(what, x, y - 2, C.subtext, 11); y = y - 22 end

    ------------------------------------------------------------------
    -- 6. Per-season table: what each season costs, and act on just that one.
    ------------------------------------------------------------------
    local seasons = History.SeasonsPresent()
    if Arch and #seasons > 0 then
        y = y - 6
        b:Label("BY SEASON", x, y, C.accent, 11); y = y - 22
        local cur = currentSeason()
        for _, sid in ipairs(seasons) do
            local e = stat.seasons[sid] or { n = 0, bytes = 0, trimmed = 0 }
            local sp = stat.seasonPlan[sid] or { compact = 0, bytes = 0 }
            local isCur = (sid == cur)
            b:Label(ML.SeasonLabel(sid) .. (isCur and "  |cff8fbf6b(current)|r" or ""), x, y - 2, C.text, 12)
            b:Label(string.format("%s  -  %.1f MB%s", nRuns(e.n), e.bytes / 1048576,
                e.trimmed > 0 and string.format("  -  %d trimmed", e.trimmed) or ""),
                x + 230, y - 2, C.subtext, 11)
            if sp.compact > 0 then
                T(b, b:Button(x + COLW - 150, y + 2, 110, "Trim", "default", function()
                    local theme = _G.TAP and _G.TAP.uiTheme
                    theme:Confirm({
                        title = "Trim " .. ML.SeasonLabel(sid) .. "?",
                        variant = isCur and "danger" or "warning",
                        confirmLabel = "Trim " .. nRuns(sp.compact),
                        message = string.format(
                            "%s will lose the deep review detail, freeing about %.1f MB. Dates, keys, "
                            .. "results, parties, scores and grades are all kept.%s",
                            nRuns(sp.compact), sp.bytes / 1048576,
                            isCur and "\n\nThis is your CURRENT season, so you will lose the review "
                                .. "detail on runs you may still want to study." or ""),
                        onConfirm = function()
                            local res = Arch.CompactSeason(sid)
                            storageStats = nil
                            if theme and theme.Toast then
                                theme:Toast({ variant = "success", icon = "check",
                                    text = string.format("Trimmed %s. %.1f MB back.",
                                        nRuns(res.runs), res.bytes / 1048576) })
                            end
                            win:Refresh()
                        end,
                    })
                end, { height = 22 }), "Trim this season",
                    string.format("%s here can be trimmed, freeing about %.1f MB.", nRuns(sp.compact), sp.bytes / 1048576))
            else
                b:Label((e.n > 0 and e.trimmed >= e.n) and "all trimmed" or "nothing to trim",
                    x + COLW - 150, y - 2, C.subtext, 11)
            end
            y = y - 28
        end
    end

    ------------------------------------------------------------------
    -- 7. The nuclear option.
    ------------------------------------------------------------------
    y = y - 8
    T(b, b:Button(x, y, 160, "Delete All History", "danger", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        theme:Confirm({ title = "Delete ALL history?", variant = "danger", confirmLabel = "Delete everything",
            message = "This permanently erases every recorded run and summary, including runs you locked. "
                .. "Your player notes, tags and favorites are kept. This cannot be undone.",
            onConfirm = function() DB.WipeHistory(); storageStats = nil; win:Refresh() end })
    end, { icon = "trash", iconSize = 13 }), "Delete all",
        "Permanently erase every recorded run. Player notes, tags and favorites are kept.")
    y = y - 44
    end


    local function secDebug()
    b:Sub("DEBUG", x, y); y = y - 30
    toggle("Debug logging", function() return s.debug end, function(v) s.debug = v; ML._debugEcho = v end,
        "Echo internal diagnostics to chat and the Debug page. Also unlocks the sidebar Debug page.")
    end

    local function secMinimap()
    b:Sub("MINIMAP", x, y); y = y - 30
    toggle("Show minimap icon", function() return _G.TAP and _G.TAP.IsMinimapButtonShown and _G.TAP:IsMinimapButtonShown(ML.MODULE_ID) end,
        function(v) if _G.TAP and _G.TAP.SetMinimapButtonShown then _G.TAP:SetMinimapButtonShown(ML.MODULE_ID, v) end end,
        "Show a Mythic Ledger button on the minimap. Left-click opens the ledger; drag to move it; right-click hides it.")
    end

    -- Each sub-tab is either { single = {...} } (one column, full width) or { cols = { {left}, {right} },
    -- span = {...} } (two columns, then optional full-width sections below). The 2-col renderer reuses the
    -- section closures with COLW set to a half-width and x pointed at each column.
    local COLGAP = 28
    local HALF = math.floor((w - COLGAP) / 2)
    local leftX, rightX = x, x + HALF + COLGAP
    local SUBTABS = {
        appearance  = { single = { secStatTiles, secDateTime } },
        tooltips    = { single = { secTooltips } },
        scoreboard  = { single = { secScoreboard } },
        deathreport = { single = { secDeathReport } },
        livecoach   = { single = { secLiveCoach } },
        -- One column: RUN HISTORY is a single tall block now (window, action, cap, locks, per-season),
        -- and splitting it across columns would break the ladder it is trying to read as.
        tracking    = { single = { secTracking, secRunHistory } },
        regroup     = { single = { secRegroup } },
        misc        = { single = { secDebug, secMinimap } },
    }
    -- Page heading for the active sub-tab, below the sub-tab bar, matching every other /tap page.
    local smeta = SETTINGS_META[settingsTab] or SETTINGS_META.appearance
    y = b:PageHeading(x, y, smeta[1], smeta[2], w)
    local spec = SUBTABS[settingsTab] or SUBTABS.appearance
    local bottom = y
    if spec.cols then
        local rowTop = y
        for _, fn in ipairs(spec.cols[1] or {}) do x, y = leftX, y; COLW = HALF; fn() end
        local lb = y
        y = rowTop
        for _, fn in ipairs(spec.cols[2] or {}) do x, y = rightX, y; COLW = HALF; fn() end
        local rb = y
        x, COLW = leftX, w
        bottom = math.min(lb, rb)
    end
    if spec.single then
        x, y, COLW = leftX, bottom, w
        for _, fn in ipairs(spec.single) do fn() end
        bottom = y
    end
    if spec.span then
        x, y, COLW = leftX, bottom, w
        for _, fn in ipairs(spec.span) do fn() end
        bottom = y
    end
    return bottom - 14
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
        "Probe every live API the add-on uses (safe on a target dummy - validates the stat pipeline without a key).")
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
-- Column header for the dungeonRunRow tables (character- and dungeon-details "runs" lists). Labels line
-- up with dungeonRunRow's column offsets below. Returns the y beneath the header band.
local function dungeonRunHeader(b, C, x, y, rowW, sort, win)
    b:Box(x, y + 4, rowW, 22, 0.10, 0, C.accent)
    sortHdr(b, C, x + 10,  y - 3, 52, "Date",      "date",     sort, win)
    hdr(b, C, x + 116, y - 3, "Character")
    sortHdr(b, C, x + 268, y - 3, 30, "Key",       "key",      sort, win)
    hdr(b, C, x + 310, y - 3, "Result")
    sortHdr(b, C, x + 402, y - 3, 40, "Time",      "duration", sort, win)
    sortHdr(b, C, x + 476, y - 3, 48, "Deaths",    "deaths",   sort, win)
    sortHdr(b, C, x + 524, y - 3, 62, "DPS / HPS", "metric",   sort, win)
    return y - 24
end

local function dungeonRunRow(b, C, x, yTop, rowW, r, i, win)
    local role = r.character and r.character.role
    b:Row(x, yTop, rowW, 26, { index = i, tipData = runTipData(r),
        onClick = function() view.detailRun = r.id; win:Refresh() end })
    b:Label(Util.dateShort(r.completedAt), x + 10, yTop - 9, C.subtext, 11)
    b:Label(classColorText(r.character and r.character.classFile, r.character and r.character.name or "?"),
        x + 116, yTop - 9, C.text, 11)
    if r.bestOfKind then b:Tex(x + 252, yTop - 9, 12, 12, "crown", nil, { 1, 0.82, 0.2 }) end
    b:Label(Util.keyLabel(r.level), x + 268, yTop - 9, C.accent, 12)
    b:Badge(x + 310, yTop - 8, { text = statusText(r.status), variant = statusBadgeVariant(r.status) })
    b:Label(Util.duration(r.duration), x + 402, yTop - 9, C.text, 11)
    b:Label(Util.numOr(r.deaths, "%d"), x + 476, yTop - 9, C.text, 11)
    b:Label(primaryMetric(role, r.playerStats), x + 524, yTop - 9, C.text, 11)
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
        lines[#lines + 1] = { text = "No per-boss DPS captured yet (needs the Blizzard meter).", color = "subtext" }
    end
    return { title = bo.name or "Boss", lines = lines }
end

local function renderDungeonDetails(b, C, x, y, w, win)
    local mapId = view.detailDungeon
    local mi = API.GetMapInfo(mapId) or {}
    local rowW = w - 12
    local rows = History.FilterRuns({ mapId = mapId, seasonId = scopeSeason(), character = scopeCharacter() })

    T(b, b:Button(x + w - 84, y, 72, "Back", "default", function() view.detailDungeon = nil; win:Refresh() end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the dungeons list.")

    -- Season + Character scope (shared with the Overview / Dungeons tabs).
    local nx = scopeControl(b, C, x, y, "Season", 170, "Season",
        "Scope this dungeon's stats to a season, or show all seasons.",
        seasonChoices(), function() return view.season end,
        function(v) view.season = v; if win then win:Refresh() end end)
    scopeControl(b, C, nx, y, "Character", 180, "Character",
        "Show this dungeon's stats for all characters combined, or focus on a single character.",
        overviewCharChoices(), function() return view.character or "all" end,
        function(v) view.character = v; if win then win:Refresh() end end)
    y = y - 40

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
        local myDeaths = History.PlayerDeaths(r)   -- YOUR deaths per run, not the whole party's
        if type(myDeaths) == "number" then dSum = dSum + myDeaths; dN = dN + 1 end
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

    -- BOSSES: one hero card per boss - big portrait, large per-boss stats, and your DPS spread.
    local bosses = History.DungeonBosses(mapId, scopeSeason(), scopeCharacter())
    y = b:Section("BOSSES", x, y); y = y - 26
    if #bosses == 0 then
        b:Label("No boss encounters recorded here yet.", x + 4, y - 2, C.subtext, 11); y = y - 22
    else
        for _, bo in ipairs(bosses) do
            local pulls = bo.engaged or 0
            local line1 = string.format("Pulls %d   ·   Kills %d   ·   Wipes %d   ·   Deaths %d",
                pulls, bo.kills or 0, bo.wipes or 0, bo.deaths or 0)
            local line2
            if bo.bestDps then
                line2 = "Your DPS   best " .. Util.shortNum(bo.bestDps)
                    .. (bo.avgDps and ("   ·   avg " .. Util.shortNum(bo.avgDps)) or "")
                    .. (bo.lowDps and ("   ·   low " .. Util.shortNum(bo.lowDps)) or "")
            else
                line2 = "No per-boss DPS captured yet"
            end
            local bIcon = API.BossIcon(bo.name, bo.id)
            heroCard(b, C, x, y, rowW, 68, {
                accent = C.accent,
                icon = bIcon or "skull", iconWide = bIcon ~= nil, iconSize = bIcon and 100 or 40,
                iconTint = (not bIcon) and C.accent or nil,   -- tint only the bundled fallback, not a portrait
                title = bo.name or "Boss",
                lines = { line1, line2 },
                tipData = bossTipData(bo),
            })
            y = y - 68 - 8
        end
    end
    y = y - 8

    -- TOP RUNS (best timed: highest key, then fastest) - the same art hero card the Dungeons + Bests
    -- tabs use, each opens the full run.
    local top = {}
    for _, r in ipairs(rows) do if r.status == STATUS.TIMED then top[#top + 1] = r end end
    table.sort(top, function(a, bb)
        if (a.level or 0) ~= (bb.level or 0) then return (a.level or 0) > (bb.level or 0) end
        return (a.duration or math.huge) < (bb.duration or math.huge)
    end)
    y = b:Section("TOP RUNS", x, y); y = y - 26
    if #top == 0 then
        b:Label("No timed runs here yet.", x + 4, y - 2, C.subtext, 11); y = y - 20
    else
        local count = math.min(5, #top)
        for i = 1, count do
            topRunCard(b, C, x, y, rowW, 66, i, top[i], win)
            y = y - 66 - 8
        end
    end
    y = y - 14

    -- ALL RUNS box (paginated).
    y = b:Section(string.format("ALL RUNS (%d)", n), x, y); y = y - 24
    if n == 0 then
        b:Label("No runs recorded for this dungeon.", x + 4, y - 2, C.subtext, 11); return y - 20
    end
    sortRuns(rows, dungeonRunSort)
    local first, last = pagerBar(b, C, x, y, rowW, n, "dungeonRuns", win); y = y - 42
    y = dungeonRunHeader(b, C, x, y, rowW, dungeonRunSort, win)
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
-- A class/spec "hero" card: the spec's icon, its name in CLASS COLOR, a class-colored accent edge +
-- subtle wash, the role, and a two-line stat readout (runs / timed% / avg key, then best key · DPS-or-
-- HPS · avg deaths). Mirrors the dungeon hero card's shape so the two sections read as one set.
function specHeroCard(b, C, cx, cy, cw, ch, sp, classFile)   -- forward-declared above
    local rgb = classRGB(classFile) or C.accent
    b:Box(cx - 1, cy + 1, cw + 2, ch + 2, 0.9, 0, C.border)              -- 1px border
    b:Box(cx, cy, cw, ch, 1, 1, { 0, 0, 0 })                            -- black base
    b:Box(cx, cy, cw, ch, 0.12, 1, rgb)                                 -- subtle class-color wash
    b:VRule(cx + 1, cy, cy - ch, 2, rgb)                                -- class-color accent edge
    local icon = specIconID(sp.specId) or sp.specIcon
    if icon then b:Tex(cx + 12, cy - 9, 30, 30, icon) end               -- large spec icon
    local nm = sp.specName or specName(sp.specId) or (sp.role and (ML.ROLE_LABEL[sp.role] or sp.role)) or "Unknown"
    b:Label(classColorText(classFile, nm), cx + 52, cy - 12, C.text, 14)
    if sp.role then b:Label(ML.ROLE_LABEL[sp.role] or sp.role, cx + cw - 62, cy - 13, C.subtext, 11) end
    local runs = (sp.totals and sp.totals.runs) or 0
    b:Label(string.format("%d run%s", runs, runs == 1 and "" or "s")
        .. "   ·   " .. (sp.timedPct and Util.percent(sp.timedPct) or "-") .. " timed"
        .. "   ·   " .. (sp.avgLevel and string.format("+%.1f avg key", sp.avgLevel) or "-"),
        cx + 52, cy - 34, C.subtext, 11)
    local perf = (sp.role == "HEALER") and (sp.avgHps and (Util.shortNum(sp.avgHps) .. " HPS"))
        or (sp.avgDps and (Util.shortNum(sp.avgDps) .. " DPS")) or nil
    local seg = "Best " .. (sp.highestTimed and ("+" .. sp.highestTimed) or "-")
    if perf then seg = seg .. "   ·   " .. perf end
    if sp.avgDeaths then seg = seg .. "   ·   " .. string.format("%.1f", sp.avgDeaths) .. " deaths" end
    b:Label(seg, cx + 52, cy - 50, C.subtext, 10)
end

----------------------------------------------------------------------
-- PROGRESSION chart (shared by Character Details = overall, Dungeon Details = per-dungeon).
--
-- The chart FORM follows the metric rather than forcing one shape on all six (see PROG_METRICS):
-- continuous metrics get a line with a rolling mean and a least-squares fit, discrete per-run counts
-- get bars on a zero baseline, and Time vs timer gets deviation bars either side of the timer itself.
-- Three views: Per run, Weekly (averaged by reset week), and By key level (one bar per keystone
-- level, which answers "how do I hold up as keys scale" - the question chronology can't).
--
-- Under the chart sits the stat strip: mean/median/IQR/SD/CV plus the regression slope, its R2, and
-- the metric's correlation with key level, each explaining itself on hover. The point is that a
-- jagged line should be readable as "noisy but flat" rather than as a crisis, and the numbers should
-- be there for anyone who wants to check that claim.
--
-- Reads scoring READ-ONLY (Store.Summary) - nothing on this page can change a score.
----------------------------------------------------------------------
-- Descriptive statistics over the series ALREADY ON SCREEN. Pure + deterministic: they read the
-- charted values only, never the scoring engine, so nothing here can move a grade. Sample (n-1)
-- standard deviation; quantiles interpolate between order statistics (the R type-7 / Excel default),
-- so a 4-point series still reports a sensible IQR.
local Stat = {}
function Stat.sorted(vals)
    local s = {}
    for i = 1, #vals do s[i] = vals[i] end
    table.sort(s)
    return s
end
function Stat.mean(vals)
    if #vals == 0 then return nil end
    local sum = 0
    for _, v in ipairs(vals) do sum = sum + v end
    return sum / #vals
end
function Stat.quantile(sorted, q)
    local n = #sorted
    if n == 0 then return nil end
    if n == 1 then return sorted[1] end
    local pos = (n - 1) * q + 1
    local lo = math.floor(pos)
    local frac = pos - lo
    if lo >= n then return sorted[n] end
    return sorted[lo] + (sorted[lo + 1] - sorted[lo]) * frac
end
function Stat.stdev(vals, mu)
    local n = #vals
    if n < 2 then return nil end
    mu = mu or Stat.mean(vals)
    local ss = 0
    for _, v in ipairs(vals) do ss = ss + (v - mu) ^ 2 end
    return math.sqrt(ss / (n - 1))
end
-- Ordinary least-squares fit of ys against xs. Returns slope, intercept, r2 (the share of the
-- variance the straight line explains: 0 = the trend says nothing, 1 = the points sit on the line).
-- nil when the sample is too small or every x is identical (a vertical fit has no slope).
function Stat.fit(xs, ys)
    local n = #xs
    if n < 3 then return nil end
    local mx, my = Stat.mean(xs), Stat.mean(ys)
    local sxx, sxy = 0, 0
    for i = 1, n do
        local dx = xs[i] - mx
        sxx = sxx + dx * dx
        sxy = sxy + dx * (ys[i] - my)
    end
    if sxx <= 0 then return nil end
    local slope = sxy / sxx
    local intercept = my - slope * mx
    local ssTot, ssRes = 0, 0
    for i = 1, n do
        ssTot = ssTot + (ys[i] - my) ^ 2
        ssRes = ssRes + (ys[i] - (slope * xs[i] + intercept)) ^ 2
    end
    local r2 = (ssTot > 0) and (1 - ssRes / ssTot) or nil
    return slope, intercept, r2
end
-- Pearson correlation of two paired series (-1..1). nil when either side never varies.
function Stat.pearson(xs, ys)
    local n = #xs
    if n < 3 then return nil end
    local mx, my = Stat.mean(xs), Stat.mean(ys)
    local sxy, sxx, syy = 0, 0, 0
    for i = 1, n do
        local dx, dy = xs[i] - mx, ys[i] - my
        sxy = sxy + dx * dy; sxx = sxx + dx * dx; syy = syy + dy * dy
    end
    if sxx <= 0 or syy <= 0 then return nil end
    return sxy / math.sqrt(sxx * syy)
end
-- TRAILING rolling mean (window w, partial at the start so the smoothed line spans the whole chart).
function Stat.rollmean(vals, w)
    local out, sum = {}, 0
    for i = 1, #vals do
        sum = sum + vals[i]
        if i > w then sum = sum - vals[i - w] end
        out[i] = sum / math.min(i, w)
    end
    return out
end

-- Each metric declares HOW it should be drawn, because one chart form does not fit all six:
--   line      = a continuous quantity worth smoothing + fitting (Score, DPS, HPS).
--   bars      = a discrete per-run count that belongs on a zero baseline (Key Level, Deaths) - a
--               line between integers implies in-between values that never existed.
--   deviation = a quantity with a natural PIVOT (Time vs timer pivots on the 100% line): bars grow
--               down for under-timer and up for over, so "how much room did I have" is the picture.
-- fmt = axis/tooltip value, dfmt = a signed CHANGE (regression slope), sfmt = an unsigned SPREAD
-- (standard deviation). Time is a fraction of the timer, so its spread/slope read in percentage
-- POINTS - "sigma 4pp" is meaningful where "sigma 0.04" is not.
local function fmtSignedShort(v)
    local a = math.abs(v)
    return (v < 0 and "-" or "+") .. Util.shortNum(a)
end
local PROG_METRICS = {
    { key = "score",  label = "Ledger Score",  icon = "award",       higherIsGood = true,  form = "line", bands = true,
      blurb = "Group-relative performance - comparable across every dungeon.", fmt = function(v) return string.format("%d", math.floor((v or 0) + 0.5)) end,
      dfmt = function(v) return string.format("%+.1f", v) end, sfmt = function(v) return string.format("%.1f", v) end },
    { key = "key",    label = "Key Level",     icon = "key",         higherIsGood = true,  form = "bars",
      blurb = "The keystone level completed each run.",                       fmt = function(v) return "+" .. string.format("%.10g", math.floor((v or 0) * 10 + 0.5) / 10) end,
      dfmt = function(v) return string.format("%+.2f", v) end, sfmt = function(v) return string.format("%.2f", v) end },
    { key = "time",   label = "Time vs timer", icon = "hourglass",   higherIsGood = false, form = "deviation",
      blurb = "Percent of the dungeon timer used - lower is faster.",         fmt = function(v) return string.format("%d%%", math.floor((v or 0) * 100 + 0.5)) end,
      dfmt = function(v) return string.format("%+.1fpp", v * 100) end, sfmt = function(v) return string.format("%.1fpp", v * 100) end },
    { key = "deaths", label = "Deaths",        icon = "skull",       higherIsGood = false, form = "bars",
      blurb = "Your deaths per run - lower is cleaner.",                      fmt = function(v) return string.format("%.1f", v or 0) end,
      dfmt = function(v) return string.format("%+.2f", v) end, sfmt = function(v) return string.format("%.2f", v) end },
    { key = "dps",    label = "DPS",           icon = "sword",       higherIsGood = true,  form = "line",
      blurb = "Your damage per second - reads best on a single dungeon.",     fmt = function(v) return Util.shortNum(v or 0) end,
      dfmt = fmtSignedShort, sfmt = function(v) return Util.shortNum(v) end },
    { key = "hps",    label = "HPS",           icon = "heartbeat",   higherIsGood = true,  form = "line",
      blurb = "Your healing per second - reads best on a single dungeon.",    fmt = function(v) return Util.shortNum(v or 0) end,
      dfmt = fmtSignedShort, sfmt = function(v) return Util.shortNum(v) end },
}
local PROG_BY_KEY, PROG_CHOICES = {}, {}
for _, m in ipairs(PROG_METRICS) do PROG_BY_KEY[m.key] = m; PROG_CHOICES[#PROG_CHOICES + 1] = { m.key, m.label } end

-- Date-range window for the chart (applied to the runs before charting).
local PROG_RANGES = {
    { "all", "All",           nil },
    { "2w",  "Last 2 weeks",  14 * 86400 },
    { "4w",  "Last 4 weeks",  28 * 86400 },
    { "8w",  "Last 8 weeks",  56 * 86400 },
    { "6m",  "Last 6 months", 182 * 86400 },
}
local PROG_RANGE_CHOICES, PROG_RANGE_SECS = {}, {}
for _, r in ipairs(PROG_RANGES) do PROG_RANGE_CHOICES[#PROG_RANGE_CHOICES + 1] = { r[1], r[2] }; PROG_RANGE_SECS[r[1]] = r[3] end

-- The selected metric's value for one run (nil = skip this run for this metric).
local function progValue(mkey, run)
    if mkey == "score" then
        local g = run.character and run.character.guid
        local St = ML.Scoring and ML.Scoring.Store
        local ms = g and St and St.Summary and St.Summary(run)[g]
        return ms and ms.overall
    elseif mkey == "key" then
        return (type(run.level) == "number") and run.level or nil
    elseif mkey == "time" then
        if run.status == STATUS.ABANDONED then return nil end
        if type(run.duration) == "number" and type(run.timeLimit) == "number" and run.timeLimit > 0 then
            return run.duration / run.timeLimit
        end
        return nil
    elseif mkey == "deaths" then
        local d = History.PlayerDeaths(run)
        return (type(d) == "number") and d or nil
    elseif mkey == "dps" then
        return run.playerStats and run.playerStats.dps
    elseif mkey == "hps" then
        return run.playerStats and run.playerStats.hps
    end
end

local progChart   -- managed frame for the line chart: real diagonal lines need CreateLine (the Builder only draws rects)
local function renderProgression(b, C, x, y, w, win, runsNewestFirst, opts)
    opts = opts or {}
    local mkey = PROG_BY_KEY[view.progMetric] and view.progMetric or "score"
    local mdef = PROG_BY_KEY[mkey]
    local vmode = view.progView or "run"
    local weekly, byLevel = (vmode == "week"), (vmode == "level")
    -- The chart FORM comes from the metric, except "By key level" which is always a bar chart (its x
    -- axis is the keystone level, not time, so a connecting line would imply a progression it isn't).
    local form = byLevel and "bars" or (mdef.form or "line")
    local unit = byLevel and "level" or (weekly and "week" or "run")

    -- Observed key-level span (from this character's runs) -> the choices for the key-level filter.
    local kLo, kHi
    for _, r in ipairs(runsNewestFirst) do
        local lv = (type(r.level) == "number") and r.level or nil
        if lv then kLo = math.min(kLo or lv, lv); kHi = math.max(kHi or lv, lv) end
    end
    local keyMinChoices, keyMaxChoices = { { "any", "Any" } }, { { "any", "Any" } }
    if kLo and kHi then
        for lv = kLo, kHi do
            keyMinChoices[#keyMinChoices + 1] = { tostring(lv), "+" .. lv }
            keyMaxChoices[#keyMaxChoices + 1] = { tostring(lv), "+" .. lv }
        end
    end

    if not opts.noSection then y = b:Section("PROGRESSION", x, y); y = y - 28 end
    local nx = scopeControl(b, C, x, y, "Metric", 150, "Metric",
        "Which metric to chart across your runs. Ledger Score is comparable across dungeons; Key / Time / DPS / HPS read best on a single dungeon.",
        PROG_CHOICES, function() return view.progMetric or "score" end,
        function(v) view.progMetric = v; if win then win:Refresh() end end)
    nx = scopeControl(b, C, nx, y, "View", 130, "View",
        "Per run = one point per run (noisy, but every run is visible).  Weekly = one point per reset "
        .. "week, averaged.  By key level = one bar per keystone level, so you can see how the metric "
        .. "holds up as keys scale instead of reading it chronologically.",
        { { "run", "Per run" }, { "week", "Weekly" }, { "level", "By key level" } },
        function() return view.progView or "run" end,
        function(v) view.progView = v; if win then win:Refresh() end end)
    scopeControl(b, C, nx, y, "Date range", 140, "Date range",
        "Limit the chart to a recent time window.",
        PROG_RANGE_CHOICES, function() return view.progRange or "all" end,
        function(v) view.progRange = v; if win then win:Refresh() end end)
    y = y - 34

    -- Second control row: key-level window (Min <= key <= Max). Choices come from this character's own runs.
    local kx = scopeControl(b, C, x, y, "Key min", 110, "Lowest key level",
        "Only include runs at or above this key level.",
        keyMinChoices, function() return view.progKeyMin or "any" end,
        function(v) view.progKeyMin = (v ~= "any") and v or nil; if win then win:Refresh() end end)
    scopeControl(b, C, kx, y, "Key max", 110, "Highest key level",
        "Only include runs at or below this key level.",
        keyMaxChoices, function() return view.progKeyMax or "any" end,
        function(v) view.progKeyMax = (v ~= "any") and v or nil; if win then win:Refresh() end end)
    y = y - 40

    -- Divider between the configuration selectors and the metric banner + content below.
    b:Box(x, y + 6, w, 1, 0.55, 2, C.border)

    -- Metric banner: clearly names the selected metric with its icon, what it measures, and its polarity.
    do
        b:Tex(x, y - 8, 30, 30, mdef.icon or "activity", nil, C.accent)
        b:Label(mdef.label, x + 42, y - 6, C.text, 19)
        if mdef.blurb then b:Label(mdef.blurb, x + 42, y - 30, C.subtext, 11) end
        local polTxt = mdef.higherIsGood and "Higher is better" or "Lower is better"
        local polCol = { 0.55, 0.62, 0.78 }
        local pillW = math.floor(22 + 6.4 * #polTxt)
        local px = x + w - pillW
        b:Box(px, y - 6, pillW, 22, 0.16, 1, polCol)
        b:Box(px, y - 6, 3, 22, 0.95, 2, polCol)
        b:Label(polTxt, px + 12, y - 10, polCol, 11)
    end
    y = y - 50

    -- chronological (oldest -> newest); FilterRuns returns newest-first.
    local chron = {}
    for i = #runsNewestFirst, 1, -1 do chron[#chron + 1] = runsNewestFirst[i] end
    local rsecs = PROG_RANGE_SECS[view.progRange or "all"]
    if rsecs then
        local cutoff = time() - rsecs
        local f = {}
        for _, r in ipairs(chron) do if (r.completedAt or r.startedAt or 0) >= cutoff then f[#f + 1] = r end end
        chron = f
    end
    local kmin, kmax = tonumber(view.progKeyMin), tonumber(view.progKeyMax)
    if kmin and kmax and kmin > kmax then kmin, kmax = kmax, kmin end   -- tolerate a crossed pair
    if kmin or kmax then
        local f = {}
        for _, r in ipairs(chron) do
            local lv = (type(r.level) == "number") and r.level or nil
            if lv and (not kmin or lv >= kmin) and (not kmax or lv <= kmax) then f[#f + 1] = r end
        end
        chron = f
    end

    local pts = {}
    if byLevel then
        -- One bar per keystone level: the metric AVERAGED over every run at that level, with the
        -- sample size and timed rate carried along (a +10 average built from one run is not the same
        -- claim as one built from nine, and the tooltip has to say so).
        local buckets, order = {}, {}
        for _, r in ipairs(chron) do
            local lv = (type(r.level) == "number") and r.level or nil
            local v = lv and progValue(mkey, r)
            if lv and type(v) == "number" then
                local bk = buckets[lv]
                if not bk then bk = { n = 0, timed = 0, vals = {} }; buckets[lv] = bk; order[#order + 1] = lv end
                bk.n = bk.n + 1; bk.vals[#bk.vals + 1] = v
                if r.status == STATUS.TIMED then bk.timed = bk.timed + 1 end
            end
        end
        table.sort(order)
        for _, lv in ipairs(order) do
            local bk = buckets[lv]
            local sv = Stat.sorted(bk.vals)
            local avg = Stat.mean(bk.vals)
            pts[#pts + 1] = { value = avg, x = lv, xlabel = "+" .. lv, n = bk.n, timedPct = bk.timed / bk.n,
                tip = { title = "Keystone +" .. lv,
                    lines = { { left = "Runs", right = tostring(bk.n) },
                              { left = "Timed", right = string.format("%d of %d", bk.timed, bk.n),
                                rcolor = (bk.timed == bk.n) and "accent" or nil },
                              { sep = true },
                              { left = "Mean " .. mdef.label, right = mdef.fmt(avg), rcolor = "accent" },
                              { left = "Median", right = mdef.fmt(Stat.quantile(sv, 0.5)) },
                              { left = "Range", right = mdef.fmt(sv[1]) .. "  ..  " .. mdef.fmt(sv[#sv]) },
                              { blank = true },
                              { text = (bk.n < 3) and "Small sample - treat this bar as provisional."
                                    or "Averaged over the runs in scope.", color = "subtext" } } } }
        end
    elseif weekly then
        local weekStart = (History.WeekStart and History.WeekStart()) or (time() - 7 * 86400)
        local WEEK = 7 * 86400
        local buckets, order = {}, {}
        for _, r in ipairs(chron) do
            local v = progValue(mkey, r)
            if type(v) == "number" then
                local t = r.completedAt or r.startedAt or 0
                local wi = math.max(0, math.ceil((weekStart - t) / WEEK))   -- 0 = this week, 1 = last, ...
                local bk = buckets[wi]
                if not bk then bk = { sum = 0, n = 0 }; buckets[wi] = bk; order[#order + 1] = wi end
                bk.sum = bk.sum + v; bk.n = bk.n + 1
            end
        end
        table.sort(order, function(a, bb) return a > bb end)   -- oldest first
        for _, wi in ipairs(order) do
            local bk = buckets[wi]
            local avg = bk.sum / bk.n
            pts[#pts + 1] = { value = avg, tip = { title = (wi == 0 and "This week" or (wi .. " week" .. (wi == 1 and "" or "s") .. " ago")),
                lines = { { left = mdef.label, right = mdef.fmt(avg), rcolor = "accent" }, { left = "Runs", right = tostring(bk.n) } } } }
        end
    else
        for _, r in ipairs(chron) do
            local v = progValue(mkey, r)
            if type(v) == "number" then pts[#pts + 1] = { value = v, run = r } end
        end
        if #pts > 40 then local t = {}; for i = #pts - 39, #pts do t[#t + 1] = pts[i] end; pts = t end
        for _, p in ipairs(pts) do
            local r = p.run
            local g = r.character and r.character.guid
            local St = ML.Scoring and ML.Scoring.Store
            local ms = g and St and St.Summary and St.Summary(r)[g]
            local lines = {}
            if opts.showDungeon and r.dungeonName then lines[#lines + 1] = { left = "Dungeon", right = r.dungeonName } end
            lines[#lines + 1] = { left = "Key", right = r.level and ("+" .. r.level) or "-", rcolor = (r.status == STATUS.TIMED) and "accent" or nil }
            lines[#lines + 1] = { left = mdef.label, right = mdef.fmt(p.value), rcolor = "accent" }
            if ms and ms.grade then lines[#lines + 1] = { left = "Grade", right = ms.grade } end
            lines[#lines + 1] = { left = "When", right = Util.dateShort(r.completedAt or r.startedAt) }
            p.tip = { title = (r.status == STATUS.TIMED and "Timed key") or (r.status == STATUS.DEPLETED and "Depleted") or "Run", lines = lines }
        end
    end

    local minPts = (vmode == "run") and 3 or 2
    if #pts < minPts then
        b:Label("Not enough data yet to chart a trend (need " .. minPts .. "+ " .. unit .. "s in scope).",
            x + 2, y - 2, C.subtext, 12)
        return y - 26
    end

    local n = #pts
    local vals = {}
    for i, p in ipairs(pts) do vals[i] = p.value end
    local svals = Stat.sorted(vals)
    local minV, maxV = svals[1], svals[n]
    local avg = Stat.mean(vals)
    local median = Stat.quantile(svals, 0.5)
    local p25, p75 = Stat.quantile(svals, 0.25), Stat.quantile(svals, 0.75)
    local sd = Stat.stdev(vals, avg)
    local cv = (sd and avg and math.abs(avg) > 1e-9) and (sd / math.abs(avg)) or nil

    -- Least-squares fit. x is the chronological INDEX in the per-run/weekly views and the keystone
    -- LEVEL in the by-level view, so the slope reads "per run" / "per week" / "per +1 key" to match.
    local xs = {}
    for i, p in ipairs(pts) do xs[i] = p.x or i end
    local slope, intercept, r2 = Stat.fit(xs, vals)

    -- How the metric tracks KEY LEVEL (per-run view only). A strongly negative r on Ledger Score says
    -- the wheels come off as keys scale - something a chronological line can never show, because your
    -- key levels bounce around from day to day.
    local kxs, kys = {}, {}
    for _, p in ipairs(pts) do
        if p.run and type(p.run.level) == "number" then kxs[#kxs + 1] = p.run.level; kys[#kys + 1] = p.value end
    end
    local rKey = Stat.pearson(kxs, kys)

    -- Timed rate across everything charted (context for every metric, not just Time vs timer).
    local timedN, runN = 0, 0
    for _, p in ipairs(pts) do
        if p.run then
            runN = runN + 1
            if p.run.status == STATUS.TIMED then timedN = timedN + 1 end
        elseif p.timedPct and p.n then
            runN = runN + p.n; timedN = timedN + p.timedPct * p.n
        end
    end
    local timedPct = (runN > 0) and (timedN / runN) or nil

    local goodCol, badCol, neutralCol = { 0.42, 0.82, 0.45 }, { 0.90, 0.42, 0.42 }, { 0.55, 0.58, 0.66 }
    local amberCol, fitCol, rollCol = { 0.95, 0.72, 0.30 }, { 1, 0.82, 0.28 }, { 0.62, 0.72, 1 }

    -- Kept for the LATEST tooltip: the plain-language version of the trend.
    local third = math.max(1, math.floor(n / 3))
    local es, rs = 0, 0
    for i = 1, third do es = es + pts[i].value end
    for i = n - third + 1, n do rs = rs + pts[i].value end
    local earlyAvg, recentAvg = es / third, rs / third

    -- TREND comes from the fitted line, not from comparing two noisy thirds: "Steady" now means the
    -- fit is flat OR too scattered to believe (low r2), rather than two small means happening to land
    -- close together. Judged on the total change the fit predicts across the whole window.
    local spanV = (maxV - minV > 0) and (maxV - minV) or 1
    local fitDelta = slope and (slope * (xs[n] - xs[1])) or 0
    local trendTxt, trendCol
    if not slope or math.abs(fitDelta) < spanV * 0.10 or (r2 or 0) < 0.08 then
        trendTxt, trendCol = "Steady", neutralCol
    elseif (fitDelta > 0) == mdef.higherIsGood then trendTxt, trendCol = "Improving", goodCol
    else trendTxt, trendCol = "Regressing", badCol end

    -- Smoothing window, scaled to the sample: too wide on a short series and the mean says nothing,
    -- too narrow and it just retraces the raw line. nil = not enough points to smooth at all.
    local rollW = (n >= 12) and 5 or ((n >= 7) and 3 or nil)

    -- Hero cards. MIN/MAX/AVERAGE were three views of the same middle; these four answer four
    -- different questions: where am I now, what is my typical result, what have I proven I can do,
    -- and how repeatable am I. The full five-number summary lives in the MEDIAN card's tooltip and
    -- the stat strip under the chart.
    do
        local gold, cool = { 1, 0.82, 0.28 }, { 0.55, 0.62, 0.78 }
        local bestIsMax = mdef.higherIsGood
        local bestV, worstV = bestIsMax and maxV or minV, bestIsMax and minV or maxV
        local gap, ch, isz = 12, 88, 34
        local cw = math.floor((w - 3 * gap) / 4)
        heroStatCard(b, C, x, y, cw, ch, {
            label = "LATEST", value = mdef.fmt(pts[n].value), accent = trendCol, sub = trendTxt,
            icon = "activity", iconSize = isz,
            tipData = { title = "Latest " .. unit,
                lines = { { left = mdef.label, right = mdef.fmt(pts[n].value), rcolor = "accent" },
                          { left = "Trend", right = trendTxt, rcolor = trendCol },
                          { sep = true },
                          { left = "First third avg", right = mdef.fmt(earlyAvg) },
                          { left = "Last third avg", right = mdef.fmt(recentAvg) },
                          { left = "Fit predicts", right = slope and (mdef.dfmt(fitDelta) .. " across " .. n .. " " .. unit .. "s") or DASH },
                          { blank = true },
                          { text = "The trend is read off the fitted line, and stays Steady unless the fit "
                                .. "is both large enough and consistent enough to mean something.", color = "subtext" } } } })
        heroStatCard(b, C, x + (cw + gap), y, cw, ch, {
            label = "MEDIAN", value = mdef.fmt(median), accent = cool, icon = "minus", iconSize = isz,
            sub = (p25 and p75) and ("IQR " .. mdef.fmt(p25) .. " - " .. mdef.fmt(p75)) or nil,
            tipData = { title = "Typical " .. unit,
                lines = { { left = "Median (p50)", right = mdef.fmt(median), rcolor = "accent" },
                          { left = "Mean", right = mdef.fmt(avg) },
                          { sep = true },
                          { left = "Max", right = mdef.fmt(maxV) },
                          { left = "Upper quartile (p75)", right = mdef.fmt(p75) },
                          { left = "Lower quartile (p25)", right = mdef.fmt(p25) },
                          { left = "Min", right = mdef.fmt(minV) },
                          { blank = true },
                          { text = "The median ignores one disaster or one hero run, so it describes your "
                                .. "normal better than the mean. Half your results sit inside the IQR band "
                                .. "shaded on the chart.", color = "subtext" } } } })
        heroStatCard(b, C, x + 2 * (cw + gap), y, cw, ch, {
            label = "BEST", value = mdef.fmt(bestV), accent = gold, icon = bestIsMax and "arrow-up" or "arrow-down",
            iconSize = isz, sub = "worst " .. mdef.fmt(worstV),
            tipData = { title = "Best " .. unit,
                lines = { { left = "Best", right = mdef.fmt(bestV), rcolor = "accent" },
                          { left = "Worst", right = mdef.fmt(worstV) },
                          { left = "Spread", right = mdef.sfmt(maxV - minV) },
                          { blank = true },
                          { text = mdef.higherIsGood and "Higher is better for this metric."
                                or "Lower is better for this metric.", color = "subtext" } } } })
        heroStatCard(b, C, x + 3 * (cw + gap), y, cw, ch, {
            label = "CONSISTENCY", value = sd and mdef.sfmt(sd) or DASH, accent = { 0.95, 0.76, 0.32 },
            icon = "activity", iconSize = isz,
            sub = cv and string.format("SD  -  CV %.0f%%", cv * 100) or "SD",
            tipData = { title = "How repeatable you are",
                lines = { { left = "Standard deviation", right = sd and mdef.sfmt(sd) or DASH, rcolor = "accent" },
                          { left = "Coefficient of variation", right = cv and string.format("%.1f%%", cv * 100) or DASH },
                          { left = "Sample", right = n .. " " .. unit .. "s" },
                          { blank = true },
                          { text = "Standard deviation is the typical distance from your own average. CV is "
                                .. "that same spread as a percentage of the average, so it compares across "
                                .. "metrics and gear levels: under 10% is metronomic, over 30% is streaky.", color = "subtext" } } } })
    end
    y = y - 104

    -- Chart card: dark base + 1px border + accent top bar.
    local axisW, chartH = 54, 124
    local plotX, plotW = x + axisW, w - axisW - 6
    local topY, botY = y, y - chartH
    b:Box(plotX - 1, topY + 1, plotW + 2, chartH + 2, 0.9, 0, C.border)
    b:Box(plotX, topY, plotW, chartH, 1, 1, { 0.055, 0.06, 0.085 })
    b:Box(plotX, topY, plotW, 2, 1, 2, C.accent)

    -- AXIS WINDOW per form. Bars sit on a zero baseline so their heights are honest; a deviation
    -- chart pivots on its reference (the dungeon timer) with symmetric room either side; a line gets
    -- a padded window so ordinary variance stops filling the plot - clamping exactly to min..max, as
    -- this chart used to, turns a 4-point wobble into a cliff. Ledger Score additionally stays inside
    -- 0..100: that scale means something and shouldn't be reinvented per render.
    local base, mn, mx
    if form == "bars" then
        base = math.min(0, minV)
        mn = base
        mx = maxV + math.max((maxV - base) * 0.15, 0.5)
    elseif form == "deviation" then
        base = 1.0
        local dev = math.max(math.abs(maxV - base), math.abs(base - minV), 0.04)
        mn, mx = base - dev * 1.25, base + dev * 1.25
    else
        local pad = (maxV - minV) * 0.12
        if pad <= 0 then pad = math.max(1, math.abs(maxV) * 0.05) end
        mn, mx = minV - pad, maxV + pad
        if mkey == "score" then mn, mx = math.max(0, mn), math.min(100, mx) end
    end
    local span = (mx - mn > 0) and (mx - mn) or 1

    local padL, padR, padV = 16, 16, 14
    local usableW = plotW - padL - padR
    local step = (n > 1) and (usableW / (n - 1)) or 0
    local slotW = usableW / n
    local function localY(v)                                     -- up from cf bottom; clamped so a
        local t = (v - mn) / span                                 -- clipped fit line can't escape the card
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        return padV + t * (chartH - 2 * padV)
    end
    -- A line spans edge to edge (one vertex per point); bars sit centred in their own slot.
    local function localX(i)
        if form == "line" then return padL + (i - 1) * step end
        return padL + (i - 0.5) * slotW
    end
    local function contentY(v) return botY + localY(v) end        -- cf bottom == botY

    -- REFERENCE LINES carry meaning wherever the metric has any. Ledger Score gets its GRADE
    -- boundaries (crossing from B into A is the event worth seeing, not an arbitrary mid-point);
    -- Time vs timer gets the chest thresholds it is actually judged against; everything else falls
    -- back to min / mid / max.
    local MAJOR_GRADES = { S = true, A = true, B = true, C = true, D = true }
    local refs = {}
    local sCfg = ML.Scoring and ML.Scoring.Config
    if mdef.bands and sCfg and sCfg.grades then
        for _, g in ipairs(sCfg.grades) do
            if MAJOR_GRADES[g.grade] and g.min > mn and g.min < mx then
                refs[#refs + 1] = { v = g.min, label = g.grade .. " " .. g.min, strong = true }
            end
        end
    elseif form == "deviation" then
        for _, t in ipairs({ { 0.6, "+3 chest" }, { 0.8, "+2 chest" }, { 1.0, "timer" } }) do
            if t[1] > mn and t[1] < mx then refs[#refs + 1] = { v = t[1], label = t[2], strong = (t[1] == base) } end
        end
    end
    if #refs == 0 then
        refs = { { v = mx }, { v = (mx + mn) / 2 }, { v = mn } }
        if form == "bars" and base == 0 then refs[#refs] = { v = 0, label = "0", strong = true } end
    end
    for _, gl in ipairs(refs) do
        local gy = contentY(gl.v)
        b:Box(plotX + 6, gy, plotW - 12, 1, gl.strong and 0.34 or 0.13, 2, gl.strong and C.accent or C.border)
        b:Label(gl.label or mdef.fmt(gl.v), x, gy + 5, C.subtext, 10)
    end

    -- IQR band: the middle half of every result in scope, shaded behind the series. A thin band is a
    -- repeatable player; a tall one is the swing the raw line is already fighting you with.
    if p25 and p75 and p75 > p25 then
        local yHi, yLo = contentY(p75), contentY(p25)
        b:Box(plotX + 6, yHi, plotW - 12, math.max(1, yHi - yLo), 0.10, 1, C.accent)
    end

    -- Average reference line (dashed amber) + label.
    local avgCol = { 0.95, 0.76, 0.32 }
    local avgY = contentY(avg)
    local dashN = 24
    local dstep = (plotW - 12) / dashN
    for k = 0, dashN - 1 do b:Box(plotX + 6 + k * dstep, avgY, dstep * 0.55, 1, 0.85, 3, avgCol) end

    -- Diagonal geometry (the raw line, the rolling mean, the fit) needs real CreateLine textures, so
    -- it lives on a managed frame that survives the Builder's per-render reset; hover regions sit on
    -- the same frame so they stay above everything drawn.
    local cf = progChart
    if not cf then cf = CreateFrame("Frame", nil, b.content); cf.segs, cf.glow, cf.dots, cf.hits = {}, {}, {}, {}; progChart = cf end
    cf.roll = cf.roll or {}     -- added later than the frame; a pooled frame from an older render lacks it
    if cf:GetParent() ~= b.content then cf:SetParent(b.content) end
    cf:ClearAllPoints(); cf:SetPoint("TOPLEFT", b.content, "TOPLEFT", plotX, topY); cf:SetSize(math.max(1, plotW), chartH); cf:Show()
    if b.Transient then b:Transient(cf) end

    -- Average label drawn ON the chart frame (OVERLAY) so the line never clips it, sitting above the line.
    cf.avgLabel = cf.avgLabel or cf:CreateFontString(nil, "OVERLAY")
    cf.avgLabel:SetFont(b.theme.FONT or _G.STANDARD_TEXT_FONT, 10)
    cf.avgLabel:SetText("avg " .. mdef.fmt(avg)); cf.avgLabel:SetTextColor(avgCol[1], avgCol[2], avgCol[3])
    local alY = localY(avg)
    cf.avgLabel:ClearAllPoints()
    cf.avgLabel:SetPoint("BOTTOMLEFT", cf, plotW - 78, (alY > chartH * 0.72) and (alY - 13) or (alY + 8))
    cf.avgLabel:Show()

    local function hideFrom(t, from) for i = from, #t do if t[i] then t[i]:Hide() end end end

    local bestI = 1
    for i = 2, n do
        local better = mdef.higherIsGood and (pts[i].value > pts[bestI].value) or ((not mdef.higherIsGood) and pts[i].value < pts[bestI].value)
        if better then bestI = i end
    end

    -- BARS. Their color carries the OUTCOME, not just the height: timed vs depleted for a run, the
    -- timed rate for a key level, and for Deaths / Time vs timer the good-or-bad side of the metric.
    local function barColor(p)
        if byLevel then
            local t = p.timedPct or 0
            if t >= 0.999 then return goodCol elseif t >= 0.5 then return amberCol else return badCol end
        end
        if mkey == "deaths" then
            if p.value <= 0 then return goodCol elseif p.value <= 2 then return amberCol else return badCol end
        end
        if form == "deviation" then return (p.value <= base) and goodCol or badCol end
        if p.run then
            if p.run.status == STATUS.TIMED then return goodCol
            elseif p.run.status == STATUS.DEPLETED then return amberCol end
        end
        return neutralCol
    end
    if form ~= "line" then
        local barW = math.max(3, math.min(30, slotW * 0.62))
        local baseY = contentY(base)
        for i, p in ipairs(pts) do
            local cx, vy = plotX + localX(i), contentY(p.value)
            -- A value sitting exactly on the baseline (a clean 0-death run) still draws a hairline,
            -- so "nothing happened" reads as a deliberate result instead of a gap.
            b:Box(cx - barW / 2, math.max(vy, baseY), barW, math.max(1, math.abs(vy - baseY)), 0.92, 2, barColor(p))
        end
    end

    -- RAW LINE: per-segment colored improve/regress with a soft glow (line metrics only).
    if form == "line" then
        for i = 1, n - 1 do
            local x1, y1, x2, y2 = localX(i), localY(pts[i].value), localX(i + 1), localY(pts[i + 1].value)
            local dd = pts[i + 1].value - pts[i].value
            local col = neutralCol
            if math.abs(dd) > 1e-9 then col = ((dd > 0) == mdef.higherIsGood) and goodCol or badCol end
            local alpha = rollW and 0.45 or 1                  -- dim the raw line when a mean rides on top
            local gl = cf.glow[i] or cf:CreateLine(); cf.glow[i] = gl
            gl:SetThickness(6); gl:SetColorTexture(col[1], col[2], col[3], 0.18 * alpha)
            gl:SetStartPoint("BOTTOMLEFT", cf, x1, y1); gl:SetEndPoint("BOTTOMLEFT", cf, x2, y2); gl:Show()
            local ln = cf.segs[i] or cf:CreateLine(); cf.segs[i] = ln
            ln:SetThickness(2.5); ln:SetColorTexture(col[1], col[2], col[3], alpha)
            ln:SetStartPoint("BOTTOMLEFT", cf, x1, y1); ln:SetEndPoint("BOTTOMLEFT", cf, x2, y2); ln:Show()
        end
        hideFrom(cf.segs, n); hideFrom(cf.glow, n)
    else
        hideFrom(cf.segs, 1); hideFrom(cf.glow, 1)
    end

    -- ROLLING MEAN: the signal under the scatter. Trailing window, so each point is "my average over
    -- the last N" - the same smoothing you do by eye, done consistently.
    if form == "line" and rollW then
        local rm = Stat.rollmean(vals, rollW)
        for i = 1, n - 1 do
            local ln = cf.roll[i] or cf:CreateLine(); cf.roll[i] = ln
            ln:SetThickness(3); ln:SetColorTexture(rollCol[1], rollCol[2], rollCol[3], 0.95)
            ln:SetStartPoint("BOTTOMLEFT", cf, localX(i), localY(rm[i]))
            ln:SetEndPoint("BOTTOMLEFT", cf, localX(i + 1), localY(rm[i + 1]))
            ln:Show()
        end
        hideFrom(cf.roll, n)
    else
        hideFrom(cf.roll, 1)
    end

    -- FITTED TREND, drawn only when the fit explains enough of the variance to be worth believing.
    local fitShown = false
    if slope and (r2 or 0) >= 0.05 then
        local ln = cf.fit or cf:CreateLine(); cf.fit = ln
        ln:SetThickness(2); ln:SetColorTexture(fitCol[1], fitCol[2], fitCol[3], 0.55)
        ln:SetStartPoint("BOTTOMLEFT", cf, localX(1), localY(intercept + slope * xs[1]))
        ln:SetEndPoint("BOTTOMLEFT", cf, localX(n), localY(intercept + slope * xs[n]))
        ln:Show()
        fitShown = true
    elseif cf.fit then cf.fit:Hide() end

    for i = 1, n do
        local lx, ly = localX(i), localY(pts[i].value)
        local dot = cf.dots[i]
        if form == "line" then                        -- bars are their own marker; dots would just add noise
            dot = dot or cf:CreateTexture(nil, "OVERLAY"); cf.dots[i] = dot
            if i == bestI then dot:SetColorTexture(1, 0.82, 0.28, 1); dot:SetSize(8, 8)
            else dot:SetColorTexture(0.93, 0.95, 0.99, 1); dot:SetSize(5, 5) end
            dot:ClearAllPoints(); dot:SetPoint("CENTER", cf, "BOTTOMLEFT", lx, ly); dot:Show()
        elseif dot then dot:Hide() end

        local hit = cf.hits[i]
        if not hit then
            hit = CreateFrame("Button", nil, cf); cf.hits[i] = hit
            hit.hl = hit:CreateTexture(nil, "HIGHLIGHT"); hit.hl:SetAllPoints(); hit.hl:SetColorTexture(1, 1, 1, 0.05)
            hit:SetScript("OnEnter", function(s) if b.theme._showTip then b.theme:_showTip(s) end end)
            hit:SetScript("OnLeave", function() if _G.GameTooltip_Hide then GameTooltip_Hide() end end)
        end
        if pts[i].tip and b.theme.SetTipData then b.theme:SetTipData(hit, pts[i].tip) end
        hit:SetSize(math.max(12, (form == "line") and step or slotW), chartH)
        hit:ClearAllPoints(); hit:SetPoint("BOTTOM", cf, "BOTTOMLEFT", lx, 0); hit:Show()
    end
    for i = n + 1, #cf.dots do if cf.dots[i] then cf.dots[i]:Hide() end; if cf.hits[i] then cf.hits[i]:Hide() end end

    -- X AXIS. By key level labels every bar (with its sample size, because a +10 average off one run
    -- is not the same claim as one off nine); the chronological views anchor first / middle / last in
    -- time, which the chart never used to say at all.
    local axisBottom = botY - 18            -- clear of the x-axis label row
    if byLevel then
        for i, p in ipairs(pts) do
            local lx = plotX + localX(i)
            b:Label(p.xlabel or "", lx - 9, botY - 3, C.subtext, 10)
            if p.n then b:Label("n=" .. p.n, lx - 11, botY - 15, C.subtext, 9) end
        end
        axisBottom = botY - 30              -- two label rows: the level, then its sample size
    elseif not weekly then
        local function dateAt(i) local r = pts[i].run; return r and Util.dateShort(r.completedAt or r.startedAt) or nil end
        local dFirst, dMid, dLast = dateAt(1), dateAt(math.floor((n + 1) / 2)), dateAt(n)
        if dFirst then b:Label(dFirst, plotX + padL - 8, botY - 3, C.subtext, 10) end
        if dMid and n >= 6 then b:Label(dMid, plotX + plotW / 2 - 24, botY - 3, C.subtext, 10) end
        if dLast then b:Label(dLast, plotX + plotW - 92, botY - 3, C.subtext, 10) end
    end

    -- Legend for whatever overlays are actually on screen (never a key to things you can't see).
    if form == "line" and (rollW or fitShown) then
        local legX, legY = plotX + padL, axisBottom - 2
        local function legendItem(col, text)
            b:Box(legX, legY, 14, 3, 0.95, 2, col)
            local lb = b:Label(text, legX + 18, legY + 4, C.subtext, 9)
            legX = legX + 18 + (lb:GetStringWidth() or 40) + 14
        end
        legendItem({ 0.93, 0.95, 0.99 }, "each " .. unit)
        if rollW then legendItem(rollCol, rollW .. "-" .. unit .. " mean") end
        if fitShown then legendItem(fitCol, "fit") end
        axisBottom = legY - 14
    end

    -- STAT STRIP: the numbers behind the picture, each explaining itself on hover. The chart says
    -- what happened; these say how much of it is signal and how much is noise.
    local chips = {}
    local function chip(label, value, col, tipTitle, tipBody)
        if value ~= nil then chips[#chips + 1] = { label = label, value = value, col = col, tt = tipTitle, tb = tipBody } end
    end
    chip("n", n .. " " .. unit .. "s", nil, "Sample size",
        "How many " .. unit .. "s this chart is built from. Small samples swing hard on one good or bad "
        .. "night - under about 8, read everything here as provisional.")
    chip("mean", mdef.fmt(avg), nil, "Mean",
        "The plain average. Pulled around by outliers, which is exactly why the median sits next to it.")
    chip("median", mdef.fmt(median), nil, "Median",
        "The middle result: half your " .. unit .. "s are better, half worse. When the mean and median "
        .. "disagree, a few extreme " .. unit .. "s are doing the talking.")
    chip("range", mdef.fmt(minV) .. " - " .. mdef.fmt(maxV), nil, "Range", "Your worst and best result in scope.")
    if p25 and p75 then
        chip("IQR", mdef.fmt(p25) .. " - " .. mdef.fmt(p75), nil, "Interquartile range",
            "The middle half of your results, shaded on the chart. Ignores the top and bottom quarter, "
            .. "so it shows your normal band without the flukes at either end.")
    end
    if sd then
        chip("SD", mdef.sfmt(sd), nil, "Standard deviation",
            "The typical distance between a single " .. unit .. " and your own average.")
    end
    if cv then
        chip("CV", string.format("%.0f%%", cv * 100), nil, "Coefficient of variation",
            "Standard deviation as a percentage of the mean, so it compares across metrics and gear "
            .. "levels. Under 10% is metronomic; over 30% is streaky.")
    end
    if slope then
        chip("slope", mdef.dfmt(slope) .. " / " .. unit, trendCol, "Trend slope",
            "The straight line that best fits your " .. unit .. "s, expressed as change per " .. unit
            .. ". Across all " .. n .. " that adds up to " .. mdef.dfmt(fitDelta) .. ".")
    end
    if r2 then
        chip("R2", string.format("%.2f", r2), nil, "Fit quality (R squared)",
            "How much of the movement the trend line actually explains, from 0 to 1. Near 0 means the "
            .. "slope is noise and you should ignore it; above about 0.3 the trend is real. This is why "
            .. "a big-looking slope can still read as Steady.")
    end
    if rKey then
        local rkCol
        if math.abs(rKey) >= 0.4 then
            local hurts = mdef.higherIsGood and (rKey < 0) or ((not mdef.higherIsGood) and (rKey > 0))
            rkCol = hurts and badCol or goodCol
        end
        chip("r vs key", string.format("%+.2f", rKey), rkCol, "Correlation with key level",
            "How this metric moves as keystone level rises, from -1 to +1. 0 means key level makes no "
            .. "difference to it. Anything past about 0.4 either way is a real relationship - and for "
            .. (mdef.higherIsGood and "this metric a negative one means you fall off as keys get harder."
                or "this metric a positive one means it gets worse as keys get harder."))
    end
    if timedPct then
        chip("timed", string.format("%.0f%%", timedPct * 100), nil, "Timed rate",
            "The share of the charted runs that beat the dungeon timer.")
    end

    local chipH, chipGap = 22, 8
    local chipX, chipY = x, axisBottom - 8
    for _, c in ipairs(chips) do
        local cwid = math.floor(20 + 6.1 * #(c.label .. "  " .. c.value))
        if chipX + cwid > x + w and chipX > x then chipX = x; chipY = chipY - (chipH + 6) end
        local col = c.col or C.border
        b:Box(chipX, chipY, cwid, chipH, 0.16, 1, col)
        b:Box(chipX, chipY, 2, chipH, 0.9, 2, col)
        b:Label(c.label .. "  |cfff2f4f8" .. c.value .. "|r", chipX + 9, chipY - 6, C.subtext, 11)
        -- SetTipData (not the Hit tipTitle/tipBody path): b:Hit pools its frames, and a pooled frame
        -- that once carried rich lines would otherwise keep showing them behind a plain tip.
        local hit = b:Hit(chipX, chipY, cwid, chipH)
        if b.theme.SetTipData then
            b.theme:SetTipData(hit, { title = c.tt, minWidth = 300,
                lines = { { left = c.label, right = c.value, rcolor = "accent" },
                          { blank = true }, { text = c.tb, color = "subtext" } } })
        end
        chipX = chipX + cwid + chipGap
    end

    return chipY - chipH - 14
end

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

    -- Score tiles come from the scoring engine: average, highest, and lowest single-run score in scope.
    local S = ML.Scoring
    local avgScore, highScore, lowScore
    if S and S.Store and S.Store.Summary and S.Score then
        local sum, cnt = 0, 0
        for _, rr in ipairs(History.FilterRuns({ character = key, seasonId = scopeSeason() })) do
            local g = rr.character and rr.character.guid
            local ms = g and S.Store.Summary(rr)[g]
            if ms and type(ms.overall) == "number" then
                sum = sum + ms.overall; cnt = cnt + 1
                highScore = (not highScore or ms.overall > highScore) and ms.overall or highScore
                lowScore  = (not lowScore  or ms.overall < lowScore ) and ms.overall or lowScore
            end
        end
        if cnt > 0 then avgScore = sum / cnt end
    end

    -- Headline stats as responsive hero tiles (the Overview page's look + color scale). Columns reflow
    -- to the page width. DPS/HPS are neutral (absolute throughput isn't rated); scores use the grade color.
    -- Panel style can't host the large right-side icon, so fall back to a large-icon-capable style there.
    local tile, finish = heroTileGrid(b, x, y, w)
    local function scoreFmt(v) return (v and S and S.Score) and string.format("%s  (%d)", S.Score.Grade(v), math.floor(v + 0.5)) or DASH end
    local function scoreOpts(label, v, desc)
        local grade = (v and S and S.Score) and S.Score.Grade(v) or nil
        return { label = label, icon = "award", color = (grade and gradeColor(grade)) or ML.TierColor("N"),
            tipData = { title = label, lines = { { text = desc, color = "subtext" } } } }
    end
    local function metricOpts(label, icon, desc)
        return { label = label, icon = icon, color = ML.TierColor("N"),
            tipData = { title = label, lines = { { text = desc, color = "subtext" } } } }
    end

    tile("runs",          d.totals.runs,  tostring(d.totals.runs))
    tile("timedPercent",  d.timedPct,     d.timedPct and Util.percent(d.timedPct) or DASH)
    tile("highestTimed",  d.highestTimed, d.highestTimed and ("+" .. d.highestTimed) or DASH)
    tile("averageKey",    d.avgLevel,     d.avgLevel and string.format("+%.1f", d.avgLevel) or DASH)
    tile("averageTime",   d.avgDuration,  Util.duration(d.avgDuration))
    tile("averageDeaths", d.avgDeaths,    d.avgDeaths and string.format("%.1f", d.avgDeaths) or DASH)
    tile("bestDps",  d.bestDps, d.bestDps and Util.shortNum(d.bestDps) or DASH,
        metricOpts("Best DPS", "sword", "Your highest DPS in a single run (in scope)."))
    tile("bestHps",  d.bestHps, d.bestHps and Util.shortNum(d.bestHps) or DASH,
        metricOpts("Best HPS", "heartbeat", "Your highest HPS in a single run (in scope)."))
    tile("avgScore",  avgScore,  scoreFmt(avgScore),  scoreOpts("Avg Score", avgScore, "Your average performance score across these runs (0-100)."))
    tile("highScore", highScore, scoreFmt(highScore), scoreOpts("Highest Score", highScore, "Your best single-run performance score (0-100)."))
    tile("lowScore",  lowScore,  scoreFmt(lowScore),  scoreOpts("Lowest Score", lowScore, "Your lowest single-run performance score (0-100)."))

    y = finish()

    -- BY SPEC: each spec played, as a class/spec hero card (class color + spec icon).
    y = b:Section("BY SPEC", x, y); y = y - 30
    do
        local cols = (w >= 720) and 2 or 1
        local sgap, sch = 12, 68
        local cw = (w - (cols - 1) * sgap) / cols
        for i, sp in ipairs(d.specs) do
            local col, rowi = (i - 1) % cols, math.floor((i - 1) / cols)
            specHeroCard(b, C, x + col * (cw + sgap), y - rowi * (sch + sgap), cw, sch, sp, classFile)
        end
        y = y - math.ceil(#d.specs / cols) * (sch + sgap) - 4
    end

    -- BY DUNGEON: each dungeon as the standard dungeon hero card. Click opens the dungeon page;
    -- detailCharacter stays set so Back returns here (dispatch checks detailDungeon first).
    y = b:Section("BY DUNGEON", x, y); y = y - 30
    do
        local cols = (w >= 720) and 2 or 1
        local dgap, dch = 12, 68
        local cw = (w - (cols - 1) * dgap) / cols
        for i, dd in ipairs(d.dungeons) do
            local col, rowi = (i - 1) % cols, math.floor((i - 1) / cols)
            dungeonHeroCard(b, C, x + col * (cw + dgap), y - rowi * (dch + dgap), cw, dch, dd, win)
        end
        y = y - math.ceil(#d.dungeons / cols) * (dch + dgap) - 4
    end

    -- RUNS (paginated) - each row opens the full run.
    local runs = History.FilterRuns({ character = key, seasonId = scopeSeason() })
    y = b:Section(string.format("RUNS (%d)", #runs), x, y); y = y - 24
    if #runs == 0 then b:Label("No runs recorded.", x + 4, y - 2, C.subtext, 11); return y - 20 end
    sortRuns(runs, dungeonRunSort)
    local first, last = pagerBar(b, C, x, y, rowW, #runs, "charRuns", win); y = y - 42
    y = dungeonRunHeader(b, C, x, y, rowW, dungeonRunSort, win)
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
-- Dedicated PROGRESSION page: pick a character + a dungeon (or all) and chart the selected metric over that
-- character's runs. Its own sidebar item; reuses renderProgression for the chart + metric/view controls.
local function renderProgressionPage(b, C, x, y, w, win)
    local chars = History.CharacterList()
    if #chars == 0 then
        b:Wrap("No runs recorded yet - your progression will show here once you've run some keys.", x, y, w - 20, C.subtext, 12)
        return y - 30
    end
    local function charExists(fn) for _, c in ipairs(chars) do if c.fullName == fn then return true end end return false end
    if not (view.progChar and charExists(view.progChar)) then
        local me = API and API.PlayerContext and API.PlayerContext()
        view.progChar = (me and me.fullName and charExists(me.fullName) and me.fullName) or chars[1].fullName
        view.progDungeon = nil
    end
    local progChar = view.progChar

    y = renderSeasonSelector(b, C, x, y, w, win)   -- Season row

    -- Character + Dungeon row.
    local charChoices = {}
    for _, ch in ipairs(chars) do
        local nm = (ch.name and ch.name ~= "?" and ch.name) or ch.fullName or "Unknown"
        charChoices[#charChoices + 1] = { ch.fullName, classColorText(ch.classFile, nm) }
    end
    local nx = scopeControl(b, C, x, y, "Character", 190, "Character",
        "Which character's progression to chart.",
        charChoices, function() return view.progChar end,
        function(v) view.progChar = v; view.progDungeon = nil; if win then win:Refresh() end end)

    local det = History.CharacterDetail(progChar, scopeSeason())
    local dunChoices = { { "all", "All dungeons" } }
    for _, dn in ipairs((det and det.dungeons) or {}) do
        dunChoices[#dunChoices + 1] = { dn.mapId, dn.name or ("Map " .. tostring(dn.mapId)) }
    end
    scopeControl(b, C, nx, y, "Dungeon", 200, "Dungeon",
        "Chart all this character's dungeons together, or focus on one.",
        dunChoices, function() return view.progDungeon or "all" end,
        function(v) view.progDungeon = (v == "all") and nil or v; if win then win:Refresh() end end)
    y = y - 40

    local runs = History.FilterRuns({ character = progChar, mapId = view.progDungeon, seasonId = scopeSeason() })
    y = renderProgression(b, C, x, y, w, win, runs, { showDungeon = (view.progDungeon == nil), noSection = true })
    return y - 8
end

local TAB_RENDER = {
    overview = renderOverview, runs = renderRunsList, dungeons = renderDungeons,
    characters = renderCharacters, progression = renderProgressionPage, players = renderPlayers,
    bests = renderBests, settings = renderSettings, debug = renderDebug,
}

-- Title + description for the standard page heading drawn on each list page (Settings draws its own;
-- the record drill-downs use their own Back header, so they're not listed here).
local PAGE_META = {
    overview   = { "Summary",        "Your account-wide Mythic+ summary - season stats, recent runs, and quick links into any of them." },
    runs       = { "Runs",           "Every timed, depleted, or abandoned key you've recorded, newest first. Click a run for its full details." },
    dungeons   = { "Dungeons",       "Per-dungeon stats across your recorded runs - best time, timed %, and averages. Click one to drill in." },
    characters = { "Characters",     "Every character you've recorded runs on, with their season stats. Click one for its full history." },
    progression = { "Progression",   "Chart a character's improvement or regression over their runs - overall or in one dungeon. Pick a metric, then read it per run, per week, or by key level, with the distribution and trend stats underneath." },
    players    = { "Players",        "Everyone you've keyed with - shared history, best run together, averages, and your private notes." },
    bests      = { "Personal Bests", "Your best recorded run for each dungeon this season, by keystone level and time." },
    debug      = { "Debug",          "Diagnostics and the recent activity log - handy when reporting an issue." },
}

-- View id for one of this module's sidebar pages ("mod:<moduleId>:<pageId>").
local function pageViewId(pid) return "mod:" .. ML.MODULE_ID .. ":" .. pid end

-- Clear the record-parameterized drill-down overlays (run / dungeon / player / character / review).
-- Fired when a sidebar page row is (re)clicked, so each page opens on its own list, not a stale detail.
function UI.ClearDetails()
    view.detailRun, view.detailPlayer, view.detailDungeon, view.detailCharacter, view.review = nil, nil, nil, nil, nil
    reviewRunRef, reviewMemberRef = nil, nil
end

-- Navigate to one of this module's pages (a window view). In-window uses SelectView; without the window
-- handle (e.g. a slash command) fall back to OpenWindow.
function UI.GoToPage(win, pid)
    if win and win.SelectView then win:SelectView(pageViewId(pid))
    elseif _G.TAP and _G.TAP.OpenWindow then _G.TAP:OpenWindow(pageViewId(pid)) end
end

-- Render ONE of the module's sidebar pages. Top-level nav now lives in the sidebar (one row per page),
-- which frees the in-body top-nav for page-level sub-tabs (see the Settings page). The record drill-downs
-- still render OVER whichever page you're on and Back returns to it, so their precedence + selective
-- clearing is unchanged.
function UI.RenderPage(pageId, m, b, x, y, win)
    local C = b.theme.C
    local w = b.contentWidth - 40

    if not DB.Ready() then
        b:Wrap("Mythic Ledger is still loading...", x, y, w - 20, C.subtext, 12)
        return y - 30
    end

    -- The Dungeons filter box is a persistent frame (kept alive so it holds keyboard focus). Hide it
    -- unless the Dungeons LIST is the active view; renderDungeons re-shows + repositions it.
    local onDungeonsList = (pageId == "dungeons")
        and not (view.review or view.detailRun or view.detailPlayer or view.detailDungeon or view.detailCharacter)
    if dungeonSearch and not onDungeonsList then dungeonSearch:Hide() end

    -- Disabled: overlay every page except Settings (where the enable toggle lives), so the ledger can
    -- always be switched back on. Saved history is never touched by this.
    if m and m.IsEnabled and not m:IsEnabled() and pageId ~= "settings" then
        return b:DisabledOverlay(x, y, w, { subtitle = "Enable Mythic Ledger from the Platform Overview.",
            onSettings = function() if win then win:SelectView("overview") end end })
    end

    -- Record-parameterized drill-downs render OVER the current page (Back returns here). detailDungeon is
    -- checked BEFORE detailPlayer / detailCharacter so a dungeon card opened from either returns correctly.
    if view.review then return renderPlayerReview(b, C, x, y, w, win) end
    if view.detailRun then return renderRunDetails(b, C, x, y, w, win) end
    if view.detailDungeon then return renderDungeonDetails(b, C, x, y, w, win) end
    if view.detailPlayer then return renderPlayerDetails(b, C, x, y, w, win) end
    if view.detailCharacter then return renderCharacterDetails(b, C, x, y, w, win) end

    -- Standard page heading (title + description) on each list page, matching the platform pages. The
    -- Settings page draws its own heading alongside its sub-tab bar; drill-downs use their Back header.
    local meta = (pageId ~= "settings") and PAGE_META[pageId]
    if meta then y = b:PageHeading(x, y, meta[1], meta[2]) end
    local fn = TAB_RENDER[pageId] or renderOverview
    return fn(b, C, x, y, w, win)
end

-- Build the module's page list for Suite:RegisterModule (each becomes a sidebar sub-row). Reuses TABS.
function UI.SpecPages()
    local pages = {}
    for i, t in ipairs(TABS) do
        local pid = t[1]
        pages[i] = {
            id = pid, label = t[2], icon = t[3],
            default = (pid == "overview"), disabledSafe = true,   -- the module draws its own disabled overlay
            render = function(m, b, x, y, w, win) return UI.RenderPage(pid, m, b, x, y, win) end,
            onSelect = function() UI.ClearDetails() end,
        }
    end
    return pages
end

function UI.ResetView()
    UI.ClearDetails()
    runFilter.playerKey = nil
end

-- Navigated away from the ledger entirely: hide the persistent Dungeons search box, which is parented to
-- the shared content frame and would otherwise linger on top of whatever module you switch to.
function UI.OnHide()
    if dungeonSearch then dungeonSearch:Hide() end
end

-- Open the module, optionally on a specific page (used by slash commands / minimap).
function UI.Show(pid)
    UI.ClearDetails()
    if _G.TAP and _G.TAP.OpenWindow then
        _G.TAP:OpenWindow(pid and pageViewId(pid) or ("mod:" .. ML.MODULE_ID))
    end
end

----------------------------------------------------------------------
-- Post-run summary (queued out of combat).
----------------------------------------------------------------------
local pendingSummary
local summaryWatcher

-- Big end-of-run scoreboard modal: a Blizzard-M+-summary-style table of every party member's
-- stats, the result header, and the boss splits. Also reachable from a past run's detail page.

-- Performance-score (ML.Scoring) helpers, shared by the scoreboard AND the run detail so the grade
-- shows everywhere a run's party breakdown appears. Grade color keys off the letter.
-- Aggressive, honest scale: only A/S read as green/gold ("met expectations"); B is amber ("room to
-- improve"), C orange, D/F red. The category bars and numbers derive from this same map (via a score's
-- grade), so a 79 category is the exact color a 79 overall would show.
-- Grade color = the shared, theme-aware F..S metric scale (ML.TierColor). M+ Score is the ONE
-- exception - it keeps Blizzard's own rarity color via API.ScoreColor.
function gradeColor(grade) return (grade and ML.TierColor(grade:sub(1, 1))) or ML.TierColor("N") end   -- forward-declared above

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
-- Color a 0-100 score by the SAME grade scale the overall uses, so a category scoring 79 is the exact
-- color a 79 overall would be. Aggressive: only ~A/S read green/gold; a 79 (B) is amber, not "green".
local function catScoreHex(n)
    if type(n) ~= "number" then return "8b91a0" end
    local S = ML.Scoring and ML.Scoring.Score
    return (S and S.Grade) and gradeColor(S.Grade(n)) or "cccccc"
end

-- The grade letter a 0-100 score earns (or nil), safe to call anywhere.
local function scoreGrade(n)
    local S = ML.Scoring and ML.Scoring.Score
    return (type(n) == "number" and S and S.Grade) and S.Grade(n) or nil
end

-- Rich tooltip that explains the grade / score COLOR SCALE - the WoW-loot-rarity ramp every grade and
-- category number is colored by. Each row is drawn in its own tier color so the legend IS the scale.
-- Pass the current grade to mark the row this score lands on. Reused everywhere a scale color appears.
local SCALE_ROWS = {   -- { first-letter tier, score range, rarity name }
    { "S", "97-100", "Artifact" }, { "A", "85-96", "Legendary" }, { "B", "70-84", "Epic" },
    { "C", "60-69", "Rare" }, { "D", "50-59", "Uncommon" }, { "F", "0-49", "Poor" },
}
local function scoreScaleTip(currentGrade)
    local cur = currentGrade and currentGrade:sub(1, 1)
    local lines = { { text = "How scores are colored (higher is better):", color = "cdd2db" }, { sep = true } }
    for _, row in ipairs(SCALE_ROWS) do
        local hex = ML.TierColor(row[1])
        local mark = (cur == row[1]) and "  <" or ""
        lines[#lines + 1] = { left = row[1] .. "   " .. row[2], right = row[3] .. mark, lcolor = hex, rcolor = hex }
    end
    lines[#lines + 1] = { sep = true }
    lines[#lines + 1] = { text = "The same colors WoW uses for item rarity. Every grade and category number is tinted by where it lands here.", color = "8b91a0" }
    return { title = "Score & grade colors", lines = lines, anchor = "ANCHOR_CURSOR" }
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
-- color codes so it renders identically in the page AND in tooltips. Catches counts, decimals, %, x
-- ratios and K/M/B-suffixed values (e.g. 94.4K, 1.01x, 22%, ~4.5, -25). Score numbers are colored by
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
-- each row is a clean "Category -> score" (score color-coded) with ONE calm, dim detail line: the
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
        local function cmp(c) return string.format("%s vs %s %s (%.2fx)", Util.shortNum(c.value), Util.shortNum(c.expected), c.requirementModel and "required" or "expected", c.ratio or 0) end
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

    -- Compact color-scale legend so the score colors are self-explaining wherever this tooltip shows
    -- (the full ranged legend lives on the grade tile / breakdown-card hovers).
    lines[#lines + 1] = { sep = true }
    local seg = {}
    for k = #SCALE_ROWS, 1, -1 do   -- worst -> best (F D C B A S)
        seg[#seg + 1] = "|cff" .. ML.TierColor(SCALE_ROWS[k][1]) .. SCALE_ROWS[k][1] .. "|r"
    end
    lines[#lines + 1] = { text = "Grade colors (low -> high): " .. table.concat(seg, "  "), color = "9198a6" }

    return lines
end

-- Review "state" (from Scoring.Review.Band) -> accent color, matching the category score scale.
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
            label = "GRADE", value = (sc.grade or "?") .. "   " .. (sc.overall or 0),
            icon = "award", iconSize = 56, iconColor = theme:Color(gradeColor(sc.grade)),
            accent = acc, valueColor = theme:Color(gradeColor(sc.grade)),
            sub = "out of 100  ·  hover for scale",
            tipData = scoreScaleTip(sc.grade),
        })
    end
    classGlyph(b, LX, y - 2, 26, m.classFile)
    specGlyph(b, LX + 32, y - 2, 26, m.specId, m.specIcon)
    -- Hero-talent glyph (the chosen sub-tree, e.g. Pack Leader) as a third icon when we captured it.
    -- iconElementID may be a texture fileID (SetTexture, via b:Tex) or an atlas name (SetAtlas override);
    -- handle both and degrade to no-icon. The hero NAME is always shown on the spec line as a fallback.
    local heroTree = m.heroTree
    local textX = LX + 68
    if heroTree and heroTree.icon then
        local ic = heroTree.icon
        local t = b:Tex(LX + 64, y - 2, 26, 26, type(ic) == "number" and ic or "")
        if type(ic) == "string" and t and t.SetAtlas then pcall(t.SetAtlas, t, ic) end
        textX = LX + 100
    end
    b:Heading(classColorText(m.classFile, m.name or "?") .. (m.isPlayer and "  (you)" or ""), textX, y, "h2")
    local specRole = specClassLabel(m.classFile, m.specId) .. "   ·   " .. (ML.ROLE_LABEL[m.role] or "-")
    if heroTree and heroTree.name then specRole = specRole .. "   ·   " .. heroTree.name end
    b:Label(specRole, textX, y - 32, C.subtext, 11)
    b:Label((r.dungeonName or "Run") .. "  " .. Util.keyLabel(r.level) .. "   ·   " .. Util.dateTime(r.completedAt),
        textX, y - 52, C.subtext, 11)
    if review and review.headline then
        b:Wrap(review.headline, LX, y - 78, w - gradeW - 28, theme:Color(BAND_HEX[review.band] or "cdd2db", C.text), 13)
    end
    y = y - 124

    -- Hero combat-stat cards, laid out in TWO rows (4 + 3) so they breathe, using the same large
    -- class-colored hero icons as the scoreboard. Avoidable is its share of damage taken (the survival
    -- metric), colored by the survival score; deaths redden when non-zero.
    local survScore = sc and sc.categories and sc.categories.survival and sc.categories.survival.score
    local avoidShare = sc and sc.categories and sc.categories.survival
        and sc.categories.survival.detail and sc.categories.survival.detail.avoidableShare
    if avoidShare == nil and type(s.avoidableDamageTaken) == "number" and type(s.damageTaken) == "number" and s.damageTaken > 0 then
        avoidShare = s.avoidableDamageTaken / s.damageTaken
    end
    local heroStyle = tileStyle()
    local rows = {
        {
            { label = "DPS",       value = Util.shortNum(s.dps),         icon = "sword" },
            { label = "HPS",       value = Util.shortNum(s.hps),         icon = "heartbeat" },
            { label = "DMG TAKEN", value = Util.shortNum(s.damageTaken), icon = "shield" },
            { label = "AVOIDABLE", value = avoidShare and string.format("%.1f%%", avoidShare * 100) or DASH,
              icon = "alert-triangle", color = survScore and catScoreHex(survScore) or nil, scaleScore = survScore },
        },
        {
            { label = "INTERRUPTS", value = Util.numOr(s.interrupts, "%d"), icon = "ban" },
            { label = "DISPELS",    value = Util.numOr(s.dispels, "%d"),    icon = "sparkles" },
            { label = "DEATHS",     value = Util.numOr(s.deaths, "%d"),     icon = "skull",
              color = (type(s.deaths) == "number" and s.deaths > 0) and "e0655a" or nil },
            { label = "ILVL",       value = m.itemLevel and tostring(m.itemLevel) or DASH, icon = "backpack" },
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
                tipData = t.scaleScore and scoreScaleTip(scoreGrade(t.scaleScore)) or nil,
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

    -- GRADE BREAKDOWN as quasi-hero cards: bold label + explanation, an aggressively-colored bar, and a
    -- big score in the exact grade color that score would earn as an overall. Throughput splits DPS/HPS.
    local cats = sc.categories
    local Cfg = ML.Scoring and ML.Scoring.Config
    local didV = m.isPlayer and "you did" or "they did"
    local landedV = m.isPlayer and "you landed" or "they landed"
    local function rnd(v) return math.floor((v or 0) + 0.5) end
    local function bar(bx, by, bw, score)
        b:Box(bx, by, bw, 9, 0.16, 1, C.border)
        b:Box(bx, by, bw * math.max(0, math.min(1, (score or 0) / 100)), 9, 0.95, 2, theme:Color(catScoreHex(score)))
    end
    local BAR_X = LX + 340
    local function card(label, score, detail, na, detail2)
        local H = detail2 and 68 or 54
        b:Box(LX, y, CW, H, 0.45, 0, C.card)
        b:Box(LX, y, 3, H, 0.95, 2, na and theme:Color("8b91a0") or theme:Color(catScoreHex(score)))
        b:Label(label, LX + 16, y - 16, C.text, 13)
        if detail then b:Label(hlNums(detail), LX + 16, y - 36, C.subtext, 10) end
        if detail2 then b:Label(hlNums(detail2), LX + 16, y - 52, theme:Color("8a90a0", C.subtext), 10) end
        if na then
            b:Label("N/A", LX + CW - 84, y - 20, theme:Color("8b91a0"), 15)
        else
            bar(BAR_X, y - 30, CW - (BAR_X - LX) - 92, score)
            b:Label(tostring(rnd(score)), LX + CW - 76, y - 22, theme:Color(catScoreHex(score)), 20)
            if b.theme.SetTipData then b.theme:SetTipData(b:Hit(LX, y, CW, H), scoreScaleTip(scoreGrade(score))) end
        end
        y = y - H - 8
    end

    y = b:Section("GRADE BREAKDOWN", LX, y); y = y - 34

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
                local vs = c.requirementModel and "required" or "expected"
                -- Clean-run bonus (v42): a timed, no-death healer's Healing half is lifted to full marks; tag
                -- it so the score doesn't look inconsistent with the raw ratio.
                local tag = c.outcomeFloorRaw and "  · clean-run bonus" or ""
                b:Label(hlNums(string.format("%s vs %s %s (%.2fx)%s", Util.shortNum(c.value), Util.shortNum(c.expected), vs, c.ratio or 0, tag)),
                    LX + 372, yy, C.subtext, 10)
            end
            subBar("Damage", det.dps, y - 52)
            subBar("Healing", det.hps, y - 70)
            if b.theme.SetTipData then b.theme:SetTipData(b:Hit(LX, y, CW, H), scoreScaleTip(scoreGrade(t.score))) end
            y = y - H - 8
        else
            local c = det.dps or det.hps
            local vs = (c and c.requirementModel) and "required" or "expected"
            local d = c and string.format("%s vs %s %s (%.2fx) · weight %d%%",
                    Util.shortNum(c.value), Util.shortNum(c.expected), vs, c.ratio or 0, pctOf(t.weight))
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

    -- Interrupt + Dispel breakdowns: what THIS player actually did vs the dungeon's priority list, as real
    -- Blizzard spell icons (hover = tooltip) grouped by priority tier - so "did they hit the right casts"
    -- is visible. The DISPEL block folds in the old coaching callout: your clearing tool(s) on the left,
    -- and the spec-addressable targets you did NOT clear as the "Not dispelled by you" row (spec-filtered,
    -- so a Magic-only dispeller is never shown Curses). From the per-spell attribution x the season catalog
    -- (same source as the Dungeon Guide). Target icons are CLICKABLE -> jump to that spell in the Guide.
    -- Reference only; never changes the score. One shared renderer, called for kicks and for dispels.
    do
        local scfg = ML.Scoring and ML.Scoring.Config
        local cat = scfg and scfg.SeasonDungeon and scfg.SeasonDungeon(r.dungeonName, r.seasonId)
        local you, them = m.isPlayer and "you" or "they", m.isPlayer and "you" or "them"
        local OFFLIST = { order = 9, color = "8b91a0" }

        -- kind: "kick"|"dispel". landed = attribution list {id,amt}. prio = catalog (for tier + caster on
        -- the landed rows). tierMap/prioSet = ordering+color and which tiers count as "priority". iconFn =
        -- the pooled icon maker (own pool per kind). tools = your ability spellIDs shown left. missed =
        -- precomputed { {id,e} } not-done row. alwaysShow renders even with nothing landed (dispels).
        local function breakdown(kind, landed, prio, tierMap, prioSet, accentHex, iconFn, verbDid, spareWord, tools, missed, alwaysShow)
            landed, missed = landed or {}, missed or {}
            if #landed == 0 and not (alwaysShow and #missed > 0) then return end
            if not (prio and #prio > 0) then return end
            local byId = {}
            for _, e in ipairs(prio) do if e.id then byId[e.id] = e end end
            local buckets = {}
            local function bucket(label, ti) buckets[label] = buckets[label] or { order = ti.order, color = ti.color, entries = {} }; return buckets[label] end
            local prioCount, spareCount = 0, 0
            for _, k in ipairs(landed) do
                local cnt, e = k.amt or 1, k.id and byId[k.id]
                if e then
                    local tl = (e.tier == nil or e.tier == "unset") and "Spare" or e.tier
                    local bk = bucket(tl, tierMap[tl] or tierMap["Spare"] or OFFLIST)
                    bk.entries[#bk.entries + 1] = { id = k.id, count = cnt, e = e }
                    if prioSet[e.tier] then prioCount = prioCount + cnt else spareCount = spareCount + cnt end
                else
                    local bk = bucket("Off-list", OFFLIST)
                    bk.entries[#bk.entries + 1] = { id = k.id, count = cnt }
                    spareCount = spareCount + cnt
                end
            end
            local labels = {}
            for l in pairs(buckets) do labels[#labels + 1] = l end
            table.sort(labels, function(a, bb) return buckets[a].order < buckets[bb].order end)

            local nLines = #labels + (#missed > 0 and 1 or 0)
            if nLines == 0 then return end
            local toolRow = (tools and #tools > 0) and 1 or 0
            local H = 40 + (nLines + toolRow) * 30
            b:Box(LX, y, CW, H, 0.35, 0, C.card)
            b:Box(LX, y, 3, H, 0.95, 2, theme:Color(accentHex))
            b:Label(string.format("%s - %s %s %d (%d priority, %d %s) in %s:", (kind == "kick") and "Interrupts" or "Dispels",
                you, verbDid, prioCount + spareCount, prioCount, spareCount, spareWord, r.dungeonName or "this dungeon"),
                LX + 14, y - 16, C.text, 12)
            local n, ry = 0, y - 44
            -- Your clearing tool(s) on the LEFT, so "left = your ability, right = what it clears" reads
            -- plainly (the ask). Not clickable (your spell, not a dungeon cast).
            if toolRow == 1 then
                local ax = LX + 14
                for _, tid in ipairs(tools) do
                    n = n + 1
                    local gi = iconFn(theme, b.content, n, 22)
                    gi:ClearAllPoints(); gi:SetPoint("TOPLEFT", b.content, "TOPLEFT", ax, ry + 1)
                    gi:SetSpell(tid); gi:SetScript("OnMouseUp", nil); gi:Show(); b:Transient(gi)
                    ax = ax + 26
                end
                b:Label("your tool  ·  right = what it clears (click an icon to open the Guide)",
                    ax + 6, ry - 3, theme:Color("8b91a0"), 11)
                ry = ry - 30
            end
            local function drawRow(label, color, entries)
                local lbl = b:Label(label, LX + 14, ry - 3, theme:Color(color), 12)
                local ix = LX + 14 + math.max(96, (lbl:GetStringWidth() or 0) + 16)   -- fits the long "Not ... by you" label
                for _, e in ipairs(entries) do
                    if ix > LX + CW - 44 then break end
                    n = n + 1
                    local gi = iconFn(theme, b.content, n, 24)
                    gi:ClearAllPoints(); gi:SetPoint("TOPLEFT", b.content, "TOPLEFT", ix, ry + 2); gi:SetSpell(e.id); gi:Show(); b:Transient(gi)
                    gi._catEntry, gi._dungeon = e.e, r.dungeonName   -- on the frame, not a captured closure
                    gi:SetScript("OnMouseUp", iconOpenGuide)
                    ix = ix + 26
                    if (e.count or 1) > 1 then b:Label("x" .. e.count, ix, ry - 3, C.subtext, 10); ix = ix + 18 end
                    ix = ix + 6
                end
                ry = ry - 30
            end
            for _, l in ipairs(labels) do drawRow(l, buckets[l].color, buckets[l].entries) end
            if #missed > 0 then drawRow("Not " .. verbDid .. " by " .. them, "8b91a0", missed) end
            y = y - H - 8
        end

        if cat then
            -- Interrupts (tier-based; missed = priority casts not kicked).
            local KICK_TIER = ML.KICK_TIERS
            local KICK_PRIO = { Critical = true, ["Must kick"] = true, ["Should kick"] = true }
            local kicked = m.attribution and m.attribution.interrupts or {}
            local kdone = {}
            for _, k in ipairs(kicked) do if k.id then kdone[k.id] = true end end
            local kmissed = {}
            for _, e in ipairs(cat.kicks or {}) do
                if e.id and KICK_PRIO[e.tier] and not kdone[e.id] then kmissed[#kmissed + 1] = { id = e.id, e = e } end
            end
            breakdown("kick", kicked, cat.kicks, KICK_TIER, KICK_PRIO, "ff9d5c", kickIcon, "kicked", "spare", nil, kmissed, false)

            -- Dispels (tier-based; folds the coaching in). Addressable targets = cats.dispels.dispelTargets,
            -- already filtered to THIS spec's cleanse/purge/soothe capability - cross-ref to the season
            -- catalog for tier + caster so the "not dispelled" icons are correct AND clickable. Tools =
            -- defensive dispel (+ the offensive purge/soothe ability when the dungeon has any).
            local DISPEL_TIER = ML.DISPEL_TIERS
            local DISPEL_PRIO = { Highest = true, ["High (remove)"] = true, High = true }
            local dRes = cats.dispels
            local dtargets = (dRes and dRes.dispelTargets) or {}   -- spec-filtered; empty for non-dispellers
            local dispelled = m.attribution and m.attribution.dispels or {}
            if #dispelled > 0 or #dtargets > 0 then
                local ddone = {}
                for _, k in ipairs(dispelled) do if k.id then ddone[k.id] = true end end
                local catById = {}
                for _, e in ipairs(cat.dispels or {}) do if e.id then catById[e.id] = e end end
                local dmissed, hasOff = {}, false
                for _, tg in ipairs(dtargets) do
                    if tg.action == "Purge" or tg.action == "Soothe" then hasOff = true end
                    if tg.id and not ddone[tg.id] then
                        dmissed[#dmissed + 1] = { id = tg.id, e = catById[tg.id] or { id = tg.id, name = tg.name } }
                    end
                end
                local tools = {}
                if dRes and dRes.dispel and dRes.dispel.spellID then tools[#tools + 1] = dRes.dispel.spellID end
                local Cap = ML.Scoring and ML.Scoring.Capability
                local off = hasOff and Cap and Cap.OffensiveAbility and Cap.OffensiveAbility(m.classFile)
                if off and off.spellID then tools[#tools + 1] = off.spellID end
                breakdown("dispel", dispelled, cat.dispels, DISPEL_TIER, DISPEL_PRIO, "a06cf0", dispIcon,
                    "dispelled", "situational", tools, dmissed, true)
            end
        end
    end

    -- Survival
    local sv = cats.survival
    if sv then
        local shr = sv.detail and sv.detail.avoidableShare
        local pen = (sc.role == "TANK" and sv.detail and (sv.detail.threatPenalty or 0) > 0) and sv.detail.threatPenalty or 0
        if pen > 0 then
            -- Split into two sections (like Throughput's DPS/HPS): the avoidable-damage base, then the
            -- loose-mob-death deduction that docks it.
            local base = (sv.detail and sv.detail.shareScore) or (sv.score + pen)
            local ltd  = (sv.detail and sv.detail.looseThreatDeaths) or 0
            local forg = ltd - ((sv.detail and sv.detail.threatDeathsCharged) or 0)
            local H = 84
            b:Box(LX, y, CW, H, 0.45, 0, C.card)
            b:Box(LX, y, 3, H, 0.95, 2, theme:Color(catScoreHex(sv.score)))
            b:Label("Survival", LX + 16, y - 16, C.text, 13)
            b:Label(hlNums("avoidable damage, docked for loose-mob deaths · weight " .. pctOf(sv.weight) .. "%"), LX + 16, y - 34, C.subtext, 10)
            b:Label(tostring(rnd(sv.score)), LX + CW - 76, y - 20, theme:Color(catScoreHex(sv.score)), 20)
            b:Label("Avoidable Damage", LX + 20, y - 52, C.subtext, 11)
            bar(LX + 160, y - 55, 170, base)
            b:Label(tostring(rnd(base)), LX + 342, y - 52, theme:Color(catScoreHex(base)), 12)
            b:Label(hlNums(shr and string.format("%.1f%% of dmg taken avoidable", shr * 100) or "no avoidable data"), LX + 392, y - 52, C.subtext, 10)
            b:Label("Loose-Mob Deaths", LX + 20, y - 70, C.subtext, 11)
            b:Box(LX + 160, y - 73, 170, 9, 0.16, 1, C.border)
            b:Box(LX + 160, y - 73, 170 * math.max(0, math.min(1, pen / 100)), 9, 0.95, 2, theme:Color("e0655a"))
            b:Label(string.format("-%d", pen), LX + 342, y - 70, theme:Color("e0655a"), 12)
            local forgTxt = (forg > 0) and string.format(" · %d forgiven", forg) or ""
            b:Label(hlNums(string.format("%d teammate death%s from a mob %s lost or never had threat on%s",
                ltd, ltd == 1 and "" or "s", m.isPlayer and "you" or "they", forgTxt)), LX + 392, y - 70, C.subtext, 10)
            if b.theme.SetTipData then b.theme:SetTipData(b:Hit(LX, y, CW, H),
                { title = "Survival", lines = { { text = "Your avoidable-damage score, then docked for every teammate death from a mob you lost or never had threat on.", color = "subtext" } } }) end
            y = y - H - 8
        else
            card("Survival", sv.score, (shr and string.format("%.1f%% of dmg taken avoidable", shr * 100)
                or (sv.note or "estimate")) .. " · weight " .. pctOf(sv.weight) .. "%")
        end
    end

    -- Avoidable-damage breakdown: the actual mechanics behind the Survival score, biggest first. Each is a
    -- real Blizzard spell icon (hover = the game's spell tooltip) with the damage taken, a share bar, and
    -- its % of your avoidable total. Reference only; it's the detail behind Survival and never changes it.
    do
        local av = m.attribution and m.attribution.avoidable
        if av and #av > 0 then
            local total = 0
            for _, e in ipairs(av) do total = total + (e.amt or 0) end
            if type(s.avoidableDamageTaken) == "number" and s.avoidableDamageTaken > total then total = s.avoidableDamageTaken end
            local maxAmt = (av[1] and av[1].amt) or 0
            local shown = math.min(#av, 8)
            local more  = #av > shown
            -- Header (y-16) + subtitle (y-34) + rows from y-52 (each 22px, 18px icon) + bottom pad.
            local H = 56 + shown * 22 + (more and 16 or 0)
            b:Box(LX, y, CW, H, 0.35, 0, C.card)
            b:Box(LX, y, 3, H, 0.95, 2, theme:Color("e0a030"))
            local you = m.isPlayer and "you" or "they"
            b:Label(hlNums(string.format("Avoidable Damage - %s took %s from %d source%s", you,
                Util.shortNum(total), #av, #av == 1 and "" or "s")), LX + 16, y - 16, C.text, 13)
            b:Label("What's behind your Survival score - hover an icon for the spell. Reference only.",
                LX + 16, y - 34, C.subtext, 10)
            -- Right-aligned amount + % columns; the share bar fills the gap between the name and the amount.
            local amtX, pctX = LX + CW - 150, LX + CW - 58
            local bx = LX + 250
            local bw = math.max(40, (amtX - 14) - bx)
            local ry = y - 52
            for i = 1, shown do
                local e = av[i]
                -- Icon top at `ry`; text/bar/amount centered on the icon (18px -> center ry-9).
                local gi = avoidIcon(theme, b.content, i, 18)
                gi:ClearAllPoints(); gi:SetPoint("TOPLEFT", b.content, "TOPLEFT", LX + 18, ry)
                gi:SetSpell(e.id); gi:Show(); b:Transient(gi)
                b:Label(spellNameOf(e.id) or ("Spell " .. tostring(e.id)), LX + 46, ry - 4, C.subtext, 11)
                b:Box(bx, ry - 5, bw, 8, 0.16, 1, C.border)
                if maxAmt > 0 and (e.amt or 0) > 0 then b:Box(bx, ry - 5, bw * ((e.amt or 0) / maxAmt), 8, 0.95, 2, theme:Color("e0a030")) end
                b:Label(Util.shortNum(e.amt or 0), amtX, ry - 4, C.text, 11)
                if total > 0 then b:Label(string.format("%d%%", math.floor((e.amt or 0) / total * 100 + 0.5)), pctX, ry - 4, C.subtext, 10) end
                ry = ry - 22
            end
            -- Defensive: hide any pooled icons left from a render that showed more rows (Reset also clears them).
            for i = shown + 1, #avoidIconPool do if avoidIconPool[i] then avoidIconPool[i]:Hide() end end
            if more then
                b:Label(string.format("+ %d more source%s", #av - shown, (#av - shown) == 1 and "" or "s"),
                    LX + 46, ry - 2, C.subtext, 10)
            end
            y = y - H - 8
        end
    end

    -- Deaths
    local de = cats.deaths
    if de then
        local d = (de.deaths == nil) and (de.note or "no death data recorded")
            or ((de.deaths == 0) and ("no deaths · weight " .. pctOf(de.weight) .. "%")
            or string.format("%d death%s · -%d penalty · weight %d%%", de.deaths, de.deaths == 1 and "" or "s", de.penalty or 0, pctOf(de.weight)))
        card("Death Impact", de.score, d)
    end

    -- Death-cause breakdown. From the death recap, each death is bucketed as Avoidable (fatal damage was
    -- in the run's avoidable list), Missed Kick (a cast that should have been interrupted), Threat
    -- (unmitigated melee while not tanking - pulled aggro), or Other (unavoidable / unpinnable). Buckets
    -- sum to the death total and feed the cause-weighted Death Impact penalty (Missed Kick == Other).
    -- Recompute from the stored raw recaps so classifier changes (e.g. Missed Kick) show on already-saved
    -- runs; falls back to the frozen capture-time value when no recaps are stored.
    local dcz = (ML.Providers and ML.Providers.ClassifyMemberDeaths and ML.Providers.ClassifyMemberDeaths(r, m)) or m.deathCauses
    local dczTotal = dcz and ((dcz.avoidable or 0) + (dcz.kickable or 0) + (dcz.threat or 0) + (dcz.other or 0)) or 0
    if dcz and dczTotal > 0 then
        local total = dczTotal
        local H = 120
        b:Box(LX, y, CW, H, 0.45, 0, C.card)
        b:Box(LX, y, 3, H, 0.95, 2, theme:Color("e0655a"))
        b:Label("Death Causes", LX + 16, y - 16, C.text, 13)
        b:Label(hlNums(string.format("%d death%s classified  ·  best-effort  ·  drives the Death Impact score",
            total, total == 1 and "" or "s")), LX + 16, y - 34, C.subtext, 10)
        -- What actually killed you, per cause, from the classifier's per-death `fatal` detail: the finishing
        -- blow for avoidable / missed-kick / threat deaths, and the biggest single source (with its % of the
        -- death) for "Other" - whose fatal blow is often just the straw. Deduped, "x2" for repeats.
        local byCause = {}
        for _, f in ipairs(dcz.fatal or {}) do
            local c = f.cause or "other"; byCause[c] = byCause[c] or {}
            local l = byCause[c]; l[#l + 1] = f
        end
        local function culprits(cause)
            local list = byCause[cause]; if not list or #list == 0 then return nil end
            local order, seen = {}, {}
            -- Avoidable / missed-kick: name the FINISHING blow (it is the mechanic). Threat / other: name the
            -- biggest single source with its %, since the fatal blow is often just the last straw there.
            local useTop = (cause == "other" or cause == "threat")
            for _, f in ipairs(list) do
                local nm = (useTop and (f.topName or f.killer)) or (f.killer or f.topName) or "?"
                local e = seen[nm]
                if not e then e = { name = nm, n = 0, pct = useTop and f.topPct or nil }; seen[nm] = e; order[#order + 1] = e end
                e.n = e.n + 1
            end
            local parts = {}
            for i = 1, math.min(#order, 3) do
                local e = order[i]; local s = e.name
                if e.n > 1 then s = s .. " x" .. e.n end
                if e.pct and e.pct > 0 then s = s .. " (" .. e.pct .. "%)" end
                parts[#parts + 1] = s
            end
            if #order > 3 then parts[#parts + 1] = "+" .. (#order - 3) .. " more" end
            return table.concat(parts, ", ")
        end
        local function causeBar(name, count, hex, yy, tipBody, culpritStr)
            b:Label(name, LX + 20, yy, C.subtext, 11)
            local bw = 190
            b:Box(LX + 120, yy - 3, bw, 9, 0.16, 1, C.border)
            if count > 0 then b:Box(LX + 120, yy - 3, bw * (count / total), 9, 0.95, 2, theme:Color(hex)) end
            b:Label(tostring(count), LX + 322, yy, theme:Color(hex), 12)
            if culpritStr and culpritStr ~= "" then b:Label(culpritStr, LX + 348, yy, theme:Color(hex, C.subtext), 10) end
            if tipBody and b.theme.SetTipData then
                local lines = { { text = tipBody, color = "subtext" } }
                if culpritStr and culpritStr ~= "" then lines[#lines + 1] = { text = "Culprits: " .. culpritStr, color = "subtext" } end
                b.theme:SetTipData(b:Hit(LX + 16, yy + 7, CW - 32, 18), { title = name, lines = lines })
            end
        end
        causeBar("Avoidable", dcz.avoidable or 0, "e0655a", y - 54,
            "Died to a mechanic you could have sidestepped - the fatal damage was in this run's avoidable-damage list.", culprits("avoidable"))
        causeBar("Missed Kick", dcz.kickable or 0, "5f8dff", y - 72,
            "Died to a cast that should have been interrupted - the fatal damage came from a spell in this dungeon's kick list that wasn't kicked.", culprits("kickable"))
        causeBar("Threat", dcz.threat or 0, "e0a030", y - 90,
            "Died to unmitigated melee while not tanking - usually a threat/pickup issue (pulled aggro, or the tank never grabbed it). Note: fixate / soak / cleave mechanics can also read as melee.", culprits("threat"))
        causeBar("Other", dcz.other or 0, "8b91a0", y - 108,
            "Unavoidable mechanics, or a death we couldn't pin to a specific cause.", culprits("other"))
        y = y - H - 8
    end


    y = y - 10

    -- (HOW TARGETS WERE SET now renders AFTER the coaching sections below - see the end of this function.)

    -- What went well.
    if review and #review.strengths > 0 then
        y = b:Section("WHAT WENT WELL", LX, y); y = y - 32
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
        y = b:Section("FOCUS ON", LX, y)
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
        y = b:Section("FOCUS ON", LX, y); y = y - 32
        b:Label("Nothing meaningful to fix - a clean key. Keep it up.", LX + 18, y - 2, theme:Color("6fd06f"), 12)
        y = y - 28
    end

    -- HOW TARGETS WERE SET: plain-language explanation of every target this player's score was measured
    -- against, using their own numbers and a quick example. Drawn AFTER the coaching so the takeaways come
    -- first. Reference only - none of it changes the score.
    y = y - 4
    y = b:Section("HOW YOUR TARGETS WERE SET", LX, y); y = y - 32
    local youW = m.isPlayer and "you" or "they"
    local YouW = m.isPlayer and "You" or "They"
    local function expl(title, body)
        b:Label(hlNums(title), LX + 16, y - 2, C.text, 12)
        local _, hh = b:Wrap(hlNums(body), LX + 16, y - 20, CW - 32, C.subtext, 10)
        y = y - 22 - (hh or 12) - 8
    end
    if t and t.detail and t.detail.dps then
        local d = t.detail.dps
        expl(string.format("Damage - %s DPS target  (%s %s, %.2fx)",
                Util.shortNum(d.expected), didV, Util.shortNum(d.value), d.ratio or 0),
            string.format("You're measured against a fair slice of the group's damage this run, not a fixed number - so a slow key and a fast key are judged the same. Meeting your slice is full marks; going over never hurts. Example: %s did %s against a %s target, about %.0f%% of it.",
                youW, Util.shortNum(d.value), Util.shortNum(d.expected), (d.ratio or 0) * 100))
    end
    if t and t.detail and t.detail.hps then
        local h = t.detail.hps
        if h.requirementModel then
            local rd = h.reqDetail or {}
            local why = (sc.role == "TANK")
                and string.format("As a tank you're expected to self-cover about %d%% of the unavoidable damage you take; the healer covers the rest. Healing and absorbs both count. Example: %s covered %s of the %s asked, about %.0f%%.",
                    math.floor((rd.selfCoverage or 0) * 100 + 0.5), youW, Util.shortNum(h.value), Util.shortNum(h.expected), (h.ratio or 0) * 100)
                or string.format("Your target is the damage the group couldn't self-cover - the tank's leftover plus most of the group's unavoidable damage. Someone standing in avoidable stuff hits their own Survival, not your target, and absorbs count as healing. Example: %s healed %s of the %s asked, about %.0f%%.",
                    youW, Util.shortNum(h.value), Util.shortNum(h.expected), (h.ratio or 0) * 100)
            expl(string.format("Healing - %s required  (%s %s, %.2fx)",
                    Util.shortNum(h.expected), didV, Util.shortNum(h.value), h.ratio or 0), why)
        else
            expl(string.format("Healing - %s HPS target  (%s %s, %.2fx)",
                    Util.shortNum(h.expected), didV, Util.shortNum(h.value), h.ratio or 0),
                string.format("A fair slice of the group's healing this run, group-relative like damage. Tanks are expected to self-sustain some of it. Example: %s did %s against a %s target, about %.0f%%.",
                    youW, Util.shortNum(h.value), Util.shortNum(h.expected), (h.ratio or 0) * 100))
        end
    end
    local iC = cats.interrupts
    if iC and iC.applicable and iC.expected then
        local kit = iC.interruptSpell and string.format("%s (%ds CD)%s", iC.interruptSpell, iC.interruptCD or 0,
            iC.interruptExtras and (" + " .. iC.interruptExtras) or "") or (iC.profile or "?")
        expl(string.format("Interrupts - ~%.1f target  (%s %s)", iC.expected, landedV, iC.actual and tostring(iC.actual) or "-"),
            string.format("Your fair share of the kicks in reach. %s had about %.0f kickable casts (trash + the bosses you killed), split by each spec's kick cooldown - %s draws roughly %.0f%% of them, so ~%.1f is your share. Landing that is full marks and extra never hurts; a teammate over-kicking lowers their share, not yours. Example: %s landed %s of ~%.1f.",
                r.dungeonName or "This dungeon", iC.supply or 0, kit, (iC.share or 0) * 100, iC.expected,
                youW, iC.actual and tostring(iC.actual) or "-", iC.expected))
    end
    local dC = cats.dispels
    if dC and dC.applicable and dC.expected then
        expl(string.format("Dispels - ~%.1f target  (%s %s)", dC.expected, didV, dC.actual and tostring(dC.actual) or "-"),
            string.format("Your fair share of the dispels a %s kit can actually handle. Each school's cleanses (from this run's trash + bosses) are split only among teammates who can touch that school, so anything only you can clear falls entirely to you. Example: %s cleared %s of ~%.1f asked.",
                dC.profile or "?", youW, dC.actual and tostring(dC.actual) or "-", dC.expected))
    end
    if Cfg and Cfg.survival then
        local grace = (Cfg.survival.graceShare or 0.025) * 100
        local zero  = (Cfg.survival.zeroShare or 0.40) * 100
        local shr   = sv and sv.detail and sv.detail.avoidableShare
        local body
        if shr and type(s.avoidableDamageTaken) == "number" and type(s.damageTaken) == "number" then
            body = string.format("Only damage %s could have dodged counts, as a share of all the damage %s took - so it's fair whatever the key level or health pool. %s took %.1f%% avoidable (%s of %s), scoring %d. %.1f%% or less is a perfect 100; %.0f%%+ is 0. Example: cutting that roughly in half moves this well up toward 100.",
                youW, youW, YouW, shr * 100, Util.shortNum(s.avoidableDamageTaken), Util.shortNum(s.damageTaken), sv.score or 0, grace, zero)
        else
            body = string.format("Only damage %s could have dodged counts, as a share of all the damage %s took - scale-free, so key level and health pools don't matter. %.1f%% or less scores 100; %.0f%%+ scores 0.",
                youW, youW, grace, zero)
        end
        expl(string.format("Survival - %.1f%% avoidable or less = 100, %.0f%%+ = 0", grace, zero), body)
    end
    if Cfg and Cfg.deaths then
        local n = de and de.deaths
        if n == nil then
            expl("Deaths - no death data recorded",
                "No death information was captured for this run, so the Death score is left neutral rather than guessed.")
        elseif n == 0 then
            expl(string.format("Deaths - no deaths, scored %d", (de and de.score) or 100),
                string.format("%s didn't die - a perfect Death score. Dying is the single most expensive thing that can happen in a run, so a clean key really counts.", YouW))
        else
            local weighted = dcz and dczTotal > 0
            expl(string.format("Deaths - %d death%s, -%d, scored %d", n, n == 1 and "" or "s", de.penalty or 0, de.score or 0),
                string.format("Dying costs more than anything else in a run%s. %s died %d time%s for a %d-point hit, leaving %d.%s",
                    weighted and ", and not every death costs the same: an avoidable-mechanic death hurts most, a missed-kick or unavoidable death less, and a pulled-aggro death least (see Death Causes above)" or "",
                    YouW, n, n == 1 and "" or "s", de.penalty or 0, de.score or 0,
                    weighted and " Example: turning your most costly death into a survived pull recovers the biggest chunk of these points." or " Example: one fewer death is the biggest single score gain available."))
        end
    end

    return y - 14
end

-- The player's own spec on a run (the isPlayer party member's spec id), or nil if it wasn't captured.
local function runPlayerSpec(rr)
    for _, m in ipairs(rr and rr.party or {}) do
        if m.isPlayer then return m.specId or m.specID end
    end
    return nil
end

-- Your best TIMED completion for the SAME dungeon + character + spec + key level as `run`, excluding
-- `run` itself. Returns the RUN RECORD (nil when this is your first timed run of that exact combo) so
-- callers get both its duration and its party stats. Character is the run's own character (guid); spec
-- is the one you played THIS run, so a different spec keeps a separate best.
local function playerBestForCombo(run)
    local guid = run and run.character and run.character.guid
    local spec = runPlayerSpec(run)
    if not (guid and run.mapId and run.level) then return nil end
    local best
    for _, rr in ipairs(DB.Runs() or {}) do
        if rr.id ~= run.id and rr.status == STATUS.TIMED and type(rr.duration) == "number"
            and rr.mapId == run.mapId and rr.level == run.level
            and (rr.character and rr.character.guid) == guid
            and (spec == nil or runPlayerSpec(rr) == spec)
        then
            if not best or rr.duration < best.duration then best = rr end
        end
    end
    return best
end

function UI.ShowScoreboard(run, opts)
    local theme = _G.TAP and _G.TAP.uiTheme
    if not (theme and theme.Modal and run) then return end
    opts = opts or {}

    -- Theme-AGNOSTIC: the scoreboard always renders on its own fixed dark palette so it looks identical
    -- on every UI theme (and stays readable in light mode - its art backdrop is dark). Swap the shared
    -- palette in just while the modal is BUILT, then restore it: fontstrings capture their color, the
    -- Builder captures the palette reference (so row hovers stay dark too), and grades resolve to their
    -- bright variants because the swapped bg reads as dark - all locked in at build time.
    local savedC = theme.C
    theme.C = SB_PALETTE
    local C = theme.C

    -- Optional scoreboard-specific font: swap the theme font just while the modal is built, then
    -- restore it (all the modal's fontstrings capture theme.FONT at creation).
    local prevFont = theme.FONT
    local sbFontKey = DB.Settings().scoreboardFont
    if sbFontKey and sbFontKey ~= "" and _G.TAP and _G.TAP.ResolveFontFile then
        theme.FONT = _G.TAP.ResolveFontFile(theme:ResolveFont(sbFontKey))
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
    -- A member who took NO avoidable damage usually has it recorded as nil (shown as "-"), not 0 - the
    -- meter simply never reported an avoidable hit. For the LEAST AVOIDABLE leader we must read that as
    -- a true 0 (a clean run), matching the scoring normalize, so a genuinely clean player wins the crown
    -- instead of being skipped in favor of someone who actually stood in something.
    local function effAvoid(m)
        local s = m.stats
        if not s then return nil end
        if type(s.avoidableDamageTaken) == "number" then return s.avoidableDamageTaken end
        -- Participated (has any throughput / damage-taken number) but no avoidable logged => took 0.
        if type(s.damageTaken) == "number" or type(s.dps) == "number" or type(s.damage) == "number"
            or type(s.hps) == "number" or type(s.healing) == "number" then return 0 end
        return nil   -- no usable data for this member at all
    end
    local function statVal(key) return function(m) return m.stats and m.stats[key] end end
    local function bestOf(cmp, valueFn)
        local bestM, bestV
        for _, m in ipairs(run.party or {}) do
            local v = valueFn(m)
            if type(v) == "number" then
                if bestV == nil or (cmp == "min" and v < bestV) or (cmp == "max" and v > bestV) then
                    bestV, bestM = v, m
                end
            end
        end
        return bestM, bestV
    end
    local HERO_DEFS = {
        { label = "TOP DPS",        cmp = "max", val = statVal("dps"),        fmt = Util.shortNum, icon = "sword" },
        { label = "TOP HPS",        cmp = "max", val = statVal("hps"),        fmt = Util.shortNum, icon = "heartbeat" },
        { label = "INTERRUPTS",     cmp = "max", val = statVal("interrupts"), fmt = function(v) return string.format("%d", v) end, icon = "ban" },
        { label = "DISPELS",        cmp = "max", val = statVal("dispels"),    fmt = function(v) return string.format("%d", v) end, icon = "sparkles" },
        -- Lower is better; a clean 0 IS worth crowning, so this card shows even when the leader is at 0.
        { label = "LEAST AVOIDABLE",cmp = "min", val = effAvoid,              fmt = Util.shortNum, icon = "shield", showZero = true },
    }
    local heroes = {}
    for _, h in ipairs(HERO_DEFS) do
        local m, v = bestOf(h.cmp, h.val)
        if m and v and (h.showZero or v > 0) then
            heroes[#heroes + 1] = { label = h.label, member = m, value = v, fmt = h.fmt, icon = h.icon }
        end
    end
    local heroStyle = tileStyle()

    -- Group-utility strip (interrupts + the two dispel axes vs expected). Computed up front so its height
    -- can be reserved in the fixed body layout below; nil / no items => no strip, no reserved space.
    local groupUtil = ML.Scoring and ML.Scoring.Distribute and ML.Scoring.Distribute.GroupUtility
        and ML.Scoring.Distribute.GroupUtility(run)
    local guPart = (#groupUtilityItems(groupUtil) > 0) and (28 + GU_TILE_H + 14) or 0

    local W, rowH, headerH, colH = 1520, 50, 124, 22   -- headerH has room for the "vs your best" line;
                                                        -- rowH fits a full-size per-stat delta line under each value
    local heroPart = (#heroes > 0) and 88 or 0
    local partyPart = 28   -- the "PARTY" section header above the table
    local bossPart = (#bosses > 0) and (56 + #bosses * 42) or 0
    -- The timeline's "0:00" / end-time labels sit below the track (clear of the death gravestones just
    -- above them). Reserve extra bottom room so those labels clear the modal's footer buttons instead
    -- of tucking under them.
    local timePart = timelineOK and 268 or 0
    local newBest = run._newBests and #run._newBests > 0
    local bodyH = headerH + heroPart + guPart + partyPart + colH + math.max(1, #party) * rowH + bossPart + timePart + 12

    local timeStr = Util.duration(run.duration)
    local remStr = run.timeRemaining and ((run.timeRemaining >= 0 and "+" or "-") .. Util.duration(math.abs(run.timeRemaining)))

    local ok, sb = pcall(theme.Modal, theme, {
        title = "Mythic+ Scoreboard",
        variant = run.status == STATUS.TIMED and "success" or (run.status == STATUS.ABANDONED and "danger" or "warning"),
        icon = theme:GetIcon("award"),
        width = W, bodyHeight = bodyH,
        buttons = {
            { label = "View full run", kind = "default", onClick = function(m)
                m:Close()
                if _G.TAP and _G.TAP.OpenWindow then
                    view.detailRun = run.id; view.detailPlayer = nil
                    _G.TAP:OpenWindow(pageViewId("runs"))   -- Open doesn't clear detail state; renders over Runs
                end
            end },
            { label = "Close", kind = "primary", onClick = function(m) m:Close() end },
        },
        content = function(body, modal)
            local b = modal:Builder({ contentWidth = W - 32 })   -- cached+reused; no per-open frame leak
            local rowW = W - 32
            local x, y = 0, -2
            -- The MVP card and the hero-stat cards share one card width so they line up.
            local heroGap, heroN = 8, math.max(1, #heroes)
            local heroCW = (rowW - (heroN - 1) * heroGap) / heroN

            local mi = run.mapId and API.GetMapInfo(run.mapId)

            -- Your previous best run of this exact key (drives the header's time delta).
            local bestRun = playerBestForCombo(run)

            -- Per-member best index: for EVERY (character guid + spec) in your saved history, that
            -- player's stats in THEIR fastest timed run of THIS key (same dungeon + key level), excluding
            -- the current run. So each party member's per-stat delta is driven by THEIR OWN best run -
            -- not just whoever happened to be in yours - as long as you've logged a run with them at this
            -- dungeon + level + character + spec. (guid pins character + class; spec pins the build.)
            local memberBest = {}   -- "guid|specId" -> { dur, stats }
            for _, rr in ipairs(DB.Runs() or {}) do
                if rr.id ~= run.id and rr.status == STATUS.TIMED and type(rr.duration) == "number"
                    and rr.mapId == run.mapId and rr.level == run.level then
                    for _, pm in ipairs(rr.party or {}) do
                        local g, sp = pm.guid, (pm.specId or pm.specID)
                        if g and sp then
                            local key = g .. "|" .. sp
                            local cur = memberBest[key]
                            if not cur or rr.duration < cur.dur then
                                memberBest[key] = { dur = rr.duration, stats = pm.stats or {} }
                            end
                        end
                    end
                end
            end

            -- Backdrop: a solid black fill with the dungeon's own art laid over it at 25% opacity,
            -- covering the WHOLE modal (header + body + footer), not just the body. Drawn on the modal
            -- frame at BACKGROUND sublevels 2/3 - above the panel fill (sublevel 1) but below the header
            -- bar/title (ARTWORK/OVERLAY) and the body content (a child frame), so everything renders on
            -- top. Inset 2px so the modal's border still shows. Cached on the (pooled) modal frame and
            -- reused across opens; Adopt()ed so the modal hides them if the frame is reused for another
            -- dialog (the body reset can't reach frame-level textures).
            local backdrop = (modal and modal.frame) or body
            local blackBg = backdrop._sbBlackBg
            if not blackBg then
                blackBg = backdrop:CreateTexture(nil, "BACKGROUND", nil, 2)
                blackBg:SetColorTexture(0, 0, 0, 1)
                blackBg:SetPoint("TOPLEFT", 2, -2); blackBg:SetPoint("BOTTOMRIGHT", -2, 2)
                backdrop._sbBlackBg = blackBg
            end
            blackBg:Show(); if modal and modal.Adopt then modal:Adopt(blackBg) end
            -- Prefer the dungeon's wide Encounter-Journal background art (atmospheric, fills nicely);
            -- fall back to the small square GetMapUIInfo portal icon when the EJ art isn't available.
            local bgTex = API.DungeonBackground(run.dungeonName) or (mi and mi.texture)
            local watermark = backdrop._sbWatermark
            if not watermark then
                watermark = backdrop:CreateTexture(nil, "BACKGROUND", nil, 3)
                watermark:SetPoint("TOPLEFT", 2, -2); watermark:SetPoint("BOTTOMRIGHT", -2, 2)
                backdrop._sbWatermark = watermark
            end
            if bgTex then
                watermark:SetTexture(bgTex); watermark:SetAlpha(0.25); watermark:Show()
                if modal and modal.Adopt then modal:Adopt(watermark) end
            else
                watermark:Hide()
            end

            -- Header: dungeon portal + name + result + affixes + date.
            if mi and mi.texture then b:Tex(x, y - 4, 60, 60, mi.texture)
            else b:Tex(x, y - 4, 60, 60, "map", nil, { 0.55, 0.6, 0.72 }) end
            b:Heading((run.dungeonName or "Dungeon") .. "   " .. Util.keyLabel(run.level), x + 72, y, "h2")
            local result = statusText(run.status) .. "    " .. timeStr .. (remStr and ("   (" .. remStr .. ")") or "")
            if run.keystoneUpgrade and run.keystoneUpgrade > 0 then result = result .. "    +" .. run.keystoneUpgrade end
            b:Label(result, x + 72, y - 28, theme:Color(ML.STATUS_HEX[run.status] or "cccccc", C.text), 13)
            if run.affixNames and #run.affixNames > 0 then
                b:Label(table.concat(run.affixNames, ", "), x + 72, y - 48, C.subtext, 11)
            end
            b:Label(Util.dateTime(run.completedAt), x + 72, y - 66, C.subtext, 11)
            if newBest then b:Label("New personal best!", x + 72, y - 84, theme:Color("20C997"), 12) end

            -- Delta vs YOUR best for this exact key (same dungeon + character + spec + key level).
            do
                local best = bestRun and bestRun.duration
                local timed = run.status == STATUS.TIMED and type(run.duration) == "number"
                local txt, hex
                if not best then
                    if timed then txt, hex = "First timed clear of this key on this character + spec.", "20C997" end
                else
                    local delta = (run.duration or 0) - best
                    if timed and delta < -0.5 then
                        txt = string.format("New best for this key!  %s faster than your previous best (%s).",
                            Util.duration(-delta), Util.duration(best)); hex = "20C997"
                    elseif math.abs(delta) <= 0.5 then
                        txt = string.format("Matched your best for this key (%s).", Util.duration(best))
                    else
                        txt = string.format("%s off your best for this key (%s).", Util.duration(delta), Util.duration(best))
                        hex = "e0a030"
                    end
                end
                if txt then b:Label(txt, x + 72, y - 102, hex and theme:Color(hex) or C.subtext, 12) end
            end

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
                        icon = h.icon, iconSize = 64, iconColor = acc,   -- big class-colored hero icon
                        accent = acc, valueColor = C.text,               -- number neutral; name class-colored
                        sub = cname, footer = { cname },
                    })
                end
                y = y - heroPart
            end

            -- Group utility: party interrupts + the two dispel axes, each landed vs expected.
            y = groupUtilityStrip(b, C, x, y, rowW, run, heroStyle, groupUtil)

            y = b:Section("PARTY", x, y); y = y - 28

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

            -- Small per-stat delta drawn UNDER a member's value: this run vs the SAME player's stats in
            -- your previous best run of this key (only for members who were in both). Green = improved in
            -- that stat's good direction (damage-taken / deaths / avoidable are lower-is-better).
            local function intFmt(v) return string.format("%d", v) end
            local function statDelta(colX, ry, cur, prev, lowerBetter, fmt, minShow)
                if type(cur) ~= "number" or type(prev) ~= "number" then return end
                local d = cur - prev
                if math.abs(d) < (minShow or 1) then return end
                local improved = (lowerBetter and d < 0) or ((not lowerBetter) and d > 0)
                b:Label((d > 0 and "+" or "-") .. fmt(math.abs(d)), x + colX, ry - 34,
                    theme:Color(improved and "20C997" or "e0655a"), 12)
            end

            for i, m in ipairs(party) do
                local s = m.stats or {}
                local sc = memberScore(scores, m)
                local lines = {
                    { left = "Spec", right = specClassLabel(m.classFile, m.specId) },
                    { left = "Role", right = ML.ROLE_LABEL[m.role] or "-" },
                    { left = "Item level", right = m.itemLevel and tostring(m.itemLevel) or "-" },
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
                        view.detailRun = run.id; view.detailPlayer = nil
                        if _G.TAP and _G.TAP.OpenWindow then _G.TAP:OpenWindow(pageViewId("runs")) end
                    end })
                specGlyph(b, x + 4, y - 7, 26, m.specId, m.specIcon)
                roleIcon(b, x + 34, y - 11, 18, m.role)
                local nm = (m.isPlayer and "|cffffd200> |r" or "") .. classColorText(m.classFile, m.name or "?")
                b:Label(nm, x + COL.name, y - 16, C.text, 13)
                -- Equipped item level, small, under the name (captured live for you, via inspect for teammates).
                if m.itemLevel then b:Label("|cff8b8b8bilvl|r " .. tostring(m.itemLevel), x + COL.name, y - 33, C.subtext, 10) end
                -- Gold crown next to the MVP (the highest-graded player), matching the MVP hero card.
                local isMVP = mvp and sc and ((sc.playerGUID and sc.playerGUID == mvp.playerGUID)
                    or (sc.name and sc.name == mvp.name))
                if isMVP then b:Tex(x + COL.name - 14, y - 15, 12, 12, "crown", nil, { 1, 0.82, 0.2 }) end
                -- Our performance grade (color-coded) + the numeric score.
                if sc then
                    b:Label(sc.grade or "?", x + COL.grade, y - 16, theme:Color(gradeColor(sc.grade)), 14)
                    b:Label(tostring(sc.overall or 0), x + COL.grade + 40, y - 16, C.subtext, 12)
                else
                    b:Label(DASH, x + COL.grade, y - 16, C.subtext, 12)
                end
                -- M+ score, rarity-colored; the player also shows this run's gain in green.
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
                -- Deltas vs THIS member's own best run of this key (their guid + spec), if you've logged
                -- one with them. So you, and any teammate you've run this key with before, each compare
                -- to their own personal best.
                local mspec = m.specId or m.specID
                local mb = (m.guid and mspec) and memberBest[m.guid .. "|" .. mspec]
                local pb = mb and mb.stats
                if pb then
                    statDelta(COL.dps,    y, s.dps,                  pb.dps,                  false, Util.shortNum, 1000)
                    statDelta(COL.hps,    y, s.hps,                  pb.hps,                  false, Util.shortNum, 1000)
                    statDelta(COL.dtk,    y, s.damageTaken,          pb.damageTaken,          true,  Util.shortNum, 100000)
                    statDelta(COL.deaths, y, s.deaths,               pb.deaths,               true,  intFmt,        1)
                    statDelta(COL.int,    y, s.interrupts,           pb.interrupts,           false, intFmt,        1)
                    statDelta(COL.dsp,    y, s.dispels,              pb.dispels,              false, intFmt,        1)
                    statDelta(COL.avoid,  y, s.avoidableDamageTaken, pb.avoidableDamageTaken, true,  Util.shortNum, 10000)
                end
                y = y - rowH
            end

            -- Boss splits: per-boss kill time, the party's top DPS / top HPS, the lowest avoidable
            -- damage taken, and party deaths - each row hoverable for the encounter's full details.
            if #bosses > 0 then
                y = y - 6
                y = b:Section("BOSSES", x, y); y = y - 30   -- extra padding under the underline
                b:Label("BOSS", x + 60, y - 2, C.subtext, 10)
                b:Label("TIME", x + 430, y - 2, C.subtext, 10)
                b:Label("TOP DPS", x + 540, y - 2, C.subtext, 10)
                b:Label("TOP HPS", x + 810, y - 2, C.subtext, 10)
                b:Label("LEAST AVOIDABLE", x + 1080, y - 2, C.subtext, 10)
                b:Label("DEATHS", x + 1400, y - 2, C.subtext, 10)
                y = y - 20
                local function hl(h, k) return h and (classColorText(h.classFile, h.name or "?") .. "  " .. Util.shortNum(h[k])) end
                -- Top DPS/HPS aren't stored anymore - derive from perMember (the max entry). Falls back to
                -- a stored boss.topDps/topHps for very old bosses that predate perMember.
                local function topBy(pm, k)
                    if type(pm) ~= "table" then return nil end
                    local best
                    for _, e in ipairs(pm) do if (e[k] or 0) > 0 and (not best or e[k] > best[k]) then best = e end end
                    return best
                end
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
                    b:Label(hl(boss.topDps or topBy(boss.perMember, "dps"), "dps") or DASH, x + 540, y - 21, C.text, 11)
                    b:Label(hl(boss.topHps or topBy(boss.perMember, "hps"), "hps") or DASH, x + 810, y - 21, C.text, 11)
                    b:Label(hl(boss.lowAvoid, "amount") or DASH, x + 1080, y - 21, C.text, 11)
                    b:Label(string.format("%d", boss.deaths or 0), x + 1400, y - 21, C.subtext, 11)
                    y = y - 42
                end
            end

            -- Timeline (shared with the run-details page, so the two read identically): a combat /
            -- downtime track, boss portraits at their kill times, gravestones for deaths, the keystone
            -- +1/+2/+3 time targets, and your best time for this key.
            if timelineOK then
                renderRunTimeline(b, C, x, y, rowW, run)   -- last block in this cell; its returned y isn't reused
            end
        end,
    })
    theme.FONT = prevFont   -- restore the UI font now the modal's fontstrings are built
    theme.C = savedC        -- restore the UI palette; the modal captured the fixed scoreboard palette
    if not ok then          -- build failed under pcall - palette/font already restored, so bail cleanly
        if ML.Log then ML.Log("Scoreboard build failed: %s", tostring(sb)) end
        return
    end

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
            if theme.PlaySound then theme:PlaySound(st.scoreboardSoundKey or "VictoryFanfare", st.scoreboardSoundChannel or "Master") end
        end
    end

    -- "Change your keystone" reminder (set via /tap changekey): once THIS post-run scoreboard is up,
    -- pop a small alert OVER it, then clear the flag (one-shot). Only for the end-of-run popup, not when
    -- re-viewing an old run's scoreboard.
    if opts.postRun and st.pendingChangeKey then
        st.pendingChangeKey = nil
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, function()
                if theme.Alert then
                    theme:Alert({
                        title = "Change your keystone!",
                        variant = "warning",
                        icon = theme.GetIcon and theme:GetIcon("key") or nil,
                        message = "Don't forget to slot your next Mythic+ keystone before you head off again.",
                        okLabel = "Got it",
                    })
                end
            end)
        end
    end
end

-- Post-run auto-popup (gated by the postRunSummary setting) just opens the scoreboard.
function UI.ShowPostRun(run)
    UI.ShowScoreboard(run, { postRun = true })
end

-- Show the post-run summary after the configured delay (postRunDelay, default 5s) so it doesn't slam
-- onto the screen the instant its trigger fires (loot closed / combat drop). 0 = show immediately.
local function showPostRunAfterDelay(run)
    local delay = tonumber(DB.Settings().postRunDelay)
    if not delay then delay = 5 end
    if delay <= 0 then pcall(UI.ShowPostRun, run); return end
    C_Timer.After(delay, function() pcall(UI.ShowPostRun, run) end)
end

-- Watcher created + registered ONCE, lazily, but its RegisterEvent is never called from the
-- end-of-run path (which runs during the protected challenge-mode completion and taints). We flip
-- `pendingSummary` to arm it; the handler stays registered and only acts when something is pending.
local function ensureSummaryWatcher()
    if summaryWatcher then return end
    summaryWatcher = CreateFrame("Frame")
    summaryWatcher:SetScript("OnEvent", function(_, event)
        if not pendingSummary then return end
        -- "After loot" -> wait for you to close the end-chest loot window; otherwise the next combat drop.
        local trigger = DB.Settings().postRunAfterLoot and "LOOT_CLOSED" or "PLAYER_REGEN_ENABLED"
        if event ~= trigger then return end
        local r = pendingSummary; pendingSummary = nil; showPostRunAfterDelay(r)
    end)
    summaryWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    summaryWatcher:RegisterEvent("LOOT_CLOSED")   -- looting the run-end chest
end
ensureSummaryWatcher()   -- at file load (clean context), not from the protected completion path

function UI.QueuePostRun(run)
    if DB.Settings().postRunAfterLoot then
        -- Hold the summary until you loot the chest at the end of the run (LOOT_CLOSED). Safety net: if
        -- the chest is never looted, show it after a couple of minutes so it can't get stuck forever.
        pendingSummary = run
        C_Timer.After(150, function()
            if pendingSummary == run then pendingSummary = nil; showPostRunAfterDelay(run) end
        end)
    elseif InCombatLockdown() then
        pendingSummary = run   -- shown when PLAYER_REGEN_ENABLED fires (watcher already registered)
    else
        showPostRunAfterDelay(run)
    end
end
