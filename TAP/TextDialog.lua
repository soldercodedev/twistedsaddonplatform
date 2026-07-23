-- TAP - TextDialog.lua
-- A reusable multi-line text dialog with a scroll-clipped editbox. WoW addons can't open a
-- browser or the clipboard directly, so this is how you hand a string to the user
-- (export / copy a link) or take one back (import / paste). Each theme builds one.
--
--   theme:ShowCopyDialog(title, text, info)         -- selected + ready for Ctrl+C
--   theme:ShowLinkDialog(title, url)                -- same, phrased for a URL
--   theme:ShowInputDialog(title, info, acceptLabel, function(text) ... end)  -- paste + accept

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

local function ensureDialog(theme)
    if theme._textDlg then return theme._textDlg end
    local C = theme.C
    local name = TAP.NextId(theme.id .. "TextDialog")
    local d = CreateFrame("Frame", name, UIParent)
    d:SetSize(470, 300); d:SetPoint("CENTER"); d:SetFrameStrata("FULLSCREEN_DIALOG"); d:SetToplevel(true); d:SetClampedToScreen(true)
    theme:StylePanel(d, C.panel, C.border)
    d:EnableMouse(true); d:SetMovable(true)
    tinsert(UISpecialFrames, name)

    local hd = CreateFrame("Button", nil, d); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(28)
    local hbg = hd:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); TAP.paint(hbg, C.card)
    hd:RegisterForDrag("LeftButton")
    hd:SetScript("OnDragStart", function() d:StartMoving() end)
    hd:SetScript("OnDragStop", function() d:StopMovingOrSizing() end)
    d.title = hd:CreateFontString(nil, "OVERLAY"); d.title:SetFont(theme.FONT, 13); d.title:SetPoint("LEFT", 10, 0); d.title:SetTextColor(unpack(C.text))
    local x = theme:Button(d); x:Configure("X", 24, 22, "danger", function() d:Hide() end); x:SetPoint("TOPRIGHT", -4, -4)
    x:SetFrameLevel(hd:GetFrameLevel() + 5)

    local box = CreateFrame("Frame", nil, d); box:SetPoint("TOPLEFT", 12, -38); box:SetPoint("BOTTOMRIGHT", -12, 46); theme:StylePanel(box, C.bg); d.box = box
    -- A ScrollFrame clips the editbox to the panel so a long string can't overflow.
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", TAP.scrollWheel)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFont(theme.FONT, 12, ""); eb:SetTextColor(unpack(C.text))
    eb:SetTextInsets(2, 2, 2, 2); eb:SetWidth(420)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then eb:SetWidth(w) end end)
    -- Follow the cursor so long content scrolls into view while typing / pasting.
    eb:SetScript("OnCursorChanged", function(_, _, cy, _, ch)
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        if -cy < top then scroll:SetVerticalScroll(-cy)
        elseif (-cy + ch) > (top + view) then scroll:SetVerticalScroll(-cy + ch - view) end
    end)
    scroll:SetScript("OnMouseDown", function() eb:SetFocus() end)
    scroll:SetScrollChild(eb)
    d.eb = eb

    d.info = d:CreateFontString(nil, "OVERLAY"); d.info:SetFont(theme.FONT, 11); d.info:SetPoint("BOTTOMLEFT", 14, 16); d.info:SetTextColor(unpack(C.subtext))
    d.accept = theme:Button(d); d.accept:SetPoint("BOTTOMRIGHT", -12, 12)
    theme._textDlg = d
    return d
end

-- Show a string selected and ready for Ctrl+C (export).
-- opts: singleLine (short one-line box) · autoClose (close once you copy + click away / Esc).
function Mixin:ShowCopyDialog(title, text, info, opts)
    opts = opts or {}
    local d = ensureDialog(self)
    -- Single-line mode: a compact one-row box (for links / short strings).
    local single = opts.singleLine and true or false
    d.eb:SetMultiLine(not single)
    d:SetHeight(single and 128 or 300)
    -- A multi-line editbox auto-sizes its height to its content (so it works as a scroll child),
    -- but a single-line one has NO content-driven height - as a scroll child it ends up zero-height
    -- and the text renders in an invisible strip (the "empty link box" bug). Give the single-line
    -- box an explicit height so the string actually shows (and vertically centres); clear it again
    -- for multi-line so that mode goes back to auto-sizing with its content.
    d.eb:SetHeight(single and 26 or 0)
    d.title:SetText(title or "Copy this text (Ctrl+C)")
    d.eb:SetText(text or ""); d.eb:SetCursorPosition(0); d.eb:HighlightText()
    d.info:SetText(info or "Selected for you - press Ctrl+C.")
    d.accept:Hide()
    -- Auto-close: WoW can't detect the copy itself, so we close once focus leaves the box
    -- (i.e. after you Ctrl+C and click away or press Escape).
    d.eb:SetScript("OnEditFocusLost", opts.autoClose and function() d:Hide() end or nil)
    d:Show(); d.eb:SetFocus()
    return d
end

-- Show a URL (WoW can't open a browser; the user copies it out). Single-line + optional
-- auto-close by default via opts.
function Mixin:ShowLinkDialog(title, url, opts)
    opts = opts or {}
    if opts.singleLine == nil then opts.singleLine = true end
    return self:ShowCopyDialog(title or "Copy this link (Ctrl+C)", url,
        "Selected for you - press Ctrl+C, then paste it into your browser.", opts)
end

-- Take a pasted string. onAccept(text) fires on the accept button; return a string to keep
-- the dialog open and show it as the new info line (e.g. a validation error), else it hides.
function Mixin:ShowInputDialog(title, info, acceptLabel, onAccept)
    local d = ensureDialog(self)
    d.eb:SetMultiLine(true); d:SetHeight(300); d.eb:SetScript("OnEditFocusLost", nil)   -- reset shared dialog
    d.title:SetText(title or "Paste text")
    d.eb:SetText(""); d.info:SetText(info or "Paste, then click the button.")
    d.accept:Configure(acceptLabel or "OK", 90, 24, "primary", function()
        local keepOpen = onAccept and onAccept(d.eb:GetText())
        if type(keepOpen) == "string" then d.info:SetText(keepOpen) else d:Hide() end
    end)
    d.accept:Show()
    d:Show(); d.eb:SetFocus()
    return d
end
