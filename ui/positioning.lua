local api = require("api")
local Runtime = require("nuzi-core/runtime")

local Positioning = {}

local function resolveKeys(kind, mappings)
    local map = type(mappings) == "table" and mappings or {}
    local entry = map[kind]
    if type(entry) ~= "table" then
        entry = map.default
    end
    if type(entry) ~= "table" then
        if kind == "default" or kind == nil or kind == "" then
            return "x", "y"
        end
        return tostring(kind) .. "_x", tostring(kind) .. "_y"
    end
    return tostring(entry.x or "x"), tostring(entry.y or "y")
end

local function tryReadOffset(widget, methodName)
    if widget == nil or type(widget[methodName]) ~= "function" then
        return false, nil, nil
    end
    local ok, x, y = pcall(function()
        return widget[methodName](widget)
    end)
    if not ok then
        return false, nil, nil
    end
    x = tonumber(x)
    y = tonumber(y)
    if x == nil or y == nil then
        return false, nil, nil
    end
    return true, x, y
end

local function readOffset(widget, options)
    if widget == nil then
        return nil, nil
    end

    local cfg = type(options) == "table" and options or {}
    local first = cfg.prefer_effective_offset == true and "GetEffectiveOffset" or "GetOffset"
    local second = first == "GetOffset" and "GetEffectiveOffset" or "GetOffset"

    local ok, x, y = tryReadOffset(widget, first)
    if not ok then
        ok, x, y = tryReadOffset(widget, second)
    end
    if not ok then
        return nil, nil
    end
    return x, y
end

local function clearCursor()
    if type(api) == "table" and type(api.Cursor) == "table" and type(api.Cursor.ClearCursor) == "function" then
        pcall(function()
            api.Cursor:ClearCursor()
        end)
    end
end

local function isShiftAllowed(options)
    local cfg = type(options) == "table" and options or {}
    if cfg.require_shift ~= true then
        return true
    end
    if type(api) ~= "table" or type(api.Input) ~= "table" or type(api.Input.IsShiftKeyDown) ~= "function" then
        return false
    end
    local ok, result = pcall(function()
        return api.Input:IsShiftKeyDown()
    end)
    return ok and result and true or false
end

local function normalizeTargets(window, targets)
    local items = {}
    local seen = {}

    local function add(target)
        if target == nil or seen[target] then
            return
        end
        seen[target] = true
        items[#items + 1] = target
    end

    add(window)
    if type(targets) == "table" then
        for _, target in ipairs(targets) do
            add(target)
        end
    else
        add(targets)
    end

    return items
end

function Positioning.ResolveKeys(kind, mappings)
    return resolveKeys(kind, mappings)
end

function Positioning.ReadOffset(widget, options)
    return readOffset(widget, options)
end

function Positioning.Get(settings, kind, mappings, fallback)
    local xKey, yKey = resolveKeys(kind, mappings)
    fallback = type(fallback) == "table" and fallback or {}
    return {
        x = tonumber(settings ~= nil and settings[xKey] or nil) or tonumber(fallback.x) or 0,
        y = tonumber(settings ~= nil and settings[yKey] or nil) or tonumber(fallback.y) or 0,
        x_key = xKey,
        y_key = yKey
    }
end

function Positioning.Save(settings, kind, x, y, mappings, options)
    if type(settings) ~= "table" then
        return false
    end
    local cfg = type(options) == "table" and options or {}
    local point = Positioning.Get(settings, kind, mappings, cfg.fallback)
    settings[point.x_key] = Runtime.Clamp(x, cfg.min_x, cfg.max_x, point.x)
    settings[point.y_key] = Runtime.Clamp(y, cfg.min_y, cfg.max_y, point.y)
    return true, point
end

function Positioning.SaveFromWidget(settings, kind, widget, mappings, options)
    local x, y = readOffset(widget, options)
    if x == nil or y == nil then
        return false, nil
    end
    return Positioning.Save(settings, kind, x, y, mappings, options)
end

function Positioning.Apply(widget, settings, kind, mappings, options)
    if widget == nil then
        return false
    end
    local cfg = type(options) == "table" and options or {}
    local point = Positioning.Get(settings, kind, mappings, cfg.fallback)
    local anchor = tostring(cfg.anchor or "TOPLEFT")
    local relative = cfg.relative_to
    local targetAnchor = tostring(cfg.target_anchor or anchor)
    pcall(function()
        if cfg.clear_anchors ~= false and widget.RemoveAllAnchors ~= nil then
            widget:RemoveAllAnchors()
        end
    end)
    local ok = pcall(function()
        if relative ~= nil then
            widget:AddAnchor(anchor, relative, targetAnchor, point.x, point.y)
        else
            widget:AddAnchor(anchor, point.x, point.y)
        end
    end)
    return ok and true or false, point
end

function Positioning.BindDrag(window, targets, onStop, options)
    if window == nil then
        return false, {}
    end

    local cfg = type(options) == "table" and options or {}
    local button = tostring(cfg.mouse_button or "LeftButton")
    local dragTargets = normalizeTargets(window, targets)
    local state = {
        dragging = false
    }

    for _, target in ipairs(dragTargets) do
        if target.__nuzi_core_drag_original_start == nil and type(target.OnDragStart) == "function" then
            target.__nuzi_core_drag_original_start = target.OnDragStart
        end
        if target.__nuzi_core_drag_original_stop == nil and type(target.OnDragStop) == "function" then
            target.__nuzi_core_drag_original_stop = target.OnDragStop
        end

        if target.RegisterForDrag ~= nil then
            pcall(function()
                target:RegisterForDrag(button)
            end)
        end
        if target.EnableDrag ~= nil then
            pcall(function()
                target:EnableDrag(true)
            end)
        end
        if target.SetHandler ~= nil then
            target:SetHandler("OnDragStart", function(self, ...)
                if state.dragging or not isShiftAllowed(cfg) then
                    return
                end
                state.dragging = true

                local originalStart = target.__nuzi_core_drag_original_start
                if type(originalStart) == "function" then
                    pcall(originalStart, self, ...)
                elseif window.StartMoving ~= nil then
                    pcall(function()
                        window:StartMoving()
                    end)
                end
                clearCursor()
            end)

            target:SetHandler("OnDragStop", function(self, ...)
                local originalStop = target.__nuzi_core_drag_original_stop
                if not state.dragging then
                    if type(originalStop) == "function" then
                        pcall(originalStop, self, ...)
                    end
                    return
                end

                local beforeX, beforeY = readOffset(window, cfg)
                if type(originalStop) == "function" then
                    pcall(originalStop, self, ...)
                elseif window.StopMovingOrSizing ~= nil then
                    pcall(function()
                        window:StopMovingOrSizing()
                    end)
                elseif self ~= nil and self.StopMovingOrSizing ~= nil then
                    pcall(function()
                        self:StopMovingOrSizing()
                    end)
                end

                state.dragging = false

                local x, y = readOffset(window, cfg)
                if x == nil or y == nil then
                    x, y = beforeX, beforeY
                end

                if x ~= nil and y ~= nil and type(onStop) == "function" then
                    onStop(x, y, window, self, ...)
                end
            end)
        end
    end

    return true, dragTargets
end

function Positioning.BindManagedDrag(window, targets, settingsRef, kind, mappings, options)
    local cfg = type(options) == "table" and options or {}
    return Positioning.BindDrag(window, targets, function(x, y, movedWindow, target, ...)
        local settings = settingsRef
        if type(settingsRef) == "function" then
            settings = settingsRef()
        end
        if type(settings) ~= "table" then
            return
        end
        local ok, point = Positioning.Save(settings, kind, x, y, mappings, cfg)
        if ok and type(cfg.save_settings) == "function" then
            cfg.save_settings(settings, kind, x, y, point, movedWindow, target, ...)
        end
        if ok and type(cfg.after_save) == "function" then
            cfg.after_save(settings, kind, x, y, point, movedWindow, target, ...)
        end
    end, cfg)
end

function Positioning.CreateNamedPositionManager(config)
    local options = type(config) == "table" and config or {}
    local manager = {
        get_settings = options.get_settings,
        save_settings = options.save_settings,
        mappings = options.mappings or {},
        options = options
    }

    function manager:Get(kind, fallback)
        if type(self.get_settings) ~= "function" then
            return Positioning.Get(nil, kind, self.mappings, fallback)
        end
        local settings = self.get_settings()
        return Positioning.Get(settings, kind, self.mappings, fallback)
    end

    function manager:Save(kind, x, y)
        if type(self.get_settings) ~= "function" then
            return false
        end
        local settings = self.get_settings()
        local ok, point = Positioning.Save(settings, kind, x, y, self.mappings, self.options)
        if ok and type(self.save_settings) == "function" then
            self.save_settings(settings, kind, x, y, point)
        end
        return ok, point
    end

    function manager:SaveWidget(kind, widget)
        if type(self.get_settings) ~= "function" then
            return false, nil
        end
        local settings = self.get_settings()
        local ok, point = Positioning.SaveFromWidget(settings, kind, widget, self.mappings, self.options)
        if ok and type(self.save_settings) == "function" then
            self.save_settings(settings, kind, point.x, point.y, point, widget)
        end
        return ok, point
    end

    function manager:Apply(widget, kind, applyOptions)
        local settings = nil
        if type(self.get_settings) == "function" then
            settings = self.get_settings()
        end
        return Positioning.Apply(widget, settings, kind, self.mappings, applyOptions or self.options)
    end

    function manager:BindDrag(window, targets, kind, dragOptions)
        if type(self.get_settings) ~= "function" then
            return false, {}
        end
        local cfg = Runtime.DeepCopy(self.options or {})
        if type(dragOptions) == "table" then
            Runtime.MergeInto(cfg, dragOptions)
        end
        if type(cfg.save_settings) ~= "function" and type(self.save_settings) == "function" then
            cfg.save_settings = function(settings, savedKind, x, y, point, ...)
                self.save_settings(settings, savedKind, x, y, point, ...)
            end
        end
        return Positioning.BindManagedDrag(window, targets, self.get_settings, kind, self.mappings, cfg)
    end

    function manager:ApplyAndBind(widget, targets, kind, applyOptions, dragOptions)
        local applied, point = self:Apply(widget, kind, applyOptions)
        self:BindDrag(widget, targets, kind, dragOptions or applyOptions)
        return applied, point
    end

    return manager
end

return Positioning
