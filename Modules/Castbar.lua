--===========================================================================
-- EzWoW - Unit Frames
-- Modules/Castbar.lua : Cast bar for target / focus (shows uninterruptible casts)
--===========================================================================
local _, ns = ...
local type, pcall = type, pcall
local Plain, Raw, IsSecret = ns.Plain, ns.Raw, ns.IsSecret

local TEX = "Interface\\Buttons\\WHITE8X8"
local HEIGHT = 16

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

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

    cb.shield = cb:CreateTexture(nil, "OVERLAY")
    cb.shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
    cb.shield:SetSize(HEIGHT * 2, HEIGHT * 2)
    cb.shield:SetPoint("CENTER", cb.iconFrame, "CENTER", 0, -1)
    cb.shield:Hide()

    cb:SetScript("OnHide", function(self)
        clearTimer(self)
        self.holdUntil = nil
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

function ns.UpdateCastbar(f)
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

    local locked = (not IsSecret(notInterruptible)) and notInterruptible == true
    local color = locked and ns.Style.castLocked or (channel and ns.Style.castChannel or ns.Style.castbar)
    cb:SetStatusBarColor(color[1], color[2], color[3])
    cb.shield:SetShown(locked)

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
