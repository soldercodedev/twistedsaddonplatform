-- TAP - Suite.lua
-- The modular backbone for the suite: a tiny registry that lets self-contained "sidecar"
-- addons plug into one shared hub so features can be turned on and off individually - you
-- only run the pieces you want.
--
-- A sidecar is just its own addon folder that lists `## Dependencies: TAP`
-- and, on load, calls:
--
--     local Suite = _G.TAP
--     local mod = Suite:RegisterModule({
--         id      = "rotationCue",                 -- unique, stable key (used in SavedVariables)
--         title   = "Rotation Assistant",
--         desc    = "Shows the keybind of Blizzard's next suggested ability.",
--         icon    = "keyboard",                    -- bundled TAP icon name (or a texture path)
--         addon   = "TAP_RotationAssistant",         -- its own addon folder (for hard load control)
--         default = true,                          -- enabled on first run?
--         OnEnable  = function(m) ... end,         -- create frames / register events
--         OnDisable = function(m) ... end,         -- tear them down
--         Settings  = function(m, b, x, y, w, win) return y end,  -- optional inline options page
--     })
--
-- Enabling / disabling a module is a *live soft toggle* - no /reload needed. `OnDisable` must
-- fully stand the feature down (hide frames, unregister events) so a disabled module costs
-- nothing at runtime. The registration chunk itself stays tiny, so an unwanted feature is
-- effectively dormant. For a *hard* unload (don't even load the sidecar's Lua), disable the
-- sidecar addon from the Manager's Overview page (or Blizzard's AddOns list) - that needs a
-- reload but keeps the code entirely out of memory.

local ADDON, TAP = ...

----------------------------------------------------------------------
-- The module registry lives ON the shared framework table (TAP, set up in Core.lua), so _G.TAP is the
-- single entry point for both the UI kit and module registration. `Suite` below is a local alias.
----------------------------------------------------------------------
local Suite = TAP
Suite.modules   = {}   -- array, in registration order
Suite.byId      = {}   -- id -> module handle
Suite._loggedIn = false
TAP.Suite = Suite      -- self-reference, for any consumer that reached the registry via TAP.Suite

----------------------------------------------------------------------
-- SavedVariables (declared in the .toc as TAPDB) and PROFILES.
--
-- Two stores, split on one question: is this a matter of taste, or a matter of what this
-- character does?
--
--   db.global    Taste and installation. Shared by every character, never profiled: which
--                add-ons are switched on, the theme, minimap icons, the manager window.
--   db.profiles  Everything a character's setup depends on - every module's settings, which
--                means every frame position, size, colour and behaviour toggle they own.
--
-- A profile is a NAMED bundle and each character is BOUND to one, so alts can share a setup or
-- have their own without copying anything by hand. Per-SPEC behaviour is deliberately NOT part
-- of this: the modules that need it already carry their own spec filters (Rotation Assistant's
-- `specs`, Focus Interrupt's `triggerSpecs`), which is the finer-grained and better-targeted
-- tool. Profiles answer "this character is set up differently", not "this spec behaves
-- differently".
--
--   TAPDB = {
--     global   = { modules = { [id] = { enabled = bool } } },
--     profiles = { ["Default"] = { modules = { [id] = { <settings> } } } },
--     bindings = { ["Name-Realm"] = "Default" },
--     manager  = { ... },   -- global, owned by SuiteManager
--     minimap  = { ... },   -- global, owned by SuiteManager
--   }
----------------------------------------------------------------------
local DEFAULT_PROFILE = "Default"
Suite.DEFAULT_PROFILE = DEFAULT_PROFILE

function Suite:CharKey()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or ""
    realm = (realm or ""):gsub("%s+", "")
    return (realm ~= "") and (name .. "-" .. realm) or name
end

-- Fold the pre-profile layout (db.modules[id] = { enabled, settings }) into the split store.
-- Runs once, in place, and reads the old key only long enough to empty it.
local function migrate(db)
    if db.profiles then return end
    db.global   = db.global   or { modules = {} }
    db.global.modules = db.global.modules or {}
    db.profiles = { [DEFAULT_PROFILE] = { modules = {} } }
    db.bindings = db.bindings or {}
    if type(db.modules) == "table" then
        for id, rec in pairs(db.modules) do
            if type(rec) == "table" then
                db.global.modules[id] = { enabled = rec.enabled }
                db.profiles[DEFAULT_PROFILE].modules[id] = rec.settings or {}
            end
        end
    end
    db.modules = nil
end

function Suite:DB()
    local db = _G.TAPDB
    if not db then db = {}; _G.TAPDB = db end
    migrate(db)
    db.global         = db.global or {}
    db.global.modules = db.global.modules or {}
    db.profiles       = db.profiles or {}
    db.bindings       = db.bindings or {}
    if type(db.profiles[DEFAULT_PROFILE]) ~= "table" then
        db.profiles[DEFAULT_PROFILE] = { modules = {} }
    end
    return db
end

----------------------------------------------------------------------
-- Profile access.
----------------------------------------------------------------------
function Suite:ActiveProfileName()
    local db = self:DB()
    local name = db.bindings[self:CharKey()]
    if name and db.profiles[name] then return name end
    return DEFAULT_PROFILE
end

function Suite:ActiveProfile()
    local db = self:DB()
    local p = db.profiles[self:ActiveProfileName()]
    p.modules = p.modules or {}
    return p
end

-- Names: Default first, then the rest alphabetically. The order they are always listed in.
function Suite:ListProfiles()
    local db, out = self:DB(), {}
    for name in pairs(db.profiles) do
        if name ~= DEFAULT_PROFILE then out[#out + 1] = name end
    end
    table.sort(out)
    table.insert(out, 1, DEFAULT_PROFILE)
    return out
end

-- Which characters are bound to a profile. Worth showing before a delete: dropping a profile
-- three alts share should not be a silent surprise.
function Suite:ProfileUsers(name)
    local db, out = self:DB(), {}
    for charKey, prof in pairs(db.bindings) do
        if prof == name then out[#out + 1] = charKey end
    end
    table.sort(out)
    return out
end

local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = deepcopy(val) end
    return t
end
Suite._deepcopy = deepcopy

function Suite:CreateProfile(name, copyFrom)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "a profile needs a name" end
    local db = self:DB()
    if db.profiles[name] then return false, "there is already a profile called that" end
    local src = copyFrom and db.profiles[copyFrom]
    local p = src and deepcopy(src) or { modules = {} }
    p.modules = p.modules or {}
    db.profiles[name] = p
    if src then self:_profileOp("OnProfileCopy", copyFrom, name) end
    return true
end

function Suite:DeleteProfile(name)
    if name == DEFAULT_PROFILE then return false, "the Default profile cannot be deleted" end
    local db = self:DB()
    if not db.profiles[name] then return false, "no such profile" end
    db.profiles[name] = nil
    -- Anyone pointed at it falls back to Default rather than to a dangling name.
    for charKey, prof in pairs(db.bindings) do
        if prof == name then db.bindings[charKey] = nil end
    end
    self:_profileOp("OnProfileDelete", name)
    self:_applyProfile()
    return true
end

function Suite:RenameProfile(old, new)
    new = tostring(new or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if old == DEFAULT_PROFILE then return false, "the Default profile cannot be renamed" end
    if new == "" then return false, "a profile needs a name" end
    local db = self:DB()
    if not db.profiles[old] then return false, "no such profile" end
    if db.profiles[new] then return false, "there is already a profile called that" end
    db.profiles[new], db.profiles[old] = db.profiles[old], nil
    for charKey, prof in pairs(db.bindings) do
        if prof == old then db.bindings[charKey] = new end
    end
    self:_profileOp("OnProfileRename", old, new)
    return true
end

-- Bind THIS character to a profile and re-apply everything to match.
function Suite:SetActiveProfile(name)
    local db = self:DB()
    if not db.profiles[name] then return false, "no such profile" end
    db.bindings[self:CharKey()] = (name ~= DEFAULT_PROFILE) and name or nil
    self:_applyProfile()
    return true
end

-- Overwrite the active profile's contents with another's. Distinct from switching: this is
-- "make this character look like that one" without leaving the profile you are on.
function Suite:CopyProfileInto(fromName)
    local db = self:DB()
    local src = db.profiles[fromName]
    if not src then return false, "no such profile" end
    local activeName = self:ActiveProfileName()
    if fromName == activeName then return false, "that is the profile you are already on" end
    db.profiles[activeName] = deepcopy(src)
    self:_profileOp("OnProfileCopy", fromName, activeName)
    self:_applyProfile()
    return true
end

-- Wipe the active profile back to defaults. Modules re-seed on their next read.
function Suite:ResetProfile()
    local db = self:DB()
    local activeName = self:ActiveProfileName()
    db.profiles[activeName] = { modules = {} }
    self:_profileOp("OnProfileReset", activeName)
    self:_applyProfile()
    return true
end

----------------------------------------------------------------------
-- Re-applying after a switch.
--
-- A module's settings table is a DIFFERENT table after a profile change, so anything holding a
-- reference to the old one is stale. `OnProfileChanged` is the hook to re-read and re-apply; a
-- module without one gets an off/on cycle, which is the blunt version of the same thing.
----------------------------------------------------------------------
Suite._profileListeners = {}
function Suite:OnProfileChanged(fn) self._profileListeners[#self._profileListeners + 1] = fn end

-- Profile LIFECYCLE, for modules that keep their own SavedVariables keyed by the profile name
-- (Combat Alerts' rules, Mythic Ledger's settings). Copying a profile here only duplicates the
-- platform's own table, so without these a copy came up with a default rule set, a rename orphaned
-- the old rows, a delete leaked them and a reset left them untouched.
--
--   spec.OnProfileCopy(m, fromName, toName)
--   spec.OnProfileRename(m, oldName, newName)
--   spec.OnProfileDelete(m, name)
--   spec.OnProfileReset(m, name)
function Suite:_profileOp(hook, a, b)
    for _, mod in ipairs(self.modules) do
        local fn = mod.spec[hook]
        if fn then
            local ok, err = pcall(fn, mod, a, b)
            if not ok then
                geterrorhandler()(("TAP: module '%s' %s failed: %s"):format(mod.spec.id, hook, tostring(err)))
            end
        end
    end
end

function Suite:_applyProfile()
    for _, mod in ipairs(self.modules) do
        local spec = mod.spec
        if spec.OnProfileChanged then
            local ok, err = pcall(spec.OnProfileChanged, mod)
            if not ok then
                geterrorhandler()(("TAP: module '%s' OnProfileChanged failed: %s"):format(spec.id, tostring(err)))
            end
        elseif mod._active then
            -- No hook: the only general way to make a module re-read its settings is to stand it
            -- down and bring it back up.
            self:_deactivate(mod)
            self:_activate(mod)
        end
        self:_sync(mod)
    end
    for _, fn in ipairs(self._profileListeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(("TAP: a profile listener failed: %s"):format(tostring(err))) end
    end
    self:_notify()
end

----------------------------------------------------------------------
-- Per-module records. `enabled` is GLOBAL - "is this add-on switched on" is not a per-character
-- question - and is only seeded from the module's `default` the first time we see it, so a
-- user's choice always wins after. `settings` come from the ACTIVE PROFILE.
----------------------------------------------------------------------
local function globalRecord(spec)
    local db = Suite:DB()
    local rec = db.global.modules[spec.id]
    if not rec then
        rec = { enabled = spec.default ~= false }
        db.global.modules[spec.id] = rec
    end
    return rec
end

local function moduleSettings(spec)
    local p = Suite:ActiveProfile()
    local s = p.modules[spec.id]
    if not s then s = {}; p.modules[spec.id] = s end
    return s
end

----------------------------------------------------------------------
-- Module handle - what RegisterModule returns and what the callbacks receive.
----------------------------------------------------------------------
local ModuleMixin = {}
local ModuleMeta = { __index = ModuleMixin }

-- Persisted, per-module settings table the sidecar reads/writes freely.
function ModuleMixin:GetSettings() return moduleSettings(self.spec) end

-- Convenience getter/seed: returns the stored value, defaulting (and storing the default) when absent.
function ModuleMixin:Setting(key, default)
    local s = self:GetSettings()
    if s[key] == nil then s[key] = default end
    return s[key]
end
function ModuleMixin:SetSetting(key, value) self:GetSettings()[key] = value end

function ModuleMixin:IsEnabled() return globalRecord(self.spec).enabled and true or false end
function ModuleMixin:IsActive()  return self._active and true or false end

-- Flip the module on/off live. Persists the choice, then activates/deactivates to match.
function ModuleMixin:SetEnabled(on)
    globalRecord(self.spec).enabled = on and true or false
    Suite:_sync(self)
    Suite:_notify()
end
function ModuleMixin:Toggle() self:SetEnabled(not self:IsEnabled()) end

----------------------------------------------------------------------
-- Activation - reconcile a module's live state with its desired (enabled) state, calling the
-- OnEnable / OnDisable hooks exactly once per transition. Errors in a sidecar hook are caught
-- so one bad module can't break the others (or the Manager).
----------------------------------------------------------------------
function Suite:_activate(mod)
    if mod._active then return end
    mod._active = true
    if mod.spec.OnEnable then
        local ok, err = pcall(mod.spec.OnEnable, mod)
        if not ok then
            mod._active = false
            geterrorhandler()(("TAP: module '%s' OnEnable failed: %s"):format(mod.spec.id, tostring(err)))
        end
    end
end

function Suite:_deactivate(mod)
    if not mod._active then return end
    mod._active = false
    if mod.spec.OnDisable then
        local ok, err = pcall(mod.spec.OnDisable, mod)
        if not ok then
            geterrorhandler()(("TAP: module '%s' OnDisable failed: %s"):format(mod.spec.id, tostring(err)))
        end
    end
end

-- Drive one module toward its persisted enabled state. No-ops until after login so every
-- module activates in a single pass once the game (and SavedVariables) are fully ready.
function Suite:_sync(mod)
    if not self._loggedIn then return end
    if mod:IsEnabled() then self:_activate(mod) else self:_deactivate(mod) end
end

----------------------------------------------------------------------
-- Registration.
----------------------------------------------------------------------
function Suite:RegisterModule(spec)
    assert(type(spec) == "table" and spec.id, "RegisterModule: spec.id is required")
    if self.byId[spec.id] then
        -- Re-registration (e.g. a reload of a LoadOnDemand sidecar) - update the spec in place.
        local mod = self.byId[spec.id]
        mod.spec = spec
        self:_sync(mod)
        return mod
    end
    local mod = setmetatable({ spec = spec, _active = false }, ModuleMeta)
    self.modules[#self.modules + 1] = mod
    self.byId[spec.id] = mod
    globalRecord(spec); moduleSettings(spec)   -- seed both records now
    self:_sync(mod)             -- activate immediately if we're already past login
    self:_notify()
    return mod
end

function Suite:GetModule(id) return self.byId[id] end

----------------------------------------------------------------------
-- Slash-command registry. Modules add entries so the Manager's Commands page can list every
-- command in one place, and (when an entry supplies `sub` + `handler`) so `/tap <sub> ...`
-- dispatches to the module. A module's own slash (e.g. /rcue) keeps working alongside this.
--   entry = {
--     cmd     = "/tap alerts",          -- display string
--     desc    = "Open the alerts manager",
--     owner   = "Combat Alerts",        -- groups the list (defaults to "Platform")
--     sub     = "alerts",               -- optional: the /tap subcommand token (dispatch)
--     handler = function(rest) ... end, -- optional: runs on "/tap <sub> <rest>"
--     subcommands = { { "test", "Play a test alert" }, ... },  -- optional display-only children
--   }
----------------------------------------------------------------------
Suite._commands = {}
function Suite:RegisterCommand(entry)
    if type(entry) ~= "table" or not entry.cmd then return end
    self._commands[#self._commands + 1] = entry
    self:_notify()   -- refresh the Commands page if the Manager is open
    return entry
end
function Suite:GetCommands() return self._commands end

-- Dispatch "/tap <sub> <rest>" to a registered handler. Returns true if one took it.
function Suite:RunCommand(sub, rest)
    if not sub then return false end
    sub = sub:lower()
    for _, c in ipairs(self._commands) do
        if c.sub == sub and c.handler then c.handler(rest or ""); return true end
    end
    return false
end

-- Counts for the Manager header ("3 modules · 2 active").
function Suite:Stats()
    local total, active = 0, 0
    for _, m in ipairs(self.modules) do
        total = total + 1
        if m._active then active = active + 1 end
    end
    return total, active
end

----------------------------------------------------------------------
-- Manager hookup - the Manager registers a listener so its window re-renders whenever a
-- module is added or toggled (kept decoupled so Suite.lua has no dependency on the UI).
----------------------------------------------------------------------
Suite._listeners = {}
function Suite:OnChanged(fn) self._listeners[#self._listeners + 1] = fn end
function Suite:_notify()
    for _, fn in ipairs(self._listeners) do
        -- Surface a listener error (e.g. the Manager's rebuild/refresh) instead of swallowing it;
        -- one bad listener still must not block the others, hence the per-listener pcall.
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(("TAP: a registry listener failed: %s"):format(tostring(err))) end
    end
end

----------------------------------------------------------------------
-- Slash command: /tap profile [name]
----------------------------------------------------------------------
if Suite.RegisterCommand then
    Suite:RegisterCommand({
        cmd = "/tap profile", desc = "Show or switch this character's profile",
        owner = "Platform", sub = "profile",
        handler = function(rest)
            rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if rest == "" then
                print(("|cffa06cf0TAP|r  %s is using profile |cff5fc9c0%s|r."):format(
                    Suite:CharKey(), Suite:ActiveProfileName()))
                print("|cffa06cf0TAP|r  Available: " .. table.concat(Suite:ListProfiles(), ", "))
                return
            end
            local ok, err = Suite:SetActiveProfile(rest)
            if ok then print("|cffa06cf0TAP|r  Profile: |cff5fc9c0" .. rest .. "|r")
            else print("|cffa06cf0TAP|r  " .. tostring(err)) end
        end,
    })
end

----------------------------------------------------------------------
-- Boot: on login, seed the DB and activate every enabled module in one pass. Modules that
-- register later (rare) activate on the spot via _sync.
----------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    Suite:DB()
    Suite._loggedIn = true
    for _, mod in ipairs(Suite.modules) do Suite:_sync(mod) end
    Suite:_notify()
end)
