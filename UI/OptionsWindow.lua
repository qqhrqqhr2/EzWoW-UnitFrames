--===========================================================================
-- EzWoW - Unit Frames
-- UI/OptionsWindow.lua : EzWoW Style Settings Window, Blizzard Launcher & Slash
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall

local UIKit = ns.UIKit
local configFrame, optionsPanel, copyBox

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local TEXT_MODES = { "curpct", "both", "current", "percent", "deficit", "none" }

-----------------------------------------------------------------------------
-- Donate Copy Modal
-----------------------------------------------------------------------------
local function showDonatePopup()
    local S = ns.Style
    if not copyBox then
        copyBox = CreateFrame("Frame", "EzWoWUnitFramesDonate", UIParent, "BackdropTemplate")
        copyBox:SetSize(390, 116)
        copyBox:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        UIKit:ApplyBackdrop(copyBox)
        copyBox:SetBackdropColor(S.bgPrimary[1], S.bgPrimary[2], S.bgPrimary[3], 0.98)
        copyBox:SetBackdropBorderColor(rgba(S.accent))
        copyBox.label = copyBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        copyBox.label:SetPoint("TOP", 0, -14)
        copyBox.label:SetTextColor(rgba(S.accent))
        local box, edit = UIKit:CreateEditBox(copyBox, 346, 27)
        box:SetPoint("TOP", 0, -43)
        box:SetFrameLevel(copyBox:GetFrameLevel() + 5)
        edit:SetText(ns.DONATE_URL)
        edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
        edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
        edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
        edit:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(ns.DONATE_URL) self:HighlightText() end end)
        copyBox.edit = edit
        local close = UIKit:CreateCloseButton(copyBox, function() copyBox:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
    end
    copyBox.label:SetText(ns:L("copy"))
    UIKit:ElevateModal(copyBox, 260)
    copyBox:Show()
    copyBox.edit:SetFocus()
    copyBox.edit:HighlightText()
end

-----------------------------------------------------------------------------
-- Settings Window (EzWoWUnitFramesConfig)
-----------------------------------------------------------------------------
function ns:ToggleOptions()
    if not self.db then return end
    if configFrame then
        configFrame:SetShown(not configFrame:IsShown())
        if configFrame:IsShown() then configFrame:Raise() end
        return
    end

    local S = ns.Style
    local db = self.db
    configFrame = CreateFrame("Frame", "EzWoWUnitFramesConfig", UIParent, "BackdropTemplate")
    configFrame:SetSize(460, 1012)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:SetToplevel(true)
    configFrame:SetClampedToScreen(true)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWUnitFramesConfig") end
    UIKit:ApplyBackdrop(configFrame, 1, 1)
    configFrame:SetBackdropColor(rgba(S.bgPrimary))
    configFrame:SetBackdropBorderColor(rgba(S.border))

    local top = UIKit:CreateHeader(configFrame, ns.TITLE)
    top.subtitle:SetWidth(340)
    local close = UIKit:CreateCloseButton(top, function() configFrame:Hide() end)
    close:SetPoint("TOPRIGHT", top, "TOPRIGHT", -10, -10)

    local headings = {}
    local function section(key, y)
        local t = UIKit:CreateSectionLabel(configFrame, 20, y)
        local line = configFrame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(S.border[1], S.border[2], S.border[3], 0.85)
        line:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, y - 20)
        line:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -20, y - 20)
        line:SetHeight(1)
        headings[#headings + 1] = { fs = t, key = key }
    end

    local checks = {}
    -- get/set default to db[key]; after = what to refresh ("layout", "visibility" or a function)
    local function option(x, y, labelKey, get, set, after)
        local c, t = UIKit:CreateCheck(configFrame, function(value)
            set(value)
            if after == "layout" then
                ns.ApplyLayout()
            elseif after == "visibility" then
                ns.ApplyVisibility()
            elseif type(after) == "function" then
                after(value)
            else
                ns.RefreshAll()
            end
        end)
        c:SetPoint("TOPLEFT", x, y)
        checks[#checks + 1] = { check = c, label = t, get = get, labelKey = labelKey }
    end
    local function dbOption(x, y, key, after)
        option(x, y, "opt_" .. key, function() return db[key] end, function(v) db[key] = v end, after)
    end

    -- 1. Frames
    section("secFrames", -70)
    for i, key in ipairs(ns.FRAME_KEYS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        option(20 + col * 140, -94 - row * 26, key,
            function() return db.enabled[key] end,
            function(v) db.enabled[key] = v end,
            function(value)
                ns.ApplyVisibility()
                if db.hideBlizzard then
                    if value then ns.HideBlizzardFrames() else ns.Print(ns:L("reloadNeeded")) end
                end
            end)
    end

    -- 2. Display
    section("secDisplay", -160)
    local L1, L2 = 20, 236
    dbOption(L1, -184, "classColor")
    dbOption(L2, -184, "portraits", "layout")
    dbOption(L1, -210, "targetCastbar")
    dbOption(L2, -210, "focusCastbar")
    dbOption(L1, -236, "targetAuras")
    dbOption(L2, -236, "onlyMyDebuffs")
    dbOption(L1, -262, "comboPoints")
    dbOption(L2, -262, "druidMana")
    dbOption(L1, -288, "partyDebuffs")
    dbOption(L2, -288, "rangeFade")
    dbOption(L1, -314, "threatBorder")
    dbOption(L2, -314, "partyInRaid", "visibility")
    dbOption(L1, -340, "hideBlizzard", function(value)
        if value then ns.HideBlizzardFrames() else ns.Print(ns:L("reloadNeeded")) end
    end)

    dbOption(L2, -340, "playerAuras")
    dbOption(L1, -366, "powerTicks", function() ns.UpdatePowerTicker() end)
    dbOption(L2, -366, "healthFX")
    dbOption(L1, -392, "hitFX")
    dbOption(L2, -392, "partyBuffs", function()
        ns.ApplyLayout()
        ns.RefreshAll()
    end)
    dbOption(L1, -418, "healPrediction")
    dbOption(L2, -418, "bigMyAuras", function()
        -- party rows change height with it
        ns.ApplyLayout()
        ns.RefreshAll()
    end)
    dbOption(L1, -444, "partyHorizontal", "layout")

    -- 3. Nameplates
    section("secPlates", -482)
    local function plateRefresh() if ns.RefreshNameplates then ns.RefreshNameplates() end end
    dbOption(L1, -506, "nameplates", plateRefresh)
    dbOption(L2, -506, "plateCastbar", plateRefresh)
    dbOption(L1, -532, "plateDebuffs", plateRefresh)
    dbOption(L2, -532, "plateThreat", plateRefresh)
    dbOption(L1, -558, "plateTankMode", plateRefresh)
    dbOption(L2, -558, "plateFadeOthers", plateRefresh)
    dbOption(L1, -584, "plateQuest", plateRefresh)
    -- interrupt warning: nameplates and the target / focus cast bars
    local function kickRefresh()
        ns.RefreshAll()
        plateRefresh()
    end
    dbOption(L2, -584, "kickWarn", kickRefresh)
    dbOption(L1, -610, "kickTargetOnly", kickRefresh)
    dbOption(L2, -610, "kickSound", kickRefresh)
    -- friendly nameplates: game look / name only / name + thin bar
    local function friendlyRefresh()
        plateRefresh()
        if ns.ApplyFriendlyCVars then ns.ApplyFriendlyCVars() end
    end
    local friendlyBtn = UIKit:CreateButton(configFrame, 205, 24, "", false, "GameFontHighlightSmall")
    friendlyBtn:SetPoint("TOPLEFT", L1, -637)
    friendlyBtn:SetScript("OnClick", function(self)
        local items = {}
        for _, mode in ipairs({ "default", "name", "bar" }) do
            items[#items + 1] = { value = mode, text = function() return ns:L("friendly_" .. mode) end }
        end
        UIKit:ShowMenu(self, items, {
            current = db.friendlyPlates,
            onSelect = function(value)
                db.friendlyPlates = value
                friendlyRefresh()
                ns.RefreshOptions()
            end,
        })
    end)
    dbOption(L2, -636, "friendlyHideInstance", friendlyRefresh)
    dbOption(300, -668, "plateOverlap", friendlyRefresh)
    local plateScaleLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    plateScaleLabel:SetPoint("TOPLEFT", 24, -672)
    local plateMinus = UIKit:CreateButton(configFrame, 27, 27, "-", false, "GameFontNormalLarge")
    plateMinus:SetPoint("TOPLEFT", 150, -665)
    local plateScaleValue = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    plateScaleValue:SetPoint("LEFT", plateMinus, "RIGHT", 4, 0)
    plateScaleValue:SetWidth(52)
    local platePlus = UIKit:CreateButton(configFrame, 27, 27, "+", false, "GameFontNormalLarge")
    platePlus:SetPoint("LEFT", plateMinus, "RIGHT", 60, 0)
    local function changePlateScale(delta)
        db.plateScale = math.max(0.7, math.min(1.6, math.floor(((db.plateScale or 1) + delta) * 100 + 0.5) / 100))
        plateRefresh()
        ns.RefreshOptions()
    end
    plateMinus:SetScript("OnClick", function() changePlateScale(-0.05) end)
    platePlus:SetScript("OnClick", function() changePlateScale(0.05) end)

    -- 3. Health text
    section("secText", -700)
    local textButtons = {}
    local function textPicker(x, dbKey, labelKey)
        local label = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x + 2, -726)
        label:SetTextColor(rgba(S.textMuted))
        local b = UIKit:CreateButton(configFrame, 132, 26, "", false, "GameFontHighlightSmall")
        b:SetPoint("TOPLEFT", x, -742)
        b:SetScript("OnClick", function(self)
            local items = {}
            for _, mode in ipairs(TEXT_MODES) do
                items[#items + 1] = { value = mode, text = function() return ns:L("text_" .. mode) end }
            end
            UIKit:ShowMenu(self, items, {
                current = db[dbKey],
                onSelect = function(value)
                    db[dbKey] = value
                    ns.RefreshAll()
                    ns.RefreshOptions()
                end,
            })
        end)
        textButtons[#textButtons + 1] = { button = b, label = label, dbKey = dbKey, labelKey = labelKey }
    end
    textPicker(20, "healthText", "textBig")
    textPicker(162, "smallText", "textSmall")
    textPicker(304, "partyText", "textParty")

    -- 4. Size & position
    section("secLayout", -784)
    local scaleLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleLabel:SetPoint("TOPLEFT", 24, -818)
    local minus = UIKit:CreateButton(configFrame, 27, 27, "-", false, "GameFontNormalLarge")
    minus:SetPoint("TOPLEFT", 150, -811)
    local scaleValue = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleValue:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    scaleValue:SetWidth(52)
    local plus = UIKit:CreateButton(configFrame, 27, 27, "+", false, "GameFontNormalLarge")
    plus:SetPoint("LEFT", minus, "RIGHT", 60, 0)
    local function changeScale(delta)
        db.scale = math.max(0.6, math.min(1.6, math.floor((db.scale + delta) * 100 + 0.5) / 100))
        ns.ApplyLayout()
        ns.RefreshOptions()
    end
    minus:SetScript("OnClick", function() changeScale(-0.05) end)
    plus:SetScript("OnClick", function() changeScale(0.05) end)

    local lockBtn = UIKit:CreateButton(configFrame, 205, 32, "", true)
    lockBtn:SetPoint("TOPLEFT", 20, -848)
    lockBtn:SetScript("OnClick", function() ns.SetLocked(not db.locked) end)
    local resetBtn = UIKit:CreateButton(configFrame, 205, 32, "")
    resetBtn:SetPoint("TOPLEFT", 235, -848)
    resetBtn:SetScript("OnClick", function() ns.ResetPositions() end)

    local langBtn = UIKit:CreateButton(configFrame, 205, 28, "")
    langBtn:SetPoint("TOPLEFT", 20, -888)
    local langItems = {}
    for i, v in ipairs(ns.LANGUAGE_OPTIONS) do langItems[i] = { value = v[1], text = v[2] } end
    ns.LanguageDropdown.Attach(langBtn, {
        items = langItems,
        colors = { accent = ns.Style.accent },
        get = function() return db.language end,
        set = function(code)
            db.language = code
            ns.RefreshAll()
            ns.RefreshOptions()
        end,
    })

    local donateBtn = UIKit:CreateButton(configFrame, 205, 28, "", true)
    donateBtn:SetPoint("TOPLEFT", 235, -888)
    donateBtn:SetScript("OnClick", showDonatePopup)

    local hint = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 22, -928)
    hint:SetWidth(416)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(rgba(S.textMuted))

    local foot = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", 0, 12)

    function ns.RefreshOptions()
        if not configFrame then return end
        ns.FitText(top.subtitle, ns:L("settingsSub"), 340, 10, 8)
        for _, h in ipairs(headings) do ns.FitText(h.fs, ns:L(h.key), 415, 13, 10) end
        for _, item in ipairs(checks) do
            item.check:SetChecked(item.get() and true or false)
            ns.FitText(item.label, ns:L(item.labelKey), item.check:GetLeft() and 180 or 180, 12, 9)
        end
        for _, tb in ipairs(textButtons) do
            ns.FitText(tb.label, ns:L(tb.labelKey), 128, 11, 8)
            tb.button:SetLabel(ns:L("text_" .. tostring(db[tb.dbKey])) .. " ▼")
        end
        friendlyBtn:SetLabel(ns:L("friendlyPlates") .. ": " .. ns:L("friendly_" .. tostring(db.friendlyPlates)) .. " ▼")
        ns.FitText(plateScaleLabel, ns:L("plateScale"), 120, 12, 9)
        plateScaleValue:SetText(math.floor((db.plateScale or 1) * 100 + 0.5) .. "%")
        ns.FitText(scaleLabel, ns:L("scale"), 120, 12, 9)
        scaleValue:SetText(math.floor(db.scale * 100 + 0.5) .. "%")
        lockBtn:SetLabel(ns:L(db.locked and "unlock" or "lock"))
        lockBtn:SetActive(not db.locked)
        resetBtn:SetLabel(ns:L("resetPos"))
        langBtn:SetLabel(ns:L("language") .. ": " .. ns:GetLanguageDisplayLabel() .. " ▼")
        donateBtn:SetLabel(ns:L("donate"))
        hint:SetText(ns:L("hint"))
        local ver = ns.GetVersion()
        foot:SetText(ns.TITLE .. (ver ~= "" and (" v" .. ver) or "") .. "  ·  /ezuf")
        if copyBox and copyBox:IsShown() then copyBox.label:SetText(ns:L("copy")) end
        if optionsPanel and optionsPanel.refreshText then optionsPanel.refreshText() end
    end

    configFrame:SetScript("OnShow", ns.RefreshOptions)
    ns.RefreshOptions()
    configFrame:Raise()
end

-----------------------------------------------------------------------------
-- Blizzard Settings Canvas Launcher
-----------------------------------------------------------------------------
function ns:RegisterBlizzardOptions()
    if optionsPanel then return end
    local S = ns.Style
    optionsPanel = CreateFrame("Frame", "EzWoWUnitFramesOptionsPanel", UIParent)
    optionsPanel.name = ns.TITLE

    local icon = optionsPanel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 18, -18)
    icon:SetTexture(ns.MEDIA_PATH .. "Icon")
    local heading = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    heading:SetText(ns.TITLE)
    heading:SetTextColor(rgba(S.accent))
    local desc = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    local open = UIKit:CreateButton(optionsPanel, 220, 28, "", true)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    open:SetScript("OnClick", function() ns:ToggleOptions() end)
    local hint = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -14)
    hint:SetTextColor(rgba(S.textMuted))

    optionsPanel.refreshText = function()
        desc:SetText(ns:L("panelDesc"))
        open:SetLabel(ns:L("panelOpen"))
        hint:SetText(ns:L("panelHint"))
    end
    optionsPanel:SetScript("OnShow", optionsPanel.refreshText)
    -- fill the texts now: the settings window does not always fire OnShow
    optionsPanel.refreshText()

    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, optionsPanel, ns.TITLE)
        if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
    elseif type(InterfaceOptions_AddCategory) == "function" then
        pcall(InterfaceOptions_AddCategory, optionsPanel)
    end
end

-----------------------------------------------------------------------------
-- Slash Commands (/ezuf, /유닛프레임, /ezwowunitframes)
-----------------------------------------------------------------------------
SLASH_EZWOWUNITFRAMES1 = "/ezuf"
SLASH_EZWOWUNITFRAMES2 = "/유닛프레임"
SLASH_EZWOWUNITFRAMES3 = "/ezwowunitframes"

SlashCmdList.EZWOWUNITFRAMES = function(msg)
    if not ns.db or not ns.built then
        ns.Print(ns:L("waiting"))
        return
    end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "unlock" or msg == "move" or msg == "이동" then
        ns.SetLocked(false)
    elseif msg == "lock" or msg == "잠금" then
        ns.SetLocked(true)
    elseif msg == "plates" or msg == "이름표" then
        if ns.DescribeTargetPlate then ns.DescribeTargetPlate() end
    elseif msg == "reset" or msg == "초기화" then
        ns.ResetPositions()
    elseif msg:match("^lang") then
        local arg = msg:match("^%S+%s+(%S+)")
        local norm = arg and ns.LANG_ALIASES[arg]
        if not norm then
            ns.Print("/ezuf lang auto | ko | en | de | fr | es | ru | cn | tw")
            return
        end
        ns.db.language = norm
        ns.RefreshAll()
        if ns.RefreshOptions then ns.RefreshOptions() end
    else
        ns:ToggleOptions()
    end
end
