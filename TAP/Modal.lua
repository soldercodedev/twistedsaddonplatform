-- TAP - Modal.lua
-- Centered dialog windows over a dimmed backdrop. One flexible builder (theme:Modal) plus
-- ready-made Alert / Confirm helpers. Modals stack, support variants (accent color
-- + icon), a custom content region, and a footer button row.
--
--   theme:Alert({ title = "Saved", message = "Your changes were saved.", variant = "success" })
--   theme:Confirm({ title = "Delete alert?", message = "This can't be undone.", variant = "danger",
--                   confirmLabel = "Delete", onConfirm = function() ... end })
--
--   local m = theme:Modal({ title = "Settings", width = 460, height = 300, dismissable = true,
--       content = function(body, modal) local b = theme:Button(body); ... end,
--       buttons = { { label = "Close", onClick = function(m) m:Close() end } } })
--   m:Open()
--
-- Modal frames are POOLED per theme and reused (re-bound on each open) instead of created per call,
-- so opening a confirm dialog dozens of times never leaks frames or grows UISpecialFrames.

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

local function ensureBackdrop(theme)
    if theme._modalBackdrop then return theme._modalBackdrop end
    local bd = CreateFrame("Button", nil, UIParent)
    bd:SetAllPoints(UIParent); bd:SetFrameStrata("FULLSCREEN_DIALOG"); bd:Hide()
    local t = bd:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(0, 0, 0, 0.55)
    bd._tex = t
    bd:SetScript("OnClick", function()
        local top = theme._modalStack[#theme._modalStack]
        if top and top._clickClose then top:Close() end
    end)
    theme._modalBackdrop = bd
    theme._modalStack = {}
    return bd
end

local function restack(theme)
    local bd, stack = theme._modalBackdrop, theme._modalStack
    for i, m in ipairs(stack) do m.frame:SetFrameLevel(200 + i * 10) end
    local top = stack[#stack]
    if not top then bd:Hide(); return end
    -- Show the backdrop only if the top modal dims OR closes on outside click. When it dims,
    -- darken; when it only wants click-to-close, keep it fully transparent but click-catching.
    if top._dim or top._clickClose then
        bd:Show(); bd:SetParent(UIParent)
        bd._tex:SetColorTexture(0, 0, 0, top._dim and 0.55 or 0)
        bd:SetFrameLevel(math.max(1, 200 + #stack * 10 - 5))
    else
        bd:Hide()   -- non-modal: no dim, clicks pass through to whatever is behind
    end
end

-- Build the reusable frame + its fixed children ONCE. Everything that varies per open (title text,
-- icon, footer buttons, body text/content, sizing) is (re)bound in Mixin:Modal; footer buttons and
-- body text lines are pooled within the modal so repeated opens create no new frames.
local function makeModal(theme)
    local C = theme.C
    local modal = { _btnPool = {}, _fsPool = {}, _adopted = {} }
    local name = TAP.NextId(theme.id .. "Modal")
    local f = CreateFrame("Frame", name, UIParent)
    modal.frame = f
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:SetClampedToScreen(true); f:Hide()
    theme:StylePanel(f, C.panel, C.border)
    f:EnableMouse(true); f:SetMovable(true)

    modal._bar = f:CreateTexture(nil, "ARTWORK")
    modal._bar:SetPoint("TOPLEFT", 1, -1); modal._bar:SetPoint("TOPRIGHT", -1, -1); modal._bar:SetHeight(3)

    -- Header (drag handle) - dragging is gated on the per-open _draggable flag.
    local hd = CreateFrame("Button", nil, f); hd:SetPoint("TOPLEFT", 1, -4); hd:SetPoint("TOPRIGHT", -1, -4); hd:SetHeight(34)
    hd:RegisterForDrag("LeftButton")
    hd:SetScript("OnDragStart", function() if modal._draggable then f:StartMoving() end end)
    hd:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    modal._icon = f:CreateTexture(nil, "ARTWORK"); modal._icon:SetSize(18, 18); modal._icon:SetPoint("TOPLEFT", 16, -13); modal._icon:Hide()
    modal._title = theme:Heading(f, { text = "", role = "h4" })
    modal._xb = theme:Button(f); modal._xb:SetPoint("TOPRIGHT", -6, -8); modal._xb:SetFrameLevel(hd:GetFrameLevel() + 5)
    modal._xb:Configure("X", 24, 22, "danger", function() modal:Close() end)

    modal.body = CreateFrame("Frame", nil, f)

    -- Escape closes it. Registered ONCE (the frame is reused for every dialog), so UISpecialFrames
    -- never grows past the pool size.
    tinsert(UISpecialFrames, name)

    function modal:_syncClose()
        local stack = theme._modalStack
        for i = #stack, 1, -1 do if stack[i] == self then table.remove(stack, i) end end
        restack(theme)
        if self._onClose then self._onClose(self) end
    end
    -- OnHide covers the Escape / UISpecialFrames path; Close() drives the normal path and sets _open
    -- false first so the resulting OnHide is a no-op (no double removal).
    f:SetScript("OnHide", function() if modal._open then modal._open = false; modal:_syncClose() end end)

    function modal:Open()
        if self._open then return self end
        self._open = true
        tinsert(theme._modalStack, self)
        f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        f:Show(); restack(theme)
        return self
    end
    function modal:Close()
        if not self._open then return end
        self._open = false
        f:Hide()
        self:_syncClose()
    end

    -- A Builder bound to this modal's body, created ONCE and reused across opens (its widget pool is
    -- reset, not rebuilt). Content callbacks that draw through a Builder must use this instead of
    -- theme:Builder(body, ...) - a fresh builder per open would strand a whole page of frames/regions on
    -- the reused body every time the modal opens. The modal reset also Resets it, so a later non-builder
    -- dialog on the same pooled frame doesn't inherit stale widgets.
    function modal:Builder(bopts)
        if not self._builder then self._builder = theme:Builder(self.body, bopts) end
        self._builder:Reset()
        if bopts and bopts.contentWidth then self._builder.contentWidth = bopts.contentWidth end
        return self._builder
    end

    -- Adopt a content-created frame or region (e.g. a full-modal backdrop drawn on modal.frame, which the
    -- body reset doesn't reach) so it's HIDDEN when this pooled modal is next reused. Cache the object
    -- yourself (create-once) and re-Adopt each open; this only manages visibility, not creation.
    function modal:Adopt(obj)
        self._adopted[#self._adopted + 1] = obj
        return obj
    end

    return modal
end

-- A free (not currently open) pooled modal for this theme, or a fresh one when all are in use (a
-- stacked dialog).
local function acquireModal(theme)
    theme._modalPool = theme._modalPool or {}
    for _, m in ipairs(theme._modalPool) do if not m._open then return m end end
    local m = makeModal(theme)
    theme._modalPool[#theme._modalPool + 1] = m
    return m
end

function Mixin:Modal(opts)
    opts = opts or {}
    local theme, C = self, self.C
    ensureBackdrop(theme)
    local modal = acquireModal(theme)
    local f = modal.frame
    local w = opts.width or 380
    local pad = 16
    local variant = opts.variant and TAP.BADGE_VARIANTS[opts.variant]
    local accentCol = TAP.toColor(opts.accentColor or opts.color,
        variant and (type(variant) == "string" and C[variant] or variant) or C.accent)

    modal._onClose = opts.onClose
    modal._draggable = opts.draggable ~= false
    TAP.paint(modal._bar, accentCol)

    -- Header: optional icon + title.
    local titleX = pad
    if opts.icon then
        modal._icon:SetTexture(theme:IconPath(opts.icon) or opts.icon)
        modal._icon:SetVertexColor(accentCol[1], accentCol[2], accentCol[3]); modal._icon:Show()
        titleX = pad + 26
    else
        modal._icon:Hide()
    end
    theme:_applyHeading(modal._title, opts.title or "", "h4")   -- re-styles (picks up live font) + text
    modal._title:ClearAllPoints(); modal._title:SetPoint("TOPLEFT", titleX, -14)

    local dismissable = opts.dismissable ~= false
    modal._xb:SetShown(dismissable)
    -- dim (default true) darkens the screen behind; closeOnClickOutside (default = dismissable) closes
    -- when you click off the modal. Set both false for a non-modal, non-dimming dialog.
    modal._dim = opts.dim ~= false
    local clickClose = opts.closeOnClickOutside
    if clickClose == nil then clickClose = dismissable end
    modal._clickClose = clickClose

    local headerH = 42

    -- Reset anything a previous use of this pooled modal left behind.
    for _, b in ipairs(modal._btnPool) do b:Hide() end
    for _, fs in ipairs(modal._fsPool) do fs:Hide(); fs:ClearAllPoints() end
    for _, ch in ipairs({ modal.body:GetChildren() }) do ch:Hide(); ch:ClearAllPoints() end   -- prior content-callback frames
    if modal._builder then modal._builder:Reset() end                    -- clear a prior content-builder's widgets
    for i = #modal._adopted, 1, -1 do modal._adopted[i]:Hide() end        -- hide prior frame-level decorations
    modal._adopted = {}

    -- Footer buttons (right-aligned, right-to-left), pooled per modal.
    local btns = opts.buttons or {}
    local footerH = (#btns > 0) and 48 or pad
    local bx, used = -pad, 0
    for i = #btns, 1, -1 do
        local spec = btns[i]
        local bw = spec.width or 96
        used = used + 1
        local btn = modal._btnPool[used]
        if not btn then btn = theme:Button(f); modal._btnPool[used] = btn end
        btn:Configure(spec.label, bw, 26, spec.kind or (i == #btns and "primary" or "default"),
            function() if spec.onClick then spec.onClick(modal) elseif spec.close ~= false then modal:Close() end end,
            spec.style)
        btn:ClearAllPoints(); btn:SetPoint("BOTTOMRIGHT", bx, pad - 4); btn:Show()
        bx = bx - bw - 8
    end

    -- Body: a custom content region, or text lines (message + optional lines list) drawn on pooled
    -- fontstrings.
    local body = modal.body
    local bodyH
    if opts.content then
        bodyH = opts.bodyHeight or (opts.height and (opts.height - headerH - footerH)) or 140
    else
        local lines = {}
        if opts.message then lines[#lines + 1] = opts.message end
        if opts.lines then for _, l in ipairs(opts.lines) do lines[#lines + 1] = l end end
        local y, nfs = 0, 0
        for i, l in ipairs(lines) do
            local txt = type(l) == "table" and l.text or l
            local col = (type(l) == "table" and l.color) and TAP.toColor(l.color, C.text) or (i == 1 and C.text or C.subtext)
            if type(l) == "table" and type(l.color) == "string" and C[l.color] then col = C[l.color] end
            nfs = nfs + 1
            local fs = modal._fsPool[nfs]
            if not fs then fs = body:CreateFontString(nil, "OVERLAY"); modal._fsPool[nfs] = fs end
            fs:SetFont(theme.FONT, 12); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetWidth(w - 2 * pad)
            fs:SetText(theme:HL(txt)); fs:SetTextColor(col[1], col[2], col[3])
            fs:SetPoint("TOPLEFT", 0, y); fs:Show()
            y = y - (fs:GetStringHeight() or 14) - 6
        end
        bodyH = math.max(opts.minBodyHeight or 10, -y)
    end
    body:ClearAllPoints(); body:SetPoint("TOPLEFT", pad, -headerH); body:SetSize(w - 2 * pad, bodyH)

    f:SetSize(w, headerH + bodyH + footerH)
    if opts.content then opts.content(body, modal) end

    return modal
end

----------------------------------------------------------------------
-- Ready-made variants
----------------------------------------------------------------------
function Mixin:Alert(opts)
    opts = opts or {}
    return self:Modal({
        title = opts.title or "Alert", message = opts.message, lines = opts.lines,
        variant = opts.variant, icon = opts.icon, width = opts.width,
        dismissable = opts.dismissable, draggable = opts.draggable,
        buttons = { { label = opts.okLabel or "OK", kind = "primary",
            onClick = function(m) m:Close(); if opts.onOk then opts.onOk() end end } },
    }):Open()
end

function Mixin:Confirm(opts)
    opts = opts or {}
    return self:Modal({
        title = opts.title or "Are you sure?", message = opts.message, lines = opts.lines,
        variant = opts.variant, icon = opts.icon, width = opts.width,
        buttons = {
            { label = opts.cancelLabel or "Cancel", kind = "default",
              onClick = function(m) m:Close(); if opts.onCancel then opts.onCancel() end end },
            { label = opts.confirmLabel or "Confirm", kind = (opts.variant == "danger") and "danger" or "primary",
              onClick = function(m) m:Close(); if opts.onConfirm then opts.onConfirm() end end },
        },
    }):Open()
end
