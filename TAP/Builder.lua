-- UIFoundry - Builder.lua
-- An immediate-mode layout helper over a scroll content frame. Every page redraw calls
-- :Reset() then lays widgets out by (x, y) offsets from the content's TOPLEFT (y grows
-- downward as negatives). Widgets are pooled per builder, so rebuilding a page every
-- keystroke is cheap and never leaks frames.
--
--   local b = theme:Builder(contentFrame, { contentWidth = 660 })
--   -- inside a render:
--   b:Reset()
--   b:Section("GENERAL", 24, -20)
--   b:Toggle(24, -54, db.enabled, function(v) db.enabled = v end)
--   b:Label("Enable addon", 70, -56, theme.C.text)
--   b:Button(24, -100, 120, "Save", "primary", function() end)
--
-- Chaining widgets (dropdown / slider) return the widget so you can :SetChoices/:Configure.
-- SetTip works on anything returned:  theme:SetTip(b:Dropdown(x,y), "Title", "Body"):SetChoices(...)

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

-- Simple grow-only pool: acq hands out the next free widget of a kind (creating on demand);
-- releaseAll hides everything and rewinds the counters for the next frame.
local function acq(store, name, factory)
    local p = store[name]; if not p then p = { items = {}, used = 0 }; store[name] = p end
    p.used = p.used + 1
    local w = p.items[p.used]; if not w then w = factory(); p.items[p.used] = w end
    w._tipTitle, w._tipBody, w._tipAnchor, w._tipLines, w._tipIcon = nil, nil, nil, nil, nil   -- no stale tooltip
    w:Show(); return w
end
local function releaseAll(store)
    for _, p in pairs(store) do
        for i = p.used, 1, -1 do local w = p.items[i]; if w then w:Hide(); w:ClearAllPoints() end end
        p.used = 0
    end
end

local BuilderMixin = {}
local BuilderMeta = { __index = BuilderMixin }

-- Create a builder bound to a content frame. opts.contentWidth sets the default divider /
-- wrap width (defaults to the content frame's current width).
function Mixin:Builder(content, opts)
    opts = opts or {}
    return setmetatable({
        theme = self, content = content, pool = {},
        contentWidth = opts.contentWidth or content:GetWidth() or 660,
    }, BuilderMeta)
end

function BuilderMixin:Reset() releaseAll(self.pool) end

-- Position a widget relative to the content TOPLEFT.
function BuilderMixin:put(w, x, y) w:ClearAllPoints(); w:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y); return w end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------
function BuilderMixin:Label(text, x, y, color, size)
    local theme = self.theme
    local fs = acq(self.pool, "label", function() return self.content:CreateFontString(nil, "OVERLAY") end)
    -- Reset width/justify/wrap: a pooled fontstring may carry a prior caller's SetWidth (e.g. the
    -- centred pager label), which would otherwise constrain this label and wrap its text.
    fs:SetWidth(0); fs:SetWordWrap(false); fs:SetJustifyH("LEFT")
    fs:SetFont(theme.FONT, size or 12); fs:SetText(theme:HL(text))
    fs:SetTextColor(unpack(color or theme.C.text)); self:put(fs, x, y); return fs
end

-- Word-wrapped read-only text; returns the fontstring and its rendered height.
function BuilderMixin:Wrap(text, x, y, w, color, size)
    local theme = self.theme
    local fs = acq(self.pool, "wrap", function() return self.content:CreateFontString(nil, "OVERLAY") end)
    fs:SetFont(theme.FONT, size or 11); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
    fs:SetWidth(w); fs:SetText(theme:HL(text)); fs:SetTextColor(unpack(color or theme.C.subtext))
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y); fs:Show()
    return fs, (fs:GetStringHeight() or 14)
end

-- Section header: accent label + a full-width divider under it.
function BuilderMixin:Section(text, x, y, w)
    local theme = self.theme
    self:Label(text, x, y, theme.C.accent, 12)
    local d = acq(self.pool, "divider", function() return self.content:CreateTexture(nil, "ARTWORK") end)
    d:SetColorTexture(theme.C.border[1], theme.C.border[2], theme.C.border[3], 0.8); d:SetHeight(1)
    -- Default width = full content span minus a symmetric left/right margin equal to x, so the
    -- underline ends the same distance from the right edge as it starts from the left.
    d:ClearAllPoints(); d:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y - 18)
    d:SetWidth(w or (self.contentWidth - 2 * (x or 0))); d:Show()
end

-- Lighter sub-header used inside a section.
function BuilderMixin:Sub(text, x, y, w)
    local theme = self.theme
    self:Label(text, x, y, theme.C.accent, 11)
    local d = acq(self.pool, "divider", function() return self.content:CreateTexture(nil, "ARTWORK") end)
    d:SetColorTexture(theme.C.border[1], theme.C.border[2], theme.C.border[3], 0.45); d:SetHeight(1)
    d:ClearAllPoints(); d:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y - 15)
    d:SetWidth(w or (self.contentWidth - 2 * (x or 0))); d:Show()
end

----------------------------------------------------------------------
-- Widgets (pooled)
----------------------------------------------------------------------
-- The trailing `opts` on these forwards the full style-override table (color, icon, radius,
-- font, border, ...) to the widget, so anything you can style directly also styles here.
function BuilderMixin:Toggle(x, y, checked, cb, opts)
    local w = acq(self.pool, "toggle", function() return self.theme:Toggle(self.content) end)
    w:Configure(checked, cb, opts); return self:put(w, x, y)
end

function BuilderMixin:Button(x, y, w_, text, kind, cb, opts)
    local b = acq(self.pool, "button", function() return self.theme:Button(self.content) end)
    b:Configure(text, w_, (opts and opts.height) or 26, kind, cb, opts); return self:put(b, x, y)
end

function BuilderMixin:Dropdown(x, y)
    local d = acq(self.pool, "dd", function() return self.theme:Dropdown(self.content) end)
    return self:put(d, x, y)
end

function BuilderMixin:EditBox(x, y, w_, value, onCommit, opts)
    local e = acq(self.pool, "edit", function() return self.theme:EditBox(self.content) end)
    e:Configure(w_, (opts and opts.height) or 24, value, onCommit)
    if opts then e:ApplyStyle(opts) end
    return self:put(e, x, y)
end

function BuilderMixin:Slider(x, y, opts)
    local s = acq(self.pool, "slider", function() return self.theme:Slider(self.content) end)
    if opts then s._style = opts end   -- applied on the caller's :Configure
    return self:put(s, x, y)
end

function BuilderMixin:Icon(x, y, opts)
    local theme = self.theme
    local b = acq(self.pool, "icon", function() return theme:Icon(self.content) end)
    theme:StylePanel(b, theme.C.bg)                -- pooled: re-apply shape so a live skin swap sticks
    b:SetSize(20, 20)                              -- reset: pooled, a prior caller may have resized it
    b.tex:SetTexCoord(unpack(theme.iconInset))     -- reset the default crop too
    b.tex:SetVertexColor(1, 1, 1)                  -- reset tint
    if opts then b:ApplyStyle(opts) end
    return self:put(b, x, y)
end

function BuilderMixin:Swatch(x, y, colorTbl, onChange, tipTitle, tipBody)
    local s = acq(self.pool, "swatch", function() return self.theme:Swatch(self.content) end)
    s:Configure(colorTbl, onChange, tipTitle, tipBody)
    return self:put(s, x, y)
end

function BuilderMixin:Logo(x, y, size, texture)
    local f = acq(self.pool, "logo", function() return self.theme:Logo(self.content) end)
    f:SetLogo(texture, size)
    return self:put(f, x, y)
end

function BuilderMixin:Preview(x, y, w, h)
    local f = acq(self.pool, "preview", function() return self.theme:Preview(self.content) end)
    f:SetSize(w, h)
    return self:put(f, x, y)
end

----------------------------------------------------------------------
-- Background decoration (drawn on the content BACKGROUND / ARTWORK layers, behind widgets)
----------------------------------------------------------------------
-- Filled rectangle. Deeper nesting can pass a higher `sub` sublevel so a nested tint shows
-- over its parent's.
function BuilderMixin:Box(x, yTop, w, h, alpha, sub, col)
    col = col or self.theme.C.accent
    local t = acq(self.pool, "box", function() return self.content:CreateTexture(nil, "BACKGROUND") end)
    t:SetDrawLayer("BACKGROUND", sub or 0)
    t:SetColorTexture(col[1], col[2], col[3], alpha or 0.06)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, yTop)
    t:SetSize(math.max(1, w), math.max(1, h)); t:Show()
    return t
end

-- Thin vertical rail (e.g. a group bracket), on ARTWORK so it shows over a Box tint.
function BuilderMixin:VRule(x, yTop, yBottom, sub, col)
    col = col or self.theme.C.accent
    local t = acq(self.pool, "vrule", function() return self.content:CreateTexture(nil, "ARTWORK") end)
    t:SetDrawLayer("ARTWORK", sub or 0)
    t:SetColorTexture(col[1], col[2], col[3], 0.85); t:SetWidth(2)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, yTop)
    t:SetHeight(math.max(2, yTop - yBottom)); t:Show()
    return t
end

-- Interactive list row for zebra-striped, hover-highlighted tables. A pooled Button with a
-- background drawn BEHIND the row's content (place labels/Glyphs on top - FontStrings/Glyph
-- frames are non-interactive, so the whole row stays hoverable and clickable). Brightens + shows
-- an accent left-edge on hover, and reveals a tooltip if one is set.
--   opts = { index (for the zebra stripe), onClick, color, tipTitle, tipBody, tipAnchor }
function BuilderMixin:Row(x, yTop, w, h, opts)
    opts = opts or {}
    local theme, C = self.theme, self.theme.C
    w, h = math.max(1, w), math.max(1, h)
    -- The highlight + accent edge are CONTENT textures on BACKGROUND, so they sit UNDER the row's
    -- labels/icons (drawn on ARTWORK). The Button on top carries no textures - it only captures the
    -- mouse for hover/click, so the highlight never covers the text.
    local bg = acq(self.pool, "rowbg", function() return self.content:CreateTexture(nil, "BACKGROUND", nil, 0) end)
    local edge = acq(self.pool, "rowedge", function() return self.content:CreateTexture(nil, "BACKGROUND", nil, 1) end)
    bg:ClearAllPoints(); bg:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, yTop); bg:SetSize(w, h); bg:Show()
    edge:ClearAllPoints(); edge:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, yTop); edge:SetSize(2, h); edge:Show()
    local col = opts.color or C.card
    local base = (opts.index and (opts.index % 2 == 0)) and 0.07 or 0.02   -- zebra stripe
    bg:SetColorTexture(col[1], col[2], col[3], base)
    edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0)
    local r = acq(self.pool, "row", function() return CreateFrame("Button", nil, self.content) end)
    r:SetSize(w, h); r:ClearAllPoints(); r:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, yTop)
    r._bg, r._edge, r._col, r._base = bg, edge, col, base
    r:SetScript("OnEnter", function(s)
        s._bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 0.6)
        s._edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        theme:_showTip(s)
    end)
    r:SetScript("OnLeave", function(s)
        s._bg:SetColorTexture(s._col[1], s._col[2], s._col[3], s._base)
        s._edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0)
        GameTooltip_Hide()
    end)
    r:SetScript("OnClick", opts.onClick)
    if opts.tipData then theme:SetTipData(r, opts.tipData)
    elseif opts.tipTitle then theme:SetTip(r, opts.tipTitle, opts.tipBody, opts.tipAnchor) end
    -- Table-row tooltips follow the cursor by default (nicer for dense, tall tables than a fixed
    -- ANCHOR_RIGHT that can land off-screen), unless the caller asked for a specific anchor.
    if r._tipTitle or r._tipLines then r._tipAnchor = r._tipAnchor or "ANCHOR_CURSOR" end
    return r
end

-- Pooled decorative texture (non-interactive, so the mouse passes through to a Row behind it).
-- Ideal for class / spec / dungeon icons in list rows - unlike the rich Glyph, this is pooled, so
-- it's cheap even with many rows. `texture` may be a fileID, a path, or a bundled icon name;
-- `coords` = {l,r,t,b} (e.g. CLASS_ICON_TCOORDS); `color` tints (defaults white = untinted).
-- `sub` optionally raises the ARTWORK sublevel so layered textures (icon behind, frame on top)
-- render deterministically despite texture pooling. Defaults to 1.
function BuilderMixin:Tex(x, y, w, h, texture, coords, color, sub)
    local t = acq(self.pool, "tex", function() return self.content:CreateTexture(nil, "ARTWORK") end)
    t:SetDrawLayer("ARTWORK", sub or 1)
    t:SetTexture(self.theme:IconPath(texture) or texture)
    if coords then t:SetTexCoord(unpack(coords)) else t:SetTexCoord(0, 1, 0, 1) end
    local col = color or { 1, 1, 1 }
    t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y)
    t:SetSize(math.max(1, w), math.max(1, h)); t:Show()
    return t
end

-- Pooled transparent click region with NO chrome - just a faint auto-highlight on hover (a
-- HIGHLIGHT-layer texture, shown by the client only while moused over). For making plain labels
-- or areas clickable (e.g. sortable table headers) without a full Button's border/background.
function BuilderMixin:Hit(x, y, w, h, onClick, tipTitle, tipBody)
    local theme = self.theme
    local btn = acq(self.pool, "hit", function()
        local f = CreateFrame("Button", nil, self.content)
        f.hl = f:CreateTexture(nil, "ARTWORK", nil, 3)
        f.hl:SetAllPoints(); f.hl:SetColorTexture(1, 1, 1, 0.10); f.hl:Hide()
        f:SetScript("OnEnter", function(s) s.hl:Show(); theme:_showTip(s) end)
        f:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip_Hide() end)
        return f
    end)
    btn:SetSize(math.max(1, w), math.max(1, h))
    btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y)
    btn:SetScript("OnClick", onClick)
    if tipTitle then theme:SetTip(btn, tipTitle, tipBody) end
    return btn
end

----------------------------------------------------------------------
-- Richer components. Each takes an opts table so you can restyle at draw time (fontSize,
-- colors, borders, backgrounds, fonts, icons, ...). Unlike the simple widgets above, rich
-- components can't cheaply re-skin from arbitrary opts, so they use a TRANSIENT model:
-- created fresh per call and registered so :Reset() hides them. That's ideal for pages that
-- redraw on view changes; for a page that rebuilds on every keystroke, build the rich
-- component once yourself and reposition it instead of drawing it through the Builder.
----------------------------------------------------------------------
local function put(self, w, x, y) w:ClearAllPoints(); w:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y); return w end

-- Register a transient so the next Reset() hides it.
local function transient(self, w)
    self._transient = self._transient or {}
    self._transient[#self._transient + 1] = w
    return w
end

-- Public: adopt an externally-created frame into the page lifecycle - it's hidden on the next
-- :Reset() (i.e. when the page redraws or the view changes). Re-call each render to keep it up;
-- lets a consumer embed its own persistent frame (e.g. a live preview) on a builder page.
function BuilderMixin:Transient(w) return transient(self, w) end

-- Extend Reset to also hide transient components.
local _baseReset = BuilderMixin.Reset
function BuilderMixin:Reset()
    _baseReset(self)
    if self._transient then
        for i = #self._transient, 1, -1 do local w = self._transient[i]; w:Hide(); w:ClearAllPoints() end
        self._transient = {}
    end
end

-- Heading via a role (display/h1..h6/title/subtitle/overline/caption/label/body) + overrides.
-- Pooled (it's a plain fontstring), so cheap even in per-keystroke rebuilds.
function BuilderMixin:Heading(text, x, y, role, opts)
    opts = opts or {}
    local fs = acq(self.pool, "heading", function() return self.content:CreateFontString(nil, "OVERLAY") end)
    local r = UIF.HEADING_ROLES[role or opts.role or "h3"] or UIF.HEADING_ROLES.h3
    self.theme:StyleFont(fs, opts, { fontSize = r.fontSize, fontFlags = r.fontFlags, textColor = self.theme.C[r.color] or self.theme.C.text, justify = "LEFT" })
    local t = text or ""
    if (opts.upper == nil and r.upper) or opts.upper then t = t:upper() end
    -- Reset any width a prior (pooled) caller left on this fontstring, else a leaked width would
    -- wrap/clip this heading. Only constrain when this caller explicitly asked to wrap.
    fs:SetWordWrap(opts.wrapWidth ~= nil); fs:SetWidth(opts.wrapWidth or 0)
    fs:SetText(self.theme:HL(t)); return put(self, fs, x, y)
end

-- Draw-at-(x,y) wrappers for the transient rich components. Return the live component.
local RICH = {
    "ProgressBar", "Spinner", "Badge", "Card", "StatTile", "Separator", "Avatar",
    "RadioGroup", "SegmentedControl", "Stepper", "SearchBox", "TextArea",
    "TabBar", "Accordion", "SocialButton", "Glyph",
    "RangeSlider", "ComboBox", "FontSelect", "TooltipPreview", "ClassSpecButton",
    "Portrait2D", "PortraitModel", "UnitModel", "GameIcon", "SoundSelect",
}
for _, kind in ipairs(RICH) do
    BuilderMixin[kind] = function(self, x, y, opts)
        return put(self, transient(self, self.theme[kind](self.theme, self.content, opts)), x, y)
    end
end

-- SocialBar takes a list + layout opts rather than a single opts table.
function BuilderMixin:SocialBar(x, y, list, opts)
    return put(self, transient(self, self.theme:SocialBar(self.content, list, opts)), x, y)
end

----------------------------------------------------------------------
-- Grid / columns (responsive)
----------------------------------------------------------------------
-- Lay a list of `cells` out across columns. Each cell is a function(cellX, cellWidth, cellTopY)
-- that renders that column starting at cellTopY and RETURNS the y it ended at (most negative).
-- Cells fill left-to-right and wrap to new rows when they exceed the column count; each row is
-- as tall as its tallest cell. Returns the y below the whole grid.
--
--   b:Grid(x, y, { cellA, cellB, cellC }, { columns = 3, gap = 20, minColWidth = 190, width = w })
--
-- opts: columns (max, default #cells) · gap (h-gap, 20) · rowGap (v-gap, 14) ·
--       width (total; default content width from x) · minColWidth (drop columns until each is at
--       least this wide -> responsive to the frame). Pass the builder's live `contentWidth` (which
--       tracks a contentFluid window) as `width` to react to maximize.
function BuilderMixin:Grid(x, yTop, cells, opts)
    opts = opts or {}
    local n = #cells
    if n == 0 then return yTop end
    local totalW = opts.width or (self.contentWidth - x - 24)
    local gap = opts.gap or 20
    local cols = opts.columns or n
    if opts.minColWidth then
        local fit = math.floor((totalW + gap) / (opts.minColWidth + gap))
        cols = math.max(1, math.min(cols, fit))
    end
    cols = math.max(1, math.min(cols, n))
    local colW = math.floor((totalW - gap * (cols - 1)) / cols)
    local y, i = yTop, 1
    while i <= n do
        local rowBottom = y
        for c = 0, cols - 1 do
            local cell = cells[i]; if not cell then break end
            local endY = cell(x + c * (colW + gap), colW, y)
            if type(endY) == "number" and endY < rowBottom then rowBottom = endY end
            i = i + 1
        end
        y = rowBottom - (opts.rowGap or 14)
    end
    return y
end

UIF.BuilderMixin = BuilderMixin   -- exposed so consumers can add their own builder helpers
