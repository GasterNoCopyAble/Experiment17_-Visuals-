--[[
    Experiment 17 - Modular Loader v0.4 / GuiLib v19

    Purpose:
      * Load one independent Lua module per tab.
      * Load optional add-on modules into existing tabs.
      * Prefer local module files when filesystem APIs exist.
      * Watch local module files and hot-reload only the changed module.
      * Accept runtime module registration from separately executed LocalScripts.

    Module contract:
      return {
          Id = "ESP",
          Name = "ESP",
          Version = "1.0.0",
          Order = 30,
          OwnTab = true, -- default true when TargetTab is nil
          TargetTab = nil, -- e.g. "ESP" for add-ons

          Init = function(Context, Scope, Tab)
              -- create UI / state
          end,

          Start = function(Context, Scope, Tab)
              -- optional runtime connections
          end,

          Unload = function(Context, Scope)
              -- optional custom cleanup
          end,
      }

    Runtime add-on registration from another LocalScript:
      local E17 = getgenv().Experiment17
      E17:RegisterModule({ ... })
]]

local ENV = (getgenv and getgenv()) or _G

if ENV.Experiment17 and type(ENV.Experiment17.Unload) == "function" then
    pcall(function()
        ENV.Experiment17:Unload("reload")
    end)
end

local Core = {
    Name = "Experiment 17",
    Version = "0.4.0-v19-allfeatures",
    Unloaded = false,
    Tabs = {},
    States = {},
    Shared = {},
    Connections = {},
    Instances = {},
    ModuleScopes = {},
}
ENV.Experiment17 = Core

Core.Config = {
    Repository = "GasterNoCopyAble/Experiment17_-Visuals-",
    Branch = "main",
    LoaderURL = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/Loader.lua",
    LibraryURL = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_GuiLib/main/Experiment17_VisualUI_v19.lua",

    RootFolder = "Experiment17_Visuals",
    ModuleFolder = "Experiment17_Visuals/modules",

    -- Optional raw GitHub base. Example:
    -- https://raw.githubusercontent.com/USER/REPO/main/modules/
    RemoteBase = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/modules/",

    PreferLocal = true,
    AutoReloadLocal = true,
    PollInterval = 1.50,

    -- Modules keep every feature accessible in v19. Performance cost is handled
    -- by FPSImpact metadata + Performance.lua instead of UI GraphicsLevel locks.

    Modules = {
        {Id="Performance", File="Performance.lua", Order=5},
        {Id="Visual",     File="Visual.lua",     Order=10},
        {Id="Lighting",   File="Lighting.lua",   Order=20},
        {Id="ESP",        File="ESP.lua",        Order=30},
        {Id="World",      File="World.lua",      Order=40},
        {Id="Player",     File="Player.lua",     Order=50},
        {Id="Trajectory", File="Trajectory.lua", Order=60},
        {Id="Waypoints",  File="Waypoints.lua",  Order=70},
    },
}

--============================================================
-- SERVICES
--============================================================

Core.Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    UIS = game:GetService("UserInputService"),
    Lighting = game:GetService("Lighting"),
    Workspace = game:GetService("Workspace"),
    TweenService = game:GetService("TweenService"),
    HttpService = game:GetService("HttpService"),
    CollectionService = game:GetService("CollectionService"),
}

Core.LocalPlayer = Core.Services.Players.LocalPlayer
Core.Camera = Core.Services.Workspace.CurrentCamera

--============================================================
-- HELPERS
--============================================================

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return true
    end
    return pcall(fn, ...)
end

local function normalizePath(path)
    return tostring(path or ""):gsub("\\", "/")
end

local function basename(path)
    path = normalizePath(path)
    return path:match("([^/]+)$") or path
end

local function joinPath(a, b)
    a = normalizePath(a):gsub("/+$", "")
    b = normalizePath(b):gsub("^/+", "")
    if a == "" then return b end
    if b == "" then return a end
    return a .. "/" .. b
end

local function joinURL(base, file)
    base = tostring(base or "")
    file = tostring(file or "")
    if base == "" then return "" end
    if base:sub(-1) ~= "/" then base = base .. "/" end
    return base .. file:gsub("^/+", "")
end

local function hashSource(source)
    -- Simple deterministic source fingerprint; avoids depending on bit32/crypt APIs.
    local h = 5381
    for i = 1, #source do
        h = (h * 33 + string.byte(source, i)) % 2147483647
    end
    return tostring(#source) .. ":" .. tostring(h)
end

local function removeArrayValue(array, value)
    if type(array) ~= "table" then return end
    for i = #array, 1, -1 do
        if array[i] == value then
            table.remove(array, i)
        end
    end
end

local function copyDefaults(defaults)
    local out = {}
    for k, v in pairs(defaults or {}) do
        if type(v) == "table" then
            local child = {}
            for ck, cv in pairs(v) do child[ck] = cv end
            out[k] = child
        else
            out[k] = v
        end
    end
    return out
end

function Core:Log(...)
    print("[Experiment17]", ...)
end

function Core:Warn(...)
    warn("[Experiment17]", ...)
end

function Core:GetState(id, defaults)
    id = tostring(id)
    defaults = defaults or {}

    if not self.States[id] then
        self.States[id] = copyDefaults(defaults)
    else
        -- v0.3: merge newly introduced defaults into an existing state.
        -- This is important when Performance.lua pre-patches a module before
        -- that module has mounted for the first time.
        local state = self.States[id]
        for key, value in pairs(defaults) do
            if state[key] == nil then
                if type(value) == "table" then
                    state[key] = copyDefaults(value)
                else
                    state[key] = value
                end
            end
        end
    end

    return self.States[id]
end

--============================================================
-- EVENT BUS
--============================================================

Core.Bus = {Listeners = {}}

function Core.Bus:On(eventName, callback)
    eventName = tostring(eventName)
    self.Listeners[eventName] = self.Listeners[eventName] or {}

    local listener = {
        Connected = true,
        Callback = callback,
    }
    table.insert(self.Listeners[eventName], listener)

    function listener:Disconnect()
        self.Connected = false
    end

    return listener
end

function Core.Bus:Emit(eventName, ...)
    local listeners = self.Listeners[tostring(eventName)]
    if not listeners then return end

    for _, listener in ipairs(listeners) do
        if listener.Connected and type(listener.Callback) == "function" then
            local ok, err = pcall(listener.Callback, ...)
            if not ok then
                warn("[Experiment17 Bus]", eventName, err)
            end
        end
    end
end

--============================================================
-- MODULE SCOPES / CLEANUP
--============================================================

function Core:CreateScope(moduleId)
    local scope = {
        Id = moduleId,
        Connections = {},
        Instances = {},
        Controls = {},
        Cleaners = {},
        Cleaned = false,
    }

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

    function scope:AddCleaner(callback)
        if type(callback) == "function" then
            table.insert(self.Cleaners, callback)
        end
        return callback
    end

    function scope:Cleanup()
        if self.Cleaned then return end
        self.Cleaned = true

        for i = #self.Cleaners, 1, -1 do
            pcall(self.Cleaners[i])
        end

        for _, connection in ipairs(self.Connections) do
            pcall(function()
                if connection and connection.Disconnect then
                    connection:Disconnect()
                end
            end)
        end

        for _, control in ipairs(self.Controls) do
            pcall(function()
                if Core.Library then
                    removeArrayValue(Core.Library.Controls, control)
                    removeArrayValue(Core.Library.GatedControls, control)
                    if control and control.Section and control.Section.Controls then
                        removeArrayValue(control.Section.Controls, control)
                    end
                    if control and control.Flag and Core.Library.ControlsByFlag
                        and Core.Library.ControlsByFlag[control.Flag] == control then
                        Core.Library.ControlsByFlag[control.Flag] = nil
                    end
                end
                if control and control.Holder and control.Holder.Parent then
                    control.Holder:Destroy()
                end
            end)
        end

        for i = #self.Instances, 1, -1 do
            local instance = self.Instances[i]
            pcall(function()
                if instance and instance.Parent then
                    instance:Destroy()
                end
            end)
        end

        table.clear(self.Cleaners)
        table.clear(self.Connections)
        table.clear(self.Controls)
        table.clear(self.Instances)
    end

    self.ModuleScopes[moduleId] = scope
    return scope
end

--============================================================
-- UI LIBRARY
--============================================================

local okLibrary, libraryOrError = pcall(function()
    return loadstring(game:HttpGet(Core.Config.LibraryURL, true))()
end)

if not okLibrary then
    error("[Experiment17] Failed to load Experiment17_GuiLib: " .. tostring(libraryOrError))
end

Core.Library = libraryOrError

Core.DefaultImpact = {
    Low = 0,
    LM = {-1, 0},
    Medium = {-2, 0},
    MH = {-4, 0},
    High = {-6, -1},
    HE = {-9, -2},
    Epic = {-12, -3},
}

function Core:DestroyTab(tab)
    if not tab then return end

    if self.Library.CurrentTab == tab then
        self.Library.CurrentTab = nil
    end

    removeArrayValue(self.Library.Tabs, tab)

    pcall(function()
        if tab.Button and tab.Button.Parent then tab.Button:Destroy() end
    end)
    pcall(function()
        if tab.PageGroup and tab.PageGroup.Parent then
            tab.PageGroup:Destroy()
        elseif tab.Page and tab.Page.Parent then
            tab.Page:Destroy()
        end
    end)
end

function Core:CreateTab(ownerId, name, order, scope)
    local existing = self.Tabs[name]
    if existing then
        return existing
    end

    local tab = self.Library:CreateTab(name)
    tab.__Experiment17Owner = ownerId
    tab.__Experiment17Order = order or 100

    if tab.Button then
        tab.Button.LayoutOrder = order or 100
    end

    self.Tabs[name] = tab

    if scope then
        scope:AddCleaner(function()
            if Core.Tabs[name] == tab and tab.__Experiment17Owner == ownerId then
                Core.Tabs[name] = nil
                Core:DestroyTab(tab)
            end
        end)
    end

    self:FixTabOrder()
    self.Bus:Emit("TabCreated", name, tab, ownerId)
    return tab
end

function Core:GetTab(name)
    return self.Tabs[tostring(name)]
end

function Core:FixTabOrder()
    for _, tab in pairs(self.Tabs) do
        if tab.Button then
            tab.Button.LayoutOrder = tab.__Experiment17Order or 100
        end
    end

    if self.ModuleTab and self.ModuleTab.Button then
        self.ModuleTab.Button.LayoutOrder = 9000
    end

    if self.Library.SettingsTab and self.Library.SettingsTab.Button then
        self.Library.SettingsTab.Button.LayoutOrder = 9999
    end
end

function Core:CreateSection(scope, tab, name, opened, contextName)
    local section = tab:CreateSection(name, opened == true)
    -- GuiLib v19 adds several extended controls. Wrapping them here keeps
    -- module cleanup / tooltip metadata consistent during hot reload.
    local methods = {
        "AddButton",
        "AddToggle",
        "AddSlider",
        "AddChoice",
        "AddInput",
        "AddKeybind",
        "AddColorPicker",
        "AddMultiChoice",
        "AddRangeSlider",
        "AddNumberInput",
        "AddLabel",
        "AddParagraph",
        "AddProgressBar",
        "AddStatus",
        "AddButtonGroup",
    }

    for _, methodName in ipairs(methods) do
        local original = section[methodName]
        if type(original) == "function" then
            section[methodName] = function(selfSection, options)
                options = options or {}
                if options.Description == nil then
                    options.Description = "Experiment 17 module: " .. tostring(contextName or name)
                end
                if options.FPSImpact == nil then
                    options.FPSImpact = Core.DefaultImpact[tostring(options.RequiredGraphics or "Low")] or 0
                end
                if options.PingImpact == nil then
                    options.PingImpact = 0
                end

                local control = original(selfSection, options)
                if scope then scope:TrackControl(control) end
                return control
            end
        end
    end

    return section
end

--============================================================
-- FILESYSTEM CAPABILITIES
--============================================================

Core.FS = {
    Available = type(readfile) == "function" and type(listfiles) == "function",
    CanWrite = type(writefile) == "function",
    CanMakeFolder = type(makefolder) == "function",
    Read = type(readfile) == "function" and readfile or nil,
    Write = type(writefile) == "function" and writefile or nil,
    List = type(listfiles) == "function" and listfiles or nil,
    IsFile = type(isfile) == "function" and isfile or nil,
    IsFolder = type(isfolder) == "function" and isfolder or nil,
    MakeFolder = type(makefolder) == "function" and makefolder or nil,
}

function Core:EnsureFolders()
    if not self.FS.CanMakeFolder then return false end

    local function ensure(path)
        local exists = false
        if self.FS.IsFolder then
            local ok, result = pcall(self.FS.IsFolder, path)
            exists = ok and result == true
        end
        if not exists then
            pcall(self.FS.MakeFolder, path)
        end
    end

    ensure(self.Config.RootFolder)
    ensure(self.Config.ModuleFolder)
    return true
end

Core:EnsureFolders()

--============================================================
-- MODULE MANAGER
--============================================================

Core.Modules = {
    Records = {},
    SourceToId = {},
    Pending = {},
    DynamicControls = {},
    Accumulator = 0,
    UIReady = false,
}

function Core.Modules:_compile(source, chunkName)
    if type(loadstring) ~= "function" then
        return nil, "loadstring unavailable"
    end

    local chunk, err = loadstring(source, "=" .. tostring(chunkName or "Experiment17Module"))
    if not chunk then
        return nil, err
    end

    local ok, result = pcall(chunk)
    if not ok then
        return nil, result
    end

    if type(result) == "function" then
        local okFactory, descriptor = pcall(result, Core)
        if not okFactory then
            return nil, descriptor
        end
        result = descriptor
    end

    if type(result) ~= "table" then
        return nil, "module must return a descriptor table or descriptor factory function"
    end

    return result
end

function Core.Modules:_resolveTab(descriptor, scope)
    local target = descriptor.TargetTab
    if target and target ~= "" then
        return Core:GetTab(target)
    end

    local name = descriptor.TabName or descriptor.Name or descriptor.Id
    return Core:CreateTab(descriptor.Id, name, descriptor.Order or 100, scope)
end

function Core.Modules:_mount(descriptor, meta)
    descriptor.Id = tostring(descriptor.Id or descriptor.Name or meta.IdHint or "UnnamedModule")
    descriptor.Name = tostring(descriptor.Name or descriptor.Id)
    descriptor.Version = tostring(descriptor.Version or "0.0.0")

    if self.Records[descriptor.Id] then
        self:Unload(descriptor.Id, "replace")
    end

    local targetTab = self:_resolveTab(descriptor, nil)
    if descriptor.TargetTab and not targetTab then
        self.Pending[descriptor.Id] = {
            Descriptor = descriptor,
            Meta = meta,
        }
        Core:Log("Module pending; target tab not loaded:", descriptor.Id, descriptor.TargetTab)
        return false, "pending target tab"
    end

    local scope = Core:CreateScope(descriptor.Id)

    -- If the module owns a tab, create it with this module's cleanup scope.
    if not descriptor.TargetTab then
        targetTab = Core:GetTab(descriptor.TabName or descriptor.Name or descriptor.Id)
        if not targetTab then
            targetTab = Core:CreateTab(descriptor.Id, descriptor.TabName or descriptor.Name or descriptor.Id, descriptor.Order or 100, scope)
        else
            -- Existing tab may have been created during the pre-check without a scope.
            targetTab.__Experiment17Owner = descriptor.Id
            scope:AddCleaner(function()
                if Core.Tabs[targetTab.Name] == targetTab and targetTab.__Experiment17Owner == descriptor.Id then
                    Core.Tabs[targetTab.Name] = nil
                    Core:DestroyTab(targetTab)
                end
            end)
        end
    end

    local record = {
        Id = descriptor.Id,
        Descriptor = descriptor,
        Scope = scope,
        Tab = targetTab,
        SourceKind = meta.SourceKind or "runtime",
        SourceKey = meta.SourceKey,
        SourcePath = meta.SourcePath,
        SourceURL = meta.SourceURL,
        SourceHash = meta.SourceHash,
        LoadedAt = os.clock(),
        Status = "loading",
    }

    self.Records[descriptor.Id] = record
    if record.SourceKey then
        self.SourceToId[record.SourceKey] = descriptor.Id
    end

    local okInit, initError = safeCall(descriptor.Init, Core, scope, targetTab)
    if not okInit then
        Core:Warn("Module Init failed:", descriptor.Id, initError)
        self:Unload(descriptor.Id, "init error")
        return false, initError
    end

    local okStart, startError = safeCall(descriptor.Start, Core, scope, targetTab)
    if not okStart then
        Core:Warn("Module Start failed:", descriptor.Id, startError)
        self:Unload(descriptor.Id, "start error")
        return false, startError
    end

    record.Status = "loaded"
    Core:FixTabOrder()
    Core.Bus:Emit("ModuleLoaded", descriptor.Id, descriptor, record)
    Core:Log("Loaded module:", descriptor.Id, "v" .. descriptor.Version, "[" .. record.SourceKind .. "]")
    self:RetryPending()
    self:RefreshUI()
    return true, record
end

function Core.Modules:LoadSource(source, meta)
    meta = meta or {}
    if type(source) ~= "string" or source:match("^%s*$") then
        return false, "empty module source"
    end

    meta.SourceHash = meta.SourceHash or hashSource(source)
    local descriptor, err = self:_compile(source, meta.SourceKey or meta.SourceURL or meta.SourcePath or meta.IdHint)
    if not descriptor then
        Core:Warn("Module compile failed:", meta.IdHint or meta.SourceKey or "unknown", err)
        return false, err
    end

    return self:_mount(descriptor, meta)
end

function Core.Modules:LoadFile(path, idHint)
    if not Core.FS.Read then
        return false, "readfile unavailable"
    end

    path = normalizePath(path)
    if Core.FS.IsFile then
        local okExists, exists = pcall(Core.FS.IsFile, path)
        if okExists and not exists then
            return false, "file not found: " .. path
        end
    end

    local ok, source = pcall(Core.FS.Read, path)
    if not ok then return false, source end

    return self:LoadSource(source, {
        SourceKind = "local",
        SourceKey = "file:" .. path,
        SourcePath = path,
        IdHint = idHint or basename(path):gsub("%.lua$", ""),
    })
end

function Core.Modules:LoadURL(url, idHint)
    url = tostring(url or "")
    if url == "" then return false, "empty url" end

    local ok, source = pcall(function()
        return game:HttpGet(url, true)
    end)
    if not ok then return false, source end

    return self:LoadSource(source, {
        SourceKind = "remote",
        SourceKey = "url:" .. url,
        SourceURL = url,
        IdHint = idHint,
    })
end

function Core.Modules:Register(descriptor)
    if type(descriptor) ~= "table" then
        return false, "descriptor must be a table"
    end

    return self:_mount(descriptor, {
        SourceKind = "runtime",
        SourceKey = "runtime:" .. tostring(descriptor.Id or descriptor.Name or os.clock()),
        IdHint = descriptor.Id,
    })
end

function Core.Modules:Unload(id, reason)
    id = tostring(id)
    local record = self.Records[id]
    if not record then
        self.Pending[id] = nil
        return false
    end

    record.Status = "unloading"
    safeCall(record.Descriptor.Unload, Core, record.Scope, reason)

    if record.Scope then
        record.Scope:Cleanup()
    end

    if record.SourceKey and self.SourceToId[record.SourceKey] == id then
        self.SourceToId[record.SourceKey] = nil
    end

    self.Records[id] = nil
    Core.ModuleScopes[id] = nil
    Core.Bus:Emit("ModuleUnloaded", id, reason)
    Core:Log("Unloaded module:", id, reason or "")
    self:RefreshUI()
    return true
end

function Core.Modules:Reload(id)
    id = tostring(id)
    local record = self.Records[id]
    if not record then return false, "module not loaded" end

    local sourceKind = record.SourceKind
    local path = record.SourcePath
    local url = record.SourceURL
    local descriptor = record.Descriptor

    self:Unload(id, "reload")

    if sourceKind == "local" and path then
        return self:LoadFile(path, id)
    elseif sourceKind == "remote" and url then
        return self:LoadURL(url, id)
    elseif sourceKind == "runtime" then
        return self:Register(descriptor)
    end

    return false, "unknown source"
end

function Core.Modules:ReloadAll()
    local ids = {}
    for id in pairs(self.Records) do table.insert(ids, id) end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local ok, err = self:Reload(id)
        if not ok then
            Core:Warn("Reload failed:", id, err)
        end
        task.wait()
    end
end

function Core.Modules:RetryPending()
    local pendingIds = {}
    for id in pairs(self.Pending) do table.insert(pendingIds, id) end

    for _, id in ipairs(pendingIds) do
        local item = self.Pending[id]
        if item and item.Descriptor.TargetTab and Core:GetTab(item.Descriptor.TargetTab) then
            self.Pending[id] = nil
            self:_mount(item.Descriptor, item.Meta)
        end
    end
end

function Core.Modules:_loadConfiguredRemoteById(id)
    for _, spec in ipairs(Core.Config.Modules) do
        if tostring(spec.Id) == tostring(id) then
            local url = spec.URL or joinURL(Core.Config.RemoteBase, spec.File)
            if url ~= "" then
                local ok, err = self:LoadURL(url, spec.Id)
                if not ok and err ~= "empty module source" then
                    Core:Warn("Remote fallback failed:", spec.Id, err)
                end
                return ok, err
            end
            break
        end
    end
    return false, "no configured remote module"
end

function Core.Modules:ScanLocal()
    if not Core.FS.Available or not Core.FS.List then
        return false, "filesystem module scanning unavailable"
    end

    Core:EnsureFolders()

    local ok, paths = pcall(Core.FS.List, Core.Config.ModuleFolder)
    if not ok then
        return false, paths
    end

    local seen = {}

    for _, rawPath in ipairs(paths) do
        local path = normalizePath(rawPath)
        if path:lower():sub(-4) == ".lua" then
            local sourceKey = "file:" .. path
            seen[sourceKey] = true

            local okRead, source = pcall(Core.FS.Read, path)
            if okRead and type(source) == "string" then
                local newHash = hashSource(source)
                local loadedId = self.SourceToId[sourceKey]
                local record = loadedId and self.Records[loadedId]

                if not record then
                    self:LoadSource(source, {
                        SourceKind = "local",
                        SourceKey = sourceKey,
                        SourcePath = path,
                        SourceHash = newHash,
                        IdHint = basename(path):gsub("%.lua$", ""),
                    })
                elseif Core.Config.AutoReloadLocal and record.SourceHash ~= newHash then
                    Core:Log("Detected local module change:", path)
                    self:Unload(loadedId, "file changed")
                    self:LoadSource(source, {
                        SourceKind = "local",
                        SourceKey = sourceKey,
                        SourcePath = path,
                        SourceHash = newHash,
                        IdHint = basename(path):gsub("%.lua$", ""),
                    })
                end
            end
        end
    end

    -- If a watched local file is deleted, unload that module.
    if Core.Config.AutoReloadLocal then
        local deleted = {}
        for sourceKey, id in pairs(self.SourceToId) do
            if sourceKey:sub(1, 5) == "file:" and not seen[sourceKey] then
                table.insert(deleted, id)
            end
        end
        for _, id in ipairs(deleted) do
            self:Unload(id, "local file removed")
            self:_loadConfiguredRemoteById(id)
        end
    end

    return true
end

function Core.Modules:LoadConfigured()
    for _, spec in ipairs(Core.Config.Modules) do
        local localPath = joinPath(Core.Config.ModuleFolder, spec.File)
        local loaded = false

        if Core.Config.PreferLocal and Core.FS.Read then
            local exists = true
            if Core.FS.IsFile then
                local okExists, result = pcall(Core.FS.IsFile, localPath)
                exists = okExists and result == true
            end
            if exists then
                local ok = self:LoadFile(localPath, spec.Id)
                loaded = ok == true
            end
        end

        if not loaded then
            local url = spec.URL or joinURL(Core.Config.RemoteBase, spec.File)
            if url ~= "" then
                local ok, err = self:LoadURL(url, spec.Id)
                if not ok then
                    if err == "empty module source" then
                        Core:Log("Remote module is empty; skipped:", spec.Id)
                    else
                        Core:Warn("Remote module failed:", spec.Id, err)
                    end
                end
            else
                Core:Warn("Module not found locally and no remote URL configured:", spec.Id)
            end
        end

        task.wait()
    end

    -- Also picks up extra local add-ons not listed above.
    self:ScanLocal()
end

--============================================================
-- PUBLIC API FOR SEPARATELY EXECUTED LOCAL SCRIPTS
--============================================================

function Core:RegisterModule(descriptor)
    return self.Modules:Register(descriptor)
end

function Core:LoadModuleURL(url, idHint)
    return self.Modules:LoadURL(url, idHint)
end

function Core:LoadModuleFile(path, idHint)
    return self.Modules:LoadFile(path, idHint)
end

function Core:UnloadModule(id, reason)
    return self.Modules:Unload(id, reason)
end

function Core:ReloadModule(id)
    return self.Modules:Reload(id)
end

-- Patch a persistent module state and optionally hot-reload that module so
-- existing UI controls/runtime immediately pick up the new values.
function Core:PatchModuleState(id, patch, reloadNow)
    id = tostring(id)
    if type(patch) ~= "table" then
        return false, "patch must be a table"
    end

    local state = self:GetState(id, {})
    for key, value in pairs(patch) do
        state[key] = value
    end

    if reloadNow and self.Modules and self.Modules.Records[id] then
        return self.Modules:Reload(id)
    end

    return true, state
end

--============================================================
-- MODULE MANAGER TAB
--============================================================

Core.ModuleTab = Core.Library:CreateTab("Modules")
Core.ModuleTab.__Experiment17Order = 9000
if Core.ModuleTab.Button then Core.ModuleTab.Button.LayoutOrder = 9000 end

local ManagerScope = Core:CreateScope("__ModuleManager")
local ManagerSettings = Core:CreateSection(ManagerScope, Core.ModuleTab, "Module Runtime", true, "Modules / Runtime")

ManagerSettings:AddToggle({
    Name = "Prefer Local Modules",
    Flag = "Modules_PreferLocal",
    Default = Core.Config.PreferLocal,
    RequiredGraphics = "Low",
    Description = "Uses Experiment17_Visuals/modules/*.lua before the GitHub modules.",
    Callback = function(value)
        Core.Config.PreferLocal = value == true
    end,
})

ManagerSettings:AddToggle({
    Name = "Auto Reload Local Modules",
    Flag = "Modules_AutoReload",
    Default = Core.Config.AutoReloadLocal,
    RequiredGraphics = "Low",
    Description = "Polls local module source. Only the changed module is unloaded and loaded again.",
    FPSImpact = {-1, 0},
    Callback = function(value)
        Core.Config.AutoReloadLocal = value == true
    end,
})

ManagerSettings:AddSlider({
    Name = "Module Poll Interval",
    Flag = "Modules_PollInterval",
    Min = 0.5,
    Max = 10,
    Default = Core.Config.PollInterval,
    Rounding = 2,
    RequiredGraphics = "Low",
    Description = "Seconds between local module folder scans.",
    Callback = function(value)
        Core.Config.PollInterval = math.max(0.5, tonumber(value) or 1.5)
    end,
})

ManagerSettings:AddInput({
    Name = "Remote Module Base URL",
    Flag = "Modules_RemoteBase",
    Default = Core.Config.RemoteBase,
    Placeholder = "https://raw.githubusercontent.com/.../modules/",
    RequiredGraphics = "Low",
    Description = "Optional fallback base URL for Performance.lua, Visual.lua, Lighting.lua, ESP.lua and other tab modules.",
    Callback = function(value)
        Core.Config.RemoteBase = tostring(value or "")
    end,
})

ManagerSettings:AddButton({
    Name = "Scan Local Modules",
    ButtonText = "Scan",
    RequiredGraphics = "Low",
    Description = "Loads new local modules and checks existing local modules for changes.",
    Callback = function()
        local ok, err = Core.Modules:ScanLocal()
        if not ok then Core:Warn(err) end
    end,
})

ManagerSettings:AddButton({
    Name = "Reload All Modules",
    ButtonText = "Reload",
    RequiredGraphics = "Low",
    Description = "Reloads each loaded tab/add-on module without restarting the UI library.",
    Callback = function()
        task.spawn(function()
            Core.Modules:ReloadAll()
        end)
    end,
})

ManagerSettings:AddButton({
    Name = "Reload GitHub Modules",
    ButtonText = "Fetch",
    RequiredGraphics = "Low",
    Description = "Fetches the configured module list from the GitHub repository again. Local modules still have priority when Prefer Local Modules is enabled.",
    PingImpact = 0,
    Callback = function()
        task.spawn(function()
            for _, spec in ipairs(Core.Config.Modules) do
                local localPath = joinPath(Core.Config.ModuleFolder, spec.File)
                local useLocal = false
                if Core.Config.PreferLocal and Core.FS.IsFile then
                    local okLocal, exists = pcall(Core.FS.IsFile, localPath)
                    useLocal = okLocal and exists == true
                end
                if not useLocal then
                    local current = Core.Modules.Records[spec.Id]
                    if current then
                        Core.Modules:Unload(spec.Id, "github refresh")
                    end
                    local url = spec.URL or joinURL(Core.Config.RemoteBase, spec.File)
                    local ok, err = Core.Modules:LoadURL(url, spec.Id)
                    if not ok and err ~= "empty module source" then
                        Core:Warn("GitHub refresh failed:", spec.Id, err)
                    end
                end
                task.wait(0.05)
            end
        end)
    end,
})

local ManualSection = Core:CreateSection(ManagerScope, Core.ModuleTab, "Manual Module Load", false, "Modules / Manual")
local URLInput = ManualSection:AddInput({
    Name = "Module URL",
    Flag = "Modules_URL",
    Default = "",
    Placeholder = "raw .lua URL",
    RequiredGraphics = "Low",
    Description = "Loads a module descriptor from a URL.",
})

ManualSection:AddButton({
    Name = "Load Module URL",
    ButtonText = "Load",
    RequiredGraphics = "Low",
    Callback = function()
        local ok, err = Core.Modules:LoadURL(URLInput:Get())
        if not ok then Core:Warn("URL module load failed:", err) end
    end,
})

local FileInput = ManualSection:AddInput({
    Name = "Local Module Path",
    Flag = "Modules_FilePath",
    Default = "",
    Placeholder = "Experiment17_Visuals/modules/MyAddon.lua",
    RequiredGraphics = "Low",
    Description = "Loads one local Lua module file when readfile is available.",
})

ManualSection:AddButton({
    Name = "Load Local Module",
    ButtonText = "Load",
    RequiredGraphics = "Low",
    Callback = function()
        local ok, err = Core.Modules:LoadFile(FileInput:Get())
        if not ok then Core:Warn("Local module load failed:", err) end
    end,
})

local LoadedSection = Core:CreateSection(ManagerScope, Core.ModuleTab, "Loaded Modules", false, "Modules / Loaded")
Core.Modules.LoadedSection = LoadedSection

function Core.Modules:RefreshUI()
    if not self.LoadedSection then return end

    for _, control in ipairs(self.DynamicControls) do
        pcall(function()
            if control and control.Holder and control.Holder.Parent then
                control.Holder:Destroy()
            end
            removeArrayValue(Core.Library.Controls, control)
            removeArrayValue(Core.Library.GatedControls, control)
            if control and control.Section and control.Section.Controls then
                removeArrayValue(control.Section.Controls, control)
            end
            if control and control.Flag and Core.Library.ControlsByFlag
                and Core.Library.ControlsByFlag[control.Flag] == control then
                Core.Library.ControlsByFlag[control.Flag] = nil
            end
            if ManagerScope and ManagerScope.Controls then
                removeArrayValue(ManagerScope.Controls, control)
            end
        end)
    end
    table.clear(self.DynamicControls)

    local ids = {}
    for id in pairs(self.Records) do table.insert(ids, id) end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local record = self.Records[id]
        local descriptor = record.Descriptor
        local control = self.LoadedSection:AddButton({
            Name = string.format("%s  v%s  [%s]", id, descriptor.Version or "0.0.0", record.SourceKind or "?") ,
            ButtonText = "Reload",
            RequiredGraphics = "Low",
            Description = record.SourcePath or record.SourceURL or "Runtime-registered module",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function()
                task.spawn(function()
                    local ok, err = Core.Modules:Reload(id)
                    if not ok then Core:Warn("Reload failed:", id, err) end
                end)
            end,
        })
        table.insert(self.DynamicControls, control)
    end
end

Core.Modules.UIReady = true
Core:FixTabOrder()

--============================================================
-- AUTO RELOAD WATCHER
--============================================================

Core.Connections.ModuleWatcher = Core.Services.RunService.Heartbeat:Connect(function(dt)
    if Core.Unloaded then return end
    if not Core.Config.AutoReloadLocal or not Core.FS.Available then return end

    Core.Modules.Accumulator += dt
    if Core.Modules.Accumulator < Core.Config.PollInterval then return end
    Core.Modules.Accumulator = 0

    local ok, err = Core.Modules:ScanLocal()
    if not ok and err then
        Core:Warn("Local module scan failed:", err)
    end
end)

Core.Connections.CameraWatcher = Core.Services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Core.Camera = Core.Services.Workspace.CurrentCamera
    Core.Bus:Emit("CameraChanged", Core.Camera)
end)

--============================================================
-- LOAD MODULES
--============================================================

task.spawn(function()
    Core.Modules:LoadConfigured()
    Core:FixTabOrder()

    local visual = Core:GetTab("Visual")
    if visual and visual.Select then
        visual:Select()
    elseif Core.ModuleTab and Core.ModuleTab.Select then
        Core.ModuleTab:Select()
    end
end)

--============================================================
-- UNLOAD
--============================================================

function Core:Unload(reason)
    if self.Unloaded then return end
    self.Unloaded = true

    self.Bus:Emit("CoreUnloading", reason)

    local ids = {}
    for id in pairs(self.Modules.Records) do table.insert(ids, id) end
    for _, id in ipairs(ids) do
        self.Modules:Unload(id, reason or "core unload")
    end

    if ManagerScope then
        ManagerScope:Cleanup()
    end

    for _, connection in pairs(self.Connections) do
        pcall(function()
            if connection and connection.Disconnect then connection:Disconnect() end
        end)
    end
    table.clear(self.Connections)

    for _, instance in ipairs(self.Instances) do
        pcall(function()
            if instance and instance.Parent then instance:Destroy() end
        end)
    end
    table.clear(self.Instances)

    if self.Library and not self.Library.Unloaded and type(self.Library.Unload) == "function" then
        pcall(function()
            self.Library:Unload()
        end)
    end

    if ENV.Experiment17 == self then
        ENV.Experiment17 = nil
    end
end

Core:Log("Modular loader ready for", Core.Config.Repository, "| local watcher:", Core.FS.Available and "available" or "unavailable")
return Core
