-- TAP: Mythic Ledger - LiveCoach.lua
-- On-screen LIVE COACH. After a combat encounter settles (a boss, or a big pull), it scores the run SO FAR
-- with the SAME engine the final grade uses (Score.ScorePlayer -> Review.Build - nothing here changes any
-- scoring logic or knob), then flashes a short, self-fading overlay with your grade-so-far and the
-- highest-leverage reminder(s): "Kick more", "Push your DPS", "Heal harder", "Cut avoidable damage", etc.
-- Look, feel, position, font and dismissal all mirror the Death Report, and everything is configurable +
-- previewable in Settings. The number shown is a labelled "so far" preview; the authoritative score is
-- still the one at run completion.

local ADDON, ML = ...
local DB = ML.DB

local LC = {}
ML.LiveCoach = LC

local frame, eventFrame
local previewFrame
local hideTimer
local moving = false
local combatStart, bossPending   -- combat-length + boss-just-ended tracking for the cadence gate
local evalTimer

----------------------------------------------------------------------
-- Helpers.
----------------------------------------------------------------------
local function theme() return _G.TAP and _G.TAP.uiTheme end
local FIX_DEFAULT  = { 0.95, 0.62, 0.30 }   -- "focus on" lines
local GOOD_DEFAULT = { 0.42, 0.82, 0.45 }   -- praise / on-pace lines
local function fixColor(cfg)  return cfg.fixColor  or FIX_DEFAULT  end
local function goodColor(cfg) return cfg.goodColor or GOOD_DEFAULT end

-- One scored category -> a terse, imperative reminder (built from the SAME detail the grade uses).
local function shortTip(key, label, cats)
    cats = cats or {}
    if key == "interrupts" then
        local c = cats.interrupts or {}
        return string.format("Kick more  -  %d of ~%.0f so far", c.actual or 0, c.expected or 0)
    elseif key == "dispels" then
        local c = cats.dispels or {}
        return string.format("Dispel more  -  %d of ~%.0f so far", c.actual or 0, c.expected or 0)
    elseif key == "survival" then
        local sh = (cats.survival and cats.survival.detail and cats.survival.detail.avoidableShare) or 0
        return string.format("Cut avoidable damage  -  %.0f%% of what you've taken", sh * 100)
    elseif key == "deaths" then
        local d = (cats.deaths and cats.deaths.deaths) or 0
        return string.format("Stay alive  -  %d death%s so far", d, d == 1 and "" or "s")
    elseif key == "throughput" then
        local det = (cats.throughput and cats.throughput.detail) or {}
        -- Prefer the labelled component; if the item is unlabelled (single component), infer from which
        -- detail exists, so a healer's HPS-only throughput never reads as "Push your DPS".
        local isHeal = (label and label:find("Healing")) or (det.dps == nil and det.hps ~= nil)
        local c = isHeal and det.hps or det.dps
        local under = c and c.ratio and math.max(0, math.floor((1 - (c.ratio or 1)) * 100 + 0.5)) or nil
        if isHeal then
            return under and string.format("Heal harder  -  %d%% under your share", under) or "Heal harder"
        end
        return under and string.format("Push your DPS  -  %d%% under your share", under) or "Push your DPS"
    end
    return label or "Keep it up"
end

local function gradeText(score) return string.format("%s (%d) so far", score.grade or "?", score.overall or 0) end

-- Turn a scored+reviewed player into (header, lines) or nil (stay silent, per the pop policy).
-- lines = { { text, color }, ... }. depth = ONE (one reminder) / TWO (top 2) / MINI (headline + strength).
local function buildContent(score, review, cfg)
    local cats = score.categories or {}
    local imps = review.improvements or {}
    local strs = review.strengths or {}
    local policy = cfg.popPolicy or "SLIP"
    local depth  = cfg.depth or "ONE"
    local onPace = (#imps == 0)

    local header = "Live Coach  -  " .. gradeText(score)
    local lines = {}

    if onPace then
        if policy == "SLIP" then return nil end                -- quiet when there's nothing to fix
        lines[#lines + 1] = { text = "On pace - keep it up.", color = goodColor(cfg) }
        if (policy == "ALWAYS" or depth == "MINI") and strs[1] then
            lines[#lines + 1] = { text = "Best: " .. (strs[1].label or "solid work"), color = goodColor(cfg) }
        end
        return header, lines
    end

    if depth == "MINI" and review.headline then
        lines[#lines + 1] = { text = review.headline, color = cfg.textColor or { 0.9, 0.92, 0.96 } }
    end
    local nFix = (depth == "ONE") and 1 or 2
    for i = 1, math.min(nFix, #imps) do
        lines[#lines + 1] = { text = shortTip(imps[i].key, imps[i].label, cats), color = fixColor(cfg) }
    end
    if depth == "MINI" and strs[1] then
        lines[#lines + 1] = { text = "Nice: " .. (strs[1].label or "solid work"), color = goodColor(cfg) }
    end
    return header, lines
end

-- A representative sample, so Settings can preview / position without a real fight. Respects `depth`.
local function sampleContent(cfg)
    local depth = cfg.depth or "ONE"
    local lines = {}
    if depth == "MINI" then
        lines[#lines + 1] = { text = "Solid run - a couple of concrete gains to chase.",
            color = cfg.textColor or { 0.9, 0.92, 0.96 } }
    end
    lines[#lines + 1] = { text = "Kick more  -  2 of ~4 so far", color = fixColor(cfg) }
    if depth ~= "ONE" then
        lines[#lines + 1] = { text = "Push your DPS  -  12% under your share", color = fixColor(cfg) }
    end
    if depth == "MINI" then
        lines[#lines + 1] = { text = "Nice: Survival", color = goodColor(cfg) }
    end
    return "Live Coach  -  B (78) so far", lines
end

----------------------------------------------------------------------
-- Overlay frame + rendering (shared by the live overlay, the Test flash, and the Settings preview).
----------------------------------------------------------------------
local function makeFrame(name, parent)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(360, 44)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    f.title = f:CreateFontString(nil, "OVERLAY"); f.title:SetPoint("TOP", 0, -8)
    f.lines = {}
    return f
end

local function renderInto(f, header, lines, cfg)
    local th = theme()
    local fontPath = (th and th.ResolveFont and cfg.font and cfg.font ~= "" and th:ResolveFont(cfg.font))
        or (th and th.FONT) or _G.STANDARD_TEXT_FONT
    local size = tonumber(cfg.fontSize) or 15

    f.title:SetFont(fontPath, size + 2, "OUTLINE")
    local tc = cfg.titleColor or { 0.36, 0.83, 0.92 }
    f.title:SetTextColor(tc[1], tc[2], tc[3])
    f.title:SetText(header or "Live Coach")

    local ty = -8 - (size + 2) - 6
    local maxW = f.title:GetStringWidth() or 120
    for i, ln in ipairs(lines) do
        local fs = f.lines[i]
        if not fs then fs = f:CreateFontString(nil, "OVERLAY"); f.lines[i] = fs end
        fs:SetFont(fontPath, size, "OUTLINE")
        fs:SetText(ln.text or "")
        local col = ln.color or cfg.textColor or { 0.94, 0.95, 0.98 }
        fs:SetTextColor(col[1], col[2], col[3])
        fs:ClearAllPoints(); fs:SetPoint("TOP", 0, ty); fs:Show()
        maxW = math.max(maxW, fs:GetStringWidth() or 0)
        ty = ty - (size + 6)
    end
    for i = #lines + 1, #f.lines do f.lines[i]:Hide() end

    local w, h = math.max(240, maxW + 44), (-ty) + 8
    f:SetSize(w, h)
    if cfg.background then
        local bc = cfg.bgColor or { 0.03, 0.04, 0.06, 0.85 }
        f.bg:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.85); f.bg:Show()
    else
        f.bg:Hide()
    end
    return w, h
end

local function ensureFrame()
    if frame then return frame end
    local f = makeFrame("TAPMythicLedgerLiveCoach", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    -- No drag scripts: positioning goes through the platform's mover ghost, which writes back
    -- through the registered Set. The overlay itself only ever captures a click-to-dismiss.
    f:SetScript("OnMouseUp", function(self) if not moving and self._clickDismiss then LC.Dismiss() end end)
    frame = f
    return f
end

function LC.Reposition()
    if not frame then return end
    local cfg = DB.LiveCoach()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", cfg.posX or 0, cfg.posY or -160)
end

function LC.Dismiss()
    if not frame or moving then return end
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if _G.UIFrameFadeOut then _G.UIFrameFadeOut(frame, 0.4, frame:GetAlpha() or 1, 0) end
    C_Timer.After(0.45, function() if not moving then frame:Hide() end end)
end

local function dismissModes(cfg)
    local d = cfg.dismiss or "AUTO"
    return (d == "CLICK" or d == "BOTH"), (d == "AUTO" or d == "BOTH")
end

local function show(header, lines, cfg, clickDismiss, autoFade)
    local f = ensureFrame()
    renderInto(f, header, lines, cfg)
    LC.Reposition()
    f:SetAlpha(1); f:Show()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    f._clickDismiss = (clickDismiss and not moving) or false
    if not moving then f:EnableMouse(f._clickDismiss) end
    if autoFade and not moving and cfg.duration and cfg.duration < 9000 then
        hideTimer = C_Timer.NewTimer(cfg.duration, LC.Dismiss)
    end
end

local function showContent(header, lines, cfg)
    local clickDismiss, autoFade = dismissModes(cfg)
    local hdr = clickDismiss and (header .. "   |cff8b91a0(click to dismiss)|r") or header
    show(hdr, lines, cfg, clickDismiss, autoFade)
end

----------------------------------------------------------------------
-- Evaluate: score the run so far and show the coach. Runs OUT OF COMBAT (the trigger is combat-end + a
-- short delay so the meter has settled). Uses the scoring engine READ-ONLY; changes nothing it computes.
----------------------------------------------------------------------
local function inKey()
    return ML.Tracker and ML.Tracker.GetState and ML.Tracker.GetState() == ML.STATE.ACTIVE
end

local function evaluate()
    local cfg = DB.LiveCoach()
    if not (cfg and cfg.enabled) or not inKey() then return end
    local run = ML.Tracker and ML.Tracker.ScoreSnapshot and ML.Tracker.ScoreSnapshot()
    if not run then return end
    local Sc = ML.Scoring and ML.Scoring.Score
    local Rv = ML.Scoring and ML.Scoring.Review
    if not (Sc and Sc.ScorePlayer and Rv and Rv.Build) then return end
    local score = Sc.ScorePlayer(run); if not score then return end
    local review = Rv.Build(score, true); if not review then return end
    local header, lines = buildContent(score, review, cfg)
    if not header then return end   -- policy = only-when-slipping and you're on pace
    showContent(header, lines, cfg)
end

local function evaluateSoon()
    if evalTimer then evalTimer:Cancel() end
    evalTimer = C_Timer.NewTimer(1.0, function() evalTimer = nil; evaluate() end)
end

----------------------------------------------------------------------
-- Public: test, preview, drag-to-move.
----------------------------------------------------------------------
function LC.Test()
    local cfg = DB.LiveCoach()
    local header, lines = sampleContent(cfg)
    local clickDismiss, autoFade = dismissModes(cfg)
    local hdr = (clickDismiss and (header .. "   |cff8b91a0(click to dismiss)|r") or header) .. "   |cff8b91a0- test|r"
    show(hdr, lines, cfg, clickDismiss, autoFade)
end

function LC.RenderPreview(b, x, y)
    if not (b and b.content) then return 0 end
    if not previewFrame then previewFrame = makeFrame(nil, b.content) end
    if previewFrame:GetParent() ~= b.content then previewFrame:SetParent(b.content) end
    local header, lines = sampleContent(DB.LiveCoach())
    local _, h = renderInto(previewFrame, header, lines, DB.LiveCoach())
    previewFrame:ClearAllPoints()
    previewFrame:SetPoint("TOPLEFT", b.content, "TOPLEFT", x, y)
    previewFrame:Show()
    if b.Transient then b:Transient(previewFrame) end
    return h
end

function LC.RefreshPreview()
    if previewFrame and previewFrame:IsShown() then
        local header, lines = sampleContent(DB.LiveCoach())
        renderInto(previewFrame, header, lines, DB.LiveCoach())
    end
end

----------------------------------------------------------------------
-- Placement.
--
-- This used to be a whole bespoke mover: a Save/Cancel bar, a position backup, a moving flag,
-- and its own hide/restore of the manager window. All of that now lives in the platform
-- (TAP/Movers.lua), so this overlay is positioned alongside every other add-on's frames in one
-- session from one page. What is left is the registration and the preview hook.
----------------------------------------------------------------------
local MOVER_ID = "mythicLedger:livecoach"

function LC.RegisterMover()
    local S = _G.TAP
    if not (S and S.RegisterMover) then return end
    S:RegisterMover({
        id      = MOVER_ID,
        owner   = "Mythic Ledger",
        ownerId = ML.MODULE_ID,
        label   = "Live Coach",
        icon    = "message-2",
        Get = function()
            local cfg = DB.LiveCoach()
            return "CENTER", cfg.posX or 0, cfg.posY or -160
        end,
        Set = function(_, x, y)
            local cfg = DB.LiveCoach()
            cfg.posX, cfg.posY = x, y
        end,
        frame = function() return frame end,
        -- The overlay only appears after a real pull, so placing it dry would mean dragging an
        -- invisible box. The preview puts sample content up for the duration of the session.
        Preview = function(on)
            moving = on and true or false
            if on then
                local header, lines = sampleContent(DB.LiveCoach())
                show(header .. "   |cff8b91a0- placing|r", lines, DB.LiveCoach(), false, false)
                if frame then frame:EnableMouse(false) end
            else
                if hideTimer then hideTimer:Cancel(); hideTimer = nil end
                if frame then frame:Hide() end
            end
        end,
        OnChange = function() LC.Reposition() end,
        defaults = { point = "CENTER", x = 0, y = -160 },
    })
end

-- Kept under the old names: the settings page and the slash commands both call these, and the
-- platform session is what actually does the work now.
function LC.StartMove(win)
    LC.RegisterMover()
    local S = _G.TAP
    if S and S.StartPlacement then S:StartPlacement({ id = MOVER_ID, win = win }) end
end

function LC.StopMove(save)
    local S = _G.TAP
    if S and S.StopPlacement then S:StopPlacement(save ~= false) end
end

function LC.IsMoving() return moving end

----------------------------------------------------------------------
-- Events + lifecycle. The coach fires when combat truly drops (PLAYER_REGEN_ENABLED): boss encounters
-- (via ENCOUNTER_END) always qualify; with "bosses + big pulls" a pull that lasted >= minCombat also does.
----------------------------------------------------------------------
local function onEvent(_, event, ...)
    local cfg = DB.LiveCoach()
    if not (cfg and cfg.enabled) then return end
    if event == "CHALLENGE_MODE_START" then
        combatStart, bossPending = nil, nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatStart = GetTime()
    elseif event == "ENCOUNTER_END" then
        if inKey() then bossPending = true end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not inKey() then combatStart, bossPending = nil, nil; return end
        local dur = combatStart and (GetTime() - combatStart) or 0
        combatStart = nil
        local boss = bossPending; bossPending = nil
        local fire
        if (cfg.cadence or "BOSS") == "BOSS" then fire = boss
        else fire = boss or (dur >= (cfg.minCombat or 10)) end
        if fire then evaluateSoon() end
    end
end

function LC.Start()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    combatStart, bossPending = nil, nil
    ML.Log("LiveCoach started")
end

function LC.Stop()
    if eventFrame then eventFrame:UnregisterAllEvents() end
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if evalTimer then evalTimer:Cancel(); evalTimer = nil end
    if frame then frame:Hide() end
    moving = false
    ML.Log("LiveCoach stopped")
end
