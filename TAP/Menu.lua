-- TAP - Menu.lua
-- The popup engine behind every select control. One menu, two modes:
--
--   single - click a row, the menu closes and onPick(value) fires
--   multi  - checkbox rows; the menu STAYS open and onToggle(value, checked) fires per click
--
-- Both modes get a type-to-filter search box (it appears on its own once the list is long),
-- section headers, dividers, per-row icons / notes / fonts, rows that explain why they are
-- disabled, hover submenus, arrow-key navigation, and a thin scrollbar with smooth wheel
-- scrolling. Everything is pooled per theme: one menu frame (plus one flyout) is reused by
-- every dropdown in the addon, so opening a 300-row list never creates 300 frames again.
--
--   theme:OpenMenu(anchorFrame, items, getSelected, onPick)   -- classic positional form
--   theme:OpenMenu(anchorFrame, opts)                         -- full form
--   theme:CloseMenu()                                         -- close whatever is open
--   theme:MenuIsOpen([anchorFrame])                           -- open at all / open for that control
--
-- opts:
--   items        array, or function() -> array (re-evaluated on every open)
--   width        menu width (default: the anchor's width, min 170)
--   selected     the selected value, or function() -> value            [single]
--   onPick       function(value) - row picked; the menu then closes    [single]
--   multi        true -> checkbox rows that keep the menu open         [multi]
--   checked      function(value) -> bool                              [multi]
--   onToggle     function(value, checked)                             [multi]
--   selectAll    false to drop the automatic "Select all / Clear" rows [multi]
--   actions      { { label =, icon =, onClick =, keepOpen = }, ... } pinned above the search
--   search       true / false / a row-count threshold (default: auto at 10 rows)
--   placeholder  search box placeholder ("Search...")
--   itemHeight   row height (default 24)
--   maxHeight    tallest the list may grow before it scrolls (default 320)
--   autoFocus    false to stop the search box taking keyboard focus on open
--   onClose      function() - fired when the menu closes
--
-- items (each entry is one of):
--   { label, value }                            a selectable row
--   { label, header = true }                    a section header (label + hairline rule)
--   { divider = true }                          a separator line
--   { label, value, note = "8 runs" }           dim trailing note
--   { label, value, icon =, coords =, iconColor =, variant = }
--   { label, value, font =, fontSize = }        row rendered in a specific font
--   { label, value, color = }                   label color override
--   { label, value, disabled = true | "why" }   dim + unclickable; a string shows as a tooltip
--   { label, value, tip = "..." | { title =, body = } }   hover tooltip
--   { label, value, keywords = "..." }          extra text the search matches on
--   { label, submenu = { ...items... } }        opens a flyout on hover
--   { label, onClick = function() end }         an action row (runs, no value)

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

local MIN_W, MAX_H        = 170, 320
local ROW_H, HDR_H, DIV_H = 24, 20, 9
local SEARCH_H, PAD       = 24, 4
local SEARCH_AUTO         = 10     -- rows before the filter box shows up on its own
local FLYOUT_DELAY        = 0.25   -- grace period so the mouse can travel into a submenu
local SCROLL_STEP         = 44     -- pixels per wheel notch
local SCROLL_SPEED        = 16     -- how fast the smooth scroll catches its target

-- Rows come in three shapes; everything else is a normal (selectable / checkable) row.
local function rowKind(it)
    if it.divider then return "divider" end
    if it.header then return "header" end
    return "row"
end

-- A row is pickable when it carries a value, an action, or a submenu, and is not disabled.
local function isPickable(it)
    if rowKind(it) ~= "row" then return false end
    if it.disabled then return false end
    return it.value ~= nil or it.onClick ~= nil or it.submenu ~= nil
end

-- Text the search box matches against.
local function haystack(it)
    return string.lower(tostring(it.label or "") .. " " .. tostring(it.note or "") .. " " .. tostring(it.keywords or ""))
end

----------------------------------------------------------------------
-- Row frame
----------------------------------------------------------------------
local function makeRow(theme, menu, parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW_H)
    b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:Hide()
    -- Divider / header hairline (one texture serves both: full width for a divider, a short
    -- rule trailing the caption for a header).
    b.line = b:CreateTexture(nil, "ARTWORK"); b.line:SetHeight(1); b.line:Hide()
    b.dot = b:CreateTexture(nil, "ARTWORK"); b.dot:SetSize(5, 5); b.dot:SetPoint("LEFT", 8, 0); b.dot:Hide()
    -- Checkbox: border texture, inset fill, and the check glyph on top.
    b.box = b:CreateTexture(nil, "ARTWORK"); b.box:SetSize(14, 14); b.box:SetPoint("LEFT", 7, 0); b.box:Hide()
    b.boxIn = b:CreateTexture(nil, "ARTWORK", nil, 1); b.boxIn:Hide()
    b.boxIn:SetPoint("TOPLEFT", b.box, "TOPLEFT", 1, -1); b.boxIn:SetPoint("BOTTOMRIGHT", b.box, "BOTTOMRIGHT", -1, 1)
    b.check = b:CreateTexture(nil, "OVERLAY"); b.check:SetSize(10, 10); b.check:SetPoint("CENTER", b.box, "CENTER"); b.check:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:Hide()
    -- Both fontstrings get a font up front: assigning text to one that has none is an error,
    -- and Render can reach SetText before it picks the row's font (a divider, say).
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(theme.FONT, 12)
    b.fs:SetJustifyH("LEFT"); b.fs:SetWordWrap(false); b.fs:SetMaxLines(1)
    b.note = b:CreateFontString(nil, "OVERLAY"); b.note:SetFont(theme.FONT, 10)
    b.note:SetJustifyH("RIGHT"); b.note:SetWordWrap(false); b.note:Hide()
    b.arrow = b:CreateTexture(nil, "ARTWORK"); b.arrow:SetSize(9, 9); b.arrow:SetPoint("RIGHT", -6, 0); b.arrow:Hide()

    -- Hover: highlight, tooltip (or the reason the row is disabled), and open its submenu.
    b:SetScript("OnEnter", function(self)
        local it = self._item; if not it then return end
        if isPickable(it) then menu:SetCursor(self._index) end
        if type(it.disabled) == "string" then
            theme:SetTip(self, it.label, it.disabled); theme:_showTip(self)
        elseif it.tip then
            if type(it.tip) == "table" then theme:SetTip(self, it.tip.title or it.label, it.tip.body, it.tip.anchor)
            else theme:SetTip(self, it.label, it.tip) end
            theme:_showTip(self)
        end
        if it.submenu then menu:OpenFlyout(self) else menu:QueueFlyoutClose() end
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip_Hide()
        self._tipTitle, self._tipBody, self._tipAnchor = nil, nil, nil
        if self._item and self._item.submenu then menu:QueueFlyoutClose() end
        if menu.cursor == self._index then menu:SetCursor(nil) end
    end)
    b:SetScript("OnClick", function(self) menu:Activate(self._index) end)

    -- Repaint the state-driven bits (hover wash, selected accent, check mark) without a
    -- rebuild, so toggling one checkbox in multi mode just repaints every row.
    function b:Paint()
        local C, it, cfg = theme.C, self._item, menu.cfg
        if not it or not cfg or rowKind(it) ~= "row" then return end
        local hovered = (menu.cursor == self._index)
        local sel = (not cfg.multi) and it.value ~= nil and cfg.isSelected(it.value)
        if it.disabled then
            self.hl:Hide()
            self.fs:SetTextColor(C.subtext[1] * 0.7, C.subtext[2] * 0.7, C.subtext[3] * 0.7)
        elseif hovered then
            TAP.paint(self.hl, TAP.mix(C.card, C.accent, 0.55)); self.hl:Show()
            self.fs:SetTextColor(1, 1, 1)
        elseif sel then
            TAP.paint(self.hl, TAP.mix(C.panel, C.accent, 0.22)); self.hl:Show()
            self.fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        else
            self.hl:Hide()
            local col = it.color and TAP.toColor(it.color, C.text) or C.text
            self.fs:SetTextColor(col[1], col[2], col[3])
        end
        self.dot:SetShown(sel and not it.icon and not cfg.multi)
        if sel then TAP.paint(self.dot, C.accent) end
        if cfg.multi and it.value ~= nil then
            local on = cfg.isChecked(it.value)
            TAP.paint(self.box, on and C.accent or C.border)
            TAP.paint(self.boxIn, on and C.accent or C.bg)
            self.check:SetShown(on and self._checkArt ~= nil)
        end
    end

    -- Full (re)draw from an item. Called once per row per open; Paint() handles state after that.
    function b:Render(it, index, cfg)
        local C = theme.C
        self._item, self._index = it, index
        local k = rowKind(it)
        self.hl:Hide(); self.line:Hide(); self.dot:Hide(); self.icon:Hide(); self.arrow:Hide()
        self.box:Hide(); self.boxIn:Hide(); self.check:Hide(); self.note:Hide()
        self.fs:ClearAllPoints(); self.fs:SetPoint("RIGHT", -6, 0)

        if k == "divider" then
            self:SetHeight(DIV_H); self:EnableMouse(false); self.fs:SetText("")
            self.line:ClearAllPoints()
            self.line:SetPoint("LEFT", 8, 0); self.line:SetPoint("RIGHT", -8, 0)
            self.line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.55); self.line:Show()
            return
        end

        if k == "header" then
            self:SetHeight(HDR_H); self:EnableMouse(false)
            self.fs:SetFont(theme.FONT, it.fontSize or 10)
            self.fs:SetText(it.label); self.fs:SetTextColor(unpack(C.subtext))
            -- Left anchor only: the caption sizes to its text so the rule can take the rest of
            -- the row (a stretched fontstring would leave the hairline no width at all).
            self.fs:ClearAllPoints(); self.fs:SetPoint("LEFT", 8, 0)
            -- Hairline trailing the caption, so sections read as groups instead of stray labels.
            self.line:ClearAllPoints()
            self.line:SetPoint("LEFT", self.fs, "RIGHT", 6, 0); self.line:SetPoint("RIGHT", -8, 0)
            self.line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.45); self.line:Show()
            return
        end

        self:SetHeight(cfg.itemHeight); self:EnableMouse(true)
        self.fs:SetFont(it.font and theme:ResolveFont(it.font) or theme.FONT, it.fontSize or 12)
        self.fs:SetText(it.label or "")

        local left = 18   -- default: room for the selected dot
        if cfg.multi and it.value ~= nil then
            self.box:Show(); self.boxIn:Show()
            -- Bundled check glyph when the theme has an icon dir; without one the box just fills
            -- with the accent (the same fallback the standalone Checkbox widget uses).
            self._checkArt = theme:GetIcon("check")
            if self._checkArt then
                self.check:SetTexture(self._checkArt); self.check:SetTexCoord(0, 1, 0, 1)
                self.check:SetVertexColor(0.05, 0.06, 0.08)
            end
            left = 27
        end
        if it.icon then
            -- Icons sit after the checkbox in multi mode, otherwise hard against the left pad
            -- (a row with an icon shows no selected dot, so the dot gutter is free).
            self.icon:ClearAllPoints()
            self.icon:SetPoint("LEFT", (cfg.multi and it.value ~= nil) and left or 8, 0)
            self.icon:SetTexture(theme:IconPath(it.icon, it.variant) or it.icon)
            if it.coords then self.icon:SetTexCoord(it.coords[1], it.coords[2], it.coords[3], it.coords[4])
            elseif theme:GetIcon(it.icon) then self.icon:SetTexCoord(0, 1, 0, 1)
            else self.icon:SetTexCoord(unpack(theme.iconInset)) end
            local ic = it.iconColor and TAP.toColor(it.iconColor) or nil
            if ic then self.icon:SetVertexColor(ic[1], ic[2], ic[3]) else self.icon:SetVertexColor(1, 1, 1) end
            self.icon:Show()
            self.fs:SetPoint("LEFT", self.icon, "RIGHT", 7, 0)
        else
            self.fs:SetPoint("LEFT", left, 0)
        end
        if it.note then
            self.note:SetFont(theme.FONT, 10); self.note:SetText(it.note)
            self.note:SetTextColor(theme.C.subtext[1], theme.C.subtext[2], theme.C.subtext[3])
            self.note:ClearAllPoints(); self.note:SetPoint("RIGHT", -8, 0); self.note:Show()
            self.fs:SetPoint("RIGHT", self.note, "LEFT", -6, 0)
        end
        if it.submenu then
            local art = theme:GetIcon("chevron-right")
            if art then
                self.arrow:SetTexture(art)
                self.arrow:SetVertexColor(theme.C.subtext[1], theme.C.subtext[2], theme.C.subtext[3])
                self.arrow:Show()
                self.fs:SetPoint("RIGHT", self.arrow, "LEFT", -4, 0)
            end
        end
        self:Paint()
    end
    return b
end

----------------------------------------------------------------------
-- Menu frame. Two exist per theme: depth 1 is the menu itself, depth 2 its submenu flyout.
----------------------------------------------------------------------
local function makeMenu(theme, depth)
    local m = CreateFrame("Frame", TAP.NextId(theme.id .. "Menu"), UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetToplevel(true); m:SetClampedToScreen(true)
    m:EnableMouse(true); m:Hide()
    m.depth, m.rows, m.pins = depth, {}, {}

    m.scroll = CreateFrame("ScrollFrame", nil, m)
    m.child = CreateFrame("Frame", nil, m.scroll); m.child:SetSize(10, 10)
    m.scroll:SetScrollChild(m.child)
    m.scroll:EnableMouseWheel(true)

    -- Thin scrollbar: a 4px track plus a draggable thumb, shown only when the list overflows.
    m.track = CreateFrame("Frame", nil, m.scroll); m.track:SetWidth(4); m.track:Hide()
    m.track:SetPoint("TOPRIGHT", m.scroll, "TOPRIGHT", -1, -2)
    m.track:SetPoint("BOTTOMRIGHT", m.scroll, "BOTTOMRIGHT", -1, 2)
    m.trackTex = m.track:CreateTexture(nil, "BACKGROUND"); m.trackTex:SetAllPoints()
    m.thumb = CreateFrame("Button", nil, m.track); m.thumb:SetWidth(4); m.thumb:EnableMouse(true)
    m.thumbTex = m.thumb:CreateTexture(nil, "ARTWORK"); m.thumbTex:SetAllPoints()

    -- Search box, created once and shown only when the menu asks for it.
    local e = CreateFrame("EditBox", nil, m)
    e:SetHeight(SEARCH_H); e:SetAutoFocus(false); e:SetTextInsets(22, 8, 0, 0); e:SetMaxLetters(40)
    -- Fonts before any text: the box is cleared on close even if this menu never showed it.
    e:SetFont(theme.FONT, 11, "")
    e.bg = e:CreateTexture(nil, "BACKGROUND"); e.bg:SetAllPoints()
    e.icon = e:CreateTexture(nil, "ARTWORK"); e.icon:SetSize(12, 12); e.icon:SetPoint("LEFT", 6, 0)
    e.ph = e:CreateFontString(nil, "OVERLAY"); e.ph:SetFont(theme.FONT, 11); e.ph:SetPoint("LEFT", 22, 0)
    e:Hide()
    m.search = e

    ------------------------------------------------------------------
    -- Scrolling
    ------------------------------------------------------------------
    function m:UpdateThumb()
        local maxScroll = TAP.scrollMax(self.scroll)
        if maxScroll <= 0 then self.track:Hide(); return end
        self.track:Show()
        local trackH, visH = self.track:GetHeight(), self.scroll:GetHeight()
        local thumbH = math.max(18, trackH * (visH / (visH + maxScroll)))
        local cur = self.scroll:GetVerticalScroll()
        if not TAP.CanRead(cur) then cur = 0 end
        self.thumb:SetHeight(thumbH)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.track, "TOP", 0, -((cur / maxScroll) * (trackH - thumbH)))
    end
    function m:ScrollTo(v)
        local cur = self.scroll:GetVerticalScroll()
        if not TAP.CanRead(cur) then return end
        self._target = math.max(0, math.min(TAP.scrollMax(self.scroll), v))
    end
    -- Keep a row fully in view (used by arrow-key navigation).
    function m:ScrollIntoView(row)
        local top = -select(5, row:GetPoint(1))          -- row offset from the child TOPLEFT
        local h, visH = row:GetHeight(), self.scroll:GetHeight()
        local cur = self._target or self.scroll:GetVerticalScroll()
        if not TAP.CanRead(cur) then return end
        if top < cur then self:ScrollTo(top)
        elseif top + h > cur + visH then self:ScrollTo(top + h - visH) end
    end
    m.scroll:SetScript("OnMouseWheel", function(_, delta)
        local base = m._target or m.scroll:GetVerticalScroll()
        if not TAP.CanRead(base) then return end
        m:ScrollTo(base - delta * SCROLL_STEP)
    end)
    m.thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        local startY = cy / self:GetEffectiveScale()
        local startScroll = m.scroll:GetVerticalScroll()
        if not TAP.CanRead(startScroll) then return end
        m._dragging = true
        self:SetScript("OnUpdate", function(s)
            if not IsMouseButtonDown("LeftButton") then m._dragging = false; s:SetScript("OnUpdate", nil); return end
            local _, y = GetCursorPosition()
            local travel = m.track:GetHeight() - s:GetHeight()
            if travel <= 0 then return end
            local maxScroll = TAP.scrollMax(m.scroll)
            local moved = (startY - y / s:GetEffectiveScale()) / travel * maxScroll
            m._target = nil
            m.scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, startScroll + moved)))
            m:UpdateThumb()
        end)
    end)
    m.thumb:SetScript("OnMouseUp", function(self) m._dragging = false; self:SetScript("OnUpdate", nil) end)

    ------------------------------------------------------------------
    -- Cursor (hover / keyboard highlight)
    ------------------------------------------------------------------
    function m:SetCursor(index)
        if self.cursor == index then return end
        self.cursor = index
        for _, r in ipairs(self.rows) do if r:IsShown() then r:Paint() end end
        for _, r in ipairs(self.pins) do if r:IsShown() then r:Paint() end end
    end
    -- Step the cursor to the next visible pickable row (dir 1 = down, -1 = up).
    function m:MoveCursor(dir)
        local vis = {}
        for _, r in ipairs(self.rows) do
            if r:IsShown() and r._item and isPickable(r._item) then vis[#vis + 1] = r end
        end
        if #vis == 0 then return end
        local at
        for i, r in ipairs(vis) do if r._index == self.cursor then at = i break end end
        local nextAt = at and (at + dir) or (dir > 0 and 1 or #vis)
        if nextAt < 1 then nextAt = #vis elseif nextAt > #vis then nextAt = 1 end
        self:SetCursor(vis[nextAt]._index)
        self:ScrollIntoView(vis[nextAt])
    end

    ------------------------------------------------------------------
    -- Activation
    ------------------------------------------------------------------
    function m:Activate(index)
        local cfg = self.cfg; if not cfg then return end
        local it = cfg.rowItems[index]; if not it or not isPickable(it) then return end
        if it.submenu then return end                       -- submenu parents open on hover only
        if it.onClick then
            if it.keepOpen then self:PinPosition() end
            it.onClick(it.value)
            if it.keepOpen then self:Repaint() else theme:CloseMenu() end
            return
        end
        if cfg.multi then
            local on = not cfg.isChecked(it.value)
            self:PinPosition()   -- the callback may rebuild the page (and the control) under us
            if cfg.onToggle then cfg.onToggle(it.value, on) end
            self:Repaint()
            return
        end
        if cfg.onPick then cfg.onPick(it.value) end
        theme:CloseMenu()
    end
    function m:Repaint()
        for _, r in ipairs(self.rows) do r:Paint() end
        for _, r in ipairs(self.pins) do r:Paint() end
    end
    -- Freeze the menu where it is on screen. A multi-select callback usually redraws the page,
    -- which hides and re-lays the pooled control we are anchored to; without this the open
    -- menu would slide around (or vanish) mid-edit.
    function m:PinPosition()
        if self._pinned then return end
        local cx, cy = self:GetCenter()
        if not cx or not TAP.CanRead(cx) then return end
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        self._pinned = true
    end

    ------------------------------------------------------------------
    -- Submenu flyout
    ------------------------------------------------------------------
    function m:OpenFlyout(row)
        if self.depth ~= 1 then return end
        local fly = theme:_menuFrame(2)
        self._closeAt = nil
        if fly:IsShown() and fly.parentRow == row then return end
        fly.parentRow = row
        theme:_openMenu(2, row, {
            items = row._item.submenu,
            width = self.cfg.width,
            selected = self.cfg.selected,
            onPick = self.cfg.onPick,
            itemHeight = self.cfg.itemHeight,
            search = false,
            point = "flyout",
        })
    end
    function m:QueueFlyoutClose()
        if self.depth ~= 1 then return end
        local fly = theme._menus and theme._menus[2]
        if fly and fly:IsShown() then self._closeAt = FLYOUT_DELAY end
    end

    ------------------------------------------------------------------
    -- Per-frame work: smooth scroll, flyout grace period, anchor watchdog
    ------------------------------------------------------------------
    m:SetScript("OnUpdate", function(self, elapsed)
        if self._target then
            local cur = self.scroll:GetVerticalScroll()
            if TAP.CanRead(cur) then
                local diff = self._target - cur
                if math.abs(diff) < 0.4 then
                    self.scroll:SetVerticalScroll(self._target); self._target = nil
                else
                    self.scroll:SetVerticalScroll(cur + diff * math.min(1, SCROLL_SPEED * elapsed))
                end
                self:UpdateThumb()
            else
                self._target = nil
            end
        end
        if self._closeAt then
            self._closeAt = self._closeAt - elapsed
            if self._closeAt <= 0 then
                self._closeAt = nil
                local fly = theme._menus and theme._menus[2]
                if fly and fly:IsShown() and not fly:IsMouseOver()
                   and not (fly.parentRow and fly.parentRow:IsMouseOver()) then
                    fly:Hide()
                end
            end
        end
        -- Follow the control down when it goes away, instead of leaving an orphaned popup over
        -- the UI. A page redraw hides pooled widgets for a frame before re-showing them, so
        -- only act once the control has really stayed gone.
        -- Combat can start with the menu open; hand the keyboard straight back if it does.
        if self._kb and InCombatLockdown() then
            self._kb = false; self:EnableKeyboard(false); self.search:ClearFocus()
        end
        if self.depth == 1 and self.anchor then
            if self.anchor:IsVisible() then
                self._gone = 0
            else
                self._gone = (self._gone or 0) + elapsed
                if self._gone > 0.25 then theme:CloseMenu() end
            end
        end
    end)

    ------------------------------------------------------------------
    -- Keyboard: arrows move the cursor, Enter picks, Escape closes. Everything else is
    -- passed straight back to the game so an open menu never eats a keybind.
    ------------------------------------------------------------------
    m:SetScript("OnKeyDown", function(self, key)
        local handled = true
        if key == "DOWN" then self:MoveCursor(1)
        elseif key == "UP" then self:MoveCursor(-1)
        elseif key == "ENTER" then if self.cursor then self:Activate(self.cursor) end
        elseif key == "ESCAPE" then theme:CloseMenu()
        else handled = false end
        self:SetPropagateKeyboardInput(not handled)
    end)

    function m:Filter(text) theme:_menuFilter(self, text) end
    e:SetScript("OnTextChanged", function(self)
        if m._building or not m:IsShown() then return end   -- not while (re)building or closing
        m:Filter(self:GetText())
    end)
    -- Escape clears a filter you have typed; a second press closes the menu.
    e:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else theme:CloseMenu() end
    end)
    e:SetScript("OnEnterPressed", function() if m.cursor then m:Activate(m.cursor) end end)
    -- The edit box owns the keyboard while focused, so drive the cursor from here too.
    e:SetScript("OnKeyDown", function(self, key)
        if key == "DOWN" then m:MoveCursor(1)
        elseif key == "UP" then m:MoveCursor(-1) end
    end)
    return m
end

-- Cached menu frame for a depth (1 = menu, 2 = submenu flyout).
function Mixin:_menuFrame(depth)
    self._menus = self._menus or {}
    local m = self._menus[depth]
    if not m then m = makeMenu(self, depth); self._menus[depth] = m end
    return m
end

-- Fullscreen click catcher behind the menu: any click outside closes it (and is swallowed, so
-- a stray click never also presses whatever was underneath).
local function ensureCloser(theme)
    if theme._menuCloser then return theme._menuCloser end
    local c = CreateFrame("Button", nil, UIParent)
    c:SetAllPoints(UIParent); c:SetFrameStrata("FULLSCREEN_DIALOG"); c:SetFrameLevel(1); c:Hide()
    c:RegisterForClicks("AnyUp")
    c:SetScript("OnClick", function() theme:CloseMenu() end)
    theme._menuCloser = c
    return c
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
-- Lay the visible rows out top to bottom. `filter` hides non-matching rows; a section header
-- survives only while something under it still matches, and a divider only between two
-- visible rows, so a filtered list never ends up with dangling captions or double rules.
local function layout(m, filter)
    local cfg = m.cfg
    local q = filter and filter ~= "" and string.lower(filter) or nil
    local items = cfg.rowItems
    local visible = {}
    for i, it in ipairs(items) do
        local show
        local k = rowKind(it)
        if not q then show = true
        elseif k == "divider" then show = false
        -- Headers stay in the running while filtering (the pass below drops the ones whose
        -- section ends up empty), so a filtered list keeps telling you where you are.
        elseif k == "header" then show = true
        else show = string.find(haystack(it), q, 1, true) ~= nil end
        visible[i] = show
    end
    -- Drop a divider that would lead the list, trail it, or double up on another rule.
    local prevKind
    for i = 1, #items do
        if visible[i] then
            local k = rowKind(items[i])
            if k == "divider" and (prevKind == nil or prevKind ~= "row") then
                visible[i] = false
            else
                prevKind = k
            end
        end
    end
    for i = #items, 1, -1 do
        if visible[i] then
            if rowKind(items[i]) == "row" then break end
            visible[i] = false
        end
    end
    -- A header with no visible row beneath it (before the next header) is dropped.
    for i = 1, #items do
        if visible[i] and rowKind(items[i]) == "header" then
            local keep = false
            for j = i + 1, #items do
                local k = rowKind(items[j])
                if k == "header" then break end
                if visible[j] and k == "row" then keep = true; break end
            end
            visible[i] = keep
        end
    end

    local y, shown = 0, 0
    for i, it in ipairs(items) do
        local row = m.rows[i]
        if visible[i] and row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", m.child, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", m.child, "TOPRIGHT", 0, -y)
            row:Show()
            y = y + row:GetHeight()
            if rowKind(it) == "row" then shown = shown + 1 end
        elseif row then
            row:Hide()
        end
    end
    m.child:SetHeight(math.max(1, y))
    m._contentH = y
    m._shown = shown
    return y
end

----------------------------------------------------------------------
-- Open
----------------------------------------------------------------------
-- Normalize the caller's opts into the config the frame runs on.
local function buildConfig(opts)
    local items = opts.items
    if type(items) == "function" then items = items() end
    items = items or {}

    local cfg = {
        multi      = opts.multi and true or false,
        itemHeight = opts.itemHeight or ROW_H,
        maxHeight  = opts.maxHeight or MAX_H,
        onPick     = opts.onPick,
        onToggle   = opts.onToggle,
        onClose    = opts.onClose,
        selected   = opts.selected,
        width      = opts.width,
        rowItems   = {},
    }

    -- Selection / check state readers, so rows never care how the caller stores things.
    local sel = opts.selected
    if type(sel) == "function" then cfg.isSelected = function(v) return sel() == v end
    else cfg.isSelected = function(v) return sel ~= nil and sel == v end end
    local chk = opts.checked
    if type(chk) == "function" then cfg.isChecked = function(v) return chk(v) and true or false end
    else cfg.isChecked = function() return false end end

    -- Pinned action rows sit above the search box: "Select all" / "Clear" in multi mode plus
    -- whatever the caller adds, so the common bulk edits stay one click away in a long list.
    local pins = {}
    if cfg.multi and opts.selectAll ~= false then
        local values = {}
        for _, it in ipairs(items) do
            if rowKind(it) == "row" and it.value ~= nil and not it.disabled then values[#values + 1] = it.value end
        end
        pins[#pins + 1] = { label = "Select all", icon = "checks", keepOpen = true, onClick = function()
            for _, v in ipairs(values) do if not cfg.isChecked(v) and cfg.onToggle then cfg.onToggle(v, true) end end
        end }
        pins[#pins + 1] = { label = "Clear", icon = "x", keepOpen = true, onClick = function()
            for _, v in ipairs(values) do if cfg.isChecked(v) and cfg.onToggle then cfg.onToggle(v, false) end end
        end }
    end
    for _, a in ipairs(opts.actions or {}) do pins[#pins + 1] = a end
    cfg.pinItems = pins

    for _, it in ipairs(items) do cfg.rowItems[#cfg.rowItems + 1] = it end

    -- Search: on when asked, off when refused, and automatic once the list is long enough to
    -- be worth typing at. A number sets that threshold.
    local rows = 0
    for _, it in ipairs(items) do if rowKind(it) == "row" then rows = rows + 1 end end
    local s = opts.search
    if s == true then cfg.search = true
    elseif s == false then cfg.search = false
    elseif type(s) == "number" then cfg.search = rows >= s
    else cfg.search = rows >= SEARCH_AUTO end
    cfg.placeholder = opts.placeholder or "Search..."
    cfg.autoFocus = opts.autoFocus ~= false
    return cfg
end

function Mixin:_openMenu(depth, anchor, opts)
    local theme, C = self, self.C
    local m = self:_menuFrame(depth)
    local cfg = buildConfig(opts)
    m.cfg, m.anchor, m.cursor = cfg, anchor, nil
    m._target, m._closeAt, m._dragging = nil, nil, false
    m._pinned, m._gone = false, 0
    m._building = true   -- suppress the search box's OnTextChanged while we (re)build

    -- Re-skin on every open so a live palette / skin swap sticks, instead of the cached frame
    -- keeping the colors it had when it was first created.
    self:StylePanel(m, C.panel, C.accent)
    -- Layer explicitly: rows over the panel fill, scrollbar and search over the rows. A flyout
    -- sits a full band above its parent menu.
    local base = 400 + depth * 20
    m:SetFrameLevel(base)
    m.scroll:SetFrameLevel(base + 1)
    m.child:SetFrameLevel(base + 2)
    m.track:SetFrameLevel(base + 6); m.thumb:SetFrameLevel(base + 7)
    m.search:SetFrameLevel(base + 6)
    m.trackTex:SetColorTexture(C.text[1], C.text[2], C.text[3], 0.06)
    m.thumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.75)

    local width = math.max(cfg.width or (anchor:GetWidth() or MIN_W), MIN_W)
    local inner = width - PAD * 2

    -- Pinned rows (above the search box). They live at negative indices so Activate() can
    -- reach them through the same rowItems lookup the list uses.
    local pinH = 0
    for i, it in ipairs(cfg.pinItems) do
        local r = m.pins[i]
        if not r then r = makeRow(theme, m, m); m.pins[i] = r end
        local item = { label = it.label, icon = it.icon, onClick = it.onClick,
                       keepOpen = it.keepOpen, tip = it.tip, color = it.color or C.accent }
        cfg.rowItems[-i] = item
        r:SetFrameLevel(base + 4)
        r:Render(item, -i, cfg)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, -(PAD + pinH))
        r:SetPoint("TOPRIGHT", m, "TOPRIGHT", -PAD, -(PAD + pinH))
        r:Show()
        pinH = pinH + r:GetHeight()
    end
    for i = #cfg.pinItems + 1, #m.pins do m.pins[i]:Hide() end
    if pinH > 0 then pinH = pinH + 3 end

    -- Search box.
    local searchH = 0
    if cfg.search then
        local e = m.search
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, -(PAD + pinH))
        e:SetWidth(inner)
        e:SetFont(theme.FONT, 11, "")
        e:SetTextColor(C.text[1], C.text[2], C.text[3])
        e.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
        e.ph:SetFont(theme.FONT, 11); e.ph:SetText(cfg.placeholder)
        e.ph:SetTextColor(C.subtext[1], C.subtext[2], C.subtext[3], 0.8)
        local art = theme:GetIcon("search")
        if art then e.icon:SetTexture(art); e.icon:SetVertexColor(C.subtext[1], C.subtext[2], C.subtext[3]); e.icon:Show()
        else e.icon:Hide() end
        e:SetText("")
        e.ph:Show()
        e:Show()
        searchH = SEARCH_H + 4
    else
        m.search:Hide()
    end

    -- List rows.
    m.scroll:ClearAllPoints()
    m.scroll:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, -(PAD + pinH + searchH))
    m.scroll:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -PAD, PAD)
    m.child:SetWidth(inner)
    for i, it in ipairs(cfg.rowItems) do
        local r = m.rows[i]
        if not r then r = makeRow(theme, m, m.child); m.rows[i] = r end
        r:Render(it, i, cfg)
    end
    for i = #cfg.rowItems + 1, #m.rows do m.rows[i]:Hide(); m.rows[i]._item = nil end

    local contentH = layout(m, nil)
    local listH = math.min(contentH, cfg.maxHeight)
    m:SetSize(width, PAD * 2 + pinH + searchH + listH)
    m.scroll:SetVerticalScroll(0)
    m:UpdateThumb()

    -- Placement: under the control by default, flipped above it when there is no room below,
    -- and to the side for a submenu flyout.
    m:ClearAllPoints()
    if opts.point == "flyout" then
        m:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 2)
    elseif (anchor:GetBottom() or 999) < m:GetHeight() + 8 then
        m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else
        m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end

    if depth == 1 then
        -- The catcher sits directly under the menu (and so above any modal a dropdown lives
        -- in), which is what makes "click anywhere else to dismiss" work from inside a dialog.
        local c = ensureCloser(theme); c:SetFrameLevel(math.max(1, base - 1)); c:Show()
        -- Typing straight into a fresh menu is the point of the search box, and arrow keys walk
        -- the list. Both grab the keyboard, so neither happens in combat: an open dropdown must
        -- never sit between the player and their keybinds (arrow keys included).
        local safe = not InCombatLockdown()
        if cfg.search and cfg.autoFocus and safe then m.search:SetFocus() end
        m._kb = safe
        m:EnableKeyboard(safe)
        if safe then m:SetPropagateKeyboardInput(true) end
    end
    m._building = false
    m:Show()
    return m
end

-- Live filter from the search box.
function Mixin:_menuFilter(m, text)
    if not m.cfg then return end
    local contentH = layout(m, text)
    local listH = math.min(contentH, m.cfg.maxHeight)
    local pinH, searchH = 0, m.cfg.search and (SEARCH_H + 4) or 0
    for _, r in ipairs(m.pins) do if r:IsShown() then pinH = pinH + r:GetHeight() end end
    if pinH > 0 then pinH = pinH + 3 end
    m:SetHeight(PAD * 2 + pinH + searchH + listH)
    m.search.ph:SetShown((text or "") == "")
    m._target = nil
    m.scroll:SetVerticalScroll(0)
    m:UpdateThumb()
    -- Park the cursor on the first match so Enter picks the obvious thing.
    m.cursor = nil
    if text and text ~= "" then
        for _, r in ipairs(m.rows) do
            if r:IsShown() and r._item and isPickable(r._item) then m:SetCursor(r._index); break end
        end
    end
    m:Repaint()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function Mixin:CloseMenu()
    for _, m in ipairs(self._menus or {}) do
        if m:IsShown() then
            m:EnableKeyboard(false)
            m:SetPropagateKeyboardInput(true)
            m:Hide()
            m.anchor, m.parentRow, m._target, m._closeAt = nil, nil, nil, nil
            if m.cfg and m.cfg.onClose then m.cfg.onClose() end
        end
        m.search:SetText(""); m.search:ClearFocus()
    end
    if self._menuCloser then self._menuCloser:Hide() end
end

-- True while this theme has a menu open (optionally: open for that anchor).
function Mixin:MenuIsOpen(anchor)
    local m = self._menus and self._menus[1]
    if not m or not m:IsShown() then return false end
    return anchor == nil or m.anchor == anchor
end

-- theme:OpenMenu(anchor, opts) or the classic theme:OpenMenu(anchor, items, getSel, onPick).
function Mixin:OpenMenu(anchor, a, b, c)
    local opts
    if type(a) == "table" and (a.items or a.multi or a.onPick or a.actions) then
        opts = a
    else
        opts = { items = a, selected = b, onPick = c }
    end
    -- Clicking the control that owns the open menu closes it again (the click catcher swallows
    -- the press, so this only matters for programmatic reopens).
    if self:MenuIsOpen(anchor) then self:CloseMenu(); return end
    self:CloseMenu()
    GameTooltip_Hide()
    return self:_openMenu(1, anchor, opts)
end
