-- Experiment17 - Sync v1.2 compact
return {
    Id="Sync", Name="Sync", Version="1.2.0", Order=80,
    Init=function(Context,Scope,Tab)
        local S=Context.Services
        local RunService,HttpService,Workspace,Players=S.RunService,S.HttpService,S.Workspace,S.Players
        local LocalPlayer=Context.LocalPlayer
        local ENV=(getgenv and getgenv()) or _G
        local State=Context:GetState("Sync",{
            RelayURL="ws://127.0.0.1:8765",Room="Experiment17",RoomKey="",SendRate=12,OnlySamePlace=true,
            SyncPose=true,SyncCamera=true,ShowGhosts=true,Interpolate=true,InterpolationSpeed=14,
            GhostColor=Color3.fromRGB(110,200,255),GhostTransparency=.45,GhostRainbow=false,GhostRainbowSpeed=.22,
            ShowNames=true,ShowVisualsTags=false,ShowSelfVisualsTag=false,VisualsTagText="E17 VISUALS",
            VisualsTagColor=Color3.fromRGB(125,215,255),VisualsTagRainbow=false,VisualsTagRainbowSpeed=.18,VisualsTagMaxDistance=1200,VisualsTagYOffset=2.8,
        })
        local R={Protocol="E17SYNC1",ClientId=HttpService:GenerateGUID(false),Socket=nil,SocketConnections={},Peers={},Acc=0,Status=nil,PeerStatus=nil,Root=nil,SelfTag=nil}
        local bodyNames={Head=true,Torso=true,UpperTorso=true,LowerTorso=true,["Left Arm"]=true,["Right Arm"]=true,["Left Leg"]=true,["Right Leg"]=true,LeftUpperArm=true,LeftLowerArm=true,LeftHand=true,RightUpperArm=true,RightLowerArm=true,RightHand=true,LeftUpperLeg=true,LeftLowerLeg=true,LeftFoot=true,RightUpperLeg=true,RightLowerLeg=true,RightFoot=true,HumanoidRootPart=true}
        R.Root=Scope:TrackInstance(Instance.new("Folder")); R.Root.Name="Experiment17_SyncGhosts"; R.Root.Parent=Workspace

        local function status(t) if R.Status then R.Status:Set(t) end end
        local function peerStatus() local n=0 for _ in pairs(R.Peers) do n+=1 end if R.PeerStatus then R.PeerStatus:Set(tostring(n).." connected") end end
        local function cfToArray(cf) return {cf:GetComponents()} end
        local function arrayToCF(a) if type(a)~="table" or #a<12 then return nil end return CFrame.new(a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],a[10],a[11],a[12]) end
        local function rgb(speed,off) return Color3.fromHSV(((os.clock()*(speed or .2))+(off or 0))%1,.85,1) end
        local function wsConnect()
            local c={ENV.WebSocket and ENV.WebSocket.connect,ENV.websocket and ENV.websocket.connect,ENV.syn and ENV.syn.websocket and ENV.syn.websocket.connect}
            for _,fn in ipairs(c) do if type(fn)=="function" then return fn end end
        end
        local function sendRaw(text)
            if not R.Socket then return false end
            return pcall(function() if type(R.Socket.Send)=="function" then R.Socket:Send(text) elseif type(R.Socket.send)=="function" then R.Socket:send(text) else error("no Send") end end)
        end
        local function send(packet)
            if not R.Socket then return false end
            packet.protocol=R.Protocol; packet.room=State.Room; packet.key=State.RoomKey; packet.client=R.ClientId
            packet.place=game.PlaceId; packet.game=game.GameId; packet.user=LocalPlayer.UserId; packet.name=LocalPlayer.Name; packet.visuals=true; packet.visualsVersion=Context.Version
            local ok,text=pcall(HttpService.JSONEncode,HttpService,packet); return ok and sendRaw(text) or false
        end
        local function disconnect(reason)
            local sock=R.Socket; R.Socket=nil
            if sock then pcall(function() if sock.Close then sock:Close() elseif sock.close then sock:close() end end) end
            for _,c in ipairs(R.SocketConnections) do pcall(function() c:Disconnect() end) end; table.clear(R.SocketConnections)
            status(reason or "Disconnected")
        end
        local function bindSignal(sig,fn)
            if not sig then return end
            if type(sig.Connect)=="function" then local ok,c=pcall(function() return sig:Connect(fn) end); if ok and c then table.insert(R.SocketConnections,c) end
            elseif type(sig.connect)=="function" then local ok,c=pcall(function() return sig:connect(fn) end); if ok and c then table.insert(R.SocketConnections,c) end end
        end

        local function destroyTag(holder)
            if holder and holder.Tag then pcall(function() holder.Tag:Destroy() end); holder.Tag=nil; holder.TagLabel=nil; holder.TagStroke=nil end
        end
        local function tagColor(off) return State.VisualsTagRainbow and rgb(State.VisualsTagRainbowSpeed,off) or State.VisualsTagColor end
        local function ensureTag(holder,player,isSelf)
            if not holder or not player then return end
            if not State.ShowVisualsTags or (isSelf and not State.ShowSelfVisualsTag) then destroyTag(holder); return end
            local head=player.Character and player.Character:FindFirstChild("Head"); if not head then destroyTag(holder); return end
            if holder.Tag and holder.Tag.Parent~=head then destroyTag(holder) end
            if not holder.Tag then
                local gui=Instance.new("BillboardGui"); gui.Name="Experiment17_VisualsTag"; gui.Size=UDim2.fromOffset(170,30); gui.AlwaysOnTop=true; gui.MaxDistance=State.VisualsTagMaxDistance; gui.StudsOffset=Vector3.new(0,State.VisualsTagYOffset,0); gui.Parent=head
                local frame=Instance.new("Frame"); frame.Size=UDim2.fromScale(1,1); frame.BackgroundColor3=Color3.fromRGB(12,14,20); frame.BackgroundTransparency=.22; frame.BorderSizePixel=0; frame.Parent=gui
                local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,8); corner.Parent=frame
                local stroke=Instance.new("UIStroke"); stroke.Thickness=1.2; stroke.Transparency=.08; stroke.Parent=frame
                local label=Instance.new("TextLabel"); label.BackgroundTransparency=1; label.Size=UDim2.fromScale(1,1); label.Font=Enum.Font.GothamBold; label.TextSize=12; label.TextStrokeTransparency=.65; label.Parent=frame
                holder.Tag,holder.TagLabel,holder.TagStroke=gui,label,stroke
            end
            local c=tagColor(((player.UserId or 0)%31)/31); holder.Tag.MaxDistance=State.VisualsTagMaxDistance; holder.Tag.StudsOffset=Vector3.new(0,State.VisualsTagYOffset,0); holder.TagLabel.Text="◆  "..tostring(State.VisualsTagText); holder.TagLabel.TextColor3=c; holder.TagStroke.Color=c
        end
        local function refreshTags()
            for _,p in pairs(R.Peers) do
                local rp=p.UserId and Players:GetPlayerByUserId(p.UserId)
                if rp and p.HasVisuals~=false then ensureTag(p,rp,false) else destroyTag(p) end
            end
            R.SelfHolder=R.SelfHolder or {}; if State.ShowSelfVisualsTag then ensureTag(R.SelfHolder,LocalPlayer,true) else destroyTag(R.SelfHolder) end
        end

        local function ensurePeer(packet)
            local id=tostring(packet.client or ""); if id=="" or id==R.ClientId then return nil end
            local p=R.Peers[id]
            if not p then
                local m=Instance.new("Model"); m.Name="E17_Sync_"..tostring(packet.name or id); m.Parent=R.Root
                p={Id=id,Name=tostring(packet.name or "Peer"),UserId=tonumber(packet.user),HasVisuals=packet.visuals~=false,Model=m,Parts={},Targets={},LastSeen=os.clock()}; R.Peers[id]=p; peerStatus()
            end
            p.LastSeen=os.clock(); p.UserId=tonumber(packet.user) or p.UserId; p.HasVisuals=packet.visuals~=false; return p
        end
        local function ensurePart(peer,name,size)
            local part=peer.Parts[name]; if part and part.Parent then return part end
            part=Instance.new("Part"); part.Name=name; part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false; part.Material=Enum.Material.Neon; part.Size=size or Vector3.new(2,2,1); part.Transparency=State.GhostTransparency; part.Parent=peer.Model; peer.Parts[name]=part; return part
        end
        local function applyPacket(packet)
            if packet.protocol~=R.Protocol or packet.client==R.ClientId or packet.room~=State.Room or tostring(packet.key or "")~=tostring(State.RoomKey or "") then return end
            if State.OnlySamePlace and tonumber(packet.place)~=game.PlaceId then return end
            if packet.type=="bye" then local p=R.Peers[tostring(packet.client)]; if p then destroyTag(p); p.Model:Destroy(); R.Peers[tostring(packet.client)]=nil; peerStatus() end; return end
            local peer=ensurePeer(packet); if not peer then return end
            if type(packet.pose)=="table" then for name,data in pairs(packet.pose) do if bodyNames[name] and type(data)=="table" then local cf=arrayToCF(data.cf); local size=data.size and Vector3.new(data.size[1],data.size[2],data.size[3]) or Vector3.new(2,2,1); if cf then local part=ensurePart(peer,name,size); part.Size=size; peer.Targets[name]=cf end end end end
            if packet.camera then peer.Camera=packet.camera end
            refreshTags()
        end
        local function onMessage(raw)
            if type(raw)=="table" then raw=raw.Data or raw.data or raw.Message or raw.message end
            if type(raw)~="string" then return end
            local ok,p=pcall(HttpService.JSONDecode,HttpService,raw); if ok and type(p)=="table" then applyPacket(p) end
        end
        local function connect()
            disconnect("Connecting...")
            local fn=wsConnect(); if not fn then status("WebSocket API unavailable"); return end
            local ok,sock=pcall(fn,State.RelayURL); if not ok or not sock then status("Connect failed"); return end
            R.Socket=sock; status("Connected")
            bindSignal(sock.OnMessage or sock.MessageReceived,onMessage)
            bindSignal(sock.OnClose or sock.Closed,function() R.Socket=nil; status("Disconnected") end)
            send({type="hello"})
        end

        local function buildPose()
            if not State.SyncPose then return nil end
            local c=LocalPlayer.Character; if not c then return nil end
            local pose={}
            for _,o in ipairs(c:GetChildren()) do if o:IsA("BasePart") and bodyNames[o.Name] then pose[o.Name]={cf=cfToArray(o.CFrame),size={o.Size.X,o.Size.Y,o.Size.Z}} end end
            return pose
        end
        local function packet()
            local p={type="state",pose=buildPose()}
            if State.SyncCamera and Workspace.CurrentCamera then local cf=Workspace.CurrentCamera.CFrame; p.camera={cf=cfToArray(cf)} end
            return p
        end

        Scope:TrackConnection(RunService.RenderStepped:Connect(function(dt)
            R.Acc+=dt
            if R.Socket and R.Acc>=1/math.max(1,State.SendRate) then R.Acc=0; send(packet()) end
            local alpha=State.Interpolate and (1-math.exp(-dt*State.InterpolationSpeed)) or 1
            local dead={}
            for id,p in pairs(R.Peers) do
                if os.clock()-p.LastSeen>8 then dead[#dead+1]=id else
                    local c=State.GhostRainbow and rgb(State.GhostRainbowSpeed,(p.UserId or 0)%37/37) or State.GhostColor
                    for name,part in pairs(p.Parts) do
                        part.Color=c; part.Transparency=State.ShowGhosts and State.GhostTransparency or 1
                        local t=p.Targets[name]; if t then part.CFrame=part.CFrame:Lerp(t,alpha) end
                    end
                    if p.TagLabel and p.TagStroke then local tc=tagColor((p.UserId or 0)%31/31); p.TagLabel.TextColor3=tc; p.TagStroke.Color=tc end
                end
            end
            if R.SelfHolder and R.SelfHolder.TagLabel and R.SelfHolder.TagStroke then local tc=tagColor(0); R.SelfHolder.TagLabel.TextColor3=tc; R.SelfHolder.TagStroke.Color=tc end
            for _,id in ipairs(dead) do local p=R.Peers[id]; if p then destroyTag(p); p.Model:Destroy(); R.Peers[id]=nil end end; if #dead>0 then peerStatus() end
        end))
        Scope:TrackConnection(Players.PlayerRemoving:Connect(function(plr) for _,p in pairs(R.Peers) do if p.UserId==plr.UserId then destroyTag(p) end end end))

        local Net=Context:CreateSection(Scope,Tab,"Party Sync",true,"Sync / Network")
        R.Status=Net:AddStatus({Name="Connection",Default="Disconnected"}); R.PeerStatus=Net:AddStatus({Name="Peers",Default="0 connected"})
        Net:AddInput({Name="Relay WebSocket URL",Flag="Sync_Relay",Default=State.RelayURL,Placeholder="wss://relay.example.com",RequiredGraphics="Low",Callback=function(v) State.RelayURL=tostring(v or "") end})
        Net:AddInput({Name="Room",Flag="Sync_Room",Default=State.Room,RequiredGraphics="Low",Callback=function(v) State.Room=tostring(v or "") end})
        Net:AddInput({Name="Room Key",Flag="Sync_Key",Default=State.RoomKey,RequiredGraphics="Low",Description="Room separator only; do not use a real password.",Callback=function(v) State.RoomKey=tostring(v or "") end})
        Net:AddSlider({Name="Network Rate",Flag="Sync_Rate",Min=2,Max=30,Default=State.SendRate,Decimals=0,RequiredGraphics="Low",FPSImpact={-2,0},PingImpact={0,3},Callback=function(v) State.SendRate=math.floor(v) end})
        Net:AddToggle({Name="Only Same Place",Flag="Sync_SamePlace",Default=State.OnlySamePlace,RequiredGraphics="Low",Callback=function(v) State.OnlySamePlace=v end})
        Net:AddButtonGroup({Name="Connection",Buttons={{Text="Connect",Callback=connect},{Text="Disconnect",Callback=function() disconnect("Disconnected") end}}})

        local Ghost=Context:CreateSection(Scope,Tab,"Remote Ghosts",false,"Sync / Ghosts")
        Ghost:AddToggle({Name="Show Synced Ghosts",Flag="Sync_Ghosts",Default=State.ShowGhosts,RequiredGraphics="Low",FPSImpact={-6,-1},Callback=function(v) State.ShowGhosts=v end})
        Ghost:AddToggle({Name="Interpolate Movement",Flag="Sync_Interp",Default=State.Interpolate,RequiredGraphics="Low",Callback=function(v) State.Interpolate=v end})
        Ghost:AddSlider({Name="Interpolation Speed",Flag="Sync_InterpSpeed",Min=2,Max=40,Default=State.InterpolationSpeed,Decimals=1,RequiredGraphics="Low",Callback=function(v) State.InterpolationSpeed=v end})
        Ghost:AddColorPicker({Name="Ghost Color",Flag="Sync_GhostColor",Default=State.GhostColor,RequiredGraphics="Low",Callback=function(v) State.GhostColor=v end})
        Ghost:AddToggle({Name="Rainbow Ghost",Flag="Sync_GhostRGB",Default=State.GhostRainbow,RequiredGraphics="Low",Callback=function(v) State.GhostRainbow=v end})
        Ghost:AddSlider({Name="Ghost RGB Speed",Flag="Sync_GhostRGBSpeed",Min=.02,Max=1.5,Default=State.GhostRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.GhostRainbowSpeed=v end})
        Ghost:AddSlider({Name="Ghost Transparency",Flag="Sync_GhostTransparency",Min=0,Max=.95,Default=State.GhostTransparency,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.GhostTransparency=v end})

        local Presence=Context:CreateSection(Scope,Tab,"Visuals Presence Tags",false,"Sync / Presence")
        Presence:AddToggle({Name="Show VISUALS Tag",Flag="Sync_VisualsTag",Default=State.ShowVisualsTags,RequiredGraphics="Low",FPSImpact={-1,0},Description="Shows a local tag above real players whose Experiment17 client is visible through this Sync room.",Callback=function(v) State.ShowVisualsTags=v; refreshTags() end})
        Presence:AddToggle({Name="Show Tag On Self",Flag="Sync_VisualsTagSelf",Default=State.ShowSelfVisualsTag,RequiredGraphics="Low",Callback=function(v) State.ShowSelfVisualsTag=v; refreshTags() end})
        Presence:AddInput({Name="Tag Text",Flag="Sync_TagText",Default=State.VisualsTagText,Placeholder="E17 VISUALS",RequiredGraphics="Low",Callback=function(v) State.VisualsTagText=tostring(v or "E17 VISUALS"); refreshTags() end})
        Presence:AddColorPicker({Name="Tag Color",Flag="Sync_TagColor",Default=State.VisualsTagColor,RequiredGraphics="Low",Callback=function(v) State.VisualsTagColor=v; refreshTags() end})
        Presence:AddToggle({Name="Rainbow Tag",Flag="Sync_TagRGB",Default=State.VisualsTagRainbow,RequiredGraphics="Low",Callback=function(v) State.VisualsTagRainbow=v end})
        Presence:AddSlider({Name="Tag RGB Speed",Flag="Sync_TagRGBSpeed",Min=.02,Max=1.5,Default=State.VisualsTagRainbowSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.VisualsTagRainbowSpeed=v end})
        Presence:AddSlider({Name="Tag Max Distance",Flag="Sync_TagDistance",Min=50,Max=5000,Default=State.VisualsTagMaxDistance,Decimals=0,RequiredGraphics="Low",Callback=function(v) State.VisualsTagMaxDistance=math.floor(v); refreshTags() end})
        Presence:AddSlider({Name="Tag Height",Flag="Sync_TagHeight",Min=1.5,Max=6,Default=State.VisualsTagYOffset,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.VisualsTagYOffset=v; refreshTags() end})

        Context.Shared.Sync={Connect=connect,Disconnect=disconnect,Send=send,GetPeers=function() return R.Peers end,GetClientId=function() return R.ClientId end}
        Scope:AddCleaner(function() disconnect("Unloaded"); for _,p in pairs(R.Peers) do destroyTag(p) end; if R.SelfHolder then destroyTag(R.SelfHolder) end; if Context.Shared.Sync then Context.Shared.Sync=nil end end)
    end,
}
