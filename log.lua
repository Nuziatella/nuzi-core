local api = require("api")

local Log = {}

local function normalizePrefix(prefix)
    local text = tostring(prefix or "")
    if text == "" then
        return ""
    end
    if string.match(text, "^%[.*%]%s*$") ~= nil then
        return text .. " "
    end
    return "[" .. text .. "] "
end

local function unwrapPrefix(prefix)
    local text = tostring(prefix or "")
    text = string.gsub(text, "%s+$", "")
    local inner = string.match(text, "^%[(.*)%]$")
    if inner ~= nil then
        return inner
    end
    return text
end

local function emit(methodName, message)
    if type(api) ~= "table" or type(api.Log) ~= "table" then
        return
    end
    local method = api.Log[methodName]
    if type(method) ~= "function" then
        return
    end
    pcall(function()
        api.Log[methodName](api.Log, tostring(message or ""))
    end)
end

function Log.Create(options)
    local config = options
    if type(config) ~= "table" then
        config = {
            prefix = options
        }
    end

    local logger = {
        prefix = normalizePrefix(config.prefix or ""),
        debug_enabled = config.debug_enabled == true
    }

    function logger:Format(message)
        return self.prefix .. tostring(message or "")
    end

    function logger:Debug(message)
        if not self.debug_enabled then
            return
        end
        emit("Info", self:Format(message))
    end

    function logger:Info(message)
        emit("Info", self:Format(message))
    end

    function logger:Warn(message)
        if type(api) == "table" and type(api.Log) == "table" and type(api.Log.Warn) == "function" then
            emit("Warn", self:Format(message))
            return
        end
        emit("Info", self:Format(message))
    end

    function logger:Err(message)
        emit("Err", self:Format(message))
    end

    function logger:Try(label, fn, ...)
        local ok, resultA, resultB, resultC, resultD, resultE = pcall(fn, ...)
        if not ok then
            self:Err(tostring(label or "operation failed") .. ": " .. tostring(resultA))
            return false, resultA
        end
        return true, resultA, resultB, resultC, resultD, resultE
    end

    function logger:Wrap(label, fn)
        return function(...)
            local ok, resultA, resultB, resultC, resultD, resultE = self:Try(label, fn, ...)
            if not ok then
                return nil
            end
            return resultA, resultB, resultC, resultD, resultE
        end
    end

    function logger:Child(suffix)
        local childPrefix = unwrapPrefix(self.prefix)
        if suffix ~= nil and suffix ~= "" then
            childPrefix = childPrefix .. "/" .. tostring(suffix)
        end
        return Log.Create({
            prefix = childPrefix,
            debug_enabled = self.debug_enabled
        })
    end

    return logger
end

return Log
