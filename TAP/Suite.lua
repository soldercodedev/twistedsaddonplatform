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
--         icon    = "keyboard",                    -- bundled UIFoundry icon name (or a texture path)
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

local ADDON, UIF = ...

----------------------------------------------------------------------
-- The registry (exposed as a global so sidecars can reach it without LibStub).
----------------------------------------------------------------------
local Suite = {
    modules = {},   -- array, in registration order
    byId    = {},   -- id -> module handle
    _loggedIn = false,
}
_G.TAP = Suite
UIF.Suite = Suite

----------------------------------------------------------------------
-- SavedVariables (declared in the .toc as TAPDB). Created lazily so it works on a
-- first run before the saved file exists, and is safe to call from any point.
----------------------------------------------------------------------
function Suite:DB()
    local db = _G.TAPDB
    if not db then db = {}; _G.TAPDB = db end
    db.modules = db.modules or {}
    return db
end

-- Persistent per-module record { enabled = bool, settings = {} }. `enabled` is only seeded
-- from the module's `default` the first time we see it, so a user's choice always wins after.
local function moduleRecord(spec)
    local db = Suite:DB()
    local rec = db.modules[spec.id]
    if not rec then
        rec = { enabled = spec.default ~= false, settings = {} }
        db.modules[spec.id] = rec
    end
    rec.settings = rec.settings or {}
    return rec
end

----------------------------------------------------------------------
-- Module handle - what RegisterModule returns and what the callbacks receive.
----------------------------------------------------------------------
local ModuleMixin = {}
local ModuleMeta = { __index = ModuleMixin }

-- Persisted, per-module settings table the sidecar reads/writes freely.
function ModuleMixin:GetSettings() return moduleRecord(self.spec).settings end

-- Convenience getter/seed: returns the stored value, defaulting (and storing the default) when absent.
function ModuleMixin:Setting(key, default)
    local s = self:GetSettings()
    if s[key] == nil then s[key] = default end
    return s[key]
end
function ModuleMixin:SetSetting(key, value) self:GetSettings()[key] = value end

function ModuleMixin:IsEnabled() return moduleRecord(self.spec).enabled and true or false end
function ModuleMixin:IsActive()  return self._active and true or false end

-- Flip the module on/off live. Persists the choice, then activates/deactivates to match.
function ModuleMixin:SetEnabled(on)
    moduleRecord(self.spec).enabled = on and true or false
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
    moduleRecord(spec)          -- seed the persistent record now
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

----------------------------------------------------------------------
-- Central load-on-demand data. Modules that need a big optional dataset ask the SUITE to load it,
-- so on-demand loading lives in ONE place instead of each module poking C_AddOns itself. (WoW has
-- no real "unload" - an addon stays resident for the session once loaded - so this is load-when-
-- needed; the payload just isn't parsed until something asks for it.)
----------------------------------------------------------------------
function Suite:IsDataLoaded(addonName)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return isLoaded and isLoaded(addonName) and true or false
end

function Suite:LoadData(addonName)
    if self:IsDataLoaded(addonName) then return true end
    local loader = C_AddOns and C_AddOns.LoadAddOn
    if not loader then return false end
    pcall(loader, addonName)
    return self:IsDataLoaded(addonName)
end

-- The suite's bundled spell / item name database (load-on-demand). Any module can call these; the
-- data addon is only pulled in (and its ~5 MB of strings parsed) the first time one is requested.
local GAME_DB = "TAP_GameDB"
function Suite:GetSpellDB() self:LoadData(GAME_DB); return _G.TAP_GameDB_Spells end
function Suite:GetItemDB()  self:LoadData(GAME_DB); return _G.TAP_GameDB_Items end

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
