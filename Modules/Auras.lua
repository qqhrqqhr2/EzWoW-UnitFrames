--===========================================================================
-- EzWoW - Unit Frames
-- Modules/Auras.lua : Target buffs/debuffs, party debuffs & dispel highlight
--===========================================================================
local _, ns = ...
local type, ipairs, pcall = type, ipairs, pcall
local Plain, Raw, IsSecret = ns.Plain, ns.Raw, ns.IsSecret

local TEX = "Interface\\Buttons\\WHITE8X8"
local MAX_SCAN = 40

local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
}
local DEFAULT_DEBUFF = { 0.80, 0.10, 0.10 }
local BUFF_BORDER = { 0.20, 0.25, 0.30 }

-- Returns the aura table, nil when the list has ended, or false for an aura of the
-- other kind (some clients ignore the HARMFUL/HELPFUL filter, which showed every
-- buff a second time in the debuff row).
local function getAura(unit, index, filter)
    if not C_UnitAuras then return nil end
    local harmful = filter:find("HARMFUL", 1, true) ~= nil
    local fn = harmful and C_UnitAuras.GetDebuffDataByIndex or C_UnitAuras.GetBuffDataByIndex
    if type(fn) ~= "function" then fn = C_UnitAuras.GetAuraDataByIndex end
    if type(fn) ~= "function" then return nil end
    local ok, data = pcall(fn, unit, index, filter)
    if not ok or type(data) ~= "table" then return nil end
    local isHarmful, isHelpful = data.isHarmful, data.isHelpful
    if harmful and not IsSecret(isHelpful) and isHelpful == true and not (not IsSecret(isHarmful) and isHarmful == true) then
        return false
    end
    if not harmful and not IsSecret(isHarmful) and isHarmful == true then
        return false
    end
    return data
end

local function plainField(data, key)
    local value = data[key]
    if IsSecret(value) then return nil end
    return value
end

local function showAuraTooltip(self)
    if not self.unit or not self.auraID then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local done = false
    if self.isDebuff and GameTooltip.SetUnitDebuffByAuraInstanceID then
        done = pcall(GameTooltip.SetUnitDebuffByAuraInstanceID, GameTooltip, self.unit, self.auraID, self.filter)
    elseif GameTooltip.SetUnitBuffByAuraInstanceID then
        done = pcall(GameTooltip.SetUnitBuffByAuraInstanceID, GameTooltip, self.unit, self.auraID, self.filter)
    end
    if not done and GameTooltip.SetUnitAuraByAuraInstanceID then
        pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, self.auraID)
    end
    GameTooltip:Show()
end

local function createIcon(parent, size)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(size, size)
    b:SetBackdrop({ edgeFile = TEX, edgeSize = 1 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(size < 22) end
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, 0)
    b:EnableMouse(true)
    b:SetScript("OnEnter", showAuraTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local function setCooldown(b, unit, data)
    local duration, expiration = plainField(data, "duration"), plainField(data, "expirationTime")
    if type(duration) == "number" and type(expiration) == "number" then
        if duration > 0 then
            b.cd:SetCooldown(expiration - duration, duration)
            b.cd:Show()
        else
            b.cd:Hide()
        end
        return
    end
    -- secret timing: let the client drive the swipe
    local id = data.auraInstanceID
    if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" and b.cd.SetCooldownFromDurationObject then
        local durObj = Raw(C_UnitAuras.GetAuraDuration, unit, id)
        if durObj and pcall(b.cd.SetCooldownFromDurationObject, b.cd, durObj) then
            b.cd:Show()
            return
        end
    end
    b.cd:Hide()
end

local function setCount(b, unit, data)
    local stacks = plainField(data, "applications")
    if type(stacks) == "number" then
        b.count:SetText(stacks > 1 and stacks or "")
        return
    end
    if C_UnitAuras and type(C_UnitAuras.GetAuraApplicationDisplayCount) == "function" then
        local text = Raw(C_UnitAuras.GetAuraApplicationDisplayCount, unit, data.auraInstanceID, 2, 99)
        if pcall(b.count.SetText, b.count, text) then return end
    end
    b.count:SetText("")
end

local function fillIcon(b, unit, data, filter, isDebuff)
    b.unit, b.auraID, b.filter, b.isDebuff = unit, data.auraInstanceID, filter, isDebuff
    pcall(b.icon.SetTexture, b.icon, data.icon)
    setCooldown(b, unit, data)
    setCount(b, unit, data)
    local border = BUFF_BORDER
    if isDebuff then
        local dispel = plainField(data, "dispelName")
        border = (dispel and DISPEL_COLORS[dispel]) or DEFAULT_DEBUFF
    end
    if plainField(data, "isFromPlayerOrPlayerPet") == true then
        border = ns.Style.accent
        b:SetAlpha(1)
    else
        b:SetAlpha(isDebuff and 0.85 or 1)
    end
    b:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    b:Show()
end

-----------------------------------------------------------------------------
-- Target: debuffs first, buffs on the following rows
-----------------------------------------------------------------------------
local TARGET_COLUMNS, TARGET_MAX = 8, 32

-- yOffset: gap below the frame (the player frame keeps room for combo points / druid mana)
function ns.CreateTargetAuras(f, yOffset)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -(yOffset or 4))
    holder:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -(yOffset or 4))
    holder:SetHeight(1)
    holder.icons = {}
    f.auras = holder
end

local function layoutTargetIcon(f, b, slot)
    local width = f:GetWidth() or 232
    local size = math.floor((width - (TARGET_COLUMNS - 1) * 3) / TARGET_COLUMNS)
    b:SetSize(size, size)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(size < 22) end
    local row = math.floor((slot - 1) / TARGET_COLUMNS)
    local col = (slot - 1) % TARGET_COLUMNS
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f.auras, "TOPLEFT", col * (size + 3), -row * (size + 3))
end

local function updateTargetAuras(f)
    local holder = f.auras
    local slot, filled = 0, {}
    local function add(data, filter, isDebuff)
        if slot >= TARGET_MAX then return end
        slot = slot + 1
        local b = holder.icons[slot]
        if not b then
            b = createIcon(holder, 24)
            holder.icons[slot] = b
        end
        layoutTargetIcon(f, b, slot)
        fillIcon(b, f.unit, data, filter, isDebuff)
        filled[slot] = true
    end

    local enabled = (f.unit == "player") and ns.db.playerAuras or ns.db.targetAuras
    if enabled and Plain(UnitExists, f.unit) then
        local debuffFilter = (ns.db.onlyMyDebuffs and f.unit ~= "player") and "HARMFUL|PLAYER" or "HARMFUL"
        for i = 1, MAX_SCAN do
            local data = getAura(f.unit, i, debuffFilter)
            if data == nil then break end
            if data then add(data, debuffFilter, true) end
        end
        -- buffs start on a new row
        if slot % TARGET_COLUMNS ~= 0 then slot = slot + (TARGET_COLUMNS - slot % TARGET_COLUMNS) end
        for i = 1, MAX_SCAN do
            local data = getAura(f.unit, i, "HELPFUL")
            if data == nil then break end
            if data then add(data, "HELPFUL", false) end
        end
    end
    for i, b in ipairs(holder.icons) do
        if not filled[i] then
            b:Hide()
            b.auraID = nil
        end
    end
end

-----------------------------------------------------------------------------
-- Party: up to 4 debuffs beside the frame, dispellable first + highlight
-----------------------------------------------------------------------------
local PARTY_ICONS, PARTY_SIZE = 4, 20

function ns.CreatePartyAuras(f)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("LEFT", f, "RIGHT", 4, 0)
    holder:SetSize(PARTY_ICONS * (PARTY_SIZE + 2), PARTY_SIZE)
    holder.icons = {}
    for i = 1, PARTY_ICONS do
        local b = createIcon(holder, PARTY_SIZE)
        b:SetPoint("LEFT", holder, "LEFT", (i - 1) * (PARTY_SIZE + 2), 0)
        holder.icons[i] = b
    end
    f.auras = holder
end

-- true when a (secret-id) debuff is also in the dispellable list: the client
-- answers this even when it hides the aura instance id from us.
local function inRaidList(unit, id)
    if not (C_UnitAuras and type(C_UnitAuras.IsAuraFilteredOutByInstanceID) == "function") then return nil end
    local ok, filteredOut = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, id, "HARMFUL|RAID")
    if not ok or IsSecret(filteredOut) or type(filteredOut) ~= "boolean" then return nil end
    return not filteredOut
end

-- Key that identifies a debuff across both passes. The aura instance id is best;
-- when it is secret the icon texture is used, and when that is secret too there
-- is no key (nil).
local function auraKey(data)
    local id = data.auraInstanceID
    if id ~= nil and not IsSecret(id) then return id end
    local icon = data.icon
    if icon ~= nil and not IsSecret(icon) then return "i" .. tostring(icon) end
    return nil
end

local function updatePartyAuras(f)
    local holder = f.auras
    local used, seen = 0, {}
    local fromRaidPass = 0
    local glow
    if ns.db.partyDebuffs and Plain(UnitExists, f.unit) then
        for _, filter in ipairs({ "HARMFUL|RAID", "HARMFUL" }) do
            local secondPass = filter == "HARMFUL"
            for i = 1, MAX_SCAN do
                if used >= PARTY_ICONS then break end
                local data = getAura(f.unit, i, filter)
                if data == nil then break end
                local key = data and auraKey(data)
                local duplicate = false
                if data and key == nil then
                    -- nothing comparable: in the second pass, skip debuffs the first
                    -- pass may already show (dispellable ones, or all when unsure)
                    if secondPass and fromRaidPass > 0 then
                        local inRaid = inRaidList(f.unit, data.auraInstanceID)
                        duplicate = (inRaid == nil) or inRaid
                    end
                    key = "s" .. filter .. i
                end
                if data and not duplicate and not seen[key] then
                    seen[key] = true
                    if not secondPass then fromRaidPass = fromRaidPass + 1 end
                    used = used + 1
                    fillIcon(holder.icons[used], f.unit, data, filter, true)
                    if filter == "HARMFUL|RAID" and not glow then
                        local dispel = plainField(data, "dispelName")
                        glow = (dispel and DISPEL_COLORS[dispel]) or DEFAULT_DEBUFF
                    end
                end
            end
        end
    end
    for i = used + 1, PARTY_ICONS do
        holder.icons[i]:Hide()
        holder.icons[i].auraID = nil
    end
    if f.dispelGlow then
        if glow then
            f.dispelGlow:SetBackdropBorderColor(glow[1], glow[2], glow[3], 1)
            f.dispelGlow:Show()
        else
            f.dispelGlow:Hide()
        end
    end
end

-- shared with the nameplates
ns.CreateAuraIcon = createIcon
ns.FillAuraIcon = fillIcon
ns.GetAuraData = getAura

function ns.UpdateAuras(f)
    if not f.auras then return end
    if f.preview and not Plain(UnitExists, f.unit) then
        for _, b in ipairs(f.auras.icons) do b:Hide() end
        if f.dispelGlow then f.dispelGlow:Hide() end
        return
    end
    if f.sizeKey == "party" then
        updatePartyAuras(f)
    else
        updateTargetAuras(f)
    end
end
