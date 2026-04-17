local Require = {}
local nativeRequire = require

local function toCandidateList(...)
    local args = { ... }

    if #args == 1 then
        local first = args[1]
        if type(first) == "table" then
            local list = {}
            for _, candidate in ipairs(first) do
                if type(candidate) == "string" and candidate ~= "" then
                    list[#list + 1] = candidate
                end
            end
            return list
        end
    end

    local list = {}
    for _, candidate in ipairs(args) do
        if type(candidate) == "string" and candidate ~= "" then
            list[#list + 1] = candidate
        end
    end
    return list
end

local function appendError(errors, candidate, detail)
    errors[#errors + 1] = string.format("%s: %s", tostring(candidate), tostring(detail))
end

function Require.Try(...)
    local candidates = toCandidateList(...)
    local errors = {}
    for _, candidate in ipairs(candidates) do
        local ok, mod = pcall(nativeRequire, candidate)
        if ok and mod ~= nil then
            return mod, candidate, errors
        end
        if ok then
            appendError(errors, candidate, "module returned nil")
        else
            appendError(errors, candidate, mod)
        end
    end
    return nil, nil, errors
end

function Require.WithDotFallback(primary, secondary)
    local candidates = {}
    if type(primary) == "string" and primary ~= "" then
        candidates[#candidates + 1] = primary
        if type(secondary) == "string" and secondary ~= "" then
            candidates[#candidates + 1] = secondary
        elseif string.find(primary, "/", 1, true) ~= nil then
            candidates[#candidates + 1] = string.gsub(primary, "/", ".")
        end
    end
    return Require.Try(candidates)
end

function Require.GetAddonCandidates(addonName, moduleName)
    local addon = tostring(addonName or "")
    local name = tostring(moduleName or "")
    if addon == "" or name == "" then
        return {}
    end
    return {
        addon .. "/" .. name,
        addon .. "." .. name
    }
end

function Require.Addon(addonName, moduleName)
    return Require.Try(Require.GetAddonCandidates(addonName, moduleName))
end

function Require.AddonMap(addonName, names)
    local modules = {}
    local failures = {}
    for _, moduleName in ipairs(names or {}) do
        local mod, candidate, errors = Require.Addon(addonName, moduleName)
        modules[moduleName] = mod
        if mod == nil then
            failures[moduleName] = {
                candidate = candidate,
                errors = errors
            }
        end
    end
    return modules, failures
end

function Require.LoadSet(spec, options)
    local config = type(options) == "table" and options or {}
    local modules = {}
    local failures = {}

    for key, value in pairs(spec or {}) do
        local candidates = value
        if type(value) == "string" then
            candidates = { value }
        end
        local mod, candidate, errors = Require.Try(candidates)
        modules[key] = mod
        if mod == nil then
            failures[key] = {
                candidate = candidate,
                errors = errors
            }
            if type(config.logger) == "table" and type(config.logger.Err) == "function" then
                config.logger:Err(
                    tostring(config.label or "module load failed") ..
                    " [" .. tostring(key) .. "]: " ..
                    Require.DescribeErrors(errors)
                )
            end
        end
    end

    return modules, failures
end

function Require.AddonSet(addonName, names, options)
    local spec = {}
    for _, moduleName in ipairs(names or {}) do
        spec[moduleName] = Require.GetAddonCandidates(addonName, moduleName)
    end
    return Require.LoadSet(spec, options)
end

function Require.DescribeErrors(errors)
    if type(errors) ~= "table" or #errors == 0 then
        return ""
    end
    return table.concat(errors, "; ")
end

return Require
