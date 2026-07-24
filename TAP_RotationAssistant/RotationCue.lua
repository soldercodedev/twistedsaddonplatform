-- TAP_RotationAssistant - RotationCue.lua
-- A sidecar plugin for Twisteds Addon Platform.
--
-- Reads Blizzard's built-in one-button rotation (C_AssistedCombat.GetNextCastSpell), finds
-- that spell on the player's action bars (C_ActionBar.FindSpellActionButtons), and draws its
-- on-screen KEYBIND as a cue. Show-only: it never presses anything, so no secure/protected
-- action is involved. See RotationKeybindCue.md for the design notes this implements.
--
-- The whole feature is wrapped as a suite module: it does nothing until enabled from /tap,
-- and OnDisable fully stands it down (hides the cue, unregisters every event).

local TAP   = _G.TAP
local Suite = _G.TAP

if not (TAP and Suite) then
    print("|cffff5555TAP_RotationAssistant:|r requires TAP. Enable it and reload.")
    return
end

----------------------------------------------------------------------
-- Guarded Midnight rotation API. Present from 11.1.7 on; nil on older clients.
----------------------------------------------------------------------
local AC        = _G.C_AssistedCombat
local GetNext   = AC and AC.GetNextCastSpell
local FindSlots = _G.C_ActionBar and _G.C_ActionBar.FindSpellActionButtons
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local GetSpellInfoT   = C_Spell and C_Spell.GetSpellInfo
local GetSpellCooldownT = C_Spell and C_Spell.GetSpellCooldown
local IsSpellInRangeT = C_Spell and C_Spell.IsSpellInRange
local IsSpellUsableT  = C_Spell and C_Spell.IsSpellUsable
local GCD_SPELL = 61304   -- the "Global Cooldown" spell; its cooldown IS the GCD

-- Can you AFFORD the suggested spell right now? IsSpellUsable's 2nd return flags "not enough power"
-- (mana / energy / rage / combo points / ...). true = affordable / unknown; false = short on resource.
local function spellAffordable(spellID)
    if not spellID or not IsSpellUsableT then return true end
    local ok, _, insufficientPower = pcall(IsSpellUsableT, spellID)
    if ok and insufficientPower then return false end
    return true
end

-- Is the suggested spell in range of your current target? true / false / nil (no target or the
-- spell isn't range-checkable, in which case we DON'T tint - you're not "out of range" of nothing).
local function spellInRange(spellID)
    if not spellID or not (UnitExists and UnitExists("target")) then return nil end
    if IsSpellInRangeT then
        local ok, r = pcall(IsSpellInRangeT, spellID, "target")
        if ok then return r end
    end
    return nil
end
-- Is a spell currently proc-glowing (spell activation overlay) on the bars?
local IsOverlayed = _G.IsSpellOverlayed or (_G.C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)

-- The next suggested spell's cast time in ms (nil if it can't be read). Tries the modern table API,
-- the per-field API, then the legacy multi-return - whichever this client actually exposes.
local function spellCastMS(spellID)
    if not spellID then return nil end
    if GetSpellInfoT then
        local ok, info = pcall(GetSpellInfoT, spellID)
        if ok and type(info) == "table" and info.castTime ~= nil then return info.castTime end
    end
    if _G.GetSpellCastTime then                         -- some clients expose this directly
        local ok, ms = pcall(GetSpellCastTime, spellID)
        if ok and ms ~= nil then return ms end
    end
    return nil
end

-- Does the next suggested spell have a cast time (hard cast) or is it instant?
local function spellIsCast(spellID)
    local ms = spellCastMS(spellID)
    return (ms and ms > 0) and true or false
end
local RANGE     = _G.RANGE_INDICATOR or "\226\151\143"   -- the range dot HotKey text we must ignore
local QUESTION  = 134400   -- inv_misc_questionmark fallback icon

-- Bundled shape art (shape masks + border rings) lives in the always-present parent hub.
local SHAPE_DIR = "Interface\\AddOns\\TAP\\assets\\shapes\\"

-- Where the keybind text sits relative to the icon: anchor-on-text, anchor-on-frame, x, y.
local TEXT_ANCHORS = {
    BOTTOM      = { "TOP", "BOTTOM", 0, -2 },
    TOP         = { "BOTTOM", "TOP", 0, 2 },
    LEFT        = { "RIGHT", "LEFT", -4, 0 },
    RIGHT       = { "LEFT", "RIGHT", 4, 0 },
    CENTER      = { "CENTER", "CENTER", 0, 0 },
    TOPLEFT     = { "TOPLEFT", "TOPLEFT", 2, -2 },
    TOPRIGHT    = { "TOPRIGHT", "TOPRIGHT", -2, -2 },
    BOTTOMLEFT  = { "BOTTOMLEFT", "BOTTOMLEFT", 2, 2 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2 },
}
local TEXT_ANCHOR_ORDER = { "BOTTOM", "TOP", "LEFT", "RIGHT", "CENTER", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "custom" }
local ANCHOR_LABELS = {
    BOTTOM = "Below", TOP = "Above", LEFT = "Left", RIGHT = "Right", CENTER = "Center (over icon)",
    TOPLEFT = "Top-left", TOPRIGHT = "Top-right", BOTTOMLEFT = "Bottom-left", BOTTOMRIGHT = "Bottom-right",
    custom = "Custom (X / Y offset)",
}

local theme = TAP:NewTheme({
    name    = "TAP_RotationAssistant",
    accent  = { 0.62, 0.36, 0.96 },
    iconDir = "Interface\\AddOns\\TAP\\assets\\icons\\",
})

-- Which button frames to harvest keybind text from (every standard action bar).
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton",
    "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

----------------------------------------------------------------------
-- Module-scoped runtime state.
----------------------------------------------------------------------
local mod                    -- suite module handle (settings live here)
local cue                    -- on-screen frame
local driver                 -- event-only driver frame (the poll is a C_Timer ticker, not OnUpdate)
local slotToButton = {}      -- reverse map: action slot -> the action button frame that owns it
local keyCache = {}          -- spellID -> resolved key string (false = looked-up-but-unbound)
local glowing = {}           -- spellID -> true while its proc (spell activation overlay) is up
local testMode = false       -- preview mode (settings page / placement) - shows the cue on-demand
local placing = false        -- true only while in placement mode (the ONLY time the cue is draggable)
local inCombat = false       -- tracked from REGEN events (reliable, unlike InCombatLockdown timing)
local scanInterval = 0.1     -- seconds between poll ticks (cached from settings)
local diagRefreshes = 0      -- /rcue diagnostics: how many times refresh() has run
local diagEvents = 0         -- ... and how many driver events have fired
local DEFAULT_POS = { x = 0, y = 140 }   -- offset from UIParent CENTER (scale-independent)

local function S() return mod:GetSettings() end

-- Seed defaults once so the settings page and runtime agree.
local function seedDefaults()
    local s = S()
    local defaults = {
        scale = 1.0, iconSize = 48, iconZoom = 1.0,
        onlyInCombat = true, visibleOnly = false, showGlow = true,
        scanInterval = 0.1,
        shape = "square", textAnchor = "BOTTOM", textX = 0, textY = 0,
        borderSize = 3,
        keySize = 20, keyFont = "UBUNTU",
        opacity = 1, borderOpacity = 1, iconOpacity = 1, textOpacity = 1,
        castIndicator = false, castStyle = "dot",
        showGCD = false, gcdOpacity = 0.6,
        rangeCheck = false, rangeStyle = "red",
        resourceCheck = false, resourceStyle = "tint",
    }
    for k, v in pairs(defaults) do if s[k] == nil then s[k] = v end end
    if s.borderColor == nil then s.borderColor = { theme.C.accent[1], theme.C.accent[2], theme.C.accent[3] } end
    if s.castColor    == nil then s.castColor    = { 1, 0.85, 0.15 } end   -- hard cast = yellow
    if s.instantColor == nil then s.instantColor = { 0.30, 1, 0.45 } end   -- instant = green
    if s.rangeColor   == nil then s.rangeColor   = { 1, 0.25, 0.25 } end    -- out of range = red
    if s.resourceColor == nil then s.resourceColor = { 0.40, 0.50, 1 } end  -- no resource = blue
    -- One-time move to the clearer corner-dot style (the old border-tint default was easy to miss on
    -- a warm-colored border). Runs once; a later manual choice of "border" is respected.
    if not s._castStyleV2 then s.castStyle = "dot"; s._castStyleV2 = true end
    if s.keyColor    == nil then s.keyColor = { 1, 1, 1 } end
    if s.specs       == nil then s.specs = {} end   -- class/spec visibility filter (empty = all)
    if s.pos         == nil then s.pos = { x = DEFAULT_POS.x, y = DEFAULT_POS.y } end
end

----------------------------------------------------------------------
-- Keybind resolution (bar-addon agnostic). We map each action SLOT to the button frame that
-- currently owns it, then read the key off that live button. Three button sources are
-- harvested so it works everywhere:
--   1. Blizzard's named buttons (default UI, and restyle overhauls like EllesmereUI that keep
--      the Blizzard bars) + Blizzard's own ActionBarButtonEventsFrame registry.
--   2. LibActionButton-1.0 buttons - the shared engine behind ElvUI, Bartender4 and Dominos.
-- For each button we prefer the addon's own formatted hotkey, then the on-screen HotKey text,
-- then the raw key binding (so a hidden-hotkey-text setting still resolves instead of "?").
----------------------------------------------------------------------
-- Shorten a raw binding key ("SHIFT-BUTTON4") into the compact form the game shows ("S-M4").
local function abbrev(key)
    if not key or key == "" then return nil end
    key = key:upper()
    key = key:gsub("ALT%-", "A-"):gsub("CTRL%-", "C-"):gsub("SHIFT%-", "S-")
    key = key:gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD")
    key = key:gsub("BUTTON", "M")          -- mouse buttons: BUTTON4 -> M4
    key = key:gsub("NUMPAD", "N")
    key = key:gsub("SPACE", "SPC")
    return key
end

-- The Blizzard binding command a button fires ("ACTIONBUTTON1", "MULTIACTIONBAR1BUTTON3", ...).
local function commandForButton(btn)
    if btn.commandName then return btn.commandName end
    local bt, id = btn.buttonType, (btn.GetID and btn:GetID())
    if bt and id then return bt .. id end
    return nil
end

-- The action slot a button currently holds, across button implementations.
local function actionOfButton(btn)
    if btn.GetAction then
        local ok, t, a = pcall(btn.GetAction, btn)
        if ok and t == "action" and a and TAP.CanRead(a) then return a end
    end
    local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
    if slot and TAP.CanRead(slot) then return slot end
    return nil
end

-- A button's displayed key, across button implementations.
local function keyForButton(btn)
    if btn.GetHotkey then
        local ok, hk = pcall(btn.GetHotkey, btn)
        if ok and hk and hk ~= "" and hk ~= RANGE then return hk end
    end
    local hk = btn.HotKey
    local txt = hk and hk.GetText and hk:GetText()
    if txt and txt ~= "" and txt ~= RANGE then return txt end
    local cmd = commandForButton(btn)
    if cmd then
        local key = GetBindingKey(cmd)
        if key then return abbrev(key) end
    end
    return nil
end

-- The standard Blizzard binding command for an ACTION SLOT (1-120), by the fixed slot range each bar
-- owns. This lets us resolve a keybind straight from the slot FindSpellActionButtons reports even when
-- NO button frame was harvested for it (a bar addon we don't recognise, or a bar whose frames aren't
-- named/registered where we look - the "NO BUTTON MAPPED -> ?" case). Each MultiBar owns a contiguous
-- 12-slot block; the main bar (1-12) assumes page 1 / no active bonus bar, which is the common case.
local SLOT_RANGES = {
    { 1,  "ACTIONBUTTON" },            -- 1-12   Action Bar 1 (main, page 1)
    { 25, "MULTIACTIONBAR3BUTTON" },   -- 25-36  Right bar
    { 37, "MULTIACTIONBAR4BUTTON" },   -- 37-48  Left bar
    { 49, "MULTIACTIONBAR2BUTTON" },   -- 49-60  Bottom Right bar
    { 61, "MULTIACTIONBAR1BUTTON" },   -- 61-72  Bottom Left bar
    { 73, "MULTIACTIONBAR5BUTTON" },   -- 73-84  Action Bar 6
    { 85, "MULTIACTIONBAR6BUTTON" },   -- 85-96  Action Bar 7
    { 97, "MULTIACTIONBAR7BUTTON" },   -- 97-108 Action Bar 8
}
local function commandForSlot(slot)
    if type(slot) ~= "number" then return nil end
    for _, r in ipairs(SLOT_RANGES) do
        local base = r[1]
        if slot >= base and slot <= base + 11 then return r[2] .. (slot - base + 1) end
    end
    return nil
end

-- Keybind for an action SLOT via its standard binding command (fallback for keyForButton).
local function keyForSlot(slot)
    local cmd = commandForSlot(slot)
    if not cmd then return nil end
    local key = GetBindingKey(cmd)
    return key and abbrev(key) or nil
end

-- Harvest every LibActionButton-1.0 instance (ElvUI/Bartender/Dominos each embed their own copy).
local function harvestLAB(add)
    local LibStub = _G.LibStub
    if not (LibStub and LibStub.libs) then return end
    for name, lib in pairs(LibStub.libs) do
        if type(name) == "string" and name:find("LibActionButton") and type(lib) == "table" and lib.GetAllButtons then
            local ok, buttons = pcall(lib.GetAllButtons, lib)
            if ok and type(buttons) == "table" then
                for k, v in pairs(buttons) do
                    add((type(k) == "table" and k) or (type(v) == "table" and v) or nil)
                end
            end
        end
    end
end

-- Rebuild the slot -> button map from all sources. When two buttons claim the same slot (e.g. a
-- hidden Blizzard button shadowed by an ElvUI one), keep whichever actually resolves a key.
local function rebuildSlotMap()
    wipe(slotToButton)
    wipe(keyCache)   -- keys are derived from the map; rebuilding it invalidates every cached key
    local function add(btn)
        if not btn then return end
        local slot = actionOfButton(btn)
        if not slot then return end
        if not slotToButton[slot] or keyForButton(btn) then slotToButton[slot] = btn end
    end
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do add(_G[prefix .. i]) end
    end
    local ev = _G.ActionBarButtonEventsFrame
    if ev and ev.frames then for _, btn in pairs(ev.frames) do add(btn) end end
    harvestLAB(add)
end

-- spellID -> keybind string (or nil). Cached per spellID; rebuildSlotMap wipes the cache on
-- every bind / bar / page change (the CACHE_EVENTS), so a hit is always current. The suggestion
-- usually repeats for many ticks, so this makes the steady-state lookup a single hash hit.
local function keybindForSpell(spellID)
    if not FindSlots then return nil end
    local cached = keyCache[spellID]
    if cached ~= nil then return cached or nil end        -- false = resolved-but-unbound
    if not next(slotToButton) then rebuildSlotMap() end   -- lazy heal if the map is empty
    local resolved
    local slots = FindSlots(spellID)
    if type(slots) == "table" then
        for _, slot in ipairs(slots) do
            if TAP.CanRead(slot) then
                local btn = slotToButton[slot]
                -- Prefer the live button's key; fall back to the slot's standard binding command when no
                -- button frame was harvested for that slot (e.g. an unrecognised bar addon) so it still
                -- resolves instead of showing "?".
                local k = (btn and keyForButton(btn)) or keyForSlot(slot)
                if k then resolved = k; break end
            end
        end
    end
    keyCache[spellID] = resolved or false
    return resolved
end

----------------------------------------------------------------------
-- Proc glow (a.k.a. spell activation overlay): the highlight the bars show when the suggested
-- ability procs. Drawn as a pulsing, shaped gold ring outset around the icon. (We render it
-- ourselves rather than calling ActionButton_ShowOverlayGlow, which silently no-ops on a plain
-- frame in Midnight - the reason it wasn't appearing.)
----------------------------------------------------------------------
local function setGlow(on)
    if not cue then return end
    local g = cue._glow
    if on then
        if not g then
            g = (cue.chrome or cue):CreateTexture(nil, "OVERLAY", nil, 7)
            g:SetPoint("TOPLEFT", cue, "TOPLEFT", -5, 5); g:SetPoint("BOTTOMRIGHT", cue, "BOTTOMRIGHT", 5, -5)
            g:SetBlendMode("ADD")
            g:SetVertexColor(1.0, 0.85, 0.30)
            local ag = g:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
            local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0.45); a:SetToAlpha(1); a:SetDuration(0.5)
            g._ag = ag; cue._glow = g
        end
        local shp = S().shape or "square"
        local k = math.max(3, math.min(10, math.floor((S().borderSize or 3) + 0.5)))
        g:SetTexture(SHAPE_DIR .. "ring-" .. shp .. "-" .. k .. ".tga")
        g:Show(); if g._ag and not g._ag:IsPlaying() then g._ag:Play() end
    elseif g then
        if g._ag then g._ag:Stop() end
        g:Hide()
    end
    cue._glowOn = on
end

----------------------------------------------------------------------
-- The on-screen cue frame (built once, reused across enable/disable).
--   icon : the spell art, clipped to the shape via a mask. NO fill sits behind it, so fading
--          the icon reveals the world - not a dark plate.
--   ring : a real hollow border ring (its centre is transparent), drawn over the icon's edge;
--          thickness comes from pre-baked ring textures, color + opacity are tint + alpha.
----------------------------------------------------------------------
-- Pre-baked ring thickness levels available on disk (ring-<shape>-1 .. -10).
local RING_MIN, RING_MAX = 1, 10

local function ringPath(shape, borderSize)
    local k = math.max(RING_MIN, math.min(RING_MAX, math.floor((borderSize or 3) + 0.5)))
    return SHAPE_DIR .. "ring-" .. shape .. "-" .. k .. ".tga"
end

-- Icon crop from a zoom factor. z=1 -> the standard 0.07..0.93 trim of the icon's own border;
-- higher zooms in (tighter crop), lower shows more of the art (clamped to the full texture).
local function iconCoords(zoom)
    local half = 0.43 / (zoom or 1)
    if half > 0.5 then half = 0.5 end
    return 0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half
end

-- Build a cue-shaped frame: spell icon clipped to the shape (NO fill behind it, so fading the
-- icon reveals the world), a hollow border ring over its edge, and the keybind text. Position,
-- drag and glow belong to the live cue only, added by buildCue().
local function buildCueFrame(parent, name)
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(48, 48)
    local icon = f:CreateTexture(nil, "ARTWORK", nil, 0); icon:SetAllPoints(f); f.icon = icon
    local maskTex = f:CreateMaskTexture(); maskTex:SetAllPoints(icon); icon:AddMaskTexture(maskTex); f.maskTex = maskTex
    -- GCD sweep sits JUST ABOVE the icon (its own frame one level up), so it wipes over the art but
    -- UNDER the border / keybind / indicator (which live on the chrome frame above it).
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(icon); cd:SetDrawEdge(false); cd:SetDrawBling(false)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    cd:SetFrameLevel(f:GetFrameLevel() + 1); cd:Hide(); f.cd = cd
    -- Chrome layer: border ring + keybind + indicator dot (+ the live glow), above the GCD sweep.
    local chrome = CreateFrame("Frame", nil, f); chrome:SetAllPoints(f)
    chrome:SetFrameLevel(f:GetFrameLevel() + 5); f.chrome = chrome
    local ring = chrome:CreateTexture(nil, "ARTWORK", nil, 2); ring:SetAllPoints(f); f.ring = ring
    -- Cast/instant indicator dot (corner-dot style); recolored + shown on demand. A dark backing
    -- gives it an outline so it reads on bright icons.
    local pipBg = chrome:CreateTexture(nil, "OVERLAY", nil, 5); pipBg:Hide(); f.pipBg = pipBg
    local pip   = chrome:CreateTexture(nil, "OVERLAY", nil, 6); pip:Hide();   f.pip   = pip
    local key = chrome:CreateFontString(nil, "OVERLAY"); key:SetFont(theme.FONT, 20, "OUTLINE"); key:SetTextColor(1, 1, 1); f.key = key
    return f
end

-- Apply appearance (shape / border / icon mask + zoom / opacity / font / text placement) to a
-- cue-shaped frame at a display size. Shared by the live cue and the settings preview. Does NOT
-- touch position, lock, or which spell is shown.
local function applyAppearance(f, s, size)
    local shape = s.shape or "square"
    local dispScale = size / (s.iconSize or 48)
    f:SetSize(size, size)
    f.maskTex:SetTexture(SHAPE_DIR .. "mask-" .. shape .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.icon:SetTexCoord(iconCoords(s.iconZoom or 1))
    if (s.borderSize or 0) >= 1 then
        f.ring:SetTexture(ringPath(shape, s.borderSize))
        f.ring:SetVertexColor(s.borderColor[1], s.borderColor[2], s.borderColor[3])
        f.ring:SetAlpha(s.borderOpacity or 1)
        -- The ring texture's band runs INWARD from its outer edge. To sit the border OUTSIDE the
        -- icon (not over the art), enlarge the ring so its INNER edge lands on the frame boundary
        -- (= the icon/mask edge) and the band extends outward beyond the frame.
        local k = math.max(RING_MIN, math.min(RING_MAX, math.floor((s.borderSize or 3) + 0.5)))
        local bandFrac = (k * 3) / 128                 -- band thickness per side, as a texture fraction
        local ringSize = size / (1 - 2 * bandFrac)
        f.ring:ClearAllPoints(); f.ring:SetPoint("CENTER", f, "CENTER"); f.ring:SetSize(ringSize, ringSize)
        f.ring:Show()
    else
        f.ring:Hide()
    end
    f:SetAlpha(s.opacity or 1)
    f.icon:SetAlpha(s.iconOpacity or 1)
    f.key:SetAlpha(s.textOpacity or 1)
    f.key:SetFont(TAP.ResolveFontFile(theme:ResolveFont(s.keyFont or "UBUNTU")), (s.keySize or 20) * dispScale, "OUTLINE")
    f.key:SetTextColor(s.keyColor[1], s.keyColor[2], s.keyColor[3])
    f.key:ClearAllPoints()
    if (s.textAnchor or "BOTTOM") == "custom" then
        f.key:SetPoint("CENTER", f, "CENTER", (s.textX or 0) * dispScale, (s.textY or 0) * dispScale)
    else
        local A = TEXT_ANCHORS[s.textAnchor] or TEXT_ANCHORS.BOTTOM
        f.key:SetPoint(A[1], f, A[2], A[3], A[4])
    end
    -- Corner-dot indicator geometry (color/visibility handled dynamically per spell).
    local pipSz = math.max(8, size * 0.30)
    f.pip:SetSize(pipSz, pipSz)
    f.pip:ClearAllPoints(); f.pip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    f.pipBg:SetSize(pipSz + 4, pipSz + 4)
    f.pipBg:ClearAllPoints(); f.pipBg:SetPoint("CENTER", f.pip, "CENTER", 0, 0)
    -- GCD sweep sits on the icon. Clip it to the icon SHAPE by using the shape mask as the swipe
    -- texture: the mask is white RGB with the shape in its ALPHA channel, so the radial wipe is
    -- tinted by SetSwipeColor and revealed only within the shape (no square overhang on hexagons).
    if f.cd then
        f.cd:SetSwipeColor(0, 0, 0, s.gcdOpacity or 0.6)
        if f.cd.SetSwipeTexture then
            f.cd:SetSwipeTexture(SHAPE_DIR .. "mask-" .. shape .. ".tga")
        end
    end
end

-- Color the cue by whether the next ability is a hard cast or instant. Two styles: tint the
-- border ring, or a corner dot. Called live (per spell) and for the preview.
local function applyCastIndicator(f, s, spellID)
    if not f then return end
    local function hidePip() f.pip:Hide(); if f.pipBg then f.pipBg:Hide() end end
    if not s.castIndicator then
        hidePip()
        if s.borderColor then f.ring:SetVertexColor(s.borderColor[1], s.borderColor[2], s.borderColor[3]) end
        return
    end
    local isCast = spellIsCast(spellID)
    local col = isCast and (s.castColor or { 1, 0.85, 0.15 }) or (s.instantColor or { 0.30, 1, 0.45 })
    if (s.castStyle or "dot") == "dot" or not f.ring:IsShown() then
        if f.pipBg then f.pipBg:SetColorTexture(0, 0, 0, 0.9); f.pipBg:Show() end
        f.pip:SetColorTexture(col[1], col[2], col[3], 1); f.pip:Show()
        if s.borderColor then f.ring:SetVertexColor(s.borderColor[1], s.borderColor[2], s.borderColor[3]) end
    else
        hidePip()
        f.ring:SetVertexColor(col[1], col[2], col[3])
    end
end

-- Drive the GCD sweep from the Global Cooldown. Idempotent: only (re)starts the swipe when a new
-- GCD begins, so calling it every tick is cheap and flicker-free.
local function applyGCD(f, s)
    if not (f and f.cd) then return end
    if not s.showGCD then f.cd:Hide(); f._gcdStart = nil; return end
    f.cd:Show(); f.cd:SetSwipeColor(0, 0, 0, s.gcdOpacity or 0.6)
    local start, dur
    if GetSpellCooldownT then
        local info = GetSpellCooldownT(GCD_SPELL)
        if info then start, dur = info.startTime, info.duration end
    end
    if start and dur and dur > 0 then
        if f._gcdStart ~= start then f.cd:SetCooldown(start, dur); f._gcdStart = start end
    elseif f._gcdStart then
        if f.cd.Clear then f.cd:Clear() else f.cd:SetCooldown(0, 0) end
        f._gcdStart = nil
    end
end

-- Icon feedback for "can't use this right now": out of range, or can't afford (resource). Both
-- recolor/desaturate the icon; out-of-range wins when both apply (you can't even reach). Called
-- every tick since range/resource change independently of which spell is suggested.
local function tintIcon(f, style, color)
    if style == "grey" then
        f.icon:SetDesaturated(true); f.icon:SetVertexColor(0.7, 0.7, 0.7)
    else
        f.icon:SetDesaturated(false)
        f.icon:SetVertexColor(color[1], color[2], color[3])
    end
end
local function applyIconState(f, s, spellID)
    if not f then return end
    if s.rangeCheck and spellInRange(spellID) == false then
        tintIcon(f, s.rangeStyle or "red", s.rangeColor or { 1, 0.25, 0.25 })
    elseif s.resourceCheck and not spellAffordable(spellID) then
        tintIcon(f, s.resourceStyle or "tint", s.resourceColor or { 0.4, 0.5, 1 })
    else
        f.icon:SetDesaturated(false); f.icon:SetVertexColor(1, 1, 1)
    end
end

local function buildCue()
    if cue then return cue end
    cue = buildCueFrame(UIParent, "TAP_RotationAssistantFrame")
    cue:SetFrameStrata("MEDIUM"); cue:SetClampedToScreen(true); cue:Hide()
    cue:RegisterForDrag("LeftButton")
    cue:SetScript("OnDragStart", function(self) if placing then self:StartMoving() end end)
    cue:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Store the CENTRE offset from UIParent (scale-independent), so re-scaling never moves it.
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then S().pos = { x = cx - ux, y = cy - uy } end
    end)
    return cue
end

-- Forward-declared: the ticker callback, assigned far below.
local refresh

----------------------------------------------------------------------
-- The poll: a SINGLE C_Timer ticker, running ONLY while the cue could be shown (in combat, or
-- always when not combat-gated). Defined up here so refresh() can self-cancel every tick - a
-- hard guarantee it never keeps polling out of combat, whatever the event timing.
----------------------------------------------------------------------
local ticker, tickerInterval
local function stopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end
local function needsPoll()
    if not mod then return false end
    if not S().onlyInCombat then return true end
    return inCombat   -- combat flag set by REGEN events (stable throughout combat)
end
local function startTicker()
    if ticker then ticker:Cancel() end
    tickerInterval = scanInterval
    ticker = C_Timer.NewTicker(scanInterval, function() refresh() end)
end
-- Called from applyLayout and the combat events: start / stop / retime to match the state.
local function syncTicker()
    if needsPoll() then
        if (not ticker) or tickerInterval ~= scanInterval then startTicker() end
    else
        stopTicker()
    end
end

-- Live preview shown on the settings page (created lazily by the Settings renderer).
local preview
local PREVIEW_MAX = 140   -- preview icon display cap (px); the PREVIEW cell's box is sized to fit

-- Cheap per-tick update: show the player's ACTUAL next-cast suggestion + its keybind; fall back
-- to a Fireball demo when there's no suggestion (e.g. out of combat with no target).
local function updatePreviewSpell()
    if not preview or not preview:IsVisible() then return end
    local spellID
    if GetNext then
        local ok, id = pcall(GetNext, false)
        if ok and id and TAP.CanRead(id) then spellID = id end
    end
    local shown = spellID or 133   -- demo = Fireball (a cast) when there's no live suggestion
    if spellID then
        preview.icon:SetTexture((GetSpellTexture and GetSpellTexture(spellID)) or QUESTION)
        preview.key:SetText(keybindForSpell(spellID) or "?")
    else
        preview.icon:SetTexture((GetSpellTexture and GetSpellTexture(133)) or QUESTION)   -- demo
        preview.key:SetText("S-4")
    end
    applyCastIndicator(preview, S(), shown)
    applyIconState(preview, S(), shown)
end

-- Full update: restyle appearance from settings, then refresh the shown spell.
local function updatePreview()
    if not preview or not preview:IsVisible() then return end
    local s = S()
    local size = math.min((s.iconSize or 48) * (s.scale or 1), PREVIEW_MAX)
    applyAppearance(preview, s, size)
    updatePreviewSpell()
    applyGCD(preview, s)
end

-- The four indicator previews on the Indicators page (GCD / Range / Resource / Cast). Each is a demo
-- cue styled from the live APPEARANCE settings, then forced to SHOW one indicator's effect using that
-- indicator's own colors + style - so you see what each looks like without having to trigger it live.
local IND_PREVIEWS = {
    { key = "gcd",      label = "GCD",      enabledKey = "showGCD" },
    { key = "range",    label = "Range",    enabledKey = "rangeCheck" },
    { key = "resource", label = "Resource", enabledKey = "resourceCheck" },
    { key = "cast",     label = "Cast",     enabledKey = "castIndicator" },
}
local indPreviews = {}   -- key -> frame (created lazily the first time the Indicators page is drawn)

local function styleIndicatorPreview(f, s, kind, size)
    applyAppearance(f, s, size)
    f.icon:SetTexture((GetSpellTexture and GetSpellTexture(133)) or QUESTION)   -- Fireball demo art
    f.key:SetText("S-4")
    f.icon:SetDesaturated(false); f.icon:SetVertexColor(1, 1, 1)                -- reset any prior tint
    f.pip:Hide(); if f.pipBg then f.pipBg:Hide() end
    if f.cd then f.cd:Hide(); f._gcdEnd = nil end
    f:SetScript("OnUpdate", nil)                                                -- clear the GCD loop by default
    if kind == "cast" then
        applyCastIndicator(f, setmetatable({ castIndicator = true }, { __index = s }), 133)  -- 133 = a cast
    elseif kind == "gcd" then
        f.cd:Show(); f.cd:SetSwipeColor(0, 0, 0, s.gcdOpacity or 0.6)
        f:SetScript("OnUpdate", function(self)          -- loop a 1.5s GCD so the sweep is always on show
            if not self:IsVisible() then return end
            if (self._gcdEnd or 0) - GetTime() <= 0 then
                self.cd:SetCooldown(GetTime(), 1.5); self._gcdEnd = GetTime() + 1.5
            end
        end)
    elseif kind == "range" then
        tintIcon(f, s.rangeStyle or "red", s.rangeColor or { 1, 0.25, 0.25 })
    elseif kind == "resource" then
        tintIcon(f, s.resourceStyle or "tint", s.resourceColor or { 0.4, 0.5, 1 })
    end
end

-- Apply every visual setting to the live cue (size follows scale as a SIZE multiplier so the
-- CENTER anchor keeps one fixed pivot), then mirror the look to the preview.
local function applyLayout()
    if not cue then return end
    local s = S()
    scanInterval = s.scanInterval or 0.1
    if syncTicker then syncTicker() end   -- start/stop/retime the poll to match combat + interval
    applyAppearance(cue, s, (s.iconSize or 48) * (s.scale or 1))
    if cue._glow then cue._glow:SetTexture(ringPath(s.shape or "square", math.max(3, s.borderSize or 3))) end
    applyCastIndicator(cue, s, cue._lastSpell)   -- re-tint after a settings change
    applyGCD(cue, s)
    applyIconState(cue, s, cue._lastSpell)

    local pos = s.pos or DEFAULT_POS
    cue:ClearAllPoints()
    cue:SetPoint("CENTER", UIParent, "CENTER", pos.x or 0, pos.y or 0)
    -- The cue is draggable ONLY during placement mode; otherwise it's locked in place.
    cue:SetMovable(placing); cue:EnableMouse(placing)

    updatePreview()
    -- Live-restyle any visible indicator previews (Indicators page) so dropdowns / swatches / sliders
    -- that only call applyLayout still update them immediately.
    for _, ind in ipairs(IND_PREVIEWS) do
        local f = indPreviews[ind.key]
        if f and f:IsVisible() then
            styleIndicatorPreview(f, s, ind.key, math.min((s.iconSize or 48) * (s.scale or 1), 64))
        end
    end
end

-- Hide the cue and make sure any glow is torn down with it.
local function hideCue()
    if not cue then return end
    setGlow(false)
    cue:Hide()
end

----------------------------------------------------------------------
-- Placement mode: hide the manager, unlock + show a demo cue for dragging, show a small Done bar,
-- then restore lock / test state and reopen the manager.
----------------------------------------------------------------------
local placementBar

-- The suite's selected theme (from the manager's appearance page), so our chrome matches it.
-- Falls back to our own theme if the suite hasn't exposed one.
local function uiTheme()
    local s = _G.TAP
    return (s and s.uiTheme) or theme
end

-- When the global UI font is (re)applied - on login once TTFs index, or when the user changes it -
-- re-lay the on-screen cue so its text picks up the corrected font instead of a first-launch fallback.
theme._onFont = function() pcall(applyLayout) end

-- End placement: lock the cue again, drop test mode, hide the cue, reopen the manager. Runs from
-- the bar's OnHide, so Done, Escape, or any other hide all cleanly return you to the UI.
local function finalizePlacement()
    if not placing then return end
    placing = false
    testMode = false
    applyLayout()   -- placing=false -> cue re-locked
    hideCue()
    local w = placementBar and placementBar._win
    if w then w:Open(placementBar._view or "overview") end
end

local function buildPlacementBar()
    local t = uiTheme()
    local f = CreateFrame("Frame", "TAP_RotationAssistantPlacementBar", UIParent)
    f:SetSize(400, 62)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = t:Heading(f, { text = "Placement mode", role = "h5" }); f.title:SetPoint("TOPLEFT", 16, -11)
    f.sub = t:Heading(f, { text = "Drag the cue where you want it.", role = "caption" }); f.sub:SetPoint("TOPLEFT", 16, -31)
    f.done = t:Button(f); f.done:Configure("Done", 96, 28, "primary", function() f:Hide() end); f.done:SetPoint("RIGHT", -14, 0)
    f:SetScript("OnHide", finalizePlacement)   -- Done / Escape / any hide -> restore + reopen
    tinsert(UISpecialFrames, f:GetName())      -- Escape closes it
    f:Hide()
    placementBar = f
    return f
end

local function startPlacement(win)
    buildCue()
    if not placementBar then buildPlacementBar() end
    -- Re-apply the suite theme in case the appearance changed since the bar was built (guarded so
    -- a theming hiccup can never leave the UI hidden with no way back).
    pcall(function()
        local t = uiTheme()
        t:StylePanel(placementBar, t.C.panel, t.C.accent)
        if placementBar.title then placementBar.title:SetTextColor(unpack(t.C.text)) end
        if placementBar.sub then placementBar.sub:SetTextColor(unpack(t.C.subtext)) end
        if placementBar.done then placementBar.done:Retheme() end
    end)

    placementBar._win = win
    placementBar._view = (win and win.view) or "overview"
    placementBar:ClearAllPoints(); placementBar:SetPoint("TOP", 0, -140)   -- always back on-screen

    placing = true
    testMode = true
    if win then win:Hide() end
    applyLayout()           -- placing=true -> cue draggable
    refresh()               -- show the cue (real next-cast, or demo) for dragging
    placementBar:Show()
end

-- Is this spell currently proc-glowing on the bars? Prefer the event-tracked set (authoritative
-- and API-independent); fall back to IsSpellOverlayed where it exists.
local function spellHasGlow(spellID)
    if glowing[spellID] then return true end
    if IsOverlayed then
        local ok, res = pcall(IsOverlayed, spellID)
        if ok and res then return true end
    end
    return false
end

----------------------------------------------------------------------
-- The display pass.
----------------------------------------------------------------------
local function showSpell(spellID, keyText, forceGlow)
    local wantGlow = (S().showGlow and (forceGlow or spellHasGlow(spellID))) and true or false
    -- Steady-state fast path: if nothing the cue draws (icon spell, key text, glow, visibility)
    -- has changed since the last pass, skip the texture / string / glow work entirely. Compares
    -- against the live glow state (cue._glowOn) so an external setGlow() still forces a redraw.
    if spellID == cue._lastSpell and keyText == cue._lastKey
        and wantGlow == cue._glowOn and cue:IsShown() then
        return
    end
    cue.icon:SetTexture((GetSpellTexture and GetSpellTexture(spellID)) or QUESTION)
    cue.key:SetText(keyText or "?")
    setGlow(wantGlow)
    applyCastIndicator(cue, S(), spellID)
    cue:Show()
    cue._lastSpell, cue._lastKey = spellID, keyText
end

-- Visibility gate: does the player's current spec match the (optional) class/spec filter?
-- No specs selected = show for all classes/specs.
local function specAllowed()
    local specs = S().specs
    if not specs or not next(specs) then return true end
    local idx = GetSpecialization and GetSpecialization()
    local specID = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
    if not specID then return true end   -- unknown (e.g. no spec chosen yet) -> don't hide
    return specs[specID] and true or false
end

-- (assigns the forward-declared `refresh` local so placement helpers above can call it)
function refresh()
    if not cue then return end
    diagRefreshes = diagRefreshes + 1
    -- Self-cancel: if we no longer need to poll, kill the ticker now (safe from its own callback).
    if ticker and not needsPoll() then stopTicker() end
    local s = S()

    updatePreviewSpell()   -- keep the settings-window preview tracking the live rotation

    -- Test / placement mode: show the REAL next-cast if there is one, else a demo, so what you
    -- position is what you'll actually see.
    if testMode then
        local id
        if GetNext then local ok, sid = pcall(GetNext, false); if ok and sid and TAP.CanRead(sid) then id = sid end end
        applyGCD(cue, s); applyIconState(cue, s, id or 133)
        if id then showSpell(id, keybindForSpell(id)) else showSpell(133, "S-4") end
        return
    end

    if not GetNext then hideCue(); return end
    if not specAllowed() then hideCue(); return end        -- wrong class/spec -> don't load here
    if s.onlyInCombat and not inCombat then hideCue(); return end

    local ok, spellID = pcall(GetNext, s.visibleOnly and true or false)
    if not ok or spellID == nil or not TAP.CanRead(spellID) then
        hideCue()   -- no suggestion right now
        return
    end

    applyGCD(cue, s)
    applyIconState(cue, s, spellID)
    showSpell(spellID, keybindForSpell(spellID))
end

----------------------------------------------------------------------
-- Event / update driver.
----------------------------------------------------------------------
-- The "what's next" poll is a single C_Timer ticker (above), gated to combat. These events only
-- keep the button map / key cache correct and track combat - NONE of them poll.
--   MAP  : the slot->button map actually changes -> rebuild it (rare). Rebuilding also wipes keys.
--   KEY  : a spell may have moved slots or bindings changed -> just wipe the key cache. This is the
--          FREQUENT one (ACTIONBAR_SLOT_CHANGED floods on load and in combat), so it must be cheap -
--          rebuilding the whole map here was the CPU cost.
local MAP_EVENTS    = { "ACTIONBAR_PAGE_CHANGED", "PLAYER_ENTERING_WORLD" }
local KEY_EVENTS    = { "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS" }
local GLOW_EVENTS   = { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }
local COMBAT_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                        "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }

local function buildDriver()
    if driver then return driver end
    local d = CreateFrame("Frame")
    d:SetScript("OnEvent", function(_, event, arg1)
        diagEvents = diagEvents + 1
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then glowing[arg1] = true; return end
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then glowing[arg1] = nil; return end
        if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_BINDINGS" then wipe(keyCache); return end
        if event == "ACTIONBAR_PAGE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then rebuildSlotMap(); return end
        -- Combat / spec transition (rare): update the combat flag, start/stop the poll, reflect it.
        if event == "PLAYER_REGEN_DISABLED" then inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false end
        syncTicker()
        refresh()
    end)
    driver = d
    return d
end

----------------------------------------------------------------------
-- Suite module: enable / disable / settings.
----------------------------------------------------------------------
local function OnEnable(m)
    mod = m
    seedDefaults()
    buildCue()
    buildDriver()
    rebuildSlotMap()
    inCombat = InCombatLockdown() and true or false
    applyLayout()
    for _, e in ipairs(MAP_EVENTS) do driver:RegisterEvent(e) end
    for _, e in ipairs(KEY_EVENTS) do driver:RegisterEvent(e) end
    for _, e in ipairs(GLOW_EVENTS) do driver:RegisterEvent(e) end
    for _, e in ipairs(COMBAT_EVENTS) do driver:RegisterEvent(e) end
    syncTicker()   -- start the poll only if we're already in combat (else it stays off)
    refresh()
end

local function OnDisable(m)
    testMode = false; placing = false
    if driver then driver:UnregisterAllEvents() end
    stopTicker()
    hideCue()
end

-- Inline settings, rendered into the Suite Manager's builder. Returns the new y.
-- `win` (the manager window) lets us re-render when a control changes what's shown (e.g.
-- picking the Custom text position reveals the X / Y sliders).
-- Renders ONE of the module's pages (its tabs now live in the sidebar as sub-rows). Keeps all the
-- per-tab render closures; only the top-nav dispatch is replaced by a pageId dispatch.
local function RenderPage(pageId, m, b, x, y, w, win)
    local C = b.theme.C
    local s = m:GetSettings()
    local function repage() if win then win:Refresh() end end

    local anchorChoices = {}
    for _, a in ipairs(TEXT_ANCHOR_ORDER) do anchorChoices[#anchorChoices + 1] = { a, ANCHOR_LABELS[a] or a } end

    -- A column "pen": label-left controls that fill their column's width (with tooltips), so the
    -- same code lays out cleanly whether a section is full-width or a responsive grid column.
    local function pen(cx, cw, cy)
        local P = { x = cx, w = cw, y = cy }
        -- Draw the row label and return where the control should start / how wide it can be. The
        -- control never starts before the label ends (+gap), so long labels (e.g. "Scan interval")
        -- can't collide with the control.
        function P:_ctl(label, dy)
            local lbl = b:Label(label, self.x, self.y + (dy or -2), C.subtext)
            local ctlX = math.max(self.x + 72, self.x + (lbl:GetStringWidth() or 0) + 12)
            return ctlX, math.max(60, self.x + self.w - ctlX - 2)
        end
        function P:sub(t) b:Sub(t, self.x, self.y, self.w - 8); self.y = self.y - 26 end
        function P:note(t) local _, h = b:Wrap(t, self.x, self.y, self.w - 2, C.subtext, 10); self.y = self.y - (h + 8) end
        -- tipTitle defaults to the label; onChange (optional) replaces the default apply+refresh (used
        -- by toggles that reveal sub-controls and want a full page rebuild).
        function P:toggle(label, key, invert, tip, tipTitle, onChange)
            local val = s[key]; if invert then val = not val end
            local tg = b:Toggle(self.x, self.y, val and true or false, function(v)
                s[key] = invert and (not v) or v
                if onChange then onChange() else applyLayout(); refresh() end
            end)
            b.theme:SetTip(tg, tipTitle or label, tip)
            b:Label(label, self.x + 46, self.y - 2, C.text)
            self.y = self.y - 30
        end
        function P:slider(label, key, minv, maxv, step, fmt, tip)
            self.y = self.y - 16   -- headroom so the value readout above the thumb can't clip the row above
            local ctlX, ctlW = self:_ctl(label)
            local sl = b:Slider(ctlX, self.y)
            sl:Configure(ctlW, minv, maxv, step, function() return s[key] or minv end, function(v) s[key] = v; applyLayout() end, fmt)
            b.theme:SetTip(sl, label, tip)
            self.y = self.y - 24
        end
        function P:dropdown(label, choices, getter, setter, tip)
            local ctlX, ctlW = self:_ctl(label)
            local dd = b:Dropdown(ctlX, self.y); dd:SetChoices(ctlW, choices, getter, setter)
            b.theme:SetTip(dd, label, tip)
            self.y = self.y - 30
        end
        function P:swatch(label, tbl, tip)
            local ctlX = self:_ctl(label)
            b:Swatch(ctlX, self.y - 2, tbl, function() applyLayout() end, label, tip)   -- (title, body)
            self.y = self.y - 30
        end
        function P:fontsel(label, key)
            local ctlX, ctlW = self:_ctl(label)
            b:FontSelect(ctlX, self.y, { width = ctlW, value = s[key] or "UBUNTU",
                onChange = function(v) s[key] = v; applyLayout() end })
            self.y = self.y - 30
        end
        return P
    end

    -- Sections as grid cells: fn(cellX, cellWidth, cellTopY) -> ending y.
    local function behaviorCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("BEHAVIOR")
        P:toggle("Only on a visible button", "visibleOnly", false,
            "Only suggest an ability that's on a currently-visible action button.")
        local tg = b:Toggle(P.x, P.y, s.showGlow ~= false, function(v) s.showGlow = v; refresh() end)
        b.theme:SetTip(tg, "Proc glow", "Light up the cue when the suggested ability is proc-highlighted (spell activation overlay) on your bars.")
        b:Label("Proc glow", P.x + 46, P.y - 2, C.text)
        P.y = P.y - 30   -- (hand-rolled: default-on via showGlow ~= false, and refresh-only on toggle)
        P:note("The cue is only draggable in Placement mode - use Set Placement below to move it.")
        return P.y
    end
    local function visibilityCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("VISIBILITY")
        P:toggle("Only show in combat", "onlyInCombat", false, "Hide the cue unless you're in combat.")
        b:Label("Class / Spec", P.x, P.y - 2, C.subtext); P.y = P.y - 18
        local csb = b:ClassSpecButton(P.x, P.y, { selected = s.specs, width = math.min(P.w - 2, 220),
            title = "Show Rotation Cue for these specs", hint = "none checked = every class / spec",
            onChange = function() refresh() end })
        b.theme:SetTip(csb, "Class / Spec", "Limit the cue to specific classes/specs. None selected = shows for every spec.")
        P.y = P.y - 32
        P:note("None checked = every class / spec.")
        return P.y
    end
    -- Cast/instant indicator: color the cue by whether the next ability is a hard cast or instant.
    local function castCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("CAST INDICATOR")
        P:toggle("Show cast vs instant", "castIndicator", false,
            "Color the cue by whether Blizzard's next suggested ability is a hard cast or instant.",
            "Cast / instant indicator", function() applyLayout(); repage() end)
        if s.castIndicator then
            P:dropdown("Style", { { "border", "Tint the border" }, { "dot", "Corner dot" } },
                function() return s.castStyle or "border" end, function(v) s.castStyle = v; applyLayout() end,
                "Show it by recoloring the border ring, or with a dot in the corner.")
            P:swatch("Cast", s.castColor, "Color used when the next ability has a cast time.")
            P:swatch("Instant", s.instantColor, "Color used when the next ability is instant.")
        end
        return P.y
    end
    -- GCD wiper: a radial sweep over the icon that empties with your global cooldown.
    local function gcdCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("GLOBAL COOLDOWN")
        P:toggle("Show GCD sweep", "showGCD", false,
            "Draw a radial sweep on the icon that wipes with your global cooldown.",
            "GCD sweep", function() applyLayout(); repage() end)
        if s.showGCD then
            P:slider("Sweep opacity", "gcdOpacity", 0, 1, 0.05, "%.2f", "Darkness of the GCD sweep over the icon.")
        end
        return P.y
    end
    -- Out-of-range: desaturate or red-tint the icon when the suggestion can't reach your target.
    local function rangeCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("RANGE")
        P:toggle("Show out of range", "rangeCheck", false,
            "Grey out or red-tint the icon when the suggested ability is out of range of your target.",
            "Out-of-range feedback", function() applyLayout(); repage() end)
        if s.rangeCheck then
            P:dropdown("Style", { { "red", "Red tint" }, { "grey", "Desaturate (grey)" } },
                function() return s.rangeStyle or "red" end, function(v) s.rangeStyle = v; applyLayout() end,
                "How to show out-of-range: tint the icon red, or grey it out.")
            if (s.rangeStyle or "red") == "red" then
                P:swatch("Tint", s.rangeColor, "Color applied to the icon when out of range.")
            end
        end
        return P.y
    end
    -- Out-of-resource: tint / grey the icon when you can't afford the suggested ability.
    local function resourceCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("RESOURCE")
        P:toggle("Show can't afford", "resourceCheck", false,
            "Tint or grey the icon when you can't afford the suggested ability (not enough mana / energy / rage / combo points / ...).",
            "Out-of-resource feedback", function() applyLayout(); repage() end)
        if s.resourceCheck then
            P:dropdown("Style", { { "tint", "Color tint" }, { "grey", "Desaturate (grey)" } },
                function() return s.resourceStyle or "tint" end, function(v) s.resourceStyle = v; applyLayout() end,
                "How to show it: tint the icon a color, or grey it out.")
            if (s.resourceStyle or "tint") == "tint" then
                P:swatch("Tint", s.resourceColor, "Color applied to the icon when you can't afford it.")
            end
        end
        return P.y
    end
    local function iconCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("ICON")
        P:dropdown("Shape", { { "square", "Square" }, { "rounded", "Rounded" }, { "circle", "Circle" }, { "hexagon", "Hexagon" } },
            function() return s.shape or "square" end, function(v) s.shape = v; applyLayout() end,
            "Shape of the frame around the icon.")
        P:slider("Size", "iconSize", 24, 96, 2, "%d", "Base icon size, in pixels.")
        P:slider("Zoom", "iconZoom", 0.75, 1.5, 0.05, "%.2f", "Zoom / crop the icon art inside the frame.")
        P:slider("Scale", "scale", 0.5, 2.5, 0.05, "%.2f", "Overall scale multiplier for the whole cue (grows around its centre).")
        P:slider("Opacity", "iconOpacity", 0, 1, 0.05, "%.2f", "Transparency of the icon (fade it to see the world through it).")
        P:slider("Overall", "opacity", 0, 1, 0.05, "%.2f", "Transparency of the entire cue.")
        return P.y
    end
    local function borderCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("BORDER")
        P:slider("Thickness", "borderSize", 0, 10, 1, "%d", "Border ring thickness. 0 = no border.")
        P:swatch("Color", s.borderColor, "Border ring color.")
        P:slider("Opacity", "borderOpacity", 0, 1, 0.05, "%.2f", "Transparency of the border ring.")
        return P.y
    end
    local function keybindCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("KEYBIND TEXT")
        P:dropdown("Position", anchorChoices, function() return s.textAnchor or "BOTTOM" end,
            function(v) s.textAnchor = v; applyLayout(); repage() end,
            "Where the keybind text sits relative to the icon. Pick Custom for X/Y offsets.")
        if (s.textAnchor or "BOTTOM") == "custom" then
            P:slider("X offset", "textX", -150, 150, 1, "%d", "Horizontal offset of the keybind text.")
            P:slider("Y offset", "textY", -150, 150, 1, "%d", "Vertical offset of the keybind text.")
        end
        P:fontsel("Font", "keyFont")
        P:slider("Size", "keySize", 8, 48, 1, "%d", "Keybind text size.")
        P:swatch("Color", s.keyColor, "Keybind text color.")
        P:slider("Opacity", "textOpacity", 0, 1, 0.05, "%.2f", "Transparency of the keybind text.")
        return P.y
    end
    -- Live preview cell: a real cue showing your ACTUAL next-cast, mirroring the settings live.
    local function previewCell(cx, cw, cy)
        local P = pen(cx, cw, cy)
        P:sub("PREVIEW")
        local boxTop, boxH = P.y, 190
        b:Box(cx, boxTop, cw, boxH, 0.12, 0, C.card)
        preview:SetParent(b.content)
        b:Transient(preview)                 -- hide it when the page/view changes
        preview:ClearAllPoints()
        preview:SetPoint("CENTER", b.content, "TOPLEFT", cx + cw / 2, boxTop - boxH / 2)
        preview:Show()
        updatePreview()
        b:Label("live - your next-cast, at your settings", cx, boxTop - boxH - 2, C.subtext, 10)
        return boxTop - boxH - 16
    end

    -- Preview frame created once; the PREVIEW grid cell (row 2 / column 2) positions it next to
    -- the appearance controls so it updates live as you drag the sliders.
    if not preview then preview = buildCueFrame(b.content) end

    -- Behavior page: Behavior + Visibility cells, then the full-width Performance / Minimap / actions.
    local function renderBehavior(cy)
        cy = b:Grid(x, cy, { behaviorCell, visibilityCell }, { columns = 2, gap = 24, width = w, minColWidth = 240 })
        cy = cy - 8

        -- Performance (full width)
        local P = pen(x, w, cy)
        P:sub("PERFORMANCE")
        P:slider("Scan interval", "scanInterval", 0.05, 1.0, 0.05, "%.2f",
            "How often the cue re-checks your next ability, in seconds. Higher = less CPU, a touch less "
            .. "responsive. A single lightweight timer - combat start/end and spec changes still update instantly.")
        P:note("The suggestion refreshes on this timer (higher = less CPU). Combat start/end, spec "
            .. "changes and procs update immediately via events.")
        cy = P.y - 4

        -- Actions
        b:Button(x, cy, 120, testMode and "Stop Test" or "Test On Screen", testMode and "danger" or "default", function()
            testMode = not testMode
            if not testMode then hideCue() end
            refresh()
        end)
        b:Button(x + 128, cy, 130, "Set Placement", "primary", function() startPlacement(win) end)
        b:Button(x + 266, cy, 130, "Reset Position", "default", function()
            s.pos = { x = DEFAULT_POS.x, y = DEFAULT_POS.y }
            applyLayout(); refresh()
        end)
        cy = cy - 34

        if not GetNext then
            b:Label("|cffffaa00Note:|r C_AssistedCombat.GetNextCastSpell isn't available on this client.", x, cy, C.subtext, 10)
            cy = cy - 16
        end

        -- Compatibility note (bottom of the Behavior tab) - accent + outlined so it pops, matching
        -- the What's New callout.
        cy = cy - 6
        local nfs, nh = b:Wrap("Note: the cue reads keybinds from Action Bars 1-5 only - the bars listed "
            .. "under Action Bars in the keybinding editor. Keys bound solely on third-party action-bar "
            .. "addons may not be picked up.", x, cy, w - 2, C.accent, 10)
        nfs:SetFont(b.theme.FONT, 10, "OUTLINE")
        cy = cy - (nh + 8)
        return cy
    end
    -- Preview strip: the four indicators laid 4-across, each a demo cue styled from the Appearance
    -- settings and forced to show its own effect - a live "what it'll look like" for the toggles above.
    local function renderIndicatorPreviews(cy)
        b:Sub("PREVIEW", x, cy, w); cy = cy - 26
        local boxTop, boxH = cy, 150
        b:Box(x, boxTop, w, boxH, 0.12, 0, C.card)
        local size = math.min((s.iconSize or 48) * (s.scale or 1), 64)   -- capped so four fit comfortably
        local colW = w / #IND_PREVIEWS
        for i, ind in ipairs(IND_PREVIEWS) do
            local f = indPreviews[ind.key]
            if not f then f = buildCueFrame(b.content); indPreviews[ind.key] = f end
            f:SetParent(b.content); b:Transient(f)
            local ccx = x + (i - 0.5) * colW
            f:ClearAllPoints(); f:SetPoint("CENTER", b.content, "TOPLEFT", ccx, boxTop - 62)
            f:Show()
            styleIndicatorPreview(f, s, ind.key, size)
            local on = s[ind.enabledKey] and true or false
            local lfs = b:Label(ind.label .. (on and "" or "  (off)"), ccx - 60, boxTop - boxH + 26,
                on and C.text or C.subtext, 11)
            lfs:SetWidth(120); lfs:SetJustifyH("CENTER")
        end
        b:Label("Shown with your Appearance settings.", x, boxTop - boxH - 2, C.subtext, 10)
        return boxTop - boxH - 16
    end
    local function renderIndicators(cy)
        cy = b:Grid(x, cy, { castCell, gcdCell, rangeCell, resourceCell }, { columns = 2, gap = 24, width = w, minColWidth = 240 })
        return renderIndicatorPreviews(cy - 8) - 8
    end
    local function renderAppearance(cy)
        cy = b:Grid(x, cy, { iconCell, borderCell, keybindCell, previewCell }, { columns = 2, gap = 22, width = w, minColWidth = 240 })
        return cy - 8
    end
    -- SETTINGS page: the master enable/disable and the minimap button (moved here from Behavior).
    local function renderSettings(cy)
        -- (enable/disable lives on the Platform Overview page, not repeated here)
        if Suite and Suite.IsMinimapButtonShown then
            b:Sub("MINIMAP", x, cy, w); cy = cy - 30
            local tg = b:Toggle(x, cy, Suite:IsMinimapButtonShown("rotationCue"),
                function(v) Suite:SetMinimapButtonShown("rotationCue", v) end)
            b.theme:SetTip(tg, "Minimap icon", "Show a Rotation Assistant button on the minimap (left-click opens this page).")
            b:Label("Show a minimap button", x + 46, cy - 2, C.text)
            b:Label("Left-click it to open this page.", x + 46, cy - 20, C.subtext, 10)
            cy = cy - 42
        end
        return cy
    end

    -- Top-level nav now lives in the sidebar (one row per page). Disabled: overlay every page except
    -- Settings (where the enable toggle lives), so the module can always be switched back on.
    if m and m.IsEnabled and not m:IsEnabled() and pageId ~= "settings" then
        return b:DisabledOverlay(x, y, w, { subtitle = "Enable Rotation Assistant from the Platform Overview.",
            onSettings = function() if win then win:SelectView("overview") end end })
    end

    -- Standard page heading (matches the platform + other modules).
    local HEAD = {
        behavior   = { "Behavior",   "How the on-screen keybind cue behaves - what it reads, when it shows, and its checks." },
        indicators = { "Indicators", "Optional cast, GCD, range, and resource indicators around the cue." },
        appearance = { "Appearance", "Size, position, colors, and keybind text of the on-screen cue." },
        settings   = { "Settings",   "Master options for Rotation Assistant and its minimap button." },
    }
    if HEAD[pageId] then y = b:PageHeading(x, y, HEAD[pageId][1], HEAD[pageId][2]) end

    if pageId == "indicators" then
        y = renderIndicators(y)
    elseif pageId == "appearance" then
        y = renderAppearance(y)
    elseif pageId == "settings" then
        y = renderSettings(y)
    else
        y = renderBehavior(y)
    end
    return y
end

-- Page render closures for the sidebar (each delegates to RenderPage with its page id).
local function rotationPages()
    local function pg(id) return function(m, b, x, y, w, win) return RenderPage(id, m, b, x, y, w, win) end end
    return {
        { id = "behavior",   label = "Behavior",   icon = "adjustments-horizontal", default = true, disabledSafe = true, render = pg("behavior") },
        { id = "indicators", label = "Indicators", icon = "activity", disabledSafe = true, render = pg("indicators") },
        { id = "appearance", label = "Appearance", icon = "palette",  disabledSafe = true, render = pg("appearance") },
        { id = "settings",   label = "Settings",   icon = "settings", disabledSafe = true, render = pg("settings") },
    }
end

----------------------------------------------------------------------
-- Register with the suite. Everything above stays dormant until the module is enabled.
----------------------------------------------------------------------
local CHANGELOG = [==[
# Rotation Assistant - What's New

## 1.0.1

- **[CHANGE]** Spell cooldown, cast, and icon lookups now use the current **C_Spell** API directly; the legacy global fallbacks were removed. No functional change.

## 1.0.0

- **[CHANGE]** Out of beta - Rotation Assistant is now a stable 1.0 release.
- **[NOTE]** The on-screen cue reads keybinds from **Action Bars 1-5** only - the bars listed under
  Action Bars in the keybinding editor. Keys bound solely on third-party action-bar addons may not
  be picked up.

## 1.0.0-beta.3

- **[CHANGE]** **Tabbed layout.** The page is now split into tabs - **Behavior**, **Indicators**,
  **Appearance**, and **Settings** - docked under the title bar, instead of one long scrolling page.
  Everything's in the same place, just quicker to get to.
- **[BUG FIX]** Picks up the latest shared appearance fixes - custom theme colors now save correctly
  from the color picker, and the **Menu scale** slider is smoother to drag.

## 1.0.0-beta.2

- **[NEW]** Slash commands: **/tap rotation** jumps straight to this page, and **/rcue** runs the
  diagnostics (run it twice, ~10s apart, to check the cue is reading Blizzard's suggestions).
- **[CHANGE]** The on-screen cue now follows your chosen **Platform font** automatically.
- **[NEW]** Fresh platform look in Settings: pick a **shape** and a **color scheme** (neutrals,
  light themes, or a WoW-expansion palette) or full custom colors, and scale the menu with
  **Menu scale**.

## 1.1.0 (standalone, pre-platform)

- **[NEW]** Cast vs instant indicator - a colored corner dot (or border tint) tells you whether
  your next suggested ability is a hard cast or an instant.
- **[NEW]** Global-cooldown sweep - an optional radial "wipe" on the icon that empties with your
  GCD, shaped to match your icon.
- **[NEW]** Out-of-range warning - grey out or red-tint the icon when the suggestion can't reach
  your target.
- **[NEW]** Can't-afford warning - tint the icon when you're short on resource (mana, energy,
  rage, combo points, and so on).

## 1.0.0 (standalone, pre-platform)

- **[NEW]** First release. Shows the keybind of Blizzard's suggested next ability on screen - it
  only shows the key, it never presses anything for you.
- **[NEW]** Make it yours: icon shape (square, rounded, circle, hexagon), size, zoom, border, and
  where the keybind text sits.
- **[NEW]** Optional proc glow when the suggested ability is lit up on your action bars.
- **[NEW]** A live preview and a Set Placement button so you can drag the cue exactly where you
  want it.
]==]

Suite:RegisterModule({
    id      = "rotationCue",
    title   = "Rotation Assistant",
    desc    = "Reads Blizzard's one-button assistant and shows the KEYBIND of the next "
           .. "suggested ability on screen. Show-only - never presses anything.",
    icon    = "keyboard",
    addon   = "TAP_RotationAssistant",
    default = true,
    group   = "Rotation Assistant",   -- single-module addon: its own sidebar category
    groupColor = "4fd18b",            -- signature tint for this add-on's sidebar category
    rendersWhenDisabled = true,   -- keep our pages (and the Settings page) reachable while disabled
    changelog = CHANGELOG,
    OnEnable  = OnEnable,
    OnDisable = OnDisable,
    pages     = rotationPages(),
})

-- Optional minimap icon for this module (hidden by default; toggled in this module's settings).
if Suite.RegisterMinimapButton then
    Suite:RegisterMinimapButton("rotationCue", {
        icon = "Interface\\AddOns\\TAP_RotationAssistant\\assets\\images\\tap_rotation_assistant_icon.tga",
        title = "|cffa06cf0Rotation Assistant|r", action = "open the settings",
        onClick = function() Suite:OpenWindow("mod:rotationCue") end,
        defaultHidden = true,
    })
end

-- List this module's commands on the Manager's Help > Commands page. /tap rotation opens the
-- module page; /rcue (registered below) stays the native diagnostics command.
if Suite and Suite.RegisterCommand then
    Suite:RegisterCommand({
        cmd = "/tap rotation", desc = "Open the Rotation Assistant page", owner = "Rotation Assistant",
        sub = "rotation", handler = function() if Suite.OpenWindow then Suite:OpenWindow("mod:rotationCue") end end,
    })
    Suite:RegisterCommand({
        cmd = "/rcue", desc = "Rotation Assistant diagnostics (run twice, ~10s apart)",
        owner = "Rotation Assistant",
    })
end

----------------------------------------------------------------------
-- /rcue - diagnostics. Prints the whole pipeline (API availability, mapped buttons, the
-- current suggestion, its slots, and the resolved key) so a "?" is easy to trace.
----------------------------------------------------------------------
SLASH_TWROTCUE1 = "/rcue"
SlashCmdList["TWROTCUE"] = function()
    local function p(str) print("|cffa06cf0RotationCue|r " .. str) end
    -- CPU / activity diagnostics: run /rcue, wait ~10s, run /rcue again. The refresh/event
    -- counts should barely move out of combat. If refreshes climb while you're NOT in combat,
    -- something is still polling.
    p(("POLL: ticker=%s  interval=%.2fs  onlyInCombat=%s  inCombat=%s(api %s)  needsPoll=%s"):format(
        ticker and "|cffff5555RUNNING|r" or "stopped", scanInterval,
        S().onlyInCombat and "yes" or "no", inCombat and "yes" or "no",
        InCombatLockdown() and "yes" or "no", needsPoll() and "yes" or "no"))
    p(("ACTIVITY since load: refreshes=%d  events=%d  (glow=%s, anim=%s)"):format(
        diagRefreshes, diagEvents, S().showGlow and "on" or "off",
        (cue and cue._glow and cue._glow._ag and cue._glow._ag:IsPlaying()) and "|cffff5555PLAYING|r" or "stopped"))
    p(("API: GetNextCastSpell=%s  FindSpellActionButtons=%s"):format(GetNext and "yes" or "NO", FindSlots and "yes" or "NO"))
    local labs = {}
    if _G.LibStub and _G.LibStub.libs then
        for name, lib in pairs(_G.LibStub.libs) do
            if type(name) == "string" and name:find("LibActionButton") and type(lib) == "table" and lib.GetAllButtons then
                local ok, buttons = pcall(lib.GetAllButtons, lib)
                local c = 0; if ok and type(buttons) == "table" then for _ in pairs(buttons) do c = c + 1 end end
                labs[#labs + 1] = ("%s(%d)"):format(name, c)
            end
        end
    end
    p("LibActionButton engines: " .. (#labs > 0 and table.concat(labs, ", ") or "none (Blizzard/EllesmereUI bars)"))
    rebuildSlotMap()
    local n = 0; for _ in pairs(slotToButton) do n = n + 1 end
    p("action slots mapped: " .. n)
    if not GetNext then return end
    local ok, id = pcall(GetNext, false)
    if not ok then p("GetNextCastSpell error: " .. tostring(id)); return end
    if id == nil then p("no suggestion right now (are you in/near combat with a target?)"); return end
    if not TAP.CanRead(id) then p("suggestion is a secret value right now"); return end
    p("next spell: " .. tostring(id))
    local ms = spellCastMS(id)
    p(("cast time: %s ms -> %s   (C_Spell.GetSpellInfo=%s)"):format(
        tostring(ms), (ms and ms > 0) and "|cffffd166CAST|r" or "|cff5ad8ffINSTANT|r",
        GetSpellInfoT and "yes" or "NO"))
    local rng = spellInRange(id)
    p(("in range: %s   affordable: %s"):format(
        rng == nil and "n/a (no target)" or (rng and "|cff77dd77yes|r" or "|cffff6666NO|r"),
        spellAffordable(id) and "|cff77dd77yes|r" or "|cffff6666NO (out of resource)|r"))
    if not FindSlots then return end
    local slots = FindSlots(id)
    if type(slots) ~= "table" then p("FindSpellActionButtons -> " .. tostring(slots)); return end
    if #slots == 0 then p("|cffff6666that spell is not on any action bar slot|r"); return end
    for _, slot in ipairs(slots) do
        if not TAP.CanRead(slot) then
            p("  slot <secret>")
        else
            local btn = slotToButton[slot]
            p(("  slot %s -> %s  btnKey=%s  slotKey=%s (%s)"):format(tostring(slot),
                btn and (btn:GetName() or "unnamed") or "|cffff6666NO BUTTON MAPPED|r",
                tostring(btn and keyForButton(btn)), tostring(keyForSlot(slot)),
                tostring(commandForSlot(slot) or "no std binding")))
        end
    end
    p("resolved keybind: " .. tostring(keybindForSpell(id)))
end
