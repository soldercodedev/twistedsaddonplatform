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
local view = { tab = "overview", season = "current", character = "all", detailRun = nil, detailPlayer = nil, detailDungeon = nil, detailCharacter = nil, review = nil }
-- Per-run player-review target (object refs, so it works for both saved and unsaved/preview runs).
local reviewRunRef, reviewMemberRef = nil, nil

-- Pooled hoverable spell/aura icons for the GROUP UTILITY tiles (real Blizzard tooltip on hover). Its own
-- pool so indices never collide with the breakdown icons.
local guIconPool = {}
local function guIcon(theme, parent, i, size)
    local gi = guIconPool[i]
    if not gi then gi = theme:GameIcon(parent, { size = size }); guIconPool[i] = gi end
    if gi:GetParent() ~= parent then gi:SetParent(parent) end
    gi:SetSize(size, size)
    return gi
end

-- Pooled icons for the INTERRUPT and DISPEL breakdowns (actual-vs-priority). Separate pools so they never
-- collide with each other, the dispel-coaching, or the group-utility icons in the same render.
local kickIconPool = {}
local function kickIcon(theme, parent, i, size)
    local gi = kickIconPool[i]
    if not gi then gi = theme:GameIcon(parent, { size = size }); kickIconPool[i] = gi end
    if gi:GetParent() ~= parent then gi:SetParent(parent) end
    gi:SetSize(size, size)
    return gi
end
local dispIconPool = {}
local function dispIcon(theme, parent, i, size)
    local gi = dispIconPool[i]
    if not gi then gi = theme:GameIcon(parent, { size = size }); dispIconPool[i] = gi end
    if gi:GetParent() ~= parent then gi:SetParent(parent) end
    gi:SetSize(size, size)
    return gi
end
-- Its own pool for the AVOIDABLE-damage breakdown (Blizzard spell icons + game tooltips).
local avoidIconPool = {}
local function avoidIcon(theme, parent, i, size)
    local gi = avoidIconPool[i]
    if not gi then gi = theme:GameIcon(parent, { size = size }); avoidIconPool[i] = gi end
    if gi:GetParent() ~= parent then gi:SetParent(parent) end
    gi:SetSize(size, size)
    return gi
end

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
local runFilter    = { character = nil, mapId = nil, status = nil, playerKey = nil }
local runSort      = { key = "date", dir = "desc" }
local playerFilter = { search = "", role = nil, favorite = false, minShared = 1 }
local playerSort   = { key = "runs", dir = "desc" }
local retentionPending = nil   -- staged retention cap; committed only via the Settings "Apply" button
local retScopePending   = nil  -- staged retention scope (ALL / SEASON / EXPANSION); committed on Apply
local retKeepTopPending = nil  -- staged "never remove a top run"; committed on Apply
local charSort     = { key = "runs", dir = "desc" }
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
    { "overview", "Overview", "layout-grid" }, { "runs", "Runs", "list" }, { "dungeons", "Dungeons", "map" },
    { "characters", "Characters", "users" }, { "players", "Players", "user" }, { "bests", "Bests", "trophy" },
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

-- Draw a dungeon's wide Encounter-Journal art as a card backdrop using a COVER crop instead of a
-- straight stretch. The EJ backgrounds are ~2.5:1 landscape images; a card that's much wider (or
-- much shorter) than that would otherwise scale the whole image up and smear it. We keep the art's
-- aspect and crop to a centred band so it always fills the card at a sane zoom. `bg` is a texture
-- fileID (from API.DungeonBackground / mapInfo.texture); no-op when nil.
local DUNGEON_ART_ASPECT = 2.5
local function dungeonArt(b, x, y, w, h, bg, alpha)
    if not bg then return end
    local target = w / math.max(1, h)
    local u0, u1, v0, v1 = 0, 1, 0, 1
    if target > DUNGEON_ART_ASPECT then          -- card wider than the art: crop top/bottom
        local vh = DUNGEON_ART_ASPECT / target
        v0 = (1 - vh) / 2; v1 = 1 - v0
    else                                          -- card narrower/taller than the art: crop sides
        local uh = target / DUNGEON_ART_ASPECT
        u0 = (1 - uh) / 2; u1 = 1 - u0
    end
    b:Tex(x, y, w, h, bg, { u0, u1, v0, v1 }, { 1, 1, 1, alpha or 0.5 }, 1)
end

-- Dark base for the KPI/highlight hero cards, so they read in the same dark, art-card family as the
-- dungeon-hero cards even though they carry no background art.
local HERO_CARD_BG = { 0.05, 0.055, 0.07 }

-- A KPI / highlight card in the STANDARD dungeon-hero visual language: dark base, 1px border, an accent
-- left edge, a large left icon, then a label + big value (+ optional sub line). This is what keeps the
-- Overview and Bests hero cards consistent with the dungeon-hero cards on the Dungeons tab. `accent`
-- (hex or {r,g,b}) tints the edge, label and (bundled) icon. Provide either `icon` (a bundled icon,
-- tinted with the accent) or `drawIcon(b, ix, iy, isz)` for a custom glyph (e.g. a class crest). The
-- value keeps its own inline color if it has one. Optional `onClick` / `tipData` (hover) wire a hit region.
local function heroStatCard(b, C, cx, cy, cw, ch, opts)
    local acc = opts.accent or C.accent
    if type(acc) == "string" then acc = b.theme:Color(acc, C.accent) end
    b:Box(cx - 1, cy + 1, cw + 2, ch + 2, 0.9, 0, C.border)   -- 1px border
    b:Box(cx, cy, cw, ch, 1, 1, HERO_CARD_BG)                 -- dark base (matches the dungeon cards)
    b:VRule(cx + 1, cy, cy - ch, 2, acc)                      -- accent left edge
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

-- The canonical ENTITY hero card, in the exact same visual language as the dungeon-hero cards: dark
-- base (+ optional background art), 1px border, an accent left edge, a LARGE left icon (a square
-- portrait/portal, or a 2:1 banner via iconWide), a title with an optional right-aligned accent value,
-- and up to a few subtext stat lines. This is the ONE hero-card look shared by dungeons, bosses and
-- top runs so every hero across the module reads the same. `iconTint` tints the icon (nil = full color
-- portrait/portal); `art` lays dimmed background art; `onClick` / `tipData` wire a hit region.
local function heroCard(b, C, cx, cy, cw, ch, opts)
    local acc = opts.accent or C.accent
    if type(acc) == "string" then acc = b.theme:Color(acc, C.accent) end
    b:Box(cx - 1, cy + 1, cw + 2, ch + 2, 0.9, 0, C.border)   -- 1px border
    b:Box(cx, cy, cw, ch, 1, 1, { 0, 0, 0 })                  -- black base
    if opts.art then dungeonArt(b, cx, cy, cw, ch, opts.art, opts.artAlpha or 0.42) end
    b:VRule(cx + 1, cy, cy - ch, 2, opts.art and artAccent(C) or acc)   -- accent left edge
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
        b:Box(x - 1, y + 1, w + 2, bh + 2, 0.9, 0, C.border)   -- 1px border
        b:Box(x, y, w, bh, 1, 1, { 0, 0, 0 })                  -- black base under the art
        local mi = d and d.mapId and API.GetMapInfo(d.mapId)
        dungeonArt(b, x, y, w, bh, d and (API.DungeonBackground(d.name) or (mi and mi.texture)), 0.5)
        b:VRule(x + 1, y, y - bh, 2, artAccent(C))             -- light accent left edge (over the art)
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

    -- Date column widened (cDate->cChar) to fit the date + time-of-day stamp without touching the name.
    local cIcon, cDate, cChar, cDun, cKey, cRes, cDur, cDth, cPerf =
        x + 6, x + 32, x + 140, x + 250, x + 400, x + 442, x + 532, x + 606, x + 648

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
        -- Crown marks your best-SCORING run for this dungeon + key level + class/spec (one per combo).
        if r.bestOfKind then b:Tex(cKey - 16, yTop - 10, 13, 13, "crown", nil, { 1, 0.82, 0.2 }) end
        b:Label(Util.keyLabel(r.level), cKey, yTop - 10, C.accent, 12)
        b:Badge(cRes, yTop - 9, { text = statusUpgradeText(r), variant = statusBadgeVariant(r.status) })
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
        return { title = "Target buffs — purge / soothe", minWidth = 240, lines = {
            { text = "Enemy buffs the group could strip here. Hover an icon for its spell tooltip.", color = "subtext" } } }
    elseif key == "cleanse" then
        return { title = "Debuffs — cleanse", minWidth = 240, lines = {
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
local GU_SCHOOL_COL = {
    magic   = { 0.31, 0.66, 1.00 }, curse = { 0.75, 0.49, 1.00 }, poison = { 0.29, 0.76, 0.35 },
    disease = { 0.78, 0.62, 0.40 }, enrage = { 1.00, 0.42, 0.33 },
}
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
        b:Box(x - 1, y + 1, w + 2, bh + 2, 0.9, 0, C.border)   -- 1px border
        b:Box(x, y, w, bh, 1, 1, { 0, 0, 0 })                  -- black base under the art
        dungeonArt(b, x, y, w, bh, bg, 0.5)
        b:VRule(x + 1, y, y - bh, 2, artAccent(C))             -- light accent left edge (over the art)
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
    b:Box(cx - 1, cy + 1, cw + 2, ch + 2, 0.9, 0, C.border)              -- 1px border
    b:Box(cx, cy, cw, ch, 1, 1, { 0, 0, 0 })                            -- black base under the art
    local mi = d.mapId and API.GetMapInfo(d.mapId)
    dungeonArt(b, cx, cy, cw, ch, API.DungeonBackground(d.name) or (mi and mi.texture), 0.40)
    b:VRule(cx + 1, cy, cy - ch, 2, C.accent)                           -- accent left edge (over the art)
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
    dungeonGlyph(b, x + 106, yTop - 5, 18, r.mapId)
    b:Label(r.dungeonName or "?", x + 130, yTop - 10, C.text, 11)
    b:Label(Util.keyLabel(r.level), x + 300, yTop - 10, C.accent, 12)
    b:Label(statusText(r.status), x + 344, yTop - 10, b.theme:Color(STATUS_HEX[r.status] or "cccccc", C.text), 11)
    b:Label(Util.duration(r.duration), x + 438, yTop - 10, C.text, 11)
    b:Label(Util.numOr(m.stats and m.stats.deaths, "%d"), x + 506, yTop - 10, C.subtext, 11)
    b:Label(primaryMetric(m.role, m.stats), x + 552, yTop - 10, C.text, 11)
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

    -- Headline stats as responsive hero tiles - the SAME look, sizing and reflow as the character-
    -- details page (color-scaled metrics via HeroStatStyle; the run-outcome tallies carry fixed
    -- status colors + a describing tooltip). Panel style can't host the large icon, so fall back to a
    -- large-icon-capable style there, exactly like the character page.
    local t = p.totals
    local pct = History.timedPct(t)
    local avgK = Util.safeDiv(p.levelSum, p.levelN)
    local avgD = History.avgOf(p.stats, "deaths")
    local setStyle = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[DB.Settings().cardStyle]
    local style = (setStyle == "panel" or not setStyle) and "clean" or setStyle
    local th = 92
    local tw, gap = 150, 12
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

    y = y - math.ceil(idx / cols) * gy - 6

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
        b:Label("DUNGEON", x + 130, y - 2, C.subtext, 10)
        b:Label("KEY", x + 300, y - 2, C.subtext, 10)
        b:Label("RESULT", x + 344, y - 2, C.subtext, 10)
        b:Label("TIME", x + 438, y - 2, C.subtext, 10)
        b:Label("DEATHS", x + 500, y - 2, C.subtext, 10)
        b:Label("DPS / HPS", x + 552, y - 2, C.subtext, 10)
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
    b:Box(cx - 1, cy + 1, cw + 2, ch + 2, 0.9, 0, C.border)              -- 1px border
    b:Box(cx, cy, cw, ch, 1, 1, { 0, 0, 0 })                            -- black base under the art
    local mi = r.mapId and API.GetMapInfo(r.mapId)
    dungeonArt(b, cx, cy, cw, ch, API.DungeonBackground(r.dungeonName) or (mi and mi.texture), 0.42)  -- dimmed art
    b:VRule(cx + 1, cy, cy - ch, 2, artAccent(C))                       -- light accent left edge (over the art)
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
        st.healing = 1.1e7; st.hps = st.healing / dur; st.overhealing = st.healing * 0.25
        st.dispels = 9; st.damage = 2.4e6; st.dps = st.damage / dur; st.interrupts = 2
    elseif role == "TANK" then
        st.damageTaken = 2.6e7; st.damage = 9.5e6; st.dps = st.damage / dur
        st.healing = 4.6e6; st.hps = st.healing / dur; st.overhealing = st.healing * 0.3
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
    { "tracking",    "Tracking",     "activity" },
    { "recap",       "Recap",        "users" },
    { "retention",   "Data",         "database" },
    { "debug",       "Debug",        "tools" },
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

    -- MODULE enable/disable (shown at the top of every sub-tab, so it's always reachable to re-enable).
    if UI._mod then
        y = b:ModuleToggle(x, y, w, UI._mod, { onToggle = function() win:Refresh() end,
            sub = "When off, no runs are recorded and recaps stop. Your saved history is kept." })
    end
    y = y - 8

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
    b:Sub("TOOLTIPS", x, y); y = y - 30
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
    end

    local function secStatTiles()
    b:Sub("STAT TILES", x, y); y = y - 30
    b:Label("Tile style", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Stat tile style",
        "How the stat tiles on the run scoreboard and detail pages look. Clean = flat dashboard tiles; "
        .. "Panel = darker WoW-style in-game tiles with a rank meter; Compact = data-rich cards with an "
        .. "extra footer line. (The Overview and Bests hero cards use a fixed style to match the dungeon cards.)"):SetChoices(210, {
        { "CLEAN", "Clean (dashboard)" }, { "PANEL", "Panel (WoW tiles)" }, { "COMPACT", "Compact (data-rich)" },
    }, function() return s.cardStyle or "PANEL" end, function(v) s.cardStyle = v; win:Refresh() end)
    y = y - 40
    -- Live preview of two stat tiles in the currently-selected style.
    do
        local pstyle = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[s.cardStyle or "COMPACT"] or "compact"
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
    b:Sub("SCOREBOARD", x, y); y = y - 30
    slider("Scale", 90, 180, 0.5, 3.0, 0.05, "%.2fx",
        function() return s.scoreboardScale or 1.5 end, function(v) s.scoreboardScale = v end,
        "How big the end-of-run scoreboard opens (still capped to fit your screen). Also: /ledger scale <n>.")
    b:Label("Font", x, y - 2, C.subtext)
    b:FontSelect(x + 90, y, { width = 200, value = (s.scoreboardFont ~= "" and s.scoreboardFont) or "UBUNTU",
        onChange = function(key) s.scoreboardFont = key end })
    y = y - 30
    T(b, b:Button(x, y, 130, "Use UI font", "default", function() s.scoreboardFont = ""; win:Refresh() end),
        "Use UI font", "Reset the scoreboard to use the same font as the rest of the UI.")
    y = y - 38

    toggle("Play a sound when the scoreboard opens", function() return s.scoreboardSound end,
        function(v) s.scoreboardSound = v end,
        "Play a sound (default: FFVII Victory Fanfare) when the scoreboard appears.")
    if s.scoreboardSound then
        b:Label("Sound", x, y - 2, C.subtext)
        T(b, b:SoundSelect(x + 90, y, { width = 140, value = s.scoreboardSoundKey or "VictoryFanfare",
            channel = s.scoreboardSoundChannel or "Master",
            onChange = function(v) s.scoreboardSoundKey = v end }), "Scoreboard sound", "The sound played when the scoreboard opens.")
        T(b, b:Button(x + 238, y, 58, "Test", "default", function()
            local theme = _G.TAP and _G.TAP.uiTheme
            if theme and theme.PlaySound then theme:PlaySound(s.scoreboardSoundKey or "VictoryFanfare", s.scoreboardSoundChannel or "Master") end
        end, { icon = "volume", iconSize = 13 }), "Test sound", "Preview the selected scoreboard sound.")
        y = y - 34
        b:Label("Channel", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 90, y), "Scoreboard sound channel",
            "Which audio channel the scoreboard sound plays on (e.g. Master, or Sound FX so it follows that "
            .. "volume slider)."):SetChoices(150, CHANNEL_CHOICES,
            function() return s.scoreboardSoundChannel or "Master" end, function(v) s.scoreboardSoundChannel = v end)
        y = y - 34
        b:Label("Play sound", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 90, y), "When to play the scoreboard sound",
            "End of run only = just the automatic post-run popup; Every view = also when you re-open a "
            .. "scoreboard from history."):SetChoices(180, {
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
        b:Sub("DEATH REPORT", x, y); y = y - 30
        toggle("On-screen death report after each pull", function() return dr.enabled end,
            function(v) dr.enabled = v end,
            "After combat drops (or at the run's end), flash a short overlay listing who died since the last "
            .. "report and why - time in the key, the killing blow, and the cause (including a missed kick's "
            .. "cast). Repost the last one to party chat with /ledger deathreport.")
        if dr.enabled then
            b:Label("When", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "When to show the report",
                "As soon as combat drops = a report after every pull (that pull's new deaths only). At the end "
                .. "of the run = one report of every death, when the key finishes."):SetChoices(210, {
                { "COMBAT", "As soon as combat drops" }, { "RUN_END", "At the end of the run" },
            }, function() return dr.trigger or "COMBAT" end, function(v) dr.trigger = v end)
            y = y - 40
            b:Label("Dismiss", x, y - 2, C.subtext)
            T(b, b:Dropdown(x + 90, y), "How the report goes away",
                "Auto = it fades on its own after the time below. Click to dismiss = it stays until you "
                .. "click it (it captures the mouse while shown). Both = it fades after the time below OR "
                .. "when you click it, whichever happens first."):SetChoices(210, {
                { "AUTO", "Auto (fade after time)" }, { "CLICK", "Click to dismiss" }, { "BOTH", "Both (fade or click)" },
            }, function() return dr.dismiss or "AUTO" end, function(v) dr.dismiss = v; win:Refresh() end)
            y = y - 40
            toggle("Only report my own deaths", function() return dr.onlyMe end, function(v) dr.onlyMe = v end,
                "Show only your deaths, not the whole party's.")
            if (dr.dismiss or "AUTO") ~= "CLICK" then   -- AUTO and BOTH both auto-fade after this time
                slider("On screen for", 130, 170,2, 20, 1, "%.0fs",
                    function() return dr.duration or 6 end, function(v) dr.duration = v end,
                    "How long the overlay stays before it fades out (also applies to Both).")
            end
            slider("Max deaths shown", 130, 170,3, 20, 1, "%.0f",
                function() return dr.maxLines or 8 end, function(v) dr.maxLines = v end,
                "Cap how many deaths are listed at once.")

            local function refreshPrev() if ML.DeathReport and ML.DeathReport.RefreshPreview then ML.DeathReport.RefreshPreview() end end
            b:Label("Font", x, y - 2, C.subtext)
            b:FontSelect(x + 90, y, { width = 200, value = (dr.font ~= "" and dr.font) or "UBUNTU",
                onChange = function(key) dr.font = key; win:Refresh() end })
            y = y - 30
            T(b, b:Button(x, y, 120, "Use UI font", "default", function() dr.font = ""; win:Refresh() end),
                "Use UI font", "Use the same font as the rest of the UI.")
            y = y - 38
            slider("Text size", 130, 170,10, 30, 1, "%.0f",
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
                slider("Panel opacity", 130, 170,0, 1, 0.05, "%.2f",
                    function() return (dr.bgColor and dr.bgColor[4]) or 0.82 end,
                    function(v) dr.bgColor = dr.bgColor or { 0.03, 0.04, 0.06, 0.82 }; dr.bgColor[4] = v; refreshPrev() end,
                    "How opaque the background panel is (0 = invisible).")
            end

            -- Live preview - all four causes, styled with the settings above; updates as you tweak them.
            b:Label("Preview", x, y - 2, C.subtext); y = y - 24
            local ph = (ML.DeathReport and ML.DeathReport.RenderPreview and ML.DeathReport.RenderPreview(b, x, y)) or 40
            y = y - ph - 14

            T(b, b:Button(x, y, 90, "Test", "default", function() if ML.DeathReport then ML.DeathReport.Test() end end,
                { icon = "eye", iconSize = 13 }), "Test", "Flash a sample death report (one of every cause) with your settings.")
            T(b, b:Button(x + 100, y, 140, "Move on screen", "default", function()
                if _G.TAP and _G.TAP.CloseWindow then _G.TAP:CloseWindow() end
                if ML.DeathReport then ML.DeathReport.StartMove() end
            end, { icon = "arrows-sort", iconSize = 13 }), "Move on screen",
                "Drag a sample where you want it, then click Save (or Cancel) on the bar that appears.")
            y = y - 40
        end
    end

    local function secTracking()
    b:Sub("TRACKING", x, y); y = y - 30
    toggle("Track abandoned runs", function() return s.trackAbandoned end, function(v) s.trackAbandoned = v end,
        "Save keys you leave or reset before completion (kept apart from your timed %).")
    toggle("Show post-run summary", function() return s.postRunSummary end, function(v) s.postRunSummary = v end,
        "Pop a summary modal after each completed key (queued until out of combat).")
    toggle("Show it only after looting the end chest", function() return s.postRunAfterLoot end, function(v) s.postRunAfterLoot = v end,
        "Wait to pop the summary until you loot the chest at the end of the run, instead of right when it finishes.")
    slider("Popup delay", 90, 200, 0, 30, 1, "%ds",
        function() return s.postRunDelay or 5 end, function(v) s.postRunDelay = v end,
        "How long to wait after the trigger (looting the end chest, or leaving combat) before the summary "
        .. "pops. 0 = instantly.")
    toggle("Confirm before saving a recovered abandoned run", function() return s.confirmAbandonSave end, function(v) s.confirmAbandonSave = v end,
        "After a reload/disconnect with an unfinished key, ask before saving it as abandoned.")
    toggle("Show minimap icon", function() return _G.TAP and _G.TAP.IsMinimapButtonShown and _G.TAP:IsMinimapButtonShown(ML.MODULE_ID) end,
        function(v) if _G.TAP and _G.TAP.SetMinimapButtonShown then _G.TAP:SetMinimapButtonShown(ML.MODULE_ID, v) end end,
        "Show a Mythic Ledger button on the minimap (left-click opens the ledger).")
    end

    local function secRecap()
    b:Sub("RETURNING-PLAYER RECAP", x, y); y = y - 26
    b:Label("Local only - never posted to group.", x, y - 2, C.subtext, 10); y = y - 22
    toggle("Show previous-player recaps", function() return rc.enabled end, function(v) rc.enabled = v end,
        "When you group with someone you've keyed with, print a short local-only reminder.")
    b:Label("Display", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Recap display", "Where recaps appear. Local chat is only visible to you."):SetChoices(160, {
        { "CHAT", "Local chat" }, { "TOAST", "Toast" }, { "BOTH", "Both" }, { "OFF", "Off" },
    }, function() return rc.display end, function(v) rc.display = v end)
    y = y - 34
    b:Label("Detail", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Recap detail", "How much a recap shows."):SetChoices(160, {
        { "COMPACT", "Compact" }, { "DETAILED", "Detailed" }, { "OFF", "Off" },
    }, function() return rc.detail end, function(v) rc.detail = v end)
    y = y - 34
    b:Label("History", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Recap history", "Count shared runs from the current season only, or all seasons."):SetChoices(160, {
        { "SEASON", "Current season" }, { "ALL", "All seasons" },
    }, function() return rc.history end, function(v) rc.history = v end)
    y = y - 34
    b:Label("Fires on", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Recap trigger",
        "When a recap fires. On join = as soon as a returning player is in your group; On ready check "
        .. "= only when a ready check starts; Both = either. (It never fires on zoning in/out.)"):SetChoices(160, {
        { "JOIN", "On join" }, { "READY", "On ready check" }, { "BOTH", "Both" },
    }, function() return rc.trigger or "JOIN" end, function(v) rc.trigger = v end)
    y = y - 34
    slider("Minimum shared runs", 160, 130, 1, 10, 1, "%d",
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
        T(b, b:SoundSelect(x + 90, y, { width = 140, value = rc.soundKey or "Applause",
            channel = rc.soundChannel or "Master",
            onChange = function(v) rc.soundKey = v end }), "Recap sound", "The sound played when a returning player is detected.")
        T(b, b:Button(x + 238, y, 58, "Test", "default", function()
            local theme = _G.TAP and _G.TAP.uiTheme
            if theme and theme.PlaySound then theme:PlaySound(rc.soundKey or "Applause", rc.soundChannel or "Master") end
        end, { icon = "volume", iconSize = 13 }), "Test sound", "Preview the selected recap sound.")
        y = y - 34
        b:Label("Channel", x, y - 2, C.subtext)
        T(b, b:Dropdown(x + 90, y), "Recap sound channel",
            "Which audio channel the recap sound plays on."):SetChoices(150, CHANNEL_CHOICES,
            function() return rc.soundChannel or "Master" end, function(v) rc.soundChannel = v end)
        y = y - 34
    end
    T(b, b:Button(x, y, 190, "Preview for current group", "default", function() ML.Recap.PreviewCurrentGroup() end),
        "Preview recaps", "Print a sample recap for everyone in your current group (ignores the once-per-session guard).")
    y = y - 34
    -- In-window preview: a sample recap rendered with your current display / detail / averages settings.
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

    local function secRetention()
    b:Sub("DATA RETENTION", x, y); y = y - 30
    -- The scope, numeric cap and keep-top toggle only STAGE a policy; nothing is removed until Apply
    -- is clicked (guarding against accidental deletion). The applied policy still auto-enforces as new
    -- runs save.
    if retentionPending  == nil then retentionPending  = s.retentionRuns or 0 end
    if retScopePending   == nil then retScopePending   = s.retentionScope or "ALL" end
    if retKeepTopPending == nil then retKeepTopPending = (s.retentionKeepTop ~= false) end
    local count = DB.CountRuns()
    b:Label(string.format("Currently storing |cfff4f6fb%d|r recorded run%s.", count, count == 1 and "" or "s"),
        x, y - 2, C.subtext, 11)
    y = y - 28
    b:Label("Retain", x, y - 2, C.subtext)
    T(b, b:Dropdown(x + 90, y), "Retention scope",
        "Which runs to keep. Current season / expansion delete every run OUTSIDE that window when you "
        .. "Apply; All keeps every season. Runs recorded before this tag existed are always kept."):SetChoices(200, {
        { "ALL", "All seasons" }, { "SEASON", "Current season only" }, { "EXPANSION", "Current expansion only" },
    }, function() return retScopePending end, function(v) retScopePending = v; win:Refresh() end)
    y = y - 34
    b:Label("Also cap to newest (0 = no cap)", x, y - 2, C.subtext); y = y - 22
    -- Digits only, 0-10000; sanitised on commit. Only STAGES the value - Apply enforces it.
    T(b, b:EditBox(x, y, 90, tostring(retentionPending), function(txt)
        local n = tonumber((tostring(txt or "")):gsub("%D", "")) or 0
        if n > 10000 then n = 10000 end
        retentionPending = n
        win:Refresh()
    end), "Run cap", "Keep at most this many of the newest runs (0 = no cap). Digits only, up to 10000.")
    y = y - 34
    local kt = b:Toggle(x, y, retKeepTopPending, function(v) retKeepTopPending = v; win:Refresh() end)
    b.theme:SetTip(kt, "Never remove a top run",
        "Protect your best key per dungeon, your top 10, and every crowned best-of-kind run - they are "
        .. "never deleted by retention, even outside the retained season/expansion.")
    b:Label("Never remove a top run", x + 46, y - 2, C.text)
    y = y - 34
    local dirty = (retentionPending ~= (s.retentionRuns or 0))
        or (retScopePending ~= (s.retentionScope or "ALL"))
        or (retKeepTopPending ~= (s.retentionKeepTop ~= false))
    T(b, b:Button(x, y, 90, "Apply", dirty and "primary" or "default", function()
        s.retentionScope   = retScopePending
        s.retentionRuns    = retentionPending
        s.retentionKeepTop = retKeepTopPending
        DB.ApplyRetention()
        win:Refresh()
    end), "Apply retention", "Commit the policy above and prune now. Runs are never removed until you click this.")
    if dirty then b:Label("staged - not yet applied", x + 100, y - 2, b.theme:Color("e0a030", C.subtext), 11) end
    y = y - 28
    local _, wh = b:Wrap("|cffe0a030Warning:|r applying removes every run that falls outside the policy above. "
        .. "This permanently deletes runs and cannot be undone.", x, y, COLW - 20, { 0.85, 0.68, 0.35 }, 11)
    y = y - (wh + 14)
    T(b, b:Button(x, y, 160, "Delete All History", "danger", function()
        local theme = _G.TAP and _G.TAP.uiTheme
        theme:Confirm({ title = "Delete ALL history?", variant = "danger", confirmLabel = "Delete everything",
            message = "This permanently erases every recorded run and summary. Notes/tags are kept. This can't be undone.",
            onConfirm = function() DB.WipeHistory(); win:Refresh() end })
    end, { icon = "trash", iconSize = 13 }), "Delete all", "Permanently erase every recorded run. Notes/tags are kept.")
    y = y - 44
    end

    local function secDebug()
    b:Sub("DEBUG", x, y); y = y - 30
    toggle("Debug logging", function() return s.debug end, function(v) s.debug = v; ML._debugEcho = v end,
        "Echo internal diagnostics to chat and the Debug page.")
    end

    -- Render the active sub-tab's section(s), single-column full-width. Appearance groups the two small
    -- display sections (Stat Tiles + Date & Time) so no sub-tab is nearly empty.
    local SUBTABS = {
        appearance  = { secStatTiles, secDateTime },
        tooltips    = { secTooltips },
        scoreboard  = { secScoreboard },
        deathreport = { secDeathReport },
        tracking    = { secTracking },
        recap       = { secRecap },
        retention   = { secRetention },
        debug       = { secDebug },
    }
    for _, fn in ipairs(SUBTABS[settingsTab] or SUBTABS.appearance) do fn() end
    return y - 14
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
    if r.bestOfKind then b:Tex(x + 236, yTop - 9, 12, 12, "crown", nil, { 1, 0.82, 0.2 }) end
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
    local setStyle = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[DB.Settings().cardStyle]
    local style = (setStyle == "panel" or not setStyle) and "clean" or setStyle
    local th = 92
    local tw, gap = 150, 12
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

    y = y - math.ceil(idx / cols) * gy - 6

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
    UI._mod = m               -- module handle (the Settings page offers the enable/disable toggle)
    view.tab = pageId         -- mirror the active page for internal code that reads view.tab

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
        return b:DisabledOverlay(x, y, w, { subtitle = "Go to the Settings page to turn Mythic Ledger back on.",
            onSettings = function() UI.GoToPage(win, "settings") end })
    end

    -- Record-parameterized drill-downs render OVER the current page (Back returns here). detailDungeon is
    -- checked BEFORE detailPlayer / detailCharacter so a dungeon card opened from either returns correctly.
    if view.review then return renderPlayerReview(b, C, x, y, w, win) end
    if view.detailRun then return renderRunDetails(b, C, x, y, w, win) end
    if view.detailDungeon then return renderDungeonDetails(b, C, x, y, w, win) end
    if view.detailPlayer then return renderPlayerDetails(b, C, x, y, w, win) end
    if view.detailCharacter then return renderCharacterDetails(b, C, x, y, w, win) end

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
local SB_STATUS_HEX = { TIMED = "33dd66", DEPLETED = "e0a030", ABANDONED = "9098a8" }

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

    -- Role contribution (only when it carries weight).
    local rc = cats.roleContribution
    if rc and (rc.weight or 0) > 0 then
        block("Role Contribution", rc.score, false, "survival + utility composite" .. wt(rc.weight))
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
    local heroStyle = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[DB.Settings().cardStyle] or "compact"
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
                b:Label(hlNums(string.format("%s vs %s %s (%.2fx)", Util.shortNum(c.value), Util.shortNum(c.expected), vs, c.ratio or 0)),
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
        local cat = scfg and scfg.SeasonDungeon and scfg.SeasonDungeon(r.dungeonName)
        local you, them = m.isPlayer and "you" or "they", m.isPlayer and "you" or "them"
        local OFFLIST = { o = 9, c = "8b91a0" }

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
            local function bucket(label, ti) buckets[label] = buckets[label] or { order = ti.o, color = ti.c, entries = {} }; return buckets[label] end
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
                    local catEntry = e.e
                    gi:SetScript("OnMouseUp", function()
                        if catEntry and ML.DungeonGuide and ML.DungeonGuide.SelectAndOpen then
                            ML.DungeonGuide.SelectAndOpen(r.dungeonName, catEntry)
                        end
                    end)
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
            local KICK_TIER = { ["Critical"] = { o = 1, c = "ff4d4d" }, ["Must kick"] = { o = 2, c = "ff7a45" },
                ["Should kick"] = { o = 3, c = "ffd200" }, ["Spare"] = { o = 8, c = "9aa0ad" } }
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
            local DISPEL_TIER = { ["Highest"] = { o = 1, c = "ff4d4d" }, ["High (remove)"] = { o = 2, c = "ff7a45" },
                ["High"] = { o = 3, c = "ffb038" }, ["Medium"] = { o = 4, c = "ffd200" }, ["Conditional"] = { o = 5, c = "8fbf6b" },
                ["When needed"] = { o = 6, c = "6fb0c9" }, ["Spare"] = { o = 8, c = "9aa0ad" } }
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
        card("Survival", sv.score, shr and string.format("%.1f%% of dmg taken avoidable · weight %d%%", shr * 100, pctOf(sv.weight))
            or ((sv.note or "estimate") .. " · weight " .. pctOf(sv.weight) .. "%"))
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
        local function causeBar(name, count, hex, yy, tipBody)
            b:Label(name, LX + 20, yy, C.subtext, 11)
            local bw = 190
            b:Box(LX + 120, yy - 3, bw, 9, 0.16, 1, C.border)
            if count > 0 then b:Box(LX + 120, yy - 3, bw * (count / total), 9, 0.95, 2, theme:Color(hex)) end
            b:Label(tostring(count), LX + 322, yy, theme:Color(hex), 12)
            if tipBody and b.theme.SetTipData then
                b.theme:SetTipData(b:Hit(LX + 16, yy + 7, CW - 32, 18),
                    { title = name, lines = { { text = tipBody, color = "subtext" } } })
            end
        end
        causeBar("Avoidable", dcz.avoidable or 0, "e0655a", y - 54,
            "Died to a mechanic you could have sidestepped - the fatal damage was in this run's avoidable-damage list.")
        causeBar("Missed Kick", dcz.kickable or 0, "5f8dff", y - 72,
            "Died to a cast that should have been interrupted - the fatal damage came from a spell in this dungeon's kick list that wasn't kicked.")
        causeBar("Threat", dcz.threat or 0, "e0a030", y - 90,
            "Died to unmitigated melee while not tanking - usually a threat/pickup issue (pulled aggro, or the tank never grabbed it). Note: fixate / soak / cleave mechanics can also read as melee.")
        causeBar("Other", dcz.other or 0, "8b91a0", y - 108,
            "Unavoidable mechanics, or a death we couldn't pin to a specific cause.")
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
        expl(string.format("Damage — %s DPS target  (%s %s, %.2fx)",
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
            expl(string.format("Healing — %s required  (%s %s, %.2fx)",
                    Util.shortNum(h.expected), didV, Util.shortNum(h.value), h.ratio or 0), why)
        else
            expl(string.format("Healing — %s HPS target  (%s %s, %.2fx)",
                    Util.shortNum(h.expected), didV, Util.shortNum(h.value), h.ratio or 0),
                string.format("A fair slice of the group's healing this run, group-relative like damage. Tanks are expected to self-sustain some of it. Example: %s did %s against a %s target, about %.0f%%.",
                    youW, Util.shortNum(h.value), Util.shortNum(h.expected), (h.ratio or 0) * 100))
        end
    end
    local iC = cats.interrupts
    if iC and iC.applicable and iC.expected then
        local kit = iC.interruptSpell and string.format("%s (%ds CD)%s", iC.interruptSpell, iC.interruptCD or 0,
            iC.interruptExtras and (" + " .. iC.interruptExtras) or "") or (iC.profile or "?")
        expl(string.format("Interrupts — ~%.1f target  (%s %s)", iC.expected, landedV, iC.actual and tostring(iC.actual) or "-"),
            string.format("Your fair share of the kicks in reach. %s had about %.0f kickable casts (trash + the bosses you killed), split by each spec's kick cooldown - %s draws roughly %.0f%% of them, so ~%.1f is your share. Landing that is full marks and extra never hurts; a teammate over-kicking lowers their share, not yours. Example: %s landed %s of ~%.1f.",
                r.dungeonName or "This dungeon", iC.supply or 0, kit, (iC.share or 0) * 100, iC.expected,
                youW, iC.actual and tostring(iC.actual) or "-", iC.expected))
    end
    local dC = cats.dispels
    if dC and dC.applicable and dC.expected then
        expl(string.format("Dispels — ~%.1f target  (%s %s)", dC.expected, didV, dC.actual and tostring(dC.actual) or "-"),
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
        expl(string.format("Survival — %.1f%% avoidable or less = 100, %.0f%%+ = 0", grace, zero), body)
    end
    if Cfg and Cfg.deaths then
        local n = de and de.deaths
        if n == nil then
            expl("Deaths — no death data recorded",
                "No death information was captured for this run, so the Death score is left neutral rather than guessed.")
        elseif n == 0 then
            expl(string.format("Deaths — no deaths, scored %d", (de and de.score) or 100),
                string.format("%s didn't die - a perfect Death score. Dying is the single most expensive thing that can happen in a run, so a clean key really counts.", YouW))
        else
            local weighted = dcz and dczTotal > 0
            expl(string.format("Deaths — %d death%s, -%d, scored %d", n, n == 1 and "" or "s", de.penalty or 0, de.score or 0),
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
    local heroStyle = ({ CLEAN = "clean", PANEL = "panel", COMPACT = "compact" })[DB.Settings().cardStyle] or "compact"

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
            local b = theme:Builder(body, { contentWidth = W - 32 })
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

            -- Timeline (shared with the run-details page, so the two read identically): a combat /
            -- downtime track, boss portraits at their kill times, gravestones for deaths, the keystone
            -- +1/+2/+3 time targets, and your best time for this key.
            if timelineOK then
                y = renderRunTimeline(b, C, x, y, rowW, run)
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
