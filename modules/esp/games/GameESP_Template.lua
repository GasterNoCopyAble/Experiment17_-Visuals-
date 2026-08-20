--[[
    Experiment 17 - Standalone game-specific ESP template

    1. Rename this file, e.g. Doors.lua
    2. Add its path to modules/esp/registry.json for a PlaceId/GameId.
    3. Build only the ESP needed by that game.

    IMPORTANT: game-specific ESP profiles are standalone. Do NOT import
    Universal.lua here. The router loads Universal only when no specific
    profile matches, preventing two ESP renderers from fighting each other.
]]

return {
    Id = "ESP",
    Name = "Game-specific ESP",
    Version = "2.0.0-template",
    Order = 30,

    Init = function(Context, Scope, Tab)
        local State = Context:GetState("ESP_GameSpecific", {
            Enabled = false,
            ObjectName = "",
            Color = Color3.fromRGB(255, 210, 80),
        })

        local Runtime = {Highlights = setmetatable({}, {__mode = "k"})}

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
        Custom:AddToggle({Name="Enable Object ESP",Flag="ESP_Game_ObjectEnabled",Default=State.Enabled,RequiredGraphics="Low",FPSImpact={-3,0},Description="Template scanner. Prefer direct game paths/events instead of broad scans in production profiles.",Callback=function(v) State.Enabled=v; scan() end})
        Custom:AddInput({Name="Object Name",Flag="ESP_Game_ObjectName",Default=State.ObjectName,Placeholder="Exact object name",RequiredGraphics="Low",Callback=function(v) State.ObjectName=tostring(v or "") end})
        Custom:AddColorPicker({Name="Object Color",Flag="ESP_Game_ObjectColor",Default=State.Color,RequiredGraphics="Low",Callback=function(v) State.Color=v; if State.Enabled then scan() end end})
        Custom:AddButton({Name="Rescan Game Objects",ButtonText="Scan",RequiredGraphics="Low",Callback=scan})

        Context.Shared.ESPProfile = "GameSpecific"
        Scope:AddCleaner(clear)
    end,
}
