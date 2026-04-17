local api = require("api")

-- Portions of this implementation are based on the original AddonLibrary
-- check button code by Misosoup and contributors.

local function getDefaultCheckButtonFontColor()
    return {
        normal = FONT_COLOR.DEFAULT,
        highlight = FONT_COLOR.DEFAULT,
        pushed = FONT_COLOR.DEFAULT,
        disabled = { 0.42, 0.42, 0.42, 1 }
    }
end

local function getButtonDefaultFontColor()
    return {
        normal = { ConvertColor(104), ConvertColor(68), ConvertColor(18), 1 },
        highlight = { ConvertColor(154), ConvertColor(96), ConvertColor(16), 1 },
        pushed = { ConvertColor(104), ConvertColor(68), ConvertColor(18), 1 },
        disabled = { ConvertColor(92), ConvertColor(92), ConvertColor(92), 1 }
    }
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

local function initTextButton(button)
    if button.EnableDrawables ~= nil then
        button:EnableDrawables("background")
    end
    if button.style ~= nil and button.style.SetAlign ~= nil then
        button.style:SetAlign(ALIGN.CENTER)
    end
    if button.style ~= nil and button.style.SetSnap ~= nil then
        button.style:SetSnap(true)
    end
    if button.style ~= nil and button.style.SetColor ~= nil then
        button.style:SetColor(0.87, 0.69, 0, 1)
    end
    setButtonFontColor(button, getButtonDefaultFontColor())
    if button.RegisterForClicks ~= nil then
        button:RegisterForClicks("LeftButton")
    end
end

local function createEmptyButton(id, parent)
    local button = api.Interface:CreateWidget("button", id, parent)
    if button.RegisterForClicks ~= nil then
        button:RegisterForClicks("LeftButton")
        button:RegisterForClicks("RightButton", false)
    end
    if button.style ~= nil and button.style.SetAlign ~= nil then
        button.style:SetAlign(ALIGN.CENTER)
    end
    if button.style ~= nil and button.style.SetSnap ~= nil then
        button.style:SetSnap(true)
    end
    setButtonFontColor(button, getButtonDefaultFontColor())
    return button
end

local function setButtonBackground(button)
    button:SetNormalBackground(button.bgs[1])
    button:SetHighlightBackground(button.bgs[2])
    button:SetPushedBackground(button.bgs[3])
    button:SetDisabledBackground(button.bgs[4])
    if button.bgs[5] ~= nil then
        button:SetCheckedBackground(button.bgs[5])
    end
    if button.bgs[6] ~= nil then
        button:SetDisabledCheckedBackground(button.bgs[6])
    end
end

local function setButtonCoordsForBg(bg, coords)
    if coords == nil then
        return
    end
    bg:SetExtent(coords[3], coords[4])
    bg:SetCoords(coords[1], coords[2], coords[3], coords[4])
end

local function createDefaultDrawable(widget, drawableType, path, layer)
    local currentLayer = layer or "background"
    if drawableType == "threePart" then
        return widget:CreateThreePartDrawable(path, currentLayer)
    end
    if drawableType == "ninePart" then
        return widget:CreateNinePartDrawable(path, currentLayer)
    end
    return widget:CreateImageDrawable(path, currentLayer)
end

local function createCheckButtonBackground(button, path, drawableType, count)
    button.bgs = {}
    for index = 1, count or 4 do
        local drawable = createDefaultDrawable(button, drawableType, path)
        drawable:SetExtent(16, 16)
        drawable:AddAnchor("CENTER", button, 0, 0)
        if drawable.SetTexture ~= nil then
            drawable:SetTexture(path)
        end
        button.bgs[index] = drawable
    end
end

local function setTextButtonStyle(textButton, checkButton, anchorPoint, fontColor)
    if textButton == nil then
        return
    end
    textButton:RemoveAllAnchors()
    textButton:AddAnchor(anchorPoint, checkButton, anchorPoint == "RIGHT" and "LEFT" or "RIGHT", anchorPoint == "RIGHT" and -5 or 0, 0)
    setButtonFontColor(textButton, fontColor)
end

local function setViewOfCheckButton(id, parent, text)
    local button = api.Interface:CreateWidget("checkbutton", id, parent)
    createCheckButtonBackground(button, "ui/button/check_button.dds", "drawable", 6)

    if text ~= nil then
        local textButton = createEmptyButton(id .. ".textButton", button)
        textButton:AddAnchor("LEFT", button, "RIGHT", 0, 0)
        initTextButton(textButton)
        textButton:SetAutoResize(true)
        textButton:SetHeight(16)
        textButton:SetText(text)
        if textButton.style ~= nil and textButton.style.SetAlign ~= nil then
            textButton.style:SetAlign(ALIGN.LEFT)
        end
        button.textButton = textButton
    end

    function button:SetButtonStyle(style)
        local coords = {}
        if style == "eyeShape" then
            self:SetExtent(27, 18)
            setTextButtonStyle(self.textButton, button, "RIGHT", getDefaultCheckButtonFontColor())
            coords[1] = { 37, 0, 27, 18 }
            coords[2] = { 37, 0, 27, 18 }
            coords[3] = { 37, 0, 27, 18 }
            coords[4] = { 37, 36, 27, 18 }
            coords[5] = { 37, 18, 27, 18 }
            coords[6] = { 37, 36, 27, 18 }
        elseif style == "soft_brown" then
            self:SetExtent(18, 17)
            if self.textButton ~= nil then
                setTextButtonStyle(self.textButton, button, "LEFT", GetSoftCheckButtonFontColor())
            end
            coords[1] = { 0, 0, 18, 17 }
            coords[2] = { 0, 0, 18, 17 }
            coords[3] = { 0, 0, 18, 17 }
            coords[4] = { 0, 17, 18, 17 }
            coords[5] = { 18, 0, 18, 17 }
            coords[6] = { 18, 17, 18, 17 }
        elseif style == "quest_notifier" then
            self:SetExtent(18, 17)
            setTextButtonStyle(self.textButton, button, "LEFT", getDefaultCheckButtonFontColor())
            coords[1] = { 57, 54, 7, 10 }
            coords[2] = { 0, 0, 18, 17 }
            coords[3] = { 0, 0, 18, 17 }
            coords[4] = { 0, 17, 18, 17 }
            coords[5] = { 18, 0, 18, 17 }
            coords[6] = { 18, 17, 18, 17 }
        elseif style == "tutorial" then
            self:SetExtent(18, 18)
            if self.textButton ~= nil then
                setTextButtonStyle(self.textButton, button, "LEFT", GetBlackCheckButtonFontColor())
            end
            coords[1] = { 0, 0, 18, 17 }
            coords[2] = { 0, 0, 18, 17 }
            coords[3] = { 0, 0, 18, 17 }
            coords[4] = { 0, 17, 18, 17 }
            coords[5] = { 18, 0, 18, 17 }
            coords[6] = { 18, 17, 18, 17 }
        else
            self:SetExtent(18, 17)
            setTextButtonStyle(self.textButton, button, "LEFT", getDefaultCheckButtonFontColor())
            coords[1] = { 0, 0, 18, 17 }
            coords[2] = { 0, 0, 18, 17 }
            coords[3] = { 0, 0, 18, 17 }
            coords[4] = { 0, 17, 18, 17 }
            coords[5] = { 18, 0, 18, 17 }
            coords[6] = { 18, 17, 18, 17 }
        end

        for index = 1, #coords do
            setButtonCoordsForBg(self.bgs[index], coords[index])
        end
        setButtonBackground(self)
    end

    button:SetButtonStyle(nil)
    setButtonBackground(button)
    return button
end

local function createCheckButton(id, parent, text)
    local button = setViewOfCheckButton(id, parent, text)

    function button:SetEnableCheckButton(enable)
        self:Enable(enable, true)
        if self.textButton ~= nil then
            self.textButton:Enable(enable)
        end
    end

    function button:OnCheckChanged()
        if self.CheckBtnCheckChagnedProc ~= nil then
            self:CheckBtnCheckChagnedProc(self:GetChecked())
        end
    end

    button:SetHandler("OnCheckChanged", button.OnCheckChanged)

    if button.textButton ~= nil then
        function button.textButton:OnClick()
            if button:IsEnabled() then
                button:SetChecked(not button:GetChecked())
            end
        end
        button.textButton:SetHandler("OnClick", button.textButton.OnClick)
    end

    return button
end

return createCheckButton
