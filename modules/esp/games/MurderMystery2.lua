--[[
    Experiment 17 - Murder Mystery 2 ESP
    PlaceId: 142823291

    Role getter logic based on the GetPlayerData RemoteFunction pattern
    supplied by the project owner (original getter credits: Kiriot22).

    Extends Universal ESP and adds optimized role highlights for:
      * Murderer
      * Sheriff
      * Hero
      * Innocent

    Important performance difference from older standalone snippets:
    GetPlayerData is NOT invoked every RenderStepped. Role data is polled
    at a configurable low rate and cached between updates.
]]

local UNIVERSAL_URL = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/modules/esp/Universal.lua"
local source = game:HttpGet(UNIVERSAL_URL, true)
local Base = assert(loadstring(source, "=Experiment17_UniversalESP"))()

local BaseInit = Base.Init
local BaseUnload = Base.Unload

Base.Name = "ESP"
Base.Version = tostring(Base.Version or "0") .. "+mm2"

Base.Init = function(Context, Scope, Tab)
    if type(BaseInit) == "function" then
        BaseInit(Context, Scope, Tab)
    end

    local S = Context.Services
    local Players = S.Players
    local ReplicatedStorage = S.ReplicatedStorage or game:GetService("ReplicatedStorage")
    local LocalPlayer = Context.LocalPlayer

    local State = Context:GetState("ESP_MM2_Roles", {
        Enabled = true,
        ShowSelf = false,
        HideDead = true,
        RoleTags = true,
        RefreshRate = 4,
        FillTransparency = 0.64,
        OutlineTransparency = 0.05,
        MurdererColor = Color3.fromRGB(235, 55, 55),
        SheriffColor = Color3.fromRGB(70, 135, 255),
        HeroColor = Color3.fromRGB(255, 225, 55),
        InnocentColor = Color3.fromRGB(75, 225, 95),
        UnknownColor = Color3.fromRGB(170, 170, 180),
    })

    local Runtime = {
        Roles = {},
        Highlights = setmetatable({}, {__mode = "k"}),
        Tags = setmetatable({}, {__mode = "k"}),
        Busy = false,
        Running = true,
        Remote = nil,
        SheriffName = nil,
    }

    local function findRoleRemote()
        local remote = Runtime.Remote
        if remote and remote.Parent and remote:IsA("RemoteFunction") then
            return remote
        end

        remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if remote and remote:IsA("RemoteFunction") then
            Runtime.Remote = remote
            return remote
        end

        Runtime.Remote = nil
        return nil
    end

    local function isAlive(player)
        if not player then return false end

        local info = Runtime.Roles[player.Name]
        if type(info) == "table" and (info.Killed or info.Dead) then
            return false
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health <= 0 then
            return false
        end

        return true
    end

    local function getRole(player)
        local info = player and Runtime.Roles[player.Name]
        if type(info) ~= "table" then
            return "Unknown"
        end

        local role = tostring(info.Role or "")
        if role == "Murderer" then
            return "Murderer"
        elseif role == "Sheriff" then
            return "Sheriff"
        elseif role == "Hero" then
            -- Preserve the behavior of the supplied role getter: Hero is
            -- considered the active hero once the sheriff is no longer alive.
            local sheriff = Runtime.SheriffName and Players:FindFirstChild(Runtime.SheriffName)
            if not sheriff or not isAlive(sheriff) then
                return "Hero"
            end
            return "Innocent"
        elseif role == "Innocent" then
            return "Innocent"
        end

        return role ~= "" and role or "Unknown"
    end

    local function roleColor(role)
        if role == "Murderer" then
            return State.MurdererColor
        elseif role == "Sheriff" then
            return State.SheriffColor
        elseif role == "Hero" then
            return State.HeroColor
        elseif role == "Innocent" then
            return State.InnocentColor
        end
        return State.UnknownColor
    end

    local function destroyVisual(player)
        local highlight = Runtime.Highlights[player]
        if highlight then
            pcall(function() highlight:Destroy() end)
            Runtime.Highlights[player] = nil
        end

        local tag = Runtime.Tags[player]
        if tag then
            pcall(function() tag:Destroy() end)
            Runtime.Tags[player] = nil
        end
    end

    local function ensureHighlight(player, character)
        local highlight = Runtime.Highlights[player]
        if not highlight or not highlight.Parent then
            highlight = Instance.new("Highlight")
            highlight.Name = "E17_MM2_Role"
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = character
            Runtime.Highlights[player] = highlight
        elseif highlight.Parent ~= character then
            highlight.Parent = character
        end

        highlight.Adornee = character
        return highlight
    end

    local function ensureTag(player, character)
        local head = character:FindFirstChild("Head")
        if not head then return nil end

        local tag = Runtime.Tags[player]
        if not tag or not tag.Parent then
            tag = Instance.new("BillboardGui")
            tag.Name = "E17_MM2_RoleTag"
            tag.AlwaysOnTop = true
            tag.Size = UDim2.fromOffset(150, 24)
            tag.StudsOffset = Vector3.new(0, 2.75, 0)
            tag.MaxDistance = 2500

            local text = Instance.new("TextLabel")
            text.Name = "Text"
            text.BackgroundTransparency = 1
            text.Size = UDim2.fromScale(1, 1)
            text.Font = Enum.Font.Code
            text.TextSize = 13
            text.TextStrokeTransparency = 0.3
            text.TextColor3 = Color3.new(1, 1, 1)
            text.Parent = tag

            Runtime.Tags[player] = tag
        end

        tag.Adornee = head
        tag.Parent = head
        return tag
    end

    local function updatePlayer(player)
        if not player then return end
        if player == LocalPlayer and not State.ShowSelf then
            destroyVisual(player)
            return
        end

        local character = player.Character
        if not character then
            destroyVisual(player)
            return
        end

        local alive = isAlive(player)
        if State.HideDead and not alive then
            destroyVisual(player)
            return
        end

        if not State.Enabled then
            destroyVisual(player)
            return
        end

        local role = getRole(player)
        local color = roleColor(role)

        local highlight = ensureHighlight(player, character)
        highlight.Enabled = true
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.FillTransparency = State.FillTransparency
        highlight.OutlineTransparency = State.OutlineTransparency

        if State.RoleTags then
            local tag = ensureTag(player, character)
            if tag then
                local text = tag:FindFirstChild("Text")
                if text then
                    text.Text = string.upper(role)
                    text.TextColor3 = color
                end
                tag.Enabled = true
            end
        else
            local tag = Runtime.Tags[player]
            if tag then
                pcall(function() tag:Destroy() end)
                Runtime.Tags[player] = nil
            end
        end
    end

    local function updateAllPlayers()
        for _, player in ipairs(Players:GetPlayers()) do
            updatePlayer(player)
        end
    end

    local function rebuildRoleCache(data)
        Runtime.Roles = type(data) == "table" and data or {}
        Runtime.SheriffName = nil

        for name, info in pairs(Runtime.Roles) do
            if type(info) == "table" and info.Role == "Sheriff" and not info.Killed and not info.Dead then
                Runtime.SheriffName = name
                break
            end
        end
    end

    local function refreshRoles()
        if Runtime.Busy or not Runtime.Running then return end
        Runtime.Busy = true

        local remote = findRoleRemote()
        if remote then
            local ok, data = pcall(function()
                return remote:InvokeServer()
            end)
            if ok and type(data) == "table" then
                rebuildRoleCache(data)
                updateAllPlayers()
            end
        end

        Runtime.Busy = false
    end

    local function clearAll()
        for _, player in ipairs(Players:GetPlayers()) do
            destroyVisual(player)
        end
    end

    local RoleESP = Context:CreateSection(Scope, Tab, "Murder Mystery 2 Roles", false, "ESP / MM2 Roles")

    RoleESP:AddToggle({
        Name = "Role ESP",
        Flag = "ESP_MM2_Enabled",
        Default = State.Enabled,
        RequiredGraphics = "Low",
        Description = "Highlights Murderer, Sheriff, Hero and Innocents using MM2 GetPlayerData role data.",
        FPSImpact = {-2, 0},
        PingImpact = 0,
        Callback = function(v)
            State.Enabled = v
            if v then refreshRoles() else clearAll() end
        end,
    })

    RoleESP:AddToggle({
        Name = "Role Tags",
        Flag = "ESP_MM2_RoleTags",
        Default = State.RoleTags,
        RequiredGraphics = "Low",
        Description = "Shows MURDERER / SHERIFF / HERO / INNOCENT above highlighted players.",
        FPSImpact = {-1, 0},
        PingImpact = 0,
        Callback = function(v) State.RoleTags = v; updateAllPlayers() end,
    })

    RoleESP:AddToggle({
        Name = "Hide Dead Players",
        Flag = "ESP_MM2_HideDead",
        Default = State.HideDead,
        RequiredGraphics = "Low",
        Callback = function(v) State.HideDead = v; updateAllPlayers() end,
    })

    RoleESP:AddToggle({
        Name = "Show Self",
        Flag = "ESP_MM2_ShowSelf",
        Default = State.ShowSelf,
        RequiredGraphics = "Low",
        Callback = function(v) State.ShowSelf = v; updateAllPlayers() end,
    })

    RoleESP:AddSlider({
        Name = "Role Refresh Rate",
        Flag = "ESP_MM2_RefreshRate",
        Min = 1,
        Max = 10,
        Default = State.RefreshRate,
        Decimals = 0,
        Suffix = " Hz",
        RequiredGraphics = "Low",
        Description = "How often GetPlayerData is requested. 3-5 Hz is usually enough and is far cheaper than calling InvokeServer every frame.",
        FPSImpact = {0, 0},
        PingImpact = 0,
        Callback = function(v) State.RefreshRate = math.clamp(v, 1, 10) end,
    })

    RoleESP:AddSlider({
        Name = "Fill Transparency",
        Flag = "ESP_MM2_FillTransparency",
        Min = 0,
        Max = 1,
        Default = State.FillTransparency,
        Decimals = 2,
        RequiredGraphics = "Low",
        Callback = function(v) State.FillTransparency = v; updateAllPlayers() end,
    })

    RoleESP:AddSlider({
        Name = "Outline Transparency",
        Flag = "ESP_MM2_OutlineTransparency",
        Min = 0,
        Max = 1,
        Default = State.OutlineTransparency,
        Decimals = 2,
        RequiredGraphics = "Low",
        Callback = function(v) State.OutlineTransparency = v; updateAllPlayers() end,
    })

    RoleESP:AddColorPicker({Name="Murderer Color", Flag="ESP_MM2_MurdererColor", Default=State.MurdererColor, RequiredGraphics="Low", Callback=function(v) State.MurdererColor=v; updateAllPlayers() end})
    RoleESP:AddColorPicker({Name="Sheriff Color", Flag="ESP_MM2_SheriffColor", Default=State.SheriffColor, RequiredGraphics="Low", Callback=function(v) State.SheriffColor=v; updateAllPlayers() end})
    RoleESP:AddColorPicker({Name="Hero Color", Flag="ESP_MM2_HeroColor", Default=State.HeroColor, RequiredGraphics="Low", Callback=function(v) State.HeroColor=v; updateAllPlayers() end})
    RoleESP:AddColorPicker({Name="Innocent Color", Flag="ESP_MM2_InnocentColor", Default=State.InnocentColor, RequiredGraphics="Low", Callback=function(v) State.InnocentColor=v; updateAllPlayers() end})

    RoleESP:AddButton({
        Name = "Refresh Roles Now",
        ButtonText = "Refresh",
        RequiredGraphics = "Low",
        Callback = refreshRoles,
    })

    Scope:TrackConnection(Players.PlayerRemoving:Connect(function(player)
        destroyVisual(player)
    end))

    Scope:TrackConnection(Players.PlayerAdded:Connect(function(player)
        Scope:TrackConnection(player.CharacterAdded:Connect(function()
            task.defer(function()
                if State.Enabled then updatePlayer(player) end
            end)
        end))
    end))

    for _, player in ipairs(Players:GetPlayers()) do
        Scope:TrackConnection(player.CharacterAdded:Connect(function()
            task.defer(function()
                if State.Enabled then updatePlayer(player) end
            end)
        end))
    end

    task.spawn(function()
        while Runtime.Running do
            if State.Enabled then
                refreshRoles()
            end
            task.wait(1 / math.max(1, State.RefreshRate))
        end
    end)

    Scope:AddCleaner(function()
        Runtime.Running = false
        clearAll()
    end)

    task.defer(refreshRoles)
end

Base.Unload = function(Context, Scope, reason)
    if type(BaseUnload) == "function" then
        BaseUnload(Context, Scope, reason)
    end
end

return Base
