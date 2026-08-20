--[[
    Experiment 17 - ESP Router v1.0
    This module owns no UI. It resolves a game-specific ESP source and returns
    RedirectURL to Loader v0.5+.

    Resolution order:
      1) local Experiment17_Visuals/esp/registry.json (when available)
      2) GitHub modules/esp/registry.json
      3) Universal ESP fallback

    registry.json supports exact PlaceId and GameId/UniverseId entries.
]]

local HttpService = game:GetService("HttpService")

local RAW_ROOT = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/"
local REGISTRY_URL = RAW_ROOT .. "modules/esp/registry.json"
local UNIVERSAL_URL = RAW_ROOT .. "modules/esp/Universal.lua"
local LOCAL_REGISTRY = "Experiment17_Visuals/esp/registry.json"

local function absoluteURL(value)
    value = tostring(value or "")
    if value == "" then return "" end
    if value:match("^https?://") then return value end
    return RAW_ROOT .. value:gsub("^/+", "")
end

local function readRegistry()
    if type(readfile) == "function" then
        local canRead = true
        if type(isfile) == "function" then
            local ok, exists = pcall(isfile, LOCAL_REGISTRY)
            canRead = ok and exists == true
        end
        if canRead then
            local ok, text = pcall(readfile, LOCAL_REGISTRY)
            if ok and type(text) == "string" and text ~= "" then
                local okDecode, data = pcall(HttpService.JSONDecode, HttpService, text)
                if okDecode and type(data) == "table" then
                    return data, "local"
                end
            end
        end
    end

    local okHttp, text = pcall(function()
        return game:HttpGet(REGISTRY_URL, true)
    end)
    if okHttp and type(text) == "string" and text ~= "" then
        local okDecode, data = pcall(HttpService.JSONDecode, HttpService, text)
        if okDecode and type(data) == "table" then
            return data, "github"
        end
    end

    return nil, "fallback"
end

local function unpackEntry(entry)
    if type(entry) == "string" then
        return absoluteURL(entry), nil
    end
    if type(entry) == "table" then
        if entry.enabled == false then return "", entry.name end
        return absoluteURL(entry.url or entry.URL), entry.name
    end
    return "", nil
end

local registry, source = readRegistry()
local placeKey = tostring(game.PlaceId)
local universeKey = tostring(game.GameId)
local selectedURL = ""
local profileName = "Universal"
local matchedBy = "default"

if registry then
    local entry
    if type(registry.places) == "table" then
        entry = registry.places[placeKey]
        if entry ~= nil then matchedBy = "PlaceId" end
    end
    if entry == nil and type(registry.universes) == "table" then
        entry = registry.universes[universeKey]
        if entry ~= nil then matchedBy = "GameId" end
    end

    if entry ~= nil then
        local url, name = unpackEntry(entry)
        selectedURL = url
        profileName = name or ("Game ESP " .. placeKey)
    end

    if selectedURL == "" then
        selectedURL = absoluteURL(registry.default)
        profileName = tostring(registry.default_name or "Universal")
        matchedBy = "default"
    end
end

if selectedURL == "" then
    selectedURL = UNIVERSAL_URL
end

return {
    Id = "ESP",
    Name = "ESP Router",
    Version = "1.0.0",
    RedirectURL = selectedURL,
    FallbackURL = UNIVERSAL_URL,
    RedirectId = "ESP",
    RouteMeta = {
        RegistrySource = source,
        RegistryURL = REGISTRY_URL,
        PlaceId = game.PlaceId,
        GameId = game.GameId,
        MatchedBy = matchedBy,
        Profile = profileName,
    },
}
