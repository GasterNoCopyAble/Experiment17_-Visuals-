--[[
    Experiment 17 - Visual module
    Target: Experiment17 modular Loader v0.2+

    Features:
      * High-layer custom cursor + RGB + shape-preserving trail
      * Custom cursor image asset ID
      * Map material / color / texture overrides with independent restoration
      * Force texture reload (same asset can be applied again)
      * Shader-style screen FX: tint, vignette, scanlines, grain, letterbox

    This module only changes the local client's presentation.
]]

return {
    Id = "Visual",
    Name = "Visual",
    Version = "1.0.0",
    Order = 10,

    Init = function(Context, Scope, Tab)
        local Services = Context.Services
        local Workspace = Services.Workspace
        local RunService = Services.RunService
        local UIS = Services.UIS
        local Player = Context.LocalPlayer
        local PlayerGui = Player:WaitForChild("PlayerGui")

        local State = Context:GetState("Visual", {
            CursorEnabled = false,
            CursorType = "Cross",
            CursorColor = Color3.fromRGB(180, 110, 255),
            CursorSize = 18,
            CursorGap = 4,
            CursorThickness = 2,
            CursorRainbow = false,
            CursorRainbowSpeed = 0.35,
            CursorImage = "",
            CursorTrail = false,
            CursorTrailLength = 12,
            CursorTrailSpacing = 5,

            MaterialOverride = false,
            Material = "SmoothPlastic",
            ColorOverride = false,
            MapColor = Color3.fromRGB(180, 180, 180),
            TextureOverride = false,
            TextureId = "",
            ScanBatch = 250,

            ScreenFX = false,
            ScreenPreset = "Custom",
            ScreenTint = Color3.fromRGB(255, 255, 255),
            ScreenTintTransparency = 0.94,
            ScreenRainbow = false,
            ScreenRainbowSpeed = 0.18,
            Vignette = false,
            VignetteStrength = 0.45,
            Scanlines = false,
            ScanlineTransparency = 0.82,
            ScanlineSpacing = 5,
            Grain = false,
            GrainStrength = 0.88,
            Letterbox = false,
            LetterboxSize = 8,
        })

        local Runtime = {
            OriginalMouseIcon = UIS.MouseIconEnabled,
            CursorRoots = {},
            CursorColorables = setmetatable({}, {__mode = "k"}),
            CursorHistory = {},
            LastCursorSample = nil,
            LastCursorSampleAt = 0,
            MaterialBaseline = setmetatable({}, {__mode = "k"}),
            ColorBaseline = setmetatable({}, {__mode = "k"}),
            TextureBaseline = setmetatable({}, {__mode = "k"}),
            ScanToken = 0,
            TextureReloadToken = 0,
            ScanlineObjects = {},
            GrainObjects = {},
            Controls = {},
            Dead = false,
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
            if value:match("^rbxasset://") or value:match("^rbxthumb://") then
                return value
            end
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

        local function silentSet(control, value)
            if control and type(control.Set) == "function" then
                pcall(function() control:Set(value, true) end)
            end
        end

        --====================================================
        -- CURSOR
        --====================================================

        local baseDisplayOrder = 999999
        if Context.Library and Context.Library.Root then
            baseDisplayOrder = safeGet(Context.Library.Root, "DisplayOrder", baseDisplayOrder)
        end

        local CursorGui = Scope:TrackInstance(Instance.new("ScreenGui"))
        CursorGui.Name = "Experiment17_Visual_Cursor"
        CursorGui.IgnoreGuiInset = true
        CursorGui.ResetOnSpawn = false
        CursorGui.DisplayOrder = baseDisplayOrder + 100
        CursorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        CursorGui.Parent = PlayerGui

        local CursorRoot = Instance.new("CanvasGroup")
        CursorRoot.Name = "CursorRoot"
        CursorRoot.AnchorPoint = Vector2.new(0.5, 0.5)
        CursorRoot.BackgroundTransparency = 1
        CursorRoot.Size = UDim2.fromOffset(96, 96)
        CursorRoot.ZIndex = 500
        CursorRoot.Visible = false
        CursorRoot.Parent = CursorGui
        Runtime.CursorRoots[1] = CursorRoot

        for index = 1, 30 do
            local root = Instance.new("CanvasGroup")
            root.Name = "Trail_" .. index
            root.AnchorPoint = Vector2.new(0.5, 0.5)
            root.BackgroundTransparency = 1
            root.Size = UDim2.fromOffset(96, 96)
            root.ZIndex = 450 - index
            root.Visible = false
            root.Parent = CursorGui
            Runtime.CursorRoots[#Runtime.CursorRoots + 1] = root
        end

        local function clearShape(root)
            for _, child in ipairs(root:GetChildren()) do
                child:Destroy()
            end
            Runtime.CursorColorables[root] = {}
        end

        local function registerColorable(root, object, property)
            Runtime.CursorColorables[root] = Runtime.CursorColorables[root] or {}
            table.insert(Runtime.CursorColorables[root], {Object = object, Property = property})
        end

        local function cursorColor()
            if State.CursorRainbow then
                return rainbowColor(State.CursorRainbowSpeed, 0, 0.92, 1)
            end
            return State.CursorColor
        end

        local function addFrame(root, size, position, rotation, circle, transparency)
            local frame = Instance.new("Frame")
            frame.AnchorPoint = Vector2.new(0.5, 0.5)
            frame.BorderSizePixel = 0
            frame.BackgroundColor3 = cursorColor()
            frame.BackgroundTransparency = transparency or 0
            frame.Size = size
            frame.Position = position
            frame.Rotation = rotation or 0
            frame.ZIndex = root.ZIndex + 1
            frame.Parent = root
            if circle then
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(1, 0)
                corner.Parent = frame
            end
            registerColorable(root, frame, "BackgroundColor3")
            return frame
        end

        local function addStroke(root, target, thickness)
            local stroke = Instance.new("UIStroke")
            stroke.Thickness = thickness or 1
            stroke.Color = cursorColor()
            stroke.Parent = target
            registerColorable(root, stroke, "Color")
            return stroke
        end

        local function buildCursorShape(root)
            clearShape(root)

            local cursorType = State.CursorType
            local size = State.CursorSize
            local gap = State.CursorGap
            local thickness = State.CursorThickness
            local center = 48
            local C = function(x, y) return UDim2.fromOffset(center + x, center + y) end

            if cursorType == "Dot" then
                addFrame(root, UDim2.fromOffset(math.max(3, thickness * 2.6), math.max(3, thickness * 2.6)), C(0, 0), 0, true)

            elseif cursorType == "Circle" or cursorType == "Ring + Dot" then
                local ring = Instance.new("Frame")
                ring.AnchorPoint = Vector2.new(0.5, 0.5)
                ring.BackgroundTransparency = 1
                ring.Size = UDim2.fromOffset(size, size)
                ring.Position = C(0, 0)
                ring.ZIndex = root.ZIndex + 1
                ring.Parent = root
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(1, 0)
                corner.Parent = ring
                addStroke(root, ring, thickness)
                if cursorType == "Ring + Dot" then
                    addFrame(root, UDim2.fromOffset(math.max(3, thickness * 2), math.max(3, thickness * 2)), C(0, 0), 0, true)
                end

            elseif cursorType == "X" then
                addFrame(root, UDim2.fromOffset(size, thickness), C(0, 0), 45)
                addFrame(root, UDim2.fromOffset(size, thickness), C(0, 0), -45)

            elseif cursorType == "Plus" then
                addFrame(root, UDim2.fromOffset(size, thickness), C(0, 0), 0)
                addFrame(root, UDim2.fromOffset(thickness, size), C(0, 0), 0)

            elseif cursorType == "Cross + Dot" then
                local half = math.max(2, (size - gap * 2) * 0.5)
                addFrame(root, UDim2.fromOffset(half, thickness), C(-gap - half * 0.5, 0))
                addFrame(root, UDim2.fromOffset(half, thickness), C(gap + half * 0.5, 0))
                addFrame(root, UDim2.fromOffset(thickness, half), C(0, -gap - half * 0.5))
                addFrame(root, UDim2.fromOffset(thickness, half), C(0, gap + half * 0.5))
                addFrame(root, UDim2.fromOffset(math.max(2, thickness * 1.8), math.max(2, thickness * 1.8)), C(0, 0), 0, true)

            elseif cursorType == "T" then
                addFrame(root, UDim2.fromOffset(size, thickness), C(0, -size * 0.15))
                addFrame(root, UDim2.fromOffset(thickness, size * 0.72), C(0, size * 0.2))

            elseif cursorType == "Diamond" then
                local box = addFrame(root, UDim2.fromOffset(math.max(7, size * 0.62), math.max(7, size * 0.62)), C(0, 0), 45, false, 0.65)
                addStroke(root, box, thickness)

            elseif cursorType == "Chevron" then
                addFrame(root, UDim2.fromOffset(size * 0.72, thickness), C(-size * 0.16, 0), 35)
                addFrame(root, UDim2.fromOffset(size * 0.72, thickness), C(size * 0.16, 0), -35)

            elseif cursorType == "Brackets" then
                local h = size * 0.72
                local w = size * 0.32
                addFrame(root, UDim2.fromOffset(thickness, h), C(-size * 0.48, 0))
                addFrame(root, UDim2.fromOffset(w, thickness), C(-size * 0.35, -h * 0.5))
                addFrame(root, UDim2.fromOffset(w, thickness), C(-size * 0.35, h * 0.5))
                addFrame(root, UDim2.fromOffset(thickness, h), C(size * 0.48, 0))
                addFrame(root, UDim2.fromOffset(w, thickness), C(size * 0.35, -h * 0.5))
                addFrame(root, UDim2.fromOffset(w, thickness), C(size * 0.35, h * 0.5))

            elseif cursorType == "Triangle" then
                addFrame(root, UDim2.fromOffset(size * 0.65, thickness), C(-size * 0.16, size * 0.12), 60)
                addFrame(root, UDim2.fromOffset(size * 0.65, thickness), C(size * 0.16, size * 0.12), -60)
                addFrame(root, UDim2.fromOffset(size * 0.62, thickness), C(0, size * 0.38), 0)

            elseif cursorType == "Image" then
                local image = Instance.new("ImageLabel")
                image.AnchorPoint = Vector2.new(0.5, 0.5)
                image.BackgroundTransparency = 1
                image.Size = UDim2.fromOffset(size * 1.75, size * 1.75)
                image.Position = C(0, 0)
                image.Image = State.CursorImage
                image.ImageColor3 = cursorColor()
                image.ScaleType = Enum.ScaleType.Fit
                image.ZIndex = root.ZIndex + 1
                image.Parent = root
                registerColorable(root, image, "ImageColor3")

            else -- Cross
                local half = math.max(2, (size - gap * 2) * 0.5)
                addFrame(root, UDim2.fromOffset(half, thickness), C(-gap - half * 0.5, 0))
                addFrame(root, UDim2.fromOffset(half, thickness), C(gap + half * 0.5, 0))
                addFrame(root, UDim2.fromOffset(thickness, half), C(0, -gap - half * 0.5))
                addFrame(root, UDim2.fromOffset(thickness, half), C(0, gap + half * 0.5))
            end
        end

        local function rebuildCursor()
            for _, root in ipairs(Runtime.CursorRoots) do
                buildCursorShape(root)
            end
        end

        local function applyCursorColor(root, color)
            local entries = Runtime.CursorColorables[root]
            if not entries then return end
            for _, entry in ipairs(entries) do
                local object = entry.Object
                if object and object.Parent then
                    safeSet(object, entry.Property, color)
                end
            end
        end

        local function clearCursorHistory()
            table.clear(Runtime.CursorHistory)
            Runtime.LastCursorSample = nil
            for index = 2, #Runtime.CursorRoots do
                Runtime.CursorRoots[index].Visible = false
            end
        end

        rebuildCursor()

        Scope:TrackConnection(RunService.RenderStepped:Connect(function()
            if Runtime.Dead then return end

            CursorRoot.Visible = State.CursorEnabled
            UIS.MouseIconEnabled = not State.CursorEnabled
            if not State.CursorEnabled then
                clearCursorHistory()
                return
            end

            local mouse = UIS:GetMouseLocation()
            CursorRoot.Position = UDim2.fromOffset(mouse.X, mouse.Y)
            local color = cursorColor()
            applyCursorColor(CursorRoot, color)

            if not State.CursorTrail then
                clearCursorHistory()
                return
            end

            local now = os.clock()
            local shouldSample = false
            if not Runtime.LastCursorSample then
                shouldSample = true
            else
                local delta = (mouse - Runtime.LastCursorSample).Magnitude
                shouldSample = delta >= State.CursorTrailSpacing or (now - Runtime.LastCursorSampleAt) >= 0.06
            end

            if shouldSample then
                Runtime.LastCursorSample = mouse
                Runtime.LastCursorSampleAt = now
                table.insert(Runtime.CursorHistory, 1, mouse)
                while #Runtime.CursorHistory > State.CursorTrailLength do
                    table.remove(Runtime.CursorHistory)
                end
            end

            for i = 1, 30 do
                local root = Runtime.CursorRoots[i + 1]
                local point = Runtime.CursorHistory[i]
                if point and i <= State.CursorTrailLength then
                    root.Visible = true
                    root.Position = UDim2.fromOffset(point.X, point.Y)
                    root.GroupTransparency = 0.15 + (i / math.max(1, State.CursorTrailLength)) * 0.82
                    local trailColor = State.CursorRainbow and rainbowColor(State.CursorRainbowSpeed, i * 0.012, 0.92, 1) or color
                    applyCursorColor(root, trailColor)
                else
                    root.Visible = false
                end
            end
        end))

        --====================================================
        -- MAP SURFACE OVERRIDES
        --====================================================

        local function isCharacterDescendant(object)
            local current = object
            while current and current ~= Workspace do
                if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
                    return true
                end
                current = current.Parent
            end
            return false
        end

        local function isMapObject(object)
            if not object or not object.Parent then return false end
            if object:IsDescendantOf(CursorGui) then return false end
            if object:FindFirstAncestorOfClass("Tool") then return false end
            if isCharacterDescendant(object) then return false end
            return object:IsA("BasePart")
                or object:IsA("Decal")
                or object:IsA("Texture")
                or object:IsA("SurfaceAppearance")
        end

        local function rememberMaterial(part)
            if not part:IsA("BasePart") or Runtime.MaterialBaseline[part] then return end
            Runtime.MaterialBaseline[part] = {
                Material = part.Material,
                MaterialVariant = safeGet(part, "MaterialVariant", ""),
            }
        end

        local function rememberColor(part)
            if not part:IsA("BasePart") or Runtime.ColorBaseline[part] ~= nil then return end
            Runtime.ColorBaseline[part] = part.Color
        end

        local function rememberTexture(object)
            if Runtime.TextureBaseline[object] then return end
            if object:IsA("MeshPart") then
                Runtime.TextureBaseline[object] = {Kind = "MeshPart", TextureID = object.TextureID}
            elseif object:IsA("Decal") or object:IsA("Texture") then
                Runtime.TextureBaseline[object] = {Kind = "Texture", Texture = object.Texture}
            elseif object:IsA("SurfaceAppearance") then
                Runtime.TextureBaseline[object] = {
                    Kind = "SurfaceAppearance",
                    ColorMap = safeGet(object, "ColorMap", ""),
                }
            end
        end

        local function applyMaterial(part)
            if not State.MaterialOverride or not part:IsA("BasePart") then return end
            rememberMaterial(part)
            local material = Enum.Material[State.Material] or Enum.Material.SmoothPlastic
            safeSet(part, "MaterialVariant", "")
            part.Material = material
        end

        local function applyColor(part)
            if not State.ColorOverride or not part:IsA("BasePart") then return end
            rememberColor(part)
            part.Color = State.MapColor
        end

        local function applyTexture(object)
            if not State.TextureOverride or State.TextureId == "" then return end
            rememberTexture(object)
            if object:IsA("MeshPart") then
                object.TextureID = State.TextureId
            elseif object:IsA("Decal") or object:IsA("Texture") then
                object.Texture = State.TextureId
            elseif object:IsA("SurfaceAppearance") then
                safeSet(object, "ColorMap", State.TextureId)
            end
        end

        local function applyMapObject(object)
            if not isMapObject(object) then return end
            if object:IsA("BasePart") then
                applyMaterial(object)
                applyColor(object)
                if object:IsA("MeshPart") then applyTexture(object) end
            else
                applyTexture(object)
            end
        end

        local function scanMap()
            Runtime.ScanToken = Runtime.ScanToken + 1
            local token = Runtime.ScanToken
            task.spawn(function()
                local descendants = Workspace:GetDescendants()
                local batch = math.max(50, math.floor(State.ScanBatch))
                for index, object in ipairs(descendants) do
                    if Runtime.Dead or token ~= Runtime.ScanToken then return end
                    applyMapObject(object)
                    if index % batch == 0 then task.wait() end
                end
            end)
        end

        local function restoreMaterials()
            Runtime.ScanToken = Runtime.ScanToken + 1
            for part, baseline in pairs(Runtime.MaterialBaseline) do
                if part and part.Parent then
                    pcall(function()
                        part.Material = baseline.Material
                        part.MaterialVariant = baseline.MaterialVariant or ""
                    end)
                end
            end
            table.clear(Runtime.MaterialBaseline)
        end

        local function restoreColors()
            for part, color in pairs(Runtime.ColorBaseline) do
                if part and part.Parent then
                    pcall(function() part.Color = color end)
                end
            end
            table.clear(Runtime.ColorBaseline)
        end

        local function restoreTextures()
            Runtime.TextureReloadToken = Runtime.TextureReloadToken + 1
            for object, baseline in pairs(Runtime.TextureBaseline) do
                if object and object.Parent then
                    pcall(function()
                        if baseline.Kind == "MeshPart" and object:IsA("MeshPart") then
                            object.TextureID = baseline.TextureID or ""
                        elseif baseline.Kind == "Texture" and (object:IsA("Decal") or object:IsA("Texture")) then
                            object.Texture = baseline.Texture or ""
                        elseif baseline.Kind == "SurfaceAppearance" and object:IsA("SurfaceAppearance") then
                            object.ColorMap = baseline.ColorMap or ""
                        end
                    end)
                end
            end
            table.clear(Runtime.TextureBaseline)
        end

        local function forceTextureReload()
            if not State.TextureOverride or State.TextureId == "" then return end
            Runtime.TextureReloadToken = Runtime.TextureReloadToken + 1
            local token = Runtime.TextureReloadToken
            local touched = {}

            task.spawn(function()
                local descendants = Workspace:GetDescendants()
                local batch = math.max(50, math.floor(State.ScanBatch))
                for index, object in ipairs(descendants) do
                    if Runtime.Dead or token ~= Runtime.TextureReloadToken then return end
                    if isMapObject(object) and (object:IsA("MeshPart") or object:IsA("Decal") or object:IsA("Texture") or object:IsA("SurfaceAppearance")) then
                        rememberTexture(object)
                        touched[#touched + 1] = object
                        pcall(function()
                            if object:IsA("MeshPart") then
                                object.TextureID = ""
                            elseif object:IsA("Decal") or object:IsA("Texture") then
                                object.Texture = ""
                            elseif object:IsA("SurfaceAppearance") then
                                object.ColorMap = ""
                            end
                        end)
                    end
                    if index % batch == 0 then task.wait() end
                end

                task.wait()
                if Runtime.Dead or token ~= Runtime.TextureReloadToken or not State.TextureOverride then return end
                for index, object in ipairs(touched) do
                    if object and object.Parent then
                        applyTexture(object)
                    end
                    if index % batch == 0 then task.wait() end
                end
            end)
        end

        Scope:TrackConnection(Workspace.DescendantAdded:Connect(function(object)
            if Runtime.Dead then return end
            if State.MaterialOverride or State.ColorOverride or State.TextureOverride then
                task.defer(function()
                    if object and object.Parent and not Runtime.Dead then
                        applyMapObject(object)
                    end
                end)
            end
        end))

        --====================================================
        -- SCREEN FX / SHADER-STYLE OVERLAY
        --====================================================

        local FXGui = Scope:TrackInstance(Instance.new("ScreenGui"))
        FXGui.Name = "Experiment17_Visual_ScreenFX"
        FXGui.IgnoreGuiInset = true
        FXGui.ResetOnSpawn = false
        FXGui.DisplayOrder = math.max(1, baseDisplayOrder - 20)
        FXGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        FXGui.Parent = PlayerGui

        local Tint = Instance.new("Frame")
        Tint.Name = "Tint"
        Tint.BorderSizePixel = 0
        Tint.Size = UDim2.fromScale(1, 1)
        Tint.BackgroundColor3 = State.ScreenTint
        Tint.BackgroundTransparency = 1
        Tint.ZIndex = 1
        Tint.Parent = FXGui

        local ScanlineLayer = Instance.new("Frame")
        ScanlineLayer.Name = "Scanlines"
        ScanlineLayer.BackgroundTransparency = 1
        ScanlineLayer.Size = UDim2.fromScale(1, 1)
        ScanlineLayer.ZIndex = 3
        ScanlineLayer.Parent = FXGui

        local GrainLayer = Instance.new("Frame")
        GrainLayer.Name = "Grain"
        GrainLayer.BackgroundTransparency = 1
        GrainLayer.Size = UDim2.fromScale(1, 1)
        GrainLayer.ZIndex = 4
        GrainLayer.Parent = FXGui

        local LetterTop = Instance.new("Frame")
        LetterTop.BorderSizePixel = 0
        LetterTop.BackgroundColor3 = Color3.new(0, 0, 0)
        LetterTop.AnchorPoint = Vector2.new(0, 0)
        LetterTop.Position = UDim2.fromScale(0, 0)
        LetterTop.ZIndex = 6
        LetterTop.Parent = FXGui

        local LetterBottom = LetterTop:Clone()
        LetterBottom.AnchorPoint = Vector2.new(0, 1)
        LetterBottom.Position = UDim2.fromScale(0, 1)
        LetterBottom.Parent = FXGui

        local VignetteLayer = Instance.new("Frame")
        VignetteLayer.Name = "Vignette"
        VignetteLayer.BackgroundTransparency = 1
        VignetteLayer.Size = UDim2.fromScale(1, 1)
        VignetteLayer.ZIndex = 5
        VignetteLayer.Parent = FXGui

        local VignetteEdges = {}
        local function makeVignetteEdge(name, size, position, rotation)
            local edge = Instance.new("Frame")
            edge.Name = name
            edge.BorderSizePixel = 0
            edge.BackgroundColor3 = Color3.new(0, 0, 0)
            edge.BackgroundTransparency = 0
            edge.Size = size
            edge.Position = position
            edge.ZIndex = 5
            edge.Parent = VignetteLayer
            local gradient = Instance.new("UIGradient")
            gradient.Rotation = rotation
            gradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            })
            gradient.Parent = edge
            VignetteEdges[#VignetteEdges + 1] = edge
        end

        makeVignetteEdge("Left", UDim2.fromScale(0.18, 1), UDim2.fromScale(0, 0), 0)
        makeVignetteEdge("Right", UDim2.fromScale(0.18, 1), UDim2.fromScale(0.82, 0), 180)
        makeVignetteEdge("Top", UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0), 90)
        makeVignetteEdge("Bottom", UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.82), -90)

        local function rebuildScanlines()
            for _, line in ipairs(Runtime.ScanlineObjects) do
                if line then line:Destroy() end
            end
            table.clear(Runtime.ScanlineObjects)

            local spacing = math.clamp(math.floor(State.ScanlineSpacing), 3, 16)
            local maxLines = math.ceil(1100 / spacing) + 8
            maxLines = math.min(maxLines, 280)
            for index = 0, maxLines do
                local line = Instance.new("Frame")
                line.BorderSizePixel = 0
                line.BackgroundColor3 = Color3.new(0, 0, 0)
                line.BackgroundTransparency = State.ScanlineTransparency
                line.Size = UDim2.new(1, 0, 0, 1)
                line.Position = UDim2.new(0, 0, 0, index * spacing)
                line.ZIndex = 3
                line.Parent = ScanlineLayer
                Runtime.ScanlineObjects[#Runtime.ScanlineObjects + 1] = line
            end
        end

        local function rebuildGrain()
            for _, dot in ipairs(Runtime.GrainObjects) do
                if dot then dot:Destroy() end
            end
            table.clear(Runtime.GrainObjects)
            for _ = 1, 48 do
                local dot = Instance.new("Frame")
                dot.BorderSizePixel = 0
                dot.BackgroundColor3 = Color3.new(1, 1, 1)
                dot.BackgroundTransparency = State.GrainStrength
                dot.Size = UDim2.fromOffset(math.random(1, 4), math.random(1, 4))
                dot.ZIndex = 4
                dot.Parent = GrainLayer
                Runtime.GrainObjects[#Runtime.GrainObjects + 1] = dot
            end
        end

        local function updateScreenFXStatic()
            local enabled = State.ScreenFX
            Tint.Visible = enabled
            ScanlineLayer.Visible = enabled and State.Scanlines
            GrainLayer.Visible = enabled and State.Grain
            VignetteLayer.Visible = enabled and State.Vignette
            LetterTop.Visible = enabled and State.Letterbox
            LetterBottom.Visible = enabled and State.Letterbox

            if not enabled then
                Tint.BackgroundTransparency = 1
                return
            end

            Tint.BackgroundColor3 = State.ScreenTint
            Tint.BackgroundTransparency = State.ScreenTintTransparency

            for _, edge in ipairs(VignetteEdges) do
                edge.BackgroundTransparency = 1 - math.clamp(State.VignetteStrength, 0, 1)
            end

            local letterScale = math.clamp(State.LetterboxSize, 0, 25) / 100
            LetterTop.Size = UDim2.fromScale(1, letterScale)
            LetterBottom.Size = UDim2.fromScale(1, letterScale)

            for _, line in ipairs(Runtime.ScanlineObjects) do
                if line and line.Parent then line.BackgroundTransparency = State.ScanlineTransparency end
            end
            for _, dot in ipairs(Runtime.GrainObjects) do
                if dot and dot.Parent then dot.BackgroundTransparency = State.GrainStrength end
            end
        end

        local grainAccumulator = 0
        Scope:TrackConnection(RunService.RenderStepped:Connect(function(dt)
            if Runtime.Dead or not State.ScreenFX then return end

            if State.ScreenRainbow then
                Tint.BackgroundColor3 = rainbowColor(State.ScreenRainbowSpeed, 0, 0.65, 1)
            elseif Tint.BackgroundColor3 ~= State.ScreenTint then
                Tint.BackgroundColor3 = State.ScreenTint
            end

            if State.Grain then
                grainAccumulator = grainAccumulator + dt
                if grainAccumulator >= 0.075 then
                    grainAccumulator = 0
                    for _, dot in ipairs(Runtime.GrainObjects) do
                        dot.Position = UDim2.fromScale(math.random(), math.random())
                        dot.BackgroundColor3 = math.random() > 0.5 and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
                    end
                end
            end
        end))

        rebuildScanlines()
        rebuildGrain()
        updateScreenFXStatic()

        --====================================================
        -- UI: CURSOR
        --====================================================

        local CursorSection = Context:CreateSection(Scope, Tab, "Cursor", false, "Visual / Cursor")
        Runtime.Controls.CursorEnabled = CursorSection:AddToggle({
            Name = "Custom Cursor",
            Flag = "Visual_CustomCursor",
            Default = State.CursorEnabled,
            RequiredGraphics = "Low",
            Description = "Replaces the Roblox mouse icon with a custom cursor drawn above Experiment17 GUI.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.CursorEnabled = value end,
        })
        CursorSection:AddChoice({
            Name = "Cursor Type",
            Flag = "Visual_CursorType",
            Values = {"Cross", "Cross + Dot", "Dot", "Circle", "Ring + Dot", "X", "Plus", "T", "Diamond", "Chevron", "Brackets", "Triangle", "Image"},
            Default = State.CursorType,
            RequiredGraphics = "Low",
            Description = "Changes the custom cursor geometry. Image uses Cursor Image ID.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.CursorType = value rebuildCursor() end,
        })
        CursorSection:AddInput({
            Name = "Cursor Image ID",
            Flag = "Visual_CursorImage",
            Default = State.CursorImage,
            Placeholder = "rbxassetid://... or numeric id",
            RequiredGraphics = "Low",
            Description = "Asset used by the Image cursor type.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value)
                State.CursorImage = normalizeAssetId(value)
                if State.CursorType == "Image" then rebuildCursor() end
            end,
        })
        CursorSection:AddColorPicker({
            Name = "Cursor Color",
            Flag = "Visual_CursorColor",
            Default = State.CursorColor,
            RequiredGraphics = "Low",
            Description = "Static cursor color when RGB Cursor is disabled.",
            FPSImpact = 0,
            PingImpact = 0,
            Callback = function(value) State.CursorColor = value end,
        })
        CursorSection:AddToggle({
            Name = "RGB Cursor",
            Flag = "Visual_CursorRainbow",
            Default = State.CursorRainbow,
            RequiredGraphics = "Low",
            Description = "Cycles cursor and trail colors through HSV.",
            FPSImpact = {-1, 0},
            PingImpact = 0,
            Callback = function(value) State.CursorRainbow = value end,
        })
        CursorSection:AddSlider({
            Name = "RGB Speed",
            Flag = "Visual_CursorRainbowSpeed",
            Min = 0.02, Max = 1.5, Default = State.CursorRainbowSpeed, Decimals = 2,
            RequiredGraphics = "Low",
            Description = "Hue-cycle speed for RGB Cursor.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.CursorRainbowSpeed = value end,
        })
        CursorSection:AddSlider({
            Name = "Cursor Size", Flag = "Visual_CursorSize",
            Min = 4, Max = 56, Default = State.CursorSize, Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Overall size of the cursor geometry.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.CursorSize = value rebuildCursor() end,
        })
        CursorSection:AddSlider({
            Name = "Cursor Gap", Flag = "Visual_CursorGap",
            Min = 0, Max = 22, Default = State.CursorGap, Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Gap around the center for cross-style cursors.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.CursorGap = value rebuildCursor() end,
        })
        CursorSection:AddSlider({
            Name = "Cursor Thickness", Flag = "Visual_CursorThickness",
            Min = 1, Max = 8, Default = State.CursorThickness, Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Thickness of lines and outlines.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.CursorThickness = value rebuildCursor() end,
        })
        CursorSection:AddSeparator()
        CursorSection:AddToggle({
            Name = "Cursor Trail", Flag = "Visual_CursorTrail",
            Default = State.CursorTrail, RequiredGraphics = "Medium",
            Description = "Leaves fading copies of the currently selected cursor shape instead of dots.",
            FPSImpact = {-3, -1}, PingImpact = 0,
            Callback = function(value) State.CursorTrail = value if not value then clearCursorHistory() end end,
        })
        CursorSection:AddSlider({
            Name = "Trail Length", Flag = "Visual_CursorTrailLength",
            Min = 2, Max = 30, Default = State.CursorTrailLength, Decimals = 0,
            RequiredGraphics = "Medium",
            Description = "Number of stored cursor-shape samples.", FPSImpact = {-3, 0}, PingImpact = 0,
            Callback = function(value) State.CursorTrailLength = math.floor(value) end,
        })
        CursorSection:AddSlider({
            Name = "Trail Sample Spacing", Flag = "Visual_CursorTrailSpacing",
            Min = 1, Max = 24, Default = State.CursorTrailSpacing, Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Minimum mouse travel in pixels before another trail sample is recorded; higher values make the trail less point-like.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.CursorTrailSpacing = value end,
        })

        --====================================================
        -- UI: MAP SURFACE
        --====================================================

        local SurfaceSection = Context:CreateSection(Scope, Tab, "Map Surface Override", false, "Visual / Map Surface")
        Runtime.Controls.Material = SurfaceSection:AddToggle({
            Name = "Material Override", Flag = "Visual_MaterialOverride",
            Default = State.MaterialOverride, RequiredGraphics = "Medium",
            Description = "Replaces map BasePart materials locally. Original Material and MaterialVariant are stored independently and restored on disable.",
            FPSImpact = {-4, 0}, PingImpact = 0,
            Callback = function(value)
                State.MaterialOverride = value
                if value then scanMap() else restoreMaterials() end
            end,
        })
        SurfaceSection:AddChoice({
            Name = "Material", Flag = "Visual_Material",
            Values = {"SmoothPlastic", "Plastic", "Neon", "Metal", "Concrete", "Brick", "Wood", "WoodPlanks", "Glass", "Granite", "Marble", "Slate", "Sand", "Fabric", "Ice", "ForceField", "Foil", "Pebble", "Cobblestone", "DiamondPlate"},
            Default = State.Material, RequiredGraphics = "Low",
            Description = "Material applied to map BaseParts while Material Override is enabled.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.Material = value if State.MaterialOverride then scanMap() end end,
        })
        Runtime.Controls.Color = SurfaceSection:AddToggle({
            Name = "Map Color Override", Flag = "Visual_MapColorOverride",
            Default = State.ColorOverride, RequiredGraphics = "Medium",
            Description = "Recolors map BaseParts locally. Original part colors are restored when disabled.",
            FPSImpact = {-3, 0}, PingImpact = 0,
            Callback = function(value)
                State.ColorOverride = value
                if value then scanMap() else restoreColors() end
            end,
        })
        SurfaceSection:AddColorPicker({
            Name = "Map Color", Flag = "Visual_MapColor",
            Default = State.MapColor, RequiredGraphics = "Low",
            Description = "Color used by Map Color Override.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.MapColor = value if State.ColorOverride then scanMap() end end,
        })
        SurfaceSection:AddSeparator()
        Runtime.Controls.Texture = SurfaceSection:AddToggle({
            Name = "Texture Override", Flag = "Visual_TextureOverride",
            Default = State.TextureOverride, RequiredGraphics = "Medium",
            Description = "Replaces MeshPart.TextureID, Decal/Texture.Texture and SurfaceAppearance.ColorMap. Each original value is stored and restored separately.",
            FPSImpact = {-6, -1}, PingImpact = 0,
            Callback = function(value)
                State.TextureOverride = value
                Runtime.TextureReloadToken = Runtime.TextureReloadToken + 1
                if value then scanMap() else restoreTextures() end
            end,
        })
        SurfaceSection:AddInput({
            Name = "Texture Asset ID", Flag = "Visual_TextureId",
            Default = State.TextureId, Placeholder = "rbxassetid://... or numeric id",
            RequiredGraphics = "Medium",
            Description = "Texture used for the map override. Changing the ID while enabled forces a fresh apply.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function(value)
                State.TextureId = normalizeAssetId(value)
                if State.TextureOverride then forceTextureReload() end
            end,
        })
        SurfaceSection:AddButton({
            Name = "Force Texture Reload", ButtonText = "Reload",
            RequiredGraphics = "Medium",
            Description = "Temporarily clears affected texture properties for one frame and applies the same asset again, allowing repeated reloads.",
            FPSImpact = {-8, -1}, PingImpact = 0,
            Callback = forceTextureReload,
        })
        SurfaceSection:AddSlider({
            Name = "Scan Batch Size", Flag = "Visual_ScanBatch",
            Min = 50, Max = 1000, Default = State.ScanBatch, Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Objects processed before yielding during full-map scans. Lower = less hitching, slower completion.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.ScanBatch = math.floor(value) end,
        })
        SurfaceSection:AddButton({
            Name = "Reapply Active Overrides", ButtonText = "Reapply",
            RequiredGraphics = "Medium",
            Description = "Rescans the full Workspace and applies currently enabled surface overrides to new/changed map objects.",
            FPSImpact = {-6, 0}, PingImpact = 0,
            Callback = function()
                scanMap()
                if State.TextureOverride and State.TextureId ~= "" then forceTextureReload() end
            end,
        })
        SurfaceSection:AddButton({
            Name = "Restore Original Map", ButtonText = "Restore",
            RequiredGraphics = "Low",
            Description = "Disables all map overrides and restores every captured Material, MaterialVariant, Color and texture property.",
            FPSImpact = {-4, 0}, PingImpact = 0,
            Callback = function()
                State.MaterialOverride = false
                State.ColorOverride = false
                State.TextureOverride = false
                Runtime.ScanToken = Runtime.ScanToken + 1
                Runtime.TextureReloadToken = Runtime.TextureReloadToken + 1
                restoreMaterials()
                restoreColors()
                restoreTextures()
                silentSet(Runtime.Controls.Material, false)
                silentSet(Runtime.Controls.Color, false)
                silentSet(Runtime.Controls.Texture, false)
            end,
        })

        --====================================================
        -- UI: SCREEN FX
        --====================================================

        local FXSection = Context:CreateSection(Scope, Tab, "Screen FX / Shader Style", false, "Visual / Screen FX")
        Runtime.Controls.ScreenFX = FXSection:AddToggle({
            Name = "Enable Screen FX", Flag = "Visual_ScreenFX",
            Default = State.ScreenFX, RequiredGraphics = "Medium",
            Description = "Master switch for client-side UI shader-style overlays. This is not a true GPU post shader.",
            FPSImpact = {-2, 0}, PingImpact = 0,
            Callback = function(value) State.ScreenFX = value updateScreenFXStatic() end,
        })
        FXSection:AddChoice({
            Name = "FX Preset", Flag = "Visual_ScreenPreset",
            Values = {"Custom", "Clean", "CRT", "VHS", "Noir", "Warm", "Cold", "Night Vision", "Cinematic"},
            Default = State.ScreenPreset, RequiredGraphics = "Medium",
            Description = "Quickly configures tint, vignette, scanlines, grain and letterbox. You can edit values afterward.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function(value)
                State.ScreenPreset = value
                if value == "Clean" then
                    State.ScreenTint = Color3.new(1,1,1); State.ScreenTintTransparency = 1
                    State.Vignette = false; State.Scanlines = false; State.Grain = false; State.Letterbox = false
                elseif value == "CRT" then
                    State.ScreenTint = Color3.fromRGB(230,255,235); State.ScreenTintTransparency = 0.96
                    State.Vignette = true; State.VignetteStrength = 0.52; State.Scanlines = true; State.ScanlineTransparency = 0.76; State.ScanlineSpacing = 4; State.Grain = true; State.GrainStrength = 0.9; State.Letterbox = false
                elseif value == "VHS" then
                    State.ScreenTint = Color3.fromRGB(245,235,255); State.ScreenTintTransparency = 0.96
                    State.Vignette = true; State.VignetteStrength = 0.38; State.Scanlines = true; State.ScanlineTransparency = 0.84; State.ScanlineSpacing = 6; State.Grain = true; State.GrainStrength = 0.86; State.Letterbox = false
                elseif value == "Noir" then
                    State.ScreenTint = Color3.fromRGB(190,190,190); State.ScreenTintTransparency = 0.90
                    State.Vignette = true; State.VignetteStrength = 0.62; State.Scanlines = false; State.Grain = true; State.GrainStrength = 0.91; State.Letterbox = true; State.LetterboxSize = 7
                elseif value == "Warm" then
                    State.ScreenTint = Color3.fromRGB(255,205,160); State.ScreenTintTransparency = 0.92
                    State.Vignette = true; State.VignetteStrength = 0.25; State.Scanlines = false; State.Grain = false; State.Letterbox = false
                elseif value == "Cold" then
                    State.ScreenTint = Color3.fromRGB(170,210,255); State.ScreenTintTransparency = 0.92
                    State.Vignette = true; State.VignetteStrength = 0.30; State.Scanlines = false; State.Grain = false; State.Letterbox = false
                elseif value == "Night Vision" then
                    State.ScreenTint = Color3.fromRGB(75,255,95); State.ScreenTintTransparency = 0.84
                    State.Vignette = true; State.VignetteStrength = 0.70; State.Scanlines = true; State.ScanlineTransparency = 0.90; State.ScanlineSpacing = 5; State.Grain = true; State.GrainStrength = 0.88; State.Letterbox = false
                elseif value == "Cinematic" then
                    State.ScreenTint = Color3.fromRGB(255,244,226); State.ScreenTintTransparency = 0.97
                    State.Vignette = true; State.VignetteStrength = 0.28; State.Scanlines = false; State.Grain = false; State.Letterbox = true; State.LetterboxSize = 9
                end
                rebuildScanlines()
                rebuildGrain()
                updateScreenFXStatic()
            end,
        })
        FXSection:AddColorPicker({
            Name = "Screen Tint", Flag = "Visual_ScreenTint",
            Default = State.ScreenTint, RequiredGraphics = "Low",
            Description = "Color overlay used by Screen FX.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.ScreenTint = value updateScreenFXStatic() end,
        })
        FXSection:AddSlider({
            Name = "Tint Transparency", Flag = "Visual_TintTransparency",
            Min = 0.5, Max = 1, Default = State.ScreenTintTransparency, Decimals = 2,
            RequiredGraphics = "Low",
            Description = "1 is invisible; lower values make the tint stronger.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.ScreenTintTransparency = value updateScreenFXStatic() end,
        })
        FXSection:AddToggle({
            Name = "RGB Screen Tint", Flag = "Visual_ScreenRainbow",
            Default = State.ScreenRainbow, RequiredGraphics = "Medium",
            Description = "Animates the screen tint through HSV.", FPSImpact = {-1, 0}, PingImpact = 0,
            Callback = function(value) State.ScreenRainbow = value end,
        })
        FXSection:AddSlider({
            Name = "RGB Screen Speed", Flag = "Visual_ScreenRainbowSpeed",
            Min = 0.02, Max = 1, Default = State.ScreenRainbowSpeed, Decimals = 2,
            RequiredGraphics = "Medium",
            Description = "Hue-cycle speed for RGB Screen Tint.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.ScreenRainbowSpeed = value end,
        })

        local FXDetail = Context:CreateSection(Scope, Tab, "Screen FX Details", false, "Visual / Screen FX Details")
        FXDetail:AddToggle({
            Name = "Vignette", Flag = "Visual_Vignette",
            Default = State.Vignette, RequiredGraphics = "Low",
            Description = "Adds dark edge gradients around the screen.", FPSImpact = {-1, 0}, PingImpact = 0,
            Callback = function(value) State.Vignette = value updateScreenFXStatic() end,
        })
        FXDetail:AddSlider({
            Name = "Vignette Strength", Flag = "Visual_VignetteStrength",
            Min = 0, Max = 1, Default = State.VignetteStrength, Decimals = 2,
            RequiredGraphics = "Low",
            Description = "Darkness of vignette edges.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.VignetteStrength = value updateScreenFXStatic() end,
        })
        FXDetail:AddToggle({
            Name = "Scanlines", Flag = "Visual_Scanlines",
            Default = State.Scanlines, RequiredGraphics = "Medium",
            Description = "Static horizontal CRT/VHS-style scanlines.", FPSImpact = {-2, 0}, PingImpact = 0,
            Callback = function(value) State.Scanlines = value updateScreenFXStatic() end,
        })
        FXDetail:AddSlider({
            Name = "Scanline Transparency", Flag = "Visual_ScanlineTransparency",
            Min = 0.5, Max = 0.99, Default = State.ScanlineTransparency, Decimals = 2,
            RequiredGraphics = "Medium",
            Description = "Visibility of scanlines; 1 is almost invisible.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.ScanlineTransparency = value updateScreenFXStatic() end,
        })
        FXDetail:AddSlider({
            Name = "Scanline Spacing", Flag = "Visual_ScanlineSpacing",
            Min = 3, Max = 16, Default = State.ScanlineSpacing, Decimals = 0,
            RequiredGraphics = "Medium",
            Description = "Pixel spacing between scanlines. Larger values create fewer UI objects.", FPSImpact = {-2, 0}, PingImpact = 0,
            Callback = function(value) State.ScanlineSpacing = value rebuildScanlines() updateScreenFXStatic() end,
        })
        FXDetail:AddToggle({
            Name = "Film Grain", Flag = "Visual_Grain",
            Default = State.Grain, RequiredGraphics = "Medium",
            Description = "Procedural lightweight grain made from a small pool of moving UI specks.", FPSImpact = {-2, 0}, PingImpact = 0,
            Callback = function(value) State.Grain = value updateScreenFXStatic() end,
        })
        FXDetail:AddSlider({
            Name = "Grain Transparency", Flag = "Visual_GrainStrength",
            Min = 0.65, Max = 0.99, Default = State.GrainStrength, Decimals = 2,
            RequiredGraphics = "Medium",
            Description = "Visibility of film grain; larger values are subtler.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.GrainStrength = value updateScreenFXStatic() end,
        })
        FXDetail:AddToggle({
            Name = "Letterbox", Flag = "Visual_Letterbox",
            Default = State.Letterbox, RequiredGraphics = "Low",
            Description = "Adds cinematic black bars at the top and bottom.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.Letterbox = value updateScreenFXStatic() end,
        })
        FXDetail:AddSlider({
            Name = "Letterbox Size", Flag = "Visual_LetterboxSize",
            Min = 0, Max = 20, Default = State.LetterboxSize, Decimals = 0,
            RequiredGraphics = "Low",
            Description = "Height of each cinematic bar as a percentage of the screen.", FPSImpact = 0, PingImpact = 0,
            Callback = function(value) State.LetterboxSize = value updateScreenFXStatic() end,
        })

        Scope:AddCleaner(function()
            Runtime.Dead = true
            Runtime.ScanToken = Runtime.ScanToken + 1
            Runtime.TextureReloadToken = Runtime.TextureReloadToken + 1
            pcall(restoreMaterials)
            pcall(restoreColors)
            pcall(restoreTextures)
            pcall(function() UIS.MouseIconEnabled = Runtime.OriginalMouseIcon end)
        end)

        -- Re-apply persisted state after hot reload.
        if State.MaterialOverride or State.ColorOverride or State.TextureOverride then
            scanMap()
        end
        if State.TextureOverride and State.TextureId ~= "" then
            task.defer(forceTextureReload)
        end
    end,

    Unload = function(Context, Scope, reason)
        -- The Scope cleaner restores map properties and the original mouse icon.
        -- State is intentionally preserved so hot reload can re-apply enabled features.
        Context.Bus:Emit("VisualModuleUnloading", reason)
    end,
}
