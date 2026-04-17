local Runtime = require("nuzi-core/runtime")

local Render = {}

function Render.BuildSignature(values, separator)
    return Runtime.MakeSignature(values, separator or "|")
end

function Render.CreateSignatureGate()
    local gate = {
        last_signature = nil
    }

    function gate:Reset()
        self.last_signature = nil
    end

    function gate:Get()
        return self.last_signature
    end

    function gate:ShouldRender(signature)
        local current = tostring(signature or "")
        if current == self.last_signature then
            return false
        end
        self.last_signature = current
        return true
    end

    function gate:Run(signature, fn, ...)
        if not self:ShouldRender(signature) then
            return false
        end
        if type(fn) == "function" then
            return true, fn(...)
        end
        return true
    end

    return gate
end

return Render
