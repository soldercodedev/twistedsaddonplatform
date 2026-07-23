-- TAP - Selectors.lua
-- FontSelect: a dropdown where each option's label is rendered in its own font.

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

----------------------------------------------------------------------
-- FontSelect: a dropdown where each option's label is rendered in that font, so you can see what
-- you're picking. Built on the standard Dropdown (SetMenu) rather than a hand-rolled shell; the
-- closed-state label is rendered in the selected font via the labelFor hook. Uses the theme's font
-- registry (bundled set by default).
--   theme:FontSelect(parent, { width=200, value="UBUNTU", onChange=function(key) end })
----------------------------------------------------------------------
function Mixin:FontSelect(parent, opts)
    opts = opts or {}
    local theme = self
    local fonts = opts.fonts or theme:FontList()
    local function fdFor(key)
        for _, fd in ipairs(fonts) do if fd.key == key then return fd end end
        return fonts[1]
    end
    local dd = theme:Dropdown(parent)
    dd._value = opts.value or (fonts[1] and fonts[1].key)
    return dd:SetMenu(opts.width or 200,
        function()   -- each option's row rendered in its own font
            local items = {}
            for _, fd in ipairs(fonts) do
                items[#items + 1] = { label = fd.label, value = fd.key, font = fd.path or fd.key, fontSize = 13 }
            end
            return items
        end,
        function() return dd._value end,
        function(v) dd._value = v; if opts.onChange then opts.onChange(v) end end,
        function(key)   -- labelFor: render the closed-state label in the selected font
            local fd = fdFor(key)
            if fd then dd.fs:SetFont(theme:ResolveFont(fd.path or fd.key), 13) end
            return fd and fd.label or ""
        end)
end
