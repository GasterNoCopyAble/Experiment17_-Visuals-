--[[
    Experiment 17 - Performance module
    Target: Experiment17 Modular Loader v0.3 + Experiment17_GuiLib v19

    Goals:
      * Real client-side FPS reduction controls with reversible baselines.
      * GuiLib v19 Performance profile integration.
      * Presets that can lower the cost of Experiment17's own modules.
      * Batched scene scans so applying a preset does not freeze for one long frame.

    Notes:
      * FPS gains depend heavily on the game/map/GPU. Metadata is an estimate only.
      * Scene overrides are local-client presentation changes.
      * Simplify Materials / Hide Textures may conflict visually with Visual.lua overrides.
]]

return {
    Id = "Performance",
    Name = "Performance",
    Version = "2.0.0-v19",
    Order = 5,

    Init = function(Context, Scope, Tab)
        local S = Context.Services
        local Players = S.Players
        local RunService = S.RunService
        local Lighting = S.Lighting
        local Workspace = S.Workspace
        local LocalPlayer = Context.LocalPlayer
        local Terrain = Workspace:FindFirstChildOfClass("Terrain") or Workspace.Terrain
        local Library = Context.Library

        local State = Context:GetState("Performance", {
            Preset = "Balanced FPS",
            UseV19PerformanceProfile = true,
            FollowStartupWizard = true,

            DisableGlobalShadows = false,
            DisablePostFX = false,
            DisableAtmosphere = false,
            DisableClouds = false,
            TerrainLowCost = false,

            DisableCastShadows = false,
            DisableParticles = false,
            DisableTrails = false,
            DisableBeams = false,
            HideTextures = false,
            SimplifyMaterials = false,
            ScanBatch = 350,

            OptimizeESP = true,
            OptimizeWorld = true,
            OptimizePlayerFX = true,
            OptimizeTrajectory = true,

            FPSCapEnabled = false,
            FPSCap = 240,

            -- Adaptive mode never hides/removes features. It throttles numeric budgets.
            AdaptiveFPS = false,
            AdaptiveTargetFPS = 90,
            AdaptiveHysteresis = 8,
            AdaptiveSampleTime = 1.0,
            AdaptiveRecoverySamples = 3,
            AdaptiveProtectPlayerFX = true,
            PreservePlayerFXInHighFPS = true,
        })

        local R = {
            Dead = false,
            ScanTokens = {},
            Baseline = {
                GlobalShadows = nil,
                PostFX = setmetatable({}, {__mode = "k"}),
                Atmosphere = setmetatable({}, {__mode = "k"}),
                Clouds = setmetatable({}, {__mode = "k"}),
                CastShadow = setmetatable({}, {__mode = "k"}),
                Emitters = setmetatable({}, {__mode = "k"}),
                Trails = setmetatable({}, {__mode = "k"}),
                Beams = setmetatable({}, {__mode = "k"}),
                Decals = setmetatable({}, {__mode = "k"}),
                MeshTextures = setmetatable({}, {__mode = "k"}),
                SurfaceAppearance = setmetatable({}, {__mode = "k"}),
                Materials = setmetatable({}, {__mode = "k"}),
                Terrain = {},
            },
            ModuleSnapshots = {},
            UIProfileSnapshot = nil,
            FPSFrames = 0,
            FPSTime = 0,
            FPS = 0,
            Controls = {},
            AdaptiveAccumulator = 0,
            AdaptiveRecovery = 0,
            AdaptiveLevel = 0,
            AdaptiveBaseline = nil,
        }

        local POST_FX_CLASSES = {
            BloomEffect = true,
            BlurEffect = true,
            ColorCorrectionEffect = true,
            DepthOfFieldEffect = true,
            SunRaysEffect = true,
        }

        local function notify(text, kind)
            if Library and type(Library.Notify) == "function" then
                pcall(function()
                    Library:Notify({
                        Title = "Experiment 17 • Performance",
                        Text = tostring(text),
                        Type = kind or "Info",
                        Duration = 4,
                    })
                end)
            else
                Context:Log("[Performance]", text)
            end
        end

        local function safeGet(object, property, fallback)
            local ok, value = pcall(function()
                return object[property]
            end)
            if ok then return value end
            return fallback
        end

        local function safeSet(object, property, value)
            return pcall(function()
                object[property] = value
            end)
        end

        local function cloneFlat(tbl)
            local out = {}
            for k, v in pairs(tbl or {}) do
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

        local function isExperiment17Object(object)
            local current = object
            while current and current ~= game do
                if tostring(current.Name):match("^Experiment17") then
                    return true
                end
                current = current.Parent
            end
            return false
        end

        local function isCharacterObject(object)
            local model = object and object:FindFirstAncestorOfClass("Model")
            return model and Players:GetPlayerFromCharacter(model) ~= nil
        end

        local function isMapPart(object)
            return object
                and object:IsA("BasePart")
                and object.Parent ~= nil
                and not isExperiment17Object(object)
                and not isCharacterObject(object)
        end

        local function nextToken(key)
            R.ScanTokens[key] = (R.ScanTokens[key] or 0) + 1
            return R.ScanTokens[key]
        end

        local function scanWorkspace(key, callback)
            local token = nextToken(key)
            task.spawn(function()
                local list = Workspace:GetDescendants()
                local batch = math.max(50, math.floor(tonumber(State.ScanBatch) or 350))
                for i, object in ipairs(list) do
                    if R.Dead or R.ScanTokens[key] ~= token then return end
                    callback(object)
                    if i % batch == 0 then task.wait() end
                end
            end)
        end

        local function scanLighting(key, callback)
            local token = nextToken(key)
            task.spawn(function()
                local list = Lighting:GetDescendants()
                for i, object in ipairs(list) do
                    if R.Dead or R.ScanTokens[key] ~= token then return end
                    callback(object)
                    if i % 120 == 0 then task.wait() end
                end
            end)
        end

        local function restoreWeakTable(tbl, restoreFn)
            for object, value in pairs(tbl) do
                if object and object.Parent then
                    pcall(restoreFn, object, value)
                end
            end
            table.clear(tbl)
        end

        --====================================================
        -- RENDER / LIGHTING OPTIMIZERS
        --====================================================

        local function setGlobalShadows(disable)
            if disable then
                if R.Baseline.GlobalShadows == nil then
                    R.Baseline.GlobalShadows = Lighting.GlobalShadows
                end
                Lighting.GlobalShadows = false
            elseif R.Baseline.GlobalShadows ~= nil then
                Lighting.GlobalShadows = R.Baseline.GlobalShadows
                R.Baseline.GlobalShadows = nil
            end
        end

        local function applyPostFX(object)
            if not State.DisablePostFX or not POST_FX_CLASSES[object.ClassName] then return end
            if R.Baseline.PostFX[object] == nil then
                local enabled = safeGet(object, "Enabled", nil)
                if enabled == nil then return end
                R.Baseline.PostFX[object] = enabled
            end
            safeSet(object, "Enabled", false)
        end

        local function setPostFX(disable)
            nextToken("PostFX")
            if disable then
                scanLighting("PostFX", applyPostFX)
            else
                restoreWeakTable(R.Baseline.PostFX, function(object, enabled)
                    object.Enabled = enabled
                end)
            end
        end

        local function applyAtmosphere(object)
            if not State.DisableAtmosphere or not object:IsA("Atmosphere") then return end
            if R.Baseline.Atmosphere[object] == nil then
                R.Baseline.Atmosphere[object] = {
                    Density = object.Density,
                    Haze = object.Haze,
                    Glare = object.Glare,
                }
            end
            object.Density = 0
            object.Haze = 0
            object.Glare = 0
        end

        local function setAtmosphere(disable)
            nextToken("Atmosphere")
            if disable then
                scanLighting("Atmosphere", applyAtmosphere)
            else
                restoreWeakTable(R.Baseline.Atmosphere, function(object, old)
                    object.Density = old.Density
                    object.Haze = old.Haze
                    object.Glare = old.Glare
                end)
            end
        end

        local function applyClouds(object)
            if not State.DisableClouds or not object:IsA("Clouds") then return end
            if R.Baseline.Clouds[object] == nil then
                R.Baseline.Clouds[object] = {
                    Enabled = safeGet(object, "Enabled", nil),
                    Cover = safeGet(object, "Cover", 0),
                    Density = safeGet(object, "Density", 0),
                }
            end
            if not safeSet(object, "Enabled", false) then
                safeSet(object, "Cover", 0)
                safeSet(object, "Density", 0)
            end
        end

        local function setClouds(disable)
            local token = nextToken("Clouds")
            if disable then
                local function scanCloudRoot(root)
                    for i, object in ipairs(root:GetDescendants()) do
                        if R.Dead or R.ScanTokens.Clouds ~= token then return false end
                        applyClouds(object)
                        if i % 120 == 0 then task.wait() end
                    end
                    return true
                end
                task.spawn(function()
                    if not scanCloudRoot(Lighting) then return end
                    if Terrain then scanCloudRoot(Terrain) end
                end)
            else
                restoreWeakTable(R.Baseline.Clouds, function(object, old)
                    if old.Enabled ~= nil then safeSet(object, "Enabled", old.Enabled) end
                    safeSet(object, "Cover", old.Cover)
                    safeSet(object, "Density", old.Density)
                end)
            end
        end

        local function setTerrainLowCost(enabled)
            if not Terrain then return end
            local props = {
                Decoration = false,
                WaterWaveSize = 0,
                WaterWaveSpeed = 0,
                WaterReflectance = 0,
            }

            if enabled then
                for property, value in pairs(props) do
                    if R.Baseline.Terrain[property] == nil then
                        R.Baseline.Terrain[property] = safeGet(Terrain, property, nil)
                    end
                    safeSet(Terrain, property, value)
                end
            else
                for property, value in pairs(R.Baseline.Terrain) do
                    if value ~= nil then safeSet(Terrain, property, value) end
                end
                table.clear(R.Baseline.Terrain)
            end
        end

        --====================================================
        -- WORKSPACE OPTIMIZERS
        --====================================================

        local function applyCastShadow(object)
            if not State.DisableCastShadows or not isMapPart(object) then return end
            if R.Baseline.CastShadow[object] == nil then
                R.Baseline.CastShadow[object] = object.CastShadow
            end
            object.CastShadow = false
        end

        local function setCastShadows(disable)
            nextToken("CastShadow")
            if disable then
                scanWorkspace("CastShadow", applyCastShadow)
            else
                restoreWeakTable(R.Baseline.CastShadow, function(object, old)
                    object.CastShadow = old
                end)
            end
        end

        local function applyParticle(object)
            if not State.DisableParticles or not object:IsA("ParticleEmitter") or isExperiment17Object(object) then return end
            if R.Baseline.Emitters[object] == nil then
                R.Baseline.Emitters[object] = object.Enabled
            end
            object.Enabled = false
        end

        local function setParticles(disable)
            nextToken("Particles")
            if disable then
                scanWorkspace("Particles", applyParticle)
            else
                restoreWeakTable(R.Baseline.Emitters, function(object, old)
                    object.Enabled = old
                end)
            end
        end

        local function applyTrail(object)
            if not State.DisableTrails or not object:IsA("Trail") or isExperiment17Object(object) then return end
            if R.Baseline.Trails[object] == nil then
                R.Baseline.Trails[object] = object.Enabled
            end
            object.Enabled = false
        end

        local function setTrails(disable)
            nextToken("Trails")
            if disable then
                scanWorkspace("Trails", applyTrail)
            else
                restoreWeakTable(R.Baseline.Trails, function(object, old)
                    object.Enabled = old
                end)
            end
        end

        local function applyBeam(object)
            if not State.DisableBeams or not object:IsA("Beam") or isExperiment17Object(object) then return end
            if R.Baseline.Beams[object] == nil then
                R.Baseline.Beams[object] = object.Enabled
            end
            object.Enabled = false
        end

        local function setBeams(disable)
            nextToken("Beams")
            if disable then
                scanWorkspace("Beams", applyBeam)
            else
                restoreWeakTable(R.Baseline.Beams, function(object, old)
                    object.Enabled = old
                end)
            end
        end

        local function applyTexture(object)
            if not State.HideTextures or isExperiment17Object(object) or isCharacterObject(object) then return end

            if object:IsA("Decal") or object:IsA("Texture") then
                if R.Baseline.Decals[object] == nil then
                    R.Baseline.Decals[object] = object.Transparency
                end
                object.Transparency = 1
                return
            end

            if object:IsA("MeshPart") and not isCharacterObject(object) then
                if R.Baseline.MeshTextures[object] == nil then
                    local old = safeGet(object, "TextureID", nil)
                    if old == nil then return end
                    R.Baseline.MeshTextures[object] = old
                end
                safeSet(object, "TextureID", "")
                return
            end

            if object:IsA("SurfaceAppearance") then
                if R.Baseline.SurfaceAppearance[object] == nil then
                    R.Baseline.SurfaceAppearance[object] = {
                        ColorMap = safeGet(object, "ColorMap", ""),
                        NormalMap = safeGet(object, "NormalMap", ""),
                        RoughnessMap = safeGet(object, "RoughnessMap", ""),
                        MetalnessMap = safeGet(object, "MetalnessMap", ""),
                    }
                end
                safeSet(object, "ColorMap", "")
                safeSet(object, "NormalMap", "")
                safeSet(object, "RoughnessMap", "")
                safeSet(object, "MetalnessMap", "")
            end
        end

        local function setTextures(disable)
            nextToken("Textures")
            if disable then
                scanWorkspace("Textures", applyTexture)
            else
                restoreWeakTable(R.Baseline.Decals, function(object, old)
                    object.Transparency = old
                end)
                restoreWeakTable(R.Baseline.MeshTextures, function(object, old)
                    safeSet(object, "TextureID", old)
                end)
                restoreWeakTable(R.Baseline.SurfaceAppearance, function(object, old)
                    safeSet(object, "ColorMap", old.ColorMap)
                    safeSet(object, "NormalMap", old.NormalMap)
                    safeSet(object, "RoughnessMap", old.RoughnessMap)
                    safeSet(object, "MetalnessMap", old.MetalnessMap)
                end)
            end
        end

        local function applyMaterial(object)
            if not State.SimplifyMaterials or not isMapPart(object) then return end
            if R.Baseline.Materials[object] == nil then
                R.Baseline.Materials[object] = {
                    Material = object.Material,
                    MaterialVariant = safeGet(object, "MaterialVariant", ""),
                }
            end
            object.Material = Enum.Material.Plastic
            safeSet(object, "MaterialVariant", "")
        end

        local function setMaterials(disable)
            nextToken("Materials")
            if disable then
                scanWorkspace("Materials", applyMaterial)
            else
                restoreWeakTable(R.Baseline.Materials, function(object, old)
                    object.Material = old.Material
                    safeSet(object, "MaterialVariant", old.MaterialVariant)
                end)
            end
        end

        local function applyActiveToObject(object)
            if State.DisableClouds then applyClouds(object) end
            if State.DisableCastShadows then applyCastShadow(object) end
            if State.DisableParticles then applyParticle(object) end
            if State.DisableTrails then applyTrail(object) end
            if State.DisableBeams then applyBeam(object) end
            if State.HideTextures then applyTexture(object) end
            if State.SimplifyMaterials then applyMaterial(object) end
        end

        local function rescanActive()
            if State.DisablePostFX then setPostFX(true) end
            if State.DisableAtmosphere then setAtmosphere(true) end
            if State.DisableClouds then setClouds(true) end
            if State.DisableCastShadows then setCastShadows(true) end
            if State.DisableParticles then setParticles(true) end
            if State.DisableTrails then setTrails(true) end
            if State.DisableBeams then setBeams(true) end
            if State.HideTextures then setTextures(true) end
            if State.SimplifyMaterials then setMaterials(true) end
        end

        --====================================================
        -- EXPERIMENT17 MODULE COST PROFILES
        --====================================================

        local MODULE_IDS = {"Visual", "Lighting", "ESP", "World", "Player", "Trajectory", "Waypoints"}

        local function snapshotModuleStates()
            if next(R.ModuleSnapshots) ~= nil then return end
            for _, id in ipairs(MODULE_IDS) do
                R.ModuleSnapshots[id] = cloneFlat(Context:GetState(id, {}))
            end
        end

        local function reloadModules(ids)
            task.spawn(function()
                for _, id in ipairs(ids) do
                    if not R.Dead and Context.Modules and Context.Modules.Records[id] then
                        local ok, err = Context.Modules:Reload(id)
                        if not ok then Context:Warn("Performance reload failed:", id, err) end
                        task.wait(0.04)
                    end
                end
            end)
        end

        local function patchState(id, patch)
            local state = Context:GetState(id, {})
            for key, value in pairs(patch) do
                state[key] = value
            end
        end

        local function applyModuleOptimization(kind)
            snapshotModuleStates()

            local touched = {}
            local function patch(id, values)
                patchState(id, values)
                touched[id] = true
            end

            if kind == "Balanced FPS" then
                if State.OptimizeESP then patch("ESP", {
                    UpdateRate = 24,
                    MaxRenderedPlayers = 24,
                    FarLOD = 750,
                    Skeleton = false,
                    ESP3D = false,
                    PlayerTrails = false,
                }) end
                if State.OptimizeTrajectory then patch("Trajectory", {
                    UpdateRate = 16,
                    PredictionSamples = 18,
                    MaxPlayers = 8,
                }) end
                if State.OptimizeWorld then patch("World", {
                    WireframeMaxParts = math.min(80, tonumber(Context:GetState("World", {}).WireframeMaxParts) or 80),
                    RefreshRate = math.max(1.25, tonumber(Context:GetState("World", {}).RefreshRate) or 1.25),
                }) end

            elseif kind == "High FPS" then
                if State.OptimizeESP then patch("ESP", {
                    UpdateRate = 18,
                    MaxRenderedPlayers = 18,
                    FarLOD = 600,
                    Skeleton = false,
                    ESP3D = false,
                    Chams = false,
                    PlayerTrails = false,
                    Radar = false,
                    ToolESP = false,
                    DepthBased = false,
                    Occlusion = false,
                }) end
                if State.OptimizeWorld then patch("World", {
                    Wireframe = false,
                    Inspector = false,
                    MovementEcho = false,
                    MaxParts = 300,
                    RefreshRate = 1.5,
                }) end
                if State.OptimizePlayerFX then
                    if State.PreservePlayerFXInHighFPS then
                        local ps = Context:GetState("Player", {})
                        patch("Player", {
                            TrailLayers = 1,
                            ParticleRate = math.min(tonumber(ps.ParticleRate) or 22, 12),
                            AfterimageInterval = math.max(tonumber(ps.AfterimageInterval) or 0.09, 0.16),
                            AfterimageMaxActive = math.min(tonumber(ps.AfterimageMaxActive) or 12, 7),
                        })
                    else
                        patch("Player", {
                            Particles = false,
                            Afterimage = false,
                            ToolTrails = false,
                            TrailLayers = 1,
                        })
                    end
                end
                if State.OptimizeTrajectory then patch("Trajectory", {
                    UpdateRate = 12,
                    PredictionSamples = 12,
                    MaxPlayers = 5,
                }) end
                patch("Visual", {
                    CursorTrail = false,
                    Scanlines = false,
                    Grain = false,
                })
                patch("Lighting", {
                    Rainbow = false,
                    WeatherEnabled = false,
                })

            elseif kind == "Potato" then
                if State.OptimizeESP then patch("ESP", {
                    UpdateRate = 12,
                    MaxRenderedPlayers = 12,
                    FarLOD = 450,
                    Skeleton = false,
                    ESP3D = false,
                    Chams = false,
                    Tracers = false,
                    PlayerTrails = false,
                    Radar = false,
                    ToolESP = false,
                    DepthBased = false,
                    Occlusion = false,
                    DamageVisualizer = false,
                }) end
                if State.OptimizeWorld then patch("World", {
                    Wireframe = false,
                    Inspector = false,
                    MovementEcho = false,
                    XRay = false,
                }) end
                if State.OptimizePlayerFX then patch("Player", {
                    Chams = false,
                    Trail = false,
                    Particles = false,
                    Afterimage = false,
                    ToolTrails = false,
                }) end
                if State.OptimizeTrajectory then patch("Trajectory", {
                    Enabled = false,
                    UpdateRate = 10,
                    PredictionSamples = 8,
                    MaxPlayers = 3,
                }) end
                patch("Visual", {
                    CursorTrail = false,
                    ScreenFX = false,
                    ScreenRainbow = false,
                    Vignette = false,
                    Scanlines = false,
                    Grain = false,
                    Letterbox = false,
                })
                patch("Lighting", {
                    Preset = "Performance",
                    Rainbow = false,
                    WeatherEnabled = false,
                    Lightning = false,
                })
                patch("Waypoints", {
                    RouteEnabled = false,
                    ShowCards = false,
                    MaxRenderDistance = 3000,
                })
            end

            local ids = {}
            for id in pairs(touched) do table.insert(ids, id) end
            table.sort(ids)
            reloadModules(ids)
        end

        local function restoreModuleStates()
            if next(R.ModuleSnapshots) == nil then return end
            local ids = {}
            for id, snapshot in pairs(R.ModuleSnapshots) do
                local state = Context:GetState(id, {})
                table.clear(state)
                for key, value in pairs(cloneFlat(snapshot)) do
                    state[key] = value
                end
                table.insert(ids, id)
            end
            table.clear(R.ModuleSnapshots)
            table.sort(ids)
            reloadModules(ids)
        end

        --====================================================
        -- ADAPTIVE FPS BUDGET
        --====================================================

        local ADAPTIVE_FIELDS = {
            ESP = {"UpdateRate", "MaxRenderedPlayers", "FarLOD", "ToolRefreshRate", "OcclusionRate"},
            Trajectory = {"UpdateRate", "PredictionSamples", "MaxPlayers"},
            World = {"MaxParts", "RefreshRate", "WireframeMaxParts"},
            Player = {"TrailLayers", "ParticleRate", "AfterimageInterval", "AfterimageMaxActive"},
        }

        local ADAPTIVE_FLAGS = {
            ["ESP.UpdateRate"] = "ESP_UpdateRate",
            ["ESP.MaxRenderedPlayers"] = "ESP_MaxPlayers",
            ["ESP.FarLOD"] = "ESP_FarLOD",
            ["ESP.ToolRefreshRate"] = "ESP_ToolRefresh",
            ["ESP.OcclusionRate"] = "ESP_OcclusionRate",
            ["Trajectory.UpdateRate"] = "Trajectory_UpdateRate",
            ["Trajectory.PredictionSamples"] = "Trajectory_PredictionSamples",
            ["Trajectory.MaxPlayers"] = "Trajectory_MaxPlayers",
            ["World.MaxParts"] = "World_MaxParts",
            ["World.RefreshRate"] = "World_RefreshRate",
            ["World.WireframeMaxParts"] = "World_WireMaxParts",
            ["Player.TrailLayers"] = "Player_TrailLayers",
            ["Player.ParticleRate"] = "Player_ParticleRate",
            ["Player.AfterimageInterval"] = "Player_AfterInterval",
            ["Player.AfterimageMaxActive"] = "Player_AfterMax",
        }

        local function captureAdaptiveBaseline()
            if R.AdaptiveBaseline then return end
            R.AdaptiveBaseline = {}
            for moduleId, fields in pairs(ADAPTIVE_FIELDS) do
                local state = Context:GetState(moduleId, {})
                local snap = {}
                for _, key in ipairs(fields) do
                    snap[key] = state[key]
                end
                R.AdaptiveBaseline[moduleId] = snap
            end
        end

        local function setAdaptiveValue(moduleId, key, value)
            local state = Context:GetState(moduleId, {})
            state[key] = value
            local flag = ADAPTIVE_FLAGS[moduleId .. "." .. key]
            local control = flag and Library and Library.ControlsByFlag and Library.ControlsByFlag[flag]
            if control and type(control.Set) == "function" then
                pcall(function() control:Set(value, true) end)
            end
        end

        local function baselineValue(moduleId, key, fallback)
            local module = R.AdaptiveBaseline and R.AdaptiveBaseline[moduleId]
            local value = module and module[key]
            if value == nil then value = fallback end
            return value
        end

        local function restoreAdaptiveBudget()
            if not R.AdaptiveBaseline then
                R.AdaptiveLevel = 0
                return
            end
            for moduleId, values in pairs(R.AdaptiveBaseline) do
                for key, value in pairs(values) do
                    if value ~= nil then setAdaptiveValue(moduleId, key, value) end
                end
            end
            R.AdaptiveBaseline = nil
            R.AdaptiveLevel = 0
            R.AdaptiveRecovery = 0
            if R.Controls.AdaptiveStatus and R.Controls.AdaptiveStatus.Set then
                R.Controls.AdaptiveStatus:Set("Adaptive: off / restored")
            end
        end

        local function adaptiveFloor(moduleId, key, value)
            local base = tonumber(baselineValue(moduleId, key, value)) or value
            return math.min(base, value)
        end

        local function adaptiveCeil(moduleId, key, value)
            local base = tonumber(baselineValue(moduleId, key, value)) or value
            return math.max(base, value)
        end

        local function applyAdaptiveLevel(level)
            captureAdaptiveBaseline()
            level = math.clamp(math.floor(tonumber(level) or 0), 0, 3)
            if R.AdaptiveLevel == level then return end
            R.AdaptiveLevel = level

            if level == 0 then
                for moduleId, values in pairs(R.AdaptiveBaseline) do
                    for key, value in pairs(values) do
                        if value ~= nil then setAdaptiveValue(moduleId, key, value) end
                    end
                end
            elseif level == 1 then
                setAdaptiveValue("ESP", "UpdateRate", adaptiveFloor("ESP", "UpdateRate", 24))
                setAdaptiveValue("ESP", "MaxRenderedPlayers", adaptiveFloor("ESP", "MaxRenderedPlayers", 24))
                setAdaptiveValue("ESP", "FarLOD", adaptiveFloor("ESP", "FarLOD", 750))
                setAdaptiveValue("ESP", "ToolRefreshRate", adaptiveCeil("ESP", "ToolRefreshRate", 0.45))
                setAdaptiveValue("ESP", "OcclusionRate", adaptiveCeil("ESP", "OcclusionRate", 0.14))
                setAdaptiveValue("Trajectory", "UpdateRate", adaptiveFloor("Trajectory", "UpdateRate", 18))
                setAdaptiveValue("Trajectory", "PredictionSamples", adaptiveFloor("Trajectory", "PredictionSamples", 18))
                setAdaptiveValue("Trajectory", "MaxPlayers", adaptiveFloor("Trajectory", "MaxPlayers", 8))
                setAdaptiveValue("World", "MaxParts", adaptiveFloor("World", "MaxParts", 500))
                setAdaptiveValue("World", "RefreshRate", adaptiveCeil("World", "RefreshRate", 1.15))
                setAdaptiveValue("World", "WireframeMaxParts", adaptiveFloor("World", "WireframeMaxParts", 80))
                if State.AdaptiveProtectPlayerFX then
                    setAdaptiveValue("Player", "TrailLayers", adaptiveFloor("Player", "TrailLayers", 2))
                    setAdaptiveValue("Player", "ParticleRate", adaptiveFloor("Player", "ParticleRate", 18))
                    setAdaptiveValue("Player", "AfterimageInterval", adaptiveCeil("Player", "AfterimageInterval", 0.11))
                    setAdaptiveValue("Player", "AfterimageMaxActive", adaptiveFloor("Player", "AfterimageMaxActive", 10))
                end
            elseif level == 2 then
                setAdaptiveValue("ESP", "UpdateRate", adaptiveFloor("ESP", "UpdateRate", 18))
                setAdaptiveValue("ESP", "MaxRenderedPlayers", adaptiveFloor("ESP", "MaxRenderedPlayers", 18))
                setAdaptiveValue("ESP", "FarLOD", adaptiveFloor("ESP", "FarLOD", 600))
                setAdaptiveValue("ESP", "ToolRefreshRate", adaptiveCeil("ESP", "ToolRefreshRate", 0.65))
                setAdaptiveValue("ESP", "OcclusionRate", adaptiveCeil("ESP", "OcclusionRate", 0.20))
                setAdaptiveValue("Trajectory", "UpdateRate", adaptiveFloor("Trajectory", "UpdateRate", 12))
                setAdaptiveValue("Trajectory", "PredictionSamples", adaptiveFloor("Trajectory", "PredictionSamples", 12))
                setAdaptiveValue("Trajectory", "MaxPlayers", adaptiveFloor("Trajectory", "MaxPlayers", 5))
                setAdaptiveValue("World", "MaxParts", adaptiveFloor("World", "MaxParts", 320))
                setAdaptiveValue("World", "RefreshRate", adaptiveCeil("World", "RefreshRate", 1.6))
                setAdaptiveValue("World", "WireframeMaxParts", adaptiveFloor("World", "WireframeMaxParts", 55))
                if State.AdaptiveProtectPlayerFX then
                    setAdaptiveValue("Player", "TrailLayers", adaptiveFloor("Player", "TrailLayers", 2))
                    setAdaptiveValue("Player", "ParticleRate", adaptiveFloor("Player", "ParticleRate", 12))
                    setAdaptiveValue("Player", "AfterimageInterval", adaptiveCeil("Player", "AfterimageInterval", 0.16))
                    setAdaptiveValue("Player", "AfterimageMaxActive", adaptiveFloor("Player", "AfterimageMaxActive", 7))
                end
            else
                setAdaptiveValue("ESP", "UpdateRate", adaptiveFloor("ESP", "UpdateRate", 12))
                setAdaptiveValue("ESP", "MaxRenderedPlayers", adaptiveFloor("ESP", "MaxRenderedPlayers", 12))
                setAdaptiveValue("ESP", "FarLOD", adaptiveFloor("ESP", "FarLOD", 450))
                setAdaptiveValue("ESP", "ToolRefreshRate", adaptiveCeil("ESP", "ToolRefreshRate", 0.9))
                setAdaptiveValue("ESP", "OcclusionRate", adaptiveCeil("ESP", "OcclusionRate", 0.28))
                setAdaptiveValue("Trajectory", "UpdateRate", adaptiveFloor("Trajectory", "UpdateRate", 8))
                setAdaptiveValue("Trajectory", "PredictionSamples", adaptiveFloor("Trajectory", "PredictionSamples", 8))
                setAdaptiveValue("Trajectory", "MaxPlayers", adaptiveFloor("Trajectory", "MaxPlayers", 3))
                setAdaptiveValue("World", "MaxParts", adaptiveFloor("World", "MaxParts", 180))
                setAdaptiveValue("World", "RefreshRate", adaptiveCeil("World", "RefreshRate", 2.2))
                setAdaptiveValue("World", "WireframeMaxParts", adaptiveFloor("World", "WireframeMaxParts", 35))
                if State.AdaptiveProtectPlayerFX then
                    setAdaptiveValue("Player", "TrailLayers", 1)
                    setAdaptiveValue("Player", "ParticleRate", adaptiveFloor("Player", "ParticleRate", 8))
                    setAdaptiveValue("Player", "AfterimageInterval", adaptiveCeil("Player", "AfterimageInterval", 0.23))
                    setAdaptiveValue("Player", "AfterimageMaxActive", adaptiveFloor("Player", "AfterimageMaxActive", 5))
                end
            end

            if R.Controls.AdaptiveStatus and R.Controls.AdaptiveStatus.Set then
                local names = {"Full quality", "Light throttle", "Medium throttle", "Heavy throttle"}
                R.Controls.AdaptiveStatus:Set(string.format("Adaptive L%d • %s", level, names[level + 1]))
            end
        end

        local function updateAdaptiveFPS()
            if not State.AdaptiveFPS or R.FPS <= 0 then return end
            local target = math.max(30, tonumber(State.AdaptiveTargetFPS) or 90)
            local hysteresis = math.max(2, tonumber(State.AdaptiveHysteresis) or 8)
            local low = target - hysteresis
            local high = target + hysteresis

            if R.FPS < low then
                R.AdaptiveRecovery = 0
                applyAdaptiveLevel(math.min(3, R.AdaptiveLevel + 1))
            elseif R.FPS > high then
                R.AdaptiveRecovery += 1
                if R.AdaptiveRecovery >= math.max(1, math.floor(State.AdaptiveRecoverySamples or 3)) then
                    R.AdaptiveRecovery = 0
                    applyAdaptiveLevel(math.max(0, R.AdaptiveLevel - 1))
                end
            else
                R.AdaptiveRecovery = 0
            end
        end

        --====================================================
        -- PRESETS / RESTORE
        --====================================================

        local function setControl(name, value)
            local control = R.Controls[name]
            if control and type(control.Set) == "function" then
                pcall(function() control:Set(value) end)
            else
                State[name] = value
            end
        end

        local function snapshotUIProfile()
            if R.UIProfileSnapshot ~= nil then return end
            R.UIProfileSnapshot = Library and Library.ActiveProfile or "Balanced"
        end

        local function applyUIPerformance()
            if not State.UseV19PerformanceProfile or not Library or type(Library.ApplyProfile) ~= "function" then return end
            snapshotUIProfile()
            pcall(function() Library:ApplyProfile("Performance") end)
        end

        local function restoreUIProfile()
            if not Library or type(Library.ApplyProfile) ~= "function" then return end
            local name = R.UIProfileSnapshot
            R.UIProfileSnapshot = nil
            if name and Library.Profiles and Library.Profiles[name] then
                pcall(function() Library:ApplyProfile(name) end)
            end
        end

        local function applyPreset(name)
            name = tostring(name or State.Preset)
            State.Preset = name
            applyUIPerformance()

            if name == "Balanced FPS" then
                setControl("DisableGlobalShadows", true)
                setControl("DisablePostFX", true)
                setControl("DisableAtmosphere", false)
                setControl("DisableClouds", false)
                setControl("TerrainLowCost", true)
                setControl("DisableCastShadows", false)
                setControl("DisableParticles", false)
                setControl("DisableTrails", false)
                setControl("DisableBeams", false)
                setControl("HideTextures", false)
                setControl("SimplifyMaterials", false)
                applyModuleOptimization("Balanced FPS")

            elseif name == "High FPS" then
                setControl("DisableGlobalShadows", true)
                setControl("DisablePostFX", true)
                setControl("DisableAtmosphere", true)
                setControl("DisableClouds", true)
                setControl("TerrainLowCost", true)
                setControl("DisableCastShadows", true)
                setControl("DisableParticles", true)
                setControl("DisableTrails", true)
                setControl("DisableBeams", true)
                setControl("HideTextures", false)
                setControl("SimplifyMaterials", false)
                applyModuleOptimization("High FPS")

            elseif name == "Potato" then
                setControl("DisableGlobalShadows", true)
                setControl("DisablePostFX", true)
                setControl("DisableAtmosphere", true)
                setControl("DisableClouds", true)
                setControl("TerrainLowCost", true)
                setControl("DisableCastShadows", true)
                setControl("DisableParticles", true)
                setControl("DisableTrails", true)
                setControl("DisableBeams", true)
                setControl("HideTextures", true)
                setControl("SimplifyMaterials", true)
                applyModuleOptimization("Potato")
            end

            notify("Applied preset: " .. name, "Success")
        end

        local function restoreAll(silent)
            setControl("DisableGlobalShadows", false)
            setControl("DisablePostFX", false)
            setControl("DisableAtmosphere", false)
            setControl("DisableClouds", false)
            setControl("TerrainLowCost", false)
            setControl("DisableCastShadows", false)
            setControl("DisableParticles", false)
            setControl("DisableTrails", false)
            setControl("DisableBeams", false)
            setControl("HideTextures", false)
            setControl("SimplifyMaterials", false)
            restoreModuleStates()
            restoreUIProfile()
            if not silent then
                notify("Restored captured graphics/module settings.", "Success")
            end
        end

        --====================================================
        -- UI
        --====================================================

        local Overview = Context:CreateSection(Scope, Tab, "FPS / Presets", true, "Performance / Presets")

        R.Controls.FPSStatus = Overview:AddStatus({
            Name = "Current Performance",
            Default = "FPS: measuring...",
            Description = "Local frame-rate monitor. It samples RenderStepped and updates twice per second.",
            FPSImpact = 0,
            PingImpact = 0,
        })

        R.Controls.Preset = Overview:AddChoice({
            Name = "Performance Preset",
            Flag = "Performance_Preset",
            Values = {"Balanced FPS", "High FPS", "Potato"},
            Default = State.Preset,
            RequiredGraphics = "Low",
            Description = "Balanced keeps more visuals. High FPS removes expensive effects. Potato also removes textures/material complexity.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.Preset = value end,
        })

        R.Controls.UseV19PerformanceProfile = Overview:AddToggle({
            Name = "Use v19 UI Performance Profile",
            Flag = "Performance_UseV19UIProfile",
            Default = State.UseV19PerformanceProfile,
            RequiredGraphics = "Low",
            Description = "Also applies GuiLib v19's built-in Performance profile: Low graphics gate, no menu blur/dim, stepped/no open animation and lighter UI settings.",
            FPSImpact = {0, 2},
            PingImpact = 0,
            Callback = function(value) State.UseV19PerformanceProfile = value end,
        })

        R.Controls.FollowStartupWizard = Overview:AddToggle({
            Name = "Follow v19 Optimization Answer",
            Flag = "Performance_FollowWizard",
            Default = State.FollowStartupWizard,
            RequiredGraphics = "Low",
            Description = "If the v19 startup wizard was answered Performance + aggressive optimization, automatically applies High FPS after startup.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.FollowStartupWizard = value end,
        })

        Overview:AddButtonGroup({
            Name = "Preset Actions",
            RequiredGraphics = "Low",
            Description = "Apply the selected preset or restore every baseline captured by this module.",
            FPSImpact = 0,
            PingImpact = 0,
            Buttons = {
                {Text = "Apply", Callback = function() applyPreset(State.Preset) end},
                {Text = "Restore", Callback = restoreAll},
            },
        })

        local Render = Context:CreateSection(Scope, Tab, "Lighting / Render Cost", false, "Performance / Render")

        R.Controls.DisableGlobalShadows = Render:AddToggle({
            Name = "Disable Global Shadows",
            Flag = "Performance_NoGlobalShadows",
            Default = State.DisableGlobalShadows,
            RequiredGraphics = "Low",
            Description = "Disables Lighting.GlobalShadows locally and restores the captured value when turned off.",
            FPSImpact = {1, 14},
            PingImpact = 0,
            Callback = function(value)
                State.DisableGlobalShadows = value
                setGlobalShadows(value)
            end,
        })

        R.Controls.DisablePostFX = Render:AddToggle({
            Name = "Disable Post Processing",
            Flag = "Performance_NoPostFX",
            Default = State.DisablePostFX,
            RequiredGraphics = "Low",
            Description = "Temporarily disables Bloom, Blur, ColorCorrection, DepthOfField and SunRays effects under Lighting.",
            FPSImpact = {1, 10},
            PingImpact = 0,
            Callback = function(value)
                State.DisablePostFX = value
                setPostFX(value)
            end,
        })

        R.Controls.DisableAtmosphere = Render:AddToggle({
            Name = "Disable Atmosphere",
            Flag = "Performance_NoAtmosphere",
            Default = State.DisableAtmosphere,
            RequiredGraphics = "Low",
            Description = "Sets Atmosphere density/haze/glare to zero while preserving their captured values.",
            FPSImpact = {0, 6},
            PingImpact = 0,
            Callback = function(value)
                State.DisableAtmosphere = value
                setAtmosphere(value)
            end,
        })

        R.Controls.DisableClouds = Render:AddToggle({
            Name = "Disable Clouds",
            Flag = "Performance_NoClouds",
            Default = State.DisableClouds,
            RequiredGraphics = "Low",
            Description = "Disables dynamic Clouds when possible, otherwise reduces cover/density to zero. Restorable.",
            FPSImpact = {1, 8},
            PingImpact = 0,
            Callback = function(value)
                State.DisableClouds = value
                setClouds(value)
            end,
        })

        R.Controls.TerrainLowCost = Render:AddToggle({
            Name = "Low Cost Terrain",
            Flag = "Performance_TerrainLowCost",
            Default = State.TerrainLowCost,
            RequiredGraphics = "Low",
            Description = "Reduces Terrain decoration and water wave/reflectance cost using reversible property overrides.",
            FPSImpact = {0, 8},
            PingImpact = 0,
            Callback = function(value)
                State.TerrainLowCost = value
                setTerrainLowCost(value)
            end,
        })

        local Scene = Context:CreateSection(Scope, Tab, "Scene Simplification", false, "Performance / Scene")

        R.Controls.DisableCastShadows = Scene:AddToggle({
            Name = "Disable Part CastShadow",
            Flag = "Performance_NoCastShadow",
            Default = State.DisableCastShadows,
            RequiredGraphics = "Low",
            Description = "Batched scan of map BaseParts. Disables CastShadow but skips player characters and Experiment17 runtime objects.",
            FPSImpact = {1, 18},
            PingImpact = 0,
            Callback = function(value)
                State.DisableCastShadows = value
                setCastShadows(value)
            end,
        })

        R.Controls.DisableParticles = Scene:AddToggle({
            Name = "Disable World Particles",
            Flag = "Performance_NoParticles",
            Default = State.DisableParticles,
            RequiredGraphics = "Low",
            Description = "Disables non-Experiment17 ParticleEmitters and also catches newly created emitters.",
            FPSImpact = {1, 25},
            PingImpact = 0,
            Callback = function(value)
                State.DisableParticles = value
                setParticles(value)
            end,
        })

        R.Controls.DisableTrails = Scene:AddToggle({
            Name = "Disable World Trails",
            Flag = "Performance_NoTrails",
            Default = State.DisableTrails,
            RequiredGraphics = "Low",
            Description = "Disables non-Experiment17 Trail instances and restores their previous Enabled state.",
            FPSImpact = {0, 12},
            PingImpact = 0,
            Callback = function(value)
                State.DisableTrails = value
                setTrails(value)
            end,
        })

        R.Controls.DisableBeams = Scene:AddToggle({
            Name = "Disable World Beams",
            Flag = "Performance_NoBeams",
            Default = State.DisableBeams,
            RequiredGraphics = "Low",
            Description = "Disables non-Experiment17 Beam instances and restores them later.",
            FPSImpact = {0, 12},
            PingImpact = 0,
            Callback = function(value)
                State.DisableBeams = value
                setBeams(value)
            end,
        })

        R.Controls.HideTextures = Scene:AddToggle({
            Name = "Hide Map Textures",
            Flag = "Performance_HideTextures",
            Default = State.HideTextures,
            RequiredGraphics = "Low",
            Description = "Aggressive: hides Decal/Texture, MeshPart.TextureID and SurfaceAppearance maps. Can noticeably change the map. Values are captured for restore.",
            FPSImpact = {2, 30},
            PingImpact = 0,
            Callback = function(value)
                State.HideTextures = value
                setTextures(value)
            end,
        })

        R.Controls.SimplifyMaterials = Scene:AddToggle({
            Name = "Simplify Map Materials",
            Flag = "Performance_SimpleMaterials",
            Default = State.SimplifyMaterials,
            RequiredGraphics = "Low",
            Description = "Aggressive: converts map BaseParts to Plastic and clears MaterialVariant locally. Characters and Experiment17 objects are skipped.",
            FPSImpact = {1, 20},
            PingImpact = 0,
            Callback = function(value)
                State.SimplifyMaterials = value
                setMaterials(value)
            end,
        })

        R.Controls.ScanBatch = Scene:AddSlider({
            Name = "Optimization Scan Batch",
            Flag = "Performance_ScanBatch",
            Min = 50,
            Max = 1200,
            Default = State.ScanBatch,
            Rounding = 0,
            RequiredGraphics = "Low",
            Description = "Objects processed before yielding. Lower = smoother application, higher = faster complete scan but larger temporary frame spikes.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.ScanBatch = math.floor(value) end,
        })

        Scene:AddButton({
            Name = "Rescan Active Optimizers",
            ButtonText = "Rescan",
            RequiredGraphics = "Low",
            Description = "Re-applies every enabled scene optimizer to objects that may have appeared after the initial scan.",
            FPSImpact = {-4, 0},
            PingImpact = 0,
            Callback = rescanActive,
        })

        local E17 = Context:CreateSection(Scope, Tab, "Experiment17 Workload", false, "Performance / Experiment17")

        R.Controls.OptimizeESP = E17:AddToggle({
            Name = "Optimize ESP Settings",
            Flag = "Performance_OptimizeESP",
            Default = State.OptimizeESP,
            RequiredGraphics = "Low",
            Description = "When applying a preset, allows Performance to lower ESP update rate/player count and disable costly sub-features.",
            FPSImpact = {0, 35},
            PingImpact = 0,
            Callback = function(value) State.OptimizeESP = value end,
        })

        R.Controls.OptimizeWorld = E17:AddToggle({
            Name = "Optimize World Settings",
            Flag = "Performance_OptimizeWorld",
            Default = State.OptimizeWorld,
            RequiredGraphics = "Low",
            Description = "Allows presets to disable expensive World wireframe/inspector/echo features.",
            FPSImpact = {0, 25},
            PingImpact = 0,
            Callback = function(value) State.OptimizeWorld = value end,
        })

        R.Controls.OptimizePlayerFX = E17:AddToggle({
            Name = "Optimize Player FX",
            Flag = "Performance_OptimizePlayer",
            Default = State.OptimizePlayerFX,
            RequiredGraphics = "Low",
            Description = "Allows presets to reduce or disable local particles, afterimages and tool trails.",
            FPSImpact = {0, 25},
            PingImpact = 0,
            Callback = function(value) State.OptimizePlayerFX = value end,
        })

        R.Controls.OptimizeTrajectory = E17:AddToggle({
            Name = "Optimize Trajectory",
            Flag = "Performance_OptimizeTrajectory",
            Default = State.OptimizeTrajectory,
            RequiredGraphics = "Low",
            Description = "Allows presets to lower trajectory update rate, samples and player count.",
            FPSImpact = {0, 20},
            PingImpact = 0,
            Callback = function(value) State.OptimizeTrajectory = value end,
        })

        E17:AddButtonGroup({
            Name = "Experiment17 Actions",
            RequiredGraphics = "Low",
            Description = "Apply the selected cost profile only to Experiment17 modules, or restore their captured pre-optimization state.",
            FPSImpact = 0,
            PingImpact = 0,
            Buttons = {
                {Text = "Optimize", Callback = function() applyModuleOptimization(State.Preset) end},
                {Text = "Restore", Callback = restoreModuleStates},
            },
        })

        local Adaptive = Context:CreateSection(Scope, Tab, "Adaptive FPS", true, "Performance / Adaptive")

        R.Controls.AdaptiveStatus = Adaptive:AddStatus({
            Name = "Adaptive Budget",
            Default = "Adaptive: off",
            Description = "Shows the current automatic quality throttle. Adaptive mode changes only numeric budgets; it does not remove ESP, Asriel afterimages, trails or other features.",
            FPSImpact = 0,
            PingImpact = 0,
        })

        R.Controls.AdaptiveFPS = Adaptive:AddToggle({
            Name = "Adaptive FPS",
            Flag = "Performance_AdaptiveFPS",
            Default = State.AdaptiveFPS,
            RequiredGraphics = "Low",
            Description = "Automatically lowers ESP/Trajectory/World update budgets when FPS falls below the target, then gradually restores them when FPS recovers.",
            FPSImpact = {0, 18},
            PingImpact = 0,
            Callback = function(value)
                State.AdaptiveFPS = value
                R.AdaptiveAccumulator = 0
                R.AdaptiveRecovery = 0
                if value then
                    captureAdaptiveBaseline()
                    applyAdaptiveLevel(0)
                    if R.Controls.AdaptiveStatus and R.Controls.AdaptiveStatus.Set then
                        R.Controls.AdaptiveStatus:Set("Adaptive L0 • Full quality")
                    end
                else
                    restoreAdaptiveBudget()
                end
            end,
        })

        R.Controls.AdaptiveTargetFPS = Adaptive:AddSlider({
            Name = "Target FPS",
            Flag = "Performance_TargetFPS",
            Min = 30,
            Max = 240,
            Default = State.AdaptiveTargetFPS,
            Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Adaptive mode tries to keep FPS near this value. It uses hysteresis so settings do not bounce every frame.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.AdaptiveTargetFPS = math.floor(value) end,
        })

        R.Controls.AdaptiveHysteresis = Adaptive:AddSlider({
            Name = "FPS Hysteresis",
            Flag = "Performance_Hysteresis",
            Min = 2,
            Max = 30,
            Default = State.AdaptiveHysteresis,
            Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Quality is reduced below Target-Hysteresis and restored above Target+Hysteresis.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.AdaptiveHysteresis = math.floor(value) end,
        })

        R.Controls.AdaptiveSampleTime = Adaptive:AddSlider({
            Name = "Adaptive Sample Time",
            Flag = "Performance_AdaptiveSample",
            Min = 0.5,
            Max = 4,
            Default = State.AdaptiveSampleTime,
            Decimals = 1,
            RequiredGraphics = "Low",
            Description = "Seconds between adaptive decisions. Higher values react slower but are calmer.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.AdaptiveSampleTime = value end,
        })

        R.Controls.AdaptiveRecoverySamples = Adaptive:AddSlider({
            Name = "Recovery Samples",
            Flag = "Performance_RecoverySamples",
            Min = 1,
            Max = 8,
            Default = State.AdaptiveRecoverySamples,
            Decimals = 0,
            RequiredGraphics = "Low",
            Description = "How many good samples are required before quality is raised again.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.AdaptiveRecoverySamples = math.floor(value) end,
        })

        R.Controls.AdaptiveProtectPlayerFX = Adaptive:AddToggle({
            Name = "Throttle Player FX, Do Not Disable",
            Flag = "Performance_AdaptivePlayerFX",
            Default = State.AdaptiveProtectPlayerFX,
            RequiredGraphics = "Low",
            Description = "When adaptive mode is under load it reduces particle rate, trail layers and Asriel ghost density instead of turning the effects off.",
            FPSImpact = {0, 12},
            PingImpact = 0,
            Callback = function(value) State.AdaptiveProtectPlayerFX = value end,
        })

        R.Controls.PreservePlayerFXInHighFPS = Adaptive:AddToggle({
            Name = "Keep Asriel / Player FX in High FPS",
            Flag = "Performance_KeepPlayerFX",
            Default = State.PreservePlayerFXInHighFPS,
            RequiredGraphics = "Low",
            Description = "High FPS preset keeps Player Trail, Particles, Tool Trails and Asriel Afterimage available; it only reduces their density. Potato remains intentionally aggressive.",
            FPSImpact = {-8, 0},
            PingImpact = 0,
            Callback = function(value) State.PreservePlayerFXInHighFPS = value end,
        })

        Adaptive:AddButtonGroup({
            Name = "Adaptive Actions",
            RequiredGraphics = "Low",
            Description = "Immediately restore the numeric budgets captured when Adaptive FPS was enabled, or force a re-snapshot from current module settings.",
            FPSImpact = 0,
            PingImpact = 0,
            Buttons = {
                {Text = "Restore Budget", Callback = restoreAdaptiveBudget},
                {Text = "Re-capture", Callback = function()
                    restoreAdaptiveBudget()
                    captureAdaptiveBaseline()
                    if State.AdaptiveFPS then applyAdaptiveLevel(0) end
                end},
            },
        })

        local Cap = Context:CreateSection(Scope, Tab, "Frame Cap", false, "Performance / Cap")
        local hasSetFPSCap = type(setfpscap) == "function"

        R.Controls.FPSCapEnabled = Cap:AddToggle({
            Name = "Use Executor FPS Cap",
            Flag = "Performance_FPSCapEnabled",
            Default = State.FPSCapEnabled and hasSetFPSCap,
            RequiredGraphics = "Low",
            Description = hasSetFPSCap
                and "Uses setfpscap when the executor exposes it. Raising the cap does not create FPS by itself; it only removes a lower cap."
                or "setfpscap is unavailable in this environment, so this control has no effect.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value)
                State.FPSCapEnabled = value and hasSetFPSCap
                if State.FPSCapEnabled then
                    pcall(setfpscap, math.max(30, math.floor(State.FPSCap)))
                end
            end,
        })

        R.Controls.FPSCap = Cap:AddSlider({
            Name = "FPS Cap",
            Flag = "Performance_FPSCap",
            Min = 30,
            Max = 360,
            Default = State.FPSCap,
            Rounding = 0,
            RequiredGraphics = "Low",
            Description = "Requested cap for setfpscap. Useful only when the environment supports it and the machine can actually render above Roblox's current cap.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value)
                State.FPSCap = math.floor(value)
                if State.FPSCapEnabled and hasSetFPSCap then
                    pcall(setfpscap, State.FPSCap)
                end
            end,
        })

        --====================================================
        -- CONNECTIONS / INITIAL STATE
        --====================================================

        Scope:TrackConnection(Workspace.DescendantAdded:Connect(function(object)
            if R.Dead then return end
            task.defer(function()
                if not R.Dead and object and object.Parent then
                    applyActiveToObject(object)
                end
            end)
        end))

        Scope:TrackConnection(Lighting.DescendantAdded:Connect(function(object)
            if R.Dead then return end
            task.defer(function()
                if R.Dead or not object or not object.Parent then return end
                if State.DisablePostFX then applyPostFX(object) end
                if State.DisableAtmosphere then applyAtmosphere(object) end
                if State.DisableClouds then applyClouds(object) end
            end)
        end))

        Scope:TrackConnection(RunService.RenderStepped:Connect(function(dt)
            if R.Dead then return end
            R.FPSFrames += 1
            R.FPSTime += dt
            if R.FPSTime >= 0.5 then
                R.FPS = math.floor((R.FPSFrames / R.FPSTime) + 0.5)
                R.FPSFrames = 0
                R.FPSTime = 0
                if R.Controls.FPSStatus and R.Controls.FPSStatus.Set then
                    local ms = R.FPS > 0 and (1000 / R.FPS) or 0
                    R.Controls.FPSStatus:Set(string.format("FPS: %d  •  %.1f ms", R.FPS, ms))
                end
            end

            if State.AdaptiveFPS then
                R.AdaptiveAccumulator += dt
                if R.AdaptiveAccumulator >= math.max(0.5, tonumber(State.AdaptiveSampleTime) or 1.0) then
                    R.AdaptiveAccumulator = 0
                    updateAdaptiveFPS()
                end
            end
        end))

        -- Reapply persisted toggles after UI construction.
        setGlobalShadows(State.DisableGlobalShadows)
        setPostFX(State.DisablePostFX)
        setAtmosphere(State.DisableAtmosphere)
        setClouds(State.DisableClouds)
        setTerrainLowCost(State.TerrainLowCost)
        setCastShadows(State.DisableCastShadows)
        setParticles(State.DisableParticles)
        setTrails(State.DisableTrails)
        setBeams(State.DisableBeams)
        setTextures(State.HideTextures)
        setMaterials(State.SimplifyMaterials)

        if State.FPSCapEnabled and hasSetFPSCap then
            pcall(setfpscap, math.max(30, math.floor(State.FPSCap)))
        end

        if State.AdaptiveFPS then
            captureAdaptiveBaseline()
            if R.Controls.AdaptiveStatus and R.Controls.AdaptiveStatus.Set then
                R.Controls.AdaptiveStatus:Set("Adaptive L0 • Full quality")
            end
        end

        -- GuiLib v19 contains a startup question for aggressive optimization.
        -- Give the wizard time to finish and then honor the user's answer.
        task.spawn(function()
            local waited = 0
            while not R.Dead and waited < 12 do
                if Library and Library.Flags and Library.Flags.VisualProfile ~= nil then break end
                task.wait(0.5)
                waited += 0.5
            end
            if R.Dead or not State.FollowStartupWizard or not Library or not Library.Flags then return end
            if Library.Flags.VisualProfile == "Performance" and Library.Flags.AggressiveOptimization == true then
                State.Preset = "High FPS"
                if R.Controls.Preset and R.Controls.Preset.Set then
                    pcall(function() R.Controls.Preset:Set("High FPS", true) end)
                end
                applyPreset("High FPS")
            end
        end)

        Context.Shared.Performance = {
            ApplyPreset = applyPreset,
            RestoreAll = restoreAll,
            Rescan = rescanActive,
            GetFPS = function() return R.FPS end,
            GetAdaptiveLevel = function() return R.AdaptiveLevel end,
            SetAdaptive = function(enabled)
                State.AdaptiveFPS = enabled == true
                if State.AdaptiveFPS then captureAdaptiveBaseline() else restoreAdaptiveBudget() end
            end,
        }

        Scope:AddCleaner(function()
            for key in pairs(R.ScanTokens) do nextToken(key) end
            restoreAdaptiveBudget()
            restoreAll(true)
            R.Dead = true
            if Context.Shared.Performance and Context.Shared.Performance.GetFPS then
                Context.Shared.Performance = nil
            end
        end)
    end,
}
