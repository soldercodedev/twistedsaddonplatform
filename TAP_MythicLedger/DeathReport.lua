-- TAP: Mythic Ledger - DeathReport.lua
-- On-screen post-pull DEATH REPORT. After combat drops (or at the run's finish), it flashes a short,
-- self-fading overlay listing who has died since the last report and WHY - the time in the key, the
-- killing blow, and the cause (avoidable / missed kick + which cast / threat / unavoidable). Appearance
-- (font, size, colors, background, position) is user-configurable, and a slash command reposts the last
-- report to party/raid chat. Reads deaths from the same C_DamageMeter Deaths session + C_DeathRecap the
-- rest of the module uses, and classifies them with Providers.ClassifyDeaths - it never scores anything.

local ADDON, ML = ...
local API = ML.API
local DB  = ML.DB
local Providers = ML.Providers

local DR = {}
ML.DeathReport = DR

local frame, eventFrame          -- the overlay + the event listener (created lazily)
local previewFrame               -- the live Settings preview (created lazily)
local seen = {}                  -- recapID -> true: deaths already reported this run (COMBAT trigger)
local lastReport                 -- { header, entries } cached for the party-chat re-post
local hideTimer
local moving = false             -- true while the user is dragging the overlay to reposition it
local moveBackup                 -- { posX, posY } saved when move mode starts, restored on Cancel

----------------------------------------------------------------------
-- Helpers.
----------------------------------------------------------------------
local function theme() return _G.TAP and _G.TAP.uiTheme end

local function classHex(classFile)
    local rc = classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
    if rc then return string.format("%02x%02x%02x", rc.r * 255, rc.g * 255, rc.b * 255) end
    return "cdd2db"
end

-- "seconds into the key" -> "M:SS" (the recap event ts and run.startedAt are both epoch seconds).
local function keyTime(sec)
    if type(sec) ~= "number" or sec < 0 then return "--:--" end
    return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

-- Cause -> short label + accent (matches the Death Causes card colors).
local CAUSE = {
    kickable  = { label = "missed kick", hex = "5f8dff" },
    avoidable = { label = "avoidable",   hex = "e0655a" },
    threat    = { label = "threat",      hex = "e0a030" },
    other     = { label = "unavoidable", hex = "9aa0ad" },
}
local function killerName(e)
    if e.killer and e.killer ~= "" then return e.killer end
    if e.cause == "threat" then return "Melee" end
    return "?"
end

----------------------------------------------------------------------
-- Gather NEW deaths (recapIDs not yet reported) and classify each. Returns a time-sorted array of
-- { t, name, classFile, killer, cause } or nil. `onlyNew` false = include every death (run-end).
----------------------------------------------------------------------
local function gatherDeaths(onlyNew, runOverride)
    -- `runOverride` lets the RUN_END path pass the run captured at CHALLENGE_MODE_COMPLETED, since the
    -- Tracker clears its `current` ~1.5s later when it finalizes.
    local run = runOverride or (ML.Tracker and ML.Tracker.Current and ML.Tracker.Current())
    if not run or not Providers or not Providers.ReadDeathRecaps then return nil end
    local ctx = { player = run.character, party = run.party or (API.GroupMembers and API.GroupMembers()) or {}, petOwners = {} }
    local recaps = Providers.ReadDeathRecaps(ctx)
    if not recaps then return nil end
    local attrib = (Providers.ReadAttribution and Providers.ReadAttribution(ctx)) or {}

    -- The dungeon's interruptible casts, so a death to an un-kicked cast reads as "missed kick".
    local kickSet
    local Cfg = ML.Scoring and ML.Scoring.Config
    local cat = Cfg and Cfg.SeasonDungeon and Cfg.SeasonDungeon(run.dungeonName)
    if cat and type(cat.kicks) == "table" then
        kickSet = {}
        for _, e in ipairs(cat.kicks) do if e.id then kickSet[e.id] = true end end
    end

    local byGuid = {}
    for _, m in ipairs(ctx.party or {}) do if m.guid then byGuid[m.guid] = m end end
    if run.character and run.character.guid then byGuid[run.character.guid] = byGuid[run.character.guid] or run.character end
    local myGuid = run.character and run.character.guid
    local cfg = DB.DeathReport()

    local out = {}
    for guid, deaths in pairs(recaps) do
        if not (cfg.onlyMe and guid ~= myGuid) then
            local m = byGuid[guid] or {}
            local dc = Providers.ClassifyDeaths(attrib[guid], deaths, m.role, #deaths, kickSet)
            local fatals = (dc and dc.fatal) or {}
            for i, d in ipairs(deaths) do   -- fatals[i] is parallel to deaths[i]
                local rid = d.recapID
                if (not onlyNew) or (rid and not seen[rid]) then
                    if onlyNew and rid then seen[rid] = true end
                    local f = fatals[i] or {}
                    local evs = d.events or {}
                    local last = evs[#evs]
                    local t = (last and last.ts and run.startedAt) and (last.ts - run.startedAt) or nil
                    out[#out + 1] = { t = t, name = m.name or m.fullName or "?", classFile = m.classFile,
                                      killer = f.killer, cause = f.cause or "other" }
                end
            end
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

----------------------------------------------------------------------
-- Report frame + rendering (shared by the overlay, the Test flash, and the Settings preview).
----------------------------------------------------------------------
local function makeReportFrame(name, parent)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(360, 44)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    f.title = f:CreateFontString(nil, "OVERLAY"); f.title:SetPoint("TOP", 0, -8)
    f.lines = {}
    return f
end

-- The live overlay (UIParent-parented, draggable only while repositioning).
local function ensureFrame()
    if frame then return frame end
    local f = makeReportFrame("TAPMythicLedgerDeathReport", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local cfg = DB.DeathReport()
        cfg.posPoint = "CENTER"
        cfg.posX = math.floor((cx or ux) - ux + 0.5)
        cfg.posY = math.floor((cy or uy) - uy + 0.5)
        DR.Reposition()
    end)
    f:SetScript("OnMouseUp", function(self) if not moving and self._clickDismiss then DR.Dismiss() end end)
    frame = f
    return f
end

function DR.Reposition()
    if not frame then return end
    local cfg = DB.DeathReport()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", cfg.posX or 0, cfg.posY or 220)
end

local function lineText(e)
    local ci = CAUSE[e.cause] or CAUSE.other
    return string.format("|cff8b91a0%s|r   |cff%s%s|r  -  %s  |cff%s(%s)|r",
        keyTime(e.t), classHex(e.classFile), e.name or "?", killerName(e), ci.hex, ci.label)
end

-- Render `header` + `entries` into report frame `f` with the current appearance settings; sizes the
-- frame to its content and returns (width, height). Positioning/hold/fade are the caller's job.
local function renderInto(f, entries, header, cfg)
    local th = theme()
    local fontPath = (th and th.ResolveFont and cfg.font and cfg.font ~= "" and th:ResolveFont(cfg.font))
        or (th and th.FONT) or _G.STANDARD_TEXT_FONT
    local size = tonumber(cfg.fontSize) or 15

    f.title:SetFont(fontPath, size + 2, "OUTLINE")
    local tc = cfg.titleColor or { 1, 1, 1 }
    f.title:SetTextColor(tc[1], tc[2], tc[3])
    f.title:SetText(header or "Death Report")

    local ty = -8 - (size + 2) - 6
    local maxW = f.title:GetStringWidth() or 120
    for i, e in ipairs(entries) do
        local fs = f.lines[i]
        if not fs then fs = f:CreateFontString(nil, "OVERLAY"); f.lines[i] = fs end
        fs:SetFont(fontPath, size, "OUTLINE")
        fs:SetText(lineText(e))
        fs:ClearAllPoints(); fs:SetPoint("TOP", 0, ty)
        fs:Show()
        maxW = math.max(maxW, fs:GetStringWidth() or 0)
        ty = ty - (size + 6)
    end
    for i = #entries + 1, #f.lines do f.lines[i]:Hide() end

    local w, h = math.max(220, maxW + 44), (-ty) + 8
    f:SetSize(w, h)
    if cfg.background then
        local bc = cfg.bgColor or { 0, 0, 0, 0.8 }
        f.bg:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.8); f.bg:Show()
    else
        f.bg:Hide()
    end
    return w, h
end

-- Fade + hide the live overlay (auto-dismiss timer and click-to-dismiss both route here).
function DR.Dismiss()
    if not frame or moving then return end
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if _G.UIFrameFadeOut then _G.UIFrameFadeOut(frame, 0.4, frame:GetAlpha() or 1, 0) end
    C_Timer.After(0.45, function() if not moving then frame:Hide() end end)
end

-- Show the live overlay. `clickDismiss` = stays until clicked; otherwise it fades after `hold` seconds.
local function show(entries, header, hold, clickDismiss)
    local f = ensureFrame()
    renderInto(f, entries, header, DB.DeathReport())
    DR.Reposition()
    f:SetAlpha(1); f:Show()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if clickDismiss and not moving then
        f._clickDismiss = true
        f:EnableMouse(true)          -- capture clicks so the user can dismiss it
    else
        f._clickDismiss = false
        if not moving then f:EnableMouse(false) end
        if hold and hold < 9000 then hideTimer = C_Timer.NewTimer(hold, DR.Dismiss) end
    end
end

----------------------------------------------------------------------
-- Public: run the report, test it, preview it in Settings, reposition it, and post it to chat.
----------------------------------------------------------------------
function DR.Run(onlyNew, runOverride)
    local cfg = DB.DeathReport()
    if not (cfg and cfg.enabled) then return end
    local entries = gatherDeaths(onlyNew ~= false, runOverride)
    if not entries then return end
    local cap = tonumber(cfg.maxLines) or 8
    local shown = {}
    for i = 1, math.min(cap, #entries) do shown[i] = entries[i] end
    local header = (onlyNew ~= false) and "Deaths this pull" or "Death Report"
    if #entries > cap then header = header .. string.format("  (top %d of %d)", cap, #entries) end
    lastReport = { header = header, entries = entries }   -- plain header for the chat re-post
    local click = cfg.dismiss == "CLICK"
    show(shown, click and (header .. "   |cff8b91a0(click to dismiss)|r") or header, cfg.duration, click)
end

-- A representative sample - ONE OF EVERY cause - so Settings can preview / position without a real death.
local function sampleEntries()
    local _, myClass = UnitClass("player")
    return {
        { t = 272, name = UnitName("player") or "You", classFile = myClass,  killer = "Spirit Rend",  cause = "kickable" },
        { t = 415, name = "Sparkles", classFile = "MAGE",    killer = "Void Blast",    cause = "avoidable" },
        { t = 618, name = "Tankalot", classFile = "PALADIN", killer = "Melee",         cause = "threat" },
        { t = 744, name = "Healbot",  classFile = "PRIEST",  killer = "Necrotic Bolt", cause = "other" },
    }
end

function DR.Test()
    local cfg = DB.DeathReport()
    local click = cfg.dismiss == "CLICK"
    show(sampleEntries(), click and "Death Report - test   |cff8b91a0(click to dismiss)|r" or "Death Report - test",
        cfg.duration or 6, click)
end

-- Live Settings preview: render the sample into a pooled frame parented to the settings content at
-- (x, y). Returns its height so the layout can advance. `b:Transient` auto-hides it off the tab.
function DR.RenderPreview(b, x, y)
    if not (b and b.content) then return 0 end
    if not previewFrame then previewFrame = makeReportFrame(nil, b.content) end
    if previewFrame:GetParent() ~= b.content then previewFrame:SetParent(b.content) end
    local _, h = renderInto(previewFrame, sampleEntries(), "Death Report - preview", DB.DeathReport())
    previewFrame:ClearAllPoints()
    previewFrame:SetPoint("TOPLEFT", b.content, "TOPLEFT", x, y)
    previewFrame:Show()
    if b.Transient then b:Transient(previewFrame) end
    return h
end

-- Re-render just the preview in place (for color/opacity tweaks that don't change its size, so we can
-- update live without a full settings re-layout).
function DR.RefreshPreview()
    if previewFrame and previewFrame:IsShown() then
        renderInto(previewFrame, sampleEntries(), "Death Report - preview", DB.DeathReport())
    end
end

----------------------------------------------------------------------
-- Drag-to-move, with a Save/Cancel bar - without it there's no way to leave move mode, so a dragged
-- position could never be saved. Save keeps the position; Cancel restores the pre-move one.
----------------------------------------------------------------------
local function showMoverBar()
    local th = theme()
    if not (th and th.Button) then return end
    local bar = DR._moverBar
    if not bar then
        bar = CreateFrame("Frame", "TAPMythicLedgerDeathReportMover", UIParent)
        bar:SetSize(300, 74)
        bar:SetFrameStrata("FULLSCREEN_DIALOG"); bar:SetToplevel(true); bar:SetClampedToScreen(true)
        if th.StylePanel then th:StylePanel(bar, th.C.panel, th.C.border) end
        bar.label = bar:CreateFontString(nil, "OVERLAY")
        bar.label:SetFont(th.FONT or _G.STANDARD_TEXT_FONT, 12)
        bar.label:SetPoint("TOP", 0, -12); bar.label:SetPoint("LEFT", 12, 0); bar.label:SetPoint("RIGHT", -12, 0)
        bar.label:SetJustifyH("CENTER"); bar.label:SetText("Drag the death report into place, then Save.")
        if th.C then bar.label:SetTextColor(unpack(th.C.text)) end
        bar.save = th:Button(bar); bar.save:Configure("Save", 120, 26, "primary", function() DR.StopMove(true) end)
        bar.save:SetPoint("BOTTOMLEFT", 14, 12)
        bar.cancel = th:Button(bar); bar.cancel:Configure("Cancel", 120, 26, "default", function() DR.StopMove(false) end)
        bar.cancel:SetPoint("BOTTOMRIGHT", -14, 12)
        DR._moverBar = bar
    end
    bar:ClearAllPoints(); bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    bar:Show()
end

function DR.StartMove()
    local cfg = DB.DeathReport()
    moveBackup = { cfg.posX or 0, cfg.posY or 220 }
    moving = true
    show(sampleEntries(), "Death Report - drag to move", 99999, false)
    if frame then frame:EnableMouse(true) end
    showMoverBar()
end

-- `save` == false restores the pre-move position (Cancel); nil/true keeps the dragged one (Save/slash).
function DR.StopMove(save)
    if save == false and moveBackup then
        local cfg = DB.DeathReport()
        cfg.posX, cfg.posY = moveBackup[1], moveBackup[2]
        DR.Reposition()
    end
    moveBackup = nil
    moving = false
    if frame then frame:EnableMouse(false); frame:Hide() end
    if DR._moverBar then DR._moverBar:Hide() end
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if _G.TAP and _G.TAP.OpenWindow then _G.TAP:OpenWindow("mod:" .. ML.MODULE_ID) end
end
function DR.IsMoving() return moving end

-- Post the last report to party/raid chat (plain text; no color escapes in chat).
function DR.PostToParty()
    if not (lastReport and lastReport.entries and #lastReport.entries > 0) then
        ML.Print("No death report to post yet - it fills in after a pull where someone died.")
        return
    end
    local chan = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil)
    if not chan then ML.Print("You're not in a group - nothing to post to."); return end
    SendChatMessage("[Mythic Ledger] Death report:", chan)
    for i = 1, math.min(12, #lastReport.entries) do
        local e = lastReport.entries[i]
        local ci = CAUSE[e.cause] or CAUSE.other
        SendChatMessage(string.format("%s  %s - %s (%s)", keyTime(e.t), e.name or "?", killerName(e), ci.label), chan)
    end
end

----------------------------------------------------------------------
-- Events + lifecycle (driven by the module's OnEnable/OnDisable).
----------------------------------------------------------------------
local function inKey()
    return ML.Tracker and ML.Tracker.GetState and ML.Tracker.GetState() == ML.STATE.ACTIVE
end

-- Read the pull's new deaths just after combat TRULY ends - anchored to the end-of-fight EVENTS, not to
-- your death. PLAYER_REGEN_ENABLED is the signal: a grouped dead player is held in combat until the
-- whole group's fight resolves, so REGEN_ENABLED fires at the group's combat-end (the wipe / clear), even
-- if you died minutes earlier. ENCOUNTER_END(wipe) is a boss backstop. The 0.6s + 3s reads only cover
-- meter/recap lag AFTER the real end; seen[] dedup means each death is reported at most once.
local function readSoon()
    C_Timer.After(0.6, function() DR.Run(true) end)
    C_Timer.After(3.0, function() DR.Run(true) end)
end

local function onEvent(_, event, ...)
    local cfg = DB.DeathReport()
    if not (cfg and cfg.enabled) then return end
    if event == "CHALLENGE_MODE_START" then
        wipe(seen)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if cfg.trigger == "COMBAT" and inKey() then readSoon() end
    elseif event == "ENCOUNTER_END" then
        -- Boss wipe (success == 0): the fight has ended; read here too in case REGEN_ENABLED is delayed.
        if cfg.trigger == "COMBAT" and inKey() and select(5, ...) == 0 then readSoon() end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if cfg.trigger == "RUN_END" then
            -- Capture the run NOW; the Tracker clears `current` when it finalizes ~1.5s later. Read the
            -- live meter after combat has dropped for one report of every death.
            local run = ML.Tracker and ML.Tracker.Current and ML.Tracker.Current()
            C_Timer.After(1.8, function() DR.Run(false, run) end)
        end
    end
end

function DR.Start()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    wipe(seen)
    ML.Log("DeathReport started")
end

function DR.Stop()
    if eventFrame then eventFrame:UnregisterAllEvents() end
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if frame then frame:Hide() end
    moving = false
    ML.Log("DeathReport stopped")
end
