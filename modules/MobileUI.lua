-- Experiment17 - Mobile UI runtime fixes
return {
    Id = "MobileUI",
    Name = "Mobile UI",
    Version = "1.0.0",
    Order = 1001,
    TargetTab = "Visual",

    Init = function(Context, Scope, _Tab)
        local Library = Context.Library
        local UIS = Context.Services.UIS or game:GetService("UserInputService")
        local Workspace = Context.Services.Workspace or workspace

        -- Do not change desktop behavior. Tablets/phones normally have TouchEnabled.
        if not UIS.TouchEnabled then return end

        local State = Context:GetState("MobileUI", {
            TextScale = 185,
            DragMain = true,
            DragWatermark = true,
            DragMenuButton = true,
            HideKeybindUI = true,
            MainXScale = nil, MainXOffset = nil, MainYScale = nil, MainYOffset = nil,
            WatermarkXScale = nil, WatermarkXOffset = nil, WatermarkYScale = nil, WatermarkYOffset = nil,
            ButtonX = nil, ButtonY = nil,
        })

        local Root = Library and Library.Root
        local Main = Library and Library.Main
        local Watermark = Library and Library.Watermark
        if not Root then return end

        local function viewportSize()
            local camera = Workspace.CurrentCamera
            return camera and camera.ViewportSize or Vector2.new(1280, 720)
        end

        local function setTextScale(value)
            value = math.clamp(tonumber(value) or 185, 100, 200)
            State.TextScale = value
            if Library and type(Library.SetTextScale) == "function" then
                pcall(function() Library:SetTextScale(value) end)
            end
            for _, control in pairs((Library and Library.Controls) or {}) do
                if control and control.Flag == "UI_TextScale" and type(control.Set) == "function" then
                    pcall(function() control:Set(value, true) end)
                    break
                end
            end
        end

        local function hideKeybindUI()
            if not Library then return end
            Library.Settings = Library.Settings or {}
            Library.Settings.KeybindListEnabled = false
            if type(Library.RefreshKeybindList) == "function" then
                pcall(function() Library:RefreshKeybindList() end)
            end

            local settingsTab = Library.SettingsTab
            if settingsTab and type(settingsTab.Sections) == "table" then
                for _, section in ipairs(settingsTab.Sections) do
                    local key = tostring(section.LocaleKey or ""):lower()
                    if key:find("keybind", 1, true) and section.Frame then
                        section.Frame.Visible = false
                    end
                end
            end
        end

        local function restoreKeybindSections()
            local settingsTab = Library and Library.SettingsTab
            if settingsTab and type(settingsTab.Sections) == "table" then
                for _, section in ipairs(settingsTab.Sections) do
                    local key = tostring(section.LocaleKey or ""):lower()
                    if key:find("keybind", 1, true) and section.Frame then
                        section.Frame.Visible = true
                    end
                end
            end
        end

        local function findMobileButton()
            for _, object in ipairs(Root:GetChildren()) do
                if object:IsA("TextButton") then
                    local s = object.Size
                    if s.X.Scale == 0 and s.Y.Scale == 0 and s.X.Offset >= 48 and s.X.Offset <= 64 and s.Y.Offset >= 48 and s.Y.Offset <= 64 then
                        return object
                    end
                end
            end
            return nil
        end

        local MobileButton = findMobileButton()

        local function applySavedPositions()
            if Main and State.MainXScale ~= nil then
                Main.Position = UDim2.new(State.MainXScale, State.MainXOffset or 0, State.MainYScale or 0, State.MainYOffset or 0)
            end
            if Watermark and State.WatermarkXScale ~= nil then
                Watermark.Position = UDim2.new(State.WatermarkXScale, State.WatermarkXOffset or 0, State.WatermarkYScale or 0, State.WatermarkYOffset or 0)
            end
            if MobileButton and State.ButtonX ~= nil and State.ButtonY ~= nil then
                MobileButton.AnchorPoint = Vector2.new(0, 0)
                MobileButton.Position = UDim2.fromOffset(State.ButtonX, State.ButtonY)
            end
        end

        local function saveUDim2(prefix, pos)
            State[prefix .. "XScale"] = pos.X.Scale
            State[prefix .. "XOffset"] = pos.X.Offset
            State[prefix .. "YScale"] = pos.Y.Scale
            State[prefix .. "YOffset"] = pos.Y.Offset
        end

        local function inside(gui, p)
            if not gui or not gui.Parent or not gui.Visible then return false end
            local a, s = gui.AbsolutePosition, gui.AbsoluteSize
            return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
        end

        local Drag = nil
        local TOUCH_THRESHOLD = 7

        local function beginDrag(kind, gui, input)
            if not gui or Drag then return end
            Drag = {
                Kind = kind,
                Gui = gui,
                Input = input,
                StartInput = Vector2.new(input.Position.X, input.Position.Y),
                StartPos = gui.Position,
                StartAbs = gui.AbsolutePosition,
                Moved = false,
                DisabledButton = false,
            }
        end

        local function clampShift(drag, delta)
            local gui = drag.Gui
            local vp = viewportSize()
            local size = gui.AbsoluteSize
            local wanted = drag.StartAbs + delta

            if drag.Kind == "Main" then
                -- Keep a useful piece of the topbar on screen even if the user drags far away.
                local minVisibleX = math.min(120, size.X)
                local minVisibleY = math.min(56, size.Y)
                wanted = Vector2.new(
                    math.clamp(wanted.X, -size.X + minVisibleX, vp.X - minVisibleX),
                    math.clamp(wanted.Y, 0, vp.Y - minVisibleY)
                )
            else
                wanted = Vector2.new(
                    math.clamp(wanted.X, 4, math.max(4, vp.X - size.X - 4)),
                    math.clamp(wanted.Y, 4, math.max(4, vp.Y - size.Y - 4))
                )
            end

            return wanted - drag.StartAbs
        end

        Scope:TrackConnection(UIS.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch or Drag then return end
            local p = Vector2.new(input.Position.X, input.Position.Y)

            -- Floating GUI button gets priority over everything below it.
            if State.DragMenuButton and MobileButton and inside(MobileButton, p) then
                beginDrag("Button", MobileButton, input)
                return
            end

            if State.DragWatermark and Watermark and inside(Watermark, p) then
                beginDrag("Watermark", Watermark, input)
                return
            end

            if State.DragMain and Main and Library.MenuVisible ~= false and inside(Main, p) then
                local localX = p.X - Main.AbsolutePosition.X
                local localY = p.Y - Main.AbsolutePosition.Y
                -- Left part of topbar is a dedicated touch drag zone. Right side stays free for search/favorites/buttons.
                if localY <= math.max(58, Main.AbsoluteSize.Y * 0.12) and localX <= math.max(190, Main.AbsoluteSize.X * 0.46) then
                    beginDrag("Main", Main, input)
                end
            end
        end))

        Scope:TrackConnection(UIS.InputChanged:Connect(function(input)
            local drag = Drag
            if not drag or input ~= drag.Input or input.UserInputType ~= Enum.UserInputType.Touch then return end

            local now = Vector2.new(input.Position.X, input.Position.Y)
            local delta = now - drag.StartInput
            if not drag.Moved and delta.Magnitude < TOUCH_THRESHOLD then return end
            drag.Moved = true

            if drag.Kind == "Button" and not drag.DisabledButton then
                -- Cancels the button's normal Activated gesture once this becomes a drag.
                drag.DisabledButton = true
                pcall(function() drag.Gui.Active = false end)
            end

            local shift = clampShift(drag, delta)
            drag.Gui.Position = UDim2.new(
                drag.StartPos.X.Scale, drag.StartPos.X.Offset + shift.X,
                drag.StartPos.Y.Scale, drag.StartPos.Y.Offset + shift.Y
            )
        end))

        Scope:TrackConnection(UIS.InputEnded:Connect(function(input)
            local drag = Drag
            if not drag or input ~= drag.Input then return end

            if drag.Moved then
                if drag.Kind == "Main" then
                    saveUDim2("Main", drag.Gui.Position)
                elseif drag.Kind == "Watermark" then
                    saveUDim2("Watermark", drag.Gui.Position)
                elseif drag.Kind == "Button" then
                    local abs = drag.Gui.AbsolutePosition
                    drag.Gui.AnchorPoint = Vector2.new(0, 0)
                    drag.Gui.Position = UDim2.fromOffset(abs.X, abs.Y)
                    State.ButtonX, State.ButtonY = abs.X, abs.Y
                end
            end

            if drag.DisabledButton then
                task.defer(function()
                    if drag.Gui and drag.Gui.Parent then drag.Gui.Active = true end
                end)
            end
            Drag = nil
        end))

        local function resetPositions()
            State.MainXScale, State.MainXOffset, State.MainYScale, State.MainYOffset = nil, nil, nil, nil
            State.WatermarkXScale, State.WatermarkXOffset, State.WatermarkYScale, State.WatermarkYOffset = nil, nil, nil, nil
            State.ButtonX, State.ButtonY = nil, nil
            if Main then Main.Position = UDim2.fromScale(0.5, 0.5) end
            if Watermark then Watermark.AnchorPoint = Vector2.new(0,0); Watermark.Position = UDim2.fromOffset(16,16) end
            if MobileButton then MobileButton.AnchorPoint = Vector2.new(1,1); MobileButton.Position = UDim2.new(1,-18,1,-18) end
        end

        setTextScale(State.TextScale)
        applySavedPositions()
        if State.HideKeybindUI then hideKeybindUI() end

        -- Re-apply after configs/modules finish touching the same UI state.
        local running = true
        Scope:AddCleaner(function() running = false end)
        task.spawn(function()
            while running do
                if State.HideKeybindUI then hideKeybindUI() end
                task.wait(1.0)
            end
        end)

        local settingsTab = Library.SettingsTab
        if settingsTab and type(settingsTab.CreateSection) == "function" then
            local Mobile = settingsTab:CreateSection("Mobile UI", false, "Mobile UI")
            Mobile:AddSlider({Name="Mobile Text Size",Flag="Mobile_TextScale",Min=120,Max=200,Default=State.TextScale,Decimals=0,RequiredGraphics="Low",Callback=setTextScale})
            Mobile:AddToggle({Name="Drag Main Window",Flag="Mobile_DragMain",Default=State.DragMain,RequiredGraphics="Low",Callback=function(v) State.DragMain=v end})
            Mobile:AddToggle({Name="Drag Watermark",Flag="Mobile_DragWatermark",Default=State.DragWatermark,RequiredGraphics="Low",Callback=function(v) State.DragWatermark=v end})
            Mobile:AddToggle({Name="Drag GUI Button",Flag="Mobile_DragButton",Default=State.DragMenuButton,RequiredGraphics="Low",Callback=function(v) State.DragMenuButton=v end})
            Mobile:AddToggle({Name="Hide Keybind UI On Touch",Flag="Mobile_HideKeybinds",Default=State.HideKeybindUI,RequiredGraphics="Low",Callback=function(v) State.HideKeybindUI=v; if v then hideKeybindUI() else restoreKeybindSections() end end})
            Mobile:AddButton({Name="Reset Mobile Positions",ButtonText="Reset",RequiredGraphics="Low",Callback=resetPositions})
        end

        Context.Shared.MobileUI = {
            IsTouch = true,
            ResetPositions = resetPositions,
            GetMobileButton = function() return MobileButton end,
        }
    end,
}