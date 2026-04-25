local api = require("api")

local Events = {}

local function noop()
end

Events.Noop = noop

Events.GlobalEvents = {
    UPDATE = true,
    CHAT_MESSAGE = true,
    TEAM_MEMBERS_CHANGED = true,
    UI_RELOADED = true,
    UPDATE_PING_INFO = true,
    raid_role_changed = true,
    ShowPopUp = true
}

Events.BlockedPrivateEvents = {
    HOUSE_TAX_INFO = true,
    UNIT_ENTERED_SIGHT = true,
    UNIT_LEAVED_SIGHT = true
}

local function logError(logger, message)
    if type(logger) == "table" and type(logger.Err) == "function" then
        logger:Err(message)
    end
end

local function createHandlerList()
    return {
        __count = 0,
        __dispatch_depth = 0,
        __dirty = false
    }
end

local function handlerCount(handlers)
    if type(handlers) ~= "table" then
        return 0
    end
    return tonumber(handlers.__count) or #handlers
end

local function addHandler(handlers, handler)
    local count = handlerCount(handlers) + 1
    handlers[count] = handler
    handlers.__count = count
    return handler
end

local function compactHandlers(handlers)
    local count = handlerCount(handlers)
    local writeIndex = 1
    for readIndex = 1, count do
        local handler = handlers[readIndex]
        if handler ~= nil then
            handlers[writeIndex] = handler
            if writeIndex ~= readIndex then
                handlers[readIndex] = nil
            end
            writeIndex = writeIndex + 1
        end
    end
    for index = writeIndex, count do
        handlers[index] = nil
    end
    handlers.__count = writeIndex - 1
    handlers.__dirty = false
end

local function dispatchHandlers(handlers, ...)
    local count = handlerCount(handlers)
    if count == 0 then
        return
    end
    handlers.__dispatch_depth = (tonumber(handlers.__dispatch_depth) or 0) + 1
    for i = 1, count do
        local handler = handlers[i]
        if handler ~= nil then
            handler(...)
        end
    end
    handlers.__dispatch_depth = handlers.__dispatch_depth - 1
    if handlers.__dispatch_depth <= 0 then
        handlers.__dispatch_depth = 0
        if handlers.__dirty then
            compactHandlers(handlers)
        end
    end
end

local function removeHandler(handlers, handler)
    if type(handlers) ~= "table" then
        return
    end
    local count = handlerCount(handlers)
    if handler == nil then
        for i = count, 1, -1 do
            handlers[i] = nil
        end
        handlers.__count = 0
        handlers.__dirty = false
        return
    end
    if (tonumber(handlers.__dispatch_depth) or 0) > 0 then
        for i = count, 1, -1 do
            if handlers[i] == handler then
                handlers[i] = nil
                handlers.__dirty = true
            end
        end
        return
    end
    for i = count, 1, -1 do
        if handlers[i] == handler then
            table.remove(handlers, i)
            count = count - 1
        end
    end
    handlers.__count = count
end

function Events.IsGlobalEvent(eventName)
    return Events.GlobalEvents[tostring(eventName or "")] == true
end

function Events.IsBlockedPrivateEvent(eventName)
    return Events.BlockedPrivateEvents[tostring(eventName or "")] == true
end

function Events.Create(options)
    local config = type(options) == "table" and options or {}
    local registry = {
        api = config.api or api,
        logger = config.logger,
        bindings = {},
        dispatchers = {}
    }

    function registry:EnsureDispatcher(eventName)
        if self.dispatchers[eventName] ~= nil then
            return
        end
        local token = {}
        local dispatcher = function(...)
            if self.dispatchers[eventName] ~= token then
                return
            end
            dispatchHandlers(self.bindings[eventName], ...)
        end
        self.api.On(eventName, dispatcher)
        self.dispatchers[eventName] = token
    end

    function registry:On(eventName, handler)
        if type(handler) ~= "function" then
            error("event handler must be a function")
        end
        self:EnsureDispatcher(eventName)
        if self.bindings[eventName] == nil then
            self.bindings[eventName] = createHandlerList()
        end
        return addHandler(self.bindings[eventName], handler)
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

    function registry:Off(eventName, handler)
        local handlers = self.bindings[eventName]
        if handlers == nil then
            return true
        end
        removeHandler(handlers, handler)
        if handler == nil or handlerCount(handlers) == 0 then
            self.bindings[eventName] = nil
        end
        return true
    end

    function registry:ClearAll()
        self.bindings = {}
        self.dispatchers = {}
    end

    return registry
end

function Events.CreateEventWindow(options)
    local config = type(options) == "table" and options or {}
    local registry = {
        api = config.api or api,
        logger = config.logger,
        id = config.id,
        window = nil,
        handlers = {},
        registered = {}
    }

    function registry:EnsureWindow()
        if self.window ~= nil then
            return self.window
        end
        if type(self.id) ~= "string" or self.id == "" then
            error("event window id is required")
        end
        if self.api.Interface == nil or type(self.api.Interface.CreateEmptyWindow) ~= "function" then
            error("api.Interface:CreateEmptyWindow is unavailable")
        end
        local window = self.api.Interface:CreateEmptyWindow(self.id)
        if window == nil then
            error("failed to create event window " .. tostring(self.id))
        end
        if type(window.Show) == "function" then
            window:Show(false)
        end
        window:SetHandler("OnEvent", function(_, eventName, ...)
            dispatchHandlers(self.handlers[eventName], ...)
        end)
        self.window = window
        return self.window
    end

    function registry:On(eventName, handler)
        if type(handler) ~= "function" then
            error("event handler must be a function")
        end
        if Events.IsBlockedPrivateEvent(eventName) then
            local err = "client blocks private event registration for " .. tostring(eventName)
            logError(self.logger, err)
            return nil, err
        end
        local window = self:EnsureWindow()
        if self.handlers[eventName] == nil then
            self.handlers[eventName] = createHandlerList()
        end
        addHandler(self.handlers[eventName], handler)
        if self.registered[eventName] ~= true then
            local ok, err = pcall(function()
                window:RegisterEvent(eventName)
            end)
            if not ok then
                removeHandler(self.handlers[eventName], handler)
                if handlerCount(self.handlers[eventName]) == 0 then
                    self.handlers[eventName] = nil
                end
                err = tostring(err or "unknown error")
                logError(self.logger, "private event registration failed for " .. tostring(eventName) .. ": " .. err)
                return nil, err
            end
            self.registered[eventName] = true
        end
        return handler
    end

    function registry:OnSafe(eventName, label, handler)
        local wrapped = function(...)
            local ok, err = pcall(handler, ...)
            if not ok then
                logError(self.logger, tostring(label or eventName) .. ": " .. tostring(err))
            end
        end
        local registered, err = self:On(eventName, wrapped)
        if registered == nil then
            return nil, err
        end
        return wrapped
    end

    function registry:OptionalOn(eventName, handler)
        local registered = nil
        local registerErr = nil
        local ok, pcallErr = pcall(function()
            registered, registerErr = self:On(eventName, handler)
        end)
        if not ok or registered == nil then
            local err = ok and registerErr or pcallErr
            logError(self.logger, "Optional event registration failed for " .. tostring(eventName) .. ": " .. tostring(err))
            if ok then
                return false, registerErr
            end
            return false, pcallErr
        end
        return true, nil
    end

    function registry:OptionalOnSafe(eventName, label, handler)
        local registered = nil
        local registerErr = nil
        local ok, pcallErr = pcall(function()
            registered, registerErr = self:OnSafe(eventName, label, handler)
        end)
        if not ok or registered == nil then
            local err = ok and registerErr or pcallErr
            logError(self.logger, "Optional event registration failed for " .. tostring(eventName) .. ": " .. tostring(err))
            if ok then
                return false, registerErr
            end
            return false, pcallErr
        end
        return true, nil
    end

    function registry:Off(eventName, handler)
        local handlers = self.handlers[eventName]
        if handlers == nil then
            return true
        end
        removeHandler(handlers, handler)
        if handler == nil or handlerCount(handlers) == 0 then
            self.handlers[eventName] = nil
        end
        return true
    end

    function registry:ClearAll()
        self.handlers = {}
        self.registered = {}
        if self.window ~= nil then
            if type(self.window.Show) == "function" then
                self.window:Show(false)
            end
            if self.api.Interface ~= nil and type(self.api.Interface.Free) == "function" then
                self.window = self.api.Interface:Free(self.window)
            else
                self.window = nil
            end
        end
    end

    return registry
end

return Events
