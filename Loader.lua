-- Experiment17 Visuals - modular GitHub loader
-- GuiLib integration: stable Experiment17.lua entrypoint (currently v21)

local ENV = (getgenv and getgenv()) or _G
if ENV.Experiment17 and type(ENV.Experiment17.Unload) == "function" then
    pcall(function()
        ENV.Experiment17:Unload("reload")
    end)
end

local ROOT = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/"
local GUI_ROOT = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_GuiLib/main/"
local DEFAULT_GUI = "Experiment17.lua"

local HttpService = game:GetService("HttpService")

local function fetch(url)
    local ok, result = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok and type(result) == "string" and #result > 0 then
        return result
    end
    return nil, result
end

local function compile(source, label)
    local compiler = loadstring or (getgenv and getgenv().loadstring)
    if type(compiler) ~= "function" then
        return nil, "loadstring unavailable"
    end

    local fn, err = compiler(source, "=" .. tostring(label))
    if not fn then
        return nil, err
    end

    local ok, result = pcall(fn)
    if not ok then
        return nil, result
    end
    return result
end

local function absolute(path)
    path = tostring(path or "")
    if path:match("^https?://") then
        return path
    end
    return ROOT .. path:gsub("^/+", "")
end

local fallbackModules = {
    {id="Performance",file="Performance.lua",order=5},
    {id="Visual",file="Visual.lua",order=10},
    {id="Lighting",file="Lighting.lua",order=20},
    {id="LightingPlus",file="LightingPlus.lua",order=25},
    {id="ESP",file="ESP.lua",order=30},
    {id="DamageVisualizer",file="DamageVisualizer.lua",order=35},
    {id="World",file="World.lua",order=40},
    {id="WorldEchoPlus",file="WorldEchoPlus.lua",order=45},
    {id="Player",file="Player.lua",order=50},
    {id="PlayerAnimations",file="PlayerAnimations.lua",order=55},
    {id="Trajectory",file="Trajectory.lua",order=60},
    {id="Waypoints",file="Waypoints.lua",order=70},
    {id="Music",file="Music.lua",order=75},
    {id="Sync",file="Sync.lua",order=80},
    {id="SharedBus",file="SharedBus.lua",order=82},
    {id="PerformanceStreaming",file="PerformanceStreaming.lua",order=915},
    {id="UIEnhancements",file="UIEnhancements.lua",order=1000},
}

local function readManifest()
    local source = fetch(ROOT .. "manifest.json")
    if not source then
        return {
            version = 0,
            gui = DEFAULT_GUI,
            modules = fallbackModules,
        }
    end

    local ok, data = pcall(HttpService.JSONDecode, HttpService, source)
    if not ok or type(data) ~= "table" then
        return {
            version = 0,
            gui = DEFAULT_GUI,
            modules = fallbackModules,
        }
    end

    if type(data.modules) ~= "table" then
        data.modules = fallbackModules
    end
    if type(data.gui) ~= "string" or data.gui == "" then
        data.gui = DEFAULT_GUI
    end
    return data
end

local Manifest = readManifest()
local guiEntry = Manifest.gui
local guiURL = guiEntry:match("^https?://") and guiEntry or (GUI_ROOT .. guiEntry)

local Core = {
    Version = "0.8.0-v21",
    GuiEntry = guiEntry,
    GuiURL = guiURL,
    Manifest = Manifest,
    Tabs = {},
    States = {},
    Shared = {},
    Modules = {},
    Scopes = {},
    Services = {},
    Unloaded = false,
}
ENV.Experiment17 = Core

for _, serviceName in ipairs({
    "Players",
    "RunService",
    "UserInputService",
    "Lighting",
    "Workspace",
    "TweenService",
    "HttpService",
    "CollectionService",
    "ReplicatedStorage",
    "SoundService",
}) do
    local key = serviceName == "UserInputService" and "UIS" or serviceName
    Core.Services[key] = game:GetService(serviceName)
end
Core.LocalPlayer = Core.Services.Players.LocalPlayer

local function cloneDefaults(tbl)
    local out = {}
    for key, value in pairs(tbl or {}) do
        if type(value) == "table" then
            local child = {}
            for childKey, childValue in pairs(value) do
                child[childKey] = childValue
            end
            out[key] = child
        else
            out[key] = value
        end
    end
    return out
end

function Core:GetState(id, defaults)
    if not self.States[id] then
        self.States[id] = cloneDefaults(defaults)
    else
        for key, value in pairs(defaults or {}) do
            if self.States[id][key] == nil then
                self.States[id][key] = type(value) == "table" and cloneDefaults(value) or value
            end
        end
    end
    return self.States[id]
end

function Core:Log(...)
    print("[Experiment17]", ...)
end

function Core:Warn(...)
    warn("[Experiment17]", ...)
end

Core.Bus = {Listeners = {}}

function Core.Bus:On(name, callback)
    self.Listeners[name] = self.Listeners[name] or {}
    table.insert(self.Listeners[name], callback)
    return {
        Disconnect = function()
            local listeners = self.Listeners[name] or {}
            for index = #listeners, 1, -1 do
                if listeners[index] == callback then
                    table.remove(listeners, index)
                end
            end
        end,
    }
end

function Core.Bus:Emit(name, ...)
    for _, callback in ipairs(self.Listeners[name] or {}) do
        pcall(callback, ...)
    end
end

local function newScope(id)
    local scope = {
        Id = id,
        Cleaners = {},
        Connections = {},
        Instances = {},
        Controls = {},
    }

    function scope:AddCleaner(callback)
        table.insert(self.Cleaners, callback)
        return callback
    end

    function scope:TrackConnection(connection)
        if connection then
            table.insert(self.Connections, connection)
        end
        return connection
    end

    function scope:TrackInstance(instance)
        if instance then
            table.insert(self.Instances, instance)
        end
        return instance
    end

    function scope:TrackControl(control)
        if control then
            table.insert(self.Controls, control)
        end
        return control
    end

    function scope:Clean()
        for index = #self.Cleaners, 1, -1 do
            pcall(self.Cleaners[index])
        end
        for _, connection in ipairs(self.Connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        for _, instance in ipairs(self.Instances) do
            pcall(function()
                instance:Destroy()
            end)
        end
        table.clear(self.Cleaners)
        table.clear(self.Connections)
        table.clear(self.Instances)
        table.clear(self.Controls)
    end

    return scope
end

local guiSource, guiFetchError = fetch(guiURL)
if not guiSource then
    error("[Experiment17] GuiLib fetch failed: " .. tostring(guiFetchError))
end

local library, guiCompileError = compile(guiSource, "E17_GuiLib_Stable")
if not library then
    error("[Experiment17] GuiLib load failed: " .. tostring(guiCompileError))
end
Core.Library = library

local function destroyTab(tab)
    if not tab then return end
    pcall(function()
        if tab.Button then tab.Button:Destroy() end
    end)
    pcall(function()
        if tab.PageGroup then
            tab.PageGroup:Destroy()
        elseif tab.Page then
            tab.Page:Destroy()
        end
    end)
end

function Core:GetTab(name)
    return self.Tabs[tostring(name)]
end

function Core:CreateTab(owner, name, order, scope)
    name = tostring(name)
    if self.Tabs[name] then
        return self.Tabs[name]
    end

    local tab = self.Library:CreateTab(name)
    tab.__Experiment17Owner = owner
    tab.__Experiment17Order = order or 100

    if tab.Button then
        tab.Button.LayoutOrder = order or 100
    end

    self.Tabs[name] = tab

    if scope then
        scope:AddCleaner(function()
            if Core.Tabs[name] == tab then
                Core.Tabs[name] = nil
                destroyTab(tab)
            end
        end)
    end

    return tab
end

local TRACKED_SECTION_METHODS = {
    "AddButton",
    "AddToggle",
    "AddSlider",
    "AddRangeSlider",
    "AddChoice",
    "AddMultiChoice",
    "AddMultiDropdown",
    "AddInput",
    "AddNumberInput",
    "AddKeybind",
    "AddColorPicker",
    "AddProgressBar",
    "AddButtonGroup",
    "AddStatus",
    "AddLabel",
    "AddParagraph",
}

function Core:CreateSection(scope, tab, name, opened, localeKey)
    local section = tab:CreateSection(name, opened == true, localeKey)

    for _, methodName in ipairs(TRACKED_SECTION_METHODS) do
        if type(section[methodName]) == "function" then
            local raw = section[methodName]
            section[methodName] = function(self, options, ...)
                local control = raw(self, options, ...)
                if scope and control then
                    scope:TrackControl(control)
                end
                return control
            end
        end
    end

    return section
end

local function unloadModule(id, reason)
    local record = Core.Modules[id]
    if not record then return end

    if record.Descriptor and type(record.Descriptor.Unload) == "function" then
        pcall(record.Descriptor.Unload, Core, record.Scope, reason or "reload")
    end
    if record.Scope then
        record.Scope:Clean()
    end

    Core.Modules[id] = nil
    Core.Scopes[id] = nil
end

local function mountDescriptor(descriptor, sourceURL, forcedId)
    if type(descriptor) ~= "table" then
        return false, "module did not return a table"
    end

    if descriptor.RedirectURL then
        local source, err = fetch(absolute(descriptor.RedirectURL))
        if not source and descriptor.FallbackURL then
            source, err = fetch(absolute(descriptor.FallbackURL))
            descriptor.__UsingFallback = true
        end
        if not source then
            return false, err
        end

        local redirected, compileErr = compile(source, descriptor.RedirectId or forcedId or descriptor.Id or "Redirect")
        if not redirected and descriptor.FallbackURL and not descriptor.__UsingFallback then
            local fallbackSource = fetch(absolute(descriptor.FallbackURL))
            if fallbackSource then
                redirected, compileErr = compile(fallbackSource, "ESP_Fallback")
                descriptor.__UsingFallback = true
            end
        end
        if not redirected then
            return false, compileErr
        end

        redirected.__RouteMeta = descriptor.RouteMeta
        descriptor = redirected
    end

    local id = tostring(forcedId or descriptor.Id or descriptor.Name or "Module")
    unloadModule(id, "replace")

    local scope = newScope(id)
    Core.Scopes[id] = scope

    local targetName = descriptor.TargetTab
    local tab
    if targetName then
        tab = Core:GetTab(targetName)
        if not tab then
            tab = Core:CreateTab(targetName, targetName, descriptor.Order or 100, nil)
        end
    else
        tab = Core:CreateTab(id, descriptor.TabName or descriptor.Name or id, descriptor.Order or 100, scope)
    end

    Core.Modules[id] = {
        Descriptor = descriptor,
        Scope = scope,
        Tab = tab,
        SourceURL = sourceURL,
    }

    if descriptor.__RouteMeta then
        Core.Shared.ModuleRoutes = Core.Shared.ModuleRoutes or {}
        Core.Shared.ModuleRoutes[id] = {
            Meta = descriptor.__RouteMeta,
            UsingFallback = descriptor.__UsingFallback == true,
        }
    end

    if type(descriptor.Init) == "function" then
        local ok, err = pcall(descriptor.Init, Core, scope, tab)
        if not ok then
            unloadModule(id, "init-error")
            return false, err
        end
    end

    if type(descriptor.Start) == "function" then
        task.spawn(function()
            local ok, err = pcall(descriptor.Start, Core, scope, tab)
            if not ok then
                Core:Warn(id, "Start error", err)
            end
        end)
    end

    Core.Bus:Emit("ModuleLoaded", id, descriptor)
    return true
end

function Core:LoadModule(id, file)
    local url = absolute("modules/" .. tostring(file))
    local source, err = fetch(url)
    if not source then
        self:Warn("fetch failed", id, err)
        return false
    end

    local descriptor, compileErr = compile(source, id)
    if not descriptor then
        self:Warn("compile failed", id, compileErr)
        return false
    end

    local ok, why = mountDescriptor(descriptor, url, id)
    if not ok then
        self:Warn("mount failed", id, why)
    end
    return ok
end

function Core:RegisterModule(descriptor)
    local ok, err = mountDescriptor(descriptor, "runtime", descriptor.Id)
    if not ok then
        self:Warn(err)
    end
    return ok
end

function Core:ReloadModule(id)
    local record = self.Modules[id]
    if record and record.SourceURL and record.SourceURL ~= "runtime" then
        local file = record.SourceURL:match("/modules/(.+)$")
        return self:LoadModule(id, file)
    end
    return false
end

function Core:Unload(reason)
    if self.Unloaded then return end
    self.Unloaded = true

    local ids = {}
    for id in pairs(self.Modules) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(ids) do
        unloadModule(id, reason or "unload")
    end

    pcall(function()
        if self.Library and self.Library.Unload then
            self.Library:Unload()
        end
    end)

    if ENV.Experiment17 == self then
        ENV.Experiment17 = nil
    end
end

local modules = Manifest.modules or fallbackModules
local enabledModules = {}
for _, moduleData in ipairs(modules) do
    if moduleData.enabled ~= false then
        enabledModules[#enabledModules + 1] = moduleData
    end
end

table.sort(enabledModules, function(a, b)
    return (a.order or a.Order or 100) < (b.order or b.Order or 100)
end)

for _, moduleData in ipairs(enabledModules) do
    Core:LoadModule(moduleData.id or moduleData.Id, moduleData.file or moduleData.File)
end

local first = Core:GetTab("Visual") or Core:GetTab("Performance")
if first and first.Select then
    pcall(function()
        first:Select()
    end)
end

Core:Log("loaded", Core.Version, "GuiLib:", Core.GuiEntry)
return Core
