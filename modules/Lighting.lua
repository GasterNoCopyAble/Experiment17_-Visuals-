--[[
-- v19 compatibility: every feature stays accessible even when the UI Performance profile is active.
    Experiment 17 - Lighting module
    Target: Experiment17 modular Loader v0.2+

    Features:
      * Base Lighting editor
      * 20+ graphics presets
      * Rainbow / dynamic Lighting
      * Runtime element creator/editor (Bloom, Blur, CC, DOF, SunRays, Atmosphere, Clouds, Sky)
      * Local weather editor (Rain, Snow, Dust, Storm) + lightning flashes
      * Full restore on module unload / hot reload
]]

return {
    Id = "Lighting",
    Name = "Lighting",
    Version = "1.1.0-v19",
    Order = 20,

    Init = function(Context, Scope, Tab)
        local Services = Context.Services
        local Lighting = Services.Lighting
        local Workspace = Services.Workspace
        local RunService = Services.RunService
        local Terrain = Workspace.Terrain
        local Player = Context.LocalPlayer

        local State = Context:GetState("Lighting", {
            Preset = "Default",
            Rainbow = false,
            RainbowTarget = "Ambient + Outdoor",
            RainbowSpeed = 0.22,
            RainbowSaturation = 0.85,
            RainbowValue = 1,
            NewElementType = "BloomEffect",
            NewElementName = "",
            Counter = 0,

            WeatherEnabled = false,
            WeatherType = "Rain",
            WeatherRate = 180,
            WeatherRadius = 70,
            WeatherHeight = 42,
            WeatherColor = Color3.fromRGB(210, 225, 255),
            WeatherTransparency = 0.12,
            WeatherWindX = 0,
            WeatherWindZ = 0,
            Lightning = false,
            LightningInterval = 8,
            LightningStrength = 1.4,
        })

        local Runtime = {
            Dead = false,
            Base = {},
            BaseProperties = {
                "Brightness", "ClockTime", "ExposureCompensation", "GlobalShadows",
                "Ambient", "OutdoorAmbient", "FogColor", "FogStart", "FogEnd",
                "EnvironmentDiffuseScale", "EnvironmentSpecularScale",
                "ColorShift_Top", "ColorShift_Bottom", "GeographicLatitude",
            },
            PresetInstances = {},
            Created = {},
            Selected = nil,
            Editor = {},
            ElementListSection = nil,
            RainbowBaseline = nil,
            Weather = {},
            WeatherAccumulator = 0,
            LightningAccumulator = 0,
            LightningBusy = false,
        }

        local function safeGet(object, property, fallback)
            local ok, value = pcall(function() return object[property] end)
            return ok and value or fallback
        end

        local function safeSet(object, property, value)
            return pcall(function() object[property] = value end)
        end

        local function normalizeAssetId(value)
            value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if value == "" then return "" end
            if value:match("^rbxasset://") then return value end
            local direct = value:match("^rbxassetid://(%d+)$")
            if direct then return "rbxassetid://" .. direct end
            local query = value:match("[?&]id=(%d+)")
            if query then return "rbxassetid://" .. query end
            if value:match("^%d+$") then return "rbxassetid://" .. value end
            return value
        end

        local function rainbowColor(speed, offset, saturation, value)
            return Color3.fromHSV(((os.clock() * (speed or 0.25)) + (offset or 0)) % 1, saturation or 0.9, value or 1)
        end

        for _, property in ipairs(Runtime.BaseProperties) do
            Runtime.Base[property] = safeGet(Lighting, property, nil)
        end

        local function restoreBaseLighting()
            for property, value in pairs(Runtime.Base) do
                if value ~= nil then safeSet(Lighting, property, value) end
            end
        end

        local function clearPresetInstances()
            for _, object in ipairs(Runtime.PresetInstances) do
                if object and object.Parent then object:Destroy() end
            end
            table.clear(Runtime.PresetInstances)
        end

        local function presetInstance(className, suffix, parent)
            local object = Instance.new(className)
            object.Name = "Experiment17_Preset_" .. suffix
            object.Parent = parent or Lighting
            Runtime.PresetInstances[#Runtime.PresetInstances + 1] = object
            return object
        end

        local function applyPreset(name)
            name = tostring(name or "Default")
            State.Preset = name
            clearPresetInstances()
            restoreBaseLighting()

            if name == "Default" then
                return
            elseif name == "Performance" then
                Lighting.Brightness = math.max(1.5, Runtime.Base.Brightness or 2)
                Lighting.GlobalShadows = false
                Lighting.FogStart = 100000
                Lighting.FogEnd = 100001
                safeSet(Lighting, "EnvironmentDiffuseScale", 0)
                safeSet(Lighting, "EnvironmentSpecularScale", 0)
                local cc = presetInstance("ColorCorrectionEffect", "Performance")
                cc.Contrast = 0.02; cc.Saturation = -0.05

            elseif name == "Cinematic" then
                Lighting.ClockTime = 15.2; Lighting.Brightness = 2.15; Lighting.ExposureCompensation = -0.08; Lighting.GlobalShadows = true
                safeSet(Lighting, "EnvironmentDiffuseScale", 0.55); safeSet(Lighting, "EnvironmentSpecularScale", 0.8)
                local bloom = presetInstance("BloomEffect", "CinematicBloom")
                bloom.Intensity = 0.45; bloom.Size = 32; bloom.Threshold = 0.9
                local cc = presetInstance("ColorCorrectionEffect", "CinematicColor")
                cc.Contrast = 0.13; cc.Saturation = -0.04; cc.TintColor = Color3.fromRGB(244, 238, 230)
                local atmosphere = presetInstance("Atmosphere", "CinematicAtmosphere")
                atmosphere.Density = 0.31; atmosphere.Offset = 0.12; atmosphere.Haze = 1.25; atmosphere.Glare = 0.08
                atmosphere.Color = Color3.fromRGB(206, 217, 230); atmosphere.Decay = Color3.fromRGB(116, 126, 145)
                local clouds = presetInstance("Clouds", "CinematicClouds", Terrain)
                clouds.Cover = 0.42; clouds.Density = 0.58; clouds.Color = Color3.fromRGB(235, 238, 245)

            elseif name == "Realistic" then
                Lighting.ClockTime = 13.3; Lighting.Brightness = 2.3; Lighting.ExposureCompensation = 0.02; Lighting.GlobalShadows = true
                Lighting.Ambient = Color3.fromRGB(95, 95, 100); Lighting.OutdoorAmbient = Color3.fromRGB(135, 140, 150)
                safeSet(Lighting, "EnvironmentDiffuseScale", 0.65); safeSet(Lighting, "EnvironmentSpecularScale", 0.85)
                local atmosphere = presetInstance("Atmosphere", "RealisticAtmosphere")
                atmosphere.Density = 0.28; atmosphere.Offset = 0.12; atmosphere.Haze = 0.9; atmosphere.Glare = 0.12
                atmosphere.Color = Color3.fromRGB(205, 220, 235); atmosphere.Decay = Color3.fromRGB(115, 125, 145)

            elseif name == "Horror" then
                Lighting.ClockTime = 1.35; Lighting.Brightness = 1.2; Lighting.ExposureCompensation = -0.45
                Lighting.Ambient = Color3.fromRGB(18, 20, 24); Lighting.OutdoorAmbient = Color3.fromRGB(24, 27, 32)
                Lighting.FogColor = Color3.fromRGB(25, 29, 28); Lighting.FogStart = 30; Lighting.FogEnd = 420
                local cc = presetInstance("ColorCorrectionEffect", "HorrorColor")
                cc.Contrast = 0.32; cc.Saturation = -0.55; cc.TintColor = Color3.fromRGB(190, 220, 202)
                local atmosphere = presetInstance("Atmosphere", "HorrorAtmosphere")
                atmosphere.Density = 0.47; atmosphere.Offset = 0; atmosphere.Haze = 2.4; atmosphere.Glare = 0
                atmosphere.Color = Color3.fromRGB(103, 125, 114); atmosphere.Decay = Color3.fromRGB(28, 36, 34)

            elseif name == "Warm Sunset" then
                Lighting.ClockTime = 18.25; Lighting.Brightness = 2.2; Lighting.ExposureCompensation = 0.08
                Lighting.Ambient = Color3.fromRGB(118, 84, 76); Lighting.OutdoorAmbient = Color3.fromRGB(155, 112, 90)
                local bloom = presetInstance("BloomEffect", "SunsetBloom")
                bloom.Intensity = 0.38; bloom.Size = 26; bloom.Threshold = 0.86
                local cc = presetInstance("ColorCorrectionEffect", "SunsetColor")
                cc.Contrast = 0.08; cc.Saturation = 0.14; cc.TintColor = Color3.fromRGB(255, 205, 164)
                local atmosphere = presetInstance("Atmosphere", "SunsetAtmosphere")
                atmosphere.Density = 0.32; atmosphere.Offset = 0.18; atmosphere.Haze = 1.7; atmosphere.Glare = 0.25
                atmosphere.Color = Color3.fromRGB(255, 194, 151); atmosphere.Decay = Color3.fromRGB(131, 78, 85)

            elseif name == "Golden Hour" then
                Lighting.ClockTime = 17.3; Lighting.Brightness = 2.45; Lighting.ExposureCompensation = 0.15
                Lighting.Ambient = Color3.fromRGB(140, 105, 82); Lighting.OutdoorAmbient = Color3.fromRGB(190, 145, 104)
                local cc = presetInstance("ColorCorrectionEffect", "GoldenColor")
                cc.Contrast = 0.06; cc.Saturation = 0.18; cc.TintColor = Color3.fromRGB(255, 222, 174)
                local rays = presetInstance("SunRaysEffect", "GoldenRays")
                rays.Intensity = 0.16; rays.Spread = 0.72

            elseif name == "Cold Night" or name == "Moonlight" then
                Lighting.ClockTime = name == "Moonlight" and 23.25 or 0.7
                Lighting.Brightness = name == "Moonlight" and 1.8 or 1.55
                Lighting.ExposureCompensation = name == "Moonlight" and -0.05 or -0.18
                Lighting.Ambient = Color3.fromRGB(39, 48, 72); Lighting.OutdoorAmbient = Color3.fromRGB(45, 57, 87)
                local cc = presetInstance("ColorCorrectionEffect", "NightColor")
                cc.Contrast = 0.11; cc.Saturation = -0.12; cc.TintColor = Color3.fromRGB(174, 202, 255)
                local atmosphere = presetInstance("Atmosphere", "NightAtmosphere")
                atmosphere.Density = 0.27; atmosphere.Offset = 0.12; atmosphere.Haze = 1.25; atmosphere.Glare = 0
                atmosphere.Color = Color3.fromRGB(133, 157, 206); atmosphere.Decay = Color3.fromRGB(45, 54, 88)

            elseif name == "Fullbright" then
                Lighting.ClockTime = 14; Lighting.Brightness = 3; Lighting.ExposureCompensation = 0.35
                Lighting.GlobalShadows = false
                Lighting.Ambient = Color3.fromRGB(210, 210, 210); Lighting.OutdoorAmbient = Color3.fromRGB(210, 210, 210)
                Lighting.FogStart = 100000; Lighting.FogEnd = 100001
                safeSet(Lighting, "EnvironmentDiffuseScale", 1); safeSet(Lighting, "EnvironmentSpecularScale", 0.65)

            elseif name == "Vaporwave" then
                Lighting.ClockTime = 18.8; Lighting.Brightness = 2.1; Lighting.ExposureCompensation = 0.12
                Lighting.Ambient = Color3.fromRGB(105, 52, 145); Lighting.OutdoorAmbient = Color3.fromRGB(70, 110, 180)
                Lighting.FogColor = Color3.fromRGB(113, 72, 166); Lighting.FogStart = 90; Lighting.FogEnd = 1100
                local bloom = presetInstance("BloomEffect", "VaporBloom")
                bloom.Intensity = 0.85; bloom.Size = 42; bloom.Threshold = 0.72
                local cc = presetInstance("ColorCorrectionEffect", "VaporColor")
                cc.Contrast = 0.12; cc.Saturation = 0.38; cc.TintColor = Color3.fromRGB(255, 175, 247)
                local atmosphere = presetInstance("Atmosphere", "VaporAtmosphere")
                atmosphere.Density = 0.28; atmosphere.Haze = 1.8; atmosphere.Glare = 0.2
                atmosphere.Color = Color3.fromRGB(185, 125, 255); atmosphere.Decay = Color3.fromRGB(70, 105, 190)

            elseif name == "Cyberpunk" then
                Lighting.ClockTime = 21.5; Lighting.Brightness = 1.85; Lighting.ExposureCompensation = 0.08
                Lighting.Ambient = Color3.fromRGB(40, 18, 70); Lighting.OutdoorAmbient = Color3.fromRGB(18, 75, 95)
                local bloom = presetInstance("BloomEffect", "CyberBloom")
                bloom.Intensity = 1.15; bloom.Size = 36; bloom.Threshold = 0.62
                local cc = presetInstance("ColorCorrectionEffect", "CyberColor")
                cc.Contrast = 0.2; cc.Saturation = 0.45; cc.TintColor = Color3.fromRGB(215, 145, 255)

            elseif name == "Dream" then
                Lighting.ClockTime = 11.6; Lighting.Brightness = 2.45; Lighting.ExposureCompensation = 0.22
                Lighting.Ambient = Color3.fromRGB(170, 182, 215); Lighting.OutdoorAmbient = Color3.fromRGB(190, 205, 235)
                local bloom = presetInstance("BloomEffect", "DreamBloom")
                bloom.Intensity = 0.72; bloom.Size = 46; bloom.Threshold = 0.74
                local cc = presetInstance("ColorCorrectionEffect", "DreamColor")
                cc.Contrast = -0.08; cc.Saturation = -0.08; cc.TintColor = Color3.fromRGB(244, 232, 255)
                local atmosphere = presetInstance("Atmosphere", "DreamAtmosphere")
                atmosphere.Density = 0.22; atmosphere.Haze = 2.0; atmosphere.Glare = 0.18
                atmosphere.Color = Color3.fromRGB(211, 220, 255); atmosphere.Decay = Color3.fromRGB(175, 145, 210)

            elseif name == "Noir" then
                Lighting.ClockTime = 14; Lighting.Brightness = 1.65; Lighting.ExposureCompensation = -0.1
                Lighting.Ambient = Color3.fromRGB(70, 70, 70); Lighting.OutdoorAmbient = Color3.fromRGB(105, 105, 105)
                local cc = presetInstance("ColorCorrectionEffect", "NoirColor")
                cc.Contrast = 0.34; cc.Saturation = -1; cc.Brightness = -0.04

            elseif name == "Toxic" then
                Lighting.ClockTime = 13.2; Lighting.Brightness = 2.0; Lighting.ExposureCompensation = -0.02
                Lighting.Ambient = Color3.fromRGB(55, 100, 45); Lighting.OutdoorAmbient = Color3.fromRGB(85, 135, 55)
                Lighting.FogColor = Color3.fromRGB(100, 145, 65); Lighting.FogStart = 45; Lighting.FogEnd = 650
                local cc = presetInstance("ColorCorrectionEffect", "ToxicColor")
                cc.Contrast = 0.16; cc.Saturation = 0.32; cc.TintColor = Color3.fromRGB(180, 255, 135)
                local atmosphere = presetInstance("Atmosphere", "ToxicAtmosphere")
                atmosphere.Density = 0.36; atmosphere.Haze = 2.3; atmosphere.Color = Color3.fromRGB(145, 190, 95)
                atmosphere.Decay = Color3.fromRGB(50, 75, 35)

            elseif name == "Desert" then
                Lighting.ClockTime = 15.5; Lighting.Brightness = 2.7; Lighting.ExposureCompensation = 0.18
                Lighting.Ambient = Color3.fromRGB(170, 130, 90); Lighting.OutdoorAmbient = Color3.fromRGB(205, 165, 110)
                Lighting.FogColor = Color3.fromRGB(220, 183, 130); Lighting.FogStart = 200; Lighting.FogEnd = 1800
                local cc = presetInstance("ColorCorrectionEffect", "DesertColor")
                cc.Contrast = 0.08; cc.Saturation = 0.08; cc.TintColor = Color3.fromRGB(255, 226, 181)

            elseif name == "Overcast" then
                Lighting.ClockTime = 11.5; Lighting.Brightness = 1.75; Lighting.ExposureCompensation = -0.08
                Lighting.Ambient = Color3.fromRGB(115, 122, 132); Lighting.OutdoorAmbient = Color3.fromRGB(125, 134, 145)
                Lighting.FogColor = Color3.fromRGB(155, 164, 174); Lighting.FogStart = 100; Lighting.FogEnd = 950
                local atmosphere = presetInstance("Atmosphere", "OvercastAtmosphere")
                atmosphere.Density = 0.42; atmosphere.Haze = 2.1; atmosphere.Glare = 0
                atmosphere.Color = Color3.fromRGB(185, 195, 205); atmosphere.Decay = Color3.fromRGB(115, 125, 140)
                local clouds = presetInstance("Clouds", "OvercastClouds", Terrain)
                clouds.Cover = 0.78; clouds.Density = 0.72; clouds.Color = Color3.fromRGB(190, 195, 202)

            elseif name == "Storm" then
                Lighting.ClockTime = 15; Lighting.Brightness = 1.25; Lighting.ExposureCompensation = -0.35
                Lighting.Ambient = Color3.fromRGB(65, 72, 82); Lighting.OutdoorAmbient = Color3.fromRGB(80, 87, 98)
                Lighting.FogColor = Color3.fromRGB(90, 100, 112); Lighting.FogStart = 80; Lighting.FogEnd = 700
                local atmosphere = presetInstance("Atmosphere", "StormAtmosphere")
                atmosphere.Density = 0.48; atmosphere.Haze = 2.5; atmosphere.Glare = 0
                atmosphere.Color = Color3.fromRGB(135, 145, 158); atmosphere.Decay = Color3.fromRGB(72, 78, 88)
                local clouds = presetInstance("Clouds", "StormClouds", Terrain)
                clouds.Cover = 0.95; clouds.Density = 0.9; clouds.Color = Color3.fromRGB(115, 120, 128)

            elseif name == "Soft Day" then
                Lighting.ClockTime = 10.8; Lighting.Brightness = 2.25; Lighting.ExposureCompensation = 0.08
                Lighting.Ambient = Color3.fromRGB(145, 150, 160); Lighting.OutdoorAmbient = Color3.fromRGB(165, 175, 190)
                local cc = presetInstance("ColorCorrectionEffect", "SoftDayColor")
                cc.Contrast = -0.03; cc.Saturation = 0.05; cc.TintColor = Color3.fromRGB(250, 248, 240)

            elseif name == "Anime" then
                Lighting.ClockTime = 12.4; Lighting.Brightness = 2.8; Lighting.ExposureCompensation = 0.2
                Lighting.Ambient = Color3.fromRGB(160, 175, 210); Lighting.OutdoorAmbient = Color3.fromRGB(185, 205, 235)
                local bloom = presetInstance("BloomEffect", "AnimeBloom")
                bloom.Intensity = 0.65; bloom.Size = 38; bloom.Threshold = 0.8
                local cc = presetInstance("ColorCorrectionEffect", "AnimeColor")
                cc.Contrast = 0.10; cc.Saturation = 0.30; cc.TintColor = Color3.fromRGB(245, 250, 255)

            elseif name == "Retro" then
                Lighting.ClockTime = 16.3; Lighting.Brightness = 1.8; Lighting.ExposureCompensation = -0.08
                Lighting.Ambient = Color3.fromRGB(95, 82, 72); Lighting.OutdoorAmbient = Color3.fromRGB(125, 108, 88)
                local cc = presetInstance("ColorCorrectionEffect", "RetroColor")
                cc.Contrast = 0.18; cc.Saturation = -0.28; cc.TintColor = Color3.fromRGB(238, 214, 172)

            elseif name == "Underwater" then
                Lighting.ClockTime = 12; Lighting.Brightness = 1.65; Lighting.ExposureCompensation = -0.2
                Lighting.Ambient = Color3.fromRGB(25, 82, 105); Lighting.OutdoorAmbient = Color3.fromRGB(35, 110, 135)
                Lighting.FogColor = Color3.fromRGB(30, 115, 145); Lighting.FogStart = 0; Lighting.FogEnd = 450
                local cc = presetInstance("ColorCorrectionEffect", "WaterColor")
                cc.Contrast = 0.06; cc.Saturation = -0.05; cc.TintColor = Color3.fromRGB(150, 230, 255)
                local blur = presetInstance("BlurEffect", "WaterBlur")
                blur.Size = 2

            elseif name == "Mars" then
                Lighting.ClockTime = 15.8; Lighting.Brightness = 2.2; Lighting.ExposureCompensation = 0.05
                Lighting.Ambient = Color3.fromRGB(125, 65, 45); Lighting.OutdoorAmbient = Color3.fromRGB(165, 90, 55)
                Lighting.FogColor = Color3.fromRGB(170, 85, 55); Lighting.FogStart = 80; Lighting.FogEnd = 900
                local atmosphere = presetInstance("Atmosphere", "MarsAtmosphere")
                atmosphere.Density = 0.37; atmosphere.Haze = 2.1; atmosphere.Color = Color3.fromRGB(220, 125, 85)
                atmosphere.Decay = Color3.fromRGB(95, 45, 35)

            elseif name == "Frozen" then
                Lighting.ClockTime = 10.5; Lighting.Brightness = 2.4; Lighting.ExposureCompensation = 0.12
                Lighting.Ambient = Color3.fromRGB(155, 180, 210); Lighting.OutdoorAmbient = Color3.fromRGB(190, 220, 245)
                local cc = presetInstance("ColorCorrectionEffect", "FrozenColor")
                cc.Contrast = 0.05; cc.Saturation = -0.18; cc.TintColor = Color3.fromRGB(205, 235, 255)
                local bloom = presetInstance("BloomEffect", "FrozenBloom")
                bloom.Intensity = 0.35; bloom.Size = 28; bloom.Threshold = 0.9
            end
        end

        --====================================================
        -- RAINBOW LIGHTING
        --====================================================

        local function setRainbow(enabled)
            enabled = enabled == true
            if enabled and not Runtime.RainbowBaseline then
                Runtime.RainbowBaseline = {
                    Ambient = Lighting.Ambient,
                    OutdoorAmbient = Lighting.OutdoorAmbient,
                    FogColor = Lighting.FogColor,
                    ColorShift_Top = safeGet(Lighting, "ColorShift_Top", Color3.new()),
                    ColorShift_Bottom = safeGet(Lighting, "ColorShift_Bottom", Color3.new()),
                }
            elseif not enabled and Runtime.RainbowBaseline then
                Lighting.Ambient = Runtime.RainbowBaseline.Ambient
                Lighting.OutdoorAmbient = Runtime.RainbowBaseline.OutdoorAmbient
                Lighting.FogColor = Runtime.RainbowBaseline.FogColor
                safeSet(Lighting, "ColorShift_Top", Runtime.RainbowBaseline.ColorShift_Top)
                safeSet(Lighting, "ColorShift_Bottom", Runtime.RainbowBaseline.ColorShift_Bottom)
                Runtime.RainbowBaseline = nil
            end
            State.Rainbow = enabled
        end

        Scope:TrackConnection(RunService.RenderStepped:Connect(function()
            if Runtime.Dead or not State.Rainbow then return end
            local color = rainbowColor(State.RainbowSpeed, 0, State.RainbowSaturation, State.RainbowValue)
            local target = State.RainbowTarget
            if target == "Ambient" or target == "Ambient + Outdoor" or target == "All" then Lighting.Ambient = color end
            if target == "Outdoor" or target == "Ambient + Outdoor" or target == "All" then Lighting.OutdoorAmbient = color end
            if target == "Fog" or target == "All" then Lighting.FogColor = color end
            if target == "Color Shift" or target == "All" then
                safeSet(Lighting, "ColorShift_Top", color)
                safeSet(Lighting, "ColorShift_Bottom", Color3.fromHSV((select(1, Color3.toHSV(color)) + 0.16) % 1, State.RainbowSaturation, State.RainbowValue))
            end
        end))

        --====================================================
        -- CREATED ELEMENT MANAGER
        --====================================================

        local function selectedIs(className)
            local data = Runtime.Selected
            return data and data.Instance and data.Instance.Parent and data.Instance:IsA(className) and data.Instance or nil
        end

        local function selectElement(data)
            if not data or not data.Instance or not data.Instance.Parent then return end
            Runtime.Selected = data
            local object = data.Instance
            local E = Runtime.Editor

            if E.Name then pcall(function() E.Name:Set(object.Name, true) end) end
            if E.Enabled then pcall(function() E.Enabled:Set(safeGet(object, "Enabled", true), true) end) end

            local class = object.ClassName
            if class == "BloomEffect" then
                E.BloomIntensity:Set(object.Intensity, true); E.BloomSize:Set(object.Size, true); E.BloomThreshold:Set(object.Threshold, true)
            elseif class == "BlurEffect" then
                E.BlurSize:Set(object.Size, true)
            elseif class == "ColorCorrectionEffect" then
                E.CCBrightness:Set(object.Brightness, true); E.CCContrast:Set(object.Contrast, true); E.CCSaturation:Set(object.Saturation, true); E.CCTint:Set(object.TintColor, true)
            elseif class == "DepthOfFieldEffect" then
                E.DOFFar:Set(object.FarIntensity, true); E.DOFFocus:Set(object.FocusDistance, true); E.DOFRadius:Set(object.InFocusRadius, true); E.DOFNear:Set(object.NearIntensity, true)
            elseif class == "SunRaysEffect" then
                E.SunIntensity:Set(object.Intensity, true); E.SunSpread:Set(object.Spread, true)
            elseif class == "Atmosphere" then
                E.AtmoDensity:Set(object.Density, true); E.AtmoOffset:Set(object.Offset, true); E.AtmoColor:Set(object.Color, true); E.AtmoDecay:Set(object.Decay, true); E.AtmoGlare:Set(object.Glare, true); E.AtmoHaze:Set(object.Haze, true)
            elseif class == "Clouds" then
                E.CloudCover:Set(object.Cover, true); E.CloudDensity:Set(object.Density, true); E.CloudColor:Set(object.Color, true)
            elseif class == "Sky" then
                E.SkyBk:Set(object.SkyboxBk, true); E.SkyDn:Set(object.SkyboxDn, true); E.SkyFt:Set(object.SkyboxFt, true); E.SkyLf:Set(object.SkyboxLf, true); E.SkyRt:Set(object.SkyboxRt, true); E.SkyUp:Set(object.SkyboxUp, true)
                E.SkyStars:Set(object.StarCount, true); E.SkySunSize:Set(object.SunAngularSize, true); E.SkyMoonSize:Set(object.MoonAngularSize, true); E.SkyBodies:Set(object.CelestialBodiesShown, true)
            end
        end

        local function createElement(className, requestedName)
            State.Counter = State.Counter + 1
            local object = Instance.new(className)
            object.Name = (requestedName and requestedName ~= "" and requestedName) or (className .. " " .. State.Counter)
            object.Parent = className == "Clouds" and Terrain or Lighting
            Scope:TrackInstance(object)

            local data = {Instance = object, Id = State.Counter, Class = className}
            Runtime.Created[#Runtime.Created + 1] = data

            if Runtime.ElementListSection then
                Runtime.ElementListSection:AddButton({
                    Name = object.Name .. "  [" .. className .. "]",
                    ButtonText = "Select",
                    RequiredGraphics = "Low",
                    Description = "Selects this runtime-created Lighting element for editing below.",
                    FPSImpact = 0, PingImpact = 0,
                    Callback = function() selectElement(data) end,
                })
            end
            selectElement(data)
            return data
        end

        local function deleteSelected()
            local data = Runtime.Selected
            if not data or not data.Instance then return end
            if data.Instance.Parent then data.Instance:Destroy() end
            Runtime.Selected = nil
        end

        --====================================================
        -- WEATHER
        --====================================================

        local WeatherFolder = Scope:TrackInstance(Instance.new("Folder"))
        WeatherFolder.Name = "Experiment17_Weather"
        WeatherFolder.Parent = Workspace

        local WeatherPart = Instance.new("Part")
        WeatherPart.Name = "Emitter"
        WeatherPart.Anchored = true
        WeatherPart.CanCollide = false
        WeatherPart.CanTouch = false
        WeatherPart.CanQuery = false
        WeatherPart.Transparency = 1
        WeatherPart.Size = Vector3.new(1, 1, 1)
        WeatherPart.Parent = WeatherFolder
        Runtime.Weather.Part = WeatherPart

        local WeatherEmitter = Instance.new("ParticleEmitter")
        WeatherEmitter.Name = "WeatherParticles"
        WeatherEmitter.Enabled = false
        WeatherEmitter.LightInfluence = 0
        WeatherEmitter.LockedToPart = false
        WeatherEmitter.EmissionDirection = Enum.NormalId.Bottom
        WeatherEmitter.SpreadAngle = Vector2.new(4, 4)
        WeatherEmitter.Parent = WeatherPart
        Runtime.Weather.Emitter = WeatherEmitter

        local function configureWeather()
            local emitter = WeatherEmitter
            local weatherType = State.WeatherType
            emitter.Enabled = State.WeatherEnabled
            emitter.Rate = State.WeatherRate
            emitter.Color = ColorSequence.new(State.WeatherColor)
            emitter.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, math.clamp(State.WeatherTransparency, 0, 1)),
                NumberSequenceKeypoint.new(0.85, math.clamp(State.WeatherTransparency + 0.08, 0, 1)),
                NumberSequenceKeypoint.new(1, 1),
            })
            emitter.Shape = Enum.ParticleEmitterShape.Box
            WeatherPart.Size = Vector3.new(State.WeatherRadius * 2, 2, State.WeatherRadius * 2)

            if weatherType == "Rain" or weatherType == "Storm" then
                emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
                emitter.Lifetime = NumberRange.new(0.7, 1.1)
                emitter.Speed = NumberRange.new(65, 90)
                emitter.Acceleration = Vector3.new(State.WeatherWindX, -35, State.WeatherWindZ)
                emitter.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.08),
                    NumberSequenceKeypoint.new(0.1, 0.12),
                    NumberSequenceKeypoint.new(1, 0.05),
                })
                emitter.Squash = NumberSequence.new(5)
                emitter.Rotation = NumberRange.new(-3, 3)
                emitter.RotSpeed = NumberRange.new(0, 0)
                emitter.Drag = 0
            elseif weatherType == "Snow" then
                emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
                emitter.Lifetime = NumberRange.new(3.5, 5.5)
                emitter.Speed = NumberRange.new(8, 14)
                emitter.Acceleration = Vector3.new(State.WeatherWindX, -1.5, State.WeatherWindZ)
                emitter.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.12),
                    NumberSequenceKeypoint.new(0.3, 0.22),
                    NumberSequenceKeypoint.new(1, 0.12),
                })
                emitter.Squash = NumberSequence.new(0)
                emitter.Rotation = NumberRange.new(0, 360)
                emitter.RotSpeed = NumberRange.new(-90, 90)
                emitter.Drag = 0.3
            else -- Dust
                emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
                emitter.Lifetime = NumberRange.new(3, 6)
                emitter.Speed = NumberRange.new(2, 7)
                emitter.Acceleration = Vector3.new(State.WeatherWindX, 0.5, State.WeatherWindZ)
                emitter.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.5),
                    NumberSequenceKeypoint.new(0.6, 1.6),
                    NumberSequenceKeypoint.new(1, 2.2),
                })
                emitter.Squash = NumberSequence.new(0)
                emitter.Rotation = NumberRange.new(0, 360)
                emitter.RotSpeed = NumberRange.new(-30, 30)
                emitter.Drag = 0.5
            end
        end

        local function doLightningFlash()
            if Runtime.LightningBusy then return end
            Runtime.LightningBusy = true
            local oldBrightness = Lighting.Brightness
            local oldExposure = Lighting.ExposureCompensation
            task.spawn(function()
                if Runtime.Dead then Runtime.LightningBusy = false return end
                Lighting.Brightness = math.clamp(oldBrightness + State.LightningStrength * 2.2, 0, 10)
                Lighting.ExposureCompensation = math.clamp(oldExposure + State.LightningStrength, -5, 5)
                task.wait(0.055)
                Lighting.Brightness = oldBrightness
                Lighting.ExposureCompensation = oldExposure
                task.wait(0.06)
                if math.random() > 0.45 then
                    Lighting.Brightness = math.clamp(oldBrightness + State.LightningStrength * 1.3, 0, 10)
                    Lighting.ExposureCompensation = math.clamp(oldExposure + State.LightningStrength * 0.55, -5, 5)
                    task.wait(0.035)
                end
                Lighting.Brightness = oldBrightness
                Lighting.ExposureCompensation = oldExposure
                Runtime.LightningBusy = false
            end)
        end

        configureWeather()
        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            if Runtime.Dead then return end
            local camera = Workspace.CurrentCamera
            if camera and State.WeatherEnabled then
                WeatherPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, State.WeatherHeight, 0))
            end

            if State.WeatherEnabled and State.Lightning and (State.WeatherType == "Storm" or State.WeatherType == "Rain") then
                Runtime.LightningAccumulator = Runtime.LightningAccumulator + dt
                local interval = math.max(1, State.LightningInterval)
                if Runtime.LightningAccumulator >= interval then
                    Runtime.LightningAccumulator = 0
                    doLightningFlash()
                end
            else
                Runtime.LightningAccumulator = 0
            end
        end))

        --====================================================
        -- UI: PRESETS
        --====================================================

        local PresetSection = Context:CreateSection(Scope, Tab, "Graphics Presets", false, "Lighting / Presets")
        PresetSection:AddChoice({
            Name = "Graphics Preset", Flag = "Lighting_GraphicsPreset",
            Values = {"Default", "Performance", "Cinematic", "Realistic", "Horror", "Warm Sunset", "Golden Hour", "Cold Night", "Moonlight", "Fullbright", "Vaporwave", "Cyberpunk", "Dream", "Noir", "Toxic", "Desert", "Overcast", "Storm", "Soft Day", "Anime", "Retro", "Underwater", "Mars", "Frozen"},
            Default = State.Preset, RequiredGraphics = "Low",
            Description = "Applies a complete client-side Lighting look. Preset-created effects are isolated and removed when another preset is selected.",
            FPSImpact = {-4, 0}, PingImpact = 0,
            Callback = applyPreset,
        })
        PresetSection:AddButton({
            Name = "Restore Original Lighting", ButtonText = "Restore",
            RequiredGraphics = "Low",
            Description = "Removes Experiment17 preset effects and restores Lighting values captured when this module loaded.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function() State.Preset = "Default" clearPresetInstances() restoreBaseLighting() end,
        })

        --====================================================
        -- UI: RGB
        --====================================================

        local RainbowSection = Context:CreateSection(Scope, Tab, "RGB / Dynamic Lighting", false, "Lighting / RGB")
        RainbowSection:AddToggle({
            Name = "Rainbow Lighting", Flag = "Lighting_Rainbow",
            Default = State.Rainbow, RequiredGraphics="Low",
            Description = "Cycles selected Lighting colors through HSV and restores the values captured when RGB mode was enabled.",
            FPSImpact = {-1, 0}, PingImpact = 0,
            Callback = setRainbow,
        })
        RainbowSection:AddChoice({
            Name = "Rainbow Target", Flag = "Lighting_RainbowTarget",
            Values = {"Ambient + Outdoor", "Ambient", "Outdoor", "Fog", "Color Shift", "All"},
            Default = State.RainbowTarget, RequiredGraphics="Low",
            Description = "Lighting properties animated by Rainbow Lighting.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.RainbowTarget = value end,
        })
        RainbowSection:AddSlider({
            Name = "Rainbow Speed", Flag = "Lighting_RainbowSpeed",
            Min = 0.02, Max = 1.2, Default = State.RainbowSpeed, Decimals = 2,
            RequiredGraphics="Low", Description = "Hue-cycle speed.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.RainbowSpeed = value end,
        })
        RainbowSection:AddSlider({
            Name = "Rainbow Saturation", Flag = "Lighting_RainbowSaturation",
            Min = 0, Max = 1, Default = State.RainbowSaturation, Decimals = 2,
            RequiredGraphics="Low", Description = "HSV saturation of dynamic colors.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.RainbowSaturation = value end,
        })
        RainbowSection:AddSlider({
            Name = "Rainbow Brightness", Flag = "Lighting_RainbowValue",
            Min = 0.1, Max = 1, Default = State.RainbowValue, Decimals = 2,
            RequiredGraphics="Low", Description = "HSV brightness/value of dynamic colors.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.RainbowValue = value end,
        })

        --====================================================
        -- UI: BASE LIGHTING
        --====================================================

        local BaseSection = Context:CreateSection(Scope, Tab, "Base Lighting", false, "Lighting / Base")
        BaseSection:AddSlider({Name="Brightness", Flag="Lighting_Brightness", Min=0, Max=10, Default=Lighting.Brightness, Decimals=2, RequiredGraphics="Low", Description="Global scene brightness.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.Brightness=v end})
        BaseSection:AddSlider({Name="Clock Time", Flag="Lighting_ClockTime", Min=0, Max=24, Default=Lighting.ClockTime, Decimals=2, RequiredGraphics="Low", Description="Local time of day used for sun/moon position.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.ClockTime=v end})
        BaseSection:AddSlider({Name="Exposure", Flag="Lighting_Exposure", Min=-5, Max=5, Default=Lighting.ExposureCompensation, Decimals=2, RequiredGraphics="Low", Description="Scene exposure compensation.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.ExposureCompensation=v end})
        BaseSection:AddToggle({Name="Global Shadows", Flag="Lighting_GlobalShadows", Default=Lighting.GlobalShadows, RequiredGraphics="Low", Description="Enables Roblox global shadows; can cost GPU performance.", FPSImpact={-5,0}, PingImpact=0, Callback=function(v) Lighting.GlobalShadows=v end})
        BaseSection:AddColorPicker({Name="Ambient", Flag="Lighting_Ambient", Default=Lighting.Ambient, RequiredGraphics="Low", Description="Ambient color applied to occluded/interior surfaces.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.Ambient=v end})
        BaseSection:AddColorPicker({Name="Outdoor Ambient", Flag="Lighting_OutdoorAmbient", Default=Lighting.OutdoorAmbient, RequiredGraphics="Low", Description="Ambient color for outdoor surfaces.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.OutdoorAmbient=v end})
        BaseSection:AddColorPicker({Name="Fog Color", Flag="Lighting_FogColor", Default=Lighting.FogColor, RequiredGraphics="Low", Description="Classic Lighting fog color. Atmosphere can visually supersede classic fog.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.FogColor=v end})
        BaseSection:AddSlider({Name="Fog Start", Flag="Lighting_FogStart", Min=0, Max=10000, Default=math.clamp(Lighting.FogStart,0,10000), Decimals=0, RequiredGraphics="Low", Description="Distance where classic fog begins.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.FogStart=v end})
        BaseSection:AddSlider({Name="Fog End", Flag="Lighting_FogEnd", Min=1, Max=100000, Default=math.clamp(Lighting.FogEnd,1,100000), Decimals=0, RequiredGraphics="Low", Description="Distance where classic fog becomes fully opaque.", FPSImpact=0, PingImpact=0, Callback=function(v) Lighting.FogEnd=v end})
        BaseSection:AddSlider({Name="Diffuse Scale", Flag="Lighting_Diffuse", Min=0, Max=1, Default=safeGet(Lighting,"EnvironmentDiffuseScale",0), Decimals=2, RequiredGraphics="Low", Description="Amount of diffuse environment lighting.", FPSImpact={-2,0}, PingImpact=0, Callback=function(v) safeSet(Lighting,"EnvironmentDiffuseScale",v) end})
        BaseSection:AddSlider({Name="Specular Scale", Flag="Lighting_Specular", Min=0, Max=1, Default=safeGet(Lighting,"EnvironmentSpecularScale",0), Decimals=2, RequiredGraphics="Low", Description="Amount of specular environment reflection, especially visible on smooth/metal surfaces.", FPSImpact={-2,0}, PingImpact=0, Callback=function(v) safeSet(Lighting,"EnvironmentSpecularScale",v) end})
        BaseSection:AddSlider({Name="Geographic Latitude", Flag="Lighting_Latitude", Min=-90, Max=90, Default=math.clamp(safeGet(Lighting,"GeographicLatitude",41.7),-90,90), Decimals=1, RequiredGraphics="Low", Description="Changes sun/moon path for the current time of day.", FPSImpact=0, PingImpact=0, Callback=function(v) safeSet(Lighting,"GeographicLatitude",v) end})
        BaseSection:AddColorPicker({Name="Color Shift Top", Flag="Lighting_ColorShiftTop", Default=safeGet(Lighting,"ColorShift_Top",Color3.new()), RequiredGraphics="Low", Description="Adds color shift to surfaces facing the sun or moon.", FPSImpact=0, PingImpact=0, Callback=function(v) safeSet(Lighting,"ColorShift_Top",v) end})
        BaseSection:AddColorPicker({Name="Color Shift Bottom", Flag="Lighting_ColorShiftBottom", Default=safeGet(Lighting,"ColorShift_Bottom",Color3.new()), RequiredGraphics="Low", Description="Adds color shift to surfaces facing away from the sun or moon.", FPSImpact=0, PingImpact=0, Callback=function(v) safeSet(Lighting,"ColorShift_Bottom",v) end})
        BaseSection:AddButton({Name="Restore Base Lighting", ButtonText="Restore", RequiredGraphics="Low", Description="Restores base Lighting properties without deleting manually created Experiment17 elements.", FPSImpact=0, PingImpact=0, Callback=restoreBaseLighting})

        --====================================================
        -- UI: ELEMENT CREATOR + EDITOR
        --====================================================

        local CreateSection = Context:CreateSection(Scope, Tab, "Create Element", false, "Lighting / Element Creator")
        CreateSection:AddChoice({
            Name = "Element Type", Flag = "Lighting_NewType",
            Values = {"BloomEffect", "BlurEffect", "ColorCorrectionEffect", "DepthOfFieldEffect", "SunRaysEffect", "Atmosphere", "Clouds", "Sky"},
            Default = State.NewElementType, RequiredGraphics = "Low",
            Description = "Class to create. Clouds are parented to Terrain; all other elements are parented to Lighting.", FPSImpact = 0, PingImpact = 0,
            Callback = function(v) State.NewElementType = v end,
        })
        CreateSection:AddInput({
            Name = "Element Name", Flag = "Lighting_NewName", Default = State.NewElementName,
            Placeholder = "optional name", RequiredGraphics = "Low",
            Description = "Optional name for the new runtime element.", FPSImpact = 0, PingImpact = 0,
            Callback = function(v) State.NewElementName = v end,
        })
        CreateSection:AddButton({
            Name = "Create New Element", ButtonText = "Create", RequiredGraphics = "Low",
            Description = "Creates the selected Lighting/Terrain element and adds a Select button to Created Elements.", FPSImpact = 0, PingImpact = 0,
            Callback = function() createElement(State.NewElementType, State.NewElementName) end,
        })

        Runtime.ElementListSection = Context:CreateSection(Scope, Tab, "Created Elements", false, "Lighting / Created Elements")
        Runtime.ElementListSection:AddButton({Name="Created elements appear here", ButtonText="List", RequiredGraphics="Low", Description="Create an element above; each created element receives its own Select button here.", FPSImpact=0, PingImpact=0, Callback=function() end})

        local SelectedSection = Context:CreateSection(Scope, Tab, "Selected Element", false, "Lighting / Selected Element")
        Runtime.Editor.Name = SelectedSection:AddInput({
            Name="Name", Flag="Lighting_SelectedName", Default="", Placeholder="select an element first", RequiredGraphics="Low",
            Description="Renames the currently selected runtime element.", FPSImpact=0, PingImpact=0,
            Callback=function(v) local d=Runtime.Selected if d and d.Instance and d.Instance.Parent and v~="" then d.Instance.Name=v end end,
        })
        Runtime.Editor.Enabled = SelectedSection:AddToggle({
            Name="Enabled", Flag="Lighting_SelectedEnabled", Default=true, RequiredGraphics="Low",
            Description="Toggles Enabled when the selected class supports that property.", FPSImpact=0, PingImpact=0,
            Callback=function(v) local d=Runtime.Selected if d and d.Instance and d.Instance.Parent then safeSet(d.Instance,"Enabled",v) end end,
        })
        SelectedSection:AddButton({Name="Delete Selected", ButtonText="Delete", RequiredGraphics="Low", Description="Destroys the currently selected runtime element.", FPSImpact=0, PingImpact=0, Callback=deleteSelected})

        local BloomSection = Context:CreateSection(Scope, Tab, "Editor - Bloom", false, "Lighting / Bloom Editor")
        Runtime.Editor.BloomIntensity = BloomSection:AddSlider({Name="Intensity", Min=0, Max=5, Default=1, Decimals=2, RequiredGraphics="Low", Description="Bloom intensity for selected BloomEffect.", FPSImpact={-2,0}, PingImpact=0, Callback=function(v) local o=selectedIs("BloomEffect") if o then o.Intensity=v end end})
        Runtime.Editor.BloomSize = BloomSection:AddSlider({Name="Size", Min=0, Max=56, Default=24, Decimals=0, RequiredGraphics="Low", Description="Bloom blur size.", FPSImpact={-2,0}, PingImpact=0, Callback=function(v) local o=selectedIs("BloomEffect") if o then o.Size=v end end})
        Runtime.Editor.BloomThreshold = BloomSection:AddSlider({Name="Threshold", Min=0, Max=1, Default=0.95, Decimals=2, RequiredGraphics="Low", Description="Brightness threshold before bloom appears.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("BloomEffect") if o then o.Threshold=v end end})

        local BlurSection = Context:CreateSection(Scope, Tab, "Editor - Blur", false, "Lighting / Blur Editor")
        Runtime.Editor.BlurSize = BlurSection:AddSlider({Name="Size", Min=0, Max=56, Default=0, Decimals=0, RequiredGraphics="Low", Description="Screen blur size for selected BlurEffect.", FPSImpact={-4,0}, PingImpact=0, Callback=function(v) local o=selectedIs("BlurEffect") if o then o.Size=v end end})

        local CCSection = Context:CreateSection(Scope, Tab, "Editor - Color Correction", false, "Lighting / Color Correction Editor")
        Runtime.Editor.CCBrightness = CCSection:AddSlider({Name="Brightness", Min=-1, Max=1, Default=0, Decimals=2, RequiredGraphics="Low", Description="Selected ColorCorrectionEffect brightness.", FPSImpact={-1,0}, PingImpact=0, Callback=function(v) local o=selectedIs("ColorCorrectionEffect") if o then o.Brightness=v end end})
        Runtime.Editor.CCContrast = CCSection:AddSlider({Name="Contrast", Min=-1, Max=1, Default=0, Decimals=2, RequiredGraphics="Low", Description="Selected ColorCorrectionEffect contrast.", FPSImpact={-1,0}, PingImpact=0, Callback=function(v) local o=selectedIs("ColorCorrectionEffect") if o then o.Contrast=v end end})
        Runtime.Editor.CCSaturation = CCSection:AddSlider({Name="Saturation", Min=-1, Max=1, Default=0, Decimals=2, RequiredGraphics="Low", Description="Selected ColorCorrectionEffect saturation.", FPSImpact={-1,0}, PingImpact=0, Callback=function(v) local o=selectedIs("ColorCorrectionEffect") if o then o.Saturation=v end end})
        Runtime.Editor.CCTint = CCSection:AddColorPicker({Name="Tint", Default=Color3.new(1,1,1), RequiredGraphics="Low", Description="Selected ColorCorrectionEffect tint color.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("ColorCorrectionEffect") if o then o.TintColor=v end end})

        local DOFSection = Context:CreateSection(Scope, Tab, "Editor - Depth Of Field", false, "Lighting / DOF Editor")
        Runtime.Editor.DOFFar = DOFSection:AddSlider({Name="Far Intensity", Min=0, Max=1, Default=0, Decimals=2, RequiredGraphics="Low", Description="Blur intensity beyond the focus zone.", FPSImpact={-5,-1}, PingImpact=0, Callback=function(v) local o=selectedIs("DepthOfFieldEffect") if o then o.FarIntensity=v end end})
        Runtime.Editor.DOFFocus = DOFSection:AddSlider({Name="Focus Distance", Min=0, Max=1000, Default=50, Decimals=1, RequiredGraphics="Low", Description="Distance from camera to the DOF focus plane.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("DepthOfFieldEffect") if o then o.FocusDistance=v end end})
        Runtime.Editor.DOFRadius = DOFSection:AddSlider({Name="In Focus Radius", Min=0, Max=1000, Default=50, Decimals=1, RequiredGraphics="Low", Description="Depth range that stays sharp around the focus plane.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("DepthOfFieldEffect") if o then o.InFocusRadius=v end end})
        Runtime.Editor.DOFNear = DOFSection:AddSlider({Name="Near Intensity", Min=0, Max=1, Default=0, Decimals=2, RequiredGraphics="Low", Description="Blur intensity nearer than the focus zone.", FPSImpact={-5,-1}, PingImpact=0, Callback=function(v) local o=selectedIs("DepthOfFieldEffect") if o then o.NearIntensity=v end end})

        local SunSection = Context:CreateSection(Scope, Tab, "Editor - Sun Rays", false, "Lighting / Sun Rays Editor")
        Runtime.Editor.SunIntensity = SunSection:AddSlider({Name="Intensity", Min=0, Max=1, Default=0.25, Decimals=2, RequiredGraphics="Low", Description="SunRaysEffect intensity.", FPSImpact={-3,0}, PingImpact=0, Callback=function(v) local o=selectedIs("SunRaysEffect") if o then o.Intensity=v end end})
        Runtime.Editor.SunSpread = SunSection:AddSlider({Name="Spread", Min=0, Max=1, Default=1, Decimals=2, RequiredGraphics="Low", Description="SunRaysEffect spread.", FPSImpact={-2,0}, PingImpact=0, Callback=function(v) local o=selectedIs("SunRaysEffect") if o then o.Spread=v end end})

        local AtmoSection = Context:CreateSection(Scope, Tab, "Editor - Atmosphere", false, "Lighting / Atmosphere Editor")
        Runtime.Editor.AtmoDensity = AtmoSection:AddSlider({Name="Density", Min=0, Max=1, Default=0.3, Decimals=3, RequiredGraphics="Low", Description="Atmosphere particle density.", FPSImpact={-4,0}, PingImpact=0, Callback=function(v) local o=selectedIs("Atmosphere") if o then o.Density=v end end})
        Runtime.Editor.AtmoOffset = AtmoSection:AddSlider({Name="Offset", Min=-1, Max=1, Default=0.25, Decimals=2, RequiredGraphics="Low", Description="Atmosphere horizon offset.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("Atmosphere") if o then o.Offset=v end end})
        Runtime.Editor.AtmoColor = AtmoSection:AddColorPicker({Name="Color", Default=Color3.fromRGB(200,200,200), RequiredGraphics="Low", Description="Atmosphere body color.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("Atmosphere") if o then o.Color=v end end})
        Runtime.Editor.AtmoDecay = AtmoSection:AddColorPicker({Name="Decay", Default=Color3.fromRGB(100,100,100), RequiredGraphics="Low", Description="Atmosphere color at long distances.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("Atmosphere") if o then o.Decay=v end end})
        Runtime.Editor.AtmoGlare = AtmoSection:AddSlider({Name="Glare", Min=0, Max=10, Default=0, Decimals=2, RequiredGraphics="Low", Description="Atmosphere glare around the sun.", FPSImpact={-1,0}, PingImpact=0, Callback=function(v) local o=selectedIs("Atmosphere") if o then o.Glare=v end end})
        Runtime.Editor.AtmoHaze = AtmoSection:AddSlider({Name="Haze", Min=0, Max=10, Default=0, Decimals=2, RequiredGraphics="Low", Description="Atmosphere haze strength.", FPSImpact={-1,0}, PingImpact=0, Callback=function(v) local o=selectedIs("Atmosphere") if o then o.Haze=v end end})

        local CloudSection = Context:CreateSection(Scope, Tab, "Editor - Clouds", false, "Lighting / Clouds Editor")
        Runtime.Editor.CloudCover = CloudSection:AddSlider({Name="Cover", Min=0, Max=1, Default=0.5, Decimals=2, RequiredGraphics="Low", Description="Cloud layer coverage from sparse to full.", FPSImpact={-6,-1}, PingImpact=0, Callback=function(v) local o=selectedIs("Clouds") if o then o.Cover=v end end})
        Runtime.Editor.CloudDensity = CloudSection:AddSlider({Name="Density", Min=0, Max=1, Default=0.7, Decimals=2, RequiredGraphics="Low", Description="Cloud particulate density.", FPSImpact={-6,-1}, PingImpact=0, Callback=function(v) local o=selectedIs("Clouds") if o then o.Density=v end end})
        Runtime.Editor.CloudColor = CloudSection:AddColorPicker({Name="Color", Default=Color3.new(1,1,1), RequiredGraphics="Low", Description="Base color of dynamic clouds.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("Clouds") if o then o.Color=v end end})

        local SkySection = Context:CreateSection(Scope, Tab, "Editor - Sky", false, "Lighting / Sky Editor")
        local function skyInput(label, property)
            return SkySection:AddInput({
                Name=label, Default="", Placeholder="rbxassetid://...", RequiredGraphics="Low",
                Description="Texture asset for " .. label .. ".", FPSImpact=0, PingImpact=0,
                Callback=function(v) local o=selectedIs("Sky") if o then o[property]=normalizeAssetId(v) end end,
            })
        end
        Runtime.Editor.SkyBk = skyInput("Skybox Back", "SkyboxBk")
        Runtime.Editor.SkyDn = skyInput("Skybox Down", "SkyboxDn")
        Runtime.Editor.SkyFt = skyInput("Skybox Front", "SkyboxFt")
        Runtime.Editor.SkyLf = skyInput("Skybox Left", "SkyboxLf")
        Runtime.Editor.SkyRt = skyInput("Skybox Right", "SkyboxRt")
        Runtime.Editor.SkyUp = skyInput("Skybox Up", "SkyboxUp")
        Runtime.Editor.SkyStars = SkySection:AddSlider({Name="Star Count", Min=0, Max=10000, Default=3000, Decimals=0, RequiredGraphics="Low", Description="Number of stars rendered by selected Sky.", FPSImpact={-2,0}, PingImpact=0, Callback=function(v) local o=selectedIs("Sky") if o then o.StarCount=v end end})
        Runtime.Editor.SkySunSize = SkySection:AddSlider({Name="Sun Angular Size", Min=0, Max=60, Default=21, Decimals=1, RequiredGraphics="Low", Description="Angular size of the sun disc.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("Sky") if o then o.SunAngularSize=v end end})
        Runtime.Editor.SkyMoonSize = SkySection:AddSlider({Name="Moon Angular Size", Min=0, Max=60, Default=11, Decimals=1, RequiredGraphics="Low", Description="Angular size of the moon disc.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("Sky") if o then o.MoonAngularSize=v end end})
        Runtime.Editor.SkyBodies = SkySection:AddToggle({Name="Celestial Bodies", Default=true, RequiredGraphics="Low", Description="Shows or hides the sun, moon and stars on selected Sky.", FPSImpact=0, PingImpact=0, Callback=function(v) local o=selectedIs("Sky") if o then o.CelestialBodiesShown=v end end})

        --====================================================
        -- UI: WEATHER
        --====================================================

        local WeatherSection = Context:CreateSection(Scope, Tab, "Weather Editor", false, "Lighting / Weather")
        WeatherSection:AddToggle({
            Name="Enable Weather", Flag="Lighting_WeatherEnabled", Default=State.WeatherEnabled, RequiredGraphics="Low",
            Description="Enables a camera-following local particle weather layer.", FPSImpact={-12,-2}, PingImpact=0,
            Callback=function(v) State.WeatherEnabled=v configureWeather() end,
        })
        WeatherSection:AddChoice({
            Name="Weather Type", Flag="Lighting_WeatherType", Values={"Rain","Snow","Dust","Storm"}, Default=State.WeatherType, RequiredGraphics="Low",
            Description="Changes particle behavior. Storm uses rain particles and can pair with lightning.", FPSImpact={-2,0}, PingImpact=0,
            Callback=function(v) State.WeatherType=v configureWeather() end,
        })
        WeatherSection:AddSlider({Name="Particle Rate", Flag="Lighting_WeatherRate", Min=10, Max=600, Default=State.WeatherRate, Decimals=0, RequiredGraphics="Low", Description="Weather particles emitted per second. This is the main weather FPS cost control.", FPSImpact={-12,-1}, PingImpact=0, Callback=function(v) State.WeatherRate=v configureWeather() end})
        WeatherSection:AddSlider({Name="Weather Radius", Flag="Lighting_WeatherRadius", Min=20, Max=160, Default=State.WeatherRadius, Decimals=0, RequiredGraphics="Low", Description="Horizontal area around the camera in which weather particles spawn.", FPSImpact={-4,0}, PingImpact=0, Callback=function(v) State.WeatherRadius=v configureWeather() end})
        WeatherSection:AddSlider({Name="Emitter Height", Flag="Lighting_WeatherHeight", Min=15, Max=100, Default=State.WeatherHeight, Decimals=0, RequiredGraphics="Low", Description="Height above the camera for the weather emitter.", FPSImpact=0, PingImpact=0, Callback=function(v) State.WeatherHeight=v end})
        WeatherSection:AddColorPicker({Name="Weather Color", Flag="Lighting_WeatherColor", Default=State.WeatherColor, RequiredGraphics="Low", Description="Base color of rain/snow/dust particles.", FPSImpact=0, PingImpact=0, Callback=function(v) State.WeatherColor=v configureWeather() end})
        WeatherSection:AddSlider({Name="Particle Transparency", Flag="Lighting_WeatherTransparency", Min=0, Max=0.95, Default=State.WeatherTransparency, Decimals=2, RequiredGraphics="Low", Description="Base transparency of weather particles.", FPSImpact=0, PingImpact=0, Callback=function(v) State.WeatherTransparency=v configureWeather() end})
        WeatherSection:AddSlider({Name="Wind X", Flag="Lighting_WeatherWindX", Min=-60, Max=60, Default=State.WeatherWindX, Decimals=1, RequiredGraphics="Low", Description="World-X acceleration applied to weather particles.", FPSImpact=0, PingImpact=0, Callback=function(v) State.WeatherWindX=v configureWeather() end})
        WeatherSection:AddSlider({Name="Wind Z", Flag="Lighting_WeatherWindZ", Min=-60, Max=60, Default=State.WeatherWindZ, Decimals=1, RequiredGraphics="Low", Description="World-Z acceleration applied to weather particles.", FPSImpact=0, PingImpact=0, Callback=function(v) State.WeatherWindZ=v configureWeather() end})
        WeatherSection:AddSeparator()
        WeatherSection:AddToggle({Name="Lightning Flashes", Flag="Lighting_Lightning", Default=State.Lightning, RequiredGraphics="Low", Description="Adds local Lighting brightness/exposure flashes while Rain or Storm weather is active.", FPSImpact=0, PingImpact=0, Callback=function(v) State.Lightning=v end})
        WeatherSection:AddSlider({Name="Lightning Interval", Flag="Lighting_LightningInterval", Min=1, Max=30, Default=State.LightningInterval, Decimals=1, RequiredGraphics="Low", Description="Approximate seconds between automatic lightning flashes.", FPSImpact=0, PingImpact=0, Callback=function(v) State.LightningInterval=v end})
        WeatherSection:AddSlider({Name="Lightning Strength", Flag="Lighting_LightningStrength", Min=0.1, Max=3, Default=State.LightningStrength, Decimals=2, RequiredGraphics="Low", Description="Brightness/exposure increase during a lightning flash.", FPSImpact=0, PingImpact=0, Callback=function(v) State.LightningStrength=v end})
        WeatherSection:AddButton({Name="Test Lightning", ButtonText="Flash", RequiredGraphics="Low", Description="Triggers one local lightning flash immediately.", FPSImpact=0, PingImpact=0, Callback=doLightningFlash})
        WeatherSection:AddButton({Name="Clear Weather Particles", ButtonText="Clear", RequiredGraphics="Low", Description="Instantly clears active emitted particles without changing weather settings.", FPSImpact=0, PingImpact=0, Callback=function() pcall(function() WeatherEmitter:Clear() end) end})

        -- Re-apply persistent state on hot reload.
        if State.Preset and State.Preset ~= "Default" then applyPreset(State.Preset) end
        if State.Rainbow then setRainbow(true) end
        configureWeather()

        Scope:AddCleaner(function()
            Runtime.Dead = true
            pcall(function() setRainbow(false) end)
            pcall(function() WeatherEmitter.Enabled = false WeatherEmitter:Clear() end)
            pcall(clearPresetInstances)
            pcall(restoreBaseLighting)
        end)
    end,

    Unload = function(Context, Scope, reason)
        Context.Bus:Emit("LightingModuleUnloading", reason)
    end,
}
