local Runtime = require("nuzi-core/runtime")

local Scheduler = {}

local function resolveInterval(value, fallback)
    local raw = value
    if type(raw) == "function" then
        local ok, result = pcall(raw)
        if ok then
            raw = result
        else
            raw = fallback
        end
    end
    local number = tonumber(raw)
    if number == nil then
        number = tonumber(fallback) or 0
    end
    if number < 0 then
        return 0
    end
    return math.floor(number + 0.5)
end

function Scheduler.CreateTicker(config)
    config = type(config) == "table" and config or {}

    local ticker = {
        elapsed_ms = 0,
        interval_ms = resolveInterval(config.interval_ms, 0),
        max_elapsed_ms = resolveInterval(config.max_elapsed_ms, 0)
    }

    function ticker:Reset()
        self.elapsed_ms = 0
    end

    function ticker:SetInterval(intervalMs)
        self.interval_ms = resolveInterval(intervalMs, self.interval_ms)
    end

    function ticker:GetElapsedMs()
        return self.elapsed_ms
    end

    function ticker:Advance(dt, intervalMs)
        self.elapsed_ms = self.elapsed_ms + Runtime.NormalizeDeltaMs(dt)
        if self.max_elapsed_ms > 0 and self.elapsed_ms > self.max_elapsed_ms then
            self.elapsed_ms = self.max_elapsed_ms
        end

        local resolvedInterval = resolveInterval(intervalMs, self.interval_ms)
        if resolvedInterval <= 0 then
            local elapsed = self.elapsed_ms
            self.elapsed_ms = 0
            return true, elapsed, resolvedInterval
        end

        if self.elapsed_ms < resolvedInterval then
            return false, self.elapsed_ms, resolvedInterval
        end

        local elapsed = self.elapsed_ms
        self.elapsed_ms = 0
        return true, elapsed, resolvedInterval
    end

    function ticker:Run(dt, intervalMs, fn, ...)
        local shouldRun, elapsed, resolvedInterval = self:Advance(dt, intervalMs)
        if not shouldRun then
            return false, elapsed, resolvedInterval
        end
        if type(fn) == "function" then
            return true, elapsed, resolvedInterval, fn(elapsed, ...)
        end
        return true, elapsed, resolvedInterval
    end

    return ticker
end

function Scheduler.CreateMultiLoop(config)
    local options = type(config) == "table" and config or {}
    local multi = {
        loops = {},
        order = {}
    }

    function multi:Add(name, loopConfig)
        local key = tostring(name or "")
        local entry = {
            name = key,
            callback = type(loopConfig) == "table" and loopConfig.callback or nil,
            ticker = Scheduler.CreateTicker(loopConfig)
        }
        if self.loops[key] == nil then
            self.order[#self.order + 1] = key
        end
        self.loops[key] = entry
        return entry
    end

    function multi:Get(name)
        return self.loops[tostring(name or "")]
    end

    function multi:SetInterval(name, intervalMs)
        local loop = self:Get(name)
        if loop ~= nil then
            loop.ticker:SetInterval(intervalMs)
        end
    end

    function multi:Reset(name)
        if name ~= nil then
            local loop = self:Get(name)
            if loop ~= nil then
                loop.ticker:Reset()
            end
            return
        end
        for _, key in ipairs(self.order) do
            local loop = self.loops[key]
            if loop ~= nil then
                loop.ticker:Reset()
            end
        end
    end

    function multi:Tick(dt, context)
        local results = {}
        for _, key in ipairs(self.order) do
            local loop = self.loops[key]
            if loop ~= nil then
                local ran, elapsed, intervalMs = loop.ticker:Advance(dt)
                results[key] = {
                    ran = ran,
                    elapsed_ms = elapsed,
                    interval_ms = intervalMs
                }
                if ran and type(loop.callback) == "function" then
                    loop.callback(elapsed, context, key, self)
                end
            end
        end
        return results
    end

    for key, loopConfig in pairs(options.loops or {}) do
        multi:Add(key, loopConfig)
    end

    return multi
end

return Scheduler
