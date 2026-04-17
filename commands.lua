local Commands = {}

local function trim(value)
    local text = tostring(value or "")
    return string.match(text, "^%s*(.-)%s*$") or text
end

function Commands.Trim(value)
    return trim(value)
end

function Commands.ExtractChatPayload(...)
    local values = { ... }
    local payload = {
        args = values,
        message = "",
        sender_name = "",
        sender_unit = ""
    }

    if type(values[5]) == "string" then
        payload.message = values[5]
    elseif type(values[3]) == "string" then
        payload.message = values[3]
    elseif type(values[1]) == "string" then
        payload.message = values[1]
    end

    if type(values[4]) == "string" then
        payload.sender_name = values[4]
    elseif type(values[2]) == "string" then
        payload.sender_name = values[2]
    end

    if type(values[1]) == "string" then
        payload.sender_unit = values[1]
    end

    payload.message = trim(payload.message)
    payload.sender_name = tostring(payload.sender_name or "")
    payload.sender_unit = tostring(payload.sender_unit or "")
    return payload
end

function Commands.Parse(rawMessage)
    local message = trim(rawMessage)
    local command, rest = string.match(message, "^(%S+)%s*(.-)$")
    command = tostring(command or "")
    rest = tostring(rest or "")

    local args = {}
    for token in string.gmatch(rest, "%S+") do
        args[#args + 1] = token
    end

    return {
        raw = message,
        command = command,
        rest = rest,
        args = args,
        subcommand = tostring(args[1] or "")
    }
end

function Commands.IsLocalSender(payload, options)
    local config = type(options) == "table" and options or {}
    if type(config.is_local) == "function" then
        return config.is_local(payload) and true or false
    end

    local senderUnit = tostring(payload ~= nil and payload.sender_unit or "")
    if senderUnit == "player" then
        return true
    end

    local localName = ""
    if type(config.get_player_name) == "function" then
        local ok, value = pcall(config.get_player_name)
        if ok and type(value) == "string" then
            localName = value
        end
    elseif type(config.player_name) == "string" then
        localName = config.player_name
    end

    local senderName = tostring(payload ~= nil and payload.sender_name or "")
    return localName ~= "" and senderName == localName
end

function Commands.CreateRouter(options)
    local config = type(options) == "table" and options or {}
    local router = {
        commands = {},
        aliases = {},
        logger = config.logger,
        get_player_name = config.get_player_name,
        default_local_only = config.local_only ~= false,
        fallback = nil
    }

    function router:Add(command, handler, entryOptions)
        self.commands[tostring(command or "")] = {
            handler = handler,
            options = type(entryOptions) == "table" and entryOptions or {}
        }
    end

    function router:AddAlias(alias, command)
        self.aliases[tostring(alias or "")] = tostring(command or "")
    end

    function router:SetFallback(handler)
        self.fallback = handler
    end

    function router:DispatchPayload(payload)
        local parsed = Commands.Parse(payload.message)
        if parsed.command == "" then
            return false, "empty"
        end

        local resolvedCommand = self.aliases[parsed.command] or parsed.command
        local entry = self.commands[resolvedCommand]
        if entry == nil then
            if type(self.fallback) == "function" then
                return self.fallback({
                    payload = payload,
                    parsed = parsed,
                    router = self
                })
            end
            return false, "unhandled"
        end

        local localOnly = self.default_local_only
        if entry.options.local_only ~= nil then
            localOnly = entry.options.local_only and true or false
        end

        local isLocal = Commands.IsLocalSender(payload, {
            get_player_name = self.get_player_name
        })
        if localOnly and not isLocal then
            return false, "nonlocal"
        end

        local ctx = {
            payload = payload,
            parsed = parsed,
            command = resolvedCommand,
            rest = parsed.rest,
            args = parsed.args,
            subcommand = parsed.subcommand,
            sender_name = payload.sender_name,
            sender_unit = payload.sender_unit,
            is_local = isLocal,
            router = self,
            logger = self.logger
        }

        return entry.handler(ctx)
    end

    function router:DispatchMessage(message, senderName, senderUnit)
        return self:DispatchPayload({
            message = trim(message),
            sender_name = tostring(senderName or ""),
            sender_unit = tostring(senderUnit or "")
        })
    end

    function router:Handle(...)
        return self:DispatchPayload(Commands.ExtractChatPayload(...))
    end

    return router
end

return Commands
