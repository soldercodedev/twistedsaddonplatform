-- Twisteds Combat Alerts - Conditions.lua
-- Condition type metadata (for the UI), condition evaluation, and the recursive
-- rule-tree evaluation (nested AND/OR groups).
local addonName, TCC = ...
local TAP = _G.TAP

----------------------------------------------------------------------
-- Condition type metadata
--
-- param.kind: "choice" (dropdown), "text", "number", "spell", "item".
-- choice params carry {value,label} pairs. "showIf" hides a param unless another
-- param has a given value.
----------------------------------------------------------------------
TCC.CONDITION_TYPES = {
    {
        type = "combat", label = "Combat state",
        params = {
            { key = "op", kind = "choice", width = 130, default = "in",
              choices = { { "in", "In combat" }, { "out", "Out of combat" } } },
        },
    },
    {
        type = "target", label = "Target state",
        params = {
            { key = "state", kind = "choice", width = 150, default = "none",
              choices = {
                  { "none", "No target" },
                  { "exists", "Has any target" },
                  { "hostile", "Hostile & alive" },
                  { "dead", "Target is dead" },
                  { "attackable", "Attackable" },
              } },
        },
    },
    {
        type = "threat", label = "Threat (vs target)",
        params = {
            { key = "state", kind = "choice", width = 210, default = "aggro",
              choices = {
                  { "aggro", "You pulled aggro" },
                  { "high", "High threat (about to pull)" },
                  { "safe", "Not tanking (safe)" },
              } },
        },
    },
    {
        type = "range", label = "Target range",
        params = {
            { key = "spell", pre = "Spell", kind = "spell",  width = 150, default = "", hint = "Spell to range-check" },
            { key = "op",    pre = "is",    kind = "choice", width = 130, default = "out",
              choices = { { "out", "out of range" }, { "in", "in range" } } },
        },
    },
    {
        type = "pet", label = "Pet state",
        params = {
            { key = "state", kind = "choice", width = 170, default = "dead",
              choices = {
                  { "dead", "Pet is dead" },
                  { "missing", "No pet" },
                  { "alive", "Pet is alive" },
                  { "exists", "Have a pet (any)" },
              } },
        },
    },
    {
        type = "groupRange", label = "Group range",
        params = {
            { key = "role", kind = "choice", width = 120, default = "HEALER",
              choices = { { "HEALER", "Healer" }, { "TANK", "Tank" }, { "DAMAGER", "DPS" }, { "any", "Anyone" } } },
            { key = "op", kind = "choice", width = 120, default = "out",
              choices = { { "out", "Out of range" }, { "in", "In range" } } },
        },
    },
    {
        type = "itemReady", label = "Item ready",
        params = {
            { key = "item", pre = "Item", kind = "item", width = 230, default = "", hint = "Item (trinket) name or ID" },
            { key = "op",   pre = "is",   kind = "choice", width = 150, default = "ready",
              choices = { { "ready", "off cooldown (ready)" }, { "cd", "on cooldown" } } },
        },
    },
    {
        type = "instance", label = "Instance type",
        params = {
            { key = "value", kind = "choice", width = 160, default = "any",
              choices = {
                  { "any", "In any instance" },
                  { "none", "Not in an instance" },
                  { "party", "Dungeon" },
                  { "raid", "Raid" },
                  { "arena", "Arena" },
                  { "pvp", "Battleground" },
                  { "scenario", "Scenario" },
              } },
        },
    },
    {
        type = "group", label = "Group / raid",
        params = {
            { key = "state", kind = "choice", width = 170, default = "ingroup",
              choices = {
                  { "ingroup", "In a group" },
                  { "solo", "Not in a group" },
                  { "inraid", "In a raid" },
                  { "notraid", "Not in a raid" },
              } },
        },
    },
    -- NOTE: as of 1.2.0 this is a COMBAT-SAFE toolset. Conditions that Midnight (12.0)
    -- protects as "Secret values" in combat/instances - Health/Resource %, Spell ready,
    -- and all Buff/Aura (present/missing/time-left/gained/lost) checks - were removed
    -- because they can't be evaluated reliably in combat. Everything above works in combat.
    -- Rendered specially in the UI (class + spec dropdowns with icons).
    { type = "classSpec", label = "Class / Spec", params = {} },
}

-- Resolve a spell input (numeric ID or name) to id, name, iconID.
function TCC.ResolveSpell(input)
    if input == nil or input == "" then return nil, nil, nil end
    local num = tonumber(input)
    local info
    if C_Spell and C_Spell.GetSpellInfo then
        info = C_Spell.GetSpellInfo(num or input)
    end
    if info then
        return info.spellID or num, info.name, info.iconID
    end
    if num then return num, nil, nil end
    return nil, input, nil
end

-- Resolve an item input (numeric ID or name) to id, name, iconFileID.
function TCC.ResolveItem(input)
    local id = tonumber(input)
    if not id then return nil, tostring(input or ""), nil end
    local name, icon
    if C_Item then
        if C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(id) end
        if C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
    end
    return id, name, icon
end

function TCC.GetConditionMeta(ctype)
    for _, m in ipairs(TCC.CONDITION_TYPES) do
        if m.type == ctype then return m end
    end
    return nil
end

function TCC.NewCondition(ctype)
    local meta = TCC.GetConditionMeta(ctype)
    local c = { type = ctype }
    if meta then
        for _, p in ipairs(meta.params) do c[p.key] = p.default end
    end
    if ctype == "classSpec" then
        local _, token = UnitClass("player")
        c.class = token
        c.spec = "all"
    end
    return c
end

-- Readable spell/item name for the plain-English summary (falls back to the raw value).
local function spellLabel(v)
    if v == nil or v == "" then return "?" end
    local _, name = TCC.ResolveSpell(v)
    return name or tostring(v)
end
local function itemLabel(v)
    if v == nil or v == "" then return "?" end
    local _, name = TCC.ResolveItem(v)
    return name or tostring(v)
end

-- A short human-readable clause for one condition (used in the summary sentence).
function TCC.DescribeCondition(c)
    if c.type == "combat" then
        return c.op == "out" and "out of combat" or "in combat"
    elseif c.type == "target" then
        local m = { none = "no target", exists = "have a target", hostile = "target is hostile",
                    dead = "target is dead", attackable = "target is attackable" }
        return m[c.state or "none"] or "target"
    elseif c.type == "threat" then
        local m = { aggro = "you pulled aggro", high = "high threat on target", safe = "not tanking target" }
        return m[c.state or "aggro"] or "threat"
    elseif c.type == "range" then
        return spellLabel(c.spell) .. ((c.op == "in") and " in range" or " out of range")
    elseif c.type == "pet" then
        local m = { dead = "pet is dead", missing = "no pet", alive = "pet is alive", exists = "have a pet" }
        return m[c.state or "dead"] or "pet"
    elseif c.type == "groupRange" then
        local r = { HEALER = "healer", TANK = "tank", DAMAGER = "a DPS", any = "the group" }
        return ((c.op == "in") and "in range of " or "out of range of ") .. (r[c.role or "HEALER"] or "group")
    elseif c.type == "itemReady" then
        return itemLabel(c.item) .. ((c.op == "cd") and " on cooldown" or " off cooldown")
    elseif c.type == "instance" then
        local m = { any = "in any instance", none = "not in an instance", party = "in a dungeon",
                    raid = "in a raid", arena = "in an arena", pvp = "in a battleground", scenario = "in a scenario" }
        return m[c.value or "any"] or "in an instance"
    elseif c.type == "group" then
        local m = { ingroup = "in a group", solo = "not in a group", inraid = "in a raid", notraid = "not in a raid" }
        return m[c.state or "ingroup"] or "group"
    elseif c.type == "classSpec" then
        local className = "any class"
        if c.class and c.class ~= "" then
            className = c.class
            for _, cl in ipairs(TAP.GetClassList()) do
                if cl.token == c.class then className = cl.name; break end
            end
        end
        if c.spec and c.spec ~= "all" then
            local specName
            for _, sp in ipairs(TAP.GetSpecList(c.class)) do
                if tostring(sp.id) == tostring(c.spec) then specName = sp.name; break end
            end
            return className .. " / " .. (specName or ("spec " .. tostring(c.spec)))
        end
        return className
    end
    local meta = TCC.GetConditionMeta(c.type)
    return meta and meta.label or c.type
end

-- Recursively describe a node in plain English (nested AND/OR groups parenthesised).
function TCC.DescribeNode(node)
    if node.children then
        if #node.children == 0 then return "(empty)" end
        local sep = (node.op == "ANY") and " OR " or " AND "
        local out = {}
        for _, ch in ipairs(node.children) do
            out[#out + 1] = ch.children and TCC.DescribeNode(ch) or TCC.DescribeCondition(ch)
        end
        return "(" .. table.concat(out, sep) .. ")"
    end
    return TCC.DescribeCondition(node)
end

-- Plain-English summary of a whole rule tree (root group not parenthesised).
function TCC.DescribeRuleText(root)
    if not root or not root.children or #root.children == 0 then
        return "no conditions yet - add one below"
    end
    local parts = {}
    for _, ch in ipairs(root.children) do parts[#parts + 1] = TCC.DescribeNode(ch) end
    return table.concat(parts, (root.op == "ANY") and " OR " or " AND ")
end

----------------------------------------------------------------------
-- Runtime evaluators. Each returns true when the condition is satisfied.
----------------------------------------------------------------------
local EVAL = {}

EVAL.combat = function(c)
    local inCombat = UnitAffectingCombat("player")
    if c.op == "out" then return not inCombat end
    return inCombat
end

EVAL.target = function(c)
    local exists = UnitExists("target")
    local state = c.state or "none"
    if state == "none" then return not exists
    elseif state == "exists" then return exists
    elseif state == "hostile" then return exists and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
    elseif state == "dead" then return exists and UnitIsDeadOrGhost("target")
    elseif state == "attackable" then return exists and UnitCanAttack("player", "target") end
    return false
end

-- Range to group members of a role (e.g. "am I out of range of the healer?").
-- Uses UnitInRange (the ~40yd operational range healing addons use) + assigned roles.
EVAL.groupRange = function(c)
    local role = c.role or "HEALER"
    local op = c.op or "out"
    if not (UnitInRange and IsInGroup and IsInGroup()) then return false end

    local units, n = {}, 0
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then n = n + 1; units[n] = u end
        end
    else
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then n = n + 1; units[n] = u end
        end
    end
    if n == 0 then return false end

    local maxYards = tonumber(c.yards) or 40           -- ~UnitInRange operational range
    local anyMatch, anyInRange, restricted = false, false, false
    for i = 1, n do
        local u = units[i]
        local matches = (role == "any")
            or (UnitGroupRolesAssigned and UnitGroupRolesAssigned(u) == role)
        if matches and (not UnitIsDeadOrGhost or not UnitIsDeadOrGhost(u)) then
            anyMatch = true
            local yd = TCC.UnitDistanceYards(u)
            if yd then
                if yd <= maxYards + TCC.RANGE_REACH_PAD then anyInRange = true end
            else
                -- No readable distance -> fall back to UnitInRange (guarded for secrets).
                local inR, checked = UnitInRange(u)
                if TCC.CanRead(inR) and TCC.CanRead(checked) then
                    if checked ~= false and inR then anyInRange = true end
                else
                    restricted = true                -- secret here (identity-restricted unit)
                end
            end
        end
    end
    if not anyMatch then return false end          -- no living member of that role
    -- If range was secret for everyone we could check and none read as in-range, we
    -- genuinely can't tell -- don't fire either "in" or "out" on a guess.
    if restricted and not anyInRange then return false end
    if op == "in" then return anyInRange end
    return not anyInRange                            -- out: no one of that role in range
end

EVAL.pet = function(c)
    local exists = UnitExists("pet")
    local s = c.state or "dead"
    if s == "missing" then return not exists end
    if s == "exists" then return exists and true or false end
    if s == "alive" then return exists and not UnitIsDead("pet") end
    return exists and UnitIsDead("pet") and true or false   -- dead (corpse present)
end

EVAL.threat = function(c)
    if not UnitExists("target") then return false end
    if not UnitThreatSituation then return false end
    local sit = UnitThreatSituation("player", "target")
    if not TCC.CanRead(sit) then return false end  -- threat can be secret -> don't fire on a guess
    sit = sit or 0
    local s = c.state or "aggro"
    if s == "aggro" then return sit >= 2 end       -- you're tanking it (pulled aggro)
    if s == "high" then return sit >= 1 end        -- high threat, about to pull
    return sit < 2                                  -- safe: not tanking
end

EVAL.range = function(c)
    if not UnitExists("target") then return false end
    if not c.spell or c.spell == "" then return false end
    -- Prefer an ID (Mythic+-safe); upgrade a typed name once.
    local key = tonumber(c.spell)
    if not key then
        local id = TCC.ResolveSpell(c.spell)
        if id then c.spell = id; key = id end
    end
    key = key or c.spell
    if not (C_Spell and C_Spell.IsSpellInRange) then return false end
    local r = C_Spell.IsSpellInRange(key, "target")
    if not TCC.CanRead(r) then return false end    -- secret here -> can't decide, don't fire
    if r == nil then return false end              -- spell has no range check
    local inRange = (r == true or r == 1)
    if c.op == "in" then return inRange end
    return not inRange
end

EVAL.itemReady = function(c)
    local id = tonumber(c.item)
    if not id then return false end
    local getCd = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
    if not getCd then return false end
    local start, duration = getCd(id)
    if start == nil then return false end
    local onCd = (duration and duration > 1.5 and start and start > 0) and true or false
    if c.op == "cd" then return onCd end   -- fire while on cooldown
    return not onCd                         -- default "ready": fire when off cooldown
end

EVAL.instance = function(c)
    local inInstance, itype = IsInInstance()
    if c.value == "any" then return inInstance and true or false end
    return (itype or "none") == (c.value or "none")
end

EVAL.classSpec = function(c)
    local _, classToken = UnitClass("player")
    if c.class and c.class ~= "" and c.class ~= classToken then return false end
    if c.spec and c.spec ~= "all" then
        local si = GetSpecialization and GetSpecialization()
        local specID = si and GetSpecializationInfo and GetSpecializationInfo(si)
        if tostring(specID) ~= tostring(c.spec) then return false end
    end
    return true
end

EVAL.group = function(c)
    local s = c.state or "ingroup"
    if s == "solo" then return not IsInGroup()
    elseif s == "inraid" then return IsInRaid() and true or false
    elseif s == "notraid" then return not IsInRaid() end
    return IsInGroup() and true or false
end

----------------------------------------------------------------------
-- Polling: types that events can't fully catch.
----------------------------------------------------------------------
local POLLING_TYPES = { itemReady = true, range = true, groupRange = true }

local function nodeNeedsPolling(node)
    if node.children then
        for _, ch in ipairs(node.children) do
            if nodeNeedsPolling(ch) then return true end
        end
        return false
    end
    if POLLING_TYPES[node.type] then return true end
    return false
end

function TCC.RuleNeedsPolling(rule)
    -- A grace period needs the poller so the delay can elapse and fire even if no
    -- further event arrives while the conditions keep holding.
    if rule.action and (tonumber(rule.action.debounce) or 0) > 0 then return true end
    if rule.kind and rule.kind ~= "advanced" then
        return (rule.trigger and POLLING_TYPES[rule.trigger.type]) and true or false
    end
    if rule.root then return nodeNeedsPolling(rule.root) end
    for _, c in ipairs(rule.conditions or {}) do
        if POLLING_TYPES[c.type] then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Rule-tree evaluation (nested AND/OR groups)
--
--   rule.root = { op = "ALL"|"ANY", children = { <condition|group>, ... } }
-- A condition is a table with a .type; a group has .children.
----------------------------------------------------------------------
local function evalCondition(c)
    local fn = EVAL[c.type]
    if not fn then return false end
    -- pcall so one condition hitting a secret-value comparison (Midnight) can't break the whole pass.
    local ok, result = pcall(fn, c)
    return ok and result or false
end

local function evalNode(node)
    if node.children then  -- group
        if #node.children == 0 then return false end
        if (node.op or "ALL") == "ANY" then
            for _, child in ipairs(node.children) do
                if evalNode(child) then return true end
            end
            return false
        end
        for _, child in ipairs(node.children) do
            if not evalNode(child) then return false end
        end
        return true
    end
    return evalCondition(node)
end

-- Migrate a legacy flat rule (conditions + match) to a root group in place.
function TCC.EnsureRuleTree(rule)
    if type(rule) ~= "table" then return end
    if rule.kind and rule.kind ~= "advanced" then return end   -- type-based: no tree
    if type(rule.root) ~= "table" then
        rule.root = { op = (rule.match == "ANY") and "ANY" or "ALL", children = rule.conditions or {} }
    end
    rule.conditions = nil
    rule.match = nil
    return rule.root
end

----------------------------------------------------------------------
-- Type-based alerts (kind + single trigger + Load gates)
--
-- An alert with a `kind` (range/target/threat/pet/item) is a single trigger
-- condition plus a set of "Load" gates that decide WHEN it's active. Alerts with
-- no kind (or kind "advanced") use the AND/OR condition tree above.
----------------------------------------------------------------------
TCC.ALERT_KINDS = {
    { kind = "range",  label = "Range",  triggers = { "range", "groupRange" }, default = "range" },
    { kind = "target", label = "Target", triggers = { "target" },             default = "target" },
    { kind = "threat", label = "Threat", triggers = { "threat" },             default = "threat" },
    { kind = "pet",    label = "Pet",    triggers = { "pet" },                 default = "pet" },
    { kind = "item",   label = "Item",   triggers = { "itemReady" },           default = "itemReady" },
}

function TCC.GetAlertKind(kind)
    for _, k in ipairs(TCC.ALERT_KINDS) do if k.kind == kind then return k end end
    return nil
end

-- Load gates: returns true when the alert should be active right now.
-- load = { specs = {[specID]=true,...} or nil, combat, instance, group }
function TCC.LoadPasses(load)
    if not load then return true end
    if load.specs and next(load.specs) then
        local si = GetSpecialization and GetSpecialization()
        local sid = si and GetSpecializationInfo and GetSpecializationInfo(si)
        if not (sid and load.specs[sid]) then return false end
    end
    local combat = load.combat
    if combat and combat ~= "any" then
        local inC = UnitAffectingCombat("player") and true or false
        if combat == "in" and not inC then return false end
        if combat == "out" and inC then return false end
    end
    local inst = load.instance
    if inst and inst ~= "any" then
        local inI, t = IsInInstance()
        if inst == "none" then
            if inI then return false end
        elseif inst == "any_instance" then
            if not inI then return false end
        elseif (t or "none") ~= inst then
            return false
        end
    end
    local grp = load.group
    if grp and grp ~= "any" then
        if grp == "solo" and IsInGroup() then return false end
        if grp == "party" and (not IsInGroup() or IsInRaid()) then return false end
        if grp == "raid" and not IsInRaid() then return false end
    end
    return true
end

function TCC.EvaluateRule(rule)
    if not rule or not rule.enabled then return false end
    -- Type-based alert: Load gates + a single trigger.
    if rule.kind and rule.kind ~= "advanced" then
        if not TCC.LoadPasses(rule.load) then return false end
        if not rule.trigger then return false end
        return evalCondition(rule.trigger)
    end
    -- Advanced alert: the AND/OR condition tree.
    local root = rule.root
    if not root then TCC.EnsureRuleTree(rule); root = rule.root end
    if not (root and root.children and #root.children > 0) then return false end
    return evalNode(root)
end
