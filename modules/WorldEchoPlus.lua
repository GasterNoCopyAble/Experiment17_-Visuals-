-- Experiment17 - Movement Echo+ / Footsteps
return {
    Id = "WorldEchoPlus",
    Name = "Movement Echo+",
    Version = "1.0.0",
    Order = 45,
    TargetTab = "World",

    Init = function(Context, Scope, Tab)
        local Players = Context.Services.Players or game:GetService("Players")
        local Workspace = Context.Services.Workspace or workspace
        local RunService = Context.Services.RunService or game:GetService("RunService")
        local TweenService = Context.Services.TweenService or game:GetService("TweenService")
        local LocalPlayer = Context.LocalPlayer or Players.LocalPlayer
        local Library = Context.Library

        local State = Context:GetState("WorldEchoPlus", {
            Enabled=false,
            ShowSelf=true,
            ShowOthers=true,
            Style="Both",
            ColorMode="Per Player",
            Color=Color3.fromRGB(120,190,255),
            RainbowSpeed=0.30,
            Lifetime=0.75,
            StepSpacing=2.2,
            FootWidth=0.65,
            FootLength=1.25,
            FootOffset=0.42,
            MaxDistance=900,
            JumpLand=true,
            PulseSize=3.8,
            ActiveLimit=100,
        })

        local R={Running=true,PlayerState=setmetatable({}, {__mode="k"}),Active={}}
        R.Root=Scope:TrackInstance(Instance.new("Folder")); R.Root.Name="Experiment17_EchoPlus_Runtime"; R.Root.Parent=Workspace

        local function notify(text,kind)
            local shared=Context.Shared and Context.Shared.UIEnhancements
            if shared and type(shared.Notify)=="function" then shared.Notify(text,kind)
            elseif Library and type(Library.Notify)=="function" then pcall(function() Library:Notify({Title="Experiment 17 • Echo+",Text=tostring(text),Type=kind or "Info",Duration=2.5}) end) end
        end

        local function findControl(flag)
            for _,c in pairs((Library and Library.Controls) or {}) do if c and c.Flag==flag then return c end end
        end

        local function disableOldEcho()
            local c=findControl("World_Echo")
            if c and type(c.Get)=="function" and type(c.Set)=="function" then
                local ok,v=pcall(function() return c:Get() end)
                if ok and v==true then pcall(function() c:Set(false) end) end
            end
        end

        local function colorFor(player,hit)
            if State.ColorMode=="Rainbow" then
                return Color3.fromHSV(((os.clock()*State.RainbowSpeed)+(player.UserId%97)/97)%1,0.9,1)
            elseif State.ColorMode=="Team" then
                return player.TeamColor and player.TeamColor.Color or State.Color
            elseif State.ColorMode=="Surface" and hit and hit.Instance and hit.Instance:IsA("BasePart") then
                return hit.Instance.Color
            elseif State.ColorMode=="Per Player" then
                return Color3.fromHSV((player.UserId*0.61803398875)%1,0.78,1)
            end
            return State.Color
        end

        local function removeActive(obj)
            for i=#R.Active,1,-1 do if R.Active[i]==obj then table.remove(R.Active,i) break end end
            if obj and obj.Parent then pcall(function() obj:Destroy() end) end
        end

        local function capActive()
            local limit=math.max(10,math.floor(State.ActiveLimit))
            while #R.Active>limit do removeActive(R.Active[1]) end
        end

        local function surfaceCFrame(position,normal,forward)
            normal=normal.Magnitude>0 and normal.Unit or Vector3.yAxis
            forward=forward-normal*forward:Dot(normal)
            if forward.Magnitude<0.01 then forward=Vector3.zAxis-normal*Vector3.zAxis:Dot(normal) end
            if forward.Magnitude<0.01 then forward=Vector3.xAxis end
            forward=forward.Unit
            local right=forward:Cross(normal)
            if right.Magnitude<0.01 then right=Vector3.xAxis else right=right.Unit end
            forward=normal:Cross(right).Unit
            return CFrame.fromMatrix(position,right,normal,-forward)
        end

        local function rayGround(character,origin)
            local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={character,R.Root}; params.IgnoreWater=false
            return Workspace:Raycast(origin+Vector3.new(0,2,0),Vector3.new(0,-8,0),params)
        end

        local function spawnFoot(player,character,root,side,direction)
            if State.Style=="Rings" then return end
            local sideOffset=root.CFrame.RightVector*(State.FootOffset*side)
            local hit=rayGround(character,root.Position+sideOffset)
            if not hit then return end
            local color=colorFor(player,hit)
            local part=Instance.new("Part")
            part.Name=side<0 and "E17_LeftFootEcho" or "E17_RightFootEcho"
            part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false; part.CastShadow=false
            part.Material=Enum.Material.Neon; part.Color=color; part.Transparency=0.18
            part.Size=Vector3.new(State.FootWidth,0.025,State.FootLength)
            part.CFrame=surfaceCFrame(hit.Position+hit.Normal*0.025,hit.Normal,direction)
            part.Parent=R.Root
            R.Active[#R.Active+1]=part; capActive()
            local life=math.max(0.15,State.Lifetime)
            local tween=TweenService:Create(part,TweenInfo.new(life,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=1,Size=Vector3.new(State.FootWidth*1.12,0.02,State.FootLength*1.12)})
            tween:Play(); task.delay(life+0.05,function() removeActive(part) end)
        end

        local function spawnRing(player,character,root,scale)
            if State.Style=="Footprints" and scale<=1.05 then return end
            local hit=rayGround(character,root.Position)
            if not hit then return end
            local color=colorFor(player,hit)
            local anchor=Instance.new("Part")
            anchor.Name="E17_EchoPulse"; anchor.Anchored=true; anchor.CanCollide=false; anchor.CanTouch=false; anchor.CanQuery=false; anchor.CastShadow=false; anchor.Transparency=1
            anchor.Size=Vector3.new(0.1,0.02,0.1); anchor.CFrame=surfaceCFrame(hit.Position+hit.Normal*0.03,hit.Normal,root.CFrame.LookVector); anchor.Parent=R.Root
            local adorn=Instance.new("CylinderHandleAdornment")
            adorn.Name="Ring"; adorn.Adornee=anchor; adorn.AlwaysOnTop=false; adorn.Color3=color; adorn.Transparency=0.18; adorn.Height=0.025
            adorn.Radius=math.max(0.4,State.PulseSize*0.22*scale); adorn.CFrame=CFrame.Angles(math.rad(90),0,0); adorn.Parent=anchor
            R.Active[#R.Active+1]=anchor; capActive()
            local life=math.max(0.15,State.Lifetime)
            TweenService:Create(adorn,TweenInfo.new(life,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Radius=State.PulseSize*scale,Transparency=1}):Play()
            task.delay(life+0.05,function() removeActive(anchor) end)
        end

        local function eligible(player,root)
            if player==LocalPlayer and not State.ShowSelf then return false end
            if player~=LocalPlayer and not State.ShowOthers then return false end
            local myRoot=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myRoot and (root.Position-myRoot.Position).Magnitude>State.MaxDistance then return false end
            return true
        end

        local accumulator=0
        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            if not State.Enabled then return end
            accumulator+=dt
            if accumulator<1/30 then return end
            accumulator=0

            for _,player in ipairs(Players:GetPlayers()) do
                local char=player.Character
                local hum=char and char:FindFirstChildOfClass("Humanoid")
                local root=char and char:FindFirstChild("HumanoidRootPart")
                if hum and root and hum.Health>0 and eligible(player,root) then
                    local data=R.PlayerState[player]
                    if not data then data={LastPos=root.Position,LastState=hum:GetState(),Side=-1}; R.PlayerState[player]=data end
                    local state=hum:GetState()
                    local delta=Vector3.new(root.Position.X-data.LastPos.X,0,root.Position.Z-data.LastPos.Z)
                    local moved=delta.Magnitude
                    local direction=moved>0.05 and delta.Unit or root.CFrame.LookVector
                    local jumping=(state==Enum.HumanoidStateType.Jumping and data.LastState~=Enum.HumanoidStateType.Jumping)
                    local landed=((data.LastState==Enum.HumanoidStateType.Freefall or data.LastState==Enum.HumanoidStateType.Jumping) and (state==Enum.HumanoidStateType.Landed or state==Enum.HumanoidStateType.Running or state==Enum.HumanoidStateType.RunningNoPhysics))

                    if State.JumpLand and jumping then spawnRing(player,char,root,0.8) end
                    if State.JumpLand and landed then spawnRing(player,char,root,1.35) end

                    local grounded=hum.FloorMaterial~=Enum.Material.Air
                    if grounded and moved>=State.StepSpacing then
                        data.Side=-data.Side
                        spawnFoot(player,char,root,data.Side,direction)
                        if State.Style=="Rings" or State.Style=="Both" then spawnRing(player,char,root,0.55) end
                        data.LastPos=root.Position
                    elseif moved>State.StepSpacing*3 then
                        data.LastPos=root.Position
                    end
                    data.LastState=state
                end
            end
        end))

        Scope:TrackConnection(Players.PlayerRemoving:Connect(function(p) R.PlayerState[p]=nil end))

        local Section=Context:CreateSection(Scope,Tab,"Movement Echo+ / Footsteps",false,"World / Echo Plus")
        Section:AddToggle({Name="Movement Echo+",Flag="World_EchoPlus",Default=State.Enabled,RequiredGraphics="Low",Description="Alternating left/right floor footprints with optional pulse rings. Enabling this disables the older Movement Echo to avoid duplicates.",FPSImpact={-8,-1},Callback=function(v) State.Enabled=v if v then disableOldEcho(); notify("Movement Echo+ enabled","Success") else table.clear(R.PlayerState) end end})
        Section:AddToggle({Name="Show Self",Flag="World_EchoPlusSelf",Default=State.ShowSelf,RequiredGraphics="Low",Callback=function(v) State.ShowSelf=v end})
        Section:AddToggle({Name="Show Other Players",Flag="World_EchoPlusOthers",Default=State.ShowOthers,RequiredGraphics="Low",Callback=function(v) State.ShowOthers=v end})
        Section:AddChoice({Name="Echo Style",Flag="World_EchoPlusStyle",Values={"Both","Footprints","Rings"},Default=State.Style,RequiredGraphics="Low",Callback=function(v) State.Style=v end})
        Section:AddChoice({Name="Color Mode",Flag="World_EchoPlusColorMode",Values={"Per Player","Solid","Team","Rainbow","Surface"},Default=State.ColorMode,RequiredGraphics="Low",Callback=function(v) State.ColorMode=v end})
        Section:AddColorPicker({Name="Solid Color",Flag="World_EchoPlusColor",Default=State.Color,RequiredGraphics="Low",Callback=function(v) State.Color=v end})
        Section:AddSlider({Name="Rainbow Speed",Flag="World_EchoPlusRGBSpeed",Min=0.02,Max=1.5,Default=State.RainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.RainbowSpeed=v end})
        Section:AddSlider({Name="Step Spacing",Flag="World_EchoPlusSpacing",Min=0.6,Max=8,Default=State.StepSpacing,Decimals=1,Suffix=" studs",RequiredGraphics="Low",Callback=function(v) State.StepSpacing=v end})
        Section:AddSlider({Name="Foot Width",Flag="World_EchoPlusWidth",Min=0.2,Max=2,Default=State.FootWidth,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.FootWidth=v end})
        Section:AddSlider({Name="Foot Length",Flag="World_EchoPlusLength",Min=0.4,Max=3,Default=State.FootLength,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.FootLength=v end})
        Section:AddSlider({Name="Left / Right Offset",Flag="World_EchoPlusOffset",Min=0,Max=1.5,Default=State.FootOffset,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.FootOffset=v end})
        Section:AddSlider({Name="Lifetime",Flag="World_EchoPlusLifetime",Min=0.15,Max=3,Default=State.Lifetime,Decimals=2,Suffix=" s",RequiredGraphics="Low",Callback=function(v) State.Lifetime=v end})
        Section:AddToggle({Name="Jump / Landing Pulses",Flag="World_EchoPlusJumpLand",Default=State.JumpLand,RequiredGraphics="Low",Callback=function(v) State.JumpLand=v end})
        Section:AddSlider({Name="Pulse Size",Flag="World_EchoPlusPulse",Min=1,Max=12,Default=State.PulseSize,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.PulseSize=v end})
        Section:AddSlider({Name="Max Distance",Flag="World_EchoPlusDistance",Min=50,Max=2500,Default=State.MaxDistance,Decimals=0,Suffix=" studs",RequiredGraphics="Low",FPSImpact={-5,2},Callback=function(v) State.MaxDistance=v end})
        Section:AddSlider({Name="Active Echo Limit",Flag="World_EchoPlusLimit",Min=10,Max=250,Default=State.ActiveLimit,Decimals=0,RequiredGraphics="Low",FPSImpact={-8,2},Callback=function(v) State.ActiveLimit=math.floor(v); capActive() end})

        Scope:AddCleaner(function()
            R.Running=false
            for i=#R.Active,1,-1 do removeActive(R.Active[i]) end
        end)
        Context.Shared.WorldEchoPlus={Clear=function() for i=#R.Active,1,-1 do removeActive(R.Active[i]) end end}
    end,
}
