-- TAP - Toast.lua
-- Transient on-screen notifications that stack and (optionally) auto-dismiss. Variants set
-- the accent stripe + default icon; position, animation, and dismissibility are all options.
--
--   theme:Toast({ text = "Saved!", variant = "success" })
--   theme:Toast({ title = "Heads up", text = "Something happened", variant = "warning",
--                 position = "BOTTOM-RIGHT", animation = "slide", duration = 6 })
--   local t = theme:Toast({ text = "Working...", duration = 0, dismissible = true })  -- sticky + ×
--   t:Dismiss()
--
-- opts:
--   text · title · variant (info/success/warning/danger) · color · icon
--   position   = TOP · TOP-LEFT · TOP-RIGHT · BOTTOM · BOTTOM-LEFT · BOTTOM-RIGHT · CENTER   (default TOP)
--   animation  = "fade" (default) · "slide" · "none"
--   duration   = seconds before auto-dismiss (default 4; 0 = stays until dismissed / clicked)
--   dismissible= show a × close button (default true)
--   parent     = a frame/window to spawn within (default the viewport / whole screen)
--   inset      = corner inset (px) when anchored to a frame (default 10)
--   sound      = a sound key, or true for the variant default · soundChannel
--   width · onClick

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

TAP.TOAST_VARIANTS = {
    info    = { color = { 0.05, 0.55, 0.75 }, slug = "info-circle" },
    success = { color = { 0.13, 0.60, 0.38 }, slug = "circle-check" },
    warning = { color = { 0.80, 0.60, 0.22 }, slug = "alert-triangle" },
    danger  = { color = { 0.72, 0.26, 0.28 }, slug = "alert-circle" },
}

-- point = where the host pins to UIParent; grow = stack direction (-1 down, +1 up);
-- slideFrom = initial y offset sign for the slide animation.
local POSITIONS = {
    ["TOP"]          = { point = "TOP",         x = 0,   y = -80,  grow = -1, slide =  20 },
    ["TOP-LEFT"]     = { point = "TOPLEFT",     x = 20,  y = -80,  grow = -1, slide =  20 },
    ["TOP-RIGHT"]    = { point = "TOPRIGHT",    x = -20, y = -80,  grow = -1, slide =  20 },
    ["BOTTOM"]       = { point = "BOTTOM",      x = 0,   y = 160,  grow =  1, slide = -20 },
    ["BOTTOM-LEFT"]  = { point = "BOTTOMLEFT",  x = 20,  y = 160,  grow =  1, slide = -20 },
    ["BOTTOM-RIGHT"] = { point = "BOTTOMRIGHT", x = -20, y = 160,  grow =  1, slide = -20 },
    ["CENTER"]       = { point = "CENTER",      x = 0,   y = 0,    grow = -1, slide =  20 },
}

-- Hosts are keyed by (anchor frame, position). The anchor defaults to the viewport
-- (UIParent) but may be any frame/window, so toasts can spawn within a specific frame's
-- bounds. Viewport anchors use the big screen offsets; frame anchors use a small corner inset.
local function ensureHost(theme, anchorFrame, poskey, inset)
    anchorFrame = anchorFrame or UIParent
    theme._toastHosts = theme._toastHosts or {}
    local key = tostring(anchorFrame) .. "|" .. poskey
    if theme._toastHosts[key] then return theme._toastHosts[key] end
    local pos = POSITIONS[poskey] or POSITIONS["TOP"]
    local host = CreateFrame("Frame", nil, anchorFrame)
    host:SetSize(320, 10); host:SetToplevel(true)
    local ox, oy
    if anchorFrame == UIParent then
        host:SetFrameStrata("FULLSCREEN_DIALOG")
        ox, oy = pos.x, pos.y
    else
        local ins = inset or 10
        ox = (pos.point:find("LEFT") and ins) or (pos.point:find("RIGHT") and -ins) or 0
        oy = (pos.point:find("TOP") and -ins) or (pos.point:find("BOTTOM") and ins) or 0
        host:SetFrameLevel((anchorFrame:GetFrameLevel() or 1) + 50)
    end
    host:SetPoint(pos.point, anchorFrame, pos.point, ox, oy)
    host.pos = pos; host.stack = {}
    theme._toastHosts[key] = host
    return host
end

local function relayout(host)
    -- grow -1 stacks downward (top anchors), grow +1 stacks upward (bottom anchors).
    local y = 0
    for _, t in ipairs(host.stack) do
        t:ClearAllPoints(); t:SetPoint("TOP", host, "TOP", 0, y)
        y = y + host.pos.grow * (t:GetHeight() + 8)
    end
end

function Mixin:Toast(opts)
    opts = opts or {}
    local theme, C = self, self.C
    -- opts.parent: a frame to spawn within (default the viewport); opts.inset: corner inset.
    local host = ensureHost(theme, opts.parent, opts.position or "TOP", opts.inset)
    local variant = TAP.TOAST_VARIANTS[opts.variant or "info"] or TAP.TOAST_VARIANTS.info
    local accent = TAP.toColor(opts.color, variant.color)
    local w = opts.width or 320
    local hasTitle = opts.title ~= nil
    local dismissible = opts.dismissible ~= false

    local t = CreateFrame("Button", nil, host); t:SetSize(w, hasTitle and 52 or 36)
    theme:StylePanel(t, C.panel, C.border)
    theme:StyleFrame(t, opts)
    local stripe = t:CreateTexture(nil, "ARTWORK"); stripe:SetPoint("TOPLEFT", 1, -1); stripe:SetPoint("BOTTOMLEFT", 1, 1); stripe:SetWidth(3); TAP.paint(stripe, accent)

    local rightPad = dismissible and 26 or 14
    local textX = 14
    local iconTex = opts.icon and theme:IconPath(opts.icon) or theme:GetIcon(variant.slug)
    if iconTex then
        local ic = t:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); ic:SetPoint("LEFT", 12, 0)
        ic:SetTexture(iconTex); ic:SetVertexColor(accent[1], accent[2], accent[3])
        textX = 38
    end
    local bo
    if hasTitle then
        local ti = theme:Heading(t, { text = opts.title, role = "h5", textColor = C.text }); ti:SetPoint("TOPLEFT", textX, -9)
        bo = theme:Heading(t, { text = opts.text or "", role = "caption", wrapWidth = w - textX - rightPad }); bo:SetPoint("TOPLEFT", textX, -26)
    else
        bo = t:CreateFontString(nil, "OVERLAY"); theme:StyleFont(bo, opts, { fontSize = 12, textColor = C.text })
        bo:SetPoint("TOPLEFT", textX, -10); bo:SetWidth(w - textX - rightPad); bo:SetJustifyH("LEFT"); bo:SetWordWrap(true); bo:SetText(theme:HL(opts.text or ""))
    end

    -- Size the toast to its content so long / multi-line bodies aren't clipped (the body wraps at
    -- a fixed width, so its rendered height tells us how tall the card needs to be).
    local bodyH = (bo and bo:GetStringHeight()) or 12
    local topInset = hasTitle and 26 or 10
    local needed = topInset + bodyH + 12
    t:SetHeight(math.max(hasTitle and 52 or 36, needed))

    local function dismiss()
        if t._gone then return end
        t._gone = true
        for i, x in ipairs(host.stack) do if x == t then table.remove(host.stack, i); break end end
        t:Hide(); relayout(host)
    end
    t.Dismiss = dismiss

    if dismissible then
        local xb = CreateFrame("Button", nil, t); xb:SetSize(16, 16); xb:SetPoint("TOPRIGHT", -6, -6)
        xb.fs = xb:CreateFontString(nil, "OVERLAY"); theme:StyleFont(xb.fs, {}, { fontSize = 13, textColor = C.subtext }); xb.fs:SetPoint("CENTER"); xb.fs:SetText("x")
        xb:SetScript("OnEnter", function(self) self.fs:SetTextColor(unpack(theme.C.text)) end)
        xb:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(theme.C.subtext)) end)
        xb:SetScript("OnClick", function() dismiss() end)
        t.closeBtn = xb
    end
    t:SetScript("OnClick", function() if opts.onClick then opts.onClick() end dismiss() end)

    table.insert(host.stack, 1, t); relayout(host)

    -- Optional audible notification: a sound key, or `true` for the variant's default sound.
    if opts.sound and theme.PlaySound then
        local key = (opts.sound == true) and ((TAP.TOAST_SOUNDS and TAP.TOAST_SOUNDS[opts.variant or "info"]) or "SUBTLE") or opts.sound
        theme:PlaySound(key, opts.soundChannel)
    end

    -- Entrance animation.
    local anim = opts.animation or "fade"
    if anim == "none" then
        t:SetAlpha(1)
    else
        t:SetAlpha(0)
        local ag = t:CreateAnimationGroup()
        local fin = ag:CreateAnimation("Alpha"); fin:SetFromAlpha(0); fin:SetToAlpha(1); fin:SetDuration(0.2); fin:SetOrder(1)
        if anim == "slide" then
            local tr = ag:CreateAnimation("Translation"); tr:SetOffset(0, -host.pos.slide); tr:SetDuration(0.2); tr:SetOrder(1)
            -- start shifted so the translation brings it home
            t:SetPoint("TOP", host, "TOP", 0, (select(5, t:GetPoint()) or 0) + host.pos.slide)
        end
        ag:SetScript("OnFinished", function() t:SetAlpha(1); relayout(host) end)
        ag:Play()
    end

    local dur = opts.duration or 4
    if dur > 0 and C_Timer and C_Timer.After then
        C_Timer.After(dur, function() if not t._gone then dismiss() end end)
    end
    return t
end
