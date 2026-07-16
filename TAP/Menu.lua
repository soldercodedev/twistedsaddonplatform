-- UIFoundry - Menu.lua
-- A self-skinned dropdown menu (replaces Blizzard's MenuUtil for our dropdowns). Supports
-- section headers, per-row icons, per-row fonts, and nested submenus.
--
--   theme:OpenMenu(anchorFrame, items, getSelected, onPick)
--
-- items: array of
--   { label, value }                                  -- a selectable row
--   { label, header = true }                          -- a non-clickable section header
--   { label, value, icon = tex, coords = {l,r,t,b} }  -- row with an icon
--   { label, value, font = "UBUNTU" | path }          -- row rendered in a specific font
--   { label, submenu = { …items… } or function() … }  -- opens a nested menu on hover
-- getSelected(): the currently selected value (row gets an accent dot).
-- onPick(value): chosen value; the whole menu tree then closes.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

local MAX_LEVELS = 5

local function makeMenuItem(theme, menu)
    local b = CreateFrame("Button", nil, menu.child); b:SetHeight(22)
    b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:Hide()
    b.dot = b:CreateTexture(nil, "ARTWORK"); b.dot:SetSize(6, 6); b.dot:SetPoint("LEFT", 5, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 14, 0); b.icon:Hide()
    b.arrow = b:CreateFontString(nil, "OVERLAY"); b.arrow:SetFont(theme.FONT, 12); b.arrow:SetPoint("RIGHT", -6, 0); b.arrow:SetText(">"); b.arrow:Hide()
    b.arrowTex = b:CreateTexture(nil, "ARTWORK"); b.arrowTex:SetSize(12, 12); b.arrowTex:SetPoint("RIGHT", -5, 0); b.arrowTex:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetPoint("RIGHT", -6, 0); b.fs:SetJustifyH("LEFT")
    b._menu = menu
    b:SetScript("OnEnter", function(self)
        if self._header then return end
        self.hl:Show()
        if self._submenu then
            menu.owner:_openLevel(menu.level + 1, self, self._submenu)
        else
            menu.owner:_closeFrom(menu.level + 1)
        end
    end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    function b:Set(it, selected, onClick)
        local C = theme.C
        self._header, self._submenu = it.header, it.submenu
        UIF.paint(self.hl, UIF.mix(C.card, C.accent, 0.55))
        self.fs:ClearAllPoints(); self.fs:SetPoint("RIGHT", (it.submenu and -20 or -6), 0)
        -- Submenu indicator: a chevron-right icon when the bundled set is available, else "›".
        if it.submenu then
            local chev = theme:GetIcon(it.submenuIcon or "chevron-right")
            if chev then
                self.arrowTex:SetTexture(chev); self.arrowTex:SetVertexColor(C.subtext[1], C.subtext[2], C.subtext[3])
                self.arrowTex:Show(); self.arrow:Hide()
            else
                self.arrow:SetText(">"); self.arrow:SetTextColor(unpack(C.subtext)); self.arrow:Show(); self.arrowTex:Hide()
            end
        else
            self.arrow:Hide(); self.arrowTex:Hide()
        end
        local font = it.font and theme:ResolveFont(it.font) or theme.FONT
        if it.header then
            self.fs:SetFont(font, it.fontSize or 10); self.fs:SetText(it.label); self.fs:SetTextColor(unpack(C.subtext))
            self.fs:SetPoint("LEFT", 8, 0)
            self.dot:Hide(); self.icon:Hide(); self:SetHeight(20); self:EnableMouse(false); self:SetScript("OnClick", nil)
        else
            self.fs:SetFont(font, it.fontSize or 12); self.fs:SetText(it.label)
            if it.icon then
                self.icon:SetTexture(theme:IconPath(it.icon) or it.icon)
                if it.coords then self.icon:SetTexCoord(it.coords[1], it.coords[2], it.coords[3], it.coords[4])
                else self.icon:SetTexCoord(unpack(theme.iconInset)) end
                if it.iconColor then local ic = UIF.toColor(it.iconColor); self.icon:SetVertexColor(ic[1], ic[2], ic[3]) else self.icon:SetVertexColor(1, 1, 1) end
                self.icon:Show(); self.fs:SetPoint("LEFT", 34, 0)
            else
                self.icon:Hide(); self.fs:SetPoint("LEFT", 16, 0)
            end
            if selected then
                self.fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3]); UIF.paint(self.dot, C.accent); self.dot:Show()
            else
                self.fs:SetTextColor(C.text[1], C.text[2], C.text[3]); self.dot:Hide()
            end
            self:SetHeight(22); self:EnableMouse(true)
            self:SetScript("OnClick", function() if not it.submenu then onClick(it.value) end end)
        end
    end
    return b
end

local function ensureMenu(theme, level)
    theme._menus = theme._menus or {}
    if theme._menus[level] then return theme._menus[level] end
    local C = theme.C
    local m = CreateFrame("Frame", UIF.NextId(theme.id .. "Menu" .. level), UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetToplevel(true); m:SetClampedToScreen(true); m:Hide()
    theme:StylePanel(m, C.panel, C.accent)
    m.scroll = CreateFrame("ScrollFrame", nil, m)
    m.scroll:SetPoint("TOPLEFT", 4, -4); m.scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    m.child = CreateFrame("Frame", nil, m.scroll); m.child:SetSize(10, 10); m.scroll:SetScrollChild(m.child)
    m.scroll:EnableMouseWheel(true); m.scroll:SetScript("OnMouseWheel", UIF.scrollWheel)
    m.items = {}; m.level = level; m.owner = theme
    if level == 1 then
        local closer = CreateFrame("Button", nil, UIParent)
        closer:SetAllPoints(UIParent); closer:SetFrameStrata("FULLSCREEN_DIALOG"); closer:Hide()
        closer:SetScript("OnClick", function() theme:_closeFrom(1) end)
        m.closer = closer
    end
    theme._menus[level] = m
    return m
end

-- Populate + show menu `level`, anchored below (level 1) or to the right of (deeper) `anchor`.
function Mixin:_openLevel(level, anchor, items, getSel, onPick)
    if level > MAX_LEVELS then return end
    local m = ensureMenu(self, level)
    self:_closeFrom(level)   -- close this level + deeper before reopening
    if type(items) == "function" then items = items() end
    -- deeper levels reuse the top-level's getSel/onPick captured on the menu
    if level == 1 then m._getSel, m._onPick = getSel, onPick
    else m._getSel, m._onPick = self._menus[1]._getSel, self._menus[1]._onPick end
    getSel, onPick = m._getSel, m._onPick

    -- The menu frame is cached per level, so re-skin it on every open: this re-applies the live
    -- palette (panel bg + accent border) AND the current shape, so a theme/skin swap sticks instead of
    -- the popup keeping the colours it had when first created (e.g. a dark bg under a light theme).
    self:StylePanel(m, self.C.panel, self.C.accent)
    for _, it in ipairs(m.items) do it:Hide() end
    local width = math.max((level == 1 and (anchor:GetWidth() or 150)) or 150, 160)
    local sel = getSel and getSel() or nil
    local y, n = -2, 0
    for _, it in ipairs(items) do
        n = n + 1
        local bi = m.items[n]; if not bi then bi = makeMenuItem(self, m); m.items[n] = bi end
        bi:ClearAllPoints(); bi:SetPoint("TOPLEFT", 0, y); bi:SetWidth(width - 8)
        -- Only true value rows can be "selected"; submenu parents (value == nil) never are.
        bi:Set(it, (not it.header) and it.value ~= nil and sel == it.value, function(v) onPick(v); self:_closeFrom(1) end)
        bi:Show()
        y = y - (it.header and 20 or 22)
    end
    m.child:SetWidth(width - 8); m.child:SetHeight(math.max(1, -y + 2))
    local h = math.min(-y + 8, 340)
    m:SetSize(width, h)
    if m.closer then m.closer:Show() end
    m:Show(); m:SetFrameLevel(400 + level * 10)
    m:ClearAllPoints()
    if level == 1 then
        if (anchor:GetBottom() or 999) < h + 8 then m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
        else m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
    else
        m:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 3, 2)
    end
    m.scroll:SetVerticalScroll(0)
end

-- Hide menu levels >= `level`.
function Mixin:_closeFrom(level)
    if not self._menus then return end
    for l = MAX_LEVELS, level, -1 do
        local m = self._menus[l]
        if m then m:Hide(); if m.closer and l == 1 then m.closer:Hide() end end
    end
end

function Mixin:OpenMenu(anchor, items, getSel, onPick)
    self:_openLevel(1, anchor, items, getSel, onPick)
end
