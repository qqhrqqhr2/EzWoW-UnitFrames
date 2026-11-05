--===========================================================================
-- EzWoW - Unit Frames
-- Core/UIKit.lua : Unified EzWoW Surface, Widget & Event Dispatch Toolkit
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local UIKit = ns.UIKit or {}
ns.UIKit = UIKit

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

UIKit.Theme = {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.95 },
    bgSecondary = { 0.114, 0.157, 0.192, 0.96 },
    bgInput     = { 0.047, 0.067, 0.086, 0.96 },
    border      = { 0.204, 0.298, 0.357, 1.00 },
    textBody    = { 0.929, 0.957, 0.969, 1.00 },
    textMuted   = { 0.655, 0.725, 0.773, 1.00 },
    accent      = { 0.949, 0.706, 0.353, 1.00 },
    accentHex   = "F2B45A",
    warning     = { 0.906, 0.486, 0.439, 1.00 },
    disabled    = { 0.388, 0.447, 0.482, 1.00 },
}

local SHARED_BACKDROPS = {}

function UIKit:GetBackdropSpec(edgeSize, insetSize, tileFlag, tileSize)
    local e = edgeSize or 1
    local i = insetSize or 0
    local key = e .. ":" .. i .. ":" .. (tileFlag and 1 or 0) .. ":" .. (tileSize or 0)
    local spec = SHARED_BACKDROPS[key]
    if not spec then
        spec = {
            bgFile   = WHITE8X8,
            edgeFile = e > 0 and WHITE8X8 or nil,
            tile     = tileFlag or false,
            tileSize = tileSize or 0,
            edgeSize = e > 0 and e or nil,
            insets   = { left = i, right = i, top = i, bottom = i },
        }
        SHARED_BACKDROPS[key] = spec
    end
    return spec
end

function UIKit:ApplyBackdrop(frame, edgeSize, insetSize, tileFlag, tileSize)
    if not frame or not frame.SetBackdrop then return frame end
    frame:SetBackdrop(self:GetBackdropSpec(edgeSize, insetSize, tileFlag, tileSize))
    return frame
end

function UIKit:ApplySurface(frame, bgRGBA, borderRGBA, edgeSize, insetSize)
    if not frame or not frame.SetBackdrop then return frame end
    frame:SetBackdrop(self:GetBackdropSpec(edgeSize or 1, insetSize or 0))
    local bg = bgRGBA or self.Theme.bgPrimary
    local bd = borderRGBA or self.Theme.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.95)
    if frame.SetBackdropBorderColor and bd then
        frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1.0)
    end
    return frame
end

function UIKit:CreateLabel(parent, template, point, relFrame, relPoint, offsetX, offsetY, colorRGBA, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    if point then
        if type(relFrame) == "number" then
            fs:SetPoint(point, relFrame, relPoint or 0)
        else
            fs:SetPoint(point, relFrame or parent, relPoint or point, offsetX or 0, offsetY or 0)
        end
    end
    local col = colorRGBA or self.Theme.textBody
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1.0)
    if text then fs:SetText(text) end
    return fs
end

function UIKit:BindEvents(frame, handlerMap)
    if not frame or type(handlerMap) ~= "table" then return frame end
    for eventName in pairs(handlerMap) do
        pcall(frame.RegisterEvent, frame, eventName)
    end
    frame:SetScript("OnEvent", function(selfFrame, eventName, ...)
        local fn = handlerMap[eventName]
        if fn then fn(selfFrame, ...) end
    end)
    return frame
end

function UIKit:ElevateModal(frame, baseLevel)
    if not frame then return end
    local lvl = tonumber(baseLevel) or 260
    if frame.SetFrameStrata then frame:SetFrameStrata("TOOLTIP") end
    if frame.SetToplevel then frame:SetToplevel(true) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    if frame.SetFrameLevel then frame:SetFrameLevel(lvl) end
    if frame.Raise then frame:Raise() end
end

-----------------------------------------------------------------------------
-- Text Fitting (long translations such as German must not spill out)
-----------------------------------------------------------------------------
local FIT_MIN_SCALE = 0.7

local function setFitScale(fs, scale)
    if fs.SetTextScale then
        fs:SetTextScale(scale)            -- keeps the font object, so font addons still apply
    else
        local base = fs.ezFitBase
        fs:SetFont(base[1], base[2] * scale, base[3])
    end
end

-- Shrinks the text (down to 70%) until it fits maxWidth on maxLines lines.
-- Call again after every SetText.
function UIKit:FitFontString(fs, maxWidth, maxLines)
    if not (fs and fs.GetStringWidth and maxWidth and maxWidth > 0) then return end
    if not fs.SetTextScale and not fs.ezFitBase then
        local path, size, flags = fs:GetFont()
        if not path then return end
        fs.ezFitBase = { path, size, flags }
    end
    maxLines = maxLines or 1
    local scale = 1
    setFitScale(fs, scale)
    local _, baseSize = fs:GetFont()
    local function fits()
        if maxLines <= 1 then
            local width = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
            return width <= maxWidth
        end
        local lineHeight = (baseSize or 10) * scale * 1.3
        return fs:GetStringHeight() <= lineHeight * maxLines + 1
    end
    while not fits() and scale > FIT_MIN_SCALE do
        scale = scale - 0.05
        setFitScale(fs, scale)
    end
end

-- Button grows with its text between minWidth and maxWidth; beyond that the text shrinks.
function UIKit:SizeButtonToText(button, fs, minWidth, maxWidth, padding)
    if not (button and fs) then return end
    padding = padding or 12
    setFitScale(fs, 1)
    local textWidth = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    local width = math.min(maxWidth, math.max(minWidth, math.ceil((textWidth or 0) + padding)))
    button:SetWidth(width)
    self:FitFontString(fs, width - padding + 4, 1)
end

-----------------------------------------------------------------------------
-- Widgets: buttons, check boxes, edit boxes, window header
-----------------------------------------------------------------------------
local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local function paintButton(b)
    local S = ns.Style
    local hover = b.hover
    if not b.enabledState then
        b:SetBackdropColor(rgba(S.bgSecondary))
        b:SetBackdropBorderColor(rgba(S.border))
        b.label:SetTextColor(rgba(S.disabled))
    elseif b.active or b.accent then
        b:SetBackdropColor(rgba(hover and S.bgAccentHot or S.bgAccent))
        b:SetBackdropBorderColor(rgba(S.accent))
        b.label:SetTextColor(rgba(b.activeColor or S.accent))
    else
        b:SetBackdropColor(rgba(hover and S.bgHover or S.bgSecondary))
        b:SetBackdropBorderColor(rgba(hover and S.accent or S.border))
        b.label:SetTextColor(rgba(S.textBody))
    end
end

-- Flat EzWoW button. accent = highlighted style; :SetActive() makes a toggle chip.
function UIKit:CreateButton(parent, width, height, text, accent, fontObject)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    self:ApplyBackdrop(b)
    b.label = b:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    b.label:SetPoint("CENTER")
    b.accent = accent and true or false
    b.enabledState = true
    b.fontSize = fontObject == "GameFontHighlightSmall" and 11 or 12
    function b:SetLabel(value)
        self.text = value or ""
        ns.FitText(self.label, self.text, self:GetWidth() - 10, self.fontSize, 8)
    end
    function b:SetActive(value)
        self.active = value and true or false
        paintButton(self)
    end
    function b:SetEnabledState(value)
        self.enabledState = value and true or false
        self:SetEnabled(self.enabledState)
        paintButton(self)
    end
    b:SetScript("OnEnter", function(self)
        self.hover = true
        paintButton(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(type(self.tooltip) == "function" and self.tooltip() or self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        paintButton(self)
        if self.tooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnMouseDown", function(self) if self.enabledState then self.label:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetLabel(text)
    paintButton(b)
    return b
end

function UIKit:CreateCloseButton(parent, onClick)
    local close = self:CreateButton(parent, 22, 22, "X")
    close:SetFrameLevel(parent:GetFrameLevel() + 3)
    close:SetScript("OnClick", onClick)
    return close
end

-- Check box with a label on its right. Returns check, label.
function UIKit:CreateCheck(parent, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", c, "RIGHT", 4, 0)
    t:SetJustifyH("LEFT")
    t:SetTextColor(rgba(ns.Style.textBody))
    c:SetScript("OnClick", function(self) if onClick then onClick(self:GetChecked() and true or false) end end)
    return c, t
end

function UIKit:CreateEditBox(parent, width, height, placeholderFn, multiLine)
    local S = ns.Style
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    self:ApplyBackdrop(box)
    box:SetBackdropColor(rgba(S.bgInput))
    box:SetBackdropBorderColor(rgba(S.border))

    local edit = CreateFrame("EditBox", nil, box)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextColor(rgba(S.textBody))
    edit:SetAutoFocus(false)
    if multiLine then
        edit:SetMultiLine(true)
        edit:SetPoint("TOPLEFT", 8, -6)
        edit:SetPoint("TOPRIGHT", -8, -6)
        edit:SetHeight(height - 12)
        box:EnableMouse(true)
        box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    else
        edit:SetPoint("TOPLEFT", 8, 0)
        edit:SetPoint("BOTTOMRIGHT", -8, 0)
    end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint(multiLine and "TOPLEFT" or "LEFT", 9, multiLine and -7 or 0)
    local function updatePlaceholder()
        placeholder:SetText(placeholderFn and placeholderFn() or "")
        placeholder:SetShown(edit:GetText() == "" and not edit:HasFocus())
    end
    edit:HookScript("OnEditFocusGained", function()
        box:SetBackdropBorderColor(rgba(S.accent))
        updatePlaceholder()
    end)
    edit:HookScript("OnEditFocusLost", function()
        box:SetBackdropBorderColor(rgba(S.border))
        updatePlaceholder()
    end)
    edit:HookScript("OnTextChanged", updatePlaceholder)
    box.edit = edit
    box.UpdatePlaceholder = updatePlaceholder
    updatePlaceholder()
    return box, edit
end

-- 58px EzWoW header bar with icon, title, subtitle and a 2px accent line.
function UIKit:CreateHeader(frame, title)
    local S = ns.Style
    local top = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    top:SetHeight(58)
    top:SetBackdrop({ bgFile = WHITE8X8 })
    top:SetBackdropColor(S.bgSecondary[1], S.bgSecondary[2], S.bgSecondary[3], 0.98)
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() frame:StartMoving() end)
    top:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if frame.OnMoved then frame:OnMoved() end
    end)

    local line = top:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(rgba(S.accent))
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(2)

    local icon = top:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -14)
    icon:SetTexture(ns.MEDIA_PATH .. "Icon")

    local heading = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 48, -11)
    heading:SetText(title)
    heading:SetTextColor(rgba(S.accent))

    local sub = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -3)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(rgba(S.textMuted))
    top.subtitle = sub
    return top
end

function UIKit:CreateSectionLabel(parent, x, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", x, y)
    t:SetJustifyH("LEFT")
    t:SetTextColor(rgba(ns.Style.accent))
    return t
end

-----------------------------------------------------------------------------
-- Scroll list (fixed-height rows, mouse wheel, thin scroll bar)
-----------------------------------------------------------------------------
-- createRow(list, index) -> row frame ; updateRow(row, item, dataIndex)
function UIKit:CreateScrollList(parent, rowHeight, rowGap, wheelStep, createRow, updateRow)
    local S = ns.Style
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.data, list.offset = {}, {}, 0
    list:EnableMouseWheel(true)

    local track = list:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(S.border[1], S.border[2], S.border[3], 0.35)
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(4)
    local thumb = list:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(S.accent[1], S.accent[2], S.accent[3], 0.75)
    thumb:SetWidth(4)

    local step = rowHeight + rowGap

    function list:VisibleCount()
        return math.max(1, math.floor(((self:GetHeight() or 0) + rowGap) / step))
    end

    function list:Refresh()
        local visible = self:VisibleCount()
        for i = #self.rows + 1, visible do
            local row = createRow(self, i)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * step)
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -8, -(i - 1) * step)
            self.rows[i] = row
        end
        local total = #self.data
        local maxOffset = math.max(0, total - visible)
        if self.offset > maxOffset then self.offset = maxOffset end
        for i, row in ipairs(self.rows) do
            local item = (i <= visible) and self.data[self.offset + i] or nil
            if item then
                updateRow(row, item, self.offset + i)
                row:Show()
            else
                row:Hide()
            end
        end
        local trackHeight = self:GetHeight() or 0
        if total > visible and trackHeight > 0 then
            local thumbHeight = math.max(20, trackHeight * visible / total)
            local y = (trackHeight - thumbHeight) * (self.offset / maxOffset)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -y)
            thumb:SetHeight(thumbHeight)
            thumb:Show()
            track:Show()
        else
            thumb:Hide()
            track:Hide()
        end
    end

    function list:SetData(data, keepOffset)
        self.data = data or {}
        if not keepOffset then self.offset = 0 end
        self:Refresh()
    end

    list:SetScript("OnMouseWheel", function(self, delta)
        local maxOffset = math.max(0, #self.data - self:VisibleCount())
        self.offset = math.max(0, math.min(maxOffset, self.offset - delta * (wheelStep or 1)))
        self:Refresh()
    end)
    list:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    return list
end

-----------------------------------------------------------------------------
-- Pop-up pick list (one open at a time, closes on an outside click)
-----------------------------------------------------------------------------
local menu, catcher

local function hideMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
UIKit.HideMenu = hideMenu

-- items = { { value, text, sub, color } ... }; opts = { columns, width, current, onSelect }
function UIKit:ShowMenu(anchor, items, opts)
    local S = ns.Style
    if menu and menu:IsShown() and menu.anchor == anchor then
        hideMenu()
        return
    end
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", hideMenu)
        catcher:Hide()

        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        self:ApplyBackdrop(menu, 1, 1)
        menu.rows = {}
        menu:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
    end
    catcher:SetFrameLevel(1)
    menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    menu:SetBackdropColor(S.bgPrimary[1], S.bgPrimary[2], S.bgPrimary[3], 0.99)
    menu:SetBackdropBorderColor(rgba(S.accent))
    menu.anchor = anchor

    local columns = opts.columns or 1
    local colWidth = opts.width or anchor:GetWidth()
    local rowHeight = 20
    local perColumn = math.ceil(#items / columns)

    for i, item in ipairs(items) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(rowHeight)
            row.hl = row:CreateTexture(nil, "BACKGROUND")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(S.accent[1], S.accent[2], S.accent[3], 0.18)
            row.hl:Hide()
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetJustifyH("LEFT")
            row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.sub:SetPoint("RIGHT", -6, 0)
            row.sub:SetJustifyH("RIGHT")
            row.sub:SetTextColor(rgba(S.textMuted))
            row:SetScript("OnEnter", function(r) r.hl:Show() end)
            row:SetScript("OnLeave", function(r) r.hl:Hide() end)
            menu.rows[i] = row
        end
        local col = math.floor((i - 1) / perColumn)
        local line = (i - 1) % perColumn
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 3 + col * colWidth, -3 - line * rowHeight)
        row:SetWidth(colWidth)
        local label = type(item.text) == "function" and item.text() or (item.text or tostring(item.value))
        local selected = item.value == opts.current
        row.sub:SetText(item.sub or "")
        local subWidth = (item.sub and item.sub ~= "") and (row.sub:GetStringWidth() + 10) or 0
        ns.FitText(row.text, (selected and "> " or "") .. label, colWidth - 16 - subWidth, 11, 8)
        if selected then
            row.text:SetTextColor(rgba(S.accent))
        elseif item.color then
            row.text:SetTextColor(rgba(item.color))
        else
            row.text:SetTextColor(rgba(S.textBody))
        end
        row.value = item.value
        row:SetScript("OnClick", function(r)
            hideMenu()
            if opts.onSelect then opts.onSelect(r.value) end
        end)
        row:Show()
    end
    for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end

    menu:SetSize(columns * colWidth + 6, perColumn * rowHeight + 6)
    menu:ClearAllPoints()
    local bottom = anchor:GetBottom() or 0
    if bottom - menu:GetHeight() < 10 then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    catcher:Show()
    menu:Show()
    menu:Raise()
end
