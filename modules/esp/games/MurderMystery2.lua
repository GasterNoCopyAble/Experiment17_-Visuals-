--[[
    Experiment17 - Murder Mystery 2 standalone ESP
    PlaceId: 142823291

    This is intentionally standalone. When this game profile is routed,
    Universal.lua is NOT loaded, so universal ESP cannot overwrite the
    game-specific role renderer.
]]

return {
    Id = "ESP",
    Name = "Murder Mystery 2 ESP",
    Version = "2.0.0",
    Order = 30,

    Init = function(Context, Scope, Tab)
        local Players = Context.Services.Players or game:GetService("Players")
        local RunService = Context.Services.RunService or game:GetService("RunService")
        local Workspace = Context.Services.Workspace or workspace
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local LocalPlayer = Context.LocalPlayer or Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

        local State = Context:GetState("ESP_MM2", {
            Enabled = true, Boxes = true, Distance = true, RoleHighlight = true, RoleTags = true,
            ShowSelf = false, HideDead = true, MaxDistance = 2500, Thickness = 1.5, UpdateRate = 30, RoleRefreshRate = 4,
            FillTransparency = 0.70, OutlineTransparency = 0.05,
            MurdererColor = Color3.fromRGB(235,55,55), SheriffColor = Color3.fromRGB(70,135,255),
            HeroColor = Color3.fromRGB(255,225,55), InnocentColor = Color3.fromRGB(75,225,95), UnknownColor = Color3.fromRGB(180,180,190),
        })

        local R = {Running=true,Camera=Workspace.CurrentCamera,Roles={},SheriffName=nil,Remote=nil,Busy=false,Bundles={},Cache=setmetatable({}, {__mode="k"}),Accumulator=0}
        local BODY = {Head=true,Torso=true,UpperTorso=true,LowerTorso=true,["Left Arm"]=true,["Right Arm"]=true,["Left Leg"]=true,["Right Leg"]=true,LeftUpperArm=true,LeftLowerArm=true,LeftHand=true,RightUpperArm=true,RightLowerArm=true,RightHand=true,LeftUpperLeg=true,LeftLowerLeg=true,LeftFoot=true,RightUpperLeg=true,RightLowerLeg=true,RightFoot=true}

        R.Root=Scope:TrackInstance(Instance.new("Folder")); R.Root.Name="Experiment17_MM2ESP_Runtime"; R.Root.Parent=Workspace
        R.Gui=Scope:TrackInstance(Instance.new("ScreenGui")); R.Gui.Name="Experiment17_MM2ESP_Overlay"; R.Gui.ResetOnSpawn=false; R.Gui.IgnoreGuiInset=true; R.Gui.DisplayOrder=999990; R.Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; R.Gui.Parent=PlayerGui
        R.Overlay=Instance.new("Frame"); R.Overlay.Name="Overlay"; R.Overlay.BackgroundTransparency=1; R.Overlay.Size=UDim2.fromScale(1,1); R.Overlay.Parent=R.Gui

        local function newLine(name,z) local f=Instance.new("Frame"); f.Name=name; f.AnchorPoint=Vector2.new(0.5,0.5); f.BorderSizePixel=0; f.Visible=false; f.ZIndex=z or 50; f.Parent=R.Overlay; return f end
        local function newText(name,z) local t=Instance.new("TextLabel"); t.Name=name; t.BackgroundTransparency=1; t.AnchorPoint=Vector2.new(0.5,0.5); t.Font=Enum.Font.Code; t.TextSize=13; t.TextStrokeColor3=Color3.new(0,0,0); t.TextStrokeTransparency=0.25; t.Visible=false; t.ZIndex=z or 55; t.Parent=R.Overlay; return t end
        local function drawLine(frame,a,b,color,thickness,transparency) local d=b-a; local len=d.Magnitude; if len<0.5 then frame.Visible=false return end; frame.Position=UDim2.fromOffset((a.X+b.X)*0.5,(a.Y+b.Y)*0.5); frame.Size=UDim2.fromOffset(len,thickness or 1); frame.Rotation=math.deg(math.atan2(d.Y,d.X)); frame.BackgroundColor3=color; frame.BackgroundTransparency=transparency or 0; frame.Visible=true end
        local function screenPoint(world) R.Camera=Workspace.CurrentCamera or R.Camera; if not R.Camera then return Vector2.zero,false,-1 end; local p,on=R.Camera:WorldToViewportPoint(world); return Vector2.new(p.X,p.Y),on,p.Z end

        local function findRoleRemote() if R.Remote and R.Remote.Parent and R.Remote:IsA("RemoteFunction") then return R.Remote end; local remote=ReplicatedStorage:FindFirstChild("GetPlayerData",true); if remote and remote:IsA("RemoteFunction") then R.Remote=remote; return remote end; R.Remote=nil; return nil end
        local function isAlive(player) if not player then return false end; local info=R.Roles[player.Name]; if type(info)=="table" and (info.Killed or info.Dead) then return false end; local char=player.Character; local hum=char and char:FindFirstChildOfClass("Humanoid"); return not hum or hum.Health>0 end
        local function roleOf(player) local info=player and R.Roles[player.Name]; if type(info)~="table" then return "Unknown" end; local role=tostring(info.Role or ""); if role=="Murderer" or role=="Sheriff" or role=="Innocent" then return role end; if role=="Hero" then local sheriff=R.SheriffName and Players:FindFirstChild(R.SheriffName); return (not sheriff or not isAlive(sheriff)) and "Hero" or "Innocent" end; return role~="" and role or "Unknown" end
        local function roleColor(role) if role=="Murderer" then return State.MurdererColor end; if role=="Sheriff" then return State.SheriffColor end; if role=="Hero" then return State.HeroColor end; if role=="Innocent" then return State.InnocentColor end; return State.UnknownColor end
        local function rebuildRoles(data) R.Roles=type(data)=="table" and data or {}; R.SheriffName=nil; for name,info in pairs(R.Roles) do if type(info)=="table" and info.Role=="Sheriff" and not info.Killed and not info.Dead then R.SheriffName=name break end end end
        local function refreshRoles() if R.Busy or not R.Running then return end; R.Busy=true; local remote=findRoleRemote(); if remote then local ok,data=pcall(function() return remote:InvokeServer() end); if ok and type(data)=="table" then rebuildRoles(data) end end; R.Busy=false end

        local function bodyCache(player,char,root)
            local cached=R.Cache[player]; if cached and cached.Character==char and cached.Root==root then return cached end
            local minL=Vector3.new(math.huge,math.huge,math.huge); local maxL=Vector3.new(-math.huge,-math.huge,-math.huge); local count=0
            for _,part in ipairs(char:GetChildren()) do if part:IsA("BasePart") and BODY[part.Name] then count+=1; local h=part.Size*0.5; for _,x in ipairs({-h.X,h.X}) do for _,y in ipairs({-h.Y,h.Y}) do for _,z in ipairs({-h.Z,h.Z}) do local lp=root.CFrame:PointToObjectSpace((part.CFrame*CFrame.new(x,y,z)).Position); minL=Vector3.new(math.min(minL.X,lp.X),math.min(minL.Y,lp.Y),math.min(minL.Z,lp.Z)); maxL=Vector3.new(math.max(maxL.X,lp.X),math.max(maxL.Y,lp.Y),math.max(maxL.Z,lp.Z)) end end end end end
            if count==0 then return nil end; cached={Character=char,Root=root,Center=(minL+maxL)*0.5,Size=maxL-minL}; R.Cache[player]=cached; return cached
        end
        local function box2D(root,data)
            if not data then return nil end; local cf=root.CFrame*CFrame.new(data.Center); local h=data.Size*0.5; local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge; local valid=0
            for _,x in ipairs({-h.X,h.X}) do for _,y in ipairs({-h.Y,h.Y}) do for _,z in ipairs({-h.Z,h.Z}) do local p,_,depth=screenPoint((cf*CFrame.new(x,y,z)).Position); if depth>0 then minX=math.min(minX,p.X); minY=math.min(minY,p.Y); maxX=math.max(maxX,p.X); maxY=math.max(maxY,p.Y); valid+=1 end end end end
            if valid<4 then return nil end; return Vector2.new(minX,minY),Vector2.new(maxX,maxY)
        end

        local function createBundle(player)
            local b=R.Bundles[player]; if b then return b end; b={Lines={}}; for i=1,4 do b.Lines[i]=newLine("MM2_Box_"..i,50) end; b.Distance=newText("MM2_Distance",55)
            b.Highlight=Instance.new("Highlight"); b.Highlight.Name="E17_MM2_Role"; b.Highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; b.Highlight.Enabled=false; b.Highlight.Parent=R.Root
            b.Tag=Instance.new("BillboardGui"); b.Tag.Name="E17_MM2_RoleTag"; b.Tag.AlwaysOnTop=true; b.Tag.Size=UDim2.fromOffset(150,24); b.Tag.StudsOffset=Vector3.new(0,2.75,0); b.Tag.MaxDistance=State.MaxDistance; b.Tag.Enabled=false; b.Tag.Parent=PlayerGui
            b.TagText=Instance.new("TextLabel"); b.TagText.BackgroundTransparency=1; b.TagText.Size=UDim2.fromScale(1,1); b.TagText.Font=Enum.Font.Code; b.TagText.TextSize=13; b.TagText.TextStrokeTransparency=0.25; b.TagText.Parent=b.Tag; R.Bundles[player]=b; return b
        end
        local function hideBundle(b) if not b then return end; for _,line in ipairs(b.Lines) do line.Visible=false end; b.Distance.Visible=false; b.Highlight.Enabled=false; b.Tag.Enabled=false end
        local function destroyBundle(player) local b=R.Bundles[player]; if not b then return end; for _,line in ipairs(b.Lines) do pcall(function() line:Destroy() end) end; pcall(function() b.Distance:Destroy() end); pcall(function() b.Highlight:Destroy() end); pcall(function() b.Tag:Destroy() end); R.Bundles[player]=nil; R.Cache[player]=nil end

        local function renderPlayer(player)
            local b=createBundle(player); if not State.Enabled or (player==LocalPlayer and not State.ShowSelf) then hideBundle(b); return end
            local char=player.Character; local root=char and char:FindFirstChild("HumanoidRootPart"); if not char or not root or (State.HideDead and not isAlive(player)) then hideBundle(b); return end
            local myRoot=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); local distance=myRoot and (root.Position-myRoot.Position).Magnitude or (R.Camera and (root.Position-R.Camera.CFrame.Position).Magnitude or 0); if distance>State.MaxDistance then hideBundle(b); return end
            local role=roleOf(player); local color=roleColor(role)
            b.Highlight.Adornee=char; b.Highlight.FillColor=color; b.Highlight.OutlineColor=color; b.Highlight.FillTransparency=State.FillTransparency; b.Highlight.OutlineTransparency=State.OutlineTransparency; b.Highlight.Enabled=State.RoleHighlight
            local head=char:FindFirstChild("Head") or root; b.Tag.Adornee=head; b.Tag.MaxDistance=State.MaxDistance; b.TagText.Text=string.upper(role); b.TagText.TextColor3=color; b.Tag.Enabled=State.RoleTags
            local min,max=box2D(root,bodyCache(player,char,root)); if not min or not max then for _,line in ipairs(b.Lines) do line.Visible=false end; b.Distance.Visible=false; return end
            local tl=Vector2.new(min.X,min.Y); local tr=Vector2.new(max.X,min.Y); local bl=Vector2.new(min.X,max.Y); local br=Vector2.new(max.X,max.Y)
            if State.Boxes then drawLine(b.Lines[1],tl,tr,color,State.Thickness); drawLine(b.Lines[2],tr,br,color,State.Thickness); drawLine(b.Lines[3],br,bl,color,State.Thickness); drawLine(b.Lines[4],bl,tl,color,State.Thickness) else for _,line in ipairs(b.Lines) do line.Visible=false end end
            if State.Distance then b.Distance.Position=UDim2.fromOffset((min.X+max.X)*0.5,max.Y+12); b.Distance.Text=string.format("%.0f studs",distance); b.Distance.TextColor3=color; b.Distance.Visible=true else b.Distance.Visible=false end
        end

        Scope:TrackConnection(RunService.RenderStepped:Connect(function(dt) if not R.Running then return end; R.Accumulator+=dt; local interval=1/math.max(1,State.UpdateRate); if R.Accumulator<interval then return end; R.Accumulator=0; for _,p in ipairs(Players:GetPlayers()) do renderPlayer(p) end end))
        Scope:TrackConnection(Players.PlayerRemoving:Connect(destroyBundle))
        Scope:TrackConnection(Players.PlayerAdded:Connect(function(p) Scope:TrackConnection(p.CharacterAdded:Connect(function() R.Cache[p]=nil end)) end))
        for _,p in ipairs(Players:GetPlayers()) do Scope:TrackConnection(p.CharacterAdded:Connect(function() R.Cache[p]=nil end)) end
        task.spawn(function() while R.Running do if State.Enabled then refreshRoles() end; task.wait(1/math.max(1,State.RoleRefreshRate)) end end)

        local Main=Context:CreateSection(Scope,Tab,"MM2 Player ESP",true,"ESP / MM2")
        Main:AddToggle({Name="MM2 ESP",Flag="ESP_MM2_Enabled",Default=State.Enabled,RequiredGraphics="Low",Callback=function(v) State.Enabled=v if v then refreshRoles() else for _,b in pairs(R.Bundles) do hideBundle(b) end end end})
        Main:AddToggle({Name="2D Boxes",Flag="ESP_MM2_Boxes",Default=State.Boxes,RequiredGraphics="Low",FPSImpact={-2,0},Callback=function(v) State.Boxes=v end})
        Main:AddToggle({Name="Distance",Flag="ESP_MM2_Distance",Default=State.Distance,RequiredGraphics="Low",FPSImpact={-1,0},Callback=function(v) State.Distance=v end})
        Main:AddToggle({Name="Role Highlight",Flag="ESP_MM2_Highlight",Default=State.RoleHighlight,RequiredGraphics="Low",Callback=function(v) State.RoleHighlight=v end})
        Main:AddToggle({Name="Role Tags",Flag="ESP_MM2_RoleTags",Default=State.RoleTags,RequiredGraphics="Low",Callback=function(v) State.RoleTags=v end})
        Main:AddToggle({Name="Hide Dead Players",Flag="ESP_MM2_HideDead",Default=State.HideDead,RequiredGraphics="Low",Callback=function(v) State.HideDead=v end})
        Main:AddToggle({Name="Show Self",Flag="ESP_MM2_ShowSelf",Default=State.ShowSelf,RequiredGraphics="Low",Callback=function(v) State.ShowSelf=v end})
        Main:AddSlider({Name="Max Distance",Flag="ESP_MM2_MaxDistance",Min=100,Max=5000,Default=State.MaxDistance,Decimals=0,Suffix=" studs",RequiredGraphics="Low",Callback=function(v) State.MaxDistance=v end})
        Main:AddSlider({Name="Box Thickness",Flag="ESP_MM2_Thickness",Min=1,Max=5,Default=State.Thickness,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.Thickness=v end})
        Main:AddSlider({Name="Render Rate",Flag="ESP_MM2_UpdateRate",Min=5,Max=60,Default=State.UpdateRate,Decimals=0,Suffix=" Hz",RequiredGraphics="Low",FPSImpact={-5,2},Callback=function(v) State.UpdateRate=v end})
        Main:AddSlider({Name="Role Refresh Rate",Flag="ESP_MM2_RoleRate",Min=1,Max=10,Default=State.RoleRefreshRate,Decimals=0,Suffix=" Hz",RequiredGraphics="Low",PingImpact={-1,1},Callback=function(v) State.RoleRefreshRate=v end})

        local Colors=Context:CreateSection(Scope,Tab,"MM2 Role Colors",false,"ESP / MM2 Colors")
        Colors:AddSlider({Name="Highlight Fill Transparency",Flag="ESP_MM2_Fill",Min=0,Max=1,Default=State.FillTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.FillTransparency=v end})
        Colors:AddSlider({Name="Highlight Outline Transparency",Flag="ESP_MM2_Outline",Min=0,Max=1,Default=State.OutlineTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.OutlineTransparency=v end})
        Colors:AddColorPicker({Name="Murderer",Flag="ESP_MM2_MurdererColor",Default=State.MurdererColor,RequiredGraphics="Low",Callback=function(v) State.MurdererColor=v end})
        Colors:AddColorPicker({Name="Sheriff",Flag="ESP_MM2_SheriffColor",Default=State.SheriffColor,RequiredGraphics="Low",Callback=function(v) State.SheriffColor=v end})
        Colors:AddColorPicker({Name="Hero",Flag="ESP_MM2_HeroColor",Default=State.HeroColor,RequiredGraphics="Low",Callback=function(v) State.HeroColor=v end})
        Colors:AddColorPicker({Name="Innocent",Flag="ESP_MM2_InnocentColor",Default=State.InnocentColor,RequiredGraphics="Low",Callback=function(v) State.InnocentColor=v end})
        Colors:AddButton({Name="Refresh Roles Now",ButtonText="Refresh",RequiredGraphics="Low",Callback=refreshRoles})

        Scope:AddCleaner(function() R.Running=false; for p in pairs(R.Bundles) do destroyBundle(p) end end)
        task.defer(refreshRoles)
        Context.Shared.ESPProfile="MM2"
    end,
}
