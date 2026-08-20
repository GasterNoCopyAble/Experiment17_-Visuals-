-- Experiment17 - same-client global script bus + Sync diagnostics
return {
    Id = "SharedBus",
    Name = "Shared Bus",
    Version = "1.0.0",
    Order = 82,
    TargetTab = "Sync",

    Init = function(Context, Scope, Tab)
        local Library = Context.Library
        local UIS = Context.Services.UIS or game:GetService("UserInputService")
        local ENV = (getgenv and getgenv()) or _G

        local Bus = ENV.Experiment17Bus
        if type(Bus) ~= "table" or Bus.__Experiment17Bus ~= true then
            Bus = {
                __Experiment17Bus = true,
                Version = 1,
                Data = {},
                Listeners = {},
                NextListenerId = 0,
            }

            function Bus:Get(key, default)
                local value = self.Data[key]
                if value == nil then return default end
                return value
            end

            function Bus:Set(key, value)
                local old = self.Data[key]
                self.Data[key] = value
                if old ~= value then
                    self:Emit("Changed", key, value, old)
                    self:Emit("Changed:" .. tostring(key), value, old)
                end
                return value
            end

            function Bus:Emit(eventName, ...)
                local bucket = self.Listeners[tostring(eventName)]
                if not bucket then return 0 end
                local called = 0
                for id, fn in pairs(bucket) do
                    if type(fn) == "function" then
                        local ok = pcall(fn, ...)
                        if ok then called += 1 else bucket[id] = nil end
                    else
                        bucket[id] = nil
                    end
                end
                return called
            end

            function Bus:On(eventName, callback)
                assert(type(callback) == "function", "callback must be a function")
                eventName = tostring(eventName)
                self.NextListenerId += 1
                local id = self.NextListenerId
                self.Listeners[eventName] = self.Listeners[eventName] or {}
                self.Listeners[eventName][id] = callback
                local alive = true
                return function()
                    if not alive then return end
                    alive = false
                    local bucket = self.Listeners[eventName]
                    if bucket then bucket[id] = nil end
                end
            end

            function Bus:Once(eventName, callback)
                local disconnect
                disconnect = self:On(eventName, function(...)
                    if disconnect then disconnect() end
                    callback(...)
                end)
                return disconnect
            end
        end

        ENV.Experiment17Bus = Bus
        ENV.E17 = type(ENV.E17) == "table" and ENV.E17 or {}
        ENV.E17.Bus = Bus
        ENV.E17.Core = Context
        ENV.E17.Library = Library
        ENV.E17_VISUALS = true

        pcall(function()
            if type(shared) == "table" then
                shared.Experiment17Bus = Bus
                shared.E17 = ENV.E17
            end
        end)

        Bus:Set("Visuals.Loaded", true)
        Bus:Set("Visuals.Version", tostring(Context.Version or "unknown"))
        Bus:Set("Roblox.PlaceId", game.PlaceId)
        Bus:Set("Roblox.GameId", game.GameId)
        Bus:Set("Client.TouchEnabled", UIS.TouchEnabled == true)

        local StatusBus, StatusWS, StatusRelay, StatusRoom

        local function websocketFunction()
            local candidates = {
                ENV.WebSocket and ENV.WebSocket.connect,
                ENV.websocket and ENV.websocket.connect,
                ENV.syn and ENV.syn.websocket and ENV.syn.websocket.connect,
            }
            for _, fn in ipairs(candidates) do
                if type(fn) == "function" then return fn end
            end
            return nil
        end

        local function getFlag(name, fallback)
            if Library and Library.Flags and Library.Flags[name] ~= nil then
                return Library.Flags[name]
            end
            return fallback
        end

        local function peerCount()
            local sync = Context.Shared and Context.Shared.Sync
            if not sync or type(sync.GetPeers) ~= "function" then return 0 end
            local ok, peers = pcall(sync.GetPeers)
            if not ok or type(peers) ~= "table" then return 0 end
            local n = 0
            for _ in pairs(peers) do n += 1 end
            return n
        end

        local function relayAdvice(relay)
            relay = tostring(relay or "")
            local lower = relay:lower()
            if UIS.TouchEnabled and (lower:find("127.0.0.1", 1, true) or lower:find("localhost", 1, true)) then
                return "PHONE: localhost points to this phone. Use PC LAN IP or a public wss:// relay."
            end
            if relay == "" then return "Relay URL is empty." end
            if not websocketFunction() then return "Executor has no supported WebSocket.connect API." end
            return "Relay URL looks usable; peer discovery still requires the relay server to be running."
        end

        local lastRoom, lastRelay, lastPeers
        local running = true
        Scope:AddCleaner(function() running = false end)

        local function refresh()
            local room = tostring(getFlag("Sync_Room", "Experiment17") or "Experiment17")
            local relay = tostring(getFlag("Sync_Relay", "ws://127.0.0.1:8765") or "")
            local peers = peerCount()
            local ws = websocketFunction() ~= nil
            local sync = Context.Shared and Context.Shared.Sync

            ENV.E17_SYNC_ROOM = room
            ENV.E17_SYNC_RELAY = relay
            ENV.E17_SYNC_PEERS = peers
            ENV.E17.Sync = sync

            Bus:Set("Sync.API", sync)
            Bus:Set("Sync.Room", room)
            Bus:Set("Sync.Relay", relay)
            Bus:Set("Sync.PeerCount", peers)
            Bus:Set("Sync.WebSocketAvailable", ws)
            if sync and type(sync.GetClientId) == "function" then
                local ok, id = pcall(sync.GetClientId)
                if ok then Bus:Set("Sync.ClientId", id); ENV.E17_SYNC_CLIENT = id end
            end

            if lastRoom ~= room then Bus:Emit("Sync.RoomChanged", room, lastRoom); lastRoom = room end
            if lastRelay ~= relay then Bus:Emit("Sync.RelayChanged", relay, lastRelay); lastRelay = relay end
            if lastPeers ~= peers then Bus:Emit("Sync.PeerCountChanged", peers, lastPeers); lastPeers = peers end

            if StatusBus then StatusBus:Set("READY • getgenv().Experiment17Bus • same client only") end
            if StatusWS then StatusWS:Set(ws and "WebSocket API: available" or "WebSocket API: unavailable") end
            if StatusRelay then StatusRelay:Set(relayAdvice(relay)) end
            if StatusRoom then StatusRoom:Set(string.format("Room: %s • peers: %d", room, peers)) end
        end

        local Section = Context:CreateSection(Scope, Tab, "Script Bus / Sync Diagnostics", false, "Sync / Script Bus")
        StatusBus = Section:AddStatus({Name="Global Script Bus",Default="Starting...",Description="Shared Lua bus visible to other scripts running inside the SAME executor/client environment."})
        StatusWS = Section:AddStatus({Name="WebSocket Support",Default="Checking..."})
        StatusRelay = Section:AddStatus({Name="Relay Diagnostic",Default="Checking relay..."})
        StatusRoom = Section:AddStatus({Name="Room State",Default="Room: ?"})
        Section:AddButtonGroup({Name="Bus Test",Buttons={
            {Text="Emit",Callback=function() Bus:Emit("E17.Test", os.clock(), game.PlaceId); if Library and Library.Notify then Library:Notify({Title="Experiment 17",Text="E17.Test emitted to same-client scripts",Type="Success",Duration=2.5}) end end},
            {Text="Refresh",Callback=refresh},
        }})

        task.spawn(function()
            while running do
                refresh()
                task.wait(0.5)
            end
        end)

        refresh()
        Context.Shared.ScriptBus = Bus
    end,
}