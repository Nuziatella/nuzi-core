local api = require("api")

if type(api) == "table" and type(api._NuziCore) == "table" then
    return api._NuziCore
end

local Core = {
    Version = "2.0.4"
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

local function installUnitApiGuards(targetApi)
    targetApi = targetApi or api
    if type(targetApi) ~= "table" or type(targetApi.Unit) ~= "table" or targetApi.Unit.__nuzi_core_api_guards == true then
        return
    end

    local unitApi = targetApi.Unit
    local abilityApi = targetApi.Ability
    local originalUnitName = unitApi.UnitName

    local function callOriginal(original, normalized, colonCall, maybeValue, ...)
        if colonCall then
            return original(unitApi, normalized, ...)
        end
        return original(unitApi, normalized, maybeValue, ...)
    end

    local function unitTokenMayExist(unit)
        if unit == "player" then
            return true
        end
        if type(originalUnitName) ~= "function" then
            return true
        end

        local ok, name = pcall(originalUnitName, unitApi, unit)
        return ok and normalizeApiStringArg(name) ~= nil
    end

    local function wrapStringMethod(methodName, invalidReturn, requireLiveUnit)
        local original = unitApi[methodName]
        if type(original) ~= "function" then
            return
        end

        unitApi["__nuzi_core_original_" .. methodName] = original
        unitApi[methodName] = function(selfOrValue, maybeValue, ...)
            local value = maybeValue
            local colonCall = selfOrValue == unitApi
            if not colonCall then
                value = selfOrValue
            end

            local normalized = normalizeApiStringArg(value)
            if normalized == nil then
                return invalidReturn
            end
            if requireLiveUnit and not unitTokenMayExist(normalized) then
                return invalidReturn
            end

            return callOriginal(original, normalized, colonCall, maybeValue, ...)
        end
    end

    wrapStringMethod("GetUnitInfoById", nil)
    wrapStringMethod("GetUnitNameById", "")
    wrapStringMethod("UnitName", "")
    wrapStringMethod("GetUnitName", "")
    wrapStringMethod("GetUnitId", nil, true)
    wrapStringMethod("UnitBuffCount", nil, true)
    wrapStringMethod("UnitBuff", {}, true)
    wrapStringMethod("UnitDeBuffCount", nil, true)
    wrapStringMethod("UnitDeBuff", {}, true)
    wrapStringMethod("UnitHealth", nil, true)
    wrapStringMethod("UnitMaxHealth", nil, true)
    wrapStringMethod("UnitMana", nil, true)
    wrapStringMethod("UnitMaxMana", nil, true)
    wrapStringMethod("UnitInfo", nil, true)
    wrapStringMethod("UnitModifierInfo", nil, true)
    wrapStringMethod("UnitClass", nil, true)
    wrapStringMethod("UnitGearScore", nil, true)
    wrapStringMethod("UnitWorldPosition", nil, true)
    wrapStringMethod("GetUnitScreenNameTagOffset", nil, true)
    if type(abilityApi) == "table" then
        local original = abilityApi.GetUnitClassName
        if type(original) == "function" then
            abilityApi.__nuzi_core_original_GetUnitClassName = original
            abilityApi.GetUnitClassName = function(selfOrValue, maybeValue, ...)
                local value = maybeValue
                local colonCall = selfOrValue == abilityApi
                if not colonCall then
                    value = selfOrValue
                end

                local normalized = normalizeApiStringArg(value)
                if normalized == nil or not unitTokenMayExist(normalized) then
                    return nil
                end
                if colonCall then
                    return original(abilityApi, normalized, ...)
                end
                return original(abilityApi, normalized, maybeValue, ...)
            end
        end
    end
    targetApi.Unit.__nuzi_core_api_guards = true
end

function Core.InstallApiGuards(targetApi)
    installUnitApiGuards(targetApi)
end

Core.InstallApiGuards(api)

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
