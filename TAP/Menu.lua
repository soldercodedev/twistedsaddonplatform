-- UIFoundry - Menu.lua
-- A self-skinned dropdown menu (replaces Blizzard's MenuUtil for our dropdowns). Supports
-- section headers, per-row icons, and per-row fonts.
--
--   theme:OpenMenu(anchorFrame, items, getSelected, onPick)
--
-- items: array of
--   { label, value }                                  -- a selectable row
--   { label, header = true }                          -- a non-clickable section header
--   { label, value, icon = tex, coords = {l,r,t,b} }  -- row with an icon
--   { label, value, font = "UBUNTU" | path }          -- row rendered in a specific font
-- getSelected(): the currently selected value (row gets an accent dot).
-- onPick(value): chosen value; the menu then closes.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

local function makeMenuItem(theme, menu)
    local b = CreateFrame("Button", nil, menu.child); b:SetHeight(22)
    b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:Hide()
    b.dot = b:CreateTexture(nil, "ARTWORK"); b.dot:SetSize(6, 6); b.dot:SetPoint("LEFT", 5, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 14, 0); b.icon:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetPoint("RIGHT", -6, 0); b.fs:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) if not self._header then self.hl:Show() end end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    function b:Set(it, selected, onClick)
        local C = theme.C
        self._header = it.header
        UIF.paint(self.hl, UIF.mix(C.card, C.accent, 0.55))
        self.fs:ClearAllPoints(); self.fs:SetPoint("RIGHT", -6, 0)
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
            self:SetScript("OnClick", function() onClick(it.value) end)
        end
    end
    return b
end

-- The menu frame is cached per theme (one open at a time) with a fullscreen click-catcher behind it.
local function ensureMenu(theme)
    if theme._menu then return theme._menu end
    local C = theme.C
    local m = CreateFrame("Frame", UIF.NextId(theme.id .. "Menu"), UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetToplevel(true); m:SetClampedToScreen(true); m:Hide()
    theme:StylePanel(m, C.panel, C.accent)
    m.scroll = CreateFrame("ScrollFrame", nil, m)
    m.scroll:SetPoint("TOPLEFT", 4, -4); m.scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    m.child = CreateFrame("Frame", nil, m.scroll); m.child:SetSize(10, 10); m.scroll:SetScrollChild(m.child)
    m.scroll:EnableMouseWheel(true); m.scroll:SetScript("OnMouseWheel", UIF.scrollWheel)
    m.items = {}
    local closer = CreateFrame("Button", nil, UIParent)
    closer:SetAllPoints(UIParent); closer:SetFrameStrata("FULLSCREEN_DIALOG"); closer:Hide()
    closer:SetScript("OnClick", function() theme:CloseMenu() end)
    m.closer = closer
    theme._menu = m
    return m
end

function Mixin:CloseMenu()
    local m = self._menu
    if m then m:Hide(); m.closer:Hide() end
end

function Mixin:OpenMenu(anchor, items, getSel, onPick)
    local m = ensureMenu(self)
    if type(items) == "function" then items = items() end
    -- Cached frame: re-skin on every open so the live palette (panel bg + accent border) and the
    -- current shape stick, instead of the popup keeping the colors it had when first created (e.g. a
    -- dark bg under a light theme).
    self:StylePanel(m, self.C.panel, self.C.accent)
    for _, it in ipairs(m.items) do it:Hide() end
    local width = math.max(anchor:GetWidth() or 150, 160)
    local sel = getSel and getSel() or nil
    local y, n = -2, 0
    for _, it in ipairs(items) do
        n = n + 1
        local bi = m.items[n]; if not bi then bi = makeMenuItem(self, m); m.items[n] = bi end
        bi:ClearAllPoints(); bi:SetPoint("TOPLEFT", 0, y); bi:SetWidth(width - 8)
        -- Only true value rows can be "selected"; headers (value == nil) never are.
        bi:Set(it, (not it.header) and it.value ~= nil and sel == it.value, function(v) onPick(v); self:CloseMenu() end)
        bi:Show()
        y = y - (it.header and 20 or 22)
    end
    m.child:SetWidth(width - 8); m.child:SetHeight(math.max(1, -y + 2))
    local h = math.min(-y + 8, 340)
    m:SetSize(width, h)
    m.closer:Show()
    m:Show(); m:SetFrameLevel(410)
    m:ClearAllPoints()
    if (anchor:GetBottom() or 999) < h + 8 then m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
    m.scroll:SetVerticalScroll(0)
end
