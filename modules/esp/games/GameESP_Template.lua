--[[
    Experiment 17 - Game-specific ESP template

    1. Rename this file, e.g. Doors.lua
    2. Add the raw path to modules/esp/registry.json for a PlaceId/GameId.
    3. Put game-specific object ESP / path discovery in the Custom section.

    It extends Universal.lua so all normal player/tool/radar ESP remains present.
]]

local UNIVERSAL_URL = "https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/modules/esp/Universal.lua"
local source = game:HttpGet(UNIVERSAL_URL, true)
local Base = assert(loadstring(source, "=Experiment17_UniversalESP"))()

local BaseInit = Base.Init
local BaseUnload = Base.Unload
Base.Version = tostring(Base.Version or "0") .. "+game-template"

Base.Init = function(Context, Scope, Tab)
    if type(BaseInit) == "function" then
        BaseInit(Context, Scope, Tab)
    end

    local State = Context:GetState("ESP_GameSpecific", {
        Enabled = false,
        ObjectName = "",
        Color = Color3.fromRGB(255, 210, 80),
    })

    local Runtime = {
        Highlights = setmetatable({}, {__mode = "k"}),
    }

    local function clear()
        for object, highlight in pairs(Runtime.Highlights) do
            if highlight then pcall(function() highlight:Destroy() end) end
            Runtime.Highlights[object] = nil
        end
    end

    local function scan()
        clear()
        if not State.Enabled or State.ObjectName == "" then return end
        for _, object in ipairs(workspace:GetDescendants()) do
            if object.Name == State.ObjectName and (object:IsA("Model") or object:IsA("BasePart")) then
                local h = Instance.new("Highlight")
                h.Name = "E17_GameESP"
                h.Adornee = object
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.FillColor = State.Color
                h.OutlineColor = State.Color
                h.FillTransparency = 0.75
                h.OutlineTransparency = 0.1
                h.Parent = workspace
                Runtime.Highlights[object] = h
            end
        end
    end

    local Custom = Context:CreateSection(Scope, Tab, "Game-specific ESP", false, "ESP / Game-specific")
    Custom:AddToggle({
        Name = "Enable Object ESP",
        Flag = "ESP_Game_ObjectEnabled",
        Default = State.Enabled,
        RequiredGraphics = "Low",
        FPSImpact = {-3, 0},
        Description = "Template scanner for this game's named objects. Replace this with direct game paths for better performance.",
        Callback = function(v) State.Enabled = v; scan() end,
    })
    Custom:AddInput({
        Name = "Object Name",
        Flag = "ESP_Game_ObjectName",
        Default = State.ObjectName,
        Placeholder = "Exact object name",
        RequiredGraphics = "Low",
        Callback = function(v) State.ObjectName = tostring(v or "") end,
    })
    Custom:AddColorPicker({
        Name = "Object Color",
        Flag = "ESP_Game_ObjectColor",
        Default = State.Color,
        RequiredGraphics = "Low",
        Callback = function(v) State.Color = v; if State.Enabled then scan() end end,
    })
    Custom:AddButton({Name = "Rescan Game Objects", ButtonText = "Scan", RequiredGraphics = "Low", Callback = scan})

    Scope:AddCleaner(clear)
end

Base.Unload = function(Context, Scope, reason)
    if type(BaseUnload) == "function" then
        BaseUnload(Context, Scope, reason)
    end
end

return Base
