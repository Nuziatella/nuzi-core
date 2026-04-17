local api = require("api")

local Events = {}

local function noop()
end

Events.Noop = noop

local function logError(logger, message)
    if type(logger) == "table" and type(logger.Err) == "function" then
        logger:Err(message)
    end
end

function Events.Create(options)
    local config = type(options) == "table" and options or {}
    local registry = {
        api = config.api or api,
        logger = config.logger,
        bindings = {}
    }

    function registry:On(eventName, handler)
        self.api.On(eventName, handler)
        self.bindings[eventName] = handler
        return handler
    end

    function registry:OnSafe(eventName, label, handler)
        local wrapped = function(...)
            local ok, err = pcall(handler, ...)
            if not ok then
                logError(self.logger, tostring(label or eventName) .. ": " .. tostring(err))
            end
        end
        self:On(eventName, wrapped)
        return wrapped
    end

    function registry:OptionalOn(eventName, handler)
        local ok, err = pcall(function()
            self:On(eventName, handler)
        end)
        if not ok then
            logError(self.logger, "Optional event registration failed for " .. tostring(eventName) .. ": " .. tostring(err))
        end
        return ok and true or false, err
    end

    function registry:OptionalOnSafe(eventName, label, handler)
        local ok, err = pcall(function()
            self:OnSafe(eventName, label, handler)
        end)
        if not ok then
            logError(self.logger, "Optional event registration failed for " .. tostring(eventName) .. ": " .. tostring(err))
        end
        return ok and true or false, err
    end

    function registry:OnAll(map)
        for eventName, handler in pairs(map or {}) do
            self:On(eventName, handler)
        end
    end

    function registry:Off(eventName)
        local ok, err = pcall(function()
            self.api.On(eventName, noop)
        end)
        if ok then
            self.bindings[eventName] = nil
        else
            logError(self.logger, "Failed to clear event " .. tostring(eventName) .. ": " .. tostring(err))
        end
        return ok and true or false, err
    end

    function registry:ClearAll()
        local names = {}
        for eventName in pairs(self.bindings) do
            names[#names + 1] = eventName
        end
        for _, eventName in ipairs(names) do
            self:Off(eventName)
        end
    end

    return registry
end

return Events
