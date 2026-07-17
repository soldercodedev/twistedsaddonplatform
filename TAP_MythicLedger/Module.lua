-- TAP: Mythic Ledger - Module.lua
-- Registers the module with the platform, wires the live enable/disable lifecycle to the tracker
-- and recap services, and adds the slash commands. Loads LAST so every ML.* subsystem exists.

local ADDON, ML = ...
local Suite = _G.TAP
local UIF   = _G.UIFoundry

if not (Suite and UIF) then
    print("|cffff5555TAP: Mythic Ledger|r requires the Twisteds Addon Platform. Enable TAP and reload.")
    return
end

local mod   -- module handle

----------------------------------------------------------------------
-- Lifecycle. Enabling starts tracking + recaps; disabling fully stands them down (events
-- unregistered, timers cancelled) while leaving saved history untouched.
----------------------------------------------------------------------
local function OnEnable(m)
    mod = m
    ML.Tracker.Start()
    ML.Recap.Start()
    ML.Log("Module enabled")
end

local function OnDisable(m)
    ML.Tracker.Stop()
    ML.Recap.Stop()
    ML.Log("Module disabled")
end

local function Settings(m, b, x, y, w, win)
    return ML.UI.Render(m, b, x, y, win)
end

----------------------------------------------------------------------
-- Register with the platform. Overview / Installed / About / sidebar all populate automatically.
----------------------------------------------------------------------
mod = Suite:RegisterModule({
    id      = ML.MODULE_ID,
    title   = "Mythic Ledger",
    desc    = "An account-wide Mythic+ journal that records every run, character, party member, "
           .. "boss split, and performance summary - and reminds you who you've run keys with before.",
    icon    = "book",
    addon   = ML.ADDON,
    default = true,
    fullPage = true,   -- we render our own tabbed page; suite skips the "SETTINGS" band
    rendersWhenDisabled = true,   -- keep our page (and its Settings tab) reachable while disabled
    changelog = ML.CHANGELOG,
    OnEnable  = OnEnable,
    OnDisable = OnDisable,
    OnSelect  = function() ML.UI.ResetView() end,
    OnDeselect = function() ML.UI.OnHide() end,
    Settings  = Settings,
})

-- Optional minimap icon for this module (hidden by default; toggled in the Ledger's Settings tab).
if Suite.RegisterMinimapButton then
    Suite:RegisterMinimapButton(ML.MODULE_ID, {
        icon = "Interface\\AddOns\\TAP_MythicLedger\\assets\\images\\tap_mythic_ledger_icon.tga",
        title = "|cffa06cf0Mythic Ledger|r", action = "open the ledger",
        onClick = function() Suite:OpenWindow("mod:" .. ML.MODULE_ID) end,
        defaultHidden = true,
    })
end

----------------------------------------------------------------------
-- Slash commands: /tap ledger ... via the platform router, plus a native /ledger.
----------------------------------------------------------------------
local function handleSlash(rest)
    rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd = rest:match("^(%S+)") or ""
    if cmd == "history" or cmd == "runs" then
        ML.UI.Show("runs")
    elseif cmd == "players" then
        ML.UI.Show("players")
    elseif cmd == "debug" then
        ML.UI.Show("debug")
    elseif cmd == "apicheck" or cmd == "api" then
        ML.Diag.Run(function(s) print(s) end)
    elseif cmd == "probe" then
        ML.Diag.ProbeCapture()
    elseif cmd == "current" then
        local cur = ML.Tracker.Current()
        if cur then
            ML.Print("Current run: %s +%s (%s), started %s.", tostring(cur.dungeonName),
                tostring(cur.level), ML.Tracker.GetState(), ML.Util.dateTime(cur.startedAt))
        else
            ML.Print("No Mythic+ run in progress (state: %s).", ML.Tracker.GetState())
        end
    elseif cmd == "export" then
        local theme = Suite.uiTheme
        if theme and theme.ShowCopyDialog then theme:ShowCopyDialog("Export entire ledger", ML.Export.ExportAll() or "") end
    elseif cmd == "scale" then
        local s = ML.DB.Settings()
        local n = tonumber(rest:match("^scale%s+([%d%.]+)"))
        if n then
            n = math.max(0.5, math.min(3, n))
            s.scoreboardScale = n
            ML.Print("Scoreboard scale set to %.2fx (still capped to fit the screen). Reopen the scoreboard to see it.", n)
        else
            ML.Print("Scoreboard scale is %.2fx. Usage: /ledger scale <0.5 - 3.0>", s.scoreboardScale or 1.5)
        end
    elseif cmd == "scoreboard" or cmd == "sb" then
        local runs = ML.DB.Runs()
        local last = runs[#runs]
        if last then ML.UI.ShowScoreboard(last) else ML.Print("No runs recorded yet - run a key or use /mldev.") end
    else
        ML.UI.Show()   -- open the page
    end
end

if Suite.RegisterCommand then
    Suite:RegisterCommand({
        cmd = "/tap ledger", desc = "Open Mythic Ledger", owner = "Mythic Ledger",
        sub = "ledger", handler = handleSlash,
        subcommands = {
            { "history",  "Open the run history" },
            { "players",  "Open the party-member browser" },
            { "current",  "Show the in-progress run's status" },
            { "debug",    "Open the diagnostics page" },
            { "apicheck", "Probe the live API surface (safe on a target dummy)" },
            { "probe",    "Print provider stats for the current fight" },
            { "export",   "Copy the whole ledger as a share string" },
            { "scoreboard", "Open the scoreboard for your most recent run" },
            { "scale",    "Set the scoreboard scale, e.g. /ledger scale 1.2" },
        },
    })
    Suite:RegisterCommand({ cmd = "/ledger", desc = "Alias for /tap ledger (native slash)", owner = "Mythic Ledger" })
    -- One-shot "change your keystone" reminder: arm it now, and the next post-run scoreboard pops an
    -- alert over itself to remind you to slot your next key (see UI.ShowScoreboard).
    Suite:RegisterCommand({
        cmd = "/tap changekey", desc = "Remind me to swap my keystone after this run's scoreboard",
        owner = "Mythic Ledger", sub = "changekey",
        handler = function()
            ML.DB.Settings().pendingChangeKey = true
            ML.Print("Reminder set - you'll be prompted to change your keystone after this run's scoreboard.")
        end,
    })
end

SLASH_TAPMYTHICLEDGER1 = "/ledger"
SLASH_TAPMYTHICLEDGER2 = "/mythicledger"
SlashCmdList["TAPMYTHICLEDGER"] = handleSlash

-- Small public/dev bridge. Used by the optional, release-EXCLUDED TAP_MythicLedger_Dev tools
-- addon (mock-data generator) and available for integrations. Harmless if nothing calls it.
_G.TAPMythicLedger = {
    AddRun   = function(run) return ML.DB.AddRun(run) end,
    NewRunId = function() return ML.DB.NewRunId() end,
    Rebuild  = function() ML.History.RebuildAll() end,
    Wipe     = function() ML.DB.WipeHistory() end,
    -- DEV: remove ONLY generated mock runs (providerVersion == "mock"); returns the count removed.
    WipeDummy = function() return ML.DB.WipeMockRuns() end,
    Refresh  = function() if _G.TAP and _G.TAP.RefreshWindow then _G.TAP:RefreshWindow() end end,
    STATUS   = ML.STATUS,
    Season   = function() return ML.API.GetCurrentSeason() end,
    -- DEV: run the scoring unit tests to chat (dispel gate + per-dungeon demand, etc). /run TAPMythicLedger.RunTests()
    RunTests = function(p) if ML.Scoring and ML.Scoring.RunTests then return ML.Scoring.RunTests(p or print) end end,
    -- Preview the returning-player recap as configured, faking a group of 1-4 returning players.
    SimRecap = function(n) if ML.Recap and ML.Recap.Simulate then return ML.Recap.Simulate(n) end end,
    -- Show the end-of-run scoreboard for a run record (used by /mldev scoreboard to test it).
    ShowScoreboard = function(run) if ML.UI and ML.UI.ShowScoreboard then return ML.UI.ShowScoreboard(run) end end,
    -- DEV: reproduce per-boss combat totals at a target dummy (no real ENCOUNTER needed). Call once to
    -- start the window, hit the dummy, call again to diff + print. Used by /mldev boss.
    DevBossSim = function() if ML.Tracker and ML.Tracker.DevBossSim then return ML.Tracker.DevBossSim() end end,
    -- Spec "healiness" multiplier for a tank's self-healing (1.0 = a standard tank). Lets the dev
    -- mock-data generator simulate realistic tank HPS so the tank-healiness scoring path is exercised,
    -- reading from the SAME source of truth the scorer uses (Scoring Config).
    TankHealiness = function(specID)
        local cfg = ML.Scoring and ML.Scoring.Config
        return (cfg and cfg.throughput and cfg.throughput.tankHealiness[specID]) or 1.0
    end,
    -- DEV: the capability DISPEL record for a spec (profile, spellID/name, talentDependent), from the
    -- SAME Capability profiles the scorer uses. Lets /mldev inspect check whether a teammate actually
    -- has a talent-gated dispel before we let live talent inspection gate the dispel score.
    DispelInfo = function(specID, role, classFile)
        local Cap = ML.Scoring and ML.Scoring.Capability
        if not (Cap and Cap.Get) then return nil end
        local p = Cap.Get(specID, role, classFile)
        local d = p and p.dispel
        if not d then return nil end
        return { profile = d.profile, spellID = d.spellID, spellName = d.spellName,
                 talentDependent = d.talentDependent and true or false }
    end,
    -- DEV: run the live group dispel inspection (same engine as the Debug page's "Inspect group"
    -- button). onLine(line) fires per member; onDone(fullReport) fires at the end. Used by /mldev inspect.
    InspectDispels = function(onLine, onDone)
        if ML.Inspect and ML.Inspect.Run then return ML.Inspect.Run({ onLine = onLine, onDone = onDone }) end
    end,
}
