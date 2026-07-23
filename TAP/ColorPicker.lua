-- TAP - ColorPicker.lua
-- A self-skinned color picker: live preview + hex box + RGB sliders + a preset grid.
-- Each theme builds one draggable, Escape-closable picker on demand.
--
--   theme:OpenColorPicker(r, g, b, function(r, g, b) ... end)   -- callback fires live

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

-- Bootstrap-ish preset palette (8 columns).
local PRESETS = {
    "0D6EFD", "0A58CA", "0B5ED7", "6610F2", "6F42C1", "D63384", "DC3545", "E35D6A",
    "FD7E14", "FFC107", "FFDA6A", "198754", "20C997", "0DCAF0", "3DD5F3", "FFFFFF",
    "CED4DA", "ADB5BD", "6C757D", "343A40", "000000", "FF0000", "00FF00", "00A2FF",
}

local function ensurePicker(theme)
    if theme._cpick then return theme._cpick end
    local C = theme.C
    local name = TAP.NextId(theme.id .. "ColorPicker")
    local p = CreateFrame("Frame", name, UIParent)
    theme._cpick = p
    p:SetSize(260, 340); p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
    theme:StylePanel(p, C.panel, C.border)
    p:EnableMouse(true); p:SetMovable(true)
    tinsert(UISpecialFrames, name)

    local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(26)
    local hbg = hd:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); TAP.paint(hbg, C.card)
    hd:RegisterForDrag("LeftButton")
    hd:SetScript("OnDragStart", function() p:StartMoving() end)
    hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    local t = hd:CreateFontString(nil, "OVERLAY"); t:SetFont(theme.FONT, 12); t:SetPoint("LEFT", 10, 0); t:SetText("Choose a color"); t:SetTextColor(unpack(C.text))
    local xb = theme:Button(p); xb:Configure("X", 22, 20, "danger", function() p:Hide() end); xb:SetPoint("TOPRIGHT", -3, -3); xb:SetFrameLevel(hd:GetFrameLevel() + 5)

    -- Preview + hex
    local prev = CreateFrame("Frame", nil, p); prev:SetSize(46, 46); prev:SetPoint("TOPLEFT", 14, -34); theme:StylePanel(prev, C.bg)
    p.prevTex = prev:CreateTexture(nil, "ARTWORK"); p.prevTex:SetPoint("TOPLEFT", 2, -2); p.prevTex:SetPoint("BOTTOMRIGHT", -2, 2)
    local hexL = p:CreateFontString(nil, "OVERLAY"); hexL:SetFont(theme.FONT, 11); hexL:SetPoint("TOPLEFT", prev, "TOPRIGHT", 12, -2); hexL:SetText("Hex"); hexL:SetTextColor(unpack(C.subtext))
    local hexBox = theme:EditBox(p); hexBox:Configure(120, 22, "", nil); hexBox:ClearAllPoints(); hexBox:SetPoint("TOPLEFT", prev, "TOPRIGHT", 12, -16)
    p.hex = hexBox

    p.cur = { 1, 1, 1 }
    local function emit(src)
        local r, g, b = p.cur[1], p.cur[2], p.cur[3]
        p.prevTex:SetColorTexture(r, g, b)
        p._sync = true
        if src ~= "hex" then p.hex:SetText(TAP.hexOf(r, g, b)) end
        if p.sr and p.sg and p.sb then
            p.sr:SetValue(r * 255); p.sg:SetValue(g * 255); p.sb:SetValue(b * 255)
        end
        p._sync = false
        if p.cb then p.cb(r, g, b) end
    end
    p.emit = emit

    hexBox:SetScript("OnTextChanged", function(self)
        if p._sync then return end
        local r, g, b = TAP.parseHex(self:GetText())
        if r then p.cur[1], p.cur[2], p.cur[3] = r, g, b; emit("hex") end
    end)

    -- RGB sliders
    local sy = -92
    local function mkChannel(label, idx)
        local l = p:CreateFontString(nil, "OVERLAY"); l:SetFont(theme.FONT, 11); l:SetPoint("TOPLEFT", 14, sy); l:SetText(label); l:SetTextColor(unpack(C.subtext))
        local s = theme:Slider(p); s:ClearAllPoints(); s:SetPoint("TOPLEFT", 40, sy - 2)
        s:Configure(190, 0, 255, 1, function() return p.cur[idx] * 255 end, function(v)
            if p._sync then return end
            p.cur[idx] = v / 255; emit("slider")
        end, "%d")
        sy = sy - 34
        return s
    end
    p.sr = mkChannel("R", 1)
    p.sg = mkChannel("G", 2)
    p.sb = mkChannel("B", 3)

    -- Preset grid
    local gx, gy, col = 14, sy - 6, 0
    for _, hex in ipairs(PRESETS) do
        local sw = CreateFrame("Button", nil, p); sw:SetSize(24, 18)
        sw:SetPoint("TOPLEFT", gx + col * 28, gy)
        theme:StylePanel(sw, C.bg)
        local tx = sw:CreateTexture(nil, "ARTWORK"); tx:SetPoint("TOPLEFT", 1, -1); tx:SetPoint("BOTTOMRIGHT", -1, 1)
        local r, g, b = TAP.parseHex(hex); tx:SetColorTexture(r, g, b)
        sw:SetScript("OnClick", function() p.cur[1], p.cur[2], p.cur[3] = r, g, b; emit("preset") end)
        col = col + 1
        if col >= 8 then col = 0; gy = gy - 22 end
    end

    return p
end

-- Open the picker seeded with r,g,b; callback(r,g,b) fires live as the color changes.
function Mixin:OpenColorPicker(r, g, b, callback)
    local p = ensurePicker(self)
    p.cb = callback
    p.cur[1], p.cur[2], p.cur[3] = r or 1, g or 1, b or 1
    p:Show()
    p.emit("open")
end
