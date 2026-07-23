-- TAP - Tooltip.lua
-- Rich multi-line hover tooltips: theme:SetTipData(frame, { icon, title, anchor, lines = {...} })
-- attaches structured lines (plain, colored, two-column, spacers, dividers) that the extended
-- _showTip renderer below emits. (theme:SetTip already handles a plain title + body.)

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

-- Resolve a line's color: a palette key name, a hex string, an { r,g,b } table, or nil.
local function lineColor(theme, c, default)
    if type(c) == "string" and theme.C[c] then return theme.C[c] end
    return TAP.toColor(c, default or theme.C.text)
end

-- Attach a RICH hover tooltip. data = {
--   icon   = texture/fileID,           -- shown inline before the title
--   title  = "Header",
--   anchor = "ANCHOR_RIGHT",
--   lines  = {                          -- each entry is one of:
--     "plain wrapped line",
--     { text = "colored line", color = "accent"|"20C997"|{r,g,b} },
--     { left = "Label", right = "Value", lcolor = ..., rcolor = ... },   -- aligned two columns
--     { blank = true },                 -- vertical spacer
--     { sep = true },                   -- faint divider line
--   } }
function Mixin:SetTipData(frame, data)
    if not frame then return frame end
    data = data or {}
    frame._tipTitle    = data.title
    frame._tipLines    = data.lines
    frame._tipIcon     = data.icon
    frame._tipBody     = nil
    frame._tipAnchor   = data.anchor
    frame._tipMinWidth = data.minWidth   -- force a wider tooltip so long lines wrap less (optional)
    return frame
end

-- Extend the live tooltip renderer to also emit _tipLines / _tipIcon and the richer line specs
-- (kept in sync with Theme's _showTip). Backward-compatible with string / { text, color } lines.
local baseShowTip = Mixin._showTip
function Mixin:_showTip(f)
    if f._tipLines then
        GameTooltip:SetOwner(f, f._tipAnchor or "ANCHOR_RIGHT")
        -- Force a minimum width (or clear it for the next tooltip). A wider box lets wrapped detail
        -- lines use the extra room instead of stacking into three cramped rows.
        GameTooltip:SetMinimumWidth(f._tipMinWidth or 0)
        local title = f._tipTitle or " "
        if f._tipIcon then title = "|T" .. tostring(f._tipIcon) .. ":18:18:0:0|t " .. title end
        GameTooltip:SetText(title, self:AccentHeader())
        for _, l in ipairs(f._tipLines) do
            if type(l) == "table" and l.blank then
                GameTooltip:AddLine(" ")
            elseif type(l) == "table" and l.sep then
                GameTooltip:AddLine("|cff3a3f4a------------------------------|r")
            elseif type(l) == "table" and (l.left ~= nil or l.right ~= nil) then
                local lc = lineColor(self, l.lcolor, self.C.subtext)
                local rc = lineColor(self, l.rcolor, { 0.96, 0.97, 1 })
                GameTooltip:AddDoubleLine(self:HL(l.left or ""), self:HL(l.right or ""),
                    lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
            else
                local txt = type(l) == "table" and l.text or l
                local col = lineColor(self, type(l) == "table" and l.color or nil, { 0.82, 0.86, 0.92 })
                GameTooltip:AddLine(self:HL(txt), col[1], col[2], col[3], true)
            end
        end
        GameTooltip:Show()
        return
    end
    return baseShowTip(self, f)
end
