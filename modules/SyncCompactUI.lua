-- Experiment17 - compact presentation layer for Sync
return {
    Id="SyncCompactUI", Name="Sync Quick UI", Version="1.0.0", Order=81, TargetTab="Sync",
    Init=function(Context,Scope,Tab)
        local Library=Context.Library
        local R={Status=nil,Peers=nil}

        local function notify(text,kind)
            if Library and type(Library.Notify)=="function" then
                pcall(function() Library:Notify({Title="Experiment 17 • Sync",Text=tostring(text),Type=kind or "Info",Duration=2.4}) end)
            end
        end
        local function syncApi() return Context.Shared and Context.Shared.Sync end
        local function room()
            if Library and Library.Flags and Library.Flags.Sync_Room~=nil then return tostring(Library.Flags.Sync_Room) end
            return "Experiment17"
        end
        local function peerCount()
            local api=syncApi(); if not api or type(api.GetPeers)~="function" then return 0 end
            local ok,peers=pcall(api.GetPeers); if not ok or type(peers)~="table" then return 0 end
            local n=0; for _ in pairs(peers) do n=n+1 end; return n
        end
        local function refresh()
            if R.Status then R.Status:Set("Room: "..room()) end
            if R.Peers then R.Peers:Set(tostring(peerCount()).." connected") end
        end
        local function call(name,...)
            local api=syncApi(); local fn=api and api[name]
            if type(fn)~="function" then notify("Sync API is not ready","Warning"); return false end
            local ok,res=pcall(fn,...)
            if not ok then notify("Sync "..name.." failed: "..tostring(res),"Warning") else refresh() end
            return ok,res
        end

        -- Collapse older detailed panels so opening Sync no longer presents a wall of controls.
        task.defer(function()
            for _,section in ipairs(Tab.Sections or {}) do
                if section and section.__E17CompactQuick~=true then
                    if type(section.SetOpen)=="function" then pcall(function() section:SetOpen(false) end)
                    elseif type(section.SetExpanded)=="function" then pcall(function() section:SetExpanded(false) end)
                    else section.Open=false end
                end
            end
        end)

        local Quick=Context:CreateSection(Scope,Tab,"Quick Sync",true,"Sync / Quick")
        Quick.__E17CompactQuick=true
        if Quick.Frame then Quick.Frame.LayoutOrder=-100 end
        R.Status=Quick:AddStatus({Name="Room",Default="Room: "..room()})
        R.Peers=Quick:AddStatus({Name="Peers",Default="0 connected"})
        if type(Quick.AddTileButtons)=="function" then
            Quick:AddTileButtons({Name="Party",TileSize=68,Columns=3,Buttons={
                {Text="●\nConnect",Callback=function() call("Connect") end},
                {Text="○\nDisconnect",Callback=function() call("Disconnect","Disconnected") end},
                {Text="↻\nRefresh",Callback=refresh},
            }})
        else
            Quick:AddButtonGroup({Name="Party",Buttons={{Text="Connect",Callback=function() call("Connect") end},{Text="Disconnect",Callback=function() call("Disconnect","Disconnected") end},{Text="Refresh",Callback=refresh}}})
        end
        Quick:AddParagraph({Text="Room, relay, ghost style and presence options are still available below, but stay collapsed until you need them."})

        local alive=true; Scope:AddCleaner(function() alive=false end)
        task.spawn(function() while alive do refresh(); task.wait(.75) end end)
        refresh()
    end,
}
