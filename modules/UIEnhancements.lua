-- Experiment17 - UI Enhancements
return {
    Id = "UIEnhancements",
    Name = "UI Enhancements",
    Version = "1.0.0",
    Order = 1000,
    TargetTab = "Visual",

    Init = function(Context, Scope, _Tab)
        local Library = Context.Library
        local ENV = (getgenv and getgenv()) or _G
        local UIS = Context.Services.UIS or game:GetService("UserInputService")
        local Players = Context.Services.Players or game:GetService("Players")
        local LocalPlayer = Context.LocalPlayer or Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

        local State = Context:GetState("UIEnhancements", {
            CursorKey = "Insert", XRayKey = "Home", ThirdPersonKey = "V", MusicKey = "M",
            ESPKey = "F6", EchoKey = "F7", DamageKey = "F8", LightingKey = "F9",
            SearchKey = "F3", FavoritesKey = "F4", NotifyQuickActions = true, FavoriteStars = true, ForceCursorTopmost = true,
        })

        local function notify(text, kind)
            if not State.NotifyQuickActions then return end
            if Library and type(Library.Notify) == "function" then
                pcall(function() Library:Notify({Title="Experiment 17",Text=tostring(text),Type=kind or "Info",Duration=2.6}) end)
            end
        end

        local function applyTabOrder()
            local settingsTab = Library and Library.SettingsTab
            if settingsTab and settingsTab.Button then settingsTab.Button.LayoutOrder = 900 end
            local performance = Context:GetTab("Performance")
            if performance and performance.Button then performance.Button.LayoutOrder = 910 end
        end

        local function forceCursorTop()
            if not State.ForceCursorTopmost then return end
            for _, object in ipairs(PlayerGui:GetChildren()) do
                if object:IsA("ScreenGui") and object.Name == "Experiment17_Visual_Cursor" then
                    pcall(function() object.DisplayOrder=2147483646; object.ZIndexBehavior=Enum.ZIndexBehavior.Sibling end)
                end
            end
        end

        local function findControl(flag)
            if not Library then return nil end
            for _, control in pairs(Library.Controls or {}) do if control and control.Flag == flag then return control end end
        end

        local function toggleControl(flag, label)
            local control=findControl(flag)
            if not control or type(control.Get)~="function" or type(control.Set)~="function" then notify((label or flag).." is not loaded","Warning"); return false end
            local ok,current=pcall(function() return control:Get() end)
            if not ok or type(current)~="boolean" then notify((label or flag).." is not a toggle","Warning"); return false end
            pcall(function() control:Set(not current) end); notify((label or flag)..": "..((not current) and "ON" or "OFF"),"Info"); return true
        end

        local function findSearchBox()
            local root=Library and Library.Root; if not root then return nil end
            for _,object in ipairs(root:GetDescendants()) do if object:IsA("TextBox") then local placeholder=tostring(object.PlaceholderText or ""):lower(); if placeholder:find("search",1,true) or placeholder:find("поиск",1,true) then return object end end end
        end
        local function findFavoritesButton()
            local root=Library and Library.Root; if not root then return nil end
            for _,object in ipairs(root:GetDescendants()) do if object:IsA("TextButton") and tostring(object.Text):find("★",1,true) then local size=object.Size; if size.X.Offset<=48 and size.Y.Offset<=40 then return object end end end
        end
        local FavoritesButton=findFavoritesButton()
        local function focusSearch() local box=findSearchBox(); if box then pcall(function() box:CaptureFocus() end) else notify("Search field not found","Warning") end end
        local function toggleFavoritesPanel()
            FavoritesButton=FavoritesButton and FavoritesButton.Parent and FavoritesButton or findFavoritesButton()
            if FavoritesButton then
                local fire=ENV.firesignal or _G.firesignal; local ok=false
                if type(fire)=="function" then ok=pcall(fire,FavoritesButton.MouseButton1Click) end
                if not ok then ok=pcall(function() FavoritesButton:Activate() end) end
                if not ok then notify("Favorites button could not be activated","Warning") end
            else notify("Favorites button not found","Warning") end
        end
        local function toggleMusic() local music=Context.Shared and Context.Shared.Music; if music and type(music.Toggle)=="function" then music.Toggle() else notify("Music module is not loaded","Warning") end end
        local function toggleFirst(flags,label) for _,flag in ipairs(flags) do local c=findControl(flag); if c then return toggleControl(flag,label) end end; notify((label or "Function").." is not loaded","Warning"); return false end
        local function validKey(name) return type(name)=="string" and Enum.KeyCode[name]~=nil end
        local function pressed(input,name) return input.UserInputType==Enum.UserInputType.Keyboard and validKey(name) and input.KeyCode==Enum.KeyCode[name] end

        Scope:TrackConnection(UIS.InputBegan:Connect(function(input,processed)
            if processed or UIS:GetFocusedTextBox() then return end
            if pressed(input,State.CursorKey) then toggleControl("Visual_CustomCursor","Cursor")
            elseif pressed(input,State.XRayKey) then toggleControl("World_XRay","X-Ray")
            elseif pressed(input,State.ThirdPersonKey) then toggleControl("Player_ThirdPerson","Third Person")
            elseif pressed(input,State.MusicKey) then toggleMusic()
            elseif pressed(input,State.ESPKey) then toggleFirst({"ESP_MM2_Enabled","ESP_Enabled"},"ESP")
            elseif pressed(input,State.EchoKey) then toggleFirst({"World_EchoPlus","World_Echo"},"Movement Echo")
            elseif pressed(input,State.DamageKey) then toggleFirst({"ESP_DamagePlus","ESP_Damage"},"Damage Visualizer")
            elseif pressed(input,State.LightingKey) then toggleFirst({"LightingPlus_Master","Lighting_Rainbow"},"Lighting")
            elseif pressed(input,State.SearchKey) then focusSearch()
            elseif pressed(input,State.FavoritesKey) then toggleFavoritesPanel() end
        end))

        local decorated=setmetatable({}, {__mode="k"})
        local function refreshFavoriteStar(control,star)
            if not star or not star.Parent then return end
            local favorite=Library:IsFavorite(control); star.Text=favorite and "★" or "☆"; star.TextTransparency=favorite and 0 or 0.18; star.TextColor3=favorite and Library.Theme.Accent or Library.Theme.SubText
        end
        local function decorateControl(control)
            if not State.FavoriteStars or not control or decorated[control] then return end
            local holder=control.Holder; if not holder or not holder.Parent or not holder:IsA("GuiObject") then return end
            if holder:FindFirstChild("E17_FavoriteStar") then decorated[control]=true; return end
            local star=Instance.new("TextButton"); star.Name="E17_FavoriteStar"; star.AnchorPoint=Vector2.new(0,0.5); star.Position=UDim2.new(0,5,0.5,0); star.Size=UDim2.fromOffset(18,22); star.BackgroundTransparency=1; star.Text="☆"; star.TextSize=15; star.Font=Enum.Font.GothamBold; star.AutoButtonColor=false; star.ZIndex=math.max(70,holder.ZIndex+20); star.Parent=holder
            local displayName=tostring(control.DisplayName or "")
            if displayName~="" then for _,child in ipairs(holder:GetDescendants()) do if child:IsA("TextLabel") and child.Text==displayName then local p=child.Position; if p.X.Offset<28 then child.Position=UDim2.new(p.X.Scale,p.X.Offset+18,p.Y.Scale,p.Y.Offset) end; break end end end
            star.MouseButton1Click:Connect(function() Library:SetFavorite(control,not Library:IsFavorite(control)); refreshFavoriteStar(control,star) end)
            decorated[control]=star; refreshFavoriteStar(control,star)
        end

        local running=true; Scope:AddCleaner(function() running=false end)
        task.spawn(function()
            while running and not Context.Unloaded do
                applyTabOrder(); forceCursorTop()
                if State.FavoriteStars then for _,control in pairs(Library.Controls or {}) do decorateControl(control); local star=decorated[control]; if typeof(star)=="Instance" then refreshFavoriteStar(control,star) end end end
                task.wait(0.5)
            end
        end)

        local SettingsTab=Library and Library.SettingsTab
        if SettingsTab and type(SettingsTab.CreateSection)=="function" then
            local Section=SettingsTab:CreateSection("Quick Keybinds",false,"Quick Keybinds")
            Section:AddKeybind({Name="Toggle Custom Cursor",Flag="UIX_CursorKey",Default=State.CursorKey,RequiredGraphics="Low",Callback=function(v) State.CursorKey=v end})
            Section:AddKeybind({Name="Toggle X-Ray",Flag="UIX_XRayKey",Default=State.XRayKey,RequiredGraphics="Low",Callback=function(v) State.XRayKey=v end})
            Section:AddKeybind({Name="Toggle Third Person",Flag="UIX_ThirdPersonKey",Default=State.ThirdPersonKey,RequiredGraphics="Low",Callback=function(v) State.ThirdPersonKey=v end})
            Section:AddKeybind({Name="Music Play / Pause",Flag="UIX_MusicKey",Default=State.MusicKey,RequiredGraphics="Low",Callback=function(v) State.MusicKey=v end})
            Section:AddKeybind({Name="Toggle ESP",Flag="UIX_ESPKey",Default=State.ESPKey,RequiredGraphics="Low",Callback=function(v) State.ESPKey=v end})
            Section:AddKeybind({Name="Toggle Movement Echo",Flag="UIX_EchoKey",Default=State.EchoKey,RequiredGraphics="Low",Callback=function(v) State.EchoKey=v end})
            Section:AddKeybind({Name="Toggle Damage Visualizer",Flag="UIX_DamageKey",Default=State.DamageKey,RequiredGraphics="Low",Callback=function(v) State.DamageKey=v end})
            Section:AddKeybind({Name="Toggle Lighting+",Flag="UIX_LightingKey",Default=State.LightingKey,RequiredGraphics="Low",Callback=function(v) State.LightingKey=v end})
            Section:AddKeybind({Name="Focus Search",Flag="UIX_SearchKey",Default=State.SearchKey,RequiredGraphics="Low",Callback=function(v) State.SearchKey=v end})
            Section:AddKeybind({Name="Open Favorites",Flag="UIX_FavoritesKey",Default=State.FavoritesKey,RequiredGraphics="Low",Callback=function(v) State.FavoritesKey=v end})
            Section:AddToggle({Name="Quick Action Notifications",Flag="UIX_Notify",Default=State.NotifyQuickActions,RequiredGraphics="Low",Callback=function(v) State.NotifyQuickActions=v end})
            Section:AddToggle({Name="Favorite Star On Functions",Flag="UIX_FavoriteStars",Default=State.FavoriteStars,RequiredGraphics="Low",Callback=function(v) State.FavoriteStars=v end})
            Section:AddToggle({Name="Force Cursor Above GUI",Flag="UIX_CursorTop",Default=State.ForceCursorTopmost,RequiredGraphics="Low",Callback=function(v) State.ForceCursorTopmost=v forceCursorTop() end})
            Section:AddButton({Name="Test Notification",ButtonText="Notify",RequiredGraphics="Low",Callback=function() notify("Notifications are working","Success") end})
        end

        applyTabOrder(); forceCursorTop()
        Context.Shared.UIEnhancements={ToggleFlag=toggleControl,FocusSearch=focusSearch,ToggleFavorites=toggleFavoritesPanel,Notify=notify}
    end,
}
