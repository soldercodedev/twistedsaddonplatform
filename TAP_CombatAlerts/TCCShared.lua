-- TAP_CombatAlerts - TCCShared.lua
-- Bridges the (kept) TCC alerts engine to the Twisteds Addon Platform. The old self-skinned UI is
-- gone; the alerts UI is rebuilt on the suite's framework as the Combat Alerts module. (Focus
-- Tools has moved to its own addon, TAP_FocusInterrupt.)
--
-- The engine (Core.lua) calls a handful of UI hooks GUARDED with `if TCC.X then`. Here we point
-- those hooks at the suite manager window. Loads after the engine (so TCC.* exists) and before
-- the module file.

local addonName, TCC = ...
local UIF   = _G.UIFoundry
local Suite = _G.TAP
local theme = (Suite and Suite.uiTheme) or (UIF and UIF:NewTheme({ name = "TAP_CombatAlertsEngine" }))

----------------------------------------------------------------------
-- Centralize sounds + fonts on the SUITE's shared catalogs. The engine (Core.lua) plays sounds
-- via TCC.PlayKey and reads visual fonts via TCC.ResolveFont; override both to use the suite so
-- there's ONE sound/font set for the whole suite (the suite's catalog was extracted from TCC, so
-- every soundKey maps 1:1 - no migration).
----------------------------------------------------------------------
function TCC.PlayKey(key, channel) if theme then theme:PlaySound(key, channel) end end
function TCC.ResolveFont(key) return (theme and theme:ResolveFont(key)) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF") end

----------------------------------------------------------------------
-- Engine -> suite window hooks.
----------------------------------------------------------------------
-- Called by the engine whenever settings/rules change: re-render the open manager page.
function TCC.RefreshManager()
    if Suite and Suite.RefreshWindow then Suite:RefreshWindow() end
end
TCC.RefreshOptions = TCC.RefreshManager   -- the engine uses both names interchangeably

-- Old TCC "views" -> the suite module page they now live on (all alerts views map to one module).
local VIEW_MAP = {
    alerts = "mod:combatAlerts",
    global = "mod:combatAlerts",
    debug  = "mod:combatAlerts",
}
function TCC.OpenManager(view)
    if Suite and Suite.OpenWindow then Suite:OpenWindow(view and VIEW_MAP[view]) end
end
TCC.OpenOptions = TCC.OpenManager

-- Close the manager window (the engine hides it before entering the on-screen position mover).
function TCC.HideManager()
    if Suite and Suite.CloseWindow then Suite:CloseWindow() end
end

----------------------------------------------------------------------
-- On-screen position mover Save/Cancel bar. The old themed UI drew this; rebuild it on the suite
-- theme. startMover() calls ShowMoverControls(anchor, onSave, onCancel); StopMover() calls
-- HideMoverControls(). Without these there is no way to leave the mover, so positions can't be
-- saved.
----------------------------------------------------------------------
function TCC.ShowMoverControls(anchorFrame, onSave, onCancel)
    local bar = TCC._moverBar
    if not bar then
        bar = CreateFrame("Frame", "TAP_CombatAlertsMoverBar", UIParent)
        bar:SetSize(300, 74)
        bar:SetFrameStrata("FULLSCREEN_DIALOG"); bar:SetToplevel(true); bar:SetClampedToScreen(true)
        bar:EnableMouse(true); bar:SetMovable(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
        bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if theme and theme.StylePanel then theme:StylePanel(bar, theme.C.panel, theme.C.border) end

        bar.label = bar:CreateFontString(nil, "OVERLAY")
        bar.label:SetFont((theme and theme.FONT) or STANDARD_TEXT_FONT, 12)
        bar.label:SetPoint("TOP", 0, -10); bar.label:SetPoint("LEFT", 12, 0); bar.label:SetPoint("RIGHT", -12, 0)
        bar.label:SetJustifyH("CENTER")
        bar.label:SetText("Drag the alert into place, then Save.")
        if theme then bar.label:SetTextColor(unpack(theme.C.text)) end

        bar.save = theme:Button(bar); bar.save:Configure("Save", 120, 26, "primary", function()
            if bar._onSave then bar._onSave() end
        end)
        bar.save:SetPoint("BOTTOMLEFT", 14, 12)
        bar.cancel = theme:Button(bar); bar.cancel:Configure("Cancel", 120, 26, "default", function()
            if bar._onCancel then bar._onCancel() end
        end)
        bar.cancel:SetPoint("BOTTOMRIGHT", -14, 12)
        TCC._moverBar = bar
    end
    bar._onSave, bar._onCancel = onSave, onCancel
    bar:ClearAllPoints()
    if anchorFrame then
        bar:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -48)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end
    bar:Show()
end

function TCC.HideMoverControls()
    if TCC._moverBar then TCC._moverBar:Hide() end
end

-- On-screen "Stop Test" bar, shown while a test cue plays (TCC.StartTest -> ShowTestControls). The
-- old themed UI drew this; rebuild it on the suite theme. Without it StopTest is unreachable, so a
-- looping test sound runs until /reload and TCC.testActive stays stuck on.
function TCC.ShowTestControls(ruleName, onStop)
    local bar = TCC._testBar
    if not bar then
        bar = CreateFrame("Frame", "TAP_CombatAlertsTestBar", UIParent)
        bar:SetSize(300, 68)
        bar:SetFrameStrata("FULLSCREEN_DIALOG"); bar:SetToplevel(true); bar:SetClampedToScreen(true)
        bar:EnableMouse(true); bar:SetMovable(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
        bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if theme and theme.StylePanel then theme:StylePanel(bar, theme.C.panel, theme.C.border) end

        bar.label = bar:CreateFontString(nil, "OVERLAY")
        bar.label:SetFont((theme and theme.FONT) or STANDARD_TEXT_FONT, 12)
        bar.label:SetPoint("TOP", 0, -10); bar.label:SetPoint("LEFT", 12, 0); bar.label:SetPoint("RIGHT", -12, 0)
        bar.label:SetJustifyH("CENTER")
        if theme then bar.label:SetTextColor(unpack(theme.C.text)) end

        bar.stop = theme:Button(bar); bar.stop:Configure("Stop Test", 160, 26, "primary", function()
            if bar._onStop then bar._onStop() end
        end)
        bar.stop:SetPoint("BOTTOM", 0, 12)
        TCC._testBar = bar
    end
    bar._onStop = onStop
    bar.label:SetText("Testing alert: " .. (ruleName or "Alert"))
    bar:ClearAllPoints(); bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
    bar:Show()
end

function TCC.HideTestControls()
    if TCC._testBar then TCC._testBar:Hide() end
end

-- Minimap button + Blizzard options panel belonged to the old UI; the suite manager (/tap)
-- replaces both. Stub them so the engine's guarded calls are harmless no-ops.
TCC.InitMinimap = TCC.InitMinimap or function() end
TCC.InitOptions = TCC.InitOptions or function() end
