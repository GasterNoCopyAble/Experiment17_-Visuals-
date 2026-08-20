-- Experiment17 - Performance / Streaming controls
return {
    Id = "PerformanceStreaming",
    Name = "Performance Streaming",
    Version = "1.0.0",
    Order = 915,
    TargetTab = "Performance",

    Init = function(Context, Scope, Tab)
        local Workspace = Context.Services.Workspace or workspace
        local Players = Context.Services.Players or game:GetService("Players")
        local LocalPlayer = Context.LocalPlayer or Players.LocalPlayer
        local Library = Context.Library
        local ENV = (getgenv and getgenv()) or _G

        local State = Context:GetState("PerformanceStreaming", {
            TargetRadius = 1024,
            MinRadius = 128,
            Enforce = false,
            EnforceInterval = 2.0,
            Notify = true,
        })

        local R = {Running=true, LastMethod="none", Status=nil}

        local function notify(text, kind)
            if not State.Notify then return end
            local shared = Context.Shared and Context.Shared.UIEnhancements
            if shared and type(shared.Notify) == "function" then
                shared.Notify(text, kind)
            elseif Library and type(Library.Notify) == "function" then
                pcall(function() Library:Notify({Title="Experiment 17 • Streaming", Text=tostring(text), Type=kind or "Info", Duration=3}) end)
            end
        end

        local function safeGet(property)
            local ok, value = pcall(function() return Workspace[property] end)
            if ok then return value, "property" end
            local getter = ENV.gethiddenproperty or gethiddenproperty
            if type(getter) == "function" then
                local ok2, value2 = pcall(getter, Workspace, property)
                if ok2 then return value2, "hidden" end
            end
            return nil, "unavailable"
        end

        local function safeSet(property, value)
            local ok = pcall(function() Workspace[property] = value end)
            if ok then return true, "property" end

            local setter = ENV.sethiddenproperty or sethiddenproperty
            if type(setter) == "function" then
                local ok2 = pcall(setter, Workspace, property, value)
                if ok2 then return true, "hidden" end
            end
            return false, "unavailable"
        end

        local function streamingEnabled()
            local value = false
            pcall(function() value = Workspace.StreamingEnabled end)
            return value == true
        end

        local function refreshStatus(extra)
            if not R.Status or type(R.Status.Set) ~= "function" then return end
            local currentTarget = safeGet("StreamingTargetRadius")
            local currentMin = safeGet("StreamingMinRadius")
            local text = string.format(
                "Streaming: %s | target %s | min %s | via %s%s",
                streamingEnabled() and "ON" or "OFF",
                tostring(currentTarget or "?"),
                tostring(currentMin or "?"),
                tostring(R.LastMethod),
                extra and (" | " .. tostring(extra)) or ""
            )
            pcall(function() R.Status:Set(text) end)
        end

        local function applyRadius(silent)
            if not streamingEnabled() then
                R.LastMethod = "game disabled"
                refreshStatus("server must enable StreamingEnabled")
                if not silent then notify("Workspace.StreamingEnabled is OFF in this game", "Warning") end
                return false
            end

            local target = math.floor(math.clamp(tonumber(State.TargetRadius) or 1024, 64, 8192))
            local minimum = math.floor(math.clamp(tonumber(State.MinRadius) or 128, 16, target))
            State.TargetRadius = target
            State.MinRadius = minimum

            local okTarget, methodTarget = safeSet("StreamingTargetRadius", target)
            local okMin, methodMin = safeSet("StreamingMinRadius", minimum)
            R.LastMethod = okTarget and okMin and ((methodTarget == "hidden" or methodMin == "hidden") and "hidden property" or "property") or "blocked"
            refreshStatus()

            if not silent then
                if okTarget and okMin then
                    notify("Streaming radius applied: " .. target .. " / " .. minimum, "Success")
                else
                    notify("This executor/game blocks client streaming-radius writes", "Warning")
                end
            end
            return okTarget and okMin
        end

        local Section = Context:CreateSection(Scope, Tab, "Workspace Streaming", false, "Performance / Streaming")
        R.Status = Section:AddStatus({
            Name = "Streaming State",
            Default = "Reading Workspace streaming...",
            Description = "Controls the local requested streaming radii when Roblox exposes them. The server must already have Workspace.StreamingEnabled enabled.",
        })

        Section:AddSlider({
            Name = "Streaming Target Radius",
            Flag = "Performance_StreamingTargetRadius",
            Min = 64, Max = 8192, Default = State.TargetRadius, Decimals = 0, Suffix = " studs",
            RequiredGraphics = "Low",
            Description = "Approximate target radius the client tries to keep streamed. Lower values reduce loaded Workspace content; higher values keep more map nearby.",
            FPSImpact = {-12, 6}, PingImpact = {-2, 4},
            Callback = function(v) State.TargetRadius = math.floor(v); if State.Enforce then applyRadius(true) end end,
        })

        Section:AddSlider({
            Name = "Streaming Minimum Radius",
            Flag = "Performance_StreamingMinRadius",
            Min = 16, Max = 2048, Default = State.MinRadius, Decimals = 0, Suffix = " studs",
            RequiredGraphics = "Low",
            Description = "Minimum area Roblox should try to keep around the player. It is clamped not to exceed Target Radius when applied.",
            FPSImpact = {-4, 2}, PingImpact = {-1, 2},
            Callback = function(v) State.MinRadius = math.floor(v); if State.Enforce then applyRadius(true) end end,
        })

        Section:AddToggle({
            Name = "Enforce Streaming Radius",
            Flag = "Performance_StreamingEnforce",
            Default = State.Enforce,
            RequiredGraphics = "Low",
            Description = "Re-applies the selected radii periodically in case the game changes them locally.",
            FPSImpact = 0, PingImpact = 0,
            Callback = function(v) State.Enforce = v; if v then applyRadius(false) end end,
        })

        Section:AddSlider({
            Name = "Enforce Interval",
            Flag = "Performance_StreamingInterval",
            Min = 0.5, Max = 10, Default = State.EnforceInterval, Decimals = 1, Suffix = " s",
            RequiredGraphics = "Low",
            Callback = function(v) State.EnforceInterval = v end,
        })

        Section:AddButtonGroup({
            Name = "Streaming Actions",
            RequiredGraphics = "Low",
            Buttons = {
                {Text="Apply", Callback=function() applyRadius(false) end},
                {Text="Read", Callback=function() refreshStatus("refreshed") end},
                {Text="Stream Here", Callback=function()
                    local char = LocalPlayer.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end
                    local ok = pcall(function() LocalPlayer:RequestStreamAroundAsync(root.Position, 3) end)
                    notify(ok and "Requested streaming around current position" or "RequestStreamAroundAsync failed", ok and "Success" or "Warning")
                end},
            },
        })

        Section:AddToggle({Name="Streaming Notifications", Flag="Performance_StreamingNotify", Default=State.Notify, RequiredGraphics="Low", Callback=function(v) State.Notify=v end})

        Scope:AddCleaner(function() R.Running=false end)
        task.spawn(function()
            while R.Running and not Context.Unloaded do
                if State.Enforce then applyRadius(true) else refreshStatus() end
                task.wait(math.max(0.5, tonumber(State.EnforceInterval) or 2))
            end
        end)

        task.defer(refreshStatus)
        Context.Shared.PerformanceStreaming = {Apply=applyRadius, Refresh=refreshStatus}
    end,
}
