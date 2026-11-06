--===========================================================================
-- EzWoW - Unit Frames
-- Modules/HealthEffects.lua : Health bar look (gloss, edge spark, shine sweep,
--                             pulsing combat glow, low-health tint,
--                             hit & heal trails and flashes)
--===========================================================================
-- Everything here lives on our own plain child frames (no mouse, never
-- protected), so it may change in combat. Health values are never read: the
-- spark follows the bar's fill texture and the low-health tint comes from the
-- client's colour curve, so secret values work too.
local _, ns = ...
local type, ipairs, pcall = type, ipairs, pcall
local Plain, IsSecret = ns.Plain, ns.IsSecret

local TEX = "Interface\\Buttons\\WHITE8X8"
local SPARK_TEX = "Interface\\CastingBar\\UI-CastingBar-Spark"
local LOW_TEX = "Interface\\FullScreenTextures\\LowHealth"
local GLOW_SIZE = 5
local GLOW_COLOR = { 1.0, 0.16, 0.10 }
local SWEEP_W = 18
local SWEEP_EVERY, SWEEP_TIME = 6, 1.1
local LOW_HEALTH = 0.35

local function gradient(tex, orientation, r, g, b, a1, a2)
    if type(CreateColor) == "function" and tex.SetGradient then
        if pcall(tex.SetGradient, tex, orientation, CreateColor(r, g, b, a1), CreateColor(r, g, b, a2)) then return true end
    end
    if tex.SetGradientAlpha then
        return pcall(tex.SetGradientAlpha, tex, orientation, r, g, b, a1, r, g, b, a2)
    end
    return false
end

-----------------------------------------------------------------------------
-- Low-health colour curve (0-1 health -> tint). Built once; nil when missing.
-----------------------------------------------------------------------------
local lowCurve
local function lowHealthCurve()
    if lowCurve ~= nil then return lowCurve or nil end
    lowCurve = false
    if not (C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function" and type(CreateColor) == "function") then return nil end
    if type(UnitHealthPercent) ~= "function" then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then return nil end
    local built = pcall(function()
        if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then curve:SetType(Enum.LuaCurveType.Linear) end
        curve:AddPoint(0, CreateColor(1, 1, 1, 0.9))
        curve:AddPoint(LOW_HEALTH, CreateColor(1, 1, 1, 0.35))
        curve:AddPoint(LOW_HEALTH + 0.001, CreateColor(1, 1, 1, 0))
        curve:AddPoint(1, CreateColor(1, 1, 1, 0))
    end)
    if built then lowCurve = curve end
    return lowCurve or nil
end

-----------------------------------------------------------------------------
-- Construction (on first use)
-----------------------------------------------------------------------------
local function buildGlow(f)
    local glow = CreateFrame("Frame", nil, f)
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    glow:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    glow:EnableMouse(false)
    local r, g, b = GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3]
    -- four soft strips, strongest at the frame's edge
    local top = glow:CreateTexture(nil, "BACKGROUND")
    top:SetTexture(TEX)
    top:SetPoint("TOPLEFT", glow, "TOPLEFT", 0, 0)
    top:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", GLOW_SIZE, 0)
    gradient(top, "VERTICAL", r, g, b, 0.8, 0)
    local bottom = glow:CreateTexture(nil, "BACKGROUND")
    bottom:SetTexture(TEX)
    bottom:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -GLOW_SIZE, 0)
    bottom:SetPoint("BOTTOMRIGHT", glow, "BOTTOMRIGHT", 0, 0)
    gradient(bottom, "VERTICAL", r, g, b, 0, 0.8)
    local left = glow:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(TEX)
    left:SetPoint("TOPLEFT", f, "TOPLEFT", -GLOW_SIZE, 0)
    left:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
    gradient(left, "HORIZONTAL", r, g, b, 0, 0.8)
    local right = glow:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(TEX)
    right:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", GLOW_SIZE, 0)
    gradient(right, "HORIZONTAL", r, g, b, 0.8, 0)

    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.35)
    fade:SetToAlpha(0.9)
    fade:SetDuration(0.6)
    if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
    glow.pulse = pulse
    glow:Hide()
    return glow
end

local function buildSweep(fx, health)
    local clip = CreateFrame("Frame", nil, fx)
    clip:SetAllPoints(health)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local sweep = CreateFrame("Frame", nil, clip)
    sweep:SetWidth(SWEEP_W)
    sweep:SetPoint("TOPLEFT", clip, "TOPLEFT", -SWEEP_W * 2, 0)
    sweep:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", -SWEEP_W * 2, 0)
    -- two halves (clear -> light -> clear), tilted round their shared edge
    local halves = {}
    for i = 1, 2 do
        local t = sweep:CreateTexture(nil, "OVERLAY")
        t:SetTexture(TEX)
        t:SetBlendMode("ADD")
        if i == 1 then
            t:SetPoint("TOPLEFT", sweep, "TOPLEFT", 0, 12)
            t:SetPoint("BOTTOMRIGHT", sweep, "BOTTOM", 0, -12)
            gradient(t, "HORIZONTAL", 1, 1, 1, 0, 0.28)
        else
            t:SetPoint("TOPLEFT", sweep, "TOP", 0, 12)
            t:SetPoint("BOTTOMRIGHT", sweep, "BOTTOMRIGHT", 0, -12)
            gradient(t, "HORIZONTAL", 1, 1, 1, 0.28, 0)
        end
        halves[i] = t
    end
    if type(CreateVector2D) == "function" then
        pcall(halves[1].SetRotation, halves[1], -0.4, CreateVector2D(1, 0.5))
        pcall(halves[2].SetRotation, halves[2], -0.4, CreateVector2D(0, 0.5))
    end
    local anim = sweep:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    local move = anim:CreateAnimation("Translation")
    move:SetStartDelay(SWEEP_EVERY - SWEEP_TIME)
    move:SetDuration(SWEEP_TIME)
    if move.SetSmoothing then move:SetSmoothing("IN_OUT") end
    clip.anim, clip.move = anim, move
    return clip
end

local function buildFX(f)
    local health = f.health
    local fill = health:GetStatusBarTexture()
    local fx = CreateFrame("Frame", nil, f)
    fx:SetAllPoints(health)
    fx:SetFrameLevel(health:GetFrameLevel() + 1)
    fx:EnableMouse(false)

    -- gloss on the top half of the filled part
    fx.gloss = fx:CreateTexture(nil, "ARTWORK")
    fx.gloss:SetTexture(TEX)
    fx.gloss:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    fx.gloss:SetPoint("BOTTOMRIGHT", fill, "RIGHT", 0, 0)
    if not gradient(fx.gloss, "VERTICAL", 1, 1, 1, 0, 0.25) then fx.gloss:Hide() fx.noGloss = true end

    -- low-health tint over the whole bar
    fx.low = fx:CreateTexture(nil, "ARTWORK", nil, 1)
    fx.low:SetAllPoints(health)
    if not fx.low:SetTexture(LOW_TEX) then fx.low:SetColorTexture(1, 0.1, 0.1, 1) end
    fx.low:SetBlendMode("ADD")
    fx.low:SetVertexColor(1, 1, 1, 0)

    -- bright line on the fill's edge
    fx.spark = fx:CreateTexture(nil, "OVERLAY")
    fx.spark:SetTexture(SPARK_TEX)
    fx.spark:SetBlendMode("ADD")
    fx.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)

    fx.sweep = buildSweep(fx, health)
    fx.glow = buildGlow(f)
    f.fx = fx
    return fx
end

-----------------------------------------------------------------------------
-- State
-----------------------------------------------------------------------------
local function playerInCombat()
    return ns.InCombat() or (Plain(UnitAffectingCombat, "player") and true or false)
end

local function inCombat(f)
    if f.unit == "player" then return playerInCombat() end
    local ok, value = pcall(UnitAffectingCombat, f.unit)
    if ok and not IsSecret(value) and value ~= nil then return value and true or false end
    return playerInCombat()
end

local function startSweep(fx)
    local clip = fx.sweep
    local width = fx:GetWidth() or 0
    if width <= 0 then return end
    if clip.anim:IsPlaying() and clip.width == width then return end
    clip.anim:Stop()
    clip.width = width
    clip.move:SetOffset(width + SWEEP_W * 3, 0)
    clip.anim:Play()
end

local function stopSweep(fx)
    if fx.sweep.anim:IsPlaying() then fx.sweep.anim:Stop() end
end

local function setGlow(fx, on)
    local glow = fx.glow
    if on then
        if not glow:IsShown() then glow:Show() end
        if not glow.pulse:IsPlaying() then glow.pulse:Play() end
    elseif glow:IsShown() then
        glow.pulse:Stop()
        glow:Hide()
    end
end

local function updateLowHealth(f, fx, alive)
    local curve = alive and not f.preview and lowHealthCurve()
    if not curve then
        fx.low:Hide()
        return
    end
    local ok = pcall(function()
        local color = UnitHealthPercent(f.unit, true, curve)
        fx.low:SetVertexColor(color:GetRGBA())
    end)
    fx.low:SetShown(ok)
end

function ns.UpdateHealthFX(f)
    if not f or not f.health then return end
    local fx = f.fx
    if not ns.db or not ns.db.healthFX then
        if fx then
            stopSweep(fx)
            setGlow(fx, false)
            fx:Hide()
        end
        if f.health.shine and not f.health.shine.ezOff then f.health.shine:Show() end
        return
    end
    fx = fx or buildFX(f)
    fx:Show()
    if f.health.shine then f.health.shine:Hide() end

    local previewing = f.preview and not Plain(UnitExists, f.unit)
    local unit = f.unit
    local alive = previewing or not (Plain(UnitIsDeadOrGhost, unit)
        or (Plain(UnitIsPlayer, unit) and Plain(UnitIsConnected, unit) == false))
    local fighting = (not previewing) and alive and inCombat(f)

    local height = f.health:GetHeight() or 10
    fx.spark:SetSize(10, height * 2)
    fx.spark:SetShown(alive and true or false)
    if fighting then
        fx.spark:SetVertexColor(1, 0.45, 0.30, 0.95)
        if not fx.noGloss then fx.gloss:SetAlpha(0.5) end
        stopSweep(fx)
    else
        fx.spark:SetVertexColor(1, 0.97, 0.85, 0.7)
        if not fx.noGloss then fx.gloss:SetAlpha(1) end
        if alive then startSweep(fx) else stopSweep(fx) end
    end
    setGlow(fx, fighting)
    updateLowHealth(f, fx, alive and not previewing)
end

-----------------------------------------------------------------------------
-- Hit & heal effects
--   loss bar (red)  : under the fill, follows the health a moment later, so a
--                     hit leaves a red piece that then shrinks away
--   gain bar (green): under the fill, jumps to the new health at once while the
--                     fill eases after it, so a heal shows a green lead
--   flash           : red (hit, with a small shake) or green (heal) over the bar
-- Values are only handed to the bars (secret values work); nothing is compared.
-----------------------------------------------------------------------------
local INTERP = Enum and Enum.StatusBarInterpolation
local SMOOTH = INTERP and INTERP.ExponentialEaseOut
local INSTANT = INTERP and INTERP.Immediate
local LOSS_DELAY = 0.4
local LOSS_COLOR = { 0.85, 0.15, 0.15, 0.9 }
local GAIN_COLOR = { 0.25, 0.9, 0.35, 0.9 }
local FLASH_PEAK = 0.55

local function trailsOn()
    return ns.db and ns.db.healthFX and ns.db.hitFX and true or false
end

local function setBar(bar, value, interp)
    if ns.SetBarValue then return ns.SetBarValue(bar, value, interp) end
    return pcall(bar.SetValue, bar, value)
end

local function trailBar(f, level, color)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetAllPoints(f.health)
    bar:SetFrameLevel(level)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture(TEX)
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local function buildFlash(f, level)
    local hit = CreateFrame("Frame", nil, f)
    hit:SetAllPoints(f.health)
    hit:SetFrameLevel(level)
    hit:EnableMouse(false)
    hit:SetAlpha(0)
    hit.tex = hit:CreateTexture(nil, "ARTWORK")
    hit.tex:SetAllPoints(hit)
    hit.tex:SetTexture(TEX)

    local flash = hit:CreateAnimationGroup()
    local up = flash:CreateAnimation("Alpha")
    up:SetFromAlpha(0)
    up:SetToAlpha(FLASH_PEAK)
    up:SetDuration(0.06)
    up:SetOrder(1)
    local down = flash:CreateAnimation("Alpha")
    down:SetFromAlpha(FLASH_PEAK)
    down:SetToAlpha(0)
    down:SetDuration(0.19)
    down:SetOrder(2)
    if down.SetSmoothing then down:SetSmoothing("OUT") end
    hit.flash = flash

    -- a 2px jolt of this overlay only (the unit button itself never moves)
    local shake = hit:CreateAnimationGroup()
    for i, step in ipairs({ { 2, 0.03 }, { -3, 0.05 }, { 1, 0.03 } }) do
        local move = shake:CreateAnimation("Translation")
        move:SetOffset(step[1], 0)
        move:SetDuration(step[2])
        move:SetOrder(i)
    end
    hit.shake = shake
    return hit
end

-- Called while the unit button is built (out of combat), right after the health
-- bar: background holder < loss bar < gain bar < health fill < everything else.
function ns.BuildHealthTrails(f)
    local health = f.health
    if not health or f.trails then return end
    local base = health:GetFrameLevel()

    -- the bar background moves to a holder below the trail bars; f.health.bg
    -- points at the new texture, so colouring code works unchanged
    local under = CreateFrame("Frame", nil, f)
    under:SetAllPoints(health)
    under:SetFrameLevel(base)
    under:EnableMouse(false)
    local bg = under:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(under)
    bg:SetTexture(TEX)
    if health.bg then
        bg:SetVertexColor(health.bg:GetVertexColor())
        health.bg:Hide()
    end
    health.bg = bg

    local t = { under = under, snap = true }
    t.loss = trailBar(f, base + 1, LOSS_COLOR)
    t.gain = trailBar(f, base + 2, GAIN_COLOR)
    health:SetFrameLevel(base + 3)
    t.hit = buildFlash(f, base + 4)
    t.loss:Hide()
    t.gain:Hide()
    f.trails = t
end

-- Decides how the health fill moves for this update: eased, or set at once when
-- the trails must not show a change (new unit, death, offline, preview, first
-- show). nil when the effect is off (plain set, as before).
function ns.HealthBarInterp(f)
    local t = f.trails
    if not t then return nil end
    if not trailsOn() then
        t.off, t.snap = true, true
        return nil
    end
    t.off = false
    local unit = f.unit
    local snap = t.forceSnap or not f:IsVisible()
        or (f.preview and not Plain(UnitExists, unit))
        or Plain(UnitIsDeadOrGhost, unit)
        or (Plain(UnitIsPlayer, unit) and Plain(UnitIsConnected, unit) == false)
    t.forceSnap = nil
    -- the unit behind the token changed without an event (target of target)
    local guid = Plain(UnitGUID, unit)
    if type(guid) == "string" then
        if guid ~= t.guid then snap = true end
        t.guid = guid
    end
    t.snap = snap and true or false
    if t.snap then return INSTANT end
    return SMOOTH
end

local function applyLoss(t)
    t.scheduled = false
    if t.off or not t.hasPending then return end
    local value = t.pending
    t.pending, t.hasPending = nil, false
    setBar(t.loss, value, SMOOTH)
end

-- top/value: the same range and value the health fill just got (may be secret).
function ns.UpdateHealthTrails(f, top, value)
    local t = f.trails
    if not t then return end
    if t.off then
        t.pending, t.hasPending = nil, false
        if t.loss:IsShown() then t.loss:Hide() end
        if t.gain:IsShown() then t.gain:Hide() end
        return
    end
    -- range: only set when it changes (a plain number), always when secret
    local plainTop = not IsSecret(top)
    if not plainTop or t.top ~= top then
        pcall(t.loss.SetMinMaxValues, t.loss, 0, top)
        pcall(t.gain.SetMinMaxValues, t.gain, 0, top)
        t.top = plainTop and top or nil
    end
    if not t.loss:IsShown() then t.loss:Show() end
    if not t.gain:IsShown() then t.gain:Show() end

    if t.snap then
        t.pending, t.hasPending = nil, false
        setBar(t.loss, value, INSTANT)
        setBar(t.gain, value, INSTANT)
        return
    end
    setBar(t.gain, value, INSTANT)
    -- the loss bar follows later; repeated updates keep only the newest value
    t.pending, t.hasPending = value, true
    if t.scheduled then return end
    if C_Timer and type(C_Timer.After) == "function" then
        t.scheduled = true
        C_Timer.After(LOSS_DELAY, function() applyLoss(t) end)
    else
        applyLoss(t)
    end
end

local function playFlash(f, hurt)
    local hit = f.trails.hit
    if hurt then
        hit.tex:SetVertexColor(1, 0.12, 0.08, 1)
    else
        hit.tex:SetVertexColor(0.3, 1, 0.4, 0.7)
    end
    hit.flash:Stop()
    hit.flash:Play()
    if hurt then
        hit.shake:Stop()
        hit.shake:Play()
    end
end

-- UNIT_COMBAT(unit, action, ...): the action may be secret; then no flash.
local combatEvents = CreateFrame("Frame")
pcall(combatEvents.RegisterEvent, combatEvents, "UNIT_COMBAT")
combatEvents:SetScript("OnEvent", function(_, _, unit, action)
    if IsSecret(unit) or type(unit) ~= "string" then return end
    if IsSecret(action) or type(action) ~= "string" then return end
    local hurt
    if action == "WOUND" then
        hurt = true
    elseif action == "HEAL" then
        hurt = false
    else
        return
    end
    if not trailsOn() or not ns.frameList then return end
    for _, f in ipairs(ns.frameList) do
        if f.unit == unit and f.trails and f:IsVisible() and not Plain(UnitIsDeadOrGhost, unit) then
            playFlash(f, hurt)
        end
    end
end)

-- player combat changes the look of every frame
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
    if not ns.frameList then return end
    for _, f in ipairs(ns.frameList) do
        if f:IsShown() then ns.UpdateHealthFX(f) end
    end
end)
