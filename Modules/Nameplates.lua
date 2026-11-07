--===========================================================================
-- EzWoW - Unit Frames
-- Modules/Nameplates.lua : EzWoW-style enemy nameplates (threat colour, cast bar,
--                          my debuffs, target highlight) and simple friendly
--                          nameplates (name only, or name + thin health bar)
--===========================================================================
-- The game's own nameplate stays in place (clicks, stacking and positions are
-- untouched); only its look is faded out and ours is drawn on top of it.
local _, ns = ...
local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local Plain, Raw, IsSecret = ns.Plain, ns.Raw, ns.IsSecret

local TEX = "Interface\\Buttons\\WHITE8X8"
local WIDTH, HEIGHT = 120, 10
local MAX_DEBUFFS, DEBUFF_SIZE = 5, 18

local active = {}   -- nameplate unit token -> our plate widget
local pool = {}

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local THREAT_DPS = { [1] = { 1.0, 0.85, 0.2 }, [2] = { 1.0, 0.5, 0.1 }, [3] = { 0.95, 0.15, 0.15 } }
local THREAT_TANK_GOOD = { 0.30, 0.75, 1.00 }
local THREAT_TANK_LOSING = { 1.0, 0.6, 0.1 }
local THREAT_TANK_LOST = { 0.95, 0.15, 0.15 }

-----------------------------------------------------------------------------
-- Widget
-----------------------------------------------------------------------------
local function createWidget()
    local w = CreateFrame("Frame", nil, UIParent)
    w:SetSize(WIDTH, HEIGHT)
    w.isPlate = true

    w.health = CreateFrame("StatusBar", nil, w, "BackdropTemplate")
    w.health:SetAllPoints()
    w.health:SetStatusBarTexture(TEX)
    ns.UIKit:ApplyBackdrop(w.health, 1, 0)
    w.health:SetBackdropColor(rgba(ns.Style.barBg))
    w.health:SetBackdropBorderColor(0, 0, 0, 1)

    w.glow = CreateFrame("Frame", nil, w, "BackdropTemplate")
    w.glow:SetPoint("TOPLEFT", -2, 2)
    w.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    w.glow:SetBackdrop({ edgeFile = TEX, edgeSize = 1 })
    w.glow:SetBackdropBorderColor(rgba(ns.Style.accent))
    w.glow:Hide()

    w.name = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.name:SetPoint("BOTTOMLEFT", w, "TOPLEFT", 0, 3)
    w.name:SetPoint("BOTTOMRIGHT", w, "TOPRIGHT", 0, 3)
    w.name:SetJustifyH("CENTER")
    w.name:SetWordWrap(false)
    w.level = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.level:SetPoint("RIGHT", w, "LEFT", -3, 0)
    w.pct = w.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.pct:SetPoint("CENTER", w.health, "CENTER", 0, 0)
    for _, fs in ipairs({ w.name, w.level, w.pct }) do
        local path, size = fs:GetFont()
        if path then fs:SetFont(path, fs == w.pct and math.max(8, (size or 10) - 2) or size, "OUTLINE") end
        fs:SetShadowOffset(0, 0)
    end

    w.raidIcon = w:CreateTexture(nil, "OVERLAY")
    w.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    w.raidIcon:SetSize(18, 18)
    w.raidIcon:SetPoint("LEFT", w, "RIGHT", 4, 0)
    w.raidIcon:Hide()

    ns.CreateCastbar(w, false, 9)
    w.castbar:ClearAllPoints()
    w.castbar:SetPoint("TOPLEFT", w, "BOTTOMLEFT", 11, -3)
    w.castbar:SetPoint("TOPRIGHT", w, "BOTTOMRIGHT", 0, -3)

    w.debuffs = {}
    for i = 1, MAX_DEBUFFS do
        local b = ns.CreateAuraIcon(w, DEBUFF_SIZE)
        b:EnableMouse(false)   -- the plate must stay clickable through the icons
        w.debuffs[i] = b
    end
    w:Hide()
    return w
end

-- My debuffs through an engine aura container (works in combat). Built out of
-- combat only; a widget without one keeps the icon scan above.
local PLATE_FILTERS = { "HARMFUL|INCLUDE_NAME_PLATE_ONLY|PLAYER", "HARMFUL|PLAYER" }

local function ensureContainer(w)
    if w.auraContainer or w.noContainer or ns.InCombat() then return end
    if not ns.CreatePlateAuraContainer then return end
    local ok, c = pcall(ns.CreatePlateAuraContainer, w, w.name, PLATE_FILTERS, MAX_DEBUFFS, DEBUFF_SIZE, 2)
    if ok and c then
        w.auraContainer = c
    else
        w.noContainer = true
    end
end

-- Widgets (with their containers) made ahead, so plates that appear in combat
-- still get one.
local PREWARM = 16
local function prewarm()
    if ns.InCombat() or not ns.db or not ns.db.nameplates then return end
    for _, w in ipairs(pool) do ensureContainer(w) end
    for _ = #pool + 1, PREWARM do
        local w = createWidget()
        ensureContainer(w)
        pool[#pool + 1] = w
    end
end

local function layoutDebuffs(w)
    local shown = 0
    for _, b in ipairs(w.debuffs) do if b:IsShown() then shown = shown + 1 end end
    local total = shown * DEBUFF_SIZE + math.max(0, shown - 1) * 2
    local x = -total / 2
    for _, b in ipairs(w.debuffs) do
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", w.name, "TOP", x, 2)
            x = x + DEBUFF_SIZE + 2
        end
    end
end

-----------------------------------------------------------------------------
-- Updates
-----------------------------------------------------------------------------
local function reactionColor(unit)
    if Plain(UnitIsTapDenied, unit) then return ns.Style.tapped end
    if Plain(UnitIsPlayer, unit) then
        local ok, _, classFile = pcall(UnitClass, unit)
        if ok and not IsSecret(classFile) and ns.ClassColor(classFile) and ns.db.classColor then
            return ns.ClassColor(classFile)
        end
    end
    local reaction = Plain(UnitReaction, unit, "player")
    local fc = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    return fc and { fc.r, fc.g, fc.b } or { 0.9, 0.2, 0.2 }
end

-- Returns a colour, or nil plus true when the threat status is secret.
local function threatColor(unit)
    if not ns.db.plateThreat then return nil end
    if not Plain(UnitAffectingCombat, unit) then return nil end
    local status = Raw(UnitThreatSituation, "player", unit)
    if IsSecret(status) then return nil, true end
    local inGroup = Plain(IsInGroup) and true or false
    if ns.db.plateTankMode then
        if status == 3 then return THREAT_TANK_GOOD end
        if status == 2 then return THREAT_TANK_LOSING end
        if inGroup then return THREAT_TANK_LOST end
        return nil
    end
    return type(status) == "number" and THREAT_DPS[status] or nil
end

-- Secret threat: the client still tells whether I am tanking the unit (as a
-- secret boolean), and picks between two colours for us without a comparison.
local function secretThreatColor(w, base)
    local fold = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if type(fold) ~= "function" or type(UnitDetailedThreatSituation) ~= "function" then return false end
    local ok, isTanking = pcall(UnitDetailedThreatSituation, "player", w.unit)
    if not ok or type(isTanking) ~= "boolean" then return false end
    local on, off
    if ns.db.plateTankMode then
        on = THREAT_TANK_GOOD
        off = (Plain(IsInGroup) and THREAT_TANK_LOST) or base
    else
        on, off = THREAT_DPS[3], base
    end
    return pcall(function()
        w.health:SetStatusBarColor(fold(isTanking, on[1], off[1]), fold(isTanking, on[2], off[2]),
            fold(isTanking, on[3], off[3]))
    end)
end

local function updateColor(w)
    local c, secret = threatColor(w.unit)
    if not c then
        c = reactionColor(w.unit)
        if secret and secretThreatColor(w, c) then return end
    end
    w.health:SetStatusBarColor(c[1], c[2], c[3])
end

local function updateHealth(w)
    local unit = w.unit
    local hp, maxhp = Raw(UnitHealth, unit), Raw(UnitHealthMax, unit)
    if not ns.FillBarFromPercent(w.health, ns.HealthPercent(unit)) then
        if not IsSecret(maxhp) and (type(maxhp) ~= "number" or maxhp <= 0) then maxhp = 1 end
        w.health.ezTop = nil
        pcall(w.health.SetMinMaxValues, w.health, 0, maxhp)
        pcall(w.health.SetValue, w.health, hp or 0)
    end
    if not IsSecret(maxhp) and (type(maxhp) ~= "number" or maxhp <= 0) then maxhp = 1 end
    if not IsSecret(hp) and not IsSecret(maxhp) and type(hp) == "number" then
        local pct = math.floor(hp / maxhp * 100 + 0.5)
        w.pct:SetText(pct < 100 and (pct .. "%") or "")
    elseif type(UnitHealthPercent) == "function" and CurveConstants and CurveConstants.ScaleTo100 then
        local pct = Raw(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        if not pcall(w.pct.SetFormattedText, w.pct, "%d%%", pct) then w.pct:SetText("") end
    else
        w.pct:SetText("")
    end
end

local CLASSIFICATION_SUFFIX = { elite = "+", rare = "R", rareelite = "R+", worldboss = "B" }

local function updateName(w)
    local unit = w.unit
    if not pcall(w.name.SetText, w.name, ns.UnitDisplayName(unit)) then w.name:SetText("") end
    local level = Plain(UnitLevel, unit)
    if type(level) == "number" then
        local text = level > 0 and tostring(level) or "??"
        local class = Plain(UnitClassification, unit)
        text = text .. (CLASSIFICATION_SUFFIX[class] or "")
        local color = (level > 0) and ((type(GetCreatureDifficultyColor) == "function" and Plain(GetCreatureDifficultyColor, level))
            or (type(GetQuestDifficultyColor) == "function" and Plain(GetQuestDifficultyColor, level)))
        w.level:SetText(text)
        if type(color) == "table" and color.r then w.level:SetTextColor(color.r, color.g, color.b) else w.level:SetTextColor(1, 0.1, 0.1) end
    else
        w.level:SetText("")
    end
end

local function updateDebuffs(w)
    local c = w.auraContainer
    if c then
        -- the engine follows UNIT_AURA itself
        pcall(c.SetShown, c, ns.db.plateDebuffs and true or false)
        return
    end
    local used = 0
    if ns.db.plateDebuffs then
        for i = 1, 40 do
            if used >= MAX_DEBUFFS then break end
            local data = ns.GetAuraData(w.unit, i, "HARMFUL|PLAYER")
            if data == nil then break end
            if data then
                used = used + 1
                ns.FillAuraIcon(w.debuffs[used], w.unit, data, "HARMFUL|PLAYER", true)
            end
        end
    end
    for i = used + 1, MAX_DEBUFFS do w.debuffs[i]:Hide() end
    layoutDebuffs(w)
end

local function updateRaidIcon(w)
    local index = Plain(GetRaidTargetIndex, w.unit)
    if index and type(SetRaidTargetIconTexture) == "function" then
        SetRaidTargetIconTexture(w.raidIcon, index)
        w.raidIcon:Show()
    else
        w.raidIcon:Hide()
    end
end

local function updateTarget(w)
    local isTarget = Plain(UnitIsUnit, w.unit, "target") and true or false
    w.glow:SetShown(isTarget)
    local hasTarget = Plain(UnitExists, "target") and true or false
    if ns.db.plateFadeOthers and hasTarget and not isTarget then
        w:SetAlpha(0.6)
    else
        w:SetAlpha(1)
    end
end

local function updateAll(w)
    updateName(w)
    updateColor(w)
    updateHealth(w)
    updateDebuffs(w)
    updateRaidIcon(w)
    updateTarget(w)
    ns.UpdateCastbar(w)
end

-----------------------------------------------------------------------------
-- Quest mob markers
-- A small quest icon above enemies that are a quest objective (kill target or
-- carrier of a quest item). It sits on the nameplate frame itself, so it shows
-- with our plate and with the default one alike.
-----------------------------------------------------------------------------
local QUEST_SIZE = 18
local QUEST_CACHE_TIME = 5          -- seconds a unit's answer is reused
local QUEST_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"
local questCache = {}               -- unit GUID -> { time, isQuest }
local questCacheSize = 0
local markers = {}                  -- nameplate frame -> marker texture
local markerPlates = {}             -- nameplate unit token -> nameplate frame
local questAtlas                    -- false when the atlas is missing

local function plainText(value)
    if type(value) == "string" and not IsSecret(value) then return value end
    return nil
end

-- "3/8" -> true (unfinished) / false (done); nil when the text has no progress
local function progressOpen(text)
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    if have then return tonumber(have) < tonumber(need) end
    local pct = text:match("(%d+)%%")
    if pct then return tonumber(pct) < 100 end
    return nil
end

-- true / false, or nil when the tooltip can't be read right now
local function scanQuestLines(unit)
    if not (C_TooltipInfo and type(C_TooltipInfo.GetUnit) == "function") then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or IsSecret(data) then return nil end
    local lines = data.lines
    if type(lines) ~= "table" or IsSecret(lines) then return nil end
    local types = Enum and Enum.TooltipDataLineType
    local OBJECTIVE = types and types.QuestObjective
    local foundObjective = false
    if OBJECTIVE then
        for _, line in ipairs(lines) do
            local lineType = type(line) == "table" and line.type
            if lineType ~= nil and not IsSecret(lineType) and lineType == OBJECTIVE then
                foundObjective = true
                local done = line.completed
                if IsSecret(done) then done = nil end
                if done == false then return true end
                if done == nil then
                    local text = plainText(line.leftText)
                    if text and progressOpen(text) ~= false then return true end
                end
            end
        end
    end
    if foundObjective then return false end
    -- no typed lines: an unfinished "x/y" line below the unit's name
    for i = 2, #lines do
        local line = lines[i]
        local text = type(line) == "table" and plainText(line.leftText)
        if text and progressOpen(text) == true then return true end
    end
    return false
end

local function isQuestUnit(unit)
    local guid = Plain(UnitGUID, unit)
    if type(guid) ~= "string" then guid = nil end
    local now = GetTime()
    local cached = guid and questCache[guid]
    if cached and now - cached.time < QUEST_CACHE_TIME then return cached.isQuest end
    local result = scanQuestLines(unit)
    if result == nil then return false end   -- not cached: try again next time
    if guid then
        if questCacheSize > 300 then wipe(questCache) questCacheSize = 0 end
        if not cached then questCacheSize = questCacheSize + 1 end
        questCache[guid] = { time = now, isQuest = result }
    end
    return result
end

local function markerFor(plate)
    local tex = markers[plate]
    if tex then return tex end
    local ok
    ok, tex = pcall(plate.CreateTexture, plate, nil, "OVERLAY", nil, 7)
    if not ok or not tex then return nil end
    tex:SetSize(QUEST_SIZE, QUEST_SIZE)
    if questAtlas == nil then
        questAtlas = false
        if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
            local okInfo, info = pcall(C_Texture.GetAtlasInfo, "QuestNormal")
            if okInfo and info then questAtlas = "QuestNormal" end
        end
    end
    if not (questAtlas and tex.SetAtlas and pcall(tex.SetAtlas, tex, questAtlas)) then
        tex:SetTexture(QUEST_TEXTURE)
    end
    tex:Hide()
    markers[plate] = tex
    return tex
end

-- above our name (and our debuff row), or above the default plate's name
local function placeMarker(tex, plate, unit)
    tex:ClearAllPoints()
    local w = active[unit]
    if w and w.plate == plate and w:IsShown() then
        if w.auraContainer and ns.db.plateDebuffs then
            -- the engine row's size is unknown to us (and nothing may anchor to
            -- it), so the marker goes left of the name instead of above the row
            tex:SetPoint("BOTTOMRIGHT", w, "TOPLEFT", -2, 1)
            return
        end
        local offset = 2
        for _, b in ipairs(w.debuffs) do
            if b:IsShown() then offset = DEBUFF_SIZE + 4 break end
        end
        tex:SetPoint("BOTTOM", w.name, "TOP", 0, offset * (ns.db.plateScale or 1))
        return
    end
    local uf = plate.UnitFrame
    local anchor = type(uf) == "table" and (uf.name or uf.healthBar) or nil
    if not (anchor and pcall(tex.SetPoint, tex, "BOTTOM", anchor, "TOP", 0, 2)) then
        tex:SetPoint("BOTTOM", plate, "TOP", 0, 0)
    end
end

local function hideQuestMarker(unit)
    local plate = markerPlates[unit]
    markerPlates[unit] = nil
    if plate and markers[plate] then markers[plate]:Hide() end
end

local function updateQuestMarker(unit)
    if type(unit) ~= "string" or IsSecret(unit) then return end
    local plate
    if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        local ok, found = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and found and not (found.IsForbidden and found:IsForbidden()) then plate = found end
    end
    if markerPlates[unit] ~= plate then hideQuestMarker(unit) end
    if not plate then return end
    markerPlates[unit] = plate
    local show = ns.db.plateQuest and Plain(UnitCanAttack, "player", unit)
        and not Plain(UnitIsDeadOrGhost, unit) and isQuestUnit(unit)
    local tex = markers[plate]
    if not show then
        if tex then tex:Hide() end
        return
    end
    tex = tex or markerFor(plate)
    if not tex then return end
    placeMarker(tex, plate, unit)
    tex:Show()
end

local function repositionQuestMarker(unit)
    local plate = markerPlates[unit]
    local tex = plate and markers[plate]
    if tex and tex:IsShown() then placeMarker(tex, plate, unit) end
end

local function refreshQuestMarkers()
    local units = {}
    for unit in pairs(markerPlates) do units[unit] = true end
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
                if type(unit) == "string" and not IsSecret(unit) then units[unit] = true end
            end
        end
    end
    for unit in pairs(units) do updateQuestMarker(unit) end
end

-- quest log events come in bursts: one refresh shortly after the last one
local questRefreshPending = false
local function scheduleQuestRefresh()
    if questRefreshPending then return end
    questRefreshPending = true
    C_Timer.After(0.5, function()
        questRefreshPending = false
        wipe(questCache)
        questCacheSize = 0
        refreshQuestMarkers()
    end)
end

-----------------------------------------------------------------------------
-- Friendly nameplates
-- "name": a class-coloured (players) / reaction-coloured (NPCs) name only;
-- "bar": the name above a thin health bar. Party and raid members get a larger
-- name. Inside instances the game's friendly plates are forbidden to addons:
-- they are never touched there (no plate is handed out for them), and only the
-- game's own settings are used (see the CVars below).
-----------------------------------------------------------------------------
local FRIEND_W, FRIEND_BAR_H = 90, 5

local friends = {}      -- nameplate unit token -> our friendly widget
local friendPool = {}

local function createFriendWidget()
    local w = CreateFrame("Frame", nil, UIParent)
    w:SetSize(FRIEND_W, 14)
    w.isFriend = true
    w.name = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.name:SetJustifyH("CENTER")
    w.name:SetWordWrap(false)
    w.name:SetShadowOffset(0, 0)
    local path, size = w.name:GetFont()
    w.fontPath, w.fontSize = path, size or 10
    -- party / raid mark left of the name (a crown for the group leader)
    w.groupIcon = w:CreateTexture(nil, "OVERLAY")
    w.groupIcon:SetSize(16, 16)
    w.groupIcon:Hide()
    w.health = CreateFrame("StatusBar", nil, w, "BackdropTemplate")
    w.health:SetStatusBarTexture(TEX)
    w.health:SetSize(FRIEND_W, FRIEND_BAR_H)
    w.health:SetPoint("CENTER", w, "CENTER", 0, -4)
    ns.UIKit:ApplyBackdrop(w.health, 1, 0)
    w.health:SetBackdropColor(rgba(ns.Style.barBg))
    w.health:SetBackdropBorderColor(0, 0, 0, 1)
    w:Hide()
    return w
end

local function friendColor(unit)
    if Plain(UnitIsPlayer, unit) then
        local ok, _, classFile = pcall(UnitClass, unit)
        local c = ok and not IsSecret(classFile) and ns.ClassColor(classFile)
        if c then return c end
        return { 1, 1, 1 }
    end
    local reaction = Plain(UnitReaction, unit, "player")
    local fc = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    return fc and { fc.r, fc.g, fc.b } or { 0.3, 0.9, 0.3 }
end

local GROUP_ATLAS = "socialqueuing-icon-group"
local GROUP_TEXTURE = "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon"
local LEADER_TEXTURE = "Interface\\GroupFrame\\UI-Group-LeaderIcon"

local function updateGroupIcon(w)
    local icon = w.groupIcon
    if not icon then return end
    local inGroup = Plain(UnitInParty, w.unit) or Plain(UnitInRaid, w.unit)
    if not inGroup or Plain(UnitIsUnit, w.unit, "player") then
        icon:Hide()
        return
    end
    if Plain(UnitIsGroupLeader, w.unit) then
        icon:SetTexture(LEADER_TEXTURE)
    elseif not (icon.SetAtlas and pcall(icon.SetAtlas, icon, GROUP_ATLAS)) then
        icon:SetTexture(GROUP_TEXTURE)
    end
    icon:ClearAllPoints()
    local ok, textWidth = pcall(w.name.GetStringWidth, w.name)
    if ok and type(textWidth) == "number" and not IsSecret(textWidth) and textWidth > 0 then
        icon:SetPoint("RIGHT", w.name, "CENTER", -(textWidth / 2) - 2, 0)
    else
        icon:SetPoint("BOTTOM", w.name, "TOP", 0, 1)
    end
    icon:Show()
end

local function layoutFriend(w)
    local inGroup = Plain(UnitInParty, w.unit) or Plain(UnitInRaid, w.unit)
    -- party and raid members get clearly bigger names than other friendly players
    local size = w.fontSize + (inGroup and 5 or 0)
    if w.fontPath then w.name:SetFont(w.fontPath, size, "OUTLINE") end
    w.name:ClearAllPoints()
    if ns.db.friendlyPlates == "bar" then
        w.health:Show()
        w.name:SetPoint("BOTTOM", w.health, "TOP", 0, 2)
    else
        w.health:Hide()
        w.name:SetPoint("CENTER", w, "CENTER", 0, 0)
    end
    w.name:SetWidth(FRIEND_W + 40)
    updateGroupIcon(w)
end

local function updateFriendName(w)
    if not pcall(w.name.SetText, w.name, ns.UnitDisplayName(w.unit)) then w.name:SetText("") end
    local c = friendColor(w.unit)
    w.name:SetTextColor(c[1], c[2], c[3])
    w.health:SetStatusBarColor(c[1], c[2], c[3])
    updateGroupIcon(w)
end

-- secret-safe fill, like the enemy plates
local function updateFriendHealth(w)
    if ns.db.friendlyPlates ~= "bar" then return end
    local unit = w.unit
    if not ns.FillBarFromPercent(w.health, ns.HealthPercent(unit)) then
        local hp, maxhp = Raw(UnitHealth, unit), Raw(UnitHealthMax, unit)
        if not IsSecret(maxhp) and (type(maxhp) ~= "number" or maxhp <= 0) then maxhp = 1 end
        w.health.ezTop = nil
        pcall(w.health.SetMinMaxValues, w.health, 0, maxhp)
        pcall(w.health.SetValue, w.health, hp or 0)
    end
end

local function updateFriend(w)
    layoutFriend(w)
    updateFriendName(w)
    updateFriendHealth(w)
end

-- The game's own settings for instances (set out of combat only). The user's
-- values are kept in the saved variables and given back when not needed.
local CVAR_ONLY_NAMES, CVAR_SHOW_FRIENDS = "nameplateShowOnlyNames", "nameplateShowFriends"
-- 0 = plates overlap and stay over their units, 1 = plates stack upward
local CVAR_MOTION = "nameplateMotion"

local function getCVar(name)
    local value
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        value = Plain(C_CVar.GetCVar, name)
    else
        value = Plain(GetCVar, name)
    end
    return type(value) == "string" and value or nil
end

local function setCVar(name, value)
    if C_CVar and type(C_CVar.SetCVar) == "function" then return pcall(C_CVar.SetCVar, name, value) end
    if type(SetCVar) == "function" then return pcall(SetCVar, name, value) end
    return false
end

-- want = the value we need, or nil to give the user's value back
local function manageCVar(name, want)
    local backup = ns.db.cvarBackup
    local current = getCVar(name)
    if current == nil then return end   -- not on this client
    if want then
        if backup[name] == nil then backup[name] = current end
        if current ~= want then setCVar(name, want) end
    elseif backup[name] ~= nil then
        if current ~= backup[name] then setCVar(name, backup[name]) end
        backup[name] = nil
    end
end

function ns.ApplyFriendlyCVars()
    if not ns.db then return end
    if ns.InCombat() then
        ns.RunAfterCombat("friendlyCVars", ns.ApplyFriendlyCVars)
        return
    end
    if type(ns.db.cvarBackup) ~= "table" then ns.db.cvarBackup = {} end
    local mode = ns.db.friendlyPlates
    local on = mode == "name" or mode == "bar"
    local inInstance = Plain(IsInInstance) and true or false
    manageCVar(CVAR_ONLY_NAMES, (on and inInstance and mode == "name") and "1" or nil)
    manageCVar(CVAR_SHOW_FRIENDS, (on and inInstance and ns.db.friendlyHideInstance) and "0" or nil)
    manageCVar(CVAR_MOTION, ns.db.plateOverlap ~= false and "0" or nil)
end

-----------------------------------------------------------------------------
-- Attach / detach
-----------------------------------------------------------------------------
local function blizzardFrame(plate)
    return plate and plate.UnitFrame
end

-- The default plate is faded out while ours is shown: every part of the nameplate
-- that isn't ours (its unit frame, and anything shown for the current target).
-- If the game turns one back up it is faded again. If a part can't be faded at all
-- (protected on this client), our plates are switched off for the session so the
-- two never overlap.
local fadedFrames, hookedFrames = {}, {}
local blocked, warned = false, false

local function canControl(frame)
    if not frame then return false end
    if frame.IsForbidden then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or forbidden then return false end
    end
    return true
end

local function fadeFrame(frame, faded)
    if not canControl(frame) then return false end
    fadedFrames[frame] = faded or nil
    if faded and not hookedFrames[frame] then
        hookedFrames[frame] = true
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            if fadedFrames[self] and not self.ezFading and type(alpha) == "number" and alpha > 0 then
                self.ezFading = true
                pcall(self.SetAlpha, self, 0)
                self.ezFading = false
            end
        end)
    end
    frame.ezFading = true
    local ok = pcall(frame.SetAlpha, frame, faded and 0 or 1)
    frame.ezFading = false
    return ok
end

-- the parts of a nameplate that belong to the game (everything but our widget)
local function defaultParts(plate, ours)
    local parts = {}
    local uf = blizzardFrame(plate)
    if uf then parts[#parts + 1] = uf end
    local ok, children = pcall(function() return { plate:GetChildren() } end)
    if ok then
        for _, child in ipairs(children) do
            if child ~= ours and child ~= uf then parts[#parts + 1] = child end
        end
    end
    return parts
end

local function setBlizzardVisible(plate, visible, ours)
    local allOk = true
    for _, part in ipairs(defaultParts(plate, ours)) do
        if not fadeFrame(part, not visible) then allOk = false end
    end
    return allOk
end

-- true when some default part is still visible on screen
local function blizzardStillShown(plate, ours)
    for _, part in ipairs(defaultParts(plate, ours)) do
        if not canControl(part) then
            local okShown, shown = pcall(part.IsVisible, part)
            if not okShown or shown then return true end
        else
            local okShown, shown = pcall(part.IsVisible, part)
            if okShown and shown then
                local okAlpha, alpha = pcall(part.GetEffectiveAlpha or part.GetAlpha, part)
                if okAlpha and type(alpha) == "number" and alpha > 0.05 then return true end
            end
        end
    end
    return false
end

local function detachFriend(unit)
    local w = friends[unit]
    if not w then return end
    friends[unit] = nil
    if w.plate then setBlizzardVisible(w.plate, true, w) end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(UIParent)
    w.plate, w.unit = nil, nil
    friendPool[#friendPool + 1] = w
end

local function detach(unit)
    detachFriend(unit)
    local w = active[unit]
    if not w then return end
    active[unit] = nil
    if w.plate then setBlizzardVisible(w.plate, true, w) end
    if w.auraContainer and not pcall(w.auraContainer.SetUnit, w.auraContainer, "none") then
        pcall(w.auraContainer.SetUnit, w.auraContainer, nil)
    end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(UIParent)
    w.plate, w.unit = nil, nil
    pool[#pool + 1] = w
    repositionQuestMarker(unit)
end

local function giveUp()
    if blocked then return end
    blocked = true
    for unit in pairs(active) do detach(unit) end
    for unit in pairs(friends) do detach(unit) end
    if not warned then
        warned = true
        ns.Print(ns:L("platesBlocked"))
    end
end

-- friendly plate (outside instances only: there the game hands out no plate)
local function attachFriend(unit, plate)
    local mode = ns.db.friendlyPlates
    if mode ~= "name" and mode ~= "bar" then return end
    if Plain(UnitIsUnit, unit, "player") then return end   -- my own resource plate
    local w = table.remove(friendPool) or createFriendWidget()
    w.unit, w.plate = unit, plate
    w:SetParent(plate)
    w:SetScale(ns.db.plateScale or 1)
    w:ClearAllPoints()
    w:SetPoint("CENTER", plate, "CENTER", 0, 0)
    w:SetFrameLevel(plate:GetFrameLevel() + 5)
    w:Show()
    friends[unit] = w
    -- a part that can't be faded: this plate keeps the default look
    if not setBlizzardVisible(plate, false, w) then
        detachFriend(unit)
        return
    end
    updateFriend(w)
end

local function attach(unit)
    if blocked or type(unit) ~= "string" or IsSecret(unit) then return end
    detach(unit)
    if not (C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function") then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    if not Plain(UnitCanAttack, "player", unit) then
        attachFriend(unit, plate)
        return
    end
    if not ns.db.nameplates then return end

    local w = table.remove(pool) or createWidget()
    ensureContainer(w)
    w.unit, w.plate = unit, plate
    if w.auraContainer then
        pcall(w.auraContainer.SetUnit, w.auraContainer, unit)
        pcall(w.auraContainer.UpdateAllAuras, w.auraContainer)
    end
    w:SetParent(plate)
    w:SetScale(ns.db.plateScale or 1)
    w:ClearAllPoints()
    w:SetPoint("CENTER", plate, "CENTER", 0, 0)
    w:SetFrameLevel(plate:GetFrameLevel() + 5)
    w:Show()
    active[unit] = w
    if not setBlizzardVisible(plate, false, w) then
        giveUp()
        return
    end
    updateAll(w)
    ns.CheckPlate(unit)
end

-- Fades again (new parts appear when a unit becomes the target) and stops our
-- plates if the default one still shows.
function ns.CheckPlate(unit)
    local w = active[unit]
    if not w or not w.plate then return end
    setBlizzardVisible(w.plate, false, w)
    C_Timer.After(0.3, function()
        if active[unit] == w and blizzardStillShown(w.plate, w) then giveUp() end
    end)
end

-- /ezuf plates : what the target's nameplate is made of (to report problems)
function ns.DescribeTargetPlate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return ns.Print("no nameplate API") end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    if not ok or not plate then return ns.Print("no nameplate for the target") end
    local function describe(frame, label)
        local okF, forbidden = pcall(frame.IsForbidden, frame)
        local okN, name = pcall(frame.GetName, frame)
        local okV, visible = pcall(frame.IsVisible, frame)
        local okA, alpha = pcall(frame.GetEffectiveAlpha or frame.GetAlpha, frame)
        ns.Print(string.format("%s %s forbidden=%s visible=%s alpha=%s", label, tostring(okN and name or "?"),
            tostring(okF and forbidden), tostring(okV and visible), tostring(okA and alpha)))
    end
    describe(plate, "plate")
    local w = active["target"]
    for i, part in ipairs(defaultParts(plate, w)) do describe(part, "part" .. i) end
    if w then describe(w, "ezwow") end
    ns.Print("blocked=" .. tostring(blocked))
end

function ns.RefreshNameplates()
    for unit in pairs(active) do detach(unit) end
    for unit in pairs(friends) do detach(unit) end
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
                if type(unit) == "string" then attach(unit) end
            end
        end
    end
    refreshQuestMarkers()
end

-----------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------
local UNIT_HANDLERS = {
    UNIT_HEALTH = updateHealth,
    UNIT_MAXHEALTH = updateHealth,
    UNIT_NAME_UPDATE = updateName,
    UNIT_LEVEL = updateName,
    UNIT_CLASSIFICATION_CHANGED = updateName,
    UNIT_FACTION = updateColor,
    UNIT_AURA = updateDebuffs,
    UNIT_THREAT_LIST_UPDATE = updateColor,
    UNIT_SPELLCAST_START = function(w) ns.UpdateCastbar(w, true) end,
    UNIT_SPELLCAST_CHANNEL_START = function(w) ns.UpdateCastbar(w, true) end,
    UNIT_SPELLCAST_DELAYED = function(w) ns.UpdateCastbar(w) end,
    UNIT_SPELLCAST_CHANNEL_UPDATE = function(w) ns.UpdateCastbar(w) end,
    UNIT_SPELLCAST_INTERRUPTIBLE = function(w) ns.UpdateCastbar(w) end,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(w) ns.UpdateCastbar(w) end,
    UNIT_SPELLCAST_STOP = function(w) ns.CastbarStopped(w, false) end,
    UNIT_SPELLCAST_CHANNEL_STOP = function(w) ns.CastbarStopped(w, false) end,
    UNIT_SPELLCAST_FAILED = function(w) ns.CastbarStopped(w, false) end,
    UNIT_SPELLCAST_INTERRUPTED = function(w) ns.CastbarStopped(w, true) end,
}

local FRIEND_HANDLERS = {
    UNIT_HEALTH = updateFriendHealth,
    UNIT_MAXHEALTH = updateFriendHealth,
    UNIT_NAME_UPDATE = updateFriendName,
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        for name in pairs(UNIT_HANDLERS) do pcall(self.RegisterEvent, self, name) end
        for _, name in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
            "RAID_TARGET_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_FOCUS_CHANGED",
            "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
            "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED" }) do
            pcall(self.RegisterEvent, self, name)
        end
        C_Timer.After(1, prewarm)
        ns.ApplyFriendlyCVars()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then prewarm() end
    -- a unit that turns hostile or friendly gets the other kind of plate
    if event == "UNIT_FACTION" and type(unit) == "string" and not IsSecret(unit) and unit:find("^nameplate") then
        local hostile = Plain(UnitCanAttack, "player", unit) and true or false
        if (hostile and (friends[unit] or (ns.db.nameplates and not active[unit]))) or (not hostile and active[unit]) then
            attach(unit)
            updateQuestMarker(unit)
            return
        end
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        attach(unit)
        updateQuestMarker(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        detach(unit)
        if type(unit) == "string" and not IsSecret(unit) then hideQuestMarker(unit) end
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        scheduleQuestRefresh()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ns.ApplyFriendlyCVars()
    elseif event == "GROUP_ROSTER_UPDATE" then
        for _, w in pairs(friends) do layoutFriend(w) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- the target's default plate gets new parts: fade them too
        for _, w in pairs(friends) do setBlizzardVisible(w.plate, false, w) end
        for unit, w in pairs(active) do
            updateTarget(w)
            ns.CheckPlate(unit)
            -- the interrupt warning may be limited to my target and focus
            if ns.db.kickTargetOnly then ns.UpdateCastbar(w) end
        end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        if ns.db.kickTargetOnly then
            for _, w in pairs(active) do ns.UpdateCastbar(w) end
        end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, w in pairs(active) do updateRaidIcon(w) end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        for _, w in pairs(active) do updateColor(w) end
    else
        local handler = UNIT_HANDLERS[event]
        local w = type(unit) == "string" and not IsSecret(unit) and active[unit]
        local fw = type(unit) == "string" and not IsSecret(unit) and friends[unit]
        if fw and FRIEND_HANDLERS[event] then FRIEND_HANDLERS[event](fw) end
        if handler and w then
            handler(w)
            if event == "UNIT_AURA" then repositionQuestMarker(unit) end
        end
    end
end)
