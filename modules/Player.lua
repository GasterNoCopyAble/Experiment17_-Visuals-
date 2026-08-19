--[[
    Experiment 17 - Player module
    Target: Experiment17 modular Loader v0.2+

    Features:
      * FOV override + enforced third person
      * Local chams + rainbow chams
      * Volumetric multi-ribbon character Trail
      * 3D particle volume
      * Asriel-style rainbow character afterimages / clone trail
      * Motion Trails for equipped Tools / weapons

    All changes are local presentation only and are restored/cleaned on unload.
]]

return {
    Id = "Player",
    Name = "Player",
    Version = "2.0.0",
    Order = 50,

    Init = function(Context, Scope, Tab)
        local S = Context.Services
        local Workspace, RunService = S.Workspace, S.RunService
        local TweenService = S.TweenService
        local LocalPlayer = Context.LocalPlayer

        local State = Context:GetState("Player", {
            FOVEnabled = false,
            FOV = 70,
            ThirdPerson = false,
            ThirdPersonDistance = 10,
            ThirdPersonEnforce = true,

            Chams = false,
            ChamColor = Color3.fromRGB(180, 110, 255),
            ChamRainbow = false,
            ChamRainbowSpeed = 0.28,
            ChamFillTransparency = 0.72,
            ChamOutlineTransparency = 0.14,

            Trail = false,
            TrailColor = Color3.fromRGB(180, 110, 255),
            TrailColor2 = Color3.fromRGB(255, 80, 180),
            TrailRainbow = false,
            TrailRainbowSpeed = 0.30,
            TrailLifetime = 0.35,
            TrailWidth = 1.0,
            TrailLayers = 3,
            TrailTexture = "",

            Particles = false,
            ParticleColor = Color3.fromRGB(180, 110, 255),
            ParticleRainbow = false,
            ParticleRainbowSpeed = 0.24,
            ParticleRate = 22,
            ParticleSize = 0.35,
            ParticleSpeed = 1.5,
            ParticleRadius = 1.15,
            ParticleLifetime = 0.8,
            ParticleTexture = "rbxasset://textures/particles/sparkles_main.dds",

            Afterimage = false,
            AfterimageColorMode = "Rainbow",
            AfterimageColorA = Color3.fromRGB(110, 190, 255),
            AfterimageColorB = Color3.fromRGB(255, 90, 210),
            AfterimageRainbowSpeed = 0.35,
            AfterimageLifetime = 0.75,
            AfterimageInterval = 0.09,
            AfterimageSpacing = 0.65,
            AfterimageTransparency = 0.22,
            AfterimageMaxActive = 12,
            AfterimageMaterial = "Neon",
            AfterimageOnlyMoving = true,

            ToolTrails = false,
            ToolTrailAxis = "Longest",
            ToolTrailColorA = Color3.fromRGB(120, 200, 255),
            ToolTrailColorB = Color3.fromRGB(255, 90, 190),
            ToolTrailRainbow = false,
            ToolTrailRainbowSpeed = 0.35,
            ToolTrailLifetime = 0.28,
            ToolTrailWidth = 0.95,
            ToolTrailTexture = "",
            ToolTrailLightEmission = 0.4,
        })

        local R = {
            Camera = Workspace.CurrentCamera,
            Original = {
                FOV = (Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView) or 70,
                CameraMode = LocalPlayer.CameraMode,
                MinZoom = LocalPlayer.CameraMinZoomDistance,
                MaxZoom = LocalPlayer.CameraMaxZoomDistance,
            },
            Highlight = nil,
            Trails = {},
            TrailAttachments = {},
            TrailRoot = nil,
            ParticleEmitters = {},
            ParticleAttachments = {},
            ParticleRoot = nil,
            ToolTrailData = setmetatable({}, {__mode="k"}),
            Afterimages = {},
            AfterTimer = 0,
            LastAfterPosition = nil,
            BodyNames = {
                Head=true, Torso=true, UpperTorso=true, LowerTorso=true,
                ["Left Arm"]=true, ["Right Arm"]=true, ["Left Leg"]=true, ["Right Leg"]=true,
                LeftUpperArm=true, LeftLowerArm=true, LeftHand=true,
                RightUpperArm=true, RightLowerArm=true, RightHand=true,
                LeftUpperLeg=true, LeftLowerLeg=true, LeftFoot=true,
                RightUpperLeg=true, RightLowerLeg=true, RightFoot=true,
            },
        }

        R.Root = Scope:TrackInstance(Instance.new("Folder"))
        R.Root.Name="Experiment17_Player_Runtime"
        R.Root.Parent=Workspace

        R.rainbow = function(speed, offset)
            return Color3.fromHSV(((os.clock()*(speed or 0.3))+(offset or 0))%1,0.9,1)
        end

        R.normalizeAsset = function(value)
            value=tostring(value or ""):gsub("^%s+",""):gsub("%s+$","")
            if value=="" then return "" end
            if value:match("^rbxasset://") or value:match("^rbxassetid://") then return value end
            local id=value:match("[?&]id=(%d+)") or value:match("^(%d+)$")
            return id and ("rbxassetid://"..id) or value
        end

        R.getCharacter = function()
            local char=LocalPlayer.Character
            local root=char and char:FindFirstChild("HumanoidRootPart")
            return char,root
        end

        R.applyCamera = function()
            R.Camera=Workspace.CurrentCamera or R.Camera
            if R.Camera then
                if State.FOVEnabled then R.Camera.FieldOfView=State.FOV end
            end
            if State.ThirdPerson then
                pcall(function() LocalPlayer.CameraMode=Enum.CameraMode.Classic end)
                LocalPlayer.CameraMinZoomDistance=State.ThirdPersonDistance
                LocalPlayer.CameraMaxZoomDistance=State.ThirdPersonDistance
            end
        end

        R.restoreCamera = function()
            R.Camera=Workspace.CurrentCamera or R.Camera
            if R.Camera then pcall(function() R.Camera.FieldOfView=R.Original.FOV end) end
            pcall(function() LocalPlayer.CameraMode=R.Original.CameraMode end)
            pcall(function() LocalPlayer.CameraMinZoomDistance=R.Original.MinZoom end)
            pcall(function() LocalPlayer.CameraMaxZoomDistance=R.Original.MaxZoom end)
        end

        R.updateChams = function()
            local char=LocalPlayer.Character
            if State.Chams and char then
                if not R.Highlight then
                    R.Highlight=Instance.new("Highlight")
                    R.Highlight.Name="Experiment17_LocalChams"
                    R.Highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                    R.Highlight.Parent=R.Root
                end
                local c=State.ChamRainbow and R.rainbow(State.ChamRainbowSpeed,0) or State.ChamColor
                R.Highlight.Adornee=char; R.Highlight.FillColor=c; R.Highlight.OutlineColor=c
                R.Highlight.FillTransparency=State.ChamFillTransparency; R.Highlight.OutlineTransparency=State.ChamOutlineTransparency; R.Highlight.Enabled=true
            elseif R.Highlight then R.Highlight.Enabled=false end
        end

        R.destroyTrail = function()
            for _,x in ipairs(R.Trails) do pcall(function() x:Destroy() end) end
            for _,x in ipairs(R.TrailAttachments) do pcall(function() x:Destroy() end) end
            table.clear(R.Trails); table.clear(R.TrailAttachments); R.TrailRoot=nil
        end

        R.trailAttachment = function(root,name,pos)
            local a=Instance.new("Attachment"); a.Name=name; a.Position=pos; a.Parent=root; R.TrailAttachments[#R.TrailAttachments+1]=a; return a
        end

        R.newTrailLayer = function(root,index,p0,p1)
            local a0=R.trailAttachment(root,"E17_TrailA_"..index,p0)
            local a1=R.trailAttachment(root,"E17_TrailB_"..index,p1)
            local tr=Instance.new("Trail")
            tr.Name="E17_CharacterTrail_"..index; tr.Attachment0=a0; tr.Attachment1=a1; tr.FaceCamera=false; tr.MinLength=0.03; tr.LightEmission=0.22; tr.Parent=root
            R.Trails[#R.Trails+1]=tr
            return tr
        end

        R.rebuildTrail = function()
            local _,root=R.getCharacter(); R.destroyTrail()
            if not State.Trail or not root then return end
            R.TrailRoot=root
            local w=State.TrailWidth
            R.newTrailLayer(root,1,Vector3.new(-0.72*w,0,0),Vector3.new(0.72*w,0,0))
            if State.TrailLayers>=2 then R.newTrailLayer(root,2,Vector3.new(0,-0.95*w,0),Vector3.new(0,0.95*w,0)) end
            if State.TrailLayers>=3 then R.newTrailLayer(root,3,Vector3.new(0,0,-0.62*w),Vector3.new(0,0,0.62*w)) end
            if State.TrailLayers>=4 then R.newTrailLayer(root,4,Vector3.new(-0.58*w,-0.58*w,0),Vector3.new(0.58*w,0.58*w,0)) end
        end

        R.updateTrail = function()
            local _,root=R.getCharacter()
            if not State.Trail or not root then if #R.Trails>0 then R.destroyTrail() end return end
            if R.TrailRoot~=root or #R.Trails==0 then R.rebuildTrail() end
            local a,b=State.TrailColor,State.TrailColor2
            if State.TrailRainbow then a=R.rainbow(State.TrailRainbowSpeed,0); b=R.rainbow(State.TrailRainbowSpeed,0.17) end
            local tex=R.normalizeAsset(State.TrailTexture)
            for _,tr in ipairs(R.Trails) do
                tr.Color=ColorSequence.new(a,b); tr.Lifetime=State.TrailLifetime; tr.Texture=tex
                tr.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.08),NumberSequenceKeypoint.new(0.6,0.35),NumberSequenceKeypoint.new(1,1)})
                tr.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0.15)})
            end
        end

        R.destroyParticles = function()
            for _,x in ipairs(R.ParticleEmitters) do pcall(function() x:Destroy() end) end
            for _,x in ipairs(R.ParticleAttachments) do pcall(function() x:Destroy() end) end
            table.clear(R.ParticleEmitters); table.clear(R.ParticleAttachments); R.ParticleRoot=nil
        end

        R.buildParticles = function()
            local _,root=R.getCharacter(); R.destroyParticles()
            if not State.Particles or not root then return end
            R.ParticleRoot=root
            local r=State.ParticleRadius
            local offsets={Vector3.new(r,0,0),Vector3.new(-r,0,0),Vector3.new(0,r,0),Vector3.new(0,-r,0),Vector3.new(0,0,r),Vector3.new(0,0,-r)}
            for i,pos in ipairs(offsets) do
                local a=Instance.new("Attachment"); a.Name="E17_ParticlePoint_"..i; a.Position=pos; a.Parent=root; R.ParticleAttachments[#R.ParticleAttachments+1]=a
                local e=Instance.new("ParticleEmitter")
                e.Name="E17_PlayerParticles"; e.Enabled=true; e.SpreadAngle=Vector2.new(180,180); e.Rotation=NumberRange.new(0,360); e.RotSpeed=NumberRange.new(-80,80); e.LightEmission=0.35; e.Parent=a
                R.ParticleEmitters[#R.ParticleEmitters+1]=e
            end
        end

        R.updateParticles = function()
            local _,root=R.getCharacter()
            if not State.Particles or not root then if #R.ParticleEmitters>0 then R.destroyParticles() end return end
            if R.ParticleRoot~=root or #R.ParticleEmitters==0 then R.buildParticles() end
            local color=State.ParticleRainbow and R.rainbow(State.ParticleRainbowSpeed,0) or State.ParticleColor
            local each=State.ParticleRate/math.max(1,#R.ParticleEmitters)
            local tex=R.normalizeAsset(State.ParticleTexture)
            for i,e in ipairs(R.ParticleEmitters) do
                local c=State.ParticleRainbow and R.rainbow(State.ParticleRainbowSpeed,(i-1)/#R.ParticleEmitters) or color
                e.Color=ColorSequence.new(c); e.Rate=each; e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,State.ParticleSize),NumberSequenceKeypoint.new(1,0)})
                e.Speed=NumberRange.new(State.ParticleSpeed*0.35,State.ParticleSpeed); e.Lifetime=NumberRange.new(State.ParticleLifetime*0.65,State.ParticleLifetime)
                e.Texture=tex
            end
        end

        R.afterMaterial = function()
            local map = {
                Neon = Enum.Material.Neon,
                ForceField = Enum.Material.ForceField,
                SmoothPlastic = Enum.Material.SmoothPlastic,
                Glass = Enum.Material.Glass,
            }
            return map[State.AfterimageMaterial] or Enum.Material.Neon
        end

        R.afterColor = function(index)
            if State.AfterimageColorMode=="Rainbow" then return R.rainbow(State.AfterimageRainbowSpeed,(index or 0)*0.035) end
            if State.AfterimageColorMode=="Gradient" then
                local t=((os.clock()*0.65)+(index or 0)*0.09)%1
                return State.AfterimageColorA:Lerp(State.AfterimageColorB,t)
            end
            return State.AfterimageColorA
        end

        R.removeAfterimage = function(model)
            for i=#R.Afterimages,1,-1 do if R.Afterimages[i]==model then table.remove(R.Afterimages,i) break end end
            if model then pcall(function() model:Destroy() end) end
        end

        R.spawnAfterimage = function()
            if not State.Afterimage then return end
            local char,root=R.getCharacter(); if not char or not root then return end
            if State.AfterimageOnlyMoving and root.AssemblyLinearVelocity.Magnitude<0.8 then return end
            if R.LastAfterPosition and (root.Position-R.LastAfterPosition).Magnitude<State.AfterimageSpacing then return end
            R.LastAfterPosition=root.Position
            local model=Instance.new("Model"); model.Name="Experiment17_AsrielAfterimage"; model.Parent=R.Root
            local baseColor=R.afterColor(#R.Afterimages)
            local made=0
            for _,part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") and R.BodyNames[part.Name] then
                    local ok,clone=pcall(function() return part:Clone() end)
                    if ok and clone then
                        for _,d in ipairs(clone:GetChildren()) do
                            if d:IsA("SpecialMesh") then
                                pcall(function() d.TextureId="" end)
                                pcall(function() d.VertexColor=Vector3.new(1,1,1) end)
                            else d:Destroy() end
                        end
                        clone.Name="Ghost_"..part.Name; clone.Anchored=true; clone.CanCollide=false; clone.CanTouch=false; clone.CanQuery=false; clone.CastShadow=false; clone.Massless=true
                        clone.CFrame=part.CFrame; clone.Material=R.afterMaterial(); clone.Color=baseColor; clone.Transparency=State.AfterimageTransparency
                        if clone:IsA("MeshPart") then pcall(function() clone.TextureID="" end) end
                        clone.Parent=model; made+=1
                        local info=TweenInfo.new(State.AfterimageLifetime,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
                        pcall(function() TweenService:Create(clone,info,{Transparency=1,Color=R.afterColor(made+2)}):Play() end)
                    end
                end
            end
            if made==0 then model:Destroy() return end
            R.Afterimages[#R.Afterimages+1]=model
            while #R.Afterimages>State.AfterimageMaxActive do R.removeAfterimage(R.Afterimages[1]) end
            task.delay(State.AfterimageLifetime+0.08,function() R.removeAfterimage(model) end)
        end

        R.clearAfterimages = function()
            local copy={}; for _,m in ipairs(R.Afterimages) do copy[#copy+1]=m end
            for _,m in ipairs(copy) do R.removeAfterimage(m) end
            table.clear(R.Afterimages); R.LastAfterPosition=nil
        end

        R.toolTrailPositions = function(handle)
            local s=handle.Size*0.5*State.ToolTrailWidth
            local axis=State.ToolTrailAxis
            if axis=="Longest" then
                if s.X>=s.Y and s.X>=s.Z then axis="X" elseif s.Y>=s.X and s.Y>=s.Z then axis="Y" else axis="Z" end
            end
            if axis=="X" then return Vector3.new(-s.X,0,0),Vector3.new(s.X,0,0)
            elseif axis=="Y" then return Vector3.new(0,-s.Y,0),Vector3.new(0,s.Y,0)
            else return Vector3.new(0,0,-s.Z),Vector3.new(0,0,s.Z) end
        end

        R.destroyToolTrail = function(tool)
            local data=R.ToolTrailData[tool]
            if not data then return end
            if data.Trail then pcall(function() data.Trail:Destroy() end) end
            if data.A0 then pcall(function() data.A0:Destroy() end) end
            if data.A1 then pcall(function() data.A1:Destroy() end) end
            R.ToolTrailData[tool]=nil
        end

        R.ensureToolTrail = function(tool)
            if not State.ToolTrails then R.destroyToolTrail(tool) return nil end
            local handle=tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart",true)
            if not handle then R.destroyToolTrail(tool) return nil end
            local data=R.ToolTrailData[tool]
            if data and data.Handle~=handle then R.destroyToolTrail(tool); data=nil end
            if not data then
                local p0,p1=R.toolTrailPositions(handle)
                local a0=Instance.new("Attachment"); a0.Name="E17_ToolTrailA"; a0.Position=p0; a0.Parent=handle
                local a1=Instance.new("Attachment"); a1.Name="E17_ToolTrailB"; a1.Position=p1; a1.Parent=handle
                local tr=Instance.new("Trail"); tr.Name="E17_ToolMotionTrail"; tr.Attachment0=a0; tr.Attachment1=a1; tr.FaceCamera=false; tr.MinLength=0.02; tr.Parent=handle
                data={Handle=handle,A0=a0,A1=a1,Trail=tr}; R.ToolTrailData[tool]=data
            end
            return data
        end

        R.updateToolTrails = function()
            local char=LocalPlayer.Character
            local seen={}
            if State.ToolTrails and char then
                for _,tool in ipairs(char:GetChildren()) do
                    if tool:IsA("Tool") then
                        local data=R.ensureToolTrail(tool)
                        if data then
                            seen[tool]=true
                            local p0,p1=R.toolTrailPositions(data.Handle); data.A0.Position=p0; data.A1.Position=p1
                            local a,b=State.ToolTrailColorA,State.ToolTrailColorB
                            if State.ToolTrailRainbow then a=R.rainbow(State.ToolTrailRainbowSpeed,0); b=R.rainbow(State.ToolTrailRainbowSpeed,0.18) end
                            data.Trail.Color=ColorSequence.new(a,b); data.Trail.Lifetime=State.ToolTrailLifetime; data.Trail.Texture=R.normalizeAsset(State.ToolTrailTexture); data.Trail.LightEmission=State.ToolTrailLightEmission
                            data.Trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.02),NumberSequenceKeypoint.new(0.7,0.28),NumberSequenceKeypoint.new(1,1)})
                            data.Trail.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0.1)})
                        end
                    end
                end
            end
            local keys={}; for tool in pairs(R.ToolTrailData) do keys[#keys+1]=tool end
            for _,tool in ipairs(keys) do if not seen[tool] or not tool.Parent then R.destroyToolTrail(tool) end end
        end

        R.onCharacter = function()
            task.delay(0.25,function()
                R.destroyTrail(); R.destroyParticles(); R.clearAfterimages()
                if State.Trail then R.rebuildTrail() end
                if State.Particles then R.buildParticles() end
                R.updateChams(); R.updateToolTrails()
            end)
        end

        Scope:TrackConnection(LocalPlayer.CharacterAdded:Connect(R.onCharacter))

        Scope:TrackConnection(RunService.RenderStepped:Connect(function(dt)
            R.Camera=Workspace.CurrentCamera or R.Camera
            if State.FOVEnabled and R.Camera then R.Camera.FieldOfView=State.FOV end
            if State.ThirdPerson and State.ThirdPersonEnforce then R.applyCamera() end
            R.updateChams(); R.updateTrail(); R.updateParticles(); R.updateToolTrails()
            if State.Afterimage then
                R.AfterTimer+=dt
                if R.AfterTimer>=math.max(0.03,State.AfterimageInterval) then R.AfterTimer=0; R.spawnAfterimage() end
            else R.AfterTimer=0 end
        end))

        -- UI
        local Camera=Context:CreateSection(Scope,Tab,"Camera",false,"Player / Camera")
        Camera:AddToggle({Name="FOV Override",Flag="Player_FOVEnabled",Default=State.FOVEnabled,RequiredGraphics="Low",Description="Continuously applies the selected camera FieldOfView while enabled.",FPSImpact=0,Callback=function(v) State.FOVEnabled=v if not v and R.Camera then R.Camera.FieldOfView=R.Original.FOV end end})
        Camera:AddSlider({Name="FOV",Flag="Player_FOV",Min=30,Max=120,Default=State.FOV,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.FOV=v if State.FOVEnabled and R.Camera then R.Camera.FieldOfView=v end end})
        Camera:AddSeparator()
        Camera:AddToggle({Name="Third Person",Flag="Player_ThirdPerson",Default=State.ThirdPerson,RequiredGraphics="Low",Description="Sets Classic camera mode and fixes min/max zoom at the selected distance.",FPSImpact=0,Callback=function(v) State.ThirdPerson=v if v then R.applyCamera() else pcall(function() LocalPlayer.CameraMode=R.Original.CameraMode; LocalPlayer.CameraMinZoomDistance=R.Original.MinZoom; LocalPlayer.CameraMaxZoomDistance=R.Original.MaxZoom end) end end})
        Camera:AddSlider({Name="Third Person Distance",Flag="Player_ThirdDistance",Min=3,Max=40,Default=State.ThirdPersonDistance,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.ThirdPersonDistance=v if State.ThirdPerson then R.applyCamera() end end})
        Camera:AddToggle({Name="Enforce Third Person",Flag="Player_ThirdEnforce",Default=State.ThirdPersonEnforce,RequiredGraphics="Low",Description="Re-applies third person each frame if the game tries to force LockFirstPerson or another zoom distance.",FPSImpact=0,Callback=function(v) State.ThirdPersonEnforce=v end})

        local Chams=Context:CreateSection(Scope,Tab,"Local Chams",false,"Player / Chams")
        Chams:AddToggle({Name="Local Chams",Flag="Player_Chams",Default=State.Chams,RequiredGraphics="Medium",FPSImpact={-1,0},Callback=function(v) State.Chams=v R.updateChams() end})
        Chams:AddColorPicker({Name="Cham Color",Flag="Player_ChamColor",Default=State.ChamColor,RequiredGraphics="Low",Callback=function(v) State.ChamColor=v end})
        Chams:AddToggle({Name="Rainbow Chams",Flag="Player_ChamRainbow",Default=State.ChamRainbow,RequiredGraphics="Low",Callback=function(v) State.ChamRainbow=v end})
        Chams:AddSlider({Name="Rainbow Speed",Flag="Player_ChamRGBSpeed",Min=0.02,Max=1.5,Default=State.ChamRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ChamRainbowSpeed=v end})
        Chams:AddSlider({Name="Fill Transparency",Flag="Player_ChamFill",Min=0,Max=1,Default=State.ChamFillTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ChamFillTransparency=v end})
        Chams:AddSlider({Name="Outline Transparency",Flag="Player_ChamOutline",Min=0,Max=1,Default=State.ChamOutlineTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ChamOutlineTransparency=v end})

        local Trail=Context:CreateSection(Scope,Tab,"Character Trail",false,"Player / Trail")
        Trail:AddToggle({Name="Character Trail",Flag="Player_Trail",Default=State.Trail,RequiredGraphics="High",Description="Uses multiple crossing Trail ribbons so the effect does not look like one flat plane.",FPSImpact={-6,-1},Callback=function(v) State.Trail=v if v then R.rebuildTrail() else R.destroyTrail() end end})
        Trail:AddColorPicker({Name="Trail Start",Flag="Player_TrailA",Default=State.TrailColor,RequiredGraphics="Low",Callback=function(v) State.TrailColor=v end})
        Trail:AddColorPicker({Name="Trail End",Flag="Player_TrailB",Default=State.TrailColor2,RequiredGraphics="Low",Callback=function(v) State.TrailColor2=v end})
        Trail:AddToggle({Name="Rainbow Trail",Flag="Player_TrailRainbow",Default=State.TrailRainbow,RequiredGraphics="Medium",Callback=function(v) State.TrailRainbow=v end})
        Trail:AddSlider({Name="Trail RGB Speed",Flag="Player_TrailRGBSpeed",Min=0.02,Max=1.5,Default=State.TrailRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.TrailRainbowSpeed=v end})
        Trail:AddSlider({Name="Trail Lifetime",Flag="Player_TrailLifetime",Min=0.05,Max=3,Default=State.TrailLifetime,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.TrailLifetime=v end})
        Trail:AddSlider({Name="Trail Width",Flag="Player_TrailWidth",Min=0.25,Max=3,Default=State.TrailWidth,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.TrailWidth=v if State.Trail then R.rebuildTrail() end end})
        Trail:AddSlider({Name="Trail Layers",Flag="Player_TrailLayers",Min=1,Max=4,Default=State.TrailLayers,Decimals=0,RequiredGraphics="High",Description="1 = flat ribbon; 3-4 = volumetric crossed ribbons.",FPSImpact={-7,-1},Callback=function(v) State.TrailLayers=math.floor(v) if State.Trail then R.rebuildTrail() end end})
        Trail:AddInput({Name="Trail Texture",Flag="Player_TrailTexture",Default=State.TrailTexture,Placeholder="optional rbxassetid://...",RequiredGraphics="Medium",Callback=function(v) State.TrailTexture=R.normalizeAsset(v) end})

        local Particles=Context:CreateSection(Scope,Tab,"Particle Volume",false,"Player / Particles")
        Particles:AddToggle({Name="Particles",Flag="Player_Particles",Default=State.Particles,RequiredGraphics="High",Description="Six emitters are placed around the root to form a 3D particle volume instead of a single flat origin.",FPSImpact={-10,-2},Callback=function(v) State.Particles=v if v then R.buildParticles() else R.destroyParticles() end end})
        Particles:AddColorPicker({Name="Particle Color",Flag="Player_ParticleColor",Default=State.ParticleColor,RequiredGraphics="Low",Callback=function(v) State.ParticleColor=v end})
        Particles:AddToggle({Name="Rainbow Particles",Flag="Player_ParticleRainbow",Default=State.ParticleRainbow,RequiredGraphics="High",FPSImpact={-2,0},Callback=function(v) State.ParticleRainbow=v end})
        Particles:AddSlider({Name="Particle RGB Speed",Flag="Player_ParticleRGBSpeed",Min=0.02,Max=1.5,Default=State.ParticleRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ParticleRainbowSpeed=v end})
        Particles:AddSlider({Name="Particle Rate",Flag="Player_ParticleRate",Min=1,Max=240,Default=State.ParticleRate,Decimals=0,RequiredGraphics="High",FPSImpact={-12,2},Callback=function(v) State.ParticleRate=v end})
        Particles:AddSlider({Name="Particle Size",Flag="Player_ParticleSize",Min=0.05,Max=3,Default=State.ParticleSize,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.ParticleSize=v end})
        Particles:AddSlider({Name="Particle Speed",Flag="Player_ParticleSpeed",Min=0,Max=20,Default=State.ParticleSpeed,Decimals=1,RequiredGraphics="Medium",Callback=function(v) State.ParticleSpeed=v end})
        Particles:AddSlider({Name="Particle Radius",Flag="Player_ParticleRadius",Min=0.1,Max=5,Default=State.ParticleRadius,Decimals=2,RequiredGraphics="High",Callback=function(v) State.ParticleRadius=v if State.Particles then R.buildParticles() end end})
        Particles:AddSlider({Name="Particle Lifetime",Flag="Player_ParticleLifetime",Min=0.1,Max=4,Default=State.ParticleLifetime,Decimals=2,RequiredGraphics="High",FPSImpact={-5,1},Callback=function(v) State.ParticleLifetime=v end})
        Particles:AddInput({Name="Particle Texture",Flag="Player_ParticleTexture",Default=State.ParticleTexture,Placeholder="rbxassetid://...",RequiredGraphics="Medium",Callback=function(v) State.ParticleTexture=R.normalizeAsset(v) end})

        local Ghost=Context:CreateSection(Scope,Tab,"Asriel Afterimage",false,"Player / Afterimage")
        Ghost:AddToggle({Name="Character Afterimage",Flag="Player_Afterimage",Default=State.Afterimage,RequiredGraphics="Epic",Description="Periodically snapshots body parts into anchored colored clones, creating an Undertale/Asriel-like rainbow character trail.",FPSImpact={-15,-3},Callback=function(v) State.Afterimage=v if not v then R.clearAfterimages() end end})
        Ghost:AddChoice({Name="Color Mode",Flag="Player_AfterColorMode",Values={"Rainbow","Gradient","Solid"},Default=State.AfterimageColorMode,RequiredGraphics="Medium",Callback=function(v) State.AfterimageColorMode=v end})
        Ghost:AddColorPicker({Name="Color A",Flag="Player_AfterColorA",Default=State.AfterimageColorA,RequiredGraphics="Low",Callback=function(v) State.AfterimageColorA=v end})
        Ghost:AddColorPicker({Name="Color B",Flag="Player_AfterColorB",Default=State.AfterimageColorB,RequiredGraphics="Low",Callback=function(v) State.AfterimageColorB=v end})
        Ghost:AddSlider({Name="Rainbow Speed",Flag="Player_AfterRGBSpeed",Min=0.02,Max=1.5,Default=State.AfterimageRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.AfterimageRainbowSpeed=v end})
        Ghost:AddChoice({Name="Ghost Material",Flag="Player_AfterMaterial",Values={"Neon","ForceField","SmoothPlastic","Glass"},Default=State.AfterimageMaterial,RequiredGraphics="Medium",Callback=function(v) State.AfterimageMaterial=v end})
        Ghost:AddSlider({Name="Ghost Transparency",Flag="Player_AfterTransparency",Min=0,Max=0.95,Default=State.AfterimageTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.AfterimageTransparency=v end})
        Ghost:AddSlider({Name="Ghost Lifetime",Flag="Player_AfterLifetime",Min=0.15,Max=3,Default=State.AfterimageLifetime,Decimals=2,RequiredGraphics="High",FPSImpact={-8,2},Callback=function(v) State.AfterimageLifetime=v end})
        Ghost:AddSlider({Name="Spawn Interval",Flag="Player_AfterInterval",Min=0.03,Max=0.6,Default=State.AfterimageInterval,Decimals=2,RequiredGraphics="Epic",Description="Lower values create more body clones per second and cost significantly more FPS.",FPSImpact={-20,5},Callback=function(v) State.AfterimageInterval=v end})
        Ghost:AddSlider({Name="Movement Spacing",Flag="Player_AfterSpacing",Min=0,Max=5,Default=State.AfterimageSpacing,Decimals=2,RequiredGraphics="High",Description="Minimum distance before another snapshot. Increase this to reduce duplicate ghosts.",FPSImpact={-10,3},Callback=function(v) State.AfterimageSpacing=v end})
        Ghost:AddSlider({Name="Max Active Ghosts",Flag="Player_AfterMax",Min=2,Max=30,Default=State.AfterimageMaxActive,Decimals=0,RequiredGraphics="Epic",FPSImpact={-20,5},Callback=function(v) State.AfterimageMaxActive=math.floor(v) end})
        Ghost:AddToggle({Name="Only While Moving",Flag="Player_AfterMoving",Default=State.AfterimageOnlyMoving,RequiredGraphics="Low",Callback=function(v) State.AfterimageOnlyMoving=v end})
        Ghost:AddButton({Name="Clear Afterimages",ButtonText="Clear",RequiredGraphics="Low",Callback=function() R.clearAfterimages() end})

        local Tool=Context:CreateSection(Scope,Tab,"Tool / Weapon Motion Trails",false,"Player / Tool Trails")
        Tool:AddToggle({Name="Tool Motion Trails",Flag="Player_ToolTrails",Default=State.ToolTrails,RequiredGraphics="High",Description="Adds a Trail between two attachments on the equipped Tool handle. The Longest mode automatically uses the handle's longest local axis.",FPSImpact={-5,-1},Callback=function(v) State.ToolTrails=v if not v then local keys={}; for t in pairs(R.ToolTrailData) do keys[#keys+1]=t end; for _,t in ipairs(keys) do R.destroyToolTrail(t) end end end})
        Tool:AddChoice({Name="Trail Axis",Flag="Player_ToolTrailAxis",Values={"Longest","X","Y","Z"},Default=State.ToolTrailAxis,RequiredGraphics="Low",Callback=function(v) State.ToolTrailAxis=v end})
        Tool:AddColorPicker({Name="Trail Start",Flag="Player_ToolTrailA",Default=State.ToolTrailColorA,RequiredGraphics="Low",Callback=function(v) State.ToolTrailColorA=v end})
        Tool:AddColorPicker({Name="Trail End",Flag="Player_ToolTrailB",Default=State.ToolTrailColorB,RequiredGraphics="Low",Callback=function(v) State.ToolTrailColorB=v end})
        Tool:AddToggle({Name="Rainbow Tool Trails",Flag="Player_ToolTrailRainbow",Default=State.ToolTrailRainbow,RequiredGraphics="Medium",Callback=function(v) State.ToolTrailRainbow=v end})
        Tool:AddSlider({Name="Trail RGB Speed",Flag="Player_ToolTrailRGBSpeed",Min=0.02,Max=1.5,Default=State.ToolTrailRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ToolTrailRainbowSpeed=v end})
        Tool:AddSlider({Name="Trail Lifetime",Flag="Player_ToolTrailLifetime",Min=0.03,Max=2,Default=State.ToolTrailLifetime,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.ToolTrailLifetime=v end})
        Tool:AddSlider({Name="Trail Width",Flag="Player_ToolTrailWidth",Min=0.15,Max=2,Default=State.ToolTrailWidth,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.ToolTrailWidth=v end})
        Tool:AddSlider({Name="Light Emission",Flag="Player_ToolTrailLight",Min=0,Max=1,Default=State.ToolTrailLightEmission,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ToolTrailLightEmission=v end})
        Tool:AddInput({Name="Trail Texture",Flag="Player_ToolTrailTexture",Default=State.ToolTrailTexture,Placeholder="optional rbxassetid://...",RequiredGraphics="Medium",Callback=function(v) State.ToolTrailTexture=R.normalizeAsset(v) end})

        Scope:AddCleaner(function()
            R.restoreCamera(); R.destroyTrail(); R.destroyParticles(); R.clearAfterimages()
            local keys={}; for t in pairs(R.ToolTrailData) do keys[#keys+1]=t end
            for _,t in ipairs(keys) do R.destroyToolTrail(t) end
            if R.Highlight then pcall(function() R.Highlight:Destroy() end); R.Highlight=nil end
        end)
    end,
}
