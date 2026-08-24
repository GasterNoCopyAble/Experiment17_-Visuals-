-- Experiment17 - Lighting v2.0 compact
return {
    Id="Lighting", Name="Lighting", Version="2.0.0", Order=20,
    Init=function(Context,Scope,Tab)
        local Lighting=Context.Services.Lighting or game:GetService("Lighting")
        local Workspace=Context.Services.Workspace or workspace
        local Terrain=Workspace.Terrain
        local Library=Context.Library

        local State=Context:GetState("LightingCompact",{
            Enabled=false,
            Brightness=Lighting.Brightness,
            Exposure=Lighting.ExposureCompensation,
            ClockTime=Lighting.ClockTime,
            Shadows=Lighting.GlobalShadows,
            ShadowSoftness=Lighting.ShadowSoftness,
            Ambient=Lighting.Ambient,
            OutdoorAmbient=Lighting.OutdoorAmbient,
            FogColor=Lighting.FogColor,
            FogStart=Lighting.FogStart,
            FogEnd=Lighting.FogEnd,
            Atmosphere=false, AtmosDensity=.30, AtmosHaze=1.0, AtmosGlare=.05,
            AtmosColor=Color3.fromRGB(205,220,235), AtmosDecay=Color3.fromRGB(105,120,145),
            Clouds=false, CloudCover=.35, CloudDensity=.45, CloudColor=Color3.fromRGB(235,238,245),
            Bloom=false, BloomIntensity=.45, BloomSize=32, BloomThreshold=.9,
            ColorCorrection=false, Contrast=.08, Saturation=0, Tint=Color3.new(1,1,1),
            DepthOfField=false, FocusDistance=35, FocusRadius=18, FarIntensity=.15,
            SunRays=false, RayIntensity=.08, RaySpread=.75,
            Blur=false, BlurSize=8,
        })

        local Base={
            Brightness=Lighting.Brightness, ExposureCompensation=Lighting.ExposureCompensation,
            ClockTime=Lighting.ClockTime, GlobalShadows=Lighting.GlobalShadows,
            ShadowSoftness=Lighting.ShadowSoftness, Ambient=Lighting.Ambient,
            OutdoorAmbient=Lighting.OutdoorAmbient, FogColor=Lighting.FogColor,
            FogStart=Lighting.FogStart, FogEnd=Lighting.FogEnd,
        }

        local function notify(text,kind)
            if Library and type(Library.Notify)=="function" then
                pcall(function() Library:Notify({Title="Experiment 17 • Lighting",Text=tostring(text),Type=kind or "Info",Duration=2.4}) end)
            end
        end
        local function safeSet(object,property,value) pcall(function() object[property]=value end) end
        local function owned(className,name,parent)
            parent=parent or Lighting
            local object=parent:FindFirstChild(name)
            if object and not object:IsA(className) then object:Destroy(); object=nil end
            if not object then object=Instance.new(className); object.Name=name; object.Parent=parent end
            return Scope:TrackInstance(object)
        end

        local FX={
            Atmos=owned("Atmosphere","Experiment17_Atmosphere"),
            Bloom=owned("BloomEffect","Experiment17_Bloom"),
            CC=owned("ColorCorrectionEffect","Experiment17_ColorCorrection"),
            DOF=owned("DepthOfFieldEffect","Experiment17_DOF"),
            Rays=owned("SunRaysEffect","Experiment17_SunRays"),
            Blur=owned("BlurEffect","Experiment17_Blur"),
            Clouds=owned("Clouds","Experiment17_Clouds",Terrain),
        }

        local function restoreBase()
            for property,value in pairs(Base) do safeSet(Lighting,property,value) end
        end
        local function disableFX()
            FX.Atmos.Density=0; FX.Atmos.Haze=0; FX.Atmos.Glare=0
            FX.Bloom.Enabled=false; FX.CC.Enabled=false; FX.DOF.Enabled=false; FX.Rays.Enabled=false; FX.Blur.Enabled=false
            safeSet(FX.Clouds,"Enabled",false)
        end
        local function apply()
            if not State.Enabled then restoreBase(); disableFX(); return end
            safeSet(Lighting,"Brightness",State.Brightness)
            safeSet(Lighting,"ExposureCompensation",State.Exposure)
            safeSet(Lighting,"ClockTime",State.ClockTime)
            safeSet(Lighting,"GlobalShadows",State.Shadows)
            safeSet(Lighting,"ShadowSoftness",State.ShadowSoftness)
            safeSet(Lighting,"Ambient",State.Ambient)
            safeSet(Lighting,"OutdoorAmbient",State.OutdoorAmbient)
            safeSet(Lighting,"FogColor",State.FogColor)
            safeSet(Lighting,"FogStart",State.FogStart)
            safeSet(Lighting,"FogEnd",math.max(State.FogStart+1,State.FogEnd))
            FX.Atmos.Density=State.Atmosphere and State.AtmosDensity or 0
            FX.Atmos.Haze=State.Atmosphere and State.AtmosHaze or 0
            FX.Atmos.Glare=State.Atmosphere and State.AtmosGlare or 0
            FX.Atmos.Color=State.AtmosColor; FX.Atmos.Decay=State.AtmosDecay
            FX.Bloom.Enabled=State.Bloom; FX.Bloom.Intensity=State.BloomIntensity; FX.Bloom.Size=State.BloomSize; FX.Bloom.Threshold=State.BloomThreshold
            FX.CC.Enabled=State.ColorCorrection; FX.CC.Contrast=State.Contrast; FX.CC.Saturation=State.Saturation; FX.CC.TintColor=State.Tint
            FX.DOF.Enabled=State.DepthOfField; FX.DOF.FocusDistance=State.FocusDistance; FX.DOF.InFocusRadius=State.FocusRadius; FX.DOF.FarIntensity=State.FarIntensity
            FX.Rays.Enabled=State.SunRays; FX.Rays.Intensity=State.RayIntensity; FX.Rays.Spread=State.RaySpread
            FX.Blur.Enabled=State.Blur; FX.Blur.Size=State.BlurSize
            safeSet(FX.Clouds,"Enabled",State.Clouds); safeSet(FX.Clouds,"Cover",State.CloudCover); safeSet(FX.Clouds,"Density",State.CloudDensity); safeSet(FX.Clouds,"Color",State.CloudColor)
        end

        local PRESETS={
            Default=function() State.Enabled=false end,
            Performance=function()
                State.Enabled=true; State.Brightness=2; State.Exposure=0; State.ClockTime=14; State.Shadows=false; State.ShadowSoftness=0
                State.Atmosphere=false; State.Clouds=false; State.Bloom=false; State.ColorCorrection=false; State.DepthOfField=false; State.SunRays=false; State.Blur=false
                State.FogStart=100000; State.FogEnd=100001
            end,
            Cinematic=function()
                State.Enabled=true; State.Brightness=2.1; State.Exposure=-.08; State.ClockTime=15.2; State.Shadows=true; State.ShadowSoftness=.55
                State.Atmosphere=true; State.AtmosDensity=.31; State.AtmosHaze=1.25; State.AtmosGlare=.08
                State.Bloom=true; State.BloomIntensity=.45; State.BloomThreshold=.9
                State.ColorCorrection=true; State.Contrast=.13; State.Saturation=-.04; State.Tint=Color3.fromRGB(244,238,230)
                State.DepthOfField=true; State.FocusDistance=38; State.FocusRadius=22; State.FarIntensity=.12
                State.SunRays=true; State.RayIntensity=.06
            end,
            Realistic=function()
                State.Enabled=true; State.Brightness=2.3; State.Exposure=.02; State.ClockTime=13.3; State.Shadows=true; State.ShadowSoftness=.38
                State.Ambient=Color3.fromRGB(95,95,100); State.OutdoorAmbient=Color3.fromRGB(135,140,150)
                State.Atmosphere=true; State.AtmosDensity=.28; State.AtmosHaze=.9; State.AtmosGlare=.12
                State.ColorCorrection=true; State.Contrast=.05; State.Saturation=.02; State.Tint=Color3.new(1,1,1)
                State.Bloom=false; State.DepthOfField=false; State.Blur=false
            end,
            Horror=function()
                State.Enabled=true; State.ClockTime=1.35; State.Brightness=1.2; State.Exposure=-.45
                State.Ambient=Color3.fromRGB(18,20,24); State.OutdoorAmbient=Color3.fromRGB(24,27,32)
                State.FogColor=Color3.fromRGB(25,29,28); State.FogStart=30; State.FogEnd=420
                State.Atmosphere=true; State.AtmosDensity=.47; State.AtmosHaze=2.4; State.AtmosGlare=0
                State.ColorCorrection=true; State.Contrast=.32; State.Saturation=-.55; State.Tint=Color3.fromRGB(190,220,202)
                State.Bloom=false; State.DepthOfField=false
            end,
            Sunset=function()
                State.Enabled=true; State.ClockTime=18.25; State.Brightness=2.2; State.Exposure=.08
                State.Ambient=Color3.fromRGB(118,84,76); State.OutdoorAmbient=Color3.fromRGB(155,112,90)
                State.Atmosphere=true; State.AtmosDensity=.32; State.AtmosHaze=1.7; State.AtmosGlare=.25; State.AtmosColor=Color3.fromRGB(255,194,151)
                State.Bloom=true; State.BloomIntensity=.38; State.BloomThreshold=.86
                State.ColorCorrection=true; State.Contrast=.08; State.Saturation=.14; State.Tint=Color3.fromRGB(255,205,164)
            end,
            Night=function()
                State.Enabled=true; State.ClockTime=.7; State.Brightness=1.55; State.Exposure=-.18
                State.Ambient=Color3.fromRGB(39,48,72); State.OutdoorAmbient=Color3.fromRGB(45,57,87)
                State.Atmosphere=true; State.AtmosDensity=.27; State.AtmosHaze=1.25; State.AtmosColor=Color3.fromRGB(133,157,206)
                State.ColorCorrection=true; State.Contrast=.11; State.Saturation=-.12; State.Tint=Color3.fromRGB(174,202,255)
                State.Bloom=true; State.BloomIntensity=.22
            end,
            Fullbright=function()
                State.Enabled=true; State.ClockTime=14; State.Brightness=3; State.Exposure=.35; State.Shadows=false
                State.Ambient=Color3.fromRGB(210,210,210); State.OutdoorAmbient=Color3.fromRGB(210,210,210)
                State.FogStart=100000; State.FogEnd=100001; State.Atmosphere=false; State.Bloom=false; State.ColorCorrection=false
            end,
            Vapor=function()
                State.Enabled=true; State.ClockTime=18.8; State.Brightness=2.1; State.Exposure=.12
                State.Ambient=Color3.fromRGB(105,52,145); State.OutdoorAmbient=Color3.fromRGB(70,110,180)
                State.FogColor=Color3.fromRGB(113,72,166); State.FogStart=90; State.FogEnd=1100
                State.Bloom=true; State.BloomIntensity=.85; State.BloomThreshold=.72
                State.ColorCorrection=true; State.Contrast=.12; State.Saturation=.38; State.Tint=Color3.fromRGB(255,175,247)
                State.Atmosphere=true; State.AtmosDensity=.28; State.AtmosHaze=1.8; State.AtmosGlare=.2; State.AtmosColor=Color3.fromRGB(185,125,255)
            end,
            Cyber=function()
                State.Enabled=true; State.ClockTime=21.5; State.Brightness=1.85; State.Exposure=.08
                State.Ambient=Color3.fromRGB(40,18,70); State.OutdoorAmbient=Color3.fromRGB(18,75,95)
                State.Bloom=true; State.BloomIntensity=1.15; State.BloomThreshold=.62
                State.ColorCorrection=true; State.Contrast=.2; State.Saturation=.45; State.Tint=Color3.fromRGB(215,145,255)
                State.Atmosphere=true; State.AtmosDensity=.24; State.AtmosHaze=1.4; State.AtmosColor=Color3.fromRGB(120,80,200)
            end,
        }
        local function preset(name)
            local fn=PRESETS[name]; if not fn then return end
            fn(); apply(); notify("Preset: "..name,"Success")
        end

        local Presets=Context:CreateSection(Scope,Tab,"Looks",true,"Lighting / Presets")
        if type(Presets.AddTileButtons)=="function" then
            local buttons={}
            for _,name in ipairs({"Default","Performance","Cinematic","Realistic","Horror","Sunset","Night","Fullbright","Vapor","Cyber"}) do
                local n=name
                buttons[#buttons+1]={Text=n,Callback=function() preset(n) end}
            end
            Presets:AddTileButtons({Name="Presets",TileSize=68,Columns=5,Buttons=buttons})
        else
            Presets:AddChoice({Name="Preset",Flag="LightingCompact_Preset",Values={"Default","Performance","Cinematic","Realistic","Horror","Sunset","Night","Fullbright","Vapor","Cyber"},Default="Default",Callback=preset})
        end
        Presets:AddToggle({Name="Custom Override",Flag="LightingCompact_Enabled",Default=State.Enabled,Callback=function(v) State.Enabled=v; apply() end})

        local Scene=Context:CreateSection(Scope,Tab,"Scene",false,"Lighting / Scene")
        Scene:AddSlider({Name="Brightness",Flag="LightingCompact_Brightness",Min=0,Max=8,Default=State.Brightness,Decimals=2,Callback=function(v) State.Brightness=v; apply() end})
        Scene:AddSlider({Name="Exposure",Flag="LightingCompact_Exposure",Min=-3,Max=3,Default=State.Exposure,Decimals=2,Callback=function(v) State.Exposure=v; apply() end})
        Scene:AddSlider({Name="Time",Flag="LightingCompact_Time",Min=0,Max=24,Default=State.ClockTime,Decimals=2,Callback=function(v) State.ClockTime=v; apply() end})
        Scene:AddToggle({Name="Global Shadows",Flag="LightingCompact_Shadows",Default=State.Shadows,Callback=function(v) State.Shadows=v; apply() end})
        Scene:AddColorPicker({Name="Ambient",Flag="LightingCompact_Ambient",Default=State.Ambient,Callback=function(v) State.Ambient=v; apply() end})
        Scene:AddColorPicker({Name="Outdoor Ambient",Flag="LightingCompact_Outdoor",Default=State.OutdoorAmbient,Callback=function(v) State.OutdoorAmbient=v; apply() end})
        Scene:AddRangeSlider({Name="Fog Range",Flag="LightingCompact_FogRange",Min=0,Max=10000,Default={State.FogStart,State.FogEnd},Callback=function(_,low,high) State.FogStart=low; State.FogEnd=high; apply() end})
        Scene:AddColorPicker({Name="Fog Color",Flag="LightingCompact_FogColor",Default=State.FogColor,Callback=function(v) State.FogColor=v; apply() end})

        local Atmos=Context:CreateSection(Scope,Tab,"Atmosphere & Sky",false,"Lighting / Atmosphere")
        Atmos:AddToggle({Name="Atmosphere",Flag="LightingCompact_Atmos",Default=State.Atmosphere,Callback=function(v) State.Atmosphere=v; apply() end})
        Atmos:AddSlider({Name="Density",Flag="LightingCompact_AtmosDensity",Min=0,Max=1,Default=State.AtmosDensity,Decimals=2,Callback=function(v) State.AtmosDensity=v; apply() end})
        Atmos:AddSlider({Name="Haze",Flag="LightingCompact_Haze",Min=0,Max=10,Default=State.AtmosHaze,Decimals=2,Callback=function(v) State.AtmosHaze=v; apply() end})
        Atmos:AddColorPicker({Name="Atmosphere Color",Flag="LightingCompact_AtmosColor",Default=State.AtmosColor,Callback=function(v) State.AtmosColor=v; apply() end})
        Atmos:AddToggle({Name="Clouds",Flag="LightingCompact_Clouds",Default=State.Clouds,Callback=function(v) State.Clouds=v; apply() end})
        Atmos:AddSlider({Name="Cloud Cover",Flag="LightingCompact_CloudCover",Min=0,Max=1,Default=State.CloudCover,Decimals=2,Callback=function(v) State.CloudCover=v; apply() end})
        Atmos:AddSlider({Name="Cloud Density",Flag="LightingCompact_CloudDensity",Min=0,Max=1,Default=State.CloudDensity,Decimals=2,Callback=function(v) State.CloudDensity=v; apply() end})

        local Post=Context:CreateSection(Scope,Tab,"Post FX",false,"Lighting / PostFX")
        Post:AddToggle({Name="Bloom",Flag="LightingCompact_Bloom",Default=State.Bloom,Callback=function(v) State.Bloom=v; apply() end})
        Post:AddSlider({Name="Bloom Intensity",Flag="LightingCompact_BloomIntensity",Min=0,Max=3,Default=State.BloomIntensity,Decimals=2,Callback=function(v) State.BloomIntensity=v; apply() end})
        Post:AddToggle({Name="Color Correction",Flag="LightingCompact_CC",Default=State.ColorCorrection,Callback=function(v) State.ColorCorrection=v; apply() end})
        Post:AddSlider({Name="Contrast",Flag="LightingCompact_Contrast",Min=-1,Max=1,Default=State.Contrast,Decimals=2,Callback=function(v) State.Contrast=v; apply() end})
        Post:AddSlider({Name="Saturation",Flag="LightingCompact_Saturation",Min=-1,Max=1,Default=State.Saturation,Decimals=2,Callback=function(v) State.Saturation=v; apply() end})
        Post:AddColorPicker({Name="Tint",Flag="LightingCompact_Tint",Default=State.Tint,Callback=function(v) State.Tint=v; apply() end})
        Post:AddToggle({Name="Depth Of Field",Flag="LightingCompact_DOF",Default=State.DepthOfField,Callback=function(v) State.DepthOfField=v; apply() end})
        Post:AddToggle({Name="Sun Rays",Flag="LightingCompact_Rays",Default=State.SunRays,Callback=function(v) State.SunRays=v; apply() end})
        Post:AddToggle({Name="Blur",Flag="LightingCompact_Blur",Default=State.Blur,Callback=function(v) State.Blur=v; apply() end})
        Post:AddSlider({Name="Blur Size",Flag="LightingCompact_BlurSize",Min=0,Max=56,Default=State.BlurSize,Decimals=0,Callback=function(v) State.BlurSize=v; apply() end})

        Context.Shared.Lighting={Apply=apply,Preset=preset,Restore=function() State.Enabled=false; apply() end}
        Scope:AddCleaner(function() restoreBase(); disableFX(); if Context.Shared.Lighting then Context.Shared.Lighting=nil end end)
        apply()
    end,
}
