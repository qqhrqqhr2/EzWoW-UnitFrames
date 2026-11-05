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
    party = { w = 176, info = 13, health = 22, power = 6, level = true },
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
    if not ok then shine:Hide() end
    bar.shine = shine
    return bar
end

local function showUnitTooltip(self)
    if not self.unit or not Plain(UnitExists, self.unit) then return end
    if type(GameTooltip_SetDefaultAnchor) == "function" then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    end
    if pcall(GameTooltip.SetUnit, GameTooltip, self.unit) then GameTooltip:Show() end
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
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    ns.UIKit:ApplyBackdrop(f, 1, 0)
    f:SetBackdropColor(rgba(ns.Style.frameBg))
    f:SetBackdropBorderColor(rgba(ns.Style.border))

    f.health = makeBar(f)
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
    local ok
    if mode == "percent" and pct ~= nil then
        ok = pcall(fs.SetFormattedText, fs, "%d%%", pct)
    elseif mode == "both" then
        ok = pcall(fs.SetFormattedText, fs, "%s / %s", ns.ShortNumber(hp), ns.ShortNumber(maxhp))
    elseif mode == "curpct" and pct ~= nil then
        ok = pcall(fs.SetFormattedText, fs, "%s · %d%%", ns.ShortNumber(hp), pct)
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
        f.health:SetMinMaxValues(0, 1)
        f.health:SetValue(0.72)
        f.healthText:SetText("72%")
        f.healthText:Show()
        f.statusText:Hide()
        return
    end
    local hp, maxhp = Raw(UnitHealth, unit), Raw(UnitHealthMax, unit)
    if not IsSecret(maxhp) and (type(maxhp) ~= "number" or maxhp <= 0) then maxhp = 1 end
    pcall(f.health.SetMinMaxValues, f.health, 0, maxhp)
    pcall(f.health.SetValue, f.health, hp or 0)

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
    pcall(f.power.SetMinMaxValues, f.power, 0, maxpw)
    pcall(f.power.SetValue, f.power, pw or 0)
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

function ns.UpdateIcons(f)
    local unit = f.unit
    local exists = unitExists(f)
    local index = exists and Plain(GetRaidTargetIndex, unit)
    if index and type(SetRaidTargetIconTexture) == "function" then
        SetRaidTargetIconTexture(f.raidIcon, index)
        f.raidIcon:Show()
    else
        f.raidIcon:Hide()
    end
    local leader = exists and (Plain(UnitIsGroupLeader, unit)) and (Plain(IsInGroup) or false)
    f.leaderIcon:SetShown(leader and true or false)
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

function ns.UpdateThreat(f)
    local status
    if ns.db.threatBorder and unitExists(f) then
        if f.unit == "target" or f.unit == "focus" or f.unit == "targettarget" then
            if Plain(UnitCanAttack, "player", f.unit) then status = Plain(UnitThreatSituation, "player", f.unit) end
        else
            status = Plain(UnitThreatSituation, f.unit)
        end
    end
    local c = (type(status) == "number" and status > 0) and ns.Style.threat[status]
    if c then
        f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    else
        f:SetBackdropBorderColor(rgba(ns.Style.border))
    end
end

function ns.UpdateRange(f)
    if f.sizeKey ~= "party" then return end
    if not ns.db.rangeFade or previewing(f) or not unitExists(f) then
        f:SetAlpha(1)
        return
    end
    local ok, inRange, checked = pcall(UnitInRange, f.unit)
    if not ok then f:SetAlpha(1) return end
    if IsSecret(inRange) or IsSecret(checked) then
        if f.SetAlphaFromBoolean and IsSecret(inRange) then pcall(f.SetAlphaFromBoolean, f, inRange, 1, 0.45) end
        return
    end
    f:SetAlpha((checked and not inRange) and 0.45 or 1)
end

-- Everything (on show, unit change, settings change).
function ns.UpdateFrame(f)
    if not f or not ns.db then return end
    if not unitExists(f) and not f.preview then return end
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
