--===========================================================================
-- EzWoW - Unit Frames
-- Modules/Castbar.lua : Cast bar for target / focus (shows uninterruptible casts
--                       and warns about casts that can be interrupted)
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local Plain, Raw, IsSecret = ns.Plain, ns.Raw, ns.IsSecret

local TEX = "Interface\\Buttons\\WHITE8X8"
local HEIGHT = 16

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

-----------------------------------------------------------------------------
-- Interrupt warning
-- A pulsing rim around the bar (it also makes the bar look taller) and a short
-- "Kick!" label. Its visibility comes from the cast's "not interruptible" flag;
-- when the flag is secret the client applies it (SetAlphaFromBoolean), nothing
-- is compared here. The rim is tinted by my interrupt's cooldown when that can
-- be read: plain numbers, or a secret "active" flag folded into a colour.
-----------------------------------------------------------------------------
local KICK_EDGE = 2
local KICK_SOUND_GAP = 1.5
local KICK_SOUND = (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3) or 12889
local warnBars = {}          -- every cast bar with a warning (for cooldown re-tints)

-- my interrupt spells, preferred first (every rank: any known rank will do;
-- { id, true } = a pet spell)
local KICK_SPELLS = {
    WARRIOR = { { 6554 }, { 6552 }, { 1672 }, { 1671 }, { 72 } },                -- Pummel, Shield Bash
    ROGUE = { { 1769 }, { 1768 }, { 1767 }, { 1766 } },                          -- Kick
    SHAMAN = { { 10414 }, { 10413 }, { 10412 }, { 8046 }, { 8045 }, { 8044 }, { 8042 } }, -- Earth Shock
    MAGE = { { 2139 } },                                                         -- Counterspell
    WARLOCK = { { 19647, true }, { 19244, true } },                              -- Spell Lock (Felhunter)
}

local kickSpell, kickDirty = nil, true

local function spellKnown(id, pet)
    local book = C_SpellBook
    local banks = Enum and Enum.SpellBookSpellBank
    local bank = banks and (pet and banks.Pet or banks.Player)
    if book and bank ~= nil then
        if type(book.IsSpellInSpellBook) == "function" and Plain(book.IsSpellInSpellBook, id, bank) == true then return true end
        if type(book.IsSpellKnown) == "function" and Plain(book.IsSpellKnown, id, bank) == true then return true end
    end
    if pet then return Plain(IsSpellKnown, id, true) == true end
    return Plain(IsPlayerSpell, id) == true or Plain(IsSpellKnown, id) == true
end

local function myKickSpell()
    if kickDirty then
        kickDirty = false
        kickSpell = nil
        local ok, _, classFile = pcall(UnitClass, "player")
        local list = ok and not IsSecret(classFile) and KICK_SPELLS[classFile]
        if list then
            for _, entry in ipairs(list) do
                if spellKnown(entry[1], entry[2]) then
                    kickSpell = entry[1]
                    break
                end
            end
        end
    end
    return kickSpell
end

-- "plain", ready, secondsLeft  |  "secret", activeFlag (secret boolean)  |  nil
local function kickState()
    local id = myKickSpell()
    if not id or not (C_Spell and type(C_Spell.GetSpellCooldown) == "function") then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(info) ~= "table" or IsSecret(info) then return nil end
    local start, duration = info.startTime, info.duration
    if not IsSecret(start) and not IsSecret(duration) and type(start) == "number" and type(duration) == "number" then
        local gcd = info.isOnGCD
        if duration <= 1.5 or (not IsSecret(gcd) and gcd == true) then return "plain", true, 0 end
        local left = start + duration - GetTime()
        return "plain", left <= 0, left
    end
    local active = info.isActive
    if IsSecret(active) then return "secret", active end
    if type(active) == "boolean" then return "plain", not active, 0 end
    return nil
end

local function paintKick(cb, r, g, b)
    local k = cb.kick
    for _, tex in ipairs(k.inner) do tex:SetVertexColor(r, g, b, 1) end
    for _, tex in ipairs(k.outer) do tex:SetVertexColor(r, g, b, 0.35) end
    k.label:SetTextColor(r, g, b)
end

local retintPending = false
local function tintKick(cb)
    local ready, cooldown = ns.Style.kickReady, ns.Style.kickCooldown
    local kind, value, left = kickState()
    if kind == "secret" then
        -- the client picks the colour from the secret flag (true = on cooldown)
        local fold = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
        if type(fold) == "function" and pcall(function()
            paintKick(cb, fold(value, cooldown[1], ready[1]), fold(value, cooldown[2], ready[2]),
                fold(value, cooldown[3], ready[3]))
        end) then return end
        kind = nil
    end
    local c = (kind == "plain" and not value) and cooldown or ready
    paintKick(cb, c[1], c[2], c[3])
    -- plain cooldown: tint back when it runs out (no event may come then)
    if kind == "plain" and not value and type(left) == "number" and left > 0 and not retintPending then
        retintPending = true
        C_Timer.After(left + 0.05, function()
            retintPending = false
            for bar in pairs(warnBars) do
                if bar.kickOn and bar:IsShown() then tintKick(bar) end
            end
        end)
    end
end

local function hideKick(cb)
    local k = cb.kick
    if not k then return end
    cb.kickOn = false
    k.host:SetAlpha(0)
    k.anim:Stop()
end

local lastKickSound = 0
local function playKickSound()
    local now = GetTime()
    if now - lastKickSound < KICK_SOUND_GAP then return end
    lastKickSound = now
    if type(PlaySound) == "function" then pcall(PlaySound, KICK_SOUND, "Master") end
end

local function kickWanted(f)
    local db = ns.db
    if not db.kickWarn then return false end
    local unit = f.unit
    if not Plain(UnitCanAttack, "player", unit) then return false end
    -- casts out of combat (before a pull) don't warn; unknown counts as in combat
    if Plain(UnitAffectingCombat, unit) == false then return false end
    if f.isPlate and db.kickTargetOnly then
        return (Plain(UnitIsUnit, unit, "target") or Plain(UnitIsUnit, unit, "focus")) and true or false
    end
    return true
end

local function updateKick(f, cb, notInterruptible, isStart)
    local k = cb.kick
    if not k then return end
    if not kickWanted(f) then return hideKick(cb) end
    local known = false
    if IsSecret(notInterruptible) then
        -- shown when the flag is false, hidden when true: decided by the client
        if not (k.host.SetAlphaFromBoolean and pcall(k.host.SetAlphaFromBoolean, k.host, notInterruptible, 0, 1)) then
            return hideKick(cb)
        end
    elseif notInterruptible == true then
        return hideKick(cb)
    else
        k.host:SetAlpha(1)
        known = true
    end
    cb.kickOn = true
    k.label:SetText(ns:L("kickLabel"))   -- follows a language change
    tintKick(cb)
    if not k.anim:IsPlaying() then k.anim:Play() end
    -- the sound needs a plain answer: a secret flag can't decide anything here
    if isStart and known and ns.db.kickSound then playKickSound() end
end

local function createKickWarning(cb, height)
    local k = {}
    k.host = CreateFrame("Frame", nil, cb)
    k.host:SetAllPoints(cb)
    k.host:EnableMouse(false)
    k.host:SetAlpha(0)
    k.pulse = CreateFrame("Frame", nil, k.host)
    k.pulse:SetAllPoints(cb)
    k.pulse:EnableMouse(false)

    -- four strips around the bar (never over it), from gap to gap + size outside
    local function ring(gap, size, list)
        local function strip()
            local t = k.pulse:CreateTexture(nil, "OVERLAY")
            t:SetTexture(TEX)
            list[#list + 1] = t
            return t
        end
        local o = gap + size
        local top = strip()
        top:SetPoint("BOTTOMLEFT", cb, "TOPLEFT", -o, gap)
        top:SetPoint("BOTTOMRIGHT", cb, "TOPRIGHT", o, gap)
        top:SetHeight(size)
        local bottom = strip()
        bottom:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", -o, -gap)
        bottom:SetPoint("TOPRIGHT", cb, "BOTTOMRIGHT", o, -gap)
        bottom:SetHeight(size)
        local left = strip()
        left:SetPoint("TOPRIGHT", cb, "TOPLEFT", -gap, gap)
        left:SetPoint("BOTTOMRIGHT", cb, "BOTTOMLEFT", -gap, -gap)
        left:SetWidth(size)
        local right = strip()
        right:SetPoint("TOPLEFT", cb, "TOPRIGHT", gap, gap)
        right:SetPoint("BOTTOMLEFT", cb, "BOTTOMRIGHT", gap, -gap)
        right:SetWidth(size)
    end
    k.inner, k.outer = {}, {}
    ring(0, KICK_EDGE, k.inner)
    ring(KICK_EDGE, KICK_EDGE, k.outer)

    k.label = k.host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local path = k.label:GetFont()
    if path then k.label:SetFont(path, height < 14 and 9 or 11, "OUTLINE") end
    k.label:SetShadowOffset(0, 0)
    k.label:SetPoint("LEFT", cb, "RIGHT", KICK_EDGE * 2 + 3, 0)
    k.label:SetText(ns:L("kickLabel"))

    k.anim = k.pulse:CreateAnimationGroup()
    k.anim:SetLooping("BOUNCE")
    local fade = k.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.35)

    cb.kick = k
    warnBars[cb] = true
end

local kickEvents = CreateFrame("Frame")
kickEvents:RegisterEvent("PLAYER_LOGIN")
kickEvents:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        for _, name in ipairs({ "SPELLS_CHANGED", "UNIT_PET", "LEARNED_SPELL_IN_TAB", "SPELL_UPDATE_COOLDOWN" }) do
            pcall(self.RegisterEvent, self, name)
        end
        kickDirty = true
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        for bar in pairs(warnBars) do
            if bar.kickOn and bar:IsShown() then tintKick(bar) end
        end
        return
    end
    if event == "UNIT_PET" and unit ~= "player" then return end
    kickDirty = true
end)

-- Drops whatever is driving the bar (a client duration timer or our own OnUpdate),
-- so a reused bar never keeps animating the previous cast.
local function clearTimer(cb)
    if cb.ClearTimerDuration then pcall(cb.ClearTimerDuration, cb) end
    cb.startTime, cb.endTime, cb.channel = nil, nil, nil
    cb:SetScript("OnUpdate", nil)
    cb:SetMinMaxValues(0, 1)
    cb:SetValue(0)
end

local function onUpdate(cb)
    if not cb.startTime then return end
    local now = GetTime()
    if now >= cb.endTime then
        cb:Hide()
        return
    end
    local total = cb.endTime - cb.startTime
    local value = cb.channel and (cb.endTime - now) or (now - cb.startTime)
    cb:SetValue(value)
    cb.time:SetFormattedText("%.1f", cb.endTime - now)
    if total <= 0 then cb:Hide() end
end

-- above = place the bar above the frame (target: auras use the space below)
-- height = bar height (nameplates use a thin one)
function ns.CreateCastbar(f, above, height)
    local HEIGHT = height or HEIGHT
    local cb = CreateFrame("StatusBar", nil, f, "BackdropTemplate")
    cb:SetStatusBarTexture(TEX)
    cb:SetHeight(HEIGHT)
    if above then
        cb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", HEIGHT + 2, 4)
        cb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 4)
    else
        cb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", HEIGHT + 2, -4)
        cb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
    end
    ns.UIKit:ApplyBackdrop(cb, 1, 0)
    cb:SetBackdropColor(rgba(ns.Style.frameBg))
    cb:SetBackdropBorderColor(rgba(ns.Style.border))

    cb.iconFrame = CreateFrame("Frame", nil, cb, "BackdropTemplate")
    cb.iconFrame:SetSize(HEIGHT, HEIGHT)
    cb.iconFrame:SetPoint("RIGHT", cb, "LEFT", -2, 0)
    ns.UIKit:ApplyBackdrop(cb.iconFrame, 1, 0)
    cb.iconFrame:SetBackdropBorderColor(rgba(ns.Style.border))
    cb.icon = cb.iconFrame:CreateTexture(nil, "ARTWORK")
    cb.icon:SetPoint("TOPLEFT", 1, -1)
    cb.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if HEIGHT < 14 then
        local path, size = cb.text:GetFont()
        if path then cb.text:SetFont(path, math.max(8, (size or 10) - 2), "OUTLINE") end
    end
    cb.text:SetPoint("LEFT", 4, 0)
    cb.text:SetPoint("RIGHT", -36, 0)
    cb.text:SetJustifyH("LEFT")
    cb.text:SetWordWrap(false)
    cb.time = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.time:SetPoint("RIGHT", -4, 0)
    if HEIGHT < 14 then cb.time:Hide() cb.time.SetFormattedText = function() end end

    -- The shield sits on its own frame: a secret "not interruptible" flag can only
    -- be applied through SetAlphaFromBoolean, which works on frames (on a texture
    -- it draws nothing).
    cb.shieldHost = CreateFrame("Frame", nil, cb)
    cb.shieldHost:SetAllPoints(cb.iconFrame)
    cb.shieldHost:SetFrameLevel(cb.iconFrame:GetFrameLevel() + 1)
    cb.shieldHost:EnableMouse(false)
    cb.shieldHost:SetAlpha(0)
    cb.shield = cb.shieldHost:CreateTexture(nil, "OVERLAY")
    cb.shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
    cb.shield:SetSize(HEIGHT * 2, HEIGHT * 2)
    cb.shield:SetPoint("CENTER", cb.iconFrame, "CENTER", 0, -1)

    createKickWarning(cb, HEIGHT)

    cb:SetScript("OnHide", function(self)
        clearTimer(self)
        self.holdUntil = nil
        hideKick(self)
    end)
    cb:Hide()
    f.castbar = cb
end

local function castbarEnabled(f)
    if f.isPlate then return ns.db.plateCastbar end
    if f.unit == "target" then return ns.db.targetCastbar end
    if f.unit == "focus" then return ns.db.focusCastbar end
    return false
end

local function readCast(unit)
    local name, _, texture, startMS, endMS, _, _, notInterruptible = Raw(UnitCastingInfo, unit)
    if name ~= nil then return name, texture, startMS, endMS, notInterruptible, false end
    local cName, _, cTexture, cStart, cEnd, _, cNotInterruptible = Raw(UnitChannelInfo, unit)
    if cName ~= nil then return cName, cTexture, cStart, cEnd, cNotInterruptible, true end
    return nil
end

-- Secret "not interruptible": the client picks the colour and the shield's
-- visibility from the flag; nothing is compared here. false when unsupported.
local function applySecretLock(cb, flag, normal)
    local fold = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if type(fold) ~= "function" or not cb.shieldHost.SetAlphaFromBoolean then return false end
    local locked = ns.Style.castLocked
    return pcall(function()
        cb:SetStatusBarColor(fold(flag, locked[1], normal[1]), fold(flag, locked[2], normal[2]),
            fold(flag, locked[3], normal[3]))
        cb.shieldHost:SetAlphaFromBoolean(flag, 1, 0)
    end)
end

-- isStart = called for a cast that just began (the warning sound plays then)
function ns.UpdateCastbar(f, isStart)
    local cb = f.castbar
    if not cb then return end
    if not castbarEnabled(f) or not Plain(UnitExists, f.unit) then
        cb:Hide()
        return
    end
    local name, texture, startMS, endMS, notInterruptible, channel = readCast(f.unit)
    if name == nil then
        if not cb.holdUntil or GetTime() > cb.holdUntil then cb:Hide() end
        return
    end
    cb.holdUntil = nil
    if not pcall(cb.text.SetText, cb.text, name) then cb.text:SetText("") end
    pcall(cb.icon.SetTexture, cb.icon, texture)

    local normal = channel and ns.Style.castChannel or ns.Style.castbar
    if not (IsSecret(notInterruptible) and applySecretLock(cb, notInterruptible, normal)) then
        local locked = (not IsSecret(notInterruptible)) and notInterruptible == true
        local color = locked and ns.Style.castLocked or normal
        cb:SetStatusBarColor(color[1], color[2], color[3])
        cb.shieldHost:SetAlpha(locked and 1 or 0)
    end
    updateKick(f, cb, notInterruptible, isStart)

    if not IsSecret(startMS) and not IsSecret(endMS) and type(startMS) == "number" and type(endMS) == "number" then
        clearTimer(cb)
        cb.startTime, cb.endTime, cb.channel = startMS / 1000, endMS / 1000, channel
        cb:SetMinMaxValues(0, math.max(0.01, cb.endTime - cb.startTime))
        cb:SetScript("OnUpdate", onUpdate)
        onUpdate(cb)
        cb:Show()
        return
    end
    -- secret timing: the client animates the bar from a duration object
    local getter = channel and UnitChannelDuration or UnitCastingDuration
    if type(getter) == "function" and cb.SetTimerDuration then
        local duration = Raw(getter, f.unit)
        local direction = Enum and Enum.StatusBarTimerDirection and
            (channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
        clearTimer(cb)
        if duration and pcall(cb.SetTimerDuration, cb, duration, nil, direction) then
            cb.time:SetText("")
            cb:Show()
            return
        end
    end
    cb:Hide()
end

-- Interrupted / failed: show a short red notice, then hide.
function ns.CastbarStopped(f, interrupted)
    local cb = f.castbar
    if not cb or not cb:IsShown() then return end
    if interrupted then
        clearTimer(cb)
        cb:SetValue(1)
        cb:SetStatusBarColor(rgba(ns.Style.warning))
        cb.shieldHost:SetAlpha(0)
        hideKick(cb)
        cb.text:SetText(ns:L("interrupted"))
        cb.time:SetText("")
        cb.holdUntil = GetTime() + 0.6
        C_Timer.After(0.65, function()
            if cb.holdUntil and GetTime() >= cb.holdUntil then
                cb.holdUntil = nil
                ns.UpdateCastbar(f)
            end
        end)
    else
        ns.UpdateCastbar(f)
    end
end
