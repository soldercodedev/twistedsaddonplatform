-- TAP: Mythic Ledger - Export.lua
-- Versioned, validated, NON-EXECUTABLE serialization for sharing/backing up runs and player
-- history. Data is encoded with a tiny tagged format parsed by hand (never loadstring), then
-- base64-wrapped with a version prefix, so importing a string can never run code.

local ADDON, ML = ...
local DB = ML.DB

local Export = {}
ML.Export = Export

local PREFIX = "TAPML"          -- payload tag
local FMT_VERSION = 1

----------------------------------------------------------------------
-- base64 (standard alphabet).
----------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64DEC = {}
for i = 1, #B64 do B64DEC[B64:sub(i, i)] = i - 1 end

local function base64Encode(data)
    local out, len = {}, #data
    local i = 1
    while i <= len do
        local b1 = data:byte(i)
        local b2 = data:byte(i + 1)
        local b3 = data:byte(i + 2)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1)
        out[#out + 1] = B64:sub(c2 + 1, c2 + 1)
        out[#out + 1] = b2 and B64:sub(c3 + 1, c3 + 1) or "="
        out[#out + 1] = b3 and B64:sub(c4 + 1, c4 + 1) or "="
        i = i + 3
    end
    return table.concat(out)
end

local function base64Decode(str)
    str = str:gsub("[^%w%+%/=]", "")
    local out = {}
    local i = 1
    while i <= #str do
        local c1 = B64DEC[str:sub(i, i)]
        local c2 = B64DEC[str:sub(i + 1, i + 1)]
        local s3 = str:sub(i + 2, i + 2)
        local s4 = str:sub(i + 3, i + 3)
        local c3 = B64DEC[s3]
        local c4 = B64DEC[s4]
        if not c1 or not c2 then break end
        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if s3 ~= "=" and c3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if s4 ~= "=" and c4 then out[#out + 1] = string.char(n % 256) end
        i = i + 4
    end
    return table.concat(out)
end

----------------------------------------------------------------------
-- Tagged serializer. Grammar (no whitespace, self-delimiting):
--   Sn:<bytes>   string of length n
--   N<digits>;   number
--   B0 | B1      boolean
--   Z            nil (skipped inside maps)
--   L <value>* E list (array part)
--   M (<value key><value>)* E   map
----------------------------------------------------------------------
local function enc(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "S" .. #v .. ":" .. v
    elseif t == "number" then
        -- Guard against inf/nan which don't round-trip.
        if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "N0;" else
            out[#out + 1] = "N" .. string.format("%.14g", v) .. ";"
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "B1" or "B0"
    elseif t == "table" then
        -- Decide array vs map.
        local n = #v
        local isArray = true
        local cnt = 0
        for k in pairs(v) do
            cnt = cnt + 1
            if type(k) ~= "number" then isArray = false end
        end
        if isArray and cnt == n then
            out[#out + 1] = "L"
            for i = 1, n do enc(v[i], out) end
            out[#out + 1] = "E"
        else
            out[#out + 1] = "M"
            for k, val in pairs(v) do
                if val ~= nil then enc(k, out); enc(val, out) end
            end
            out[#out + 1] = "E"
        end
    else
        out[#out + 1] = "Z"
    end
end

local function serialize(v)
    local out = {}
    enc(v, out)
    return table.concat(out)
end

-- Strict cursor-based parser. Returns value, nextIndex - or nil on any malformation.
local function parse(s, i)
    local tag = s:sub(i, i)
    if tag == "S" then
        local colon = s:find(":", i + 1, true)
        if not colon then return nil end
        local len = tonumber(s:sub(i + 1, colon - 1))
        if not len or len < 0 then return nil end
        local str = s:sub(colon + 1, colon + len)
        if #str ~= len then return nil end
        return str, colon + len + 1
    elseif tag == "N" then
        local semi = s:find(";", i + 1, true)
        if not semi then return nil end
        local num = tonumber(s:sub(i + 1, semi - 1))
        if num == nil then return nil end
        return num, semi + 1
    elseif tag == "B" then
        local b = s:sub(i + 1, i + 1)
        return (b == "1"), i + 2
    elseif tag == "Z" then
        return nil, i + 1
    elseif tag == "L" then
        local arr, j = {}, i + 1
        while s:sub(j, j) ~= "E" do
            if j > #s then return nil end
            local val, nj = parse(s, j)
            if not nj then return nil end
            arr[#arr + 1] = val
            j = nj
        end
        return arr, j + 1
    elseif tag == "M" then
        local map, j = {}, i + 1
        while s:sub(j, j) ~= "E" do
            if j > #s then return nil end
            local key, jk = parse(s, j)
            if not jk then return nil end
            local val, jv = parse(s, jk)
            if not jv then return nil end
            if key ~= nil then map[key] = val end
            j = jv
        end
        return map, j + 1
    end
    return nil
end

local function deserialize(s)
    local v, j = parse(s, 1)
    if not j then return nil end
    return v
end

----------------------------------------------------------------------
-- Public encode/decode of a versioned payload.
----------------------------------------------------------------------
local function pack(kind, data)
    local payload = { v = FMT_VERSION, schema = ML.SCHEMA_VERSION, kind = kind, data = data }
    return PREFIX .. FMT_VERSION .. "!" .. base64Encode(serialize(payload))
end

local function unpack(str)
    if type(str) ~= "string" then return nil, "empty" end
    local body = str:match("^" .. PREFIX .. "%d+!(.+)$")
    if not body then return nil, "not a Mythic Ledger export string" end
    local raw = base64Decode(body)
    if raw == "" then return nil, "corrupt data" end
    local ok, payload = pcall(deserialize, raw)
    if not ok or type(payload) ~= "table" or type(payload.kind) ~= "string" then
        return nil, "unreadable payload"
    end
    return payload
end

----------------------------------------------------------------------
-- Exports.
----------------------------------------------------------------------
function Export.ExportRun(run) return pack("run", run) end
function Export.ExportRuns(runs) return pack("runs", runs) end

function Export.ExportPlayer(identityKey)
    local summary = DB.PlayerIndex()[identityKey]
    local runs = ML.History.PlayerRuns(identityKey)
    return pack("player", { identityKey = identityKey, summary = summary, runs = runs,
        meta = DB.PlayerMeta()[identityKey] })
end

function Export.ExportAll()
    if not DB.root then return pack("all", {}) end
    return pack("all", {
        schemaVersion = DB.root.schemaVersion,
        runs = DB.root.runs,
        playerMeta = DB.root.playerMeta,
        settings = DB.Settings(),   -- the ACTIVE profile's settings, not a vanished root table
    })
end

----------------------------------------------------------------------
-- Import. Merges runs (de-duplicated); returns (true, countAdded) or (false, reason).
----------------------------------------------------------------------
function Export.Import(str)
    local payload, err = unpack(str)
    if not payload then return false, err end
    local added = 0
    local function addRun(r) if type(r) == "table" and r.mapId and DB.AddRun(r) then added = added + 1 end end

    if payload.kind == "run" then
        addRun(payload.data)
    elseif payload.kind == "runs" then
        for _, r in ipairs(payload.data or {}) do addRun(r) end
    elseif payload.kind == "player" then
        for _, r in ipairs((payload.data and payload.data.runs) or {}) do addRun(r) end
        if payload.data and payload.data.identityKey and payload.data.meta then
            DB.PlayerMeta()[payload.data.identityKey] = payload.data.meta
        end
    elseif payload.kind == "all" then
        for _, r in ipairs((payload.data and payload.data.runs) or {}) do addRun(r) end
        if payload.data and type(payload.data.playerMeta) == "table" then
            for k, v in pairs(payload.data.playerMeta) do
                if DB.PlayerMeta()[k] == nil then DB.PlayerMeta()[k] = v end
            end
        end
    else
        return false, "unknown export kind"
    end
    if ML.History and ML.History.RebuildAll then pcall(ML.History.RebuildAll) end
    return true, added
end
