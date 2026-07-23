-- TAP - Tabs.lua
-- NavBar: a horizontal navigation strip of segmented buttons (the docked page top-nav).

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

----------------------------------------------------------------------
-- NavBar: a horizontal navigation strip of segmented buttons - one per item, one marked active -
-- meant to dock across the top of a body/content frame. Each item is an optional ICON plus a label.
-- By default the buttons fill the given width evenly (pass tabWidth to fix their size). Pooled +
-- reconfigurable, so redrawing it every frame is cheap.
--   local nav = theme:NavBar(parent)
--   nav:Configure({ items = { {key="overview", label="Overview", icon="layout-grid"}, ... },
--       active = "overview", width = 700, onSelect = function(key) ... end,
--       tip = function(key) return TIPS[key] end })
--   local h = nav:GetHeight()   -- for laying out content below it
----------------------------------------------------------------------
function Mixin:NavBar(parent)
    local theme = self
    local f = CreateFrame("Frame", nil, parent)
    f.buttons = {}
    f.line = f:CreateTexture(nil, "ARTWORK"); f.line:SetHeight(2)

    function f:Configure(opts)
        opts = opts or {}
        local items = opts.items or {}
        local n = #items
        local gap = opts.gap or 4
        local h = opts.height or 28
        local width = opts.width or (parent.GetWidth and parent:GetWidth()) or 600
        local tw = opts.tabWidth or math.max(40, math.floor((width - math.max(0, n - 1) * gap) / math.max(1, n)))
        -- Hide any pooled buttons beyond the current item count.
        for i = n + 1, #self.buttons do self.buttons[i]:Hide() end
        for i, it in ipairs(items) do
            local btn = self.buttons[i]
            if not btn then btn = theme:Button(self); self.buttons[i] = btn end
            local active = (it.key == opts.active)
            btn:Configure(it.label, tw, h, active and "primary" or "default",
                function() if opts.onSelect then opts.onSelect(it.key) end end,
                it.icon and { icon = it.icon, iconSize = it.iconSize or 14 } or nil)
            btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", (i - 1) * (tw + gap), 0); btn:Show()
            if theme.SetTip then theme:SetTip(btn, it.label, (opts.tip and opts.tip(it.key)) or it.label) end
        end
        f:SetSize(math.max(1, width), h + 8)
        -- Accent baseline across the whole bar (the "docked header" underline).
        f.line:ClearAllPoints(); f.line:SetPoint("TOPLEFT", 0, -h - 2); f.line:SetWidth(math.max(1, width))
        TAP.paint(f.line, theme.C.accent); f.line:SetAlpha(0.5); f.line:Show()
    end
    return f
end
