-- TAP: Mythic Ledger - Inspect.lua
-- Live talent-inspection for DISPEL capability. Given the current group, it inspects each member (one
-- at a time - the API only allows one active inspect) and works out whether each player actually HAS
-- their dispel: baseline dispels are always present; talent-gated ones (flagged in Scoring/Capability)
-- are confirmed by reading the inspected talent tree for the exact spell id.
--
-- Two consumers share one engine:
--   * Inspect.Run{onLine,onDone}  -> a crisp, copyable TEXT report (Debug page + /mldev inspect).
--   * Inspect.CaptureGroup(onDone) -> a data map guid -> { hasTool=bool/nil, specID } that the Tracker
--     records on the run so the dispel scorer can gate expectations (a player we can't confirm has the
--     tool is scored N/A, never docked).
--
-- Reads the SAME Scoring.Capability profiles the scorer uses, so "has the dispel?" lines up 1:1 with
-- what the dispel category expects.

local ADDON, ML = ...
ML.Inspect = ML.Inspect or {}
local Inspect = ML.Inspect

local C_Traits = _G.C_Traits
local C_ClassTalents = _G.C_ClassTalents

----------------------------------------------------------------------
-- Talent-tree reading. In ONE pass over the purchased nodes of a trait config, collect:
--   * the SPELL IDs granted by purchased nodes (baseline abilities aren't in the tree, so absence here
--     only matters for talent-gated spells) - used for the dispel gate + stored as metadata;
--   * the active HERO TREE (subtree). Hero talents can only be purchased from the chosen subtree, so the
--     first purchased node carrying a subTreeID identifies it (War Within C_Traits).
-- Returns (spellSet, count, hero{id,name} | nil, err | nil). Heavily pcall-guarded - degrades to nil.
----------------------------------------------------------------------
local function readTalents(configID)
    local out, n, hero = {}, 0, nil
    if not (configID and C_Traits and C_Traits.GetConfigInfo) then return out, n, nil, "no C_Traits API" end
    local ok, cfg = pcall(C_Traits.GetConfigInfo, configID)
    if not (ok and type(cfg) == "table" and cfg.treeIDs) then return out, n, nil, "no config (inspect not ready?)" end
    for _, treeID in ipairs(cfg.treeIDs) do
        local okn, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if okn and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local node = select(2, pcall(C_Traits.GetNodeInfo, configID, nodeID))
                if type(node) == "table" and (node.ranksPurchased or 0) > 0 then
                    -- hero subtree: the first purchased hero node reveals the active tree
                    if not hero and node.subTreeID and C_Traits.GetSubTreeInfo then
                        local oks, st = pcall(C_Traits.GetSubTreeInfo, configID, node.subTreeID)
                        st = (oks and type(st) == "table") and st or nil
                        -- iconElementID is the hero-spec's icon (atlas/texture) - captured so the UI can
                        -- show the actual hero-talent glyph, not just the name. nil-safe if absent.
                        hero = { id = node.subTreeID, name = st and st.name or nil, icon = st and st.iconElementID or nil }
                    end
                    if node.activeEntry then
                        local ent = select(2, pcall(C_Traits.GetEntryInfo, configID, node.activeEntry.entryID))
                        if type(ent) == "table" and ent.definitionID then
                            local def = select(2, pcall(C_Traits.GetDefinitionInfo, ent.definitionID))
                            local sid = type(def) == "table" and def.spellID
                            if sid and not out[sid] then out[sid] = true; n = n + 1 end
                        end
                    end
                end
            end
        end
    end
    return out, n, hero
end

-- Set -> sorted array of ids (compact for saved metadata).
local function idList(set)
    local t = {}
    for sid in pairs(set or {}) do t[#t + 1] = sid end
    table.sort(t)
    return t
end

-- The trait config id to read for a unit: your own active config for "player"; the shared inspect
-- config id (valid only while an inspect on that unit is live) for everyone else.
local function configForUnit(unit)
    if unit == "player" then
        return C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    end
    return Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
end

local ROLE_MAP = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER" }

local function specOf(unit)
    if unit == "player" then
        local idx = GetSpecialization and GetSpecialization()
        return idx and GetSpecializationInfo and GetSpecializationInfo(idx) or nil
    end
    return GetInspectSpecialization and GetInspectSpecialization(unit) or nil
end

----------------------------------------------------------------------
-- Evaluate one unit's dispel capability into a structured record. `hasTool`:
--   true  = has the dispel (baseline, or talent confirmed present)
--   false = talent-gated dispel and the talent is NOT taken (confirmed absent)
--   nil   = unknown (no dispel tool for the spec, spec unread, or talents unreadable)
----------------------------------------------------------------------
local function evalUnit(unit)
    local Cap = ML.Scoring and ML.Scoring.Capability
    local rec = { unit = unit, guid = UnitGUID(unit), name = UnitName(unit) or unit }
    -- Grab equipped item level while this unit is inspected (self reads live) - the run tracker's only
    -- reliable window for a teammate's ilvl, so we piggyback it on the dispel inspect.
    rec.itemLevel = ML.API and ML.API.ItemLevel and ML.API.ItemLevel(unit) or nil
    local _, classFile = UnitClass(unit); rec.classFile = classFile
    rec.role = (UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "NONE"
    rec.specID = specOf(unit)
    if not rec.specID or rec.specID == 0 then rec.specUnknown = true; return rec end
    rec.specName = select(2, GetSpecializationInfoByID(rec.specID)) or ("spec" .. rec.specID)

    -- Metadata capture for ALL specs (not just gated dispellers): hero tree + full talent set + ilvl,
    -- so we can build class+spec+ilvl+hero-tree expectations later. Read once, reuse for the dispel gate.
    local granted, gcount, hero, gerr = readTalents(configForUnit(unit))
    rec.talentCount = gcount
    rec.heroTree = hero
    rec.talents = idList(granted)   -- compact sorted id list for saving
    if gerr then rec.readErr = gerr end

    if ML.Log then
        ML.Log("Inspect %s (%s/%d): ilvl=%s hero=%s talents=%s%s",
            tostring(rec.name), tostring(classFile), rec.specID,
            tostring(rec.itemLevel), (hero and hero.name) or "nil",
            tostring(gcount), gerr and (" err=" .. tostring(gerr)) or "")
    end

    local prof = Cap and Cap.Get and Cap.Get(rec.specID, ROLE_MAP[rec.role], classFile)
    local d = prof and prof.dispel
    if not d or d.profile == "NONE" or not d.spellID then rec.noTool = true; return rec end
    rec.dispelName, rec.dispelSpellID, rec.profile = d.spellName, d.spellID, d.profile
    rec.talentGated = d.talentDependent and true or false
    if not rec.talentGated then rec.hasTool = true; return rec end      -- baseline: always present

    rec.talentRead = gcount
    if gerr then return rec end                                        -- hasTool stays nil (unknown)
    rec.hasTool = granted[rec.dispelSpellID] and true or false
    return rec
end

-- Metadata suffix (ilvl / hero tree / talent count) - the class+spec+ilvl+hero-tree data we save.
local function metaSuffix(rec)
    return string.format(" {ilvl=%s hero=%s talents=%s}",
        tostring(rec.itemLevel), (rec.heroTree and rec.heroTree.name) or "nil", tostring(rec.talentCount))
end

-- A single crisp, plain-text (copy-friendly) line for a record.
local function formatLine(rec)
    local tag = "[" .. rec.unit .. "] " .. rec.name
    if rec.specUnknown then return tag .. ": spec=UNKNOWN (inspect failed / out of range)" end
    local who = string.format("%s (%s/%s %d, %s)", tag, rec.classFile or "?", rec.specName, rec.specID, rec.role)
    local meta = metaSuffix(rec)
    if rec.noTool then return who .. ": dispel=none -> N/A (no tool)" .. meta end
    local base = string.format("%s: %s (%d) [%s]", who, rec.dispelName or "?", rec.dispelSpellID, rec.profile)
    if not rec.talentGated then return base .. " baseline -> expect dispels" .. meta end
    if rec.readErr then return base .. " talent-gated inspect=FAIL(" .. rec.readErr .. ") -> UNKNOWN (score neutral)" .. meta end
    return string.format("%s talent-gated inspect=OK read=%d hasTalent=%s -> %s%s",
        base, rec.talentRead or 0, rec.hasTool and "YES" or "NO",
        rec.hasTool and "expect dispels" or "N/A (not talented)", meta)
end

----------------------------------------------------------------------
-- Async queue: NotifyInspect is one-at-a-time; INSPECT_READY is async, so we walk the group serially.
-- Inspect.Eval collects an evalUnit record per member, then calls onDone(records).
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
local state

local function finish()
    if state.timer then state.timer:Cancel(); state.timer = nil end
    ev:UnregisterAllEvents()
    if ClearInspectPlayer then ClearInspectPlayer() end
    state.running = false
    local onDone = state.onDone
    if onDone then pcall(onDone, state.recs) end
end

local function collect(unit)
    local rec = evalUnit(unit)
    state.recs[#state.recs + 1] = rec
    if state.onRec then pcall(state.onRec, rec) end
end

local function stepNext()
    state.idx = state.idx + 1
    if state.idx > #state.queue then return finish() end
    local unit = state.queue[state.idx]
    if unit == "player" then collect("player"); return stepNext() end   -- self: read directly
    if not (UnitExists(unit) and CanInspect and CanInspect(unit)) then
        state.recs[#state.recs + 1] = { unit = unit, name = UnitName(unit) or unit, guid = UnitGUID(unit),
                                        specUnknown = true }
        if state.onRec then pcall(state.onRec, state.recs[#state.recs]) end
        return stepNext()
    end
    NotifyInspect(unit)
    state.timer = C_Timer.NewTimer(2.5, function()   -- inspect never landed
        state.timer = nil
        state.recs[#state.recs + 1] = { unit = unit, name = UnitName(unit) or unit, guid = UnitGUID(unit),
                                        specUnknown = true }
        if state.onRec then pcall(state.onRec, state.recs[#state.recs]) end
        stepNext()
    end)
end

ev:SetScript("OnEvent", function(_, event, guid)
    if event ~= "INSPECT_READY" or not (state and state.running) then return end
    local unit = state.queue[state.idx]
    if not unit or UnitGUID(unit) ~= guid then return end   -- stale/other reply
    if state.timer then state.timer:Cancel(); state.timer = nil end
    collect(unit)
    if ClearInspectPlayer then ClearInspectPlayer() end
    stepNext()
end)

-- Core: inspect the group, collect a record per member. opts = { onRec=fn(rec), onDone=fn(records) }.
-- Returns false if a run is already in progress. Async.
function Inspect.Eval(opts)
    opts = opts or {}
    if state and state.running then return false end
    local queue = { "player" }
    for i = 1, 4 do local u = "party" .. i; if UnitExists(u) then queue[#queue + 1] = u end end
    state = { queue = queue, idx = 0, recs = {}, running = true, timer = nil,
              onRec = opts.onRec, onDone = opts.onDone }
    ev:UnregisterAllEvents()
    ev:RegisterEvent("INSPECT_READY")
    stepNext()
    return true
end

-- Text report. opts = { onLine=fn(line), onDone=fn(fullReport) }.
function Inspect.Run(opts)
    opts = opts or {}
    return Inspect.Eval({
        onRec = opts.onLine and function(rec) pcall(opts.onLine, formatLine(rec)) end or nil,
        onDone = function(recs)
            local lines = {}
            for _, r in ipairs(recs) do lines[#lines + 1] = formatLine(r) end
            local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("TAP_MythicLedger", "Version")) or "?"
            local header = string.format("== Mythic Ledger group inspect ==  client=%s ML=%s units=%d",
                tostring(select(4, GetBuildInfo())), ver, #recs)
            if opts.onDone then pcall(opts.onDone, header .. "\n" .. table.concat(lines, "\n")) end
        end,
    })
end

-- Data capture for the scorer + future calibration: onDone(map) where
--   map[guid] = { hasTool, specID, itemLevel, heroTree = {id,name}, talents = {ids...}, talentCount }.
-- heroTree/talents are metadata (not read by scoring yet) - they let us bucket expectations by
-- class+spec+ilvl+hero-tree once we have enough samples.
function Inspect.CaptureGroup(onDone)
    return Inspect.Eval({ onDone = function(recs)
        local map = {}
        for _, r in ipairs(recs) do
            if r.guid then
                map[r.guid] = { hasTool = r.hasTool, specID = r.specID, itemLevel = r.itemLevel,
                                heroTree = r.heroTree, talents = r.talents, talentCount = r.talentCount }
            end
        end
        if onDone then pcall(onDone, map) end
    end })
end
