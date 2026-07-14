-- UIFoundry - Progress.lua
-- ProgressBar (determinate or indeterminate) and Spinner. Both are fully styleable.
--
--   local pb = theme:ProgressBar(parent, { width = 300, height = 16, min = 0, max = 100,
--       value = 40, color = "20C997", bg = "1A1D24", showText = true, format = "%d%%" })
--   pb:SetValue(75)
--   pb:SetIndeterminate(true)      -- animated barber-pole sweep
--
--   local sp = theme:Spinner(parent, { size = 24, color = "accent", icon = "...loader-2.tga" })
--   sp:Start();  sp:Stop()

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

function Mixin:ProgressBar(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w, h = opts.width or 240, opts.height or 14
    local f = CreateFrame("Frame", nil, parent); f:SetSize(w, h)
    theme:StylePanel(f, UIF.toColor(opts.bg, C.bg), UIF.toColor(opts.borderColor, C.border))
    theme:StyleFrame(f, opts)

    local fill = f:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMLEFT", 1, 1)
    f.fill = fill
    f.fillColor = UIF.toColor(opts.color, C.accent)
    UIF.paint(fill, f.fillColor)

    local txt = f:CreateFontString(nil, "OVERLAY"); txt:SetPoint("CENTER")
    theme:StyleFont(txt, opts, { fontSize = math.max(9, h - 5), textColor = C.text })
    f.txt = txt; txt:SetShown(opts.showText and true or false)

    f.min, f.max = opts.min or 0, opts.max or 100
    f.format = opts.format or "%d%%"

    function f:_render()
        local range = (self.max - self.min)
        local frac = range > 0 and ((self.value - self.min) / range) or 0
        frac = math.max(0, math.min(1, frac))
        local innerW = (self:GetWidth() - 2)
        self.fill:SetWidth(math.max(0.001, innerW * frac))
        if self.txt:IsShown() then self.txt:SetText(string.format(self.format, self.value)) end
    end
    function f:SetValue(v) self.value = v; self:_render() end
    function f:SetMinMax(mn, mx) self.min, self.max = mn, mx; self:_render() end
    function f:SetBarColor(c) self.fillColor = UIF.toColor(c, self.fillColor); UIF.paint(self.fill, self.fillColor) end

    -- Indeterminate: a moving highlight sweep for "working, unknown duration".
    function f:SetIndeterminate(on)
        if on then
            self.fill:SetWidth(math.max(2, self:GetWidth() * 0.30))
            if not self._anim then
                local ag = self.fill:CreateAnimationGroup(); ag:SetLooping("REPEAT")
                local tr = ag:CreateAnimation("Translation")
                tr:SetOffset((self:GetWidth() * 0.72), 0); tr:SetDuration(1.1)
                self._anim = ag
            end
            self.txt:Hide(); self._anim:Play()
        else
            if self._anim then self._anim:Stop() end
            self:_render()
        end
    end

    f.value = opts.value or f.min
    f:_render()
    return f
end

-- A rotating spinner. Uses a bundled loader texture if you provide opts.icon; otherwise it
-- draws a simple spinning tick mark from a solid texture so it works with no art.
function Mixin:Spinner(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local size = opts.size or 24
    local f = CreateFrame("Frame", nil, parent); f:SetSize(size, size)
    local tex = f:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints()
    local col = UIF.toColor(opts.color, C.accent)
    if opts.icon then
        tex:SetTexture(theme:ResolveIcon(opts.icon) or opts.icon); tex:SetVertexColor(col[1], col[2], col[3])
    else
        -- no art: a short vertical bar pinned to the top, spun around center reads as a spinner.
        tex:ClearAllPoints(); tex:SetPoint("TOP"); tex:SetSize(math.max(2, size * 0.14), size * 0.42)
        UIF.paint(tex, col)
    end
    f.tex = tex
    local ag = tex:CreateAnimationGroup(); ag:SetLooping("REPEAT")
    local rot = ag:CreateAnimation("Rotation"); rot:SetDegrees(-360); rot:SetDuration(opts.speed or 0.9)
    f.anim = ag
    function f:Start() self:Show(); self.anim:Play() end
    function f:Stop() self.anim:Stop(); self:Hide() end
    if opts.autostart ~= false then f:Start() end
    return f
end
