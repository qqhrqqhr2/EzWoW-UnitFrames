--===========================================================================
-- EzWoW - Unit Frames
-- Modules/UnitButton.lua : One secure unit button (bars, texts, icons) + updaters
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall
local Plain, Raw, IsSecret = ns.Plain, ns.Raw, ns.IsSecret

local TEX = "Interface\\Buttons\\WHITE8X8"
local FONT_BIG, FONT_SMALL = "GameFontHighlight", "GameFontHighlightSmall"

-- w = width, info = name strip height (EzWoW header look), health/power = bar heights,
-- portrait = square portrait, level = show level
ns.SIZES = {
    big   = { w = 232, info = 15, health = 24, power = 10, portrait = true, level = true, powerText = true },
    focus = { w = 180, info = 13, health = 20, power = 6, level = true },
    party = { w = 84, info = 13, health = 22, power = 6, level = true },
    small = { w = 128, health = 20, power = 0 },
    pet   = { w = 128, health = 18, power = 5 },
}

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

function ns.FrameHeight(size)
    local info = (size.info or 0) > 0 and (size.info + 2) or 0
    return 2 + info + size.health + ((size.power > 0) and (size.power + 1) or 0)
end

-----------------------------------------------------------------------------
-- Construction
-----------------------------------------------------------------------------
local function makeBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(TEX)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(TEX)
    bar.bg:SetVertexColor(rgba(ns.Style.barBg))
    -- soft light on the top half of the filled part
    local shine = bar:CreateTexture(nil, "OVERLAY")
    shine:SetAllPoints(bar:GetStatusBarTexture())
    shine:SetColorTexture(1, 1, 1, 1)
    local ok = false
    if type(CreateColor) == "function" and shine.SetGradient then
        ok = pcall(shine.SetGradient, shine, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.16))
    end
    if not ok and shine.SetGradientAlpha then
        ok = pcall(shine.SetGradientAlpha, shine, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, 0.16)
    end
    if not ok then
        shine:Hide()
        shine.ezOff = true -- stays hidden (it would be a plain white block)
    end
    bar.shine = shine
    return bar
end

-----------------------------------------------------------------------------
-- Incoming heals: two thin bars that continue the health fill to the right
-- (mine brighter, other healers' paler). Each runs 0..max health over the
-- whole bar width, so its filled part is the heal's share of max health; a clip
-- frame the size of the health bar cuts what would run past full health.
-- Values may be secret: they only go into the bars, never into comparisons.
-----------------------------------------------------------------------------
local HEAL_MINE = { 0.35, 1.0, 0.45, 0.55 }
local HEAL_OTHER = { 0.35, 0.85, 1.0, 0.40 }

local function buildHealPrediction(f)
    local clip = CreateFrame("Frame", nil, f.health)
    clip:SetAllPoints(f.health)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local function bar(color, anchor)
        local b = CreateFrame("StatusBar", nil, clip)
        b:SetStatusBarTexture(TEX)
        b:SetStatusBarColor(color[1], color[2], color[3], color[4])
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
        b:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
        b:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
        b:EnableMouse(false)
        return b
    end
    local mine = bar(HEAL_MINE, f.health:GetStatusBarTexture())
    local other = bar(HEAL_OTHER, mine:GetStatusBarTexture())
    -- the bars are as wide as the health bar itself
    local function fitWidth()
        local w = f.health:GetWidth()
        if w and w > 0 then
            mine:SetWidth(w)
            other:SetWidth(w)
        end
    end
    f.health:HookScript("OnSizeChanged", fitWidth)
    fitWidth()
    if type(CreateUnitHealPredictionCalculator) == "function" then
        local ok, calc = pcall(CreateUnitHealPredictionCalculator)
        if ok and calc then
            local modes = Enum and Enum.UnitIncomingHealClampMode
            if calc.SetIncomingHealClampMode and modes and modes.MaximumHealth then
                pcall(calc.SetIncomingHealClampMode, calc, modes.MaximumHealth)
            end
            f.healCalc = calc
        end
    end
    f.healMine, f.healOther, f.healClip = mine, other, clip
end

local function setHealBars(f, maxhp, mine, other)
    for _, pair in ipairs({ { f.healMine, mine }, { f.healOther, other } }) do
        local b, value = pair[1], pair[2]
        if (IsSecret(value) or value ~= nil) and (IsSecret(maxhp) or maxhp ~= nil) then
            pcall(b.SetMinMaxValues, b, 0, maxhp)
            if not pcall(b.SetValue, b, value) then pcall(b.SetValue, b, 0) end
        else
            pcall(b.SetValue, b, 0)
        end
    end
end

function ns.UpdateHealPrediction(f)
    if not f.healClip then return end
    local unit = f.unit
    -- (a preview frame has no real unit, so this also covers previews)
    if not ns.db.healPrediction or not Plain(UnitExists, unit) then
        f.healClip:Hide()
        return
    end
    f.healClip:Show()
    local maxhp = Raw(UnitHealthMax, unit)
    local mine, other
    if f.healCalc and type(UnitGetDetailedHealPrediction) == "function" then
        local calc = f.healCalc
        if pcall(UnitGetDetailedHealPrediction, unit, "player", calc) then
            local ok, _, m, o = pcall(calc.GetIncomingHeals, calc)
            if ok then mine, other = m, o end
        end
    end
    if mine == nil and other == nil and type(UnitGetIncomingHeals) == "function" then
        -- older call: total and mine; the others' part is only known with plain values
        local okAll, all = pcall(UnitGetIncomingHeals, unit)
        local okMine, my = pcall(UnitGetIncomingHeals, unit, "player")
        mine = okMine and my or nil
        if okAll and not IsSecret(all) and type(all) == "number" then
            local m = (not IsSecret(mine) and type(mine) == "number") and mine or 0
            other = math.max(0, all - m)
        elseif okAll then
            -- secret total: shown as one bar
            mine, other = all, nil
        end
    end
    setHealBars(f, maxhp, mine, other)
end

local function showUnitTooltip(self)
    if not self.unit or not Plain(UnitExists, self.unit) then return end
    if type(GameTooltip_SetDefaultAnchor) == "function" then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    end
    -- Hovering the frame makes its unit the "mouseover" unit. Inside instances the
    -- tooltip built for a group token ("party1") can't be read by tooltip addons,
    -- while the same person's "mouseover" tooltip can, so that one is used.
    local unit = self.unit
    if Plain(UnitExists, "mouseover") then
        local ok, same = pcall(UnitIsUnit, "mouseover", unit)
        if ok and not IsSecret(same) and same then unit = "mouseover" end
    end
    -- a plain call, like the game's own unit frames: wrapped in pcall, an error in
    -- any tooltip hook would stop the hooks after it (tooltip addons) silently
    if GameTooltip:SetUnit(unit) then GameTooltip:Show() end
end

-- key: saved-position key; unit: unit token; sizeKey: ns.SIZES key
-- opts: { portraitSide = "LEFT"/"RIGHT", label = locale key for the preview name }
function ns.CreateUnitButton(key, unit, sizeKey, opts, parent)
    local f = CreateFrame("Button", "EzWoWUF_" .. key, parent or UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    f.key, f.unit, f.sizeKey, f.opts = key, unit, sizeKey, opts or {}
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    -- the frame only uses the left and right buttons: middle and side buttons go
    -- through to the player's key bindings (mouseover heals bound to them)
    if f.SetPassThroughButtons then pcall(f.SetPassThroughButtons, f, "MiddleButton", "Button4", "Button5") end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    ns.UIKit:ApplyBackdrop(f, 1, 0)
    f:SetBackdropColor(rgba(ns.Style.frameBg))
    f:SetBackdropBorderColor(rgba(ns.Style.border))

    f.health = makeBar(f)
    -- hit/heal trail bars go between the bar background and the fill; built
    -- before anything else takes its frame level from the health bar
    if ns.BuildHealthTrails then ns.BuildHealthTrails(f) end
    buildHealPrediction(f)
    f.power = makeBar(f)

    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(f.health)
    hl:SetColorTexture(1, 1, 1, 0.08)

    -- texts live on an overlay so they sit above both bars
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f.health:GetFrameLevel() + 3)
    f.overlay = overlay

    local size = ns.SIZES[sizeKey]
    local font = (sizeKey == "small" or sizeKey == "pet") and FONT_SMALL or FONT_BIG
    local nameFont = (size.info or 0) > 0 and FONT_SMALL or font
    if (size.info or 0) > 0 then
        -- name strip + 2px accent line: the same header look as every EzWoW window
        f.infoBg = f:CreateTexture(nil, "BORDER")
        f.infoBg:SetColorTexture(ns.Style.bgSecondary[1], ns.Style.bgSecondary[2], ns.Style.bgSecondary[3], 0.95)
        f.accentLine = f:CreateTexture(nil, "ARTWORK")
        f.accentLine:SetColorTexture(rgba(ns.Style.accent))
    end
    f.levelText = overlay:CreateFontString(nil, "OVERLAY", nameFont)
    f.levelText:SetJustifyH("LEFT")
    f.nameText = overlay:CreateFontString(nil, "OVERLAY", nameFont)
    f.nameText:SetJustifyH("LEFT")
    f.nameText:SetWordWrap(false)
    f.healthText = overlay:CreateFontString(nil, "OVERLAY", font)
    f.healthText:SetJustifyH("RIGHT")
    f.statusText = overlay:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    f.statusText:SetTextColor(rgba(ns.Style.textMuted))
    if size.powerText then
        f.powerText = overlay:CreateFontString(nil, "OVERLAY", FONT_SMALL)
        f.powerText:SetJustifyH("RIGHT")
    end
    for _, fs in ipairs({ f.levelText, f.nameText, f.healthText, f.statusText, f.powerText }) do
        local path, height = fs:GetFont()
        if path then fs:SetFont(path, height, "OUTLINE") end
        fs:SetShadowOffset(0, 0)
    end

    if size.portrait then
        f.portraitBg = f:CreateTexture(nil, "BORDER")
        f.portraitBg:SetColorTexture(0, 0, 0, 0.6)
        f.portrait = f:CreateTexture(nil, "ARTWORK")
        f.portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end

    -- icons
    f.raidIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raidIcon:SetSize(16, 16)
    f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 1)
    f.raidIcon:Hide()
    f.leaderIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    f.leaderIcon:SetSize(12, 12)
    f.leaderIcon:SetPoint("CENTER", f, "TOPLEFT", 8, 0)
    f.leaderIcon:Hide()
    f.roleIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.roleIcon:SetSize(14, 14)
    f.roleIcon:SetPoint("CENTER", f, "TOPLEFT", 22, 0)
    f.roleIcon:Hide()
    if unit == "player" then
        f.stateIcon = overlay:CreateTexture(nil, "OVERLAY")
        f.stateIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        f.stateIcon:SetSize(16, 16)
        f.stateIcon:SetPoint("CENTER", f, "BOTTOMLEFT", 2, 2)
        f.stateIcon:Hide()
    end

    -- debuff-type highlight around the health bar (party members)
    if sizeKey == "party" then
        f.dispelGlow = CreateFrame("Frame", nil, f, "BackdropTemplate")
        f.dispelGlow:SetPoint("TOPLEFT", f.health, "TOPLEFT", -1, 1)
        f.dispelGlow:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", 1, -1)
        f.dispelGlow:SetFrameLevel(f.health:GetFrameLevel() + 2)
        f.dispelGlow:SetBackdrop({ edgeFile = TEX, edgeSize = 2 })
        f.dispelGlow:Hide()
    end

    f:SetScript("OnEnter", showUnitTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:HookScript("OnShow", function(self) ns.UpdateFrame(self) end)

    ns.LayoutUnitButton(f)
    return f
end

-- Sizes and places the parts. Changes the protected frame size: out of combat only.
function ns.LayoutUnitButton(f)
    local size = ns.SIZES[f.sizeKey]
    local height = ns.FrameHeight(size)
    local portraitW = (f.portrait and ns.db.portraits) and height or 0
    f:SetSize(size.w + portraitW, height)

    local left, right = 1, -1
    if portraitW > 0 then
        local side = f.opts.portraitSide or "LEFT"
        f.portrait:ClearAllPoints()
        f.portraitBg:ClearAllPoints()
        if side == "LEFT" then
            f.portrait:SetPoint("TOPLEFT", 1, -1)
            f.portrait:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", portraitW - 1, 1)
            left = portraitW
        else
            f.portrait:SetPoint("TOPRIGHT", -1, -1)
            f.portrait:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -portraitW + 1, 1)
            right = -portraitW
        end
        f.portraitBg:SetAllPoints(f.portrait)
        f.portrait:Show()
        f.portraitBg:Show()
    elseif f.portrait then
        f.portrait:Hide()
        f.portraitBg:Hide()
    end
    -- raid target mark above the portrait, or on the top edge without one
    f.raidIcon:ClearAllPoints()
    if portraitW > 0 then
        f.raidIcon:SetPoint("BOTTOM", f.portrait, "TOP", 0, 2)
    else
        f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 1)
    end

    local top = -1
    if f.infoBg then
        f.infoBg:ClearAllPoints()
        f.infoBg:SetPoint("TOPLEFT", left, -1)
        f.infoBg:SetPoint("TOPRIGHT", right, -1)
        f.infoBg:SetHeight(size.info)
        f.accentLine:ClearAllPoints()
        f.accentLine:SetPoint("TOPLEFT", f.infoBg, "BOTTOMLEFT", 0, 0)
        f.accentLine:SetPoint("TOPRIGHT", f.infoBg, "BOTTOMRIGHT", 0, 0)
        f.accentLine:SetHeight(2)
        top = -(1 + size.info + 2)
    end
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", left, top)
    f.health:SetPoint("TOPRIGHT", right, top)
    f.health:SetHeight(size.health)
    if size.power > 0 then
        f.power:ClearAllPoints()
        f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1)
        f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -1)
        f.power:SetHeight(size.power)
        f.power:Show()
    else
        f.power:Hide()
    end

    f.healthText:ClearAllPoints()
    f.healthText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0)
    f.levelText:ClearAllPoints()
    f.levelText:SetPoint("LEFT", f.infoBg or f.health, "LEFT", 4, 0)
    f.nameText:ClearAllPoints()
    if size.level then
        f.nameText:SetPoint("LEFT", f.levelText, "RIGHT", 3, 0)
    else
        f.nameText:SetPoint("LEFT", f.health, "LEFT", 4, 0)
    end
    if f.infoBg then
        f.nameText:SetPoint("RIGHT", f.infoBg, "RIGHT", -4, 0)
    else
        f.nameText:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)
    end
    f.statusText:ClearAllPoints()
    f.statusText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0)
    if f.powerText then
        f.powerText:ClearAllPoints()
        f.powerText:SetPoint("RIGHT", f.power, "RIGHT", -3, 0)
        f.powerText:SetShown(size.power >= 10)
    end
end

-----------------------------------------------------------------------------
-- Updaters
-----------------------------------------------------------------------------
local function unitExists(f)
    return Plain(UnitExists, f.unit) and true or false
end

local function previewing(f)
    return f.preview and not unitExists(f)
end

local function classOf(unit)
    local ok, _, classFile = pcall(UnitClass, unit)
    if ok and type(classFile) == "string" and not IsSecret(classFile) then return classFile end
    return nil
end

local function classColor(classFile)
    if not classFile then return nil end
    if C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
        local ok, color = pcall(C_ClassColor.GetClassColor, classFile)
        if ok and color and color.r then return { color.r, color.g, color.b } end
    end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    return color and { color.r, color.g, color.b } or nil
end
ns.ClassColor = classColor

local function isDead(unit)
    return Plain(UnitIsDeadOrGhost, unit) and true or false
end

local function isOffline(unit)
    if not Plain(UnitIsPlayer, unit) then return false end
    return Plain(UnitIsConnected, unit) == false
end

function ns.UpdateHealthColor(f)
    local unit = f.unit
    local color
    if previewing(f) then
        color = ns.Style.accent
    elseif isDead(unit) or isOffline(unit) then
        color = ns.Style.dead
    elseif Plain(UnitIsPlayer, unit) then
        color = ns.db.classColor and classColor(classOf(unit)) or ns.Style.health
    elseif Plain(UnitIsTapDenied, unit) then
        color = ns.Style.tapped
    elseif f.unit == "pet" then
        color = ns.Style.health
    else
        local reaction = Plain(UnitReaction, unit, "player")
        local fc = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        color = fc and { fc.r, fc.g, fc.b } or ns.Style.health
    end
    f.health:SetStatusBarColor(color[1], color[2], color[3])
    f.health.bg:SetVertexColor(color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 0.9)
    if f.accentLine then
        -- amber (EzWoW) normally, coral when the unit is hostile
        local hostile = not previewing(f) and Plain(UnitCanAttack, "player", unit)
            and (Plain(UnitReaction, unit, "player") or 4) <= 3
        f.accentLine:SetColorTexture(rgba(hostile and ns.Style.warning or ns.Style.accent))
    end
end

-- Percent (0-100) that may be secret; nil when the client can't give one.
local function secretPercent(unit)
    if type(UnitHealthPercent) == "function" and CurveConstants and CurveConstants.ScaleTo100 then
        return Raw(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
    end
    return nil
end
ns.HealthPercent = secretPercent

function ns.PowerPercent(unit, powerType)
    if type(UnitPowerPercent) == "function" and CurveConstants and CurveConstants.ScaleTo100 then
        return Raw(UnitPowerPercent, unit, powerType, true, CurveConstants.ScaleTo100)
    end
    return nil
end

-- Bar value with an optional fill animation (Enum.StatusBarInterpolation).
-- Clients that refuse the second argument get the plain call from then on.
local interpOK = Enum and Enum.StatusBarInterpolation and true or false
function ns.SetBarValue(bar, value, interp)
    if interp ~= nil and interpOK then
        if pcall(bar.SetValue, bar, value, interp) then return true end
        if pcall(bar.SetValue, bar, value) then
            interpOK = false
            return true
        end
        return false
    end
    return pcall(bar.SetValue, bar, value) and true or false
end

-- A bar's range can't be set from a secret maximum (the call is ignored), so the
-- bar runs 0-100 on the client's percent, which works with secret values.
-- false when there is no percent (older client): the caller uses the plain values.
-- The range is only set when it changes (bar.ezTop), so a running fill animation
-- isn't restarted; code that sets another range clears bar.ezTop.
function ns.FillBarFromPercent(bar, pct, interp)
    if not IsSecret(pct) and pct == nil then return false end
    if bar.ezTop ~= 100 then
        if not pcall(bar.SetMinMaxValues, bar, 0, 100) then return false end
        bar.ezTop = 100
    end
    return ns.SetBarValue(bar, pct, interp)
end

-- Missing health as "-12.3k", blank at full health, also for secret values.
local function setSecretDeficit(fs, unit)
    if type(UnitHealthMissing) ~= "function" then return false end
    if not (C_StringUtil and type(C_StringUtil.TruncateWhenZero) == "function") then return false end
    local missing = Raw(UnitHealthMissing, unit, true)
    if not IsSecret(missing) and missing == nil then return false end
    return pcall(function()
        fs:SetText(C_StringUtil.TruncateWhenZero(missing))
        -- the text is empty exactly when nothing is missing
        if fs:GetText() then fs:SetFormattedText("-%s", ns.ShortNumber(missing)) end
    end)
end

local function setHealthText(fs, mode, unit, hp, maxhp)
    if mode == "none" then fs:SetText("") return end
    if not IsSecret(hp) and not IsSecret(maxhp) and type(hp) == "number" and type(maxhp) == "number" then
        local pct = (maxhp > 0) and math.floor(hp / maxhp * 100 + 0.5) or 0
        if mode == "percent" then
            fs:SetText(pct .. "%")
        elseif mode == "current" then
            fs:SetText(ns.ShortNumber(hp))
        elseif mode == "both" then
            fs:SetText(ns.ShortNumber(hp) .. " / " .. ns.ShortNumber(maxhp))
        elseif mode == "deficit" then
            fs:SetText(hp < maxhp and ("-" .. ns.ShortNumber(maxhp - hp)) or "")
        else -- curpct
            fs:SetText(ns.ShortNumber(hp) .. " · " .. pct .. "%")
        end
        return
    end
    -- secret values (restricted combat): only what the client can format for us
    local pct = secretPercent(unit)
    -- a secret value is never compared, only checked for presence
    local hasPct = IsSecret(pct) or pct ~= nil
    local ok
    if mode == "percent" and hasPct then
        ok = pcall(fs.SetFormattedText, fs, "%.0f%%", pct)
    elseif mode == "both" then
        ok = pcall(fs.SetFormattedText, fs, "%s / %s", ns.ShortNumber(hp), ns.ShortNumber(maxhp))
    elseif mode == "curpct" and hasPct then
        ok = pcall(fs.SetFormattedText, fs, "%s · %.0f%%", ns.ShortNumber(hp), pct)
    elseif mode == "deficit" then
        ok = setSecretDeficit(fs, unit)
    else
        ok = pcall(fs.SetFormattedText, fs, "%s", ns.ShortNumber(hp))
    end
    if not ok then fs:SetText("") end
end

local function textModeFor(f)
    if f.sizeKey == "small" or f.sizeKey == "pet" then return ns.db.smallText end
    if f.sizeKey == "party" then return ns.db.partyText end
    return ns.db.healthText
end

function ns.UpdateHealth(f)
    local unit = f.unit
    if previewing(f) then
        f.health.ezTop = nil
        f.health:SetMinMaxValues(0, 1)
        f.health:SetValue(0.72)
        if ns.HealthBarInterp then ns.HealthBarInterp(f) end
        if ns.UpdateHealthTrails then ns.UpdateHealthTrails(f, 1, 0.72) end
        f.healthText:SetText("72%")
        f.healthText:Show()
        f.statusText:Hide()
        if ns.UpdateHealthFX then ns.UpdateHealthFX(f) end
        return
    end
    local hp, maxhp = Raw(UnitHealth, unit), Raw(UnitHealthMax, unit)
    if not IsSecret(maxhp) and (type(maxhp) ~= "number" or maxhp <= 0) then maxhp = 1 end
    -- eased fill (nil = plain set) and the trail bars behind it (HealthEffects)
    local interp = ns.HealthBarInterp and ns.HealthBarInterp(f) or nil
    local value, top = secretPercent(unit), 100
    if not ns.FillBarFromPercent(f.health, value, interp) then
        value, top = hp or 0, maxhp
        f.health.ezTop = nil
        pcall(f.health.SetMinMaxValues, f.health, 0, maxhp)
        ns.SetBarValue(f.health, value, interp)
    end
    if ns.UpdateHealthTrails then ns.UpdateHealthTrails(f, top, value) end

    local status
    if isOffline(unit) then
        status = ns:L("offline")
    elseif Plain(UnitIsGhost, unit) then
        status = ns:L("ghost")
    elseif isDead(unit) then
        status = ns:L("dead")
    end
    if status then
        f.healthText:Hide()
        f.statusText:SetText(status)
        f.statusText:Show()
    else
        f.statusText:Hide()
        f.healthText:Show()
        setHealthText(f.healthText, textModeFor(f), unit, hp, maxhp)
    end
    if ns.UpdateHealthFX then ns.UpdateHealthFX(f) end
    ns.UpdateHealPrediction(f)
end

local function powerColor(unit)
    local ok, pType, pToken = pcall(UnitPowerType, unit)
    if not ok or IsSecret(pType) or IsSecret(pToken) then return nil, nil end
    local c = PowerBarColor and ((pToken and PowerBarColor[pToken]) or PowerBarColor[pType])
    return c, pType
end

function ns.UpdatePower(f)
    if not f.power:IsShown() then return end
    local unit = f.unit
    if previewing(f) then
        f.power.ezTop = nil
        f.power:SetMinMaxValues(0, 1)
        f.power:SetValue(0.55)
        f.power:SetStatusBarColor(0.31, 0.45, 0.85)
        if f.powerText then f.powerText:SetText("") end
        return
    end
    local c = powerColor(unit)
    local r, g, b = 0.31, 0.45, 0.85
    if c then r, g, b = c.r, c.g, c.b end
    f.power:SetStatusBarColor(r, g, b)
    f.power.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.9)
    local pw, maxpw = Raw(UnitPower, unit), Raw(UnitPowerMax, unit)
    if not IsSecret(maxpw) and (type(maxpw) ~= "number" or maxpw <= 0) then maxpw = 1 end
    if not ns.FillBarFromPercent(f.power, ns.PowerPercent(unit, Raw(UnitPowerType, unit))) then
        f.power.ezTop = nil
        pcall(f.power.SetMinMaxValues, f.power, 0, maxpw)
        pcall(f.power.SetValue, f.power, pw or 0)
    end
    if f.powerText then
        if isDead(unit) then
            f.powerText:SetText("")
        elseif not pcall(f.powerText.SetFormattedText, f.powerText, "%s", ns.ShortNumber(pw)) then
            f.powerText:SetText("")
        end
    end
end

local CLASSIFICATION_SUFFIX = { elite = "+", rare = "R", rareelite = "R+", worldboss = "B" }

-- Display name. WoW Forever names have a surname ("드라이브 쓰랄"): UnitName returns
-- them as two values, so use the client's display formatter and fall back to joining them.
local realmName
function ns.UnitDisplayName(unit)
    if NameUtil and type(NameUtil.FormatUnitNameForDisplay) == "function" then
        local ok, full = pcall(NameUtil.FormatUnitNameForDisplay, unit)
        if ok and type(full) == "string" and not IsSecret(full) and full ~= "" then return full end
    end
    local first, second = Raw(UnitName, unit)
    if IsSecret(first) or IsSecret(second) then return first end
    if type(second) == "string" and second ~= "" then
        if realmName == nil then realmName = Plain(GetRealmName) or "" end
        if second ~= realmName then return first .. " " .. second end
    end
    return first
end

function ns.UpdateInfo(f)
    local unit = f.unit
    local size = ns.SIZES[f.sizeKey]
    if previewing(f) then
        f.nameText:SetText(ns:L(f.opts.label or f.key))
        f.levelText:SetText(size.level and "60" or "")
        f.levelText:SetTextColor(1, 0.82, 0)
        return
    end
    if not pcall(f.nameText.SetText, f.nameText, ns.UnitDisplayName(unit)) then f.nameText:SetText("") end
    if not size.level then
        f.levelText:SetText("")
        return
    end
    local level = Plain(UnitLevel, unit)
    if type(level) ~= "number" then
        f.levelText:SetText("")
        return
    end
    local text, r, g, b
    if level <= 0 then
        text, r, g, b = "??", 1, 0.1, 0.1
    else
        text = tostring(level)
        local color = (type(GetCreatureDifficultyColor) == "function" and Plain(GetCreatureDifficultyColor, level))
            or (type(GetQuestDifficultyColor) == "function" and Plain(GetQuestDifficultyColor, level))
        if type(color) == "table" and color.r then r, g, b = color.r, color.g, color.b else r, g, b = 1, 0.82, 0 end
        if Plain(UnitIsPlayer, unit) or unit == "player" then r, g, b = 1, 0.82, 0 end
    end
    if not Plain(UnitIsPlayer, unit) then
        local class = Plain(UnitClassification, unit)
        text = text .. (CLASSIFICATION_SUFFIX[class] or "")
    end
    f.levelText:SetText(text)
    f.levelText:SetTextColor(r, g, b)
end

function ns.UpdatePortrait(f)
    if not f.portrait or not f.portrait:IsShown() then return end
    if previewing(f) then
        f.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        return
    end
    if type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, f.portrait, f.unit) end
end

-- The raid target index reads secret on current clients. type() tells nil
-- from a mark without reading it, and the default texture function accepts
-- the secret index as it is.
function ns.SetRaidIcon(texture, unit)
    local index = unit and type(GetRaidTargetIndex) == "function" and GetRaidTargetIndex(unit)
    if type(index) == "number" and type(SetRaidTargetIconTexture) == "function"
        and pcall(SetRaidTargetIconTexture, texture, index) then
        texture:Show()
    else
        texture:Hide()
    end
end

local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer" }
local SECRET_ROLE_MAP = { TANK = ROLE_ATLAS.TANK, HEALER = ROLE_ATLAS.HEALER, DAMAGER = "", VEHICLE = "" }

-- Tank / healer mark. A role that reads secret (a unit the client hides) is
-- painted by the default secret-safe role painter onto a texture of our own.
function ns.SetRoleIcon(f, unit)
    local icon, secretIcon = f.roleIcon, f.roleIconSecret
    local role = unit and type(UnitGroupRolesAssigned) == "function" and ns.Raw(UnitGroupRolesAssigned, unit)
    if IsSecret(role) then
        icon:Hide()
        local paint = UnitFrameUtil and UnitFrameUtil.UpdateUnitFrameRoleIcon
        if type(paint) ~= "function" then
            if secretIcon then secretIcon:Hide() end
            return
        end
        if not secretIcon then
            secretIcon = icon:GetParent():CreateTexture(nil, "OVERLAY")
            secretIcon:SetAllPoints(icon)
            f.roleIconSecret = secretIcon
            f.roleSecretProxy = { roleIcon = secretIcon,
                optionTable = { displayRoleIcon = true, displayRaidRoleIcon = false, textureMap = SECRET_ROLE_MAP } }
        end
        f.roleSecretProxy.unit = unit
        if not pcall(paint, f.roleSecretProxy) then secretIcon:Hide() end
        return
    end
    if secretIcon then secretIcon:Hide() end
    local atlas = ROLE_ATLAS[role]
    if atlas and pcall(icon.SetAtlas, icon, atlas) then
        icon:Show()
    else
        icon:Hide()
    end
end

function ns.UpdateIcons(f)
    local unit = f.unit
    local exists = unitExists(f)
    ns.SetRaidIcon(f.raidIcon, exists and unit or nil)
    local leader = exists and (Plain(UnitIsGroupLeader, unit)) and (Plain(IsInGroup) or false)
    f.leaderIcon:SetShown(leader and true or false)
    -- tank / healer mark of group members
    ns.SetRoleIcon(f, exists and Plain(IsInGroup) and unit or nil)
    if f.stateIcon then
        if Plain(UnitAffectingCombat, "player") then
            f.stateIcon:SetTexCoord(0.5, 1, 0, 0.49)
            f.stateIcon:Show()
        elseif Plain(IsResting) then
            f.stateIcon:SetTexCoord(0, 0.5, 0, 0.421875)
            f.stateIcon:Show()
        else
            f.stateIcon:Hide()
        end
    end
end

-- Secret threat status: the client still says (as a secret boolean) whether
-- `who` is tanking `mob`, and picks the border colour for us without a comparison.
local function secretThreatBorder(f, who, mob)
    local fold = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if type(fold) ~= "function" or type(UnitDetailedThreatSituation) ~= "function" then return false end
    local ok, isTanking = pcall(UnitDetailedThreatSituation, who, mob)
    if not ok or type(isTanking) ~= "boolean" then return false end
    local hot, cold = ns.Style.threat[3], ns.Style.border
    return pcall(function()
        f:SetBackdropBorderColor(fold(isTanking, hot[1], cold[1]), fold(isTanking, hot[2], cold[2]),
            fold(isTanking, hot[3], cold[3]), 1)
    end)
end

function ns.UpdateThreat(f)
    local status, who, mob
    if ns.db.threatBorder and unitExists(f) then
        if f.unit == "target" or f.unit == "focus" or f.unit == "targettarget" then
            if Plain(UnitCanAttack, "player", f.unit) then
                status, who, mob = Raw(UnitThreatSituation, "player", f.unit), "player", f.unit
            end
        else
            status = Raw(UnitThreatSituation, f.unit)
            -- secret: judged against my target only
            if Plain(UnitCanAttack, "player", "target") then who, mob = f.unit, "target" end
        end
    end
    if IsSecret(status) then
        if who and secretThreatBorder(f, who, mob) then return end
        status = nil
    end
    local c = (type(status) == "number" and status > 0) and ns.Style.threat[status]
    if c then
        f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    else
        f:SetBackdropBorderColor(rgba(ns.Style.border))
    end
end

-- Party fade by range. The in-range answer may be secret: the client applies it
-- through SetAlphaFromBoolean, so it is never compared here.
function ns.UpdateRange(f)
    if f.sizeKey ~= "party" then return end
    if not ns.db.rangeFade or previewing(f) or not unitExists(f) then
        f:SetAlpha(1)
        return
    end
    local ok, inRange, checked = pcall(UnitInRange, f.unit)
    if not ok then f:SetAlpha(1) return end
    -- not checked (plain false): the client can't tell, so no fading
    if not IsSecret(checked) and checked == false then f:SetAlpha(1) return end
    if f.SetAlphaFromBoolean and pcall(f.SetAlphaFromBoolean, f, inRange, 1, 0.45) then return end
    if IsSecret(inRange) then return end
    f:SetAlpha((checked and not inRange) and 0.45 or 1)
end

-- Everything (on show, unit change, settings change).
function ns.UpdateFrame(f)
    if not f or not ns.db then return end
    if not unitExists(f) and not f.preview then return end
    -- shown, new unit or settings change: trails start at the current health
    if f.trails then f.trails.forceSnap = true end
    ns.UpdateInfo(f)
    ns.UpdateHealthColor(f)
    ns.UpdateHealth(f)
    ns.UpdatePower(f)
    ns.UpdatePortrait(f)
    ns.UpdateIcons(f)
    ns.UpdateThreat(f)
    ns.UpdateRange(f)
    if ns.UpdateAuras then ns.UpdateAuras(f) end
    if ns.UpdateCastbar then ns.UpdateCastbar(f) end
    if f.UpdateExtras then f:UpdateExtras() end
end
