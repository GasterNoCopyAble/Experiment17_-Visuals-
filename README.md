# Experiment17 Visuals

Experiment17 Visuals is a modular Roblox client visual toolkit. The project is split into a small loader, a manifest, independent feature modules, routed game-specific ESP profiles, and an optional WebSocket sync relay.

The interface now follows the **stable Experiment17 GuiLib entrypoint** instead of pinning an old monolithic UI file. The current stable GuiLib implementation is v21.

## One-line loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/Loader.lua"))()
```

## GuiLib

Visuals reads the GUI entry from `manifest.json`:

```json
"gui": "Experiment17.lua"
```

That resolves to:

```text
GasterNoCopyAble/Experiment17_GuiLib/main/Experiment17.lua
```

The stable GuiLib loader currently assembles the v21 source. This removes the old dependency on `Experiment17_VisualUI_v19.lua` and lets Visuals follow the stable library entrypoint.

Relevant GuiLib v21 behavior used by this project:

- desktop + touch/mobile input
- native main-window dragging
- native watermark dragging
- draggable mobile GUI button
- touch-friendly sliders and range sliders
- touch HSV color picker
- smaller mobile notifications
- Search + Favorites
- config browser/autoload
- themes + gradients
- Settings always remains the final sidebar tab

The old Visuals-side `MobileUI.lua` compatibility patch was removed because these behaviors now belong to GuiLib itself.

## Repository layout

```text
Experiment17_-Visuals-/
├── Loader.lua
├── manifest.json
├── README.md
├── sync_relay.py
└── modules/
    ├── Performance.lua
    ├── PerformanceStreaming.lua
    ├── Visual.lua
    ├── Lighting.lua
    ├── LightingPlus.lua
    ├── ESP.lua
    ├── DamageVisualizer.lua
    ├── World.lua
    ├── WorldEchoPlus.lua
    ├── Player.lua
    ├── PlayerAnimations.lua
    ├── Trajectory.lua
    ├── Waypoints.lua
    ├── Music.lua
    ├── Sync.lua
    ├── SharedBus.lua
    ├── UIEnhancements.lua
    └── esp/
        ├── registry.json
        ├── Universal.lua
        └── games/
            ├── GameESP_Template.lua
            └── MurderMystery2.lua
```

## Loader architecture

`Loader.lua` now performs these steps:

1. unloads an older Experiment17 instance if one is running;
2. downloads `manifest.json`;
3. resolves and loads the stable GuiLib entrypoint from the manifest;
4. creates the shared Experiment17 core/context;
5. loads enabled modules in manifest order;
6. routes modules that target an existing tab into that tab;
7. tracks module instances/connections/cleaners for safe reload/unload.

The loader exposes:

```lua
getgenv().Experiment17
```

Useful runtime fields include:

```lua
local E17 = getgenv().Experiment17

print(E17.Version)
print(E17.GuiEntry)
print(E17.Manifest)

E17:GetTab("Visual")
E17:ReloadModule("ESP")
E17:Unload("manual")
```

## Module format

A normal module returns a descriptor:

```lua
return {
    Id = "Example",
    Name = "Example",
    Version = "1.0.0",
    Order = 100,

    Init = function(Context, Scope, Tab)
        local State = Context:GetState("Example", {
            Enabled = false,
        })

        local Section = Context:CreateSection(
            Scope,
            Tab,
            "Example",
            false,
            "Example / General"
        )

        Section:AddToggle({
            Name = "Enabled",
            Flag = "Example_Enabled",
            Default = State.Enabled,
            Callback = function(value)
                State.Enabled = value
            end,
        })
    end,
}
```

A module can add controls to an existing tab with:

```lua
TargetTab = "Player"
```

The loader tracks common GuiLib v21 controls, including toggle, slider, range slider, choice, multi dropdown, input, number input, keybind, color picker, progress/status, button groups, labels and paragraphs.

## manifest.json

`manifest.json` is the project-level module list. Modules can be disabled without deleting them:

```json
{
  "id": "Example",
  "file": "Example.lua",
  "order": 100,
  "enabled": false
}
```

Lower `order` values are initialized first.

## ESP routing

`modules/ESP.lua` is a router. It checks:

1. `game.PlaceId`
2. `game.GameId`
3. Universal fallback

Registry:

```text
modules/esp/registry.json
```

Example:

```json
{
  "places": {
    "142823291": {
      "name": "Murder Mystery 2",
      "url": "modules/esp/games/MurderMystery2.lua"
    }
  }
}
```

Game-specific ESP profiles are standalone. When a matching game profile exists, it should not import Universal ESP, which prevents two renderers from fighting each other.

### Murder Mystery 2

The MM2 profile currently provides:

- role-aware ESP
- Murderer / Sheriff / Hero / Innocent colors
- role tags
- 2D boxes
- distance
- role highlight
- dead-player filtering
- configurable role refresh rate

It intentionally does not show HP.

## Visual / Lighting / World

The project contains both base and extended modules:

- `Visual.lua` — cursor and general screen visuals
- `Lighting.lua` — full lighting editor/presets/weather/effects
- `LightingPlus.lua` — extra fast lighting controls and presets
- `World.lua` — world inspector, X-Ray, wireframe and movement echo
- `WorldEchoPlus.lua` — enhanced footsteps / jump / landing visualization
- `DamageVisualizer.lua` — enhanced floating damage/heal feedback

## Performance

`Performance.lua` contains the main optimization controls.

`PerformanceStreaming.lua` adds client streaming-radius controls where the environment/game exposes the necessary Workspace properties. The server still has to have `Workspace.StreamingEnabled` enabled.

GuiLib v21 keeps Settings as the final tab. Performance is intentionally positioned near the bottom before Settings instead of attempting to move Settings away from its native final position.

## Music

`Music.lua` is a local file music player.

Default folder:

```text
Experiment17_Visuals/Music
```

Supported file extensions in the module:

```text
.mp3
.ogg
.wav
```

Local playback requires an environment that exposes `getcustomasset` or `getsynasset`.

## Player animations

`PlayerAnimations.lua` adds animation controls to the Player tab:

- custom Animation ID playback
- speed and weight
- loop
- fade
- priority
- freeze current pose
- current-track status
- idle/walk/run/jump/fall/climb/swim overrides
- original AnimationIds restored on disable/unload

## Same-client script bus

`SharedBus.lua` exposes a bus that other scripts running in the same executor/client environment can use:

```lua
local Bus = getgenv().Experiment17Bus

Bus:Set("Example.Value", 123)
print(Bus:Get("Example.Value"))

Bus:On("MyEvent", function(message)
    print(message)
end)

Bus:Emit("MyEvent", "hello")
```

This bus is **same-client only**. Another Roblox player has a separate Lua environment and cannot read your `getgenv()` values.

## Sync

`Sync.lua` uses the `E17SYNC1` WebSocket protocol. Connected clients can voluntarily exchange local pose/camera state and render peers as local ghosts.

Reference relay:

```bash
pip install websockets
python sync_relay.py --host 0.0.0.0 --port 8765
```

Default development URL:

```text
ws://127.0.0.1:8765
```

On a phone, `127.0.0.1` points to the phone itself. When the relay runs on a PC on the same LAN, use the PC's LAN address instead, for example:

```text
ws://192.168.1.50:8765
```

For internet use, host a reachable relay and preferably expose it through `wss://`.

## UI extras

`UIEnhancements.lua` now only adds behavior that is not already owned by GuiLib v21:

- keeps the custom cursor overlay above the main UI;
- adds one-tap favorite stars to function rows, especially useful on touch;
- provides desktop quick keybinds;
- omits the extra quick-keybind section on touch devices;
- exposes a small notification helper to other modules.

It no longer implements custom mobile dragging or manually moves the Settings tab.

## Reloading modules during development

```lua
local E17 = getgenv().Experiment17
E17:ReloadModule("Lighting")
E17:ReloadModule("ESP")
```

A full reload can still use the normal one-line loader; the loader automatically unloads the previous Experiment17 instance first.
