-- TAP - Movers.lua
-- The platform-wide frame placement system.
--
-- Every add-on on the platform used to grow its own mover: Rotation Assistant had a placement mode,
-- Combat Alerts had per-rule drag ghosts, Mythic Ledger had StartMove/StopMove on two overlays,
-- Focus Interrupt let you drag the palette directly, and each one drew its own Save/Cancel bar.
-- Same idea four times, four sets of bugs, and no way to lay the whole UI out in one sitting.
--
-- This replaces all of it. A sidecar REGISTERS each movable thing:
--
--     TAP:RegisterMover({
--         id      = "mythicLedger:livecoach",  -- unique, stable
--         owner   = "Mythic Ledger",           -- group heading on the Movers page
--         ownerId = "mythicLedger",            -- platform module id (optional; enables the on/off note)
--         label   = "Live Coach",
--         icon    = "message-2",
--         Get     = function() return point, x, y end,     -- REQUIRED
--         Set     = function(point, x, y) end,             -- REQUIRED
--         frame   = frameOrFunction,           -- live frame, for ghost size + strata
--         size    = function() return w, h end,-- fallback size when the frame is hidden/absent
--         scale   = function() return n end,   -- the element's own scale, so the ghost matches it
--         Preview = function(on) end,          -- show a demo while placing (optional)
--         defaults= { point = "CENTER", x = 0, y = 0 },    -- for Reset
--     })
--
-- Persistence stays with the module: Get/Set read and write the sidecar's own SavedVariables, so
-- nothing here needs migrating and each add-on keeps owning its data.
--
-- Placement mode hides the manager window, drops a labelled drag ghost over every registered
-- element, and shows one control bar with Done / Cancel / Reset. The real element follows the
-- ghost live while you drag, so you are positioning the thing itself and not a stand-in. Done or
-- Escape keeps the new positions; Cancel restores every position captured when the session began.

local ADDON, TAP = ...
local Suite = TAP

----------------------------------------------------------------------
-- Registry.
----------------------------------------------------------------------
TAP._movers   = {}     -- id -> spec
TAP._moverIDs = {}     -- array of ids, registration order (stable secondary sort)

local function moverTheme()
    -- Resolved lazily: this file loads BEFORE SuiteManager (which owns the manager window and
    -- therefore has to be able to reference the Movers page), so the shared theme does not exist
    -- yet at load time. Every chrome build happens on demand, long after login.
    return TAP.uiTheme
end

local function resolveFrame(spec)
    local f = spec.frame
    if type(f) == "function" then
        local ok, res = pcall(f)
        return ok and res or nil
    end
    return f
end

local function moverScale(spec)
    if type(spec.scale) == "function" then
        local ok, s = pcall(spec.scale)
        if ok and type(s) == "number" and s > 0 then return s end
    end
    local f = resolveFrame(spec)
    if f and f.GetScale then return f:GetScale() or 1 end
    return 1
end

-- Read a mover's stored anchor, normalised. A Get that errors or returns junk degrades to the
-- spec defaults rather than taking the session down with it.
local function moverGet(spec)
    local ok, p, x, y = pcall(spec.Get)
    local d = spec.defaults or {}
    if not ok or type(p) ~= "string" then
        return d.point or "CENTER", tonumber(d.x) or 0, tonumber(d.y) or 0
    end
    return p, tonumber(x) or 0, tonumber(y) or 0
end

local function moverSet(spec, p, x, y)
    local ok, err = pcall(spec.Set, p, x, y)
    if not ok then geterrorhandler()(("TAP: mover '%s' Set failed: %s"):format(spec.id, tostring(err))) end
end

function Suite:RegisterMover(spec)
    assert(type(spec) == "table" and spec.id, "RegisterMover: spec.id is required")
    assert(type(spec.Get) == "function" and type(spec.Set) == "function",
        "RegisterMover: Get and Set are required")
    if not TAP._movers[spec.id] then TAP._moverIDs[#TAP._moverIDs + 1] = spec.id end
    TAP._movers[spec.id] = spec
    return spec
end

function Suite:UnregisterMover(id)
    if not TAP._movers[id] then return end
    TAP._movers[id] = nil
    for i, v in ipairs(TAP._moverIDs) do
        if v == id then table.remove(TAP._moverIDs, i); break end
    end
    local g = TAP._moverGhosts and TAP._moverGhosts[id]
    if g then g:Hide() end
end

-- Drop every mover an owner registered, so a sidecar with a DYNAMIC set (per-rule alerts, per-
-- group displays) can re-register from scratch whenever its list changes.
function Suite:UnregisterMoversFor(ownerId)
    for _, id in ipairs({ unpack(TAP._moverIDs) }) do
        local spec = TAP._movers[id]
        if spec and spec.ownerId == ownerId then self:UnregisterMover(id) end
    end
end

function Suite:GetMover(id) return TAP._movers[id] end

-- All movers, grouped and ordered for display: owner A-Z, then the spec's own `order`, then label.
function Suite:GetMovers()
    local out = {}
    for i, id in ipairs(TAP._moverIDs) do
        local spec = TAP._movers[id]
        if spec then spec._seq = i; out[#out + 1] = spec end
    end
    table.sort(out, function(a, b)
        local ao, bo = a.owner or "", b.owner or ""
        if ao ~= bo then return ao < bo end
        local an, bn = a.order or 100, b.order or 100
        if an ~= bn then return an < bn end
        return a._seq < b._seq
    end)
    return out
end

function Suite:MoverReset(id)
    local spec = TAP._movers[id]
    if not spec then return end
    local d = spec.defaults or {}
    moverSet(spec, d.point or "CENTER", tonumber(d.x) or 0, tonumber(d.y) or 0)
    if spec.OnChange then pcall(spec.OnChange) end
    if TAP._placing then TAP._syncGhosts() end
end

function Suite:MoverSet(id, p, x, y)
    local spec = TAP._movers[id]
    if not spec then return end
    local cp, cx, cy = moverGet(spec)
    moverSet(spec, p or cp, x == nil and cx or x, y == nil and cy or y)
    if spec.OnChange then pcall(spec.OnChange) end
    if TAP._placing then TAP._syncGhosts() end
end

function Suite:MoverGet(id)
    local spec = TAP._movers[id]
    if not spec then return nil end
    return moverGet(spec)
end

----------------------------------------------------------------------
-- Anchor maths.
--
-- A mover stores its offset as `frame:SetPoint(P, UIParent, P, x, y)`. To turn a dragged ghost
-- back into that offset we compare the ghost's P-corner with UIParent's P-corner in SCREEN
-- space, then express the difference in the ghost's own scaled space - which is what SetPoint
-- offsets are measured in. Doing it generally (rather than assuming CENTER) is what lets a
-- module anchor to a corner and still drag correctly.
----------------------------------------------------------------------
local function pointCoords(f, p)
    local l, bm, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    if not l or not bm then return nil end
    local x, y = l + w / 2, bm + h / 2
    if p:find("LEFT")   then x = l
    elseif p:find("RIGHT") then x = l + w end
    if p:find("TOP")    then y = bm + h
    elseif p:find("BOTTOM") then y = bm end
    return x, y
end

local function offsetFromGhost(ghost, p)
    local gx, gy = pointCoords(ghost, p)
    local ux, uy = pointCoords(UIParent, p)
    if not gx or not ux then return nil end
    local gs, us = ghost:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not gs or gs <= 0 then return nil end
    return (gx * gs - ux * us) / gs, (gy * gs - uy * us) / gs
end

----------------------------------------------------------------------
-- Placement session.
--
-- Entering placement closes the config window and drops one translucent box per registered
-- element, sized to that element's real bounds. The box is the thing you grab; whether the
-- element itself is DRAWN inside it is a separate, toggleable "live preview" - per element from
-- the box's own eye button (or a right-click), and for everything at once from the control bar.
--
-- Why they are separate: most of these elements only exist in combat, and several of them
-- animate, pulse, or fade. Being able to drop back to plain boxes makes a crowded screen
-- readable and stops a flashing alert from fighting you for the cursor. Being able to turn one
-- back on lets you check a single element against the rest of your UI.
--
-- Bounds stay correct either way, because a size measured while the preview was up is cached
-- for the rest of the session and used once it goes back off.
----------------------------------------------------------------------
TAP._moverGhosts = {}
TAP._placing     = false

-- { ids, backup, view, snap, preview = {id->bool}, sizes = {id->{w,h}}, ticker }
local session = nil

local GHOST_COLORS = {
    { 0.63, 0.42, 0.94 },   -- suite violet
    { 0.36, 0.62, 0.94 },
    { 0.37, 0.82, 0.63 },
    { 0.92, 0.62, 0.28 },
    { 0.90, 0.40, 0.40 },
    { 0.40, 0.80, 0.85 },
}

local function ownerColor(spec, idx)
    if spec.color then return spec.color end
    return GHOST_COLORS[((idx - 1) % #GHOST_COLORS) + 1]
end

-- Snap ONE axis to the painted grid, in UIParent units and measured from screen centre - which
-- is exactly where the grid is drawn from. Snapping the stored OFFSET instead (the obvious thing,
-- and what this did first) is wrong twice over: the offset lives in the element's own scaled
-- space, so a scaled element lands at size*scale screen pixels, and it is measured from the
-- element's anchor point, which for anything but CENTER is not where the lines start. Both showed
-- up as boxes sitting a few pixels off the lines.
local function snapAxis(v, centre, size)
    return centre + math.floor((v - centre) / size + 0.5) * size
end

-- The grid pitch currently in force, or nil when snapping is off.
local function snapPitch()
    if not (session and session.snap) then return nil end
    return session.snap
end

----------------------------------------------------------------------
-- Bounds.
--
-- Preferred order: the live frame while it is actually drawn, then whatever we measured earlier
-- this session, then the spec's declared size, then a placeholder. That ordering is what lets
-- the box keep the element's real footprint after you switch its preview off.
----------------------------------------------------------------------
local function measure(spec)
    local f = resolveFrame(spec)
    if f and f.GetWidth and f:IsShown() then
        local w, h = f:GetWidth(), f:GetHeight()
        if w and h and w > 1 and h > 1 then return w, h, true end
    end
    local cached = session and session.sizes[spec.id]
    if cached then return cached[1], cached[2], false end
    if f and f.GetWidth then
        local w, h = f:GetWidth(), f:GetHeight()
        if w and h and w > 1 and h > 1 then return w, h, false end
    end
    if type(spec.size) == "function" then
        local ok, w, h = pcall(spec.size)
        if ok and type(w) == "number" and type(h) == "number" and w > 1 and h > 1 then
            return w, h, false
        end
    end
    return 140, 36, false
end

----------------------------------------------------------------------
-- Preview toggles.
----------------------------------------------------------------------
local function isPreview(id) return session and session.preview[id] and true or false end

local function setPreview(id, on)
    if not session then return end
    local spec = TAP._movers[id]
    if not spec then return end
    on = on and true or false
    if session.preview[id] == on then return end
    session.preview[id] = on
    if spec.Preview then pcall(spec.Preview, on) end
    -- The element needs a frame to lay itself out before it can be measured, so the size is
    -- re-read on the next sync rather than right now.
    TAP._syncGhosts()
end

local function setPreviewAll(on)
    if not session then return end
    for _, id in ipairs(session.ids) do setPreview(id, on) end
    TAP._refreshBar()
end

----------------------------------------------------------------------
-- Selection and keyboard nudging.
--
-- Dragging is fine for roughing a layout out and hopeless for the last few pixels. Click a box to
-- select it, then the arrow keys walk it: by the grid pitch when a grid is on (so it steps line to
-- line), otherwise a pixel at a time. Shift forces single pixels regardless, Ctrl takes bigger
-- strides, Tab cycles which box is selected.
--
-- The step is applied in UIParent space, exactly like snapping, so a scaled element still moves in
-- screen pixels rather than its own scaled ones.
----------------------------------------------------------------------
local function selectMover(id)
    if not session then return end
    if session.selected == id then return end
    session.selected = id
    TAP._syncGhosts()
    TAP._refreshBar()
end

local function cycleSelection(back)
    if not session or #session.ids == 0 then return end
    local cur = session.selected
    local idx
    for i, id in ipairs(session.ids) do if id == cur then idx = i; break end end
    if not idx then idx = back and 1 or #session.ids end
    local nextIdx = back and (idx - 1) or (idx + 1)
    if nextIdx < 1 then nextIdx = #session.ids elseif nextIdx > #session.ids then nextIdx = 1 end
    selectMover(session.ids[nextIdx])
end

local function nudge(dx, dy)
    if not (session and session.selected) then return false end
    local spec = TAP._movers[session.selected]
    local g = TAP._moverGhosts[session.selected]
    if not (spec and g) then return false end

    local p = select(1, moverGet(spec))
    local gx, gy = pointCoords(g, p)
    if not gx then return false end
    local gs, us = g:GetEffectiveScale(), UIParent:GetEffectiveScale()

    -- Current anchor position in UIParent units, stepped, then snapped to the visible grid.
    local nx = gx * gs / us + dx
    local ny = gy * gs / us + dy
    local pitch = snapPitch()
    if pitch then
        nx = snapAxis(nx, UIParent:GetWidth() / 2, pitch)
        ny = snapAxis(ny, UIParent:GetHeight() / 2, pitch)
    end

    local ax, ay = pointCoords(UIParent, p)
    moverSet(spec, p,
        math.floor((nx - ax) * us / gs + 0.5),
        math.floor((ny - ay) * us / gs + 0.5))
    if spec.OnChange then pcall(spec.OnChange) end
    TAP._syncGhosts()
    return true
end

-- How far one arrow press moves. Following the grid by default is what makes the keyboard useful
-- for alignment rather than just a slower mouse.
local function nudgeStep()
    if IsShiftKeyDown and IsShiftKeyDown() then return 1 end
    local pitch = snapPitch()
    local base = pitch or 1
    if IsControlKeyDown and IsControlKeyDown() then return pitch and (pitch * 4) or 10 end
    return base
end

local function previewCount()
    if not session then return 0, 0 end
    local n = 0
    for _, id in ipairs(session.ids) do if session.preview[id] then n = n + 1 end end
    return n, #session.ids
end

----------------------------------------------------------------------
-- Ghosts.
----------------------------------------------------------------------
local function ensureGhost(id)
    local g = TAP._moverGhosts[id]
    if g then return g end
    g = CreateFrame("Frame", nil, UIParent)
    -- FULLSCREEN sits above HUD elements (MEDIUM/HIGH) but below the control bar, which is on
    -- FULLSCREEN_DIALOG - so a ghost can never cover the only way out of placement mode.
    g:SetFrameStrata("FULLSCREEN")
    -- Not SetMovable/SetClampedToScreen: the drag is driven by hand (see OnDragStart below) so
    -- it can snap mid-drag, and the clamp is applied to the anchor point ourselves.
    g:EnableMouse(true)
    g:RegisterForDrag("LeftButton")

    g.bg = g:CreateTexture(nil, "BACKGROUND"); g.bg:SetAllPoints()
    g.edge = {}
    for i = 1, 4 do g.edge[i] = g:CreateTexture(nil, "BORDER") end
    g.edge[1]:SetPoint("TOPLEFT");    g.edge[1]:SetPoint("TOPRIGHT");    g.edge[1]:SetHeight(2)
    g.edge[2]:SetPoint("BOTTOMLEFT"); g.edge[2]:SetPoint("BOTTOMRIGHT"); g.edge[2]:SetHeight(2)
    g.edge[3]:SetPoint("TOPLEFT");    g.edge[3]:SetPoint("BOTTOMLEFT");  g.edge[3]:SetWidth(2)
    g.edge[4]:SetPoint("TOPRIGHT");   g.edge[4]:SetPoint("BOTTOMRIGHT"); g.edge[4]:SetWidth(2)

    -- Label above the box rather than inside it, so a live preview underneath stays readable.
    g.label = g:CreateFontString(nil, "OVERLAY")
    g.label:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 0, 3)
    g.coords = g:CreateFontString(nil, "OVERLAY")
    g.coords:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -3)

    -- Per-element preview toggle. A visible button because right-click alone is not
    -- discoverable, and right-click as well because the button is tiny on a small element.
    g.eye = CreateFrame("Button", nil, g)
    g.eye:SetSize(18, 18)
    g.eye:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", 0, 2)
    g.eye.tex = g.eye:CreateTexture(nil, "OVERLAY")
    g.eye.tex:SetAllPoints()
    g.eye:SetScript("OnClick", function(self)
        local gg = self:GetParent()
        setPreview(gg._id, not isPreview(gg._id))
        TAP._refreshBar()
    end)
    g.eye:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(isPreview(self:GetParent()._id) and "Hide live preview" or "Show live preview")
        GameTooltip:AddLine("Right-click the box does the same.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    g.eye:SetScript("OnLeave", GameTooltip_Hide)

    -- Right-click anywhere on the box toggles its preview. OnMouseUp rather than OnClick because
    -- the ghost is a Frame, and RegisterForClicks / OnClick are Button-only.
    g:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            setPreview(self._id, not isPreview(self._id))
            TAP._refreshBar()
        else
            selectMover(self._id)
        end
    end)

    -- Dragging is driven by hand rather than by StartMoving, because StartMoving owns the frame's
    -- position for the duration and cannot be snapped mid-drag - you would only ever see the box
    -- jump to the grid on release. Tracking the cursor ourselves means the box CLICKS onto the
    -- grid as you move it, which is the whole point of having one.
    g:SetScript("OnDragStart", function(self)
        local us = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        local gs = self:GetEffectiveScale()
        local gx, gy = pointCoords(self, self._point or "CENTER")
        if not gx then return end
        self._grabCursor = { mx / us, my / us }                 -- UIParent units
        self._grabAnchor = { gx * gs / us, gy * gs / us }       -- ditto
        self._dragging = true
        selectMover(self._id)   -- what you just grabbed is what the arrow keys should move
    end)
    g:SetScript("OnDragStop", function(self)
        self._dragging = false
        TAP._commitGhost(self)
        TAP._syncGhosts()
    end)
    -- While dragging: move the box every frame (so it feels attached to the cursor) but only push
    -- the position into the module on a throttle, since Set can be expensive - a group relayout,
    -- an overlay rebuild. The real element still visibly follows.
    g:SetScript("OnUpdate", function(self, elapsed)
        if not self._dragging or not self._grabCursor then return end
        local us = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        local nx = self._grabAnchor[1] + (mx / us - self._grabCursor[1])
        local ny = self._grabAnchor[2] + (my / us - self._grabCursor[2])

        local pitch = snapPitch()
        if pitch then
            nx = snapAxis(nx, UIParent:GetWidth() / 2, pitch)
            ny = snapAxis(ny, UIParent:GetHeight() / 2, pitch)
        end
        -- Keep the anchor point on screen so a box can never be flung somewhere unrecoverable.
        nx = math.max(0, math.min(UIParent:GetWidth(), nx))
        ny = math.max(0, math.min(UIParent:GetHeight(), ny))

        local p = self._point or "CENTER"
        local ax, ay = pointCoords(UIParent, p)
        local gs = self:GetEffectiveScale()
        local ox = math.floor((nx - ax) * us / gs + 0.5)
        local oy = math.floor((ny - ay) * us / gs + 0.5)
        self._dragOffset = { ox, oy }

        self:ClearAllPoints()
        self:SetPoint(p, UIParent, p, ox, oy)
        if self.coords then self.coords:SetText(("%s  %d, %d"):format(p, ox, oy)) end

        self._acc = (self._acc or 0) + elapsed
        if self._acc < 0.03 then return end
        self._acc = 0
        TAP._commitGhost(self, true)
    end)
    -- Created frames start SHOWN. A brand-new ghost has no size or position yet, so it is parked
    -- hidden and _syncGhosts is what puts it on screen once it has both.
    g:Hide()
    TAP._moverGhosts[id] = g
    return g
end

-- Write a ghost's current screen position back through its mover's Set.
function TAP._commitGhost(ghost, live)
    local spec = ghost and ghost._spec
    if not spec then return end
    local p = ghost._point or "CENTER"
    -- Prefer the offset the drag handler just computed: it is already snapped and already in the
    -- element's space. Re-deriving it from the frame would re-round what was exact.
    local x, y
    if ghost._dragOffset then
        x, y = ghost._dragOffset[1], ghost._dragOffset[2]
    else
        x, y = offsetFromGhost(ghost, p)
        if not x then return end
        x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    end
    moverSet(spec, p, x, y)
    if spec.OnChange then pcall(spec.OnChange) end
    if not live then ghost._dragOffset = nil end
end

-- Re-read every mover and put its box back exactly over the element, at the element's current
-- bounds. Called after a drag, a reset, a preview toggle, an edit from the Movers page, and on a
-- slow ticker - elements resize as their contents change (a group gains a bar, an alert swaps
-- text), and a box that does not follow is a box that lies about what you are positioning.
function TAP._syncGhosts()
    if not session then return end
    local t = moverTheme()
    local font = (t and t.FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

    for idx, id in ipairs(session.ids) do
        local spec = TAP._movers[id]
        local g = TAP._moverGhosts[id]
        if spec and g and not g._dragging then
            local p, x, y = moverGet(spec)
            local w, h, live = measure(spec)
            if live then session.sizes[id] = { w, h } end   -- true bounds: keep them for later
            local sc = moverScale(spec)
            local on = isPreview(id)

            g._spec, g._point, g._id = spec, p, id
            g:SetScale(sc)
            g:SetSize(w, h)
            g:ClearAllPoints()
            g:SetPoint(p, UIParent, p, x, y)

            -- The box is drawn at the element's true bounds, but a 20px icon is miserable to
            -- grab, so the CLICK area is expanded outward instead of inflating the box itself.
            local padX = math.max(0, (56 - w) / 2)
            local padY = math.max(0, (26 - h) / 2)
            g:SetHitRectInsets(-padX, -padX, -padY, -padY)

            local col = ownerColor(spec, idx)
            local sel = (session.selected == id)
            -- Fainter fill while previewing, so the element underneath stays legible. The selected
            -- box is the one the arrow keys move, so it has to be obvious at a glance: brighter
            -- fill, a thicker edge, and a white label rather than the owner tint.
            g.bg:SetColorTexture(col[1], col[2], col[3], (on and 0.10 or 0.24) + (sel and 0.14 or 0))
            local edgeA = sel and 1 or 0.6
            local edgeW = sel and 3 or 2
            for i = 1, 4 do
                g.edge[i]:SetColorTexture(col[1], col[2], col[3], edgeA)
            end
            g.edge[1]:SetHeight(edgeW); g.edge[2]:SetHeight(edgeW)
            g.edge[3]:SetWidth(edgeW);  g.edge[4]:SetWidth(edgeW)

            g.label:SetFont(font, 12, "OUTLINE")
            if sel then g.label:SetTextColor(1, 1, 1) else g.label:SetTextColor(col[1], col[2], col[3]) end
            g.label:SetText(((sel and "> %s - %s") or "%s - %s"):format(spec.owner or "?", spec.label or spec.id))
            g.coords:SetFont(font, 11, "OUTLINE")
            g.coords:SetTextColor(1, 1, 1, 0.75)
            g.coords:SetText(("%s  %d, %d  -  %d x %d"):format(p, x, y, math.floor(w + 0.5), math.floor(h + 0.5)))

            g.eye.tex:SetTexture(t and t:ResolveIcon(on and "eye" or "eye-off") or nil)
            g.eye.tex:SetVertexColor(col[1], col[2], col[3], on and 1 or 0.6)
            g:Show()
        end
    end
end

----------------------------------------------------------------------
-- The alignment grid.
--
-- Drawn outward FROM SCREEN CENTRE rather than from a corner, because every offset a mover
-- stores is relative to its UIParent anchor - so an element parked at 0,0 lands exactly on the
-- centre cross. That makes the grid a real alignment tool instead of decoration.
--
-- On BACKGROUND strata: above the world, below every add-on's frames, so previewed elements and
-- the drag boxes both read clearly over it.
----------------------------------------------------------------------
----------------------------------------------------------------------
-- The dim layer.
--
-- BACKGROUND strata: over the 3D world, under every add-on's frames. That is deliberate - the
-- noise you want gone while laying out a UI is the world behind it, and dimming ABOVE the UI
-- would grey out the very previews you are positioning against.
----------------------------------------------------------------------
local dimFrame

local function paintDim()
    if not dimFrame then
        dimFrame = CreateFrame("Frame", nil, UIParent)
        dimFrame:SetFrameStrata("BACKGROUND")
        dimFrame:SetAllPoints(UIParent)
        dimFrame.tex = dimFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        dimFrame.tex:SetAllPoints()
        dimFrame.tex:SetColorTexture(0, 0, 0, 0.82)
        dimFrame:Hide()
    end
    dimFrame:SetShown(session and session.dim and true or false)
end

local GRID_SIZES = { 8, 16, 32, 64, 128 }
local GRID_MAX_LINES = 420   -- a fine grid on a wide monitor is thousands of textures; cap it

local gridFrame

local function ensureGrid()
    if gridFrame then return gridFrame end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("BACKGROUND")
    g:SetFrameLevel(20)          -- above the dim, which sits at the default level
    g:SetAllPoints(UIParent)
    g.lines, g.used = {}, 0
    g:Hide()
    gridFrame = g
    return g
end

local function gridLine(g, i)
    local t = g.lines[i]
    if not t then t = g:CreateTexture(nil, "BACKGROUND"); g.lines[i] = t end
    return t
end

local function paintGrid()
    local g = ensureGrid()
    local size = session and session.grid
    if not size then
        for i = 1, g.used do g.lines[i]:Hide() end
        g.used = 0
        g:Hide()
        return
    end

    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    -- Coarsen rather than refuse: a grid too fine for the screen still gets you something useful.
    while (w / size + h / size) > GRID_MAX_LINES do size = size * 2 end

    local cx, cy = w / 2, h / 2
    local n = 0

    local function vline(x, centre)
        n = n + 1
        local t = gridLine(g, n)
        t:ClearAllPoints()
        t:SetPoint("TOP", g, "TOPLEFT", x, 0)
        t:SetPoint("BOTTOM", g, "BOTTOMLEFT", x, 0)
        t:SetWidth(1)
        if centre then t:SetColorTexture(0.63, 0.42, 0.94, 0.65)
        else t:SetColorTexture(1, 1, 1, 0.14) end
        t:Show()
    end
    local function hline(y, centre)
        n = n + 1
        local t = gridLine(g, n)
        t:ClearAllPoints()
        t:SetPoint("LEFT", g, "BOTTOMLEFT", 0, y)
        t:SetPoint("RIGHT", g, "BOTTOMRIGHT", 0, y)
        t:SetHeight(1)
        if centre then t:SetColorTexture(0.63, 0.42, 0.94, 0.65)
        else t:SetColorTexture(1, 1, 1, 0.14) end
        t:Show()
    end

    vline(cx, true)
    for k = 1, math.ceil(cx / size) do
        if cx - k * size >= 0 then vline(cx - k * size) end
        if cx + k * size <= w then vline(cx + k * size) end
    end
    hline(cy, true)
    for k = 1, math.ceil(cy / size) do
        if cy - k * size >= 0 then hline(cy - k * size) end
        if cy + k * size <= h then hline(cy + k * size) end
    end

    for i = n + 1, g.used do g.lines[i]:Hide() end
    g.used = n
    g:Show()
end

----------------------------------------------------------------------
-- The control bar: a slim single-line strip across the top of the screen.
--
-- Full width and out of the way at the top, rather than a panel parked over the middle of the
-- screen - the whole point of placement mode is seeing your layout, and the old box sat right
-- where a lot of people put things. FULLSCREEN_DIALOG + UISpecialFrames, so it is above every
-- drag box and Escape always gets you out.
----------------------------------------------------------------------
local bar
local BAR_H = 34

local function buildBar()
    local t = moverTheme()
    if not t then return nil end   -- no shared theme yet: caller aborts rather than half-building
    local f = CreateFrame("Frame", "TAP_MoverBar", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
    f:SetHeight(BAR_H)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    f:EnableMouse(true)   -- swallow clicks so the bar is never a hole through to the world

    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    f.rule = f:CreateTexture(nil, "BORDER")
    f.rule:SetPoint("BOTTOMLEFT"); f.rule:SetPoint("BOTTOMRIGHT"); f.rule:SetHeight(1)

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetPoint("LEFT", 14, 0)
    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetPoint("LEFT", f.title, "RIGHT", 12, 0)

    -- Laid out right to left, each control hung off the previous one's left edge, so the strip
    -- stays correct at any resolution without measuring anything.
    f.done   = t:Button(f); f.done:SetPoint("RIGHT", -12, 0)
    f.cancel = t:Button(f); f.cancel:SetPoint("RIGHT", f.done, "LEFT", -6, 0)
    f.reset  = t:Button(f); f.reset:SetPoint("RIGHT", f.cancel, "LEFT", -6, 0)

    f.snapLabel = f:CreateFontString(nil, "OVERLAY")
    f.snapLabel:SetPoint("RIGHT", f.reset, "LEFT", -16, 0)
    f.snap = t:Toggle(f)
    f.snap:SetPoint("RIGHT", f.snapLabel, "LEFT", -6, 0)

    f.gridDD = t:Dropdown(f)
    f.gridDD:SetPoint("RIGHT", f.snap, "LEFT", -16, 0)
    f.gridLabel = f:CreateFontString(nil, "OVERLAY")
    f.gridLabel:SetPoint("RIGHT", f.gridDD, "LEFT", -6, 0)

    f.dimLabel = f:CreateFontString(nil, "OVERLAY")
    f.dimLabel:SetPoint("RIGHT", f.gridLabel, "LEFT", -16, 0)
    f.dim = t:Toggle(f)
    f.dim:SetPoint("RIGHT", f.dimLabel, "LEFT", -6, 0)

    f.prevLabel = f:CreateFontString(nil, "OVERLAY")
    f.prevLabel:SetPoint("RIGHT", f.dim, "LEFT", -16, 0)
    f.prev = t:Toggle(f)
    f.prev:SetPoint("RIGHT", f.prevLabel, "LEFT", -6, 0)

    -- Keyboard for nudging. Propagation is re-enabled at the top of every keypress and only
    -- switched off for the keys we actually consume, so everything else - Escape, ability binds,
    -- movement - still reaches the game while placement mode is open.
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(true)
        if not session then return end
        local step = nudgeStep()
        local handled = false
        if     key == "LEFT"  then handled = nudge(-step, 0)
        elseif key == "RIGHT" then handled = nudge( step, 0)
        elseif key == "UP"    then handled = nudge(0,  step)
        elseif key == "DOWN"  then handled = nudge(0, -step)
        elseif key == "TAB"   then cycleSelection(IsShiftKeyDown and IsShiftKeyDown()); handled = true
        end
        if handled then self:SetPropagateKeyboardInput(false) end
    end)

    tinsert(UISpecialFrames, f:GetName())

    -- ORDER MATTERS. A freshly created frame starts SHOWN, so this Hide() fires OnHide - and
    -- buildBar runs from inside StartPlacement, which has already set up the session. Wiring the
    -- handler first meant the very first placement of each reload tore down the session it was
    -- still building, then indexed the nil it had just created. Hide first, wire second.
    f:Hide()

    -- Escape (or any other hide) finishes the session KEEPING what you dragged, matching the
    -- placement mode Rotation Assistant already had. Cancel is the explicit undo.
    f:SetScript("OnHide", function() Suite:StopPlacement(true) end)

    bar = f
    return f
end

-- Just the parts that change as you toggle things. Split out so a preview click does not rebuild
-- the whole bar.
function TAP._refreshBar()
    if not (bar and session and bar.prevLabel) then return end
    local on, total = previewCount()
    -- Re-Configure rather than poking .checked/_render: safe to call from inside the toggle's own
    -- callback, because Configure does not rewire OnClick.
    bar.prev:Configure(on == total and total > 0,
        function(v) setPreviewAll(v) end, { width = 34, height = 16 })
    if on == 0 then bar.prevLabel:SetText("Preview")
    elseif on == total then bar.prevLabel:SetText("Preview (all)")
    else bar.prevLabel:SetText(("Preview (%d/%d)"):format(on, total)) end

    -- The hint doubles as the selection readout: with the arrow keys in play you need to know
    -- which box they are pointed at without hunting for the highlighted one.
    local spec = session.selected and TAP._movers[session.selected]
    if spec then
        local pitch = snapPitch()
        bar.hint:SetText(("Selected: %s - %s   |   arrows nudge %s, shift 1px, ctrl bigger, tab cycles"):format(
            spec.owner or "?", spec.label or spec.id,
            pitch and (tostring(pitch) .. "px to the grid") or "1px"))
    else
        bar.hint:SetText(("%d element%s - drag a box to move it, click one to select it for the arrow keys, right-click to preview it."):format(
            #session.ids, #session.ids == 1 and "" or "s"))
    end
end

local function styleBar(count)
    local t = moverTheme()
    if not t then return end

    -- Controls first and UNGUARDED. These are the only way out of placement mode other than
    -- Escape, so they must not end up half-configured because a later cosmetic line threw.
    bar.done:Configure("Done", 74, 22, "primary", function() Suite:StopPlacement(true) end)
    bar.cancel:Configure("Cancel", 74, 22, "default", function() Suite:StopPlacement(false) end)
    bar.reset:Configure("Reset all", 80, 22, "danger", function()
        if not session then return end
        for _, id in ipairs(session.ids) do Suite:MoverReset(id) end
    end)
    bar.prev:Configure(false, function(v) setPreviewAll(v) end, { width = 34, height = 16 })
    bar.snap:Configure(session and session.snap ~= nil,
        function(v) if session then session.snap = v and (session.grid or 16) or nil end end,
        { width = 34, height = 16 })
    bar.dim:Configure(session and session.dim and true or false,
        function(v) if session then session.dim = v or nil; paintDim() end end,
        { width = 34, height = 16 })

    -- 0 rather than false/nil for "Off": a falsy menu value is one truthiness test away from
    -- being skipped, which is the same trap the nil-valued rows fell into elsewhere.
    local gridChoices = { { 0, "Off" } }
    for _, n in ipairs(GRID_SIZES) do gridChoices[#gridChoices + 1] = { n, tostring(n) .. " px" } end
    bar.gridDD:SetChoices(84, gridChoices,
        function() return (session and session.grid) or 0 end,
        function(v)
            if not session then return end
            session.grid = (type(v) == "number" and v > 0) and v or nil
            -- Snapping follows the painted grid: snapping to a different pitch than the one you
            -- can see would be actively misleading.
            if session.snap then session.snap = session.grid or 16 end
            paintGrid()
        end,
        { height = 22 })

    -- Cosmetics guarded: a theming hiccup must never leave the UI hidden with no way back.
    pcall(function()
        local C = t.C
        bar.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.94)
        bar.rule:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.85)
        local font = t.FONT
        bar.title:SetFont(font, 13); bar.title:SetTextColor(unpack(C.accent))
        bar.hint:SetFont(font, 11);  bar.hint:SetTextColor(unpack(C.subtext))
        bar.prevLabel:SetFont(font, 11); bar.prevLabel:SetTextColor(unpack(C.text))
        bar.gridLabel:SetFont(font, 11); bar.gridLabel:SetTextColor(unpack(C.text))
        bar.dimLabel:SetFont(font, 11);  bar.dimLabel:SetTextColor(unpack(C.text))
        bar.snapLabel:SetFont(font, 11); bar.snapLabel:SetTextColor(unpack(C.text))
        bar.title:SetText("PLACEMENT MODE")
        bar.gridLabel:SetText("Grid")
        bar.dimLabel:SetText("Dim")
        bar.snapLabel:SetText("Snap")
    end)
    TAP._refreshBar()
end

----------------------------------------------------------------------
-- Start / stop.
--
--   TAP:StartPlacement()                  every registered mover
--   TAP:StartPlacement({ id = "x" })      just that one
--   TAP:StartPlacement({ ids = {...} })   a named set
--   TAP:StartPlacement({ ownerId = "x" }) every mover a module registered
--
-- `opts.preview` seeds whether live previews start on (default true - you almost always want to
-- see what you are placing the first time, and the bar makes it one click to drop to boxes).
----------------------------------------------------------------------
function Suite:StartPlacement(opts)
    opts = opts or {}
    if TAP._placing then return end

    local ids = {}
    if opts.id then
        if TAP._movers[opts.id] then ids[1] = opts.id end
    elseif opts.ids then
        for _, id in ipairs(opts.ids) do if TAP._movers[id] then ids[#ids + 1] = id end end
    else
        for _, spec in ipairs(self:GetMovers()) do
            if not opts.ownerId or spec.ownerId == opts.ownerId then ids[#ids + 1] = spec.id end
        end
    end
    if #ids == 0 then
        print("|cffa06cf0TAP|r  Nothing to place - no movable elements are registered yet.")
        return
    end

    -- Where to return to. Captured before the window is closed so Done lands you back on the
    -- page you launched from rather than the Overview.
    local w = opts.win
    session = {
        ids     = ids,
        backup  = {},
        view    = (w and w.view) or opts.view or "movers",
        grid    = nil,
        snap    = nil,
        dim     = nil,
        preview = {},
        sizes   = {},
    }
    for _, id in ipairs(ids) do
        local p, x, y = moverGet(TAP._movers[id])
        session.backup[id] = { p, x, y }
    end

    TAP._placing = true

    -- Close the config window BEFORE anything is drawn, so the screen you are laying out is the
    -- screen you actually play on.
    if w then w:Hide() elseif self.CloseWindow then self:CloseWindow() end

    if not bar then buildBar() end
    if not bar then
        -- No theme, no bar, no way out: unwind rather than stranding the user with ghosts.
        TAP._placing = false
        session = nil
        if self.OpenWindow then self:OpenWindow() end
        return
    end

    -- Previews on by default. An element that only shows in combat (or after a death, or on a
    -- proc) has nothing on screen otherwise, and this is also how the boxes learn their real
    -- bounds - measured once here, then reused if the preview is switched off.
    local wantPreview = opts.preview ~= false
    for _, id in ipairs(ids) do
        ensureGhost(id)
        session.preview[id] = false
        if wantPreview then setPreview(id, true) end
    end

    if #ids == 1 then session.selected = ids[1] end
    styleBar(#ids)
    paintGrid()
    paintDim()
    TAP._syncGhosts()
    bar:Show()

    -- Elements resize as their contents change, so the boxes re-measure on a slow ticker. Also
    -- catches an element whose frame was built lazily a moment after its preview came on.
    session.ticker = C_Timer.NewTicker(0.25, function() TAP._syncGhosts() end)
end

function Suite:StopPlacement(save)
    -- `session` is checked as well as the flag: StartPlacement builds the session, flips the
    -- flag, then creates chrome, and any hide fired during that window must not unwind it.
    if not (TAP._placing and session) then return end
    TAP._placing = false
    local s = session
    session = nil

    if s.ticker then s.ticker:Cancel() end
    paintGrid()   -- session is nil now, so these tear the overlays down
    paintDim()

    if save == false then
        for _, id in ipairs(s.ids) do
            local spec, b = TAP._movers[id], s.backup[id]
            if spec and b then
                moverSet(spec, b[1], b[2], b[3])
                if spec.OnChange then pcall(spec.OnChange) end
            end
        end
    end

    for _, id in ipairs(s.ids) do
        local g = TAP._moverGhosts[id]
        if g then g._dragging = false; g._spec = nil; g:Hide() end
        -- Only stand a preview down if we put it up: Preview(false) on something that was never
        -- previewed can hide an element the module legitimately had on screen.
        local spec = TAP._movers[id]
        if spec and spec.Preview and s.preview[id] then pcall(spec.Preview, false) end
    end

    -- The bar's own OnHide calls back in here, which is harmless now that _placing is already
    -- false, but the guard keeps the intent obvious.
    if bar and bar:IsShown() then bar:Hide() end

    if self.OpenWindow then self:OpenWindow(s.view) end
end

function Suite:IsPlacing() return TAP._placing and true or false end

----------------------------------------------------------------------
-- The Movers page (rendered by SuiteManager, which calls TAP.MoversPage).
--
-- Deliberately one thing: a hero and a button. Anchor point and pixel offsets used to be
-- editable here in a dense per-element table, which was the wrong shape twice over - it was
-- laborious for the common case, and it duplicated a job placement mode does better by showing
-- you the screen you are actually aiming at. Numbers are still reachable per add-on in each
-- module's own settings; this page is the front door to dragging.
----------------------------------------------------------------------
function TAP.MoversPage(b, win)
    local C = b.theme.C
    local w = (b.contentWidth or 700) - 48
    local x = 24
    local y = -70

    local movers = Suite:GetMovers()

    -- Owner summary, built first because the subtext names them.
    local owners, seen = {}, {}
    for _, spec in ipairs(movers) do
        local o = spec.owner or "Other"
        if not seen[o] then seen[o] = 0; owners[#owners + 1] = o end
        seen[o] = seen[o] + 1
    end

    local title = b:Label("Frame Placement", x, y, C.text, 30)
    title:SetWidth(w); title:SetJustifyH("CENTER")
    y = y - 48

    local body
    if #movers == 0 then
        body = "No movable elements are registered yet. Turn on an add-on that puts something on "
            .. "screen and it will appear here automatically."
    else
        body = ("Every movable element on the platform, laid out in one sitting. Placement mode closes "
            .. "this window, drops a labelled box over each of the %d element%s, and lets you drag "
            .. "them into place against a live preview and an optional alignment grid."):format(
                #movers, #movers == 1 and "" or "s")
    end
    local sub, subH = b:Wrap(body, x + math.floor(w * 0.12), y, math.floor(w * 0.76), C.subtext, 13)
    sub:SetJustifyH("CENTER")
    y = y - (subH + 34)

    if #movers > 0 then
        local BW, BH = 300, 52
        b:Button(x + math.floor((w - BW) / 2), y, BW, "Enter placement mode", "primary", function()
            Suite:StartPlacement({ win = win })
        end, { icon = "anchor", iconSize = 22, iconGap = 10, iconAlign = "center",
               fontSize = 16, height = BH })
        y = y - (BH + 28)

        -- A quiet inventory line, so it is obvious what is about to appear on screen. Names only:
        -- anything clickable here would pull the page back toward the table it just replaced.
        local parts = {}
        for _, o in ipairs(owners) do parts[#parts + 1] = ("%s (%d)"):format(o, seen[o]) end
        local inv, invH = b:Wrap(table.concat(parts, "     "), x + math.floor(w * 0.08), y,
            math.floor(w * 0.84), C.subtext, 11)
        inv:SetJustifyH("CENTER")
        y = y - (invH + 26)

        local tipTxt = "Done or Escape keeps your changes. Cancel puts everything back. "
            .. "Each add-on also has its own Place button, and /tap move opens this directly."
        local tip, tipH = b:Wrap(tipTxt, x + math.floor(w * 0.12), y, math.floor(w * 0.76), C.subtext, 11)
        tip:SetJustifyH("CENTER")
        y = y - (tipH + 20)
    end

    return y
end


----------------------------------------------------------------------
-- Slash command: /tap move [all | <owner id>]
----------------------------------------------------------------------
if Suite.RegisterCommand then
    Suite:RegisterCommand({
        cmd = "/tap move", desc = "Place platform frames on screen", owner = "Platform", sub = "move",
        handler = function(rest)
            rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if rest ~= "" and rest ~= "all" then
                Suite:StartPlacement({ ownerId = rest })
            else
                Suite:StartPlacement()
            end
        end,
    })
end
