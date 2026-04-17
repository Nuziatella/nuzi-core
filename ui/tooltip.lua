local api = require("api")

-- Portions of this implementation are based on the original AddonLibrary
-- tooltip code by Misosoup and contributors.

local tooltipColor = {
    normal = {
        ConvertColor(209),
        ConvertColor(192),
        ConvertColor(172),
        1
    }
}

local frameMargin = 10

local function getLargeFontSize()
    if type(FONT_SIZE) == "table" and tonumber(FONT_SIZE.LARGE) ~= nil then
        return tonumber(FONT_SIZE.LARGE)
    end
    return 14
end

local function createTooltipDrawable(widget)
    local bg = widget:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:AddAnchor("TOPLEFT", widget, 0, -7)
    bg:AddAnchor("BOTTOMRIGHT", widget, 0, -3)
    bg:SetCoords(733, 169, 14, 15)
    bg:SetInset(7, 7, 6, 7)
    widget.bg = bg
end

local function createTooltip(id, widget, text)
    local window = api.Interface:CreateEmptyWindow(id, widget)
    window:SetTitleInset(0, frameMargin, 0, 0)
    createTooltipDrawable(window)

    local label = window:CreateChildWidget("label", "toolTip", 0, true)
    label:SetText(text)
    label.style:SetAlign(1)
    label:SetHeight(getLargeFontSize() + 14)
    label:SetWidth(label.style:GetTextWidth(text) + 14)
    label:AddAnchor("CENTER", window, 0, 2)
    ApplyTextColor(label, tooltipColor.normal)

    widget.tooltip = window
    window:Show(false)

    function widget:OnEnter()
        self.tooltip:Show(true)
    end
    widget:SetHandler("OnEnter", widget.OnEnter)

    function widget:OnLeave()
        self.tooltip:Show(false)
    end
    widget:SetHandler("OnLeave", widget.OnLeave)

    window:SetExtent(label:GetWidth() + 2, label:GetHeight() + 2)
    window:AddAnchor("BOTTOM", widget, "TOP", 0, 5)
end

return createTooltip
