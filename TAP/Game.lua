-- TAP - Game.lua
-- Widgets that pull live data from the game client:
--   UnitModel     - a full 3D character model (PlayerModel), drag-to-rotate.
--   GameIcon      - the icon for any spell / buff / debuff / item, with the real game tooltip.
--
-- All guard for API availability, so they degrade to a placeholder icon on odd states.

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin
local QMARK = "Interface\\ICONS\\INV_Misc_QuestionMark"

-- For a truly ANIMATED backdrop, pass background = "model:<fileID or name>" to a 3D model
-- widget: it puts a live, self-animating M2 behind the character. A few verified fileIDs are
-- named below; pass a raw number for any other (find them on wago.tools DB2 "ModelFileData",
-- or in-game). A wrong id just renders empty - it never errors.
--   theme:UnitModel(parent, { unit = "player", background = "model:illidan" })
--   theme:UnitModel(parent, { unit = "player", background = "model:122968" })   -- raw fileID
-- Static scenes accept `animated = true` for a gentle breathing accent glow instead.
TAP.MODEL_BACKDROPS = {
    illidan = 124614,   -- Creature/illidan/illidandark.m2  (verified, WeakAuras default)
    arthas  = 122968,   -- Creature/arthaslichking/arthaslichking.m2  (verified, WeakAuras default)
}

-- Apply a background spec to a texture. spec may be:
--   nil                -> hidden
--   { r,g,b } / "hex"  -> solid color
--   "atlas:AtlasName"  -> a Blizzard atlas
--   "Interface\\..."   -> a texture path
--   "dusk" / a scene   -> a bundled scene backdrop (theme.sceneDir .. name .. ".tga")
local function applyBackground(theme, tex, spec)
    if spec == nil then tex:Hide(); return end
    if type(spec) == "table" then local c = TAP.toColor(spec); tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1); tex:Show(); return end
    if type(spec) == "string" then
        if spec:find("^atlas:") then if tex.SetAtlas then pcall(tex.SetAtlas, tex, spec:sub(7), false) end
        elseif spec:find("\\") then tex:SetTexture(spec)
        elseif TAP.parseHex(spec) then local r, g, b = TAP.parseHex(spec); tex:SetColorTexture(r, g, b)
        else tex:SetTexture((theme.sceneDir or "") .. spec .. ".tga") end   -- scene name
        tex:SetTexCoord(0, 1, 0, 1); tex:Show()
    end
end

----------------------------------------------------------------------
-- Shared 3D model builder used by UnitModel (full body).
----------------------------------------------------------------------
local function makeModel(theme, parent, opts, defZoom, defW, defH)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or opts.size or defW, opts.height or opts.size or defH)
    theme:StylePanel(f, opts.bg and TAP.toColor(opts.bg) or theme.C.bg, TAP.toColor(opts.borderColor, theme.C.accent))
    -- Scene / background behind the 3D model (the character renders on top; the scene shows
    -- around it). Sits above the panel fill, below the model.
    local sceneTex = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    sceneTex:SetPoint("TOPLEFT", 2, -2); sceneTex:SetPoint("BOTTOMRIGHT", -2, 2); sceneTex:Hide()
    f.sceneTex = sceneTex
    -- Animated ambiance overlay: a soft accent glow that breathes (used for animated scenes).
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    glow:SetPoint("TOPLEFT", 2, -2); glow:SetPoint("BOTTOMRIGHT", -2, 2); glow:Hide()
    local gag = glow:CreateAnimationGroup(); gag:SetLooping("REPEAT")
    local ga1 = gag:CreateAnimation("Alpha"); ga1:SetFromAlpha(0.08); ga1:SetToAlpha(0.32); ga1:SetDuration(1.8); ga1:SetOrder(1); ga1:SetSmoothing("IN_OUT")
    local ga2 = gag:CreateAnimation("Alpha"); ga2:SetFromAlpha(0.32); ga2:SetToAlpha(0.08); ga2:SetDuration(1.8); ga2:SetOrder(2); ga2:SetSmoothing("IN_OUT")
    f.sceneGlow, f._glowAnim = glow, gag

    -- PlayerModel is what draws a live unit in 3D. Guard: it can be absent in headless envs.
    local model = CreateFrame("PlayerModel", nil, f)
    model:SetPoint("TOPLEFT", 2, -2); model:SetPoint("BOTTOMRIGHT", -2, 2)
    if model.SetFrameLevel then model:SetFrameLevel((f:GetFrameLevel() or 1) + 3) end
    f.model = model

    -- Lazily-built 3D backdrop model (an animated environment/effect M2 behind the character).
    local function ensureSceneModel()
        if f.sceneModel then return f.sceneModel end
        local sm = CreateFrame("Model", nil, f)
        sm:SetPoint("TOPLEFT", 2, -2); sm:SetPoint("BOTTOMRIGHT", -2, 2)
        if sm.SetFrameLevel then sm:SetFrameLevel((f:GetFrameLevel() or 1) + 1) end   -- below the character
        f.sceneModel = sm
        return sm
    end

    -- spec: any applyBackground spec, OR "model:<fileID|path>" for an animated game-asset
    -- backdrop. `animated` adds the breathing accent glow to a static scene.
    function f:SetBackground(spec, animated)
        if f.sceneModel then f.sceneModel:Hide() end
        if type(spec) == "string" and spec:find("^model:") then
            local sm = ensureSceneModel(); sm:Show()
            local id = spec:sub(7)
            local num = tonumber(id) or TAP.MODEL_BACKDROPS[id]   -- named preset or raw fileID
            if sm.SetModel then pcall(sm.SetModel, sm, num or id) end
            if sm.SetCamera then pcall(sm.SetCamera, sm, 0) end
            self.sceneTex:Hide(); self.sceneGlow:Hide(); self._glowAnim:Stop()
            return
        end
        applyBackground(theme, self.sceneTex, spec)
        if animated and spec ~= nil then
            local a = theme.C.accent; self.sceneGlow:SetColorTexture(a[1], a[2], a[3])
            self.sceneGlow:Show(); if not self._glowAnim:IsPlaying() then self._glowAnim:Play() end
        else
            self.sceneGlow:Hide(); self._glowAnim:Stop()
        end
    end
    if opts.background ~= nil then f:SetBackground(opts.background, opts.animated) end
    f.unit = opts.unit or "player"
    f._facing = opts.facing or 0
    f._zoom = opts.zoom ~= nil and opts.zoom or defZoom

    function f:Refresh()
        local m = self.model
        if m.ClearModel then pcall(m.ClearModel, m) end
        if m.SetUnit then pcall(m.SetUnit, m, self.unit) end
        if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, self._zoom) end
        if m.SetCamDistanceScale and opts.camDistanceScale then pcall(m.SetCamDistanceScale, m, opts.camDistanceScale) end
        if m.SetFacing then pcall(m.SetFacing, m, self._facing) end
        if m.SetAnimation and opts.animation then pcall(m.SetAnimation, m, opts.animation) end
    end
    function f:SetUnit(u) self.unit = u; self:Refresh() end
    function f:SetFacing(v) self._facing = v; if self.model.SetFacing then pcall(self.model.SetFacing, self.model, v) end end
    f:Refresh()
    f:RegisterEvent("UNIT_MODEL_CHANGED"); f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, _, unit) if not unit or unit == self.unit then self:Refresh() end end)

    -- Drag to spin.
    if opts.rotatable ~= false then
        model:EnableMouse(true); model:RegisterForDrag("LeftButton")
        model:SetScript("OnDragStart", function(self)
            local sx = GetCursorPosition()
            self:SetScript("OnUpdate", function()
                local cx = GetCursorPosition()
                f._facing = f._facing + ((cx - sx) * 0.02); sx = cx
                if self.SetFacing then pcall(self.SetFacing, self, f._facing) end
            end)
        end)
        model:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    end
    return f
end

-- Full 3D character model (drag to rotate).
--   theme:UnitModel(parent, { unit = "player", width = 150, height = 220 })
function Mixin:UnitModel(parent, opts)
    return makeModel(self, parent, opts, 0, 150, 220)
end

----------------------------------------------------------------------
-- GameIcon: the icon for any spell / buff / debuff / item, with the real game tooltip.
--   theme:GameIcon(parent, { spell = 133, size = 36 })          -- Fireball
--   theme:GameIcon(parent, { item = 6948 })                     -- Hearthstone
--   theme:GameIcon(parent, { aura = 1459 })                     -- a buff/debuff (spell icon + tip)
--   icon:SetSpell(id) / :SetItem(id) / :SetAura(id)             -- swap live
----------------------------------------------------------------------
local function spellIcon(spell)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell)
    local id = (info and info.spellID) or (type(spell) == "number" and spell) or nil
    local icon = (info and info.iconID) or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell))
    return icon, id
end
local function itemIcon(item)
    local id = (type(item) == "number" and item)
        or (C_Item and C_Item.GetItemInfoInstant and (C_Item.GetItemInfoInstant(item)))
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id or item)
    return icon, id
end

function Mixin:GameIcon(parent, opts)
    opts = opts or {}
    local theme = self
    local size = opts.size or 32
    local b = CreateFrame("Button", nil, parent); b:SetSize(size, size)
    theme:StylePanel(b, theme.C.bg)
    b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1); b.tex:SetTexCoord(unpack(theme.iconInset))
    b._tip = opts.showTooltip ~= false
    b._anchor = opts.tooltipAnchor or "ANCHOR_RIGHT"
    b:SetScript("OnEnter", function(self)
        if not self._tip or not self._id then return end
        GameTooltip:SetOwner(self, self._anchor)
        if self._kind == "item" then if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self._id) end
        else if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self._id) end end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    function b:SetSpell(spell) local ic, id = spellIcon(spell); self._kind, self._id = "spell", id; self.tex:SetTexture(ic or QMARK) end
    function b:SetAura(spell)  self:SetSpell(spell) end   -- buffs/debuffs share the spell icon + tooltip
    function b:SetItem(item)   local ic, id = itemIcon(item); self._kind, self._id = "item", id; self.tex:SetTexture(ic or QMARK) end
    function b:SetIcon(v)      self._id = nil; self.tex:SetTexture(theme:IconPath(v) or v or QMARK) end

    if opts.spell then b:SetSpell(opts.spell)
    elseif opts.aura then b:SetAura(opts.aura)
    elseif opts.item then b:SetItem(opts.item)
    elseif opts.icon then b:SetIcon(opts.icon)
    else b.tex:SetTexture(QMARK) end
    return b
end
