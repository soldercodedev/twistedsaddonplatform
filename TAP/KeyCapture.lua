-- UIFoundry - KeyCapture.lua
-- A themed "press a key" popup. It captures a modifier-aware key combo (e.g. "CTRL-F") and
-- hands it back; it does NOT itself bind anything, so the caller stays in control of what
-- the combo means (SetBinding, a saved hotkey string, etc.).
--
--   theme:CaptureKey({
--     title = "Bind a key to <thing>",
--     sub   = "Press any key  \194\183  Esc to cancel",   -- optional
--     onDone = function(combo, cancelled) ... end,        -- combo is nil if cancelled
--   })

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

local IGNORE = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, UNKNOWN = 1 }

function Mixin:CaptureKey(opts)
    opts = opts or {}
    local theme, C = self, self.C
    local f = theme._keyCapture
    if not f then
        f = CreateFrame("Frame", UIF.NextId(theme.id .. "KeyCapture"), UIParent)
        theme._keyCapture = f
        f:SetSize(380, 96); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
        theme:StylePanel(f, C.panel, C.accent)
        f.fs = f:CreateFontString(nil, "OVERLAY"); f.fs:SetFont(theme.FONT, 15); f.fs:SetPoint("CENTER", 0, 8); f.fs:SetTextColor(unpack(C.text))
        f.sub = f:CreateFontString(nil, "OVERLAY"); f.sub:SetFont(theme.FONT, 11); f.sub:SetPoint("CENTER", 0, -20); f.sub:SetTextColor(unpack(C.subtext))
        f:EnableKeyboard(true); f:SetPropagateKeyboardInput(false)
        f:SetScript("OnHide", function(self) self:EnableKeyboard(false) end)
        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide(); if self._onDone then self._onDone(nil, true) end return end
            if IGNORE[key] then return end
            local combo = key
            if IsAltKeyDown() then combo = "ALT-" .. combo end
            if IsControlKeyDown() then combo = "CTRL-" .. combo end
            if IsShiftKeyDown() then combo = "SHIFT-" .. combo end
            self:Hide()
            if self._onDone then self._onDone(combo, false) end
        end)
    end
    -- Re-assert the accent border in case the theme accent changed since last use.
    UIF.paint(f._brd, theme.C.accent)
    f._onDone = opts.onDone
    f.fs:SetText(opts.title or "Press a key")
    f.sub:SetText(opts.sub or "Press any key  \194\183  Esc to cancel")
    f:Show(); f:EnableKeyboard(true)
    return f
end
