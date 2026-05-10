local api = require("api")
local Runtime = require("nuzi-core/runtime")

local Settings = {}

local detectedAddonsBasePath = false

local function resolveAddonsBasePath()
    if detectedAddonsBasePath ~= false then
        return detectedAddonsBasePath
    end

    local resolved = nil
    pcall(function()
        if type(api) == "table" and type(api.baseDir) == "string" and api.baseDir ~= "" then
            resolved = Runtime.NormalizePath(api.baseDir)
            return
        end
        if type(debug) == "table" and type(debug.getinfo) == "function" then
            local info = debug.getinfo(1, "S")
            local source = type(info) == "table" and tostring(info.source or "") or ""
            if string.sub(source, 1, 1) == "@" then
                source = string.sub(source, 2)
            end
            source = Runtime.NormalizePath(source)
            local folder = string.match(source, "^(.*)/[^/]+$")
            if folder ~= nil then
                local base = string.match(folder, "^(.*)/[^/]+$")
                if base ~= nil and base ~= "" then
                    resolved = base
                end
            end
        end
    end)

    detectedAddonsBasePath = resolved
    return detectedAddonsBasePath
end

local function normalizeMode(mode)
    local value = tostring(mode or "serialized_then_flat")
    if value == "serialized" or value == "flat" or value == "flat_then_serialized" or value == "serialized_then_flat" then
        return value
    end
    return "serialized_then_flat"
end

local function parseScalar(rawValue)
    local value = Runtime.Trim(rawValue)
    if value == "" then
        return nil
    end
    if value == "true" then
        return true
    end
    if value == "false" then
        return false
    end
    local quoted = string.match(value, '^"(.*)"$')
    if quoted ~= nil then
        quoted = string.gsub(quoted, "\\\\", "\\")
        quoted = string.gsub(quoted, '\\"', '"')
        return quoted
    end
    return tonumber(value)
end

local function encodeScalar(value)
    local valueType = type(value)
    if valueType == "boolean" then
        return value and "true" or "false"
    end
    if valueType == "number" then
        return tostring(value)
    end
    if valueType == "string" then
        local escaped = string.gsub(value, "\\", "\\\\")
        escaped = string.gsub(escaped, '"', '\\"')
        return '"' .. escaped .. '"'
    end
    return nil
end

local function normalizeStringList(values)
    local list = {}
    local seen = {}
    for _, value in ipairs(values or {}) do
        local text = tostring(value or "")
        if text ~= "" and not seen[text] then
            seen[text] = true
            list[#list + 1] = text
        end
    end
    return list
end

local function tableHasEntries(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for _ in pairs(tbl) do
        return true
    end
    return false
end

local function parseFlatTableText(raw)
    if type(raw) ~= "string" then
        return nil
    end

    local text = Runtime.Trim(raw)
    if text == "" then
        return nil
    end

    -- Only treat legacy scalar key/value files as flat text.
    -- Nested tables should fall through to the chunk parser.
    if string.match(text, "=%s*{") ~= nil then
        return nil
    end

    local output = {}
    for key, rawValue in string.gmatch(text, "([%a_][%w_]*)%s*=%s*([^,\r\n}]+)") do
        local parsed = parseScalar(rawValue)
        if parsed ~= nil then
            output[key] = parsed
        end
    end

    if tableHasEntries(output) then
        return output
    end
    return nil
end

local function getApiSettings(addonId)
    local normalizedId = tostring(addonId or "")
    if normalizedId == "" then
        return nil
    end

    if type(api) == "table" and type(api.GetSettings) == "function" then
        local ok, candidate = pcall(api.GetSettings, normalizedId)
        if ok and type(candidate) == "table" then
            return candidate
        end
    end

    if type(api) == "table" and type(api.File) == "table" and type(api.File.GetSettings) == "function" then
        local ok, candidate = pcall(function()
            return api.File:GetSettings(normalizedId)
        end)
        if ok and type(candidate) == "table" then
            return candidate
        end
    end

    return nil
end

local function saveApiSettings()
    if type(api) == "table" and type(api.SaveSettings) == "function" then
        local ok = pcall(api.SaveSettings)
        if ok then
            return true
        end
    end

    if type(api) == "table" and type(api.File) == "table" and type(api.File.SaveSettings) == "function" then
        local ok = pcall(function()
            api.File:SaveSettings()
        end)
        if ok then
            return true
        end
    end

    return false
end

local function readRawFileFallback(path)
    if type(io) ~= "table" or type(io.open) ~= "function" then
        return nil, false, false
    end

    for _, fullPath in ipairs(Settings.GetFullPathCandidates(path)) do
        local file = nil
        local ok = pcall(function()
            file = io.open(fullPath, "rb")
        end)
        if ok and file ~= nil then
            local contents = nil
            pcall(function()
                contents = file:read("*a")
            end)
            pcall(function()
                file:close()
            end)
            if type(contents) == "string" and contents ~= "" then
                return contents, true, true
            end
            return nil, true, true
        end
    end

    return nil, false, true
end

function Settings.ParseTableText(raw)
    if type(raw) ~= "string" then
        return nil, "not a string"
    end

    local text = Runtime.Trim(raw)
    if text == "" then
        return nil, "empty settings text"
    end

    local flatParsed = parseFlatTableText(text)
    if type(flatParsed) == "table" then
        return flatParsed, ""
    end

    local sourceText = text
    if string.match(sourceText, "^return[%s{]") == nil then
        sourceText = "return " .. sourceText
    end

    local chunk = nil
    local err = nil
    if type(load) == "function" then
        if type(setfenv) == "function" and type(loadstring) == "function" then
            chunk, err = loadstring(sourceText, "=(nuzi-core settings)")
            if chunk ~= nil then
                pcall(function()
                    setfenv(chunk, {})
                end)
            end
        else
            chunk, err = load(sourceText, "=(nuzi-core settings)", "t", {})
        end
    elseif type(loadstring) == "function" then
        chunk, err = loadstring(sourceText, "=(nuzi-core settings)")
        if chunk ~= nil and type(setfenv) == "function" then
            pcall(function()
                setfenv(chunk, {})
            end)
        end
    else
        return nil, "no Lua loader available"
    end

    if chunk == nil then
        return nil, tostring(err or "failed to compile settings text")
    end

    local ok, parsed = pcall(chunk)
    if not ok then
        return nil, tostring(parsed)
    end
    if type(parsed) ~= "table" then
        return nil, "settings text did not evaluate to a table"
    end
    return parsed, ""
end

function Settings.ReadFlexibleTable(path, options)
    local config = type(options) == "table" and options or {}
    local mode = normalizeMode(config.mode)

    if mode ~= "serialized" then
        local tableValue = Settings.ReadTable(path, mode)
        if type(tableValue) == "table" then
            return tableValue, "file:table", ""
        end
    end

    if api.File == nil or api.File.Read == nil then
        if config.raw_text_fallback == true then
            local raw, exists, probed = readRawFileFallback(path)
            if type(raw) == "string" then
                local parsed, parseErr = Settings.ParseTableText(raw)
                if type(parsed) == "table" then
                    return parsed, "file:raw_table", ""
                end
                return nil, "file:legacy_text", tostring(parseErr or "failed to parse raw settings text")
            end
            if probed and exists then
                return nil, "file:unreadable", ""
            end
            if probed then
                return nil, "file:missing", ""
            end
        end
        return nil, "file:unavailable", ""
    end

    local ok, result = pcall(function()
        return api.File:Read(path)
    end)
    if not ok then
        return nil, "file:read_error", tostring(result)
    end
    if type(result) == "table" then
        return result, "file:table", ""
    end
    if type(result) == "string" then
        local parsed, parseErr = Settings.ParseTableText(result)
        if type(parsed) == "table" then
            return parsed, "file:string_table", ""
        end
        return nil, "file:string", tostring(parseErr or "string settings are unsupported")
    end
    if result == nil and config.raw_text_fallback == true then
        local raw, exists, probed = readRawFileFallback(path)
        if type(raw) == "string" then
            local parsed, parseErr = Settings.ParseTableText(raw)
            if type(parsed) == "table" then
                return parsed, "file:raw_table", ""
            end
            return nil, "file:legacy_text", tostring(parseErr or "failed to parse raw settings text")
        end
        if probed and exists then
            return nil, "file:unreadable", ""
        end
        if probed then
            return nil, "file:missing", ""
        end
    end
    if result == nil then
        return nil, "file:nil", ""
    end
    return nil, "file:unknown_type", ""
end

function Settings.TryReadFlexibleCandidates(paths, options)
    for _, path in ipairs(paths or {}) do
        local parsed, source, err = Settings.ReadFlexibleTable(path, options)
        if type(parsed) == "table" then
            return parsed, path, source, err
        end
    end
    return nil, nil, "", ""
end

function Settings.ScoreTableTree(value, seen)
    if type(value) ~= "table" then
        if value == nil then
            return 0
        end
        return 1
    end

    seen = seen or {}
    if seen[value] then
        return 0
    end
    seen[value] = true

    local score = 1
    for key, item in pairs(value) do
        score = score + 1
        score = score + Settings.ScoreTableTree(key, seen)
        score = score + Settings.ScoreTableTree(item, seen)
    end
    return score
end

function Settings.CountTableEntries(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function Settings.ShouldPreferTable(primary, candidate, options)
    if type(primary) ~= "table" or type(candidate) ~= "table" then
        return false, ""
    end
    local config = type(options) == "table" and options or {}
    local primaryScore = Settings.ScoreTableTree(primary)
    local candidateScore = Settings.ScoreTableTree(candidate)
    local primaryBonus = 0
    local candidateBonus = 0

    for _, fieldPath in ipairs(config.bonus_paths or {}) do
        local currentPrimary = primary
        local currentCandidate = candidate
        for segment in string.gmatch(tostring(fieldPath), "[^%.]+") do
            currentPrimary = type(currentPrimary) == "table" and currentPrimary[segment] or nil
            currentCandidate = type(currentCandidate) == "table" and currentCandidate[segment] or nil
        end
        primaryBonus = primaryBonus + Settings.CountTableEntries(currentPrimary)
        candidateBonus = candidateBonus + Settings.CountTableEntries(currentCandidate)
    end

    local thresholdAbsolute = tonumber(config.min_score_delta) or 40
    local thresholdRatio = tonumber(config.min_score_ratio) or 1.35
    if candidateScore >= math.max(primaryScore + thresholdAbsolute, math.floor(primaryScore * thresholdRatio)) then
        return true, string.format("candidate snapshot is richer (%d > %d)", candidateScore, primaryScore)
    end

    if candidateBonus > primaryBonus then
        local bonusAbsolute = tonumber(config.bonus_min_score_delta) or 20
        local bonusRatio = tonumber(config.bonus_min_score_ratio) or 1.10
        if candidateScore >= math.max(primaryScore + bonusAbsolute, math.floor(primaryScore * bonusRatio)) then
            return true, string.format("candidate preserved more keyed entries (%d > %d)", candidateBonus, primaryBonus)
        end
    end

    return false, ""
end

function Settings.ResolveAddonsBasePath()
    return resolveAddonsBasePath()
end

function Settings.GetFullPath(path)
    local base = resolveAddonsBasePath()
    if base == nil or base == "" then
        return nil
    end
    return string.gsub(tostring(base) .. "/" .. tostring(path or ""), "/+", "/")
end

function Settings.GetFullPathCandidates(path)
    local rawPath = Runtime.NormalizePath(path)
    local candidates = {}
    local seen = {}

    local function add(candidate)
        if type(candidate) ~= "string" or candidate == "" then
            return
        end
        local normalized = string.gsub(candidate, "/+", "/")
        if seen[normalized] then
            return
        end
        seen[normalized] = true
        candidates[#candidates + 1] = normalized
    end

    add(Settings.GetFullPath(rawPath))
    add(rawPath)

    local addonFolder = string.match(rawPath, "^([^/]+)/")
    local base = resolveAddonsBasePath()
    if addonFolder ~= nil and type(base) == "string" then
        local lowerBase = string.lower(tostring(base))
        local lowerFolder = "/" .. string.lower(addonFolder)
        if string.sub(lowerBase, -string.len(lowerFolder)) == lowerFolder then
            local stripped = string.gsub(rawPath, "^" .. addonFolder .. "/?", "")
            add(tostring(base) .. "/" .. stripped)
        end
    end

    return candidates
end

function Settings.ReadSerialized(path)
    if api.File == nil or api.File.Read == nil then
        return nil
    end
    local ok, value = pcall(function()
        return api.File:Read(path)
    end)
    if ok and type(value) == "table" then
        return value
    end
    return nil
end

function Settings.WriteSerialized(path, value)
    if api.File == nil or api.File.Write == nil or type(value) ~= "table" then
        return false
    end
    local ok = pcall(function()
        api.File:Write(path, value)
    end)
    return ok and true or false
end

function Settings.ReadFlat(path)
    if type(io) ~= "table" or type(io.open) ~= "function" then
        return nil
    end

    for _, fullPath in ipairs(Settings.GetFullPathCandidates(path)) do
        local file = nil
        local ok = pcall(function()
            file = io.open(fullPath, "rb")
        end)
        if ok and file ~= nil then
            local contents = nil
            pcall(function()
                contents = file:read("*a")
            end)
            pcall(function()
                file:close()
            end)
            if type(contents) == "string" and contents ~= "" then
                local parsed = parseFlatTableText(contents)
                if type(parsed) == "table" then
                    return parsed
                end
            end
        end
    end

    return nil
end

function Settings.WriteFlat(path, value)
    if type(value) ~= "table" or type(io) ~= "table" or type(io.open) ~= "function" then
        return false
    end

    local keys = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" then
            return false
        end
        if encodeScalar(item) == nil then
            return false
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)

    local lines = { "{" }
    for _, key in ipairs(keys) do
        lines[#lines + 1] = "    " .. tostring(key) .. " = " .. encodeScalar(value[key]) .. ","
    end
    lines[#lines + 1] = "}"
    local payload = table.concat(lines, "\n")

    for _, fullPath in ipairs(Settings.GetFullPathCandidates(path)) do
        local file = nil
        local ok = pcall(function()
            file = io.open(fullPath, "wb")
        end)
        if ok and file ~= nil then
            local writeOk = pcall(function()
                file:write(payload)
            end)
            pcall(function()
                file:close()
            end)
            if writeOk then
                return true
            end
        end
    end

    return false
end

function Settings.ReadTable(path, mode)
    local normalizedMode = normalizeMode(mode)
    if normalizedMode == "flat" then
        return Settings.ReadFlat(path)
    end
    if normalizedMode == "serialized" then
        return Settings.ReadSerialized(path)
    end
    if normalizedMode == "flat_then_serialized" then
        local flatValue = Settings.ReadFlat(path)
        if type(flatValue) == "table" then
            return flatValue
        end
        return Settings.ReadSerialized(path)
    end

    local serializedValue = Settings.ReadSerialized(path)
    if type(serializedValue) == "table" then
        return serializedValue
    end
    return Settings.ReadFlat(path)
end

function Settings.WriteTable(path, value, mode)
    local normalizedMode = normalizeMode(mode)
    local flatSaved = false
    local serializedSaved = false

    if normalizedMode == "flat" then
        flatSaved = Settings.WriteFlat(path, value)
        return flatSaved, {
            mode = normalizedMode,
            flat = flatSaved,
            serialized = false
        }
    end

    if normalizedMode == "serialized" then
        serializedSaved = Settings.WriteSerialized(path, value)
        return serializedSaved, {
            mode = normalizedMode,
            flat = false,
            serialized = serializedSaved
        }
    end

    if normalizedMode == "flat_then_serialized" then
        flatSaved = Settings.WriteFlat(path, value)
        serializedSaved = Settings.WriteSerialized(path, value)
    else
        serializedSaved = Settings.WriteSerialized(path, value)
        flatSaved = Settings.WriteFlat(path, value)
    end

    return flatSaved or serializedSaved, {
        mode = normalizedMode,
        flat = flatSaved,
        serialized = serializedSaved
    }
end

function Settings.HasTableFile(path)
    if type(Settings.ReadSerialized(path)) == "table" then
        return true
    end
    if type(Settings.ReadFlat(path)) == "table" then
        return true
    end
    return false
end

local function buildPathEntries(primaryPath, legacyPath, fallbackPaths)
    local entries = {}
    if type(primaryPath) == "string" and primaryPath ~= "" then
        entries[#entries + 1] = {
            kind = "primary",
            path = primaryPath
        }
    end
    if type(legacyPath) == "string" and legacyPath ~= "" and legacyPath ~= primaryPath then
        entries[#entries + 1] = {
            kind = "legacy",
            path = legacyPath
        }
    end
    for _, path in ipairs(normalizeStringList(fallbackPaths)) do
        if path ~= primaryPath and path ~= legacyPath then
            entries[#entries + 1] = {
                kind = "fallback",
                path = path
            }
        end
    end
    return entries
end

local function readFirstAvailable(pathEntries, options)
    local config = type(options) == "table" and options or {}
    for _, entry in ipairs(pathEntries) do
        local parsed, source, err = Settings.ReadFlexibleTable(entry.path, config)
        if type(parsed) == "table" then
            return parsed, {
                source_path = entry.path,
                source_kind = entry.kind,
                source = source,
                last_error = err,
                migrated = entry.kind ~= "primary"
            }
        end
    end
    return nil, {
        source_path = nil,
        source_kind = "none",
        source = "",
        last_error = "",
        migrated = false
    }
end

local function logError(prefix, err)
    if api.Log ~= nil and api.Log.Err ~= nil then
        pcall(function()
            api.Log:Err(prefix .. tostring(err))
        end)
    end
end

function Settings.CreateStore(options)
    local config = Runtime.DeepCopy(options or {})
    local store = {
        options = config,
        defaults = Runtime.DeepCopy(config.defaults or {}),
        settings = nil,
        last_meta = nil
    }

    function store:GetPrimaryPath()
        return tostring(self.options.settings_file_path or "")
    end

    function store:GetLegacyPath()
        return tostring(self.options.legacy_settings_file_path or "")
    end

    function store:GetPaths()
        return {
            primary = self:GetPrimaryPath(),
            legacy = self:GetLegacyPath()
        }
    end

    function store:GetLastMeta()
        return self.last_meta
    end

    function store:Reset()
        self.settings = Runtime.DeepCopy(self.defaults)
        return self.settings
    end

    function store:Load()
        local readMode = normalizeMode(self.options.read_mode)
        local writeMode = normalizeMode(self.options.write_mode or readMode)
        local pathEntries = buildPathEntries(
            self:GetPrimaryPath(),
            self:GetLegacyPath(),
            self.options.fallback_paths
        )
        local diskSettings, diskMeta = readFirstAvailable(pathEntries, {
            mode = readMode,
            raw_text_fallback = self.options.read_raw_text_fallback == true
        })
        local hasPrimary = self:GetPrimaryPath() ~= "" and Settings.HasTableFile(self:GetPrimaryPath()) or false

        local settings = nil
        local usedApiSeed = false
        local apiSeedId = ""
        local apiIds = {}
        if self.options.addon_id ~= nil then
            apiIds[#apiIds + 1] = self.options.addon_id
        end
        for _, legacyId in ipairs(self.options.legacy_addon_ids or {}) do
            apiIds[#apiIds + 1] = legacyId
        end
        if self.options.use_api_settings ~= false then
            for _, addonId in ipairs(normalizeStringList(apiIds)) do
                local candidate = getApiSettings(addonId)
                if type(candidate) == "table" then
                    settings = candidate
                    usedApiSeed = true
                    apiSeedId = addonId
                    break
                end
            end
        end
        if type(settings) ~= "table" then
            settings = {}
        end

        for _, path in ipairs(normalizeStringList(self.options.prefer_richer_candidate_paths)) do
            local candidate, _, _ = Settings.ReadFlexibleTable(path, {
                mode = readMode,
                raw_text_fallback = self.options.read_raw_text_fallback == true
            })
            local prefer, reason = Settings.ShouldPreferTable(diskSettings, candidate, self.options.richer_preference)
            if prefer then
                diskSettings = candidate
                diskMeta.source_path = path
                diskMeta.source_kind = "preferred_candidate"
                diskMeta.migrated = true
                diskMeta.last_error = ""
                diskMeta.preferred_reason = reason
            end
        end

        if type(diskSettings) == "table" then
            Runtime.MergeInto(settings, diskSettings)
        end

        local meta = {
            source_path = diskMeta.source_path,
            source_kind = diskMeta.source_kind,
            last_source = diskMeta.source,
            migrated = diskMeta.migrated,
            has_primary = hasPrimary,
            used_api_seed = usedApiSeed,
            api_seed_id = apiSeedId,
            last_error = tostring(diskMeta.last_error or ""),
            preferred_reason = diskMeta.preferred_reason
        }

        local changed = false
        if self.options.prune_unknown == true then
            if Runtime.PruneUnknown(settings, self.defaults, {
                skip_empty_default_tables = self.options.skip_empty_default_tables == true
            }) then
                changed = true
            end
        end
        if self.options.apply_defaults ~= false and Runtime.ApplyDefaults(settings, self.defaults) then
            changed = true
        end

        self.settings = settings

        if type(self.options.normalize) == "function" then
            local ok, result, resultChanged = pcall(self.options.normalize, settings, meta)
            if not ok then
                meta.last_error = tostring(result)
                local name = tostring(self.options.log_name or self.options.addon_id or "Nuzi Core")
                logError("[" .. name .. "] settings normalize failed: ", result)
            elseif type(result) == "table" then
                self.settings = result
                settings = result
                if resultChanged ~= false then
                    changed = true
                end
            elseif result == true then
                changed = true
            end
        end

        if changed or meta.migrated or (self.options.bootstrap_if_missing ~= false and not meta.has_primary) then
            local saved = false
            saved = self:Save(writeMode)
            meta.saved = saved and true or false
        else
            meta.saved = false
        end

        self.last_meta = meta
        return self.settings, meta
    end

    function store:Ensure()
        if type(self.settings) ~= "table" then
            return self:Load()
        end
        return self.settings, self.last_meta
    end

    function store:Save(mode)
        local settings = self:Ensure()
        local writeMode = normalizeMode(mode or self.options.write_mode or self.options.read_mode)
        local primaryPath = self:GetPrimaryPath()
        local ok, writeMeta = Settings.WriteTable(primaryPath, settings, writeMode)
        local mirrorWrites = {}
        for _, mirrorPath in ipairs(normalizeStringList(self.options.write_mirror_paths)) do
            if mirrorPath ~= primaryPath then
                local mirrorOk, mirrorMeta = Settings.WriteTable(mirrorPath, settings, writeMode)
                mirrorWrites[#mirrorWrites + 1] = {
                    path = mirrorPath,
                    ok = mirrorOk and true or false,
                    meta = mirrorMeta
                }
                if not mirrorOk then
                    local name = tostring(self.options.log_name or self.options.addon_id or "Nuzi Core")
                    logError("[" .. name .. "] failed to write mirror settings file: ", mirrorPath)
                end
            end
        end
        if self.options.save_global_settings ~= false then
            saveApiSettings()
        end
        if not ok then
            local name = tostring(self.options.log_name or self.options.addon_id or "Nuzi Core")
            logError("[" .. name .. "] failed to write settings file: ", self:GetPrimaryPath())
        end
        if type(self.last_meta) ~= "table" then
            self.last_meta = {}
        end
        self.last_meta.saved = ok and true or false
        self.last_meta.write = writeMeta
        self.last_meta.write_mirrors = mirrorWrites
        return ok, writeMeta
    end

    if type(config.backups) == "table" then
        Settings.AttachBackupMethods(store, config.backups)
    end
    if type(config.profiles) == "table" then
        Settings.AttachProfileMethods(store, config.profiles)
    end

    return store
end

local function getTimestamp()
    local timestamp = nil
    pcall(function()
        if api.Time ~= nil and api.Time.GetLocalTime ~= nil then
            timestamp = api.Time:GetLocalTime()
        end
    end)
    if timestamp == nil then
        timestamp = tostring(math.random(1000000000, 9999999999))
    end
    return tostring(timestamp)
end

local function getFileName(path)
    local normalized = Runtime.NormalizePath(path)
    return string.match(normalized, "([^/]+)$") or normalized
end

local function ensureTxtExtension(name)
    local text = tostring(name or "")
    if string.match(string.lower(text), "%.txt$") ~= nil then
        return text
    end
    return text .. ".txt"
end

local function sanitizeProfileName(name)
    local text = Runtime.Trim(name)
    text = string.gsub(text, "%.txt$", "")
    text = string.gsub(text, "[^%w%-%_ ]", "_")
    text = string.gsub(text, "%s+", "_")
    text = Runtime.Trim(text)
    if text == "" then
        return nil
    end
    return ensureTxtExtension(text)
end

local function readCandidateTable(paths, options, fallback)
    local parsed, sourcePath, source, err = Settings.TryReadFlexibleCandidates(
        normalizeStringList(paths),
        options
    )
    if type(parsed) == "table" then
        return parsed, sourcePath, source, err
    end
    return fallback, nil, source, err
end

local function writeCandidateTable(paths, value, mode)
    local saved = false
    local results = {}
    for _, path in ipairs(normalizeStringList(paths)) do
        local ok, meta = Settings.WriteTable(path, value, mode)
        results[#results + 1] = {
            path = path,
            ok = ok and true or false,
            meta = meta
        }
        saved = ok or saved
    end
    return saved, results
end

function Settings.CreateBackupManager(options)
    local config = Runtime.DeepCopy(options or {})
    local manager = {
        options = config
    }

    local function readOptions()
        return {
            mode = config.read_mode or "serialized_then_flat",
            raw_text_fallback = config.read_raw_text_fallback == true
        }
    end

    local function writeMode()
        return config.write_mode or config.read_mode or "serialized_then_flat"
    end

    local function indexPaths()
        local paths = {
            config.index_file_path,
            config.index_fallback_file_path
        }
        for _, path in ipairs(config.index_write_mirror_paths or {}) do
            paths[#paths + 1] = path
        end
        for _, path in ipairs(config.legacy_index_paths or {}) do
            paths[#paths + 1] = path
        end
        return paths
    end

    local function writableIndexPaths()
        local paths = {
            config.index_file_path,
            config.index_fallback_file_path
        }
        for _, path in ipairs(config.index_write_mirror_paths or {}) do
            paths[#paths + 1] = path
        end
        return paths
    end

    local function latestPaths()
        local paths = {
            config.latest_backup_file_path
        }
        for _, path in ipairs(config.latest_backup_mirror_paths or {}) do
            paths[#paths + 1] = path
        end
        for _, path in ipairs(config.legacy_latest_paths or {}) do
            paths[#paths + 1] = path
        end
        return paths
    end

    local function writableLatestPaths()
        local paths = {
            config.latest_backup_file_path
        }
        for _, path in ipairs(config.latest_backup_mirror_paths or {}) do
            paths[#paths + 1] = path
        end
        return paths
    end

    local function readIndex()
        local parsed, sourcePath = readCandidateTable(indexPaths(), readOptions(), {
            version = 1,
            backups = {}
        })
        if type(parsed) ~= "table" then
            parsed = { version = 1, backups = {} }
        end
        if type(parsed.backups) ~= "table" then
            parsed.backups = {}
        end
        return parsed, sourcePath
    end

    local function writeIndex(value)
        local saved = writeCandidateTable(writableIndexPaths(), value, writeMode())
        return saved
    end

    function manager:BuildBackupPath(timestamp)
        local prefix = tostring(config.backup_prefix or "settings")
        local dir = tostring(config.backup_dir or "")
        if dir == "" then
            return ensureTxtExtension(prefix .. "_" .. tostring(timestamp))
        end
        return string.format("%s/%s_%s.txt", Runtime.NormalizePath(dir), prefix, tostring(timestamp))
    end

    function manager:Save(value)
        if type(value) ~= "table" then
            return false, "settings value must be a table"
        end
        local timestamp = getTimestamp()
        local backupPath = self:BuildBackupPath(timestamp)
        local ok = Settings.WriteTable(backupPath, value, writeMode())
        if not ok then
            return false, "failed to write backup file"
        end

        local index = readIndex()
        table.insert(index.backups, 1, {
            path = backupPath,
            timestamp = timestamp
        })
        local maxBackups = tonumber(config.max_backups) or 30
        while #index.backups > maxBackups do
            table.remove(index.backups)
        end
        writeIndex(index)

        writeCandidateTable(writableLatestPaths(), value, writeMode())
        return true, backupPath
    end

    function manager:GetLatestPath()
        return self:Resolve("")
    end

    function manager:Resolve(arg)
        local index = readIndex()
        local raw = Runtime.Trim(arg)
        if raw == "" then
            if type(index.backups[1]) == "table" and type(index.backups[1].path) == "string" then
                return index.backups[1].path
            end
            for _, path in ipairs(normalizeStringList(latestPaths())) do
                if path ~= "" then
                    return path
                end
            end
            return nil
        end

        local numeric = tonumber(raw)
        if numeric ~= nil and index.backups[numeric] ~= nil then
            return index.backups[numeric].path
        end

        for _, entry in ipairs(index.backups) do
            if type(entry) == "table" and (entry.path == raw or getFileName(entry.path) == raw) then
                return entry.path
            end
        end

        if string.find(raw, "/", 1, true) ~= nil or string.find(raw, "\\", 1, true) ~= nil then
            return Runtime.NormalizePath(raw)
        end
        return nil
    end

    function manager:List(maxCount)
        local index = readIndex()
        local limit = tonumber(maxCount) or #index.backups
        local items = {}
        for idx, entry in ipairs(index.backups) do
            if idx > limit then
                break
            end
            if type(entry) == "table" and type(entry.path) == "string" then
                items[#items + 1] = {
                    index = idx,
                    path = entry.path,
                    file_name = getFileName(entry.path),
                    timestamp = entry.timestamp
                }
            end
        end
        return items
    end

    function manager:Import(arg)
        local resolved = self:Resolve(arg)
        if resolved == nil then
            return nil, "no backup found"
        end

        local candidates = { resolved }
        for _, path in ipairs(normalizeStringList(latestPaths())) do
            if path ~= resolved then
                candidates[#candidates + 1] = path
            end
        end
        local parsed, sourcePath, _, err = Settings.TryReadFlexibleCandidates(candidates, readOptions())
        if type(parsed) ~= "table" then
            return nil, tostring(err ~= "" and err or "failed to read backup")
        end
        return parsed, sourcePath or resolved
    end

    return manager
end

function Settings.AttachBackupMethods(store, options)
    local manager = Settings.CreateBackupManager(options)
    store.backups = manager

    function store:SaveBackup()
        return manager:Save(self:Ensure())
    end

    function store:CreateBackup()
        return self:SaveBackup()
    end

    function store:GetLatestBackupPath()
        return manager:GetLatestPath()
    end

    function store:ResolveBackupPath(arg)
        return manager:Resolve(arg)
    end

    function store:ListBackups(maxCount)
        return manager:List(maxCount)
    end

    function store:ImportLatestBackup()
        return self:ImportBackup("")
    end

    function store:ImportBackup(arg)
        local parsed, result = manager:Import(arg)
        if type(parsed) ~= "table" then
            return false, result
        end
        local settings = self:Ensure()
        local previousSettings = Runtime.DeepCopy(settings)
        for key in pairs(settings) do
            settings[key] = nil
        end
        Runtime.MergeInto(settings, parsed)
        if self.options.apply_defaults ~= false then
            Runtime.ApplyDefaults(settings, self.defaults)
        end
        if type(self.options.normalize) == "function" then
            pcall(self.options.normalize, settings, {
                source_kind = "backup",
                source_path = result
            })
        end
        self.settings = settings
        local ok, saveMeta = self:Save()
        if not ok then
            self.settings = previousSettings
            return false, saveMeta
        end
        return true, result
    end

    return store
end

function Settings.CreateProfileManager(options)
    local config = Runtime.DeepCopy(options or {})
    local manager = {
        options = config,
        state = nil
    }

    local function stateDefaults()
        return {
            version = 1,
            active_profile = tostring(config.default_path or ""),
            profile_count = 0
        }
    end

    local function stateReadOptions()
        return {
            mode = config.state_mode or config.read_mode or "serialized_then_flat",
            raw_text_fallback = config.state_raw_text_fallback == true or config.read_raw_text_fallback == true
        }
    end

    local function stateWriteMode()
        return config.state_write_mode or config.state_mode or config.write_mode or config.read_mode or "serialized_then_flat"
    end

    local function stateReadPaths()
        local paths = {
            config.state_file_path,
            config.state_fallback_file_path
        }
        for _, path in ipairs(config.state_write_mirror_paths or {}) do
            paths[#paths + 1] = path
        end
        for _, path in ipairs(config.legacy_state_paths or {}) do
            paths[#paths + 1] = path
        end
        return paths
    end

    local function stateWritePaths()
        local paths = {
            config.state_file_path,
            config.state_fallback_file_path
        }
        for _, path in ipairs(config.state_write_mirror_paths or {}) do
            paths[#paths + 1] = path
        end
        return paths
    end

    function manager:NormalizePath(path)
        local text = Runtime.Trim(path)
        if text == "" then
            return tostring(config.default_path or "")
        end
        text = Runtime.NormalizePath(text)
        if string.find(text, "/", 1, true) == nil then
            local dir = Runtime.NormalizePath(config.profile_dir or "")
            if dir ~= "" then
                text = dir .. "/" .. ensureTxtExtension(text)
            else
                text = ensureTxtExtension(text)
            end
        end
        return text
    end

    function manager:GetFileName(path)
        return getFileName(path)
    end

    function manager:CreatePathFromName(name)
        local fileName = sanitizeProfileName(name)
        if fileName == nil then
            return nil, "enter a profile name"
        end
        return self:NormalizePath(fileName), fileName
    end

    function manager:EnsureState()
        if type(self.state) == "table" then
            return self.state
        end
        local state, sourcePath = readCandidateTable(stateReadPaths(), stateReadOptions(), stateDefaults())
        if type(state) ~= "table" then
            state = stateDefaults()
        end
        Runtime.ApplyDefaults(state, stateDefaults())

        local seen = {}
        local paths = {}
        local function add(path)
            local normalized = self:NormalizePath(path)
            if normalized ~= "" and not seen[normalized] then
                seen[normalized] = true
                paths[#paths + 1] = normalized
            end
        end

        add(config.default_path)
        local count = tonumber(state.profile_count) or 0
        for index = 1, count do
            add(state[string.format("profile_%03d", index)])
        end
        add(state.active_profile)

        for key in pairs(state) do
            if string.match(tostring(key), "^profile_%d%d%d$") ~= nil then
                state[key] = nil
            end
        end
        state.profile_count = 0
        table.sort(paths, function(a, b)
            if a == self:NormalizePath(config.default_path) then
                return true
            end
            if b == self:NormalizePath(config.default_path) then
                return false
            end
            return string.lower(getFileName(a)) < string.lower(getFileName(b))
        end)
        for index, path in ipairs(paths) do
            state.profile_count = index
            state[string.format("profile_%03d", index)] = path
        end
        state.active_profile = self:NormalizePath(state.active_profile or config.default_path)
        self.state = state
        self.state_source_path = sourcePath
        return self.state
    end

    function manager:SaveState()
        self:EnsureState()
        return writeCandidateTable(stateWritePaths(), self.state, stateWriteMode())
    end

    function manager:GetActivePath()
        return self:NormalizePath(self:EnsureState().active_profile or config.default_path)
    end

    function manager:SetActivePath(path)
        local state = self:EnsureState()
        state.active_profile = self:NormalizePath(path)
        local found = false
        local count = tonumber(state.profile_count) or 0
        for index = 1, count do
            if state[string.format("profile_%03d", index)] == state.active_profile then
                found = true
                break
            end
        end
        if not found then
            count = count + 1
            state.profile_count = count
            state[string.format("profile_%03d", count)] = state.active_profile
        end
        self:SaveState()
        return state.active_profile
    end

    function manager:List()
        local state = self:EnsureState()
        local items = {}
        local active = self:GetActivePath()
        local count = tonumber(state.profile_count) or 0
        for index = 1, count do
            local path = state[string.format("profile_%03d", index)]
            if type(path) == "string" and path ~= "" then
                items[#items + 1] = {
                    path = path,
                    file_name = getFileName(path),
                    is_active = path == active
                }
            end
        end
        return items
    end

    return manager
end

function Settings.AttachProfileMethods(store, options)
    local baseGetPrimaryPath = store.GetPrimaryPath
    local manager = Settings.CreateProfileManager(Runtime.MergeInto({
        default_path = baseGetPrimaryPath(store)
    }, Runtime.DeepCopy(options or {})))

    store.profile_manager = manager
    store.GetBasePrimaryPath = baseGetPrimaryPath

    function store:GetPrimaryPath()
        return self.profile_manager:GetActivePath()
    end

    function store:GetActiveProfilePath()
        return self.profile_manager:GetActivePath()
    end

    function store:GetActiveProfileFileName()
        return self.profile_manager:GetFileName(self:GetActiveProfilePath())
    end

    function store:ListProfiles()
        return self.profile_manager:List()
    end

    function store:SaveAsProfile(name)
        local path, result = self.profile_manager:CreatePathFromName(name)
        if path == nil then
            return false, result
        end
        local previous = self.profile_manager:GetActivePath()
        self.profile_manager:SetActivePath(path)
        local ok, err = self:Save()
        if not ok then
            self.profile_manager:SetActivePath(previous)
            return false, err
        end
        return true, result
    end

    function store:LoadProfile(path)
        local normalized = self.profile_manager:NormalizePath(path)
        local parsed, _, err = Settings.ReadFlexibleTable(normalized, {
            mode = self.options.read_mode,
            raw_text_fallback = self.options.read_raw_text_fallback == true
        })
        if type(parsed) ~= "table" then
            return false, tostring(err ~= "" and err or "profile not found")
        end
        local settings = self:Ensure()
        local previousSettings = Runtime.DeepCopy(settings)
        local previousActive = self.profile_manager:GetActivePath()
        for key in pairs(settings) do
            settings[key] = nil
        end
        Runtime.MergeInto(settings, parsed)
        if self.options.apply_defaults ~= false then
            Runtime.ApplyDefaults(settings, self.defaults)
        end
        if type(self.options.normalize) == "function" then
            pcall(self.options.normalize, settings, {
                source_kind = "profile",
                source_path = normalized
            })
        end
        self.settings = settings
        self.profile_manager:SetActivePath(normalized)
        local ok, saveMeta = self:Save()
        if not ok then
            self.settings = previousSettings
            self.profile_manager:SetActivePath(previousActive)
            return false, saveMeta
        end
        return true, self.profile_manager:GetFileName(normalized)
    end

    return store
end

function Settings.CreateAddonStore(constants, options)
    constants = type(constants) == "table" and constants or {}
    local config = Runtime.DeepCopy(options or {})
    if config.addon_id == nil then
        config.addon_id = constants.ADDON_ID
    end
    if config.settings_file_path == nil then
        config.settings_file_path = constants.SETTINGS_FILE_PATH
    end
    if config.legacy_settings_file_path == nil then
        config.legacy_settings_file_path = constants.LEGACY_SETTINGS_FILE_PATH
    end
    if config.defaults == nil then
        config.defaults = Runtime.DeepCopy(constants.DEFAULT_SETTINGS or {})
    end
    if config.log_name == nil then
        config.log_name = constants.ADDON_NAME or constants.ADDON_ID or "Nuzi Core"
    end
    return Settings.CreateStore(config)
end

Settings.CreateSidecarStore = Settings.CreateStore

return Settings
