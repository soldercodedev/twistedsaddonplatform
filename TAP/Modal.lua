-- UIFoundry - Modal.lua
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

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

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

function Mixin:Modal(opts)
    opts = opts or {}
    local theme, C = self, self.C
    ensureBackdrop(theme)
    local w = opts.width or 380
    local pad = 16
    local variant = opts.variant and (UIF.BADGE_VARIANTS[opts.variant] or nil)
    local accentCol = UIF.toColor(opts.accentColor or opts.color,
        variant and (type(variant) == "string" and C[variant] or variant) or C.accent)

    local modal = {}
    local name = UIF.NextId(theme.id .. "Modal")
    local f = CreateFrame("Frame", name, UIParent)
    modal.frame = f
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:SetClampedToScreen(true); f:Hide()
    theme:StylePanel(f, C.panel, C.border)
    f:EnableMouse(true); f:SetMovable(true)

    local bar = f:CreateTexture(nil, "ARTWORK"); bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(3); UIF.paint(bar, accentCol)

    -- Header (drag handle) with optional icon + title + close.
    local hd = CreateFrame("Button", nil, f); hd:SetPoint("TOPLEFT", 1, -4); hd:SetPoint("TOPRIGHT", -1, -4); hd:SetHeight(34)
    if opts.draggable ~= false then
        hd:RegisterForDrag("LeftButton")
        hd:SetScript("OnDragStart", function() f:StartMoving() end)
        hd:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    end
    local titleX = pad
    if opts.icon then
        local ic = f:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); ic:SetPoint("TOPLEFT", pad, -13)
        ic:SetTexture(theme:IconPath(opts.icon) or opts.icon); ic:SetVertexColor(accentCol[1], accentCol[2], accentCol[3])
        titleX = pad + 26
    end
    local title = theme:Heading(f, { text = opts.title or "", role = "h4" }); title:SetPoint("TOPLEFT", titleX, -14)

    local dismissable = opts.dismissable ~= false
    if dismissable then
        local xb = theme:Button(f); xb:Configure("X", 24, 22, "danger", function() modal:Close() end)
        xb:SetPoint("TOPRIGHT", -6, -8); xb:SetFrameLevel(hd:GetFrameLevel() + 5)
    end
    -- dim (default true) darkens the screen behind; closeOnClickOutside (default = dismissable)
    -- closes when you click off the modal. Set both false for a non-modal, non-dimming dialog.
    modal._dim = opts.dim ~= false
    local clickClose = opts.closeOnClickOutside
    if clickClose == nil then clickClose = dismissable end
    modal._clickClose = clickClose

    local headerH = 42

    -- Footer buttons (right-aligned, right-to-left).
    local btns = opts.buttons or {}
    local footerH = (#btns > 0) and 48 or pad
    if #btns > 0 then
        local bx = -pad
        for i = #btns, 1, -1 do
            local spec = btns[i]
            local bw = spec.width or 96
            local btn = theme:Button(f)
            btn:Configure(spec.label, bw, 26, spec.kind or (i == #btns and "primary" or "default"),
                function() if spec.onClick then spec.onClick(modal) elseif spec.close ~= false then modal:Close() end end,
                spec.style)
            btn:SetPoint("BOTTOMRIGHT", bx, pad - 4)
            bx = bx - bw - 8
        end
    end

    -- Body region + its content.
    local body = CreateFrame("Frame", nil, f); modal.body = body
    local bodyH
    if opts.content then
        bodyH = opts.bodyHeight or (opts.height and (opts.height - headerH - footerH)) or 140
    else
        -- Text body: message string and/or lines list.
        local lines = {}
        if opts.message then lines[#lines + 1] = opts.message end
        if opts.lines then for _, l in ipairs(opts.lines) do lines[#lines + 1] = l end end
        local y = 0
        modal._bodyFS = {}
        for i, l in ipairs(lines) do
            local txt = type(l) == "table" and l.text or l
            local col = (type(l) == "table" and l.color) and UIF.toColor(l.color, C.text) or (i == 1 and C.text or C.subtext)
            if type(l) == "table" and type(l.color) == "string" and C[l.color] then col = C[l.color] end
            local fs = body:CreateFontString(nil, "OVERLAY")
            fs:SetFont(theme.FONT, 12); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetWidth(w - 2 * pad)
            fs:SetText(theme:HL(txt)); fs:SetTextColor(col[1], col[2], col[3])
            fs:SetPoint("TOPLEFT", 0, y)
            modal._bodyFS[i] = fs
            y = y - (fs:GetStringHeight() or 14) - 6
        end
        bodyH = math.max(opts.minBodyHeight or 10, -y)
    end
    body:SetPoint("TOPLEFT", pad, -headerH); body:SetSize(w - 2 * pad, bodyH)

    f:SetSize(w, headerH + bodyH + footerH)
    if opts.content then opts.content(body, modal) end

    -- Escape closes a dismissable modal (via UISpecialFrames); keep the stack in sync.
    if dismissable then tinsert(UISpecialFrames, name) end

    function modal:_syncClose()
        local stack = theme._modalStack
        for i = #stack, 1, -1 do if stack[i] == self then table.remove(stack, i) end end
        restack(theme)
        if opts.onClose then opts.onClose(self) end
    end
    -- OnHide covers the Escape / UISpecialFrames path; Close() drives the normal path and
    -- sets _open false first so the resulting OnHide is a no-op (no double removal).
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

