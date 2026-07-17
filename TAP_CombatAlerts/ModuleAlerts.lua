-- TAP_CombatAlerts - ModuleAlerts.lua
-- The "Combat Alerts" suite module. The rule-based cue ENGINE (Core.lua + Conditions.lua) is
-- unchanged; this rebuilds the whole alerts UI - list + rule editor (typed & advanced) - on the
-- suite's Builder, and wires the module on/off to the engine's master enable (TCC.SetEnabled).

local addonName, TCC = ...
local UIF   = _G.UIFoundry
local Suite = _G.TAP
if not Suite then return end

----------------------------------------------------------------------
-- Static choice tables (mirror the engine metadata).
----------------------------------------------------------------------
local CHANNELS = { { "Master", "Master" }, { "SFX", "Sound Effects" }, { "Music", "Music" }, { "Ambience", "Ambience" } }
local CHAT_CHANNELS = { { "SELF", "Print to me" }, { "SAY", "Say" }, { "YELL", "Yell" }, { "PARTY", "Party" },
    { "RAID", "Raid" }, { "INSTANCE_CHAT", "Instance" }, { "GUILD", "Guild" }, { "OFFICER", "Officer" }, { "EMOTE", "Emote" } }
local LOAD_COMBAT   = { { "any", "Any" }, { "in", "In combat" }, { "out", "Out of combat" } }
local LOAD_GROUP    = { { "any", "Any" }, { "solo", "Solo" }, { "party", "In a party" }, { "raid", "In a raid" } }
local LOAD_INSTANCE = { { "any", "Anywhere" }, { "none", "Open world" }, { "any_instance", "Any instance" },
    { "party", "Dungeon" }, { "raid", "Raid" }, { "arena", "Arena" }, { "pvp", "Battleground" }, { "scenario", "Scenario" } }
local OP_CHOICES    = { { "ALL", "Match ALL  (and)" }, { "ANY", "Match ANY  (or)" } }

-- Condition types hidden from the pickers (still evaluated for any existing rule that uses them).
-- Group-range checks can't be made reliable across all content with Midnight's API changes, so we
-- hide them and prefer a spell-range check to your target instead.
local HIDDEN_CTYPES = { groupRange = true }
local CTYPE_CHOICES, CTYPE_META = {}, {}
for _, ct in ipairs(TCC.CONDITION_TYPES or {}) do
    local k = ct.type or ct.key   -- engine metadata keys condition types by `.type`
    if k then
        CTYPE_META[k] = ct
        if not HIDDEN_CTYPES[k] then CTYPE_CHOICES[#CTYPE_CHOICES + 1] = { k, ct.label } end
    end
end

-- Sounds, fonts and the icon-picker set all come from the SUITE's shared catalogs (one set for
-- the whole suite), not TCC's old local copies.
local theme = Suite.uiTheme
local SOUND_CHOICES = {}
if theme then for _, s in ipairs(theme:SoundList()) do SOUND_CHOICES[#SOUND_CHOICES + 1] = { s.key, s.label } end end
local FONT_CHOICES = {}
if theme then for _, f in ipairs(theme:FontList()) do FONT_CHOICES[#FONT_CHOICES + 1] = { f.key, f.label } end end
local ICON_PICK = {}
if theme then
    for _, slug in ipairs({ "bell", "bell-ringing", "target", "flame", "bolt", "skull", "shield", "sword",
        "heart", "flask", "star", "hourglass", "clock", "droplet", "paw", "bone", "feather", "leaf",
        "mountain", "diamond", "hexagon", "pentagon", "key", "lock", "power", "refresh", "sparkles" }) do
        local tex = theme:GetIcon(slug)
        if tex then ICON_PICK[#ICON_PICK + 1] = { value = tex, texture = tex, label = slug } end
    end
end
local function browseIcon(b, current, onPick)
    b.theme:OpenIconPicker({
        title        = "Choose an icon",
        icons        = ICON_PICK,
        current      = current,
        columns      = 9,
        allowDefault = true,
        defaultLabel = "Use the default (alert-type) icon",
        customInput  = true,
        customLabel  = "...or type a spell name, item, icon ID or texture path:",
        customValue  = (type(current) == "string" and current) or "",
        onPick       = onPick,
    })
end
local KIND_CARDS = {
    { kind = "range",    title = "Range",    desc = "Out of / in range of a spell." },
    { kind = "target",   title = "Target",   desc = "No target, hostile, dead, ..." },
    { kind = "threat",   title = "Threat",   desc = "Pulled aggro / high threat." },
    { kind = "pet",      title = "Pet",      desc = "Pet dead / missing." },
    { kind = "item",     title = "Item",     desc = "Trinket ready / on cooldown." },
    { kind = "advanced", title = "Advanced", desc = "Combine conditions with AND / OR." },
}

-- A default list icon per alert kind (framework icons), used when a rule has no explicit icon.
local KIND_ICON = { range = "target-arrow", target = "target", threat = "flame",
    pet = "paw", item = "flask", advanced = "sparkles" }
local KIND_ICON_TEX = {}
if theme then for k, slug in pairs(KIND_ICON) do KIND_ICON_TEX[k] = theme:GetIcon(slug) end end

----------------------------------------------------------------------
-- Editor state (which rule the settings page is currently editing; nil = the list).
----------------------------------------------------------------------
local editorId
local editorTab   -- which editor tab is showing (per the tab set below)
local listTab = "alerts"   -- active list page in the docked top-nav: alerts | profiles | settings
local TAB_TIPS = {
    alerts   = "Your alerts - create, edit, enable, duplicate, or delete them.",
    profiles = "Which alert set this character uses, and copy alerts between profiles.",
    settings = "Sound channel, check rate, import / export, and the minimap button.",
}

local function softApply()
    if TCC.RebuildEngine then TCC.RebuildEngine() end
    if TCC.Evaluate then TCC.Evaluate() end
end

local function ruleIcon(rule)
    if rule.navIcon and rule.navIcon ~= "" then return TCC.ResolveIcon(rule.navIcon) or rule.navIcon end
    -- Default to the icon that represents this alert's type.
    if rule.kind and KIND_ICON_TEX[rule.kind] then return KIND_ICON_TEX[rule.kind] end
    if TCC.GetAlertKind and rule.kind then local k = TCC.GetAlertKind(rule.kind); if k and k.icon then return k.icon end end
    if rule.action and rule.action.showIcon and rule.action.icon and rule.action.icon ~= "" then return TCC.ResolveIcon(rule.action.icon) end
    return 134400
end

----------------------------------------------------------------------
-- Live visual preview (text + draggable icon), rebuilt from the old standalone UI onto the
-- suite. One frame, reused; drag the icon to set the alert's icon offset.
----------------------------------------------------------------------
local previewFrame
local function buildAlertPreview(parent, theme)
    local C = theme.C
    local f = CreateFrame("Frame", nil, parent); theme:StylePanel(f, { 0.05, 0.05, 0.06 }, C.border)
    f.fs = f:CreateFontString(nil, "OVERLAY"); f.fs:SetPoint("CENTER")
    local ag = f.fs:CreateAnimationGroup()
    local p1 = ag:CreateAnimation("Alpha"); p1:SetFromAlpha(1); p1:SetToAlpha(0.3); p1:SetDuration(0.5); p1:SetOrder(1)
    local p2 = ag:CreateAnimation("Alpha"); p2:SetFromAlpha(0.3); p2:SetToAlpha(1); p2:SetDuration(0.5); p2:SetOrder(2)
    ag:SetLooping("REPEAT"); f.pulse = ag

    local ib = CreateFrame("Button", nil, f); ib:SetSize(24, 24); ib:EnableMouse(true); ib:RegisterForDrag("LeftButton"); ib:Hide()
    ib.tex = ib:CreateTexture(nil, "ARTWORK"); ib.tex:SetAllPoints(); ib.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ib:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Drag to position the icon", theme:AccentHeader()); GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", GameTooltip_Hide)
    ib:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local pf = self:GetParent(); local a, ps = pf._action, pf._pscale or 1
            if not a then return end
            local s = pf:GetEffectiveScale(); local cx, cy = GetCursorPosition()
            local fcx, fcy = pf.fs:GetCenter()
            if fcx and s and s > 0 then
                a.iconX = ((cx / s) - fcx) / ps; a.iconY = ((cy / s) - fcy) / ps
                self:ClearAllPoints(); self:SetPoint("CENTER", pf.fs, "CENTER", a.iconX * ps, a.iconY * ps)
            end
        end)
    end)
    ib:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local pf = self:GetParent(); if pf._onMove then pf._onMove() end
    end)
    f.iconBtn = ib
    return f
end

local function updateAlertPreview(f, a, onMove)
    if not f then return end
    local fs = tonumber(a.fontSize) or 48
    local psize = math.floor(12 + (math.max(12, math.min(96, fs)) - 12) * 30 / 84)
    local pscale = psize / fs
    f.fs:SetFont(TCC.ResolveFont(a.font), psize, "THICKOUTLINE")
    f.fs:SetText(a.visual and ((a.visualText and a.visualText ~= "" and a.visualText) or "ALERT") or "")
    local c = a.color or { 1, 0.1, 0.1 }; f.fs:SetTextColor(c[1], c[2], c[3])
    if a.visual and a.pulse ~= false then
        if not f.pulse:IsPlaying() then f.pulse:Play() end
    else
        f.pulse:Stop(); f.fs:SetAlpha(1)
    end
    f._action = a; f._pscale = pscale; f._onMove = onMove
    local tex = a.showIcon and TCC.ResolveIcon(a.icon)
    if tex then
        local isz = math.max(10, (tonumber(a.iconSize) or 40) * pscale)
        f.iconBtn:SetSize(isz, isz); f.iconBtn.tex:SetTexture(tex)
        f.iconBtn:ClearAllPoints()
        f.iconBtn:SetPoint("CENTER", f.fs, "CENTER", (a.iconX or 0) * pscale, (a.iconY or 64) * pscale)
        f.iconBtn:Show()
    else
        f.iconBtn:Hide()
    end
end

----------------------------------------------------------------------
-- "New Alert" modal: a card per alert type (icon + title + description). Built on the framework's
-- theme:Modal so it dims the rest of the viewport and closes on Esc / click-outside / X.
----------------------------------------------------------------------
local function openNewAlertModal(onPick)
    local theme = Suite.uiTheme
    if not theme then return end
    local C = theme.C
    local COLS, GAP, CH = 2, 12, 84
    local rows = math.ceil(#KIND_CARDS / COLS)
    theme:Modal({
        title       = "Choose an alert type",
        icon        = "plus",
        width       = 632,
        bodyHeight  = rows * CH + (rows - 1) * GAP,
        dismissable = true,
        content = function(body, modal)
            local CW = (body:GetWidth() - (COLS - 1) * GAP) / COLS
            for i, card in ipairs(KIND_CARDS) do
                local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
                local cd = CreateFrame("Button", nil, body); cd:SetSize(CW, CH)
                cd:SetPoint("TOPLEFT", body, "TOPLEFT", col * (CW + GAP), -row * (CH + GAP))
                theme:StylePanel(cd, C.card, C.border)
                local ic = cd:CreateTexture(nil, "ARTWORK"); ic:SetSize(38, 38); ic:SetPoint("LEFT", 16, 0)
                ic:SetTexCoord(0, 1, 0, 1); ic:SetTexture(theme:GetIcon(KIND_ICON[card.kind] or "bell"))
                local ti = cd:CreateFontString(nil, "OVERLAY"); ti:SetFont(theme.FONT, 14)
                ti:SetPoint("TOPLEFT", cd, "TOPLEFT", 66, -14); ti:SetTextColor(unpack(C.text)); ti:SetText(card.title .. " Alert")
                local de = cd:CreateFontString(nil, "OVERLAY"); de:SetFont(theme.FONT, 11)
                de:SetPoint("TOPLEFT", cd, "TOPLEFT", 66, -38); de:SetPoint("RIGHT", cd, "RIGHT", -12, 0)
                de:SetJustifyH("LEFT"); de:SetWordWrap(true); de:SetTextColor(unpack(C.subtext)); de:SetText(card.desc)
                cd:SetScript("OnEnter", function(self) theme:StylePanel(self, UIF.mix(C.card, C.accent, 0.18), C.accent) end)
                cd:SetScript("OnLeave", function(self) theme:StylePanel(self, C.card, C.border) end)
                cd._kind = card.kind
                cd:SetScript("OnClick", function(self) modal:Close(); if onPick then onPick(self._kind) end end)
            end
        end,
    }):Open()
end

----------------------------------------------------------------------
-- Small render helpers (each takes/returns the running y). `P` bundles builder + refresh.
----------------------------------------------------------------------
local function newPen(b, win, x, w)
    local C = b.theme.C
    local P = { b = b, C = C, x = x, w = w, repage = function() if win then win:Refresh() end end }
    function P:tip(widget, t, body) if widget then b.theme:SetTip(widget, t, body) end return widget end
    return P
end

----------------------------------------------------------------------
-- Spell / item search (lightweight - no bundled database). Spells come from your spellbook + your
-- current auras; items from your equipped gear + bags; plus a direct numeric-ID lookup. Enough to
-- pick the abilities / trinkets you actually use, which is what alert conditions reference.
----------------------------------------------------------------------
local function scanSpells(lower, add)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        for l = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(l)
            if line then
                for s = (line.itemIndexOffset or 0) + 1, (line.itemIndexOffset or 0) + (line.numSpellBookItems or 0) do
                    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, s, bank)
                    if ok and info and info.spellID then
                        local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(info.spellID)
                        local nm = (si and si.name) or info.name
                        if nm and nm:lower():find(lower, 1, true) then add(info.spellID, nm, si and si.iconID) end
                    end
                end
            end
        end
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            for i = 1, 40 do
                local a = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
                if not a then break end
                if a.name and a.spellId and a.name:lower():find(lower, 1, true) then add(a.spellId, a.name, a.icon) end
            end
        end
    end
end

local function scanItems(lower, add)
    for slot = 1, 19 do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id and C_Item then
            local nm = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
            if nm and nm:lower():find(lower, 1, true) then add(id, nm, C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) end
        end
    end
    if C_Container then
        for bag = 0, 4 do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    local nm = info.itemName or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID))
                    if nm and nm:lower():find(lower, 1, true) then add(info.itemID, nm, info.iconFileID) end
                end
            end
        end
    end
end

-- A search modal (dimmed) with a live-filtered result list. onPick(id) gets the chosen id.
local function openSpellItemSearch(theme, mode, onPick)
    local isItem = (mode == "item")
    local ROWS = 14
    theme:Modal({
        title       = isItem and "Find an item" or "Find a spell",
        icon        = isItem and "flask" or "sparkles",
        width       = 480,
        bodyHeight  = 52 + ROWS * 20,
        dismissable = true,
        content = function(body, modal)
            local C, bw = theme.C, body:GetWidth()
            local search = theme:EditBox(body); search:Configure(bw, 26, "", nil)
            search:ClearAllPoints(); search:SetPoint("TOPLEFT"); search:SetPoint("TOPRIGHT")
            local hint = body:CreateFontString(nil, "OVERLAY"); hint:SetFont(theme.FONT, 11)
            hint:SetPoint("TOPLEFT", 2, -30); hint:SetTextColor(unpack(C.subtext))
            hint:SetText(isItem and "Type an item name or ID (searches your gear & bags)"
                or "Type a spell name or ID (searches your spellbook & auras)")
            local rows = {}
            for i = 1, ROWS do
                local r = CreateFrame("Button", nil, body); r:SetSize(bw, 20)
                r:SetPoint("TOPLEFT", 0, -50 - (i - 1) * 20)
                r:EnableMouse(true); r:RegisterForClicks("AnyUp")
                theme:StylePanel(r, C.bg)
                r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(16, 16); r.ic:SetPoint("LEFT", 3, 0)
                r.fs = r:CreateFontString(nil, "OVERLAY"); r.fs:SetFont(theme.FONT, 12); r.fs:SetPoint("LEFT", 24, 0); r.fs:SetTextColor(unpack(C.text))
                r:SetScript("OnEnter", function(self) theme:StylePanel(self, UIF.mix(C.bg, C.accent, 0.30)) end)
                r:SetScript("OnLeave", function(self) theme:StylePanel(self, C.bg) end)
                r:Hide(); rows[i] = r
            end
            local function doSearch(text)
                text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                local results, seen = {}, {}
                local function add(id, name, icon)
                    if id and name and not seen[id] then seen[id] = true; results[#results + 1] = { id = id, name = name, icon = icon } end
                end
                if text ~= "" then
                    local num, lower = tonumber(text), text:lower()
                    if isItem then
                        if num then local _, nm, ic = TCC.ResolveItem(num); add(num, nm or ("Item " .. num), ic) end
                        scanItems(lower, add)
                    else
                        if num then local i2, n2, c2 = TCC.ResolveSpell(num); if i2 then add(i2, n2 or ("Spell " .. num), c2) end end
                        scanSpells(lower, add)
                    end
                    -- Full database: loaded ON DEMAND, CENTRALLY, by the suite (only pulled in the
                    -- first time a search actually needs it). Format is "id\tname" per line.
                    if #text >= 3 and Suite then
                        local blob = isItem and (Suite.GetItemDB and Suite:GetItemDB())
                            or (Suite.GetSpellDB and Suite:GetSpellDB())
                        if blob then
                            local hits = 0
                            for line in blob:gmatch("[^\n]+") do
                                local sep = line:find("\t", 1, true)
                                if sep and line:sub(sep + 1):lower():find(lower, 1, true) then
                                    add(tonumber(line:sub(1, sep - 1)), line:sub(sep + 1))
                                    hits = hits + 1
                                    if hits >= 60 then break end
                                end
                            end
                        end
                    end
                end
                for i, r in ipairs(rows) do
                    local res = results[i]
                    if res then
                        r.ic:SetTexture(res.icon or 134400)
                        r.fs:SetText(res.name .. "  |cff808080#" .. res.id .. "|r")
                        r:SetScript("OnClick", function() modal:Close(); onPick(res.id) end)
                        r:Show()
                    else
                        r:Hide()
                    end
                end
            end
            search:SetScript("OnTextChanged", function(self) doSearch(self:GetText()) end)
            if C_Timer and C_Timer.After then C_Timer.After(0, function() search:SetFocus() end) end
        end,
    }):Open()
end

-- One condition's params (also used for a typed alert's trigger). Renders each param on its own
-- row: [label]  [control]. Returns new y.
local function renderParams(P, cond, y)
    local b, C = P.b, P.C
    local meta = CTYPE_META[cond.type]
    if not meta then return y end
    -- classSpec: two dropdowns (single class + single spec), bound to cond.class / cond.spec.
    if cond.type == "classSpec" then
        local classes = {}
        for _, cls in ipairs(UIF.GetClassList()) do classes[#classes + 1] = { cls.token, cls.name } end
        b:Label("Class", P.x, y - 2, C.subtext)
        local dd = b:Dropdown(P.x + 70, y); dd:SetChoices(160, classes, function() return cond.class end,
            function(v) cond.class = v; cond.spec = "all"; softApply(); P.repage() end)
        y = y - 30
        local specs = {}
        for _, sp in ipairs(UIF.GetSpecList(cond.class, true)) do specs[#specs + 1] = { tostring(sp.id), sp.name } end
        b:Label("Spec", P.x, y - 2, C.subtext)
        local sd = b:Dropdown(P.x + 70, y); sd:SetChoices(180, specs, function() return tostring(cond.spec or "all") end,
            function(v) cond.spec = (v == "all") and "all" or (tonumber(v) or v); softApply() end)
        return y - 30
    end
    for _, p in ipairs(meta.params or {}) do
        local show = true
        if p.showIf then show = (cond[p.showIf.key] == p.showIf.value) end
        if show then
            b:Label((p.pre or p.key), P.x, y - 2, C.subtext)
            local cw = math.min(p.width or 180, P.w - 90)
            if p.kind == "choice" then
                -- p.choices is an ordered array of {value,label} pairs (from the engine metadata) -
                -- pass it straight through so the dropdown values match cond[p.key].
                local dd = b:Dropdown(P.x + 80, y); dd:SetChoices(cw, p.choices or {}, function() return cond[p.key] or p.default end,
                    function(v) cond[p.key] = v; softApply() end)
                P:tip(dd, p.pre or p.key, p.hint)
            elseif p.kind == "number" then
                P:tip(b:EditBox(P.x + 80, y, 80, tostring(cond[p.key] or p.default or 0), function(t)
                    cond[p.key] = tonumber(t) or p.default or 0; softApply() end), p.pre or p.key, p.hint)
            elseif p.kind == "spell" or p.kind == "item" then
                -- Lookup widget: a live icon of the resolved spell/item, a name/ID field, and a Find
                -- button that opens a searchable picker. The icon confirms the match; the stored value
                -- is the ID, which keeps working inside Mythic+ where name lookups are restricted.
                local resolve = (p.kind == "item") and TCC.ResolveItem or TCC.ResolveSpell
                local function fieldDisplay()
                    local cur = cond[p.key]
                    local id, nm, ic = resolve(cur)
                    local disp = (id and (nm or ("#" .. id))) or (cur and cur ~= "" and tostring(cur)) or ""
                    return disp, ic or 134400
                end
                local disp, icTex = fieldDisplay()
                local ew = math.max(90, math.min(160, P.w - 260))
                local iconW = b:Icon(P.x + 80, y - 3, { icon = icTex, iconCoords = { 0, 1, 0, 1 } }); iconW:SetSize(24, 24)
                local ebW
                ebW = b:EditBox(P.x + 110, y, ew, disp, function(t)
                    local rid = resolve(t)
                    cond[p.key] = rid or t; softApply(); P.repage()
                end)
                P:tip(ebW, p.pre or p.key, (p.hint or "") .. "  Type a name or ID, or use Find.")
                P:tip(b:Button(P.x + 116 + ew, y - 2, 68, "Find", "default", function()
                    openSpellItemSearch(b.theme, p.kind, function(pid)
                        cond[p.key] = tostring(pid); softApply()
                        -- Update this row's icon + box directly (robust regardless of re-render), then
                        -- refresh the page so everything else (preview, list) reflects it too.
                        local d, itex = fieldDisplay()
                        if ebW.SetText then ebW:SetText(d); if ebW.SetCursorPosition then ebW:SetCursorPosition(0) end end
                        if iconW.ApplyStyle then iconW:ApplyStyle({ icon = itex, iconCoords = { 0, 1, 0, 1 } }); iconW:SetSize(24, 24) end
                        P.repage()
                    end)
                end, { icon = "target", iconSize = 12 }), "Search", "Search your " .. ((p.kind == "item") and "gear & bags" or "spellbook & auras") .. ".")
            else
                P:tip(b:EditBox(P.x + 80, y, cw, tostring(cond[p.key] or ""), function(t) cond[p.key] = t; softApply() end),
                    p.pre or p.key, p.hint)
            end
            y = y - 30
        end
    end
    return y
end

-- One condition inside an advanced group: type dropdown + remove X + its params. Returns new y.
local function renderCondition(P, group, cond, index, y)
    local b, C = P.b, P.C
    local dd = b:Dropdown(P.x, y); dd:SetChoices(180, CTYPE_CHOICES, function() return cond.type end,
        function(v)
            local fresh = TCC.NewCondition(v)
            for k in pairs(cond) do cond[k] = nil end
            for k, val in pairs(fresh) do cond[k] = val end
            softApply(); P.repage()
        end)
    P:tip(b:Button(P.x + 190, y - 2, 26, "X", "danger", function()
        table.remove(group.children, index); softApply(); P.repage()
    end), "Remove", "Remove this condition.")
    y = y - 32
    local inner = newPen(b, nil, P.x + 16, P.w - 16); inner.repage = P.repage
    y = renderParams(inner, cond, y)
    return y - 4
end

-- An AND/OR group (recursive). Returns new y.
local function renderGroup(P, group, y, depth)
    local b, C = P.b, P.C
    group.op = group.op or "ALL"
    group.children = group.children or {}
    local yTop = y
    b:Label(depth == 0 and "Fire when" or "Sub-group", P.x, y - 2, C.accent, 12)
    local dd = b:Dropdown(P.x + 90, y); dd:SetChoices(150, OP_CHOICES, function() return group.op end,
        function(v) group.op = v; softApply(); P.repage() end)
    y = y - 32
    local child = newPen(b, nil, P.x + 14, P.w - 14); child.repage = P.repage
    for i, node in ipairs(group.children) do
        if node.children then
            y = renderGroup(child, node, y, depth + 1)
            P:tip(b:Button(child.x, y, 90, "Remove group", "default", function()
                table.remove(group.children, i); softApply(); P.repage() end), "Remove group", "Delete this sub-group.")
            y = y - 30
        else
            y = renderCondition(child, group, node, i, y)
        end
    end
    b:Button(P.x + 14, y, 110, "+ Condition", "default", function()
        table.insert(group.children, TCC.NewCondition("combat")); softApply(); P.repage() end)
    b:Button(P.x + 130, y, 90, "+ Group", "default", function()
        table.insert(group.children, { op = "ALL", children = { TCC.NewCondition("combat") } }); softApply(); P.repage() end)
    y = y - 34
    b:Box(P.x, yTop, P.w, yTop - y, 0.04 + depth * 0.02, 0, C.accent)
    return y - 8
end

----------------------------------------------------------------------
-- Action sub-sections (shared by typed + advanced). Each takes (P, a, y) -> y.
----------------------------------------------------------------------
local function sectionGrace(P, a, y)
    local b = P.b
    b:Sub("GRACE", P.x, y); y = y - 26
    b:Label("Hold conditions for", P.x, y - 2, P.C.subtext)
    P:tip(b:Slider(P.x + 130, y), "Grace period", "Conditions must hold this long before the alert fires (0 = instant)."):Configure(
        150, 0, 5, 0.1, function() return tonumber(a.debounce) or 0 end, function(v) a.debounce = v; softApply() end, "%.1fs")
    return y - 30
end

local function sectionSound(P, a, y)
    local b, C = P.b, P.C
    b:Sub("SOUND", P.x, y); y = y - 26
    P:tip(b:Toggle(P.x, y, a.playSound, function(v) a.playSound = v; softApply() end), "Play sound", "Play a sound when the alert fires.")
    b:Label("Play a sound", P.x + 46, y - 2, C.text)
    b:Label("Sound", P.x + 200, y - 2, C.subtext)
    local dd = b:Dropdown(P.x + 250, y); dd:SetChoices(200, SOUND_CHOICES, function() return a.soundKey end,
        function(v) a.soundKey = v; if TCC.PlayKey then TCC.PlayKey(v, TCC.db and TCC.db.channel) end; softApply() end)
    P:tip(dd, "Sound", "Which sound plays (previews on pick).")
    y = y - 32
    b:Label("Min gap", P.x, y - 2, C.subtext)
    P:tip(b:EditBox(P.x + 80, y, 60, tostring(a.cooldown or 3), function(t) a.cooldown = tonumber(t) or 3; softApply() end),
        "Cooldown", "Minimum seconds between repeats.")
    P:tip(b:Toggle(P.x + 170, y, a.loopSound, function(v) a.loopSound = v; softApply() end), "Loop", "Repeat the sound while active.")
    b:Label("Loop while active", P.x + 216, y - 2, C.text)
    if a.loopSound then
        b:Label("every", P.x + 360, y - 2, C.subtext)
        b:EditBox(P.x + 400, y, 50, tostring(a.loopInterval or 1.5), function(t) a.loopInterval = tonumber(t) or 1.5; softApply() end)
    end
    return y - 34
end

local function sectionVisual(P, a, rule, y, win)
    local b, C = P.b, P.C
    a.color = a.color or { 1, 0.1, 0.1 }
    -- Keep the live preview in sync as controls change, without a full page rebuild.
    local function refreshPrev() updateAlertPreview(previewFrame, a, function() softApply() end) end

    b:Sub("VISUAL", P.x, y); y = y - 26

    -- Live preview (on-screen text + draggable icon) - one persistent frame, hidden on view change.
    if not previewFrame then previewFrame = buildAlertPreview(b.content, b.theme) end
    local boxH = 130
    b:Box(P.x, y, P.w - 10, boxH, 0.16, 0, C.card)
    previewFrame:SetParent(b.content)
    b:Transient(previewFrame)
    previewFrame:ClearAllPoints()
    previewFrame:SetPoint("TOPLEFT", b.content, "TOPLEFT", P.x + 3, y - 3)
    previewFrame:SetSize(P.w - 16, boxH - 6)
    previewFrame:Show()
    refreshPrev()
    b:Label("live preview - drag the icon to position it", P.x, y - boxH - 2, C.subtext, 10)
    y = y - boxH - 20

    P:tip(b:Toggle(P.x, y, a.visual, function(v) a.visual = v; softApply(); P.repage() end), "Show text", "Flash on-screen text when the alert fires.")
    b:Label("Show on-screen text", P.x + 46, y - 2, C.text)
    y = y - 30
    if a.visual then
        b:Label("Text", P.x, y - 2, C.subtext)
        b:EditBox(P.x + 80, y, 200, a.visualText or "ALERT", function(t) a.visualText = t; refreshPrev(); softApply() end)
        b:Label("Color", P.x + 300, y - 2, C.subtext)
        P:tip(b:Swatch(P.x + 352, y - 2, a.color, function() refreshPrev(); softApply() end, "Text color"), "Text color", "Alert text color.")
        y = y - 32
        b:Label("Font", P.x, y - 2, C.subtext)
        local fd = b:Dropdown(P.x + 80, y); fd:SetChoices(200, FONT_CHOICES, function() return a.font or "UBUNTU" end,
            function(v) a.font = v; refreshPrev(); softApply() end)
        y = y - 44   -- extra headroom so the slider's value readout (above the thumb) clears the row above
        b:Label("Text size", P.x, y - 2, C.subtext)
        b:Slider(P.x + 100, y):Configure(200, 12, 96, 1, function() return tonumber(a.fontSize) or 48 end,
            function(v) a.fontSize = v; refreshPrev(); softApply() end, "%d")
        y = y - 34
        P:tip(b:Toggle(P.x, y, a.pulse ~= false, function(v) a.pulse = v; refreshPrev(); softApply() end), "Pulse", "Fade in and out.")
        b:Label("Pulse (fade)", P.x + 46, y - 2, C.text)
        y = y - 32
    end
    P:tip(b:Toggle(P.x, y, a.showIcon, function(v) a.showIcon = v; refreshPrev(); softApply(); P.repage() end), "Show icon", "Show an icon with the alert.")
    b:Label("Show an icon", P.x + 46, y - 2, C.text)
    y = y - 30
    if a.showIcon then
        b:Label("Icon", P.x, y - 2, C.subtext)
        b:Icon(P.x + 70, y - 4, { icon = TCC.ResolveIcon(a.icon) or 134400, iconCoords = { 0, 1, 0, 1 } }):SetSize(28, 28)
        P:tip(b:Button(P.x + 110, y - 2, 120, "Choose icon", "default", function()
            browseIcon(b, a.icon, function(v) a.icon = v or ""; refreshPrev(); softApply(); P.repage() end)
        end, { icon = "photo", iconSize = 13 }), "Choose icon", "Pick a framework icon, or type a spell / item / ID to use its icon.")
        y = y - 46   -- extra headroom so the slider's value readout (above the thumb) clears the row above
        b:Label("Icon size", P.x, y - 2, C.subtext)
        b:Slider(P.x + 100, y):Configure(200, 16, 96, 1, function() return tonumber(a.iconSize) or 40 end,
            function(v) a.iconSize = v; refreshPrev(); softApply() end, "%d")
        y = y - 32
    end
    -- Position controls (drive the runtime frame).
    b:Button(P.x, y, 150, "Move on screen", "default", function()
        if win then win:Hide() end
        if TCC.StartRuleMover then TCC.StartRuleMover(rule) end
    end, { icon = "arrows-sort", iconSize = 13 })
    b:Button(P.x + 160, y, 110, "Test cue", "primary", function()
        if win then win:Hide() end
        if TCC.StartTest then TCC.StartTest(rule) end
    end, { icon = "bolt", iconSize = 13 })
    return y - 34
end

local function sectionChat(P, a, y)
    local b, C = P.b, P.C
    b:Sub("CHAT", P.x, y); y = y - 26
    P:tip(b:Toggle(P.x, y, a.chatMessage, function(v) a.chatMessage = v; softApply(); P.repage() end), "Chat message", "Send a chat message / print when the alert fires.")
    b:Label("Send a chat message", P.x + 46, y - 2, C.text)
    y = y - 30
    if a.chatMessage then
        b:Label("Channel", P.x, y - 2, C.subtext)
        local dd = b:Dropdown(P.x + 80, y); dd:SetChoices(160, CHAT_CHANNELS, function() return a.chatChannel or "SELF" end,
            function(v) a.chatChannel = v; softApply() end)
        y = y - 32
        b:Label("Text", P.x, y - 2, C.subtext)
        b:EditBox(P.x + 80, y, P.w - 100, a.chatText or "", function(t) a.chatText = t; softApply() end)
        b:Label("(blank = the alert's name)", P.x + 80, y - 22, C.subtext, 10)
        y = y - 40
    end
    return y - 4
end

local function sectionLoad(P, rule, y)
    local b, C = P.b, P.C
    rule.load = rule.load or { combat = "any", instance = "any", group = "any" }
    local ld = rule.load
    ld.specs = ld.specs or {}
    b:Sub("LOAD  (only active when...)", P.x, y); y = y - 26
    b:Label("Class / Spec", P.x, y - 2, C.subtext)
    P:tip(b:ClassSpecButton(P.x + 90, y, { selected = ld.specs, width = 220,
        title = "Load this alert on these specs", hint = "none checked = every class / spec",
        onChange = function() softApply() end }), "Class / Spec", "Only run this alert on the chosen specs (none = all).")
    y = y - 32
    b:Label("Combat", P.x, y - 2, C.subtext)
    b:Dropdown(P.x + 80, y):SetChoices(150, LOAD_COMBAT, function() return ld.combat or "any" end, function(v) ld.combat = v; softApply() end)
    b:Label("Group", P.x + 250, y - 2, C.subtext)
    b:Dropdown(P.x + 300, y):SetChoices(150, LOAD_GROUP, function() return ld.group or "any" end, function(v) ld.group = v; softApply() end)
    y = y - 32
    b:Label("Zone", P.x, y - 2, C.subtext)
    b:Dropdown(P.x + 80, y):SetChoices(180, LOAD_INSTANCE, function() return ld.instance or "any" end, function(v) ld.instance = v; softApply() end)
    return y - 34
end

----------------------------------------------------------------------
-- Rule editor (typed + advanced).
----------------------------------------------------------------------
-- The tab set depends on the alert kind. Each tab is { key, label }.
local function editorTabs(rule)
    if rule.kind and rule.kind ~= "advanced" then
        return { { "load", "Load" }, { "trigger", "Trigger" }, { "sound", "Sound" }, { "visual", "Visual" }, { "chat", "Chat" } }
    end
    return { { "load", "Load" }, { "conditions", "Conditions" }, { "timing", "Timing" }, { "sound", "Sound" }, { "visual", "Visual" }, { "chat", "Chat" } }
end

local function renderTriggerTab(P, rule, x, y, w, win)
    local b, C = P.b, P.C
    b:Sub("TRIGGER", x, y); y = y - 26
    rule.trigger = rule.trigger or TCC.NewCondition("combat")
    local meta = TCC.GetAlertKind and TCC.GetAlertKind(rule.kind)
    -- Offer only the non-hidden triggers (group-range is hidden - see HIDDEN_CTYPES).
    local trig = {}
    if meta and meta.triggers then
        for _, tk in ipairs(meta.triggers) do if not HIDDEN_CTYPES[tk] then trig[#trig + 1] = tk end end
    end
    if #trig > 1 then
        b:Label("Check", x, y - 2, C.subtext)
        local tch = {}; for _, tk in ipairs(trig) do tch[#tch + 1] = { tk, CTYPE_META[tk] and CTYPE_META[tk].label or tk } end
        b:Dropdown(x + 60, y):SetChoices(200, tch, function() return rule.trigger.type end,
            function(v) rule.trigger = TCC.NewCondition(v); softApply(); P.repage() end)
        y = y - 32
    end
    y = renderParams(P, rule.trigger, y)
    -- Debounce / grace: hold the trigger this long before the alert fires (typed alerts had this
    -- on the trigger; it was dropped when the editor went tabbed - restore it here).
    return sectionGrace(P, rule.action, y - 8)
end

local function renderConditionsTab(P, rule, x, y, w)
    local b, C = P.b, P.C
    rule.root = rule.root or { op = "ALL", children = { TCC.NewCondition("combat") } }
    b:Sub("CONDITIONS", x, y); y = y - 26
    if TCC.DescribeRuleText then
        local _, dh = b:Wrap(TCC.DescribeRuleText(rule.root) or "", x, y, w - 20, C.subtext, 11)
        y = y - (dh + 8)
    end
    return renderGroup(P, rule.root, y, 0)
end

local function renderEditor(mod, b, x, y, w, win)
    local C = b.theme.C
    local rule = TCC.GetSelectedRule and TCC.GetSelectedRule()
    if not rule then editorId = nil; return y end
    local P = newPen(b, win, x, w)

    -- Header: alert type on the LEFT, Back button aligned RIGHT (across from it).
    b:Heading(rule.kind and rule.kind ~= "advanced" and (rule.kind:gsub("^%l", string.upper) .. " Alert") or "Advanced Alert",
        x, y, "h2")
    P:tip(b:Button(x + w - 104, y - 4, 92, "Back", "default", function() editorId = nil; if win then win:Refresh() end end,
        { icon = "arrow-left", iconSize = 13 }), "Back", "Return to the alert list.")
    y = y - 38

    -- Identity header (always visible above the tabs): name + enabled, then the list icon.
    b:Label("Name", x, y - 2, C.subtext)
    b:EditBox(x + 60, y, w - 240, rule.name or "", function(t) rule.name = t; TCC.RefreshManager() end)
    P:tip(b:Toggle(x + w - 120, y, rule.enabled and true or false, function(v) rule.enabled = v; softApply(); TCC.RefreshManager() end),
        "Enabled", "Enable or disable this alert.")
    b:Label("Enabled", x + w - 74, y - 2, C.text)
    y = y - 32
    b:Label("List icon", x, y - 2, C.subtext)
    b:Icon(x + 70, y - 4, { icon = ruleIcon(rule), iconCoords = { 0, 1, 0, 1 } }):SetSize(28, 28)
    P:tip(b:Button(x + 110, y - 2, 130, "Choose icon", "default", function()
        browseIcon(b, rule.navIcon, function(v) rule.navIcon = (v ~= "" and v) or nil; TCC.RefreshManager() end)
    end, { icon = "photo", iconSize = 13 }), "Choose icon",
        "Pick a framework icon, or type a spell / item / ID. Choose \"default\" to use the alert-type icon.")
    b:Label("(defaults to the alert-type icon)", x + 252, y - 2, C.subtext, 10)
    y = y - 42

    -- Clear break between the alert meta fields and the tabbed sections.
    b:Box(x, y + 6, w - 10, 1, 0.18, 0, C.border)
    y = y - 12

    -- Tab bar. Validate the active tab against this rule's tab set.
    local tabs = editorTabs(rule)
    local active = editorTab
    local valid = false
    for _, t in ipairs(tabs) do if t[1] == active then valid = true break end end
    if not valid then active = tabs[1][1]; editorTab = active end
    local tw, tgap = 92, 6
    for i, t in ipairs(tabs) do
        local isA = (t[1] == active)
        b:Button(x + (i - 1) * (tw + tgap), y, tw, t[2], isA and "primary" or "default",
            function() editorTab = t[1]; if win then win:Refresh() end end)
    end
    y = y - 30
    b:Box(x, y + 2, #tabs * (tw + tgap) - tgap, 2, 0.5, 0, C.accent)   -- accent underline
    y = y - 14

    -- Active tab body.
    if active == "trigger" then
        y = renderTriggerTab(P, rule, x, y, w, win)
    elseif active == "conditions" then
        y = renderConditionsTab(P, rule, x, y, w)
    elseif active == "timing" then
        y = sectionGrace(P, rule.action, y)
    elseif active == "sound" then
        y = sectionSound(P, rule.action, y)
    elseif active == "visual" then
        y = sectionVisual(P, rule.action, rule, y, win)
    elseif active == "chat" then
        y = sectionChat(P, rule.action, y)
    elseif active == "load" then
        y = sectionLoad(P, rule, y)
    end
    y = y - 16

    -- Footer rule buttons (persistent across tabs).
    b:Button(x, y, 100, "Duplicate", "default", function()
        TCC.selectedRuleId = rule.id; if TCC.DuplicateSelectedRule then TCC.DuplicateSelectedRule() end
        editorId = TCC.selectedRuleId; TCC.RefreshManager()
    end, { icon = "copy", iconSize = 13 })
    b:Button(x + 110, y, 100, "Export", "default", function()
        if b.theme.ShowCopyDialog and TCC.ExportRule then b.theme:ShowCopyDialog("Export alert", TCC.ExportRule(rule) or "") end
    end, { icon = "upload", iconSize = 13 })
    b:Button(x + 220, y, 100, "Delete", "danger", function()
        b.theme:Confirm({ title = "Delete '" .. (rule.name or "alert") .. "'?", variant = "danger", confirmLabel = "Delete",
            message = "Remove this alert permanently?", onConfirm = function()
                TCC.selectedRuleId = rule.id; if TCC.DeleteSelectedRule then TCC.DeleteSelectedRule() end
                editorId = nil; TCC.RefreshManager()
            end })
    end, { icon = "trash", iconSize = 13 })
    return y - 34
end

----------------------------------------------------------------------
-- Rule list + global options.
----------------------------------------------------------------------
-- The list view is split into three docked-nav pages: Alerts, Profiles, and Settings (global).
local function ensureDB(d)
    d.rules = d.rules or {}
    d.channel = d.channel or "Master"
    d.pollInterval = tonumber(d.pollInterval) or 0.25
end

-- PROFILES page: which alert set this character uses, + copy alerts between profiles.
local function renderProfiles(mod, b, x, y, w, win)
    local C = b.theme.C
    local d = TCC.db
    ensureDB(d)
    local P = newPen(b, win, x, w)

    -- PROFILE (which alert set this character uses, + copy alerts between profiles)
    b:Sub("PROFILE", x, y); y = y - 36
    b:Label("Active profile", x, y - 2, C.subtext)
    local active = TCC.activeProfile or TCC.AccountKey()
    -- Choices: Account-wide, this character, then any custom profiles (deduped, in that order).
    local choices, seen = {}, {}
    local function addChoice(name)
        if not name or seen[name] then return end
        seen[name] = true; choices[#choices + 1] = { name, TCC.ProfileLabel(name) }
    end
    addChoice(TCC.AccountKey())
    addChoice(TCC.CurrentCharKey())
    for _, n in ipairs(TCC.ListProfiles()) do addChoice(n) end
    P:tip(b:Dropdown(x + 110, y), "Active profile",
        "Which alert set this character uses. Account-wide is shared across all your characters; "
        .. "others are private. Pick This character, or create your own named profiles."):SetChoices(
        300, choices, function() return TCC.activeProfile end,
        function(v) TCC.SetActiveProfile(v) end)
    y = y - 40

    -- New / Rename / Delete named profiles (the Account profile can't be renamed or deleted).
    local canEdit = active ~= TCC.AccountKey()
    P:tip(b:Button(x + 110, y, 92, "New", "default", function()
        if b.theme.ShowInputDialog then
            b.theme:ShowInputDialog("New profile",
                "Name the new profile, then switch to it. Use the Copy tool below to bring alerts in from another profile.",
                "Create", function(txt)
                    local nm, why = TCC.CreateProfile(txt, true)
                    if not nm then print("|cffa06cf0Combat Alerts|r " ..
                        (why == "exists" and "a profile with that name already exists."
                        or why == "reserved" and "that name is reserved."
                        or "enter a profile name.")) end
                end)
        end
    end, { icon = "plus", iconSize = 13 }), "New profile", "Create a new named profile and switch to it.")
    P:tip(b:Button(x + 210, y, 92, "Rename", canEdit and "default" or "ghost", function()
        if not canEdit then return end
        if b.theme.ShowInputDialog then
            b.theme:ShowInputDialog("Rename profile", "New name for this profile.", "Rename", function(txt)
                local nn, why = TCC.RenameProfile(active, txt)
                if not nn then print("|cffa06cf0Combat Alerts|r " ..
                    (why == "exists" and "that name is taken." or "couldn't rename the profile.")) end
            end)
        end
    end, { icon = "pencil", iconSize = 13 }), "Rename profile",
        canEdit and "Rename the active profile." or "The account-wide profile can't be renamed.")
    P:tip(b:Button(x + 310, y, 92, "Delete", canEdit and "danger" or "ghost", function()
        if not canEdit then return end
        b.theme:Confirm({ title = "Delete profile?", variant = "danger", confirmLabel = "Delete",
            message = "Delete '" .. TCC.ProfileLabel(active) .. "' and its alerts? Any character using it "
                .. "falls back to Account-wide.",
            onConfirm = function() TCC.DeleteProfile(active) end })
    end, { icon = "trash", iconSize = 13 }), "Delete profile",
        canEdit and "Delete the active profile." or "The account-wide profile can't be deleted.")
    y = y - 46

    -- Copy alerts between any two profiles (account or any character that has its own set).
    local names = TCC.ListProfiles()
    local hasMe = false
    for _, n in ipairs(names) do if n == TCC.CurrentCharKey() then hasMe = true end end
    if not hasMe then names[#names + 1] = TCC.CurrentCharKey() end
    local profChoices = {}
    for _, n in ipairs(names) do profChoices[#profChoices + 1] = { n, TCC.ProfileLabel(n) } end
    TCC._copyFrom = TCC._copyFrom or TCC.AccountKey()
    TCC._copyTo   = TCC._copyTo   or TCC.CurrentCharKey()
    TCC._copyRule = TCC._copyRule or "__all__"
    b:Label("Copy from", x, y - 2, C.subtext)
    P:tip(b:Dropdown(x + 110, y), "Source profile", "Copy alerts FROM this profile."):SetChoices(300, profChoices,
        function() return TCC._copyFrom end,
        function(v) TCC._copyFrom = v; TCC._copyRule = "__all__"; TCC.RefreshManager() end)
    y = y - 34
    b:Label("Alert", x, y - 2, C.subtext)
    local ruleItems = { { "__all__", "All alerts" } }
    for _, r in ipairs(TCC.GetProfileRuleList(TCC._copyFrom)) do ruleItems[#ruleItems + 1] = { r.id, r.name } end
    P:tip(b:Dropdown(x + 110, y), "Alert to copy", "Copy every alert (replaces destination) or just one (appended)."):SetChoices(
        300, ruleItems, function() return TCC._copyRule end, function(v) TCC._copyRule = v end)
    y = y - 34
    b:Label("Copy to", x, y - 2, C.subtext)
    P:tip(b:Dropdown(x + 110, y), "Destination profile", "Copy alerts INTO this profile."):SetChoices(300, profChoices,
        function() return TCC._copyTo end, function(v) TCC._copyTo = v end)
    y = y - 40
    P:tip(b:Button(x, y, 150, "Copy alerts", "primary", function()
        TCC.CopyProfileRules(TCC._copyFrom, TCC._copyTo, TCC._copyRule)
    end, { icon = "copy", iconSize = 14 }), "Copy alerts",
        "Copy the selected alert(s) from the source profile into the destination.")
    y = y - 50
    return y
end

-- SETTINGS page: global sound/check-rate, import / export / reset, and the minimap toggle.
local function renderGlobal(mod, b, x, y, w, win)
    local C = b.theme.C
    local d = TCC.db
    ensureDB(d)
    local P = newPen(b, win, x, w)

    -- MODULE: the master enable/disable for Combat Alerts (shared platform block).
    y = b:ModuleToggle(x, y, w, mod, { onToggle = function() if win then win:Refresh() end end,
        sub = "When off, no alerts fire. Your alerts and profiles are kept." })

    -- SOUND: which channel alert sounds play on.
    b:Sub("SOUND", x, y); y = y - 36
    b:Label("Sound channel", x, y - 2, C.subtext)
    P:tip(b:Dropdown(x + 110, y), "Sound channel", "Which channel alert sounds play on."):SetChoices(
        160, CHANNELS, function() return d.channel or "Master" end, function(v) d.channel = v; softApply() end)
    b:Label("the audio channel every alert sound plays on", x + 300, y - 2, C.subtext, 10)
    y = y - 48

    -- PERFORMANCE: how often the engine re-checks your situation.
    b:Sub("PERFORMANCE", x, y); y = y - 36
    b:Label("Check rate", x, y - 2, C.subtext)
    P:tip(b:Slider(x + 110, y), "Check rate",
        "How often alerts re-check your situation. Lower = snappier alerts but slightly more CPU; higher = lighter."):Configure(
        170, 0.1, 1.0, 0.05, function() return tonumber(d.pollInterval) or 0.25 end,
        function(v) d.pollInterval = v; if TCC.ApplySettings then TCC.ApplySettings() end end, "%.2fs")
    b:Label("seconds between checks - lower is snappier, higher is lighter on CPU", x + 300, y - 2, C.subtext, 10)
    y = y - 44

    -- BACKUP & DATA: export / import the whole set (a round-trip pair), with the destructive reset
    -- set apart below its own caption so it can't be fired by reflex next to the safe actions.
    b:Sub("BACKUP & DATA", x, y); y = y - 26
    local _, dh = b:Wrap("Export your whole alert set to a text string to back it up or share it with others; "
        .. "Import adds alerts from a string shared with you.", x, y, w - 20, C.subtext, 11)
    y = y - (dh or 16) - 12
    P:tip(b:Button(x, y, 130, "Export all", "default", function()
        if b.theme.ShowCopyDialog and TCC.ExportAll then b.theme:ShowCopyDialog("Your alerts (copy this to back up or share)", TCC.ExportAll() or "") end
    end, { icon = "upload", iconSize = 14 }), "Export all alerts", "Copy all your alerts out as a text string to back up or share. Bring them back with Import.")
    P:tip(b:Button(x + 140, y, 130, "Import", "default", function()
        if b.theme.ShowInputDialog then
            b.theme:ShowInputDialog("Import alerts", "Paste an exported alert string, then Accept. Imported alerts are ADDED to your list.", "Import", function(txt)
                if TCC.Import then
                    local ok, res = TCC.Import(txt)
                    if ok then print(("|cffa06cf0Combat Alerts|r imported %d alert%s."):format(res or 0, (res == 1) and "" or "s"))
                    else print("|cffff5555Combat Alerts import failed:|r " .. tostring(res)) end
                end
                TCC.RefreshManager()
            end)
        end
    end, { icon = "download", iconSize = 14 }), "Import alerts", "Paste alerts exported from here (or shared with you). They're added to your list.")
    y = y - 42
    local _, dh2 = b:Wrap("Reset restores the default alert set for the active profile - it deletes your "
        .. "current alerts and can't be undone.", x, y, w - 20, C.subtext, 11)
    y = y - (dh2 or 16) - 12
    P:tip(b:Button(x, y, 130, "Reset all", "danger", function()
        b.theme:Confirm({ title = "Reset all alerts?", variant = "danger", confirmLabel = "Reset",
            message = "Delete your alerts and restore the default set for this profile. This can't be undone.",
            onConfirm = function() if TCC.ResetSettings then TCC.ResetSettings() end; TCC.RefreshManager() end })
    end, { icon = "refresh", iconSize = 14 }), "Reset all alerts", "Delete your alerts and restore the default set for this profile.")
    y = y - 46

    -- MINIMAP: its own section (off by default; managed by the platform).
    if Suite and Suite.IsMinimapButtonShown then
        b:Sub("MINIMAP", x, y); y = y - 30
        P:tip(b:Toggle(x, y, Suite:IsMinimapButtonShown("combatAlerts"),
            function(v) Suite:SetMinimapButtonShown("combatAlerts", v) end),
            "Minimap icon", "Show a Combat Alerts button on the minimap (left-click opens this page).")
        b:Label("Show a minimap button", x + 46, y - 2, C.text)
        b:Label("Left-click it to open this page.", x + 46, y - 20, C.subtext, 10)
        y = y - 42
    end
    return y
end

-- ALERTS page: the rule list + New Alert.
local function renderAlerts(mod, b, x, y, w, win)
    local C = b.theme.C
    local d = TCC.db
    ensureDB(d)
    local P = newPen(b, win, x, w)

    -- ALERTS  (shorten the underline so the New Alert button doesn't sit on top of it)
    b:Sub("ALERTS", x, y, w - 170)
    b:Button(x + w - 140, y - 4, 120, "New Alert", "primary", function()
        openNewAlertModal(function(kind)
            if kind == "advanced" then if TCC.AddRule then TCC.AddRule() end
            elseif TCC.NewTypedAlert then TCC.NewTypedAlert(kind) end
            editorId = TCC.selectedRuleId
            if win then win:Refresh() end
        end)
    end, { icon = "plus", iconSize = 14 })
    y = y - 34

    local rules = TCC.GetRules and TCC.GetRules() or d.rules

    -- Active-profile context. The Alerts list always shows the CURRENTLY ACTIVE profile's alert set,
    -- but nothing on this page said which profile that is (you had to open the Profiles tab to find
    -- out). Describe it inline: which profile is live, whether it's shared or private, and how many
    -- alerts it holds - so it's clear what these alerts belong to before you start editing them.
    if TCC.ProfileLabel then
        local active     = TCC.activeProfile or TCC.AccountKey()
        local isAccount  = (active == TCC.AccountKey())
        local isThisChar = (active == TCC.CurrentCharKey())
        local count = rules and #rules or 0
        local scope
        if isAccount then
            scope = "Shared across all your characters - every character without its own profile uses this set."
        elseif isThisChar then
            scope = "A private set used only by this character; your other characters aren't affected."
        else
            scope = "A custom profile, currently active on this character."
        end
        local desc = ("%d alert%s.  %s  Switch profiles or copy alerts between them on the Profiles tab."):format(
            count, count == 1 and "" or "s", scope)
        local iconSz = 22
        local tx = x + 14 + iconSz + 10
        local tw = math.max(60, w - (tx - x) - 24)
        b:Label("ACTIVE PROFILE  ·  " .. TCC.ProfileLabel(active), tx, y - 12, C.accent, 11)
        local _, dh = b:Wrap(desc, tx, y - 30, tw, C.subtext, 11)
        local boxH = 30 + (dh or 16) + 12
        b:Box(x, y, w - 10, boxH, 0.05, 0, C.accent)   -- subtle tinted fill behind the text
        b:Box(x, y, 3, boxH, 0.9, 0, C.accent)         -- accent left rail
        b:Icon(x + 12, y - 13, { icon = b.theme:GetIcon("user") or 134400, iconCoords = { 0, 1, 0, 1 } }):SetSize(iconSz, iconSz)
        y = y - boxH - 14
    end

    if not rules or #rules == 0 then
        b:Wrap("No alerts yet. Click |cffffffffNew Alert|r to create one.", x, y, w - 44, C.subtext, 12)
        return y - 30
    end
    for _, rule in ipairs(rules) do
        local yTop, rid = y, rule.id
        -- Row layout: everything centered on a 36px band; the three action buttons are compact
        -- icon-only squares, right-aligned with even gaps, with the enable toggle to their left.
        local bs = 28                              -- action-button size (square)
        local delX  = x + w - 28 - bs              -- last button, right edge 8px inside the row box
        local copyX = delX  - 8 - bs
        local editX = copyX - 8 - bs
        local togX  = editX - 16 - 38              -- toggle is 38 wide
        b:Icon(x + 6, yTop - 2, { icon = ruleIcon(rule), iconCoords = { 0, 1, 0, 1 } }):SetSize(32, 32)
        b:Label(rule.name or "?", x + 48, yTop - 10, rule.enabled and C.text or C.subtext, 13)
        P:tip(b:Toggle(togX, yTop - 9, rule.enabled and true or false, function(v)
            rule.enabled = v; softApply(); TCC.RefreshManager() end), "Enabled", "Enable or disable this alert.")
        P:tip(b:Button(editX, yTop - 4, bs, "", "default", function() editorId = rid; if win then win:Refresh() end end,
            { icon = "edit", iconSize = 15, height = bs }), "Edit", "Open this alert's settings.")
        P:tip(b:Button(copyX, yTop - 4, bs, "", "default", function()
            TCC.selectedRuleId = rid; if TCC.DuplicateSelectedRule then TCC.DuplicateSelectedRule() end; TCC.RefreshManager()
        end, { icon = "copy", iconSize = 15, height = bs }), "Duplicate", "Make a copy.")
        P:tip(b:Button(delX, yTop - 4, bs, "", "danger", function()
            b.theme:Confirm({ title = "Delete '" .. (rule.name or "alert") .. "'?", variant = "danger", confirmLabel = "Delete",
                message = "Remove this alert permanently?", onConfirm = function()
                    TCC.selectedRuleId = rid; if TCC.DeleteSelectedRule then TCC.DeleteSelectedRule() end; TCC.RefreshManager() end })
        end, { icon = "trash", iconSize = 15, height = bs }), "Delete", "Remove this alert.")
        y = yTop - 36
        b:Box(x, yTop, w - 20, yTop - y, rule.enabled and 0.05 or 0.03, 0, rule.enabled and C.accent or C.card)
        y = y - 10
    end
    return y - 6
end

local function Settings(mod, b, x, y, w, win)
    if not TCC.db then b:Wrap("Loading...", x, y, w, b.theme.C.subtext, 12); return y - 20 end
    if editorId and TCC.GetSelectedRule then TCC.selectedRuleId = editorId end

    -- Dock the tab strip flush under the title bar (matches Mythic Ledger). It must be re-issued every
    -- render - Window:Refresh clears the nav first. While editing a rule the editor is a sub-view of the
    -- Alerts page, so keep Alerts highlighted; picking any tab leaves the editor.
    if win and win.SetTopNav then
        win:SetTopNav({
            items = {
                { key = "alerts",   label = "Alerts",   icon = "bell" },
                { key = "profiles", label = "Profiles", icon = "user" },
                { key = "settings", label = "Settings", icon = "settings" },
            },
            active = editorId and "alerts" or listTab, height = 30,
            onSelect = function(key)
                editorId = nil   -- leave the editor (if open) when switching top-level page
                listTab = key
                if win then win:Refresh() end
            end,
            tip = function(key) return TAB_TIPS[key] end,
        })
        y = y - 4   -- small breathing room below the docked nav
    end

    -- Disabled: overlay every view except the Settings page (where the enable toggle lives), so the
    -- module can always be switched back on but nothing else is usable meanwhile.
    if mod and mod.IsEnabled and not mod:IsEnabled() and (editorId or listTab ~= "settings") then
        return b:DisabledOverlay(x, y, w, { subtitle = "Go to the Settings tab to turn Combat Alerts back on.",
            onSettings = function() editorId = nil; listTab = "settings"; if win then win:Refresh() end end })
    end

    if editorId then return renderEditor(mod, b, x, y, w, win) end
    if listTab == "profiles" then return renderProfiles(mod, b, x, y, w, win) end
    if listTab == "settings" then return renderGlobal(mod, b, x, y, w, win) end
    return renderAlerts(mod, b, x, y, w, win)
end

----------------------------------------------------------------------
-- Register the module. Its on/off IS the alert engine's master enable.
----------------------------------------------------------------------
local mod
local applying = false
local ready = false

local baseSetEnabled = TCC.SetEnabled
if baseSetEnabled then
    TCC.SetEnabled = function(on)
        baseSetEnabled(on)
        TCC.alertsEnabled = on and true or false
        if applying or not mod then return end
        applying = true
        if mod:IsEnabled() ~= (on and true or false) then mod:SetEnabled(on) end
        applying = false
    end
end
local function pushToEngine(on)
    if not ready or applying then return end
    applying = true
    if TCC.SetEnabled then TCC.SetEnabled(on) end
    applying = false
end

mod = Suite:RegisterModule({
    id      = "combatAlerts",
    title   = "Combat Alerts",
    desc    = "Rule-based audible & visual cues for combat-safe signals - no target, out of range, "
           .. "aggro, pet down, item ready - fired by alerts you build here.",
    icon    = "bell",
    addon   = "TAP_CombatAlerts",
    default = true,
    fullPage = true,   -- we render our own tabbed page; suite skips the "SETTINGS" band
    rendersWhenDisabled = true,   -- keep our page (and its Settings tab) reachable while disabled
    changelog = TCC.CHANGELOG,
    OnEnable  = function() pushToEngine(true) end,
    OnDisable = function() pushToEngine(false) end,
    OnSelect  = function() editorId = nil; listTab = "alerts" end,   -- reopening lands on the Alerts list
    Settings  = Settings,
})

-- Optional minimap icon for this module (hidden by default; toggled in this module's settings).
if Suite.RegisterMinimapButton then
    Suite:RegisterMinimapButton("combatAlerts", {
        icon = "Interface\\AddOns\\TAP_CombatAlerts\\assets\\images\\tap_combat_alerts_icon.tga",
        title = "|cffa06cf0Combat Alerts|r", action = "open the alerts",
        onClick = function() Suite:OpenWindow("mod:combatAlerts") end,
        defaultHidden = true,
    })
end

local boot = CreateFrame("Frame"); boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    if TCC.db then
        applying = true
        mod:SetEnabled(TCC.db.enabled and true or false)
        applying = false
        TCC.alertsEnabled = TCC.db.enabled and true or false
    end
    ready = true
end)
