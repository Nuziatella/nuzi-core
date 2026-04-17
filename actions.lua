local Runtime = require("nuzi-core/runtime")
local Positioning = require("nuzi-core/ui/positioning")

local Actions = {}

local function call(fn, ...)
    if type(fn) == "function" then
        return fn(...)
    end
    return nil
end

local function resolveSettings(getSettings, ...)
    if type(getSettings) ~= "function" then
        return nil
    end
    return getSettings(...)
end

function Actions.CreateToggle(config)
    local options = type(config) == "table" and config or {}
    return function(...)
        local settings = resolveSettings(options.get_settings, ...)
        if type(settings) ~= "table" then
            return nil
        end
        local key = tostring(options.key or "")
        local value = not (settings[key] and true or false)
        settings[key] = value
        call(options.before_save, settings, value, ...)
        call(options.save, settings, key, value, ...)
        call(options.after, settings, value, ...)
        return value, settings
    end
end

function Actions.CreateClampedNumberSetter(config)
    local options = type(config) == "table" and config or {}
    return function(rawValue, ...)
        local settings = resolveSettings(options.get_settings, ...)
        if type(settings) ~= "table" then
            return nil
        end
        local key = tostring(options.key or "")
        local value = Runtime.Clamp(rawValue, options.min, options.max, settings[key] or options.fallback)
        if options.round ~= false then
            value = math.floor((tonumber(value) or 0) + 0.5)
        end
        if options.skip_if_unchanged and settings[key] == value then
            return value, false
        end
        settings[key] = value
        call(options.before_save, settings, value, rawValue, ...)
        call(options.save, settings, key, value, ...)
        call(options.after, settings, value, rawValue, ...)
        return value, true
    end
end

function Actions.CreateChoiceCycler(config)
    local options = type(config) == "table" and config or {}
    return function(...)
        local settings = resolveSettings(options.get_settings, ...)
        if type(settings) ~= "table" then
            return nil
        end
        local key = tostring(options.key or "")
        local value = Runtime.CycleChoice(options.order or {}, settings[key])
        settings[key] = value
        call(options.before_save, settings, value, ...)
        call(options.save, settings, key, value, ...)
        call(options.after, settings, value, ...)
        return value
    end
end

function Actions.CreateNamedPositionSaver(config)
    local manager = Positioning.CreateNamedPositionManager(config)
    return function(kind, x, y)
        return manager:Save(kind, x, y)
    end
end

return Actions
