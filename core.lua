local api = require("api")

if type(api) == "table" and type(api._NuziCore) == "table" then
    return api._NuziCore
end

local Core = {
    Version = "2.0.0"
}

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
