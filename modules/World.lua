--[[
-- v19 compatibility: every feature stays accessible even when the UI Performance profile is active.
    Experiment 17 - World module
    Target: Experiment17 modular Loader v0.2+

    Features:
      * Anchored / unanchored part inspector with separate colors
      * Full-map local X-Ray with reliable LocalTransparencyModifier restore
      * Polygon-style wireframe cages built from Attachments + Beams
      * Primitive sphere/cylinder wireframe approximation
      * Movement Echo / footsteps / jump / landing markers

    Wireframe note:
      Roblox does not expose arbitrary MeshPart triangle topology to a normal
      runtime LocalScript in a universally reliable way. MeshParts therefore
      use a triangulated local bounding cage; primitive Part balls/cylinders
      get denser polygon approximations.
]]

return {
    Id = "World",
    Name = "World",
    Version = "2.1.0-v19",
    Order = 40,

    Init = function(Context, Scope, Tab)
        local S = Context.Services
        local Players, Workspace, RunService = S.Players, S.Workspace, S.RunService
        local TweenService = S.TweenService
        local LocalPlayer = Context.LocalPlayer

        local State = Context:GetState("World", {
            Inspector = false,
            Anchored = true,
            Unanchored = true,
            AnchoredColor = Color3.fromRGB(70, 215, 110),
            UnanchoredColor = Color3.fromRGB(230, 70, 70),
            SurfaceTransparency = 0.90,
            LineTransparency = 0.35,
            LineThickness = 0.02,
            MaxDistance = 450,
            MaxParts = 650,
            RefreshRate = 1.0,

            XRay = false,
            XRayTransparency = 0.72,
            XRayBatch = 350,

            Wireframe = false,
            WireframeMode = "Triangulated",
            WireframeColor = Color3.fromRGB(210, 210, 230),
            WireframeRainbow = false,
            WireframeRainbowSpeed = 0.22,
            WireframeTransparency = 0.18,
            WireframeThickness = 0.015,
            WireframeMaxParts = 100,
            WireframeSegments = 12,

            MovementEcho = false,
            EchoShape = "Ring",
            EchoColorMode = "Per Player",
            EchoColor = Color3.fromRGB(255, 120, 120),
            EchoLifetime = 0.85,
            EchoSize = 4.0,
            EchoDistance = 1200,
            EchoSpacing = 2.8,
            EchoJumpOnly = false,
            EchoAlwaysOnTop = false,
        })

        local R = {
            Timer = 0,
            EchoTimer = 0,
            InspectorBoxes = setmetatable({}, {__mode="k"}),
            WireData = setmetatable({}, {__mode="k"}),
            XRayOriginal = setmetatable({}, {__mode="k"}),
            XRayToken = 0,
            EchoState = setmetatable({}, {__mode="k"}),
        }

        R.Root = Scope:TrackInstance(Instance.new("Folder"))
        R.Root.Name = "Experiment17_World_Runtime"
        R.Root.Parent = Workspace

        R.rainbow = function(speed, offset)
            return Color3.fromHSV(((os.clock()*(speed or 0.2))+(offset or 0))%1,0.9,1)
        end

        R.isCharacterPart = function(part)
            local model=part and part:FindFirstAncestorOfClass("Model")
            return model and Players:GetPlayerFromCharacter(model) ~= nil
        end

        R.isWorldPart = function(part)
            if not part or not part:IsA("BasePart") or not part.Parent then return false end
            if part:IsDescendantOf(R.Root) then return false end
            if R.isCharacterPart(part) then return false end
            return true
        end

        R.restoreXRay = function()
            R.XRayToken += 1
            for part, value in pairs(R.XRayOriginal) do
                if part and part.Parent then
                    pcall(function() part.LocalTransparencyModifier = value end)
                end
            end
            table.clear(R.XRayOriginal)
        end

        R.applyXRayPart = function(part)
            if not State.XRay or not R.isWorldPart(part) then return end
            if R.XRayOriginal[part] == nil then
                local ok,value=pcall(function() return part.LocalTransparencyModifier end)
                if not ok then return end
                R.XRayOriginal[part]=value
            end
            pcall(function()
                part.LocalTransparencyModifier = math.max(R.XRayOriginal[part] or 0, State.XRayTransparency)
            end)
        end

        R.scanXRay = function()
            if not State.XRay then return end
            R.XRayToken += 1
            local token=R.XRayToken
            task.spawn(function()
                local descendants=Workspace:GetDescendants()
                local batch=math.max(50,math.floor(State.XRayBatch))
                for i,obj in ipairs(descendants) do
                    if token~=R.XRayToken or not State.XRay then return end
                    if obj:IsA("BasePart") then R.applyXRayPart(obj) end
                    if i%batch==0 then task.wait() end
                end
            end)
        end

        R.setXRay = function(enabled)
            State.XRay=enabled==true
            if State.XRay then R.scanXRay() else R.restoreXRay() end
        end

        R.clearInspector = function()
            for part,box in pairs(R.InspectorBoxes) do
                pcall(function() box:Destroy() end)
                R.InspectorBoxes[part]=nil
            end
        end

        R.destroyWire = function(part)
            local data=R.WireData[part]
            if not data then return end
            if data.Attachments then
                for _,attachment in ipairs(data.Attachments) do
                    pcall(function() attachment:Destroy() end)
                end
            end
            if data.Folder then pcall(function() data.Folder:Destroy() end) end
            R.WireData[part]=nil
        end

        R.clearWire = function()
            local keys={}
            for part in pairs(R.WireData) do keys[#keys+1]=part end
            for _,part in ipairs(keys) do R.destroyWire(part) end
        end

        R.addBeam = function(data, a, b)
            local beam=Instance.new("Beam")
            beam.Name="E17_WireEdge"
            beam.Attachment0=a; beam.Attachment1=b
            beam.FaceCamera=true
            beam.Width0=State.WireframeThickness; beam.Width1=State.WireframeThickness
            beam.LightEmission=0.35; beam.LightInfluence=0
            beam.Color=ColorSequence.new(State.WireframeColor)
            beam.Transparency=NumberSequence.new(State.WireframeTransparency)
            beam.Parent=data.Folder
            data.Beams[#data.Beams+1]=beam
            return beam
        end

        R.addAttachment = function(data, pos)
            local a=Instance.new("Attachment")
            a.Name="E17_WirePoint"
            a.Position=pos
            a.Parent=data.Part
            data.Attachments[#data.Attachments+1]=a
            return a
        end

        R.createBoxWire = function(part, dense)
            local data={Part=part,Attachments={},Beams={}}
            data.Folder=Instance.new("Folder"); data.Folder.Name="E17_Wireframe"; data.Folder.Parent=R.Root
            local h=part.Size*0.5
            local p={
                Vector3.new(-h.X,-h.Y,-h.Z), Vector3.new(h.X,-h.Y,-h.Z),
                Vector3.new(h.X,h.Y,-h.Z), Vector3.new(-h.X,h.Y,-h.Z),
                Vector3.new(-h.X,-h.Y,h.Z), Vector3.new(h.X,-h.Y,h.Z),
                Vector3.new(h.X,h.Y,h.Z), Vector3.new(-h.X,h.Y,h.Z),
            }
            local a={}
            for i=1,8 do a[i]=R.addAttachment(data,p[i]) end
            local edges={{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
            for _,e in ipairs(edges) do R.addBeam(data,a[e[1]],a[e[2]]) end
            if State.WireframeMode~="Outline" then
                local diagonals={{1,3},{1,6},{1,8},{2,4},{2,7},{3,6},{3,8},{4,5},{4,7},{5,7},{6,8}}
                for _,e in ipairs(diagonals) do R.addBeam(data,a[e[1]],a[e[2]]) end
            end
            if dense then
                local mids={
                    {Vector3.new(-h.X,0,-h.Z),Vector3.new(h.X,0,-h.Z)},
                    {Vector3.new(-h.X,0,h.Z),Vector3.new(h.X,0,h.Z)},
                    {Vector3.new(0,-h.Y,-h.Z),Vector3.new(0,h.Y,-h.Z)},
                    {Vector3.new(0,-h.Y,h.Z),Vector3.new(0,h.Y,h.Z)},
                    {Vector3.new(-h.X,-h.Y,0),Vector3.new(-h.X,h.Y,0)},
                    {Vector3.new(h.X,-h.Y,0),Vector3.new(h.X,h.Y,0)},
                }
                for _,pair in ipairs(mids) do local x=R.addAttachment(data,pair[1]); local y=R.addAttachment(data,pair[2]); R.addBeam(data,x,y) end
            end
            R.WireData[part]=data
            return data
        end

        R.createBallWire = function(part)
            local data={Part=part,Attachments={},Beams={}}
            data.Folder=Instance.new("Folder"); data.Folder.Name="E17_WireBall"; data.Folder.Parent=R.Root
            local seg=math.clamp(math.floor(State.WireframeSegments),6,24)
            local r=part.Size*0.5
            local function ring(axis)
                local arr={}
                for i=0,seg-1 do
                    local t=(i/seg)*math.pi*2
                    local pos
                    if axis==1 then pos=Vector3.new(0,math.cos(t)*r.Y,math.sin(t)*r.Z)
                    elseif axis==2 then pos=Vector3.new(math.cos(t)*r.X,0,math.sin(t)*r.Z)
                    else pos=Vector3.new(math.cos(t)*r.X,math.sin(t)*r.Y,0) end
                    arr[#arr+1]=R.addAttachment(data,pos)
                end
                for i=1,#arr do R.addBeam(data,arr[i],arr[(i%#arr)+1]) end
            end
            ring(1); ring(2); ring(3)
            R.WireData[part]=data
            return data
        end

        R.createCylinderWire = function(part)
            local data={Part=part,Attachments={},Beams={}}
            data.Folder=Instance.new("Folder"); data.Folder.Name="E17_WireCylinder"; data.Folder.Parent=R.Root
            local seg=math.clamp(math.floor(State.WireframeSegments),6,24)
            local h=part.Size*0.5
            local left,right={},{}
            for i=0,seg-1 do
                local t=(i/seg)*math.pi*2
                local y,z=math.cos(t)*h.Y,math.sin(t)*h.Z
                left[#left+1]=R.addAttachment(data,Vector3.new(-h.X,y,z))
                right[#right+1]=R.addAttachment(data,Vector3.new(h.X,y,z))
            end
            for i=1,seg do
                R.addBeam(data,left[i],left[(i%seg)+1]); R.addBeam(data,right[i],right[(i%seg)+1])
                if i%math.max(1,math.floor(seg/6))==1 then R.addBeam(data,left[i],right[i]) end
            end
            R.WireData[part]=data
            return data
        end

        R.createWire = function(part)
            if not R.isWorldPart(part) then return nil end
            if part:IsA("Part") and part.Shape==Enum.PartType.Ball then return R.createBallWire(part) end
            if part:IsA("Part") and part.Shape==Enum.PartType.Cylinder then return R.createCylinderWire(part) end
            return R.createBoxWire(part,State.WireframeMode=="Dense")
        end

        R.updateWireStyle = function()
            for part,data in pairs(R.WireData) do
                if not part.Parent then R.destroyWire(part)
                else
                    local color=State.WireframeRainbow and R.rainbow(State.WireframeRainbowSpeed,(math.abs(part.Position.X+part.Position.Z)%83)/83) or State.WireframeColor
                    for _,beam in ipairs(data.Beams) do
                        beam.Width0=State.WireframeThickness; beam.Width1=State.WireframeThickness
                        beam.Color=ColorSequence.new(color); beam.Transparency=NumberSequence.new(State.WireframeTransparency); beam.Enabled=State.Wireframe
                    end
                end
            end
        end

        R.collectNearby = function(maxParts)
            local pos
            local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then pos=root.Position
            else local cam=Workspace.CurrentCamera; pos=cam and cam.CFrame.Position or Vector3.zero end
            local params=OverlapParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={LocalPlayer.Character,R.Root}; params.MaxParts=math.max(1,math.floor(maxParts))
            local ok,parts=pcall(function() return Workspace:GetPartBoundsInRadius(pos,State.MaxDistance,params) end)
            if not ok then return {} end
            local result={}
            for _,part in ipairs(parts) do if R.isWorldPart(part) then result[#result+1]=part end end
            return result
        end

        R.refreshWorld = function()
            if not State.Inspector and not State.Wireframe then
                R.clearInspector(); R.clearWire(); return
            end
            local limit=math.max(State.MaxParts,State.WireframeMaxParts)
            local parts=R.collectNearby(limit)
            local seenBox,seenWire={},{}
            local wireCount=0
            for _,part in ipairs(parts) do
                if State.Inspector then
                    seenBox[part]=true
                    local box=R.InspectorBoxes[part]
                    if not box then
                        box=Instance.new("SelectionBox"); box.Name="E17_WorldInspector"; box.Adornee=part; box.Parent=R.Root
                        R.InspectorBoxes[part]=box
                    end
                    local color=part.Anchored and State.AnchoredColor or State.UnanchoredColor
                    box.Color3=color; box.SurfaceColor3=color; box.SurfaceTransparency=State.SurfaceTransparency; box.Transparency=State.LineTransparency; box.LineThickness=State.LineThickness
                    box.Visible=(part.Anchored and State.Anchored) or ((not part.Anchored) and State.Unanchored)
                end
                if State.Wireframe and wireCount<State.WireframeMaxParts then
                    wireCount+=1; seenWire[part]=true
                    if not R.WireData[part] then R.createWire(part) end
                end
            end
            for part,box in pairs(R.InspectorBoxes) do if not seenBox[part] or not State.Inspector or not part.Parent then pcall(function() box:Destroy() end); R.InspectorBoxes[part]=nil end end
            local keys={}; for part in pairs(R.WireData) do keys[#keys+1]=part end
            for _,part in ipairs(keys) do if not seenWire[part] or not State.Wireframe or not part.Parent then R.destroyWire(part) end end
            R.updateWireStyle()
        end

        R.echoColor = function(player)
            if State.EchoColorMode=="Rainbow" then return R.rainbow(0.3,(player.UserId%83)/83) end
            if State.EchoColorMode=="Per Player" then return Color3.fromHSV((player.UserId*0.61803398875)%1,0.8,1) end
            if State.EchoColorMode=="Team" then return player.TeamColor and player.TeamColor.Color or State.EchoColor end
            return State.EchoColor
        end

        R.groundHit = function(character,root)
            local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={character,R.Root}; params.IgnoreWater=false
            return Workspace:Raycast(root.Position,Vector3.new(0,-14,0),params)
        end

        R.surfaceCFrame = function(position, normal)
            normal=(normal.Magnitude>0 and normal.Unit) or Vector3.yAxis
            local ref=math.abs(normal:Dot(Vector3.zAxis))>0.95 and Vector3.xAxis or Vector3.zAxis
            local right=ref:Cross(normal).Unit
            local back=right:Cross(normal).Unit
            return CFrame.fromMatrix(position+normal*0.03,right,normal,back)
        end

        R.makeEchoSurface = function(anchor,color)
            local gui=Instance.new("SurfaceGui"); gui.Name="E17_EchoSurface"; gui.Face=Enum.NormalId.Top; gui.AlwaysOnTop=State.EchoAlwaysOnTop; gui.LightInfluence=0; gui.CanvasSize=Vector2.new(256,256); gui.Parent=anchor
            local base=Instance.new("Frame"); base.Name="Shape"; base.AnchorPoint=Vector2.new(0.5,0.5); base.Position=UDim2.fromScale(0.5,0.5); base.Size=UDim2.fromScale(0.85,0.85); base.BorderSizePixel=0; base.BackgroundColor3=color; base.BackgroundTransparency=0.45; base.Parent=gui
            local shape=State.EchoShape
            if shape=="Circle" or shape=="Ring" then local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=base end
            if shape=="Ring" then base.BackgroundTransparency=1; local s=Instance.new("UIStroke"); s.Thickness=9; s.Color=color; s.Transparency=0.05; s.Parent=base
            elseif shape=="Diamond" then base.Rotation=45
            elseif shape=="Cross" then
                base.BackgroundTransparency=1
                local h=Instance.new("Frame"); h.AnchorPoint=Vector2.new(0.5,0.5); h.Position=UDim2.fromScale(0.5,0.5); h.Size=UDim2.new(1,0,0,20); h.BorderSizePixel=0; h.BackgroundColor3=color; h.Parent=base
                local v=h:Clone(); v.Size=UDim2.new(0,20,1,0); v.Parent=base
            elseif shape=="Triangle" then
                base.BackgroundTransparency=1
                local image=Instance.new("ImageLabel"); image.BackgroundTransparency=1; image.Size=UDim2.fromScale(1,1); image.Image="rbxassetid://6031094678"; image.ImageColor3=color; image.Parent=base
            end
            return gui,base
        end

        R.spawnEcho = function(player,hit)
            if not hit then return end
            local color=R.echoColor(player)
            local anchor=Instance.new("Part")
            anchor.Name="Experiment17_MovementEcho"; anchor.Anchored=true; anchor.CanCollide=false; anchor.CanTouch=false; anchor.CanQuery=false; anchor.CastShadow=false; anchor.Transparency=1
            anchor.Size=Vector3.new(0.15,0.03,0.15); anchor.CFrame=R.surfaceCFrame(hit.Position,hit.Normal); anchor.Parent=R.Root
            local gui,base=R.makeEchoSurface(anchor,color)
            local target=math.max(0.5,State.EchoSize)
            local info=TweenInfo.new(State.EchoLifetime,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
            TweenService:Create(anchor,info,{Size=Vector3.new(target,0.03,target)}):Play()
            pcall(function() TweenService:Create(base,info,{BackgroundTransparency=1}):Play() end)
            for _,d in ipairs(base:GetDescendants()) do
                if d:IsA("UIStroke") then TweenService:Create(d,info,{Transparency=1}):Play()
                elseif d:IsA("Frame") then TweenService:Create(d,info,{BackgroundTransparency=1}):Play()
                elseif d:IsA("ImageLabel") then TweenService:Create(d,info,{ImageTransparency=1}):Play() end
            end
            task.delay(State.EchoLifetime+0.08,function() if anchor and anchor.Parent then anchor:Destroy() end end)
        end

        R.updateEchoes = function()
            if not State.MovementEcho then return end
            local localRoot=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            for _,player in ipairs(Players:GetPlayers()) do
                local char=player.Character; local root=char and char:FindFirstChild("HumanoidRootPart"); local hum=char and char:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.Health>0 then
                    local dist=localRoot and (root.Position-localRoot.Position).Magnitude or 0
                    if not localRoot or dist<=State.EchoDistance then
                        local data=R.EchoState[player]
                        if not data then data={LastPos=root.Position,LastState=hum:GetState()}; R.EchoState[player]=data end
                        local state=hum:GetState(); local moved=Vector3.new(root.Position.X-data.LastPos.X,0,root.Position.Z-data.LastPos.Z).Magnitude
                        local jump=(state==Enum.HumanoidStateType.Jumping and data.LastState~=Enum.HumanoidStateType.Jumping)
                        local land=(data.LastState==Enum.HumanoidStateType.Freefall and state==Enum.HumanoidStateType.Landed)
                        if jump or land or ((not State.EchoJumpOnly) and moved>=State.EchoSpacing) then
                            R.spawnEcho(player,R.groundHit(char,root)); data.LastPos=root.Position
                        end
                        data.LastState=state
                    end
                end
            end
        end

        Scope:TrackConnection(Workspace.DescendantAdded:Connect(function(obj)
            if State.XRay and obj:IsA("BasePart") then task.defer(function() R.applyXRayPart(obj) end) end
        end))

        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            R.Timer+=dt; R.EchoTimer+=dt
            if R.Timer>=math.max(0.15,State.RefreshRate) then R.Timer=0; R.refreshWorld() end
            if R.EchoTimer>=0.12 then R.EchoTimer=0; R.updateEchoes() end
            if State.WireframeRainbow then R.updateWireStyle() end
        end))

        -- UI
        local Inspector=Context:CreateSection(Scope,Tab,"Physics Part Inspector",false,"World / Inspector")
        Inspector:AddToggle({Name="Part Inspector",Flag="World_Inspector",Default=State.Inspector,RequiredGraphics="Low",Description="Highlights nearby map parts. Anchored and unanchored parts use independent colors.",FPSImpact={-8,-1},Callback=function(v) State.Inspector=v R.refreshWorld() end})
        Inspector:AddToggle({Name="Anchored Parts",Flag="World_Anchored",Default=State.Anchored,RequiredGraphics="Low",Callback=function(v) State.Anchored=v R.refreshWorld() end})
        Inspector:AddColorPicker({Name="Anchored Color",Flag="World_AnchoredColor",Default=State.AnchoredColor,RequiredGraphics="Low",Callback=function(v) State.AnchoredColor=v R.refreshWorld() end})
        Inspector:AddToggle({Name="Unanchored Parts",Flag="World_Unanchored",Default=State.Unanchored,RequiredGraphics="Low",Callback=function(v) State.Unanchored=v R.refreshWorld() end})
        Inspector:AddColorPicker({Name="Unanchored Color",Flag="World_UnanchoredColor",Default=State.UnanchoredColor,RequiredGraphics="Low",Callback=function(v) State.UnanchoredColor=v R.refreshWorld() end})
        Inspector:AddSlider({Name="Surface Transparency",Flag="World_SurfaceTransparency",Min=0,Max=1,Default=State.SurfaceTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.SurfaceTransparency=v R.refreshWorld() end})
        Inspector:AddSlider({Name="Line Transparency",Flag="World_LineTransparency",Min=0,Max=1,Default=State.LineTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.LineTransparency=v R.refreshWorld() end})
        Inspector:AddSlider({Name="Line Thickness",Flag="World_LineThickness",Min=0.005,Max=0.08,Default=State.LineThickness,Decimals=3,RequiredGraphics="Low",Callback=function(v) State.LineThickness=v R.refreshWorld() end})
        Inspector:AddSlider({Name="Inspector Distance",Flag="World_MaxDistance",Min=50,Max=2500,Default=State.MaxDistance,Decimals=0,RequiredGraphics="Low",Description="Spatial query radius. Lower values are substantially cheaper on large maps.",FPSImpact={-8,2},Callback=function(v) State.MaxDistance=v end})
        Inspector:AddSlider({Name="Max Parts",Flag="World_MaxParts",Min=50,Max=2000,Default=State.MaxParts,Decimals=0,RequiredGraphics="Low",Description="Caps nearby inspector candidates.",FPSImpact={-14,4},Callback=function(v) State.MaxParts=v end})
        Inspector:AddSlider({Name="Refresh Rate",Flag="World_RefreshRate",Min=0.15,Max=3,Default=State.RefreshRate,Decimals=2,RequiredGraphics="Low",Description="Seconds between spatial-query refreshes. Higher values save CPU.",FPSImpact={-8,2},Callback=function(v) State.RefreshRate=v end})

        local Render=Context:CreateSection(Scope,Tab,"X-Ray / Wireframe",false,"World / Render")
        Render:AddToggle({Name="Full Map X-Ray",Flag="World_XRay",Default=State.XRay,RequiredGraphics="Low",Description="Chunk-scans all Workspace map BaseParts and changes only LocalTransparencyModifier. Every original local value is stored and restored on disable.",FPSImpact={-12,-2},Callback=function(v) R.setXRay(v) end})
        Render:AddSlider({Name="X-Ray Transparency",Flag="World_XRayTransparency",Min=0,Max=1,Default=State.XRayTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.XRayTransparency=v if State.XRay then for part in pairs(R.XRayOriginal) do R.applyXRayPart(part) end end end})
        Render:AddSlider({Name="X-Ray Scan Batch",Flag="World_XRayBatch",Min=50,Max=1500,Default=State.XRayBatch,Decimals=0,RequiredGraphics="Low",Description="How many descendants are processed before yielding during a full-map scan. Smaller batches reduce single-frame spikes.",FPSImpact={-8,2},Callback=function(v) State.XRayBatch=v end})
        Render:AddButton({Name="Rescan X-Ray",ButtonText="Rescan",RequiredGraphics="Low",Callback=function() if State.XRay then R.scanXRay() end end})
        Render:AddSeparator()
        Render:AddToggle({Name="Polygon Wireframe",Flag="World_Wireframe",Default=State.Wireframe,RequiredGraphics="Low",Description="Builds local Attachment/Beam polygon cages around nearby parts. Primitive spheres/cylinders get ring approximations; MeshParts use triangulated bounds.",FPSImpact={-18,-3},Callback=function(v) State.Wireframe=v R.refreshWorld() end})
        Render:AddChoice({Name="Wireframe Mode",Flag="World_WireMode",Values={"Outline","Triangulated","Dense"},Default=State.WireframeMode,RequiredGraphics="Low",Description="Dense adds extra cross sections. Changing topology rebuilds current wireframes.",FPSImpact={-8,-1},Callback=function(v) State.WireframeMode=v R.clearWire() R.refreshWorld() end})
        Render:AddColorPicker({Name="Wireframe Color",Flag="World_WireColor",Default=State.WireframeColor,RequiredGraphics="Low",Callback=function(v) State.WireframeColor=v R.updateWireStyle() end})
        Render:AddToggle({Name="Rainbow Wireframe",Flag="World_WireRainbow",Default=State.WireframeRainbow,RequiredGraphics="Low",FPSImpact={-3,0},Callback=function(v) State.WireframeRainbow=v R.updateWireStyle() end})
        Render:AddSlider({Name="Wireframe RGB Speed",Flag="World_WireRGBSpeed",Min=0.02,Max=1.2,Default=State.WireframeRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.WireframeRainbowSpeed=v end})
        Render:AddSlider({Name="Wireframe Transparency",Flag="World_WireTransparency",Min=0,Max=1,Default=State.WireframeTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.WireframeTransparency=v R.updateWireStyle() end})
        Render:AddSlider({Name="Wireframe Thickness",Flag="World_WireThickness",Min=0.003,Max=0.08,Default=State.WireframeThickness,Decimals=3,RequiredGraphics="Low",FPSImpact={-2,0},Callback=function(v) State.WireframeThickness=v R.updateWireStyle() end})
        Render:AddSlider({Name="Primitive Segments",Flag="World_WireSegments",Min=6,Max=24,Default=State.WireframeSegments,Decimals=0,RequiredGraphics="Low",Description="Polygon count used for Ball/Cylinder Part approximations. Rebuild required.",FPSImpact={-10,2},Callback=function(v) State.WireframeSegments=v R.clearWire() R.refreshWorld() end})
        Render:AddSlider({Name="Wireframe Max Parts",Flag="World_WireMaxParts",Min=5,Max=400,Default=State.WireframeMaxParts,Decimals=0,RequiredGraphics="Low",Description="Main Wireframe performance control. Every part can create many Attachments and Beams.",FPSImpact={-25,5},Callback=function(v) State.WireframeMaxParts=v R.refreshWorld() end})

        local Echo=Context:CreateSection(Scope,Tab,"Movement Echo / Footsteps",false,"World / Movement Echo")
        Echo:AddToggle({Name="Movement Echo",Flag="World_Echo",Default=State.MovementEcho,RequiredGraphics="Low",Description="Creates expanding floor-oriented markers for walking, jumping and landing players.",FPSImpact={-7,-1},Callback=function(v) State.MovementEcho=v if not v then table.clear(R.EchoState) end end})
        Echo:AddChoice({Name="Echo Shape",Flag="World_EchoShape",Values={"Ring","Circle","Square","Diamond","Cross","Triangle"},Default=State.EchoShape,RequiredGraphics="Low",Callback=function(v) State.EchoShape=v end})
        Echo:AddChoice({Name="Echo Color Mode",Flag="World_EchoColorMode",Values={"Per Player","Solid","Team","Rainbow"},Default=State.EchoColorMode,RequiredGraphics="Low",Callback=function(v) State.EchoColorMode=v end})
        Echo:AddColorPicker({Name="Echo Color",Flag="World_EchoColor",Default=State.EchoColor,RequiredGraphics="Low",Callback=function(v) State.EchoColor=v end})
        Echo:AddToggle({Name="Jump / Land Only",Flag="World_EchoJumpOnly",Default=State.EchoJumpOnly,RequiredGraphics="Low",Callback=function(v) State.EchoJumpOnly=v end})
        Echo:AddToggle({Name="Always On Top",Flag="World_EchoAlwaysTop",Default=State.EchoAlwaysOnTop,RequiredGraphics="Low",Description="Makes newly created SurfaceGui echoes visible through geometry.",FPSImpact={-1,0},Callback=function(v) State.EchoAlwaysOnTop=v end})
        Echo:AddSlider({Name="Echo Lifetime",Flag="World_EchoLifetime",Min=0.15,Max=3,Default=State.EchoLifetime,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.EchoLifetime=v end})
        Echo:AddSlider({Name="Echo World Size",Flag="World_EchoSize",Min=0.5,Max=12,Default=State.EchoSize,Decimals=1,RequiredGraphics="Low",Description="Final marker diameter in studs.",Callback=function(v) State.EchoSize=v end})
        Echo:AddSlider({Name="Echo Spacing",Flag="World_EchoSpacing",Min=0.5,Max=12,Default=State.EchoSpacing,Decimals=1,RequiredGraphics="Low",Description="Walking distance before another marker is emitted. Higher values are cheaper.",FPSImpact={-6,2},Callback=function(v) State.EchoSpacing=v end})
        Echo:AddSlider({Name="Echo Distance",Flag="World_EchoDistance",Min=50,Max=5000,Default=State.EchoDistance,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.EchoDistance=v end})

        Scope:AddCleaner(function()
            R.restoreXRay(); R.clearInspector(); R.clearWire(); table.clear(R.EchoState)
        end)
    end,
}
