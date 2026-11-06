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
    -- GetAuraDataByIndex with the filter is the one that returns data on the
    -- live client; the Buff/Debuff variants are only a fallback.
    local fn = C_UnitAuras.GetAuraDataByIndex
    if type(fn) ~= "function" then
        fn = harmful and C_UnitAuras.GetDebuffDataByIndex or C_UnitAuras.GetBuffDataByIndex
    end
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

-----------------------------------------------------------------------------
-- Engine aura containers (12.1 client)
-- In combat the client locks aura data away from addon code, so the rows are
-- handed to an engine AuraContainer: the client itself fills icon, timer and
-- stack count, also in combat. Addon code only builds each button's regions
-- once (initializeFrame) and sets the layout out of combat.
-----------------------------------------------------------------------------
local GAP = 3
local GROUP_MAX = 16

local function iconSize(f)
    local width = f:GetWidth() or 232
    return math.floor((width - (TARGET_COLUMNS - 1) * GAP) / TARGET_COLUMNS)
end

local function containerSupported()
    if not (C_AddOns and AnchorUtil and AnchorUtil.FlowDirection) then return false end
    if C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local ok, probe = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not probe or type(probe.AddAuraGroup) ~= "function" then return false end
    probe:Hide()
    return probe
end

-- Debuff border: a white texture the engine tints with the dispel colour.
local DISPEL_STYLE = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

-- clickThrough: no tooltip either (nameplates must stay clickable through the icons)
local function makeInitializer(f, isDebuff, clickThrough, fixedSize)
    return function(button)
        local size = fixedSize or f.auraIconSize or 24
        pcall(button.SetSize, button, size, size)
        if clickThrough then pcall(button.SetMouseMotionEnabled, button, false) end
        local base = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        base:SetAllPoints(button)
        base:SetColorTexture(BUFF_BORDER[1], BUFF_BORDER[2], BUFF_BORDER[3], 1)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(size < 22) end
        local textHost = CreateFrame("Frame", nil, button)
        textHost:SetAllPoints(button)
        textHost:SetFrameLevel(cd:GetFrameLevel() + 2)
        textHost:EnableMouse(false)
        -- the engine writes this string, so it needs its font before registering
        local count = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", 1, 0)
        pcall(button.SetMouseClickEnabled, button, false)
        button:SetIcon(icon)
        button:SetDurationCooldown(cd)
        button:SetApplicationCount(count, {})
        if isDebuff and button.AddDispelTypeTexture and DISPEL_STYLE ~= nil then
            local tint = button:CreateTexture(nil, "BACKGROUND", nil, 0)
            tint:SetAllPoints(button)
            tint:SetColorTexture(1, 1, 1, 1)
            tint:Hide()
            pcall(button.AddDispelTypeTexture, button, tint, {
                style = DISPEL_STYLE, showWhenHarmful = true,
                showWhenHelpful = false, showWithoutDispelType = true,
            })
        end
    end
end

local function debuffFilterFor(f)
    if ns.db.onlyMyDebuffs and f.unit ~= "player" then return "HARMFUL|PLAYER" end
    return "HARMFUL"
end

local function groupLayout(size, newLine)
    return { elementWidth = size, elementHeight = size, elementSpacing = GAP,
        lineSpacing = GAP, forceNewLine = newLine or nil }
end

-- While auras are secret (combat, and also out of combat in instances) the client
-- refuses our writes to the engine's buttons once they are built.
local function aurasSecret()
    if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and not IsSecret(secret) then return secret and true or false end
    end
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        return not pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
    end
    return false
end

-- Resizes the buttons the engine already built. Only when auras are not secret;
-- returns true when every button could be sized.
local function resizeGroupButtons(c, keys, size)
    if aurasSecret() then return false end
    local all = true
    for _, key in ipairs(keys) do
        local okN, n = false, 0
        if c.GetAuraGroupFrameCount then okN, n = pcall(c.GetAuraGroupFrameCount, c, key) end
        if okN and type(n) == "number" and not IsSecret(n) then
            for i = 1, n do
                local ok, button = pcall(c.GetAuraGroupFrame, c, key, i)
                if ok and button then
                    if not pcall(button.SetSize, button, size, size) then all = false end
                end
            end
        end
    end
    return all
end

-- Size, row width and filter follow the settings; out of combat only.
-- New buttons get their size at creation (initializer) and from the group layout;
-- buttons built earlier are resized once the client allows it (c.ezButtonSize).
local function applyContainerConfig(f)
    local c = f.auraContainer
    if not c or ns.InCombat() then return end
    local size = iconSize(f)
    local enabled = (f.unit == "player") and ns.db.playerAuras or ns.db.targetAuras
    pcall(c.SetShown, c, enabled and true or false)
    local filter = debuffFilterFor(f)
    if c.ezFilter ~= filter and c.SetAuraGroupFilterString then
        if pcall(c.SetAuraGroupFilterString, c, "debuffs", filter) then c.ezFilter = filter end
    end
    if c.ezSize ~= size then
        c.ezSize, f.auraIconSize = size, size
        if c.SetFlowLayoutMaximumLineSize then
            pcall(c.SetFlowLayoutMaximumLineSize, c, TARGET_COLUMNS * size + (TARGET_COLUMNS - 1) * GAP + 0.4)
        end
        pcall(c.SetAuraGroupLayout, c, "debuffs", groupLayout(size))
        pcall(c.SetAuraGroupLayout, c, "buffs", groupLayout(size, true))
    end
    if c.ezButtonSize ~= size and resizeGroupButtons(c, { "debuffs", "buffs" }, size) then
        c.ezButtonSize = size
    end
end

-- frames whose button sizing may still be pending
local containerFrames = {}

local buildContainer

local function createAuraContainer(f, yOffset)
    local c = containerSupported()
    if not c then return nil end
    local ok, err = pcall(buildContainer, c, f, yOffset)
    if ok then return c end
    pcall(c.Hide, c)
    if type(geterrorhandler) == "function" then geterrorhandler()(err) end
    return nil
end

function buildContainer(c, f, yOffset)
    c:SetParent(f)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -(yOffset or 4))
    c:SetSize(1, 1)
    local size = iconSize(f)
    f.auraIconSize = size
    if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint("TOPLEFT") end
    if c.SetFlowLayoutGrowthDirection then
        c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    end
    if c.SetFlowLayoutMaximumLineSize then
        c:SetFlowLayoutMaximumLineSize(TARGET_COLUMNS * size + (TARGET_COLUMNS - 1) * GAP + 0.4)
    end
    -- debuffs first, buffs start on a new row
    c:AddAuraGroup("debuffs", debuffFilterFor(f), {
        maxFrameCount = GROUP_MAX,
        initializeFrame = makeInitializer(f, true),
        layout = groupLayout(size),
    })
    c:AddAuraGroup("buffs", "HELPFUL", {
        maxFrameCount = GROUP_MAX,
        initializeFrame = makeInitializer(f, false),
        layout = groupLayout(size, true),
    })
    c.ezFilter, c.ezSize, c.ezButtonSize = debuffFilterFor(f), size, size
    c:SetUnit(f.unit)
    pcall(c.UpdateAllAuras, c)
    c:Show()
end

-- yOffset: gap below the frame (the player frame keeps room for combo points / druid mana)
function ns.CreateTargetAuras(f, yOffset)
    local okC, container = pcall(createAuraContainer, f, yOffset)
    if okC and container then
        f.auraContainer = container
        f.auras = { icons = {} }
        containerFrames[#containerFrames + 1] = f
        return
    end
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
local PARTY_ICONS, PARTY_SIZE, PARTY_GAP = 4, 20, 2
-- buffs: one row under the member (the party layout leaves PARTY_BUFF_ROW for it)
local PARTY_BUFF_ICONS, PARTY_BUFF_SIZE = 9, 16
ns.PARTY_BUFF_ROW = PARTY_BUFF_SIZE + 3

-- Debuff rows: debuffs I can dispel first, then the rest. The second group
-- excludes the first one's token, so no debuff is shown twice. The token pairs
-- are tried in order (the newer token first).
local PARTY_FILTERS = {
    { "HARMFUL|RAID_PLAYER_DISPELLABLE", "HARMFUL|!RAID_PLAYER_DISPELLABLE" },
    { "HARMFUL|RAID", "HARMFUL|!RAID" },
}

-- Dispel highlight: one engine slot per dispel type. The engine shows the slot
-- while the unit has a debuff of that type I can dispel; Magic draws on top.
local DISPEL_SLOTS = {
    { key = "magic",   token = "Magic",   layer = 7 },
    { key = "curse",   token = "Curse",   layer = 6 },
    { key = "disease", token = "Disease", layer = 5 },
    { key = "poison",  token = "Poison",  layer = 4 },
}

local function partyRowLayout()
    return { elementWidth = PARTY_SIZE, elementHeight = PARTY_SIZE,
        elementSpacing = PARTY_GAP, lineSpacing = PARTY_GAP }
end

local function buildPartyDebuffs(c, f, holder, filters)
    c:SetParent(holder)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    c:SetSize(1, 1)
    if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint("TOPLEFT") end
    if c.SetFlowLayoutGrowthDirection then
        c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    end
    -- one row of four; anything past it wraps below and is clipped by the holder
    if c.SetFlowLayoutMaximumLineSize then
        c:SetFlowLayoutMaximumLineSize(PARTY_ICONS * PARTY_SIZE + (PARTY_ICONS - 1) * PARTY_GAP + 0.4)
    end
    c:AddAuraGroup("mine", filters[1], {
        maxFrameCount = PARTY_ICONS,
        initializeFrame = makeInitializer(f, true),
        layout = partyRowLayout(),
    })
    c:AddAuraGroup("rest", filters[2], {
        maxFrameCount = PARTY_ICONS,
        initializeFrame = makeInitializer(f, true),
        layout = partyRowLayout(),
    })
    c:SetUnit(f.unit)
    pcall(c.UpdateAllAuras, c)
    c:Show()
end

local function buildPartyBuffs(c, f, holder)
    c:SetParent(holder)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    c:SetSize(1, 1)
    if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint("TOPLEFT") end
    if c.SetFlowLayoutGrowthDirection then
        c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    end
    if c.SetFlowLayoutMaximumLineSize then
        c:SetFlowLayoutMaximumLineSize(PARTY_BUFF_ICONS * PARTY_BUFF_SIZE + (PARTY_BUFF_ICONS - 1) * PARTY_GAP + 0.4)
    end
    c:AddAuraGroup("buffs", "HELPFUL", {
        maxFrameCount = PARTY_BUFF_ICONS,
        initializeFrame = makeInitializer(f, false, false, PARTY_BUFF_SIZE),
        layout = { elementWidth = PARTY_BUFF_SIZE, elementHeight = PARTY_BUFF_SIZE,
            elementSpacing = PARTY_GAP, lineSpacing = PARTY_GAP },
    })
    c:SetUnit(f.unit)
    pcall(c.UpdateAllAuras, c)
    c:Show()
end

-- Border strips round the health bar, built while the engine creates the slot
-- (the only moment it accepts our anchors on it).
local function makeDispelSlotInit(f, def)
    local color = DISPEL_COLORS[def.token] or DEFAULT_DEBUFF
    return function(button)
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, false)
        pcall(button.EnableMouse, button, false)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", f.health, "TOPLEFT", -1, 1)
        button:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", 1, -1)
        pcall(button.SetFrameLevel, button, f.health:GetFrameLevel() + 2)
        local edges = {
            { "TOPLEFT", "TOPRIGHT", nil, 2 },
            { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
            { "TOPLEFT", "BOTTOMLEFT", 2, nil },
            { "TOPRIGHT", "BOTTOMRIGHT", 2, nil },
        }
        for _, e in ipairs(edges) do
            local t = button:CreateTexture(nil, "OVERLAY", nil, def.layer)
            t:SetColorTexture(color[1], color[2], color[3], 1)
            t:SetPoint(e[1], button, e[1], 0, 0)
            t:SetPoint(e[2], button, e[2], 0, 0)
            if e[3] then t:SetWidth(e[3]) end
            if e[4] then t:SetHeight(e[4]) end
        end
    end
end

local function buildDispelSlots(c, f, filter)
    c:SetParent(f)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    c:SetSize(1, 1)
    for _, def in ipairs(DISPEL_SLOTS) do
        c:AddAuraSlot(def.key, filter, {
            candidateFilters = { includeDispelTypes = { [def.token] = true } },
            initializeFrame = makeDispelSlotInit(f, def),
        })
    end
    c:SetUnit(f.unit)
    pcall(c.UpdateAllAuras, c)
    c:Show()
end

-- Tries each filter pair on a fresh container (groups can't be removed again).
local function createPartyContainers(f, holder)
    for _, filters in ipairs(PARTY_FILTERS) do
        local c = containerSupported()
        if not c then return nil end
        if pcall(buildPartyDebuffs, c, f, holder, filters) then
            local slots
            if type(c.AddAuraSlot) == "function" then
                -- the slots use the "can dispel" token of the pair that worked
                local d = containerSupported()
                if d and pcall(buildDispelSlots, d, f, filters[1]) then
                    slots = d
                elseif d then
                    pcall(d.Hide, d)
                end
            end
            return c, slots
        end
        pcall(c.Hide, c)
    end
    return nil
end

local function applyPartyContainerConfig(f)
    if ns.InCombat() then return end
    local on = ns.db.partyDebuffs and true or false
    pcall(f.partyDebuffs.SetShown, f.partyDebuffs, on)
    if f.dispelSlots then pcall(f.dispelSlots.SetShown, f.dispelSlots, on) end
    if f.partyBuffs then pcall(f.partyBuffs.SetShown, f.partyBuffs, ns.db.partyBuffs and true or false) end
end

local function updatePartyContainers(f)
    applyPartyContainerConfig(f)
    if f.dispelGlow then f.dispelGlow:Hide() end
    -- same unit token, maybe another member (roster change): re-read
    pcall(f.partyDebuffs.UpdateAllAuras, f.partyDebuffs)
    if f.dispelSlots then pcall(f.dispelSlots.UpdateAllAuras, f.dispelSlots) end
    if f.partyBuffs then pcall(f.partyBuffs.UpdateAllAuras, f.partyBuffs) end
end

function ns.CreatePartyAuras(f)
    f.auraIconSize = PARTY_SIZE
    local clip = CreateFrame("Frame", nil, f)
    clip:SetPoint("LEFT", f, "RIGHT", 4, 0)
    clip:SetSize(PARTY_ICONS * (PARTY_SIZE + PARTY_GAP), PARTY_SIZE)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local okC, debuffs, slots = pcall(createPartyContainers, f, clip)
    if okC and debuffs then
        f.partyDebuffs, f.dispelSlots = debuffs, slots
        f.auras = { icons = {} }
        -- buff row under the frame, clipped to one row
        local buffClip = CreateFrame("Frame", nil, f)
        buffClip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
        buffClip:SetSize(PARTY_BUFF_ICONS * (PARTY_BUFF_SIZE + PARTY_GAP), PARTY_BUFF_SIZE)
        buffClip:SetClipsChildren(true)
        buffClip:EnableMouse(false)
        local b = containerSupported()
        if b then
            if pcall(buildPartyBuffs, b, f, buffClip) then
                f.partyBuffs = b
            else
                pcall(b.Hide, b)
            end
        end
        -- the engine slots draw the highlight now (no highlight if they're missing)
        if f.dispelGlow then f.dispelGlow:Hide() end
        return
    end
    clip:Hide()
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

-- Nameplate debuff row: one engine container per plate widget, built out of
-- combat and bound to a nameplate unit on attach. The row is centred above
-- `anchor`. filters: tried in order (groups can't be removed, so each try uses a
-- fresh container). Returns the container or nil.
local function buildPlateRow(c, w, anchor, filter, count, size, gap)
    c:SetParent(w)
    c:ClearAllPoints()
    c:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    c:SetSize(1, 1)
    if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint("BOTTOMLEFT") end
    if c.SetFlowLayoutGrowthDirection then
        c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
    end
    c:AddAuraGroup("debuffs", filter, {
        maxFrameCount = count,
        initializeFrame = makeInitializer(w, true, true),
        layout = { elementWidth = size, elementHeight = size, elementSpacing = gap, lineSpacing = gap },
    })
    c:SetUnit("none")
    c:Show()
end

function ns.CreatePlateAuraContainer(w, anchor, filters, count, size, gap)
    if ns.InCombat() then return nil end
    w.auraIconSize = size
    for _, filter in ipairs(filters) do
        local c = containerSupported()
        if not c then return nil end
        if pcall(buildPlateRow, c, w, anchor, filter, count, size, gap) then return c end
        pcall(c.Hide, c)
    end
    return nil
end

-- Buttons built before a size change are resized once auras stop being secret.
do
    local retry = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        pcall(retry.RegisterEvent, retry, event)
    end
    retry:SetScript("OnEvent", function()
        if not ns.db then return end
        for _, f in ipairs(containerFrames) do
            pcall(applyContainerConfig, f)
        end
        if ns.frameList then
            for _, f in ipairs(ns.frameList) do
                if f.partyDebuffs then pcall(applyPartyContainerConfig, f) end
            end
        end
    end)
end

function ns.UpdateAuras(f)
    if f.partyDebuffs then
        updatePartyContainers(f)
        return
    end
    if f.auraContainer then
        -- the engine follows UNIT_AURA itself; settings are applied here and a
        -- unit change (new target) is marked for a re-read
        applyContainerConfig(f)
        pcall(f.auraContainer.UpdateAllAuras, f.auraContainer)
        return
    end
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
