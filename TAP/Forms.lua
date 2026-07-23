-- TAP - Forms.lua
-- SearchBox: a live filter input (search glyph, placeholder, clear button).

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

----------------------------------------------------------------------
-- SearchBox: an input with a search glyph, placeholder, and a clear (x) button. onChange
-- fires live per keystroke. Great for filtering lists.
--   theme:SearchBox(parent, { width=240, placeholder="Search...", onChange=function(t) end })
----------------------------------------------------------------------
function Mixin:SearchBox(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w, h = opts.width or 240, opts.height or 24
    local e = theme:EditBox(parent); e:Configure(w, h, opts.value or "", nil)
    e:SetTextInsets(opts.icon and 26 or 8, 22, 0, 0)
    e:ApplyStyle(opts)
    if opts.icon then
        e.searchIcon = e:CreateTexture(nil, "ARTWORK"); e.searchIcon:SetSize(14, 14); e.searchIcon:SetPoint("LEFT", 7, 0)
        e.searchIcon:SetTexture(theme:ResolveIcon(opts.icon) or opts.icon)
        local ic = TAP.toColor(opts.iconColor, C.subtext); e.searchIcon:SetVertexColor(ic[1], ic[2], ic[3])
    end
    e._ph = e:CreateFontString(nil, "OVERLAY"); theme:StyleFont(e._ph, opts, { fontSize = 11, textColor = C.subtext })
    e._ph:SetPoint("LEFT", opts.icon and 26 or 8, 0); e._ph:SetText(opts.placeholder or "Search...")

    local clr = CreateFrame("Button", nil, e); clr:SetSize(16, 16); clr:SetPoint("RIGHT", -4, 0); clr:Hide()
    clr.fs = clr:CreateFontString(nil, "OVERLAY"); theme:StyleFont(clr.fs, {}, { fontSize = 13, textColor = C.subtext }); clr.fs:SetPoint("CENTER"); clr.fs:SetText("x")
    clr:SetScript("OnEnter", function(self) self.fs:SetTextColor(unpack(theme.C.text)) end)
    clr:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(theme.C.subtext)) end)
    clr:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
    e.clear = clr

    e:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        self._ph:SetShown(t == ""); self.clear:SetShown(t ~= "")
        if opts.onChange then opts.onChange(t) end
    end)
    e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    return e
end
