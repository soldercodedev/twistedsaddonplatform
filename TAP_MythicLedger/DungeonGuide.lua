-- TAP: Mythic Ledger - DungeonGuide.lua
-- A read-only "dungeon journal" for the CURRENT SEASON's interrupt & dispel PRIORITIES, built from the
-- per-dungeon CATALOG blocks in Scoring/Seasons/*.lua (each dungeon's `kicks`/`dispels` arrays: spell
-- id/name, caster NPC + npcId, priority tier, dispel type). Click a spell to see the caster's live 3D
-- model. Registered as its own entry in the platform's left menu, under Modules. Reference ONLY - it
-- does not drive scoring.

local ADDON, ML = ...
local Suite = _G.TAP
local TAP   = _G.TAP
if not (Suite and TAP) then return end

local Guide = {}
ML.DungeonGuide = Guide

-- Friendly names for the Midnight S1 dungeons (a season block may override with its own `name`).
local DISPLAY = {
    magistersterrace     = "Magisters' Terrace",     skyreach        = "Skyreach",
    algetharacademy      = "Algeth'ar Academy",      pitofsaron      = "Pit of Saron",
    seatofthetriumvirate = "Seat of the Triumvirate", maisaracaverns = "Maisara Caverns",
    nexuspointxenas      = "Nexus-Point Xenas",      windrunnerspire = "Windrunner Spire",
}

-- Priority tiers -> display order (high first) + color. An uncurated ("unset") entry shows as "Spare".
-- Single source of truth in Constants (shared with the run-review interrupt/dispel breakdown).
local KICK_TIERS   = ML.KICK_TIERS
local DISPEL_TIERS = ML.DISPEL_TIERS
-- Dispel school -> color (shared with the run-review tiles; see ML.SCHOOL_COLOR).
local SCHOOL_COLOR = ML.SCHOOL_COLOR

local QMARK = 134400   -- default "question mark" spell icon
local function spellTex(id)
    if id and C_Spell and C_Spell.GetSpellTexture then
        local t = C_Spell.GetSpellTexture(id)
        if t then return t end
    end
    return QMARK
end
-- "unset"/nil display as "Spare"; unknown tiers fall back to the Spare row.
local function normTier(t) return (not t or t == "unset") and "Spare" or t end
local function tierInfo(map, tier) return map[tier] or map["Spare"] end

-- Module-local view state.
local state = { dungeon = nil, selDungeon = nil, sel = nil }   -- sel = { id, npcId, name, npc, tier }

-- Dungeon art banner (crop the ~2.5:1 EJ background to fill, like the scoreboard cards). Shared: ML.DungeonArt.
local artBanner = ML.DungeonArt

----------------------------------------------------------------------
-- Persistent 3D model panel (survives the builder's per-render Reset; reparented if the window rebuilds).
----------------------------------------------------------------------
local modelPanel
local function ensureModel(b)
    if not modelPanel then
        local mp = b.theme:UnitModel(b.content, { width = 220, height = 300, rotatable = true, background = "dusk" })
        -- Show a creature by npc id (not a unit). Re-applied on model-refresh events so it doesn't revert.
        -- A PlayerModel handed a creature while it has stayed continuously shown often renders NOTHING
        -- until it passes through a hide->show transition. That is exactly why "click away and back" fixed
        -- it: leaving the guide hides this panel (Guide.Hide), returning shows it - a real transition. On a
        -- first in-place selection there is no such transition (the panel was already shown, so the render's
        -- mp:Show() is a no-op), so the creature is set but never painted. Reproduce the transition on the
        -- model itself: apply the creature, hide the model now, show it next frame. Guarded so a rapid
        -- re-selection doesn't reshow a stale creature.
        function mp:SetCreatureId(npcId)
            self._creatureId = npcId
            local m = self.model
            if not m then return end
            if m.ClearModel then pcall(m.ClearModel, m) end
            if npcId and m.SetCreature then pcall(m.SetCreature, m, npcId) end
            if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
            if m.SetFacing then pcall(m.SetFacing, m, self._facing or 0.5) end
            if npcId then
                m:Hide()
                C_Timer.After(0, function() if self._creatureId == npcId then m:Show() end end)
            end
        end
        local origRefresh = mp.Refresh
        function mp:Refresh() if self._creatureId then self:SetCreatureId(self._creatureId) else origRefresh(self) end end
        modelPanel = mp
    end
    if modelPanel:GetParent() ~= b.content then modelPanel:SetParent(b.content) end
    return modelPanel
end

-- Pooled spell-icon buttons: theme:GameIcon draws the spell icon AND shows the native Blizzard spell
-- tooltip on hover. They persist across the builder's per-render Reset; each render re-points them at a
-- spell and repositions them, and leftovers are hidden. Sit above the row hit-region so the icon's own
-- tooltip wins over the row's info tip.
local iconPool, iconUsed = {}, 0
local function iconButton(b, x, y, size, e, win)
    iconUsed = iconUsed + 1
    local btn = iconPool[iconUsed]
    if not btn then
        btn = b.theme:GameIcon(b.content, { size = size, tooltipAnchor = "ANCHOR_RIGHT" })
        iconPool[iconUsed] = btn
    end
    if btn:GetParent() ~= b.content then btn:SetParent(b.content) end
    if btn.SetFrameLevel then btn:SetFrameLevel((b.content:GetFrameLevel() or 1) + 10) end
    btn:SetSpell(e.id)
    btn:SetSize(size, size)
    btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", b.content, "TOPLEFT", x, y)
    btn._e = e
    btn:SetScript("OnMouseUp", function(self)   -- clicking the icon also selects the caster
        local ee = self._e
        state.sel = { id = ee.id, npcId = ee.npcId, name = ee.name, npc = ee.npc, tier = normTier(ee.tier) }
        if win then win:Refresh() end
    end)
    btn:Show()
    return btn
end
local function hideIconsFrom(n) for i = n + 1, #iconPool do if iconPool[i] then iconPool[i]:Hide() end end end

-- Hide the model + icons when we navigate away from this page (its content frame is reused elsewhere).
function Guide.Hide()
    if modelPanel then modelPanel:Hide() end
    for _, btn in ipairs(iconPool) do btn:Hide() end
end

-- Programmatic navigation from elsewhere (e.g. the run review's interrupt/dispel breakdown): select this
-- dungeon + spell in the guide and open the manager to the guide page. `entry` is a catalog row
-- ({ id, name, tier, npc, npcId }). Safe to call with a spell from any dungeon in the season profile.
function Guide.SelectAndOpen(dungeonName, entry)
    if not (entry and entry.id) then return end
    local Cfg = ML.Scoring and ML.Scoring.Config
    local key = Cfg and Cfg.NormDungeon and Cfg.NormDungeon(dungeonName)
    if key then state.dungeon = key; state.selDungeon = key end   -- keep our sel (render won't reset it)
    state.sel = { id = entry.id, npcId = entry.npcId, name = entry.name, npc = entry.npc, tier = normTier(entry.tier) }
    if _G.TAP and _G.TAP.OpenWindow then _G.TAP:OpenWindow("mod:dungeonGuide") end
end

----------------------------------------------------------------------
-- Rendering.
----------------------------------------------------------------------
-- One spell row: icon + name + caster/type subline + tier badge; whole row hover-tips + click-selects.
-- Returns the next y.
local function spellRow(b, C, x, y, w, e, kind, win)
    local rowH = 36
    local tiers = (kind == "kick") and KICK_TIERS or DISPEL_TIERS
    local tier = normTier(e.tier)
    local ti = tierInfo(tiers, tier)
    local selected = state.sel and e.id and state.sel.id == e.id

    if selected then b:Box(x, y, w, rowH, 0.16, 0, C.accent) end

    -- Hover tooltip.
    local lines = {
        { left = "Caster", right = (e.npc and e.npc ~= "") and e.npc or "?" },
        { left = (kind == "kick") and "Priority" or "Dispel priority", right = tier, rcolor = ti.color },
    }
    if e.dtype and e.dtype ~= "" and e.dtype ~= "?" then lines[#lines + 1] = { left = "Type", right = e.dtype } end
    if e.id then lines[#lines + 1] = { left = "Spell ID", right = tostring(e.id) } end
    if kind == "dispel" and e.counts then
        lines[#lines + 1] = { blank = true }
        lines[#lines + 1] = { text = "Counted toward the dispel score.", color = "subtext" }
    end
    lines[#lines + 1] = { blank = true }
    lines[#lines + 1] = { text = e.npcId and "Click to view the caster's model." or "No model available for this caster.", color = "subtext" }

    b:Row(x, y, w, rowH, {
        tipData = { icon = spellTex(e.id), minWidth = 260, title = e.name or ("Spell " .. tostring(e.id)), lines = lines },
        onClick = function()
            state.sel = { id = e.id, npcId = e.npcId, name = e.name, npc = e.npc, tier = tier }
            if win then win:Refresh() end
        end,
    })

    iconButton(b, x + 3, y - 5, 26, e, win)   -- real spell icon + native Blizzard tooltip on hover
    b:Label(e.name or ("Spell " .. tostring(e.id)), x + 35, y - 4, C.text, 12)

    local sub = (e.npc and e.npc ~= "") and e.npc or ""
    if kind == "dispel" and e.dtype and e.dtype ~= "" and e.dtype ~= "?" then
        local first = e.dtype:match("^(%a+)")
        local sc = (first and SCHOOL_COLOR[first]) or "8b8b8b"
        sub = (sub ~= "" and (sub .. "  ·  ") or "") .. "|cff" .. sc .. e.dtype .. "|r"
    end
    if sub ~= "" then b:Label(sub, x + 35, y - 21, C.subtext, 10) end

    -- Tier chip (a small colored dot + label) in a fixed right-hand zone (wide rows -> no name overlap).
    b:Box(x + w - 142, y - 13, 9, 9, 1, 0, TAP.toColor(ti.color))
    b:Label("|cff" .. ti.color .. tier .. "|r", x + w - 128, y - 9, C.text, 11)
    return y - rowH
end

-- One titled, tier-sorted column of kicks or dispels. Returns the next y.
local function drawList(b, C, x, y, w, title, entries, kind, win)
    b:Label(title, x, y, C.accent, 12)
    b:Label((entries and #entries or 0) .. " catalogued", x + w - 96, y, C.subtext, 10)
    y = y - 8
    b:Box(x, y, w, 1, 0.5, 0, C.border or C.subtext)
    y = y - 12
    if not entries or #entries == 0 then
        b:Label("None catalogued for this dungeon.", x, y - 4, C.subtext, 11)
        return y - 24
    end
    local tiers = (kind == "kick") and KICK_TIERS or DISPEL_TIERS
    local sorted = {}
    for _, e in ipairs(entries) do sorted[#sorted + 1] = e end
    table.sort(sorted, function(a, c)
        local oa, oc = tierInfo(tiers, normTier(a.tier)).order, tierInfo(tiers, normTier(c.tier)).order
        if oa ~= oc then return oa < oc end
        return (a.name or "") < (c.name or "")
    end)
    for _, e in ipairs(sorted) do y = spellRow(b, C, x, y, w, e, kind, win) end
    return y
end

-- Pick a sensible default selection for a dungeon: its top-priority kick that has a model.
local function defaultSel(d)
    local best
    for _, e in ipairs(d.kicks or {}) do
        if e.npcId then
            local o = tierInfo(KICK_TIERS, normTier(e.tier)).order
            if not best or o < best.o then best = { o = o, e = e } end
        end
    end
    local e = best and best.e or (d.kicks and d.kicks[1])
    if e then return { id = e.id, npcId = e.npcId, name = e.name, npc = e.npc, tier = normTier(e.tier) } end
end

-- The page. Signature matches a module Settings render: (mod, b, x, y, w, win).
local function renderGuide(mod, b, x, y, w, win)
    local C = b.theme.C
    local Cfg = ML.Scoring and ML.Scoring.Config
    local prof = Cfg and Cfg.SeasonProfile and Cfg.SeasonProfile()
    if not (prof and prof.dungeons) then
        b:Wrap("No season utility data is loaded yet - open this once you're in a Mythic+ season.", x, y, w - 20, C.subtext, 12)
        Guide.Hide()
        return y - 30
    end
    iconUsed = 0   -- start a fresh pass over the pooled spell-icon buttons

    -- Build + sort the dungeon list; keep a valid selection.
    local list = {}
    for key, d in pairs(prof.dungeons) do
        list[#list + 1] = { key = key, name = d.name or DISPLAY[key] or key, data = d }
    end
    table.sort(list, function(a, c) return a.name < c.name end)
    if not (state.dungeon and prof.dungeons[state.dungeon]) then state.dungeon = list[1] and list[1].key end

    local d = prof.dungeons[state.dungeon]
    local curName = (d and (d.name or DISPLAY[state.dungeon])) or state.dungeon
    -- Reset the model selection whenever the dungeon changes.
    if state.selDungeon ~= state.dungeon then state.sel = defaultSel(d); state.selDungeon = state.dungeon end

    -- ART BANNER with the dungeon name overlaid.
    local bannerH = 66
    local bg = ML.API and ML.API.DungeonBackground and ML.API.DungeonBackground(curName)
    artBanner(b, x, y, w, bannerH, bg, 0.55)
    b:Box(x, y, w, bannerH, bg and 0.35 or 0.5, 0, { 0.04, 0.043, 0.063 })   -- scrim so text reads over the art
    b:Label(prof.label or "Dungeon Guide", x + 16, y - 14, C.accent, 11)
    b:Heading(curName, x + 16, y - 26, "h2")
    y = y - bannerH - 12

    -- Dungeon picker.
    b:Label("Dungeon", x, y, C.subtext)
    local choices = {}
    for _, dd in ipairs(list) do choices[#choices + 1] = { dd.key, dd.name } end
    b:Dropdown(x + 66, y):SetChoices(260, choices, function() return state.dungeon end,
        function(v) state.dungeon = v; if win then win:Refresh() end end)
    b:Label("Click a spell to preview the caster - drag the model to spin it.", x + 340, y, C.subtext, 10)
    y = y - 42

    -- MODEL PANEL (right) + caption; LISTS (left, two columns).
    local panelW = 226
    local listW = math.max(320, w - panelW - 16)
    local mp = ensureModel(b)
    mp:ClearAllPoints(); mp:SetPoint("TOPLEFT", b.content, "TOPLEFT", x + listW + 16, y); mp:Show()
    mp:SetCreatureId(state.sel and state.sel.npcId)

    -- Caption under the model.
    local capX, capY = x + listW + 16, y - 308
    if state.sel then
        b:Label(state.sel.npc or "Unknown caster", capX, capY, C.text, 13)
        b:Label("casts |cffffffff" .. (state.sel.name or "?") .. "|r", capX, capY - 18, C.subtext, 11)
        if not state.sel.npcId then b:Label("(no model on record)", capX, capY - 34, C.subtext, 10) end
    else
        b:Label("Click a spell to preview its caster.", capX, capY, C.subtext, 11)
    end

    -- Full-width, STACKED lists (side-by-side columns are too narrow for name + tier badge).
    local ly = drawList(b, C, x, y, listW, "INTERRUPTS", d.kicks, "kick", win)
    ly = drawList(b, C, x, ly - 18, listW, "DISPELS", d.dispels, "dispel", win)
    hideIconsFrom(iconUsed)   -- hide any pooled icon buttons this pass didn't use
    return math.min(ly, capY - 40) - 12
end

Guide.Render = renderGuide

----------------------------------------------------------------------
-- Register as its own left-menu entry (under Modules). Read-only, so it always renders (even "disabled")
-- and has no lifecycle of its own beyond hiding the persistent model frame when you navigate away.
----------------------------------------------------------------------
Suite:RegisterModule({
    id       = "dungeonGuide",
    title    = "Dungeon Guide",
    desc     = "Per-dungeon interrupt & dispel priorities for the current Mythic+ season - what to kick, "
            .. "what to dispel, and a 3D preview of the casters. Built from the Ledger's season catalog; reference only.",
    icon     = "clipboard",
    addon    = ML.ADDON,
    default  = true,
    group      = "Mythic Ledger",   -- share the addon category with the main Ledger module
    groupOrder = 2,
    rendersWhenDisabled = true,     -- pure reference: always viewable
    OnEnable   = function() end,
    OnDisable  = function() end,
    OnSelect   = function() end,
    OnDeselect = function() Guide.Hide() end,
    -- navOrder slots this row directly under the Ledger's Overview (key 101) instead of after its whole
    -- page list. The Ledger is groupOrder 1, so Overview = 1*100+1 = 101 and Runs = 102; 101.5 sits between.
    pages = { { id = "guide", label = "Dungeon Guide", icon = "clipboard", default = true,
                disabledSafe = true, navOrder = 101.5, render = renderGuide } },
})
