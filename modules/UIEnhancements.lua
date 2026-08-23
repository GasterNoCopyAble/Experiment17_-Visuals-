-- Experiment17 - small integrations layered on top of GuiLib v21
-- v21 already owns mobile dragging, watermark dragging, sliders, color picker,
-- notifications, gradients, Settings-last ordering, search and Favorites.

return {
    Id = "UIEnhancements",
    Name = "UI Enhancements",
    Version = "2.0.0-v21",
    Order = 1000,
    TargetTab = "Visual",

    Init = function(Context, Scope, _Tab)
        local Library = Context.Library
        local ENV = (getgenv and getgenv()) or _G
        local UIS = Context.Services.UIS or game:GetService("UserInputService")
        local Players = Context.Services.Players or game:GetService("Players")
        local LocalPlayer = Context.LocalPlayer or Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local IsTouch = UIS.TouchEnabled == true

        local State = Context:GetState("UIEnhancements", {
            CursorKey = "Insert",
            XRayKey = "Home",
            ThirdPersonKey = "V",
            MusicKey = "M",
            ESPKey = "F6",
            EchoKey = "F7",
            DamageKey = "F8",
            LightingKey = "F9",
            SearchKey = "F3",
            FavoritesKey = "F4",
            NotifyQuickActions = true,
            FavoriteStars = true,
            ForceCursorTopmost = true,
        })

        local function notify(text, kind)
            if not State.NotifyQuickActions then return end
            if Library and type(Library.Notify) == "function" then
                pcall(function()
                    Library:Notify({
                        Title = "Experiment 17",
                        Text = tostring(text),
                        Type = kind or "Info",
                        Duration = IsTouch and 2.1 or 2.6,
                    })
                end)
            end
        end

        -- GuiLib v21 guarantees Settings is the final sidebar tab. Keep
        -- Performance near the bottom without ever trying to move Settings.
        local function applyPerformanceOrder()
            local performance = Context:GetTab("Performance")
            if performance and performance.Button then
                performance.Button.LayoutOrder = 900
            end
        end

        local function forceCursorTop()
            if not State.ForceCursorTopmost then return end
            for _, object in ipairs(PlayerGui:GetChildren()) do
                if object:IsA("ScreenGui") and object.Name == "Experiment17_Visual_Cursor" then
                    pcall(function()
                        object.DisplayOrder = 2147483646
                        object.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                    end)
                end
            end
        end

        local function findControl(flag)
            if not Library then return nil end
            if Library.ControlsByFlag and Library.ControlsByFlag[flag] then
                return Library.ControlsByFlag[flag]
            end
            for _, control in pairs(Library.Controls or {}) do
                if control and control.Flag == flag then
                    return control
                end
            end
            return nil
        end

        local function toggleControl(flag, label)
            local control = findControl(flag)
            if not control or type(control.Get) ~= "function" or type(control.Set) ~= "function" then
                notify((label or flag) .. " is not loaded", "Warning")
                return false
            end

            local ok, current = pcall(function()
                return control:Get()
            end)
            if not ok or type(current) ~= "boolean" then
                notify((label or flag) .. " is not a toggle", "Warning")
                return false
            end

            pcall(function()
                control:Set(not current)
            end)
            notify((label or flag) .. ": " .. ((not current) and "ON" or "OFF"), "Info")
            return true
        end

        local function toggleFirst(flags, label)
            for _, flag in ipairs(flags) do
                if findControl(flag) then
                    return toggleControl(flag, label)
                end
            end
            notify((label or "Function") .. " is not loaded", "Warning")
            return false
        end

        local function toggleMusic()
            local music = Context.Shared and Context.Shared.Music
            if music and type(music.Toggle) == "function" then
                music.Toggle()
            else
                notify("Music module is not loaded", "Warning")
            end
        end

        local function findSearchBox()
            local root = Library and Library.Root
            if not root then return nil end
            for _, object in ipairs(root:GetDescendants()) do
                if object:IsA("TextBox") then
                    local placeholder = tostring(object.PlaceholderText or ""):lower()
                    if placeholder:find("search", 1, true) or placeholder:find("поиск", 1, true) then
                        return object
                    end
                end
            end
            return nil
        end

        local function findFavoritesButton()
            local root = Library and Library.Root
            if not root then return nil end
            for _, object in ipairs(root:GetDescendants()) do
                if object:IsA("TextButton") then
                    local text = tostring(object.Text or "")
                    if text:find("★", 1, true) then
                        local size = object.Size
                        if size.X.Offset <= 56 and size.Y.Offset <= 46 then
                            return object
                        end
                    end
                end
            end
            return nil
        end

        local FavoritesButton = findFavoritesButton()

        local function focusSearch()
            local box = findSearchBox()
            if box then
                pcall(function() box:CaptureFocus() end)
            else
                notify("Search field not found", "Warning")
            end
        end

        local function toggleFavoritesPanel()
            FavoritesButton = FavoritesButton and FavoritesButton.Parent and FavoritesButton or findFavoritesButton()
            if not FavoritesButton then
                notify("Favorites button not found", "Warning")
                return
            end

            local fire = ENV.firesignal or _G.firesignal
            local ok = false
            if type(fire) == "function" then
                ok = pcall(fire, FavoritesButton.MouseButton1Click)
            end
            if not ok then
                ok = pcall(function() FavoritesButton:Activate() end)
            end
            if not ok then
                notify("Favorites button could not be activated", "Warning")
            end
        end

        local function validKey(name)
            return type(name) == "string" and Enum.KeyCode[name] ~= nil
        end

        local function pressed(input, name)
            return input.UserInputType == Enum.UserInputType.Keyboard
                and validKey(name)
                and input.KeyCode == Enum.KeyCode[name]
        end

        -- Phones do not need a second custom keybind layer. GuiLib v21 owns
        -- the floating mobile GUI button and all touch interaction itself.
        if not IsTouch then
            Scope:TrackConnection(UIS.InputBegan:Connect(function(input, processed)
                if processed or UIS:GetFocusedTextBox() then return end

                if pressed(input, State.CursorKey) then
                    toggleControl("Visual_CustomCursor", "Cursor")
                elseif pressed(input, State.XRayKey) then
                    toggleControl("World_XRay", "X-Ray")
                elseif pressed(input, State.ThirdPersonKey) then
                    toggleControl("Player_ThirdPerson", "Third Person")
                elseif pressed(input, State.MusicKey) then
                    toggleMusic()
                elseif pressed(input, State.ESPKey) then
                    toggleFirst({"ESP_MM2_Enabled", "ESP_Enabled"}, "ESP")
                elseif pressed(input, State.EchoKey) then
                    toggleFirst({"World_EchoPlus", "World_Echo"}, "Movement Echo")
                elseif pressed(input, State.DamageKey) then
                    toggleFirst({"ESP_DamagePlus", "ESP_Damage"}, "Damage Visualizer")
                elseif pressed(input, State.LightingKey) then
                    toggleFirst({"LightingPlus_Master", "Lighting_Rainbow"}, "Lighting")
                elseif pressed(input, State.SearchKey) then
                    focusSearch()
                elseif pressed(input, State.FavoritesKey) then
                    toggleFavoritesPanel()
                end
            end))
        end

        -- GuiLib already has Favorites in the topbar/context menu. The small
        -- star remains useful on touch because it gives phones a one-tap way
        -- to favorite a function without needing a mouse right-click.
        local decorated = setmetatable({}, {__mode = "k"})

        local function isFavorite(control)
            if Library and type(Library.IsFavorite) == "function" then
                local ok, result = pcall(function()
                    return Library:IsFavorite(control)
                end)
                return ok and result == true
            end
            return false
        end

        local function refreshFavoriteStar(control, star)
            if not star or not star.Parent then return end
            local favorite = isFavorite(control)
            star.Text = favorite and "★" or "☆"
            star.TextTransparency = favorite and 0 or 0.18
            star.TextColor3 = favorite and Library.Theme.Accent or Library.Theme.SubText
        end

        local function decorateControl(control)
            if not State.FavoriteStars or not control or decorated[control] then return end
            local holder = control.Holder
            if not holder or not holder.Parent or not holder:IsA("GuiObject") then return end

            local existing = holder:FindFirstChild("E17_FavoriteStar")
            if existing then
                decorated[control] = existing
                return
            end

            local star = Instance.new("TextButton")
            star.Name = "E17_FavoriteStar"
            star.AnchorPoint = Vector2.new(0, 0.5)
            star.Position = UDim2.new(0, IsTouch and 7 or 5, 0.5, 0)
            star.Size = UDim2.fromOffset(IsTouch and 24 or 18, IsTouch and 28 or 22)
            star.BackgroundTransparency = 1
            star.Text = "☆"
            star.TextSize = IsTouch and 18 or 15
            star.Font = Enum.Font.GothamBold
            star.AutoButtonColor = false
            star.ZIndex = math.max(70, holder.ZIndex + 20)
            star.Parent = holder

            local displayName = tostring(control.DisplayName or "")
            if displayName ~= "" then
                for _, child in ipairs(holder:GetDescendants()) do
                    if child:IsA("TextLabel") and child.Text == displayName then
                        local position = child.Position
                        if position.X.Offset < 34 then
                            child.Position = UDim2.new(position.X.Scale, position.X.Offset + (IsTouch and 25 or 18), position.Y.Scale, position.Y.Offset)
                        end
                        break
                    end
                end
            end

            star.Activated:Connect(function()
                if Library and type(Library.SetFavorite) == "function" then
                    pcall(function()
                        Library:SetFavorite(control, not isFavorite(control))
                    end)
                end
                refreshFavoriteStar(control, star)
            end)

            decorated[control] = star
            refreshFavoriteStar(control, star)
        end

        local running = true
        Scope:AddCleaner(function()
            running = false
        end)

        task.spawn(function()
            while running and not Context.Unloaded do
                applyPerformanceOrder()
                forceCursorTop()

                if State.FavoriteStars then
                    for _, control in pairs(Library.Controls or {}) do
                        decorateControl(control)
                        local star = decorated[control]
                        if typeof(star) == "Instance" then
                            refreshFavoriteStar(control, star)
                        end
                    end
                end

                task.wait(0.75)
            end
        end)

        local SettingsTab = Library and Library.SettingsTab
        if SettingsTab and type(SettingsTab.CreateSection) == "function" then
            -- Keybind editing is desktop-only. On phones the library's native
            -- mobile button is the menu entrypoint, so this section is omitted.
            if not IsTouch then
                local Keybinds = SettingsTab:CreateSection("Quick Keybinds", false, "Quick Keybinds")
                Keybinds:AddKeybind({Name="Toggle Custom Cursor",Flag="UIX_CursorKey",Default=State.CursorKey,RequiredGraphics="Low",Callback=function(v) State.CursorKey=v end})
                Keybinds:AddKeybind({Name="Toggle X-Ray",Flag="UIX_XRayKey",Default=State.XRayKey,RequiredGraphics="Low",Callback=function(v) State.XRayKey=v end})
                Keybinds:AddKeybind({Name="Toggle Third Person",Flag="UIX_ThirdPersonKey",Default=State.ThirdPersonKey,RequiredGraphics="Low",Callback=function(v) State.ThirdPersonKey=v end})
                Keybinds:AddKeybind({Name="Music Play / Pause",Flag="UIX_MusicKey",Default=State.MusicKey,RequiredGraphics="Low",Callback=function(v) State.MusicKey=v end})
                Keybinds:AddKeybind({Name="Toggle ESP",Flag="UIX_ESPKey",Default=State.ESPKey,RequiredGraphics="Low",Callback=function(v) State.ESPKey=v end})
                Keybinds:AddKeybind({Name="Toggle Movement Echo",Flag="UIX_EchoKey",Default=State.EchoKey,RequiredGraphics="Low",Callback=function(v) State.EchoKey=v end})
                Keybinds:AddKeybind({Name="Toggle Damage Visualizer",Flag="UIX_DamageKey",Default=State.DamageKey,RequiredGraphics="Low",Callback=function(v) State.DamageKey=v end})
                Keybinds:AddKeybind({Name="Toggle Lighting+",Flag="UIX_LightingKey",Default=State.LightingKey,RequiredGraphics="Low",Callback=function(v) State.LightingKey=v end})
                Keybinds:AddKeybind({Name="Focus Search",Flag="UIX_SearchKey",Default=State.SearchKey,RequiredGraphics="Low",Callback=function(v) State.SearchKey=v end})
                Keybinds:AddKeybind({Name="Open Favorites",Flag="UIX_FavoritesKey",Default=State.FavoritesKey,RequiredGraphics="Low",Callback=function(v) State.FavoritesKey=v end})
            end

            local Extras = SettingsTab:CreateSection("Experiment17 Extras", false, "Experiment17 Extras")
            Extras:AddToggle({Name="Quick Action Notifications",Flag="UIX_Notify",Default=State.NotifyQuickActions,RequiredGraphics="Low",Callback=function(v) State.NotifyQuickActions=v end})
            Extras:AddToggle({Name="Favorite Star On Functions",Flag="UIX_FavoriteStars",Default=State.FavoriteStars,RequiredGraphics="Low",Callback=function(v) State.FavoriteStars=v end})
            Extras:AddToggle({Name="Force Cursor Above GUI",Flag="UIX_CursorTop",Default=State.ForceCursorTopmost,RequiredGraphics="Low",Callback=function(v) State.ForceCursorTopmost=v; forceCursorTop() end})
            Extras:AddButton({Name="Test Notification",ButtonText="Notify",RequiredGraphics="Low",Callback=function() notify("Notifications are working", "Success") end})
        end

        applyPerformanceOrder()
        forceCursorTop()

        Context.Shared.UIEnhancements = {
            ToggleFlag = toggleControl,
            FocusSearch = focusSearch,
            ToggleFavorites = toggleFavoritesPanel,
            Notify = notify,
            IsTouch = IsTouch,
        }
    end,
}
