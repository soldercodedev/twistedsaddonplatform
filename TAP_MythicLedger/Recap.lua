-- TAP: Mythic Ledger - Recap.lua
-- The returning-player recap. When you join / form a group with someone you've run keys with
-- before, it prints a short LOCAL-ONLY reminder. It never posts to Party/Raid/Instance/Guild or
-- any shared channel, never recaps the current player, shows each returning member at most once
-- per group session, and only ever displays metrics that are actually available (nil = omitted,
-- never shown as 0). Averages are labelled "avg" and kept distinct from the "highest +N" peak.

local ADDON, ML = ...
local API     = ML.API
local DB      = ML.DB
local History = ML.History
local Util    = ML.Util
local STATUS  = ML.STATUS

local Recap = {}
ML.Recap = Recap

local frame
local shown = {}          -- identityKey -> true, for the current group session (anti-spam)
local scanTimer
local inGroupSession = false

----------------------------------------------------------------------
-- Formatting helpers.
----------------------------------------------------------------------
-- Color helpers. Chat + toast fontstrings both honour |cffRRGGBB..|r escapes, so one colored
-- string works in either surface. Labels are muted grey and the METRIC NUMBERS are bright, so the
-- numbers pop. (Avoid pure "ffffff": the toast runs text through theme:HL, which recolors exactly
-- |cffffffff to the accent - so a "white" would render differently in chat vs toast.)
local function cc(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end
local COL = { val = "f4f6fb", timed = "3fd07a", key = "ffd100", label = "8b91a0",
              sep = "5a606c", note = "ffd100", depleted = "e0a030", abandoned = "9098a8",
              dungeon = "cdd2db" }
local function classHex(classFile)
    local rc = classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
    if rc then
        local hex = string.format("%02x%02x%02x", rc.r * 255, rc.g * 255, rc.b * 255)
        if hex == "ffffff" then hex = "f4f4f4" end   -- Priest etc.: dodge the HL accent-swap
        return hex
    end
    return "c9a2ef"   -- suite-violet fallback when we don't know the class
end

local function classSpecLabel(rc)
    local classLoc
    if rc.lastClassFile then
        classLoc = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[rc.lastClassFile]) or rc.lastClassFile
    end
    local specName
    if rc.lastSpecId and GetSpecializationInfoByID then
        local ok, _id, nm = pcall(GetSpecializationInfoByID, rc.lastSpecId)
        if ok then specName = ML.ReadStr(nm) end
    end
    if specName and classLoc then return specName .. " " .. classLoc end
    return classLoc
end

-- "Avg DPS: 10.5K, avg deaths: 1.5" with grey labels and bright numbers.
local function avgLine(rc)
    local a = rc.avg or {}
    local bits = {}
    local function add(label, v, fmt)
        if v then bits[#bits + 1] = cc(COL.label, label .. ": ") .. cc(COL.val, fmt and fmt(v) or Util.shortNum(v)) end
    end
    if rc.lastRole == "HEALER" then
        add("Avg HPS", a.hps)
        add("avg deaths", a.deaths, function(v) return string.format("%.1f", v) end)
        add("avg dispels", a.dispels, function(v) return string.format("%.0f", v) end)
    else
        add("Avg DPS", a.dps)
        add("avg interrupts", a.interrupts, function(v) return string.format("%.0f", v) end)
        add("avg deaths", a.deaths, function(v) return string.format("%.1f", v) end)
    end
    if #bits == 0 then return nil end
    return table.concat(bits, cc(COL.label, ", "))
end

-- Build the recap as an array of short, pre-colored phrases. Chat joins them on one line with a
-- bullet; the toast stacks them as separate lines. `name` is the player (owned by the caller).
local function buildLines(rc, cfg)
    local lines = {}
    lines[#lines + 1] = cc(COL.val, rc.runs) .. cc(COL.label, " key" .. (rc.runs == 1 and "" or "s") .. " together")
    local tline = cc(COL.timed, rc.timed) .. cc(COL.label, " timed")
    if rc.highestTimed then tline = tline .. cc(COL.label, ", highest ") .. cc(COL.key, "+" .. rc.highestTimed) end
    lines[#lines + 1] = tline
    local csl = classSpecLabel(rc)
    if csl then lines[#lines + 1] = cc(COL.label, "Last seen: ") .. cc(classHex(rc.lastClassFile), csl) end
    if cfg.includeAverages then
        local al = avgLine(rc)
        if al then lines[#lines + 1] = al end
    end
    if rc.mixedLevels and rc.minLevel and rc.maxLevel then
        lines[#lines + 1] = cc(COL.label, "keys ") .. cc(COL.val, "+" .. rc.minLevel)
            .. cc(COL.label, " to ") .. cc(COL.val, "+" .. rc.maxLevel)
    end
    if cfg.includeLastResult and rc.lastRun then
        local rr = rc.lastRun
        local res = rr.status == STATUS.TIMED and cc(COL.timed, "timed")
            or (rr.status == STATUS.DEPLETED and cc(COL.depleted, "depleted") or cc(COL.abandoned, "abandoned"))
        lines[#lines + 1] = cc(COL.label, "Last: ") .. cc(COL.dungeon, tostring(rr.dungeon))
            .. " " .. cc(COL.key, "+" .. tostring(rr.level)) .. cc(COL.label, " (") .. res .. cc(COL.label, ")")
    end
    if cfg.includeNotes and rc._key then
        local meta = DB.PlayerMeta()[rc._key]
        local note = meta and meta.notes
        if note and note ~= "" then lines[#lines + 1] = cc(COL.note, "Note: ") .. cc(COL.val, note) end
    end
    return lines
end

----------------------------------------------------------------------
-- Emit (local only). One returning player -> a colored chat line and/or a centre-screen toast.
-- The sound is NOT played here (it fires once per batch via playRecapSound), so a group with
-- several returning members doesn't stack the sound.
----------------------------------------------------------------------
local function emit(name, rc, cfg)
    local disp = cfg.display or ML.RECAP_DISPLAY.CHAT
    if disp == ML.RECAP_DISPLAY.OFF then return end
    local nameC = cc(classHex(rc.lastClassFile), name)
    local lines = buildLines(rc, cfg)
    if disp == ML.RECAP_DISPLAY.CHAT or disp == ML.RECAP_DISPLAY.BOTH then
        -- DEFAULT_CHAT_FRAME print = local only. Never SendChatMessage to a shared channel.
        print(ML.PREFIX .. nameC .. cc(COL.label, ":  ") .. table.concat(lines, "  " .. cc(COL.sep, "•") .. "  "))
    end
    if disp == ML.RECAP_DISPLAY.TOAST or disp == ML.RECAP_DISPLAY.BOTH then
        local theme = _G.TAP and _G.TAP.uiTheme
        if theme and theme.Toast then
            theme:Toast({ title = nameC, text = table.concat(lines, "\n"), variant = "info",
                          icon = "users", position = "CENTER", width = 384, duration = 8 })
        end
    end
end

-- Play the recap sound ONCE for a batch (guarded by the setting). Called by the scanners after
-- they've emitted, so multiple returning players in one group still only trigger a single sound.
local function playRecapSound(cfg)
    if not cfg.sound then return end
    local theme = _G.TAP and _G.TAP.uiTheme
    if theme and theme.PlaySound then theme:PlaySound(cfg.soundKey or "Applause", cfg.soundChannel or "Master") end
end

----------------------------------------------------------------------
-- Scan the current group for returning members.
----------------------------------------------------------------------
local function scan()
    local cfg = DB.Recap()
    if not cfg or not cfg.enabled then return end
    if cfg.display == ML.RECAP_DISPLAY.OFF then return end
    if not IsInGroup() then return end
    -- Never recap during an active or completing key. That window IS the dungeon start/finish, where
    -- the just-saved run would flip the whole group to "returning" and re-toast everyone - and where
    -- firing UI into the protected challenge-mode transition risks a taint. Recaps belong to forming
    -- the group / a ready check, not mid-run.
    local st = ML.Tracker and ML.Tracker.GetState and ML.Tracker.GetState()
    if st and st ~= ML.STATE.IDLE then return end

    local minShared = tonumber(cfg.minShared) or 1
    local scope = (cfg.history == ML.RECAP_HISTORY.SEASON) and API.GetCurrentSeason() or nil

    local any = false
    for _, m in ipairs(API.GroupMembers()) do
        if not m.isPlayer then
            local key = API.IdentityKey(m)
            if key and not shown[key] then
                -- Mark as evaluated for the whole group session up front - whether or not we recap
                -- them - so a later roster update (e.g. the instant a key saves) can't re-toast them.
                shown[key] = true
                local summary = History.PlayerSummary(key)
                -- Only recap someone with at least one PRIOR saved run (the current run isn't saved yet).
                if summary and (summary.totals.runs or 0) >= 1 then
                    local rc = History.RecapStats(key, scope)
                    if rc and rc.runs >= minShared then
                        rc._key = key
                        emit(m.fullName or m.name, rc, cfg)
                        any = true
                    end
                end
            end
        end
    end
    if any then playRecapSound(cfg) end   -- one sound for the whole group, not one per member
end

-- Debounced scan: coalesce GROUP_ROSTER_UPDATE bursts and wait joinDelay so roster/role/spec settle.
local function scheduleScan()
    local cfg = DB.Recap()
    if not cfg or not cfg.enabled then return end
    if scanTimer then scanTimer:Cancel() end
    local delay = tonumber(cfg.joinDelay) or 3
    scanTimer = C_Timer.NewTimer(math.max(0.5, delay), function()
        scanTimer = nil
        local ok, err = pcall(scan)
        if not ok then ML.Log("recap scan error: %s", tostring(err)) end
    end)
end

-- Fire a scan only for the configured trigger. JOIN = when the roster changes (someone joins);
-- READY = on a ready check; BOTH = either. We deliberately do NOT recap on PLAYER_ENTERING_WORLD:
-- that fired at dungeon start AND end (zoning in/out), which spammed toasts for the whole group at
-- the end of a key and risked tainting the protected challenge-mode UI mid-transition.
local function triggerScan(kind)
    local cfg = DB.Recap()
    if not cfg or not cfg.enabled then return end
    local trig = cfg.trigger or ML.RECAP_TRIGGER.JOIN
    if trig == ML.RECAP_TRIGGER.BOTH or trig == kind then scheduleScan() end
end

local function onEvent(_, event)
    if event == "GROUP_ROSTER_UPDATE" then
        if IsInGroup() then
            inGroupSession = true
            triggerScan(ML.RECAP_TRIGGER.JOIN)
        else
            -- Left the group: end the session so the same people can be recapped again next time.
            if inGroupSession then wipe(shown) end
            inGroupSession = false
        end
    elseif event == "READY_CHECK" then
        if IsInGroup() then
            inGroupSession = true
            triggerScan(ML.RECAP_TRIGGER.READY)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Track session state only (no scan) so leaving the group between zones resets the anti-spam.
        if IsInGroup() then
            inGroupSession = true
        else
            if inGroupSession then wipe(shown) end
            inGroupSession = false
        end
    end
end

----------------------------------------------------------------------
-- Lifecycle (driven by the module OnEnable/OnDisable).
----------------------------------------------------------------------
function Recap.Start()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
    end
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("READY_CHECK")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    wipe(shown)
    inGroupSession = IsInGroup() and true or false
    ML.Log("Recap started")
end

function Recap.Stop()
    if frame then frame:UnregisterAllEvents() end
    if scanTimer then scanTimer:Cancel(); scanTimer = nil end
    ML.Log("Recap stopped")
end

-- Mark a just-played group (a run's party) as already-seen for THIS session without recapping them.
-- The tracker calls this the instant a run is SAVED: that save flips the whole party to "returning", so
-- a roster update right after (loot, someone leaving, zoning out) would otherwise toast the entire group
-- as if you'd just met them - especially a fresh LFG group that dropped straight into the key and never
-- got a clean pre-run scan. Marking them seen here closes that window. Leaving the group still wipes
-- `shown`, so re-grouping with them in a later session recaps normally.
function Recap.MarkGroupSeen(party)
    if IsInGroup and IsInGroup() then inGroupSession = true end
    local roster = party or (API.GroupMembers and API.GroupMembers()) or {}
    for _, m in ipairs(roster) do
        if not m.isPlayer then
            local key = API.IdentityKey(m)
            if key then shown[key] = true end
        end
    end
end

-- In-window preview (Settings): a representative recap for a fabricated returning player, built with
-- the SAME buildLines() the live recap uses so the preview matches your current settings exactly.
-- Returns (nameLine, lines) - both pre-colored strings/array - and neither prints nor plays a sound.
function Recap.PreviewLines(cfg)
    cfg = cfg or DB.Recap()
    local sample = {
        runs = 12, timed = 9, highestTimed = 14,
        lastClassFile = "MAGE", lastSpecId = 63, lastRole = "DAMAGER",
        avg = { dps = 1.84e6, deaths = 1.6, interrupts = 7 },
        mixedLevels = true, minLevel = 8, maxLevel = 16,
        lastRun = { status = STATUS.TIMED, dungeon = "Operation: Floodgate", level = 13 },
        _key = nil,
    }
    return cc(classHex(sample.lastClassFile), "Spellburn-Illidan"), buildLines(sample, cfg)
end

-- Manual preview (Settings/Debug): recap everyone currently grouped, ignoring the once-per-session
-- guard, so the user can see what a recap looks like.
function Recap.PreviewCurrentGroup()
    local cfg = DB.Recap()
    if not IsInGroup() then ML.Print("Join a group to preview recaps.") ; return end
    local scope = (cfg.history == ML.RECAP_HISTORY.SEASON) and API.GetCurrentSeason() or nil
    local any = false
    for _, m in ipairs(API.GroupMembers()) do
        if not m.isPlayer then
            local key = API.IdentityKey(m)
            local summary = key and History.PlayerSummary(key)
            if summary and (summary.totals.runs or 0) >= 1 then
                local rc = History.RecapStats(key, scope)
                if rc then rc._key = key; emit(m.fullName or m.name, rc, cfg); any = true end
            end
        end
    end
    if any then playRecapSound(cfg) else ML.Print("No returning players in your current group.") end
end

-- Dev preview: simulate a group with n (1-4) returning players drawn from your saved history and
-- fire the recap EXACTLY as configured (display / detail / averages / season scope / min-shared
-- are all honoured). Ignores the once-per-session guard. Backs the dev tools' /mldev recap command.
function Recap.Simulate(n)
    n = math.max(1, math.min(4, tonumber(n) or 2))
    local cfg = DB.Recap()
    if not cfg or not cfg.enabled or cfg.display == ML.RECAP_DISPLAY.OFF then
        ML.Print("Regroup recaps are disabled in Settings - enable them (and pick a display) to preview.")
        return
    end
    local minShared = tonumber(cfg.minShared) or 1
    local scope = (cfg.history == ML.RECAP_HISTORY.SEASON) and API.GetCurrentSeason() or nil
    -- Candidates by all-time shared runs, most-run first.
    local pool = {}
    for key, rec in pairs(DB.PlayerIndex()) do
        if ((rec.totals and rec.totals.runs) or 0) >= minShared then
            pool[#pool + 1] = { key = key, name = rec.fullName or rec.name or "?", runs = rec.totals.runs or 0 }
        end
    end
    table.sort(pool, function(a, b) return a.runs > b.runs end)

    -- Resolve who will ACTUALLY recap under the configured scope FIRST, so the header count can't
    -- claim more than we show. RecapStats is season-scoped, so an all-time candidate can still yield
    -- nothing in the current season (a common surprise with the fake-season dev data).
    local ready = {}
    for _, p in ipairs(pool) do
        local rc = History.RecapStats(p.key, scope)
        if rc and rc.runs >= minShared then
            rc._key = p.key
            ready[#ready + 1] = { name = p.name, rc = rc }
            if #ready >= n then break end
        end
    end
    if #ready == 0 then
        if #pool > 0 and scope then
            ML.Print("You have returning players, but none with >= %d shared run(s) in the CURRENT season. "
                .. "Set Recap history to 'All seasons' in Settings, or run /mldev to add current-season data.", minShared)
        else
            ML.Print("No returning players with >= %d shared run(s) yet. Run /mldev to generate mock data.", minShared)
        end
        return
    end
    ML.Print("Simulating a group with %d returning player%s (display: %s):",
        #ready, #ready == 1 and "" or "s", cfg.display)
    for _, e in ipairs(ready) do
        emit(e.name, e.rc, cfg)
    end
    playRecapSound(cfg)   -- once for the batch
end
