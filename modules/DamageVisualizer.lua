-- Experiment17 - Damage Visualizer+
return {
    Id = "DamageVisualizer",
    Name = "Damage Visualizer+",
    Version = "1.0.0",
    Order = 35,
    TargetTab = "ESP",

    Init = function(Context, Scope, Tab)
        local Players = Context.Services.Players or game:GetService("Players")
        local Workspace = Context.Services.Workspace or workspace
        local TweenService = Context.Services.TweenService or game:GetService("TweenService")
        local LocalPlayer = Context.LocalPlayer or Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local Library = Context.Library

        local State = Context:GetState("DamageVisualizerPlus", {
            Enabled=false,
            IncludeSelf=true,
            IncludeOthers=true,
            ShowHealing=true,
            Style="Impact",
            DamageColor=Color3.fromRGB(255,82,82),
            HealColor=Color3.fromRGB(80,235,135),
            CriticalColor=Color3.fromRGB(255,205,65),
            CriticalThreshold=35,
            Lifetime=0.9,
            Scale=1.0,
            Rise=2.5,
            Spread=0.55,
            CombineWindow=0.16,
            MaxDistance=1800,
            Rainbow=false,
            RainbowSpeed=0.35,
        })

        local R={Health=setmetatable({}, {__mode="k"}), Connections=setmetatable({}, {__mode="k"}), Pending=setmetatable({}, {__mode="k"}), Active={}}
        local Gui=Scope:TrackInstance(Instance.new("ScreenGui")); Gui.Name="Experiment17_DamagePlus"; Gui.ResetOnSpawn=false; Gui.IgnoreGuiInset=true; Gui.DisplayOrder=999991; Gui.Parent=PlayerGui

        local function findControl(flag)
            for _,c in pairs((Library and Library.Controls) or {}) do if c and c.Flag==flag then return c end end
        end
        local function disableOldDamage()
            local c=findControl("ESP_Damage")
            if c and type(c.Get)=="function" and type(c.Set)=="function" then
                local ok,v=pcall(function() return c:Get() end)
                if ok and v==true then pcall(function() c:Set(false) end) end
            end
        end

        local function colorNow(base,offset)
            if State.Rainbow then return Color3.fromHSV(((os.clock()*State.RainbowSpeed)+(offset or 0))%1,0.9,1) end
            return base
        end

        local function eligible(player,character)
            if player==LocalPlayer and not State.IncludeSelf then return false end
            if player~=LocalPlayer and not State.IncludeOthers then return false end
            local root=character and character:FindFirstChild("HumanoidRootPart")
            local mine=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root and mine and (root.Position-mine.Position).Magnitude>State.MaxDistance then return false end
            return true
        end

        local function removeGui(gui)
            for i=#R.Active,1,-1 do if R.Active[i]==gui then table.remove(R.Active,i) break end end
            if gui and gui.Parent then pcall(function() gui:Destroy() end) end
        end

        local function styleText(label,amount,isHeal,isCrit,combo)
            local sign=isHeal and "+" or "−"
            local rounded=math.max(1,math.floor(math.abs(amount)+0.5))
            local text=sign..tostring(rounded)
            if combo and combo>1 then text=text.."  ×"..tostring(combo) end
            if isCrit and not isHeal then text="CRIT  "..text end
            label.Text=text
            local base=isHeal and State.HealColor or (isCrit and State.CriticalColor or State.DamageColor)
            label.TextColor3=colorNow(base,(rounded%17)/17)
            if State.Style=="Arcade" then label.Font=Enum.Font.GothamBlack; label.TextStrokeTransparency=0.05
            elseif State.Style=="Clean" then label.Font=Enum.Font.GothamMedium; label.TextStrokeTransparency=0.55
            else label.Font=Enum.Font.GothamBold; label.TextStrokeTransparency=0.18 end
        end

        local function spawnOrCombine(player,character,humanoid,delta)
            if not State.Enabled or delta==0 or not eligible(player,character) then return end
            local isHeal=delta>0
            if isHeal and not State.ShowHealing then return end
            local amount=math.abs(delta)
            local now=os.clock()
            local pending=R.Pending[humanoid]
            if pending and pending.Gui and pending.Gui.Parent and (now-pending.Last)<=State.CombineWindow and pending.Heal==isHeal then
                pending.Amount+=amount; pending.Count+=1; pending.Last=now
                local crit=(not isHeal) and pending.Amount>=State.CriticalThreshold
                styleText(pending.Label,pending.Amount,isHeal,crit,pending.Count)
                return
            end

            local adornee=character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
            if not adornee then return end

            local gui=Instance.new("BillboardGui")
            gui.Name="E17_DamagePlus_Number"; gui.AlwaysOnTop=true; gui.LightInfluence=0; gui.MaxDistance=State.MaxDistance
            gui.Size=UDim2.fromOffset(190*State.Scale,64*State.Scale)
            local x=(math.random()-0.5)*2*State.Spread
            gui.StudsOffsetWorldSpace=Vector3.new(x,2.5,0); gui.Adornee=adornee; gui.Parent=Gui

            local label=Instance.new("TextLabel")
            label.BackgroundTransparency=1; label.Size=UDim2.fromScale(1,1); label.TextScaled=false; label.TextSize=math.floor(22*State.Scale)
            label.TextXAlignment=Enum.TextXAlignment.Center; label.TextYAlignment=Enum.TextYAlignment.Center
            label.TextStrokeColor3=Color3.new(0,0,0); label.Parent=gui

            local crit=(not isHeal) and amount>=State.CriticalThreshold
            styleText(label,amount,isHeal,crit,1)
            if State.Style=="Impact" then
                label.Rotation=math.random(-7,7)
                label.TextSize=math.floor((crit and 28 or 23)*State.Scale)
            end

            local data={Gui=gui,Label=label,Amount=amount,Count=1,Last=now,Heal=isHeal}
            R.Pending[humanoid]=data; R.Active[#R.Active+1]=gui

            local life=math.max(0.2,State.Lifetime)
            local target=gui.StudsOffsetWorldSpace+Vector3.new((math.random()-0.5)*0.25,State.Rise,0)
            TweenService:Create(gui,TweenInfo.new(life,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{StudsOffsetWorldSpace=target}):Play()
            TweenService:Create(label,TweenInfo.new(life*0.55,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,life*0.45),{TextTransparency=1,TextStrokeTransparency=1}):Play()
            task.delay(life+0.08,function()
                if R.Pending[humanoid]==data then R.Pending[humanoid]=nil end
                removeGui(gui)
            end)
        end

        local function unwatch(humanoid)
            local c=R.Connections[humanoid]
            if c then pcall(function() c:Disconnect() end); R.Connections[humanoid]=nil end
            R.Health[humanoid]=nil; R.Pending[humanoid]=nil
        end

        local function watchCharacter(player,character)
            local humanoid=character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid then
                task.spawn(function()
                    humanoid=character and character:WaitForChild("Humanoid",5)
                    if humanoid then watchCharacter(player,character) end
                end)
                return
            end
            unwatch(humanoid)
            R.Health[humanoid]=humanoid.Health
            local conn=humanoid.HealthChanged:Connect(function(newHealth)
                local old=R.Health[humanoid]
                R.Health[humanoid]=newHealth
                if old==nil then return end
                local delta=newHealth-old
                if math.abs(delta)>=0.5 then spawnOrCombine(player,character,humanoid,delta) end
            end)
            R.Connections[humanoid]=conn
        end

        local function hookPlayer(player)
            if player.Character then watchCharacter(player,player.Character) end
            Scope:TrackConnection(player.CharacterAdded:Connect(function(char) task.defer(function() watchCharacter(player,char) end) end))
        end
        for _,p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
        Scope:TrackConnection(Players.PlayerAdded:Connect(hookPlayer))
        Scope:TrackConnection(Players.PlayerRemoving:Connect(function(player)
            for hum in pairs(R.Connections) do if hum.Parent and hum.Parent==player.Character then unwatch(hum) end end
        end))

        local Section=Context:CreateSection(Scope,Tab,"Damage Visualizer+",false,"ESP / Damage Plus")
        Section:AddToggle({Name="Damage Visualizer+",Flag="ESP_DamagePlus",Default=State.Enabled,RequiredGraphics="Low",Description="Improved floating damage/heal numbers with aggregation and critical hits. Uses replicated Humanoid.Health changes, so it does not know the damage source.",FPSImpact={-2,0},Callback=function(v) State.Enabled=v if v then disableOldDamage() end end})
        Section:AddToggle({Name="Include Local Player",Flag="ESP_DamagePlusSelf",Default=State.IncludeSelf,RequiredGraphics="Low",Callback=function(v) State.IncludeSelf=v end})
        Section:AddToggle({Name="Include Other Players",Flag="ESP_DamagePlusOthers",Default=State.IncludeOthers,RequiredGraphics="Low",Callback=function(v) State.IncludeOthers=v end})
        Section:AddToggle({Name="Show Healing",Flag="ESP_DamagePlusHeal",Default=State.ShowHealing,RequiredGraphics="Low",Callback=function(v) State.ShowHealing=v end})
        Section:AddChoice({Name="Number Style",Flag="ESP_DamagePlusStyle",Values={"Impact","Clean","Arcade"},Default=State.Style,RequiredGraphics="Low",Callback=function(v) State.Style=v end})
        Section:AddColorPicker({Name="Damage Color",Flag="ESP_DamagePlusColor",Default=State.DamageColor,RequiredGraphics="Low",Callback=function(v) State.DamageColor=v end})
        Section:AddColorPicker({Name="Critical Color",Flag="ESP_DamagePlusCritColor",Default=State.CriticalColor,RequiredGraphics="Low",Callback=function(v) State.CriticalColor=v end})
        Section:AddColorPicker({Name="Healing Color",Flag="ESP_DamagePlusHealColor",Default=State.HealColor,RequiredGraphics="Low",Callback=function(v) State.HealColor=v end})
        Section:AddToggle({Name="Rainbow Numbers",Flag="ESP_DamagePlusRGB",Default=State.Rainbow,RequiredGraphics="Low",Callback=function(v) State.Rainbow=v end})
        Section:AddSlider({Name="Rainbow Speed",Flag="ESP_DamagePlusRGBSpeed",Min=0.02,Max=1.5,Default=State.RainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.RainbowSpeed=v end})
        Section:AddSlider({Name="Critical Threshold",Flag="ESP_DamagePlusCrit",Min=1,Max=200,Default=State.CriticalThreshold,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.CriticalThreshold=v end})
        Section:AddSlider({Name="Combine Window",Flag="ESP_DamagePlusCombine",Min=0,Max=0.6,Default=State.CombineWindow,Decimals=2,Suffix=" s",RequiredGraphics="Low",Description="Damage events on the same Humanoid inside this time window are combined into one number with a hit count.",Callback=function(v) State.CombineWindow=v end})
        Section:AddSlider({Name="Lifetime",Flag="ESP_DamagePlusLife",Min=0.2,Max=3,Default=State.Lifetime,Decimals=2,Suffix=" s",RequiredGraphics="Low",Callback=function(v) State.Lifetime=v end})
        Section:AddSlider({Name="Scale",Flag="ESP_DamagePlusScale",Min=0.5,Max=2.5,Default=State.Scale,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.Scale=v end})
        Section:AddSlider({Name="Rise Distance",Flag="ESP_DamagePlusRise",Min=0.5,Max=8,Default=State.Rise,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.Rise=v end})
        Section:AddSlider({Name="Horizontal Spread",Flag="ESP_DamagePlusSpread",Min=0,Max=2,Default=State.Spread,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.Spread=v end})
        Section:AddSlider({Name="Max Distance",Flag="ESP_DamagePlusDistance",Min=50,Max=5000,Default=State.MaxDistance,Decimals=0,Suffix=" studs",RequiredGraphics="Low",Callback=function(v) State.MaxDistance=v end})

        Scope:AddCleaner(function()
            for hum in pairs(R.Connections) do unwatch(hum) end
            for i=#R.Active,1,-1 do removeGui(R.Active[i]) end
        end)
        Context.Shared.DamageVisualizer={Enabled=function() return State.Enabled end}
    end,
}
