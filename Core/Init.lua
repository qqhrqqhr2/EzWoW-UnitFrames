--===========================================================================
-- EzWoW - Unit Frames
-- Core/Init.lua : Namespace, EzWoW Style Palette, Safe Helpers & SavedVariables
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall

_G.EzWoW_UnitFrames = ns

ns.ADDON_NAME = ADDON_NAME or "EzWoW-UnitFrames"
ns.TITLE = "EzWoW - Unit Frames"
ns.MEDIA_PATH = "Interface\\AddOns\\EzWoW-UnitFrames\\Media\\"
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"
ns.BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-----------------------------------------------------------------------------
-- EzWoW Style v1.0 Palette (Brand Accent: Amber #F2B45A)
-----------------------------------------------------------------------------
ns.Style = {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.97 }, -- #12181F
    bgSecondary = { 0.114, 0.157, 0.192, 0.96 }, -- #1D2831
    bgInput     = { 0.047, 0.067, 0.086, 0.96 }, -- #0C1116
    bgHover     = { 0.160, 0.210, 0.260, 1.00 },
    bgAccent    = { 0.220, 0.170, 0.090, 0.96 },
    bgAccentHot = { 0.290, 0.220, 0.110, 1.00 },
    border      = { 0.204, 0.298, 0.357, 1.00 }, -- #344C5B
    textBody    = { 0.929, 0.957, 0.969, 1.00 }, -- #EDF4F7
    textMuted   = { 0.655, 0.725, 0.773, 1.00 }, -- #A7B9C5
    accent      = { 0.949, 0.706, 0.353, 1.00 }, -- #F2B45A
    accentHex   = "F2B45A",
    warning     = { 0.906, 0.486, 0.439, 1.00 }, -- #E77C70
    disabled    = { 0.388, 0.447, 0.482, 1.00 }, -- #63727B
    -- unit frame colours
    frameBg     = { 0.055, 0.075, 0.098, 0.90 },
    barBg       = { 0.030, 0.040, 0.050, 0.85 },
    health      = { 0.380, 0.780, 0.420, 1.00 },
    tapped      = { 0.550, 0.550, 0.550, 1.00 },
    dead        = { 0.450, 0.450, 0.450, 1.00 },
    castbar     = { 0.949, 0.706, 0.353, 1.00 },
    castLocked  = { 0.600, 0.620, 0.660, 1.00 },
    castChannel = { 0.420, 0.700, 0.950, 1.00 },
    kickReady   = { 1.000, 0.270, 0.200, 1.00 }, -- interrupt warning (my interrupt ready / none)
    kickCooldown = { 0.620, 0.560, 0.950, 1.00 }, -- interrupt warning (my interrupt on cooldown)
    threat      = { { 1.0, 1.0, 0.47 }, { 1.0, 0.6, 0.0 }, { 1.0, 0.0, 0.0 } },
}

-- Frame keys in display order.
ns.FRAME_KEYS = { "player", "target", "targettarget", "focus", "pet", "party" }

ns.DEFAULTS = {
    language      = "auto",
    scale         = 1.0,
    locked        = true,
    enabled       = { player = true, target = true, targettarget = true, focus = true, pet = true, party = true },
    healthText    = "curpct",   -- big frames
    smallText     = "percent",  -- target of target, pet
    partyText     = "percent",
    classColor    = true,
    portraits     = true,
    targetCastbar = true,
    focusCastbar  = true,
    targetAuras   = true,
    playerAuras   = true,
    onlyMyDebuffs = false,
    comboPoints   = true,
    druidMana     = true,
    powerTicks    = true,
    partyInRaid   = false,
    partyDebuffs  = true,
    partyBuffs    = true,     -- one row of buffs under each party member
    partyHorizontal = false,  -- party members side by side instead of stacked
    healPrediction = true,    -- incoming heals continue the health fill
    bigMyAuras    = true,     -- my own auras on the target drawn larger
    rangeFade     = true,
    threatBorder  = true,
    healthFX      = true,
    hitFX         = true,     -- hit/heal trails and flashes (with healthFX)
    hideBlizzard  = true,
    nameplates    = true,
    plateCastbar  = true,
    plateDebuffs  = true,
    plateThreat   = true,
    plateTankMode = false,
    plateFadeOthers = true,
    plateQuest    = true,
    kickWarn      = true,     -- warn about interruptible enemy casts (plates, target, focus)
    kickTargetOnly = false,   -- nameplates: only my target and focus
    kickSound     = false,    -- a sound when such a cast starts
    friendlyPlates = "name",  -- friendly nameplates: "default" (game look), "name", "bar" (name + thin bar)
    friendlyHideInstance = false, -- hide friendly nameplates inside instances (game setting)
    plateOverlap  = true,     -- nameplates stay over their units instead of stacking upward (game setting)
    cvarBackup    = {},       -- my values of game settings changed for friendly plates
    plateScale    = 1.0,
    positions     = {},
}

-----------------------------------------------------------------------------
-- Secret-value & safe-call helpers (Interface 16001)
-----------------------------------------------------------------------------
function ns.IsSecret(value)
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(_G.issecretvalue, value)
    return ok and secret and true or false
end

-- Calls fn and returns its first result only when it is a plain (non-secret) value.
function ns.Plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or ns.IsSecret(value) then return nil end
    return value
end

-- Calls fn and returns all results, secret or not (for widgets that accept secrets).
function ns.Raw(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return select(2, unpack(result))
end

function ns.InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

-- Protected changes wait until combat ends.
local afterCombat = {}
function ns.RunAfterCombat(key, fn)
    if not ns.InCombat() then
        fn()
        return
    end
    afterCombat[key] = fn
end

function ns.FlushAfterCombat()
    for key, fn in pairs(afterCombat) do
        afterCombat[key] = nil
        pcall(fn)
    end
end

function ns.Print(msg)
    print("|cff" .. ns.Style.accentHex .. "EzWoW - Unit Frames:|r " .. tostring(msg or ""))
end

function ns.GetVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if type(getter) == "function" then
        local ok, ver = pcall(getter, ns.ADDON_NAME, "Version")
        if ok and type(ver) == "string" and ver ~= "" and not ver:find("^@") then
            return ver
        end
    end
    return ""
end

-- Short number: 12345 -> 12.3k (uses the client's helper, which also accepts secret values).
function ns.ShortNumber(value)
    if type(AbbreviateNumbers) == "function" then
        local ok, text = pcall(AbbreviateNumbers, value)
        if ok and text ~= nil then return text end
    end
    if ns.IsSecret(value) or type(value) ~= "number" then return value end
    if value >= 1e6 then return string.format("%.1fm", value / 1e6) end
    if value >= 1e4 then return string.format("%.1fk", value / 1e3) end
    return tostring(math.floor(value + 0.5))
end

-- Fits a font string into maxWidth by shrinking, then trimming with "..." (plain text only).
function ns.FitText(fs, text, maxWidth, baseSize, minSize)
    if not fs then return end
    text = text or ""
    fs:SetWordWrap(false)
    if fs.SetTextScale then fs:SetTextScale(1) end
    local font, rawSize, flags = fs:GetFont()
    if not font then
        fs:SetText(text)
        return
    end
    local function applySize(size)
        if fs.SetTextScale and rawSize and rawSize > 0 then
            fs:SetTextScale(size / rawSize)
        else
            fs:SetFont(font, size, flags)
        end
    end
    applySize(baseSize)
    fs:SetText(text)
    local size = baseSize
    while fs:GetStringWidth() > maxWidth and size > minSize do
        size = size - 0.5
        applySize(size)
    end
    if fs:GetStringWidth() > maxWidth then
        local original = text
        while #text > 0 and fs:GetStringWidth() > maxWidth do
            local cut = #text
            while cut > 1 and string.byte(text, cut) >= 128 and string.byte(text, cut) < 192 do
                cut = cut - 1
            end
            text = text:sub(1, cut - 1)
            fs:SetText(text .. "...")
            if text == original then break end
        end
    end
end

-----------------------------------------------------------------------------
-- SavedVariables
-----------------------------------------------------------------------------
function ns:InitDB()
    if type(_G.EzWoW_UnitFramesDB) ~= "table" then _G.EzWoW_UnitFramesDB = {} end
    local db = _G.EzWoW_UnitFramesDB
    for key, value in pairs(self.DEFAULTS) do
        if db[key] == nil then
            if type(value) == "table" then
                db[key] = {}
                for k, v in pairs(value) do db[key][k] = v end
            else
                db[key] = value
            end
        end
    end
    for key, value in pairs(self.DEFAULTS.enabled) do
        if db.enabled[key] == nil then db.enabled[key] = value end
    end
    if type(db.positions) ~= "table" then db.positions = {} end
    if type(db.cvarBackup) ~= "table" then db.cvarBackup = {} end
    if db.friendlyPlates ~= "default" and db.friendlyPlates ~= "bar" then db.friendlyPlates = "name" end
    -- per-frame size on top of the overall scale (Ctrl + mouse wheel on a frame)
    if type(db.frameScales) ~= "table" then db.frameScales = {} end
    db.scale = math.max(0.6, math.min(1.6, tonumber(db.scale) or 1))
    db.locked = true -- always start locked; unlocking is a per-session edit mode
    self.db = db
end

-----------------------------------------------------------------------------
-- Bootstrap
-----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ns.ADDON_NAME then ns:InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then ns:InitDB() end
        if ns.BuildAllFrames then ns.BuildAllFrames() end
        if ns.RegisterBlizzardOptions then ns:RegisterBlizzardOptions() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.FlushAfterCombat()
    end
end)
