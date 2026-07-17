-- TAP: Mythic Ledger - Constants.lua
-- Namespace bootstrap, shared enums/constants, small utilities, and the data-driven
-- expansion/season registry. Loads FIRST so every later file can rely on the ML table.
--
-- Season handling is deliberately API-driven: each run stores the live season id from
-- C_MythicPlus.GetCurrentSeason() and the challenge map id, and dungeon display names come
-- from C_ChallengeMode.GetMapUIInfo() at runtime. The registry below only supplies friendly
-- LABELS for known seasons; an unknown season still records fine as "Season <n>". This means a
-- valid Mythic+ run is never refused just because the registry is incomplete.

local ADDON, ML = ...

ML.ADDON      = ADDON                 -- "TAP_MythicLedger"
ML.MODULE_ID  = "mythicLedger"        -- Suite module id (matches ## X-Suite-Module)
ML.NAME       = "Mythic Ledger"
ML.PREFIX     = "|cffa06cf0Mythic Ledger|r "   -- chat print prefix (suite violet)
ML.SCHEMA_VERSION = 1

-- Run outcome, kept as stable string keys (never localise these - they are saved).
ML.STATUS = {
    TIMED     = "TIMED",
    DEPLETED  = "DEPLETED",   -- completed but over the timer
    ABANDONED = "ABANDONED",  -- left / reset before completion
}

-- Run lifecycle state machine.
ML.STATE = {
    IDLE          = "IDLE",
    PENDING_START = "PENDING_START",
    ACTIVE        = "ACTIVE",
    COMPLETING    = "COMPLETING",
    COMPLETED     = "COMPLETED",
    ABANDONED     = "ABANDONED",
}

-- Combat-stat provider source tags (saved with each run).
ML.SOURCE = {
    DETAILS  = "DETAILS",
    BLIZZARD = "BLIZZARD",
    NONE     = "NONE",
}

-- Roles (match Blizzard's role tokens so we can pass them straight through).
ML.ROLES = { "TANK", "HEALER", "DAMAGER" }
ML.ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

-- Recap settings enums.
ML.RECAP_DISPLAY = { CHAT = "CHAT", TOAST = "TOAST", BOTH = "BOTH", OFF = "OFF" }
ML.RECAP_DETAIL  = { COMPACT = "COMPACT", DETAILED = "DETAILED", OFF = "OFF" }
ML.RECAP_HISTORY = { SEASON = "SEASON", ALL = "ALL" }
ML.RECAP_TRIGGER = { JOIN = "JOIN", READY = "READY", BOTH = "BOTH" }   -- when a recap fires

----------------------------------------------------------------------
-- Season registry: friendly labels for known season ids. Verify the live season id + dungeon
-- pool in game (C_MythicPlus.GetCurrentSeason / C_ChallengeMode.GetMapTable); unknown ids fall
-- back to "Season <n>" and still record every run.
----------------------------------------------------------------------
-- NOTE: The Midnight Season 1 dungeon pool below is the ANNOUNCED list, kept for reference and
-- for the Dungeons page ordering. It is NOT used to gate recording - dungeon identity always
-- comes from the challenge map id + the live API name.
ML.MIDNIGHT_S1_POOL = {
    "Magisters' Terrace", "Maisara Caverns", "Nexus-Point Xenas", "Windrunner Spire",
    "Seat of the Triumvirate", "Skyreach", "Pit of Saron", "Algeth'ar Academy",
}

-- seasonId -> descriptor. Populate verified ids here; anything else uses the fallback.
ML.SEASON_LABELS = {
    -- [<liveSeasonId>] = { label = "Midnight Season 1", expansion = "Midnight", short = "M S1" },
}

function ML.SeasonLabel(seasonId)
    if seasonId == nil then return "Unknown Season" end
    local d = ML.SEASON_LABELS[seasonId]
    if d and d.label then return d.label end
    return "Season " .. tostring(seasonId)
end

function ML.SeasonShort(seasonId)
    if seasonId == nil then return "??" end
    local d = ML.SEASON_LABELS[seasonId]
    if d and d.short then return d.short end
    return "S" .. tostring(seasonId)
end

----------------------------------------------------------------------
-- Small utilities (kept dependency-free so every file can use them).
----------------------------------------------------------------------
local Util = {}
ML.Util = Util

function Util.deepcopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do out[Util.deepcopy(k, seen)] = Util.deepcopy(val, seen) end
    return out
end

function Util.count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

function Util.round(x, decimals)
    if type(x) ~= "number" then return x end
    local m = 10 ^ (decimals or 0)
    return math.floor(x * m + 0.5) / m
end

function Util.clamp(x, lo, hi)
    if x < lo then return lo elseif x > hi then return hi else return x end
end

-- Safe division: returns nil (not 0) when the denominator is missing/zero, so "unavailable"
-- never masquerades as a real zero.
function Util.safeDiv(num, den)
    if type(num) ~= "number" or type(den) ~= "number" or den == 0 then return nil end
    return num / den
end

-- Average of a numeric list, ignoring nils. Returns nil for an empty sample.
function Util.mean(list)
    local sum, n = 0, 0
    for _, v in ipairs(list) do
        if type(v) == "number" then sum = sum + v; n = n + 1 end
    end
    if n == 0 then return nil end
    return sum / n
end

----------------------------------------------------------------------
-- Formatting helpers (display only - never fabricate; return "-" for nil).
----------------------------------------------------------------------
local DASH = "-"
ML.DASH = DASH

-- 1234567 -> "1.23M", 12345 -> "12.3K". nil -> "-".
function Util.shortNum(n)
    if type(n) ~= "number" then return DASH end
    local abs = math.abs(n)
    if abs >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if abs >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if abs >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return string.format("%d", Util.round(n))
end

-- Seconds -> "M:SS" or "H:MM:SS". nil -> "-".
function Util.duration(sec)
    if type(sec) ~= "number" or sec < 0 then return DASH end
    sec = math.floor(sec + 0.5)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- Signed seconds delta -> "+1:23" over / "-0:45" under. nil -> "-".
function Util.signedDuration(sec)
    if type(sec) ~= "number" then return DASH end
    local sign = sec < 0 and "-" or "+"
    return sign .. Util.duration(math.abs(sec))
end

function Util.percent(fraction)
    if type(fraction) ~= "number" then return DASH end
    return string.format("%d%%", Util.round(fraction * 100))
end

-- number-or-dash for a possibly-nil metric.
function Util.numOr(n, fmt)
    if type(n) ~= "number" then return DASH end
    return string.format(fmt or "%d", n)
end

-- Timestamp display. Both formatters render date + LOCAL time so a timestamp shows anywhere a
-- date does. The date component and the 12/24-hour clock are user-customizable via settings
-- (dateFormat: NA/ISO/EU, clockFormat: 24H/12H); before the DB is ready we fall back to the
-- NA date + 24-hour default. WoW's date() formats in the client's local timezone.
local DATE_PATTERNS = { NA = "%m/%d/%y", ISO = "%Y-%m-%d", EU = "%d/%m/%y" }
local TIME_PATTERNS = { ["24H"] = "%H:%M", ["12H"] = "%I:%M %p" }

local function stampPattern()
    local s = ML.DB and ML.DB.Ready and ML.DB.Ready() and ML.DB.Settings() or nil
    local dPat = DATE_PATTERNS[s and s.dateFormat] or DATE_PATTERNS.NA
    local tPat = TIME_PATTERNS[s and s.clockFormat] or TIME_PATTERNS["24H"]
    return dPat .. " " .. tPat
end
ML._stampPattern = stampPattern   -- exposed so the settings page can build a live preview

-- epoch seconds -> e.g. "07/14/26 21:33" (date + local time). nil -> "-".
function Util.dateTime(epoch)
    if type(epoch) ~= "number" then return DASH end
    return date(stampPattern(), epoch)
end

-- Kept as a distinct name for callers of the old date-only formatter; now also shows the
-- local time so timestamps appear consistently everywhere a date is displayed.
Util.dateShort = Util.dateTime

-- A "+NN" keystone label.
function Util.keyLabel(level)
    if type(level) ~= "number" then return DASH end
    return "+" .. tostring(level)
end

-- Debug logging (ring buffer; surfaced on the Debug page and /tap ledger debug).
ML._log = ML._log or {}
ML._logMax = 500
function ML.Log(fmt, ...)
    local msg
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        msg = ok and s or tostring(fmt)
    else
        msg = tostring(fmt)
    end
    local line = { t = time(), msg = msg }
    local log = ML._log
    log[#log + 1] = line
    if #log > ML._logMax then table.remove(log, 1) end
    if ML._debugEcho then print(ML.PREFIX .. "|cff888888[dbg]|r " .. msg) end
end

function ML.Print(fmt, ...)
    local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
    print(ML.PREFIX .. msg)
end
