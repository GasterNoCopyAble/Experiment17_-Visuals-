--[[
    Experiment 17 - Trajectory Module
    Compatible with Experiment17 Modular Loader v0.2+

    Features:
      * Exact local-camera look direction.
      * Remote-player facing fallback (remote Camera is not replicated).
      * Vertical ground/drop line + drop text.
      * Ballistic landing prediction from AssemblyLinearVelocity + Workspace.Gravity.
      * Landing marker + time-to-impact text.
      * Target modes, distance/player caps, update-rate and sample controls.
      * Optional rainbow trajectory styling.
]]

return {
    Id = "Trajectory",
    Name = "Trajectory",
    Version = "1.0.0",
    Order = 60,

    Init = function(Context, Scope, Tab)
        local Services = Context.Services
        local Players = Services.Players
        local RunService = Services.RunService
        local Workspace = Services.Workspace
        local LocalPlayer = Context.LocalPlayer

        local State = Context:GetState("Trajectory", {
            Enabled = false,
            TargetMode = "Local Player",
            MaxDistance = 1800,
            MaxPlayers = 12,
            UpdateRate = 20,

            LookLine = true,
            LookDistance = 500,
            GroundLine = true,
            GroundDistance = 1200,
            FallText = true,

            Prediction = true,
            PredictionTime = 2.75,
            PredictionSamples = 24,
            LandingMarker = true,
            LandingInfo = true,

            Thickness = 1.5,
            PathStyle = "Solid",
            Rainbow = false,
            RainbowSpeed = 0.25,
            LookColor = Color3.fromRGB(95, 180, 255),
            GroundColor = Color3.fromRGB(255, 205, 85),
            PredictionColor = Color3.fromRGB(190, 105, 255),
            LandingColor = Color3.fromRGB(255, 85, 125),
        })

        local R = {
            Camera = Workspace.CurrentCamera,
            Bundles = {},
            Accumulator = 0,
            MaxPathObjects = 40,
        }

        R.Gui = Scope:TrackInstance(Instance.new("ScreenGui"))
        R.Gui.Name = "Experiment17_TrajectoryOverlay"
        R.Gui.ResetOnSpawn = false
        R.Gui.IgnoreGuiInset = true
        R.Gui.DisplayOrder = 900000
        R.Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        R.Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

        R.Root = Instance.new("Frame")
        R.Root.Name = "TrajectoryRoot"
        R.Root.BackgroundTransparency = 1
        R.Root.Size = UDim2.fromScale(1, 1)
        R.Root.Parent = R.Gui

        R.rainbow = function(offset)
            return Color3.fromHSV(((os.clock() * State.RainbowSpeed) + (offset or 0)) % 1, 0.92, 1)
        end

        R.newLine = function(name, z)
            local line = Instance.new("Frame")
            line.Name = name
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BorderSizePixel = 0
            line.BackgroundColor3 = Color3.new(1, 1, 1)
            line.BackgroundTransparency = 0.04
            line.Visible = false
            line.ZIndex = z or 10
            line.Parent = R.Root
            return line
        end

        R.newText = function(name, z)
            local label = Instance.new("TextLabel")
            label.Name = name
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Font = Enum.Font.Code
            label.TextSize = 13
            label.TextStrokeTransparency = 0.3
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.Visible = false
            label.ZIndex = z or 12
            label.Parent = R.Root
            return label
        end

        R.screenPoint = function(worldPosition)
            R.Camera = Workspace.CurrentCamera or R.Camera
            if not R.Camera then
                return Vector2.zero, false, -1
            end
            local p, onScreen = R.Camera:WorldToViewportPoint(worldPosition)
            return Vector2.new(p.X, p.Y), onScreen, p.Z
        end

        R.setLine = function(line, a, b, thickness, color, visible)
            if not line then return end
            if not visible then
                line.Visible = false
                return
            end
            local delta = b - a
            local length = delta.Magnitude
            if length < 0.5 then
                line.Visible = false
                return
            end
            line.Visible = true
            line.BackgroundColor3 = color
            line.Size = UDim2.fromOffset(length, math.max(1, thickness))
            line.Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5)
            line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        end

        R.hideBundle = function(bundle)
            if not bundle then return end
            bundle.Look.Visible = false
            bundle.Ground.Visible = false
            bundle.Landing.Visible = false
            bundle.DropText.Visible = false
            bundle.LandingText.Visible = false
            for _, line in ipairs(bundle.Path) do
                line.Visible = false
            end
        end

        R.createBundle = function(player)
            local existing = R.Bundles[player]
            if existing then return existing end

            local bundle = {
                Look = R.newLine("Look_" .. player.Name, 35),
                Ground = R.newLine("Ground_" .. player.Name, 35),
                Path = {},
                Landing = Instance.new("Frame"),
                DropText = R.newText("Drop_" .. player.Name, 39),
                LandingText = R.newText("LandingText_" .. player.Name, 39),
            }

            bundle.Landing.Name = "Landing_" .. player.Name
            bundle.Landing.AnchorPoint = Vector2.new(0.5, 0.5)
            bundle.Landing.Size = UDim2.fromOffset(12, 12)
            bundle.Landing.BorderSizePixel = 0
            bundle.Landing.Visible = false
            bundle.Landing.ZIndex = 38
            bundle.Landing.Parent = R.Root
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = bundle.Landing
            local stroke = Instance.new("UIStroke")
            stroke.Thickness = 1.2
            stroke.Transparency = 0.12
            stroke.Parent = bundle.Landing
            bundle.LandingStroke = stroke

            for i = 1, R.MaxPathObjects do
                bundle.Path[i] = R.newLine("Path_" .. player.Name .. "_" .. i, 36)
            end

            R.Bundles[player] = bundle
            return bundle
        end

        R.destroyBundle = function(player)
            local bundle = R.Bundles[player]
            if not bundle then return end
            pcall(function() bundle.Look:Destroy() end)
            pcall(function() bundle.Ground:Destroy() end)
            pcall(function() bundle.Landing:Destroy() end)
            pcall(function() bundle.DropText:Destroy() end)
            pcall(function() bundle.LandingText:Destroy() end)
            for _, line in ipairs(bundle.Path) do
                pcall(function() line:Destroy() end)
            end
            R.Bundles[player] = nil
        end

        R.targetAllowed = function(player)
            if State.TargetMode == "Local Player" then
                return player == LocalPlayer
            elseif State.TargetMode == "Other Players" then
                return player ~= LocalPlayer
            end
            return true
        end

        R.makeRayParams = function(character)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character}
            params.IgnoreWater = false
            return params
        end

        R.pathVisibleByStyle = function(index)
            if State.PathStyle == "Dashed" then
                return index % 2 == 1
            elseif State.PathStyle == "Dots" then
                return index % 3 == 1
            end
            return true
        end

        R.colorSet = function(playerIndex)
            if State.Rainbow then
                local base = (playerIndex or 0) * 0.037
                return R.rainbow(base), R.rainbow(base + 0.12), R.rainbow(base + 0.24), R.rainbow(base + 0.36)
            end
            return State.LookColor, State.GroundColor, State.PredictionColor, State.LandingColor
        end

        R.updatePlayer = function(player, bundle, playerIndex)
            if not State.Enabled or not R.targetAllowed(player) then
                R.hideBundle(bundle)
                return false
            end

            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not char or not root or not hum or hum.Health <= 0 then
                R.hideBundle(bundle)
                return false
            end

            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if localRoot and player ~= LocalPlayer and (root.Position - localRoot.Position).Magnitude > State.MaxDistance then
                R.hideBundle(bundle)
                return false
            end

            local lookColor, groundColor, pathColor, landingColor = R.colorSet(playerIndex)
            local params = R.makeRayParams(char)

            if State.LookLine then
                local origin, lookVector
                if player == LocalPlayer and Workspace.CurrentCamera then
                    origin = Workspace.CurrentCamera.CFrame.Position
                    lookVector = Workspace.CurrentCamera.CFrame.LookVector
                else
                    origin = root.Position + Vector3.new(0, 1.5, 0)
                    lookVector = root.CFrame.LookVector
                end

                local ray = lookVector * State.LookDistance
                local hit = Workspace:Raycast(origin, ray, params)
                local endpoint = hit and hit.Position or (origin + ray)
                local a, av, az = R.screenPoint(origin)
                local b, bv, bz = R.screenPoint(endpoint)
                R.setLine(bundle.Look, a, b, State.Thickness, lookColor, az > 0 and bz > 0 and (av or bv))
            else
                bundle.Look.Visible = false
            end

            local groundResult = Workspace:Raycast(root.Position, Vector3.new(0, -State.GroundDistance, 0), params)
            if State.GroundLine and groundResult then
                local a, av, az = R.screenPoint(root.Position)
                local b, bv, bz = R.screenPoint(groundResult.Position)
                R.setLine(bundle.Ground, a, b, State.Thickness, groundColor, az > 0 and bz > 0 and (av or bv))
            else
                bundle.Ground.Visible = false
            end

            if State.FallText and groundResult then
                local p, visible, z = R.screenPoint(root.Position)
                bundle.DropText.Visible = visible and z > 0
                if bundle.DropText.Visible then
                    local drop = (root.Position - groundResult.Position).Magnitude
                    bundle.DropText.Text = string.format("DROP %.1f", drop)
                    bundle.DropText.TextColor3 = groundColor
                    bundle.DropText.Position = UDim2.fromOffset(p.X + 38, p.Y - 8)
                    bundle.DropText.Size = UDim2.fromOffset(120, 18)
                end
            else
                bundle.DropText.Visible = false
            end

            local landingPosition, landingTime = nil, nil
            if State.Prediction then
                local start = root.Position
                local velocity = root.AssemblyLinearVelocity
                local gravity = Vector3.new(0, -Workspace.Gravity, 0)
                local previous = start
                local samples = math.clamp(math.floor(State.PredictionSamples), 4, R.MaxPathObjects)
                local maxTime = math.max(0.2, State.PredictionTime)
                local used = 0

                for i = 1, samples do
                    local t = maxTime * (i / samples)
                    local predicted = start + velocity * t + 0.5 * gravity * (t * t)
                    local delta = predicted - previous
                    local hit = Workspace:Raycast(previous, delta, params)
                    local segmentEnd = hit and hit.Position or predicted
                    local line = bundle.Path[i]

                    if R.pathVisibleByStyle(i) then
                        local a, av, az = R.screenPoint(previous)
                        local b, bv, bz = R.screenPoint(segmentEnd)
                        local width = State.PathStyle == "Dots" and (State.Thickness * 2.0) or State.Thickness
                        R.setLine(line, a, b, width, pathColor, az > 0 and bz > 0 and (av or bv))
                    else
                        line.Visible = false
                    end
                    used = i

                    if hit then
                        landingPosition = hit.Position
                        landingTime = t
                        break
                    end
                    previous = predicted
                end

                for i = used + 1, R.MaxPathObjects do
                    bundle.Path[i].Visible = false
                end
            else
                for _, line in ipairs(bundle.Path) do
                    line.Visible = false
                end
            end

            if State.LandingMarker and landingPosition then
                local p, visible, z = R.screenPoint(landingPosition)
                bundle.Landing.Visible = visible and z > 0
                if bundle.Landing.Visible then
                    bundle.Landing.Position = UDim2.fromOffset(p.X, p.Y)
                    bundle.Landing.BackgroundColor3 = landingColor
                    bundle.LandingStroke.Color = landingColor
                end
            else
                bundle.Landing.Visible = false
            end

            if State.LandingInfo and landingPosition and landingTime then
                local p, visible, z = R.screenPoint(landingPosition)
                bundle.LandingText.Visible = visible and z > 0
                if bundle.LandingText.Visible then
                    local horizontal = Vector3.new(landingPosition.X - root.Position.X, 0, landingPosition.Z - root.Position.Z).Magnitude
                    bundle.LandingText.Text = string.format("LAND %.1fs  •  %.0f studs", landingTime, horizontal)
                    bundle.LandingText.TextColor3 = landingColor
                    bundle.LandingText.Position = UDim2.fromOffset(p.X + 12, p.Y + 8)
                    bundle.LandingText.Size = UDim2.fromOffset(190, 18)
                end
            else
                bundle.LandingText.Visible = false
            end

            return true
        end

        R.updateAll = function()
            R.Camera = Workspace.CurrentCamera or R.Camera
            if not State.Enabled then
                for _, bundle in pairs(R.Bundles) do
                    R.hideBundle(bundle)
                end
                return
            end

            local rendered = 0
            for index, player in ipairs(Players:GetPlayers()) do
                if R.targetAllowed(player) then
                    if rendered >= math.max(1, math.floor(State.MaxPlayers)) and player ~= LocalPlayer then
                        local old = R.Bundles[player]
                        if old then R.hideBundle(old) end
                    else
                        local bundle = R.createBundle(player)
                        if R.updatePlayer(player, bundle, index) then
                            rendered += 1
                        end
                    end
                else
                    local old = R.Bundles[player]
                    if old then R.hideBundle(old) end
                end
            end
        end

        Scope:TrackConnection(Players.PlayerRemoving:Connect(function(player)
            R.destroyBundle(player)
        end))

        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            R.Accumulator += dt
            local interval = 1 / math.clamp(State.UpdateRate, 5, 60)
            if R.Accumulator >= interval then
                R.Accumulator = 0
                R.updateAll()
            end
        end))

        local Main = Context:CreateSection(Scope, Tab, "Trajectory", false, "Trajectory / Main")
        Main:AddToggle({
            Name = "Enable Trajectory",
            Flag = "Trajectory_Enabled",
            Default = State.Enabled,
            RequiredGraphics = "High",
            Description = "Master trajectory visualizer. Uses throttled updates rather than RenderStepped to reduce cost on large servers.",
            FPSImpact = {-12, -2},
            PingImpact = 0,
            Callback = function(v) State.Enabled = v if not v then R.updateAll() end end,
        })
        Main:AddChoice({Name="Target Mode",Flag="Trajectory_TargetMode",Values={"Local Player","Other Players","All Players"},Default=State.TargetMode,RequiredGraphics="Low",Callback=function(v) State.TargetMode=v end})
        Main:AddSlider({Name="Max Distance",Flag="Trajectory_MaxDistance",Min=100,Max=5000,Default=State.MaxDistance,Decimals=0,RequiredGraphics="Medium",Description="Remote players farther than this are skipped. Local-player trajectory is never distance-culled.",FPSImpact={-4,1},Callback=function(v) State.MaxDistance=v end})
        Main:AddSlider({Name="Max Players",Flag="Trajectory_MaxPlayers",Min=1,Max=40,Default=State.MaxPlayers,Decimals=0,RequiredGraphics="High",Description="Hard cap for simultaneous remote trajectory calculations.",FPSImpact={-12,4},Callback=function(v) State.MaxPlayers=math.floor(v) end})
        Main:AddSlider({Name="Update Rate",Flag="Trajectory_UpdateRate",Min=5,Max=60,Default=State.UpdateRate,Decimals=0,RequiredGraphics="High",Description="Trajectory calculations per second. 15-25 Hz is usually enough and is much cheaper than 60 Hz.",FPSImpact={-12,4},Callback=function(v) State.UpdateRate=v end})

        local Direction = Context:CreateSection(Scope, Tab, "Direction / Drop", false, "Trajectory / Direction")
        Direction:AddToggle({Name="Look Direction",Flag="Trajectory_Look",Default=State.LookLine,RequiredGraphics="Low",Description="Local player uses the real CurrentCamera LookVector. Remote players use character facing because their local Camera is not replicated to this client.",FPSImpact={-1,0},Callback=function(v) State.LookLine=v end})
        Direction:AddSlider({Name="Look Distance",Flag="Trajectory_LookDistance",Min=25,Max=3000,Default=State.LookDistance,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.LookDistance=v end})
        Direction:AddToggle({Name="Ground / Fall Line",Flag="Trajectory_Ground",Default=State.GroundLine,RequiredGraphics="Medium",Description="Raycasts vertically down from the root and draws the direct drop to the first surface.",FPSImpact={-2,0},Callback=function(v) State.GroundLine=v end})
        Direction:AddToggle({Name="Drop Text",Flag="Trajectory_FallText",Default=State.FallText,RequiredGraphics="Low",Callback=function(v) State.FallText=v end})
        Direction:AddSlider({Name="Ground Ray Distance",Flag="Trajectory_GroundDistance",Min=50,Max=5000,Default=State.GroundDistance,Decimals=0,RequiredGraphics="Medium",Callback=function(v) State.GroundDistance=v end})

        local Prediction = Context:CreateSection(Scope, Tab, "Landing Prediction", false, "Trajectory / Prediction")
        Prediction:AddToggle({Name="Ballistic Landing Prediction",Flag="Trajectory_Prediction",Default=State.Prediction,RequiredGraphics="High",Description="Predicts motion from AssemblyLinearVelocity and Workspace.Gravity, raycasting each simulated segment for the first collision.",FPSImpact={-12,-2},Callback=function(v) State.Prediction=v end})
        Prediction:AddSlider({Name="Prediction Time",Flag="Trajectory_PredictionTime",Min=0.25,Max=6,Default=State.PredictionTime,Decimals=2,RequiredGraphics="High",Callback=function(v) State.PredictionTime=v end})
        Prediction:AddSlider({Name="Prediction Samples",Flag="Trajectory_PredictionSamples",Min=4,Max=40,Default=State.PredictionSamples,Decimals=0,RequiredGraphics="Epic",Description="Raycast samples per player update. Higher values improve collision precision but are the main trajectory CPU cost.",FPSImpact={-18,5},Callback=function(v) State.PredictionSamples=math.floor(v) end})
        Prediction:AddToggle({Name="Landing Marker",Flag="Trajectory_LandingMarker",Default=State.LandingMarker,RequiredGraphics="Low",Callback=function(v) State.LandingMarker=v end})
        Prediction:AddToggle({Name="Landing Info",Flag="Trajectory_LandingInfo",Default=State.LandingInfo,RequiredGraphics="Low",Description="Shows predicted impact time and horizontal travel distance beside the landing marker.",Callback=function(v) State.LandingInfo=v end})
        Prediction:AddChoice({Name="Path Style",Flag="Trajectory_PathStyle",Values={"Solid","Dashed","Dots"},Default=State.PathStyle,RequiredGraphics="Low",Callback=function(v) State.PathStyle=v end})

        local Style = Context:CreateSection(Scope, Tab, "Style", false, "Trajectory / Style")
        Style:AddSlider({Name="Line Thickness",Flag="Trajectory_Thickness",Min=1,Max=6,Default=State.Thickness,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.Thickness=v end})
        Style:AddToggle({Name="Rainbow Trajectory",Flag="Trajectory_Rainbow",Default=State.Rainbow,RequiredGraphics="Medium",Callback=function(v) State.Rainbow=v end})
        Style:AddSlider({Name="Rainbow Speed",Flag="Trajectory_RainbowSpeed",Min=0.02,Max=1.5,Default=State.RainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.RainbowSpeed=v end})
        Style:AddColorPicker({Name="Look Color",Flag="Trajectory_LookColor",Default=State.LookColor,RequiredGraphics="Low",Callback=function(v) State.LookColor=v end})
        Style:AddColorPicker({Name="Ground Color",Flag="Trajectory_GroundColor",Default=State.GroundColor,RequiredGraphics="Low",Callback=function(v) State.GroundColor=v end})
        Style:AddColorPicker({Name="Prediction Color",Flag="Trajectory_PathColor",Default=State.PredictionColor,RequiredGraphics="Low",Callback=function(v) State.PredictionColor=v end})
        Style:AddColorPicker({Name="Landing Color",Flag="Trajectory_LandingColor",Default=State.LandingColor,RequiredGraphics="Low",Callback=function(v) State.LandingColor=v end})

        Scope:AddCleaner(function()
            for player in pairs(R.Bundles) do
                R.destroyBundle(player)
            end
        end)
    end,
}
