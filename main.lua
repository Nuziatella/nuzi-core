local api = require("api")
local Core = require("nuzi-core/core")

local addon = {
    name = "Nuzi Core",
    author = "Nuzi",
    version = Core.Version or "2.0.4",
    desc = "Shared runtime library for Nuzi addons",
    library = true
}

api._NuziCore = Core

return addon
