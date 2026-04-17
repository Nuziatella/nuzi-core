local api = require("api")

local Runtime = {}

function Runtime.Trim(value)
    local text = tostring(value or "")
    return string.match(text, "^%s*(.-)%s*$") or text
end

function Runtime.NormalizePath(path)
    return string.gsub(tostring(path or ""), "\\", "/")
end

function Runtime.IsEmptyTable(value)
    if type(value) ~= "table" then
        return false
    end
    for _ in pairs(value) do
        return false
    end
    return true
end

function Runtime.Clamp(value, minValue, maxValue, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    if minValue ~= nil and number < minValue then
        return minValue
    end
    if maxValue ~= nil and number > maxValue then
        return maxValue
    end
    return number
end

function Runtime.NormalizeDeltaMs(dt)
    local number = tonumber(dt) or 0
    if number < 0 then
        return 0
    end
    if number > 0 and number < 5 then
        number = number * 1000
    end
    return math.floor(number + 0.5)
end

function Runtime.GetUiNowMs()
    if api.Time ~= nil and api.Time.GetUiMsec ~= nil then
        local ok, value = pcall(function()
            return api.Time:GetUiMsec()
        end)
        if ok and value ~= nil then
            return tonumber(value) or 0
        end
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return math.floor(((tonumber(os.clock()) or 0) * 1000) + 0.5)
    end
    return 0
end

function Runtime.DeepCopy(value, visited)
    if type(value) ~= "table" then
        return value
    end
    visited = visited or {}
    if visited[value] ~= nil then
        return visited[value]
    end
    local out = {}
    visited[value] = out
    for key, item in pairs(value) do
        out[Runtime.DeepCopy(key, visited)] = Runtime.DeepCopy(item, visited)
    end
    return out
end

function Runtime.MergeInto(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            Runtime.MergeInto(dst[key], value)
        else
            dst[key] = value
        end
    end
    return dst
end

function Runtime.ApplyDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return false
    end
    local changed = false
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = Runtime.DeepCopy(value)
                changed = true
            elseif Runtime.ApplyDefaults(target[key], value) then
                changed = true
            end
        elseif target[key] == nil then
            target[key] = value
            changed = true
        end
    end
    return changed
end

function Runtime.PruneUnknown(target, defaults, options)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return false
    end
    options = type(options) == "table" and options or {}
    local skipEmptyDefaultTables = options.skip_empty_default_tables == true
    local changed = false
    for key, value in pairs(target) do
        local defaultValue = defaults[key]
        if defaultValue == nil then
            target[key] = nil
            changed = true
        elseif type(value) == "table" and type(defaultValue) == "table" then
            if not (skipEmptyDefaultTables and Runtime.IsEmptyTable(defaultValue)) then
                if Runtime.PruneUnknown(value, defaultValue, options) then
                    changed = true
                end
            end
        end
    end
    return changed
end

function Runtime.IsChoice(order, value)
    local current = tostring(value or "")
    for _, entry in ipairs(order or {}) do
        if tostring(entry) == current then
            return true
        end
    end
    return false
end

function Runtime.CycleChoice(order, current)
    local options = order or {}
    local currentValue = tostring(current or "")
    if #options == 0 then
        return current
    end
    for index, entry in ipairs(options) do
        if tostring(entry) == currentValue then
            local nextIndex = index + 1
            if nextIndex > #options then
                nextIndex = 1
            end
            return options[nextIndex]
        end
    end
    return options[1]
end

function Runtime.GetChoiceLabel(map, key, fallback)
    local value = tostring(key or "")
    if type(map) == "table" and map[value] ~= nil then
        return tostring(map[value])
    end
    return tostring(fallback or value)
end

function Runtime.MakeSignature(values, separator)
    local parts = {}
    for index, value in ipairs(values or {}) do
        parts[index] = tostring(value)
    end
    return table.concat(parts, separator or "|")
end

return Runtime
