-- Experiment17 - Local Music Player
return {
    Id="Music", Name="Music", Version="1.0.0", Order=75,
    Init=function(Context,Scope,Tab)
        local SoundService=game:GetService("SoundService")
        local RunService=Context.Services.RunService or game:GetService("RunService")
        local Library=Context.Library
        local ENV=(getgenv and getgenv()) or _G
        local State=Context:GetState("Music",{Folder="Experiment17_Visuals/Music",Volume=0.65,PlaybackSpeed=1.0,Loop=false,Shuffle=false,AutoPlay=false,Notify=true})
        local R={Tracks={},Index=0,Selected="None",Running=true,Choice=nil,Status=nil,Seek=nil,UpdatingSeek=false}
        local Sound=Scope:TrackInstance(Instance.new("Sound")); Sound.Name="Experiment17_LocalMusic"; Sound.Volume=State.Volume; Sound.PlaybackSpeed=State.PlaybackSpeed; Sound.Looped=State.Loop; Sound.Parent=SoundService

        local function notify(text,kind)
            if not State.Notify then return end
            local shared=Context.Shared and Context.Shared.UIEnhancements
            if shared and type(shared.Notify)=="function" then shared.Notify(text,kind)
            elseif Library and type(Library.Notify)=="function" then pcall(function() Library:Notify({Title="Experiment 17 • Music",Text=tostring(text),Type=kind or "Info",Duration=3}) end) end
        end
        local function fs(name) return ENV[name] or _G[name] end
        local function supported(path) local ext=tostring(path):lower():match("%.([%w]+)$"); return ext=="mp3" or ext=="ogg" or ext=="wav" end
        local function basename(path) path=tostring(path or ""):gsub("\\","/"); return path:match("([^/]+)$") or path end
        local function customAsset(path)
            local getter=fs("getcustomasset") or fs("getsynasset"); if type(getter)~="function" then return nil,"getcustomasset/getsynasset unavailable" end
            local ok,res=pcall(getter,path); if ok and type(res)=="string" and res~="" then return res end; return nil,res
        end
        local function ensureFolder()
            local isfolder=fs("isfolder"); local makefolder=fs("makefolder")
            if type(isfolder)=="function" then local ok,exists=pcall(isfolder,State.Folder); if ok and exists then return true end end
            if type(makefolder)=="function" then return pcall(makefolder,State.Folder) end; return false
        end
        local function formatTime(sec) sec=math.max(0,tonumber(sec) or 0); return string.format("%d:%02d",math.floor(sec/60),math.floor(sec%60)) end
        local function refreshStatus(extra)
            if not R.Status or type(R.Status.Set)~="function" then return end
            local name=R.Index>0 and R.Tracks[R.Index] and R.Tracks[R.Index].Name or "None"; local length=Sound.TimeLength or 0
            local text=string.format("%s | %s / %s | %s",name,formatTime(Sound.TimePosition),formatTime(length),Sound.Playing and "PLAYING" or "PAUSED"); if extra then text=text.." | "..tostring(extra) end
            pcall(function() R.Status:Set(text) end)
        end
        local function updateChoice()
            if not R.Choice or type(R.Choice.SetValues)~="function" then return end
            local names={}; for _,track in ipairs(R.Tracks) do names[#names+1]=track.Name end; if #names==0 then names={"None"} end
            R.Choice:SetValues(names,false)
            if #R.Tracks>0 then local selected=R.Selected~="None" and R.Selected or R.Tracks[1].Name; local found=false; for _,n in ipairs(names) do if n==selected then found=true break end end; if not found then selected=names[1] end; R.Selected=selected; pcall(function() R.Choice:Set(selected,true) end)
            else R.Selected="None"; pcall(function() R.Choice:Set("None",true) end) end
        end

        local playIndex
        local function rescan(silent)
            ensureFolder(); table.clear(R.Tracks); R.Index=0
            local listfiles=fs("listfiles")
            if type(listfiles)~="function" then updateChoice(); refreshStatus("listfiles unavailable"); if not silent then notify("Executor does not provide listfiles()","Warning") end; return false end
            local ok,files=pcall(listfiles,State.Folder)
            if not ok or type(files)~="table" then updateChoice(); refreshStatus("folder scan failed"); if not silent then notify("Could not scan music folder: "..State.Folder,"Warning") end; return false end
            for _,path in ipairs(files) do if supported(path) then R.Tracks[#R.Tracks+1]={Path=path,Name=basename(path)} end end
            table.sort(R.Tracks,function(a,b) return a.Name:lower()<b.Name:lower() end); updateChoice(); refreshStatus(#R.Tracks.." tracks")
            if not silent then notify("Found "..#R.Tracks.." music files",#R.Tracks>0 and "Success" or "Info") end
            if State.AutoPlay and #R.Tracks>0 then task.defer(function() if playIndex then playIndex(1) end end) end; return true
        end
        local function indexByName(name) for i,t in ipairs(R.Tracks) do if t.Name==name then return i end end end
        playIndex=function(index)
            if #R.Tracks==0 then notify("Music folder is empty","Warning"); return false end
            index=math.clamp(math.floor(tonumber(index) or 1),1,#R.Tracks); local track=R.Tracks[index]; local asset,err=customAsset(track.Path)
            if not asset then notify("Could not load "..track.Name..": "..tostring(err),"Warning"); return false end
            R.Index=index; R.Selected=track.Name; Sound:Stop(); Sound.SoundId=asset; Sound.Volume=State.Volume; Sound.PlaybackSpeed=State.PlaybackSpeed; Sound.Looped=State.Loop
            local ok=pcall(function() Sound:Play() end); if R.Choice then pcall(function() R.Choice:Set(track.Name,true) end) end; refreshStatus(ok and "loaded" or "play failed"); if ok then notify("Playing: "..track.Name,"Success") end; return ok
        end
        local function playSelected() local index=indexByName(R.Selected); return index and playIndex(index) or false end
        local function nextTrack() if #R.Tracks==0 then return end; local index; if State.Shuffle and #R.Tracks>1 then repeat index=math.random(1,#R.Tracks) until index~=R.Index else index=(R.Index%#R.Tracks)+1 end; playIndex(index) end
        local function previousTrack() if #R.Tracks==0 then return end; local index=R.Index-1; if index<1 then index=#R.Tracks end; playIndex(index) end
        local function toggle()
            if Sound.Playing then pcall(function() Sound:Pause() end); refreshStatus(); notify("Music paused","Info")
            else
                if Sound.SoundId~="" and Sound.TimePosition>0 then local ok=pcall(function() Sound:Resume() end); if not ok then pcall(function() Sound:Play() end) end; refreshStatus(); notify("Music resumed","Info")
                elseif R.Index>0 then playIndex(R.Index) elseif #R.Tracks>0 then playIndex(1) else rescan(false) end
            end
        end
        Scope:TrackConnection(Sound.Ended:Connect(function() if not State.Loop then nextTrack() end end))

        local Playback=Context:CreateSection(Scope,Tab,"Local Music Player",true,"Music / Player")
        R.Status=Playback:AddStatus({Name="Now Playing",Default="No track loaded",Description="Reads local audio through executor getcustomasset/getsynasset. MP3, OGG and WAV are supported when the executor supports them."})
        R.Choice=Playback:AddChoice({Name="Track",Flag="Music_Track",Values={"None"},Default="None",RequiredGraphics="Low",Callback=function(v) R.Selected=v end})
        Playback:AddButtonGroup({Name="Playback",RequiredGraphics="Low",Buttons={{Text="Play",Callback=playSelected},{Text="Pause",Callback=toggle}}})
        Playback:AddButtonGroup({Name="Track Navigation",RequiredGraphics="Low",Buttons={{Text="Prev",Callback=previousTrack},{Text="Next",Callback=nextTrack}}})
        Playback:AddSlider({Name="Volume",Flag="Music_Volume",Min=0,Max=2,Default=State.Volume,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.Volume=v Sound.Volume=v end})
        Playback:AddSlider({Name="Playback Speed",Flag="Music_Speed",Min=0.25,Max=2,Default=State.PlaybackSpeed,Decimals=2,RequiredGraphics="Low",Callback=function(v) State.PlaybackSpeed=v Sound.PlaybackSpeed=v end})
        R.Seek=Playback:AddSlider({Name="Seek",Flag="Music_Seek",Min=0,Max=100,Default=0,Decimals=1,Suffix="%",RequiredGraphics="Low",Callback=function(v) if R.UpdatingSeek then return end; local len=Sound.TimeLength or 0; if len>0 then pcall(function() Sound.TimePosition=len*(v/100) end) end end})
        Playback:AddToggle({Name="Loop Track",Flag="Music_Loop",Default=State.Loop,RequiredGraphics="Low",Callback=function(v) State.Loop=v Sound.Looped=v end})
        Playback:AddToggle({Name="Shuffle",Flag="Music_Shuffle",Default=State.Shuffle,RequiredGraphics="Low",Callback=function(v) State.Shuffle=v end})

        local Files=Context:CreateSection(Scope,Tab,"Music Files",false,"Music / Files")
        Files:AddInput({Name="Music Folder",Flag="Music_Folder",Default=State.Folder,Placeholder="Experiment17_Visuals/Music",RequiredGraphics="Low",Callback=function(v) if tostring(v)~="" then State.Folder=tostring(v) end end})
        Files:AddButtonGroup({Name="Folder Actions",RequiredGraphics="Low",Buttons={{Text="Rescan",Callback=function() rescan(false) end},{Text="Create Folder",Callback=function() local ok=ensureFolder(); notify(ok and ("Folder ready: "..State.Folder) or "Could not create folder",ok and "Success" or "Warning") end}}})
        Files:AddToggle({Name="Autoplay After Scan",Flag="Music_AutoPlay",Default=State.AutoPlay,RequiredGraphics="Low",Callback=function(v) State.AutoPlay=v end})
        Files:AddToggle({Name="Music Notifications",Flag="Music_Notify",Default=State.Notify,RequiredGraphics="Low",Callback=function(v) State.Notify=v end})
        Files:AddStatus({Name="Supported Files",Default=".mp3  .ogg  .wav",Description="Put files directly in the selected executor workspace folder, then press Rescan."})

        Context.Shared.Music={Toggle=toggle,Play=playSelected,PlayIndex=playIndex,Pause=function() if Sound.Playing then Sound:Pause() end end,Next=nextTrack,Previous=previousTrack,Rescan=rescan,GetTracks=function() return R.Tracks end,GetSound=function() return Sound end}
        local timer=0
        Scope:TrackConnection(RunService.Heartbeat:Connect(function(dt) timer+=dt; if timer<0.25 then return end; timer=0; refreshStatus(); if R.Seek and type(R.Seek.Set)=="function" then local len=Sound.TimeLength or 0; local pct=len>0 and math.clamp((Sound.TimePosition/len)*100,0,100) or 0; R.UpdatingSeek=true; pcall(function() R.Seek:Set(pct,true) end); R.UpdatingSeek=false end end))
        task.defer(function() rescan(true) end); Scope:AddCleaner(function() R.Running=false; pcall(function() Sound:Stop() end) end)
    end,
}
