--[[
    Experiment 17 - Player Animations v1.0
    Add-on module for the existing Player tab.

    Features:
      * play any animation ID locally
      * speed / weight / loop / priority / freeze pose
      * inspect the currently dominant AnimationTrack
      * optional standard Animate-script state overrides (idle/walk/run/jump/fall/climb/swim)
      * restores original AnimationIds on disable/unload
]]

return {
    Id = "PlayerAnimations",
    Name = "Player Animations",
    Version = "1.0.0",
    Order = 55,
    TargetTab = "Player",

    Init = function(Context, Scope, Tab)
        local Players = Context.Services.Players
        local RunService = Context.Services.RunService
        local LocalPlayer = Context.LocalPlayer

        local State = Context:GetState("PlayerAnimations", {
            AnimationId = "",
            Looped = true,
            Speed = 1.0,
            Weight = 1.0,
            FadeTime = 0.15,
            Priority = "Action",
            FreezePose = false,

            OverrideStates = false,
            IdleId = "",
            WalkId = "",
            RunId = "",
            JumpId = "",
            FallId = "",
            ClimbId = "",
            SwimId = "",
            SwimIdleId = "",
        })

        local R = {
            Track = nil,
            Animation = nil,
            OriginalIds = setmetatable({}, {__mode = "k"}),
            StatusTimer = 0,
            StatusControl = nil,
        }

        local function normalizeAsset(value)
            value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if value == "" then return "" end
            if value:match("^rbxassetid://") then return value end
            local id = value:match("[?&]id=(%d+)") or value:match("(%d+)")
            return id and ("rbxassetid://" .. id) or value
        end

        local function getHumanoidAnimator()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return nil, nil end
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if not animator then
                animator = Instance.new("Animator")
                animator.Parent = humanoid
            end
            return humanoid, animator
        end

        local function priorityFromName(name)
            local map = {
                Core = Enum.AnimationPriority.Core,
                Idle = Enum.AnimationPriority.Idle,
                Movement = Enum.AnimationPriority.Movement,
                Action = Enum.AnimationPriority.Action,
                Action2 = Enum.AnimationPriority.Action2,
                Action3 = Enum.AnimationPriority.Action3,
                Action4 = Enum.AnimationPriority.Action4,
            }
            return map[tostring(name)] or Enum.AnimationPriority.Action
        end

        local function stopCustom()
            if R.Track then
                pcall(function() R.Track:Stop(math.max(0, State.FadeTime)) end)
                pcall(function() R.Track:Destroy() end)
            end
            if R.Animation then pcall(function() R.Animation:Destroy() end) end
            R.Track, R.Animation = nil, nil
        end

        local function playCustom()
            stopCustom()
            local id = normalizeAsset(State.AnimationId)
            if id == "" then
                Context:Warn("Animation ID is empty")
                return false
            end
            local _, animator = getHumanoidAnimator()
            if not animator then return false end

            local animation = Instance.new("Animation")
            animation.Name = "Experiment17_CustomAnimation"
            animation.AnimationId = id
            local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
            if not ok or not track then
                animation:Destroy()
                Context:Warn("Failed to load animation:", track)
                return false
            end

            R.Animation = animation
            R.Track = track
            track.Priority = priorityFromName(State.Priority)
            track.Looped = State.Looped
            track:Play(math.max(0, State.FadeTime), math.clamp(State.Weight, 0, 1), State.FreezePose and 0 or State.Speed)
            if State.FreezePose then track:AdjustSpeed(0) end
            Context.Bus:Emit("PlayerCustomAnimationPlayed", id, track)
            return true
        end

        local function findPath(root, path)
            local current = root
            for segment in tostring(path):gmatch("[^/]+") do
                current = current and current:FindFirstChild(segment)
                if not current then return nil end
            end
            return current
        end

        local stateTargets = {
            IdleId = {"idle/Animation1", "idle/Animation2"},
            WalkId = {"walk/WalkAnim"},
            RunId = {"run/RunAnim"},
            JumpId = {"jump/JumpAnim"},
            FallId = {"fall/FallAnim"},
            ClimbId = {"climb/ClimbAnim"},
            SwimId = {"swim/Swim"},
            SwimIdleId = {"swimidle/SwimIdle"},
        }

        local function restoreOverrides()
            for animation, oldId in pairs(R.OriginalIds) do
                if animation and animation.Parent then
                    pcall(function() animation.AnimationId = oldId end)
                end
                R.OriginalIds[animation] = nil
            end
        end

        local function applyOverrides()
            restoreOverrides()
            if not State.OverrideStates then return end
            local character = LocalPlayer.Character
            local animate = character and character:FindFirstChild("Animate")
            if not animate then
                Context:Warn("Standard Animate LocalScript was not found; state overrides skipped")
                return
            end

            for stateKey, paths in pairs(stateTargets) do
                local id = normalizeAsset(State[stateKey])
                if id ~= "" then
                    for _, path in ipairs(paths) do
                        local animation = findPath(animate, path)
                        if animation and animation:IsA("Animation") then
                            if R.OriginalIds[animation] == nil then
                                R.OriginalIds[animation] = animation.AnimationId
                            end
                            animation.AnimationId = id
                        end
                    end
                end
            end
        end

        local function dominantTrackText()
            local _, animator = getHumanoidAnimator()
            if not animator then return "No Animator" end
            local best, bestWeight
            bestWeight = -1
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local weight = tonumber(track.WeightCurrent) or 0
                if weight > bestWeight then best, bestWeight = track, weight end
            end
            if not best then return "No animation" end
            local id = "unknown"
            pcall(function()
                if best.Animation then id = best.Animation.AnimationId end
            end)
            return string.format("%s • %.2fx", tostring(id):gsub("rbxassetid://", ""), tonumber(best.Speed) or 0)
        end

        Scope:TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
            task.delay(0.6, function()
                if State.OverrideStates then applyOverrides() end
                if R.Track then stopCustom() end
            end)
        end))

        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            R.StatusTimer += dt
            if R.Track then
                pcall(function()
                    R.Track.Looped = State.Looped
                    R.Track.Priority = priorityFromName(State.Priority)
                    R.Track:AdjustWeight(math.clamp(State.Weight, 0, 1), 0.08)
                    R.Track:AdjustSpeed(State.FreezePose and 0 or State.Speed)
                end)
            end
            if R.StatusTimer >= 0.5 then
                R.StatusTimer = 0
                if R.StatusControl then R.StatusControl:Set(dominantTrackText()) end
            end
        end))

        local Player = Context:CreateSection(Scope, Tab, "Animation Player", false, "Player / Animations")
        R.StatusControl = Player:AddStatus({Name = "Playing Animation", Default = "No animation"})
        Player:AddInput({Name = "Animation ID", Flag = "PlayerAnim_ID", Default = State.AnimationId, Placeholder = "93641215582246", RequiredGraphics = "Low", Callback = function(v) State.AnimationId = normalizeAsset(v) end})
        Player:AddChoice({Name = "Priority", Flag = "PlayerAnim_Priority", Values = {"Core","Idle","Movement","Action","Action2","Action3","Action4"}, Default = State.Priority, RequiredGraphics = "Low", Callback = function(v) State.Priority = v end})
        Player:AddToggle({Name = "Looped", Flag = "PlayerAnim_Looped", Default = State.Looped, RequiredGraphics = "Low", Callback = function(v) State.Looped = v end})
        Player:AddToggle({Name = "Freeze Pose", Flag = "PlayerAnim_Freeze", Default = State.FreezePose, RequiredGraphics = "Low", Description = "Sets the custom track speed to zero while preserving its current pose.", Callback = function(v) State.FreezePose = v end})
        Player:AddSlider({Name = "Speed", Flag = "PlayerAnim_Speed", Min = 0, Max = 5, Default = State.Speed, Decimals = 2, RequiredGraphics = "Low", Callback = function(v) State.Speed = v end})
        Player:AddSlider({Name = "Weight", Flag = "PlayerAnim_Weight", Min = 0, Max = 1, Default = State.Weight, Decimals = 2, RequiredGraphics = "Low", Callback = function(v) State.Weight = v end})
        Player:AddSlider({Name = "Fade Time", Flag = "PlayerAnim_Fade", Min = 0, Max = 2, Default = State.FadeTime, Decimals = 2, RequiredGraphics = "Low", Callback = function(v) State.FadeTime = v end})
        Player:AddButtonGroup({Name = "Animation Actions", Buttons = {
            {Text = "Play", Callback = playCustom},
            {Text = "Stop", Callback = stopCustom},
        }})

        local Overrides = Context:CreateSection(Scope, Tab, "Movement Animation Overrides", false, "Player / Animation Overrides")
        Overrides:AddToggle({Name = "Override Standard Animate", Flag = "PlayerAnim_Override", Default = State.OverrideStates, RequiredGraphics = "Low", Description = "Changes AnimationId values inside the standard local Animate script. Games with a custom animation controller may ignore this.", Callback = function(v) State.OverrideStates = v; if v then applyOverrides() else restoreOverrides() end end})
        local function addStateInput(name, flag, key)
            Overrides:AddInput({Name = name, Flag = flag, Default = State[key], Placeholder = "blank = keep game animation", RequiredGraphics = "Low", Callback = function(v) State[key] = normalizeAsset(v); if State.OverrideStates then applyOverrides() end end})
        end
        addStateInput("Idle Animation", "PlayerAnim_Idle", "IdleId")
        addStateInput("Walk Animation", "PlayerAnim_Walk", "WalkId")
        addStateInput("Run Animation", "PlayerAnim_Run", "RunId")
        addStateInput("Jump Animation", "PlayerAnim_Jump", "JumpId")
        addStateInput("Fall Animation", "PlayerAnim_Fall", "FallId")
        addStateInput("Climb Animation", "PlayerAnim_Climb", "ClimbId")
        addStateInput("Swim Animation", "PlayerAnim_Swim", "SwimId")
        addStateInput("Swim Idle", "PlayerAnim_SwimIdle", "SwimIdleId")
        Overrides:AddButtonGroup({Name = "Override Actions", Buttons = {
            {Text = "Apply", Callback = applyOverrides},
            {Text = "Restore", Callback = restoreOverrides},
        }})

        Context.Shared.PlayerAnimations = {
            Play = function(id)
                if id ~= nil then State.AnimationId = normalizeAsset(id) end
                return playCustom()
            end,
            Stop = stopCustom,
            GetTrack = function() return R.Track end,
            ApplyOverrides = applyOverrides,
            RestoreOverrides = restoreOverrides,
        }

        Scope:AddCleaner(function()
            stopCustom()
            restoreOverrides()
            if Context.Shared.PlayerAnimations and Context.Shared.PlayerAnimations.GetTrack then
                Context.Shared.PlayerAnimations = nil
            end
        end)
    end,
}
