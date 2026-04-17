-- Portions of this implementation are based on the original AddonLibrary
-- base64 code by Misosoup and contributors.

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function encode(data)
    local text = tostring(data or "")
    return ((text:gsub(".", function(character)
        local bits = ""
        local byte = character:byte()
        for index = 8, 1, -1 do
            if byte % (2 ^ index) - byte % (2 ^ (index - 1)) > 0 then
                bits = bits .. "1"
            else
                bits = bits .. "0"
            end
        end
        return bits
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(chunk)
        if #chunk < 6 then
            return ""
        end
        local value = 0
        for index = 1, 6 do
            if chunk:sub(index, index) == "1" then
                value = value + 2 ^ (6 - index)
            end
        end
        return alphabet:sub(value + 1, value + 1)
    end) .. ({ "", "==", "=" })[#text % 3 + 1])
end

local function decode(data)
    local sanitized = string.gsub(tostring(data or ""), "[^" .. alphabet .. "=]", "")
    return (sanitized:gsub(".", function(character)
        if character == "=" then
            return ""
        end
        local bits = ""
        local found = (alphabet:find(character, 1, true) or 1) - 1
        for index = 6, 1, -1 do
            if found % (2 ^ index) - found % (2 ^ (index - 1)) > 0 then
                bits = bits .. "1"
            else
                bits = bits .. "0"
            end
        end
        return bits
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(chunk)
        if #chunk ~= 8 then
            return ""
        end
        local value = 0
        for index = 1, 8 do
            if chunk:sub(index, index) == "1" then
                value = value + 2 ^ (8 - index)
            end
        end
        return string.char(value)
    end))
end

return {
    Encode = encode,
    Decode = decode
}
