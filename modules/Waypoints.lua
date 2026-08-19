--[[
    Experiment 17 - Waypoints Module
    Compatible with Experiment17 Modular Loader v0.2+

    Features:
      * Separate waypoint profiles for different games/routes.
      * Fast waypoint hotkey with modifier + key.
      * Manual current-position and XYZ waypoint creation.
      * Select, rename, delete, reorder, previous/next.
      * Multiple marker shapes and selected-waypoint styling.
      * Distance + ETA from current Humanoid.WalkSpeed.
      * Route rendering between waypoints with total distance/ETA HUD.
      * JSON persistence when readfile/writefile are available.
      * Shared API + Event Bus notifications for add-on modules.
]]

return {
    Id = "Waypoints",
    Name = "Waypoints",
    Version = "1.0.0",
    Order = 70,

    Init = function(Context, Scope, Tab)
        local Services = Context.Services
        local UIS = Services.UIS
        local RunService = Services.RunService
        local Workspace = Services.Workspace
        local HttpService = Services.HttpService
        local LocalPlayer = Context.LocalPlayer

        local State = Context:GetState("Waypoints", {
            ActiveProfile = "Place_" .. tostring(game.PlaceId),
            SelectedId = nil,
            Profiles = {},

            QuickModifier = "LeftAlt",
            QuickKey = "P",

            ShowAll = true,
            ShowCards = true,
            ShowDistance = true,
            ShowETA = true,
            AlwaysOnTop = true,
            MaxRenderDistance = 0,
            Shape = "Ring",
            MarkerSize = 1.0,
            Color = Color3.fromRGB(180, 110, 255),
            SelectedColor = Color3.fromRGB(255, 210, 80),

            RouteEnabled = false,
            RouteMode = "Profile Order",
            RouteStartFromPlayer = true,
            RouteHUD = true,
            RouteColor = Color3.fromRGB(105, 190, 255),
            RouteRainbow = false,
            RouteRainbowSpeed = 0.22,
            RouteThickness = 0.12,
            RouteTransparency = 0.12,

            ManualName = "",
            ManualX = "0",
            ManualY = "0",
            ManualZ = "0",
            NewProfileName = "",
            RenameText = "",
        })

        local R = {
            Markers = {},
            RouteBeams = {},
            DynamicProfileControls = {},
            DynamicWaypointControls = {},
            UpdateAccumulator = 0,
            ProfileSection = nil,
            ListSection = nil,
            RenameControl = nil,
            XControl = nil,
            YControl = nil,
            ZControl = nil,
            File = tostring(Context.Config.RootFolder or "Experiment17_Visuals") .. "/waypoints.json",
        }

        R.Folder = Scope:TrackInstance(Instance.new("Folder"))
        R.Folder.Name = "Experiment17_Waypoints"
        R.Folder.Parent = Workspace

        R.RouteFolder = Instance.new("Folder")
        R.RouteFolder.Name = "Routes"
        R.RouteFolder.Parent = R.Folder

        R.RouteStartPart = Instance.new("Part")
        R.RouteStartPart.Name = "RouteStart"
        R.RouteStartPart.Size = Vector3.new(0.1, 0.1, 0.1)
        R.RouteStartPart.Anchored = true
        R.RouteStartPart.CanCollide = false
        R.RouteStartPart.CanTouch = false
        R.RouteStartPart.CanQuery = false
        R.RouteStartPart.CastShadow = false
        R.RouteStartPart.Transparency = 1
        R.RouteStartPart.Parent = R.RouteFolder
        R.RouteStartAttachment = Instance.new("Attachment")
        R.RouteStartAttachment.Name = "RouteStartAttachment"
        R.RouteStartAttachment.Parent = R.RouteStartPart

        R.RouteGui = Scope:TrackInstance(Instance.new("ScreenGui"))
        R.RouteGui.Name = "Experiment17_RouteHUD"
        R.RouteGui.ResetOnSpawn = false
        R.RouteGui.IgnoreGuiInset = true
        R.RouteGui.DisplayOrder = 880000
        R.RouteGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

        R.RouteCard = Instance.new("Frame")
        R.RouteCard.Name = "RouteCard"
        R.RouteCard.AnchorPoint = Vector2.new(0.5, 0)
        R.RouteCard.Position = UDim2.new(0.5, 0, 0, 26)
        R.RouteCard.Size = UDim2.fromOffset(330, 48)
        R.RouteCard.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
        R.RouteCard.BackgroundTransparency = 0.15
        R.RouteCard.BorderSizePixel = 0
        R.RouteCard.Visible = false
        R.RouteCard.Parent = R.RouteGui
        local routeCorner = Instance.new("UICorner")
        routeCorner.CornerRadius = UDim.new(0, 9)
        routeCorner.Parent = R.RouteCard
        R.RouteStroke = Instance.new("UIStroke")
        R.RouteStroke.Thickness = 1.3
        R.RouteStroke.Transparency = 0.16
        R.RouteStroke.Parent = R.RouteCard
        R.RouteLabel = Instance.new("TextLabel")
        R.RouteLabel.BackgroundTransparency = 1
        R.RouteLabel.Position = UDim2.fromOffset(10, 4)
        R.RouteLabel.Size = UDim2.new(1, -20, 1, -8)
        R.RouteLabel.Font = Enum.Font.Code
        R.RouteLabel.TextSize = 14
        R.RouteLabel.TextStrokeTransparency = 0.55
        R.RouteLabel.TextXAlignment = Enum.TextXAlignment.Center
        R.RouteLabel.TextYAlignment = Enum.TextYAlignment.Center
        R.RouteLabel.TextWrapped = true
        R.RouteLabel.Parent = R.RouteCard

        R.trim = function(value)
            value = tostring(value or "")
            return value:match("^%s*(.-)%s*$") or ""
        end

        R.removeArrayValue = function(array, value)
            if type(array) ~= "table" then return end
            for i = #array, 1, -1 do
                if array[i] == value then
                    table.remove(array, i)
                end
            end
        end

        R.destroyControl = function(control)
            if not control then return end
            R.removeArrayValue(Scope.Controls, control)
            if Context.Library then
                R.removeArrayValue(Context.Library.Controls, control)
                R.removeArrayValue(Context.Library.GatedControls, control)
            end
            pcall(function()
                if control.Holder and control.Holder.Parent then
                    control.Holder:Destroy()
                end
            end)
        end

        R.clearDynamic = function(list)
            for _, control in ipairs(list) do
                R.destroyControl(control)
            end
            table.clear(list)
        end

        R.newId = function()
            return HttpService:GenerateGUID(false)
        end

        R.ensureProfile = function(name)
            name = R.trim(name)
            if name == "" then
                name = "Place_" .. tostring(game.PlaceId)
            end
            if type(State.Profiles[name]) ~= "table" then
                State.Profiles[name] = {}
            end
            return State.Profiles[name], name
        end

        R.activeList = function()
            local list, name = R.ensureProfile(State.ActiveProfile)
            State.ActiveProfile = name
            return list
        end

        R.getWaypoint = function(id)
            if not id then return nil, nil end
            for index, waypoint in ipairs(R.activeList()) do
                if waypoint.Id == id then
                    return waypoint, index
                end
            end
            return nil, nil
        end

        R.getRoot = function()
            local char = LocalPlayer.Character
            return char and char:FindFirstChild("HumanoidRootPart")
        end

        R.getWalkSpeed = function()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum then return 16 end
            return math.max(0, hum.WalkSpeed)
        end

        R.formatETA = function(seconds)
            if seconds == math.huge then return "∞" end
            seconds = math.max(0, seconds or 0)
            if seconds < 60 then
                return string.format("%.1fs", seconds)
            elseif seconds < 3600 then
                return string.format("%dm %02ds", math.floor(seconds / 60), math.floor(seconds % 60))
            end
            return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
        end

        R.horizontalDistance = function(a, b)
            return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
        end

        R.rainbow = function(offset)
            return Color3.fromHSV(((os.clock() * State.RouteRainbowSpeed) + (offset or 0)) % 1, 0.92, 1)
        end

        R.save = function()
            if not Context.FS or not Context.FS.CanWrite or type(Context.FS.Write) ~= "function" then
                return false
            end
            pcall(function() Context:EnsureFolders() end)
            local payload = {
                Version = 3,
                ActiveProfile = State.ActiveProfile,
                Profiles = State.Profiles,
            }
            local okEncode, encoded = pcall(function()
                return HttpService:JSONEncode(payload)
            end)
            if not okEncode then return false end
            local okWrite = pcall(Context.FS.Write, R.File, encoded)
            return okWrite
        end

        R.load = function()
            if not Context.FS or type(Context.FS.Read) ~= "function" then
                R.ensureProfile(State.ActiveProfile)
                return false
            end
            if Context.FS.IsFile then
                local okExists, exists = pcall(Context.FS.IsFile, R.File)
                if not okExists or not exists then
                    R.ensureProfile(State.ActiveProfile)
                    return false
                end
            end
            local okRead, raw = pcall(Context.FS.Read, R.File)
            if not okRead or type(raw) ~= "string" or raw == "" then
                R.ensureProfile(State.ActiveProfile)
                return false
            end
            local okDecode, data = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if not okDecode or type(data) ~= "table" then
                R.ensureProfile(State.ActiveProfile)
                return false
            end
            if type(data.Profiles) == "table" then
                State.Profiles = data.Profiles
            end
            if type(data.ActiveProfile) == "string" and data.ActiveProfile ~= "" then
                State.ActiveProfile = data.ActiveProfile
            end
            R.ensureProfile(State.ActiveProfile)
            return true
        end

        R.setColored = function(objects, color)
            for _, object in ipairs(objects or {}) do
                if object:IsA("Frame") then
                    object.BackgroundColor3 = color
                elseif object:IsA("UIStroke") then
                    object.Color = color
                end
            end
        end

        R.makeIcon = function(parent, shape, color)
            local root = Instance.new("Frame")
            root.Name = "Icon"
            root.AnchorPoint = Vector2.new(0.5, 0.5)
            root.Position = UDim2.fromScale(0.5, 0.5)
            root.Size = UDim2.fromScale(0.78, 0.78)
            root.BackgroundTransparency = 1
            root.Parent = parent

            local colored = {}
            local function piece(size, position, rotation, rounded, filled)
                local f = Instance.new("Frame")
                f.AnchorPoint = Vector2.new(0.5, 0.5)
                f.Position = position or UDim2.fromScale(0.5, 0.5)
                f.Size = size
                f.Rotation = rotation or 0
                f.BorderSizePixel = 0
                f.BackgroundColor3 = color
                f.BackgroundTransparency = filled == false and 1 or 0.08
                f.Parent = root
                table.insert(colored, f)
                if rounded then
                    local c = Instance.new("UICorner")
                    c.CornerRadius = UDim.new(1, 0)
                    c.Parent = f
                end
                if filled == false then
                    local stroke = Instance.new("UIStroke")
                    stroke.Thickness = 2
                    stroke.Color = color
                    stroke.Parent = f
                    table.insert(colored, stroke)
                end
                return f
            end

            if shape == "Circle" then
                piece(UDim2.fromScale(0.72, 0.72), nil, 0, true, true)
            elseif shape == "Square" then
                piece(UDim2.fromScale(0.68, 0.68), nil, 0, false, true)
            elseif shape == "Diamond" then
                piece(UDim2.fromScale(0.62, 0.62), nil, 45, false, true)
            elseif shape == "Cross" then
                piece(UDim2.fromScale(0.86, 0.16), nil, 0, true, true)
                piece(UDim2.fromScale(0.16, 0.86), nil, 0, true, true)
            elseif shape == "Triangle" then
                piece(UDim2.fromScale(0.68, 0.09), UDim2.fromScale(0.37, 0.62), -58, true, true)
                piece(UDim2.fromScale(0.68, 0.09), UDim2.fromScale(0.63, 0.62), 58, true, true)
                piece(UDim2.fromScale(0.58, 0.09), UDim2.fromScale(0.5, 0.77), 0, true, true)
            elseif shape == "Pin" then
                piece(UDim2.fromScale(0.54, 0.54), UDim2.fromScale(0.5, 0.36), 0, true, false)
                piece(UDim2.fromScale(0.13, 0.54), UDim2.fromScale(0.5, 0.70), 0, true, true)
                piece(UDim2.fromScale(0.18, 0.18), UDim2.fromScale(0.5, 0.36), 0, true, true)
            elseif shape == "Star" then
                for i = 0, 3 do
                    piece(UDim2.fromScale(0.82, 0.13), nil, i * 45, true, true)
                end
                piece(UDim2.fromScale(0.22, 0.22), nil, 0, true, true)
            elseif shape == "Beacon" then
                piece(UDim2.fromScale(0.14, 0.92), nil, 0, true, true)
                piece(UDim2.fromScale(0.58, 0.15), UDim2.fromScale(0.5, 0.18), 0, true, true)
                piece(UDim2.fromScale(0.58, 0.15), UDim2.fromScale(0.5, 0.82), 0, true, true)
            else
                piece(UDim2.fromScale(0.78, 0.78), nil, 0, true, false)
                piece(UDim2.fromScale(0.20, 0.20), nil, 0, true, true)
            end

            return root, colored
        end

        R.clearRoute = function()
            for _, beam in ipairs(R.RouteBeams) do
                pcall(function() beam:Destroy() end)
            end
            table.clear(R.RouteBeams)
        end

        R.routeList = function()
            local list = R.activeList()
            local output = {}
            local startIndex = 1
            if State.RouteMode == "Selected Forward" and State.SelectedId then
                local _, selectedIndex = R.getWaypoint(State.SelectedId)
                if selectedIndex then startIndex = selectedIndex end
            end
            for i = startIndex, #list do
                output[#output + 1] = list[i]
            end
            return output
        end

        R.newBeam = function(a0, a1, index)
            local beam = Instance.new("Beam")
            beam.Name = "RouteSegment_" .. tostring(index)
            beam.Attachment0 = a0
            beam.Attachment1 = a1
            beam.FaceCamera = true
            beam.Segments = 1
            beam.Width0 = State.RouteThickness
            beam.Width1 = State.RouteThickness
            beam.Transparency = NumberSequence.new(State.RouteTransparency)
            beam.LightEmission = 0.35
            beam.Color = ColorSequence.new(State.RouteRainbow and R.rainbow(index * 0.08) or State.RouteColor)
            beam.Parent = R.RouteFolder
            table.insert(R.RouteBeams, beam)
            return beam
        end

        R.rebuildRoute = function()
            R.clearRoute()
            if not State.RouteEnabled then return end

            local route = R.routeList()
            if #route == 0 then return end

            local previousAttachment = nil
            if State.RouteStartFromPlayer then
                previousAttachment = R.RouteStartAttachment
            end

            for index, waypoint in ipairs(route) do
                local marker = R.Markers[waypoint.Id]
                if marker and marker.Attachment then
                    if previousAttachment then
                        R.newBeam(previousAttachment, marker.Attachment, index)
                    end
                    previousAttachment = marker.Attachment
                end
            end
        end

        R.clearMarkers = function()
            R.clearRoute()
            for _, marker in pairs(R.Markers) do
                pcall(function() marker.Part:Destroy() end)
            end
            table.clear(R.Markers)
        end

        R.createMarker = function(waypoint)
            local part = Instance.new("Part")
            part.Name = "Waypoint_" .. tostring(waypoint.Name or waypoint.Id)
            part.Size = Vector3.new(0.18, 0.18, 0.18)
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.CastShadow = false
            part.Transparency = 1
            part.CFrame = CFrame.new(tonumber(waypoint.X) or 0, tonumber(waypoint.Y) or 0, tonumber(waypoint.Z) or 0)
            part.Parent = R.Folder

            local attachment = Instance.new("Attachment")
            attachment.Name = "WaypointAttachment"
            attachment.Parent = part

            local iconGui = Instance.new("BillboardGui")
            iconGui.Name = "WaypointIcon"
            iconGui.Adornee = part
            iconGui.AlwaysOnTop = State.AlwaysOnTop
            iconGui.LightInfluence = 0
            iconGui.StudsOffsetWorldSpace = Vector3.new(0, 0.65, 0)
            pcall(function() iconGui.MaxDistance = State.MaxRenderDistance end)
            iconGui.Parent = part
            local icon, colored = R.makeIcon(iconGui, State.Shape, State.Color)

            local card = Instance.new("BillboardGui")
            card.Name = "WaypointCard"
            card.Adornee = part
            card.AlwaysOnTop = State.AlwaysOnTop
            card.LightInfluence = 0
            card.Size = UDim2.fromOffset(285, 60)
            card.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
            pcall(function() card.MaxDistance = State.MaxRenderDistance end)
            card.Parent = part

            local bg = Instance.new("Frame")
            bg.Name = "Background"
            bg.Size = UDim2.fromScale(1, 1)
            bg.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
            bg.BackgroundTransparency = 0.16
            bg.BorderSizePixel = 0
            bg.Parent = card
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = bg
            local stroke = Instance.new("UIStroke")
            stroke.Thickness = 1.35
            stroke.Transparency = 0.16
            stroke.Color = State.Color
            stroke.Parent = bg

            local label = Instance.new("TextLabel")
            label.Name = "Text"
            label.BackgroundTransparency = 1
            label.Position = UDim2.fromOffset(9, 5)
            label.Size = UDim2.new(1, -18, 1, -10)
            label.Font = Enum.Font.Code
            label.TextSize = 13
            label.TextStrokeTransparency = 0.48
            label.TextWrapped = true
            label.TextColor3 = State.Color
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.Parent = bg

            local marker = {
                Part = part,
                Attachment = attachment,
                IconGui = iconGui,
                Icon = icon,
                Colored = colored,
                Card = card,
                Stroke = stroke,
                Label = label,
                Waypoint = waypoint,
            }
            R.Markers[waypoint.Id] = marker
            return marker
        end

        R.refreshMarkers = function()
            R.clearMarkers()
            for _, waypoint in ipairs(R.activeList()) do
                R.createMarker(waypoint)
            end
            R.rebuildRoute()
        end

        R.routeMetrics = function()
            local route = R.routeList()
            local root = R.getRoot()
            local total = 0
            local previous = nil

            if State.RouteStartFromPlayer and root and #route > 0 then
                previous = root.Position
            end

            for _, waypoint in ipairs(route) do
                local current = Vector3.new(tonumber(waypoint.X) or 0, tonumber(waypoint.Y) or 0, tonumber(waypoint.Z) or 0)
                if previous then
                    total += R.horizontalDistance(previous, current)
                end
                previous = current
            end

            local speed = R.getWalkSpeed()
            local eta = speed > 0 and (total / speed) or math.huge
            return total, eta, #route
        end

        R.updateRoute = function()
            local root = R.getRoot()
            if root then
                R.RouteStartPart.CFrame = CFrame.new(root.Position)
            end

            local routeColor = State.RouteColor
            for index, beam in ipairs(R.RouteBeams) do
                if beam and beam.Parent then
                    local color = State.RouteRainbow and R.rainbow(index * 0.08) or routeColor
                    beam.Color = ColorSequence.new(color)
                    beam.Width0 = State.RouteThickness
                    beam.Width1 = State.RouteThickness
                    beam.Transparency = NumberSequence.new(State.RouteTransparency)
                end
            end

            local total, eta, count = R.routeMetrics()
            R.RouteCard.Visible = State.RouteEnabled and State.RouteHUD and count > 0
            if R.RouteCard.Visible then
                local color = State.RouteRainbow and R.rainbow(0) or State.RouteColor
                R.RouteStroke.Color = color
                R.RouteLabel.TextColor3 = color
                R.RouteLabel.Text = string.format("ROUTE • %s\n%d points  •  %.0f studs  •  ETA %s", State.ActiveProfile, count, total, R.formatETA(eta))
            end
        end

        R.updateMarkers = function()
            local root = R.getRoot()
            local speed = R.getWalkSpeed()
            local routeIndex = {}
            if State.RouteEnabled then
                for index, waypoint in ipairs(R.routeList()) do
                    routeIndex[waypoint.Id] = index
                end
            end

            for id, marker in pairs(R.Markers) do
                local waypoint = marker.Waypoint
                if not waypoint or not marker.Part or not marker.Part.Parent then
                    R.Markers[id] = nil
                else
                    local selected = id == State.SelectedId
                    local color = selected and State.SelectedColor or State.Color
                    local show = State.ShowAll or selected
                    local scale = State.MarkerSize * (selected and 1.18 or 1)
                    local px = math.max(18, math.floor(48 * scale))

                    marker.IconGui.Enabled = show
                    marker.Card.Enabled = show and State.ShowCards
                    marker.IconGui.AlwaysOnTop = State.AlwaysOnTop
                    marker.Card.AlwaysOnTop = State.AlwaysOnTop
                    pcall(function() marker.IconGui.MaxDistance = State.MaxRenderDistance end)
                    pcall(function() marker.Card.MaxDistance = State.MaxRenderDistance end)
                    marker.IconGui.Size = UDim2.fromOffset(px, px)
                    R.setColored(marker.Colored, color)
                    marker.Stroke.Color = color
                    marker.Label.TextColor3 = color

                    if marker.Card.Enabled then
                        local position = marker.Part.Position
                        local distance = root and R.horizontalDistance(root.Position, position) or 0
                        local eta = speed > 0 and (distance / speed) or math.huge
                        local pieces = {}
                        if State.ShowDistance then pieces[#pieces + 1] = string.format("%.0f studs", distance) end
                        if State.ShowETA then pieces[#pieces + 1] = "ETA " .. R.formatETA(eta) end
                        pieces[#pieces + 1] = string.format("WS %.1f", speed)
                        local routePrefix = routeIndex[id] and ("#" .. tostring(routeIndex[id]) .. "  ") or ""
                        marker.Label.Text = string.format("%s%s%s\n%s", selected and "◆ " or "", routePrefix, tostring(waypoint.Name or "Waypoint"), table.concat(pieces, "  •  "))
                    end
                end
            end

            R.updateRoute()
        end

        R.refreshLists = function()
            if R.ProfileSection then
                R.clearDynamic(R.DynamicProfileControls)
                local names = {}
                for name in pairs(State.Profiles) do names[#names + 1] = name end
                table.sort(names)
                for index, profileName in ipairs(names) do
                    if index > 40 then break end
                    local button = R.ProfileSection:AddButton({
                        Name = (profileName == State.ActiveProfile and "● " or "") .. profileName,
                        ButtonText = "Use",
                        RequiredGraphics = "Low",
                        Description = "Switches the active waypoint profile. Profiles keep independent waypoint lists for different games, maps or routes.",
                        FPSImpact = 0,
                        PingImpact = 0,
                        Callback = function()
                            State.ActiveProfile = profileName
                            State.SelectedId = nil
                            R.refreshMarkers()
                            R.refreshLists()
                            R.save()
                            Context.Bus:Emit("WaypointProfileChanged", profileName)
                        end,
                    })
                    R.DynamicProfileControls[#R.DynamicProfileControls + 1] = button
                end
            end

            if R.ListSection then
                R.clearDynamic(R.DynamicWaypointControls)
                for index, waypoint in ipairs(R.activeList()) do
                    if index > 80 then break end
                    local button = R.ListSection:AddButton({
                        Name = (waypoint.Id == State.SelectedId and "● " or "") .. string.format("%02d  %s", index, tostring(waypoint.Name or "Waypoint")),
                        ButtonText = "Select",
                        RequiredGraphics = "Low",
                        Description = string.format("Waypoint position: %.1f, %.1f, %.1f", tonumber(waypoint.X) or 0, tonumber(waypoint.Y) or 0, tonumber(waypoint.Z) or 0),
                        FPSImpact = 0,
                        PingImpact = 0,
                        Callback = function()
                            State.SelectedId = waypoint.Id
                            State.RenameText = tostring(waypoint.Name or "Waypoint")
                            if R.RenameControl and type(R.RenameControl.Set) == "function" then
                                pcall(function() R.RenameControl:Set(State.RenameText, true) end)
                            end
                            R.refreshLists()
                            R.updateMarkers()
                            Context.Bus:Emit("WaypointSelected", waypoint, State.ActiveProfile)
                        end,
                    })
                    R.DynamicWaypointControls[#R.DynamicWaypointControls + 1] = button
                end
            end
        end

        R.addWaypoint = function(name, position)
            if typeof(position) ~= "Vector3" then return nil end
            local list = R.activeList()
            name = R.trim(name)
            if name == "" then name = "Waypoint " .. tostring(#list + 1) end
            local waypoint = {
                Id = R.newId(),
                Name = name,
                X = position.X,
                Y = position.Y,
                Z = position.Z,
            }
            list[#list + 1] = waypoint
            State.SelectedId = waypoint.Id
            State.RenameText = waypoint.Name
            R.refreshMarkers()
            R.refreshLists()
            R.save()
            Context.Bus:Emit("WaypointAdded", waypoint, State.ActiveProfile)
            return waypoint
        end

        R.nextFastName = function()
            local highest = 0
            for _, waypoint in ipairs(R.activeList()) do
                local n = tostring(waypoint.Name or ""):match("^Fast Waypoint (%d+)$")
                if n then highest = math.max(highest, tonumber(n) or 0) end
            end
            return "Fast Waypoint " .. tostring(highest + 1)
        end

        R.addFast = function()
            local root = R.getRoot()
            if root then
                return R.addWaypoint(R.nextFastName(), root.Position)
            end
            return nil
        end

        R.deleteSelected = function()
            local waypoint, index = R.getWaypoint(State.SelectedId)
            if not waypoint or not index then return end
            table.remove(R.activeList(), index)
            State.SelectedId = nil
            R.refreshMarkers()
            R.refreshLists()
            R.save()
            Context.Bus:Emit("WaypointRemoved", waypoint, State.ActiveProfile)
        end

        R.renameSelected = function(name)
            local waypoint = R.getWaypoint(State.SelectedId)
            name = R.trim(name)
            if waypoint and name ~= "" then
                local old = waypoint.Name
                waypoint.Name = name
                State.RenameText = name
                R.refreshMarkers()
                R.refreshLists()
                R.save()
                Context.Bus:Emit("WaypointRenamed", waypoint, old, name, State.ActiveProfile)
            end
        end

        R.cycle = function(direction)
            local list = R.activeList()
            if #list == 0 then return end
            local current = 0
            local _, selectedIndex = R.getWaypoint(State.SelectedId)
            if selectedIndex then current = selectedIndex end
            if direction > 0 then
                current = current % #list + 1
            else
                current = ((current - 2) % #list) + 1
            end
            State.SelectedId = list[current].Id
            State.RenameText = tostring(list[current].Name or "Waypoint")
            if R.RenameControl and type(R.RenameControl.Set) == "function" then
                pcall(function() R.RenameControl:Set(State.RenameText, true) end)
            end
            R.refreshLists()
            R.updateMarkers()
            Context.Bus:Emit("WaypointSelected", list[current], State.ActiveProfile)
        end

        R.moveSelected = function(direction)
            local list = R.activeList()
            local _, index = R.getWaypoint(State.SelectedId)
            if not index then return end
            local target = math.clamp(index + direction, 1, #list)
            if target == index then return end
            list[index], list[target] = list[target], list[index]
            R.refreshMarkers()
            R.refreshLists()
            R.save()
        end

        R.createProfile = function(name)
            name = R.trim(name)
            if name == "" then return end
            R.ensureProfile(name)
            State.ActiveProfile = name
            State.SelectedId = nil
            R.refreshMarkers()
            R.refreshLists()
            R.save()
            Context.Bus:Emit("WaypointProfileChanged", name)
        end

        R.deleteProfile = function()
            local active = State.ActiveProfile
            State.Profiles[active] = nil
            local fallback = nil
            for name in pairs(State.Profiles) do fallback = name break end
            if not fallback then
                fallback = "Place_" .. tostring(game.PlaceId)
                R.ensureProfile(fallback)
            end
            State.ActiveProfile = fallback
            State.SelectedId = nil
            R.refreshMarkers()
            R.refreshLists()
            R.save()
            Context.Bus:Emit("WaypointProfileChanged", fallback)
        end

        R.quickModifierHeld = function()
            if State.QuickModifier == "None" then return true end
            local key = Enum.KeyCode[State.QuickModifier]
            return key and UIS:IsKeyDown(key) or false
        end

        R.captureXYZ = function()
            local root = R.getRoot()
            if not root then return end
            State.ManualX = string.format("%.3f", root.Position.X)
            State.ManualY = string.format("%.3f", root.Position.Y)
            State.ManualZ = string.format("%.3f", root.Position.Z)
            if R.XControl and type(R.XControl.Set) == "function" then pcall(function() R.XControl:Set(State.ManualX, true) end) end
            if R.YControl and type(R.YControl.Set) == "function" then pcall(function() R.YControl:Set(State.ManualY, true) end) end
            if R.ZControl and type(R.ZControl.Set) == "function" then pcall(function() R.ZControl:Set(State.ManualZ, true) end) end
        end

        R.load()
        R.ensureProfile(State.ActiveProfile)

        Scope:TrackConnection(UIS.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed or UIS:GetFocusedTextBox() then return end
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if input.KeyCode.Name == State.QuickKey and R.quickModifierHeld() then
                R.addFast()
            end
        end))

        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            R.UpdateAccumulator += dt
            if R.UpdateAccumulator >= 0.20 then
                R.UpdateAccumulator = 0
                R.updateMarkers()
            end
        end))

        local Quick = Context:CreateSection(Scope, Tab, "Quick Waypoints", false, "Waypoints / Quick")
        Quick:AddChoice({Name="Quick Modifier",Flag="Waypoints_QuickModifier",Values={"None","LeftAlt","RightAlt","LeftControl","RightControl","LeftShift","RightShift"},Default=State.QuickModifier,RequiredGraphics="Low",Callback=function(v) State.QuickModifier=v end})
        Quick:AddChoice({Name="Quick Waypoint Key",Flag="Waypoints_QuickKey",Values={"P","O","I","U","Y","K","L","M","N","B","V","G","H","J"},Default=State.QuickKey,RequiredGraphics="Low",Description="Press this key while the selected modifier is held to create Fast Waypoint 1, Fast Waypoint 2 and so on at your current position.",FPSImpact=0,PingImpact=0,Callback=function(v) State.QuickKey=v end})
        Quick:AddButton({Name="Create Fast Waypoint",ButtonText="Create",RequiredGraphics="Low",Callback=function() R.addFast() end})
        Quick:AddButton({Name="Previous Waypoint",ButtonText="Previous",RequiredGraphics="Low",Callback=function() R.cycle(-1) end})
        Quick:AddButton({Name="Next Waypoint",ButtonText="Next",RequiredGraphics="Low",Callback=function() R.cycle(1) end})

        local Manual = Context:CreateSection(Scope, Tab, "Manual Add", false, "Waypoints / Manual")
        Manual:AddInput({Name="Waypoint Name",Flag="Waypoints_ManualName",Default=State.ManualName,Placeholder="Waypoint name",RequiredGraphics="Low",Callback=function(v) State.ManualName=tostring(v or "") end})
        Manual:AddButton({Name="Add At Current Position",ButtonText="Add",RequiredGraphics="Low",Callback=function() local root=R.getRoot() if root then R.addWaypoint(State.ManualName,root.Position) end end})
        Manual:AddButton({Name="Capture Current XYZ",ButtonText="Capture",RequiredGraphics="Low",Callback=function() R.captureXYZ() end})
        R.XControl = Manual:AddInput({Name="X",Flag="Waypoints_X",Default=State.ManualX,Placeholder="0",RequiredGraphics="Low",Callback=function(v) State.ManualX=tostring(v or "0") end})
        R.YControl = Manual:AddInput({Name="Y",Flag="Waypoints_Y",Default=State.ManualY,Placeholder="0",RequiredGraphics="Low",Callback=function(v) State.ManualY=tostring(v or "0") end})
        R.ZControl = Manual:AddInput({Name="Z",Flag="Waypoints_Z",Default=State.ManualZ,Placeholder="0",RequiredGraphics="Low",Callback=function(v) State.ManualZ=tostring(v or "0") end})
        Manual:AddButton({Name="Add XYZ Waypoint",ButtonText="Add XYZ",RequiredGraphics="Low",Callback=function()
            local x,y,z=tonumber(State.ManualX),tonumber(State.ManualY),tonumber(State.ManualZ)
            if x and y and z then R.addWaypoint(State.ManualName,Vector3.new(x,y,z)) end
        end})

        local Selected = Context:CreateSection(Scope, Tab, "Selected Waypoint", false, "Waypoints / Selected")
        R.RenameControl = Selected:AddInput({Name="Rename",Flag="Waypoints_Rename",Default=State.RenameText,Placeholder="select a waypoint",RequiredGraphics="Low",Callback=function(v) State.RenameText=tostring(v or "") end})
        Selected:AddButton({Name="Apply Rename",ButtonText="Rename",RequiredGraphics="Low",Callback=function() R.renameSelected(State.RenameText) end})
        Selected:AddButton({Name="Move Earlier In Route",ButtonText="Move Up",RequiredGraphics="Low",Description="Moves the selected waypoint one position earlier in the active profile. Route order follows profile order.",Callback=function() R.moveSelected(-1) end})
        Selected:AddButton({Name="Move Later In Route",ButtonText="Move Down",RequiredGraphics="Low",Callback=function() R.moveSelected(1) end})
        Selected:AddButton({Name="Delete Selected",ButtonText="Delete",RequiredGraphics="Low",Callback=function() R.deleteSelected() end})

        local Style = Context:CreateSection(Scope, Tab, "Marker Style", false, "Waypoints / Style")
        Style:AddToggle({Name="Show Waypoints",Flag="Waypoints_ShowAll",Default=State.ShowAll,RequiredGraphics="Low",Description="Shows all waypoint markers in the active profile. The selected waypoint remains visible when this is disabled.",FPSImpact={-3,0},PingImpact=0,Callback=function(v) State.ShowAll=v R.updateMarkers() end})
        Style:AddToggle({Name="Show Info Cards",Flag="Waypoints_ShowCards",Default=State.ShowCards,RequiredGraphics="Low",Callback=function(v) State.ShowCards=v R.updateMarkers() end})
        Style:AddToggle({Name="Show Distance",Flag="Waypoints_ShowDistance",Default=State.ShowDistance,RequiredGraphics="Low",Callback=function(v) State.ShowDistance=v end})
        Style:AddToggle({Name="Show ETA",Flag="Waypoints_ShowETA",Default=State.ShowETA,RequiredGraphics="Low",Description="ETA is horizontal waypoint distance divided by the current Humanoid.WalkSpeed. It is an estimate, not pathfinding time.",Callback=function(v) State.ShowETA=v end})
        Style:AddToggle({Name="Always On Top",Flag="Waypoints_AlwaysOnTop",Default=State.AlwaysOnTop,RequiredGraphics="Low",Callback=function(v) State.AlwaysOnTop=v R.updateMarkers() end})
        Style:AddChoice({Name="Marker Shape",Flag="Waypoints_Shape",Values={"Ring","Circle","Square","Diamond","Cross","Triangle","Pin","Star","Beacon"},Default=State.Shape,RequiredGraphics="Low",Callback=function(v) State.Shape=v R.refreshMarkers() end})
        Style:AddSlider({Name="Marker Size",Flag="Waypoints_Size",Min=0.5,Max=2.5,Default=State.MarkerSize,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.MarkerSize=v end})
        Style:AddSlider({Name="Max Render Distance",Flag="Waypoints_MaxDistance",Min=0,Max=10000,Default=State.MaxRenderDistance,Decimals=0,RequiredGraphics="Low",Description="Billboard render limit in studs. 0 keeps Roblox's unlimited/default behavior.",Callback=function(v) State.MaxRenderDistance=v R.updateMarkers() end})
        Style:AddColorPicker({Name="Waypoint Color",Flag="Waypoints_Color",Default=State.Color,RequiredGraphics="Low",Callback=function(v) State.Color=v end})
        Style:AddColorPicker({Name="Selected Color",Flag="Waypoints_SelectedColor",Default=State.SelectedColor,RequiredGraphics="Low",Callback=function(v) State.SelectedColor=v end})

        local Route = Context:CreateSection(Scope, Tab, "Waypoint Route", false, "Waypoints / Route")
        Route:AddToggle({Name="Route Lines",Flag="Waypoints_Route",Default=State.RouteEnabled,RequiredGraphics="Medium",Description="Connects ordered waypoint markers with 3D Beam segments. Route order is the order shown in the active profile list.",FPSImpact={-4,0},PingImpact=0,Callback=function(v) State.RouteEnabled=v R.rebuildRoute() R.updateRoute() end})
        Route:AddChoice({Name="Route Mode",Flag="Waypoints_RouteMode",Values={"Profile Order","Selected Forward"},Default=State.RouteMode,RequiredGraphics="Low",Description="Profile Order uses every waypoint. Selected Forward starts the route at the currently selected waypoint.",Callback=function(v) State.RouteMode=v R.rebuildRoute() end})
        Route:AddToggle({Name="Start Route From Player",Flag="Waypoints_RouteFromPlayer",Default=State.RouteStartFromPlayer,RequiredGraphics="Low",Description="Adds a live route segment from your current position to the first route point and includes that distance in total ETA.",Callback=function(v) State.RouteStartFromPlayer=v R.rebuildRoute() end})
        Route:AddToggle({Name="Route HUD",Flag="Waypoints_RouteHUD",Default=State.RouteHUD,RequiredGraphics="Low",Callback=function(v) State.RouteHUD=v R.updateRoute() end})
        Route:AddColorPicker({Name="Route Color",Flag="Waypoints_RouteColor",Default=State.RouteColor,RequiredGraphics="Low",Callback=function(v) State.RouteColor=v end})
        Route:AddToggle({Name="Rainbow Route",Flag="Waypoints_RouteRainbow",Default=State.RouteRainbow,RequiredGraphics="Medium",Callback=function(v) State.RouteRainbow=v end})
        Route:AddSlider({Name="Route RGB Speed",Flag="Waypoints_RouteRGBSpeed",Min=0.02,Max=1.5,Default=State.RouteRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.RouteRainbowSpeed=v end})
        Route:AddSlider({Name="Route Thickness",Flag="Waypoints_RouteThickness",Min=0.03,Max=0.7,Default=State.RouteThickness,Decimals=2,RequiredGraphics="Medium",Callback=function(v) State.RouteThickness=v end})
        Route:AddSlider({Name="Route Transparency",Flag="Waypoints_RouteTransparency",Min=0,Max=0.95,Default=State.RouteTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.RouteTransparency=v end})

        local Profiles = Context:CreateSection(Scope, Tab, "Profiles", false, "Waypoints / Profiles")
        Profiles:AddInput({Name="New Profile Name",Flag="Waypoints_NewProfile",Default=State.NewProfileName,Placeholder="MM2 / Doors / Rivals...",RequiredGraphics="Low",Callback=function(v) State.NewProfileName=tostring(v or "") end})
        Profiles:AddButton({Name="Create Profile",ButtonText="Create / Use",RequiredGraphics="Low",Description="Creates a separate waypoint profile or switches to it if it already exists.",FPSImpact=0,PingImpact=0,Callback=function() R.createProfile(State.NewProfileName) end})
        Profiles:AddButton({Name="Use Current Place Profile",ButtonText="Place Profile",RequiredGraphics="Low",Callback=function() R.createProfile("Place_"..tostring(game.PlaceId)) end})
        Profiles:AddButton({Name="Delete Active Profile",ButtonText="Delete Profile",RequiredGraphics="Low",Callback=function() R.deleteProfile() end})
        Profiles:AddButton({Name="Save Waypoints",ButtonText="Save",RequiredGraphics="Low",Callback=function() R.save() end})
        Profiles:AddButton({Name="Reload Waypoints File",ButtonText="Reload",RequiredGraphics="Low",Callback=function() R.load() R.refreshMarkers() R.refreshLists() end})

        R.ProfileSection = Context:CreateSection(Scope, Tab, "Profile List", false, "Waypoints / Profile List")
        R.ListSection = Context:CreateSection(Scope, Tab, "Waypoint List", false, "Waypoints / List")

        R.refreshMarkers()
        R.refreshLists()
        R.updateMarkers()

        R.API = {
            Add = function(name, position) return R.addWaypoint(name, position) end,
            AddFast = function() return R.addFast() end,
            GetActiveProfile = function() return State.ActiveProfile end,
            GetActiveList = function() return R.activeList() end,
            GetSelected = function() return R.getWaypoint(State.SelectedId) end,
            Select = function(id) State.SelectedId=id R.refreshLists() R.updateMarkers() end,
            Save = function() return R.save() end,
            Refresh = function() R.refreshMarkers() R.refreshLists() end,
        }
        Context.Shared.Waypoints = R.API

        Scope:AddCleaner(function()
            R.clearDynamic(R.DynamicProfileControls)
            R.clearDynamic(R.DynamicWaypointControls)
            R.clearMarkers()
            if Context.Shared.Waypoints == R.API then
                Context.Shared.Waypoints = nil
            end
        end)
    end,
}
