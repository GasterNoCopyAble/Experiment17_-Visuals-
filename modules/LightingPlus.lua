-- Experiment17 - Lighting Plus quick stack
return {
    Id = "LightingPlus",
    Name = "Lighting Plus",
    Version = "1.0.0",
    Order = 25,
    TargetTab = "Lighting",

    Init = function(Context, Scope, Tab)
        local Lighting = Context.Services.Lighting or game:GetService("Lighting")
        local Workspace = Context.Services.Workspace or workspace
        local Terrain = Workspace:FindFirstChildOfClass("Terrain") or Workspace.Terrain

        local State = Context:GetState("LightingPlus", {
            Master = false,
            Brightness = Lighting.Brightness,
            Exposure = Lighting.ExposureCompensation,
            ClockTime = Lighting.ClockTime,
            ShadowSoftness = Lighting.ShadowSoftness,
            GlobalShadows = Lighting.GlobalShadows,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            FogColor = Lighting.FogColor,
            FogStart = Lighting.FogStart,
            FogEnd = Lighting.FogEnd,

            Atmosphere = false, AtmosphereDensity = 0.30, AtmosphereOffset = 0.10, AtmosphereHaze = 1.0, AtmosphereGlare = 0.05,
            AtmosphereColor = Color3.fromRGB(205,220,235), AtmosphereDecay = Color3.fromRGB(105,120,145),

            Bloom = false, BloomIntensity = 0.45, BloomSize = 32, BloomThreshold = 0.9,
            ColorCorrection = false, CCBrightness = 0, CCContrast = 0.08, CCSaturation = 0, CCTint = Color3.new(1,1,1),
            DepthOfField = false, DOFFocusDistance = 35, DOFInFocusRadius = 18, DOFNearIntensity = 0.05, DOFFarIntensity = 0.15,
            SunRays = false, SunRaysIntensity = 0.08, SunRaysSpread = 0.75,
            Blur = false, BlurSize = 8,
            Clouds = false, CloudCover = 0.35, CloudDensity = 0.45, CloudColor = Color3.fromRGB(235,238,245),
        })

        local Base = {
            Brightness=Lighting.Brightness, ExposureCompensation=Lighting.ExposureCompensation, ClockTime=Lighting.ClockTime,
            ShadowSoftness=Lighting.ShadowSoftness, GlobalShadows=Lighting.GlobalShadows, Ambient=Lighting.Ambient,
            OutdoorAmbient=Lighting.OutdoorAmbient, FogColor=Lighting.FogColor, FogStart=Lighting.FogStart, FogEnd=Lighting.FogEnd,
        }

        local function safeSet(obj, prop, value)
            pcall(function() obj[prop]=value end)
        end

        local function owned(className, name, parent)
            local obj=(parent or Lighting):FindFirstChild(name)
            if obj and not obj:IsA(className) then obj:Destroy(); obj=nil end
            if not obj then obj=Instance.new(className); obj.Name=name; obj.Parent=parent or Lighting end
            return obj
        end

        local FX = {
            Atmosphere = Scope:TrackInstance(owned("Atmosphere","Experiment17_LightingPlus_Atmosphere",Lighting)),
            Bloom = Scope:TrackInstance(owned("BloomEffect","Experiment17_LightingPlus_Bloom",Lighting)),
            CC = Scope:TrackInstance(owned("ColorCorrectionEffect","Experiment17_LightingPlus_CC",Lighting)),
            DOF = Scope:TrackInstance(owned("DepthOfFieldEffect","Experiment17_LightingPlus_DOF",Lighting)),
            Rays = Scope:TrackInstance(owned("SunRaysEffect","Experiment17_LightingPlus_Rays",Lighting)),
            Blur = Scope:TrackInstance(owned("BlurEffect","Experiment17_LightingPlus_Blur",Lighting)),
        }
        local Clouds = Terrain and Scope:TrackInstance(owned("Clouds","Experiment17_LightingPlus_Clouds",Terrain)) or nil

        local function applyBase()
            if not State.Master then return end
            safeSet(Lighting,"Brightness",State.Brightness)
            safeSet(Lighting,"ExposureCompensation",State.Exposure)
            safeSet(Lighting,"ClockTime",State.ClockTime)
            safeSet(Lighting,"ShadowSoftness",State.ShadowSoftness)
            safeSet(Lighting,"GlobalShadows",State.GlobalShadows)
            safeSet(Lighting,"Ambient",State.Ambient)
            safeSet(Lighting,"OutdoorAmbient",State.OutdoorAmbient)
            safeSet(Lighting,"FogColor",State.FogColor)
            safeSet(Lighting,"FogStart",State.FogStart)
            safeSet(Lighting,"FogEnd",math.max(State.FogStart+1,State.FogEnd))
        end

        local function applyFX()
            FX.Atmosphere.Density=State.Atmosphere and State.AtmosphereDensity or 0
            FX.Atmosphere.Offset=State.AtmosphereOffset
            FX.Atmosphere.Haze=State.Atmosphere and State.AtmosphereHaze or 0
            FX.Atmosphere.Glare=State.Atmosphere and State.AtmosphereGlare or 0
            FX.Atmosphere.Color=State.AtmosphereColor
            FX.Atmosphere.Decay=State.AtmosphereDecay

            FX.Bloom.Enabled=State.Bloom; FX.Bloom.Intensity=State.BloomIntensity; FX.Bloom.Size=State.BloomSize; FX.Bloom.Threshold=State.BloomThreshold
            FX.CC.Enabled=State.ColorCorrection; FX.CC.Brightness=State.CCBrightness; FX.CC.Contrast=State.CCContrast; FX.CC.Saturation=State.CCSaturation; FX.CC.TintColor=State.CCTint
            FX.DOF.Enabled=State.DepthOfField; FX.DOF.FocusDistance=State.DOFFocusDistance; FX.DOF.InFocusRadius=State.DOFInFocusRadius; FX.DOF.NearIntensity=State.DOFNearIntensity; FX.DOF.FarIntensity=State.DOFFarIntensity
            FX.Rays.Enabled=State.SunRays; FX.Rays.Intensity=State.SunRaysIntensity; FX.Rays.Spread=State.SunRaysSpread
            FX.Blur.Enabled=State.Blur; FX.Blur.Size=State.BlurSize
            if Clouds then safeSet(Clouds,"Enabled",State.Clouds); safeSet(Clouds,"Cover",State.CloudCover); safeSet(Clouds,"Density",State.CloudDensity); safeSet(Clouds,"Color",State.CloudColor) end
        end

        local function restoreBase()
            for k,v in pairs(Base) do safeSet(Lighting,k,v) end
        end

        local function applyPreset(name)
            if name=="Clean" then
                State.Master=true; State.Brightness=2; State.Exposure=0; State.ShadowSoftness=0.35; State.GlobalShadows=true
                State.Atmosphere=false; State.Bloom=false; State.ColorCorrection=true; State.CCContrast=0.04; State.CCSaturation=0.02; State.CCTint=Color3.new(1,1,1)
                State.DepthOfField=false; State.SunRays=false; State.Blur=false; State.Clouds=false
            elseif name=="Cinematic+" then
                State.Master=true; State.Brightness=2.1; State.Exposure=-0.08; State.ShadowSoftness=0.55; State.GlobalShadows=true
                State.Atmosphere=true; State.AtmosphereDensity=0.32; State.AtmosphereHaze=1.35; State.AtmosphereGlare=0.08
                State.Bloom=true; State.BloomIntensity=0.5; State.BloomSize=34; State.BloomThreshold=0.88
                State.ColorCorrection=true; State.CCContrast=0.14; State.CCSaturation=-0.04; State.CCTint=Color3.fromRGB(244,238,230)
                State.DepthOfField=true; State.DOFFocusDistance=38; State.DOFInFocusRadius=22; State.DOFNearIntensity=0.04; State.DOFFarIntensity=0.12
                State.SunRays=true; State.SunRaysIntensity=0.06; State.SunRaysSpread=0.72
            elseif name=="Night+" then
                State.Master=true; State.ClockTime=0.5; State.Brightness=1.6; State.Exposure=-0.18; State.Ambient=Color3.fromRGB(34,42,66); State.OutdoorAmbient=Color3.fromRGB(45,55,82)
                State.Atmosphere=true; State.AtmosphereDensity=0.28; State.AtmosphereHaze=1.2; State.AtmosphereColor=Color3.fromRGB(140,165,220); State.AtmosphereDecay=Color3.fromRGB(45,55,90)
                State.ColorCorrection=true; State.CCContrast=0.12; State.CCSaturation=-0.12; State.CCTint=Color3.fromRGB(180,205,255)
                State.Bloom=true; State.BloomIntensity=0.25; State.BloomThreshold=0.95
            elseif name=="Foggy" then
                State.Master=true; State.FogStart=20; State.FogEnd=350; State.FogColor=Color3.fromRGB(165,175,180)
                State.Atmosphere=true; State.AtmosphereDensity=0.5; State.AtmosphereHaze=2.5; State.AtmosphereGlare=0
                State.ColorCorrection=true; State.CCSaturation=-0.2; State.CCContrast=0.05
            elseif name=="Neon" then
                State.Master=true; State.Exposure=0.12; State.Bloom=true; State.BloomIntensity=1.05; State.BloomThreshold=0.62; State.BloomSize=40
                State.ColorCorrection=true; State.CCContrast=0.18; State.CCSaturation=0.35; State.CCTint=Color3.fromRGB(225,175,255)
                State.Atmosphere=true; State.AtmosphereDensity=0.24; State.AtmosphereHaze=1.6; State.AtmosphereColor=Color3.fromRGB(190,135,255); State.AtmosphereDecay=Color3.fromRGB(70,105,190)
            end
            applyBase(); applyFX()
        end

        local Quick=Context:CreateSection(Scope,Tab,"Lighting+ Quick Controls",false,"Lighting / Plus Quick")
        Quick:AddToggle({Name="Lighting+ Override",Flag="LightingPlus_Master",Default=State.Master,RequiredGraphics="Low",Callback=function(v) State.Master=v if v then applyBase() else restoreBase() end end})
        Quick:AddChoice({Name="Quick Preset",Flag="LightingPlus_Preset",Values={"Custom","Clean","Cinematic+","Night+","Foggy","Neon"},Default="Custom",RequiredGraphics="Low",Callback=function(v) if v~="Custom" then applyPreset(v) end end})
        Quick:AddSlider({Name="Brightness",Flag="LightingPlus_Brightness",Min=0,Max=10,Default=State.Brightness,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.Brightness=v applyBase() end})
        Quick:AddSlider({Name="Exposure",Flag="LightingPlus_Exposure",Min=-3,Max=3,Default=State.Exposure,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.Exposure=v applyBase() end})
        Quick:AddSlider({Name="Clock Time",Flag="LightingPlus_Clock",Min=0,Max=24,Default=State.ClockTime,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ClockTime=v applyBase() end})
        Quick:AddSlider({Name="Shadow Softness",Flag="LightingPlus_ShadowSoftness",Min=0,Max=1,Default=State.ShadowSoftness,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ShadowSoftness=v applyBase() end})
        Quick:AddToggle({Name="Global Shadows",Flag="LightingPlus_Shadows",Default=State.GlobalShadows,RequiredGraphics="Low",Callback=function(v) State.GlobalShadows=v applyBase() end})
        Quick:AddColorPicker({Name="Ambient",Flag="LightingPlus_Ambient",Default=State.Ambient,RequiredGraphics="Low",Callback=function(v) State.Ambient=v applyBase() end})
        Quick:AddColorPicker({Name="Outdoor Ambient",Flag="LightingPlus_Outdoor",Default=State.OutdoorAmbient,RequiredGraphics="Low",Callback=function(v) State.OutdoorAmbient=v applyBase() end})
        Quick:AddColorPicker({Name="Fog Color",Flag="LightingPlus_FogColor",Default=State.FogColor,RequiredGraphics="Low",Callback=function(v) State.FogColor=v applyBase() end})
        Quick:AddSlider({Name="Fog Start",Flag="LightingPlus_FogStart",Min=0,Max=10000,Default=State.FogStart,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.FogStart=v applyBase() end})
        Quick:AddSlider({Name="Fog End",Flag="LightingPlus_FogEnd",Min=1,Max=10000,Default=State.FogEnd,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.FogEnd=v applyBase() end})

        local Atmos=Context:CreateSection(Scope,Tab,"Atmosphere+",false,"Lighting / Plus Atmosphere")
        Atmos:AddToggle({Name="Atmosphere+",Flag="LightingPlus_Atmos",Default=State.Atmosphere,RequiredGraphics="Low",Callback=function(v) State.Atmosphere=v applyFX() end})
        Atmos:AddSlider({Name="Density",Flag="LightingPlus_AtmosDensity",Min=0,Max=1,Default=State.AtmosphereDensity,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.AtmosphereDensity=v applyFX() end})
        Atmos:AddSlider({Name="Offset",Flag="LightingPlus_AtmosOffset",Min=-1,Max=1,Default=State.AtmosphereOffset,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.AtmosphereOffset=v applyFX() end})
        Atmos:AddSlider({Name="Haze",Flag="LightingPlus_AtmosHaze",Min=0,Max=10,Default=State.AtmosphereHaze,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.AtmosphereHaze=v applyFX() end})
        Atmos:AddSlider({Name="Glare",Flag="LightingPlus_AtmosGlare",Min=0,Max=10,Default=State.AtmosphereGlare,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.AtmosphereGlare=v applyFX() end})
        Atmos:AddColorPicker({Name="Atmosphere Color",Flag="LightingPlus_AtmosColor",Default=State.AtmosphereColor,RequiredGraphics="Low",Callback=function(v) State.AtmosphereColor=v applyFX() end})
        Atmos:AddColorPicker({Name="Atmosphere Decay",Flag="LightingPlus_AtmosDecay",Default=State.AtmosphereDecay,RequiredGraphics="Low",Callback=function(v) State.AtmosphereDecay=v applyFX() end})
        Atmos:AddToggle({Name="Clouds+",Flag="LightingPlus_Clouds",Default=State.Clouds,RequiredGraphics="Low",Callback=function(v) State.Clouds=v applyFX() end})
        Atmos:AddSlider({Name="Cloud Cover",Flag="LightingPlus_CloudCover",Min=0,Max=1,Default=State.CloudCover,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.CloudCover=v applyFX() end})
        Atmos:AddSlider({Name="Cloud Density",Flag="LightingPlus_CloudDensity",Min=0,Max=1,Default=State.CloudDensity,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.CloudDensity=v applyFX() end})
        Atmos:AddColorPicker({Name="Cloud Color",Flag="LightingPlus_CloudColor",Default=State.CloudColor,RequiredGraphics="Low",Callback=function(v) State.CloudColor=v applyFX() end})

        local Post=Context:CreateSection(Scope,Tab,"Post FX+",false,"Lighting / Plus PostFX")
        Post:AddToggle({Name="Bloom+",Flag="LightingPlus_Bloom",Default=State.Bloom,RequiredGraphics="Low",Callback=function(v) State.Bloom=v applyFX() end})
        Post:AddSlider({Name="Bloom Intensity",Flag="LightingPlus_BloomIntensity",Min=0,Max=5,Default=State.BloomIntensity,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.BloomIntensity=v applyFX() end})
        Post:AddSlider({Name="Bloom Size",Flag="LightingPlus_BloomSize",Min=0,Max=56,Default=State.BloomSize,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.BloomSize=v applyFX() end})
        Post:AddSlider({Name="Bloom Threshold",Flag="LightingPlus_BloomThreshold",Min=0,Max=5,Default=State.BloomThreshold,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.BloomThreshold=v applyFX() end})
        Post:AddToggle({Name="Color Correction+",Flag="LightingPlus_CC",Default=State.ColorCorrection,RequiredGraphics="Low",Callback=function(v) State.ColorCorrection=v applyFX() end})
        Post:AddSlider({Name="CC Brightness",Flag="LightingPlus_CCBrightness",Min=-1,Max=1,Default=State.CCBrightness,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.CCBrightness=v applyFX() end})
        Post:AddSlider({Name="CC Contrast",Flag="LightingPlus_CCContrast",Min=-1,Max=1,Default=State.CCContrast,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.CCContrast=v applyFX() end})
        Post:AddSlider({Name="CC Saturation",Flag="LightingPlus_CCSaturation",Min=-1,Max=1,Default=State.CCSaturation,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.CCSaturation=v applyFX() end})
        Post:AddColorPicker({Name="CC Tint",Flag="LightingPlus_CCTint",Default=State.CCTint,RequiredGraphics="Low",Callback=function(v) State.CCTint=v applyFX() end})
        Post:AddToggle({Name="Depth Of Field+",Flag="LightingPlus_DOF",Default=State.DepthOfField,RequiredGraphics="Low",Callback=function(v) State.DepthOfField=v applyFX() end})
        Post:AddSlider({Name="Focus Distance",Flag="LightingPlus_DOFFocus",Min=0,Max=300,Default=State.DOFFocusDistance,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.DOFFocusDistance=v applyFX() end})
        Post:AddSlider({Name="In Focus Radius",Flag="LightingPlus_DOFRadius",Min=0,Max=300,Default=State.DOFInFocusRadius,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.DOFInFocusRadius=v applyFX() end})
        Post:AddSlider({Name="DOF Near Intensity",Flag="LightingPlus_DOFNear",Min=0,Max=1,Default=State.DOFNearIntensity,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.DOFNearIntensity=v applyFX() end})
        Post:AddSlider({Name="DOF Far Intensity",Flag="LightingPlus_DOFFar",Min=0,Max=1,Default=State.DOFFarIntensity,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.DOFFarIntensity=v applyFX() end})
        Post:AddToggle({Name="Sun Rays+",Flag="LightingPlus_Rays",Default=State.SunRays,RequiredGraphics="Low",Callback=function(v) State.SunRays=v applyFX() end})
        Post:AddSlider({Name="Sun Rays Intensity",Flag="LightingPlus_RayIntensity",Min=0,Max=1,Default=State.SunRaysIntensity,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.SunRaysIntensity=v applyFX() end})
        Post:AddSlider({Name="Sun Rays Spread",Flag="LightingPlus_RaySpread",Min=0,Max=1,Default=State.SunRaysSpread,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.SunRaysSpread=v applyFX() end})
        Post:AddToggle({Name="Blur+",Flag="LightingPlus_Blur",Default=State.Blur,RequiredGraphics="Low",Callback=function(v) State.Blur=v applyFX() end})
        Post:AddSlider({Name="Blur Size",Flag="LightingPlus_BlurSize",Min=0,Max=56,Default=State.BlurSize,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.BlurSize=v applyFX() end})
        Post:AddButton({Name="Restore Lighting+",ButtonText="Restore",RequiredGraphics="Low",Callback=function() State.Master=false restoreBase(); State.Atmosphere=false; State.Bloom=false; State.ColorCorrection=false; State.DepthOfField=false; State.SunRays=false; State.Blur=false; State.Clouds=false; applyFX() end})

        if State.Master then applyBase() end
        applyFX()
        Scope:AddCleaner(function() restoreBase() end)
        Context.Shared.LightingPlus={Apply=applyBase,ApplyFX=applyFX,Restore=restoreBase}
    end,
}
