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

-- Build a toast (frame + every sub-element + one animation group) ONCE. Mixin:Toast reconfigures and
-- shows it; dismiss() returns it to the host's free pool. WoW never GCs frames, so recycling caps the
-- live toast frames at the max concurrently on screen instead of leaking one per notification.
local function makeToast(theme, host)
    local C = theme.C
    local t = CreateFrame("Button", nil, host)
    theme:StylePanel(t, C.panel, C.border)
    t._stripe = t:CreateTexture(nil, "ARTWORK")
    t._stripe:SetPoint("TOPLEFT", 1, -1); t._stripe:SetPoint("BOTTOMLEFT", 1, 1); t._stripe:SetWidth(3)
    t._icon = t:CreateTexture(nil, "ARTWORK"); t._icon:SetSize(18, 18); t._icon:SetPoint("LEFT", 12, 0)
    t._titleFS  = theme:Heading(t, { text = "", role = "h5" })          -- shown only when there's a title
    t._bodyRich = theme:Heading(t, { text = "", role = "caption" })     -- body when titled
    t._bodyPlain = t:CreateFontString(nil, "OVERLAY")                   -- body when untitled
    local xb = CreateFrame("Button", nil, t); xb:SetSize(16, 16); xb:SetPoint("TOPRIGHT", -6, -6)
    xb.fs = xb:CreateFontString(nil, "OVERLAY"); theme:StyleFont(xb.fs, {}, { fontSize = 13, textColor = C.subtext })
    xb.fs:SetPoint("CENTER"); xb.fs:SetText("x")
    xb:SetScript("OnEnter", function(self) self.fs:SetTextColor(unpack(theme.C.text)) end)
    xb:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(theme.C.subtext)) end)
    xb:SetScript("OnClick", function() if t._dismiss then t._dismiss() end end)
    t._xb = xb
    local ag = t:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha"); fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(0.2); fade:SetOrder(1)
    t._trans = ag:CreateAnimation("Translation"); t._trans:SetDuration(0.2); t._trans:SetOrder(1)
    ag:SetScript("OnFinished", function() t:SetAlpha(1); relayout(host) end)
    t._ag = ag
    t:SetScript("OnClick", function() if t._onClick then t._onClick() end if t._dismiss then t._dismiss() end end)
    host._pool = host._pool or {}
    host._pool[#host._pool + 1] = t
    return t
end

local function acquireToast(theme, host)
    if host._pool then
        for _, t in ipairs(host._pool) do if t._free then t._free = false; return t end end
    end
    return makeToast(theme, host)
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

    local t = acquireToast(theme, host)
    t:Show()   -- a reused toast was Hidden by its dismiss(); re-show it before the fade-in animates alpha
    t._gone = nil
    t:SetSize(w, hasTitle and 52 or 36)
    theme:StyleFrame(t, opts)
    TAP.paint(t._stripe, accent)

    local rightPad = dismissible and 26 or 14
    local textX = 14
    local iconTex = opts.icon and theme:IconPath(opts.icon) or theme:GetIcon(variant.slug)
    if iconTex then
        t._icon:SetTexture(iconTex); t._icon:SetVertexColor(accent[1], accent[2], accent[3]); t._icon:Show()
        textX = 38
    else
        t._icon:Hide()
    end

    local bo
    if hasTitle then
        theme:_applyHeading(t._titleFS, opts.title, "h5", { textColor = C.text })
        t._titleFS:ClearAllPoints(); t._titleFS:SetPoint("TOPLEFT", textX, -9); t._titleFS:Show()
        t._bodyPlain:Hide()
        bo = t._bodyRich
        theme:_applyHeading(bo, opts.text or "", "caption", { wrapWidth = w - textX - rightPad })
        bo:ClearAllPoints(); bo:SetPoint("TOPLEFT", textX, -26); bo:Show()
    else
        t._titleFS:Hide(); t._bodyRich:Hide()
        bo = t._bodyPlain
        theme:StyleFont(bo, opts, { fontSize = 12, textColor = C.text })
        bo:ClearAllPoints(); bo:SetPoint("TOPLEFT", textX, -10); bo:SetWidth(w - textX - rightPad)
        bo:SetJustifyH("LEFT"); bo:SetWordWrap(true); bo:SetText(theme:HL(opts.text or "")); bo:Show()
    end

    -- Size the toast to its content so long / multi-line bodies aren't clipped (the body wraps at
    -- a fixed width, so its rendered height tells us how tall the card needs to be).
    local bodyH = (bo and bo:GetStringHeight()) or 12
    local topInset = hasTitle and 26 or 10
    t:SetHeight(math.max(hasTitle and 52 or 36, topInset + bodyH + 12))

    local function dismiss()
        if t._gone then return end
        t._gone = true
        for i, x in ipairs(host.stack) do if x == t then table.remove(host.stack, i); break end end
        t:Hide(); t._free = true; relayout(host)   -- recycle (WoW never GCs the frame)
    end
    t._dismiss = dismiss
    t.Dismiss = dismiss
    t._onClick = opts.onClick
    t._xb:SetShown(dismissible)

    table.insert(host.stack, 1, t); relayout(host)

    -- Optional audible notification: a sound key, or `true` for the variant's default sound.
    if opts.sound and theme.PlaySound then
        local key = (opts.sound == true) and ((TAP.TOAST_SOUNDS and TAP.TOAST_SOUNDS[opts.variant or "info"]) or "SUBTLE") or opts.sound
        theme:PlaySound(key, opts.soundChannel)
    end

    -- Entrance animation (reuses the toast's own animation group).
    local anim = opts.animation or "fade"
    t._ag:Stop()
    if anim == "none" then
        t:SetAlpha(1)
    else
        t:SetAlpha(0)
        if anim == "slide" then
            t._trans:SetOffset(0, -host.pos.slide)
            t:SetPoint("TOP", host, "TOP", 0, (select(5, t:GetPoint()) or 0) + host.pos.slide)
        else
            t._trans:SetOffset(0, 0)
        end
        t._ag:Play()
    end

    local dur = opts.duration or 4
    if dur > 0 and C_Timer and C_Timer.After then
        C_Timer.After(dur, function() if not t._gone then dismiss() end end)
    end
    return t
end
