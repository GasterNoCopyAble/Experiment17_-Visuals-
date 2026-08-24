-- Experiment17 - Character Afterimage
-- Fixed age-based spectral trail inspired by chromatic temporal afterimages.
-- This is NOT an HSV/RGB cycle: each ghost changes color as it gets older.
return {
    Id = "Afterimage",
    Name = "Afterimage",
    Version = "1.0.0",
    Order = 15,
    TargetTab = "Visual",

    Init = function(Context, Scope, Tab)
        local Players = Context.Services.Players or game:GetService("Players")
        local RunService = Context.Services.RunService or game:GetService("RunService")
        local Workspace = Context.Services.Workspace or workspace
        local LocalPlayer = Context.LocalPlayer or Players.LocalPlayer
        local Library = Context.Library

        local State = Context:GetState("Afterimage", {
            Enabled = false,
            Style = "Asriel Spectrum",
            OnlyMoving = true,
            MinSpeed = 1.5,
            SpawnInterval = 0.045,
            Lifetime = 0.42,
            MaxImages = 10,
            StartTransparency = 0.28,
            TintStrength = 0.88,
            IncludeAccessories = true,
            KeepTextures = true,
            UseHighlight = true,
            HighlightStrength = 0.42,
        })

        local Runtime = {
            Active = {},
            Accumulator = 0,
            LastRootPosition = nil,
            Root = nil,
            Dead = false,
        }

        Runtime.Root = Scope:TrackInstance(Instance.new("Folder"))
        Runtime.Root.Name = "Experiment17_Afterimage_Runtime"
        Runtime.Root.Parent = Workspace

        local PALETTES = {
            ["Asriel Spectrum"] = {
                Color3.fromRGB(220, 255, 255),
                Color3.fromRGB(65, 235, 225),
                Color3.fromRGB(55, 238, 135),
                Color3.fromRGB(210, 238, 70),
                Color3.fromRGB(255, 177, 45),
                Color3.fromRGB(255, 86, 42),
            },
            ["Cold Spectrum"] = {
                Color3.fromRGB(230, 255, 255),
                Color3.fromRGB(110, 235, 255),
                Color3.fromRGB(55, 205, 235),
                Color3.fromRGB(65, 230, 185),
                Color3.fromRGB(120, 245, 160),
            },
            ["Warm Spectrum"] = {
                Color3.fromRGB(255, 245, 205),
                Color3.fromRGB(255, 220, 95),
                Color3.fromRGB(255, 175, 55),
                Color3.fromRGB(255, 110, 45),
                Color3.fromRGB(225, 65, 45),
            },
            ["Ghost"] = {
                Color3.fromRGB(210, 235, 255),
                Color3.fromRGB(155, 205, 255),
                Color3.fromRGB(110, 165, 235),
            },
        }

        local function notify(text, kind)
            if Library and type(Library.Notify) == "function" then
                pcall(function()
                    Library:Notify({
                        Title = "Experiment 17 • Afterimage",
                        Text = tostring(text),
                        Type = kind or "Info",
                        Duration = 2.4,
                    })
                end)
            end
        end

        local function smoothstep(x)
            x = math.clamp(x, 0, 1)
            return x * x * (3 - 2 * x)
        end

        local function paletteColor(style, age01)
            local palette = PALETTES[style] or PALETTES["Asriel Spectrum"]
            if #palette == 1 then return palette[1] end

            local scaled = math.clamp(age01, 0, 0.999999) * (#palette - 1)
            local index = math.floor(scaled) + 1
            local alpha = scaled - math.floor(scaled)
            local a = palette[index]
            local b = palette[math.min(index + 1, #palette)]
            return a:Lerp(b, alpha)
        end

        local function destroyEcho(entry)
            if not entry then return end
            if entry.Model and entry.Model.Parent then
                pcall(function() entry.Model:Destroy() end)
            end
        end

        local function clearAll()
            for i = #Runtime.Active, 1, -1 do
                destroyEcho(Runtime.Active[i])
                Runtime.Active[i] = nil
            end
            Runtime.Accumulator = 0
            Runtime.LastRootPosition = nil
        end

        local function stripClone(model)
            local visualParts = {}

            for _, object in ipairs(model:GetDescendants()) do
                if object:IsA("BasePart") then
                    if object.Name == "HumanoidRootPart" then
                        object.Transparency = 1
                    end
                    object.Anchored = true
                    object.CanCollide = false
                    object.CanTouch = false
                    object.CanQuery = false
                    object.CastShadow = false
                    object.Massless = true

                    visualParts[#visualParts + 1] = {
                        Part = object,
                        BaseColor = object.Color,
                        BaseTransparency = object.Transparency,
                    }
                elseif object:IsA("Script")
                    or object:IsA("LocalScript")
                    or object:IsA("ModuleScript")
                    or object:IsA("Humanoid")
                    or object:IsA("Animator")
                    or object:IsA("AnimationController")
                    or object:IsA("Motor6D")
                    or object:IsA("Weld")
                    or object:IsA("WeldConstraint")
                    or object:IsA("Constraint")
                    or object:IsA("ParticleEmitter")
                    or object:IsA("Trail")
                    or object:IsA("Beam")
                    or object:IsA("Fire")
                    or object:IsA("Smoke")
                    or object:IsA("Sparkles") then
                    object:Destroy()
                elseif object:IsA("Decal") and not State.KeepTextures then
                    object:Destroy()
                elseif object:IsA("SurfaceAppearance") and not State.KeepTextures then
                    object:Destroy()
                end
            end

            if not State.IncludeAccessories then
                for _, child in ipairs(model:GetChildren()) do
                    if child:IsA("Accessory") then child:Destroy() end
                end
            end

            return visualParts
        end

        local function createSnapshot()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not character or not humanoid or humanoid.Health <= 0 or not root then return nil end

            local wasArchivable = character.Archivable
            character.Archivable = true
            local ok, clone = pcall(function() return character:Clone() end)
            character.Archivable = wasArchivable
            if not ok or not clone then return nil end

            clone.Name = "E17_SpectralAfterimage"
            local parts = stripClone(clone)
            if #parts == 0 then
                clone:Destroy()
                return nil
            end

            local highlight
            if State.UseHighlight then
                highlight = Instance.new("Highlight")
                highlight.Name = "E17_AfterimageTint"
                highlight.DepthMode = Enum.HighlightDepthMode.Occluded
                highlight.FillTransparency = math.clamp(1 - State.HighlightStrength, 0, 1)
                highlight.OutlineTransparency = 1
                highlight.Parent = clone
            end

            clone.Parent = Runtime.Root

            local entry = {
                Model = clone,
                Parts = parts,
                Highlight = highlight,
                Born = os.clock(),
            }
            Runtime.Active[#Runtime.Active + 1] = entry

            while #Runtime.Active > math.max(2, math.floor(State.MaxImages)) do
                destroyEcho(table.remove(Runtime.Active, 1))
            end

            return entry
        end

        local function shouldSpawn()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not humanoid or not root or humanoid.Health <= 0 then return false end
            if not State.OnlyMoving then return true end

            local horizontalVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
            local moved = false
            if Runtime.LastRootPosition then
                local delta = root.Position - Runtime.LastRootPosition
                moved = Vector3.new(delta.X, 0, delta.Z).Magnitude > 0.035
            end
            Runtime.LastRootPosition = root.Position

            return horizontalVelocity >= State.MinSpeed or humanoid.MoveDirection.Magnitude > 0.05 or moved
        end

        local function updateEcho(entry, now)
            local life = math.max(0.08, State.Lifetime)
            local age = now - entry.Born
            local t = age / life
            if t >= 1 then return false end

            local color = paletteColor(State.Style, t)
            local fade = State.StartTransparency + (1 - State.StartTransparency) * smoothstep(t)
            local tint = math.clamp(State.TintStrength, 0, 1)

            for _, info in ipairs(entry.Parts) do
                local part = info.Part
                if part and part.Parent then
                    part.Color = info.BaseColor:Lerp(color, tint)
                    local baseTransparency = math.clamp(info.BaseTransparency or 0, 0, 1)
                    part.Transparency = baseTransparency + (1 - baseTransparency) * fade
                end
            end

            if entry.Highlight and entry.Highlight.Parent then
                entry.Highlight.FillColor = color
                entry.Highlight.FillTransparency = math.clamp(
                    (1 - State.HighlightStrength) + t * State.HighlightStrength,
                    0,
                    1
                )
            end

            return true
        end

        Scope:TrackConnection(RunService.RenderStepped:Connect(function(dt)
            if Runtime.Dead then return end

            if not State.Enabled then
                if #Runtime.Active > 0 then clearAll() end
                return
            end

            Runtime.Accumulator = Runtime.Accumulator + dt
            local interval = math.max(0.02, State.SpawnInterval)
            if Runtime.Accumulator >= interval then
                Runtime.Accumulator = Runtime.Accumulator % interval
                if shouldSpawn() then createSnapshot() end
            end

            local now = os.clock()
            for i = #Runtime.Active, 1, -1 do
                local entry = Runtime.Active[i]
                if not updateEcho(entry, now) then
                    destroyEcho(entry)
                    table.remove(Runtime.Active, i)
                end
            end
        end))

        Scope:TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
            clearAll()
        end))

        -- Compact UI: presets first, details stay collapsed.
        local Main = Context:CreateSection(Scope, Tab, "Character Afterimage", false, "Visual / Afterimage")
        Main:AddToggle({
            Name = "Afterimage",
            Flag = "Visual_Afterimage",
            Default = State.Enabled,
            RequiredGraphics = "Low",
            Description = "Temporal character snapshots. Asriel Spectrum uses an age-based cyan → green → yellow → orange trail, not an RGB loop.",
            FPSImpact = {-9, -2},
            Callback = function(v)
                State.Enabled = v
                if not v then clearAll() end
            end,
        })
        Main:AddChoice({
            Name = "Style",
            Flag = "Visual_AfterimageStyle",
            Values = {"Asriel Spectrum", "Cold Spectrum", "Warm Spectrum", "Ghost"},
            Default = State.Style,
            RequiredGraphics = "Low",
            Callback = function(v) State.Style = v end,
        })

        if type(Main.AddTileButtons) == "function" then
            Main:AddTileButtons({
                Name = "Presets",
                TileSize = 68,
                Columns = 4,
                RequiredGraphics = "Low",
                Buttons = {
                    {Text = "Asriel\nSpectrum", Callback = function()
                        State.Style = "Asriel Spectrum"; State.SpawnInterval = 0.045; State.Lifetime = 0.42; State.MaxImages = 10; State.StartTransparency = 0.28; State.TintStrength = 0.88
                        notify("Asriel Spectrum preset applied", "Success")
                    end},
                    {Text = "Sharp\nEcho", Callback = function()
                        State.SpawnInterval = 0.035; State.Lifetime = 0.28; State.MaxImages = 8; State.StartTransparency = 0.18; State.TintStrength = 0.95
                    end},
                    {Text = "Soft\nSmear", Callback = function()
                        State.SpawnInterval = 0.055; State.Lifetime = 0.58; State.MaxImages = 12; State.StartTransparency = 0.38; State.TintStrength = 0.72
                    end},
                    {Text = "Clear\nTrail", Callback = clearAll},
                },
            })
        end

        Main:AddSlider({
            Name = "Trail Density",
            Flag = "Visual_AfterimageDensity",
            Min = 20,
            Max = 100,
            Default = math.clamp(math.floor((0.10 - State.SpawnInterval) / 0.08 * 80 + 20), 20, 100),
            Decimals = 0,
            Suffix = "%",
            RequiredGraphics = "Low",
            Callback = function(v)
                State.SpawnInterval = 0.10 - ((math.clamp(v,20,100)-20)/80)*0.08
            end,
        })
        Main:AddSlider({
            Name = "Trail Length",
            Flag = "Visual_AfterimageLength",
            Min = 0.15,
            Max = 1.0,
            Default = State.Lifetime,
            Decimals = 2,
            Suffix = " s",
            RequiredGraphics = "Low",
            Callback = function(v) State.Lifetime = v end,
        })

        local Advanced = Context:CreateSection(Scope, Tab, "Afterimage Advanced", false, "Visual / Afterimage Advanced")
        Advanced:AddToggle({Name="Only While Moving",Flag="Visual_AfterimageMoving",Default=State.OnlyMoving,RequiredGraphics="Low",Callback=function(v) State.OnlyMoving=v end})
        Advanced:AddSlider({Name="Minimum Speed",Flag="Visual_AfterimageMinSpeed",Min=0,Max=20,Default=State.MinSpeed,Decimals=1,Suffix=" studs/s",RequiredGraphics="Low",Callback=function(v) State.MinSpeed=v end})
        Advanced:AddSlider({Name="Max Images",Flag="Visual_AfterimageMax",Min=2,Max=20,Default=State.MaxImages,Decimals=0,RequiredGraphics="Low",FPSImpact={-7,-1},Callback=function(v) State.MaxImages=math.floor(v) end})
        Advanced:AddSlider({Name="Initial Transparency",Flag="Visual_AfterimageAlpha",Min=0,Max=0.9,Default=State.StartTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.StartTransparency=v end})
        Advanced:AddSlider({Name="Spectrum Tint",Flag="Visual_AfterimageTint",Min=0,Max=1,Default=State.TintStrength,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.TintStrength=v end})
        Advanced:AddToggle({Name="Include Accessories",Flag="Visual_AfterimageAccessories",Default=State.IncludeAccessories,RequiredGraphics="Low",Callback=function(v) State.IncludeAccessories=v end})
        Advanced:AddToggle({Name="Keep Textures",Flag="Visual_AfterimageTextures",Default=State.KeepTextures,RequiredGraphics="Low",Callback=function(v) State.KeepTextures=v end})
        Advanced:AddToggle({Name="Color Highlight",Flag="Visual_AfterimageHighlight",Default=State.UseHighlight,RequiredGraphics="Low",Callback=function(v) State.UseHighlight=v end})
        Advanced:AddSlider({Name="Highlight Strength",Flag="Visual_AfterimageHighlightStrength",Min=0,Max=0.85,Default=State.HighlightStrength,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.HighlightStrength=v end})

        Context.Shared.Afterimage = {
            Clear = clearAll,
            SetEnabled = function(v) State.Enabled = v == true; if not State.Enabled then clearAll() end end,
            SetStyle = function(v) if PALETTES[v] then State.Style = v end end,
        }

        Scope:AddCleaner(function()
            Runtime.Dead = true
            clearAll()
            if Context.Shared.Afterimage then Context.Shared.Afterimage = nil end
        end)
    end,
}
