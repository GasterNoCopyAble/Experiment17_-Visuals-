--[[
    Experiment 17 - Animations v2.0

    Cleaner dedicated Animations tab:
      * scans emotes already present in the character Animate script
      * scans avatar/equipped emotes from HumanoidDescription when Roblox exposes them
      * tries Humanoid:PlayEmote(name) first, then falls back to Animator asset playback
      * square tile buttons through GuiLib v21 AddTileButtons
      * custom AnimationId player
      * compact movement override section

    Important: HumanoidDescription exposes avatar-configured/equipped emotes, not a guaranteed
    complete inventory of every emote ever purchased by the account.
]]

return {
    Id = "PlayerAnimations",
    Name = "Animations",
    TabName = "Animations",
    Version = "2.0.0",
    Order = 55,

    Init = function(Context, Scope, Tab)
        local Players = Context.Services.Players
        local RunService = Context.Services.RunService
        local LocalPlayer = Context.LocalPlayer
        local Library = Context.Library

        local State = Context:GetState("PlayerAnimations", {
            AnimationId = "",
            Looped = true,
            Speed = 1.0,
            Weight = 1.0,
            FadeTime = 0.15,
            Priority = "Action",
            FreezePose = false,
            MaxEmoteTiles = 28,

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
            EmoteStatus = nil,
            Emotes = {},
            EmoteIds = {},
            EmoteTileControl = nil,
            EmoteSection = nil,
        }

        local function notify(text, kind)
            if Library and type(Library.Notify) == "function" then
                pcall(function()
                    Library:Notify({Title="Experiment 17 • Animations", Text=tostring(text), Type=kind or "Info", Duration=2.8})
                end)
            end
        end

        local function normalizeAsset(value)
            value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if value == "" then return "" end
            if value:match("^rbxassetid://") then return value end
            local id = value:match("[?&]id=(%d+)") or value:match("(%d+)")
            return id and ("rbxassetid://" .. id) or value
        end

        local function rawId(value)
            return tostring(normalizeAsset(value)):match("(%d+)")
        end

        local function getHumanoidAnimator()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return nil, nil end
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if not animator then
                animator = Instance.new("Animator")
                animator.Name = "Animator"
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

        local function stopKnownEmotes()
            stopCustom()
            local _, animator = getHumanoidAnimator()
            if not animator then return end
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local id
                pcall(function() id = track.Animation and rawId(track.Animation.AnimationId) end)
                if id and R.EmoteIds[id] then
                    pcall(function() track:Stop(0.12) end)
                end
            end
        end

        local function playAsset(assetId, options)
            stopCustom()
            local id = normalizeAsset(assetId)
            if id == "" then return false, "empty animation id" end
            local _, animator = getHumanoidAnimator()
            if not animator then return false, "Animator unavailable" end

            local animation = Instance.new("Animation")
            animation.Name = "Experiment17_CustomAnimation"
            animation.AnimationId = id
            local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
            if not ok or not track then
                animation:Destroy()
                return false, tostring(track)
            end

            R.Animation = animation
            R.Track = track
            track.Priority = priorityFromName((options and options.Priority) or State.Priority)
            track.Looped = options and options.Looped ~= nil and options.Looped or State.Looped
            local speed = options and options.Speed or State.Speed
            local weight = options and options.Weight or State.Weight
            track:Play(math.max(0, State.FadeTime), math.clamp(weight, 0, 1), State.FreezePose and 0 or speed)
            if State.FreezePose then track:AdjustSpeed(0) end
            Context.Bus:Emit("PlayerCustomAnimationPlayed", id, track)
            return true, track
        end

        local function playCustom()
            local ok, why = playAsset(State.AnimationId)
            if not ok then
                Context:Warn("Failed to load animation:", why)
                notify("Animation failed: " .. tostring(why), "Warning")
            end
            return ok
        end

        local function addEmote(out, seen, name, id, source, emoteName, equipped)
            id = rawId(id)
            name = tostring(name or "Emote")
            local key = string.lower(name) .. "|" .. tostring(id or "") .. "|" .. tostring(source)
            if seen[key] then return end
            seen[key] = true
            out[#out + 1] = {
                Name = name,
                Id = id,
                Source = source,
                EmoteName = emoteName or name,
                Equipped = equipped == true,
            }
            if id then R.EmoteIds[id] = true end
        end

        local STANDARD_EMOTE_FOLDERS = {
            wave=true, point=true, cheer=true, laugh=true,
            dance=true, dance2=true, dance3=true,
        }

        local function scanCharacterAnimate(out, seen)
            local character = LocalPlayer.Character
            local animate = character and character:FindFirstChild("Animate")
            if not animate then return 0 end
            local before = #out

            for _, child in ipairs(animate:GetChildren()) do
                local lower = child.Name:lower()
                if STANDARD_EMOTE_FOLDERS[lower] then
                    local animations = {}
                    if child:IsA("Animation") then
                        animations[1] = child
                    else
                        for _, object in ipairs(child:GetDescendants()) do
                            if object:IsA("Animation") then animations[#animations + 1] = object end
                        end
                    end
                    table.sort(animations, function(a,b) return a.Name < b.Name end)
                    for index, animation in ipairs(animations) do
                        local label = child.Name
                        if #animations > 1 then label = label .. " " .. tostring(index) end
                        addEmote(out, seen, label, animation.AnimationId, "GAME", child.Name, false)
                    end
                end
            end
            return #out - before
        end

        local function scanAvatarDescription(out, seen)
            local before = #out
            local ok, description = pcall(function()
                return Players:GetHumanoidDescriptionFromUserId(LocalPlayer.UserId)
            end)
            if not ok or not description then return 0, "HumanoidDescription unavailable" end

            local emoteMap = {}
            pcall(function()
                local map = description:GetEmotes()
                if type(map) == "table" then emoteMap = map end
            end)

            local equippedNames = {}
            pcall(function()
                local equipped = description:GetEquippedEmotes()
                if type(equipped) == "table" then
                    for _, info in ipairs(equipped) do
                        if type(info) == "table" and info.Name then
                            equippedNames[tostring(info.Name)] = true
                        end
                    end
                end
            end)

            for name, ids in pairs(emoteMap) do
                if type(ids) == "table" then
                    for index, id in ipairs(ids) do
                        local label = tostring(name)
                        if #ids > 1 then label = label .. " " .. tostring(index) end
                        addEmote(out, seen, label, id, "AVATAR", tostring(name), equippedNames[tostring(name)] == true)
                    end
                else
                    addEmote(out, seen, name, ids, "AVATAR", tostring(name), equippedNames[tostring(name)] == true)
                end
            end

            return #out - before
        end

        local function playEmote(item)
            if not item then return false end
            stopKnownEmotes()
            local humanoid = getHumanoidAnimator()

            -- Native emote route first. When the game allows it, this is the cleanest
            -- path because Roblox's character/emote system owns the playback.
            if humanoid and item.EmoteName and type(humanoid.PlayEmote) == "function" then
                local ok, result = pcall(function() return humanoid:PlayEmote(item.EmoteName) end)
                if ok and result ~= false then
                    if R.EmoteStatus then R.EmoteStatus:Set("Playing: " .. item.Name .. " • native emote") end
                    notify("Emote: " .. item.Name, "Success")
                    Context.Bus:Emit("PlayerEmotePlayed", item)
                    return true
                end
            end

            if item.Id then
                local ok, why = playAsset(item.Id, {Looped=false, Priority="Action"})
                if ok then
                    if R.EmoteStatus then R.EmoteStatus:Set("Playing: " .. item.Name .. " • asset " .. item.Id) end
                    notify("Emote: " .. item.Name, "Success")
                    Context.Bus:Emit("PlayerEmotePlayed", item)
                    return true
                end
                if R.EmoteStatus then R.EmoteStatus:Set("Failed: " .. item.Name) end
                notify("Could not play " .. item.Name .. ": " .. tostring(why), "Warning")
            end
            return false
        end

        local function tileText(item)
            local tag = item.Equipped and "★" or (item.Source == "AVATAR" and "A" or "G")
            return tostring(item.Name) .. "\n" .. tag
        end

        local function rebuildEmoteTiles()
            local section = R.EmoteSection
            if not section then return end
            if R.EmoteTileControl and R.EmoteTileControl.Holder then
                pcall(function() R.EmoteTileControl.Holder:Destroy() end)
            end
            R.EmoteTileControl = nil

            local buttons = {}
            local limit = math.min(#R.Emotes, math.max(4, math.floor(State.MaxEmoteTiles or 28)))
            for index = 1, limit do
                local item = R.Emotes[index]
                buttons[#buttons + 1] = {Text = tileText(item), Callback = function() playEmote(item) end}
            end
            if #buttons == 0 then
                buttons[1] = {Text="No emotes\n↻", Callback=function() end}
            end

            if type(section.AddTileButtons) == "function" then
                R.EmoteTileControl = section:AddTileButtons({
                    Name = "Emotes",
                    TileSize = 72,
                    Columns = 4,
                    Gap = 6,
                    RequiredGraphics = "Low",
                    Description = "★ = equipped avatar emote, A = avatar description, G = current game's Animate emote.",
                    Buttons = buttons,
                })
            else
                R.EmoteTileControl = section:AddButtonGroup({Name="Emotes", RequiredGraphics="Low", Buttons=buttons})
            end
        end

        local function scanEmotes(silent)
            table.clear(R.Emotes)
            table.clear(R.EmoteIds)
            local seen = {}
            local gameCount = scanCharacterAnimate(R.Emotes, seen)
            local avatarCount, avatarWhy = scanAvatarDescription(R.Emotes, seen)

            table.sort(R.Emotes, function(a,b)
                if a.Equipped ~= b.Equipped then return a.Equipped end
                if a.Source ~= b.Source then return a.Source == "GAME" end
                return a.Name:lower() < b.Name:lower()
            end)

            rebuildEmoteTiles()
            local text = string.format("%d found • %d game • %d avatar", #R.Emotes, gameCount or 0, avatarCount or 0)
            if avatarWhy then text = text .. " • " .. avatarWhy end
            if R.EmoteStatus then R.EmoteStatus:Set(text) end
            if not silent then notify(text, #R.Emotes > 0 and "Success" or "Info") end
            return R.Emotes
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
                if animation and animation.Parent then pcall(function() animation.AnimationId = oldId end) end
                R.OriginalIds[animation] = nil
            end
        end

        local function applyOverrides()
            restoreOverrides()
            if not State.OverrideStates then return end
            local character = LocalPlayer.Character
            local animate = character and character:FindFirstChild("Animate")
            if not animate then
                notify("Animate LocalScript not found", "Warning")
                return
            end
            for stateKey, paths in pairs(stateTargets) do
                local id = normalizeAsset(State[stateKey])
                if id ~= "" then
                    for _, path in ipairs(paths) do
                        local animation = findPath(animate, path)
                        if animation and animation:IsA("Animation") then
                            if R.OriginalIds[animation] == nil then R.OriginalIds[animation] = animation.AnimationId end
                            animation.AnimationId = id
                        end
                    end
                end
            end
        end

        local function dominantTrackText()
            local _, animator = getHumanoidAnimator()
            if not animator then return "No Animator" end
            local best, bestWeight = nil, -1
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local weight = tonumber(track.WeightCurrent) or 0
                if weight > bestWeight then best, bestWeight = track, weight end
            end
            if not best then return "No animation" end
            local id = "unknown"
            pcall(function() if best.Animation then id = best.Animation.AnimationId end end)
            return string.format("%s • %.2fx", tostring(id):gsub("rbxassetid://", ""), tonumber(best.Speed) or 0)
        end

        -- CLEAN UI ----------------------------------------------------------
        local Emotes = Context:CreateSection(Scope, Tab, "Emote Library", true, "Animations / Emotes")
        R.EmoteSection = Emotes
        R.EmoteStatus = Emotes:AddStatus({
            Name = "Emotes",
            Default = "Scanning...",
            Description = "Scans the current game's Animate emotes plus avatar/equipped emotes exposed by HumanoidDescription.",
        })
        if type(Emotes.AddTileButtons) == "function" then
            Emotes:AddTileButtons({Name="Library", TileSize=64, Columns=3, Buttons={
                {Text="↻\nRefresh", Callback=function() scanEmotes(false) end},
                {Text="■\nStop", Callback=stopKnownEmotes},
                {Text="▶\nRescan + Play", Callback=function() local items=scanEmotes(true); if items[1] then playEmote(items[1]) end end},
            }})
        else
            Emotes:AddButtonGroup({Name="Library", Buttons={{Text="Refresh",Callback=function() scanEmotes(false) end},{Text="Stop",Callback=stopKnownEmotes}}})
        end

        local Player = Context:CreateSection(Scope, Tab, "Custom Animation", false, "Animations / Custom")
        R.StatusControl = Player:AddStatus({Name = "Current Track", Default = "No animation"})
        Player:AddInput({Name = "Animation ID", Flag = "PlayerAnim_ID", Default = State.AnimationId, Placeholder = "rbxassetid://...", RequiredGraphics = "Low", Callback = function(v) State.AnimationId = normalizeAsset(v) end})
        if type(Player.AddTileButtons) == "function" then
            Player:AddTileButtons({Name="Actions", TileSize=64, Columns=2, Buttons={
                {Text="▶\nPlay", Callback=playCustom},
                {Text="■\nStop", Callback=stopCustom},
            }})
        else
            Player:AddButtonGroup({Name="Actions",Buttons={{Text="Play",Callback=playCustom},{Text="Stop",Callback=stopCustom}}})
        end
        Player:AddChoice({Name = "Priority", Flag = "PlayerAnim_Priority", Values = {"Core","Idle","Movement","Action","Action2","Action3","Action4"}, Default = State.Priority, RequiredGraphics = "Low", Callback = function(v) State.Priority = v end})
        Player:AddSlider({Name = "Speed", Flag = "PlayerAnim_Speed", Min = 0, Max = 5, Default = State.Speed, Decimals = 2, RequiredGraphics = "Low", Callback = function(v) State.Speed = v end})
        Player:AddToggle({Name = "Looped", Flag = "PlayerAnim_Looped", Default = State.Looped, RequiredGraphics = "Low", Callback = function(v) State.Looped = v end})
        Player:AddToggle({Name = "Freeze Pose", Flag = "PlayerAnim_Freeze", Default = State.FreezePose, RequiredGraphics = "Low", Callback = function(v) State.FreezePose = v end})

        local Overrides = Context:CreateSection(Scope, Tab, "Movement Overrides", false, "Animations / Overrides")
        Overrides:AddToggle({Name = "Override Standard Animate", Flag = "PlayerAnim_Override", Default = State.OverrideStates, RequiredGraphics = "Low", Callback = function(v) State.OverrideStates = v; if v then applyOverrides() else restoreOverrides() end end})
        local function addStateInput(name, flag, key)
            Overrides:AddInput({Name=name, Flag=flag, Default=State[key], Placeholder="blank = keep game animation", RequiredGraphics="Low", Callback=function(v) State[key]=normalizeAsset(v); if State.OverrideStates then applyOverrides() end end})
        end
        addStateInput("Idle", "PlayerAnim_Idle", "IdleId")
        addStateInput("Walk", "PlayerAnim_Walk", "WalkId")
        addStateInput("Run", "PlayerAnim_Run", "RunId")
        addStateInput("Jump", "PlayerAnim_Jump", "JumpId")
        addStateInput("Fall", "PlayerAnim_Fall", "FallId")
        addStateInput("Climb", "PlayerAnim_Climb", "ClimbId")
        addStateInput("Swim", "PlayerAnim_Swim", "SwimId")
        addStateInput("Swim Idle", "PlayerAnim_SwimIdle", "SwimIdleId")
        Overrides:AddButtonGroup({Name="Overrides",Buttons={{Text="Apply",Callback=applyOverrides},{Text="Restore",Callback=restoreOverrides}}})

        Scope:TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
            task.delay(0.8, function()
                if State.OverrideStates then applyOverrides() end
                scanEmotes(true)
            end)
        end))

        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt)
            R.StatusTimer = R.StatusTimer + dt
            if R.Track then
                pcall(function()
                    R.Track.Looped = State.Looped
                    R.Track.Priority = priorityFromName(State.Priority)
                    R.Track:AdjustWeight(math.clamp(State.Weight, 0, 1), 0.08)
                    R.Track:AdjustSpeed(State.FreezePose and 0 or State.Speed)
                end)
            end
            if R.StatusTimer >= 0.6 then
                R.StatusTimer = 0
                if R.StatusControl then R.StatusControl:Set(dominantTrackText()) end
            end
        end))

        Context.Shared.PlayerAnimations = {
            Play = function(id) if id ~= nil then State.AnimationId = normalizeAsset(id) end return playCustom() end,
            Stop = stopKnownEmotes,
            GetTrack = function() return R.Track end,
            RefreshEmotes = function() return scanEmotes(false) end,
            GetEmotes = function() return R.Emotes end,
            PlayEmote = playEmote,
            ApplyOverrides = applyOverrides,
            RestoreOverrides = restoreOverrides,
        }

        task.defer(function() scanEmotes(true) end)

        Scope:AddCleaner(function()
            stopKnownEmotes()
            restoreOverrides()
            if Context.Shared.PlayerAnimations then Context.Shared.PlayerAnimations = nil end
        end)
    end,
}
