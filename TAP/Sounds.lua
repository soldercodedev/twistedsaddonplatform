-- UIFoundry - Sounds.lua
-- Sound catalog + playback (shared from Twisteds Combat Alerts). Supports both Blizzard
-- SOUNDKIT sounds (PlaySound) and the bundled .ogg/.mp3 files in the Sounds/ folder
-- (PlaySoundFile), with safe fallbacks. Also a SoundSelect widget that previews on pick, and
-- these hook into Toast (opts.sound) for audible notifications.
--
--   theme:PlaySound("AirHorn")                     -- play a bundled sound (Master channel)
--   theme:PlaySound("RAID_WARNING", "SFX")         -- a Blizzard SOUNDKIT sound
--   theme:SoundSelect(parent, { value = "Focus", onChange = function(key) ... end })
--   theme:Toast({ text = "Pull!", variant = "warning", sound = "AirHorn" })

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

local SOUND_DIR = "Interface\\AddOns\\TAP\\Sounds\\"
local FALLBACK_SOUND = 8959   -- SOUNDKIT.RAID_WARNING numeric id (hard fallback)

-- An entry uses EITHER `kit` (a SOUNDKIT constant name) OR `file` (a bundled file name).
UIF.SOUNDS = {
    -- Built-in Blizzard sounds.
    { key = "RAID_WARNING", label = "Raid Warning",       kit = "RAID_WARNING" },
    { key = "READY_CHECK",  label = "Ready Check",         kit = "READY_CHECK" },
    { key = "ALARM_CLOCK",  label = "Alarm Clock",         kit = "ALARM_CLOCK_WARNING_3" },
    { key = "MAP_PING",     label = "Map Ping",            kit = "MAP_PING" },
    { key = "SUBTLE",       label = "Subtle Notification", kit = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    { key = "PVP_WARNING",  label = "PvP Warning",         kit = "PVPTHROUGHQUEUE" },
    -- Bundled custom files (Sounds/).
    { key = "AcousticGuitar", label = "Acoustic Guitar", file = "AcousticGuitar.ogg" },
    { key = "Adds", label = "Adds", file = "Adds.ogg" },
    { key = "AirHorn", label = "Air Horn", file = "AirHorn.ogg" },
    { key = "Applause", label = "Applause", file = "Applause.ogg" },
    { key = "BananaPeelSlip", label = "Banana Peel Slip", file = "BananaPeelSlip.ogg" },
    { key = "BatmanPunch", label = "Batman Punch", file = "BatmanPunch.ogg" },
    { key = "BikeHorn", label = "Bike Horn", file = "BikeHorn.ogg" },
    { key = "Blast", label = "Blast", file = "Blast.ogg" },
    { key = "Bleat", label = "Bleat", file = "Bleat.ogg" },
    { key = "Boss", label = "Boss", file = "Boss.ogg" },
    { key = "BoxingArenaSound", label = "Boxing Arena Sound", file = "BoxingArenaSound.ogg" },
    { key = "Brass", label = "Brass", file = "Brass.mp3" },
    { key = "CartoonVoiceBaritone", label = "Cartoon Voice Baritone", file = "CartoonVoiceBaritone.ogg" },
    { key = "CartoonWalking", label = "Cartoon Walking", file = "CartoonWalking.ogg" },
    { key = "CatMeow2", label = "Cat Meow 2", file = "CatMeow2.ogg" },
    { key = "ChickenAlarm", label = "Chicken Alarm", file = "ChickenAlarm.ogg" },
    { key = "Circle", label = "Circle", file = "Circle.ogg" },
    { key = "CowMooing", label = "Cow Mooing", file = "CowMooing.ogg" },
    { key = "Cross", label = "Cross", file = "Cross.ogg" },
    { key = "Diamond", label = "Diamond", file = "Diamond.ogg" },
    { key = "DontRelease", label = "Dont Release", file = "DontRelease.ogg" },
    { key = "DoubleWhoosh", label = "Double Whoosh", file = "DoubleWhoosh.ogg" },
    { key = "Drums", label = "Drums", file = "Drums.ogg" },
    { key = "Empowered", label = "Empowered", file = "Empowered.ogg" },
    { key = "ErrorBeep", label = "Error Beep", file = "ErrorBeep.ogg" },
    { key = "Focus", label = "Focus", file = "Focus.ogg" },
    { key = "Glass", label = "Glass", file = "Glass.mp3" },
    { key = "GoatBleating", label = "Goat Bleating", file = "GoatBleating.ogg" },
    { key = "HeartbeatSingle", label = "Heartbeat Single", file = "HeartbeatSingle.ogg" },
    { key = "Idiot", label = "Idiot", file = "Idiot.ogg" },
    { key = "KittenMeow", label = "Kitten Meow", file = "KittenMeow.ogg" },
    { key = "Left", label = "Left", file = "Left.ogg" },
    { key = "Moon", label = "Moon", file = "Moon.ogg" },
    { key = "Next", label = "Next", file = "Next.ogg" },
    { key = "OhNo", label = "Oh No", file = "OhNo.ogg" },
    { key = "Portal", label = "Portal", file = "Portal.ogg" },
    { key = "Protected", label = "Protected", file = "Protected.ogg" },
    { key = "Release", label = "Release", file = "Release.ogg" },
    { key = "Right", label = "Right", file = "Right.ogg" },
    { key = "RingingPhone", label = "Ringing Phone", file = "RingingPhone.ogg" },
    { key = "RoaringLion", label = "Roaring Lion", file = "RoaringLion.ogg" },
    { key = "RobotBlip", label = "Robot Blip", file = "RobotBlip.ogg" },
    { key = "RoosterChickenCalls", label = "Rooster Chicken Calls", file = "RoosterChickenCalls.ogg" },
    { key = "RunAway", label = "Run Away", file = "RunAway.ogg" },
    { key = "SharpPunch", label = "Sharp Punch", file = "SharpPunch.ogg" },
    { key = "SheepBleat", label = "Sheep Bleat", file = "SheepBleat.ogg" },
    { key = "Shotgun", label = "Shotgun", file = "Shotgun.ogg" },
    { key = "Skull", label = "Skull", file = "Skull.ogg" },
    { key = "Spread", label = "Spread", file = "Spread.ogg" },
    { key = "Square", label = "Square", file = "Square.ogg" },
    { key = "SqueakyToyShort", label = "Squeaky Toy Short", file = "SqueakyToyShort.ogg" },
    { key = "SquishFart", label = "Squish Fart", file = "SquishFart.ogg" },
    { key = "Stack", label = "Stack", file = "Stack.ogg" },
    { key = "Star", label = "Star", file = "Star.ogg" },
    { key = "Switch", label = "Switch", file = "Switch.ogg" },
    { key = "SynthChord", label = "Synth Chord", file = "SynthChord.ogg" },
    { key = "TadaFanfare", label = "Tada Fanfare", file = "TadaFanfare.ogg" },
    { key = "Taunt", label = "Taunt", file = "Taunt.ogg" },
    { key = "TempleBellHuge", label = "Temple Bell Huge", file = "TempleBellHuge.ogg" },
    { key = "Torch", label = "Torch", file = "Torch.ogg" },
    { key = "Triangle", label = "Triangle", file = "Triangle.ogg" },
    { key = "WarningSiren", label = "Warning Siren", file = "WarningSiren.ogg" },
    { key = "WaterDrop", label = "Water Drop", file = "WaterDrop.ogg" },
    { key = "Xylophone", label = "Xylophone", file = "Xylophone.ogg" },
}

-- Default notification sound per toast variant (used when a toast passes sound = true).
UIF.TOAST_SOUNDS = { info = "SUBTLE", success = "READY_CHECK", warning = "ALARM_CLOCK", danger = "RAID_WARNING" }

function Mixin:SoundList() return self.sounds or UIF.SOUNDS end

function Mixin:SoundLabel(key)
    for _, s in ipairs(self:SoundList()) do if s.key == key then return s.label end end
    return key or "?"
end

-- Resolve a key -> "file", fullPath  or  "kit", soundKitID (with safe fallback).
function Mixin:ResolveSound(key)
    local entry
    for _, s in ipairs(self:SoundList()) do if s.key == key then entry = s break end end
    if entry and entry.file then return "file", (self.soundDir or SOUND_DIR) .. entry.file end
    if entry and entry.kit and type(SOUNDKIT) == "table" then
        local id = SOUNDKIT[entry.kit]
        if type(id) == "number" then return "kit", id end
    end
    if type(SOUNDKIT) == "table" and type(SOUNDKIT.RAID_WARNING) == "number" then return "kit", SOUNDKIT.RAID_WARNING end
    return "kit", FALLBACK_SOUND
end

-- Play a sound key on a channel (Master/SFX/Music/Ambience/Dialog). A bundled file that
-- fails to play falls back to a built-in.
function Mixin:PlaySound(key, channel)
    channel = channel or "Master"
    local mode, value = self:ResolveSound(key)
    if mode == "file" then
        local ok = PlaySoundFile and PlaySoundFile(value, channel)
        if not ok and PlaySound then PlaySound(FALLBACK_SOUND, channel) end
    elseif PlaySound then
        PlaySound(value, channel)
    end
end

----------------------------------------------------------------------
-- SoundSelect: a dropdown of all sounds (grouped Blizzard / Custom) that PREVIEWS the sound
-- when you pick it.
--   theme:SoundSelect(parent, { width = 220, value = "Focus", channel = "Master",
--       preview = true, onChange = function(key) ... end })
----------------------------------------------------------------------
function Mixin:SoundSelect(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w = opts.width or 220
    local b = CreateFrame("Button", nil, parent); theme:StylePanel(b, C.card); b:SetSize(w, 26)
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(theme.FONT, 12); b.fs:SetPoint("LEFT", 8, 0); b.fs:SetPoint("RIGHT", -20, 0); b.fs:SetJustifyH("LEFT"); b.fs:SetTextColor(unpack(C.text))
    b.caret = b:CreateFontString(nil, "OVERLAY"); b.caret:SetFont(theme.FONT, 10); b.caret:SetPoint("RIGHT", -7, -1); b.caret:SetText("v"); b.caret:SetTextColor(unpack(C.accent))
    b._value = opts.value or (theme:SoundList()[1] and theme:SoundList()[1].key)
    b:SetScript("OnEnter", function(self) theme:FillPaint(self, theme.C.hover) end)
    b:SetScript("OnLeave", function(self) theme:FillPaint(self, theme.C.card) end)
    function b:Refresh() self.fs:SetText(theme:SoundLabel(self._value)) end
    b:SetScript("OnClick", function(self)
        local items, startedCustom = {}, false
        items[#items + 1] = { label = "Blizzard Sounds", header = true }
        for _, s in ipairs(theme:SoundList()) do
            if s.file and not startedCustom then items[#items + 1] = { label = "Custom Sounds", header = true }; startedCustom = true end
            items[#items + 1] = { label = s.label, value = s.key }
        end
        theme:OpenMenu(self, items, function() return self._value end, function(v)
            self._value = v; self:Refresh()
            if opts.preview ~= false then theme:PlaySound(v, opts.channel) end
            if opts.onChange then opts.onChange(v) end
        end)
    end)
    b:Refresh()
    return b
end
