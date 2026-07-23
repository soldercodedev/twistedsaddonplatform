-- UIFoundry - Selectors.lua
-- FontSelect: a dropdown where each option's label is rendered in its own font.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

----------------------------------------------------------------------
-- FontSelect: a dropdown where each option's label is rendered in that font, so you can see
-- what you're picking. Uses the theme's font registry (bundled set by default).
--   theme:FontSelect(parent, { width=200, value="UBUNTU", onChange=function(key) end })
----------------------------------------------------------------------
function Mixin:FontSelect(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local fonts = opts.fonts or theme:FontList()
    local w = opts.width or 200
    local b = CreateFrame("Button", nil, parent); theme:StylePanel(b, C.card); b:SetSize(w, 26)
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetPoint("LEFT", 8, 0); b.fs:SetPoint("RIGHT", -20, 0); b.fs:SetJustifyH("LEFT"); b.fs:SetTextColor(unpack(C.text))
    b.caret = b:CreateFontString(nil, "OVERLAY"); b.caret:SetFont(theme.FONT, 10); b.caret:SetPoint("RIGHT", -7, -1); b.caret:SetText("v"); b.caret:SetTextColor(unpack(C.accent))
    b._value = opts.value or (fonts[1] and fonts[1].key)
    b:SetScript("OnEnter", function(self) theme:FillPaint(self, theme.C.hover) end)
    b:SetScript("OnLeave", function(self) theme:FillPaint(self, theme.C.card) end)
    local function labelFor(key)
        for _, fd in ipairs(fonts) do if fd.key == key then return fd end end
        return fonts[1]
    end
    function b:Refresh()
        local fd = labelFor(self._value)
        if fd then self.fs:SetFont(theme:ResolveFont(fd.path or fd.key), 13); self.fs:SetText(fd.label) end
    end
    b:SetScript("OnClick", function(self)
        local items = {}
        for _, fd in ipairs(fonts) do items[#items + 1] = { label = fd.label, value = fd.key, font = fd.path or fd.key, fontSize = 13 } end
        theme:OpenMenu(self, items, function() return self._value end, function(v)
            self._value = v; self:Refresh(); if opts.onChange then opts.onChange(v) end
        end)
    end)
    b:Refresh()
    return b
end
