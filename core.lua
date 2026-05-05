local api = require("api")

if type(api) == "table" and type(api._NuziCore) == "table" then
    return api._NuziCore
end

local Core = {
    Version = "2.0.1"
}

local function normalizeApiStringArg(value)
    local valueType = type(value)
    if valueType == "string" then
        local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" and text ~= "0" then
            return text
        end
    elseif valueType == "number" and value ~= 0 then
        return tostring(value)
    end
    return nil
end

local function installUnitApiGuards()
    if type(api) ~= "table" or type(api.Unit) ~= "table" or api.Unit.__nuzi_core_api_guards == true then
        return
    end

    local unitApi = api.Unit
    local function wrapStringMethod(methodName, invalidReturn)
        local original = unitApi[methodName]
        if type(original) ~= "function" then
            return
        end

        unitApi["__nuzi_core_original_" .. methodName] = original
        unitApi[methodName] = function(selfOrValue, maybeValue, ...)
            local value = maybeValue
            if selfOrValue ~= unitApi then
                value = selfOrValue
            end

            local normalized = normalizeApiStringArg(value)
            if normalized == nil then
                return invalidReturn
            end

            return original(unitApi, normalized, ...)
        end
    end

    wrapStringMethod("GetUnitInfoById", nil)
    wrapStringMethod("GetUnitNameById", "")
    wrapStringMethod("UnitName", "")
    wrapStringMethod("GetUnitName", "")
    api.Unit.__nuzi_core_api_guards = true
end

installUnitApiGuards()

Core.Require = require("nuzi-core/require")
Core.Runtime = require("nuzi-core/runtime")
Core.Log = require("nuzi-core/log")
Core.Events = require("nuzi-core/events")
Core.Commands = require("nuzi-core/commands")
Core.Render = require("nuzi-core/render")
Core.Actions = require("nuzi-core/actions")
Core.Settings = require("nuzi-core/settings")
Core.Scheduler = require("nuzi-core/scheduler")
Core.UI = require("nuzi-core/ui/_components")
Core.Util = require("nuzi-core/util/_components")
Core.LegacyLibrary = {
    UI = Core.UI,
    Util = Core.Util
}

return Core
