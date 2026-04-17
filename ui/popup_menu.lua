local api = require("api")

-- Portions of this implementation are based on the original AddonLibrary
-- popup menu code by Misosoup and contributors.

local buttonHeight = 20
local frameMargin = 10
local popupMenu = nil

local function getScreenExtent()
    local width = 2042
    local height = 1124

    if type(api) == "table" and type(api.Interface) == "table" then
        if type(api.Interface.GetScreenWidth) == "function" then
            pcall(function()
                width = tonumber(api.Interface:GetScreenWidth()) or width
            end)
        end
        if type(api.Interface.GetScreenHeight) == "function" then
            pcall(function()
                height = tonumber(api.Interface:GetScreenHeight()) or height
            end)
        end
    end

    return width, height
end

local function createTooltipDrawable(widget)
    local bg = widget:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:AddAnchor("TOPLEFT", widget, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", widget, 0, 0)
    bg:SetCoords(733, 169, 14, 15)
    bg:SetInset(7, 7, 6, 7)
    widget.bg = bg
end

local function hexColorToRgba(text)
    if type(text) ~= "string" then
        return nil
    end

    if type(Hex2Dec) == "function" then
        local ok, value = pcall(Hex2Dec, text)
        if ok and type(value) == "table" then
            return value
        end
    end

    local hex = string.gsub(text, "^#", "")
    if string.len(hex) ~= 6 and string.len(hex) ~= 8 then
        return nil
    end

    local function parsePair(index)
        return tonumber(string.sub(hex, index, index + 1), 16)
    end

    local r = parsePair(1)
    local g = parsePair(3)
    local b = parsePair(5)
    local a = string.len(hex) == 8 and parsePair(7) or 255
    if r == nil or g == nil or b == nil or a == nil then
        return nil
    end
    return { r / 255, g / 255, b / 255, a / 255 }
end

local function setButtonFontOneColor(button, color)
    button:SetTextColor(color[1], color[2], color[3], color[4])
    button:SetPushedTextColor(color[1], color[2], color[3], color[4])
    button:SetHighlightTextColor(color[1], color[2], color[3], color[4])
    button:SetDisabledTextColor(color[1], color[2], color[3], color[4])
end

local function setButtonFontColor(button, color)
    local normal = color.normal
    local highlight = color.highlight
    local pushed = color.pushed
    local disabled = color.disabled
    button:SetTextColor(normal[1], normal[2], normal[3], normal[4])
    button:SetHighlightTextColor(highlight[1], highlight[2], highlight[3], highlight[4])
    button:SetPushedTextColor(pushed[1], pushed[2], pushed[3], pushed[4])
    button:SetDisabledTextColor(disabled[1], disabled[2], disabled[3], disabled[4])
end

local function setViewOfPopupMenuFrame(id, parent)
    local window = api.Interface:CreateEmptyWindow(id, parent)
    window:SetTitleInset(0, frameMargin, 0, 0)
    createTooltipDrawable(window)
    window.buttons = {}

    function window:Resize()
        local count = #self.buttons
        local width = 0
        for index = 1, count do
            local button = self.buttons[index]
            local buttonWidthValue = button:GetWidth()
            if width < buttonWidthValue then
                width = buttonWidthValue
            end
            button:SetAutoResize(false)
        end
        for index = 1, count do
            self.buttons[index]:SetExtent(width, buttonHeight)
        end
        local height = frameMargin * 2 + count * buttonHeight
        window:SetExtent(frameMargin * 2 + width, height)
    end

    function window:AddButton(info)
        local btnColor = {
            normal = { ConvertColor(209), ConvertColor(192), ConvertColor(172), 1 },
            highlight = { ConvertColor(233), ConvertColor(197), ConvertColor(155), 1 },
            pushed = { ConvertColor(200), ConvertColor(168), ConvertColor(129), 1 },
            disabled = { ConvertColor(120), ConvertColor(120), ConvertColor(120), 1 }
        }

        local index = #self.buttons + 1
        local button = self:CreateChildWidget("button", "button", index, true)
        setButtonFontColor(button, btnColor)

        if index == 1 then
            button:AddAnchor("TOPLEFT", window, frameMargin, frameMargin)
        else
            button:AddAnchor("TOPLEFT", self.buttons[index - 1], "BOTTOMLEFT", 0, 0)
        end

        local insetLeft = 5
        local insetRight = 5
        if info.text_inset ~= nil then
            insetLeft = insetLeft + info.text_inset.left
            insetRight = insetRight + info.text_inset.right
        end

        if info.text_color ~= nil then
            if type(info.text_color) == "string" then
                local color = hexColorToRgba(info.text_color)
                if type(color) == "table" then
                    setButtonFontOneColor(button, { color[1], color[2], color[3], color[4] })
                end
            elseif type(info.text_color) == "table" then
                setButtonFontOneColor(button, {
                    info.text_color[1],
                    info.text_color[2],
                    info.text_color[3],
                    info.text_color[4]
                })
            end
        end

        if info.image ~= nil then
            local image = button:CreateImageDrawable(info.image.path, "background")
            if info.anchorInfo ~= nil then
                image:AddAnchor(
                    info.anchorInfo.myAnchor,
                    button,
                    info.anchorInfo.targetAnchor,
                    info.anchorInfo.anchorX,
                    info.anchorInfo.anchorY
                )
            else
                image:AddAnchor("RIGHT", button, -insetRight, 0)
                insetRight = insetRight + info.image.width + 3
            end
            image:SetExtent(info.image.width, info.image.height)
            image:SetCoords(info.image.x, info.image.y, info.image.width, info.image.height)
        end

        button:SetInset(insetLeft, 0, insetRight, 0)
        button:SetAutoResize(true)
        button:SetText(info.text)
        button.style:SetShadow(false)
        button.style:SetAlign(ALIGN.LEFT)
        self.buttons[index] = button

        return button
    end

    window:EnableHidingIsRemove(true)
    window:SetCloseOnEscape(true)
    return window
end

local function safeCallFunc(func, ...)
    if func ~= nil then
        func(...)
    end
end

local function getDefaultPopupInfoTable()
    local infoTable = {
        target = nil,
        hideProcedure = nil,
        infos = {}
    }

    function infoTable:AddInfo(text, proc, arg, hasChild, tooltipData)
        local index = #self.infos + 1
        self.infos[index] = {
            text = text or "",
            proc = proc or nil,
            arg = arg,
            hasChild = hasChild or false,
            tooltipData = tooltipData or nil
        }
    end

    function infoTable:AddLayoutInfo(textInset)
        self.infos[#self.infos].text_inset = textInset or nil
    end

    function infoTable:AddTextButtonColor(textColor)
        self.infos[#self.infos].text_color = textColor
    end

    function infoTable:AddRadioBtn(isChecked)
        self.infos[#self.infos].radio = isChecked
    end

    function infoTable:AddCheckBtn(isShow, isHighlight)
        self.infos[#self.infos].check = { isShow = isShow, value = isHighlight }
    end

    function infoTable:AddImage(image)
        self.infos[#self.infos].image = image
    end

    function infoTable:AddImageAnchorInfo(anchorInfo)
        self.infos[#self.infos].anchorInfo = anchorInfo
    end

    function infoTable:AddDisableStatus(disable)
        self.infos[#self.infos].disable = disable
    end

    function infoTable:GetPopupInfoTableCount()
        return #self.infos
    end

    return infoTable
end

local function hidePopUpMenu(parent)
    if popupMenu == nil then
        return
    end
    if parent ~= nil then
        if parent:GetAttachedWidget() == popupMenu then
            popupMenu:Show(false)
        end
    else
        popupMenu:Show(false)
    end
end

local function showPopUpMenu(id, stickTo, infoTable, isChild, myAnchor, targetAnchor, offsetX, offsetY)
    if infoTable:GetPopupInfoTableCount() == 0 then
        return
    end

    if isChild == nil then
        isChild = false
    end

    local parent = "UIParent"
    if isChild then
        parent = stickTo
    end

    local popup = setViewOfPopupMenuFrame(id, parent)
    if isChild then
        parent.childPopup = popup
    end

    function popup:ClearChild()
        for index = 1, #self.buttons do
            local button = self.buttons[index]
            if button.childPopup ~= nil then
                button.childPopup:Show(false)
                button.childPopup = nil
            end
        end
    end

    for index = 1, #infoTable.infos do
        local info = infoTable.infos[index]
        local button = popup:AddButton(info)

        function button:OnClick()
            if info.proc ~= nil then
                if info.hasChild then
                    popup:ClearChild()
                    info.proc(infoTable.target, info.arg, button)
                else
                    info.proc(infoTable.target, info.arg)
                    hidePopUpMenu()
                    safeCallFunc(infoTable.hideProcedure, self:GetParent())
                end
            end
        end
        button:SetHandler("OnClick", button.OnClick)

        function button:OnEnter()
            popup:ClearChild()
            if info.proc ~= nil then
                if info.hasChild and info.disable ~= true then
                    info.proc(infoTable.target, info.arg, button)
                elseif info.hasChild == false and info.tooltipData ~= nil then
                    -- Stock tooltip support can be restored here if needed.
                end
            end
        end
        button:SetHandler("OnEnter", button.OnEnter)

        function button:OnLeave()
            if info.hasChild == false and info.tooltipData ~= nil then
                if type(HideTooltip) == "function" then
                    HideTooltip()
                end
            end
        end
        button:SetHandler("OnLeave", button.OnLeave)

        if button.radioBtn ~= nil then
            button.radioBtn:SetHandler("OnClick", button.OnClick)
        end
        if info.disable == true then
            button:Enable(false)
        end
    end

    popup:Resize()

    function popup:AnchorToMousePosition()
        local mouseX = 0
        local mouseY = 0
        if type(api) == "table" and type(api.Input) == "table" and type(api.Input.GetMousePos) == "function" then
            pcall(function()
                mouseX, mouseY = api.Input:GetMousePos()
            end)
        end

        local screenWidth, screenHeight = getScreenExtent()
        local width = 0
        local height = 0
        pcall(function()
            width, height = self:GetEffectiveExtent()
        end)
        width = tonumber(width) or 0
        height = tonumber(height) or 0
        local vertOver = screenHeight <= mouseY + height
        local horzOver = screenWidth <= mouseX + width
        if vertOver and horzOver then
            self:AddAnchor("BOTTOMRIGHT", "UIParent", "TOPLEFT", mouseX, mouseY)
        elseif horzOver then
            self:AddAnchor("TOPRIGHT", "UIParent", "TOPLEFT", mouseX, mouseY)
        elseif vertOver then
            self:AddAnchor("BOTTOMLEFT", "UIParent", "TOPLEFT", mouseX, mouseY)
        else
            self:AddAnchor("TOPLEFT", "UIParent", mouseX, mouseY)
        end
    end

    popup:RemoveAllAnchors()
    if not isChild then
        if popupMenu ~= nil then
            hidePopUpMenu()
        end
        popupMenu = popup
        stickTo:AttachWidget(popup)

        function popupMenu:OnHide()
            stickTo:DetachWidget()
            popupMenu = nil
        end
        popupMenu:SetHandler("OnHide", popup.OnHide)

        local events = {
            MOUSE_DOWN = function(widgetId)
                if popupMenu:IsVisible() == true and popupMenu:IsDescendantWidget(widgetId) == false then
                    hidePopUpMenu()
                    safeCallFunc(infoTable.hideProcedure, popupMenu)
                end
            end
        }

        popupMenu:SetHandler("OnEvent", function(_, event, ...)
            local handler = events[event]
            if handler ~= nil then
                handler(...)
            end
        end)
        popupMenu:RegisterEvent("MOUSE_DOWN")
    end

    popup:Show(true)
    if myAnchor == nil then
        popup:AnchorToMousePosition()
    else
        popup:AddAnchor(myAnchor, stickTo, targetAnchor, offsetX, offsetY)
    end
end

return {
    SetViewOfPopupMenuFrame = setViewOfPopupMenuFrame,
    GetDefaultPopupInfoTable = getDefaultPopupInfoTable,
    HidePopUpMenu = hidePopUpMenu,
    ShowPopUpMenu = showPopUpMenu,
    CreateTooltipDrawable = createTooltipDrawable
}
