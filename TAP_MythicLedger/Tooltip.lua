-- TAP: Mythic Ledger - Tooltip.lua
-- Augments Blizzard tooltips with your shared Mythic+ history for a player - the same stats the
-- returning-player recap shows, plus their note/tags: keys together, timed %, highest key, role-
-- appropriate averages, last result. Read-only, local, and ONLY appended when you've actually keyed with
-- that player - so unlike Raider.IO (global DB) this only lights up for people in YOUR run history.
--
-- Surfaces (modelled on Raider.IO's coverage; hook strategy mirrors theirs so it's easy to re-point when a
-- patch moves a frame): UNIT tooltip (frames/nameplates/world, by GUID), LFG group-finder search entries,
-- FriendsTooltip, /who, guild roster, and community member lists (all by Name-Realm via History.PlayerByName).
-- Name-only surfaces set an owned GameTooltip on the row and only draw when we have data (the row keeps its
-- own behaviour otherwise). Load-on-demand frames (guild / communities) are hooked on ADDON_LOADED.

local ADDON, ML = ...
local DB   = ML.DB
local Util = ML.Util
local Tooltip = {}
ML.Tooltip = Tooltip

local LBL    = { 0.92, 0.93, 0.98 }     -- bright label side (Raider.IO-style, not dim grey)
local active, hooked = false, false

local function n0(v) return string.format("%.0f", v) end
local function n1(v) return string.format("%.1f", v) end

-- The live theme accent as a BRIGHT "RRGGBB" hex for the header: follows the user's configured accent but
-- lifts the brightest channel to ~full so it reads vivid in a tooltip (a raw accent renders dim there).
local function accentHex()
    local t = _G.TAP and _G.TAP.uiTheme
    local c = t and t.C and t.C.accent
    local r, g, b = 0.63, 0.42, 0.94   -- fallback (a06cf0-ish)
    if type(c) == "table" and type(c[1]) == "number" then r, g, b = c[1], c[2] or 0, c[3] or 0 end
    local f = 0.98 / math.max(r, g, b, 0.01)
    r, g, b = math.min(1, r * f), math.min(1, g * f), math.min(1, b * f)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Letter-grade color (matches the module's tier colors used everywhere else).
local function gradeHex(grade)
    return (grade and ML.TierColor and ML.TierColor(grade:sub(1, 1))) or "cccccc"
end

----------------------------------------------------------------------
-- Data + render.
----------------------------------------------------------------------
-- What we'd show for identityKey `key`, or nil if nothing (used to gate owner-managed surfaces).
local function dataFor(key)
    if not key then return nil end
    local H = ML.History
    local meta = DB.PlayerMeta and DB.PlayerMeta()[key]
    local note = meta and type(meta.notes) == "string" and meta.notes ~= "" and meta.notes or nil
    local fav  = meta and meta.favorite and true or false
    local rc   = H and H.RecapStats and H.RecapStats(key, nil)   -- all-time shared history
    if not rc and not (note or fav) then return nil end
    return rc, note, fav
end

-- Append the ledger block to tooltip `tt`. `nameHeader` (optional) is drawn first for surfaces with no
-- unit line of their own (who/guild/etc.). Returns true if anything was added.
local function renderInto(tt, key, nameHeader)
    local rc, note, fav = dataFor(key)
    if not rc and not note and not fav then return false end

    if nameHeader and (tt.NumLines and tt:NumLines() == 0) then
        tt:AddLine(nameHeader, 1, 1, 1)
    end
    if tt.NumLines and tt:NumLines() > 0 then tt:AddLine(" ") end
    local star = fav and "  |TInterface\\COMMON\\FavoritesIcon:14:14:0:0|t" or ""
    tt:AddLine("|cff" .. accentHex() .. "TAP: Mythic Ledger|r" .. star)

    if rc then
        tt:AddDoubleLine("Keys together", "|cffffffff" .. tostring(rc.runs) .. "|r", LBL[1], LBL[2], LBL[3])
        local timed = string.format("|cff33dd66%d|r |cff8b8b8b(%d%%)|r", rc.timed,
            math.floor((rc.timedPct or 0) * 100 + 0.5))
        if rc.highestTimed then timed = timed .. "  |cff8b8b8bbest|r |cffffd200+" .. rc.highestTimed .. "|r" end
        tt:AddDoubleLine("Timed", timed, LBL[1], LBL[2], LBL[3])

        -- Average Mythic Ledger performance grade for this player across your shared runs. (Resolve
        -- outside an `and`-chain - that would truncate the multi-value return and drop the grade.)
        local avgSc, avgGr
        if ML.History and ML.History.AvgScore then avgSc, avgGr = ML.History.AvgScore(key) end
        if avgSc then
            tt:AddDoubleLine("Avg score", string.format("|cff%s%s|r |cff8b8b8b(%d)|r",
                gradeHex(avgGr), avgGr or "?", math.floor(avgSc + 0.5)), LBL[1], LBL[2], LBL[3])
        end

        local a = rc.avg or {}
        local prim = (rc.lastRole == "HEALER") and (a.hps and ("|cffffffff" .. Util.shortNum(a.hps) .. "|r HPS"))
                     or (a.dps and ("|cffffffff" .. Util.shortNum(a.dps) .. "|r DPS"))
        if prim then tt:AddDoubleLine("Avg", prim, LBL[1], LBL[2], LBL[3]) end
        local extra = {}
        if rc.lastRole == "HEALER" then
            if a.dispels then extra[#extra + 1] = n0(a.dispels) .. " dsp" end
        elseif a.interrupts then extra[#extra + 1] = n0(a.interrupts) .. " int" end
        if a.deaths then extra[#extra + 1] = n1(a.deaths) .. " deaths" end
        if #extra > 0 then tt:AddDoubleLine(" ", "|cffd7d9e2" .. table.concat(extra, "  ") .. "|r", LBL[1], LBL[2], LBL[3]) end

        if rc.lastRun then
            local rr = rc.lastRun
            local hex, txt
            if rr.status == ML.STATUS.TIMED then hex, txt = "33dd66", "timed"
            elseif rr.status == ML.STATUS.DEPLETED then hex, txt = "e0a030", "depleted"
            else hex, txt = "e0655a", "abandoned" end
            tt:AddDoubleLine("Last", string.format("|cffccd0dc%s|r |cffffd200+%s|r |cff%s(%s)|r",
                tostring(rr.dungeon), tostring(rr.level), hex, txt), LBL[1], LBL[2], LBL[3])
        end
    end
    if note then tt:AddLine("|cffc9a76aNote:|r |cffffffff" .. note .. "|r", nil, nil, nil, true) end
    local meta = DB.PlayerMeta and DB.PlayerMeta()[key]
    local tags = meta and meta.tags
    if type(tags) == "table" and #tags > 0 then
        tt:AddLine("|cff8b8b8bTags:|r |cffb9bccb" .. table.concat(tags, ", ") .. "|r", nil, nil, nil, true)
    end
    return true
end

-- Common gates.
local function on() return active and (DB.Ready and DB.Ready()) and not (DB.Settings and DB.Settings().playerTooltip == false) end

-- Per-surface gate: the master toggle above AND this surface's own checkbox (each defaults on, so a
-- missing/legacy settings table lights every surface up).
local function surfaceOn(surface)
    if not on() then return false end
    local s = DB.Settings and DB.Settings().tooltipSurfaces
    return not (type(s) == "table" and s[surface] == false)
end

-- Resolve a Name / Name-Realm (+ optional realm) to an identityKey we know.
local function keyForName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local full = name
    if not full:find("-", 1, true) then
        realm = (realm and realm ~= "" and realm)
            or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
        if realm and realm ~= "" then full = name .. "-" .. realm end
    end
    return ML.History and ML.History.PlayerByName and ML.History.PlayerByName(full) or nil
end

-- Present our block for `key` on GameTooltip, owner-managed and LEAK-SAFE. Call it on EVERY enter of a
-- row/friend (even with a nil key) so it can clean up:
--   * idempotent - re-presenting the same player is a no-op, so repeated OnEnter/Show never stacks a
--     second copy;
--   * self-clearing - moving to a player we have no data for takes OUR tooltip back down (but only if we
--     own it - a foreign tooltip, e.g. Raider.IO's, is left alone);
--   * coexists with Raider.IO - if another addon already populated the tooltip for this row we APPEND
--     under it once; if we're alone we own it and rebuild fresh each time.
-- `owner` is the frame we anchor to when creating it; `name` is a header used only when we build it fresh.
local function present(owner, anchor, name, key, ofsX, ofsY)
    if not on() then return end
    local tt = GameTooltip
    if tt._tapmlKey == key and key and tt:IsShown() then return end     -- already showing exactly this
    local weOwn = (tt:GetOwner() == owner) and tt._tapmlOwned

    if not (key and dataFor(key)) then
        if weOwn then tt:Hide() end                                     -- take down OURS; leave foreign content
        tt._tapmlKey, tt._tapmlOwned = nil, nil
        return
    end

    local foreignOwns = (tt:GetOwner() == owner) and tt:IsShown() and not tt._tapmlOwned
    if foreignOwns then
        tt._tapmlOwned = false                                          -- append under Raider.IO etc., once
    else
        tt:SetOwner(owner, anchor or "ANCHOR_RIGHT", ofsX, ofsY)        -- clears (incl. our own stale block)
        tt._tapmlOwned = true
    end
    if renderInto(tt, key, (not foreignOwns) and name or nil) then
        tt._tapmlKey = key
        tt:Show()
    end
end

-- OnLeave / Hide for owner-managed surfaces: drop our tooltip + stamps so nothing lingers.
local function clearOwned(owner)
    if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
    GameTooltip._tapmlKey, GameTooltip._tapmlOwned = nil, nil
end

----------------------------------------------------------------------
-- Scroll-box row hooking (mirrors Raider.IO's ScrollBoxUtil + HookUtil): hook each visible button's
-- OnEnter/OnLeave once, and re-hook when the box recycles frames.
----------------------------------------------------------------------
local hookedBtn = setmetatable({}, { __mode = "k" })
local function hookButtons(scrollBox, onEnter, onLeave)
    if not scrollBox then return end
    local function hookAll()
        local frames = scrollBox.buttons or (scrollBox.GetFrames and scrollBox:GetFrames())
        if type(frames) ~= "table" then return end
        for _, b in ipairs(frames) do
            if b and not hookedBtn[b] then
                hookedBtn[b] = true
                if onEnter then b:HookScript("OnEnter", onEnter) end
                if onLeave then b:HookScript("OnLeave", onLeave) end
            end
        end
    end
    hookAll()
    if scrollBox.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
        pcall(scrollBox.RegisterCallback, scrollBox, ScrollBoxListMixin.Event.OnUpdate, hookAll)
    elseif scrollBox.update and hooksecurefunc then
        hooksecurefunc(scrollBox, "update", hookAll)
    end
end

----------------------------------------------------------------------
-- Surface handlers.
----------------------------------------------------------------------
local function onUnit(tt, guid)                       -- unit tooltip (key IS the guid)
    if not (surfaceOn("unit") and tt == GameTooltip) then return end
    if type(guid) ~= "string" or not guid:find("^Player%-") then return end
    if UnitGUID and guid == UnitGUID("player") then return end
    renderInto(tt, guid)   -- appended to the existing unit lines; tt:Show handled by the caller/system
    tt:Show()
end

local function onSearchEntry(tt, resultID)            -- LFG group-finder search entry
    if not surfaceOn("lfg") then return end
    local ok, info = pcall(function() return C_LFGList and C_LFGList.GetSearchResultInfo(resultID) end)
    local leader = ML.ReadStr(ok and info and info.leaderName)   -- may be a Secret value; ReadStr -> nil if so
    local key = leader and keyForName(leader)
    if ML._debugEcho then
        ML.Log("LFG entry: leader=%s -> key=%s data=%s", tostring(leader), tostring(key),
            tostring(key ~= nil and dataFor(key) ~= nil))
    end
    if key and renderInto(tt, key) then tt:Show() end
end

local function whoEnter(self)
    if not surfaceOn("who") then return end
    local i = self.index or self.whoIndex
    if not i then return end
    local ok, info = pcall(function() return C_FriendList and C_FriendList.GetWhoInfo(i) end)
    local full = ok and info and info.fullName
    present(self, "ANCHOR_LEFT", full, full and keyForName(full))
end

local function guildEnter(self)
    if not surfaceOn("guild") then return end
    local i = self.index or self.guildIndex
    if not i then return end
    local ok, full = pcall(GetGuildRosterInfo, i)
    present(self, "ANCHOR_TOPLEFT", full, (ok and full) and keyForName(full))
end

-- Community member row: the row carries memberInfo with a name (realm best-effort).
local function communityEnter(self)
    if not surfaceOn("community") then return end
    local mi = self.memberInfo or (self.GetMemberInfo and self:GetMemberInfo())
    local name = mi and mi.name
    present(self, "ANCHOR_RIGHT", name, name and keyForName(name))
end

local function friendsShow(self)
    if not surfaceOn("friends") then return end
    local b = self.button
    local full
    if b then
        if _G.FRIENDS_BUTTON_TYPE_BNET and b.buttonType == FRIENDS_BUTTON_TYPE_BNET and C_BattleNet then
            local acc = C_BattleNet.GetFriendAccountInfo(b.id)
            local g = acc and acc.gameAccountInfo
            if g and g.characterName then
                full = (g.realmName and g.realmName ~= "") and (g.characterName .. "-" .. g.realmName) or g.characterName
            end
        elseif C_FriendList then
            local fi = C_FriendList.GetFriendInfoByIndex(b.id)
            full = fi and fi.name
        end
    end
    present(FriendsTooltip, "ANCHOR_BOTTOMRIGHT", full, full and keyForName(full),
        -FriendsTooltip:GetWidth(), -4)
end

----------------------------------------------------------------------
-- Install (once). Load-on-demand frames are hooked on ADDON_LOADED.
----------------------------------------------------------------------
local function hookGuild()
    if _G.GuildRosterContainer then hookButtons(GuildRosterContainer, guildEnter, clearOwned) end
end
local function hookCommunities()
    local ml = _G.CommunitiesFrame and CommunitiesFrame.MemberList
    if ml and ml.ScrollBox then hookButtons(ml.ScrollBox, communityEnter, clearOwned) end
end
local function hookWho()
    if _G.WhoFrame and WhoFrame.ScrollBox then hookButtons(WhoFrame.ScrollBox, whoEnter, clearOwned) end
end
-- LFG search-entry tooltip. LFGListUtil_SetSearchEntryTooltip lives in the load-on-demand
-- Blizzard_GroupFinder, so this may run empty at login and only take once the group finder opens.
local lfgHooked = false
local function hookLFG()
    if lfgHooked or not (_G.LFGListUtil_SetSearchEntryTooltip and hooksecurefunc) then return end
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tt, resultID) pcall(onSearchEntry, tt, resultID) end)
    lfgHooked = true
    if ML._debugEcho then ML.Log("LFG search-entry tooltip hook installed") end
end

function Tooltip.Start()
    active = true
    if hooked then return end
    hooked = true

    -- Unit tooltip.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
            pcall(onUnit, tt, data and data.guid)
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(self)
            local ok, _, unit = pcall(self.GetUnit, self)
            if ok and unit then pcall(onUnit, self, UnitGUID and UnitGUID(unit)) end
        end)
    end

    -- LFG group-finder search entry (Blizzard_GroupFinder is load-on-demand -> also retried below).
    pcall(hookLFG)

    -- Friends list tooltip (base UI). Hook Hide too so leaving the list drops our owned GameTooltip
    -- (the Show hook can't clean up on its own - moving off the list never re-fires it).
    if _G.FriendsTooltip and hooksecurefunc then
        hooksecurefunc(FriendsTooltip, "Show", function(self) pcall(friendsShow, self) end)
        hooksecurefunc(FriendsTooltip, "Hide", function() pcall(clearOwned, FriendsTooltip) end)
    end

    -- /who (base UI, present now) + guild/communities (load-on-demand -> ADDON_LOADED).
    pcall(hookWho)
    pcall(hookGuild)
    pcall(hookCommunities)
    if CreateFrame then
        local w = CreateFrame("Frame")
        w:RegisterEvent("ADDON_LOADED")
        w:SetScript("OnEvent", function(_, _, name)
            if name == "Blizzard_GuildUI" then pcall(hookGuild)
            elseif name == "Blizzard_Communities" then pcall(hookCommunities)
            elseif name == "Blizzard_FriendsFrame" then pcall(hookWho) end
            -- The group finder is load-on-demand and its addon name has drifted between builds; hookLFG is
            -- idempotent + cheap, so just retry it on every load until the function exists and it takes.
            if not lfgHooked then pcall(hookLFG) end
        end)
    end

    if ML.Log then ML.Log("Tooltip: player-history hooks installed") end
end

function Tooltip.Stop() active = false end
