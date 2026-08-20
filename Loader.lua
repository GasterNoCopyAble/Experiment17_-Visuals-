-- Experiment17 Visuals - GitHub modular loader (GuiLib v19)
local ENV=(getgenv and getgenv()) or _G
if ENV.Experiment17 and type(ENV.Experiment17.Unload)=="function" then pcall(function() ENV.Experiment17:Unload("reload") end) end

local ROOT="https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/"
local LIB="https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_GuiLib/main/Experiment17_VisualUI_v19.lua"
local HttpService=game:GetService("HttpService")
local Core={Version="0.7.0-v19",Tabs={},States={},Shared={},Modules={},Scopes={},Services={},Unloaded=false}
ENV.Experiment17=Core

for _,n in ipairs({"Players","RunService","UserInputService","Lighting","Workspace","TweenService","HttpService","CollectionService"}) do
    local key=({UserInputService="UIS"})[n] or n
    Core.Services[key]=game:GetService(n)
end
Core.LocalPlayer=Core.Services.Players.LocalPlayer

local function cloneDefaults(t)
    local o={}; for k,v in pairs(t or {}) do if type(v)=="table" then local c={}; for a,b in pairs(v) do c[a]=b end; o[k]=c else o[k]=v end end; return o
end
function Core:GetState(id,defaults)
    if not self.States[id] then self.States[id]=cloneDefaults(defaults) else for k,v in pairs(defaults or {}) do if self.States[id][k]==nil then self.States[id][k]=type(v)=="table" and cloneDefaults(v) or v end end end
    return self.States[id]
end
function Core:Log(...) print("[Experiment17]",...) end
function Core:Warn(...) warn("[Experiment17]",...) end

Core.Bus={Listeners={}}
function Core.Bus:On(name,fn) self.Listeners[name]=self.Listeners[name] or {}; table.insert(self.Listeners[name],fn); return {Disconnect=function() local a=self.Listeners[name] or {}; for i=#a,1,-1 do if a[i]==fn then table.remove(a,i) end end end} end
function Core.Bus:Emit(name,...) for _,fn in ipairs(self.Listeners[name] or {}) do pcall(fn,...) end end

local function newScope(id)
    local s={Id=id,Cleaners={},Connections={},Instances={},Controls={}}
    function s:AddCleaner(fn) table.insert(self.Cleaners,fn); return fn end
    function s:TrackConnection(c) if c then table.insert(self.Connections,c) end; return c end
    function s:TrackInstance(x) if x then table.insert(self.Instances,x) end; return x end
    function s:TrackControl(x) if x then table.insert(self.Controls,x) end; return x end
    function s:Clean()
        for i=#self.Cleaners,1,-1 do pcall(self.Cleaners[i]) end
        for _,c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
        for _,x in ipairs(self.Instances) do pcall(function() x:Destroy() end) end
        table.clear(self.Cleaners); table.clear(self.Connections); table.clear(self.Instances); table.clear(self.Controls)
    end
    return s
end

local ok,lib=pcall(function() return assert(loadstring(game:HttpGet(LIB,true),"=E17_GuiLib_v19"))() end)
if not ok then error("[Experiment17] GuiLib v19 load failed: "..tostring(lib)) end
Core.Library=lib

local function destroyTab(tab)
    if not tab then return end
    pcall(function() if tab.Button then tab.Button:Destroy() end end)
    pcall(function() if tab.PageGroup then tab.PageGroup:Destroy() elseif tab.Page then tab.Page:Destroy() end end)
end
function Core:GetTab(name) return self.Tabs[tostring(name)] end
function Core:CreateTab(owner,name,order,scope)
    if self.Tabs[name] then return self.Tabs[name] end
    local tab=self.Library:CreateTab(name); tab.__Experiment17Owner=owner; tab.__Experiment17Order=order or 100
    if tab.Button then tab.Button.LayoutOrder=order or 100 end
    self.Tabs[name]=tab
    if scope then scope:AddCleaner(function() if Core.Tabs[name]==tab then Core.Tabs[name]=nil; destroyTab(tab) end end) end
    return tab
end
function Core:CreateSection(scope,tab,name,opened)
    local sec=tab:CreateSection(name,opened==true)
    for _,m in ipairs({"AddButton","AddToggle","AddSlider","AddChoice","AddInput","AddKeybind","AddColorPicker","AddMultiChoice","AddRangeSlider","AddNumberInput","AddProgressBar","AddButtonGroup","AddStatus"}) do
        if type(sec[m])=="function" then
            local raw=sec[m]
            sec[m]=function(self,opt) local c=raw(self,opt); if scope and c then scope:TrackControl(c) end; return c end
        end
    end
    return sec
end

local function fetch(url) local ok2,res=pcall(function() return game:HttpGet(url,true) end); if ok2 and type(res)=="string" and #res>0 then return res end; return nil,res end
local function compile(src,label) local fn,err=loadstring(src,"="..tostring(label)); if not fn then return nil,err end; local ok2,d=pcall(fn); if not ok2 then return nil,d end; return d end
local function absolute(path) path=tostring(path or ""); if path:match("^https?://") then return path end; return ROOT..path:gsub("^/+","") end

local fallback={
 {id="Performance",file="Performance.lua",order=5},{id="Visual",file="Visual.lua",order=10},{id="Lighting",file="Lighting.lua",order=20},{id="ESP",file="ESP.lua",order=30},{id="World",file="World.lua",order=40},{id="Player",file="Player.lua",order=50},{id="PlayerAnimations",file="PlayerAnimations.lua",order=55},{id="Trajectory",file="Trajectory.lua",order=60},{id="Waypoints",file="Waypoints.lua",order=70},{id="Sync",file="Sync.lua",order=80},
}
local function readManifest()
    local src=fetch(ROOT.."manifest.json"); if not src then return fallback end
    local ok2,data=pcall(HttpService.JSONDecode,HttpService,src); if not ok2 or type(data)~="table" or type(data.modules)~="table" then return fallback end
    return data.modules
end

local function unloadModule(id,reason)
    local rec=Core.Modules[id]; if not rec then return end
    if rec.Descriptor and type(rec.Descriptor.Unload)=="function" then pcall(rec.Descriptor.Unload,Core,rec.Scope,reason or "reload") end
    if rec.Scope then rec.Scope:Clean() end
    Core.Modules[id]=nil
end

local function mountDescriptor(desc,sourceURL,forcedId)
    if type(desc)~="table" then return false,"module did not return a table" end
    if desc.RedirectURL then
        local src,err=fetch(absolute(desc.RedirectURL)); if not src and desc.FallbackURL then src,err=fetch(absolute(desc.FallbackURL)); desc.__UsingFallback=true end
        if not src then return false,err end
        local redirected,e=compile(src,desc.RedirectId or forcedId or desc.Id or "Redirect"); if not redirected and desc.FallbackURL and not desc.__UsingFallback then local fs=fetch(absolute(desc.FallbackURL)); if fs then redirected,e=compile(fs,"ESP_Fallback"); desc.__UsingFallback=true end end
        if not redirected then return false,e end
        redirected.__RouteMeta=desc.RouteMeta
        desc=redirected
    end
    local id=tostring(forcedId or desc.Id or desc.Name or "Module")
    unloadModule(id,"replace")
    local scope=newScope(id); Core.Scopes[id]=scope
    local targetName=desc.TargetTab
    local tab
    if targetName then tab=Core:GetTab(targetName); if not tab then tab=Core:CreateTab(targetName,targetName,desc.Order or 100,nil) end else tab=Core:CreateTab(id,desc.TabName or desc.Name or id,desc.Order or 100,scope) end
    Core.Modules[id]={Descriptor=desc,Scope=scope,Tab=tab,SourceURL=sourceURL}
    if desc.__RouteMeta then Core.Shared.ModuleRoutes=Core.Shared.ModuleRoutes or {}; Core.Shared.ModuleRoutes[id]={Meta=desc.__RouteMeta,UsingFallback=desc.__UsingFallback==true} end
    if type(desc.Init)=="function" then local ok2,e=pcall(desc.Init,Core,scope,tab); if not ok2 then unloadModule(id,"init-error"); return false,e end end
    if type(desc.Start)=="function" then task.spawn(function() local ok2,e=pcall(desc.Start,Core,scope,tab); if not ok2 then Core:Warn(id,"Start error",e) end end) end
    Core.Bus:Emit("ModuleLoaded",id,desc)
    return true
end

function Core:LoadModule(id,file)
    local url=absolute("modules/"..tostring(file)); local src,err=fetch(url); if not src then self:Warn("fetch failed",id,err); return false end
    local desc,e=compile(src,id); if not desc then self:Warn("compile failed",id,e); return false end
    local ok2,why=mountDescriptor(desc,url,id); if not ok2 then self:Warn("mount failed",id,why) end; return ok2
end
function Core:RegisterModule(desc) local ok2,e=mountDescriptor(desc,"runtime",desc.Id); if not ok2 then self:Warn(e) end; return ok2 end
function Core:ReloadModule(id) local rec=self.Modules[id]; if rec and rec.SourceURL and rec.SourceURL~="runtime" then local file=rec.SourceURL:match("/modules/(.+)$"); return self:LoadModule(id,file) end return false end

function Core:Unload(reason)
    if self.Unloaded then return end; self.Unloaded=true
    local ids={}; for id in pairs(self.Modules) do ids[#ids+1]=id end; for _,id in ipairs(ids) do unloadModule(id,reason or "unload") end
    pcall(function() if self.Library and self.Library.Unload then self.Library:Unload() end end)
    if ENV.Experiment17==self then ENV.Experiment17=nil end
end

local modules=readManifest(); table.sort(modules,function(a,b) return (a.order or a.Order or 100)<(b.order or b.Order or 100) end)
for _,m in ipairs(modules) do Core:LoadModule(m.id or m.Id,m.file or m.File) end

local first=Core:GetTab("Visual") or Core:GetTab("Performance")
if first and first.Select then pcall(function() first:Select() end) end
Core:Log("loaded",Core.Version)
return Core
