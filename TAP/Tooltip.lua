-- UIFoundry - Tooltip.lua
-- A static, styled tooltip PREVIEW you can drop on a page to design/see tooltip content, plus
-- multi-line hover tooltips (theme:SetTip already does title + body; this adds line lists).
--
--   theme:TooltipPreview(parent, { title = "Fireball", width = 240, lines = {
--       "Deals |cffffffff1,240|r fire damage.",
--       { text = "Instant", color = "20C997" },
--       { text = "Cooldown: 8s", color = "subtext" },
--   } })
--
--   theme:SetTipLines(frame, "Title", { "line one", { text = "line two", color = "20C997" } })

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

-- Resolve a line's color: a palette key name, a hex string, an { r,g,b } table, or nil.
local function lineColor(theme, c, default)
    if type(c) == "string" and theme.C[c] then return theme.C[c] end
    return UIF.toColor(c, default or theme.C.text)
end

-- Render title + lines into a frame (used by TooltipPreview and the live tooltip).
local function renderLines(theme, target, title, lines, width, isPreview)
    -- target is a frame with :CreateFontString; returns total height used.
    local C = theme.C
    local y = -10
    if title then
        local t = target._uifTitle or target:CreateFontString(nil, "OVERLAY"); target._uifTitle = t
        theme:StyleFont(t, {}, { fontSize = 13, textColor = { theme:AccentHeader() } })
        t:SetText(title); t:ClearAllPoints(); t:SetPoint("TOPLEFT", 10, y); t:SetJustifyH("LEFT"); t:Show()
        y = y - (t:GetStringHeight() or 14) - 4
    end
    target._uifLines = target._uifLines or {}
    for _, l in ipairs(target._uifLines) do l:Hide() end
    for i, l in ipairs(lines or {}) do
        local fs = target._uifLines[i] or target:CreateFontString(nil, "OVERLAY"); target._uifLines[i] = fs
        local txt = type(l) == "table" and l.text or l
        local col = lineColor(theme, type(l) == "table" and l.color or nil, { 0.82, 0.86, 0.92 })
        fs:SetFont(theme.FONT, 12); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetWidth(width - 20)
        fs:SetText(theme:HL(txt)); fs:SetTextColor(col[1], col[2], col[3])
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 10, y); fs:Show()
        y = y - (fs:GetStringHeight() or 12) - 3
    end
    return -y + 8
end

-- A boxed, GameTooltip-styled preview.
function Mixin:TooltipPreview(parent, opts)
    opts = opts or {}
    local theme = self
    local width = opts.width or 240
    local f = CreateFrame("Frame", nil, parent)
    theme:StylePanel(f, opts.bg and UIF.toColor(opts.bg) or { 0.05, 0.05, 0.07 }, UIF.toColor(opts.borderColor, theme.C.accent))
    f:SetWidth(width)
    function f:SetContent(title, lines)
        local h = renderLines(theme, f, title, lines, width, true)
        f:SetHeight(math.max(opts.minHeight or 30, h))
    end
    f:SetContent(opts.title, opts.lines)
    return f
end

-- Attach a multi-line hover tooltip. lines: array of strings or { text, color } tables.
function Mixin:SetTipLines(frame, title, lines, anchor)
    if frame then frame._tipTitle, frame._tipLines, frame._tipBody, frame._tipAnchor = title, lines, nil, anchor end
    return frame
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
