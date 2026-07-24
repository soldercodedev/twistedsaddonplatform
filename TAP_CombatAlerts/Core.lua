-- Twisteds Combat Alerts (TCC)
-- Rule-based audible/visual cue engine.
-- A rule = a nested tree of conditions (AND/OR groups) + an action (sound/visual/chat).
-- Author: Twistedfury-Zul'jin  |  Version: 1.2.0-beta.3
local addonName, TCC = ...

local PREFIX = "|cff33ff99Twisteds Combat Alerts:|r "
TCC.PREFIX = PREFIX

-- Midnight (12.0) "secret values": some combat/unit/measurement APIs (UnitInRange,
-- IsSpellInRange, threat, GetVerticalScrollRange when the scroll content shows secrets,
-- ...) return values that tainted (addon) code may STORE and PASS but may not COMPARE or
-- do arithmetic on -- doing so throws "attempt to compare ... a secret value". Blizzard
-- ships canaccessvalue()/issecretvalue() to test first (calling them on a secret is
-- allowed). These globals don't exist pre-12.0, where every value is readable.
-- TCC.CanRead(v) -> true when it is safe to compare / do math on v right now.
local _canaccessvalue, _issecretvalue = canaccessvalue, issecretvalue
function TCC.CanRead(v)
    -- Prefer issecretvalue: our gate is precisely "is v secret?". canaccessvalue asks a
    -- stricter "do I have permission to operate on it", which can read false for plain
    -- nil / edge cases that are not actually secret, causing false "protected".
    if _issecretvalue then
        local ok, res = pcall(_issecretvalue, v)
        if ok then return not res end
    end
    if _canaccessvalue then
        local ok, res = pcall(_canaccessvalue, v)
        if ok then return res and true or false end
    end
    return true   -- pre-12.0 client (or guards unavailable): nothing is secret
end

-- UnitDistanceSquared is CENTER-to-center; the game's operational/spell ranges are
-- EDGE-to-edge (each unit's ~1.5yd combat reach is subtracted). Pad range thresholds by
-- both reaches (~3yd) so our "40yd" matches what UnitInRange / a 40yd spell actually
-- reach -- a unit at ~43yd center distance is in true 40yd range. Empirically 2.75yd
-- matches the game's operational range best (measured in-game against the real flip point).
TCC.RANGE_REACH_PAD = 2.75

-- Distance to a unit in yards, or nil if it can't be determined right now.
-- UnitDistanceSquared stays READABLE in most instanced content where UnitInRange goes
-- secret, and gives an exact distance -- so range checks keep working (and get better).
function TCC.UnitDistanceYards(unit)
    if UnitDistanceSquared then
        local d2 = UnitDistanceSquared(unit)
        if TCC.CanRead(d2) and type(d2) == "number" and d2 >= 0 then
            return math.sqrt(d2)
        end
    end
    return nil
end

-- NOTE: rule-visual font resolution (TCC.ResolveFont) is provided by TCCShared.lua, which loads
-- after this file and routes to the suite's shared font catalog. (The old local FONTS table +
-- ResolveFont/FontLabel lived here but were shadowed by that override, so they were removed.)

----------------------------------------------------------------------
-- Defaults (global, non-rule settings) and default rule set
----------------------------------------------------------------------
-- Global (non-rule) profile settings. The old standalone UI's own window/minimap/accent and the
-- Focus-Tools "macro" block used to live here too; those features moved to the suite chrome and the
-- Focus Target Interrupt module, so their seeds were removed (CopyDefaults only ADDS missing keys,
-- so dropping them just stops seeding dead fields - saved data and the legacy migration are untouched).
local DEFAULTS = {
    enabled     = true,
    channel     = "Master",
    pollInterval = 0.25,      -- how often polling conditions are re-checked (sec)
}

-- Default action template used when creating brand-new rules.
-- Sound / text / icon all start OFF so a new alert is silent until the user opts in.
function TCC.NewAction()
    return {
        playSound   = false,
        soundKey    = "RAID_WARNING",
        cooldown    = 3,
        loopSound   = false,
        loopInterval = 1.5,
        debounce    = 0,        -- grace period: hold conditions N sec before firing
        chatMessage = false,
        chatText    = "",
        chatChannel = "SELF",   -- SELF prints to your own frame; others use SendChatMessage
        visual      = false,
        visualText  = "ALERT",
        pulse       = true,
        color       = { 1, 0.1, 0.1 },
        font        = "UBUNTU",
        fontSize    = 48,
        posPoint    = "CENTER",
        posX        = 0,
        posY        = 150,
        showIcon    = false,
        icon        = "",     -- fileID, "Interface\\ICONS\\name", or a bare icon name
        iconSize    = 40,
        iconX       = 0,      -- icon offset from the text center
        iconY       = 64,
    }
end

-- Resolves an icon value (fileID, full path, or bare icon name) for SetTexture.
function TCC.ResolveIcon(v)
    if type(v) == "number" then return v end
    if type(v) == "string" and v ~= "" then
        if v:find("\\") then return v end
        local n = tonumber(v); if n then return n end
        return "Interface\\ICONS\\" .. v
    end
    return nil
end

-- New profiles / resets start with no rules; the user builds their own.
local function DefaultRules()
    return {}
end

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------
local db
local ruleState = {}  -- [ruleId] = { active = bool, lastWarn = number, loop = ticker }

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Unique-ish id for new rules (GetTime + counter; safe within a session).
local idCounter = 0
function TCC.NewRuleId()
    idCounter = idCounter + 1
    return string.format("rule-%d-%d", math.floor(GetTime() * 100), idCounter)
end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local n = {}
    for k, v in pairs(t) do n[k] = deepcopy(v) end
    return n
end

----------------------------------------------------------------------
-- Profiles (all stored account-wide so any character can copy to/from any
-- other character's profile).
--
--   TAP_CombatAlertsDB.profiles[name] = full settings table (incl. rules)
--   TAP_CombatAlertsDB.charChoice[charKey] = which profile that char uses
--
-- The special "Account" profile is the shared one. A character profile is
-- keyed by "Name-Realm".
----------------------------------------------------------------------
local ACCOUNT_KEY = "Account"

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function EnsureProfile(name)
    local root = TAP_CombatAlertsDB
    root.profiles = root.profiles or {}
    local p = root.profiles[name]
    if type(p) ~= "table" then p = {}; root.profiles[name] = p end
    CopyDefaults(DEFAULTS, p)
    if type(p.rules) ~= "table" then p.rules = DefaultRules() end
    -- Migrate legacy flat rules (conditions + match) to a nested condition tree.
    if TCC.EnsureRuleTree then
        for _, r in ipairs(p.rules) do TCC.EnsureRuleTree(r) end
    end
    return p
end

local function ActiveProfileName()
    local root = TAP_CombatAlertsDB
    root.charChoice = root.charChoice or {}
    return root.charChoice[charKey()] or ACCOUNT_KEY
end

local function SelectActive()
    local name = ActiveProfileName()
    db = EnsureProfile(name)
    TCC.db = db
    TCC.activeProfile = name
    TCC.useCharacter = (name ~= ACCOUNT_KEY)
    TCC.selectedRuleId = db.rules[1] and db.rules[1].id or nil
end

function TCC.CurrentCharKey() return charKey() end
function TCC.AccountKey() return ACCOUNT_KEY end

-- Friendly label for a profile name.
function TCC.ProfileLabel(name)
    if name == ACCOUNT_KEY then return "Account-wide (shared)" end
    if name == charKey() then return name .. " (this character)" end
    return name
end

-- Existing profile names: Account first, then characters alphabetically.
function TCC.ListProfiles()
    local root = TAP_CombatAlertsDB
    root.profiles = root.profiles or {}
    local names = {}
    for name in pairs(root.profiles) do
        if name ~= ACCOUNT_KEY then names[#names + 1] = name end
    end
    table.sort(names)
    table.insert(names, 1, ACCOUNT_KEY)
    return names
end

-- Point this character at any existing (or newly created) profile and make it live.
function TCC.SetActiveProfile(name)
    if not name or name == "" then return end
    for _, st in pairs(ruleState) do
        if st.loop then st.loop:Cancel(); st.loop = nil end
    end
    wipe(ruleState)
    local root = TAP_CombatAlertsDB
    root.charChoice = root.charChoice or {}
    EnsureProfile(name)
    root.charChoice[charKey()] = name
    SelectActive()
    TCC.ApplySettings()
    if TCC.RefreshOptions then TCC.RefreshOptions() end
    print(PREFIX .. "Alerts profile: |cff33ff33" .. TCC.ProfileLabel(TCC.activeProfile) .. "|r")
end

-- Create a new named profile (seeded by EnsureProfile). `activate` switches this character to it.
-- Returns the name on success, or nil + reason ("empty" / "reserved" / "exists").
function TCC.CreateProfile(name, activate)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return nil, "empty" end
    if name == ACCOUNT_KEY then return nil, "reserved" end
    local root = TAP_CombatAlertsDB
    root.profiles = root.profiles or {}
    if root.profiles[name] then return nil, "exists" end
    EnsureProfile(name)
    if activate then TCC.SetActiveProfile(name)
    elseif TCC.RefreshOptions then TCC.RefreshOptions() end
    return name
end

-- Rename a profile (the Account profile can't be renamed). Repoints any character using it.
-- Returns the new name, or nil + reason.
function TCC.RenameProfile(oldName, newName)
    newName = newName and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if not oldName or oldName == ACCOUNT_KEY then return nil, "reserved" end
    if newName == "" or newName == ACCOUNT_KEY then return nil, "invalid" end
    local root = TAP_CombatAlertsDB
    if not (root.profiles and root.profiles[oldName]) then return nil, "missing" end
    if root.profiles[newName] then return nil, "exists" end
    root.profiles[newName], root.profiles[oldName] = root.profiles[oldName], nil
    root.charChoice = root.charChoice or {}
    for ck, pn in pairs(root.charChoice) do if pn == oldName then root.charChoice[ck] = newName end end
    SelectActive()
    TCC.ApplySettings()
    if TCC.RefreshOptions then TCC.RefreshOptions() end
    return newName
end

-- Delete a profile (the Account profile can't be deleted). Any character using it falls back to
-- Account-wide. Returns true, or nil + reason.
function TCC.DeleteProfile(name)
    if not name or name == ACCOUNT_KEY then return nil, "reserved" end
    local root = TAP_CombatAlertsDB
    if not (root.profiles and root.profiles[name]) then return nil, "missing" end
    root.profiles[name] = nil
    root.charChoice = root.charChoice or {}
    for ck, pn in pairs(root.charChoice) do if pn == name then root.charChoice[ck] = ACCOUNT_KEY end end
    SelectActive()
    TCC.ApplySettings()
    if TCC.RefreshOptions then TCC.RefreshOptions() end
    return true
end

-- Rules in a profile, for the copy UI ({id, name}).
function TCC.GetProfileRuleList(profileName)
    local root = TAP_CombatAlertsDB
    local p = root.profiles and root.profiles[profileName]
    local list = {}
    if p and p.rules then
        for _, r in ipairs(p.rules) do list[#list + 1] = { id = r.id, name = r.name } end
    end
    return list
end

-- Copy from one profile to another (deep copy). ruleId == "__all__" (or nil)
-- replaces the destination's rules; a specific ruleId appends just that rule.
function TCC.CopyProfileRules(fromName, toName, ruleId)
    if not fromName or not toName then
        print(PREFIX .. "Pick source and destination profiles.")
        return
    end
    local root = TAP_CombatAlertsDB
    local src = root.profiles and root.profiles[fromName]
    if not src then
        print(PREFIX .. "Source profile not found.")
        return
    end
    local dst = EnsureProfile(toName)

    if ruleId and ruleId ~= "__all__" then
        for _, r in ipairs(src.rules or {}) do
            if r.id == ruleId then
                local c = deepcopy(r); c.id = TCC.NewRuleId()
                table.insert(dst.rules, c)
                if dst == db then TCC.selectedRuleId = c.id end
                TCC.ApplySettings()
                if TCC.RefreshOptions then TCC.RefreshOptions() end
                print(PREFIX .. "Copied alert '" .. (c.name or "?") .. "' to " .. TCC.ProfileLabel(toName) .. ".")
                return
            end
        end
        print(PREFIX .. "Alert not found in the source profile.")
        return
    end

    if fromName == toName then
        print(PREFIX .. "Pick two different profiles to copy all alerts between.")
        return
    end
    dst.rules = deepcopy(src.rules or {})
    if dst == db then TCC.selectedRuleId = db.rules[1] and db.rules[1].id or nil end
    TCC.ApplySettings()
    if TCC.RefreshOptions then TCC.RefreshOptions() end
    print(PREFIX .. string.format("Copied all %d alert(s): %s -> %s",
        #dst.rules, TCC.ProfileLabel(fromName), TCC.ProfileLabel(toName)))
end

----------------------------------------------------------------------
-- Export / import (rule sharing via strings)
--
-- Serialize a rule (or all rules) to a Lua table literal, base64-encode it, and
-- tag it. Import decodes, parses in a sandbox (no globals), and validates.
----------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(data)
    local out, bytes = {}, { data:byte(1, #data) }
    for i = 1, #bytes, 3 do
        local b1, b2, b3 = bytes[i], bytes[i + 1], bytes[i + 2]
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b2 and B64:sub(c3 + 1, c3 + 1) or "=")
            .. (b3 and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function b64decode(data)
    data = data:gsub("[^" .. "A-Za-z0-9+/" .. "]", "")
    local rev = {}
    for i = 1, #B64 do rev[B64:sub(i, i)] = i - 1 end
    local out = {}
    for i = 1, #data, 4 do
        local c1 = rev[data:sub(i, i)] or 0
        local c2 = rev[data:sub(i + 1, i + 1)] or 0
        local c3d = data:sub(i + 2, i + 2)
        local c4d = data:sub(i + 3, i + 3)
        local c3 = rev[c3d] or 0
        local c4 = rev[c4d] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if c3d ~= "=" and c3d ~= "" then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if c4d ~= "=" and c4d ~= "" then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

local function serialize(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v)
    elseif t == "number" then return tostring(v)
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            local key
            if type(k) == "number" then key = "[" .. k .. "]"
            else key = "[" .. string.format("%q", k) .. "]" end
            parts[#parts + 1] = key .. "=" .. serialize(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local function ruleForExport(rule)
    local c = deepcopy(rule)
    c.id = nil  -- importer assigns a fresh id
    return c
end

function TCC.ExportRule(rule)
    if not rule then return nil end
    return "TCC1!" .. b64encode("return " .. serialize(ruleForExport(rule)))
end

function TCC.ExportAll()
    local list = {}
    for _, r in ipairs(db.rules) do list[#list + 1] = ruleForExport(r) end
    return "TCCX1!" .. b64encode("return " .. serialize({ rules = list }))
end

-- Recursively sanitize a condition node (group or single condition).
local function sanitizeNode(node, depth)
    if type(node) ~= "table" or depth > 10 then return nil end
    if type(node.children) == "table" then
        local g = { op = (node.op == "ANY") and "ANY" or "ALL", children = {} }
        for _, ch in ipairs(node.children) do
            local sc = sanitizeNode(ch, depth + 1)
            if sc then g.children[#g.children + 1] = sc end
        end
        return g
    end
    if type(node.type) == "string" then return node end  -- a condition (plain data)
    return nil
end

-- Sanitize an imported rule table into a safe, complete rule. Accepts type-based
-- alerts (kind + trigger + load) and the tree/legacy shapes.
local function sanitizeRule(rc)
    if type(rc) ~= "table" then return nil end
    local clean = {
        id = TCC.NewRuleId(),
        name = tostring(rc.name or "Imported alert"),
        enabled = rc.enabled and true or false,
        action = TCC.NewAction(),
    }
    if rc.kind and TCC.GetAlertKind and TCC.GetAlertKind(rc.kind)
        and type(rc.trigger) == "table" and type(rc.trigger.type) == "string" then
        clean.kind = rc.kind
        clean.trigger = rc.trigger                       -- plain data (validated by type)
        clean.load = (type(rc.load) == "table") and rc.load or {}
    else
        local rootSrc = rc.root
        if type(rootSrc) ~= "table" then
            if type(rc.conditions) ~= "table" then return nil end
            rootSrc = { op = (rc.match == "ANY") and "ANY" or "ALL", children = rc.conditions }
        end
        clean.root = sanitizeNode(rootSrc, 0) or { op = "ALL", children = {} }
    end
    if type(rc.action) == "table" then
        for k, v in pairs(rc.action) do clean.action[k] = v end
    end
    return clean
end

-- Returns success, count-or-errorMessage.
function TCC.Import(str)
    str = (str or ""):gsub("%s+", "")
    local payload = str:match("^TCCX?1!(.+)$")
    if not payload then return false, "Unrecognized string (expected a TCC export)." end
    local ok, raw = pcall(b64decode, payload)
    if not ok or not raw or raw == "" then return false, "Could not decode the string." end
    local fn = (loadstring or load)(raw)
    if not fn then return false, "Could not parse the data." end
    if setfenv then setfenv(fn, {}) end  -- sandbox: no access to globals
    local ok2, data = pcall(fn)
    if not ok2 or type(data) ~= "table" then return false, "Invalid content." end

    local added = 0
    local function tryAdd(rc)
        local clean = sanitizeRule(rc)
        if clean then table.insert(db.rules, clean); added = added + 1 end
    end
    if type(data.rules) == "table" then
        for _, rc in ipairs(data.rules) do tryAdd(rc) end
    else
        tryAdd(data)
    end
    if added == 0 then return false, "No valid alerts found in the string." end
    TCC.selectedRuleId = db.rules[#db.rules].id
    TCC.ApplySettings()
    return true, added
end

----------------------------------------------------------------------
-- Visual warning frames - one per rule, so multiple alerts show at once.
----------------------------------------------------------------------
local visuals = {}      -- ruleId -> frame (active/assigned)
local freeVisuals = {}  -- reusable frames from deleted/pruned rules (WoW never GCs frames, so recycle them)
local flashFrame        -- rule-less test flash (/tap alerts test)

-- Positions a visual frame using a rule action's per-rule placement.
local function PositionVisual(f, a)
    a = a or {}
    f:ClearAllPoints()
    f:SetPoint(a.posPoint or "CENTER", UIParent, a.posPoint or "CENTER", a.posX or 0, a.posY or 150)
end

-- Build one visual frame. On drag-stop it saves the new position to its own rule
-- (f._rule), so many frames can be dragged independently in reposition mode.
local function makeVisualFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(700, 120); f:SetFrameStrata("HIGH")
    f:EnableMouse(false); f:SetMouseClickEnabled(false); f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.1, 0.5, 0.95, 0.15); bg:Hide(); f.moverBg = bg
    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont(TCC.ResolveFont(nil), 12)   -- themed UI font (follows the global font choice)
    hint:SetPoint("TOP", f, "BOTTOM", 0, -2); hint:SetTextColor(0.4, 0.7, 1); hint:Hide(); f.moverHint = hint

    -- Small identifier shown above each ghost while repositioning, so it's clear
    -- which alert is which (its icon + name).
    local idName = f:CreateFontString(nil, "OVERLAY")
    idName:SetFont(TCC.ResolveFont(nil), 13)
    idName:SetPoint("BOTTOM", f, "TOP", 10, 4); idName:SetTextColor(0.55, 0.8, 1); idName:Hide(); f.moverLabel = idName
    local idIcon = f:CreateTexture(nil, "OVERLAY")
    idIcon:SetSize(20, 20); idIcon:SetPoint("RIGHT", idName, "LEFT", -6, 0); idIcon:SetTexCoord(0, 1, 0, 1); idIcon:Hide(); f.moverIcon = idIcon

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 48, "THICKOUTLINE")
    text:SetPoint("CENTER"); text:SetTextColor(1, 0.1, 0.1, 1); f.text = text

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("BOTTOM", text, "TOP", 0, 8); icon:SetSize(40, 40); icon:Hide(); f.icon = icon

    local ag = text:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(1); a1:SetToAlpha(0.25); a1:SetDuration(0.5); a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.25); a2:SetToAlpha(1); a2:SetDuration(0.5); a2:SetOrder(2)
    ag:SetLooping("REPEAT"); f.pulse = ag

    f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if self.moving then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux and self._rule then
            local a = self._rule.action
            a.posPoint = "CENTER"; a.posX = cx - ux; a.posY = cy - uy
            PositionVisual(self, a)
        end
    end)
    return f
end

local function getVisual(rule)
    local f = visuals[rule.id]
    if not f then f = table.remove(freeVisuals) or makeVisualFrame(); visuals[rule.id] = f end
    f._rule = rule
    return f
end

-- Return a rule's visual frame to the free pool (hidden) so a later rule reuses it instead of
-- stranding it forever. Called when a rule is deleted or pruned; applyVisual re-skins it on reuse.
local function releaseVisual(id)
    local f = visuals[id]
    if not f then return end
    f:Hide(); f._rule = nil
    visuals[id] = nil
    freeVisuals[#freeVisuals + 1] = f
end

-- Applies a rule action's text + icon to the visual frame (no show/position).
local function applyVisual(f, a)
    if a.visual then
        f.text:Show()
        f.text:SetText((a.visualText and a.visualText ~= "" and a.visualText) or "!")
        local c = a.color or { 1, 0.1, 0.1 }
        f.text:SetTextColor(c[1] or 1, c[2] or 0.1, c[3] or 0.1, 1)
        f.text:SetFont(TCC.ResolveFont(a.font), a.fontSize or 48, "THICKOUTLINE")
        if a.pulse then
            if not f.pulse:IsPlaying() then f.pulse:Play() end
        else
            f.pulse:Stop(); f.text:SetAlpha(1)
        end
    else
        f.pulse:Stop(); f.text:SetText(""); f.text:Hide()
    end
    local tex = a.showIcon and TCC.ResolveIcon(a.icon)
    if tex then
        f.icon:SetTexture(tex); f.icon:SetSize(a.iconSize or 40, a.iconSize or 40)
        f.icon:ClearAllPoints(); f.icon:SetPoint("CENTER", f.text, "CENTER", a.iconX or 0, a.iconY or 64)
        f.icon:Show()
    else
        f.icon:Hide()
    end
end

-- Show / hide one rule's live visual (engine-driven).
local function showRuleVisual(rule)
    local f = getVisual(rule)
    applyVisual(f, rule.action)
    PositionVisual(f, rule.action)
    f:Show()
end
local function hideRuleVisual(id)
    local f = visuals[id]
    if f then f.pulse:Stop(); f.text:SetAlpha(1); f:Hide() end
end

-- Briefly flash a rule-less cue (used by /tap alerts test).
function TCC.FlashVisual(text, seconds)
    flashFrame = flashFrame or makeVisualFrame()
    applyVisual(flashFrame, { visualText = text or "TEST", visual = true, pulse = true, color = { 1, 0.82, 0.2 }, font        = "UBUNTU", fontSize = 48 })
    PositionVisual(flashFrame, {})
    flashFrame:Show()
    C_Timer.After(seconds or 1.5, function()
        if flashFrame then flashFrame.pulse:Stop(); flashFrame.text:SetAlpha(1); flashFrame:Hide() end
    end)
end

-- Fire a rule action's sound / chat (shared by the live engine and the tester).
-- Both are wrapped so a blocked action (e.g. SendChatMessage restricted inside an
-- active Mythic+/instance) can never abort the evaluation pass.
local function fireSound(a)
    if a.playSound then pcall(TCC.PlayKey, a.soundKey, db.channel) end
end
local function fireChat(a, ruleName)
    if a.chatMessage then
        -- Send the user's own text (no addon prefix) to the chosen channel.
        local text = (a.chatText and a.chatText ~= "" and a.chatText) or ruleName or "Cue"
        local chan = a.chatChannel or "SELF"
        if chan == "SELF" then print(text) else pcall(SendChatMessage, text, chan) end
    end
end

----------------------------------------------------------------------
-- Test mode: hide the manager and fire the cue exactly as it would live
-- (sound + chat + loop + visual/icon), with a "Stop Test" button.
----------------------------------------------------------------------
local testLoop

function TCC.StartTest(rule)
    if not rule then return end
    local a = rule.action
    TCC.testActive = true

    local f = getVisual(rule)
    applyVisual(f, a)
    PositionVisual(f, a)
    f:Show()
    TCC._testRuleId = rule.id

    fireSound(a)
    fireChat(a, rule.name)
    if testLoop then testLoop:Cancel(); testLoop = nil end
    if a.loopSound and a.playSound then
        local interval = tonumber(a.loopInterval) or 1.5
        if interval < 0.5 then interval = 0.5 end
        testLoop = C_Timer.NewTicker(interval, function()
            if TCC.testActive then fireSound(a) end
        end)
    end

    if TCC.ShowTestControls then TCC.ShowTestControls(rule.name, function() TCC.StopTest() end) end
end

function TCC.StopTest()
    if not TCC.testActive then return end
    TCC.testActive = false
    if testLoop then testLoop:Cancel(); testLoop = nil end
    if TCC.HideTestControls then TCC.HideTestControls() end
    if TCC._testRuleId then hideRuleVisual(TCC._testRuleId); TCC._testRuleId = nil end
    TCC.Evaluate()
    if TCC.OpenManager then TCC.OpenManager() end
end

----------------------------------------------------------------------
-- Position mover: drag one alert's text/icon, or ALL of them at once.
-- Positions save live on drag-stop; Cancel restores the backups.
-- The Save/Cancel bar is drawn by the UI (themed) via TCC.ShowMoverControls.
----------------------------------------------------------------------
local function startMover(rules, msg)
    if not rules or #rules == 0 then
        print(PREFIX .. "No alerts show on-screen text or an icon yet - enable |cffffff00Text|r or |cffffff00Icon|r on an alert first.")
        if TCC.OpenManager then TCC.OpenManager() end
        return
    end
    if TCC.HideManager then TCC.HideManager() end
    TCC.moverActive = true
    TCC._moverRules = rules
    TCC._moverBackup = {}
    local anchor
    for _, rule in ipairs(rules) do
        local a = rule.action
        TCC._moverBackup[rule.id] = { a.posPoint or "CENTER", a.posX or 0, a.posY or 150 }
        local f = getVisual(rule)
        applyVisual(f, a)
        -- Ensure something is draggable even for an icon-only / textless rule.
        if not a.visual then f.text:Show(); f.text:SetText((a.visualText and a.visualText ~= "" and a.visualText) or rule.name or "DRAG") end
        f.pulse:Stop(); f.text:SetAlpha(1)
        PositionVisual(f, a)
        -- Identify each ghost by the alert's name + icon.
        if f.moverLabel then f.moverLabel:SetText(rule.name or "Alert"); f.moverLabel:Show() end
        if f.moverIcon then f.moverIcon:Hide() end   -- drag ghost is name-labelled, no per-rule icon
        f.moving = true; f:EnableMouse(true); f.moverBg:Show(); f.moverHint:Show(); f:Show()
        anchor = anchor or f
    end
    -- Anchor the Save/Cancel bar under the single frame, or at a fixed spot for many.
    local barAnchor = (#rules == 1) and anchor or nil
    if TCC.ShowMoverControls then
        TCC.ShowMoverControls(barAnchor, function() TCC.StopMover(true) end, function() TCC.StopMover(false) end)
    end
    print(PREFIX .. (msg or "Drag each alert into place, then Save Positions."))
end

-- Move just one rule (the editor's "Move on screen" button).
function TCC.StartRuleMover(rule)
    if not rule then return end
    startMover({ rule }, "Drag the |cffffff00" .. (rule.name or "cue") .. "|r into place, then Save.")
end

-- Move every alert that uses on-screen text or an icon (/tap alerts move, sidebar button).
function TCC.StartPositionMode()
    if not db then return end
    local rules = {}
    for _, rule in ipairs(db.rules) do
        if rule.action and (rule.action.visual or rule.action.showIcon) then rules[#rules + 1] = rule end
    end
    startMover(rules, "Drag each alert's text/icon into place, then Save Positions.")
end

function TCC.StopMover(save)
    if not TCC.moverActive then return end
    if not save and TCC._moverBackup then
        for _, rule in ipairs(db.rules) do
            local b = TCC._moverBackup[rule.id]
            if b then rule.action.posPoint, rule.action.posX, rule.action.posY = b[1], b[2], b[3] end
        end
    end
    local rules = TCC._moverRules
    TCC.moverActive = false; TCC._moverRules = nil; TCC._moverBackup = nil
    if rules then
        for _, rule in ipairs(rules) do
            local f = visuals[rule.id]
            if f then
                f.moving = false; f:EnableMouse(false); f.moverBg:Hide(); f.moverHint:Hide()
                if f.moverLabel then f.moverLabel:Hide() end
                if f.moverIcon then f.moverIcon:Hide() end
            end
        end
    end
    if TCC.HideMoverControls then TCC.HideMoverControls() end
    TCC.Evaluate()
    if TCC.OpenManager then TCC.OpenManager() end
    print(PREFIX .. (save and "Positions saved." or "Move cancelled."))
end

----------------------------------------------------------------------
-- Rule action firing
----------------------------------------------------------------------
local function StopRuleLoop(st)
    if st.loop then
        st.loop:Cancel()
        st.loop = nil
    end
end

local function StartRuleLoop(rule, st)
    if st.loop then return end
    local a = rule.action
    local interval = tonumber(a.loopInterval) or 1.5
    if interval < 0.5 then interval = 0.5 end
    st.loop = C_Timer.NewTicker(interval, function()
        if st.active and db.enabled and a.playSound then
            TCC.PlayKey(a.soundKey, db.channel)
        end
    end)
end

-- Fired once when a rule transitions from inactive -> active.
local function FireRule(rule, st)
    local a = rule.action
    local now = GetTime()
    if (now - (st.lastWarn or 0)) >= (tonumber(a.cooldown) or 0) then
        st.lastWarn = now
        fireSound(a)
        fireChat(a, rule.name)
    end
    if a.loopSound and a.playSound then
        StartRuleLoop(rule, st)
    end
end

----------------------------------------------------------------------
-- Central evaluation
--
-- Runs every rule, tracks per-rule active state so each cue fires once on
-- entry, and shows a per-rule visual for EVERY active rule that requests one
-- (multiple alerts can be on screen at the same time).
----------------------------------------------------------------------
function TCC.Evaluate()
    if not db then return end

    -- Never fight the reposition/test overlays for the visual frames.
    local touchVisuals = not (TCC.moverActive or TCC.testActive)

    if not db.enabled then
        for _, st in pairs(ruleState) do
            st.active = false
            StopRuleLoop(st)
        end
        if touchVisuals then for id in pairs(visuals) do hideRuleVisual(id) end end
        return
    end

    local shown = {}
    for _, rule in ipairs(db.rules) do
        local st = ruleState[rule.id]
        if not st then st = {}; ruleState[rule.id] = st end

        if TCC.EvaluateRule(rule) then
            if not st.active then
                -- Debounce / grace: conditions must hold continuously for N seconds
                -- before the cue actually fires.
                local grace = tonumber(rule.action.debounce) or 0
                st.trueSince = st.trueSince or GetTime()
                if (GetTime() - st.trueSince) >= grace then
                    st.active = true
                    pcall(FireRule, rule, st)  -- never let one rule's action break the pass
                end
            end
            -- Visual only shows once the rule is actually active (post-grace).
            if st.active and (rule.action.visual or rule.action.showIcon) then
                shown[rule.id] = true
            end
        else
            st.trueSince = nil
            if st.active then
                st.active = false
                StopRuleLoop(st)
            end
        end
    end

    if touchVisuals then
        for _, rule in ipairs(db.rules) do
            if shown[rule.id] then pcall(showRuleVisual, rule) end
        end
        for id in pairs(visuals) do
            if not shown[id] then hideRuleVisual(id) end
        end
    end
end

----------------------------------------------------------------------
-- Polling: only runs while an enabled rule has a condition events can't catch.
----------------------------------------------------------------------
local pollTicker

function TCC.RebuildEngine()
    if not db then return end

    -- Drop state for rules that no longer exist.
    local live = {}
    for _, r in ipairs(db.rules) do live[r.id] = true end
    for id, st in pairs(ruleState) do
        if not live[id] then
            StopRuleLoop(st)
            ruleState[id] = nil
        end
    end
    -- Recycle visual frames for rules that no longer exist (otherwise they strand + the Evaluate
    -- hide-loop keeps walking them).
    for id in pairs(visuals) do
        if not live[id] then releaseVisual(id) end
    end

    -- Start/stop the throttled poller as needed.
    local need = false
    if db.enabled then
        for _, r in ipairs(db.rules) do
            if r.enabled and TCC.RuleNeedsPolling(r) then need = true break end
        end
    end
    if need and not pollTicker then
        local interval = tonumber(db.pollInterval) or 0.25
        if interval < 0.1 then interval = 0.1 end
        pollTicker = C_Timer.NewTicker(interval, function() TCC.Evaluate() end)
    elseif not need and pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

-- Called whenever settings/rules change: refresh engine, re-evaluate, sync UI.
function TCC.ApplySettings()
    TCC.RebuildEngine()
    TCC.Evaluate()
    if TCC.RefreshManager then TCC.RefreshManager() end
end

----------------------------------------------------------------------
-- Rule management (used by the UI)
----------------------------------------------------------------------
TCC.selectedRuleId = nil

function TCC.GetRules() return db and db.rules end

-- Convert any name-based spell/buff conditions in the active profile to spell IDs.
-- Run in the open world (at login), where name lookups still work, so the rules are
-- ID-based before entering a Mythic+/instance where names are restricted.
local function upgradeNode(node)
    if node.children then
        for _, ch in ipairs(node.children) do upgradeNode(ch) end
        return
    end
    -- The range condition is the only one that carries a spell; upgrade its name to an
    -- id in the open world so it's Mythic+-safe.
    if node.type == "range" and node.spell and node.spell ~= "" and not tonumber(node.spell) then
        local id = TCC.ResolveSpell(node.spell)
        if id then node.spell = id end
    end
end

function TCC.UpgradeSpellIds()
    if not db then return end
    for _, rule in ipairs(db.rules) do
        if rule.root then upgradeNode(rule.root) end
        if rule.trigger then upgradeNode(rule.trigger) end   -- type-based range trigger
    end
end

-- Create a type-based alert (kind + single trigger + Load gates).
function TCC.NewTypedAlert(kind, triggerType)
    local meta = TCC.GetAlertKind and TCC.GetAlertKind(kind)
    if not meta then return end
    local r = {
        id = TCC.NewRuleId(),
        name = "New " .. meta.label .. " Alert",
        enabled = true,
        kind = kind,
        trigger = TCC.NewCondition(triggerType or meta.default),
        load = { combat = "any", instance = "any", group = "any" },
        action = TCC.NewAction(),
    }
    table.insert(db.rules, r)
    TCC.selectedRuleId = r.id
    TCC.ApplySettings()
    return r
end

function TCC.GetSelectedRule()
    if not db then return nil end
    for _, r in ipairs(db.rules) do
        if r.id == TCC.selectedRuleId then return r end
    end
    return nil
end

-- Create a new blank advanced alert (combat-safe: fires only in combat until the user edits it).
-- Typed one-click alerts (range/target/threat/pet/item) are created separately via TCC.NewTypedAlert
-- from the New Alert modal's kind cards.
function TCC.AddRule()
    local r = {
        id      = TCC.NewRuleId(),
        enabled = true,
        name    = "New Alert",
        action  = TCC.NewAction(),
        root    = { op = "ALL", children = { { type = "combat", op = "in" } } },
    }
    table.insert(db.rules, r)
    TCC.selectedRuleId = r.id
    TCC.ApplySettings()
    return r
end

function TCC.DuplicateSelectedRule()
    local rule = TCC.GetSelectedRule()
    if not rule then return end
    local copy = deepcopy(rule)
    copy.id = TCC.NewRuleId()
    copy.name = (rule.name or "Rule") .. " (copy)"
    -- Insert right after the original.
    for i, r in ipairs(db.rules) do
        if r.id == rule.id then table.insert(db.rules, i + 1, copy); break end
    end
    TCC.selectedRuleId = copy.id
    TCC.ApplySettings()
    return copy
end

function TCC.DeleteSelectedRule()
    local id = TCC.selectedRuleId
    for i, r in ipairs(db.rules) do
        if r.id == id then
            local st = ruleState[id]
            if st then StopRuleLoop(st); ruleState[id] = nil end
            releaseVisual(id)
            table.remove(db.rules, i)
            break
        end
    end
    TCC.selectedRuleId = db.rules[1] and db.rules[1].id or nil
    TCC.ApplySettings()
end

----------------------------------------------------------------------
-- Enable / reset / status
----------------------------------------------------------------------
function TCC.SetEnabled(on)
    db.enabled = on and true or false
    TCC.ApplySettings()
    if TCC.RefreshOptions then TCC.RefreshOptions() end
    print(PREFIX .. (db.enabled and "|cff33ff33Enabled|r" or "|cffff3333Disabled|r"))
end

function TCC.ResetSettings()
    for _, st in pairs(ruleState) do StopRuleLoop(st) end
    wipe(ruleState)
    -- Reset only the active profile (leave other profiles untouched).
    wipe(db)
    EnsureProfile(TCC.activeProfile)
    SelectActive()
    TCC.ApplySettings()
    if TCC.RefreshOptions then TCC.RefreshOptions() end
    print(PREFIX .. "Active profile reset to defaults.")
end

function TCC.PrintStatus()
    local onOff = function(v) return v and "|cff33ff33on|r" or "|cffff3333off|r" end
    print(PREFIX .. "Status")
    print("  Profile: |cffffff00" .. (TCC.useCharacter and "This character" or "Account-wide") .. "|r")
    print("  Addon: " .. onOff(db.enabled) .. "   Alerts: " .. #db.rules)
    print("  In combat: " .. onOff(UnitAffectingCombat("player")) .. "   Channel: " .. tostring(db.channel))
    for _, rule in ipairs(db.rules) do
        local st = ruleState[rule.id]
        local active = st and st.active
        print(string.format("  [%s] %s  (%s)",
            rule.enabled and "x" or " ",
            rule.name or "?",
            active and "|cffffcc00ACTIVE|r" or "idle"))
    end
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
local pendingReset = false

local function HandleSlash(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" or msg == "config" or msg == "manager" or msg == "rules" or msg == "alerts" then
        if TCC.OpenManager then TCC.OpenManager("alerts") end   -- open /tap on the Combat Alerts page
    elseif msg == "options" then
        if TCC.OpenOptions then TCC.OpenOptions() end
    elseif msg == "on" then
        TCC.SetEnabled(true)
    elseif msg == "off" then
        TCC.SetEnabled(false)
    elseif msg == "test" then
        print(PREFIX .. "Testing alert...")
        TCC.PlayKey("RAID_WARNING", db.channel)
        TCC.FlashVisual("TEST", 1.5)
    elseif msg == "move" then
        TCC.StartPositionMode()   -- reposition every on-screen alert at once
    elseif msg == "status" then
        TCC.PrintStatus()
    elseif msg == "reset" then
        pendingReset = true
        print(PREFIX .. "This resets ALL settings and alerts. Type |cffffff00/tap alerts reset confirm|r to proceed.")
    elseif msg == "reset confirm" then
        if pendingReset then
            pendingReset = false
            TCC.ResetSettings()
        else
            print(PREFIX .. "Nothing to confirm. Type |cffffff00/tap alerts reset|r first.")
        end
    else
        print(PREFIX .. "Commands (|cffffff00/tap alerts|r):")
        print("  |cffffff00/tap alerts|r - open the Alerts Manager")
        print("  |cffffff00/tap alerts options|r - global options panel")
        print("  |cffffff00/tap alerts on|r / |cffffff00/tap alerts off|r - enable/disable")
        print("  |cffffff00/tap alerts test|r - play a test alert")
        print("  |cffffff00/tap alerts move|r - reposition all on-screen alerts")
        print("  |cffffff00/tap alerts status|r - list alerts and state")
        print("  |cffffff00/tap alerts reset|r - reset everything (confirmation required)")
    end
end

-- Commands live entirely under the platform slash (/tap alerts ...), also listed on the Manager's
-- Help > Commands page.
if _G.TAP and _G.TAP.RegisterCommand then
    _G.TAP:RegisterCommand({
        cmd = "/tap alerts", desc = "Combat Alerts manager & tools", owner = "Combat Alerts",
        sub = "alerts", handler = HandleSlash,
        subcommands = {
            { "options",       "Global options panel" },
            { "on",            "Enable Combat Alerts" },
            { "off",           "Disable Combat Alerts" },
            { "test",          "Play a test alert" },
            { "move",          "Reposition all on-screen alerts" },
            { "status",        "List alerts and state" },
            { "reset",         "Reset everything (confirmation required)" },
        },
    })
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local EVENTS = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",     -- entered combat
    "PLAYER_REGEN_ENABLED",      -- left combat
    "PLAYER_TARGET_CHANGED",
    "SPELL_UPDATE_COOLDOWN",     -- spell readiness
    "SPELL_UPDATE_USABLE",
    "ZONE_CHANGED_NEW_AREA",     -- instance type
    "GROUP_ROSTER_UPDATE",       -- group / raid conditions
    "PLAYER_SPECIALIZATION_CHANGED",  -- class/spec conditions
    "UNIT_THREAT_LIST_UPDATE",   -- threat condition
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_PET",                  -- pet summoned / dismissed
}
for _, e in ipairs(EVENTS) do eventFrame:RegisterEvent(e) end
-- Unit-filtered (cheap): only fire for the relevant unit.
eventFrame:RegisterUnitEvent("UNIT_HEALTH", "target", "pet")  -- target dying / pet death
eventFrame:RegisterUnitEvent("UNIT_FLAGS", "target")    -- target attackability

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            TAP_CombatAlertsDB = TAP_CombatAlertsDB or {}
            local root = TAP_CombatAlertsDB
            -- Migrate legacy layout (top-level settings/rules) into profiles.Account.
            if type(root.profiles) ~= "table" then
                root.profiles = {}
                if type(root.rules) == "table" then
                    local acct = { rules = deepcopy(root.rules) }
                    for _, k in ipairs({ "enabled", "channel", "visualScale", "visualPoint",
                        "visualX", "visualY", "accentColor", "windowScale", "windowPos" }) do
                        acct[k] = root[k]
                    end
                    root.profiles[ACCOUNT_KEY] = acct
                end
                root.rules = nil
            end
            root.charChoice = root.charChoice or {}
            -- Migrate a legacy per-character store, if present.
            if TAP_CombatAlertsCharDB and type(TAP_CombatAlertsCharDB.rules) == "table"
                and not root.profiles[charKey()] then
                root.profiles[charKey()] = deepcopy(TAP_CombatAlertsCharDB)
                if TAP_CombatAlertsCharDB.useCharacter then root.charChoice[charKey()] = charKey() end
            end
            SelectActive()
        end
    elseif event == "PLAYER_LOGIN" then
        if TCC.InitOptions then TCC.InitOptions() end
        if TCC.InitMinimap then TCC.InitMinimap() end
        TCC.UpgradeSpellIds()   -- name -> id while name lookups still work (open world)
        TCC.RebuildEngine()
        TCC.Evaluate()
    else
        -- Any state change re-evaluates all rules.
        TCC.Evaluate()
    end
end)
