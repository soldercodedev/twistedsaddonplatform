-- UIFoundry - Window.lua
-- The application shell: a movable, self-skinned window with a header (drag handle + logo +
-- title + close), a left sidebar of icon nav rows, a scroll-clipped content area with a
-- themed scrollbar, and a footer. Pages render into a pooled Builder.
--
--   local win = theme:Window({
--     name = "MyAddonWindow", title = "My Addon", logo = "Interface\\AddOns\\MyAddon\\logo.tga",
--     width = 920, height = 600, sidebarWidth = 210, contentWidth = 660,
--     savedPos = db.windowPos, onMovePos = function(p) db.windowPos = p end,
--     onScale  = function() return db.scale end,          -- optional: window scale
--     onSize   = function() return db.w, db.h end,        -- optional: live width/height (resizable)
--     collapsibleSidebar = true, collapsedWidth = 52,     -- optional: a bottom toggle shrinks the
--     savedCollapsed = db.collapsed,                      --   sidebar to an icon strip; state persists
--     onCollapse = function(c) db.collapsed = c end,      --   via onCollapse (win:ToggleSidebar())
--     pages = {
--       { view = "home", label = "Home", icon = "...\\home.tga",
--         render = function(b, win) ...; return finalY end },      -- return the last y used
--       { view = "edit", label = "Editor", icon = "...", subViews = { "row" } }, -- keeps Home lit on sub-pages
--     },
--     footer = { left = "My Addon", right = "v1.0", link = { label = "Discord", url = "https://..." } },
--     sidebarButton = { label = "Do Thing", kind = "primary", onClick = fn, tip = { "Title", "Body" } },
--     defaultView = "home",
--   })
--   win:Open()          -- build (first time) + show + refresh
--   win:Toggle()        -- show/hide
--   win:SelectView(v)   -- switch page + refresh
--   win:Refresh()       -- re-render current page

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

local WindowMixin = {}
local WindowMeta = { __index = WindowMixin }

function Mixin:Window(opts)
    opts = opts or {}
    local win = setmetatable({
        theme = self, opts = opts, built = false,
        view = opts.defaultView or (opts.pages and opts.pages[1] and opts.pages[1].view),
    }, WindowMeta)
    return win
end

-- Build the frame tree once, on first open.
local function build(win)
    if win.built then return end
    local theme, C = win.theme, win.theme.C
    local o = win.opts
    local W = o.width or 920
    local H = o.height or 600
    local HEADER_H = o.headerHeight or 44
    -- Footer style: none · minimal (default) · expanded (taller, larger text, socials).
    local footerCfg = o.footer
    local footerStyle = (footerCfg == false and "none") or (type(footerCfg) == "table" and footerCfg.style) or "minimal"
    local FOOTER_H = (footerStyle == "none" and 0) or (footerStyle == "expanded" and (o.footerHeight or 48)) or (o.footerHeight or 22)
    local SIDE_W   = o.sidebarWidth or 210
    local name     = o.name or UIF.NextId(theme.id .. "Window")
    win._headerH, win._footerH = HEADER_H, FOOTER_H

    local mgr = CreateFrame("Frame", name, UIParent)
    win.frame = mgr
    mgr:SetSize(W, H); mgr:SetPoint("CENTER")
    mgr:SetFrameStrata("HIGH"); mgr:SetToplevel(true); mgr:SetClampedToScreen(true)
    theme:StylePanel(mgr, C.bg, C.border)
    mgr:SetMovable(true); mgr:EnableMouse(true)
    mgr:Hide()
    mgr:SetScale((o.onScale and o.onScale()) or o.scale or 1)
    tinsert(UISpecialFrames, name)

    -- Header (drag handle)
    local header = CreateFrame("Button", nil, mgr); header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    local hbg = header:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); UIF.paint(hbg, C.panel); win._hbg = hbg
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() mgr:StartMoving() end)
    header:SetScript("OnDragStop", function()
        mgr:StopMovingOrSizing()
        local point, _, _, px, py = mgr:GetPoint()
        if o.onMovePos then o.onMovePos({ point = point, x = px, y = py }) end
    end)
    local logo = header:CreateTexture(nil, "ARTWORK"); UIF.paint(logo, C.accent); logo:SetSize(o.logo and 18 or 14, o.logo and 18 or 14); logo:SetPoint("LEFT", 16, 0)
    if o.logo then logo:SetTexture(o.logo); logo:SetTexCoord(0, 1, 0, 1); logo:SetVertexColor(C.accent[1], C.accent[2], C.accent[3]) end
    mgr.logo = logo
    local title = header:CreateFontString(nil, "OVERLAY"); title:SetFont(theme.FONT, 15)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0); title:SetText(o.title or "UIFoundry"); title:SetTextColor(unpack(C.text))
    mgr.titleFS = title

    local close = theme:Button(mgr); close:Configure("X", 28, 28, "danger", function() mgr:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8); close:SetFrameLevel(header:GetFrameLevel() + 5)

    -- Optional maximize / restore button.
    if o.maximizable then
        local maxBtn = theme:Button(mgr); maxBtn:SetPoint("TOPRIGHT", -40, -8); maxBtn:SetFrameLevel(header:GetFrameLevel() + 5)
        function win:_updateMaxBtn()
            maxBtn:Configure("", 28, 28, "default", function() win:ToggleMaximize() end,
                { icon = self._maximized and "minimize" or "maximize", iconSize = 14 })
            theme:SetTip(maxBtn, self._maximized and "Restore" or "Maximize")
        end
        win:_updateMaxBtn()
    end

    -- Restore a saved position.
    if o.savedPos and o.savedPos.point then
        mgr:ClearAllPoints()
        mgr:SetPoint(o.savedPos.point, UIParent, o.savedPos.point, o.savedPos.x or 0, o.savedPos.y or 0)
    end

    -- Collapsible sidebar (opt-in via opts.collapsibleSidebar): the bar can shrink to an icon-only
    -- strip, and the content + scrollbar re-anchor to the live width on Refresh. `savedCollapsed`
    -- seeds the initial state; `onCollapse(bool)` persists a toggle; `collapsedWidth` sets the strip.
    local COLLAPSED_W = o.collapsedWidth or 46
    win._sideWFull = SIDE_W
    win._collapsed = (o.collapsibleSidebar and o.savedCollapsed) and true or false
    win._sideW     = win._collapsed and COLLAPSED_W or SIDE_W

    -- Sidebar
    local side = CreateFrame("Frame", nil, mgr)
    side:SetPoint("TOPLEFT", 1, -HEADER_H); side:SetPoint("BOTTOMLEFT", 1, FOOTER_H + 1); side:SetWidth(win._sideW)
    win.side = side
    local sbg = side:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); UIF.paint(sbg, C.sidebar); win._sbg = sbg
    local sedge = side:CreateTexture(nil, "ARTWORK"); UIF.paint(sedge, C.border); sedge:SetWidth(1); win._sedge = sedge
    sedge:SetPoint("TOPRIGHT"); sedge:SetPoint("BOTTOMRIGHT")

    -- Bottom-of-sidebar reserve: room for an optional action button and/or the collapse toggle.
    local bottomReserve = o.sidebarButton and 46 or 6
    if o.collapsibleSidebar then bottomReserve = bottomReserve + 34 end

    -- Scrollable nav area so many pages + category headers still fit, with a themed scrollbar.
    local navScroll = CreateFrame("ScrollFrame", nil, side)
    navScroll:SetPoint("TOPLEFT", 0, -6)
    navScroll:SetPoint("BOTTOMRIGHT", -9, bottomReserve)   -- room for the scrollbar + bottom controls
    local navChild = CreateFrame("Frame", nil, navScroll); navChild:SetSize(win._sideW - 11, 10); navScroll:SetScrollChild(navChild)
    win.navScroll, win._navChild = navScroll, navChild

    local nbar = CreateFrame("Frame", nil, side); nbar:SetWidth(6)
    nbar:SetPoint("TOPRIGHT", navScroll, "TOPRIGHT", 8, 0); nbar:SetPoint("BOTTOMRIGHT", navScroll, "BOTTOMRIGHT", 8, 0)
    local ntrack = nbar:CreateTexture(nil, "BACKGROUND"); ntrack:SetAllPoints(); UIF.paint(ntrack, C.card, 0.5); win._ntrack = ntrack
    local nthumb = CreateFrame("Button", nil, nbar); nthumb:SetPoint("TOP"); nthumb:SetWidth(6); nthumb:SetHeight(30)
    local nthumbTex = nthumb:CreateTexture(nil, "ARTWORK"); nthumbTex:SetAllPoints()

    function win:updateNavScrollbar()
        local vh, ch = navScroll:GetHeight(), navChild:GetHeight()
        if not (UIF.CanRead(vh) and UIF.CanRead(ch)) then nbar:Hide(); return end
        local range = math.max(0, ch - vh)
        if range > 1 then
            nbar:Show()
            local trackH = nbar:GetHeight(); local thumbH = math.max(20, trackH * (vh / ch)); nthumb:SetHeight(thumbH)
            local pos = navScroll:GetVerticalScroll(); local frac = UIF.CanRead(pos) and (pos / range) or 0
            frac = math.min(1, math.max(0, frac))
            nthumb:ClearAllPoints(); nthumb:SetPoint("TOP", nbar, "TOP", 0, -frac * (trackH - thumbH))
            UIF.paint(nthumbTex, theme.C.accent)
        else nbar:Hide() end
    end
    navScroll:EnableMouseWheel(true)
    navScroll:SetScript("OnMouseWheel", function(self, delta) UIF.scrollWheel(self, delta); win:updateNavScrollbar() end)
    nthumb:RegisterForDrag("LeftButton")
    nthumb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local range = UIF.scrollMax(navScroll); if range <= 0 then return end
            local trackH = nbar:GetHeight(); local s = nbar:GetEffectiveScale()
            local _, cy = GetCursorPosition(); local top = nbar:GetTop()
            if top and s and s > 0 then
                local frac = (top - (cy / s)) / math.max(1, trackH - self:GetHeight())
                navScroll:SetVerticalScroll(math.min(1, math.max(0, frac)) * range); win:updateNavScrollbar()
            end
        end)
    end)
    nthumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    -- A clickable, collapsible category header. Drawn as a distinct group BAND (accent overline label,
    -- an accent chevron on the right, and a hairline divider beneath) so groups are clearly illustrated
    -- and the collapse affordance is obvious - it doesn't read like just another nav row.
    -- `color` (optional {r,g,b}) overrides the accent so each add-on category shows its signature tint.
    local function makeCategoryHeader(text, collapsible, color)
        local hb = CreateFrame("Button", nil, navChild); hb:SetHeight(20)
        local labelCol = color or (collapsible ~= false and C.accent or C.subtext)
        hb.fs = theme:Heading(hb, { text = text, role = "overline" }); hb.fs:SetPoint("LEFT", 6, 0)
        hb.fs:SetTextColor(unpack(labelCol))
        -- Hairline divider under the label so each group reads as a banded section.
        hb.rule = hb:CreateTexture(nil, "ARTWORK")
        hb.rule:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.55); hb.rule:SetHeight(1)
        hb.rule:SetPoint("BOTTOMLEFT", 6, 0); hb.rule:SetPoint("BOTTOMRIGHT", -4, 0)
        if collapsible ~= false then
            local ct = theme:GetIcon("chevron-down")
            if ct then hb.chev = hb:CreateTexture(nil, "ARTWORK"); hb.chev:SetSize(11, 11); hb.chev:SetPoint("RIGHT", -4, 1)
                hb.chev:SetTexture(ct); hb.chev:SetVertexColor(unpack(labelCol)) end
            hb:SetScript("OnEnter", function(self) self.fs:SetTextColor(unpack(C.text)); if self.chev then self.chev:SetVertexColor(unpack(C.text)) end end)
            hb:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(labelCol)); if self.chev then self.chev:SetVertexColor(unpack(labelCol)) end end)
        else hb:EnableMouse(false) end
        function hb:SetChevron(collapsed) if self.chev then self.chev:SetRotation(collapsed and -math.rad(90) or 0) end end
        return hb
    end

    -- Build headers + rows, associating rows with the category above them.
    -- A `pages` entry with `.header` (no `.view`) is a category; `.collapsible = false` keeps
    -- it a plain label, and `.collapsed = true` starts it collapsed.
    win.navRows, win.navHeaders = {}, {}
    local order, curHeader = {}, nil
    for _, page in ipairs(o.pages or {}) do
        if page.header then
            local hb = makeCategoryHeader(page.header, page.collapsible, page.color)
            hb._rows, hb._collapsed, hb._collapsible = {}, page.collapsed or false, page.collapsible ~= false
            -- `accordion` categories auto-collapse to just the active one (see ExpandCategoryForView).
            hb._accordion = page.accordion and true or false
            if hb._collapsible then hb:SetScript("OnClick", function() hb._collapsed = not hb._collapsed; win:layoutNav() end) end
            win.navHeaders[#win.navHeaders + 1] = hb; order[#order + 1] = { header = hb }; curHeader = hb
        else
            local r = theme:NavRow(navChild, SIDE_W - 20)
            if page.icon then r.icon:SetTexture(page.icon) end
            r.fs:SetText(page.label); r._page = page
            if page.pulse and r.StartPulse then r:StartPulse() end   -- attention pulse for flagged pages
            -- Fire the page's onSelect on EVERY nav click (even re-clicking the current view),
            -- so a page can reset its own sub-state (e.g. drop back to its list) when re-entered.
            r:SetScript("OnClick", function()
                if page.onSelect then page.onSelect(win) end
                win:SelectView(page.view)
            end)
            r._header = curHeader; if curHeader then curHeader._rows[#curHeader._rows + 1] = r end
            win.navRows[#win.navRows + 1] = r; order[#order + 1] = { row = r, header = curHeader }
        end
    end

    -- (Re)position everything by current collapse state. When the sidebar itself is collapsed to an
    -- icon strip, category headers are hidden (replaced by a slim gap) and every row is shown as an
    -- icon regardless of its category's own collapsed state (there's no header to expand it from).
    function win:layoutNav()
        local barCollapsed = self._collapsed
        local rowX = barCollapsed and 6 or 8
        local ty = -6
        -- NB: row items ALSO carry `.header` (their parent category), so branch on `.row`.
        for i, item in ipairs(order) do
            if item.row then
                if not barCollapsed and item.header and item.header._collapsed then item.row:Hide()
                else item.row:ClearAllPoints(); item.row:SetPoint("TOPLEFT", rowX, ty); item.row:Show(); ty = ty - 30 end
            elseif barCollapsed then
                item.header:Hide()
                if i > 1 then ty = ty - 12 end   -- slim gap between groups in place of the header
            else
                if i > 1 then ty = ty - 12 end   -- extra gap above a group band so sections read apart
                item.header:ClearAllPoints(); item.header:SetPoint("TOPLEFT", 8, ty); item.header:SetPoint("RIGHT", navChild, "RIGHT", -6, 0); item.header:Show()
                item.header:SetChevron(item.header._collapsed)
                ty = ty - 24
            end
        end
        navChild:SetHeight(math.max(1, -ty + 6))
        self:updateNavScrollbar()
    end
    win:layoutNav()

    -- Optional bottom-of-sidebar action button. Sits above the collapse toggle when both are present.
    if o.sidebarButton then
        local sb = o.sidebarButton
        local btn = theme:Button(side)
        btn:Configure(sb.label, SIDE_W - 20, 28, sb.kind or "primary", sb.onClick)
        btn:ClearAllPoints(); btn:SetPoint("BOTTOMLEFT", 10, o.collapsibleSidebar and 44 or 10)
        if sb.tip then theme:SetTip(btn, sb.tip[1], sb.tip[2]) end
        win.sidebarButton = btn
    end

    -- Optional collapse toggle, pinned to the very bottom of the sidebar.
    if o.collapsibleSidebar then
        local tgl = theme:Button(side)
        win._collapseBtn = tgl
        function win:_updateCollapseBtn()
            local collapsed = self._collapsed
            local bw = collapsed and (COLLAPSED_W - 12) or (self._sideWFull - 16)
            tgl:Configure(collapsed and "" or "Collapse", bw, 26, "default",
                function() win:ToggleSidebar() end,
                { icon = collapsed and "chevron-right" or "chevron-left", iconSize = collapsed and 14 or 12 })
            tgl:ClearAllPoints(); tgl:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", collapsed and 6 or 8, 8)
            theme:SetTip(tgl, collapsed and "Expand sidebar" or "Collapse sidebar",
                collapsed and "Show the full navigation labels." or "Shrink the sidebar to icons only.")
        end
        win:_updateCollapseBtn()
    end

    -- Content scroll + child
    local contentScroll = CreateFrame("ScrollFrame", nil, mgr)
    contentScroll:SetPoint("TOPLEFT", win._sideW + 2, -HEADER_H - 6)
    contentScroll:SetPoint("BOTTOMRIGHT", -20, FOOTER_H + 6)   -- room for the scrollbar + footer
    local content = CreateFrame("Frame", nil, contentScroll); content:SetSize(o.contentWidth or (W - SIDE_W - 40), 1)
    contentScroll:SetScrollChild(content)
    win.scroll, win.content = contentScroll, content
    win.builder = theme:Builder(content, { contentWidth = o.contentWidth or (W - SIDE_W - 40) })

    -- Themed scrollbar
    local sbar = CreateFrame("Frame", nil, mgr); sbar:SetWidth(8)
    sbar:SetPoint("TOPRIGHT", -6, -HEADER_H - 8); sbar:SetPoint("BOTTOMRIGHT", -6, FOOTER_H + 8)
    local strack = sbar:CreateTexture(nil, "BACKGROUND"); strack:SetAllPoints(); UIF.paint(strack, C.card, 0.6); win._strack = strack
    local sthumb = CreateFrame("Button", nil, sbar); sthumb:SetPoint("TOP"); sthumb:SetWidth(8); sthumb:SetHeight(40)
    local sthumbTex = sthumb:CreateTexture(nil, "ARTWORK"); sthumbTex:SetAllPoints()
    win.sbar = sbar

    local function updateScrollbar()
        local vh, ch = contentScroll:GetHeight(), content:GetHeight()
        -- Midnight: scroll range/pos come back secret when content shows secret values, and
        -- comparing a secret throws. Heights are plain, so derive range from them and only
        -- read the live scroll offset when it's safe.
        if not (UIF.CanRead(vh) and UIF.CanRead(ch)) then sbar:Hide(); return end
        local range = math.max(0, (ch or 0) - (vh or 0))
        if range > 1 and ch > 0 then
            sbar:Show()
            local trackH = sbar:GetHeight()
            local thumbH = math.max(24, trackH * (vh / ch))
            sthumb:SetHeight(thumbH)
            local pos = contentScroll:GetVerticalScroll()
            local frac = UIF.CanRead(pos) and (pos / range) or 0
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            sthumb:ClearAllPoints(); sthumb:SetPoint("TOP", sbar, "TOP", 0, -frac * (trackH - thumbH))
            UIF.paint(sthumbTex, theme.C.accent)
        else
            sbar:Hide()
        end
    end
    win.updateScrollbar = updateScrollbar

    contentScroll:EnableMouseWheel(true)
    contentScroll:SetScript("OnMouseWheel", function(self, delta) UIF.scrollWheel(self, delta); updateScrollbar() end)

    sthumb:RegisterForDrag("LeftButton")
    sthumb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local range = UIF.scrollMax(contentScroll)   -- heights-based; safe vs secret range
            if range <= 0 then return end
            local trackH = sbar:GetHeight()
            local s = sbar:GetEffectiveScale()
            local _, cy = GetCursorPosition()
            local top = sbar:GetTop()
            if top and s and s > 0 then
                local frac = (top - (cy / s)) / math.max(1, trackH - self:GetHeight())
                frac = math.min(1, math.max(0, frac))
                contentScroll:SetVerticalScroll(frac * range)
                updateScrollbar()
            end
        end)
    end)
    sthumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    -- Footer (skipped entirely for style "none").
    if footerStyle ~= "none" then
        local expanded = footerStyle == "expanded"
        local textSize = expanded and 12 or 11
        local footer = CreateFrame("Frame", nil, mgr)
        footer:SetPoint("BOTTOMLEFT", 1, 1); footer:SetPoint("BOTTOMRIGHT", -1, 1); footer:SetHeight(FOOTER_H)
        local fbg = footer:CreateTexture(nil, "BACKGROUND"); fbg:SetAllPoints(); UIF.paint(fbg, C.panel); win._fbg = fbg
        local fedge = footer:CreateTexture(nil, "ARTWORK"); UIF.paint(fedge, C.border); fedge:SetHeight(1); win._fedge = fedge
        fedge:SetPoint("TOPLEFT"); fedge:SetPoint("TOPRIGHT")
        local fcfg = (type(footerCfg) == "table") and footerCfg or {}
        if fcfg.left then
            local fname = footer:CreateFontString(nil, "OVERLAY"); fname:SetFont(theme.FONT, textSize)
            fname:SetPoint("LEFT", 14, expanded and 6 or 0); fname:SetTextColor(unpack(C.text)); fname:SetText(fcfg.left); win._fLeftFS = fname
            if expanded and fcfg.subtitle then
                local sub = footer:CreateFontString(nil, "OVERLAY"); sub:SetFont(theme.FONT, 10)
                sub:SetPoint("TOPLEFT", fname, "BOTTOMLEFT", 0, -2); sub:SetTextColor(unpack(C.subtext)); sub:SetText(fcfg.subtitle)
            end
        end
        if fcfg.right then
            local fver = footer:CreateFontString(nil, "OVERLAY"); fver:SetFont(theme.FONT, textSize)
            fver:SetPoint("RIGHT", -14, 0); fver:SetTextColor(unpack(C.accent)); fver:SetText(fcfg.right)
        end
        -- Social buttons (expanded footers), a row centered in the footer.
        if expanded and fcfg.socials then
            local bar = theme:SocialBar(footer, fcfg.socials, { iconOnly = true, size = 26, gap = 6 })
            bar:SetPoint("CENTER", 0, 0)
        elseif fcfg.link and fcfg.link.url then
            local disc = CreateFrame("Button", nil, footer)
            disc.fs = disc:CreateFontString(nil, "OVERLAY"); disc.fs:SetFont(theme.FONT, textSize)
            disc.fs:SetPoint("CENTER"); disc.fs:SetText(fcfg.link.label or "Link"); disc.fs:SetTextColor(unpack(C.accent))
            disc:SetSize(disc.fs:GetStringWidth() + 12, FOOTER_H); disc:SetPoint("CENTER", footer, "CENTER", 0, 0)
            disc:SetScript("OnEnter", function(self)
                self.fs:SetTextColor(1, 1, 1)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(fcfg.link.tipTitle or "Copy link", theme:AccentHeader())
                GameTooltip:AddLine(fcfg.link.tipBody or "Click to copy the link.", 0.82, 0.86, 0.92, true); GameTooltip:Show()
            end)
            disc:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(theme.C.accent)); GameTooltip_Hide() end)
            disc:SetScript("OnClick", function()
                theme:ShowLinkDialog(fcfg.link.copyTitle or ((fcfg.link.label or "Link") .. " - copy this (Ctrl+C)"), fcfg.link.url, { autoClose = fcfg.link.autoClose })
            end)
        end
        win.footer = footer
    end

    -- Repaint all window chrome from the current palette + re-shape the frame. Used on a live
    -- skin swap (and harmless on a plain accent change).
    function win:ReskinChrome()
        local C = theme.C
        theme:StylePanel(mgr, C.bg, C.border, theme.winRadius)
        if self._hbg then UIF.paint(self._hbg, C.panel) end
        if self._sbg then UIF.paint(self._sbg, C.sidebar) end
        if self._sedge then UIF.paint(self._sedge, C.border) end
        if self._ntrack then UIF.paint(self._ntrack, C.card, 0.5) end
        if self._strack then UIF.paint(self._strack, C.card, 0.6) end
        if self._fbg then UIF.paint(self._fbg, C.panel) end
        if self._fedge then UIF.paint(self._fedge, C.border) end
        if mgr.titleFS then mgr.titleFS:SetTextColor(unpack(C.text)) end
        if self._fLeftFS then self._fLeftFS:SetTextColor(unpack(C.subtext)) end
        if self.sidebarButton then self.sidebarButton:Retheme() end
        if self._updateCollapseBtn then self:_updateCollapseBtn() end
    end

    win.built = true

    -- Apply a persisted "start collapsed" state now that every piece exists (Open() will Refresh,
    -- which re-anchors the content/scrollbar to the collapsed width).
    if o.collapsibleSidebar and win._collapsed then
        win._collapsed = false            -- flip through _applyCollapse so rows/button take the compact path
        win:_applyCollapse(true, true)    -- silent: don't re-persist the seed value
    end
end

-- Render the current page into the content builder.
function WindowMixin:Refresh()
    if not self.built then return end
    local theme, o = self.theme, self.opts
    self.theme:ApplyAccent()   -- keep highlight code / accent-derived colors current
    local mgr = self.frame
    mgr:SetScale((o.onScale and o.onScale()) or o.scale or 1)
    local W, H = self:_size()
    if self._maximized then mgr:SetSize(self._maxW, self._maxH) else mgr:SetSize(W, H) end
    self.viewportH = mgr:GetHeight() - (self._headerH or 44) - (self._footerH or 22) - 12

    -- Fluid content: stretch the content child (and builder) to the live viewport width so pages
    -- and responsive grids fill the window and react to maximize / a collapsed sidebar. Opt-in via
    -- opts.contentFluid.
    if o.contentFluid and self.content and self.builder then
        local vw = mgr:GetWidth() - (self._sideW or o.sidebarWidth or 210) - 24
        if UIF.CanRead(vw) and vw > 120 then
            self.content:SetWidth(vw)
            self.builder.contentWidth = vw
        end
    end

    if self.ReskinChrome then self:ReskinChrome() end   -- palette + shape (live skin swaps)

    -- Retheme static chrome so a live accent change (ApplyAccent) is reflected on the
    -- header logo and sidebar button too (nav rows + scrollbar recolor on their own).
    if mgr.logo then
        if o.logo then mgr.logo:SetTexture(o.logo); mgr.logo:SetTexCoord(0, 1, 0, 1); mgr.logo:SetVertexColor(theme.C.accent[1], theme.C.accent[2], theme.C.accent[3])
        else UIF.paint(mgr.logo, theme.C.accent) end
    end
    if self.sidebarButton then self.sidebarButton:Retheme() end
    -- Re-apply the live theme font to window chrome (nav + title) so a global font swap sticks, and
    -- refresh the title text: a page may contribute a `titleSuffix` (e.g. the selected module's name),
    -- so the header reads "<Window title><suffix>" while that page is open and just the base otherwise.
    if mgr.titleFS then
        mgr.titleFS:SetFont(theme.FONT, 15)
        local page = self:_pageFor(self.view)
        mgr.titleFS:SetText((o.title or "UIFoundry") .. ((page and page.titleSuffix) or ""))
    end
    for _, r in ipairs(self.navRows or {}) do r.fs:SetFont(theme.FONT, 12) end
    for _, h in ipairs(self.navHeaders or {}) do if h.fs then h.fs:SetFont(theme.FONT, 10) end end
    if self.updateNavScrollbar then C_Timer.After(0, function() self:updateNavScrollbar() end) end

    -- Nav highlight (a page's subViews keep it lit while on a sub-page).
    for _, r in ipairs(self.navRows) do
        local page = r._page
        local active = self.view == page.view
        if not active and page.subViews then
            for _, sv in ipairs(page.subViews) do if self.view == sv then active = true break end end
        end
        r:Select(active)
    end

    -- Reset scroll to top when the view changes.
    if self.view ~= self._lastView then
        self._lastView = self.view
        if self.scroll then self.scroll:SetVerticalScroll(0) end
    end

    -- Start every render with no docked top-nav; a page that wants one re-adds it in its render()
    -- (via win:SetTopNav). This auto-clears the bar when you navigate to a page that doesn't use it.
    if self.built then self:SetTopNav(nil) end

    self.builder:Reset()
    local page = self:_pageFor(self.view)
    local ok, errOrY = pcall(function()
        if page and page.render then return page.render(self.builder, self) end
    end)
    if not ok then
        local msg = tostring(errOrY)
        print("|cffff5555UIFoundry window render error:|r " .. msg)
        -- Surface the error ON the page too, so a broken page is diagnosable at a glance.
        pcall(function()
            self.builder:Wrap("|cffff5555Render error on this page:|r\n" .. msg,
                24, -24, (o.contentWidth or 600) - 40, { 0.98, 0.5, 0.5 }, 12)
        end)
        self.content:SetHeight(self.viewportH or 400)
    elseif type(errOrY) == "number" then
        -- render returned the final y offset (negative); size the scroll child to fit.
        self.content:SetHeight(math.max(self.viewportH or 400, -errOrY + 20))
    end
    if self.updateScrollbar then C_Timer.After(0, self.updateScrollbar) end
end

-- The window's current (unmaximized) size. `opts.onSize` lets the host drive it live from saved
-- settings (e.g. width/height sliders); falls back to the fixed opts.width/height.
function WindowMixin:_size()
    local o = self.opts
    if o.onSize then
        local ok, w, h = pcall(o.onSize)
        if ok and type(w) == "number" and type(h) == "number" then return w, h end
    end
    return o.width or 920, o.height or 600
end

-- Collapsible sidebar --------------------------------------------------------------------------
-- Re-lay the sidebar for the given collapsed state WITHOUT a page re-render: resize the bar, make
-- every nav row compact (icon-only) or full, and reflow the nav. `silent` skips the onCollapse
-- persistence callback (used to apply a saved seed at build).
function WindowMixin:_applyCollapse(collapsed, silent)
    if not self.built or not self.opts.collapsibleSidebar then return end
    local o = self.opts
    collapsed = collapsed and true or false
    self._collapsed = collapsed
    if not silent and o.onCollapse then pcall(o.onCollapse, collapsed) end
    local full = self._sideWFull or (o.sidebarWidth or 210)
    local cw   = o.collapsedWidth or 46
    self._sideW = collapsed and cw or full
    if self.side then self.side:SetWidth(self._sideW) end
    if self._navChild then self._navChild:SetWidth(self._sideW - 11) end
    for _, r in ipairs(self.navRows or {}) do
        r:SetWidth(collapsed and (cw - 12) or (full - 20))
        if r.SetCompact then r:SetCompact(collapsed) end
    end
    if self._updateCollapseBtn then self:_updateCollapseBtn() end
    if self.layoutNav then self:layoutNav() end
end

-- Toggle/set the collapsed state and re-render (Refresh re-anchors the content + scrollbar to the
-- new sidebar width via SetTopNav(nil) -> anchorContent).
function WindowMixin:SetSidebarCollapsed(collapsed)
    if not self.opts.collapsibleSidebar then return end
    self:_applyCollapse(collapsed)
    self:Refresh()
end
function WindowMixin:ToggleSidebar() self:SetSidebarCollapsed(not self._collapsed) end
function WindowMixin:IsSidebarCollapsed() return self._collapsed and true or false end

-- Maximize the window up to a cap: opts.maxWidth/maxHeight (window-coord px) or
-- opts.maxWidthPct/maxHeightPct (fraction of the viewport). Defaults to (almost) full screen.
function WindowMixin:Maximize()
    if not self.built or self._maximized then return end
    local mgr, o = self.frame, self.opts
    self._restoreSize = { mgr:GetWidth(), mgr:GetHeight() }
    self._restorePoint = { mgr:GetPoint() }
    -- Window-coord dimensions that fill the viewport (accounts for the window's own scale).
    local s = (mgr:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local fullW, fullH = UIParent:GetWidth() / s, UIParent:GetHeight() / s
    local capW = o.maxWidth or (o.maxWidthPct and fullW * o.maxWidthPct) or fullW
    local capH = o.maxHeight or (o.maxHeightPct and fullH * o.maxHeightPct) or fullH
    self._maxW = math.max(o.width or 920, math.min(capW, fullW) - 16)
    self._maxH = math.max(o.height or 600, math.min(capH, fullH) - 16)
    self._maximized = true
    mgr:ClearAllPoints(); mgr:SetPoint("CENTER")
    if self._updateMaxBtn then self:_updateMaxBtn() end
    self:Refresh()
end

function WindowMixin:Restore()
    if not self._maximized then return end
    local mgr = self.frame
    self._maximized = false
    if self._restoreSize then mgr:SetSize(self._restoreSize[1], self._restoreSize[2]) end
    local p = self._restorePoint
    if p and p[1] then mgr:ClearAllPoints(); mgr:SetPoint(p[1], p[2] or UIParent, p[3] or p[1], p[4] or 0, p[5] or 0) end
    if self._updateMaxBtn then self:_updateMaxBtn() end
    self:Refresh()
end

function WindowMixin:ToggleMaximize() if self._maximized then self:Restore() else self:Maximize() end end
function WindowMixin:IsMaximized() return self._maximized and true or false end

function WindowMixin:_pageFor(view)
    for _, p in ipairs(self.opts.pages or {}) do if p.view == view then return p end end
end

-- Dock a fixed, full-width navigation bar flush under the title bar - a traditional application
-- top-nav / menu bar. It spans the whole content area (right of the sidebar to the window edge) and
-- stays put while the page scrolls; the content scroll is pushed down to sit below it. Call this from
-- a page's render() with { items, active, onSelect, tip, height, gap, tabWidth } to give that page a
-- docked nav; pass nil (or no items) to remove it. Refresh() clears it before every render, so pages
-- that don't call this get none.
function WindowMixin:SetTopNav(spec)
    if not self.built then return end
    local mgr, theme = self.frame, self.theme
    local HEADER_H, FOOTER_H = self._headerH or 44, self._footerH or 0
    local SIDE_W = self._sideW or 210

    -- Restore the content scroll (and its scrollbar) to sit directly under the header.
    local function anchorContent(topOff)
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", SIDE_W + 2, -HEADER_H - topOff)
        self.scroll:SetPoint("BOTTOMRIGHT", -20, FOOTER_H + 6)
        if self.sbar then
            self.sbar:ClearAllPoints()
            self.sbar:SetPoint("TOPRIGHT", -6, -HEADER_H - topOff - 2)
            self.sbar:SetPoint("BOTTOMRIGHT", -6, FOOTER_H + 8)
        end
    end

    if not spec or not spec.items or #spec.items == 0 then
        if self.topNav then self.topNav:Hide() end
        anchorContent(6)
        return   -- clearing the bar (done every Refresh before render) must NOT touch _topNavActive
    end

    -- Scroll the body to top whenever the docked nav's active item changes - i.e. the user switched
    -- tabs. Same intent as the view-change reset in Refresh(), but for pages whose tabs live in this
    -- top-nav (they re-render in place without changing self.view). Only fires on an actual change, so
    -- re-renders that keep the same tab (e.g. live filtering) don't fight the user's scroll position.
    if spec.active ~= nil and spec.active ~= self._topNavActive then
        self._topNavActive = spec.active
        if self.scroll then self.scroll:SetVerticalScroll(0) end
    end

    if not self.topNav then
        self.topNav = theme:NavBar(mgr)
        self.topNav:SetFrameLevel(mgr:GetFrameLevel() + 6)
    end
    local band = self.topNav
    -- Full-bleed across the content area: flush under the header, no side margins.
    local contentW = math.max(1, mgr:GetWidth() - (SIDE_W + 2) - 2)
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", mgr, "TOPLEFT", SIDE_W + 2, -HEADER_H)
    band:Configure({
        items = spec.items, active = spec.active, width = contentW,
        height = spec.height or 30, gap = spec.gap or 2,
        tabWidth = spec.tabWidth, onSelect = spec.onSelect, tip = spec.tip,
    })
    band:Show()
    anchorContent(band:GetHeight() or 38)
end

-- Accordion: when categories are marked `accordion = true`, keep only the one that owns the active
-- view expanded and collapse the rest. Categories WITHOUT the flag (e.g. Platform / Help) are left
-- alone. A no-op on windows that don't use accordion categories.
function WindowMixin:ExpandCategoryForView(view)
    if not self.built or not self.navHeaders then return end
    local activeHeader
    for _, r in ipairs(self.navRows or {}) do
        if r._page and r._page.view == view then activeHeader = r._header; break end
    end
    -- On a page that isn't inside any accordion group (Platform Overview/Settings, Help), keep the FIRST
    -- addon group expanded as a fallback - so the sidebar always shows a group's pages instead of a wall
    -- of collapsed headers, which reads as "the groups aren't working".
    if not activeHeader then
        for _, hb in ipairs(self.navHeaders) do if hb._accordion then activeHeader = hb; break end end
    end
    local changed = false
    for _, hb in ipairs(self.navHeaders) do
        if hb._accordion then
            local want = (hb ~= activeHeader)   -- collapse everything except the active (or fallback) category
            if hb._collapsed ~= want then hb._collapsed = want; changed = true end
        end
    end
    if changed and self.layoutNav then self:layoutNav() end
end

-- Switch page and re-render.
function WindowMixin:SelectView(view)
    -- Notify the OUTGOING page it's being left (only on a real change), so a page can hide any
    -- persistent frame it parked over the shared content (e.g. a search box that survives Reset to
    -- keep focus). Not fired on in-page Refresh(), so it won't fight a focused control mid-edit.
    -- The incoming `view` is passed as a 2nd arg so a page's onDeselect can tell WHERE you're going
    -- (used to fire module-level leave hooks only when actually leaving the module).
    if view ~= self.view then
        local prev = self:_pageFor(self.view)
        if prev and prev.onDeselect then pcall(prev.onDeselect, self, view) end
    end
    self.view = view
    self:ExpandCategoryForView(view)
    self:Refresh()
end

-- Build (first time), show, and render. Optional view to open on.
function WindowMixin:Open(view)
    build(self)
    if view then self.view = view end
    self:ExpandCategoryForView(self.view)   -- sync accordion for a deep-linked open (doesn't go via SelectView)
    -- Self-heal size / position so a corrupt saved state can't leave it off-screen.
    local mgr, o = self.frame, self.opts
    if not self._maximized then mgr:SetSize(self:_size()) end
    mgr:Show()
    local l, r, t, b = mgr:GetLeft(), mgr:GetRight(), mgr:GetTop(), mgr:GetBottom()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if (not l) or (r and r < 40) or (l and l > sw - 40) or (t and t < 40) or (b and b > sh - 4) then
        mgr:ClearAllPoints(); mgr:SetPoint("CENTER"); if o.onMovePos then o.onMovePos(nil) end
    end
    self:Refresh()
end

function WindowMixin:Toggle(view)
    build(self)
    if self.frame:IsShown() then self.frame:Hide() else self:Open(view) end
end

function WindowMixin:Hide() if self.built then self.frame:Hide() end end
function WindowMixin:IsShown() return self.built and self.frame:IsShown() end
function WindowMixin:GetBuilder() return self.builder end

UIF.WindowMixin = WindowMixin
