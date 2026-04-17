local api = require("api")

-- Portions of this implementation are based on the original AddonLibrary
-- slider code by Misosoup and contributors.

local UOT_SLIDER = 24

local function applyButtonSkin(widget, skin)
    if type(api) == "table" and type(api.Interface) == "table" and type(api.Interface.ApplyButtonSkin) == "function" then
        local ok = pcall(function()
            api.Interface:ApplyButtonSkin(widget, skin)
        end)
        if ok then
            return
        end
    end
    if type(ApplyButtonSkin) == "function" then
        ApplyButtonSkin(widget, skin)
    end
end

local function setViewOfSlider(id, parent)
    local slider = parent:CreateChildWidgetByType(UOT_SLIDER, id, 0, true)
    slider:SetHeight(26)

    local bg = slider:CreateImageDrawable(TEXTURE_PATH.SCROLL, "background")
    bg:SetCoords(0, 0, 256, 9)
    bg:AddAnchor("LEFT", slider, 3, 0)
    bg:AddAnchor("RIGHT", slider, -3, 0)
    bg:SetHeight(6)

    slider.bg = bg
    slider.bgColor = {
        ConvertColor(153),
        ConvertColor(132),
        ConvertColor(86),
        1
    }
    slider.bg:SetColor(slider.bgColor[1], slider.bgColor[2], slider.bgColor[3], slider.bgColor[4])

    local thumb = slider:CreateChildWidget("button", "thumb", 0, true)
    thumb:Show(true)
    applyButtonSkin(thumb, BUTTON_BASIC.SLIDER_HORIZONTAL_THUMB)
    slider:SetThumbButtonWidget(thumb)
    slider.thumb = thumb
    slider:SetFixedThumb(true)
    slider:SetMinThumbLength(17)
    thumb:SetHeight(26)
    slider:SetOrientation(1)

    return slider
end

local function createSlider(id, parent)
    local slider = setViewOfSlider(id, parent)
    slider.useWheel = false

    function slider:SetStep(value)
        self:SetValueStep(value)
        self:SetPageStep(value)
    end

    function slider:SetInitialValue(initialValue)
        self:SetValue(initialValue, false)
    end

    function slider:SetBgColor(colorTable)
        self.bgColor = colorTable
        self.bg:SetColor(self.bgColor[1], self.bgColor[2], self.bgColor[3], self.bgColor[4])
    end

    function slider:SetEnable(enable)
        if self.thumb ~= nil and self.thumb.Enable ~= nil then
            self.thumb:Enable(enable)
        end
        if self.label ~= nil then
            for index = 1, #self.label do
                self.label[index]:Enable(enable)
            end
        end
        if enable then
            self.bg:SetColor(self.bgColor[1], self.bgColor[2], self.bgColor[3], self.bgColor[4])
        else
            self.bg:SetColor(0.5, 0.5, 0.5, 1)
        end
    end

    function slider:UseWheel()
        self.useWheel = true

        self:SetHandler("OnWheelUp", function(this)
            if not this:IsEnabled() or not this.useWheel then
                return
            end
            this:Up(1)
        end)

        self:SetHandler("OnWheelDown", function(this)
            if not this:IsEnabled() or not this.useWheel then
                return
            end
            this:Down(1)
        end)
    end

    return slider
end

return createSlider
