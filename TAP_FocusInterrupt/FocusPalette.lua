-- TAP_FocusInterrupt - FocusPalette.lua
-- The on-screen marker palette (Focus Tools): a small movable bar of the 8 raid markers. Each
-- button is SECURE (macrotext = /focus + /tm ~i), so clicking one focuses + marks your target
-- live, even in combat, and makes it your focus marker. Extracted from the old self-skinned UI
-- and re-skinned on the suite theme; the behavior is unchanged.

local addonName, FTI = ...
local TAP   = _G.TAP
local Suite = _G.TAP
local theme = (Suite and Suite.uiTheme) or (TAP and TAP:NewTheme({ name = "TAP_FocusInterruptFocus" }))

local MARK_NAMES = { [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
                     [5] = "Moon", [6] = "Square", [7] = "Cross (X)", [8] = "Skull" }
FTI.MARK_NAMES = MARK_NAMES

local RAID_ATLAS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RT_COORDS = {   -- 4x4 atlas; 1..8 = Star,Circle,Diamond,Triangle,Moon,Square,Cross,Skull
    { 0, 0.25, 0, 0.25 }, { 0.25, 0.5, 0, 0.25 }, { 0.5, 0.75, 0, 0.25 }, { 0.75, 1, 0, 0.25 },
    { 0, 0.25, 0.25, 0.5 }, { 0.25, 0.5, 0.25, 0.5 }, { 0.5, 0.75, 0.25, 0.5 }, { 0.75, 1, 0.25, 0.5 },
}
local markerPalette
local paletteMover

function FTI.UpdateMarkerPalette()
    if not markerPalette then return end
    local mk = tonumber(FTI.db and FTI.db.macro and FTI.db.macro.mark) or 0
    for i, b in ipairs(markerPalette.btns) do b.sel:SetShown(i == mk) end
end

local CELL, GAP, EDGE = 28, 3, 6

-- Background / border colors + opacity for the bar (configurable in the module settings).
local function paletteColors()
    local m = (FTI.db and FTI.db.macro) or {}
    local bg = m.paletteBgColor or { 0.05, 0.05, 0.06 }
    local bd = m.paletteBorderColor or { 0.25, 0.25, 0.30 }
    local op = tonumber(m.paletteOpacity); if op == nil then op = 0.9 end
    return bg, bd, op
end

-- Position the 8 buttons in a row (horizontal) or column (vertical) and size the frame to match.
-- Re-anchoring the SECURE buttons is protected in combat, so callers gate on combat.
local function layoutPalette(p)
    local vertical = ((FTI.db and FTI.db.macro and FTI.db.macro.paletteRotation) == "vertical")
    for i, b in ipairs(p.btns) do
        b:ClearAllPoints()
        if vertical then b:SetPoint("TOP", p, "TOP", 0, -(EDGE + (i - 1) * (CELL + GAP)))
        else             b:SetPoint("LEFT", p, "LEFT", EDGE + (i - 1) * (CELL + GAP), 0) end
    end
    local long  = EDGE * 2 + 8 * CELL + 7 * GAP
    local short = CELL + EDGE * 2
    if vertical then p:SetSize(short, long) else p:SetSize(long, short) end
end

-- Real chrome: a fill texture PLUS four edge textures forming a true outline. Unlike a panel
-- whose "border" is a full-size texture behind the fill, this border stays crisp even when the
-- background is fully transparent (you can outline an empty bar).
local BORDER_T = 2
local function ensurePaletteChrome(p)
    if p.bgTex then return end
    p.bgTex = p:CreateTexture(nil, "BACKGROUND"); p.bgTex:SetAllPoints()
    local function edge() return p:CreateTexture(nil, "BORDER") end
    p.eTop = edge();   p.eTop:SetPoint("TOPLEFT");     p.eTop:SetPoint("TOPRIGHT");     p.eTop:SetHeight(BORDER_T)
    p.eBot = edge();   p.eBot:SetPoint("BOTTOMLEFT");  p.eBot:SetPoint("BOTTOMRIGHT");  p.eBot:SetHeight(BORDER_T)
    p.eLeft = edge();  p.eLeft:SetPoint("TOPLEFT");    p.eLeft:SetPoint("BOTTOMLEFT");  p.eLeft:SetWidth(BORDER_T)
    p.eRight = edge(); p.eRight:SetPoint("TOPRIGHT");  p.eRight:SetPoint("BOTTOMRIGHT"); p.eRight:SetWidth(BORDER_T)
end

local function colorPalette(p)
    if not p.bgTex then return end
    local bg, bd, op = paletteColors()
    p.bgTex:SetColorTexture(bg[1], bg[2], bg[3], op)
    for _, e in ipairs({ p.eTop, p.eBot, p.eLeft, p.eRight }) do e:SetColorTexture(bd[1], bd[2], bd[3], 1) end
end

-- Apply colors (safe any time) + layout (out of combat only, since children are secure). Scale is
-- handled separately by ApplyMarkerPaletteScale so it can pin the focal point.
local function applyPalettePresentation(p)
    p = p or markerPalette
    if not p then return end
    ensurePaletteChrome(p)
    colorPalette(p)
    if not (InCombatLockdown and InCombatLockdown()) then layoutPalette(p) end
end
-- Public: re-apply presentation (rotation / colors / opacity) from the settings page.
function FTI.ApplyPalettePresentation() applyPalettePresentation(markerPalette) end

local function ensureMarkerPalette()
    if markerPalette then return markerPalette end
    local C = theme.C
    local p = CreateFrame("Frame", "TAP_FocusInterruptMarkerPalette", UIParent)
    p:SetSize(EDGE * 2 + 8 * CELL + 7 * GAP, CELL + EDGE * 2)
    p:SetFrameStrata("MEDIUM"); p:SetClampedToScreen(true); p:SetMovable(true); p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(self)
        if FTI._paletteMoverOn and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, _, xo, yo = self:GetPoint()
        if FTI.db.macro then FTI.db.macro.palettePos = { pt, xo, yo } end
    end)
    p:SetScript("OnHide", function()
        if paletteMover then paletteMover:Hide() end
        FTI._paletteMoverOn = false
    end)
    ensurePaletteChrome(p); colorPalette(p)
    p.btns = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", "TAP_FocusInterruptPaletteBtn" .. i, p, "SecureActionButtonTemplate")
        b:SetSize(CELL, CELL)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", FTI.BuildFocusMacro({ mark = i, focusTarget = "smart" }))
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
        b.tex:SetTexture(RAID_ATLAS); b.tex:SetTexCoord(unpack(RT_COORDS[i]))
        b.sel = b:CreateTexture(nil, "OVERLAY"); b.sel:SetPoint("TOPLEFT", -2, 2); b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
        b.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55); b.sel:Hide()
        b:SetScript("PostClick", function()   -- insecure state update (the secure /focus + /tm already ran)
            -- The click already marked your target (secure). ALSO make it your saved focus marker,
            -- which edits the "TAP Focus" macro - that needs the macro pane open and can't happen in
            -- combat, so we only change it out of combat and force the pane open so it saves.
            if not (InCombatLockdown and InCombatLockdown()) then
                local ok = FTI.SetFocusMarker and FTI.SetFocusMarker(i)
                if ok then
                    print(FTI.PREFIX .. "Focus marker set to |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_"
                        .. i .. ":0|t " .. (MARK_NAMES[i] or ("marker " .. i)) .. ".")
                else
                    print(FTI.PREFIX .. "Marked your target, but couldn't open the macro window to save the focus-marker change.")
                end
            end
            FTI.UpdateMarkerPalette()   -- highlight follows the ACTUAL saved marker (unchanged in combat)
            FTI.RefreshManager()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(MARK_NAMES[i], theme:AccentHeader())
            GameTooltip:AddLine("Focus + mark your target with this icon.", 0.82, 0.86, 0.92, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        p.btns[i] = b
    end
    markerPalette = p
    layoutPalette(p)
    return p
end

function FTI.SetMarkerPaletteShown(show)
    if not show then if markerPalette then markerPalette:Hide() end return end
    if InCombatLockdown and InCombatLockdown() and not markerPalette then return end  -- can't build secure frames in combat
    local p = ensureMarkerPalette()
    applyPalettePresentation(p)
    if not (InCombatLockdown and InCombatLockdown()) then
        p:SetScale(tonumber(FTI.db.macro and FTI.db.macro.paletteScale) or 1)
    end
    local pos = FTI.db.macro and FTI.db.macro.palettePos
    p:ClearAllPoints()
    if pos and pos[1] then p:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
    else p:SetPoint("CENTER", UIParent, "CENTER", 0, -220) end
    FTI.UpdateMarkerPalette()
    p:Show()
end

function FTI.ApplyMarkerPaletteScale()
    local p = markerPalette
    if not p then return end
    local scale = tonumber(FTI.db.macro and FTI.db.macro.paletteScale) or 1
    local point, rel, relPoint, dx, dy = p:GetPoint()
    local os = p:GetScale()
    p:SetScale(scale)
    if point and dx and dy and os and os > 0 and scale > 0 then
        dx, dy = dx * os / scale, dy * os / scale
        p:ClearAllPoints()
        p:SetPoint(point, rel or UIParent, relPoint or point, dx, dy)
        if FTI.db.macro then FTI.db.macro.palettePos = { point, dx, dy } end
    end
end

local function paletteContextAllows(setting)
    if not setting or setting == "always" then return true end
    if setting == "group" then return IsInGroup and IsInGroup() and true or false end
    local inInstance, itype = false, "none"
    if IsInInstance then inInstance, itype = IsInInstance() end
    if setting == "any_instance" then return inInstance and true or false end
    return itype == setting
end

-- The single place that decides whether the bar is on screen. Respects the Focus Tools module
-- being enabled, the palette's own toggle, and its context gate. No-ops in combat (can't change
-- a frame with secure children) and re-runs on PLAYER_REGEN_ENABLED.
function FTI.RefreshMarkerPaletteVisibility()
    local m = FTI.db and FTI.db.macro
    if not m then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if FTI.focusEnabled ~= false and m.paletteShown and paletteContextAllows(m.paletteVisibility) then
        FTI.SetMarkerPaletteShown(true)
    elseif markerPalette then
        markerPalette:Hide()
    end
end

local paletteWatcher
function FTI.EnsureMarkerPaletteWatcher()
    if paletteWatcher then return end
    paletteWatcher = CreateFrame("Frame")
    paletteWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    paletteWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    paletteWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    paletteWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    paletteWatcher:SetScript("OnEvent", function() FTI.RefreshMarkerPaletteVisibility() end)
end

function FTI.SetMarkerPaletteEnabled(on)
    local m = FTI.db and FTI.db.macro
    if not m then return end
    m.paletteShown = on and true or false
    FTI.EnsureMarkerPaletteWatcher()
    if InCombatLockdown and InCombatLockdown() then
        print(FTI.PREFIX .. "Marker palette will " .. (m.paletteShown and "appear" or "hide") .. " when you leave combat.")
    else
        FTI.RefreshMarkerPaletteVisibility()
    end
end

-- On-screen mover: a small panel above the bar (drag to move + a resize slider).
local function ensurePaletteMover()
    if paletteMover then return paletteMover end
    local C = theme.C
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetSize(280, 62); m:SetFrameStrata("DIALOG"); m:SetClampedToScreen(true)
    m:EnableMouse(true); m:RegisterForDrag("LeftButton")
    theme:StylePanel(m, C.panel, C.accent)
    m:SetScript("OnDragStart", function()
        if markerPalette and not (InCombatLockdown and InCombatLockdown()) then markerPalette:StartMoving() end
    end)
    m:SetScript("OnDragStop", function()
        if not markerPalette then return end
        markerPalette:StopMovingOrSizing()
        local pt, _, _, xo, yo = markerPalette:GetPoint()
        if FTI.db.macro then FTI.db.macro.palettePos = { pt, xo, yo } end
    end)
    local hint = m:CreateFontString(nil, "OVERLAY"); hint:SetFont(theme.FONT, 11)
    hint:SetPoint("TOPLEFT", 12, -9); hint:SetTextColor(unpack(C.subtext))
    hint:SetText("|cffffffffDrag this panel|r to move the bar")
    local done = theme:Button(m); done:Configure("Done", 56, 18, "primary", function() FTI.SetMarkerPaletteMover(false) end)
    done:SetPoint("TOPRIGHT", -8, -7)
    local sizeLbl = m:CreateFontString(nil, "OVERLAY"); sizeLbl:SetFont(theme.FONT, 11)
    sizeLbl:SetPoint("BOTTOMLEFT", 12, 11); sizeLbl:SetTextColor(unpack(C.subtext)); sizeLbl:SetText("Size")
    m.slider = theme:Slider(m); m.slider:SetPoint("BOTTOMLEFT", 46, 11)
    m.slider:Configure(198, 0.6, 2.0, 0.05,
        function() return tonumber(FTI.db.macro and FTI.db.macro.paletteScale) or 1 end,
        function(v) if FTI.db.macro then FTI.db.macro.paletteScale = v end; FTI.ApplyMarkerPaletteScale() end, "%.2f")
    paletteMover = m
    return m
end

function FTI.SetMarkerPaletteMover(on)
    if on then
        if not markerPalette or not markerPalette:IsShown() then return end
        if InCombatLockdown and InCombatLockdown() then
            print(FTI.PREFIX .. "Can't reposition the marker bar during combat.")
        else
            local m = ensurePaletteMover()
            m:ClearAllPoints(); m:SetPoint("BOTTOM", markerPalette, "TOP", 0, 12)
            m:Show(); FTI._paletteMoverOn = true
        end
    else
        if paletteMover then paletteMover:Hide() end
        FTI._paletteMoverOn = false
    end
    FTI.RefreshManager()
end
