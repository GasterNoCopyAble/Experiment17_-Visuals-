-- Experiment17 - Mobile UI runtime fixes
return {
    Id = "MobileUI",
    Name = "Mobile UI",
    Version = "1.1.0",
    Order = 1001,
    TargetTab = "Visual",

    Init = function(Context, Scope, _Tab)
        local Library = Context.Library
        local UIS = Context.Services.UIS or game:GetService("UserInputService")
        local Workspace = Context.Services.Workspace or workspace
        local RunService = Context.Services.RunService or game:GetService("RunService")

        -- Desktop keeps the original GuiLib behavior.
        if not UIS.TouchEnabled then return end

        local State = Context:GetState("MobileUI", {
            TextScale = 185,

            -- Watermark has its own mobile scale. It intentionally does NOT
            -- follow the large menu text scale used on phones.
            WatermarkTextSize = 13,
            WatermarkScale = 0.82,

            DragMain = true,
            DragWatermark = true,
            DragMenuButton = true,
            HideKeybindUI = true,

            MainXScale = nil,
            MainXOffset = nil,
            MainYScale = nil,
            MainYOffset = nil,

            WatermarkX = nil,
            WatermarkY = nil,

            ButtonXScale = nil,
            ButtonXOffset = nil,
            ButtonYScale = nil,
            ButtonYOffset = nil,
        })

        local Root = Library and Library.Root
        local Main = Library and Library.Main
        local Watermark = Library and Library.Watermark
        local WatermarkLabel = Library and Library.WatermarkLabel
        if not Root then return end

        local function viewportSize()
            local camera = Workspace.CurrentCamera
            return camera and camera.ViewportSize or Vector2.new(1280, 720)
        end

        local function setTextScale(value)
            value = math.clamp(tonumber(value) or 185, 100, 200)
            State.TextScale = value

            if Library and type(Library.SetTextScale) == "function" then
                pcall(function()
                    Library:SetTextScale(value)
                end)
            end

            for _, control in pairs((Library and Library.Controls) or {}) do
                if control and control.Flag == "UI_TextScale" and type(control.Set) == "function" then
                    pcall(function()
                        control:Set(value, true)
                    end)
                    break
                end
            end
        end

        --========================================================
        -- MOBILE WATERMARK STYLE
        --========================================================

        local WatermarkScaleObject

        local function ensureWatermarkScale()
            if not Watermark or not Watermark.Parent then return nil end

            local scale = Watermark:FindFirstChild("E17_MobileWatermarkScale")
            if not scale then
                scale = Instance.new("UIScale")
                scale.Name = "E17_MobileWatermarkScale"
                scale.Parent = Watermark
            end

            WatermarkScaleObject = scale
            return scale
        end

        local function applyWatermarkStyle(refresh)
            if not Watermark or not Watermark.Parent then return end

            State.WatermarkTextSize = math.floor(math.clamp(tonumber(State.WatermarkTextSize) or 13, 9, 20))
            State.WatermarkScale = math.clamp(tonumber(State.WatermarkScale) or 0.82, 0.55, 1.15)

            local scale = ensureWatermarkScale()
            if scale then
                scale.Scale = State.WatermarkScale
            end

            if WatermarkLabel and WatermarkLabel.Parent then
                WatermarkLabel.TextSize = State.WatermarkTextSize
            end

            if refresh and Library and type(Library.RefreshWatermark) == "function" then
                pcall(function()
                    Library:RefreshWatermark()
                end)
            end
        end

        --========================================================
        -- KEYBINDS HIDDEN ON TOUCH
        --========================================================

        local function hideKeybindUI()
            if not Library then return end

            Library.Settings = Library.Settings or {}
            Library.Settings.KeybindListEnabled = false

            if type(Library.RefreshKeybindList) == "function" then
                pcall(function()
                    Library:RefreshKeybindList()
                end)
            end

            local settingsTab = Library.SettingsTab
            if settingsTab and type(settingsTab.Sections) == "table" then
                for _, section in ipairs(settingsTab.Sections) do
                    local key = tostring(section.LocaleKey or section.Title or ""):lower()
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
                    local key = tostring(section.LocaleKey or section.Title or ""):lower()
                    if key:find("keybind", 1, true) and section.Frame then
                        section.Frame.Visible = true
                    end
                end
            end
        end

        --========================================================
        -- FIND FLOATING MOBILE MENU BUTTON
        --========================================================

        local function findMobileButton()
            for _, object in ipairs(Root:GetChildren()) do
                if object:IsA("TextButton") then
                    local s = object.Size
                    if s.X.Scale == 0
                        and s.Y.Scale == 0
                        and s.X.Offset >= 48
                        and s.X.Offset <= 64
                        and s.Y.Offset >= 48
                        and s.Y.Offset <= 64
                    then
                        return object
                    end
                end
            end
            return nil
        end

        local MobileButton = findMobileButton()

        --========================================================
        -- POSITION HELPERS
        --========================================================

        local function saveUDim2(prefix, pos)
            State[prefix .. "XScale"] = pos.X.Scale
            State[prefix .. "XOffset"] = pos.X.Offset
            State[prefix .. "YScale"] = pos.Y.Scale
            State[prefix .. "YOffset"] = pos.Y.Offset
        end

        local function syncWatermarkPosition(x, y, apply)
            if not Watermark then return end

            local vp = viewportSize()
            local size = Watermark.AbsoluteSize
            if size.X <= 0 or size.Y <= 0 then
                size = Vector2.new(
                    math.max(1, Watermark.Size.X.Offset * State.WatermarkScale),
                    math.max(1, Watermark.Size.Y.Offset * State.WatermarkScale)
                )
            end

            x = math.clamp(tonumber(x) or 16, 4, math.max(4, vp.X - size.X - 4))
            y = math.clamp(tonumber(y) or 16, 4, math.max(4, vp.Y - size.Y - 4))

            State.WatermarkX = x
            State.WatermarkY = y

            -- This is the important fix: GuiLib calls RefreshWatermark often,
            -- and RefreshWatermark calls ApplyWatermarkPosition. Therefore the
            -- mobile drag must update the same settings used by GuiLib.
            Library.Settings = Library.Settings or {}
            Library.Settings.WatermarkX = x
            Library.Settings.WatermarkY = y

            if apply then
                Watermark.AnchorPoint = Vector2.new(0, 0)
                Watermark.Position = UDim2.fromOffset(x, y)
            end
        end

        local function migrateOldWatermarkState()
            if State.WatermarkX ~= nil and State.WatermarkY ~= nil then return end

            -- v1.0 stored the watermark as a UDim2. Recover an old offset-only
            -- position when possible instead of forcing the watermark to reset.
            if State.WatermarkXScale ~= nil then
                local vp = viewportSize()
                local x = vp.X * (tonumber(State.WatermarkXScale) or 0) + (tonumber(State.WatermarkXOffset) or 0)
                local y = vp.Y * (tonumber(State.WatermarkYScale) or 0) + (tonumber(State.WatermarkYOffset) or 0)
                syncWatermarkPosition(x, y, false)
            end
        end

        local function applySavedPositions()
            if Main and State.MainXScale ~= nil then
                Main.Position = UDim2.new(
                    State.MainXScale,
                    State.MainXOffset or 0,
                    State.MainYScale or 0,
                    State.MainYOffset or 0
                )
            end

            migrateOldWatermarkState()

            if Watermark then
                local x = State.WatermarkX
                local y = State.WatermarkY

                if x == nil and Library.Settings then
                    local libraryX = tonumber(Library.Settings.WatermarkX)
                    local libraryY = tonumber(Library.Settings.WatermarkY)
                    if libraryX and libraryX >= 0 then
                        x, y = libraryX, libraryY or 16
                    end
                end

                if x ~= nil then
                    syncWatermarkPosition(x, y or 16, true)
                elseif Library and type(Library.ApplyWatermarkPosition) == "function" then
                    pcall(function()
                        Library:ApplyWatermarkPosition()
                    end)
                end
            end

            if MobileButton and State.ButtonXScale ~= nil then
                -- Keep the original AnchorPoint. Changing it on release was the
                -- reason the button jumped upward on phones with a GUI inset.
                MobileButton.Position = UDim2.new(
                    State.ButtonXScale,
                    State.ButtonXOffset or 0,
                    State.ButtonYScale or 0,
                    State.ButtonYOffset or 0
                )
            end
        end

        --========================================================
        -- TOUCH DRAGGING
        --========================================================

        local Drag = nil
        local TOUCH_THRESHOLD = 7

        local function inside(gui, p)
            if not gui or not gui.Parent or not gui.Visible then return false end
            local a = gui.AbsolutePosition
            local s = gui.AbsoluteSize
            return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
        end

        local function clampAbsolute(kind, gui, wanted)
            local vp = viewportSize()
            local size = gui.AbsoluteSize

            if kind == "Main" then
                local minVisibleX = math.min(120, size.X)
                local minVisibleY = math.min(56, size.Y)
                return Vector2.new(
                    math.clamp(wanted.X, -size.X + minVisibleX, vp.X - minVisibleX),
                    math.clamp(wanted.Y, 0, vp.Y - minVisibleY)
                )
            end

            return Vector2.new(
                math.clamp(wanted.X, 4, math.max(4, vp.X - size.X - 4)),
                math.clamp(wanted.Y, 4, math.max(4, vp.Y - size.Y - 4))
            )
        end

        local function finishDrag(drag)
            if Drag ~= drag then return end

            if drag.Moved then
                if drag.Kind == "Main" then
                    saveUDim2("Main", drag.Gui.Position)

                elseif drag.Kind == "Watermark" then
                    local abs = drag.Gui.AbsolutePosition
                    syncWatermarkPosition(abs.X, abs.Y, true)

                elseif drag.Kind == "Button" then
                    -- Preserve Position + AnchorPoint exactly as they are.
                    -- No AbsolutePosition -> AnchorPoint conversion on release.
                    saveUDim2("Button", drag.Gui.Position)
                end
            end

            if drag.DisabledButton then
                local gui = drag.Gui
                task.delay(0.05, function()
                    if gui and gui.Parent then
                        gui.Active = true
                    end
                end)
            end

            Drag = nil
        end

        local function beginDrag(kind, gui, input)
            if not gui or Drag then return end

            local drag = {
                Kind = kind,
                Gui = gui,
                Input = input,
                StartInput = Vector2.new(input.Position.X, input.Position.Y),
                StartPos = gui.Position,
                StartAbs = gui.AbsolutePosition,
                Moved = false,
                DisabledButton = false,
            }

            Drag = drag

            -- Touch InputObjects update their Position while the finger moves.
            -- Reading the same object every frame is more reliable across
            -- mobile executors than comparing InputChanged objects by identity.
            local endedConnection
            endedConnection = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End
                    or input.UserInputState == Enum.UserInputState.Cancel
                then
                    if endedConnection then
                        endedConnection:Disconnect()
                        endedConnection = nil
                    end
                    finishDrag(drag)
                end
            end)

            Scope:TrackConnection(endedConnection)
        end

        Scope:TrackConnection(UIS.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch or Drag then return end

            local p = Vector2.new(input.Position.X, input.Position.Y)

            -- Floating GUI button has highest priority.
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

                -- Left part of the topbar is the phone drag zone. Right side
                -- stays usable for search/favorites/topbar buttons.
                if localY <= math.max(58, Main.AbsoluteSize.Y * 0.12)
                    and localX <= math.max(190, Main.AbsoluteSize.X * 0.46)
                then
                    beginDrag("Main", Main, input)
                end
            end
        end))

        Scope:TrackConnection(RunService.RenderStepped:Connect(function()
            local drag = Drag
            if not drag or not drag.Gui or not drag.Gui.Parent then return end

            local input = drag.Input
            if not input then return end

            local now = Vector2.new(input.Position.X, input.Position.Y)
            local delta = now - drag.StartInput

            if not drag.Moved and delta.Magnitude < TOUCH_THRESHOLD then
                return
            end

            drag.Moved = true

            if drag.Kind == "Button" and not drag.DisabledButton then
                drag.DisabledButton = true
                pcall(function()
                    drag.Gui.Active = false
                end)
            end

            local wanted = clampAbsolute(drag.Kind, drag.Gui, drag.StartAbs + delta)
            local shift = wanted - drag.StartAbs

            if drag.Kind == "Watermark" then
                -- Watermark is top-left anchored and GuiLib itself reads these
                -- exact coordinates during RefreshWatermark().
                syncWatermarkPosition(wanted.X, wanted.Y, true)
            else
                drag.Gui.Position = UDim2.new(
                    drag.StartPos.X.Scale,
                    drag.StartPos.X.Offset + shift.X,
                    drag.StartPos.Y.Scale,
                    drag.StartPos.Y.Offset + shift.Y
                )
            end
        end))

        --========================================================
        -- RESET
        --========================================================

        local function resetPositions()
            State.MainXScale = nil
            State.MainXOffset = nil
            State.MainYScale = nil
            State.MainYOffset = nil

            State.WatermarkX = nil
            State.WatermarkY = nil
            State.WatermarkXScale = nil
            State.WatermarkXOffset = nil
            State.WatermarkYScale = nil
            State.WatermarkYOffset = nil

            State.ButtonXScale = nil
            State.ButtonXOffset = nil
            State.ButtonYScale = nil
            State.ButtonYOffset = nil
            State.ButtonX = nil
            State.ButtonY = nil

            if Main then
                Main.Position = UDim2.fromScale(0.5, 0.5)
            end

            if Watermark then
                Library.Settings.WatermarkX = -1
                Library.Settings.WatermarkY = 16
                if type(Library.ApplyWatermarkPosition) == "function" then
                    pcall(function()
                        Library:ApplyWatermarkPosition()
                    end)
                end
            end

            if MobileButton then
                MobileButton.AnchorPoint = Vector2.new(1, 1)
                MobileButton.Position = UDim2.new(1, -18, 1, -18)
            end
        end

        --========================================================
        -- APPLY MOBILE MODE
        --========================================================

        setTextScale(State.TextScale)
        applyWatermarkStyle(true)
        applySavedPositions()

        if State.HideKeybindUI then
            hideKeybindUI()
        end

        -- GuiLib may reapply text scale / watermark measurements after config
        -- loading. Keep only the mobile-specific watermark text size pinned;
        -- position remains owned by Library.Settings.WatermarkX/Y.
        local running = true
        Scope:AddCleaner(function()
            running = false
        end)

        task.spawn(function()
            while running do
                if State.HideKeybindUI then
                    hideKeybindUI()
                end

                local changed = false
                if WatermarkLabel and WatermarkLabel.Parent and WatermarkLabel.TextSize ~= State.WatermarkTextSize then
                    WatermarkLabel.TextSize = State.WatermarkTextSize
                    changed = true
                end

                local scale = ensureWatermarkScale()
                if scale and math.abs(scale.Scale - State.WatermarkScale) > 0.001 then
                    scale.Scale = State.WatermarkScale
                    changed = true
                end

                if changed and Library and type(Library.RefreshWatermark) == "function" then
                    pcall(function()
                        Library:RefreshWatermark()
                    end)
                end

                task.wait(0.75)
            end
        end)

        --========================================================
        -- SETTINGS
        --========================================================

        local settingsTab = Library.SettingsTab
        if settingsTab and type(settingsTab.CreateSection) == "function" then
            local Mobile = settingsTab:CreateSection("Mobile UI", false, "Mobile UI")

            Mobile:AddSlider({
                Name = "Mobile Menu Text Size",
                Flag = "Mobile_TextScale",
                Min = 120,
                Max = 200,
                Default = State.TextScale,
                Decimals = 0,
                RequiredGraphics = "Low",
                Callback = function(v)
                    setTextScale(v)
                    -- SetTextScale also touches WatermarkLabel, so restore the
                    -- separate mobile watermark size immediately.
                    applyWatermarkStyle(true)
                end,
            })

            Mobile:AddSlider({
                Name = "Watermark Text Size",
                Flag = "Mobile_WatermarkText",
                Min = 9,
                Max = 20,
                Default = State.WatermarkTextSize,
                Decimals = 0,
                RequiredGraphics = "Low",
                Callback = function(v)
                    State.WatermarkTextSize = math.floor(v)
                    applyWatermarkStyle(true)
                end,
            })

            Mobile:AddSlider({
                Name = "Watermark Scale",
                Flag = "Mobile_WatermarkScale",
                Min = 0.55,
                Max = 1.15,
                Default = State.WatermarkScale,
                Decimals = 2,
                RequiredGraphics = "Low",
                Callback = function(v)
                    State.WatermarkScale = v
                    applyWatermarkStyle(true)
                end,
            })

            Mobile:AddToggle({Name="Drag Main Window",Flag="Mobile_DragMain",Default=State.DragMain,RequiredGraphics="Low",Callback=function(v) State.DragMain=v end})
            Mobile:AddToggle({Name="Drag Watermark",Flag="Mobile_DragWatermark",Default=State.DragWatermark,RequiredGraphics="Low",Callback=function(v) State.DragWatermark=v end})
            Mobile:AddToggle({Name="Drag GUI Button",Flag="Mobile_DragButton",Default=State.DragMenuButton,RequiredGraphics="Low",Callback=function(v) State.DragMenuButton=v end})
            Mobile:AddToggle({Name="Hide Keybind UI On Touch",Flag="Mobile_HideKeybinds",Default=State.HideKeybindUI,RequiredGraphics="Low",Callback=function(v) State.HideKeybindUI=v; if v then hideKeybindUI() else restoreKeybindSections() end end})
            Mobile:AddButton({Name="Reset Mobile Positions",ButtonText="Reset",RequiredGraphics="Low",Callback=resetPositions})
        end

        Context.Shared.MobileUI = {
            IsTouch = true,
            ResetPositions = resetPositions,
            GetMobileButton = function()
                return MobileButton
            end,
            SetWatermarkPosition = function(x, y)
                syncWatermarkPosition(x, y, true)
            end,
        }
    end,
}
