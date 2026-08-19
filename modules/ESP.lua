--[[
    Experiment 17 - ESP module
    Target: Experiment17 modular Loader v0.2+

    Optimized player renderer:
      * Cached body-only bounds (no accessories/tools in player boxes)
      * Rate-limited updates + max rendered players + far LOD
      * 2D box/name/health/distance/tracer/skeleton
      * Chams + 3D body box
      * Rainbow ESP, depth-based fade, occlusion color mode
      * Player trails
      * Tool ESP (name/distance/owner/box/chams/tracer/rainbow)
      * Radar/minimap
      * Damage visualizer from replicated Humanoid health changes

    All visuals are local-only.
]]

return {
    Id = "ESP",
    Name = "ESP",
    Version = "2.0.0",
    Order = 30,

    Init = function(Context, Scope, Tab)
        local S = Context.Services
        local Players, RunService, Workspace = S.Players, S.RunService, S.Workspace
        local TweenService = S.TweenService
        local LocalPlayer = Context.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

        local State = Context:GetState("ESP", {
            Enabled = false,
            Boxes = true,
            Names = true,
            Health = true,
            Distance = true,
            Tracers = false,
            Skeleton = false,
            Chams = false,
            ESP3D = false,
            TeamCheck = false,
            MaxDistance = 1800,
            Thickness = 1.5,
            Color = Color3.fromRGB(186, 110, 255),
            TeamColor = Color3.fromRGB(80, 210, 120),
            Rainbow = false,
            RainbowSpeed = 0.25,
            UpdateRate = 30,
            MaxRenderedPlayers = 30,
            FarLOD = 900,
            ChamFillTransparency = 0.76,
            ChamOutlineTransparency = 0.12,

            DepthBased = false,
            DepthNear = 80,
            DepthFar = 1400,
            DepthMaxFade = 0.62,

            Occlusion = false,
            OcclusionRate = 0.12,
            OccludedColor = Color3.fromRGB(255, 80, 95),
            HideOccluded = false,

            PlayerTrails = false,
            PlayerTrailMode = "Per Player",
            PlayerTrailColorA = Color3.fromRGB(100, 180, 255),
            PlayerTrailColorB = Color3.fromRGB(255, 90, 200),
            PlayerTrailLifetime = 0.45,
            PlayerTrailWidth = 0.7,

            ToolESP = false,
            ToolMode = "Both",
            ToolNames = true,
            ToolDistance = true,
            ToolOwner = true,
            ToolBoxes = true,
            ToolChams = false,
            ToolTracers = false,
            ToolRainbow = false,
            ToolColor = Color3.fromRGB(255, 190, 70),
            ToolMaxDistance = 2500,
            ToolRefreshRate = 0.40,
            ToolSurfaceTransparency = 0.80,
            ToolLineTransparency = 0.12,

            Radar = false,
            RadarShape = "Circle",
            RadarSize = 190,
            RadarRange = 900,
            RadarRotate = true,
            RadarNames = false,
            RadarTools = false,
            RadarOpacity = 0.25,

            DamageVisualizer = false,
            DamageLocalPlayer = true,
            DamageColor = Color3.fromRGB(255, 90, 90),
            DamageRainbow = false,
            DamageLifetime = 0.85,
            DamageScale = 1.0,
        })

        local R = {
            Camera = Workspace.CurrentCamera,
            Accumulator = 0,
            ToolAccumulator = 0,
            OcclusionAccumulator = 0,
            Bundles = {},
            CharacterCache = setmetatable({}, {__mode = "k"}),
            OcclusionCache = setmetatable({}, {__mode = "k"}),
            KnownTools = setmetatable({}, {__mode = "k"}),
            ToolBundles = setmetatable({}, {__mode = "k"}),
            DamageHealth = setmetatable({}, {__mode = "k"}),
            DamageWatched = setmetatable({}, {__mode = "k"}),
            RadarDots = setmetatable({}, {__mode = "k"}),
            RadarToolDots = setmetatable({}, {__mode = "k"}),
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
        R.Root.Name = "Experiment17_ESP_Runtime"
        R.Root.Parent = Workspace

        R.Gui = Scope:TrackInstance(Instance.new("ScreenGui"))
        R.Gui.Name = "Experiment17_ESP_Overlay"
        R.Gui.ResetOnSpawn = false
        R.Gui.IgnoreGuiInset = true
        R.Gui.DisplayOrder = 999990
        R.Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        R.Gui.Parent = PlayerGui

        R.Overlay = Instance.new("Frame")
        R.Overlay.Name = "Overlay"
        R.Overlay.BackgroundTransparency = 1
        R.Overlay.Size = UDim2.fromScale(1, 1)
        R.Overlay.Parent = R.Gui

        R.RadarFrame = Instance.new("Frame")
        R.RadarFrame.Name = "Radar"
        R.RadarFrame.AnchorPoint = Vector2.new(1, 0)
        R.RadarFrame.Position = UDim2.new(1, -20, 0, 80)
        R.RadarFrame.Size = UDim2.fromOffset(State.RadarSize, State.RadarSize)
        R.RadarFrame.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
        R.RadarFrame.BackgroundTransparency = State.RadarOpacity
        R.RadarFrame.BorderSizePixel = 0
        R.RadarFrame.Visible = false
        R.RadarFrame.ClipsDescendants = true
        R.RadarFrame.Parent = R.Gui

        R.RadarCorner = Instance.new("UICorner")
        R.RadarCorner.CornerRadius = UDim.new(1, 0)
        R.RadarCorner.Parent = R.RadarFrame

        R.RadarStroke = Instance.new("UIStroke")
        R.RadarStroke.Thickness = 1
        R.RadarStroke.Transparency = 0.35
        R.RadarStroke.Color = Color3.fromRGB(180, 180, 210)
        R.RadarStroke.Parent = R.RadarFrame

        R.RadarH = Instance.new("Frame")
        R.RadarH.AnchorPoint = Vector2.new(0.5, 0.5)
        R.RadarH.Position = UDim2.fromScale(0.5, 0.5)
        R.RadarH.Size = UDim2.new(1, 0, 0, 1)
        R.RadarH.BackgroundTransparency = 0.65
        R.RadarH.BackgroundColor3 = Color3.fromRGB(150, 150, 175)
        R.RadarH.BorderSizePixel = 0
        R.RadarH.Parent = R.RadarFrame

        R.RadarV = R.RadarH:Clone()
        R.RadarV.Size = UDim2.new(0, 1, 1, 0)
        R.RadarV.Parent = R.RadarFrame

        R.RadarCenter = Instance.new("Frame")
        R.RadarCenter.AnchorPoint = Vector2.new(0.5, 0.5)
        R.RadarCenter.Position = UDim2.fromScale(0.5, 0.5)
        R.RadarCenter.Size = UDim2.fromOffset(7, 7)
        R.RadarCenter.BackgroundColor3 = Color3.fromRGB(245, 245, 255)
        R.RadarCenter.BorderSizePixel = 0
        R.RadarCenter.Rotation = 45
        R.RadarCenter.Parent = R.RadarFrame

        R.rainbow = function(speed, offset)
            return Color3.fromHSV(((os.clock() * (speed or 0.25)) + (offset or 0)) % 1, 0.9, 1)
        end

        R.safeDestroy = function(object)
            if object then pcall(function() object:Destroy() end) end
        end

        R.newLine = function(name, z)
            local f = Instance.new("Frame")
            f.Name = name
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.BorderSizePixel = 0
            f.BackgroundColor3 = State.Color
            f.BackgroundTransparency = 0
            f.Visible = false
            f.ZIndex = z or 20
            f.Parent = R.Overlay
            return f
        end

        R.newText = function(name, z)
            local t = Instance.new("TextLabel")
            t.Name = name
            t.BackgroundTransparency = 1
            t.AnchorPoint = Vector2.new(0.5, 0.5)
            t.Font = Enum.Font.Code
            t.TextSize = 13
            t.TextColor3 = State.Color
            t.TextStrokeColor3 = Color3.new(0,0,0)
            t.TextStrokeTransparency = 0.35
            t.Visible = false
            t.ZIndex = z or 25
            t.Parent = R.Overlay
            return t
        end

        R.drawLine = function(frame, a, b, color, thickness, transparency)
            local d = b - a
            local len = d.Magnitude
            if len < 0.5 then frame.Visible = false return end
            frame.Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5)
            frame.Size = UDim2.fromOffset(len, thickness or 1)
            frame.Rotation = math.deg(math.atan2(d.Y, d.X))
            frame.BackgroundColor3 = color
            frame.BackgroundTransparency = transparency or 0
            frame.Visible = true
        end

        R.screenPoint = function(world)
            R.Camera = Workspace.CurrentCamera or R.Camera
            local p, on = R.Camera:WorldToViewportPoint(world)
            return Vector2.new(p.X, p.Y), on, p.Z
        end

        R.getBodyParts = function(character)
            local out = {}
            if not character then return out end
            for _, object in ipairs(character:GetChildren()) do
                if object:IsA("BasePart") and R.BodyNames[object.Name] then
                    out[#out+1] = object
                end
            end
            return out
        end

        R.buildCharacterCache = function(player, character, root)
            local parts = R.getBodyParts(character)
            if #parts == 0 then return nil end
            local minL = Vector3.new(math.huge, math.huge, math.huge)
            local maxL = Vector3.new(-math.huge, -math.huge, -math.huge)
            for _, part in ipairs(parts) do
                local h = part.Size * 0.5
                for _, x in ipairs({-h.X, h.X}) do
                    for _, y in ipairs({-h.Y, h.Y}) do
                        for _, z in ipairs({-h.Z, h.Z}) do
                            local wp = (part.CFrame * CFrame.new(x,y,z)).Position
                            local lp = root.CFrame:PointToObjectSpace(wp)
                            minL = Vector3.new(math.min(minL.X,lp.X), math.min(minL.Y,lp.Y), math.min(minL.Z,lp.Z))
                            maxL = Vector3.new(math.max(maxL.X,lp.X), math.max(maxL.Y,lp.Y), math.max(maxL.Z,lp.Z))
                        end
                    end
                end
            end
            local skeleton = {}
            for _, joint in ipairs(character:GetDescendants()) do
                if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 and R.BodyNames[joint.Part0.Name] and R.BodyNames[joint.Part1.Name] then
                    skeleton[#skeleton+1] = {joint.Part0, joint.Part1}
                end
            end
            local data = {Character=character, Root=root, CenterLocal=(minL+maxL)*0.5, Size=maxL-minL, Skeleton=skeleton}
            R.CharacterCache[player] = data
            return data
        end

        R.getCharacterCache = function(player, character, root)
            local data = R.CharacterCache[player]
            if not data or data.Character ~= character or data.Root ~= root or not root.Parent then
                data = R.buildCharacterCache(player, character, root)
            end
            return data
        end

        R.bodyBox2D = function(root, data)
            if not data then return nil end
            local cf = root.CFrame * CFrame.new(data.CenterLocal)
            local h = data.Size * 0.5
            local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
            local valid = 0
            for _, x in ipairs({-h.X, h.X}) do
                for _, y in ipairs({-h.Y, h.Y}) do
                    for _, z in ipairs({-h.Z, h.Z}) do
                        local p, _, depth = R.screenPoint((cf * CFrame.new(x,y,z)).Position)
                        if depth > 0 then
                            minX, minY = math.min(minX,p.X), math.min(minY,p.Y)
                            maxX, maxY = math.max(maxX,p.X), math.max(maxY,p.Y)
                            valid += 1
                        end
                    end
                end
            end
            if valid < 4 then return nil end
            return Vector2.new(minX,minY), Vector2.new(maxX,maxY), cf, data.Size
        end

        R.sameTeam = function(player)
            return LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
        end

        R.baseColor = function(player, sameTeam)
            if State.Rainbow then
                return R.rainbow(State.RainbowSpeed, (player.UserId % 101) / 101)
            end
            return sameTeam and State.TeamColor or State.Color
        end

        R.depthFade = function(distance)
            if not State.DepthBased then return 0 end
            local a = State.DepthNear
            local b = math.max(a + 1, State.DepthFar)
            return math.clamp((distance - a) / (b - a), 0, 1) * State.DepthMaxFade
        end

        R.isVisible = function(player, character, targetPart)
            if not State.Occlusion or not targetPart or not R.Camera then return true end
            local cached = R.OcclusionCache[player]
            if cached ~= nil then return cached end
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {LocalPlayer.Character, R.Root}
            params.IgnoreWater = true
            local origin = R.Camera.CFrame.Position
            local result = Workspace:Raycast(origin, targetPart.Position - origin, params)
            local visible = result == nil or (result.Instance and result.Instance:IsDescendantOf(character))
            R.OcclusionCache[player] = visible
            return visible
        end

        R.createBundle = function(player)
            local old = R.Bundles[player]
            if old then return old end
            local b = {Lines={}, SkeletonLines={}, Trails={}, TrailAttachments={}}
            for i=1,4 do b.Lines[i] = R.newLine("ESP_Box_"..i, 50) end
            b.Tracer = R.newLine("ESP_Tracer", 42)
            b.Name = R.newText("ESP_Name", 55)
            b.Distance = R.newText("ESP_Distance", 55)
            b.HealthBack = R.newLine("ESP_HealthBack", 51)
            b.HealthBack.BackgroundColor3 = Color3.fromRGB(20,20,24)
            b.HealthFill = R.newLine("ESP_HealthFill", 52)
            for i=1,24 do b.SkeletonLines[i] = R.newLine("ESP_Skeleton_"..i, 47) end

            b.Highlight = Instance.new("Highlight")
            b.Highlight.Name = "Experiment17_PlayerChams"
            b.Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            b.Highlight.Enabled = false
            b.Highlight.Parent = R.Root

            b.Box3D = Instance.new("BoxHandleAdornment")
            b.Box3D.Name = "Experiment17_Player3DBox"
            b.Box3D.AlwaysOnTop = true
            b.Box3D.ZIndex = 4
            b.Box3D.Visible = false
            b.Box3D.Transparency = 0.88
            b.Box3D.Parent = R.Root

            R.Bundles[player] = b
            return b
        end

        R.destroyTrails = function(bundle)
            for _, x in ipairs(bundle.Trails or {}) do R.safeDestroy(x) end
            for _, x in ipairs(bundle.TrailAttachments or {}) do R.safeDestroy(x) end
            bundle.Trails, bundle.TrailAttachments, bundle.TrailRoot = {}, {}, nil
        end

        R.trailColors = function(player, sameTeam)
            if State.PlayerTrailMode == "Rainbow" then
                return R.rainbow(State.RainbowSpeed, player.UserId%97/97), R.rainbow(State.RainbowSpeed, player.UserId%97/97 + 0.16)
            elseif State.PlayerTrailMode == "Per Player" then
                local h = (player.UserId * 0.61803398875) % 1
                return Color3.fromHSV(h,0.82,1), Color3.fromHSV((h+0.13)%1,0.82,1)
            elseif State.PlayerTrailMode == "Team" then
                local c = sameTeam and State.TeamColor or State.Color
                return c,c
            end
            return State.PlayerTrailColorA, State.PlayerTrailColorB
        end

        R.ensureTrails = function(bundle, root, player, sameTeam)
            if not State.PlayerTrails then R.destroyTrails(bundle) return end
            if bundle.TrailRoot ~= root or #bundle.Trails == 0 then
                R.destroyTrails(bundle)
                bundle.TrailRoot = root
                local w = State.PlayerTrailWidth
                local positions = {
                    {Vector3.new(-w,0,0), Vector3.new(w,0,0)},
                    {Vector3.new(0,-w,0), Vector3.new(0,w,0)},
                }
                for i,pair in ipairs(positions) do
                    local a0 = Instance.new("Attachment"); a0.Name="E17_ESPTrailA"..i; a0.Position=pair[1]; a0.Parent=root
                    local a1 = Instance.new("Attachment"); a1.Name="E17_ESPTrailB"..i; a1.Position=pair[2]; a1.Parent=root
                    local tr = Instance.new("Trail")
                    tr.Name = "E17_ESPTrail"..i
                    tr.Attachment0, tr.Attachment1 = a0, a1
                    tr.FaceCamera = false
                    tr.MinLength = 0.05
                    tr.LightEmission = 0.25
                    tr.Parent = root
                    bundle.TrailAttachments[#bundle.TrailAttachments+1]=a0
                    bundle.TrailAttachments[#bundle.TrailAttachments+1]=a1
                    bundle.Trails[#bundle.Trails+1]=tr
                end
            end
            local c1,c2 = R.trailColors(player,sameTeam)
            for _,tr in ipairs(bundle.Trails) do
                tr.Lifetime = State.PlayerTrailLifetime
                tr.Color = ColorSequence.new(c1,c2)
                tr.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.08),NumberSequenceKeypoint.new(0.6,0.36),NumberSequenceKeypoint.new(1,1)})
            end
        end

        R.hideBundle = function(b)
            if not b then return end
            for _,x in ipairs(b.Lines) do x.Visible=false end
            for _,x in ipairs(b.SkeletonLines) do x.Visible=false end
            b.Tracer.Visible=false; b.Name.Visible=false; b.Distance.Visible=false
            b.HealthBack.Visible=false; b.HealthFill.Visible=false
            b.Highlight.Enabled=false; b.Box3D.Visible=false
            if not State.PlayerTrails then R.destroyTrails(b) end
        end

        R.destroyBundle = function(player)
            local b = R.Bundles[player]
            if not b then return end
            R.destroyTrails(b)
            for _,x in ipairs(b.Lines) do R.safeDestroy(x) end
            for _,x in ipairs(b.SkeletonLines) do R.safeDestroy(x) end
            R.safeDestroy(b.Tracer); R.safeDestroy(b.Name); R.safeDestroy(b.Distance)
            R.safeDestroy(b.HealthBack); R.safeDestroy(b.HealthFill); R.safeDestroy(b.Highlight); R.safeDestroy(b.Box3D)
            R.Bundles[player]=nil; R.CharacterCache[player]=nil; R.OcclusionCache[player]=nil
        end

        R.applyBox = function(b, minP, maxP, color, thickness, fade)
            local tl, tr = minP, Vector2.new(maxP.X,minP.Y)
            local br, bl = maxP, Vector2.new(minP.X,maxP.Y)
            R.drawLine(b.Lines[1],tl,tr,color,thickness,fade)
            R.drawLine(b.Lines[2],tr,br,color,thickness,fade)
            R.drawLine(b.Lines[3],br,bl,color,thickness,fade)
            R.drawLine(b.Lines[4],bl,tl,color,thickness,fade)
        end

        R.refreshOcclusion = function()
            table.clear(R.OcclusionCache)
        end

        R.updatePlayers = function()
            R.Camera = Workspace.CurrentCamera or R.Camera
            if not R.Camera then return end
            if not State.Enabled and not State.PlayerTrails and not State.Radar then
                for _,b in pairs(R.Bundles) do R.hideBundle(b) end
                return
            end
            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local candidates = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local char = player.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if root and hum and hum.Health > 0 then
                        local same = R.sameTeam(player)
                        if not (State.TeamCheck and same) then
                            local dist = localRoot and (root.Position-localRoot.Position).Magnitude or (root.Position-R.Camera.CFrame.Position).Magnitude
                            if dist <= State.MaxDistance or State.Radar then
                                candidates[#candidates+1] = {Player=player,Character=char,Root=root,Humanoid=hum,Distance=dist,SameTeam=same}
                            end
                        end
                    end
                end
            end
            table.sort(candidates,function(a,b) return a.Distance < b.Distance end)
            local seen = {}
            local maxPlayers = math.max(1, math.floor(State.MaxRenderedPlayers))
            for index,item in ipairs(candidates) do
                if index <= maxPlayers then
                    local player, char, root, hum = item.Player,item.Character,item.Root,item.Humanoid
                    local b = R.createBundle(player)
                    seen[player]=true
                    local cache = R.getCharacterCache(player,char,root)
                    local minP,maxP,boxCF,boxSize = R.bodyBox2D(root,cache)
                    local visible = R.isVisible(player,char,char:FindFirstChild("Head") or root)
                    local color = visible and R.baseColor(player,item.SameTeam) or State.OccludedColor
                    local fade = R.depthFade(item.Distance)
                    if State.Occlusion and State.HideOccluded and not visible then fade = 1 end
                    local alpha = math.clamp(fade,0,0.98)
                    local thickness = State.Thickness

                    R.ensureTrails(b,root,player,item.SameTeam)

                    if State.Enabled and minP and maxP and alpha < 0.98 then
                        if State.Boxes then R.applyBox(b,minP,maxP,color,thickness,alpha) else for _,x in ipairs(b.Lines) do x.Visible=false end end
                        local centerX = (minP.X+maxP.X)*0.5
                        b.Name.Visible = State.Names
                        if State.Names then
                            b.Name.Position = UDim2.fromOffset(centerX,minP.Y-11)
                            b.Name.Size = UDim2.fromOffset(math.max(120,maxP.X-minP.X+60),18)
                            b.Name.Text = player.DisplayName == player.Name and player.Name or (player.DisplayName.." ["..player.Name.."]")
                            b.Name.TextColor3=color; b.Name.TextTransparency=alpha
                        end
                        b.Distance.Visible = State.Distance
                        if State.Distance then
                            b.Distance.Position=UDim2.fromOffset(centerX,maxP.Y+11)
                            b.Distance.Size=UDim2.fromOffset(120,18)
                            b.Distance.Text=string.format("%.0f studs",item.Distance)
                            b.Distance.TextColor3=color; b.Distance.TextTransparency=alpha
                        end
                        b.HealthBack.Visible=State.Health; b.HealthFill.Visible=State.Health
                        if State.Health then
                            local h = math.max(4,maxP.Y-minP.Y)
                            local ratio = math.clamp(hum.Health/math.max(1,hum.MaxHealth),0,1)
                            b.HealthBack.AnchorPoint=Vector2.new(0.5,0.5)
                            b.HealthBack.Position=UDim2.fromOffset(minP.X-6,(minP.Y+maxP.Y)*0.5)
                            b.HealthBack.Size=UDim2.fromOffset(3,h)
                            b.HealthBack.Rotation=0; b.HealthBack.BackgroundTransparency=math.clamp(0.15+alpha,0,1)
                            b.HealthFill.AnchorPoint=Vector2.new(0.5,1)
                            b.HealthFill.Position=UDim2.fromOffset(minP.X-6,maxP.Y)
                            b.HealthFill.Size=UDim2.fromOffset(3,h*ratio)
                            b.HealthFill.Rotation=0
                            b.HealthFill.BackgroundColor3=Color3.fromRGB(math.floor(255*(1-ratio)),math.floor(235*ratio),70)
                            b.HealthFill.BackgroundTransparency=alpha
                        end
                    else
                        for _,x in ipairs(b.Lines) do x.Visible=false end
                        b.Name.Visible=false; b.Distance.Visible=false; b.HealthBack.Visible=false; b.HealthFill.Visible=false
                    end

                    if State.Enabled and State.Tracers and minP and maxP and alpha < 0.98 then
                        local viewport = R.Camera.ViewportSize
                        R.drawLine(b.Tracer,Vector2.new(viewport.X*0.5,viewport.Y-2),Vector2.new((minP.X+maxP.X)*0.5,maxP.Y),color,thickness,alpha)
                    else b.Tracer.Visible=false end

                    for _,line in ipairs(b.SkeletonLines) do line.Visible=false end
                    if State.Enabled and State.Skeleton and item.Distance <= State.FarLOD and cache and alpha < 0.98 then
                        for i,pair in ipairs(cache.Skeleton) do
                            local line=b.SkeletonLines[i]
                            if not line then break end
                            local a,_,za=R.screenPoint(pair[1].Position)
                            local c,_,zb=R.screenPoint(pair[2].Position)
                            if za>0 and zb>0 then R.drawLine(line,a,c,color,math.max(1,thickness-0.2),alpha) end
                        end
                    end

                    b.Highlight.Adornee=char
                    b.Highlight.FillColor=color; b.Highlight.OutlineColor=color
                    b.Highlight.FillTransparency=math.clamp(State.ChamFillTransparency+alpha*0.25,0,1)
                    b.Highlight.OutlineTransparency=math.clamp(State.ChamOutlineTransparency+alpha*0.35,0,1)
                    b.Highlight.Enabled=State.Enabled and State.Chams and alpha<0.98

                    if State.Enabled and State.ESP3D and cache and alpha < 0.98 then
                        b.Box3D.Adornee=root
                        b.Box3D.CFrame=CFrame.new(cache.CenterLocal)
                        b.Box3D.Size=cache.Size
                        b.Box3D.Color3=color
                        b.Box3D.Transparency=math.clamp(0.80+alpha*0.18,0,0.98)
                        b.Box3D.Visible=true
                    else b.Box3D.Visible=false end
                end
            end
            for player,b in pairs(R.Bundles) do
                if not seen[player] or not player.Parent then R.hideBundle(b) end
            end
            R.updateRadar(candidates)
        end

        R.radarDot = function(player)
            local d = R.RadarDots[player]
            if d and d.Parent then return d end
            d = Instance.new("TextLabel")
            d.Name="PlayerDot"; d.AnchorPoint=Vector2.new(0.5,0.5); d.BackgroundTransparency=1
            d.Size=UDim2.fromOffset(38,16); d.Font=Enum.Font.Code; d.TextSize=12; d.TextStrokeTransparency=0.35
            d.Text="●"; d.ZIndex=5; d.Parent=R.RadarFrame
            R.RadarDots[player]=d
            return d
        end

        R.radarToolDot = function(tool)
            local d=R.RadarToolDots[tool]
            if d and d.Parent then return d end
            d=Instance.new("TextLabel"); d.Name="ToolDot"; d.AnchorPoint=Vector2.new(0.5,0.5); d.BackgroundTransparency=1
            d.Size=UDim2.fromOffset(12,12); d.Font=Enum.Font.Code; d.TextSize=10; d.Text="◆"; d.ZIndex=4; d.Parent=R.RadarFrame
            R.RadarToolDots[tool]=d
            return d
        end

        R.radarCoordinates = function(worldPosition, localRoot)
            local rel=worldPosition-localRoot.Position
            local x,z
            if State.RadarRotate and R.Camera then
                local look=Vector3.new(R.Camera.CFrame.LookVector.X,0,R.Camera.CFrame.LookVector.Z)
                if look.Magnitude<0.001 then look=Vector3.new(0,0,-1) else look=look.Unit end
                local right=Vector3.new(-look.Z,0,look.X)
                x=rel:Dot(right); z=rel:Dot(look)
            else x=rel.X; z=-rel.Z end
            local scale=(State.RadarSize*0.44)/math.max(1,State.RadarRange)
            local px,pz=x*scale,-z*scale
            local radius=State.RadarSize*0.43
            local mag=Vector2.new(px,pz).Magnitude
            if mag>radius then local k=radius/mag; px,pz=px*k,pz*k end
            return px,pz,rel.Magnitude<=State.RadarRange
        end

        R.updateRadar = function(candidates)
            R.RadarFrame.Visible=State.Radar
            if not State.Radar then
                for _,d in pairs(R.RadarDots) do d.Visible=false end
                for _,d in pairs(R.RadarToolDots) do d.Visible=false end
                return
            end
            R.RadarFrame.Size=UDim2.fromOffset(State.RadarSize,State.RadarSize)
            R.RadarFrame.BackgroundTransparency=State.RadarOpacity
            R.RadarCorner.CornerRadius=State.RadarShape=="Circle" and UDim.new(1,0) or UDim.new(0,8)
            local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local seen={}
            for _,item in ipairs(candidates) do
                local player=item.Player
                if item.Distance<=State.RadarRange then
                    local x,y=R.radarCoordinates(item.Root.Position,root)
                    local d=R.radarDot(player); seen[player]=true
                    d.Position=UDim2.fromOffset(State.RadarSize*0.5+x,State.RadarSize*0.5+y)
                    d.Text=State.RadarNames and ("● "..player.Name) or "●"
                    d.TextColor3=R.baseColor(player,item.SameTeam); d.Visible=true
                end
            end
            for p,d in pairs(R.RadarDots) do if not seen[p] then d.Visible=false end end
            local seenTools={}
            if State.RadarTools then
                for tool in pairs(R.KnownTools) do
                    local part=R.findToolPart(tool)
                    if part and part:IsDescendantOf(Workspace) then
                        local x,y,inRange=R.radarCoordinates(part.Position,root)
                        if inRange then
                            local d=R.radarToolDot(tool); seenTools[tool]=true
                            d.Position=UDim2.fromOffset(State.RadarSize*0.5+x,State.RadarSize*0.5+y)
                            d.TextColor3=State.ToolRainbow and R.rainbow(State.RainbowSpeed,(#tool.Name%31)/31) or State.ToolColor
                            d.Visible=true
                        end
                    end
                end
            end
            for t,d in pairs(R.RadarToolDots) do if not seenTools[t] then d.Visible=false end end
        end

        R.findToolPart = function(tool)
            if not tool or not tool.Parent then return nil end
            return tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart",true)
        end

        R.toolOwner = function(tool)
            local model=tool and tool.Parent
            if model and model:IsA("Model") then return Players:GetPlayerFromCharacter(model) end
            return nil
        end

        R.toolAllowed = function(tool)
            local owner=R.toolOwner(tool)
            if State.ToolMode=="Dropped" then return owner==nil end
            if State.ToolMode=="Equipped" then return owner~=nil end
            return true
        end

        R.createToolBundle = function(tool,part)
            local b=R.ToolBundles[tool]
            if b then return b end
            b={}
            b.Box=Instance.new("SelectionBox"); b.Box.Name="E17_ToolBox"; b.Box.Adornee=part; b.Box.Parent=R.Root
            b.Highlight=Instance.new("Highlight"); b.Highlight.Name="E17_ToolChams"; b.Highlight.Adornee=tool; b.Highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; b.Highlight.Parent=R.Root
            b.Tracer=R.newLine("ToolTracer",41)
            b.Gui=Instance.new("BillboardGui"); b.Gui.Name="E17_ToolLabel"; b.Gui.AlwaysOnTop=true; b.Gui.LightInfluence=0; b.Gui.Size=UDim2.fromOffset(220,30); b.Gui.StudsOffsetWorldSpace=Vector3.new(0,1.5,0); b.Gui.Adornee=part; b.Gui.Parent=PlayerGui
            b.Label=Instance.new("TextLabel"); b.Label.BackgroundTransparency=1; b.Label.Size=UDim2.fromScale(1,1); b.Label.Font=Enum.Font.Code; b.Label.TextSize=13; b.Label.TextStrokeTransparency=0.35; b.Label.Parent=b.Gui
            R.ToolBundles[tool]=b
            return b
        end

        R.destroyToolBundle = function(tool)
            local b=R.ToolBundles[tool]
            if not b then return end
            for _,x in pairs(b) do R.safeDestroy(x) end
            R.ToolBundles[tool]=nil
        end

        R.toolColor = function(tool)
            if State.ToolRainbow then return R.rainbow(State.RainbowSpeed,(#tool.Name%47)/47) end
            return State.ToolColor
        end

        R.refreshTools = function()
            if not State.ToolESP and not (State.Radar and State.RadarTools) then
                for tool in pairs(R.ToolBundles) do R.destroyToolBundle(tool) end
                return
            end
            local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local seen={}
            for tool in pairs(R.KnownTools) do
                local part=R.findToolPart(tool)
                if State.ToolESP and part and part:IsDescendantOf(Workspace) and R.toolAllowed(tool) then
                    local dist=root and (part.Position-root.Position).Magnitude or 0
                    if not root or dist<=State.ToolMaxDistance then
                        local b=R.createToolBundle(tool,part); seen[tool]=true
                        local c=R.toolColor(tool)
                        b.Box.Adornee=part; b.Box.Color3=c; b.Box.SurfaceColor3=c; b.Box.SurfaceTransparency=State.ToolSurfaceTransparency; b.Box.Transparency=State.ToolLineTransparency; b.Box.LineThickness=0.025; b.Box.Visible=State.ToolBoxes
                        b.Highlight.Adornee=tool; b.Highlight.FillColor=c; b.Highlight.OutlineColor=c; b.Highlight.FillTransparency=0.80; b.Highlight.OutlineTransparency=0.12; b.Highlight.Enabled=State.ToolChams
                        b.Gui.Adornee=part; b.Gui.Enabled=State.ToolNames or State.ToolDistance or State.ToolOwner
                        local pieces={}
                        if State.ToolNames then pieces[#pieces+1]=tool.Name end
                        if State.ToolDistance then pieces[#pieces+1]=string.format("[%.0f]",dist) end
                        if State.ToolOwner then local o=R.toolOwner(tool); if o then pieces[#pieces+1]="@"..o.Name end end
                        b.Label.Text=table.concat(pieces," "); b.Label.TextColor3=c
                        if State.ToolTracers and R.Camera then
                            local p,on,z=R.screenPoint(part.Position)
                            if z>0 then local vp=R.Camera.ViewportSize; R.drawLine(b.Tracer,Vector2.new(vp.X*0.5,vp.Y-2),p,c,1.2,0.05) else b.Tracer.Visible=false end
                        else b.Tracer.Visible=false end
                    end
                end
            end
            for tool in pairs(R.ToolBundles) do if not seen[tool] then R.destroyToolBundle(tool) end end
        end

        R.spawnDamage = function(player, character, amount)
            if not State.DamageVisualizer then return end
            if player==LocalPlayer and not State.DamageLocalPlayer then return end
            local adornee=character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
            if not adornee then return end
            local gui=Instance.new("BillboardGui")
            gui.Name="E17_Damage"; gui.AlwaysOnTop=true; gui.LightInfluence=0; gui.Size=UDim2.fromOffset(150,50); gui.StudsOffsetWorldSpace=Vector3.new(math.random(-12,12)/20,2.6,0); gui.Adornee=adornee; gui.Parent=PlayerGui
            local t=Instance.new("TextLabel"); t.BackgroundTransparency=1; t.Size=UDim2.fromScale(1,1); t.Font=Enum.Font.GothamBold; t.TextScaled=true; t.TextStrokeTransparency=0.2; t.Text=string.format("-%.0f",amount); t.Parent=gui
            t.TextColor3=State.DamageRainbow and R.rainbow(State.RainbowSpeed,math.random()) or State.DamageColor
            t.Size=UDim2.fromScale(math.clamp(State.DamageScale,0.5,2),math.clamp(State.DamageScale,0.5,2))
            local info=TweenInfo.new(State.DamageLifetime,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
            pcall(function() TweenService:Create(gui,info,{StudsOffsetWorldSpace=gui.StudsOffsetWorldSpace+Vector3.new(0,2.2,0)}):Play() end)
            pcall(function() TweenService:Create(t,info,{TextTransparency=1,TextStrokeTransparency=1}):Play() end)
            task.delay(State.DamageLifetime+0.1,function() R.safeDestroy(gui) end)
        end

        R.watchHumanoid = function(player, character)
            local hum=character and character:FindFirstChildOfClass("Humanoid")
            if not hum or R.DamageWatched[hum] then return end
            R.DamageWatched[hum]=true; R.DamageHealth[hum]=hum.Health
            Scope:TrackConnection(hum.HealthChanged:Connect(function(newHealth)
                local old=R.DamageHealth[hum] or newHealth
                R.DamageHealth[hum]=newHealth
                local delta=old-newHealth
                if delta>0.05 then R.spawnDamage(player,character,delta) end
            end))
        end

        R.watchPlayer = function(player)
            if player.Character then R.watchHumanoid(player,player.Character) end
            Scope:TrackConnection(player.CharacterAdded:Connect(function(char)
                R.CharacterCache[player]=nil; R.OcclusionCache[player]=nil
                task.defer(function() R.watchHumanoid(player,char) end)
            end))
        end

        for _,p in ipairs(Players:GetPlayers()) do R.watchPlayer(p) end
        Scope:TrackConnection(Players.PlayerAdded:Connect(function(p) R.watchPlayer(p) end))
        Scope:TrackConnection(Players.PlayerRemoving:Connect(function(p) R.destroyBundle(p); local d=R.RadarDots[p]; if d then R.safeDestroy(d); R.RadarDots[p]=nil end end))

        for _,obj in ipairs(Workspace:GetDescendants()) do if obj:IsA("Tool") then R.KnownTools[obj]=true end end
        Scope:TrackConnection(Workspace.DescendantAdded:Connect(function(obj) if obj:IsA("Tool") then R.KnownTools[obj]=true end end))
        Scope:TrackConnection(Workspace.DescendantRemoving:Connect(function(obj) if obj:IsA("Tool") then R.KnownTools[obj]=nil; R.destroyToolBundle(obj) end end))

        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            R.Accumulator += dt; R.ToolAccumulator += dt; R.OcclusionAccumulator += dt
            if R.OcclusionAccumulator >= math.max(0.03,State.OcclusionRate) then R.OcclusionAccumulator=0; R.refreshOcclusion() end
            local interval=1/math.clamp(State.UpdateRate,10,60)
            if R.Accumulator>=interval then R.Accumulator=0; R.updatePlayers() end
            if R.ToolAccumulator>=math.max(0.1,State.ToolRefreshRate) then R.ToolAccumulator=0; R.refreshTools() end
        end))

        --====================================================
        -- UI
        --====================================================
        local Main=Context:CreateSection(Scope,Tab,"Players",false,"ESP / Players")
        Main:AddToggle({Name="Enable ESP",Flag="ESP_Enabled",Default=State.Enabled,RequiredGraphics="Medium",Description="Master switch. Player geometry is cached and rendered at the selected update rate instead of every frame.",FPSImpact={-5,-1},PingImpact=0,Callback=function(v) State.Enabled=v if not v then for _,b in pairs(R.Bundles) do R.hideBundle(b) end end end})
        Main:AddToggle({Name="2D Boxes",Flag="ESP_Boxes",Default=State.Boxes,RequiredGraphics="Low",Description="Body-only boxes. Accessories, Tools and HumanoidRootPart do not expand the box.",FPSImpact={-2,0},PingImpact=0,Callback=function(v) State.Boxes=v end})
        Main:AddToggle({Name="Names",Flag="ESP_Names",Default=State.Names,RequiredGraphics="Low",Callback=function(v) State.Names=v end})
        Main:AddToggle({Name="Health",Flag="ESP_Health",Default=State.Health,RequiredGraphics="Low",Callback=function(v) State.Health=v end})
        Main:AddToggle({Name="Distance",Flag="ESP_Distance",Default=State.Distance,RequiredGraphics="Low",Callback=function(v) State.Distance=v end})
        Main:AddToggle({Name="Tracers",Flag="ESP_Tracers",Default=State.Tracers,RequiredGraphics="Medium",FPSImpact={-2,0},Callback=function(v) State.Tracers=v end})
        Main:AddToggle({Name="Skeleton",Flag="ESP_Skeleton",Default=State.Skeleton,RequiredGraphics="High",Description="Uses cached Motor6D body pairs and disables skeletons beyond Far LOD.",FPSImpact={-7,-1},Callback=function(v) State.Skeleton=v end})
        Main:AddToggle({Name="Chams",Flag="ESP_Chams",Default=State.Chams,RequiredGraphics="Medium",Description="Highlight-based character overlay.",FPSImpact={-3,0},Callback=function(v) State.Chams=v end})
        Main:AddToggle({Name="3D ESP",Flag="ESP_3D",Default=State.ESP3D,RequiredGraphics="Medium",Description="3D body-sized box using the same cached body bounds as 2D ESP.",FPSImpact={-3,0},Callback=function(v) State.ESP3D=v end})
        Main:AddToggle({Name="Team Check",Flag="ESP_TeamCheck",Default=State.TeamCheck,RequiredGraphics="Low",Callback=function(v) State.TeamCheck=v end})

        local Style=Context:CreateSection(Scope,Tab,"Style / Performance",false,"ESP / Style")
        Style:AddColorPicker({Name="Main Color",Flag="ESP_Color",Default=State.Color,RequiredGraphics="Low",Callback=function(v) State.Color=v end})
        Style:AddColorPicker({Name="Team Color",Flag="ESP_TeamColor",Default=State.TeamColor,RequiredGraphics="Low",Callback=function(v) State.TeamColor=v end})
        Style:AddToggle({Name="Rainbow ESP",Flag="ESP_Rainbow",Default=State.Rainbow,RequiredGraphics="Low",FPSImpact={-1,0},Callback=function(v) State.Rainbow=v end})
        Style:AddSlider({Name="Rainbow Speed",Flag="ESP_RainbowSpeed",Min=0.02,Max=1.5,Default=State.RainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.RainbowSpeed=v end})
        Style:AddSlider({Name="Render Distance",Flag="ESP_MaxDistance",Min=50,Max=6000,Default=State.MaxDistance,Decimals=0,RequiredGraphics="Low",Description="Players outside this range are skipped before expensive screen calculations.",FPSImpact={-8,1},Callback=function(v) State.MaxDistance=v end})
        Style:AddSlider({Name="Update Rate",Flag="ESP_UpdateRate",Min=10,Max=60,Default=State.UpdateRate,Decimals=0,RequiredGraphics="Medium",Description="ESP refresh frequency. 20-30 Hz is recommended on large servers.",FPSImpact={-10,2},Callback=function(v) State.UpdateRate=v end})
        Style:AddSlider({Name="Max Rendered Players",Flag="ESP_MaxPlayers",Min=1,Max=100,Default=State.MaxRenderedPlayers,Decimals=0,RequiredGraphics="Medium",Description="Nearest-N player cap. This is the strongest server-size performance control.",FPSImpact={-20,5},Callback=function(v) State.MaxRenderedPlayers=v end})
        Style:AddSlider({Name="Far Skeleton LOD",Flag="ESP_FarLOD",Min=50,Max=3000,Default=State.FarLOD,Decimals=0,RequiredGraphics="Medium",Callback=function(v) State.FarLOD=v end})
        Style:AddSlider({Name="Line Thickness",Flag="ESP_Thickness",Min=1,Max=4,Default=State.Thickness,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.Thickness=v end})
        Style:AddSlider({Name="Cham Fill Transparency",Flag="ESP_ChamFill",Min=0,Max=1,Default=State.ChamFillTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ChamFillTransparency=v end})
        Style:AddSlider({Name="Cham Outline Transparency",Flag="ESP_ChamOutline",Min=0,Max=1,Default=State.ChamOutlineTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.ChamOutlineTransparency=v end})

        local Depth=Context:CreateSection(Scope,Tab,"Depth / Occlusion",false,"ESP / Depth")
        Depth:AddToggle({Name="Depth-Based ESP",Flag="ESP_DepthBased",Default=State.DepthBased,RequiredGraphics="Low",Description="Gradually fades distant ESP instead of rendering every target at identical strength.",FPSImpact=0,Callback=function(v) State.DepthBased=v end})
        Depth:AddSlider({Name="Depth Near",Flag="ESP_DepthNear",Min=0,Max=1000,Default=State.DepthNear,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.DepthNear=v end})
        Depth:AddSlider({Name="Depth Far",Flag="ESP_DepthFar",Min=100,Max=6000,Default=State.DepthFar,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.DepthFar=v end})
        Depth:AddSlider({Name="Max Fade",Flag="ESP_DepthFade",Min=0,Max=0.95,Default=State.DepthMaxFade,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.DepthMaxFade=v end})
        Depth:AddSeparator()
        Depth:AddToggle({Name="Occlusion Mode",Flag="ESP_Occlusion",Default=State.Occlusion,RequiredGraphics="High",Description="Raycasts from your camera to targets and changes hidden-player color. This costs CPU, so the result is cached between checks.",FPSImpact={-7,-1},Callback=function(v) State.Occlusion=v R.refreshOcclusion() end})
        Depth:AddColorPicker({Name="Occluded Color",Flag="ESP_OccludedColor",Default=State.OccludedColor,RequiredGraphics="Low",Callback=function(v) State.OccludedColor=v end})
        Depth:AddToggle({Name="Hide Occluded",Flag="ESP_HideOccluded",Default=State.HideOccluded,RequiredGraphics="Medium",Callback=function(v) State.HideOccluded=v end})
        Depth:AddSlider({Name="Occlusion Refresh",Flag="ESP_OcclusionRate",Min=0.04,Max=0.5,Default=State.OcclusionRate,Decimals=2,RequiredGraphics="High",Description="Seconds between visibility-cache refreshes. Higher is cheaper.",FPSImpact={-8,2},Callback=function(v) State.OcclusionRate=v end})

        local Trails=Context:CreateSection(Scope,Tab,"Player Trails",false,"ESP / Player Trails")
        Trails:AddToggle({Name="Player Trails",Flag="ESP_PlayerTrails",Default=State.PlayerTrails,RequiredGraphics="High",Description="Creates two crossing Trail ribbons on rendered players.",FPSImpact={-10,-2},Callback=function(v) State.PlayerTrails=v if not v then for _,b in pairs(R.Bundles) do R.destroyTrails(b) end end end})
        Trails:AddChoice({Name="Trail Color Mode",Flag="ESP_TrailMode",Values={"Per Player","Solid Gradient","Team","Rainbow"},Default=State.PlayerTrailMode,RequiredGraphics="Medium",Callback=function(v) State.PlayerTrailMode=v end})
        Trails:AddColorPicker({Name="Trail Start",Flag="ESP_TrailA",Default=State.PlayerTrailColorA,RequiredGraphics="Low",Callback=function(v) State.PlayerTrailColorA=v end})
        Trails:AddColorPicker({Name="Trail End",Flag="ESP_TrailB",Default=State.PlayerTrailColorB,RequiredGraphics="Low",Callback=function(v) State.PlayerTrailColorB=v end})
        Trails:AddSlider({Name="Trail Lifetime",Flag="ESP_TrailLifetime",Min=0.05,Max=2,Default=State.PlayerTrailLifetime,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.PlayerTrailLifetime=v end})
        Trails:AddSlider({Name="Trail Width",Flag="ESP_TrailWidth",Min=0.15,Max=2,Default=State.PlayerTrailWidth,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.PlayerTrailWidth=v for _,b in pairs(R.Bundles) do R.destroyTrails(b) end end})

        local Tools=Context:CreateSection(Scope,Tab,"Tool ESP",false,"ESP / Tools")
        Tools:AddToggle({Name="Tool ESP",Flag="ESP_ToolEnabled",Default=State.ToolESP,RequiredGraphics="Medium",Description="Tracks Tool instances already present in Workspace and future Tools through DescendantAdded instead of rescanning every frame.",FPSImpact={-5,-1},Callback=function(v) State.ToolESP=v if not v then R.refreshTools() end end})
        Tools:AddChoice({Name="Tool Mode",Flag="ESP_ToolMode",Values={"Both","Dropped","Equipped"},Default=State.ToolMode,RequiredGraphics="Low",Callback=function(v) State.ToolMode=v end})
        Tools:AddToggle({Name="Names",Flag="ESP_ToolNames",Default=State.ToolNames,RequiredGraphics="Low",Callback=function(v) State.ToolNames=v end})
        Tools:AddToggle({Name="Distance",Flag="ESP_ToolDistance",Default=State.ToolDistance,RequiredGraphics="Low",Callback=function(v) State.ToolDistance=v end})
        Tools:AddToggle({Name="Owner",Flag="ESP_ToolOwner",Default=State.ToolOwner,RequiredGraphics="Low",Callback=function(v) State.ToolOwner=v end})
        Tools:AddToggle({Name="Boxes",Flag="ESP_ToolBoxes",Default=State.ToolBoxes,RequiredGraphics="Medium",Callback=function(v) State.ToolBoxes=v end})
        Tools:AddToggle({Name="Chams",Flag="ESP_ToolChams",Default=State.ToolChams,RequiredGraphics="Medium",Callback=function(v) State.ToolChams=v end})
        Tools:AddToggle({Name="Tracers",Flag="ESP_ToolTracers",Default=State.ToolTracers,RequiredGraphics="Medium",Callback=function(v) State.ToolTracers=v end})
        Tools:AddToggle({Name="Rainbow Tools",Flag="ESP_ToolRainbow",Default=State.ToolRainbow,RequiredGraphics="Low",Callback=function(v) State.ToolRainbow=v end})
        Tools:AddColorPicker({Name="Tool Color",Flag="ESP_ToolColor",Default=State.ToolColor,RequiredGraphics="Low",Callback=function(v) State.ToolColor=v end})
        Tools:AddSlider({Name="Tool Distance",Flag="ESP_ToolMaxDistance",Min=50,Max=6000,Default=State.ToolMaxDistance,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.ToolMaxDistance=v end})
        Tools:AddSlider({Name="Tool Refresh",Flag="ESP_ToolRefresh",Min=0.1,Max=2,Default=State.ToolRefreshRate,Decimals=2,RequiredGraphics="Medium",Description="Lower values update dropped/equipped Tools faster but cost more CPU.",FPSImpact={-5,1},Callback=function(v) State.ToolRefreshRate=v end})

        local Radar=Context:CreateSection(Scope,Tab,"Radar / Minimap",false,"ESP / Radar")
        Radar:AddToggle({Name="Radar",Flag="ESP_Radar",Default=State.Radar,RequiredGraphics="Medium",Description="Local 2D minimap using relative X/Z positions. Uses the same player candidate list as ESP.",FPSImpact={-3,0},Callback=function(v) State.Radar=v end})
        Radar:AddChoice({Name="Radar Shape",Flag="ESP_RadarShape",Values={"Circle","Square"},Default=State.RadarShape,RequiredGraphics="Low",Callback=function(v) State.RadarShape=v end})
        Radar:AddSlider({Name="Radar Size",Flag="ESP_RadarSize",Min=120,Max=360,Default=State.RadarSize,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.RadarSize=v end})
        Radar:AddSlider({Name="Radar Range",Flag="ESP_RadarRange",Min=50,Max=5000,Default=State.RadarRange,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.RadarRange=v end})
        Radar:AddToggle({Name="Rotate With Camera",Flag="ESP_RadarRotate",Default=State.RadarRotate,RequiredGraphics="Low",Callback=function(v) State.RadarRotate=v end})
        Radar:AddToggle({Name="Player Names",Flag="ESP_RadarNames",Default=State.RadarNames,RequiredGraphics="Medium",FPSImpact={-2,0},Callback=function(v) State.RadarNames=v end})
        Radar:AddToggle({Name="Show Tools",Flag="ESP_RadarTools",Default=State.RadarTools,RequiredGraphics="Medium",FPSImpact={-2,0},Callback=function(v) State.RadarTools=v end})
        Radar:AddSlider({Name="Background Transparency",Flag="ESP_RadarOpacity",Min=0,Max=0.95,Default=State.RadarOpacity,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.RadarOpacity=v end})

        local Damage=Context:CreateSection(Scope,Tab,"Damage Visualizer",false,"ESP / Damage")
        Damage:AddToggle({Name="Damage Numbers",Flag="ESP_Damage",Default=State.DamageVisualizer,RequiredGraphics="Medium",Description="Shows health decreases observed from replicated Humanoid.Health changes as floating numbers.",FPSImpact={-2,0},Callback=function(v) State.DamageVisualizer=v end})
        Damage:AddToggle({Name="Include Local Player",Flag="ESP_DamageLocal",Default=State.DamageLocalPlayer,RequiredGraphics="Low",Callback=function(v) State.DamageLocalPlayer=v end})
        Damage:AddColorPicker({Name="Damage Color",Flag="ESP_DamageColor",Default=State.DamageColor,RequiredGraphics="Low",Callback=function(v) State.DamageColor=v end})
        Damage:AddToggle({Name="Rainbow Damage",Flag="ESP_DamageRainbow",Default=State.DamageRainbow,RequiredGraphics="Low",Callback=function(v) State.DamageRainbow=v end})
        Damage:AddSlider({Name="Lifetime",Flag="ESP_DamageLifetime",Min=0.25,Max=2.5,Default=State.DamageLifetime,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.DamageLifetime=v end})
        Damage:AddSlider({Name="Scale",Flag="ESP_DamageScale",Min=0.5,Max=2,Default=State.DamageScale,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.DamageScale=v end})

        Scope:AddCleaner(function()
            for player in pairs(R.Bundles) do R.destroyBundle(player) end
            for tool in pairs(R.ToolBundles) do R.destroyToolBundle(tool) end
            table.clear(R.OcclusionCache)
        end)
    end,
}
