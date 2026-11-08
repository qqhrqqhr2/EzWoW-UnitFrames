--===========================================================================
-- EzWoW - Unit Frames
-- Modules/Frames.lua : Builds every frame, positions, edit mode, events
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall
local Plain, Raw, IsSecret = ns.Plain, ns.Raw, ns.IsSecret

local TEX = "Interface\\Buttons\\WHITE8X8"
local PARTY_GAP = 10

ns.frames = {}      -- key -> unit button (player, target, ..., party1..4)
ns.roots = {}       -- key -> movable root (unit button, or the party holder)
ns.frameList = {}   -- every unit button

-- Default spots, offsets from the screen centre (UI units).
local DEFAULT_POS = {
    player       = { -270, -190 },
    target       = { 270, -190 },
    targettarget = { 480, -168 },
    focus        = { -520, -40 },
    pet          = { -486, -190 },
    party        = { -720, 120 },
}

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

-----------------------------------------------------------------------------
-- Player extras: combo points and druid mana while shapeshifted
-----------------------------------------------------------------------------
local playerClass
do
    local ok, _, classFile = pcall(UnitClass, "player")
    playerClass = ok and classFile or nil
end

local function comboPoints()
    local points = Plain(GetComboPoints, "player", "target")
    if type(points) ~= "number" and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        points = Plain(UnitPower, "player", Enum.PowerType.ComboPoints)
    end
    return type(points) == "number" and points or 0
end

local function buildPlayerExtras(f)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -16)
    holder:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
    holder:SetHeight(18)
    f.extras = holder

    holder.pips = {}
    for i = 1, 5 do
        local pip = holder:CreateTexture(nil, "ARTWORK")
        pip:SetTexture(TEX)
        pip:SetHeight(6)
        holder.pips[i] = pip
    end
    holder.mana = CreateFrame("StatusBar", nil, holder, "BackdropTemplate")
    holder.mana:SetStatusBarTexture(TEX)
    holder.mana:SetStatusBarColor(0.31, 0.45, 0.85)
    holder.mana:SetHeight(5)
    ns.UIKit:ApplyBackdrop(holder.mana, 1, 0)
    holder.mana:SetBackdropColor(rgba(ns.Style.frameBg))
    holder.mana:SetBackdropBorderColor(rgba(ns.Style.border))

    function f:LayoutExtras()
        local width = (f.health:GetWidth() or 200)
        if width < 50 then width = ns.SIZES.big.w - 2 end
        local pipW = (width - 4 * 3) / 5
        for i, pip in ipairs(holder.pips) do
            pip:ClearAllPoints()
            pip:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (pipW + 3), 0)
            pip:SetWidth(pipW)
        end
        holder.mana:ClearAllPoints()
        holder.mana:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -9)
        holder.mana:SetWidth(width)
    end

    function f:UpdateExtras()
        local showPips = ns.db.comboPoints and (playerClass == "ROGUE" or playerClass == "DRUID")
        local points = showPips and comboPoints() or 0
        for i, pip in ipairs(holder.pips) do
            if showPips and (points > 0 or f.preview) then
                local lit = i <= points or (f.preview and points == 0 and i <= 3)
                if lit then
                    pip:SetVertexColor(1, 0.82 - i * 0.08, 0.2, 1)
                else
                    pip:SetVertexColor(0.15, 0.17, 0.2, 0.9)
                end
                pip:Show()
            else
                pip:Hide()
            end
        end
        local showMana = false
        if ns.db.druidMana and playerClass == "DRUID" then
            local pType = Plain(UnitPowerType, "player")
            showMana = type(pType) == "number" and pType ~= 0
        end
        if showMana then
            local mana, maxMana = Raw(UnitPower, "player", 0), Raw(UnitPowerMax, "player", 0)
            pcall(holder.mana.SetMinMaxValues, holder.mana, 0, maxMana or 1)
            pcall(holder.mana.SetValue, holder.mana, mana or 0)
            holder.mana:Show()
        else
            holder.mana:Hide()
        end
    end
    f:LayoutExtras()
end

-----------------------------------------------------------------------------
-- Player power ticks: a spark running across the power bar.
--   energy : every 2 seconds, kept in step with the energy gains
--   mana   : 5 seconds after mana is spent, then the 2-second mana ticks
-- Visual only (plain textures on a plain frame).
-----------------------------------------------------------------------------
local POWER_MANA, POWER_ENERGY = 0, 3
if Enum and Enum.PowerType then
    POWER_MANA = Enum.PowerType.Mana or POWER_MANA
    POWER_ENERGY = Enum.PowerType.Energy or POWER_ENERGY
end
local TICK, FIVE_SECONDS = 2, 5
local CAST_LINK = 0.5   -- a spell cast and a mana drop this close belong together

local function plainNumber(fn, ...)
    local value = Plain(fn, ...)
    return type(value) == "number" and value or nil
end

local function buildPowerTicker(f)
    local ticker = CreateFrame("Frame", nil, f.overlay or f)
    ticker:SetAllPoints(f.power)
    f.ticker = ticker
    local spark = ticker:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:Hide()
    ticker.spark = spark

    local state = {}
    ticker.state = state

    local function powerMode()
        if not ns.db.powerTicks or f.preview or not f.power:IsShown() then return nil end
        local pType = plainNumber(UnitPowerType, "player")
        if pType == POWER_ENERGY then return "energy" end
        if pType == POWER_MANA then return "mana" end
        return nil
    end

    local function powerIndex()
        return state.mode == "energy" and POWER_ENERGY or POWER_MANA
    end

    local function reset()
        state.mode = powerMode()
        state.lastTick, state.fiveStart, state.castAt, state.dropAt = nil, nil, nil, nil
        state.last = state.mode and plainNumber(UnitPower, "player", powerIndex()) or nil
        spark:Hide()
    end
    ticker.Reset = reset

    local function onPower()
        if not state.mode then return end
        local now = GetTime()
        local value = plainNumber(UnitPower, "player", powerIndex())
        if not value then state.last = nil return end
        local last = state.last
        state.last = value
        if not last or value == last then return end
        local diff = value - last
        if state.mode == "energy" then
            -- one regen tick is about 20 energy (more under haste effects); smaller
            -- gains come from abilities and don't move the clock
            if diff >= 15 then state.lastTick = now end
        elseif diff < 0 then
            state.dropAt = now
            if state.castAt and now - state.castAt <= CAST_LINK then
                state.fiveStart, state.lastTick = now, nil
            end
        elseif not state.fiveStart or now - state.fiveStart >= FIVE_SECONDS then
            -- regen outside the five seconds is a mana tick
            state.lastTick = now
        end
    end

    local function onCast()
        if state.mode ~= "mana" then return end
        local now = GetTime()
        state.castAt = now
        if state.dropAt and now - state.dropAt <= CAST_LINK then
            state.fiveStart, state.lastTick = now, nil
        end
    end

    local function place(fraction)
        local width = f.power:GetWidth() or 0
        if width <= 0 then spark:Hide() return end
        local height = f.power:GetHeight() or 10
        spark:SetSize(12, height * 2.2)
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", f.power, "LEFT", width * math.max(0, math.min(1, fraction)), 0)
        spark:Show()
    end

    ticker:SetScript("OnUpdate", function()
        if not state.mode then
            if spark:IsShown() then spark:Hide() end
            return
        end
        local now = GetTime()
        if state.mode == "mana" then
            if state.fiveStart and now - state.fiveStart < FIVE_SECONDS then
                spark:SetVertexColor(1, 0.85, 0.4, 1)
                place((now - state.fiveStart) / FIVE_SECONDS)
                return
            end
            local maxMana = plainNumber(UnitPowerMax, "player", POWER_MANA)
            if not state.lastTick or (maxMana and state.last and state.last >= maxMana) then
                if spark:IsShown() then spark:Hide() end
                return
            end
            spark:SetVertexColor(0.7, 0.85, 1, 1)
        else
            if not state.lastTick then
                if spark:IsShown() then spark:Hide() end
                return
            end
            spark:SetVertexColor(1, 1, 1, 1)
        end
        place(((now - state.lastTick) % TICK) / TICK)
    end)

    local events = CreateFrame("Frame")
    ticker.events = events
    local function register(event, unit)
        if unit and events.RegisterUnitEvent then
            if pcall(events.RegisterUnitEvent, events, event, unit) then return end
        end
        pcall(events.RegisterEvent, events, event)
    end
    register("UNIT_POWER_FREQUENT", "player")
    register("UNIT_SPELLCAST_SUCCEEDED", "player")
    register("UNIT_DISPLAYPOWER", "player")
    register("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event, unit)
        if event ~= "PLAYER_ENTERING_WORLD" and (type(unit) ~= "string" or IsSecret(unit) or unit ~= "player") then return end
        if event == "UNIT_POWER_FREQUENT" then
            if state.mode == nil then
                -- picks up a form/option change the display events missed
                local mode = powerMode()
                if mode then reset() end
            end
            onPower()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            onCast()
        else
            reset()
        end
    end)
    reset()
end

-- option or edit-mode change
function ns.UpdatePowerTicker()
    local f = ns.frames.player
    if f and f.ticker then f.ticker.Reset() end
end

-----------------------------------------------------------------------------
-- Positions
-----------------------------------------------------------------------------
local function applyPosition(key)
    local root = ns.roots[key]
    if not root then return end
    local pos = ns.db.positions[key] or DEFAULT_POS[key]
    local scale = root:GetScale() or 1
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", pos[1] / scale, pos[2] / scale)
end

local function savePosition(key)
    local root = ns.roots[key]
    local cx, cy = root:GetCenter()
    if not cx then return end
    local scale = root:GetScale() or 1
    local ux, uy = UIParent:GetCenter()
    ns.db.positions[key] = { math.floor(cx * scale - ux + 0.5), math.floor(cy * scale - uy + 0.5) }
    applyPosition(key)
end

local function layoutParty()
    local holder = ns.roots.party
    if not holder then return end
    local size = ns.SIZES.party
    local height = ns.FrameHeight(size)
    -- room for the buff row under each member
    local buffRow = (ns.db.partyBuffs and ns.PartyBuffRow and ns.PartyBuffRow()) or 0
    if ns.db.partyHorizontal then
        -- side by side; the debuffs sit above each frame (see Auras), buffs below
        local step = size.w + PARTY_GAP
        for i = 1, 4 do
            local f = ns.frames["party" .. i]
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * step, 0)
        end
        holder:SetSize(4 * size.w + 3 * PARTY_GAP, height + buffRow)
    else
        -- room for the buff row under each member
        local gap = PARTY_GAP + buffRow
        for i = 1, 4 do
            local f = ns.frames["party" .. i]
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * (height + gap))
        end
        holder:SetSize(size.w, 4 * height + 3 * gap)
    end
    for i = 1, 4 do
        if ns.PlacePartyDebuffs then ns.PlacePartyDebuffs(ns.frames["party" .. i]) end
    end
end

-- overall scale times the frame's own size (Ctrl + wheel)
local FRAME_SCALE_MIN, FRAME_SCALE_MAX = 0.5, 2.0
local function frameScale(key)
    local own = tonumber(ns.db.frameScales and ns.db.frameScales[key]) or 1
    return math.max(FRAME_SCALE_MIN, math.min(FRAME_SCALE_MAX, own))
end

-- Size, scale and position of everything. Protected: runs after combat if needed.
function ns.ApplyLayout()
    ns.RunAfterCombat("layout", function()
        for _, f in ipairs(ns.frameList) do ns.LayoutUnitButton(f) end
        if ns.frames.player and ns.frames.player.LayoutExtras then ns.frames.player:LayoutExtras() end
        layoutParty()
        for key, root in pairs(ns.roots) do
            root:SetScale(ns.db.scale * frameScale(key))
            applyPosition(key)
        end
        ns.RefreshAll()
    end)
end

function ns.ResetPositions()
    ns.RunAfterCombat("reset", function()
        wipe(ns.db.positions)
        if ns.db.frameScales then wipe(ns.db.frameScales) end
        for key, root in pairs(ns.roots) do
            root:SetScale(ns.db.scale * frameScale(key))
            applyPosition(key)
        end
    end)
end

-----------------------------------------------------------------------------
-- Visibility (unit watch) & edit mode
-----------------------------------------------------------------------------
local PARTY_VISIBILITY_RAID = "[group:raid] hide; show"

local function setWatched(f, enabled)
    if UnregisterUnitWatch then UnregisterUnitWatch(f) end
    if enabled then
        if f.preview then
            f:Show()
        elseif RegisterUnitWatch then
            RegisterUnitWatch(f)
        else
            f:SetShown(Plain(UnitExists, f.unit) and true or false)
        end
    else
        f:Hide()
    end
end

-- Applies enabled flags, raid visibility and preview. Protected: out of combat.
function ns.ApplyVisibility()
    ns.RunAfterCombat("visibility", function()
        local db = ns.db
        local editing = not db.locked
        for _, f in ipairs(ns.frameList) do
            local group = f.sizeKey == "party" and "party" or f.key
            f.preview = editing and db.enabled[group] or false
            setWatched(f, db.enabled[group])
        end
        local holder = ns.roots.party
        if holder then
            if UnregisterStateDriver then UnregisterStateDriver(holder, "visibility") end
            if not db.enabled.party then
                holder:Hide()
            elseif editing or db.partyInRaid then
                holder:Show()
            elseif RegisterStateDriver then
                RegisterStateDriver(holder, "visibility", PARTY_VISIBILITY_RAID)
            else
                holder:Show()
            end
        end
        for key, root in pairs(ns.roots) do
            if root.mover then
                root.mover:SetShown(editing and db.enabled[key] and true or false)
            end
        end
        ns.UpdatePowerTicker()
        ns.RefreshAll()
    end)
end

local function createMover(key, root)
    local mover = CreateFrame("Frame", nil, root, "BackdropTemplate")
    mover:SetAllPoints(root)
    mover:SetFrameLevel(root:GetFrameLevel() + 20)
    ns.UIKit:ApplyBackdrop(mover, 2, 0)
    local a = ns.Style.accent
    mover:SetBackdropColor(a[1], a[2], a[3], 0.18)
    mover:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover.label:SetPoint("CENTER")
    mover.label:SetTextColor(1, 1, 1)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        if ns.InCombat() then return end
        root:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        if not ns.InCombat() then savePosition(key) end
    end)
    mover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns:L(key), a[1], a[2], a[3])
        GameTooltip:AddLine(ns:L("moverTip"), 0.85, 0.9, 0.94, true)
        GameTooltip:AddDoubleLine(" ", "EzWoW - Unit Frames", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
    end)
    mover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mover:Hide()
    root.mover = mover
end

-----------------------------------------------------------------------------
-- Quick edit while locked: Ctrl + drag moves a frame, Ctrl + wheel resizes it.
-- The wheel is only taken while Ctrl is held over a frame, so the camera zoom
-- keeps working over the frames otherwise. Out of combat only.
-----------------------------------------------------------------------------
local quick = { hovered = nil, wheelOn = nil, moving = nil }
local quickEvents = CreateFrame("Frame")

local function rootKeyOf(f)
    return (f.sizeKey == "party") and "party" or f.key
end

-- Ctrl + wheel resizes a frame only when the player hasn't bound Ctrl + wheel to
-- anything (healers often bind spells there; the frame would swallow the wheel).
local function ctrlWheelBound()
    if type(GetBindingAction) ~= "function" then return false end
    for _, key in ipairs({ "CTRL-MOUSEWHEELUP", "CTRL-MOUSEWHEELDOWN" }) do
        local ok, action = pcall(GetBindingAction, key)
        if ok and type(action) == "string" and action ~= "" then return true end
    end
    return false
end

local function setWheel(f, on)
    if not f or ns.InCombat() then return end
    on = on and not ctrlWheelBound() and true or false
    if quick.wheelOn == f and on then return end
    pcall(f.EnableMouseWheel, f, on)
    quick.wheelOn = on and f or nil
end

local function showSizeTip(f, key)
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    GameTooltip:SetText(ns:L("frameSize"):format(math.floor(frameScale(key) * 100 + 0.5)), 1, 1, 1)
    GameTooltip:AddDoubleLine(" ", "EzWoW - Unit Frames", 0, 0, 0, 0.5, 0.5, 0.5)
    GameTooltip:Show()
    if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
end

local function attachQuickEdit(f)
    local key = rootKeyOf(f)
    f:RegisterForDrag("LeftButton")
    f:HookScript("OnDragStart", function()
        if ns.InCombat() or not IsControlKeyDown() then return end
        local root = ns.roots[key]
        if not root then return end
        root:StartMoving()
        quick.moving = key
    end)
    f:HookScript("OnDragStop", function()
        if quick.moving ~= key then return end
        quick.moving = nil
        local root = ns.roots[key]
        if not root then return end
        root:StopMovingOrSizing()
        if not ns.InCombat() then savePosition(key) end
    end)
    f:HookScript("OnEnter", function(self)
        quick.hovered = self
        setWheel(self, IsControlKeyDown())
    end)
    f:HookScript("OnLeave", function(self)
        if quick.hovered == self then quick.hovered = nil end
        setWheel(self, false)
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
        if ns.InCombat() or not IsControlKeyDown() then return end
        local root = ns.roots[key]
        if not root then return end
        local value = math.floor((frameScale(key) + (delta > 0 and 0.05 or -0.05)) * 100 + 0.5) / 100
        ns.db.frameScales[key] = math.max(FRAME_SCALE_MIN, math.min(FRAME_SCALE_MAX, value))
        if math.abs(ns.db.frameScales[key] - 1) < 0.001 then ns.db.frameScales[key] = nil end
        root:SetScale(ns.db.scale * frameScale(key))
        applyPosition(key)
        showSizeTip(self, key)
    end)
end

pcall(quickEvents.RegisterEvent, quickEvents, "MODIFIER_STATE_CHANGED")
pcall(quickEvents.RegisterEvent, quickEvents, "PLAYER_REGEN_DISABLED")
quickEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- still allowed at this point; frames must not keep the wheel in combat
        if quick.wheelOn then
            pcall(quick.wheelOn.EnableMouseWheel, quick.wheelOn, false)
            quick.wheelOn = nil
        end
        if quick.moving and ns.roots[quick.moving] then
            ns.roots[quick.moving]:StopMovingOrSizing()
            savePosition(quick.moving)
            quick.moving = nil
        end
        return
    end
    if quick.hovered then setWheel(quick.hovered, IsControlKeyDown()) end
end)

function ns.SetLocked(locked)
    if ns.InCombat() then
        ns.Print(ns:L("combatLater"))
    end
    ns.db.locked = locked and true or false
    ns.ApplyVisibility()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-----------------------------------------------------------------------------
-- Hiding the default frames
-----------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

-- keepEvents: only move the frame out of sight (the raid-style party frame shares
-- its code with the raid frames, so its events are left alone)
local function hideDefault(frame, keepEvents)
    if type(frame) ~= "table" then return end
    if not keepEvents then pcall(frame.UnregisterAllEvents, frame) end
    pcall(frame.Hide, frame)
    pcall(frame.SetParent, frame, hiddenParent)
end

-- The raid-style party frame (interface option) may be created later on.
local function hideCompactParty()
    local db = ns.db
    if not (db and db.hideBlizzard and db.enabled.party) then return end
    if type(_G.CompactPartyFrame) ~= "table" then return end
    ns.RunAfterCombat("blizzardCompactParty", function()
        hideDefault(_G.CompactPartyFrame, true)
    end)
end

local compactHooked = false
local function hookCompactParty()
    if compactHooked then return end
    if type(_G.CompactPartyFrame_Generate) == "function" then
        compactHooked = true
        hooksecurefunc("CompactPartyFrame_Generate", hideCompactParty)
    end
end

function ns.HideBlizzardFrames()
    local db = ns.db
    if not db.hideBlizzard then return end
    ns.RunAfterCombat("blizzard", function()
        if db.enabled.player then hideDefault(_G.PlayerFrame) end
        if db.enabled.target then
            hideDefault(_G.TargetFrame)
            hideDefault(_G.TargetFrameToT)
        end
        if db.enabled.focus then hideDefault(_G.FocusFrame) end
        if db.enabled.pet then hideDefault(_G.PetFrame) end
        if db.enabled.party then
            hideDefault(_G.PartyFrame)
            for i = 1, 4 do hideDefault(_G["PartyMemberFrame" .. i]) end
        end
    end)
    hookCompactParty()
    hideCompactParty()
end

-----------------------------------------------------------------------------
-- Building
-----------------------------------------------------------------------------
local function register(f)
    ns.frames[f.key] = f
    ns.frameList[#ns.frameList + 1] = f
end

function ns.BuildAllFrames()
    if ns.built then return end
    if ns.InCombat() then
        ns.RunAfterCombat("build", ns.BuildAllFrames)
        return
    end
    ns.built = true

    local player = ns.CreateUnitButton("player", "player", "big", { portraitSide = "LEFT" })
    buildPlayerExtras(player)
    buildPowerTicker(player)
    ns.CreateTargetAuras(player, 26)
    register(player)

    local target = ns.CreateUnitButton("target", "target", "big", { portraitSide = "RIGHT" })
    ns.CreateCastbar(target, true)
    ns.CreateTargetAuras(target)
    register(target)

    register(ns.CreateUnitButton("targettarget", "targettarget", "small", {}))

    local focus = ns.CreateUnitButton("focus", "focus", "focus", {})
    -- like the target: cast bar above, buffs and debuffs below
    ns.CreateCastbar(focus, true)
    ns.CreateTargetAuras(focus)
    register(focus)

    register(ns.CreateUnitButton("pet", "pet", "pet", {}))

    local holder = CreateFrame("Frame", "EzWoWUF_PartyHolder", UIParent, "SecureHandlerStateTemplate")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    for i = 1, 4 do
        local f = ns.CreateUnitButton("party" .. i, "party" .. i, "party", { label = "party" }, holder)
        ns.CreatePartyAuras(f)
        register(f)
    end

    for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet" }) do
        ns.roots[key] = ns.frames[key]
    end
    ns.roots.party = holder
    for _, f in ipairs(ns.frameList) do attachQuickEdit(f) end
    for key, root in pairs(ns.roots) do createMover(key, root) end

    ns.ApplyLayout()
    ns.ApplyVisibility()
    ns.HideBlizzardFrames()
    ns.StartEvents()
end

-----------------------------------------------------------------------------
-- Refresh helpers
-----------------------------------------------------------------------------
function ns.RefreshAll()
    for _, f in ipairs(ns.frameList) do
        if f:IsShown() then ns.UpdateFrame(f) end
    end
    if ns.roots then
        for key, root in pairs(ns.roots) do
            if root.mover then root.mover.label:SetText(ns:L(key)) end
        end
    end
end

local function forUnit(unit, fn, ...)
    for _, f in ipairs(ns.frameList) do
        if f.unit == unit and f:IsShown() then fn(f, ...) end
    end
end

-----------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------
local UNIT_EVENTS = {
    UNIT_HEALTH = function(f) ns.UpdateHealth(f) end,
    UNIT_MAXHEALTH = function(f) ns.UpdateHealth(f) end,
    UNIT_HEAL_PREDICTION = function(f) ns.UpdateHealPrediction(f) end,
    UNIT_CONNECTION = function(f) ns.UpdateHealthColor(f) ns.UpdateHealth(f) end,
    UNIT_FLAGS = function(f) ns.UpdateHealthColor(f) ns.UpdateHealth(f) end,
    UNIT_POWER_UPDATE = function(f) ns.UpdatePower(f) if f.UpdateExtras then f:UpdateExtras() end end,
    UNIT_POWER_FREQUENT = function(f) ns.UpdatePower(f) if f.UpdateExtras then f:UpdateExtras() end end,
    UNIT_MAXPOWER = function(f) ns.UpdatePower(f) end,
    UNIT_DISPLAYPOWER = function(f) ns.UpdatePower(f) if f.UpdateExtras then f:UpdateExtras() end end,
    UNIT_NAME_UPDATE = function(f) ns.UpdateInfo(f) ns.UpdateHealthColor(f) end,
    UNIT_LEVEL = function(f) ns.UpdateInfo(f) end,
    UNIT_FACTION = function(f) ns.UpdateHealthColor(f) end,
    UNIT_CLASSIFICATION_CHANGED = function(f) ns.UpdateInfo(f) end,
    -- party aura containers follow UNIT_AURA themselves
    UNIT_AURA = function(f) if not f.partyDebuffs then ns.UpdateAuras(f) end end,
    UNIT_IN_RANGE_UPDATE = function(f) ns.UpdateRange(f) end,
    UNIT_PORTRAIT_UPDATE = function(f) ns.UpdatePortrait(f) end,
    UNIT_MODEL_CHANGED = function(f) ns.UpdatePortrait(f) end,
    UNIT_SPELLCAST_START = function(f) ns.UpdateCastbar(f, true) end,
    UNIT_SPELLCAST_CHANNEL_START = function(f) ns.UpdateCastbar(f, true) end,
    UNIT_SPELLCAST_DELAYED = function(f) ns.UpdateCastbar(f) end,
    UNIT_SPELLCAST_CHANNEL_UPDATE = function(f) ns.UpdateCastbar(f) end,
    UNIT_SPELLCAST_INTERRUPTIBLE = function(f) ns.UpdateCastbar(f) end,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(f) ns.UpdateCastbar(f) end,
    UNIT_SPELLCAST_STOP = function(f) ns.CastbarStopped(f, false) end,
    UNIT_SPELLCAST_CHANNEL_STOP = function(f) ns.CastbarStopped(f, false) end,
    UNIT_SPELLCAST_FAILED = function(f) ns.CastbarStopped(f, false) end,
    UNIT_SPELLCAST_INTERRUPTED = function(f) ns.CastbarStopped(f, true) end,
}

local function updateKey(key)
    local f = ns.frames[key]
    if f and f:IsShown() then ns.UpdateFrame(f) end
end

local function updateAllParty()
    for i = 1, 4 do updateKey("party" .. i) end
end

local function updateIconsAll()
    for _, f in ipairs(ns.frameList) do
        if f:IsShown() then ns.UpdateIcons(f) end
    end
end

local function updateThreatAll()
    for _, f in ipairs(ns.frameList) do
        if f:IsShown() then ns.UpdateThreat(f) end
    end
end

local OTHER_EVENTS = {
    PLAYER_ENTERING_WORLD = function() ns.RefreshAll() end,
    PLAYER_TARGET_CHANGED = function()
        updateKey("target")
        updateKey("targettarget")
        local player = ns.frames.player
        if player and player.UpdateExtras then player:UpdateExtras() end
    end,
    PLAYER_FOCUS_CHANGED = function() updateKey("focus") end,
    UNIT_TARGET = function(unit) if unit == "target" then updateKey("targettarget") end end,
    UNIT_PET = function(unit) if unit == "player" then updateKey("pet") end end,
    GROUP_ROSTER_UPDATE = function() updateAllParty() updateIconsAll() end,
    PARTY_LEADER_CHANGED = updateIconsAll,
    PLAYER_ROLES_ASSIGNED = updateIconsAll,
    RAID_TARGET_UPDATE = updateIconsAll,
    PLAYER_UPDATE_RESTING = updateIconsAll,
    PLAYER_REGEN_DISABLED = function()
        updateIconsAll()
        if not ns.db.locked then
            -- leaving edit mode before the frames get locked down
            ns.db.locked = true
            ns.ApplyVisibility()
            if ns.RefreshOptions then ns.RefreshOptions() end
        end
    end,
    PLAYER_REGEN_ENABLED = updateIconsAll,
    UNIT_THREAT_SITUATION_UPDATE = updateThreatAll,
    UNIT_THREAT_LIST_UPDATE = updateThreatAll,
}

function ns.StartEvents()
    local frame = CreateFrame("Frame")
    for event in pairs(UNIT_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    for event in pairs(OTHER_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(_, event, unit, ...)
        local handler = UNIT_EVENTS[event]
        if handler then
            if type(unit) == "string" and not IsSecret(unit) then forUnit(unit, handler) end
            return
        end
        handler = OTHER_EVENTS[event]
        if handler then handler(unit, ...) end
    end)

    -- target of target has no events of its own; party range changes silently
    local elapsedToT, elapsedRange = 0, 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedToT = elapsedToT + elapsed
        elapsedRange = elapsedRange + elapsed
        if elapsedToT >= 0.25 then
            elapsedToT = 0
            local tot = ns.frames.targettarget
            if tot and tot:IsShown() then
                ns.UpdateInfo(tot)
                ns.UpdateHealthColor(tot)
                ns.UpdateHealth(tot)
            end
        end
        if elapsedRange >= 0.5 then
            elapsedRange = 0
            for i = 1, 4 do
                local f = ns.frames["party" .. i]
                if f and f:IsShown() then ns.UpdateRange(f) end
            end
        end
    end)
end
